---
name: history
description: "Use when the answer lives in an earlier session: what was decided or discussed before, which session covered something, a command run or an error hit previously, or any request to search chat history across Claude Code and Codex transcripts."
disable-model-invocation: false
user-invocable: true
argument-hint: "[-a | -am] <what to look for>"
allowed-tools: Bash(~/.agents/skills/history/hist.py:*), Read
---

# history

A full-text index over every Claude Code and Codex transcript on this machine, answering
in well under a second. Reaching for the raw transcripts instead costs minutes and floods
the context window with tool-result noise.

## Start here

```bash
~/.agents/skills/history/hist.py brief
```

`brief` reports what this harness can see and prints the command to run next. Pass it the
same flags you were given, so `/history -am ...` means `brief -am`. Run what it says, then
answer from its output, carrying the date, project, and session id so the user can reopen
the session. On a machine where nothing is indexed yet, that first call builds the index
and takes a couple of minutes. Let it finish.

Filters, other commands, and query syntax: [`references/commands.md`](references/commands.md).
Keeping projects out of the index with a rule or a `.history_exclude` file, and deleting
conversations already in it: [`references/commands.md`](references/commands.md).
What the index holds, storage, adding a parser: [`references/internals.md`](references/internals.md).
Indexing on session end instead of on query: [`references/hooks.md`](references/hooks.md).
