# ruff: noqa: PT009

from __future__ import annotations

import contextlib
import io
import json
import os
import runpy
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("executable_issue_dispatch.py")
HERDR_SESSION = Path(__file__).parents[4] / "dot_local/bin/executable_herdr-session"
ON_PATH = {"herdr", "claude", "codex", "alacritree"}


class FakeTools:
    """Answers a dispatch's tool calls; worktree n is open in workspace `wn`, shell pane `wn:p1`."""

    def __init__(
        self,
        home: Path,
        *,
        shell: bool = True,
        start_error: str | None = None,
        failing_issue: str | None = None,
        settled_status: str = "done",
        stall_issue_start: bool = False,
    ) -> None:
        self.home = home
        self.stall_issue_start = stall_issue_start
        self.shell = shell
        self.start_error = start_error
        self.failing_issue = failing_issue
        self.settled_status = settled_status
        self.worktrees: list[str] = []
        self.calls: list[list[str]] = []

    def __call__(self, cmd: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
        self.calls.append(cmd)
        out, err, code = self.reply(cmd)
        return subprocess.CompletedProcess(cmd, code, out, err)

    def workspace(self, path: str) -> str:
        return f"w{self.worktrees.index(path) + 1}"

    def reply(self, cmd: list[str]) -> tuple[str, str, int]:
        match cmd:
            case ["gh", "issue", "view", number, *_]:
                return json.dumps({"title": f"Fix the thing #{number}!"}), "", 0
            case ["issue", "setup", issue, *_]:
                if issue == self.failing_issue:
                    return "", "Error: branch already exists", 1
                worktree = self.home / "wt" / issue
                worktree.mkdir(parents=True)
                self.worktrees.append(str(worktree))
                record = {"issue": issue, "worktree": str(worktree), "branch": f"{issue}-x"}
                return f"workspace w1  created  {worktree}\n{json.dumps(record)}\n", "", 0
            case ["git", "-C", path, "rev-parse", "--show-toplevel"]:
                return path, "", 0
            case ["herdr", *args]:
                return self.herdr(args)
            case ["alacritree", "multiplexer", "list", "--json"]:
                panes = [
                    {
                        "multiplexer": {
                            "name": "herdr",
                            "session": "default",
                            "tab_id": f"{self.workspace(path)}:t2",
                            "side": "right",
                            "terminal_id": f"term-{self.workspace(path)}",
                        }
                    }
                    for path in self.worktrees
                ]
                return json.dumps({"panes": panes}), "", 0
            case ["alacritree", "multiplexer", "attach", *_]:
                return json.dumps({"session_id": "s1"}), "", 0
        raise AssertionError(cmd)

    def herdr(self, args: list[str]) -> tuple[str, str, int]:
        match args:
            case ["api", "snapshot"]:
                workspaces = [
                    {"workspace_id": self.workspace(p), "worktree": {"checkout_path": p}}
                    for p in self.worktrees
                ]
                panes = [
                    {
                        "pane_id": f"{self.workspace(p)}:p1",
                        "workspace_id": self.workspace(p),
                        "tab_id": f"{self.workspace(p)}:t1",
                        "cwd": p,
                    }
                    for p in self.worktrees
                    if self.shell
                ]
                result = {"snapshot": {"workspaces": workspaces, "panes": panes}}
            case ["agent", "start", *_, "--pane", pane] if pane.endswith(":p1"):
                if self.start_error:
                    error = {"error": {"code": self.start_error, "message": "no"}}
                    return "", json.dumps(error), 1
                result = {}
            case ["worktree", "list", "--cwd", path]:
                entry = {"path": path, "open_workspace_id": self.workspace(path)}
                result = {"worktrees": [entry], "source": {"repo_root": path}}
            case ["worktree", "open", "--cwd", _, "--path", path, "--no-focus"]:
                result = {"already_open": True, "workspace": {"workspace_id": self.workspace(path)}}
            case ["tab", "create", "--workspace", workspace, *_]:
                result = {"tab": {"tab_id": f"{workspace}:t2"}, "root_pane": {"pane_id": "p2"}}
            case ["agent", "list"]:
                result = {"agents": []}
            case ["agent", "start", *_]:
                result = {}
            case ["agent", "prompt", _, "/issue-start", *_] if self.stall_issue_start:
                error = {"error": {"code": "agent_prompt_stalled", "message": "idle"}}
                return "", json.dumps(error), 1
            case ["agent", "prompt" | "wait", *_]:
                result = {}
            case ["agent", "get", name]:
                result = {"agent": {"agent_status": self.settled_status, "pane_id": f"pane-{name}"}}
            case ["pane", "send-text" | "send-keys", *_]:
                return "", "", 0
            case _:
                raise AssertionError(["herdr", *args])
        return json.dumps({"result": result}), "", 0

    def named(self, *prefix: str) -> list[list[str]]:
        return [cmd for cmd in self.calls if cmd[: len(prefix)] == list(prefix)]


def dispatch(tools: FakeTools, *argv: str) -> list[str]:
    """Runs the script against the checked-in herdr-session, installed in a fake home."""
    installed = tools.home / ".local/bin/herdr-session"
    installed.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(HERDR_SESSION, installed)
    stdout = io.StringIO()
    with (
        patch("sys.argv", [str(SCRIPT), *argv]),
        patch("pathlib.Path.home", return_value=tools.home),
        patch.dict(os.environ, {"XDG_CONFIG_HOME": str(tools.home / ".config")}),
        patch("shutil.which", side_effect=lambda name: name if name in ON_PATH else None),
        patch("subprocess.run", side_effect=tools),
        contextlib.redirect_stdout(stdout),
        contextlib.suppress(SystemExit),
    ):
        os.environ.pop("ALACRITREE_EXE", None)
        runpy.run_path(str(SCRIPT), run_name="__main__")
    return stdout.getvalue().splitlines()


class DispatchTests(unittest.TestCase):
    def setUp(self) -> None:
        home = tempfile.TemporaryDirectory()
        self.addCleanup(home.cleanup)
        self.home = Path(home.name)

    def sent_to(self, tools: FakeTools, agent: str) -> list[list[str]]:
        pane = f"pane-{agent}"
        return [
            cmd[2:]
            for cmd in tools.calls
            if cmd[:4] == ["herdr", "agent", "prompt", agent] or cmd[3:4] == [pane]
        ]

    def test_github_number_gets_slug_and_agent_in_hook_shell(self) -> None:
        tools = FakeTools(self.home)
        lines = dispatch(tools, "--kind", "codex", "#110")
        self.assertEqual(
            tools.named("issue", "setup"),
            [["issue", "setup", "110", "--slug", "fix-the-thing-110", "--summary"]],
        )
        self.assertEqual(
            tools.named("herdr", "agent", "start"),
            [["herdr", "agent", "start", "codex-110", "--kind", "codex", "--pane", "w1:p1"]],
        )
        self.assertEqual(lines, ["#110\t110-x\tcodex-110\tworking\t", "ID-RESULT: OK"])

    def test_linear_ref_writes_summary(self) -> None:
        tools = FakeTools(self.home)
        dispatch(tools, "ENG-12")
        self.assertEqual(tools.named("issue", "setup"), [["issue", "setup", "ENG-12", "--summary"]])

    def test_every_issue_runs_issue_start_before_its_task(self) -> None:
        tools = FakeTools(self.home)
        lines = dispatch(tools, "--extra", "Plan first.", "ENG-12", "110")
        for issue in ("ENG-12", "110"):
            agent = f"claude-{issue.lower()}"
            pane = f"pane-{agent}"
            self.assertEqual(
                self.sent_to(tools, agent),
                [
                    ["prompt", agent, "/issue-start", "--wait", "--timeout", "900000"],
                    ["send-text", pane, f"Now do what issue {issue} says. Plan first."],
                    ["send-keys", pane, "enter"],
                ],
            )
        self.assertEqual(lines[-1], "ID-RESULT: OK")

    def test_start_and_task_overrides_expand_the_issue(self) -> None:
        tools = FakeTools(self.home)
        dispatch(
            tools,
            "--start",
            "/issue-start-migrate {issue}",
            "--task",
            "Plan {issue} only.",
            "--extra",
            "No code.",
            "ENG-12",
        )
        agent, pane = "claude-eng-12", "pane-claude-eng-12"
        self.assertEqual(
            self.sent_to(tools, agent),
            [
                ["prompt", agent, "/issue-start-migrate ENG-12", "--wait", "--timeout", "900000"],
                ["send-text", pane, "Plan ENG-12 only. No code."],
                ["send-keys", pane, "enter"],
            ],
        )

    def test_start_none_prompts_the_task_directly(self) -> None:
        tools = FakeTools(self.home)
        lines = dispatch(tools, "--start", "none", "110")
        self.assertEqual(
            self.sent_to(tools, "claude-110"),
            [["prompt", "claude-110", "Now do what issue 110 says."]],
        )
        self.assertEqual(lines[-1], "ID-RESULT: OK")

    def test_swallowed_enter_on_issue_start_is_pressed_again(self) -> None:
        tools = FakeTools(self.home, stall_issue_start=True)
        lines = dispatch(tools, "ENG-12")
        pane = "pane-claude-eng-12"
        self.assertEqual(
            [cmd[2:] for cmd in tools.calls if cmd[3:4] == [pane] or cmd[2:3] == ["wait"]],
            [
                ["send-keys", pane, "enter"],
                ["wait", "claude-eng-12", "--until", "working", "--timeout", "10000"],
                ["wait", "claude-eng-12", "--timeout", "900000"],
                ["send-text", pane, "Now do what issue ENG-12 says."],
                ["send-keys", pane, "enter"],
            ],
        )
        self.assertEqual(lines[-1], "ID-RESULT: OK")

    def test_question_during_issue_start_holds_the_issue_back(self) -> None:
        tools = FakeTools(self.home, settled_status="blocked")
        lines = dispatch(tools, "ENG-12")
        prompts = [cmd[4] for cmd in tools.named("herdr", "agent", "prompt")]
        self.assertEqual(prompts, ["/issue-start"])
        self.assertEqual(tools.named("herdr", "pane", "send-text"), [])
        self.assertIn("\tblocked\t", lines[0])
        self.assertEqual(lines[-1], "ID-RESULT: FAILED")

    def test_refused_shell_falls_back_to_new_tab(self) -> None:
        tools = FakeTools(self.home, start_error="agent_pane_busy")
        lines = dispatch(tools, "110")
        self.assertEqual(
            [cmd[3::2] for cmd in tools.named("herdr", "agent", "start")],
            [["claude-110", "claude", "w1:p1"], ["a-110", "claude", "p2"]],
        )
        self.assertEqual(tools.named("herdr", "agent", "prompt")[0][3], "a-110")
        self.assertEqual(
            tools.named("alacritree", "multiplexer", "attach"),
            [["alacritree", "multiplexer", "attach", "right", "term-w1", "--no-focus", "--json"]],
        )
        self.assertEqual(lines[-1], "ID-RESULT: OK")

    def test_missing_shell_falls_back_to_new_tab(self) -> None:
        tools = FakeTools(self.home, shell=False)
        dispatch(tools, "110")
        self.assertEqual(
            [cmd[-1] for cmd in tools.named("herdr", "agent", "start")],
            ["p2"],
        )
        self.assertEqual(len(tools.named("herdr", "tab", "create")), 1)

    def test_blocked_agent_is_not_prompted(self) -> None:
        tools = FakeTools(self.home, start_error="agent_not_ready")
        lines = dispatch(tools, "110")
        self.assertEqual(tools.named("herdr", "agent", "prompt"), [])
        self.assertIn("\tblocked\t", lines[0])
        self.assertEqual(lines[-1], "ID-RESULT: FAILED")

    def test_setup_failure_skips_only_that_issue(self) -> None:
        tools = FakeTools(self.home, failing_issue="98")
        lines = dispatch(tools, "98", "110", "#110")
        self.assertEqual(len(tools.named("herdr", "agent", "prompt")), 1)
        self.assertIn("branch already exists", lines[0])
        self.assertEqual(lines[-1], "ID-RESULT: PARTIAL")

    def test_unknown_kind_runs_nothing(self) -> None:
        tools = FakeTools(self.home)
        lines = dispatch(tools, "--kind", "gemini", "110")
        self.assertEqual(tools.named("issue"), [])
        self.assertEqual(lines[-1], "ID-RESULT: BAD-KIND")


if __name__ == "__main__":
    unittest.main()
