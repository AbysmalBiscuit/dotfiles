---
name: fable
description: "Use when the work should go to a more senior model than this session: the user asks to escalate it, hand it off, ask fable, or get a bigger model or a second opinion on it, and when a task is subtle or high-stakes enough that reasoning budget decides the outcome."
disable-model-invocation: false
user-invocable: true
argument-hint: "[-m <target>] [-e <effort>] [-r] <what to hand off>"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Skill, Agent, mcp__codex__codex
---

# fable

Gets a task in front of a model with more reasoning budget than this session has. That model starts on an empty context window, so the work here is writing it a prompt worth its budget, then making the call.

## Start here

```bash
~/.agents/skills/fable/fable.py
```

Pass it the same flags you were given, so `/fable -r -m sol ...` means `fable.py -r -m sol`. It works out which target this harness escalates to and how the call is made from here, then prints the steps. Follow them.

Which target each harness reaches for, and how: [`targets.toml`](targets.toml). Subagent routes raise the model but not the reasoning effort, since the Agent tool has no effort parameter; command routes put both on argv.
