---
name: commit
description: Use when needing to commit uncommitted changes.
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet
---

Commit uncommitted changes using conventional commits.
Each commit should be done atomically: stage and commit in one single operation.
There are other agents/sessions running in the same checkout, so you need to do things atomically to avoid collisions.

Don't do weird `git stash` stashing and `git pop` things. There may be other agents working in the same repo.

One logical change per commit. If the subject needs "and", consider splitting.

Before committing:
- Stage selectively: don't sweep unrelated edits, generated files, or secrets into the commit. Stage hunks whenever it makes sense.
- Review `git diff --staged` and describe what the diff *actually* does, not what you intended.
