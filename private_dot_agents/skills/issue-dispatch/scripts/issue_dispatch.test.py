# ruff: noqa: PT009

from __future__ import annotations

import contextlib
import io
import json
import runpy
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("executable_issue_dispatch.py")


class FakeTools:
    def __init__(
        self,
        *,
        shell: bool = True,
        start_error: str | None = None,
        failing_issue: str | None = None,
        settled_status: str = "done",
    ) -> None:
        self.shell = shell
        self.start_error = start_error
        self.failing_issue = failing_issue
        self.settled_status = settled_status
        self.calls: list[list[str]] = []

    def __call__(self, cmd: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
        self.calls.append(cmd)
        out, err, code = self.reply(cmd)
        return subprocess.CompletedProcess(cmd, code, out, err)

    def reply(self, cmd: list[str]) -> tuple[str, str, int]:
        match cmd:
            case ["herdr-session", "new", "--list-agents"]:
                return "claude\ncodex\n", "", 0
            case ["gh", "issue", "view", number, *_]:
                return json.dumps({"title": f"Fix the thing #{number}!"}), "", 0
            case ["issue", "setup", *rest]:
                issue = rest[1] if rest[0] == "--summary" else rest[0]
                if issue == self.failing_issue:
                    return "", "Error: branch already exists", 1
                record = {"issue": issue, "worktree": f"/wt/{issue}", "branch": f"{issue}-x"}
                return f"workspace w1  created  /wt/{issue}\n{json.dumps(record)}\n", "", 0
            case ["herdr-session", "list", *_]:
                rows = [{"pane_id": "w1:p1", "agent": "shell"}] if self.shell else []
                return json.dumps(rows), "", 0
            case ["herdr", "agent", "start", *_]:
                if self.start_error:
                    error = {"error": {"code": self.start_error, "message": "no"}}
                    return "", json.dumps(error), 1
                return json.dumps({"result": {}}), "", 0
            case ["herdr-session", "new", kind, "--path", path, *_]:
                return f"tab w1:t2  {kind} as fallback  {path}\n", "", 0
            case ["herdr", "agent", "prompt", *_]:
                return json.dumps({"result": {}}), "", 0
            case ["herdr", "agent", "get", *_]:
                agent = {"agent_status": self.settled_status}
                return json.dumps({"result": {"agent": agent}}), "", 0
        raise AssertionError(cmd)

    def named(self, *prefix: str) -> list[list[str]]:
        return [cmd for cmd in self.calls if cmd[: len(prefix)] == list(prefix)]


def dispatch(tools: FakeTools, *argv: str) -> list[str]:
    stdout = io.StringIO()
    with (
        patch("sys.argv", [str(SCRIPT), *argv]),
        patch("subprocess.run", side_effect=tools),
        contextlib.redirect_stdout(stdout),
        contextlib.suppress(SystemExit),
    ):
        runpy.run_path(str(SCRIPT), run_name="__main__")
    return stdout.getvalue().splitlines()


class DispatchTests(unittest.TestCase):
    def test_github_number_gets_slug_and_prompted_agent_in_hook_shell(self) -> None:
        tools = FakeTools()
        lines = dispatch(tools, "--kind", "codex", "--extra", "Plan first.", "#110")
        self.assertEqual(
            tools.named("issue", "setup"),
            [["issue", "setup", "110", "--slug", "fix-the-thing-110"]],
        )
        self.assertEqual(
            tools.named("herdr", "agent", "start"),
            [["herdr", "agent", "start", "codex-110", "--kind", "codex", "--pane", "w1:p1"]],
        )
        self.assertEqual(
            tools.named("herdr", "agent", "prompt"),
            [["herdr", "agent", "prompt", "codex-110", "Work on issue 110. Plan first."]],
        )
        self.assertEqual(lines, ["#110\t110-x\tcodex-110\tworking\t", "ID-RESULT: OK"])

    def test_linear_ref_writes_summary(self) -> None:
        tools = FakeTools()
        dispatch(tools, "ENG-12")
        self.assertEqual(tools.named("issue", "setup"), [["issue", "setup", "--summary", "ENG-12"]])

    def test_summarized_issue_runs_issue_start_before_the_issue(self) -> None:
        tools = FakeTools()
        lines = dispatch(tools, "--extra", "Plan first.", "ENG-12", "ENG-13")
        for issue in ("ENG-12", "ENG-13"):
            agent = f"claude-{issue.lower()}"
            prompts = [cmd[4:] for cmd in tools.named("herdr", "agent", "prompt", agent)]
            self.assertEqual(
                prompts,
                [
                    ["/issue-start", "--wait", "--timeout", "900000"],
                    [f"Now do what issue {issue} says. Plan first."],
                ],
            )
        self.assertEqual(lines[-1], "ID-RESULT: OK")

    def test_question_during_issue_start_holds_the_issue_back(self) -> None:
        tools = FakeTools(settled_status="blocked")
        lines = dispatch(tools, "ENG-12")
        prompts = [cmd[4] for cmd in tools.named("herdr", "agent", "prompt")]
        self.assertEqual(prompts, ["/issue-start"])
        self.assertIn("\tblocked\t", lines[0])
        self.assertEqual(lines[-1], "ID-RESULT: FAILED")

    def test_refused_shell_falls_back_to_new_tab(self) -> None:
        tools = FakeTools(start_error="agent_pane_busy")
        lines = dispatch(tools, "110")
        self.assertEqual(len(tools.named("herdr-session", "new", "claude")), 1)
        self.assertEqual(tools.named("herdr", "agent", "prompt")[0][3], "fallback")
        self.assertEqual(lines[-1], "ID-RESULT: OK")

    def test_missing_shell_falls_back_to_new_tab(self) -> None:
        tools = FakeTools(shell=False)
        dispatch(tools, "110")
        self.assertEqual(tools.named("herdr", "agent", "start"), [])
        self.assertEqual(len(tools.named("herdr-session", "new", "claude")), 1)

    def test_blocked_agent_is_not_prompted(self) -> None:
        tools = FakeTools(start_error="agent_not_ready")
        lines = dispatch(tools, "110")
        self.assertEqual(tools.named("herdr", "agent", "prompt"), [])
        self.assertIn("\tblocked\t", lines[0])
        self.assertEqual(lines[-1], "ID-RESULT: FAILED")

    def test_setup_failure_skips_only_that_issue(self) -> None:
        tools = FakeTools(failing_issue="98")
        lines = dispatch(tools, "98", "110", "#110")
        self.assertEqual(len(tools.named("herdr", "agent", "prompt")), 1)
        self.assertIn("branch already exists", lines[0])
        self.assertEqual(lines[-1], "ID-RESULT: PARTIAL")

    def test_unknown_kind_runs_nothing(self) -> None:
        tools = FakeTools()
        lines = dispatch(tools, "--kind", "gemini", "110")
        self.assertEqual(tools.named("issue"), [])
        self.assertEqual(lines[-1], "ID-RESULT: BAD-KIND")


if __name__ == "__main__":
    unittest.main()
