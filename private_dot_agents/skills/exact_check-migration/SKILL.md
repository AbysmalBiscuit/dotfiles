---
name: check-migration-cm
description: check kysely migration status
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__linear__get_issue, mcp__linear__get_user, mcp__linear__list_comments, mcp__linear__save_comment
---
check this linear issue:
$ARGUMENTS

tell me if anything still needs to be done for it, or if everything is finished.
