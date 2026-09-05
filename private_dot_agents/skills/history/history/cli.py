"""hist: full-text search over local Claude Code and Codex transcripts."""

import argparse
import json
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

from . import db, excludes, indexer, search
from .sources import LABELS, current_harness, current_session, resolve

PROSE_ROLES = ["user", "assistant", "summary"]
ALL_ROLES = ["user", "assistant", "thinking", "tool", "tool_result", "summary"]


def local_time(ts: str | None) -> str:
    if not ts:
        return "?" * 16
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
    except ValueError:
        return ts[:16]
    return dt.strftime("%Y-%m-%d %H:%M")


def short_project(path: str | None) -> str:
    if not path:
        return "-"
    parts = Path(path).parts
    return "/".join(parts[-2:]) if len(parts) > 1 else path


def one_line(text: str, width: int) -> str:
    text = " ".join(text.split())
    return text if len(text) <= width else text[: width - 1] + "…"


def widen_hint(scope: str) -> str:
    if scope == search.ALL:
        return "That is every indexed session."
    if scope == search.HARNESS:
        return "Widen with -am to include the other harness."
    return "Widen with -a for this harness, or -am for all."


def emit_json(rows) -> None:
    json.dump([dict(r) for r in rows], sys.stdout, indent=1, default=str)
    sys.stdout.write("\n")


def cmd_index(args, conn) -> int:
    stats = indexer.refresh(conn, resolve(args.source), rebuild=args.rebuild, progress=True)
    print(stats.line())
    return 0


def cmd_search(args, conn) -> int:
    scope = search.scope_of(args)
    rows = search.run_search(conn, args, scope)
    if not rows and scope == search.SESSION:
        scope = search.HARNESS
        rows = search.run_search(conn, args, scope)
    if args.json:
        emit_json(rows)
        return 0
    if not rows:
        print(f"no matches in {search.scope_label(scope)}. {widen_hint(scope)}")
        return 1
    for row in rows:
        side = " sidechain" if row["sidechain"] else ""
        print(f"[{row['id']}] {local_time(row['ts'])} {row['source']} {row['role']:<11}"
              f" {row['session_id'][:8] if row['session_id'] else '-':<8}"
              f" {short_project(row['project'])}{side}")
        print("        " + one_line(row["snip"], args.width))
    print(f"\n{len(rows)} hits in {search.scope_label(scope)}."
          f" Read one in context: ~/.agents/skills/history/hist.py show --around <id>")
    return 0


def cmd_sessions(args, conn) -> int:
    scope = search.scope_of(args)
    rows = search.run_sessions(conn, args, scope)
    if not rows and scope == search.SESSION:
        scope = search.HARNESS
        rows = search.run_sessions(conn, args, scope)
    if args.json:
        emit_json(rows)
        return 0
    if not rows:
        print(f"no matches in {search.scope_label(scope)}. {widen_hint(scope)}")
        return 1
    for row in rows:
        print(f"{row['session_id'][:8] if row['session_id'] else '-':<8}"
              f" {local_time(row['first_ts'])} {row['source']} {row['hits']:>4} hits"
              f"  {short_project(row['project'])}")
        if row["title"]:
            print("         " + one_line(row["title"], args.width))
    print(f"\n{len(rows)} sessions in {search.scope_label(scope)}."
          f" Replay one: ~/.agents/skills/history/hist.py show <session-id>")
    return 0


BRIEF_ONE = """You are searching {harness} history.{session}
Coverage: {rows} messages across {sessions} sessions, {span}.{stale}

Default scope is {default}. {widen}

Most questions need one call:
  {exe} ask "what you want to know"

It searches, widens the scope until something lands, falls back from every-word to
any-word matching, and prints each hit with the messages around it. Read its output and
answer from that.

When one call is not enough:
  {exe} search "terms" --role user     ranked snippets, filterable
  {exe} sessions "terms"               which conversations covered it
  {exe} show <session-id>              replay one conversation
"""

BRIEF_ALL = """You are searching every harness on this machine.
{coverage}
Total {rows} messages across {sessions} sessions, {span}.{stale}

Scope is already the widest. Narrow with --source cc or --source cx, --project <repo>,
or --since 7d.

Most questions need one call:
  {exe} ask "what you want to know" -am

It searches, falls back from every-word to any-word matching, and prints each hit with
the messages around it. Read its output and answer from that.

When one call is not enough:
  {exe} search "terms" -am --role user   ranked snippets, filterable
  {exe} sessions "terms" -am             which conversations covered it
  {exe} show <session-id>                replay one conversation
"""

EXE = "~/.agents/skills/history/hist.py"


def cmd_brief(args, conn) -> int:
    """A situation report: what this harness can see, and the command to run next."""
    totals = conn.execute(
        "SELECT COUNT(*) n, MIN(ts) lo, MAX(ts) hi FROM messages"
    ).fetchone()
    sessions = conn.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
    span = f"{local_time(totals['lo'])[:10]} to {local_time(totals['hi'])[:10]}"
    stale = "" if totals["n"] else "\n\nThe index is empty. Run `%s index` first." % EXE

    if args.all_models:
        lines = []
        for row in conn.execute(
            "SELECT source, COUNT(*) n, COUNT(DISTINCT session_id) s FROM messages"
            " GROUP BY source ORDER BY n DESC"
        ):
            lines.append(f"  {LABELS.get(row['source'], row['source']):<12}"
                         f" {row['n']:>8} messages  {row['s']:>5} sessions")
        print(BRIEF_ALL.format(coverage="\n".join(lines), rows=totals["n"],
                               sessions=sessions, span=span, stale=stale, exe=EXE))
        return 0

    harness = LABELS.get(current_harness(), current_harness())
    other = "codex" if current_harness() == "cc" else "claude-code"
    mine = conn.execute(
        "SELECT COUNT(*) n, COUNT(DISTINCT session_id) s FROM messages WHERE source = ?",
        (current_harness(),),
    ).fetchone()

    here = current_session()
    if here:
        indexed = conn.execute(
            "SELECT COUNT(*) FROM messages WHERE source = ? AND session_id = ?",
            (current_harness(), here),
        ).fetchone()[0]
        session = f"\nThis session is {here} ({indexed} messages indexed so far)."
    else:
        session = f"\n{harness} publishes no session id here, so searches start harness-wide."

    if here and not args.all:
        default = "this session, widening on its own when it comes up empty"
        widen = f"Add -a for every {harness} session, or -am to search {other} too."
    elif here:
        default = f"every {harness} session, because you passed -a"
        widen = f"Drop -a to start from this session, or add -am to search {other} too."
    else:
        default = f"every {harness} session"
        widen = f"Add -am to search {other} too."

    print(BRIEF_ONE.format(harness=harness, session=session, rows=mine["n"],
                           sessions=mine["s"], span=span, stale=stale,
                           default=default, widen=widen, exe=EXE))
    return 0


def _window(conn, conn_row, roles: list[str], before: int, after: int) -> list:
    """The prose messages surrounding one hit, with the hit itself always present."""
    holes = ",".join("?" * len(roles))
    source, session_id, seq = conn_row["source"], conn_row["session_id"], conn_row["seq"]
    lead = conn.execute(
        f"SELECT * FROM messages WHERE source=? AND session_id=? AND seq<=? "
        f"AND role IN ({holes}) ORDER BY seq DESC, id DESC LIMIT ?",
        (source, session_id, seq, *roles, before + 1),
    ).fetchall()
    trail = conn.execute(
        f"SELECT * FROM messages WHERE source=? AND session_id=? AND seq>? "
        f"AND role IN ({holes}) ORDER BY seq, id LIMIT ?",
        (source, session_id, seq, *roles, after),
    ).fetchall()
    rows = list(reversed(lead)) + list(trail)
    if all(r["id"] != conn_row["id"] for r in rows):
        cut = sum(1 for r in rows if (r["seq"], r["id"]) < (seq, conn_row["id"]))
        rows.insert(cut, conn_row)
    return rows


def cmd_ask(args, conn) -> int:
    """Search, widen until something lands, and print each answer already in context."""
    hits, scope, relaxed = search.widen(conn, args, search.run_search)
    if not hits:
        print(f"nothing in {search.scope_label(scope)} matches that.")
        return 1

    roles = ALL_ROLES if args.all_roles else PROSE_ROLES
    threads, seen = [], set()
    for hit in hits:
        key = (hit["source"], hit["session_id"])
        if key in seen:
            continue
        seen.add(key)
        threads.append((hit, _window(conn, hit, roles, args.before, args.after)))
        if len(threads) >= args.threads:
            break

    if args.json:
        emit_json([row for _, rows in threads for row in rows])
        return 0

    note = "any word" if relaxed else "every word"
    print(f"scope: {search.scope_label(scope)}, matching {note}")
    for hit, rows in threads:
        print()
        print(f"── {local_time(hit['ts'])} · {short_project(hit['project'])}"
              f" · {hit['source']} · session {hit['session_id']}")
        for row in rows:
            marker = "*" if row["id"] == hit["id"] else " "
            label = row["role"] if not row["tool"] else f"{row['role']}:{row['tool']}"
            text = " ".join(row["text"].split())
            if len(text) > args.chars:
                text = text[: args.chars] + f" … [+{len(text) - args.chars} chars]"
            print(f"{marker}[{row['id']}] {label:<14} {text}")

    print(f"\n{len(threads)} of {len(hits)} hits shown."
          f" Replay one: ~/.agents/skills/history/hist.py show <session-id>")
    return 0


def _resolve_session(conn, prefix: str):
    rows = conn.execute(
        "SELECT DISTINCT source, session_id FROM messages WHERE session_id LIKE ? LIMIT 10",
        (prefix + "%",),
    ).fetchall()
    if not rows:
        raise SystemExit(f"no session starting with {prefix!r}")
    if len(rows) > 1:
        listing = ", ".join(f"{r['session_id']} ({r['source']})" for r in rows)
        raise SystemExit(f"{prefix!r} matches several sessions: {listing}")
    return rows[0]["source"], rows[0]["session_id"]


def cmd_show(args, conn) -> int:
    roles = ALL_ROLES if args.all_roles else (args.roles or PROSE_ROLES)
    placeholders = ",".join("?" * len(roles))

    if args.around is not None:
        anchor = conn.execute(
            "SELECT * FROM messages WHERE id = ?", (args.around,)
        ).fetchone()
        if not anchor:
            raise SystemExit(f"no message with id {args.around}")
        source, session_id, seq = anchor["source"], anchor["session_id"], anchor["seq"]
        before = conn.execute(
            f"SELECT * FROM messages WHERE source=? AND session_id=? AND seq<=? "
            f"AND role IN ({placeholders}) ORDER BY seq DESC, id DESC LIMIT ?",
            (source, session_id, seq, *roles, args.before + 1),
        ).fetchall()
        after = conn.execute(
            f"SELECT * FROM messages WHERE source=? AND session_id=? AND seq>? "
            f"AND role IN ({placeholders}) ORDER BY seq, id LIMIT ?",
            (source, session_id, seq, *roles, args.after),
        ).fetchall()
        rows = list(reversed(before)) + list(after)
        if all(r["id"] != anchor["id"] for r in rows):
            # The hit's own role may sit outside the role filter; never hide it.
            cut = sum(1 for r in rows if (r["seq"], r["id"]) < (seq, anchor["id"]))
            rows.insert(cut, anchor)
    else:
        source, session_id = _resolve_session(conn, args.session)
        rows = conn.execute(
            f"SELECT * FROM messages WHERE source=? AND session_id=? "
            f"AND role IN ({placeholders}) ORDER BY seq, id LIMIT ?",
            (source, session_id, *roles, args.limit),
        ).fetchall()

    if args.json:
        emit_json(rows)
        return 0

    meta = conn.execute(
        "SELECT * FROM sessions WHERE source=? AND session_id=?", (source, session_id)
    ).fetchone()
    header = f"{LABELS.get(source, source)} {session_id}"
    if meta:
        header += f"  {meta['project'] or '-'}"
        if meta["branch"]:
            header += f"  ({meta['branch']})"
        if meta["title"]:
            header += f"\n{meta['title']}"
    print(header)
    print("-" * 72)
    for row in rows:
        marker = "*" if args.around is not None and row["id"] == args.around else " "
        label = row["role"] if not row["tool"] else f"{row['role']}:{row['tool']}"
        print(f"\n{marker}[{row['id']}] {local_time(row['ts'])} {label}")
        text = row["text"]
        if not args.full and len(text) > args.chars:
            text = text[: args.chars] + f"\n  … [+{len(text) - args.chars} chars, --full for all]"
        print("  " + text.replace("\n", "\n  "))
    return 0


def _plural(count: int, noun: str) -> str:
    return f"{count} {noun}" + ("" if count == 1 else "s")


def _describe(targets) -> str:
    by_source = {}
    for source, _ in targets:
        by_source[source] = by_source.get(source, 0) + 1
    parts = [_plural(n, f"{LABELS.get(src, src)} session") for src, n in sorted(by_source.items())]
    return ", ".join(parts) or "no sessions"


def cmd_exclude(args, conn) -> int:
    """Projects the indexer leaves alone, and the transcripts already indexed under them."""
    path = excludes.default_path()
    rules = excludes.load(path)

    if args.action is None:
        return _list_exclusions(conn, path, rules)

    if args.action == "purge":
        stale = indexer.sessions_excluded(conn, indexer.Skipper.load(conn))
        targets = [(source, session_id) for source, session_id, _ in stale]
        if not targets:
            print("nothing indexed is currently excluded")
            return 0
        if not args.yes:
            print(f"would delete {_describe(targets)} that the current exclusions cover")
            print("re-run with --yes to apply")
            return 1
        deleted = _describe(targets)
        _, messages = indexer.purge(conn, targets, tombstone=False)
        print(f"deleted {deleted}, {_plural(messages, 'message')}")
        return 0

    rule = excludes.normalize(args.path)
    if not rule:
        raise SystemExit("exclude needs a project path")

    if args.action == "rm":
        if not excludes.remove(rule, path):
            print(f"{rule} is not excluded")
            return 1
        print(f"{rule} is no longer excluded."
              f" Its transcripts are re-indexed on the next query.")
        return 0

    targets = indexer.sessions_under(conn, [rule])
    known = rule in rules
    if not args.yes:
        if known:
            print(f"{rule} is already excluded.")
        else:
            print(f"would stop indexing anything under {rule}")
        print(f"would delete {_describe(targets)} already indexed under it")
        print("re-run with --yes to apply")
        return 1

    if not known:
        excludes.add(rule, path)
    deleted = _describe(targets)
    _, messages = indexer.purge(conn, targets, tombstone=False)
    tail = ("nothing was indexed under it" if not targets
            else f"deleted {deleted}, {_plural(messages, 'message')}")
    print(f"excluded {rule}; {tail}")
    return 0


def _list_exclusions(conn, path, rules) -> int:
    stale = indexer.sessions_excluded(conn, indexer.Skipper.load(conn))
    by_reason = {}
    for _, _, reason in stale:
        by_reason[reason] = by_reason.get(reason, 0) + 1

    markers = sorted({r for r in by_reason if r not in rules})
    if not rules and not markers:
        print(f"nothing excluded. Add a project: {EXE} exclude add <path> --yes")
        print(f"Or drop a {excludes.MARKERS[0]} file in any project you want left alone.")
        return 0

    if rules:
        print(path)
        for rule in rules:
            print(f"  {rule}{_stale_note(by_reason.get(rule, 0))}")
    if markers:
        print("marker files covering an indexed project")
        for marker in markers:
            print(f"  {marker}{_stale_note(by_reason.get(marker, 0))}")
    if stale:
        print(f"\n{_plural(len(stale), 'excluded session')} still in the index."
              f" Clear with: {EXE} exclude purge --yes")
    return 0


def _stale_note(count: int) -> str:
    return f"  [{count} indexed]" if count else ""


def cmd_forget(args, conn) -> int:
    """Delete sessions from the index for good, whether or not their project is excluded."""
    if args.session:
        source, session_id = _resolve_session(conn, args.session)
        targets = [(source, session_id)]
    else:
        targets = indexer.sessions_under(conn, [excludes.normalize(args.project)])

    if not targets:
        print("nothing indexed matches that")
        return 1
    if not args.yes:
        print(f"would delete {_describe(targets)}")
        for source, session_id in targets[:10]:
            meta = conn.execute(
                "SELECT project, started FROM sessions WHERE source=? AND session_id=?",
                (source, session_id),
            ).fetchone()
            print(f"  {session_id[:8]} {source} {local_time(meta['started'] if meta else None)}"
                  f"  {short_project(meta['project'] if meta else None)}")
        if len(targets) > 10:
            print(f"  … and {len(targets) - 10} more")
        print("re-run with --yes to apply")
        return 1

    forgotten = _describe(targets)
    _, messages = indexer.purge(conn, targets, tombstone=True)
    print(f"forgot {forgotten}, {_plural(messages, 'message')}."
          f" The transcripts stay on disk but are never indexed again.")
    return 0


def cmd_stats(args, conn) -> int:
    total = conn.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
    path = Path(args.db) if args.db else db.default_path()
    size = f"{path.stat().st_size / 1e9:.2f} GB" if path.exists() else "missing"
    print(f"database  {path}  {size}")
    print(f"messages  {total}")
    for row in conn.execute(
        "SELECT source, COUNT(*) n, MIN(ts) lo, MAX(ts) hi FROM messages GROUP BY source"
    ):
        print(f"  {LABELS.get(row['source'], row['source']):<12} {row['n']:>9} messages"
              f"  {local_time(row['lo'])} .. {local_time(row['hi'])}")
    for row in conn.execute("SELECT role, COUNT(*) n FROM messages GROUP BY role ORDER BY n DESC"):
        print(f"  {row['role']:<12} {row['n']:>9}")
    here = current_session()
    print(f"harness   {LABELS.get(current_harness(), current_harness())}"
          f"  session {here or 'not exposed by this harness'}")
    sessions = conn.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
    files = conn.execute("SELECT COUNT(*) FROM files").fetchone()[0]
    print(f"sessions  {sessions} across {files} transcript files")
    rules = excludes.load()
    forgotten = conn.execute("SELECT COUNT(*) FROM forgotten").fetchone()[0]
    if rules or forgotten:
        print(f"excluded  {len(rules)} project{'' if len(rules) == 1 else 's'},"
              f" {forgotten} forgotten session{'' if forgotten == 1 else 's'}"
              f"  ({EXE} exclude)")
    return 0


def add_filters(parser) -> None:
    parser.add_argument("-a", "--all", action="store_true",
                        help="every session of the current harness, not just this one")
    parser.add_argument("-am", "--all-models", action="store_true",
                        help="every session of every harness")
    parser.add_argument("--source", action="append", metavar="cc|cx",
                        help="limit to a source; repeatable")
    parser.add_argument("--role", action="append", choices=ALL_ROLES,
                        help="limit to a role; repeatable")
    parser.add_argument("--project", help="substring of the session's working directory")
    parser.add_argument("--branch", help="substring of the git branch")
    parser.add_argument("--since", help="YYYY-MM-DD, 7d, 36h, today, yesterday")
    parser.add_argument("--until", help="same formats as --since")
    parser.add_argument("--main-only", action="store_true",
                        help="skip subagent sidechain transcripts")
    parser.add_argument("--sort", choices=("rank", "recent"), default="rank")
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--width", type=int, default=200)
    parser.add_argument("--json", action="store_true")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="~/.agents/skills/history/hist.py",
        description="Full-text search over local Claude Code and Codex chat history.",
    )
    parser.add_argument("--db", help="index location (default: ~/.cache/history/index.db)")
    parser.add_argument("--no-refresh", action="store_true",
                        help="skip the incremental index refresh before querying")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("brief", help="what this harness can see, and what to run next")
    p.add_argument("-a", "--all", action="store_true", help=argparse.SUPPRESS)
    p.add_argument("-am", "--all-models", action="store_true",
                   help="describe every harness instead of this one")
    p.set_defaults(func=cmd_brief)

    p = sub.add_parser("ask", help="one call: search, widen if empty, print hits in context")
    p.add_argument("query")
    p.add_argument("--threads", type=int, default=3, help="how many distinct sessions to show")
    p.add_argument("--before", type=int, default=2)
    p.add_argument("--after", type=int, default=3)
    p.add_argument("--chars", type=int, default=400, help="per-message character budget")
    p.add_argument("--all-roles", action="store_true", help="include tool traffic")
    p.add_argument("--snippet", type=int, default=16)
    add_filters(p)
    p.set_defaults(func=cmd_ask)

    p = sub.add_parser("search", help="ranked message snippets matching a query")
    p.add_argument("query")
    p.add_argument("--snippet", type=int, default=16, help="snippet width in tokens")
    add_filters(p)
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("sessions", help="which sessions discussed this, most hits first")
    p.add_argument("query")
    add_filters(p)
    p.set_defaults(func=cmd_sessions)

    p = sub.add_parser("show", help="replay a session, or the messages around a hit")
    p.add_argument("session", nargs="?", help="session id or unique prefix")
    p.add_argument("--around", type=int, metavar="ID", help="message id from search output")
    p.add_argument("--before", type=int, default=4)
    p.add_argument("--after", type=int, default=8)
    p.add_argument("--roles", nargs="*", choices=ALL_ROLES)
    p.add_argument("--all-roles", action="store_true", help="include thinking and tool traffic")
    p.add_argument("--chars", type=int, default=1200, help="per-message character budget")
    p.add_argument("--full", action="store_true", help="no per-message truncation")
    p.add_argument("--limit", type=int, default=60)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_show)

    p = sub.add_parser("index", help="refresh the index (runs automatically before queries)")
    p.add_argument("--rebuild", action="store_true", help="discard and reindex everything")
    p.add_argument("--source", action="append", metavar="cc|cx")
    p.set_defaults(func=cmd_index)

    p = sub.add_parser("exclude", help="projects the indexer leaves alone")
    p.add_argument("action", nargs="?", choices=("add", "rm", "purge"),
                   help="omit to list the rules and marker files in force")
    p.add_argument("path", nargs="?", help="project directory; covers everything beneath it")
    p.add_argument("--yes", action="store_true", help="apply, instead of previewing")
    p.set_defaults(func=cmd_exclude)

    p = sub.add_parser("forget", help="delete indexed sessions for good")
    target = p.add_mutually_exclusive_group(required=True)
    target.add_argument("--session", metavar="ID", help="session id or unique prefix")
    target.add_argument("--project", metavar="PATH",
                        help="project directory; covers everything beneath it")
    p.add_argument("--yes", action="store_true", help="apply, instead of previewing")
    p.set_defaults(func=cmd_forget)

    p = sub.add_parser("stats", help="index size and coverage")
    p.set_defaults(func=cmd_stats)
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "show" and args.session is None and args.around is None:
        raise SystemExit("show needs a session id or --around <message-id>")
    if args.command == "exclude" and args.action in ("add", "rm") and not args.path:
        raise SystemExit(f"exclude {args.action} needs a project path")
    conn = db.connect(Path(args.db) if args.db else None)
    try:
        if args.command in ("ask", "brief", "search", "sessions", "show") and not args.no_refresh:
            try:
                indexer.refresh(conn, resolve(None))
            except sqlite3.OperationalError as exc:
                # Another agent holds the write lock; query what is already indexed.
                print(f"note: index refresh skipped ({exc})", file=sys.stderr)
                conn.rollback()
        return args.func(args, conn)
    finally:
        conn.close()
