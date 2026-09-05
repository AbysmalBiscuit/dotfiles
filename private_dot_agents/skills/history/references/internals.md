# Internals

## Layout

Stdlib-only Python, no dependencies. `history/` holds the SQLite schema (`db.py`), the
incremental indexer (`indexer.py`), query building (`search.py`), the exclusion list
(`excludes.py`), and the CLI (`cli.py`). `history/sources/` holds one parser per
transcript format.

```bash
cd ~/.agents/skills/history && python3 -m unittest discover -s tests -t .
```

## Adding a transcript format

Write a module under `history/sources/` exposing `NAME`, `LABEL`, `discover()` returning
transcript paths, and `parse_line(obj, state, seq)` returning `Message` objects. Two more
functions let the exclusion list work without a full parse: `probe_project(path)` returns
the transcript's working directory, and `session_id_for(path)` recovers the session id
from the filename. `sources/jsonl.probe` reads the opening records for the first. Register
the module in `sources/__init__.py`. Then reindex, because stored text changes with the parser:

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

Text is stored uncompressed. The database uses a page larger than the SQLite default,
because the average message exceeds what a default page holds inline and the overflow
pages that result waste a large share of the file. `connect()` repages an existing
database on its own, which costs one slow run and then nothing. VACUUM is the only way to
repage a database that holds data, and it ignores `page_size` unless WAL is dropped for
the duration, so `repage()` does that and restores WAL afterwards. A concurrent agent
holding the database makes the attempt a no-op, and a later run retries.

Several agents can query and index at once. SQLite runs in WAL mode with a busy timeout,
and a reader that meets a busy writer waits, then falls back to the already-indexed data.

## Scope detection

`HISTORY_HARNESS` (`cc` or `cx`) and `HISTORY_SESSION` set what the `-a` / `-am` ladder
resolves against, which is how the tests drive it. Without them, Claude Code is recognised
by `CLAUDECODE` and reports its session in `CLAUDE_CODE_SESSION_ID`. Codex exports no
marker that is reliably present, so it is recognised by `CODEX_SANDBOX` or `CODEX_HOME`
and exposes no session id, leaving `-a` as its narrowest scope. `stats` prints what
detection resolved to.

## Leaving transcripts out

Two mechanisms keep a transcript out of the index, and `indexer.Skipper` applies both
before a file is opened.

Exclusion rules are project directories in `~/.cache/history/exclude`, matched as path
prefixes on a directory boundary. The file sits beside the database so one directory holds
everything the tool owns, which does mean clearing the cache takes the rules with it.
A marker file has no such problem: `.history_exclude` or `.history_exclude.local` lives in
the tree it guards, covers that directory and everything below, and is resolved fresh each
run, so deleting one takes effect immediately. Marker lookups are cached per project
rather than per transcript.
Neither mechanism is index state, so lifting either restores the transcripts it covered.

Forgotten sessions live in the `forgotten` table and are permanent. `purge` keeps the
emptied `files` rows for them, which is how a later run maps a transcript back to the
session it belongs to; a rebuild wipes those rows, so the filename is the fallback, and
both formats name a transcript after its session.

Resolving a path to its project costs a small read, so the answer is memoised in the
`skipped` table, which only holds the transcripts that have no session row to carry the
project for them. The decision itself is recomputed every run; a row no longer covered is
dropped and the transcript is indexed again. `index --rebuild` clears the memo but not the
tombstones.

Excluding a project stops future indexing but leaves whatever is already stored. That is
the state `exclude` reports and `exclude purge` clears, and it is the only path that can
delete rows for a marker file, which has no rule to hang `exclude add` off.

Deleting from `messages` is enough to keep FTS5 in step, because the delete trigger
forwards it.

## Damaged transcripts

`index` reports the count of lines it could not parse. A handful of corrupt lines exist in
Claude Code's own output, from interleaved writes. They are counted rather than hidden, and
skipping one costs a single message.
