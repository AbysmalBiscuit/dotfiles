# Commands

`brief` names the command to run for a given question, and `ask` answers most of them on
its own. This file is the fallback: the filters, the other commands, and the query syntax
they take.

Every line below is `~/.agents/skills/history/hist.py` plus the arguments shown.

| Need | Arguments |
|---|---|
| A plain question answered in one call | `ask "how did we handle X"` |
| Ranked snippets, nothing else | `search "X"` |
| Only what the user typed | `search "X" --role user` |
| A command that was run | `search "X" --role tool` |
| Recent first, not best-match | `search "X" --sort recent` |
| One repo only | `search "X" --project lab-os` |
| Last week | `search "X" --since 7d` |
| Skip subagent transcripts | `search "X" --main-only` |
| Which sessions covered X | `sessions "X"` |
| Replay a session | `show <session-id>` |
| Read around a hit | `show --around <message-id>` |
| Coverage and index size | `stats` |
| Projects the indexer leaves alone | `exclude` |
| Stop indexing a project, and drop what it already holds | `exclude add <path> --yes` |
| Index that project again | `exclude rm <path>` |
| Drop rows for everything currently excluded | `exclude purge --yes` |
| Delete one conversation for good | `forget --session <id> --yes` |
| Delete every conversation under a directory | `forget --project <path> --yes` |

`-a` and `-am` widen the scope on any of these, filters combine, and `<command> --help`
lists the rest.

## Leaving projects out

Two things keep a project out of the index, and either is enough.

A **rule** is a project directory in the list beside the database, at
`~/.cache/history/exclude`, one per line. A rule covers that directory and everything
beneath it, so `/home/u/work` also excludes `/home/u/work/client-a` while leaving
`/home/u/workshop` alone.

A **marker file** excludes the project it sits in, and every project below it. Either
`.history_exclude` or `.history_exclude.local` counts, and the content is ignored, so
`touch .history_exclude` at the top of a repository is the whole setup. Use the `.local`
variant for a personal exclusion in a shared repository, and gitignore it. A marker never
reaches the rule list, travels with the directory it guards, and survives losing the cache
the rule list lives in. Prefer one for anything that must stay out.

```bash
touch ~/work/client-a/.history_exclude          # this repo and anything under it
~/.agents/skills/history/hist.py exclude     # rules and markers currently in force
```

A transcript whose working directory is excluded is never read.

`exclude add`, `exclude purge`, and `forget` preview by default and change nothing
without `--yes`.

Exclusion is reversible. Lifting a rule with `exclude rm`, or deleting a marker file,
re-indexes those transcripts on the next query. `forget` is not reversible: the session
is recorded permanently and stays out even after `index --rebuild`. Neither touches the
transcript files themselves, which the harnesses own.

Adding a rule by hand, or dropping in a marker, only stops future indexing; anything
already stored stays searchable. `exclude` flags what is in that state and
`exclude purge --yes` clears it.

## Query syntax

`search` and `sessions` AND their bare words, unlike `ask`, which strips question filler
and falls back to any-word matching. `"quoted runs"` match as a phrase, a trailing `*` is
a prefix match, and uppercase `OR` / `NOT` / `NEAR` pass through to SQLite FTS5.

```bash
~/.agents/skills/history/hist.py search '"advisory lock" OR "pg_try_advisory"'
~/.agents/skills/history/hist.py search 'kysely NOT migration'
```
