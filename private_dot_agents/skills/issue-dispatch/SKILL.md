---
name: issue-dispatch-idp
description: "Set up a worktree per issue and start an interactive coding agent (Claude Code by default, or Codex etc.) in each, told to work its issue."
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash
argument-hint: "<110 98 ENG-1234 ...> [with codex] [extra instructions for every session]"
---

# /issue-dispatch

Fan a list of issues out to live agent sessions, one per worktree, each in its Herdr workspace. The sessions stay open for the user to steer afterwards; this skill only launches them.

## 1. Parse the request

From `$ARGUMENTS` take:

- **Refs**: GitHub numbers (`110`, `#110`), GitHub issue URLs, Linear ids (`ENG-1234`) or Linear URLs. If none parse, ask for the list.
- **Kind**: an agent the text names ("with codex", "use codex"); omit it for the default, `claude`.
- **Extra**: the remaining free text, verbatim.

## 2. Run the script

From the repo the issues belong to:

```bash
python3 ~/.agents/skills/issue-dispatch/scripts/issue_dispatch.py [--kind KIND] [--extra "EXTRA"] REF...
```

It handles setup, slugs, the Herdr pane, fallbacks and prompting for every issue in one run. Wait for it to finish; the last line is `ID-RESULT: <STATUS>`.

| `ID-RESULT` | Meaning |
|---|---|
| `OK` | Every agent is working on its issue. |
| `PARTIAL` | Some are; the rest are `blocked` or `failed`. |
| `FAILED` | None are. |
| `BAD-KIND` | The kind is not installed. Show the printed choices, ask which to use, and re-run. |

Each row before it is tab-separated: ref, branch, agent name, status, detail.

## 3. Report

Show the rows as a table. For each non-working row, name what the user has to do:

- `blocked`: the agent waits at a startup prompt (usually a trust prompt) and never got its task. The user answers the prompt in that pane, then sends the task.
- `failed`: quote the detail. A failure after setup (branch shown) leaves the worktree in place, so a re-run of that ref fails at setup; start the agent there by hand instead.
