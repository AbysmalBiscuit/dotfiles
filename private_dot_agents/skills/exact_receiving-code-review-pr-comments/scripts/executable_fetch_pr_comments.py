#!/usr/bin/env python3
"""Fetch every comment on a pull request in one pass.

Covers the three places GitHub keeps them: conversation comments, review
summary bodies, and inline review threads with their resolution state. Bot
chatter and reviewer badge markup are stripped so the output is readable.

Usage: fetch_pr_comments.py [PR] [--all] [--hunks] [--bots] [--json]

Works from a git worktree: gh resolves the repo from the shared remotes and
the PR from this worktree's HEAD.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys

NOISE_BOTS = {
    "vercel",
    "linear-code",
    "supabase",
    "github-actions",
    "netlify",
    "codecov",
    "codecov-commenter",
    "dependabot",
    "sonarcloud",
}

QUERY = """
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      title
      url
      author { login }
      baseRefName
      headRefName
      comments(first: 100) {
        pageInfo { hasNextPage }
        nodes { author { login } createdAt body }
      }
      reviews(first: 100) {
        pageInfo { hasNextPage }
        nodes { author { login } state submittedAt body }
      }
      reviewThreads(first: 100) {
        pageInfo { hasNextPage }
        nodes {
          isResolved
          isOutdated
          path
          line
          originalLine
          comments(first: 50) {
            nodes { author { login } createdAt body diffHunk url }
          }
        }
      }
    }
  }
}
"""

# Reviewer bots wrap each finding in badge images and multi-kilobyte "fix this
# in your IDE" deep links. The alt text carries the priority label, so it is
# kept; the rest is dropped.
CLEANUP = [
    (re.compile(r"<!--.*?-->", re.S), ""),
    (re.compile(r'<a[^>]*href="[^"]*prompt=[^"]*"[^>]*>.*?</a>', re.S), ""),
    (re.compile(r"<picture>.*?</picture>", re.S), ""),
    (re.compile(r'<a[^>]*>\s*<img[^>]*alt="([^"]*)"[^>]*>\s*</a>', re.S), r"[\1]"),
    (re.compile(r'<img[^>]*alt="([^"]*)"[^>]*>', re.S), r"[\1]"),
    (re.compile(r"</?(?:details|summary|p|h[1-6]|sup|source|br)[^>]*>"), ""),
    (re.compile(r"\n{3,}"), "\n\n"),
]


def run(args: list[str]) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(result.stderr.strip() or f"{args[0]} failed")
    return result.stdout


def clean(body: str | None) -> str:
    text = body or ""
    for pattern, replacement in CLEANUP:
        text = pattern.sub(replacement, text)
    return text.strip()


def login(node: dict) -> str:
    return (node.get("author") or {}).get("login") or "ghost"


def resolve_pr(target: str | None) -> tuple[str, str, int]:
    args = ["gh", "pr", "view", "--json", "number,url"]
    if target:
        args.insert(3, target)
    pr = json.loads(run(args))
    match = re.match(r"https?://[^/]+/([^/]+)/([^/]+)/pull/", pr["url"])
    if not match:
        sys.exit(f"cannot parse owner/repo from {pr['url']}")
    return match.group(1), match.group(2), pr["number"]


def render(pr: dict, opts: argparse.Namespace, number: int) -> list[str]:
    everyone = pr["comments"]["nodes"]
    conversation = [
        c for c in everyone if opts.bots or login(c).lower() not in NOISE_BOTS
    ]
    muted = len(everyone) - len(conversation)
    reviews = [r for r in pr["reviews"]["nodes"] if (r.get("body") or "").strip()]
    threads = pr["reviewThreads"]["nodes"]
    resolved = [t for t in threads if t["isResolved"]]
    shown = threads if opts.all else [t for t in threads if not t["isResolved"]]
    truncated = any(
        pr[section]["pageInfo"]["hasNextPage"]
        for section in ("comments", "reviews", "reviewThreads")
    )

    out = [
        f"# PR #{number} — {pr['title']}",
        f"@{login(pr)} · {pr['headRefName']} → {pr['baseRefName']}",
        pr["url"],
    ]
    if truncated:
        out.append("\n> TRUNCATED: a section has more than 100 items.")

    hidden = f", {muted} bot comments hidden — pass --bots to include" if muted else ""
    out.append(f"\n## Conversation comments ({len(conversation)}{hidden})")
    if not conversation:
        out.append("\n_none_")
    for comment in conversation:
        out.append(f"\n### @{login(comment)} · {comment['createdAt'][:10]}\n")
        out.append(clean(comment["body"]))

    out.append(f"\n## Review summaries ({len(reviews)})")
    if not reviews:
        out.append("\n_none_")
    for review in reviews:
        stamp = (review.get("submittedAt") or "")[:10]
        out.append(f"\n### @{login(review)} · {review['state']} · {stamp}\n")
        out.append(clean(review["body"]))

    skipped = (
        f", {len(resolved)} resolved hidden — pass --all to include"
        if resolved and not opts.all
        else ""
    )
    out.append(f"\n## Inline threads ({len(shown)} shown{skipped})")
    if not shown:
        out.append("\n_none_")
    for index, thread in enumerate(shown, start=1):
        comments = thread["comments"]["nodes"]
        first = comments[0] if comments else {}
        line = thread["line"] or thread["originalLine"] or "?"
        tags = []
        if len(comments) > 1:
            tags.append(f"{len(comments)} comments")
        if thread["isOutdated"]:
            tags.append("outdated")
        if thread["isResolved"]:
            tags.append("resolved")
        suffix = f" · {' · '.join(tags)}" if tags else ""
        out.append(f"\n### [{index}] {thread['path']}:{line}{suffix}")
        out.append(first.get("url", ""))
        if opts.hunks and first.get("diffHunk"):
            out.append(f"\n```diff\n{first['diffHunk']}\n```")
        for comment in comments:
            out.append(f"\n@{login(comment)}:\n")
            out.append(clean(comment["body"]))

    return out


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "pr", nargs="?", help="number, URL, or branch (default: current branch)"
    )
    parser.add_argument(
        "--all", action="store_true", help="include resolved inline threads"
    )
    parser.add_argument(
        "--hunks", action="store_true", help="include each thread's diff hunk"
    )
    parser.add_argument(
        "--bots", action="store_true", help="include deploy and link bot comments"
    )
    parser.add_argument(
        "--json", action="store_true", help="raw GraphQL response, no formatting"
    )
    opts = parser.parse_args()

    if not shutil.which("gh"):
        sys.exit("gh is not installed")

    owner, repo, number = resolve_pr(opts.pr)
    response = run(
        [
            "gh", "api", "graphql",
            "-f", f"owner={owner}",
            "-f", f"repo={repo}",
            "-F", f"number={number}",
            "-f", f"query={QUERY}",
        ]
    )

    if opts.json:
        print(response.strip())
        return

    pr = json.loads(response)["data"]["repository"]["pullRequest"]
    print("\n".join(render(pr, opts, number)))


if __name__ == "__main__":
    main()
