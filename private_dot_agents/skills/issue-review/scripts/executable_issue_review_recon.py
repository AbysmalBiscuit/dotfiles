#!/usr/bin/env python3
"""Read-only recon for /issue-review: work out which branch of the workflow
applies and gather everything needed to open the PR and request a review.

Usage:
    python3 ~/.agents/skills/issue-review/scripts/issue_review_recon.py [ALIAS]

    ALIAS   optional `[people]` alias from the devkit config; omit it to
            request nobody

Mutates nothing. No commit, no push, no `issue pr create`, no `issue review
request` — each needs a human-authored commit message, PR body, or Slack
summary, so they stay with the caller.

Last two lines are always:
  IR-BRANCH: A | B | STOP
  IR-RESULT: <STATUS>
    READY               proceed with the branch named in IR-BRANCH
    NOTHING-NEW         PR is open but the reviewer has already seen HEAD
    PR-MERGED           nothing to review
    PR-CLOSED           nothing to review
    PROTECTED           on a base branch, not a feature branch
    NOT-ISSUE-WORKTREE  no issue record, so the PR templates cannot render
    UNKNOWN-REVIEWER    an alias was passed but is not in the devkit config
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
    devkit_config_path,
    load_people,
    render_body,
    render_context,
    render_pr_create,
    resolve,
    trailer,
)


def reviewer_line(alias: str, person: dict) -> str:
    if not alias:
        return "reviewer: (none — no alias passed, so no review will be requested)"
    extras = "".join(
        [
            f"   github: {person.get('github')}" if person.get("github") else "",
            f"   slack: {person.get('slack')}" if person.get("slack") else "",
        ]
    )
    return f"reviewer: {alias}{extras}"


def render_next(ctx: ReviewContext, alias: str) -> str:
    """The `== next ==` block. Returns the workflow branch it described."""
    say("")
    say("== next ==")

    if not ctx.has_pr:
        say("Branch A. Commit anything pending, then open the PR:")
        say("")
        render_pr_create(ctx)
        if alias:
            say("")
            say("Then request the review:")
            say("")
            say(f'  issue review request --to "{alias}" \\')
            say('    "<one-line ask, no PR link, the template appends it>"')
        else:
            say("")
            say("No alias was passed, so stop after issue pr create. No reviewer is added on")
            say("GitHub and no Slack message goes out. Do not run issue review request.")
        return "A"

    say("Branch B. Commit anything pending, then:")
    say("")
    if alias:
        say(f'  issue review request --to "{alias}" \\')
        say('    "addressed your comments: <1-2 sentence summary>. Mind taking another look? 🙏"')
        say("")
        say("No --pr-title/--pr-body: those live on issue pr create and render only when")
        say(f"the PR is opened. PR #{ctx.pr_number} already exists, so gh pr edit is the way to")
        say("change its description.")
    else:
        say("  issue review request --no-notify")
        say("")
        say(f"No alias was passed, so PR #{ctx.pr_number} keeps the reviewers it already has.")
        say("--no-notify never falls back to the PR's current reviewers, so nobody is")
        say("added or re-requested and nothing is delivered; it pushes and prints the PR")
        say("URL. Re-run with an alias if someone should actually be pinged.")
    return "B"


def main() -> None:
    args = [a for a in sys.argv[1:] if a.strip()]
    alias = args[0] if args else ""

    try:
        ctx = resolve()
    except ReviewError as err:
        say(err.message)
        trailer(err.result, err.branch)
        raise SystemExit(err.code) from None

    config = devkit_config_path()
    people = load_people(config) if alias else {}
    person = people.get(alias, {})

    render_context(ctx, [reviewer_line(alias, person)])

    if alias and not person.get("github"):
        say("")
        say(f"the alias '{alias}' has no [people.{alias}] entry in {config}")
        say(f"known aliases: {' '.join(sorted(people))}")
        trailer("UNKNOWN-REVIEWER", "STOP")
        raise SystemExit(7)

    try:
        render_body(ctx)
    except ReviewError as err:
        trailer(err.result, err.branch)
        raise SystemExit(err.code) from None

    workflow_branch = render_next(ctx, alias)
    trailer("READY", workflow_branch)


if __name__ == "__main__":
    main()
