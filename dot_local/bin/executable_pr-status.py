#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["rich>=13"]
# ///
"""pr-status — at-a-glance triage of your GitHub PRs via `gh`.

Prints two tables:
  1. PRs you authored (open) + what to do next for each.
  2. PRs where you're a reviewer (requested or already reviewed) + your next move.

Data comes from `gh` (already authenticated; JSON via stdlib); rendering — aligned
columns, colour, and clickable OSC 8 PR links — is handled by `rich`.

Each run snapshots every PR's REVIEW / CHECK / ACTION (and, for the reviewing
table, MY VOTE / ACTION) to a per-repo cache under `$XDG_CACHE_HOME/pr-status/`.
The next run compares against that snapshot and renders changed values as
`before → after`, so you see what moved since you last looked.

Usage:
  pr-status.py                 both tables, current repo
  pr-status.py -m | --mine     only the "my PRs" table
  pr-status.py -r | --reviews  only the "reviewing" table
  pr-status.py -R owner/repo   target a specific repo (default: current dir's repo)
  pr-status.py --no-cache      don't read or write the diff cache this run
  pr-status.py -h | --help     this help

Requires: gh (authenticated), uv (resolves rich on first run).
"""

# rich is supplied at runtime via the uv inline-dependency block above; a
# repo-level type checker won't see that ephemeral env.
# pyright: reportMissingImports=false
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import TypedDict, cast

from rich.console import Console
from rich.table import Table
from rich.text import Text


class Author(TypedDict):
    login: str


class Review(TypedDict):
    author: Author
    state: str
    submittedAt: str


class Check(TypedDict, total=False):
    conclusion: str | None
    status: str | None
    state: str | None


class ReviewRequest(TypedDict, total=False):
    login: str


class BasePR(TypedDict):
    number: int
    url: str
    title: str
    headRefName: str


class MinePR(BasePR):
    isDraft: bool
    reviewDecision: str | None
    mergeable: str
    statusCheckRollup: list[Check]
    reviews: list[Review]


class ReviewPR(BasePR):
    author: Author
    latestReviews: list[Review]
    reviewRequests: list[ReviewRequest]

BOTS = {"greptile-apps", "linear-code", "coderabbitai"}
ISSUE_RE = re.compile(r"SWE-[0-9]+", re.IGNORECASE)

FAIL_CONCLUSIONS = {"FAILURE", "ERROR", "TIMED_OUT", "CANCELLED"}
RUN_STATUSES = {"IN_PROGRESS", "QUEUED", "PENDING"}


def gh(args: list[str]) -> object:
    """Run a `gh` command expected to emit JSON and return the parsed value.

    The caller knows the shape it requested via --json and narrows with cast().
    """
    try:
        out = subprocess.run(
            ["gh", *args], capture_output=True, text=True, check=True
        ).stdout
    except FileNotFoundError:
        sys.exit("gh not installed")
    except subprocess.CalledProcessError as exc:
        sys.exit(f"gh {' '.join(args)} failed:\n{exc.stderr.strip()}")
    return json.loads(out) if out.strip() else None


def is_bot(login: str) -> bool:
    return login in BOTS or login.endswith("[bot]")


def issue_of(pr: BasePR) -> str:
    m = ISSUE_RE.search(f"{pr.get('title', '')} {pr.get('headRefName', '')}")
    return m.group(0).upper() if m else "-"


def checks_of(pr: MinePR) -> str:
    rollup = pr.get("statusCheckRollup") or []
    if not rollup:
        return "-"
    if any(
        c.get("conclusion") in FAIL_CONCLUSIONS or c.get("state") in {"FAILURE", "ERROR"}
        for c in rollup
    ):
        return "fail"
    if any(
        c.get("status") in RUN_STATUSES or c.get("state") == "PENDING" for c in rollup
    ):
        return "run"
    return "ok"


def review_text(pr: MinePR) -> str:
    rd = pr.get("reviewDecision")
    if rd == "CHANGES_REQUESTED":
        return "changes"
    if rd == "APPROVED":
        return "approved"
    if rd == "REVIEW_REQUIRED":
        return "awaiting"
    return "commented" if pr.get("reviews") else "awaiting"


def has_replied(pr: MinePR, me: str) -> bool:
    """True when my latest review/comment is newer than the reviewer's — ball in their court."""
    reviews = pr.get("reviews") or []
    mine = max(
        (r["submittedAt"] for r in reviews if r["author"]["login"] == me), default=""
    )
    theirs = max(
        (
            r["submittedAt"]
            for r in reviews
            if r["author"]["login"] != me and not is_bot(r["author"]["login"])
        ),
        default="",
    )
    return bool(mine) and mine > theirs


def mine_action(pr: MinePR, me: str) -> str:
    if pr.get("isDraft"):
        return "draft"
    conflict = pr.get("mergeable") == "CONFLICTING"
    rd = pr.get("reviewDecision")
    if rd == "CHANGES_REQUESTED":
        base = "replied; await re-review" if has_replied(pr, me) else "address changes"
        return base + (" + rebase" if conflict else "")
    if rd == "APPROVED":
        if conflict:
            return "rebase -> merge"
        if checks_of(pr) == "fail":
            return "fix CI -> merge"
        return "MERGE"
    return "awaiting review" + ("; rebase" if conflict else "")


def reviewer_state(pr: ReviewPR, me: str) -> tuple[str, str]:
    """Return (my_vote, action) for a PR where I'm a reviewer."""
    my_votes = [r["state"] for r in pr.get("latestReviews") or [] if r["author"]["login"] == me]
    vote = my_votes[-1] if my_votes else ""
    requested = any(
        (req.get("login") or "") == me for req in pr.get("reviewRequests") or []
    )
    vote_label = {
        "APPROVED": "approved",
        "CHANGES_REQUESTED": "changes",
        "COMMENTED": "commented",
    }.get(vote, "-")

    if requested:
        action = "REVIEW NEEDED"
    elif vote == "APPROVED":
        action = "done (approved)"
    elif vote == "CHANGES_REQUESTED":
        action = "await fixes / re-review"
    elif vote == "COMMENTED":
        action = "commented; decide"
    else:
        action = "REVIEW NEEDED"
    return vote_label, action


def action_style(action: str) -> str:
    if action.startswith(("MERGE", "rebase -> merge", "done")):
        return "green"
    if action.startswith(("address", "fix", "REVIEW NEEDED")):
        return "red"
    if action.startswith("await fixes"):
        return "yellow"
    if action.startswith(("awaiting", "replied", "commented", "draft")):
        return "dim"
    return ""


def pr_link(pr: BasePR) -> Text:
    return Text(f"#{pr['number']}", style=f"link {pr['url']}")


def diff_cell(prev: str | None, cur: str, style: str = "") -> Text:
    """Render `cur` in `style`; if it differs from the cached `prev`, prefix
    the struck-through old value and an arrow so the change reads at a glance."""
    cur_text = Text(cur, style=style)
    if prev is not None and prev != cur:
        return Text.assemble(
            Text(prev, style="dim strike"), Text(" → ", style="dim"), cur_text
        )
    return cur_text


# --- diff cache: per-repo snapshot of each PR's tracked fields between runs ---


def cache_path(repo: str) -> Path:
    base = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    return base / "pr-status" / f"{repo.replace('/', '_')}.json"


def load_cache(path: Path) -> dict[str, dict[str, dict[str, str]]]:
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_cache(path: Path, data: dict[str, dict[str, dict[str, str]]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True))


def resolve_repo(repo: str | None) -> str:
    """The cache key: the explicit --repo, else the current dir's owner/repo."""
    if repo:
        return repo
    info = cast(
        "dict[str, str]", gh(["repo", "view", "--json", "nameWithOwner"])
    )
    return info["nameWithOwner"]


def new_table(*cols: str) -> Table:
    t = Table(box=None, pad_edge=False, header_style="dim", expand=False)
    for c in cols:
        t.add_column(c, no_wrap=(c != "ACTION"))
    return t


def repo_args(repo: str | None) -> list[str]:
    return ["--repo", repo] if repo else []


def mine_table(
    console: Console, me: str, repo: str | None, prev: dict[str, dict[str, str]]
) -> dict[str, dict[str, str]]:
    prs = cast(
        "list[MinePR]",
        gh(
            [
                "pr", "list", *repo_args(repo), "--author", "@me", "--state", "open",
                "--limit", "100", "--json",
                "number,url,title,headRefName,isDraft,reviewDecision,mergeable,statusCheckRollup,reviews",
            ]
        )
        or [],
    )
    console.print("[bold cyan]MY OPEN PRs[/]")
    if not prs:
        console.print("  [dim](none)[/]")
        return {}
    cur: dict[str, dict[str, str]] = {}
    table = new_table("PR", "ISSUE", "REVIEW", "CHECK", "ACTION")
    for pr in prs:
        review, check, action = review_text(pr), checks_of(pr), mine_action(pr, me)
        was = prev.get(str(pr["number"]), {})
        table.add_row(
            pr_link(pr),
            issue_of(pr),
            diff_cell(was.get("review"), review),
            diff_cell(was.get("check"), check),
            diff_cell(was.get("action"), action, action_style(action)),
        )
        cur[str(pr["number"])] = {"review": review, "check": check, "action": action}
    console.print(table)
    return cur


def reviews_table(
    console: Console, me: str, repo: str | None, prev: dict[str, dict[str, str]]
) -> dict[str, dict[str, str]]:
    fields = "number,url,title,headRefName,author,reviewDecision,latestReviews,reviewRequests"
    seen: dict[int, ReviewPR] = {}
    for search in ("review-requested:@me", "reviewed-by:@me"):
        batch = cast(
            "list[ReviewPR]",
            gh(
                [
                    "pr", "list", *repo_args(repo), "--state", "open", "--limit", "100",
                    "--search", search, "--json", fields,
                ]
            )
            or [],
        )
        for pr in batch:
            seen.setdefault(pr["number"], pr)

    console.print("\n[bold cyan]PRs AWAITING MY REVIEW[/]")
    rows = [pr for pr in seen.values() if pr["author"]["login"] != me]
    if not rows:
        console.print("  [dim](none)[/]")
        return {}
    cur: dict[str, dict[str, str]] = {}
    table = new_table("PR", "AUTHOR", "MY VOTE", "ACTION")
    for pr in sorted(rows, key=lambda p: p["number"]):
        vote, action = reviewer_state(pr, me)
        was = prev.get(str(pr["number"]), {})
        table.add_row(
            pr_link(pr),
            pr["author"]["login"],
            diff_cell(was.get("vote"), vote),
            diff_cell(was.get("action"), action, action_style(action)),
        )
        cur[str(pr["number"])] = {"vote": vote, "action": action}
    console.print(table)
    return cur


def main() -> None:
    parser = argparse.ArgumentParser(
        description="At-a-glance triage of your GitHub PRs via gh.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("-m", "--mine", action="store_true", help="only the 'my PRs' table")
    parser.add_argument("-r", "--reviews", action="store_true", help="only the 'reviewing' table")
    parser.add_argument("-R", "--repo", metavar="owner/repo", help="target a specific repo")
    parser.add_argument(
        "--no-cache", action="store_true", help="don't read or write the diff cache"
    )
    args = parser.parse_args()

    want_mine = args.mine or not args.reviews
    want_reviews = args.reviews or not args.mine

    me = cast("dict[str, str]", gh(["api", "user"]))["login"]
    console = Console()

    path = None if args.no_cache else cache_path(resolve_repo(args.repo))
    cache = load_cache(path) if path else {}

    if want_mine:
        cache["mine"] = mine_table(console, me, args.repo, cache.get("mine", {}))
    if want_reviews:
        cache["reviews"] = reviews_table(console, me, args.repo, cache.get("reviews", {}))

    if path:
        save_cache(path, cache)


if __name__ == "__main__":
    main()
