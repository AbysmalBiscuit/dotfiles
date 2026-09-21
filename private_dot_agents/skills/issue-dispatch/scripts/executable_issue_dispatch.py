#!/usr/bin/env python3
"""Set up a worktree per issue and start a prompted agent in each.

Run with --help for arguments; ../SKILL.md describes the output.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

GITHUB_URL = re.compile(r"^https?://github\.com/[^/]+/[^/]+/issues/(\d+)")
AGENT_NAME_MAX = 32
SLUG_MAX = 40
NEW_TAB_LINE = re.compile(r"^tab \S+\s+\S+ as (\S+)\s", re.MULTILINE)
ISSUE_START = {"claude": "/issue-start"}
ISSUE_START_FALLBACK = "Run the issue-start skill, then stop."
ISSUE_START_TIMEOUT_MS = "900000"


@dataclass
class Row:
    ref: str
    branch: str = "-"
    agent: str = "-"
    status: str = "failed"
    detail: str = ""
    issue: str = ""
    starting: bool = False


class StepError(Exception):
    pass


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd, capture_output=True, check=False, text=True, encoding="utf-8", errors="replace"
    )


def output(done: subprocess.CompletedProcess[str]) -> str:
    return " ".join((done.stdout + done.stderr).split())


def first_json(text: str) -> dict:
    """The first JSON object in `text`; hooks may print around it."""
    decoder = json.JSONDecoder()
    for match in re.finditer(r"\{", text):
        try:
            value, _ = decoder.raw_decode(text, match.start())
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    return {}


def herdr(*args: str) -> tuple[dict | None, str, str]:
    """Returns (result, error_code, message); result is None on failure."""
    done = run(["herdr", *args])
    payload = first_json(done.stdout) or first_json(done.stderr)
    error = payload.get("error")
    if isinstance(error, dict):
        return None, str(error.get("code") or ""), str(error.get("message") or "")
    result = payload.get("result")
    if done.returncode != 0 or not isinstance(result, dict):
        return None, "", output(done) or f"herdr {' '.join(args)} failed"
    return result, "", ""


def slugify(title: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    if len(slug) > SLUG_MAX:
        slug = slug[:SLUG_MAX].rsplit("-", 1)[0]
    return slug or "issue"


def github_number(ref: str) -> str | None:
    bare = ref.removeprefix("#")
    if bare.isdigit():
        return bare
    match = GITHUB_URL.match(ref)
    return match.group(1) if match else None


def setup(ref: str) -> tuple[str, str, str, bool]:
    """Runs `issue setup`; returns (issue id, worktree, branch, summary written)."""
    number = github_number(ref)
    if number:
        done = run(["gh", "issue", "view", number, "--json", "title"])
        if done.returncode != 0:
            raise StepError(f"gh issue view {number}: {output(done)}")
        title = first_json(done.stdout).get("title", "")
        cmd = ["issue", "setup", number, "--slug", slugify(title)]
    else:
        cmd = ["issue", "setup", "--summary", ref]
    done = run(cmd)
    record = first_json(done.stdout)
    if done.returncode != 0 or "worktree" not in record:
        raise StepError(f"issue setup: {output(done)}")
    issue = str(record.get("issue") or number or ref)
    return issue, record["worktree"], record.get("branch", "-"), number is None


def agent_name(kind: str, issue: str) -> str:
    return re.sub(r"[^a-z0-9_-]+", "-", f"{kind}-{issue}".lower())[:AGENT_NAME_MAX]


def shell_pane(worktree: str) -> str | None:
    done = run(["herdr-session", "list", "--path", worktree, "--json"])
    if done.returncode != 0:
        return None
    try:
        rows = json.loads(done.stdout or "[]")
    except json.JSONDecodeError:
        return None
    return next((row["pane_id"] for row in rows if row.get("agent") == "shell"), None)


def start_agent(kind: str, issue: str, worktree: str) -> tuple[str, bool]:
    """Starts the agent; returns (name, blocked at startup)."""
    pane = shell_pane(worktree)
    if pane:
        name = agent_name(kind, issue)
        started, code, _ = herdr("agent", "start", name, "--kind", kind, "--pane", pane)
        if started is not None or code == "agent_not_ready":
            return name, started is None
    done = run(["herdr-session", "new", kind, "--path", worktree, "--no-focus"])
    match = NEW_TAB_LINE.search(done.stdout)
    if done.returncode != 0 or not match:
        raise StepError(f"herdr-session new: {output(done)}")
    return match.group(1), "waiting for startup input" in done.stderr


def prompt_agent(name: str, prompt: str) -> None:
    prompted, code, message = herdr("agent", "prompt", name, prompt.strip())
    if prompted is None:
        raise StepError(f"agent prompt: {message or code}")


def launch(ref: str, kind: str, extra: str) -> Row:
    """Starts the agent. A summarized issue gets /issue-start first; hand_over sends the issue."""
    row = Row(ref)
    try:
        row.issue, worktree, row.branch, summarized = setup(ref)
        row.agent, blocked = start_agent(kind, row.issue, worktree)
        if blocked:
            row.status, row.detail = "blocked", "waiting at a startup prompt; not prompted"
            return row
        if summarized:
            row.starting = True
        else:
            prompt_agent(row.agent, f"Work on issue {row.issue}. {extra}")
        row.status = "working"
    except StepError as error:
        row.detail = str(error)
    return row


def hand_over(row: Row, kind: str, extra: str) -> None:
    """Runs issue-start and waits for it to settle, then tells the agent to do the issue."""
    start = ISSUE_START.get(kind, ISSUE_START_FALLBACK)
    waited, code, message = herdr(
        "agent", "prompt", row.agent, start, "--wait", "--timeout", ISSUE_START_TIMEOUT_MS
    )
    if waited is None:
        row.status, row.detail = "failed", f"issue-start: {message or code}"
        return
    state, _, _ = herdr("agent", "get", row.agent)
    if (state or {}).get("agent", {}).get("agent_status") == "blocked":
        row.status = "blocked"
        row.detail = "asked a question during issue-start; not given the issue"
        return
    try:
        prompt_agent(row.agent, f"Now do what issue {row.issue} says. {extra}")
    except StepError as error:
        row.status, row.detail = "failed", str(error)


def unique(refs: list[str]) -> list[str]:
    seen: dict[str, str] = {}
    for ref in refs:
        key = github_number(ref) or ref.lower()
        seen.setdefault(key, ref)
    return list(seen.values())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "refs", nargs="+", metavar="REF", help="GitHub number or URL, Linear id or URL"
    )
    parser.add_argument("--kind", default="claude", help="installed agent kind")
    parser.add_argument("--extra", default="", help="text appended to every agent's prompt")
    args = parser.parse_args()

    installed = run(["herdr-session", "new", "--list-agents"]).stdout.split()
    if args.kind not in installed:
        print(f"{args.kind} is not installed; choose one of: {', '.join(installed)}")
        print("ID-RESULT: BAD-KIND")
        return 1

    rows = [launch(ref, args.kind, args.extra) for ref in unique(args.refs)]
    starting = [row for row in rows if row.starting]
    if starting:
        with ThreadPoolExecutor(max_workers=len(starting)) as pool:
            list(pool.map(lambda row: hand_over(row, args.kind, args.extra), starting))
    for row in rows:
        print(f"{row.ref}\t{row.branch}\t{row.agent}\t{row.status}\t{row.detail}")
    working = sum(row.status == "working" for row in rows)
    status = "OK" if working == len(rows) else "PARTIAL" if working else "FAILED"
    print(f"ID-RESULT: {status}")
    return 0 if status == "OK" else 1


if __name__ == "__main__":
    sys.exit(main())
