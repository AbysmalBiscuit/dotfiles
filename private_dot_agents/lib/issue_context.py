"""Shared worktree/issue/summary resolution for the issue recon scripts.

`/issue-start` and `/validate-webapp` need the same first answer: which
worktree is this, which issue does it belong to, and where is the session
summary. That part lives here, once, because it tracks devkit's record format
and a change there should not need fixing in two places. What each skill does
with the answer lives in its own entry script:

    ~/.agents/skills/issue-start/scripts/issue_start_context.py
        adds dependency freshness
    ~/.agents/skills/validate-webapp/scripts/validate_webapp_context.py
        adds the base diff, the devrun state and the dry run

Import it the way the other skill scripts import `agentgit`:

    sys.path.insert(0, str(Path.home() / ".agents" / "lib"))
    from issue_context import ContextError, resolve

`resolve()` chdirs into the worktree it found, so every later git, devkit and
devrun call in an entry script runs against the right tree without threading a
cwd through every helper.

Nothing here mutates a repository.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

# Callers live under `skills/<skill>/scripts/`, so this module is imported from
# outside its own directory and cannot rely on Python having put that directory
# on the path for it.
sys.path.insert(0, str(Path.home() / ".agents" / "lib"))

from agentgit import (  # noqa: E402
    current_branch,
    git,
    git_ok,
    in_repo,
    indent,
    is_protected,
    repo_root,
    say,
    short_head,
    upstream_ref,
)

SUMMARY_MAX_LINES = 400

ISSUE_RE = re.compile(r"\b([A-Za-z]{2,10})-(\d{1,6})\b")


class ContextError(Exception):
    """A preflight failure the entry script turns into a status line and exit."""

    def __init__(self, message: str, result: str, code: int) -> None:
        super().__init__(message)
        self.message = message
        self.result = result
        self.code = code


@dataclass
class IssueContext:
    worktree: Path
    branch: str
    record: dict
    issue_id: str | None = None
    summary_path: Path | None = None
    siblings: list[Path] = field(default_factory=list)

    @property
    def apps(self) -> list[str]:
        """App ids `issue setup` recorded, empty when none were given."""
        return list(self.record.get("apps") or [])


def trailer(result: str, extra: Sequence[str] = ()) -> None:
    """Print the closing status lines. `extra` lands above the `IC-RESULT` line.

    Printing and exiting are separate on purpose. A helper that exits hides the
    control flow from the reader and from the type checker, which then cannot
    tell that a variable assigned in a `try` is bound by the time it is used.
    Callers raise `SystemExit` themselves, so every exit is visible where it
    happens.
    """
    say("")
    for line in extra:
        say(line)
    say(f"IC-RESULT: {result}")


def run_tool(argv: list[str], timeout: int = 25) -> tuple[int, str]:
    """A devkit or devrun call with a timeout. Never raises.

    agentgit's `run` has no timeout, and these are the calls that can hang: a
    `devrun` waiting on a registry lock would block the skill that shells out
    to this script with no way to recover.
    """
    env = {**os.environ, "NO_COLOR": "1", "CLICOLOR": "0"}
    try:
        p = subprocess.run(
            argv, env=env, capture_output=True, text=True, timeout=timeout
        )
    except FileNotFoundError:
        return 127, f"{argv[0]} is not on PATH"
    except subprocess.TimeoutExpired:
        return 124, f"{' '.join(argv)} timed out after {timeout}s"
    return p.returncode, (p.stdout + p.stderr).strip()


def head(text: str, limit: int, label: str) -> str:
    """First `limit` lines, with a note naming what was cut when anything was."""
    lines = text.splitlines()
    if len(lines) <= limit:
        return text
    kept = "\n".join(lines[:limit])
    return f"{kept}\n... {label} truncated at {limit} of {len(lines)} lines"


def extract_issue_id(text: str) -> str | None:
    m = ISSUE_RE.search(text)
    return f"{m.group(1).upper()}-{m.group(2)}" if m else None


def read_record(worktree: Path) -> dict:
    """`<worktree>/.devkit/issue.toml`, devkit's per-worktree issue record."""
    path = worktree / ".devkit" / "issue.toml"
    if not path.is_file():
        return {}
    try:
        import tomllib

        return tomllib.loads(path.read_text())
    except (OSError, ValueError) as exc:
        say(f"note: {path} exists but could not be read ({exc})")
        return {}


def find_summary(
    worktree: Path, issue_id: str, record: dict
) -> tuple[Path | None, list[Path]]:
    """The summary devkit recorded, else the parent-directory convention.

    devkit's own default is `ISSUE_SUMMARY_{{ issue }}.md` under
    `worktree_root`, which for a flat worktree layout is the worktree's parent.
    The record carries the exact path whenever `issue setup --summary` wrote
    one, so it wins over the convention.

    Returns the summary and every sibling summary, so a caller that finds
    nothing can still offer the user a list instead of a dead end.
    """
    parent = worktree.parent
    siblings = sorted(parent.glob("ISSUE_SUMMARY_*.md"))

    recorded = record.get("summary")
    if isinstance(recorded, str) and Path(recorded).is_file():
        return Path(recorded), siblings

    by_convention = parent / f"ISSUE_SUMMARY_{issue_id}.md"
    if by_convention.is_file():
        return by_convention, siblings

    return None, siblings


def resolve(issue_arg: str = "") -> IssueContext:
    """Locate the worktree, its record, its issue id and its summary.

    Chdirs into the worktree. Raises `ContextError` when there is nothing to
    work with at all; an unresolvable issue id is not one of those cases, since
    the caller can still report the worktree and branch it did find.
    """
    if not in_repo():
        raise ContextError(
            f"not inside a git repository: {Path.cwd()}", "ERROR", 3
        )

    worktree = Path(repo_root())
    os.chdir(worktree)

    branch = current_branch()
    if not branch:
        raise ContextError(
            f"HEAD is detached at {short_head()}; check out the issue branch first",
            "ERROR",
            3,
        )

    if is_protected(branch):
        raise ContextError(
            f"on {branch}, which is a base branch rather than an issue worktree",
            "PROTECTED",
            6,
        )

    record = read_record(worktree)
    ctx = IssueContext(worktree=worktree, branch=branch, record=record)

    # The record's id is authoritative: devkit writes it at setup time from the
    # id the user gave, before any branch-name mangling.
    recorded_id = (record.get("issue") or "").strip().upper() or None
    ctx.issue_id = (
        extract_issue_id(issue_arg) or recorded_id or extract_issue_id(branch)
    )

    if ctx.issue_id:
        ctx.summary_path, ctx.siblings = find_summary(worktree, ctx.issue_id, record)

    return ctx


def render_context(ctx: IssueContext) -> None:
    say("== context ==")
    say(f"worktree:   {ctx.worktree}")
    say(f"branch:     {ctx.branch}")
    say(f"issue:      {ctx.issue_id or 'UNRESOLVED'}")
    if ctx.record:
        say(f"slug:       {ctx.record.get('slug', '?')}")
        say(f"apps:       {', '.join(ctx.apps) or 'none recorded'}")
        pr = ctx.record.get("pr") or {}
        if pr:
            say(f"pr:         {pr.get('repo', '?')}#{pr.get('number', '?')}")
    else:
        say("record:     no .devkit/issue.toml — not created by `issue setup`")


def no_issue_id_advice() -> None:
    say("")
    say("No issue id in the record or the branch name. Pass one as the first")
    say("argument, or ask the user which issue this worktree is for.")


def render_summary(ctx: IssueContext) -> bool:
    """Print the summary section. Returns whether a summary file was found."""
    say("")
    say("== summary ==")
    if ctx.summary_path is None:
        say(f"no ISSUE_SUMMARY_{ctx.issue_id}.md in {ctx.worktree.parent}")
        if ctx.siblings:
            say("other summaries in that directory:")
            for s in ctx.siblings:
                say(f"  {s.name}")
            say("ask which one applies, or work from the tracker issue directly.")
        else:
            say("none at all there, and the record names no `summary` path.")
            say("the setup asked for no summary; work from the tracker issue.")
        return False

    common = ctx.summary_path.parent / "ISSUES_COMMON.md"
    if common.is_file():
        say(f"--- {common} ---")
        say(head(common.read_text(), SUMMARY_MAX_LINES, "ISSUES_COMMON.md"))
        say("")
    say(f"--- {ctx.summary_path} ---")
    say(head(ctx.summary_path.read_text(), SUMMARY_MAX_LINES, "summary"))
    return True


def render_workspace() -> None:
    """Tree state and upstream of the worktree `resolve()` chdir'd into.

    Whatever each skill checks beyond this is its own business.
    """
    say("")
    say("== workspace ==")
    status = git("status", "--short")
    if status:
        say("uncommitted changes:")
        say(indent(status))
    else:
        say("tree clean")
    say(f"upstream:   {upstream_ref() or 'none, this branch has never been pushed'}")


def devkit_defaults() -> dict:
    """The `[defaults]` table of the merged devkit config, empty when unreadable."""
    code, out = run_tool(["devkit", "config", "show", "--json"])
    if code != 0:
        return {}
    try:
        return json.loads(out).get("defaults", {})
    except (ValueError, AttributeError):
        return {}


def tracked_lockfile() -> tuple[str, str, str] | None:
    """The lockfile tracked at HEAD, its install command and its install directory.

    First match wins, so a repo carrying two package managers reports the one
    listed first. A repo tracking none has no install step to check.
    """
    lockfiles = [
        ("bun.lock", "bun install", "node_modules"),
        ("bun.lockb", "bun install", "node_modules"),
        ("pnpm-lock.yaml", "pnpm install", "node_modules"),
        ("yarn.lock", "yarn install", "node_modules"),
        ("package-lock.json", "npm install", "node_modules"),
        ("uv.lock", "uv sync", ".venv"),
        ("poetry.lock", "poetry install", ".venv"),
    ]
    for lock, install, installed_dir in lockfiles:
        if git_ok("cat-file", "-e", f"HEAD:{lock}"):
            return lock, install, installed_dir
    return None
