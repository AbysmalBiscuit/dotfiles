"""Incremental indexing: each run picks up only bytes appended since the last one."""

import json
import sys
from dataclasses import dataclass
from pathlib import Path

from .model import SessionState
from .sources import SOURCES

BATCH = 4000


@dataclass
class IndexStats:
    files_seen: int = 0
    files_changed: int = 0
    messages_added: int = 0
    errors: int = 0

    def line(self) -> str:
        return (
            f"{self.files_changed} of {self.files_seen} transcripts updated, "
            f"{self.messages_added} messages added"
            + (f", {self.errors} unparseable lines" if self.errors else "")
        )


def _load_state(conn, source: str, session_id: str | None) -> SessionState:
    state = SessionState(session_id=session_id)
    if not session_id:
        return state
    row = conn.execute(
        "SELECT project, branch, title, started, ended FROM sessions"
        " WHERE source = ? AND session_id = ?",
        (source, session_id),
    ).fetchone()
    if row:
        state.project, state.branch, state.title = row["project"], row["branch"], row["title"]
        state.started, state.ended = row["started"], row["ended"]
    return state


def _save_state(conn, source: str, path: Path, state: SessionState) -> None:
    if not state.session_id:
        return
    conn.execute(
        """
        INSERT INTO sessions(session_id, source, path, project, branch, title, started, ended)
        VALUES(?,?,?,?,?,?,?,?)
        ON CONFLICT(source, session_id) DO UPDATE SET
          path    = excluded.path,
          project = COALESCE(excluded.project, sessions.project),
          branch  = COALESCE(excluded.branch,  sessions.branch),
          title   = COALESCE(excluded.title,   sessions.title),
          started = MIN(COALESCE(sessions.started, excluded.started), COALESCE(excluded.started, sessions.started)),
          ended   = MAX(COALESCE(sessions.ended,   excluded.ended),   COALESCE(excluded.ended,   sessions.ended))
        """,
        (state.session_id, source, str(path), state.project, state.branch,
         state.title, state.started, state.ended),
    )


def index_file(conn, module, path: Path, stats: IndexStats, *, rebuild: bool) -> None:
    try:
        stat = path.stat()
    except OSError:
        return
    stats.files_seen += 1

    row = conn.execute(
        "SELECT id, bytes_indexed, session_id, mtime, size FROM files WHERE path = ?",
        (str(path),),
    ).fetchone()

    offset = 0 if rebuild or row is None else row["bytes_indexed"]
    if row is not None:
        if not rebuild and stat.st_size == row["size"] and stat.st_mtime == row["mtime"]:
            return
        if stat.st_size < offset:  # file rewritten shorter than what we consumed
            offset = 0
        if offset == 0:
            conn.execute("DELETE FROM messages WHERE file_id = ?", (row["id"],))
        file_id = row["id"]
        conn.execute("UPDATE files SET mtime = ?, size = ? WHERE id = ?",
                     (stat.st_mtime, stat.st_size, file_id))
    else:
        cur = conn.execute(
            "INSERT INTO files(path, source, bytes_indexed, mtime, size) VALUES(?,?,0,?,?)",
            (str(path), module.NAME, stat.st_mtime, stat.st_size),
        )
        file_id = cur.lastrowid

    if offset >= stat.st_size and row is not None and not rebuild:
        return

    seq = 0 if offset == 0 else conn.execute(
        "SELECT COALESCE(MAX(seq), 0) FROM messages WHERE file_id = ?", (file_id,)
    ).fetchone()[0]

    state = _load_state(conn, module.NAME, None if offset == 0 else (row and row["session_id"]))
    pending = []
    consumed = offset
    added = 0

    with path.open("rb") as fh:
        fh.seek(offset)
        for raw in fh:
            if not raw.endswith(b"\n"):
                break  # a session still being written; resume at this byte next run
            consumed += len(raw)
            seq += 1
            line = raw.decode("utf-8", "replace").strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                stats.errors += 1
                continue
            if not isinstance(obj, dict):
                continue
            for msg in module.parse_line(obj, state, seq):
                pending.append((file_id, state.session_id, module.NAME, msg.ts, msg.role,
                                msg.tool, int(msg.sidechain), msg.seq, msg.text))
            if len(pending) >= BATCH:
                added += _flush(conn, pending)

    added += _flush(conn, pending)
    conn.execute("UPDATE files SET bytes_indexed = ?, session_id = ? WHERE id = ?",
                 (consumed, state.session_id, file_id))
    _save_state(conn, module.NAME, path, state)
    stats.files_changed += 1
    stats.messages_added += added


def _flush(conn, pending: list) -> int:
    if not pending:
        return 0
    conn.executemany(
        "INSERT INTO messages(file_id, session_id, source, ts, role, tool, sidechain, seq, text)"
        " VALUES(?,?,?,?,?,?,?,?,?)",
        pending,
    )
    count = len(pending)
    pending.clear()
    return count


def refresh(conn, modules, *, rebuild: bool = False, progress: bool = False) -> IndexStats:
    stats = IndexStats()
    if rebuild:
        conn.executescript("DELETE FROM messages; DELETE FROM files; DELETE FROM sessions;")
        conn.commit()
    for module in modules:
        paths = sorted(module.discover())
        reported = 0
        for n, path in enumerate(paths, 1):
            index_file(conn, module, path, stats, rebuild=rebuild)
            if stats.files_changed - reported >= 50:
                reported = stats.files_changed
                conn.commit()
                if progress:
                    print(f"  {module.LABEL}: {n}/{len(paths)} scanned, "
                          f"{stats.messages_added} messages", file=sys.stderr)
        conn.commit()
    return stats
