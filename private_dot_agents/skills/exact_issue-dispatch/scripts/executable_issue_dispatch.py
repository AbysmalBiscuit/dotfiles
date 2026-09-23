#!/usr/bin/env python3
"""Set up a worktree per issue and start a prompted agent in each.

Run with --help for arguments; ../SKILL.md describes the output.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from importlib.machinery import SourceFileLoader
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType

GITHUB_URL = re.compile(r"^https?://github\.com/[^/]+/[^/]+/issues/(\d+)")
AGENT_NAME_MAX = 32
SLUG_MAX = 40
HERDR_SESSION = Path.home() / ".local/bin/herdr-session"
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


def load_herdr_session() -> ModuleType:
    """The herdr-session script as a module; it has no .py suffix to import by."""
    loader = SourceFileLoader("herdr_session", str(HERDR_SESSION))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise SystemExit(f"cannot load {HERDR_SESSION}")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


hs = load_herdr_session()


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


def start_agent(herdr: hs.Herdr, kind: str, issue: str, worktree: str) -> tuple[str, bool]:
    """Starts the agent in the worktree's idle shell, else in a new tab.

    Returns (name, blocked at startup).
    """
    try:
        rows = hs.sessions(herdr, Path(worktree).resolve())
        pane = next((row["pane_id"] for row in rows if row["agent"] == "shell"), None)
        if pane:
            name = agent_name(kind, issue)
            started, code, _ = herdr.call("agent", "start", name, "--kind", kind, "--pane", pane)
            if started is not None or code == "agent_not_ready":
                return name, started is None
        workspace = hs.workspace_for(herdr, worktree, None)
        tab = hs.new_tab(herdr, workspace, kind, [])
    except SystemExit as error:
        raise StepError(str(error.code)) from None
    hs.attach_tab(herdr, tab.tab_id, focus=False)
    return tab.agent, tab.waiting


def prompt_agent(herdr: hs.Herdr, name: str, prompt: str) -> None:
    prompted, code, message = herdr.call("agent", "prompt", name, prompt.strip())
    if prompted is None:
        raise StepError(f"agent prompt: {message or code}")


def launch(herdr: hs.Herdr, ref: str, kind: str, extra: str) -> Row:
    """Starts the agent. A summarized issue gets /issue-start first; hand_over sends the issue."""
    row = Row(ref)
    try:
        row.issue, worktree, row.branch, summarized = setup(ref)
        row.agent, blocked = start_agent(herdr, kind, row.issue, worktree)
        if blocked:
            row.status, row.detail = "blocked", "waiting at a startup prompt; not prompted"
            return row
        if summarized:
            row.starting = True
        else:
            prompt_agent(herdr, row.agent, f"Work on issue {row.issue}. {extra}")
        row.status = "working"
    except StepError as error:
        row.detail = str(error)
    return row


def hand_over(herdr: hs.Herdr, row: Row, kind: str, extra: str) -> None:
    """Runs issue-start and waits for it to settle, then tells the agent to do the issue."""
    start = ISSUE_START.get(kind, ISSUE_START_FALLBACK)
    waited, code, message = herdr.call(
        "agent", "prompt", row.agent, start, "--wait", "--timeout", ISSUE_START_TIMEOUT_MS
    )
    if code == "agent_prompt_stalled":
        # A slash command can open the autocomplete menu, which swallows the Enter.
        state, _, _ = herdr.call("agent", "get", row.agent)
        pane = (state or {}).get("agent", {}).get("pane_id", "")
        run(["herdr", "pane", "send-keys", pane, "enter"])
        waited, code, message = herdr.call(
            "agent", "wait", row.agent, "--until", "working", "--timeout", "10000"
        )
        if waited is not None:
            waited, code, message = herdr.call(
                "agent", "wait", row.agent, "--timeout", ISSUE_START_TIMEOUT_MS
            )
    if waited is None:
        row.status, row.detail = "failed", f"issue-start: {message or code}"
        return
    state, _, _ = herdr.call("agent", "get", row.agent)
    agent = (state or {}).get("agent", {})
    if agent.get("agent_status") == "blocked":
        row.status = "blocked"
        row.detail = "asked a question during issue-start; not given the issue"
        return
    # `agent prompt` delivers a bracketed paste, which a session that has just
    # oriented treats as untrusted pasted text; typed keystrokes read as the user.
    pane = agent.get("pane_id", "")
    prompt = f"Now do what issue {row.issue} says. {extra}".strip()
    for step in (["send-text", pane, prompt], ["send-keys", pane, "enter"]):
        done = run(["herdr", "pane", *step])
        if done.returncode != 0:
            row.status, row.detail = "failed", f"typing the issue prompt: {output(done)}"
            return


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

    installed = hs.installed_agents()
    if args.kind not in installed:
        print(f"{args.kind} is not installed; choose one of: {', '.join(installed)}")
        print("ID-RESULT: BAD-KIND")
        return 1

    herdr = hs.Herdr(None)
    rows = [launch(herdr, ref, args.kind, args.extra) for ref in unique(args.refs)]
    starting = [row for row in rows if row.starting]
    if starting:
        with ThreadPoolExecutor(max_workers=len(starting)) as pool:
            list(pool.map(lambda row: hand_over(herdr, row, args.kind, args.extra), starting))
    for row in rows:
        print(f"{row.ref}\t{row.branch}\t{row.agent}\t{row.status}\t{row.detail}")
    working = sum(row.status == "working" for row in rows)
    status = "OK" if working == len(rows) else "PARTIAL" if working else "FAILED"
    print(f"ID-RESULT: {status}")
    return 0 if status == "OK" else 1


if __name__ == "__main__":
    sys.exit(main())
