"""Correctness tests for the incremental indexer and query builder.

Run: python3 -m unittest discover -s tests -t . -v
"""

import hashlib
import os
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from history import db, indexer, search
from history.sources import claude_code, codex


def cc_line(seq, role, text, **extra):
    block = {"type": "text", "text": text}
    return json.dumps({
        "type": role, "sessionId": "sess-cc-1", "timestamp": f"2026-08-0{seq}T10:00:00.000Z",
        "cwd": "/home/u/Git/demo", "gitBranch": "main", "isSidechain": False,
        "message": {"content": [block]}, **extra,
    })


def cx_line(kind, payload, ts="2026-08-01T10:00:00.000Z"):
    return json.dumps({"type": kind, "timestamp": ts, "payload": payload})


class Fixture:
    """A throwaway home directory with one transcript per source."""

    def __init__(self, tmp: Path):
        self.cc = tmp / "cc" / "proj"
        self.cx = tmp / "cx"
        self.cc.mkdir(parents=True)
        self.cx.mkdir(parents=True)
        self.db = tmp / "index.db"

    def write(self, path: Path, lines, newline_at_end=True):
        body = "\n".join(lines) + ("\n" if newline_at_end else "")
        path.write_text(body)

    def index(self, rebuild=False):
        claude_code.roots = lambda: [self.cc.parent]
        codex.roots = lambda: [self.cx]
        conn = db.connect(self.db)
        stats = indexer.refresh(conn, [claude_code, codex], rebuild=rebuild)
        conn.close()
        return stats

    def digest(self):
        conn = sqlite3.connect(self.db)
        rows = conn.execute(
            "SELECT source, role, tool, sidechain, seq, text FROM messages ORDER BY id"
        ).fetchall()
        conn.close()
        return len(rows), hashlib.sha256(repr(rows).encode()).hexdigest()

    def rows(self, sql, *params):
        conn = sqlite3.connect(self.db)
        conn.row_factory = sqlite3.Row
        out = conn.execute(sql, params).fetchall()
        conn.close()
        return out


class IndexerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))

    def tearDown(self):
        self.tmp.cleanup()

    def _lines(self, n):
        return [cc_line(i % 9 + 1, "user" if i % 2 else "assistant", f"message number {i}")
                for i in range(n)]

    def test_append_matches_full_build(self):
        """Indexing in three appends must produce exactly the same rows as one pass."""
        lines = self._lines(30)
        target = self.fx.cc / "s.jsonl"

        self.fx.write(target, lines[:10])
        self.fx.index()
        self.fx.write(target, lines[:22])
        self.fx.index()
        self.fx.write(target, lines)
        self.fx.index()
        incremental = self.fx.digest()

        self.fx.index(rebuild=True)
        self.assertEqual(incremental, self.fx.digest())
        self.assertEqual(incremental[0], 30)

    def test_partial_trailing_line_is_deferred(self):
        """A half-written line is skipped, then picked up once the writer completes it."""
        lines = self._lines(5)
        target = self.fx.cc / "s.jsonl"

        self.fx.write(target, lines[:4])
        self.fx.write(target, lines[:4], newline_at_end=True)
        target.write_text(target.read_text() + lines[4][:20])  # torn write
        self.fx.index()
        self.assertEqual(self.fx.digest()[0], 4)

        self.fx.write(target, lines)
        self.fx.index()
        self.assertEqual(self.fx.digest()[0], 5)

    def test_shrunk_file_is_reindexed_from_scratch(self):
        target = self.fx.cc / "s.jsonl"
        self.fx.write(target, self._lines(20))
        self.fx.index()
        self.fx.write(target, self._lines(6))
        self.fx.index()
        self.assertEqual(self.fx.digest()[0], 6)

    def test_unchanged_file_does_no_work(self):
        self.fx.write(self.fx.cc / "s.jsonl", self._lines(8))
        self.fx.index()
        self.assertEqual(self.fx.index().messages_added, 0)

    def test_fts_stays_consistent_after_delete(self):
        target = self.fx.cc / "s.jsonl"
        self.fx.write(target, self._lines(20))
        self.fx.index()
        self.fx.write(target, self._lines(3))
        self.fx.index()
        conn = sqlite3.connect(self.fx.db)
        conn.execute("INSERT INTO messages_fts(messages_fts) VALUES('integrity-check')")
        self.assertEqual(conn.execute("SELECT COUNT(*) FROM messages_fts").fetchone()[0], 3)
        conn.close()


class ClaudeParserTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))

    def tearDown(self):
        self.tmp.cleanup()

    def test_extracts_roles_and_skips_noise(self):
        lines = [
            cc_line(1, "user", "please <system-reminder>ignore me</system-reminder> rebase"),
            json.dumps({"type": "attachment", "attachment": {"type": "file"}}),
            json.dumps({"type": "ai-title", "aiTitle": "A rebase session",
                        "sessionId": "sess-cc-1"}),
            json.dumps({"type": "assistant", "sessionId": "sess-cc-1",
                        "timestamp": "2026-08-01T10:00:01.000Z", "cwd": "/home/u/Git/demo",
                        "message": {"content": [
                            {"type": "tool_use", "name": "Bash",
                             "input": {"command": "git rebase origin/main"}},
                            {"type": "tool_result", "content": "Successfully rebased"},
                        ]}}),
        ]
        self.fx.write(self.fx.cc / "s.jsonl", lines)
        self.fx.index()

        roles = [r["role"] for r in self.fx.rows("SELECT role FROM messages ORDER BY id")]
        self.assertEqual(roles, ["user", "tool", "tool_result"])

        user = self.fx.rows("SELECT text FROM messages WHERE role='user'")[0]["text"]
        self.assertNotIn("ignore me", user)
        self.assertIn("rebase", user)

        title = self.fx.rows("SELECT title FROM sessions")[0]["title"]
        self.assertEqual(title, "A rebase session")

    def test_slash_command_envelopes_become_what_the_user_typed(self):
        envelope = ("<command-message>unslop</command-message>\n"
                    "<command-name>/unslop</command-name>\n"
                    "<command-args>tighten this paragraph</command-args>")
        self.fx.write(self.fx.cc / "s.jsonl", [cc_line(1, "user", envelope)])
        self.fx.index()
        row = self.fx.rows("SELECT role, text FROM messages")[0]
        self.assertEqual(row["role"], "user")
        self.assertEqual(row["text"], "/unslop tighten this paragraph")

    def test_local_command_output_is_a_tool_result_without_ansi(self):
        raw = "<local-command-stdout>Set model to \x1b[1mFable 5\x1b[22m</local-command-stdout>"
        self.fx.write(self.fx.cc / "s.jsonl", [cc_line(1, "user", raw)])
        self.fx.index()
        row = self.fx.rows("SELECT role, text FROM messages")[0]
        self.assertEqual(row["role"], "tool_result")
        self.assertEqual(row["text"], "Set model to Fable 5")

    def test_meta_records_are_not_indexed_as_prose(self):
        self.fx.write(self.fx.cc / "s.jsonl", [cc_line(1, "user", "housekeeping", isMeta=True)])
        self.fx.index()
        self.assertEqual(self.fx.digest()[0], 0)


class CodexParserTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))

    def tearDown(self):
        self.tmp.cleanup()

    def test_drops_injected_context_keeps_real_turns(self):
        lines = [
            cx_line("session_meta", {"id": "sess-cx-1", "cwd": "/home/u/Git/demo",
                                     "timestamp": "2026-08-01T09:59:00.000Z",
                                     "git": {"branch": "main"}}),
            cx_line("response_item", {"type": "message", "role": "developer",
                                      "content": [{"text": "system prompt"}]}),
            cx_line("response_item", {"type": "message", "role": "user", "content": [
                {"text": "<environment_context>\n  <cwd>/home/u</cwd>\n"},
                {"text": "# AGENTS.md instructions\n\nbe terse"},
                {"text": "how do I set a Linear initiative icon?"},
            ]}),
            cx_line("response_item", {"type": "message", "role": "assistant",
                                      "content": [{"text": "Use the icon field."}]}),
            cx_line("response_item", {"type": "custom_tool_call", "name": "exec",
                                      "input": "curl https://api.linear.app"}),
            cx_line("response_item", {"type": "custom_tool_call_output", "output":
                                      json.dumps([{"type": "input_text", "text": "HTTP 200"}])}),
            cx_line("event_msg", {"type": "token_count", "info": {}}),
        ]
        self.fx.write(self.fx.cx / "rollout.jsonl", lines)
        self.fx.index()

        rows = self.fx.rows("SELECT role, text FROM messages ORDER BY id")
        self.assertEqual([r["role"] for r in rows],
                         ["user", "assistant", "tool", "tool_result"])
        self.assertEqual(rows[0]["text"], "how do I set a Linear initiative icon?")
        self.assertEqual(rows[3]["text"], "HTTP 200")

        session = self.fx.rows("SELECT branch, project FROM sessions")[0]
        self.assertEqual(session["branch"], "main")
        self.assertEqual(session["project"], "/home/u/Git/demo")


class QueryTest(unittest.TestCase):
    def test_bare_words_are_anded_terms(self):
        self.assertEqual(search.build_match("advisory lock"), '"advisory" "lock"')

    def test_phrases_operators_and_prefixes_survive(self):
        self.assertEqual(search.build_match('"advisory lock" OR pg_try*'),
                         '"advisory lock" OR "pg_try"*')

    def test_quotes_in_input_cannot_break_the_expression(self):
        self.assertEqual(search.build_match('say "hi'), '"say" "hi"')

    def test_relative_and_absolute_dates(self):
        self.assertTrue(search.parse_when("7d") < search.parse_when("1h"))
        self.assertTrue(search.parse_when("2026-01-02").startswith("2026-01-02"))


if __name__ == "__main__":
    unittest.main()


class ShowAnchorTest(unittest.TestCase):
    """`show --around` must display the matched message even when its role is filtered out."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))
        lines = [
            cc_line(1, "user", "run the migration"),
            json.dumps({"type": "assistant", "sessionId": "sess-cc-1", "cwd": "/home/u/Git/demo",
                        "timestamp": "2026-08-01T10:00:01.000Z", "message": {"content": [
                            {"type": "tool_use", "name": "Bash",
                             "input": {"command": "pnpm migrate"}}]}}),
            cc_line(3, "assistant", "migration applied"),
        ]
        self.fx.write(self.fx.cc / "s.jsonl", lines)
        self.fx.index()

    def tearDown(self):
        self.tmp.cleanup()

    def test_tool_anchor_survives_the_prose_role_filter(self):
        from history import cli

        tool_id = self.fx.rows("SELECT id FROM messages WHERE role='tool'")[0]["id"]
        conn = db.connect(self.fx.db)
        args = cli.build_parser().parse_args(
            ["show", "--around", str(tool_id), "--json", "--before", "1", "--after", "1"]
        )
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            cli.cmd_show(args, conn)
        conn.close()
        ids = [r["id"] for r in json.loads(buf.getvalue())]
        self.assertIn(tool_id, ids)
        self.assertEqual(ids, sorted(ids))


class ScopeTest(unittest.TestCase):
    """The -a / -am ladder: this session, then this harness, then every harness."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))
        here, elsewhere = "sess-cc-1", "sess-cc-2"
        self.fx.write(self.fx.cc / "here.jsonl", [cc_line(1, "user", "shared term alpha")])
        self.fx.write(
            self.fx.cc / "elsewhere.jsonl",
            [json.dumps({"type": "user", "sessionId": elsewhere, "cwd": "/home/u/Git/other",
                         "timestamp": "2026-08-02T10:00:00.000Z",
                         "message": {"content": [{"type": "text", "text": "shared term beta"}]}})],
        )
        self.fx.write(self.fx.cx / "rollout.jsonl", [
            cx_line("session_meta", {"id": "sess-cx-1", "cwd": "/home/u/Git/demo",
                                     "timestamp": "2026-08-01T09:00:00.000Z"}),
            cx_line("response_item", {"type": "message", "role": "user",
                                      "content": [{"text": "shared term gamma"}]}),
        ])
        self.fx.index()
        self.here = here
        self._env = dict(os.environ)
        os.environ["HISTORY_HARNESS"] = "cc"
        os.environ["HISTORY_SESSION"] = here

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._env)
        self.tmp.cleanup()

    def _texts(self, argv):
        from history import cli

        conn = db.connect(self.fx.db)
        args = cli.build_parser().parse_args(argv + ["--json"])
        import contextlib, io

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            args.func(args, conn)
        conn.close()
        return sorted(r["text"] for r in json.loads(buf.getvalue()))

    def test_default_is_this_session_only(self):
        self.assertEqual(self._texts(["--no-refresh", "search", "alpha"]), ["shared term alpha"])

    def test_all_covers_the_harness_but_not_other_harnesses(self):
        self.assertEqual(
            self._texts(["--no-refresh", "search", "term", "-a"]),
            ["shared term alpha", "shared term beta"],
        )

    def test_all_models_covers_every_harness(self):
        self.assertEqual(
            self._texts(["--no-refresh", "search", "term", "-am"]),
            ["shared term alpha", "shared term beta", "shared term gamma"],
        )

    def test_empty_session_result_broadens_to_the_harness(self):
        self.assertEqual(self._texts(["--no-refresh", "search", "beta"]), ["shared term beta"])

    def test_a_widening_filter_lifts_the_session_default(self):
        self.assertEqual(self._texts(["--no-refresh", "search", "term", "--project", "other"]),
                         ["shared term beta"])

    def test_without_a_session_id_the_default_is_the_harness(self):
        del os.environ["HISTORY_SESSION"]
        self.assertEqual(
            self._texts(["--no-refresh", "search", "term"]),
            ["shared term alpha", "shared term beta"],
        )


class AskTest(unittest.TestCase):
    """`ask` must land on an answer without the caller choosing scope or search terms."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))
        self.fx.write(self.fx.cc / "here.jsonl", [
            cc_line(1, "user", "unrelated chatter about lunch"),
        ])
        self.fx.write(self.fx.cc / "elsewhere.jsonl", [
            json.dumps({"type": "user", "sessionId": "sess-cc-2", "cwd": "/home/u/Git/other",
                        "timestamp": f"2026-08-02T10:00:0{i}.000Z",
                        "message": {"content": [{"type": "text", "text": text}]}})
            for i, text in enumerate([
                "why is the plate consume step not atomic",
                "wrap it in a transaction and take the advisory lock first",
                "done, the lock key is derived from the plate id",
            ])
        ])
        self.fx.index()
        self._env = dict(os.environ)
        os.environ["HISTORY_HARNESS"] = "cc"
        os.environ["HISTORY_SESSION"] = "sess-cc-1"

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._env)
        self.tmp.cleanup()

    def _run(self, argv):
        from history import cli

        conn = db.connect(self.fx.db)
        args = cli.build_parser().parse_args(argv)
        import contextlib, io

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = args.func(args, conn)
        conn.close()
        return code, buf.getvalue()

    def test_a_plain_question_finds_the_answer_in_another_session(self):
        code, out = self._run(["--no-refresh", "ask", "how did we make the plate consume atomic"])
        self.assertEqual(code, 0)
        self.assertIn("advisory lock", out)
        self.assertIn("sess-cc-2", out)

    def test_it_shows_the_messages_around_the_hit(self):
        _, out = self._run(["--no-refresh", "ask", "advisory lock"])
        self.assertIn("not atomic", out)
        self.assertIn("lock key is derived", out)

    def test_it_relaxes_to_any_word_when_no_message_holds_every_term(self):
        # No single message mentions the plate, the lock, and the transaction together.
        _, out = self._run(
            ["--no-refresh", "ask", "was the plate consume rewritten with advisory transaction"]
        )
        self.assertIn("any word", out)
        self.assertIn("sess-cc-2", out)

    def test_every_word_matching_wins_when_it_can(self):
        _, out = self._run(["--no-refresh", "ask", "advisory lock"])
        self.assertIn("every word", out)

    def test_a_question_matching_nothing_says_so(self):
        code, out = self._run(["--no-refresh", "ask", "zqxwv"])
        self.assertEqual(code, 1)
        self.assertIn("nothing", out)


class BriefTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))
        self.fx.write(self.fx.cc / "here.jsonl", [cc_line(1, "user", "hello")])
        self.fx.write(self.fx.cx / "rollout.jsonl", [
            cx_line("session_meta", {"id": "sess-cx-1", "cwd": "/home/u/Git/demo",
                                     "timestamp": "2026-08-01T09:00:00.000Z"}),
            cx_line("response_item", {"type": "message", "role": "user",
                                      "content": [{"text": "hello from codex"}]}),
        ])
        self.fx.index()
        self._env = dict(os.environ)
        os.environ["HISTORY_HARNESS"] = "cc"
        os.environ["HISTORY_SESSION"] = "sess-cc-1"

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._env)
        self.tmp.cleanup()

    def _brief(self, argv):
        from history import cli

        conn = db.connect(self.fx.db)
        args = cli.build_parser().parse_args(["--no-refresh", "brief"] + argv)
        import contextlib, io

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            args.func(args, conn)
        conn.close()
        return buf.getvalue()

    def test_it_names_this_harness_and_session(self):
        out = self._brief([])
        self.assertIn("claude-code", out)
        self.assertIn("sess-cc-1", out)
        self.assertNotIn("codex history", out)

    def test_all_models_lists_every_source(self):
        out = self._brief(["-am"])
        self.assertIn("claude-code", out)
        self.assertIn("codex", out)

    def test_a_harness_without_sessions_says_so(self):
        del os.environ["HISTORY_SESSION"]
        os.environ["HISTORY_HARNESS"] = "cx"
        out = self._brief([])
        self.assertIn("publishes no session id", out)
