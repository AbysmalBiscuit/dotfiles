#!/usr/bin/env python3
"""Cases for tool_checks/typographic_punctuation.py and the ask tier it uses.

Which half of a call is read matters most: the text a call adds is checked and
the text it removes is not, or the rule would refuse the very edit that takes
an em dash back out. After that, exit 2 has to survive the trip through the
hook and reach the harness as an ask rather than as a refusal. Every character
under test is written as an escape, so this file is ASCII.
"""

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).parent.parent
CHECK = ROOT / "tool_checks" / "typographic_punctuation.py"
GUARD = ROOT / "scripts" / "agent_guard.py"

EM_DASH = "\u2014"
EN_DASH = "\u2013"
INTERPUNCT = "\u00b7"

ASK_EXIT = 2


def load_check():
    """The check as a module, for the roster it read at import."""
    spec = importlib.util.spec_from_file_location("check_under_test", CHECK)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check(tool, tool_input):
    payload = {"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": tool_input}
    result = subprocess.run(
        [sys.executable, str(CHECK), tool],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=15,
    )
    return result.stdout.strip(), result.returncode


class RefusedCharacters(unittest.TestCase):
    def test_em_dash_in_a_shell_command_is_denied(self):
        out, code = check("Bash", {"command": f'git commit -m "adds a thing {EM_DASH} and another"'})

        self.assertEqual(code, 1)
        self.assertIn("em dash", out)

    def test_en_dash_in_written_file_content_is_denied(self):
        out, code = check("Write", {"file_path": "notes.md", "content": f"pages 3{EN_DASH}5\n"})

        self.assertEqual(code, 1)
        self.assertIn("en dash", out)

    def test_replacement_text_of_an_edit_is_denied(self):
        out, code = check("Edit", {"old_string": "before", "new_string": f"after {EM_DASH} more"})

        self.assertEqual(code, 1)
        self.assertIn("em dash", out)

    def test_one_edit_of_a_multi_edit_is_enough(self):
        out, code = check(
            "MultiEdit",
            {"edits": [{"new_string": "clean"}, {"new_string": f"dirty {EM_DASH} here"}]},
        )

        self.assertEqual(code, 1)
        self.assertIn("em dash", out)

    def test_added_patch_lines_are_denied(self):
        patch = f"*** Begin Patch\n*** Update File: a.md\n+a line {EM_DASH} here\n*** End Patch"
        out, code = check("apply_patch", {"command": patch})

        self.assertEqual(code, 1)
        self.assertIn("em dash", out)


class TextTheCallDoesNotAdd(unittest.TestCase):
    def test_removing_a_dash_through_an_edit_is_allowed(self):
        out, code = check("Edit", {"old_string": f"before {EM_DASH} after", "new_string": "before, after"})

        self.assertEqual((out, code), ("", 0))

    def test_removed_patch_lines_are_allowed(self):
        patch = f"*** Begin Patch\n*** Update File: a.md\n-a line {EM_DASH} here\n+a line, here\n*** End Patch"
        out, code = check("apply_patch", {"command": patch})

        self.assertEqual((out, code), ("", 0))

    def test_a_search_is_not_a_write(self):
        out, code = check("Grep", {"pattern": EM_DASH, "path": "."})

        self.assertEqual((out, code), ("", 0))

    def test_an_escape_is_not_the_character(self):
        out, code = check("Write", {"content": 'DASH = "\\u2014"\n'})

        self.assertEqual((out, code), ("", 0))


class InterpunctAsks(unittest.TestCase):
    def test_interpunct_in_content_asks_rather_than_refusing(self):
        out, code = check("Write", {"content": f"home {INTERPUNCT} docs {INTERPUNCT} api\n"})

        self.assertEqual(code, ASK_EXIT)
        self.assertIn("interpunct", out)

    def test_a_refusal_outranks_a_question(self):
        out, code = check("Write", {"content": f"a {INTERPUNCT} b {EM_DASH} c\n"})

        self.assertEqual(code, 1)
        self.assertIn("em dash", out)


class TheShippedRoster(unittest.TestCase):
    """Pasting a character into banned_characters.txt is all it takes to ban
    it, so every line of that file is exercised rather than a chosen few."""

    def test_every_refused_character_is_denied_by_name(self):
        for char in load_check().REFUSED:
            with self.subTest(codepoint="U+%04X" % ord(char)):
                out, code = check("Write", {"content": "a %s b" % char})

                self.assertEqual(code, 1)
                self.assertIn("U+%04X" % ord(char), out)

    def test_every_asked_character_reaches_the_human(self):
        for char in load_check().ASKED:
            with self.subTest(codepoint="U+%04X" % ord(char)):
                out, code = check("Write", {"content": "a %s b" % char})

                self.assertEqual(code, ASK_EXIT)
                self.assertIn("U+%04X" % ord(char), out)

    def test_the_ellipsis_and_the_arrows_are_on_it(self):
        refused = load_check().REFUSED

        self.assertIn(chr(0x2026), refused)
        self.assertIn(chr(0x2192), refused)


class RosterParsing(unittest.TestCase):
    def load(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "roster.txt"
            path.write_text(text, encoding="utf-8")
            return load_check().load_roster(path)

    def test_a_tier_header_moves_later_lines_to_the_other_tier(self):
        refused, asked, _ = self.load("A\n[ask]\nC\n")

        self.assertEqual((refused, asked), (("A",), ("C",)))

    def test_advice_is_the_rest_of_the_line_and_optional(self):
        _, _, fixes = self.load("# a note\n\nA\twrite B instead\nC\n")

        self.assertEqual(fixes, {"A": "write B instead"})

    def test_a_missing_roster_bans_nothing(self):
        empty = load_check().load_roster(pathlib.Path("/nonexistent/roster.txt"))

        self.assertEqual(empty, ((), (), {}))


class ThroughTheHook(unittest.TestCase):
    """The whole path, so the exit codes are read as decisions rather than as
    two numbers a caller happens to agree on."""

    def decision(self, tool, tool_input):
        with tempfile.TemporaryDirectory() as directory:
            payload = {
                "session_id": "test-session",
                "cwd": directory,
                "hook_event_name": "PreToolUse",
                "tool_name": tool,
                "tool_input": tool_input,
            }
            result = subprocess.run(
                [sys.executable, str(GUARD)],
                input=json.dumps(payload),
                capture_output=True,
                text=True,
                cwd=directory,
                timeout=20,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.strip(), "hook returned no output")
        return json.loads(result.stdout)["hookSpecificOutput"]

    def test_em_dash_reaches_the_harness_as_a_denial(self):
        out = self.decision("Write", {"file_path": "a.md", "content": f"x {EM_DASH} y\n"})

        self.assertEqual(out["permissionDecision"], "deny")
        self.assertIn("em dash", out["permissionDecisionReason"])

    def test_interpunct_reaches_the_harness_as_a_question(self):
        out = self.decision("Write", {"file_path": "a.md", "content": f"x {INTERPUNCT} y\n"})

        self.assertEqual(out["permissionDecision"], "ask")
        self.assertIn("interpunct", out["permissionDecisionReason"])
        self.assertIn("interpunct", out["additionalContext"])

    def test_clean_content_is_not_questioned(self):
        with tempfile.TemporaryDirectory() as directory:
            payload = {
                "session_id": "test-session",
                "cwd": directory,
                "hook_event_name": "PreToolUse",
                "tool_name": "Write",
                "tool_input": {"file_path": "a.md", "content": "x, y\n"},
            }
            result = subprocess.run(
                [sys.executable, str(GUARD)],
                input=json.dumps(payload),
                capture_output=True,
                text=True,
                cwd=directory,
                timeout=20,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
