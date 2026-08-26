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

`-a` and `-am` widen the scope on any of these, filters combine, and `<command> --help`
lists the rest.

## Query syntax

`search` and `sessions` AND their bare words, unlike `ask`, which strips question filler
and falls back to any-word matching. `"quoted runs"` match as a phrase, a trailing `*` is
a prefix match, and uppercase `OR` / `NOT` / `NEAR` pass through to SQLite FTS5.

```bash
~/.agents/skills/history/hist.py search '"advisory lock" OR "pg_try_advisory"'
~/.agents/skills/history/hist.py search 'kysely NOT migration'
```
