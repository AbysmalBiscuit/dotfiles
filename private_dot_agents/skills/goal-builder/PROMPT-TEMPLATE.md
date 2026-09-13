# `/goal` prompt template

The skeleton a filled `/goal` prompt takes. Angle brackets are slots from Phase 1. Sections stay in this order: the orchestrator reads the unattended clause and the ledger before it can act on anything else.

Keep it short. Every section here exists because a skill cannot supply it. A section that repeats what a named skill already says has no place in the file.

---

```markdown
/goal <objective in one line>

Source: <URL or absolute path>. Repo: <absolute path>.

You are the orchestrator. You dispatch implementors and hold the ledger. You write no
code yourself.

Nobody is watching this run. Skills you invoke will ask for consent, raise concerns,
or present a menu. The standing rulings below answer them. Where a skill tells you to
ask a human, rule instead, record the ruling in the ledger as `what — why — cost if
wrong`, and continue.

## Ledger

<absolute path>. Read it before every dispatch. A unit the ledger marks complete is
never re-dispatched; a unit with artifacts but no completion resumes at its first
unfinished step.

## Units

<Ordered list. Per unit: name, scope, the files it owns, its base branch, and any
resume state already on disk.>

<Serial, or the parallel groups and the disjoint file sets that make them safe.>

## Workflow

<The skills, by exact name, in the order each implementor runs them. One line each.
No description of what they do.>

## Standing rulings

<One line per gate found in Phase 2. Worktree directory. Baseline test failures.
Design approval. Branch end state. Anything else the manifest's skills stop on.>

Stop and return only for: an irreversible operation, or a decision where every path
forward is a guess. Write the block to the ledger first.

## Done

Per unit: <the command that must pass, plus the review state>.
Goal: <a statement checkable against the unit list>.
Artifacts: <local and unmerged, pushed, or PR'd — stated outright, because CLAUDE.md
forbids push and PR by default>.

## Escalation

Stuck means <observable definition>. Then: write the state to the ledger, invoke
`/fable` with <what it receives>, apply its ruling, continue. Cap: <N> per unit.

## Dispatch

Every implementor prompt carries: its unit and file ownership, its base branch, the
worktree directory, the ledger path, this unattended clause and the standing rulings,
and the return contract. Skill names alone do not travel; a subagent starts empty and
does no skill discovery.

Return contract: <branch, tip SHA, artifact paths, test result, open findings,
rulings made>.
```
