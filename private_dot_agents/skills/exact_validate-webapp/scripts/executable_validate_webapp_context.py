#!/usr/bin/env python3
"""Read-only recon for /validate-webapp.

Resolves the issue worktree, its summary and what this branch changed, then
reports whether the dev servers for this worktree are already up. The server
state is the point: validating against a half-up stack produces a failure that
looks like the bug, so the caller gates on `IC-SERVERS` before touching a
browser.

Usage:
    python3 ~/.agents/skills/validate-webapp/scripts/validate_webapp_context.py [ISSUE_ID]

    ISSUE_ID    optional; otherwise taken from the devkit record, then the
                branch name

Mutates nothing. No commit, no push, no server start. `devrun up --dry-run` is
read-only in devkit 0.14.

Last two lines are always:
    IC-SERVERS: <STATE>
      UP        every app in scope has a tracked server
      DOWN      nothing tracked for this worktree
      PARTIAL   fewer tracked servers than apps in scope
      UNKNOWN   `devrun status` failed; do not validate against this
    IC-RESULT: <STATUS>
      READY               worktree, issue id and summary all resolved
      NO-SUMMARY          worktree and issue id fine, no summary file exists
      NOT-ISSUE-WORKTREE  no issue id derivable from the record or the branch
      PROTECTED           on a base branch, not an issue worktree
      ERROR               preflight failed (not a repo, detached HEAD)
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".agents" / "lib"))

from agentgit import git, indent, ref_exists, say  # noqa: E402
from issue_context import (  # noqa: E402
    ContextError,
    IssueContext,
    devkit_defaults,
    head,
    no_issue_id_advice,
    render_context,
    render_summary,
    render_workspace,
    resolve,
    run_tool,
    trailer,
)

DIFFSTAT_MAX_LINES = 60
DRY_RUN_MAX_LINES = 80
LOG_MAX_COMMITS = 40


def render_changes() -> None:
    """Commits and diffstat against the configured PR base.

    The base comes from `defaults.pr_base` rather than a hardcoded branch, so
    this reads correctly in a repo targeting `main` and one targeting
    `staging`.
    """
    say("")
    say("== changes on this branch ==")

    base = devkit_defaults().get("pr_base") or ""
    if not base:
        say("could not resolve defaults.pr_base from `devkit config show --json`;")
        say("ask the user which branch this work targets before diffing.")
        return

    ref = f"origin/{base}"
    if not ref_exists(ref):
        say(f"base:       {ref} (defaults.pr_base) — not present locally")
        say("run `git fetch origin` first, or the base is named differently here.")
        return

    say(f"base:       {ref} (defaults.pr_base)")
    log = git("log", f"{ref}..HEAD", "--oneline", f"-{LOG_MAX_COMMITS}")
    say("commits:")
    say(indent(log) if log else "  none")
    stat = git("diff", f"{ref}...HEAD", "--stat")
    say("diffstat:")
    say(indent(head(stat, DIFFSTAT_MAX_LINES, "diffstat")) if stat else "  none")


def server_rows(status_out: str) -> list[str]:
    """Data rows from a `devrun status` table, header and blanks dropped."""
    rows = []
    for line in status_out.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("PORT"):
            continue
        rows.append(stripped)
    return rows


def render_servers(ctx: IssueContext) -> str:
    """Print the tracked servers and return the `IC-SERVERS` state."""
    say("")
    say("== servers ==")
    code, out = run_tool(["devrun", "status"])
    if code != 0:
        say(out)
        return "UNKNOWN"

    say(out or "(no output)")
    rows = server_rows(out)
    in_scope = ctx.apps
    say("")
    say(
        f"{len(rows)} tracked server(s) for this worktree; apps in scope: "
        f"{', '.join(in_scope) or 'unrecorded'}"
    )

    if not rows:
        return "DOWN"
    if in_scope and len(rows) < len(in_scope):
        return "PARTIAL"
    return "UP"


def render_dry_run() -> None:
    say("")
    say("== devrun up --dry-run (nothing started) ==")
    started = time.monotonic()
    _, out = run_tool(["devrun", "up", "--dry-run"], timeout=40)
    say(head(out, DRY_RUN_MAX_LINES, "dry run"))
    say(f"({time.monotonic() - started:.1f}s)")


def main() -> None:
    args = [a for a in sys.argv[1:] if a.strip() and not a.startswith("-")]
    issue_arg = args[0] if args else ""

    try:
        ctx = resolve(issue_arg)
    except ContextError as err:
        say(err.message)
        trailer(err.result, extra=["IC-SERVERS: UNKNOWN"])
        raise SystemExit(err.code) from None

    render_context(ctx)
    if not ctx.issue_id:
        no_issue_id_advice()
        trailer("NOT-ISSUE-WORKTREE", extra=["IC-SERVERS: UNKNOWN"])
        raise SystemExit(5)

    found = render_summary(ctx)
    render_workspace()
    render_changes()

    servers = render_servers(ctx)
    if servers in {"DOWN", "PARTIAL"}:
        render_dry_run()

    trailer("READY" if found else "NO-SUMMARY", extra=[f"IC-SERVERS: {servers}"])


if __name__ == "__main__":
    main()
