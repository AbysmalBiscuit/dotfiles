#!/usr/bin/env python3
"""Read-only recon for /issue-start.

Resolves the issue worktree, its devkit record, the session summary and the
working-tree state in one pass, so the session does not spend its first turns
running git and devkit commands to find out where it is. Adds the dependency
check that matters when picking up work in a worktree someone left cold.

Usage:
    python3 ~/.agents/skills/issue-start/scripts/issue_start_context.py [ISSUE_ID]

    ISSUE_ID    optional; otherwise taken from the devkit record, then the
                branch name

Mutates nothing. No commit, no push, no install.

Last line is always:
    IC-RESULT: <STATUS>
      READY               worktree, issue id and summary all resolved
      NO-SUMMARY          worktree and issue id fine, no summary file exists
      NOT-ISSUE-WORKTREE  no issue id derivable from the record or the branch
      PROTECTED           on a base branch, not an issue worktree
      ERROR               preflight failed (not a repo, detached HEAD)
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".agents" / "lib"))

from agentgit import say  # noqa: E402
from issue_context import (  # noqa: E402
    ContextError,
    IssueContext,
    no_issue_id_advice,
    render_context,
    render_summary,
    render_workspace,
    resolve,
    tracked_lockfile,
    trailer,
)


def render_dependencies(ctx: IssueContext) -> None:
    """Whether the installed tree looks older than the lockfile describing it.

    A cold worktree whose `node_modules` predates its lockfile fails in ways
    that look like the bug under investigation, so the answer belongs in the
    recon rather than in a later debugging detour.
    """
    say("dependencies:")
    found = tracked_lockfile()
    if found is None:
        say("  no tracked lockfile — this repo has no install step to check")
        return

    lock, install, installed_dir = found
    lock_path = ctx.worktree / lock
    target = ctx.worktree / installed_dir

    if not target.exists():
        say(f"  {lock}: {installed_dir}/ is missing — needs `{install}`")
    elif lock_path.is_file() and lock_path.stat().st_mtime > target.stat().st_mtime:
        age = int((lock_path.stat().st_mtime - target.stat().st_mtime) / 60)
        say(f"  {lock}: newer than {installed_dir}/ by ~{age}m — likely needs `{install}`")
    else:
        say(f"  {lock}: {installed_dir}/ looks current")


def main() -> None:
    args = [a for a in sys.argv[1:] if a.strip() and not a.startswith("-")]
    issue_arg = args[0] if args else ""

    try:
        ctx = resolve(issue_arg)
    except ContextError as err:
        say(err.message)
        trailer(err.result)
        raise SystemExit(err.code) from None

    render_context(ctx)
    if not ctx.issue_id:
        no_issue_id_advice()
        trailer("NOT-ISSUE-WORKTREE")
        raise SystemExit(5)

    found = render_summary(ctx)
    render_workspace()
    render_dependencies(ctx)

    trailer("READY" if found else "NO-SUMMARY")


if __name__ == "__main__":
    main()
