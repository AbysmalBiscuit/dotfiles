# ruff: noqa: PT009, PT027

from __future__ import annotations

import json
import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

HELPER = Path(__file__).with_name("executable_herdr-session")
TMP = Path(tempfile.gettempdir()).resolve()
TARGET = str(TMP / "removed-worktree")


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
                "cwd": str(TMP / "elsewhere") if outside else TARGET,
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


class MachineTests(unittest.TestCase):
    def run_helper(
        self, argv: list[str], replies: dict[tuple[str, str], tuple[str, dict]]
    ) -> tuple[object, list[list[str]], list[list[str]]]:
        """Run the helper, answering each `herdr <group> <action>` from `replies`.

        A reply is (error_code, result); a non-empty code is sent as an API error.
        """
        calls: list[list[str]] = []
        spawned: list[list[str]] = []

        def run(cmd: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            calls.append(cmd)
            args = cmd[3:] if cmd[1:2] == ["--machine"] else cmd[1:]
            code, result = replies.get((args[0], args[1]), ("", {}))
            if code:
                return subprocess.CompletedProcess(
                    cmd, 1, "", json.dumps({"error": {"code": code, "message": code}})
                )
            return subprocess.CompletedProcess(cmd, 0, json.dumps({"result": result}), "")

        with (
            patch("sys.argv", [str(HELPER), *argv]),
            patch("shutil.which", return_value="herdr"),
            patch("subprocess.run", side_effect=run),
            patch("subprocess.Popen", side_effect=lambda cmd, **_: spawned.append(cmd)),
            patch.dict("os.environ", {"ALACRITREE_EXE": "alacritree"}),
            self.assertRaises(SystemExit) as raised,
        ):
            runpy.run_path(str(HELPER), run_name="__main__")
        return raised.exception.code, calls, spawned

    def test_opens_remote_checkout_found_by_remote_herdr(self) -> None:
        code, calls, _ = self.run_helper(
            ["--machine", "box", "--path", "/srv/app/src"],
            {
                ("worktree", "list"): (
                    "",
                    {
                        "source": {"repo_root": "/srv/app"},
                        "worktrees": [{"path": "/srv/app"}, {"path": "/srv/app-review"}],
                    },
                ),
                ("worktree", "open"): (
                    "",
                    {"workspace": {"workspace_id": "w3"}, "tab": {"tab_id": "w3:t1"}},
                ),
            },
        )
        self.assertEqual(code, 0)
        self.assertTrue(all(cmd[:3] == ["herdr", "--machine", "box"] for cmd in calls), calls)
        self.assertIn(
            [
                "herdr",
                "--machine",
                "box",
                "worktree",
                "open",
                "--cwd",
                "/srv/app",
                "--path",
                "/srv/app",
                "--no-focus",
                "--label",
                "app",
            ],
            calls,
        )

    def test_opens_remote_directory_outside_git(self) -> None:
        code, calls, _ = self.run_helper(
            ["--machine", "box", "--path", "/srv/notes"],
            {
                ("worktree", "list"): ("not_git_worktree", {}),
                ("pane", "list"): ("", {"panes": []}),
                ("workspace", "create"): (
                    "",
                    {"workspace": {"workspace_id": "w4"}, "tab": {"tab_id": "w4:t1"}},
                ),
            },
        )
        self.assertEqual(code, 0)
        self.assertIn(
            [
                "herdr",
                "--machine",
                "box",
                "workspace",
                "create",
                "--cwd",
                "/srv/notes",
                "--no-focus",
                "--label",
                "notes",
            ],
            calls,
        )

    def test_does_not_start_a_server_for_a_machine(self) -> None:
        code, _, spawned = self.run_helper(
            ["--machine", "box", "--path", "/srv/app"],
            {("worktree", "list"): ("server_not_running", {})},
        )
        self.assertNotEqual(code, 0)
        self.assertEqual(spawned, [])

    def test_requires_absolute_remote_path(self) -> None:
        for argv in (["--machine", "box"], ["--machine", "box", "--path", "app"]):
            with self.subTest(argv=argv):
                code, calls, _ = self.run_helper(argv, {})
                self.assertNotEqual(code, 0)
                self.assertEqual(calls, [])

    def test_rejects_session_with_machine(self) -> None:
        code, calls, _ = self.run_helper(
            ["--machine", "box", "--session", "work", "--path", "/srv/app"], {}
        )
        self.assertNotEqual(code, 0)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
