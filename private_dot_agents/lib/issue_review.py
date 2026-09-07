"""Shared PR/diff recon for the issue-review skills.

`/issue-review` and `/issue-review-kysely` ship the same worktree the same way:
work out whether a PR exists, scope the diff to what a reviewer has not seen
yet, and decide which branch of the workflow applies. That part lives here,
once, because it tracks devkit's issue record and GitHub's PR shape and a change
in either should not need fixing twice. What each skill does with the answer
lives in its own entry script:

    ~/.agents/skills/issue-review/scripts/issue_review_recon.py
        resolves a reviewer alias and prints the review-request next steps
    ~/.agents/skills/issue-review-kysely/scripts/issue_review_recon.py
        never resolves a reviewer and never mentions Slack

Import it the way the other skill scripts import `agentgit`:

    sys.path.insert(0, str(Path.home() / ".agents" / "lib"))
    from issue_review import ReviewError, resolve

`resolve()` chdirs into the repository root, so every later git and gh call in
an entry script runs against the right tree without threading a cwd through
every helper.

Nothing here mutates a repository: no commit, no push, no `issue pr create`, no
`issue review request`. Each of those needs a human-authored commit message, PR
body or Slack summary, so they stay with the caller.
"""

from __future__ import annotations

import json
import os
import sys
import tomllib
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

# Callers live under `skills/<skill>/scripts/`, so this module is imported from
# outside its own directory and cannot rely on Python having put that directory
# on the path for it.
sys.path.insert(0, str(Path.home() / ".agents" / "lib"))

from agentgit import (  # noqa: E402
    capture,
    current_branch,
    dirty,
    gh_json,
    git,
    in_repo,
    indent,
    is_protected,
    repo_root,
    resolve_base,
    run,
    say,
    say_block,
    short_head,
    untracked,
    upstream_ref,
)

FULL_DIFF_MAX_LINES = 400


class ReviewError(Exception):
    """A preflight failure the entry script turns into status lines and an exit."""

    def __init__(self, message: str, result: str, branch: str, code: int) -> None:
        super().__init__(message)
        self.message = message
        self.result = result
        self.branch = branch
        self.code = code


@dataclass
class ReviewContext:
    worktree: str
    branch: str
    base: str
    issue_id: str = ""
    linear_name: str = ""
    pr_number: str = ""
    pr_state: str = "NO_PR"
    pr_url: str = ""
    prjson: dict = field(default_factory=dict)
    uncommitted: str = ""
    untracked_files: list[str] = field(default_factory=list)
    upstream: str = ""
    last_reviewed: str = ""

    @property
    def has_pr(self) -> bool:
        return self.pr_state != "NO_PR"

    @property
    def workflow_branch(self) -> str:
        """`A` when the PR still has to be opened, `B` when it already exists."""
        return "B" if self.has_pr else "A"


def trailer(result: str, branch: str) -> None:
    """Print the closing status lines.

    Printing and exiting are separate on purpose. A helper that exits hides the
    control flow from the reader and from the type checker, which then cannot
    tell that a variable assigned in a `try` is bound by the time it is used.
    Callers raise `SystemExit` themselves, so every exit is visible where it
    happens.
    """
    say("")
    say(f"IR-BRANCH: {branch}")
    say(f"IR-RESULT: {result}")


def devkit_config_path() -> Path:
    return Path(
        os.environ.get("DEVKIT_CONFIG", Path.home() / ".config/devkit/config.toml")
    )


def load_people(config: Path) -> dict[str, dict]:
    """The `[people]` table from the devkit config, empty when it cannot be read."""
    try:
        with config.open("rb") as fh:
            return tomllib.load(fh).get("people", {})
    except (OSError, tomllib.TOMLDecodeError):
        return {}


NO_ISSUE_ID = "UNKNOWN"
"""devkit fills `issue_id` with this when the branch carries no tracker id."""


def issue_info() -> dict:
    """`issue info --json` as a dict, empty when the worktree has no issue record."""
    code, out = capture("issue", "info", "--json")
    if code != 0 or not out.strip():
        return {}
    try:
        parsed = json.loads(out)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def recorded_issue_id(info: dict) -> str:
    """The worktree's tracker id, empty when devkit reports the UNKNOWN sentinel."""
    issue_id = info.get("issue_id") or ""
    return "" if issue_id == NO_ISSUE_ID else issue_id


def resolve() -> ReviewContext:
    """Locate the worktree, its issue record and its PR.

    Chdirs into the repository root. Raises `ReviewError` when there is nothing
    to work with at all; a missing issue id is not one of those cases, since the
    entry script decides how loudly to complain about it.
    """
    if not in_repo():
        raise ReviewError(
            f"not inside a git repository: {Path.cwd()}", "ERROR", "STOP", 3
        )
    os.chdir(repo_root())

    branch = current_branch()
    if not branch:
        raise ReviewError(
            f"HEAD is detached at {short_head()}; check out the issue branch first",
            "ERROR",
            "STOP",
            3,
        )

    if is_protected(branch):
        raise ReviewError(
            f"on {branch} — that is a base branch, not an issue worktree feature branch",
            "PROTECTED",
            "STOP",
            6,
        )

    info = issue_info()
    ctx = ReviewContext(
        worktree=info.get("worktree") or str(Path.cwd()),
        branch=branch,
        base="",
        issue_id=recorded_issue_id(info),
        linear_name=info.get("linear_name") or "",
        pr_number=info.get("pr_number") or "",
        pr_state=info.get("pr_state") or "",
        pr_url=info.get("pr_url") or "",
    )

    prjson = gh_json(
        "pr", "view", "--json",
        "number,state,url,baseRefName,reviewRequests,latestReviews",
    )
    if prjson:
        ctx.prjson = prjson
        ctx.pr_number = prjson.get("number") or ""
        ctx.pr_state = prjson.get("state") or ""
        ctx.pr_url = prjson.get("url") or ""
        ctx.base = prjson.get("baseRefName") or ""
    ctx.pr_state = ctx.pr_state or "NO_PR"
    ctx.base = ctx.base or resolve_base()

    ctx.uncommitted = dirty()
    ctx.untracked_files = untracked()
    ctx.upstream = upstream_ref()

    return ctx


def render_context(ctx: ReviewContext, extra: Sequence[str] = ()) -> None:
    """The `== context ==` block. `extra` lines land at the end of it."""
    say("== context ==")
    say(f"worktree: {ctx.worktree}")
    say(f"branch:   {ctx.branch}")
    linear_note = f"   Linear: {ctx.linear_name}" if ctx.linear_name else ""
    say(f"issue:    {ctx.issue_id or '(none found)'}{linear_note}")
    say(f"base:     {ctx.base}")
    for line in extra:
        say(line)


def require_issue_id(ctx: ReviewContext) -> None:
    """Raise unless the worktree has an issue record.

    The `pr_title` / `pr_body` templates render with strict-undefined, so
    without an id the PR cannot be opened through devkit at all.
    """
    if ctx.issue_id:
        return
    say("")
    say("no issue record for this worktree — the pr_title/pr_body templates render")
    say("with strict-undefined and will fail without one. Run this from inside an")
    say("issue worktree, or pass the title/body without relying on the templates.")
    raise ReviewError("no issue record", "NOT-ISSUE-WORKTREE", "STOP", 8)


def render_pr(ctx: ReviewContext) -> None:
    """The `== pr ==` block. Raises on a PR that is already merged or closed."""
    say("")
    say("== pr ==")
    if ctx.pr_state == "NO_PR":
        say(f"no PR for {ctx.branch} — this is the first push of this branch")
        return

    if ctx.pr_state == "OPEN":
        say(f"#{ctx.pr_number} OPEN  {ctx.pr_url}")
        requests = ctx.prjson.get("reviewRequests") or []
        if requests:
            names = ", ".join(r.get("login") or r.get("name") or "?" for r in requests)
            say(f"pending review requests: {names}")
        else:
            say("pending review requests: none")
        reviews = ctx.prjson.get("latestReviews") or []
        if not reviews:
            say("latest reviews: none submitted yet")
        else:
            say("latest reviews:")
            for r in reviews:
                login = (r.get("author") or {}).get("login", "?")
                oid = ((r.get("commit") or {}).get("oid") or "")[:9]
                say(f"  {login} {r.get('state')} at {oid} ({r.get('submittedAt')})")
        return

    if ctx.pr_state in ("MERGED", "CLOSED"):
        say(f"#{ctx.pr_number} {ctx.pr_state}  {ctx.pr_url}")
        say("")
        say(f"there is nothing to review on a {ctx.pr_state} PR")
        raise ReviewError(
            f"PR is {ctx.pr_state}", f"PR-{ctx.pr_state}", "STOP", 9
        )

    say(f"unexpected PR state '{ctx.pr_state}'")
    raise ReviewError(f"unexpected PR state '{ctx.pr_state}'", "ERROR", "STOP", 3)


def render_tree(ctx: ReviewContext) -> None:
    """The `== working tree ==` block: dirt, untracked files and unpushed commits."""
    unpushed = git("log", "--oneline", f"{ctx.upstream}..HEAD") if ctx.upstream else ""

    say("")
    say("== working tree ==")
    if not ctx.uncommitted and not ctx.untracked_files:
        say("clean")
    else:
        say(git("status", "--short"))
    if not ctx.upstream:
        say("no upstream yet — the branch has never been pushed")
    elif unpushed:
        say("unpushed commits:")
        say_block(indent(unpushed))
    else:
        say("no unpushed commits")


def _review_baseline(ctx: ReviewContext) -> tuple[str, str]:
    """The revision to diff against, and how to describe it to the reader."""
    if ctx.pr_state == "OPEN":
        reviews = ctx.prjson.get("latestReviews") or []
        dated = [r for r in reviews if r.get("submittedAt")]
        if dated:
            newest = max(dated, key=lambda r: r["submittedAt"])
            ctx.last_reviewed = (newest.get("commit") or {}).get("oid") or ""

    if ctx.pr_state == "OPEN" and ctx.last_reviewed:
        return ctx.last_reviewed, f"the reviewer's last review ({ctx.last_reviewed[:9]})"
    if ctx.pr_state == "OPEN":
        return (
            ctx.upstream or f"origin/{ctx.base}",
            "the pushed tip (no review submitted yet)",
        )
    return f"origin/{ctx.base}", f"origin/{ctx.base}"


def render_changes(ctx: ReviewContext) -> None:
    """The `== changes to review ==` block and the diff itself.

    Raises `NOTHING-NEW` when HEAD is exactly what was last reviewed and the
    tree is clean, so neither skill re-ships work nobody has changed.
    """
    since, since_label = _review_baseline(ctx)

    reviewed_head = git("rev-parse", ctx.last_reviewed) if ctx.last_reviewed else ""
    if (
        ctx.pr_state == "OPEN"
        and ctx.last_reviewed
        and reviewed_head
        and git("rev-parse", "HEAD") == reviewed_head
        and not ctx.uncommitted
        and not ctx.untracked_files
    ):
        say("")
        say("HEAD is exactly what was last reviewed and the tree is clean —")
        say("there is nothing new to re-review.")
        raise ReviewError("nothing new", "NOTHING-NEW", "STOP", 0)

    say("")
    say(f"== changes to review (since {since_label}) ==")
    commits = git("log", "--reverse", "--format=%h %s", f"{since}..HEAD")
    if commits:
        say("commits:")
        say_block(indent(commits))
    else:
        say("commits: none (all the work is still uncommitted)")
    say("")
    say(f"diffstat vs {since} (committed):")
    say_block(indent(git("diff", "--stat", f"{since}..HEAD")))
    if ctx.uncommitted:
        say("")
        say("diffstat of uncommitted changes:")
        say_block(indent(git("diff", "--stat", "HEAD")))
    if ctx.untracked_files:
        say("")
        say("untracked files (NOT in any diff below — decide whether they belong):")
        say_block(indent("\n".join(ctx.untracked_files)))

    committed_diff = run("git", "diff", f"{since}..HEAD").stdout
    working_diff = run("git", "diff", "HEAD").stdout
    total = len(committed_diff.splitlines()) + len(working_diff.splitlines())

    say("")
    if total > FULL_DIFF_MAX_LINES:
        say(
            f"full diff omitted: {total} lines (> {FULL_DIFF_MAX_LINES}). "
            "Read the files you need."
        )
        return

    say(f"full diff ({total} lines):")
    if committed_diff:
        print(committed_diff, end="" if committed_diff.endswith("\n") else "\n")
    if ctx.uncommitted:
        say("--- uncommitted ---")
        print(working_diff, end="" if working_diff.endswith("\n") else "\n")
    for path in ctx.untracked_files:
        say(f"--- untracked: {path} ---")
        try:
            say(Path(path).read_text())
        except (OSError, UnicodeDecodeError) as err:
            say(f"(unreadable: {err})")


def render_pr_create(ctx: ReviewContext) -> None:
    """The `issue pr create` invocation both skills use to open the PR.

    Identical in both because the PR is opened the same way either way: the
    reviewer, if any, is added afterwards by `issue review request`.
    """
    say("  issue pr create --ready \\")
    say(
        f'    --pr-title "<conventional-commit subject, no [{ctx.issue_id}], '
        'the template adds it>" \\'
    )
    say(
        f"""    --pr-body  "<what changed + why, no 'Closes {ctx.issue_id}', """
        """the template adds it>\""""
    )
    say("")
    say("That pushes, renders pr_title/pr_body, opens the PR ready for review, and")
    say("prints the URL. Add --arg linear_magic_word=Ref if merging this PR must NOT")
    say(f'close {ctx.issue_id}, and --arg also_closes="<ids>" if it resolves issues beyond')
    say(f"{ctx.issue_id}.")


def render_body(ctx: ReviewContext) -> None:
    """Every block between the context block and `== next ==`.

    Kept out of `render_context` because `/issue-review` resolves its reviewer
    alias in between, and an unknown alias must stop the run before any of this
    prints.

    Raises `ReviewError` on any state that ends the run: a worktree with no
    issue record, a merged or closed PR, or nothing new to review.
    """
    require_issue_id(ctx)
    render_pr(ctx)
    render_tree(ctx)
    render_changes(ctx)
