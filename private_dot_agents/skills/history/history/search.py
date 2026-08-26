"""Query building: FTS5 match expressions, filters, and result rows."""

import re
from datetime import datetime, timedelta, timezone

from .sources import LABELS, current_harness, current_session

TOKEN = re.compile(r'"[^"]*"|\S+')
OPERATORS = {"AND", "OR", "NOT", "NEAR"}

# Question words carry no signal; AND-ing them makes a plain question match nothing.
STOPWORDS = {
    "a", "an", "the", "and", "or", "of", "to", "in", "on", "for", "from", "with", "about",
    "at", "by", "as", "is", "are", "was", "were", "be", "been", "do", "does", "did", "can",
    "could", "should", "would", "will", "have", "has", "had", "what", "when", "where",
    "why", "how", "who", "which", "that", "this", "these", "those", "it", "its", "we",
    "our", "us", "i", "my", "me", "you", "your", "they", "them", "there", "here", "any",
    "some", "again", "ever", "before", "after", "up", "out", "get", "got", "make", "made",
}


def content_terms(query: str) -> list[str]:
    """The query's tokens with question filler removed, quoted phrases left intact."""
    kept = []
    for token in TOKEN.findall(query.strip()):
        if token in OPERATORS or token.startswith('"'):
            kept.append(token)
            continue
        if token.strip(".,?!:;").lower() in STOPWORDS:
            continue
        kept.append(token)
    return kept or TOKEN.findall(query.strip())


def loose_match(query: str) -> str:
    """An OR of the query's content terms, ranked by BM25 so the best match leads."""
    terms = [t for t in content_terms(query) if t not in OPERATORS]
    return build_match(" OR ".join(terms))


def build_match(query: str) -> str:
    """Turn a plain query into FTS5 syntax.

    Bare words become AND-ed terms, "quoted runs" stay phrases, a trailing *
    means prefix match, and uppercase AND/OR/NOT/NEAR pass through as operators.
    """
    parts = []
    for token in TOKEN.findall(query.strip()):
        if token in OPERATORS or token in ("(", ")"):
            parts.append(token)
            continue
        prefix = token.endswith("*")
        if prefix:
            token = token[:-1]
        token = token.strip('"')
        if not token:
            continue
        parts.append('"' + token.replace('"', '""') + '"' + ("*" if prefix else ""))
    if not parts:
        raise SystemExit("empty query")
    return " ".join(parts)


def parse_when(value: str) -> str:
    """Accept 2026-08-01, 7d, 36h, 90m, today, or yesterday; return an ISO UTC bound."""
    value = value.strip().lower()
    now = datetime.now(timezone.utc)
    if value == "today":
        return now.replace(hour=0, minute=0, second=0, microsecond=0).isoformat()
    if value == "yesterday":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=1)
        return start.isoformat()
    match = re.fullmatch(r"(\d+)([dhwm])", value)
    if match:
        n, unit = int(match.group(1)), match.group(2)
        delta = {"d": timedelta(days=n), "w": timedelta(weeks=n),
                 "h": timedelta(hours=n), "m": timedelta(minutes=n)}[unit]
        return (now - delta).isoformat()
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        raise SystemExit(f"cannot read date {value!r}; use YYYY-MM-DD, 7d, 36h, today, yesterday")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.isoformat()


SESSION, HARNESS, ALL = "session", "harness", "all"

# Filters that only make sense across sessions; passing one lifts the session default.
WIDENING = ("source", "project", "branch", "since", "until")


def scope_of(args) -> str:
    """Resolve the -a / -am ladder, and widen off this session when a filter demands it."""
    if getattr(args, "all_models", False):
        return ALL
    if getattr(args, "all", False):
        return HARNESS
    if any(getattr(args, name, None) for name in WIDENING):
        return HARNESS
    return SESSION if current_session() else HARNESS


def scope_label(scope: str) -> str:
    if scope == ALL:
        return "all harnesses"
    if scope == HARNESS:
        return LABELS.get(current_harness(), current_harness())
    return "this session"


def filters(args, scope: str | None = None) -> tuple[list[str], list]:
    scope = scope or scope_of(args)
    where, params = [], []

    if getattr(args, "source", None):
        names = [s.strip().lower()[:2] for s in args.source]
        where.append("m.source IN (%s)" % ",".join("?" * len(names)))
        params += names
    elif scope != ALL:
        where.append("m.source = ?")
        params.append(current_harness())

    if scope == SESSION:
        where.append("m.session_id = ?")
        params.append(current_session())

    if getattr(args, "role", None):
        where.append("m.role IN (%s)" % ",".join("?" * len(args.role)))
        params += args.role
    if getattr(args, "project", None):
        where.append("s.project LIKE ?")
        params.append(f"%{args.project}%")
    if getattr(args, "branch", None):
        where.append("s.branch LIKE ?")
        params.append(f"%{args.branch}%")
    if getattr(args, "main_only", False):
        where.append("m.sidechain = 0")
    if getattr(args, "since", None):
        where.append("m.ts >= ?")
        params.append(parse_when(args.since))
    if getattr(args, "until", None):
        where.append("m.ts <= ?")
        params.append(parse_when(args.until))
    return where, params


SEARCH_SQL = """
SELECT m.id, m.ts, m.role, m.tool, m.source, m.session_id, m.sidechain, m.seq, m.text,
       s.project, s.branch, s.title,
       snippet(messages_fts, 0, '<<', '>>', ' … ', {tokens}) AS snip,
       bm25(messages_fts) AS score
FROM messages_fts
JOIN messages m ON m.id = messages_fts.rowid
LEFT JOIN sessions s ON s.source = m.source AND s.session_id = m.session_id
WHERE messages_fts MATCH ? {extra}
ORDER BY {order}
LIMIT ?
"""

SESSIONS_SQL = """
SELECT m.source, m.session_id, s.project, s.branch, s.title,
       COUNT(*) AS hits, MIN(m.ts) AS first_ts, MAX(m.ts) AS last_ts
FROM messages_fts
JOIN messages m ON m.id = messages_fts.rowid
LEFT JOIN sessions s ON s.source = m.source AND s.session_id = m.session_id
WHERE messages_fts MATCH ? {extra}
GROUP BY m.source, m.session_id
ORDER BY {order}
LIMIT ?
"""


def run_search(conn, args, scope: str | None = None, match: str | None = None):
    where, params = filters(args, scope)
    order = "m.ts DESC" if args.sort == "recent" else "score"
    sql = SEARCH_SQL.format(
        tokens=max(6, args.snippet),
        extra=("AND " + " AND ".join(where)) if where else "",
        order=order,
    )
    return conn.execute(sql, [match or build_match(args.query), *params, args.limit]).fetchall()


LADDER = (SESSION, HARNESS, ALL)


def widen(conn, args, run) -> tuple[list, str, bool]:
    """Every word, narrowest scope first; then any word, once the strict pass is dry."""
    start = scope_of(args)
    rungs = list(LADDER[LADDER.index(start):])
    if args.source:
        rungs = [rung for rung in rungs if rung != ALL] or [start]

    strict = build_match(" ".join(content_terms(args.query)))
    loose = loose_match(args.query)
    for relaxed, match in ((False, strict), (True, loose)):
        if relaxed and loose == strict:
            break
        for scope in rungs:
            rows = run(conn, args, scope, match)
            if rows:
                return rows, scope, relaxed
    return [], rungs[-1], False


def run_sessions(conn, args, scope: str | None = None, match: str | None = None):
    where, params = filters(args, scope)
    order = "last_ts DESC" if args.sort == "recent" else "hits DESC, last_ts DESC"
    sql = SESSIONS_SQL.format(
        extra=("AND " + " AND ".join(where)) if where else "",
        order=order,
    )
    return conn.execute(sql, [match or build_match(args.query), *params, args.limit]).fetchall()
