"""SQLite storage: message rows plus an FTS5 index kept in sync by triggers."""

import os
import sqlite3
from pathlib import Path

SCHEMA_VERSION = 1

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);

CREATE TABLE IF NOT EXISTS files(
  id            INTEGER PRIMARY KEY,
  path          TEXT UNIQUE NOT NULL,
  source        TEXT NOT NULL,
  session_id    TEXT,
  bytes_indexed INTEGER NOT NULL DEFAULT 0,
  mtime         REAL,
  size          INTEGER
);

CREATE TABLE IF NOT EXISTS sessions(
  session_id TEXT NOT NULL,
  source     TEXT NOT NULL,
  path       TEXT,
  project    TEXT,
  branch     TEXT,
  title      TEXT,
  started    TEXT,
  ended      TEXT,
  PRIMARY KEY (source, session_id)
);

CREATE TABLE IF NOT EXISTS messages(
  id         INTEGER PRIMARY KEY,
  file_id    INTEGER NOT NULL,
  session_id TEXT,
  source     TEXT NOT NULL,
  ts         TEXT,
  role       TEXT NOT NULL,
  tool       TEXT,
  sidechain  INTEGER NOT NULL DEFAULT 0,
  seq        INTEGER NOT NULL,
  text       TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS messages_by_file    ON messages(file_id);
CREATE INDEX IF NOT EXISTS messages_by_session ON messages(source, session_id, seq, id);
CREATE INDEX IF NOT EXISTS messages_by_ts      ON messages(ts);

CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts
  USING fts5(text, content='messages', content_rowid='id', tokenize='porter unicode61');

CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
  INSERT INTO messages_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, text) VALUES('delete', old.id, old.text);
END;
"""


def default_path() -> Path:
    env = os.environ.get("HISTORY_DB")
    if env:
        return Path(env).expanduser()
    cache = os.environ.get("XDG_CACHE_HOME")
    base = Path(cache).expanduser() if cache else Path.home() / ".cache"
    return base / "history" / "index.db"


def connect(path: Path | None = None, *, write: bool = True) -> sqlite3.Connection:
    path = Path(path) if path else default_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    # Parallel agents share one index; wait for a concurrent writer instead of failing.
    conn.execute("PRAGMA busy_timeout=15000")
    if write:
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.executescript(SCHEMA)
        conn.execute(
            "INSERT OR REPLACE INTO meta(key, value) VALUES('schema_version', ?)",
            (str(SCHEMA_VERSION),),
        )
        conn.commit()
    return conn
