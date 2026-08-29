#!/usr/bin/env python3
"""Course-corrects coding agents in-flight by feeding convention violations back
to the model. Dispatches on the hook event name in the payload on stdin, so a
single entry point works for every hook it is registered under.

  PostToolUse (Edit|Write|MultiEdit)  fast per-file ast-grep rules and checks/
                                      scripts, advisory, on the lines the branch
                                      introduced
  Stop | SubagentStop                 fallow audit on the changeset, gating

Always exits 0 and speaks through the hookSpecificOutput JSON contract, so a
broken check degrades to silence rather than wedging the session.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import tomllib
from pathlib import Path

_watchdog = None


def arm_watchdog(seconds):
    """The harness timeout kills the process it spawned, which stops helping the
    moment this one outlives the session that spawned it. Owning the deadline
    here bounds an orphan too."""
    global _watchdog
    if _watchdog is not None:
        _watchdog.cancel()
    _watchdog = threading.Timer(seconds, lambda: os._exit(0))
    _watchdog.daemon = True
    _watchdog.start()


arm_watchdog(float(os.environ.get("AGENT_GUARD_DEADLINE") or 55))

# Everything this hook needs lives beside it, so the whole directory relocates as
# one unit. Resolved through the symlink on PATH, not from it.
SELF = Path(__file__).resolve()
CONFIG_DIR = Path(os.environ.get("AGENT_GUARD_CONFIG_DIR") or SELF.parent.parent)
STATE_DIR = (
    Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
    / "agent-guard"
)

CONFIG_NAME = "config.toml"
_ENV_PREFIX = "AGENT_GUARD_"
_UNSET = object()
_BASH = _UNSET

# Rules come in layers, each named by its directory in a tree: the tracked one
# first, then a machine-local overlay beside it that outranks it. Later roots add
# rules and tighten settings, and a tree opts in by creating one of these
# directories; nothing in the global install changes.
ROOT_NAMES = (".agents/plugins/agent-guard", ".agents/plugins/agent-guard.local")

TEST_PATH = re.compile(r"(test|spec)\.|/tests?/|__tests__")
BARREL_OR_TEST = re.compile(r"(test|spec)\.|/tests?/|__tests__|/index\.tsx?$")


def have(tool):
    return shutil.which(tool) is not None


def run(cmd, timeout=20, cwd=None, stdin=None, env=None):
    """Stdout, or an empty string for any failure. Every external call is bounded
    so a wedged tool cannot outlive the hook."""
    try:
        p = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd,
            env=env,
            input=stdin,
            encoding="utf-8",
            errors="replace",
        )
        return p.stdout or ""
    except Exception:
        return ""


def succeeds(cmd, timeout=20, cwd=None):
    try:
        return (
            subprocess.run(cmd, capture_output=True, timeout=timeout, cwd=cwd).returncode
            == 0
        )
    except Exception:
        return False


def is_root(path):
    """A config.toml alone is enough: a tree that wants only the global rules
    under its own settings still opts in by carrying the directory."""
    return path.is_dir() and (
        (path / "rules").is_dir()
        or (path / "checks").is_dir()
        or (path / "sgconfig.yml").is_file()
        or (path / CONFIG_NAME).is_file()
    )


def discover_roots(cwd):
    """Every ancestor of the working directory, outermost first, so a nearer tree
    layers over a wider one: a checkout over the directory that holds every
    checkout of that project, over the global install. Deliberately not keyed on
    the git toplevel, because worktrees of one repository share settings that
    belong in the directory above them rather than in its own history."""
    roots = [CONFIG_DIR]
    for ancestor in reversed([cwd] + list(cwd.parents)):
        for name in ROOT_NAMES:
            candidate = ancestor / name
            if candidate != CONFIG_DIR and is_root(candidate):
                roots.append(candidate)
    return roots


def load_config(roots):
    """Every root's config.toml, in order, so a nearer tree tunes extensions,
    ignore patterns and which checks run without editing the global install.
    Keys are flat; unknown ones are ignored, and a file that will not parse is
    skipped rather than taken as empty. An AGENT_GUARD_<KEY> environment variable
    overrides the files for a single run."""
    cfg = {}
    for root in roots:
        f = root / CONFIG_NAME
        if not f.is_file():
            continue
        try:
            with f.open("rb") as handle:
                data = tomllib.load(handle)
        except (OSError, tomllib.TOMLDecodeError):
            continue
        cfg.update({k: v for k, v in data.items() if not isinstance(v, dict)})
    for key, value in os.environ.items():
        if key.startswith(_ENV_PREFIX):
            cfg[key[len(_ENV_PREFIX):].lower()] = value
    return cfg


def _compile(pattern):
    try:
        return re.compile(pattern)
    except re.error:
        # A broken pattern fails closed to "matches nothing" rather than
        # widening to everything.
        return re.compile(r"(?!x)x")


class Settings:
    """Values come from TOML, so they arrive already typed. They also come from
    the environment as strings, so every read coerces."""

    def __init__(self, cfg):
        g = cfg.get
        # Blocking is opt-in. A gate that is wrong once teaches every agent to
        # route around it, so a rule earns the right to block only after it
        # proves quiet.
        self.block = _bool(g("block"), False)
        # There is no built-in loop protection on Stop hooks, so cap how often
        # one session may be refused before this downgrades itself to advisory.
        self.max_blocks = _int(g("max_blocks"), 2)
        self.use_fallow = _bool(g("fallow"), True)
        self.fallow_timeout = _float(g("fallow_timeout"), 45.0)
        # Findings shown per report, so feedback stays inside working memory.
        self.max_findings = _int(g("max_findings"), 8)
        # Bound on symbols reference-counted per changeset, so a wide diff stays
        # cheap.
        self.max_symbols = _int(g("max_symbols"), 40)
        # A function with one caller is often a fine module boundary, so that
        # half is opt-in.
        self.single_caller = _bool(g("single_caller"), False)
        # Exports whose only consumer is their own test. A tree mid-migration,
        # where a parity test is deliberately the sole caller of the new path,
        # turns this off.
        self.test_only = _bool(g("test_only"), True)
        # Which lines of an edited file the per-file findings are reported on.
        # 'diff' keeps only the lines the branch introduced; 'file' reports the
        # whole file. Inherited debt is not the editing agent's to answer for,
        # and a report mostly made of it is one an agent learns to skim past.
        self.scope = _str(g("scope"), "diff")
        # Which files the per-file rules run on. A repo adding rules for another
        # language widens this in its own config.toml.
        self.ext_src = _str(g("extensions"), r"\.(ts|tsx|mts|cts)$")
        self.ext_re = _compile(self.ext_src)
        # Generated code is duplicated by design; flagging it trains agents to
        # ignore the hook. Only the language-wide shapes are listed here, and a
        # project names its own generated directories through the additive knob.
        ignore = _str(g("ignore"), r"\.gen\.|/generated/|/__generated__/|\.d\.ts$")
        extra = _str(g("ignore_extra"), "")
        # Appended rather than assigned, so a layer adds paths without restating
        # the defaults. Restating them by hand invites a stray leading '|', whose
        # empty alternation matches every path and silently disables the check.
        self.ignore_src = f"{ignore}|{extra}" if extra else ignore
        self.ignore_re = _compile(self.ignore_src)
        self.base_override = _str(g("base"), "")


def _bool(value, fallback):
    if isinstance(value, bool):
        return value
    if value is None:
        return fallback
    return str(value).strip().lower() in ("1", "true", "yes", "on")


def _int(value, fallback):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return fallback


def _float(value, fallback):
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return fallback


def _str(value, fallback):
    return fallback if value is None else str(value)


def sgconfig_for(root):
    """A root ships either a full sgconfig.yml, required for custom languages
    whose libraryPath resolves relative to it, or just a rules/ directory.
    Synthesise a config for the latter, cached and refreshed when rules change."""
    own = root / "sgconfig.yml"
    if own.is_file():
        return own
    rules = root / "rules"
    if not rules.is_dir():
        return None
    key = re.sub(r"[^A-Za-z0-9]", "_", str(root))
    generated = STATE_DIR / "generated" / f"{key}.yml"
    try:
        generated.parent.mkdir(parents=True, exist_ok=True)
        if not generated.is_file() or generated.stat().st_mtime <= rules.stat().st_mtime:
            generated.write_text(f"ruleDirs:\n  - {rules}\n", encoding="utf-8")
    except OSError:
        return None
    return generated


def emit_silent():
    sys.exit(0)


def emit(event, context, deny=""):
    out = {"hookEventName": event}
    if deny:
        out["permissionDecision"] = "deny"
        out["permissionDecisionReason"] = deny
    out["additionalContext"] = context
    sys.stdout.write(json.dumps({"hookSpecificOutput": out}, separators=(",", ":")) + "\n")
    sys.stdout.flush()
    sys.exit(0)


def git_base(settings, cwd):
    """The merge-base with the upstream branch, matching the changeset audit.
    With no upstream it falls back to HEAD, so the scope degrades to the
    uncommitted working tree rather than back to the whole file."""
    if settings.base_override:
        return settings.base_override
    upstream = run(
        ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], cwd=cwd
    ).strip()
    base = run(
        ["git", "merge-base", "HEAD", upstream or "origin/HEAD"], cwd=cwd
    ).strip()
    return base or run(["git", "rev-parse", "HEAD"], cwd=cwd).strip()


_HUNK = re.compile(r"^@@ \S+ \+(\d+)(?:,(\d+))?")


def changed_lines(path, base, cwd):
    """Line numbers one file gained since the branch's base. An empty set is a
    real answer meaning the branch added no lines to it; None means git cannot
    answer at all (no repository, or a file it has never tracked), which the
    caller reads as "every line is the agent's"."""
    if not have("git") or not succeeds(["git", "rev-parse", "--git-dir"], cwd=cwd):
        return None
    if not succeeds(["git", "ls-files", "--error-unmatch", "--", path], cwd=cwd):
        return None
    if not base:
        return None
    added = set()
    diff = run(["git", "diff", "--unified=0", base, "--", path], cwd=cwd)
    for line in diff.splitlines():
        m = _HUNK.match(line)
        if not m:
            continue
        start = int(m.group(1))
        count = 1 if m.group(2) is None else int(m.group(2))
        added.update(range(start, start + count))
    return added


def bash_exe():
    """Windows ships its own bash.exe in System32 as the WSL launcher, and it
    usually sits ahead of Git's on PATH. That one cannot open a C:\\ path, so a
    check script handed one fails with "No such file or directory" and the whole
    checks/ layer goes quietly empty. Find an MSYS bash by hand, and only fall
    back to PATH when none is installed where Git puts it."""
    global _BASH
    if _BASH is not _UNSET:
        return _BASH
    candidates = []
    override = os.environ.get("AGENT_GUARD_BASH")
    if override:
        candidates.append(Path(override))
    git = shutil.which("git")
    if git:
        # git.exe lives in either cmd/ or bin/ under the install root.
        home = Path(git).resolve().parent.parent
        candidates += [home / "usr" / "bin" / "bash.exe", home / "bin" / "bash.exe"]
    candidates += [
        Path(r"C:\Program Files\Git\usr\bin\bash.exe"),
        Path(r"C:\Program Files\Git\bin\bash.exe"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            _BASH = str(candidate)
            return _BASH
    found = shutil.which("bash")
    system32 = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
    if found and system32 in Path(found).parents:
        found = None
    _BASH = found
    return _BASH


def _bash_env(shell):
    """A hook is spawned with the Windows PATH, which carries git.exe but not the
    MSYS utilities beside it. Bash then starts with no awk, sed or grep, and every
    check script dies with "command not found" while the hook stays silent. Put
    the directories that ship with this bash in front of whatever PATH it
    inherits."""
    env = dict(os.environ)
    home = Path(shell).parent.parent
    dirs = [home / "usr" / "bin", home / "bin", Path(shell).parent]
    prefix = [str(d) for d in dict.fromkeys(dirs) if d.is_dir()]
    if prefix:
        env["PATH"] = os.pathsep.join(prefix + [env.get("PATH", "")])
    return env


def run_checks(path, roots, cwd):
    """Conventions ast-grep cannot reach. Tree-sitter discards whitespace, so
    nothing about blank lines or vertical spacing is expressible as a rule; those
    live here instead. A root's checks/ holds bash scripts, each called with one
    file path and printing findings on stdout in the shape the ast-grep scan
    produces:

      <2 spaces><file>:<line><2 spaces>[<rule-id>] <message>

    Run through bash rather than executed directly, because the executable bit
    does not survive a clone onto the team's Windows machines."""
    shell = bash_exe()
    if not shell:
        return ""
    env = _bash_env(shell)
    out = []
    for root in roots:
        checks = root / "checks"
        if not checks.is_dir():
            continue
        for script in sorted(checks.glob("*.sh")):
            argv = [shell, script.as_posix(), str(path).replace("\\", "/")]
            # Only newlines: the leading two spaces are part of the finding format.
            text = run(argv, timeout=10, cwd=cwd, env=env).strip("\r\n")
            if text:
                out.append(text)
    return "\n".join(out)


_FINDING_LINE = re.compile(r":(\d+)  \[")


def scan_file(path, roots, cwd):
    findings = []
    if have("ast-grep"):
        # One scan per root rather than one merged config: each root's sgconfig
        # resolves its own ruleDirs and custom-language libraryPath relative to
        # itself.
        for root in roots:
            config = sgconfig_for(root)
            if config is None:
                continue
            raw = run(
                ["ast-grep", "scan", "-c", str(config), "--json=compact", path],
                timeout=15,
                cwd=cwd,
            )
            try:
                hits = json.loads(raw) if raw.strip() else []
            except ValueError:
                continue
            for hit in hits or []:
                rule = re.sub(r"-(typescript|tsx)$", "", hit.get("ruleId", ""))
                line = hit.get("range", {}).get("start", {}).get("line", 0) + 1
                findings.append(
                    "  {}:{}  [{}] {}".format(
                        hit.get("file", path), line, rule, hit.get("message", "")
                    )
                )
    extra = run_checks(path, roots, cwd)
    if extra:
        findings.extend(extra.splitlines())
    return [f for f in findings if f.strip()]


def check_file(payload, roots, settings, cwd):
    """Per-file syntactic rules. Must stay in the low milliseconds: this fires on
    every edit from every agent and subagent, so its cost multiplies. Git is
    consulted only once a rule has fired, so a clean file costs no subprocess."""
    path = (payload.get("tool_input") or {}).get("file_path") or ""
    if not path or not Path(path).is_file():
        emit_silent()
    if not settings.ext_re.search(path):
        emit_silent()

    findings = scan_file(path, roots, cwd)
    if not findings:
        emit_silent()

    if settings.scope == "diff":
        added = changed_lines(path, git_base(settings, cwd), cwd)
        if added is not None:
            kept = []
            for line in findings:
                m = _FINDING_LINE.search(line)
                if m and int(m.group(1)) in added:
                    kept.append(line)
            findings = kept

    findings = findings[: settings.max_findings]
    if not findings:
        emit_silent()

    emit(
        "PostToolUse",
        "agent-guard found convention violations in the file you just wrote. "
        "Fix them now rather than leaving them for review:\n\n"
        + "\n".join(findings)
        + "\n\nThese come from this project's documented conventions. If a finding "
        "is genuinely wrong, say why instead of silently ignoring it.",
    )


def find_duplication(base, seen_file, settings, cwd):
    """Duplication introduced by the changeset. Generated code is excluded: it is
    duplicated by design, and flagging it teaches agents to ignore the hook."""
    if not settings.use_fallow or not have("fallow"):
        return ""
    raw = run(
        ["fallow", "audit", "--base", base, "--format", "json"],
        timeout=settings.fallow_timeout,
        cwd=cwd,
    )
    if not raw.strip():
        return ""
    try:
        data = json.loads(raw)
    except ValueError:
        return ""

    groups = []
    for group in (data.get("duplication") or {}).get("clone_groups") or []:
        if not group.get("introduced"):
            continue
        instances = group.get("instances") or []
        if any(settings.ignore_re.search(i.get("file", "")) for i in instances):
            continue
        groups.append(group)
    if not groups:
        return ""

    try:
        seen = set(seen_file.read_text(encoding="utf-8").split())
    except OSError:
        seen = set()
    fresh = [g for g in groups if g.get("fingerprint") not in seen]
    if not fresh:
        return ""
    try:
        with seen_file.open("a", encoding="utf-8") as fh:
            for g in fresh:
                fh.write(f"{g.get('fingerprint')}\n")
    except OSError:
        pass

    lines = []
    for group in fresh[: settings.max_findings]:
        instances = group.get("instances") or []
        head = "  {} duplicated lines across {} sites ({}):".format(
            group.get("line_count"), len(instances), group.get("fingerprint")
        )
        body = [f"    {i.get('file')}:{i.get('start_line')}" for i in instances[:4]]
        if len(instances) > 4:
            body.append(f"    ... and {len(instances) - 4} more")
        lines.append("\n".join([head] + body))
    return "\n".join(lines)


def find_over_extraction(changed, seen_file, roots, settings, cwd):
    """Helpers extracted past the point of usefulness. Two shapes are reported,
    each behind its own switch: an export whose only consumer is its own test,
    and an export with exactly one real caller. Barrel re-exports do not count as
    consumers. Reference counting is name-based, so it is a heuristic, which is
    why this stays advisory: a same-named symbol elsewhere reads as a consumer."""
    if not (settings.test_only or settings.single_caller) or not have("ast-grep"):
        return ""
    try:
        seen = set(seen_file.read_text(encoding="utf-8").split())
    except OSError:
        seen = set()

    out = []
    checked = 0
    for rel in changed:
        if checked >= settings.max_symbols:
            break
        path = cwd / rel
        if not path.is_file() or settings.ignore_re.search(rel) or TEST_PATH.search(rel):
            continue
        if rel.endswith(".tsx"):
            lang = "tsx"
        elif rel.endswith(".ts"):
            lang = "typescript"
        else:
            continue

        # Last root wins, so a repo can replace the global query with its own.
        query = None
        for root in reversed(roots):
            candidate = root / "queries" / f"exported-symbols-{lang}.yml"
            if candidate.is_file():
                query = candidate
                break
        if query is None:
            continue

        raw = run(
            ["ast-grep", "scan", "-r", str(query), "--json=compact", rel],
            timeout=15,
            cwd=cwd,
        )
        try:
            hits = json.loads(raw) if raw.strip() else []
        except ValueError:
            continue
        names = sorted(
            {
                (((h.get("metaVariables") or {}).get("single") or {}).get("NAME") or {})
                .get("text")
                for h in hits or []
            }
            - {None, ""}
        )

        for name in names:
            if checked >= settings.max_symbols:
                break
            checked += 1
            if f"{rel}:{name}" in seen:
                continue
            refs = [
                r.lstrip("./")
                for r in run(
                    ["rg", "-l", "--type", "ts", "--", rf"\b{re.escape(name)}\b", "."],
                    timeout=15,
                    cwd=cwd,
                ).splitlines()
                if r.strip()
            ]
            refs = [r for r in refs if r != rel]
            testrefs = sum(1 for r in refs if TEST_PATH.search(r))
            otherrefs = sum(1 for r in refs if not BARREL_OR_TEST.search(r))

            if settings.test_only and otherrefs == 0 and testrefs > 0:
                mark = (
                    f"  {rel}:{name} is exported but consumed only by its test. "
                    "Inline it, or drop the export and the test with it."
                )
            elif settings.single_caller and otherrefs == 1:
                mark = (
                    f"  {rel}:{name} has exactly one caller. Inline it there "
                    "unless the split earns its keep."
                )
            else:
                continue
            try:
                with seen_file.open("a", encoding="utf-8") as fh:
                    fh.write(f"{rel}:{name}\n")
            except OSError:
                pass
            out.append(mark)
    return "\n".join(out)


def check_changeset(event, session, agent_type, roots, settings, cwd):
    """Cross-file analysis on the changeset. Only findings the changeset
    introduced are reported; inherited debt is not this agent's to answer for."""
    if not have("git") or not succeeds(["git", "rev-parse", "--git-dir"], cwd=cwd):
        emit_silent()

    base = git_base(settings, cwd)
    changed = [
        line
        for line in run(
            ["git", "diff", "--name-only", base, "--", "*.ts", "*.tsx", "*.js", "*.jsx"],
            cwd=cwd,
        ).splitlines()
        if line.strip()
    ][:200]
    if not changed:
        emit_silent()

    sdir = STATE_DIR / session
    try:
        sdir.mkdir(parents=True, exist_ok=True)
    except OSError:
        emit_silent()
    seen_file = sdir / "seen-fingerprints"
    if not seen_file.exists():
        try:
            seen_file.touch()
        except OSError:
            pass

    # Skip re-running when the changeset has not moved since the last report.
    diff_text = run(["git", "diff", base, "--", "*.ts", "*.tsx"], cwd=cwd)
    fingerprint = hashlib.sha256(diff_text.encode("utf-8", "replace")).hexdigest()[:16]
    last = sdir / "last-diff"
    try:
        if last.is_file() and last.read_text(encoding="utf-8").strip() == fingerprint:
            emit_silent()
        last.write_text(fingerprint, encoding="utf-8")
    except OSError:
        pass

    who = f"Subagent '{agent_type}'" if agent_type else "This agent"
    dupes = find_duplication(base, seen_file, settings, cwd)
    extraction = find_over_extraction(changed, seen_file, roots, settings, cwd)

    sections = []
    if dupes:
        sections.append(
            f"{who} introduced duplicated code rather than reusing what already "
            f"exists:\n\n{dupes}\n\nConsolidate against the existing "
            "implementation, or explain why a separate one is warranted. Run "
            "'fallow dupes --trace <fingerprint>' for the full clone group.\n"
        )
    if extraction:
        sections.append(
            f"{who} added helpers that carry their own abstraction cost without "
            f"earning it:\n\n{extraction}\nAn indirection worth keeping has more "
            "than one caller, or a name that explains something the inlined code "
            "would not."
        )
    if not sections:
        emit_silent()
    context = "\n".join(sections)

    blocks_file = sdir / "blocks"
    blocks = _int(
        blocks_file.read_text(encoding="utf-8") if blocks_file.is_file() else "0", 0
    )
    if settings.block and dupes and blocks < settings.max_blocks:
        try:
            blocks_file.write_text(str(blocks + 1), encoding="utf-8")
        except OSError:
            pass
        emit(
            event,
            context,
            "agent-guard: duplication introduced by this changeset is unresolved",
        )
    emit(event, context)


def doctor(cwd):
    """A hook that is silent when healthy is indistinguishable from one that is
    silently broken, so make the difference inspectable."""
    roots = discover_roots(cwd)
    settings = Settings(load_config(roots))
    print("agent-guard doctor")
    print(f"  cwd        : {cwd}")
    print(f"  config     : {CONFIG_NAME}")
    print(f"  scope      : {settings.scope}")
    print(f"  extensions : {settings.ext_src}")
    print(f"  ignore     : {settings.ignore_src}")
    print("  roots      :")
    for root in roots:
        config = sgconfig_for(root)
        rules = len(list((root / "rules").glob("*.yml"))) if (root / "rules").is_dir() else 0
        checks = len(list((root / "checks").glob("*.sh"))) if (root / "checks").is_dir() else 0
        print(f"    {root}")
        print(f"      config   : {config if config else 'NONE'}")
        print(f"      rules(own): {rules}")
        print(f"      checks   : {checks}")
    for tool in ("ast-grep", "fallow", "git", "rg"):
        print(f"  {tool:<10} : {shutil.which(tool) or 'not installed'}")
    print(f"  {'bash':<10} : {bash_exe() or 'not installed'}")
    print()
    print("  ast-grep missing -> per-file rules skipped (checks/ still run)")
    print("  fallow missing   -> changeset duplication check skipped")
    print("  rg missing       -> over-extraction check skipped")
    print("  scope=diff       -> per-file findings limited to lines the branch")
    print("                      added; findings older than it stay quiet")
    print("  only the global root listed -> nothing here opted in; the hook is inert")
    sys.exit(0)


def main():
    argv_event = sys.argv[1] if len(sys.argv) > 1 else ""
    if argv_event == "doctor":
        doctor(Path.cwd())

    raw = sys.stdin.read()
    if not raw.strip():
        sys.exit(0)
    try:
        payload = json.loads(raw)
    except ValueError:
        sys.exit(0)

    event = argv_event or payload.get("hook_event_name") or ""
    session = payload.get("session_id") or "nosession"
    agent_type = payload.get("agent_type") or ""

    cwd = Path.cwd()
    declared = payload.get("cwd") or ""
    if declared and Path(declared).is_dir():
        cwd = Path(declared).resolve()

    roots = discover_roots(cwd)
    settings = Settings(load_config(roots))

    # Registered in user settings, so it is reachable from every project on the
    # machine. Carrying an agent-guard directory somewhere above the working
    # directory is the whole opt-in; with only the global root discovered there
    # is nothing here to enforce, and the hook stays out of the way.
    if len(roots) <= 1:
        sys.exit(0)

    if event == "PostToolUse":
        arm_watchdog(float(os.environ.get("AGENT_GUARD_DEADLINE") or 9))
        check_file(payload, roots, settings, cwd)
    elif event in ("Stop", "SubagentStop"):
        check_changeset(event, session, agent_type, roots, settings, cwd)
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except BaseException:
        # A broken check degrades to silence rather than wedging the session.
        sys.exit(0)
