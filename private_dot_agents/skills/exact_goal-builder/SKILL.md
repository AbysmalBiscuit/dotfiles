---
name: goal-builder
description: Build a /goal prompt that drives an unattended multi-agent run.
disable-model-invocation: true
user-invocable: true
argument-hint: "<objective, an issue URL, or a spec path>"
---

# goal-builder

Turns a rough objective into a `/goal` prompt: the top-level instruction set for an orchestrator that runs a multi-agent build with nobody watching.

The skills the prompt names already carry the workflow. `superpowers:writing-plans` carries the plan format. `superpowers:subagent-driven-development` carries dispatch, review, the ledger and its round caps. Restating any of that duplicates a source of truth that will move without you. Build only the layer the skills cannot know: the objective, the units, the paths, and a standing answer for every point where a skill stops and asks a human.

**A `/goal` prompt fails by stalling, not by being wrong.** Every superpowers skill has gates written for a human at the keyboard: consent before a worktree, concerns raised before execution, a menu presented at the finish. Unanswered, the run parks with a half-built branch on disk. Closing those gates is the highest-value work here.

## Phase 1: fill the slots

Read the environment for what the environment knows. Batch what only the human can answer into one question at the end of the phase.

| Slot | Fill it by | Filled when |
|---|---|---|
| Objective and source | `gh issue view N --repo O/R --json title,body`, or read the spec path | The source text is in context and its URL or absolute path is recorded |
| Units | Take the decomposition the source already carries: issue sections, spec headings. Record per unit its scope, the files it touches, and what it depends on | Every requirement in the source lands in exactly one unit, or in an `excluded` list with a reason |
| Order and ownership | Compare file sets pairwise | Units with overlapping file sets are serial. Default serial; parallel needs disjoint file sets |
| Base branch | `git -C <repo> branch -vv --all` and `git -C <repo> worktree list` | Unit 1 names a branch that exists. Later units name the previous unit's tip. Work already on disk is a resume point |
| Workspace paths | Ask, or follow the repo's existing convention | Worktree directory, ledger path, and any shared build directory are absolute |
| Skill manifest | `ls ~/.agents/skills/<name>` and the plugin skills directory under `~/.claude/plugins/cache` | Every skill name resolves, and each one produces what its step asks for |
| Done bounds | The repo's test command, plus the human's call on the end state | Per unit: a command that passes. For the goal: a statement checkable against the unit list. For artifacts: local, pushed, or PR'd, stated outright |
| Escalation | Set the definition and the caps | "Stuck" has an observable definition, `/fable` is the target, rounds are capped, and one condition ends the run and reports back |
| Return contract | Decide what each implementor hands back | Branch, tip SHA, artifact paths, test result, open findings, rulings made |

Two slots earn extra scrutiny.

**Skill manifest.** A misnamed skill fails silently into improvisation, because a dispatched subagent does no skill discovery. `superpowers:executing-plans` is the full name; `/executing-plans` is not a name. Check the pairing too: `writing-plans` writes plans from a spec, so a step that asks it for a spec runs the wrong recipe faithfully.

**Base branch.** A previous attempt leaves branches and worktrees behind. Read them before writing unit 1's base, and write the resume point into the ledger section so the run continues instead of restarting.

Phase 1 ends when every slot has a value and none of them reads as something the agent will work out later.

## Phase 2: rule on the gates

For each skill in the manifest, find where it stops:

```bash
rg -n "ask|wait|consent|approv|present.*option|STOP|human partner|HARD-GATE" <path to SKILL.md>
```

Write a standing answer for each hit. A ruling states the answer and the cost if it is wrong, so the orchestrator can weigh it rather than re-open it.

Prefer a skill that has no gate over a ruling that closes one. `superpowers:subagent-driven-development` already carries "Rulings, not stalls" and a ledger; `superpowers:executing-plans` stops on blockers and hands off to `finishing-a-development-branch`, whose menu waits for an answer. Choosing the first removes gates instead of answering them.

Phase 2 ends when every hit has a standing answer or is named as one of the run's stop conditions.

## Phase 3: write the prompt

Follow [`PROMPT-TEMPLATE.md`](PROMPT-TEMPLATE.md). Write it to `<repo>/docs/superpowers/goal-<slug>.md`.

Then prune. Every subagent inherits CLAUDE.md and the skill listing, so a line that restates commit format, path conventions, or tool preferences pays load for nothing. One CLAUDE.md rule needs an override rather than a restatement: nested dispatch is forbidden by default, and the orchestrator's whole job is dispatching.

Phase 3 ends when the file exists and no line of it restates CLAUDE.md or a manifest skill's own steps.

## Phase 4: hand it over

Show the human the units in order, the rulings, and the goal's done bound. Those three carry the decisions worth objecting to. Then give them the path and ask whether to run it here or in a fresh session.
