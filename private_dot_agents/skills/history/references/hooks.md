# Indexing with hooks

A hook is an optimization, not a correctness fix. The index refreshes itself before every
query, so it is never stale. A hook only moves that work off the query and onto session
close, where the transcript is complete, saving a fraction of a second on the first query
after a break. Add one if you want that, or if you plan to query with `--no-refresh`.

## Claude Code

Add to `~/.claude/settings.json`. If `hooks.SessionEnd` already exists, append the command
object to that group's `hooks` array.

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.agents/skills/history/hist.py index",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

`~` expands, because hooks run through a shell. Keep `timeout` generous: a first build over
every transcript takes minutes. The indexer commits in batches, so a run killed partway
resumes cleanly on the next call.

## Codex

Codex reads a Claude-shaped hooks file, with `async` and `statusMessage` available per
command. `.codex/hooks.json` in a project root works on this machine and covers only
sessions started in that project. A user-level `~/.codex/hooks.json` alongside
`config.toml` would cover every session, but no such file exists here, so verify that path
before relying on it.

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.agents/skills/history/hist.py index",
            "async": true
          }
        ]
      }
    ]
  }
}
```

Codex asks you to trust a hook source the first time it runs. Accept the prompt, or the
hook stays silent.

## Verify

```bash
~/.agents/skills/history/hist.py --no-refresh stats
```

Run it before and after ending a session. The message count climbs when the hook fired.
