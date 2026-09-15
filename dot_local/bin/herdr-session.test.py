# ruff: noqa: PT009, PT027

from __future__ import annotations

import json
import runpy
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

HELPER = Path(__file__).with_name("executable_herdr-session")
TARGET = "/tmp/removed-worktree"


class CloseWorkspaceTests(unittest.TestCase):
    def run_close(
        self,
        *,
        agent: str | None = None,
        busy: bool = False,
        unknown: bool = False,
        outside: bool = False,
    ) -> list[list[str]]:
        panes = [
            {"pane_id": "w1:p1", "workspace_id": "w1", "cwd": TARGET + " (deleted)"},
            {
                "pane_id": "w1:p2",
                "workspace_id": "w1",
                "cwd": "/tmp/elsewhere" if outside else TARGET,
                "agent": agent,
            },
        ]
        calls: list[list[str]] = []

        def run(cmd: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            calls.append(cmd)
            if cmd[1:3] == ["pane", "list"]:
                result = {"panes": panes}
            elif cmd[1:3] == ["pane", "process-info"]:
                pid = 200 if busy and cmd[-1] == "w1:p2" else 100
                result = {
                    "process_info": {}
                    if unknown
                    else {
                        "shell_pid": 100,
                        "foreground_process_group_id": pid,
                        "foreground_processes": [
                            {"pid": pid, "name": "fish" if pid == 100 else "sleep"}
                        ],
                    }
                }
            elif cmd[1:3] == ["workspace", "close"]:
                result = {}
            else:
                raise AssertionError(cmd)
            return subprocess.CompletedProcess(cmd, 0, json.dumps({"result": result}), "")

        with (
            patch("sys.argv", [str(HELPER), "close", "--if-idle", "--path", TARGET]),
            patch("shutil.which", return_value="herdr"),
            patch("subprocess.run", side_effect=run),
        ):
            with self.assertRaises(SystemExit) as raised:
                runpy.run_path(str(HELPER), run_name="__main__")
            self.assertEqual(raised.exception.code, 0)
        return [cmd for cmd in calls if cmd[1:3] == ["workspace", "close"]]

    def test_closes_idle_shells_in_deleted_worktree(self) -> None:
        self.assertEqual(self.run_close(), [["herdr", "workspace", "close", "w1"]])

    def test_preserves_agent_session(self) -> None:
        self.assertEqual(self.run_close(agent="codex"), [])

    def test_preserves_busy_shell(self) -> None:
        self.assertEqual(self.run_close(busy=True), [])

    def test_preserves_unknown_process_state(self) -> None:
        self.assertEqual(self.run_close(unknown=True), [])

    def test_preserves_workspace_with_pane_outside_worktree(self) -> None:
        self.assertEqual(self.run_close(outside=True), [])


if __name__ == "__main__":
    unittest.main()
