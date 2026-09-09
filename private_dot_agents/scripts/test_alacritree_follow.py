"""Exercise hook input through CLI dispatch without touching live terminals."""

# unittest keeps these script tests runnable without third-party dependencies.
# ruff: noqa: PT009

import io
import json
import os
import runpy
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("executable_alacritree-follow.py")
ROOT = str(Path(__file__).parent)


class FollowTests(unittest.TestCase):
    def invoke(self, env, replies, event="UserPromptSubmit"):
        def run(args, **_kwargs):
            self.assertTrue(replies, f"unexpected command: {args}")
            expected, result = replies.pop(0)
            self.assertEqual(args, expected)
            if isinstance(result, dict):
                result = json.dumps({"result": result})
            return subprocess.CompletedProcess(args, int(result is None), result or "", "")

        with (
            patch.dict(os.environ, env, clear=True),
            patch("sys.stdin", io.StringIO(json.dumps({"hook_event_name": event, "cwd": ROOT}))),
            patch("subprocess.run", side_effect=run),
            patch("shutil.which", side_effect=lambda name: name),
        ):
            runpy.run_path(str(SCRIPT), run_name="__main__")
        self.assertEqual(replies, [])

    def herdr_lookup(self, target="target"):
        return [
            (["git", "-C", ROOT, "rev-parse", "--show-toplevel"], ROOT),
            (
                ["herdr", "pane", "get", "old-pane"],
                {"pane": {"pane_id": "live-pane", "workspace_id": "source"}},
            ),
            (
                ["herdr", "worktree", "list", "--cwd", ROOT],
                {
                    "source": {"repo_root": "/repo"},
                    "worktrees": [{"path": ROOT, "open_workspace_id": target}],
                },
            ),
        ]

    def test_codex_prompt_moves_alacritree(self):
        self.invoke(
            {"ALACRITREE_SESSION_ID": "7"},
            [
                (["alacritree", "session", "move", "7", ROOT], ""),
            ],
        )

    def test_refreshes_project_after_refused_move(self):
        self.invoke(
            {"ALACRITREE_SESSION_ID": "7"},
            [
                (["alacritree", "session", "move", "7", ROOT], None),
                (
                    ["git", "-C", ROOT, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                    str(Path(ROOT) / ".git"),
                ),
                (["alacritree", "project", "refresh", ROOT], ""),
                (["alacritree", "session", "move", "7", ROOT], ""),
            ],
            event="SessionStart",
        )

    def test_herdr_moves_live_pane_without_alacritree_environment(self):
        self.invoke(
            {"HERDR_PANE_ID": "old-pane", "HERDR_WORKSPACE_ID": "stale"},
            [
                *self.herdr_lookup(),
                (
                    [
                        "herdr",
                        "pane",
                        "move",
                        "live-pane",
                        "--new-tab",
                        "--workspace",
                        "target",
                        "--no-focus",
                    ],
                    {"move_result": {"changed": True}},
                ),
            ],
        )

    def test_herdr_same_checkout_does_not_move_inherited_alacritree(self):
        self.invoke(
            {"HERDR_PANE_ID": "old-pane", "ALACRITREE_SESSION_ID": "inherited"},
            self.herdr_lookup("source"),
        )

    def test_opens_destination_without_stealing_focus(self):
        self.invoke(
            {"HERDR_PANE_ID": "old-pane"},
            [
                *self.herdr_lookup(None),
                (
                    ["herdr", "worktree", "open", "--cwd", "/repo", "--path", ROOT, "--no-focus"],
                    {"workspace": {"workspace_id": "target"}},
                ),
                (
                    [
                        "herdr",
                        "pane",
                        "move",
                        "live-pane",
                        "--new-tab",
                        "--workspace",
                        "target",
                        "--no-focus",
                    ],
                    {"move_result": {"changed": True}},
                ),
            ],
        )

    def test_failed_herdr_lookup_does_not_move_inherited_alacritree(self):
        self.invoke(
            {"HERDR_PANE_ID": "old-pane", "ALACRITREE_SESSION_ID": "inherited"},
            [
                (["git", "-C", ROOT, "rev-parse", "--show-toplevel"], ROOT),
                (["herdr", "pane", "get", "old-pane"], None),
            ],
        )

    def test_cwd_changed_and_subagents_do_not_move(self):
        for event in ("CwdChanged", "SubagentStart", "SubagentStop", "PostToolUse"):
            with self.subTest(event=event):
                self.invoke({"ALACRITREE_SESSION_ID": "7"}, [], event=event)

    def test_outside_terminal_is_noop(self):
        self.invoke({}, [])


if __name__ == "__main__":
    unittest.main()
