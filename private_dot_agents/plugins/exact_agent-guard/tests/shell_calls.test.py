"""Run shell-call collection through its stdin hook entry point."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "shell_calls.py"


class ShellCallsTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.logs = self.root / "Nextcloud" / "agent-guard" / "shell-calls"
        self.env = {
            **os.environ,
            "AGENT_GUARD_SHELL_LOG_DIR": str(self.logs),
            "AGENT_GUARD_SHELL_LOG": "1",
            "AGENT_GUARD_MACHINE_ID": "test-machine",
        }

    def invoke(self, payload, harness="claude-code", env=None):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--harness", harness],
            input=json.dumps(payload),
            capture_output=True,
            check=False,
            text=True,
            encoding="utf-8",
            env=env or self.env,
            cwd=self.root,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout == ""
        return result

    def records(self):
        return [json.loads(p.read_text(encoding="utf-8")) for p in self.logs.rglob("*.json")]

    def payload(self, command="printf 'hello\\n'") -> dict[str, object]:
        return {
            "hook_event_name": "PreToolUse",
            "session_id": "12345678-aaaa-bbbb-cccc-123456789abc",
            "agent_id": "child-1",
            "agent_type": "researcher",
            "tool_name": "Bash",
            "tool_use_id": "call-1",
            "cwd": "/repo",
            "tool_input": {"command": command, "timeout": 30000},
        }

    def test_full_multiline_command_and_context_survive_without_execution(self):
        command = f"printf 'bad' > '{self.root / 'must-not-exist'}'\n" + "# ü 漢\n" * 20000
        payload = self.payload(command)
        self.invoke(payload)
        records = self.records()
        assert len(records) == 1
        row = records[0]
        assert row["command"] == command
        assert row["session_id"] == "12345678-aaaa-bbbb-cccc-123456789abc"
        assert row["agent_id"] == "child-1"
        assert row["tool_use_id"] == "call-1"
        assert row["cwd"] == "/repo"
        assert row["harness"] == "claude-code"
        assert row["payload"] == payload
        assert not (self.root / "must-not-exist").exists()

    def test_codex_native_and_normalized_payloads_preserve_execution_options(self):
        for tool, tool_input in [
            (
                "exec_command",
                {
                    "cmd": "echo hi",
                    "workdir": "/other",
                    "shell": "/bin/bash",
                    "login": False,
                    "tty": True,
                },
            ),
            ("Bash", {"command": "echo hi", "timeout": 1000}),
            ("shell_command", {"command": "Write-Output hi", "workdir": "C:\\repo"}),
        ]:
            with self.subTest(tool=tool):
                payload = self.payload()
                payload["tool_name"] = tool
                payload["tool_input"] = tool_input
                self.invoke(payload, "codex")
        rows = self.records()
        assert len(rows) == 3
        by_tool = {r["tool_name"]: r for r in rows}
        assert by_tool["exec_command"]["cwd"] == "/other"
        assert by_tool["exec_command"]["payload"]["tool_input"]["login"] is False
        assert by_tool["shell_command"]["cwd"] == "C:\\repo"
        assert all(r["harness"] == "codex" for r in rows)

    def test_resumes_keep_session_folder_and_parallel_calls_do_not_overwrite(self):
        payload = self.payload()
        self.invoke(payload)
        original_parent = next(self.logs.rglob("*.json")).parent
        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(lambda _: self.invoke(payload), range(18)))
        paths = list(self.logs.rglob("*.json"))
        assert len(paths) == 19
        assert {p.parent for p in paths} == {original_parent}
        assert len({r["event_id"] for r in self.records()}) == 19

    def test_machine_and_harness_partition_same_session(self):
        self.invoke(self.payload())
        self.invoke(self.payload(), "codex")
        self.invoke(self.payload(), env={**self.env, "AGENT_GUARD_MACHINE_ID": "other-machine"})
        assert len({p.parent for p in self.logs.rglob("*.json")}) == 3

    def test_session_directories_remain_distinct_on_case_insensitive_filesystems(self):
        for session in ["ABC", "abc"]:
            payload = self.payload()
            payload["session_id"] = session
            self.invoke(payload)
        assert len({str(p.parent).lower() for p in self.logs.rglob("*.json")}) == 2

    def test_non_shell_post_events_and_disabled_capture_do_not_log(self):
        edit = self.payload()
        edit["tool_name"] = "Write"
        self.invoke(edit)
        post = self.payload()
        post["hook_event_name"] = "PostToolUse"
        self.invoke(post)
        self.invoke(self.payload(), env={**self.env, "AGENT_GUARD_SHELL_LOG": "0"})
        assert self.records() == []

    def test_unsafe_ids_cannot_escape_the_log_directory(self):
        payload = self.payload()
        payload["session_id"] = "../../outside"
        self.invoke(payload, env={**self.env, "AGENT_GUARD_MACHINE_ID": "C:\\CON/../"})
        assert len(self.records()) == 1
        assert self.records()[0]["session_id"] == "../../outside"
        assert not (self.root / "outside").exists()

    def test_missing_session_and_command_are_recorded_as_missing(self):
        payload = self.payload()
        del payload["session_id"]
        payload["tool_input"] = {"unexpected": "new harness shape"}
        self.invoke(payload)
        row = self.records()[0]
        assert row["session_id"] is None
        assert row["command"] is None
        assert "missing_session_id" in row["capture_notes"]
        assert "missing_command" in row["capture_notes"]

    def test_unwritable_destination_and_bad_payload_never_deny(self):
        self.logs.parent.mkdir(parents=True)
        self.logs.write_text("not a directory", encoding="utf-8")
        result = self.invoke(self.payload())
        assert "shell-call log" in result.stderr
        for raw in ["{", "[]", "null", "[" * 2000 + "0" + "]" * 2000]:
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--harness", "codex"],
                input=raw,
                capture_output=True,
                check=False,
                text=True,
                env=self.env,
                timeout=10,
            )
            assert result.returncode == 0, result.stderr
            assert result.stdout == ""


if __name__ == "__main__":
    unittest.main()
