---
name: tw
description: Use when the user invokes /tw or asks to manage tasks, todos, or reminders via Taskwarrior — adding, listing, completing, modifying, annotating, or reporting on tasks from the `task` CLI.
---

# Taskwarrior Interface

Translate the user's request into `task` CLI commands (Taskwarrior 3.x) and run them with Bash. Show the relevant command output back to the user.

## Workflow

1. Parse the request (after `/tw`) into filter + command + mods.
2. If no arguments given, run `task next` and show the result.
3. For destructive ops (`delete`, `purge`), confirm with the user first, then run with `rc.confirmation=off`.
4. For bulk modifications (3+ tasks), show which tasks match (`task <filter> list`) before applying.

Non-interactive tips: prepend `rc.confirmation=off` to skip y/n prompts; use `task <filter> export` for JSON when you need to inspect tasks programmatically.

## Writing task text

**REQUIRED SUB-SKILL:** When summarizing content into a task description or annotation (e.g. "add a task to follow up on this thread", "annotate with what we decided"), invoke the `write` skill first and apply its BLUF/anti-slop rules. Descriptions must be short, action-first, and self-contained — a reader with no context should know what to do.

## Quick reference

| Intent | Command |
|--------|---------|
| Add task | `task add <desc> project:X +tag due:friday priority:H` |
| Log already-done | `task log <desc>` |
| Most urgent | `task next` |
| Actionable now | `task ready` |
| List / details | `task <filter> list` · `task <id> information` |
| Complete | `task <id> done` |
| Modify | `task <id> modify due:tomorrow project:Y` |
| Append/prepend text | `task <id> append <text>` · `task <id> prepend <text>` |
| Annotate | `task <id> annotate <note>` (remove: `denotate <pattern>`) |
| Start/stop timer | `task <id> start` · `task <id> stop` |
| Delete | `task <id> delete` (permanent: `purge` — data loss) |
| Undo last change | `task undo` |
| Wait/hide until | `task <id> modify wait:monday` |
| Recurring | `task add <desc> due:sunday recur:weekly` (optional `until:`) |
| Overdue / waiting / blocked | `task overdue` · `task waiting` · `task blocked` |
| Projects / tags summary | `task projects` · `task tags` · `task summary` |
| Burndown | `task burndown.weekly` |
| Count | `task <filter> count` |
| Export JSON | `task <filter> export` |

## Filters

Combine with implicit `and`; `or`/`xor` need parentheses (quote them).

```
task 1,2-5 ...                       # IDs and ranges
task project:Home due.before:eom ... # attribute filters
task +work -waiting ...              # tags
task /regex/ list                    # description regex
task '(project:A or project:B)' list
```

Attribute modifiers: `.before` `.after` `.over` `.under` `.is` `.not` `.contains` `.has` — e.g. `due.before:tomorrow`, `description.contains:review`.

## Dates & priority

- Dates: `today`, `tomorrow`, `friday`, `eow`, `eom`, `eoy`, `2026-06-15`, `due:now+3d`
- Recurrence: `daily`, `weekly`, `monthly`, `3days`, ...
- Priority: `priority:H|M|L` (clear with `priority:`)
- Dependencies: `task <id> modify depends:4,7`

## Common mistakes

- Running `delete`/`done` on a filter that matches more tasks than intended — list first when the filter isn't a literal ID.
- Forgetting `rc.confirmation=off` in scripts → command hangs on a y/n prompt.
- Using `purge` when `delete` was meant — `purge` permanently erases; `delete` is reversible with `undo`.
- Quoting: descriptions with special chars need quotes; `or` filters need the whole expression quoted.
