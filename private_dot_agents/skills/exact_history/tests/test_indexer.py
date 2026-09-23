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


class RepageTest(unittest.TestCase):
    """A database created before PAGE_SIZE was raised must migrate itself."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = Path(self.dir.name) / "index.db"

    def _legacy(self):
        conn = sqlite3.connect(self.path)
        conn.execute("PRAGMA page_size=4096")
        conn.execute("PRAGMA journal_mode=WAL")
        conn.executescript(db.SCHEMA)
        conn.execute(
            "INSERT INTO messages(file_id, source, role, seq, text)"
            " VALUES(1, 'cc', 'user', 0, 'ripgrep beats grep')"
        )
        conn.commit()
        conn.close()

    def test_a_new_database_starts_at_the_larger_page(self):
        conn = db.connect(self.path)
        self.addCleanup(conn.close)
        self.assertEqual(db.PAGE_SIZE, conn.execute("PRAGMA page_size").fetchone()[0])

    def test_an_existing_database_is_repaged_and_left_in_wal(self):
        self._legacy()
        conn = db.connect(self.path)
        self.addCleanup(conn.close)
        self.assertEqual(db.PAGE_SIZE, conn.execute("PRAGMA page_size").fetchone()[0])
        self.assertEqual("wal", conn.execute("PRAGMA journal_mode").fetchone()[0])

    def test_repaging_keeps_rows_searchable(self):
        self._legacy()
        conn = db.connect(self.path)
        self.addCleanup(conn.close)
        hit = conn.execute(
            "SELECT snippet(messages_fts, 0, '<<', '>>', '…', 8) FROM messages_fts"
            " WHERE messages_fts MATCH 'ripgrep'"
        ).fetchone()
        self.assertIn("<<ripgrep>>", hit[0])


class ExclusionTest(unittest.TestCase):
    """Excluded projects stay out of the index, and `forget` keeps a session out for good."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.fx = Fixture(root)
        self.rules = root / "exclude"
        self._env = dict(os.environ)
        os.environ["HISTORY_EXCLUDE"] = str(self.rules)
        os.environ["HISTORY_HARNESS"] = "cc"
        self.addCleanup(self._restore)

        self.fx.write(self.fx.cc / "keep.jsonl", [cc_line(1, "user", "keep this one")])
        # Claude Code names a transcript after its session; the fixture matches so the
        # rebuild path, which has no files row to consult, is genuinely covered.
        self.fx.write(self.fx.cc / "sess-secret.jsonl", [
            json.dumps({"type": "user", "sessionId": "sess-secret", "cwd": "/home/u/Git/secret",
                        "timestamp": "2026-08-02T10:00:00.000Z",
                        "message": {"content": [{"type": "text", "text": "secret material"}]}}),
        ])

    def _restore(self):
        os.environ.clear()
        os.environ.update(self._env)

    def _write_rules(self, *rules):
        from history import excludes

        excludes.save([excludes.normalize(r) for r in rules], self.rules)

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

    def _texts(self):
        return sorted(r["text"] for r in self.fx.rows("SELECT text FROM messages"))

    def test_an_excluded_project_is_never_indexed(self):
        self._write_rules("/home/u/Git/secret")
        stats = self.fx.index()
        self.assertEqual(stats.files_skipped, 1)
        self.assertEqual(self._texts(), ["keep this one"])

    def test_a_sibling_sharing_a_prefix_is_not_excluded(self):
        self._write_rules("/home/u/Git/sec")
        self.fx.index()
        self.assertIn("secret material", self._texts())

    def test_exclude_add_needs_yes_and_then_purges(self):
        self.fx.index()
        self.assertIn("secret material", self._texts())

        code, out = self._run(["exclude", "add", "/home/u/Git/secret"])
        self.assertEqual(code, 1)
        self.assertIn("would delete", out)
        self.assertIn("secret material", self._texts())

        code, out = self._run(["exclude", "add", "/home/u/Git/secret", "--yes"])
        self.assertEqual(code, 0)
        self.assertEqual(self._texts(), ["keep this one"])

        self.fx.index()
        self.assertEqual(self._texts(), ["keep this one"])

    def test_removing_a_rule_brings_the_transcripts_back(self):
        self._run(["exclude", "add", "/home/u/Git/secret", "--yes"])
        self.fx.index()
        self.assertNotIn("secret material", self._texts())

        code, _ = self._run(["exclude", "rm", "/home/u/Git/secret"])
        self.assertEqual(code, 0)
        self.fx.index()
        self.assertIn("secret material", self._texts())

    def test_forget_needs_yes_and_survives_reindexing(self):
        self.fx.index()
        code, out = self._run(["forget", "--session", "sess-secret"])
        self.assertEqual(code, 1)
        self.assertIn("secret material", self._texts())

        code, _ = self._run(["forget", "--session", "sess-secret", "--yes"])
        self.assertEqual(code, 0)
        self.assertEqual(self._texts(), ["keep this one"])

        self.fx.index()
        self.assertEqual(self._texts(), ["keep this one"])
        self.fx.index(rebuild=True)
        self.assertEqual(self._texts(), ["keep this one"])

    def test_forget_survives_a_refresh_even_when_the_filename_hides_the_session(self):
        self.fx.write(self.fx.cc / "opaque.jsonl", [
            json.dumps({"type": "user", "sessionId": "sess-opaque", "cwd": "/home/u/Git/x",
                        "timestamp": "2026-08-03T10:00:00.000Z",
                        "message": {"content": [{"type": "text", "text": "opaque chatter"}]}}),
        ])
        self.fx.index()
        self._run(["forget", "--session", "sess-opaque", "--yes"])
        self.fx.index()
        self.assertNotIn("opaque chatter", self._texts())

    def test_forget_by_project_covers_everything_beneath_it(self):
        self.fx.index()
        code, _ = self._run(["forget", "--project", "/home/u/Git", "--yes"])
        self.assertEqual(code, 0)
        self.assertEqual(self._texts(), [])

    def test_purging_leaves_the_full_text_index_consistent(self):
        self.fx.index()
        self._run(["exclude", "add", "/home/u/Git/secret", "--yes"])
        conn = sqlite3.connect(self.fx.db)
        conn.execute("INSERT INTO messages_fts(messages_fts) VALUES('integrity-check')")
        remaining = conn.execute("SELECT COUNT(*) FROM messages_fts").fetchone()[0]
        conn.close()
        self.assertEqual(remaining, 1)


class ProbeTest(unittest.TestCase):
    """Both formats must yield a project and a session id without a full parse."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_claude_code_finds_cwd_past_the_opening_ui_records(self):
        path = self.root / "9f1c2d3e-0000-4000-8000-000000000001.jsonl"
        path.write_text("\n".join(
            [json.dumps({"type": "last-prompt", "prompt": "hi"})] * 3
            + [cc_line(1, "user", "hello")]
        ) + "\n")
        self.assertEqual(claude_code.probe_project(path), "/home/u/Git/demo")
        self.assertEqual(claude_code.session_id_for(path),
                         "9f1c2d3e-0000-4000-8000-000000000001")

    def test_codex_reads_session_meta_and_the_uuid_in_the_filename(self):
        uuid = "019fc132-814f-7950-9953-843b6c10fa77"
        path = self.root / f"rollout-2026-08-02T08-39-00-{uuid}.jsonl"
        path.write_text(cx_line("session_meta", {"id": uuid, "cwd": "/home/u/Git/demo"}) + "\n")
        self.assertEqual(codex.probe_project(path), "/home/u/Git/demo")
        self.assertEqual(codex.session_id_for(path), uuid)

    def test_a_transcript_with_no_cwd_probes_to_nothing(self):
        path = self.root / "empty.jsonl"
        path.write_text(json.dumps({"type": "last-prompt"}) + "\n")
        self.assertIsNone(claude_code.probe_project(path))


class ExcludeRuleTest(unittest.TestCase):
    def test_a_rule_covers_itself_and_everything_below(self):
        from history import excludes

        rules = ["/home/u/work"]
        self.assertEqual(excludes.matches("/home/u/work", rules), "/home/u/work")
        self.assertEqual(excludes.matches("/home/u/work/a/b", rules), "/home/u/work")
        self.assertIsNone(excludes.matches("/home/u/workshop", rules))
        self.assertIsNone(excludes.matches(None, rules))

    def test_comments_and_blank_lines_are_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            from history import excludes

            path = Path(tmp) / "exclude"
            path.write_text("# a comment\n\n/home/u/work/\n  /home/u/other  \n")
            self.assertEqual(excludes.load(path), ["/home/u/work", "/home/u/other"])


class MarkerTest(unittest.TestCase):
    """A marker file keeps a project out without touching the rule list."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.fx = Fixture(root)
        self.rules = root / "exclude"
        self._env = dict(os.environ)
        os.environ["HISTORY_EXCLUDE"] = str(self.rules)
        os.environ["HISTORY_HARNESS"] = "cc"
        self.addCleanup(self._restore)

        # Two projects on disk, so a marker can cover one and leave the other alone.
        self.open_dir = root / "projects" / "open"
        self.closed_dir = root / "projects" / "closed" / "inner"
        self.open_dir.mkdir(parents=True)
        self.closed_dir.mkdir(parents=True)

        self.fx.write(self.fx.cc / "sess-open.jsonl", [self._line("sess-open", self.open_dir)])
        self.fx.write(self.fx.cc / "sess-closed.jsonl",
                      [self._line("sess-closed", self.closed_dir)])

    def _restore(self):
        os.environ.clear()
        os.environ.update(self._env)

    def _line(self, session, cwd):
        return json.dumps({
            "type": "user", "sessionId": session, "cwd": str(cwd),
            "timestamp": "2026-08-02T10:00:00.000Z",
            "message": {"content": [{"type": "text", "text": f"text from {session}"}]},
        })

    def _texts(self):
        return sorted(r["text"] for r in self.fx.rows("SELECT text FROM messages"))

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

    def test_a_marker_beside_the_project_excludes_it(self):
        (self.closed_dir / ".history_exclude").touch()
        self.fx.index()
        self.assertEqual(self._texts(), ["text from sess-open"])

    def test_a_marker_in_a_parent_excludes_everything_beneath(self):
        (self.closed_dir.parent / ".history_exclude").touch()
        self.fx.index()
        self.assertEqual(self._texts(), ["text from sess-open"])

    def test_the_local_variant_counts_too(self):
        (self.closed_dir / ".history_exclude.local").touch()
        self.fx.index()
        self.assertEqual(self._texts(), ["text from sess-open"])

    def test_a_marker_never_reaches_the_rule_list(self):
        (self.closed_dir / ".history_exclude").touch()
        self.fx.index()
        from history import excludes

        self.assertEqual(excludes.load(self.rules), [])
        self.assertFalse(self.rules.exists())

    def test_deleting_the_marker_brings_the_project_back(self):
        marker = self.closed_dir / ".history_exclude"
        marker.touch()
        self.fx.index()
        self.assertNotIn("text from sess-closed", self._texts())

        marker.unlink()
        self.fx.index()
        self.assertIn("text from sess-closed", self._texts())

    def test_a_marker_added_later_leaves_rows_that_purge_clears(self):
        self.fx.index()
        self.assertEqual(len(self._texts()), 2)

        (self.closed_dir / ".history_exclude").touch()
        code, out = self._run(["exclude"])
        self.assertEqual(code, 0)
        self.assertIn(".history_exclude", out)
        self.assertIn("exclude purge", out)

        code, out = self._run(["exclude", "purge"])
        self.assertEqual(code, 1)
        self.assertEqual(len(self._texts()), 2)

        code, _ = self._run(["exclude", "purge", "--yes"])
        self.assertEqual(code, 0)
        self.assertEqual(self._texts(), ["text from sess-open"])

    def test_a_purged_marker_project_returns_once_the_marker_goes(self):
        self.fx.index()
        marker = self.closed_dir / ".history_exclude"
        marker.touch()
        self._run(["exclude", "purge", "--yes"])
        marker.unlink()
        self.fx.index()
        self.assertIn("text from sess-closed", self._texts())


class ExcludeLocationTest(unittest.TestCase):
    def test_the_rule_list_sits_beside_the_index(self):
        from history import db as dbmod, excludes

        env = dict(os.environ)
        try:
            os.environ.pop("HISTORY_EXCLUDE", None)
            os.environ["HISTORY_DB"] = "/tmp/somewhere/index.db"
            self.assertEqual(excludes.default_path(), Path("/tmp/somewhere/exclude"))
            self.assertEqual(excludes.default_path().parent, dbmod.default_path().parent)
        finally:
            os.environ.clear()
            os.environ.update(env)
