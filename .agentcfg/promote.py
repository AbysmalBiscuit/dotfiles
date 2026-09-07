#!/usr/bin/env python3
"""Assign a merge strategy to every live config key no rule covers.

chezmoi cannot surface this drift on its own. Under a modify_ script the
target is computed from the live file, so on any seed, ignore, or passthrough
path the target equals live by construction and the comparison goes quiet.
This walks what the check finds and writes your choices into the baseline and
rules files.

    python .agentcfg/promote.py            pick interactively
    python .agentcfg/promote.py --list     print the candidates and exit

Without a terminal, or under a chezmoi dry run, it prints instead of picking.

The other direction is a deletion, which the picker cannot reach: it only
offers paths the live file still has. remove takes dotted paths and clears
each one from the baseline, from the live file, and from the app that owns it.

    python .agentcfg/promote.py remove enabledPlugins.linear@claude-plugins-official

complete backs the fish and nushell completions with the paths those two files
actually carry, so a tab offers what remove would accept and nothing else.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from collections import Counter
from collections.abc import Mapping

# sys.dont_write_bytecode = True

from pathlib import Path  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))

from engine.check import _get, classify  # noqa: E402
from engine.codecs import CodecError, JsonCodec, TomlCodec  # noqa: E402
from engine.lint import LintError, lint  # noqa: E402
from engine.picker import pick  # noqa: E402
from engine.promote import LIVE_ONLY, candidates  # noqa: E402
from engine.rules import RuleSet, Strategy  # noqa: E402
from engine.writers import (  # noqa: E402
    append_rules,
    delete_paths,
    write_json_baseline,
    write_toml_baseline,
)


class Config:
    def __init__(self, target, source_dir, baseline, rules, codec, writer, uninstall=None):
        self.target = target
        self.source_dir = source_dir
        self.baseline = baseline
        self.rules = rules
        self.codec = codec
        self.writer = writer
        # Container path -> the command that retires one of its members. Editing
        # the config only changes what the app is told to load; the files on disk
        # and the app's own ledger of them are the app's to delete.
        self.uninstall = uninstall or {}


CONFIGS = [
    Config(".claude/settings.json", "private_dot_claude", ".settings.baseline.json",
           ".settings.rules.toml", JsonCodec, write_json_baseline,
           uninstall={("enabledPlugins",): ("claude", "plugin", "uninstall")}),
    Config(".codex/config.toml", "dot_codex", ".config.baseline.toml",
           ".config.rules.toml", TomlCodec, write_toml_baseline,
           uninstall={("mcp_servers",): ("codex", "mcp", "remove")}),
]


def _repo_root() -> Path:
    env = os.environ.get("CHEZMOI_SOURCE_DIR")
    return Path(env) if env else Path(__file__).resolve().parent.parent


def _dest_root() -> Path:
    env = os.environ.get("CHEZMOI_DEST_DIR")
    return Path(env) if env else Path(os.path.expanduser("~"))


def _value(live, path):
    cursor = live
    for segment in path:
        cursor = cursor[segment]
    return cursor


def apply_choices(config, source, live, choices, found) -> str:
    """Write the choices, restoring both files if the result fails to validate."""
    baseline_path = source / config.baseline
    rules_path = source / config.rules
    before = (baseline_path.read_bytes(), rules_path.read_bytes())

    kinds = {item.path: item.kind for item in found}
    additions = [(path, _value(live, path)) for path, strategy in choices.items()
                 if strategy not in (Strategy.IGNORE, Strategy.REMOVE)]
    # A live-only path already matches a rule and is merely missing from the
    # baseline. Appending a second pattern for it risks a load-time tie.
    # remove is the exception: no existing rule can express a deletion.
    new_rules = [(strategy, path) for path, strategy in choices.items()
                 if strategy is Strategy.REMOVE or kinds[path] != LIVE_ONLY]

    if additions:
        config.writer(baseline_path, additions)
    if new_rules:
        append_rules(rules_path, new_rules)

    try:
        rules = RuleSet.load(rules_path)
        baseline = config.codec.plain(config.codec.load(baseline_path.read_bytes()))
        lint(baseline, rules)
    except Exception as exc:
        baseline_path.write_bytes(before[0])
        rules_path.write_bytes(before[1])
        return f"  rolled back, the result did not validate: {exc}"
    return f"  wrote {len(additions)} baseline value(s), {len(new_rules)} rule(s)"


_DRY_RUN = re.compile(r"^(?:--dry-run|-[a-zA-Z]*n[a-zA-Z]*)$")


def dry_run(chezmoi_args: str) -> bool:
    """True when chezmoi's own argv asks for a dry run.

    Apply hooks fire under --dry-run as well, so a picker launched from one
    would seize a command the caller expected to change nothing. CHEZMOI_ARGS
    carries chezmoi's whole argv and is the only signal that separates the two.
    """
    return any(_DRY_RUN.match(arg) for arg in chezmoi_args.split())


def can_pick() -> bool:
    return (
        sys.stdin.isatty()
        and sys.stdout.isatty()
        and not dry_run(os.environ.get("CHEZMOI_ARGS", ""))
    )


# Every flag here takes a value. Reading one as valueless would turn its
# value into a phantom target; reading a valueless flag as taking one only
# drops a target, which costs at most a skipped run.
_VALUE_FLAGS = frozenset({
    "--age-recipient", "--age-recipient-file", "--cache", "--color",
    "--config", "--config-format", "--destination", "--exclude", "--include",
    "--mode", "--output", "--override-data", "--override-data-file",
    "--persistent-state", "--progress", "--refresh-externals", "--source",
    "--use-builtin-age", "--use-builtin-git", "--working-tree",
})
_VALUE_SHORTHANDS = frozenset("DRSWciox")


def _positionals(argv: list[str]) -> list[str]:
    """The tokens that are neither a flag nor the value of one."""
    out: list[str] = []
    expect_value = False
    literal = False
    for token in argv:
        if expect_value:
            expect_value = False
        elif literal or token == "-" or not token.startswith("-"):
            out.append(token)
        elif token == "--":
            literal = True
        elif token.startswith("--"):
            expect_value = "=" not in token and token in _VALUE_FLAGS
        else:
            cluster = token[1:]
            for index, letter in enumerate(cluster):
                if letter in _VALUE_SHORTHANDS:
                    expect_value = index == len(cluster) - 1
                    break
    return out


def apply_targets(chezmoi_args: str) -> list[str]:
    """The targets chezmoi was given, empty when it was given none.

    argv[0] is the executable and the first positional after it is the
    subcommand, so the targets start at the second.
    """
    return _positionals(chezmoi_args.split()[1:])[1:]


def in_scope(chezmoi_args: str, paths, home) -> bool:
    """True when the run could reach one of the config files.

    A targeted apply leaves every other file alone, so a picker that opens
    anyway seizes a command that was never about these configs. Anything
    unresolvable counts as in scope: skipping a run only defers the
    question to the next one.

    chezmoi joins its argv with single spaces and runs hooks from the home
    directory rather than the caller's, so a target carrying a space or one
    written relative to another directory does not survive the round trip.
    """
    argv = chezmoi_args.split()
    if "--source-path" in argv:
        return True
    targets = apply_targets(chezmoi_args)
    if not targets:
        return True
    for arg in targets:
        candidate = Path(os.path.expanduser(arg))
        if not candidate.is_absolute():
            candidate = home / candidate
        candidate = Path(os.path.normpath(candidate))
        if any(candidate == path or candidate in path.parents for path in paths):
            return True
    return False


REMOVE_USAGE = (
    "usage: agentcfg remove [--dry-run] [--keep-installed] <dotted.path>...\n"
    "  clears each path from the baseline, from the live file, and from the app"
)


def uninstall_command(config, path):
    """The command that retires this path from the app itself, or None.

    Only a direct member of a container the config declares: removing one
    plugin is an uninstall, editing a field inside one is not.
    """
    for container, argv in config.uninstall.items():
        if path[:-1] == container:
            return [*argv, path[-1]]
    return None


def _read(path, codec):
    return codec.plain(codec.load(path.read_bytes()))


def remove_paths(config, root, home, targets, uninstall: bool, preview: bool) -> int:
    """Clear targets from one config's pair of files, then from the app.

    Both files, because seed hands a live key straight back and enforce hands
    a baseline key straight back: clearing either side alone leaves the other
    to restore the key on the next apply.
    """
    source = root / config.source_dir
    baseline_path = source / config.baseline
    live_path = home / config.target
    commands = [cmd for cmd in (uninstall_command(config, t) for t in targets)
                if uninstall and cmd]

    print(f"{config.target}:")
    for target in targets:
        print(f"  clear  {'.'.join(target)}")
    for command in commands:
        print(f"  run    {' '.join(command)}")
    if preview:
        return 0

    before = (baseline_path.read_bytes(), live_path.read_bytes())
    delete_paths(baseline_path, config.codec, targets)
    delete_paths(live_path, config.codec, targets)
    try:
        lint(_read(baseline_path, config.codec), RuleSet.load(source / config.rules))
    except Exception as exc:
        baseline_path.write_bytes(before[0])
        live_path.write_bytes(before[1])
        print(f"  rolled back, the result did not validate: {exc}", file=sys.stderr)
        return 1

    # Last, because it deletes files no rollback here could put back. Nothing
    # irreversible runs until the edits above have validated.
    status = 0
    for command in commands:
        if subprocess.run(command, check=False).returncode != 0:
            print(f"  {' '.join(command)}: exited non-zero", file=sys.stderr)
            status = 1
    return status


def remove(argv, root, home) -> int:
    flags = [arg for arg in argv if arg.startswith("-")]
    targets = [tuple(arg.split(".")) for arg in argv if not arg.startswith("-")]
    unknown = [arg for arg in flags if arg not in ("--dry-run", "--keep-installed")]
    if unknown or not targets:
        for arg in unknown:
            print(f"remove: unknown flag {arg}", file=sys.stderr)
        print(REMOVE_USAGE, file=sys.stderr)
        return 2

    preview = "--dry-run" in flags
    uninstall = "--keep-installed" not in flags
    status, claimed = 0, set()

    for config in CONFIGS:
        live_path = home / config.target
        if not live_path.exists():
            continue
        baseline = _read(root / config.source_dir / config.baseline, config.codec)
        live = _read(live_path, config.codec)
        mine = [t for t in targets if _get(baseline, t)[1] or _get(live, t)[1]]
        if not mine:
            continue
        claimed.update(mine)
        status |= remove_paths(config, root, home, mine, uninstall, preview)

    for target in targets:
        if target not in claimed:
            print(f"{'.'.join(target)}: no config carries this path", file=sys.stderr)
            status = 1
    return status


def _walk(data, prefix=()):
    """Every path in a config, containers included.

    A container is a target in its own right: retiring an MCP server means
    removing mcp_servers.<name>, not each field underneath it.
    """
    for key, value in data.items():
        path = (*prefix, key)
        yield path
        if isinstance(value, Mapping) and value:
            yield from _walk(value, path)


def completions(root, home):
    """Every path remove would accept, each with a line describing it.

    Both sides of both configs, because remove reaches a key the baseline
    still lists after the app has already dropped it, and the reverse. The
    child counts come from the collected paths rather than from either file,
    so a container reports what removing it would take from both.
    """
    owner = {}
    for config in CONFIGS:
        live_path = home / config.target
        if not live_path.exists():
            continue
        for source in (root / config.source_dir / config.baseline, live_path):
            try:
                data = _read(source, config.codec)
            except (CodecError, OSError):
                continue
            for path in _walk(data):
                owner.setdefault(path, config)

    children = Counter(path[:-1] for path in owner if len(path) > 1)
    described = {}
    for path, config in owner.items():
        count = children.get(path, 0)
        if count:
            note = f"{config.target}, {count} key{'s' if count > 1 else ''} under it"
        elif uninstall_command(config, path):
            note = f"{config.target}, uninstalls it"
        else:
            note = config.target
        described[".".join(path)] = note
    return sorted(described.items())


def complete(argv, root, home) -> int:
    """Print `path<TAB>description` for the paths starting with a prefix.

    A shell runs this on a keypress, so it stays silent about a config it
    cannot read: no candidates is a usable answer, a traceback is not.
    """
    prefix = next((arg for arg in argv if arg != "--"), "")
    for path, note in completions(root, home):
        if path.startswith(prefix):
            print(f"{path}\t{note}")
    return 0


def usage() -> str:
    """The whole surface, with the configs named from CONFIGS rather than
    restated, so adding one cannot leave this text behind."""
    targets = ", ".join(config.target for config in CONFIGS)
    return f"""usage: agentcfg [--list]
       agentcfg remove [--dry-run] [--keep-installed] <dotted.path>...
       agentcfg complete [--] [<prefix>]

Assign a merge strategy to the live keys no rule covers, and clear the ones the
repo should stop carrying.

Configs: {targets}

  (no arguments)      pick a strategy for each drifted key
  --list              print the drifted keys and exit
  remove              clear a path from the baseline, the live file and the app
    --dry-run           print the plan and write nothing
    --keep-installed    edit the configs, leave the app's own files alone
  complete            print the paths remove accepts, for shell completion

Both sides of a config are cleared together: whichever one keeps a key puts it
back on the next apply. Without a terminal, or under a chezmoi dry run, the
picker prints its candidates instead of asking."""


def main(argv) -> int:
    root, home = _repo_root(), _dest_root()
    if argv and argv[0] == "complete":
        return complete(argv[1:], root, home)
    if "-h" in argv or "--help" in argv:
        print(usage())
        return 0
    if argv and argv[0] == "remove":
        return remove(argv[1:], root, home)
    chezmoi_args = os.environ.get("CHEZMOI_ARGS", "")
    configs = [config for config in CONFIGS
               if in_scope(chezmoi_args, [home / config.target], home)]
    if not configs:
        return 0

    interactive = can_pick()
    list_only = "--list" in argv or not interactive
    touched = 0

    for config in configs:
        source = root / config.source_dir
        target = home / config.target
        if not target.exists():
            print(f"{config.target}: not present, skipping")
            continue

        rules = RuleSet.load(source / config.rules)
        baseline = config.codec.plain(config.codec.load((source / config.baseline).read_bytes()))
        live = config.codec.plain(config.codec.load(target.read_bytes()))
        found = candidates(live, classify(live, baseline, rules))

        if not found:
            print(f"{config.target}: nothing unclassified")
            continue
        if list_only:
            print(f"{config.target}: {len(found)} candidate(s)")
            for item in found:
                flag = f"   [secret: {item.secret}]" if item.blocked else ""
                print(f"  {item.kind:12} {'.'.join(item.path)}{flag}")
            if not interactive:
                print("  run `agentcfg` to assign strategies")
            continue

        choices = pick(found, f"{config.target}  ({len(found)} unclassified)")
        if choices is None:
            print(f"{config.target}: aborted, nothing written")
            continue
        if not choices:
            print(f"{config.target}: nothing selected")
            continue
        print(f"{config.target}:")
        print(apply_choices(config, source, live, choices, found))
        touched += 1

    if touched:
        print(f"\nReview with: git -C {root} diff")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
