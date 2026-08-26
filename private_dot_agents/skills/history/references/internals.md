# Internals

## Layout

Stdlib-only Python, no dependencies. `history/` holds the SQLite schema (`db.py`), the
incremental indexer (`indexer.py`), query building (`search.py`), and the CLI (`cli.py`).
`history/sources/` holds one parser per transcript format.

```bash
cd ~/.agents/skills/history && python3 -m unittest discover -s tests -t .
```

## Adding a transcript format

Write a module under `history/sources/` exposing `NAME`, `LABEL`, `discover()` returning
transcript paths, and `parse_line(obj, state, seq)` returning `Message` objects. Register
it in `sources/__init__.py`. Then reindex, because stored text changes with the parser:

```bash
~/.agents/skills/history/hist.py index --rebuild
```

A rebuild discards everything and re-reads every transcript, taking a couple of minutes.
Routine indexing never needs it.

## What the index holds

User turns, assistant turns, compaction summaries, tool calls with their arguments, and
tool results capped at a couple of kilobytes each. A typed slash command is stored as the
user wrote it, so `/unslop tighten this` is searchable as that text. Attachments, hook
output, and file snapshots are skipped as noise. Reasoning text is absent because neither
CLI writes it to disk, which leaves `--role thinking` always empty.

Every query refreshes the index first, reading only the bytes appended since the last run,
so results are current. That costs milliseconds. The exception is a machine where it has
never run: the first call builds the whole index and takes a couple of minutes.

## Storage

The database lives at `~/.cache/history/index.db`. `HISTORY_DB`, `HISTORY_CLAUDE_DIR`, and
`HISTORY_CODEX_DIR` override the paths, which is how the tests run against fixtures.

Messages sit in a plain table with an FTS5 index kept in sync by triggers. Each indexed
file records the byte offset consumed so far, so a later run resumes from there. A file
that shrank is re-read from the start, and a half-written trailing line waits for the
writer to finish it.

Several agents can query and index at once. SQLite runs in WAL mode with a busy timeout,
and a reader that meets a busy writer waits, then falls back to the already-indexed data.

## Scope detection

`HISTORY_HARNESS` (`cc` or `cx`) and `HISTORY_SESSION` set what the `-a` / `-am` ladder
resolves against, which is how the tests drive it. Without them, Claude Code is recognised
by `CLAUDECODE` and reports its session in `CLAUDE_CODE_SESSION_ID`. Codex exports no
marker that is reliably present, so it is recognised by `CODEX_SANDBOX` or `CODEX_HOME`
and exposes no session id, leaving `-a` as its narrowest scope. `stats` prints what
detection resolved to.

## Damaged transcripts

`index` reports the count of lines it could not parse. A handful of corrupt lines exist in
Claude Code's own output, from interleaved writes. They are counted rather than hidden, and
skipping one costs a single message.
