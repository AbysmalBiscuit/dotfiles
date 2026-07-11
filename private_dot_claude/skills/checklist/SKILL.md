---
name: checklist
description: Use when a request involves 3+ distinct steps, sequential phases ("then", "after that", "finally"), a numbered or bulleted list of items, repeating an operation over several files/targets ("for each", "all of the"), or executing a plan — before taking the first action. Especially when rushed ("quickly", "just get it done") or when the steps seem obvious.
allowed-tools: TodoWrite
---

# Tracking Multi-Step Work

## Overview

Multi-step work gets a visible checklist BEFORE the first action. The task list is how the user sees progress and how you avoid silently dropping steps.

## The Rule

If the work has 3+ distinct steps, create one task per step with `TodoWrite` **before doing anything else**. It takes one task per call — `subject` (brief title) and `description` (what needs doing) as top-level strings; there is no `tasks`/`todos` array parameter, so call it once per step. Then, for every step:

1. Mark it `in_progress` with `TaskUpdate` before starting it (exactly one at a time)
2. Do the work
3. Mark it `completed` immediately after it's verified — never batch-complete at the end
4. Discovered extra work mid-task? Add it as a new task, don't just do it

**Never write the checklist out as markdown in your reply.** The task tool renders a live list pinned above the input; a list typed into chat scrolls away and can't be updated, which defeats the whole point. If `TaskCreate` appears to be unavailable, say so explicitly rather than silently substituting prose — the sole exception is a subagent context that genuinely has no task tool, where you track steps in your replies because there's nothing else.

## Rationalizations — All Wrong

| Excuse | Reality |
|--------|---------|
| "User is in a hurry, skip overhead" | Creating tasks takes seconds; a dropped step costs a whole round-trip. Hurry is a reason FOR the list. |
| "The steps are obvious" | Obvious to you now ≠ tracked when step 4 uncovers a surprise. |
| "I'll track it mentally" | The user can't see your mental list. Visibility is the point. |
| "It's mostly one thing with sub-parts" | Sub-parts ARE steps. 3+ = list. |
| "I'm almost done, no point now" | Remaining steps still get tracked. |
| "I'll just write the list in my reply" | A markdown list can't be updated and scrolls away. Call `TaskCreate` — that's what renders the pinned list. |

## When NOT to Use

Single-step or two-step trivial work, pure Q&A, conversational turns. Don't create a one-item list.
