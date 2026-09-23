#!/usr/bin/env python3
"""Read-only recon for /issue-review-kysely: work out which branch of the
workflow applies and gather the diff, with no reviewer anywhere in it.

Usage:
    python3 ~/.agents/skills/issue-review-kysely/scripts/issue_review_recon.py

Takes no reviewer alias, resolves none, and never prints an `issue review
request` line. That subcommand adds the reviewer on GitHub and delivers the
`review_request` Slack template; this skill exists to ship a PR without either.
`issue pr create` opens the PR through the same pr_title / pr_body templates
while adding no reviewer and sending no Slack.

Mutates nothing. No commit, no push, no `issue pr create` — each needs a
human-authored commit message or PR body, so they stay with the caller.

Last two lines are always:
  IR-BRANCH: A | B | STOP
  IR-RESULT: <STATUS>
    READY               proceed with the branch named in IR-BRANCH
    NOTHING-NEW         PR is open and HEAD is already pushed and reviewed
    PR-MERGED           nothing to push
    PR-CLOSED           nothing to push
    PROTECTED           on a base branch, not a feature branch
    NOT-ISSUE-WORKTREE  no issue record, so the PR templates cannot render
    ERROR               preflight failed
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".agents" / "lib"))

from agentgit import say  # noqa: E402
from issue_review import (  # noqa: E402
    ReviewContext,
    ReviewError,
    render_body,
    render_context,
    render_pr_create,
    resolve,
    trailer,
)


def render_next(ctx: ReviewContext) -> str:
    """The `== next ==` block. Returns the workflow branch it described."""
    say("")
    say("== next ==")

    if not ctx.has_pr:
        say("Branch A. Commit anything pending, then open the PR:")
        say("")
        render_pr_create(ctx)
        say("")
        say("Pass no --to: nobody is added on GitHub and nothing goes to Slack.")
        return "A"

    say("Branch B. Commit anything pending, then push:")
    say("")
    if ctx.upstream:
        say('  git push origin "$(git rev-parse --abbrev-ref HEAD)"')
    else:
        say('  git push -u origin "$(git rev-parse --abbrev-ref HEAD)"')
        say("")
        say("The branch has no upstream yet, so this first push needs -u.")
    say("")
    say(f"PR #{ctx.pr_number} keeps the reviewers it already has: pushing adds,")
    say("re-requests and notifies nobody. Report the URL and what landed.")
    return "B"


def main() -> None:
    try:
        ctx = resolve()
    except ReviewError as err:
        say(err.message)
        trailer(err.result, err.branch)
        raise SystemExit(err.code) from None

    render_context(ctx)

    try:
        render_body(ctx)
    except ReviewError as err:
        trailer(err.result, err.branch)
        raise SystemExit(err.code) from None

    workflow_branch = render_next(ctx)
    trailer("READY", workflow_branch)


if __name__ == "__main__":
    main()
