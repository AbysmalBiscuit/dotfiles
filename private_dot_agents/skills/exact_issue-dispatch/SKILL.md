---
name: issue-dispatch-idp
description: "Set up a worktree per issue and start an interactive coding agent (Claude Code by default, or Codex etc.) in each, told to run /issue-start and then work its issue."
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash
argument-hint: "<110 98 ENG-1234 ...> [with codex] [start or task override] [extra instructions for every session]"
---

# /issue-dispatch

Fan a list of issues out to live agent sessions, one per worktree, each in its Herdr workspace. The sessions stay open for the user to steer afterwards; this skill only launches them.

## 1. Parse the request

From `$ARGUMENTS` take:

- **Refs**: GitHub numbers (`110`, `#110`), GitHub issue URLs, Linear ids (`ENG-1234`) or Linear URLs. If none parse, ask for the list.
- **Kind**: an agent the text names ("with codex", "use codex"); omit it for the default, `claude`.
- **Start**: a different orientation command the text names ("start with /issue-start-migrate"), or `none` when it says to skip orientation; omit it for the default, `/issue-start`.
- **Task**: a different job than doing the issue ("only write a plan", "just investigate"); omit it for the default, `Now do what issue {issue} says.`
- **Extra**: the remaining free text, verbatim.

`{issue}` in a start command or task expands to each issue's id. Refs that need different start commands or tasks go in separate runs, one per group.

## 2. Run the script

From the repo the issues belong to:

```bash
python3 ~/.agents/skills/issue-dispatch/scripts/issue_dispatch.py [--kind KIND] [--start "CMD"|none] [--task "TASK"] [--extra "EXTRA"] REF...
```

It handles setup, slugs, the Herdr pane, fallbacks and the prompt sequence for every issue in one run: each agent runs the start command, and once that settles it is told the task. Pass only the flags the request overrides. Wait for the script to finish; the last line is `ID-RESULT: <STATUS>`.

| `ID-RESULT` | Meaning |
|---|---|
| `OK` | Every agent is working on its issue. |
| `PARTIAL` | Some are; the rest are `blocked` or `failed`. |
| `FAILED` | None are. |
| `BAD-KIND` | The kind is not installed. Show the printed choices, ask which to use, and re-run. |

Each row before it is tab-separated: ref, branch, agent name, status, detail.

## 3. Report

Show the rows as a table. For each non-working row, name what the user has to do:

- `blocked`: the agent waits at a startup prompt (usually a trust prompt) or asked a question during the start command, and never got its task. The detail says which. The user answers in that pane, then sends the task.
- `failed`: quote the detail. A failure after setup (branch shown) leaves the worktree in place, so a re-run of that ref fails at setup; the user starts the agent there, start command first.
