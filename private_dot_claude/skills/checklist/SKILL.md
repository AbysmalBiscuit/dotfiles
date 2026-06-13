---
name: checklist
description: Use when a request involves 3+ distinct steps, sequential phases ("then", "after that", "finally"), a numbered or bulleted list of items, repeating an operation over several files/targets ("for each", "all of the"), or executing a plan — before taking the first action. Especially when rushed ("quickly", "just get it done") or when the steps seem obvious.
---

# Tracking Multi-Step Work

## Overview

Multi-step work gets a visible checklist BEFORE the first action. The task list is how the user sees progress and how you avoid silently dropping steps.

## The Rule

If the work has 3+ distinct steps, create one task per step with TaskCreate (TodoWrite on older versions) **before doing anything else**. Then, for every step:

1. Mark it `in_progress` before starting it (exactly one at a time)
2. Do the work
3. Mark it `completed` immediately after it's verified — never batch-complete at the end
4. Discovered extra work mid-task? Add it as a new task, don't just do it

No task tool available (some subagent contexts)? Track the checklist visibly in your replies instead — state each step and check it off as you go.

## Rationalizations — All Wrong

| Excuse | Reality |
|--------|---------|
| "User is in a hurry, skip overhead" | Creating tasks takes seconds; a dropped step costs a whole round-trip. Hurry is a reason FOR the list. |
| "The steps are obvious" | Obvious to you now ≠ tracked when step 4 uncovers a surprise. |
| "I'll track it mentally" | The user can't see your mental list. Visibility is the point. |
| "It's mostly one thing with sub-parts" | Sub-parts ARE steps. 3+ = list. |
| "I'm almost done, no point now" | Remaining steps still get tracked. |

## When NOT to Use

Single-step or two-step trivial work, pure Q&A, conversational turns. Don't create a one-item list.
