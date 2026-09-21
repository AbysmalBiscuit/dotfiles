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
from dataclasses import dataclass

GITHUB_URL = re.compile(r"^https?://github\.com/[^/]+/[^/]+/issues/(\d+)")
AGENT_NAME_MAX = 32
SLUG_MAX = 40
NEW_TAB_LINE = re.compile(r"^tab \S+\s+\S+ as (\S+)\s", re.MULTILINE)


@dataclass
class Row:
    ref: str
    branch: str = "-"
    agent: str = "-"
    status: str = "failed"
    detail: str = ""


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


def setup(ref: str) -> tuple[str, str, str]:
    """Runs `issue setup`; returns (issue id, worktree, branch)."""
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
    return str(record.get("issue") or number or ref), record["worktree"], record.get("branch", "-")


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


def prompt_agent(name: str, issue: str, extra: str) -> None:
    prompt = f"Work on issue {issue}. {extra}".strip()
    prompted, code, message = herdr("agent", "prompt", name, prompt)
    if prompted is None:
        raise StepError(f"agent prompt: {message or code}")


def dispatch(ref: str, kind: str, extra: str) -> Row:
    row = Row(ref)
    try:
        issue, worktree, row.branch = setup(ref)
        row.agent, blocked = start_agent(kind, issue, worktree)
        if blocked:
            row.status, row.detail = "blocked", "waiting at a startup prompt; not prompted"
            return row
        prompt_agent(row.agent, issue, extra)
        row.status = "working"
    except StepError as error:
        row.detail = str(error)
    return row


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

    rows = [dispatch(ref, args.kind, args.extra) for ref in unique(args.refs)]
    for row in rows:
        print(f"{row.ref}\t{row.branch}\t{row.agent}\t{row.status}\t{row.detail}")
    working = sum(row.status == "working" for row in rows)
    status = "OK" if working == len(rows) else "PARTIAL" if working else "FAILED"
    print(f"ID-RESULT: {status}")
    return 0 if status == "OK" else 1


if __name__ == "__main__":
    sys.exit(main())
