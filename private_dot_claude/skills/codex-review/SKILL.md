---
name: codex-review
description: Use after superpowers:writing-plans — or whenever a written implementation plan or spec exists and no code has been written yet — to gate the plan with a cross-model adversarial review BEFORE superpowers:executing-plans or superpowers:subagent-driven-development. Claude is the builder; OpenAI Codex is a read-only critic that stress-tests the plan (VERDICT:APPROVED/REVISE) over bounded rounds until it converges, and the human signs off before any code. Especially for non-trivial or high-stakes work — auth, schema, concurrency, migrations, payments. Also triggers on "/codex-review", "codex review my plan", "have Codex review my plan", "argue/stress-test this plan with Codex", "adversarial plan review", "second-model sanity check on the plan". Requires the codex MCP server connected. For a requirements interview BEFORE the review use /grill-me-codex; NOT for reviewing already-written CODE, NOT for trivial changes.
---

# Codex-Review — Adversarial Plan-Review Loop

Two models, one plan, a bounded argument. **Claude is the builder and orchestrator. Codex is a read-only critic** that can read the repo and the plan but cannot touch a single file. They communicate through `PLAN.md` + a Codex MCP conversation that persists across rounds. The human enters at exactly two points: kickoff and final sign-off.

This is a **deliberate, high-stakes tool** — reach for it on auth, data models, concurrency, migrations, payments, anything expensive to get wrong. Skip it for obvious/cheap work.

## Prerequisites (verify once, fast)

- **Codex MCP server connected** — the `mcp__codex__codex` and `mcp__codex__codex-reply` tools must be available. If they aren't, tell the user to connect it: `claude mcp add codex -- codex mcp-server` (then reload). Do not fall back silently.
- Codex authenticated: a prior `codex login` (ChatGPT account is fine). If a call returns an auth/model error, surface it to the user — do not silently retry.
- **Echo the active model + effort before Round 1** so the user can confirm: state the resolved `MODEL`/`EFFORT` (see tunables) with the other values. If the user objects, stop before burning a round.
- **Read-only is enforced and inherited.** Passing `sandbox: "read-only"` on the round-1 `codex` call blocks all writes, and every `codex-reply` on that thread inherits it automatically — no re-assertion needed (verified: a reply's write attempt still hits `Read-only file system`). Codex cannot write a file at any point in this loop.

## Tunable variables (read from skill args, else default)

| Var | Default | Meaning |
|-----|---------|---------|
| `MAX_ROUNDS` | `5` | Hard cap on review rounds. The loop ALWAYS terminates at this. |
| `PLAN_FILE` | `PLAN.md` | Where the evolving plan lives (repo root). |
| `LOG_FILE` | `PLAN-REVIEW-LOG.md` | Append-only transcript of the argument (every round's critique + what changed). The artifact. |
| `MODEL` | `gpt-5.6-sol` | OpenAI model for the critic → the `model` tool param. Default `sol` is the strongest tier. Override with a weaker tier (e.g. `gpt-5.6-tera`) for a faster pass; set empty to omit the param and use the `~/.codex/config.toml` default. |
| `EFFORT` | `xhigh` | Reasoning effort → `config.model_reasoning_effort`. Supported: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, `ultra`. Keep adversarial review at `high` or above. |
| `FAST_MODE` | _(off)_ | Set `true` to add `config.fast_mode = true` (faster output). Optional; off by default for review. |

If the user invoked the skill with arguments like `rounds=3 model=gpt-5.6-sol effort=xhigh`, use those. Echo the resolved values (including the active model + effort) back before starting.

## Flow

### Step 0 — Kickoff (human gate #1)

The invocation itself is the kickoff. Confirm scope in one line: what is being planned. If the user gave no task, ask for it (one question). Then proceed — do NOT ask for approval round-by-round; that comes at the end.

### Step 1 — Claude plans

Do real planning: read the relevant code, think through the approach, surface decisions and tradeoffs. Then write the plan to `PLAN_FILE` in this structure:

```markdown
# Plan: <task>
_Round 0 — initial draft by Claude_

## Goal
<one paragraph>

## Approach
<numbered steps, concrete>

## Key decisions & tradeoffs
<the contestable choices — name them explicitly so Codex has something to bite>

## Risks / open questions
<what you're unsure about>

## Out of scope
<bounds>
```

Initialize `LOG_FILE`:
```markdown
# Plan Review Log: <task>
Started <stamp the user's local time if known, else "session start">. MAX_ROUNDS=<n>.
```

Show the user the plan inline and say you're sending it to Codex for adversarial review.

### Step 2 — The loop

Maintain `ROUND` (start 1) and `THREAD_ID` (empty until round 1 returns).

**The review prompt** sent to Codex each round (adjust the task line):

> You are an adversarial reviewer for an implementation plan. Be skeptical and specific — your job is to find what breaks, not to be agreeable. Read the plan at `PLAN.md` (and any repo files you need; you are read-only). Identify concrete flaws: security holes, race conditions, missing edge cases, schema conflicts, wrong assumptions, observability gaps, simpler alternatives. For each, give a one-line fix. Do NOT modify any files. End your reply with EXACTLY one line: `VERDICT: APPROVED` if the plan is sound enough to implement, or `VERDICT: REVISE` if it still has material problems.

**Round 1** — call the `mcp__codex__codex` tool (this creates the session):

| param | value |
|-------|-------|
| `prompt` | the review prompt above |
| `sandbox` | `"read-only"` |
| `cwd` | the repository root (where `PLAN.md` lives) |
| `approval-policy` | `"never"` |
| `model` | `MODEL` — **omit this param entirely if `MODEL` is empty** (uses config default) |
| `config` | `{ "model_reasoning_effort": "<EFFORT>" }` — add `"fast_mode": true` when `FAST_MODE` is set |

The tool returns `{ "threadId": "...", "content": "..." }`. Set `THREAD_ID = threadId`. The critique is `content` — read it directly (no file to parse). If the call errors instead of returning content (auth / model / server not connected), stop and tell the user — do not retry blind.

**Rounds 2..MAX** — call the `mcp__codex__codex-reply` tool (resumes the SAME session; Codex remembers its earlier critiques and won't re-litigate settled points):

| param | value |
|-------|-------|
| `threadId` | `THREAD_ID` |
| `prompt` | `"I revised the plan. Re-review PLAN.md. Same rules. End with VERDICT: APPROVED or VERDICT: REVISE."` |

Read-only, model, and effort are inherited from the round-1 call — `codex-reply` takes no such params and must not need them. Returns `{ threadId, content }` again.

**Each round, after Codex returns:**
1. Append to `LOG_FILE`: `## Round <n> — Codex` + the full `content` critique.
2. Read the last line of `content` for the verdict token.
   - `VERDICT: APPROVED` → break the loop, go to Step 3 (converged).
   - `VERDICT: REVISE` → Claude reads the critique, decides **what's actually worth acting on** (Claude has final say — Codex advises, it does not command). Revise `PLAN_FILE`. Append to `LOG_FILE`: `### Claude's response` + what you changed and what you rejected and why. Increment `ROUND`.
3. If `ROUND > MAX_ROUNDS` → break to Step 3 (deadlock).

### Step 3 — Resolution (human gate #2)

**If APPROVED:** Present to the user — the final `PLAN_FILE`, a 3-bullet summary of what the argument improved, and the round count. Ask: *"Plan survived N rounds of Codex. Implement it now — Codex builds it (`/codex-build`), Claude builds it, or stop here?"* Only on a yes is code written. **No code is written during the loop.** If the user picks Codex, invoke the `codex-build` skill with `SPEC_FILE=PLAN.md` and the same `LOG_FILE` — roles flip (Codex writes, Claude reviews the diff) and the build rounds append to the same log.

**If MAX_ROUNDS hit without APPROVED (deadlock):** Do NOT pretend it converged. Surface the unresolved disagreements explicitly: list each point Codex still flags and Claude's counter-position. Hand it to the human to break the tie. This is a legitimate, useful outcome — a flagged disagreement beats a false "approved."

## Hard rules

- Codex is read-only EVERY round — `sandbox: "read-only"` on the round-1 `codex` call, inherited by every `codex-reply`. It never writes. If you're tempted to give it write access, stop — that's a different skill (`/codex-build`).
- The loop ALWAYS terminates at `MAX_ROUNDS`. No unbounded recursion.
- Claude is the final arbiter on every REVISE — incorporate good critiques, reject bad ones *with a reason logged*. Don't cave to Codex on everything (that defeats the cross-model check) and don't ignore it (that defeats the point).
- Code only after human gate #2.
- `LOG_FILE` is the deliverable — it tells the whole story of the argument. Keep it complete.

## What NOT to do

- Don't use this to review existing code — that's `/codex:review`.
- Don't pin a `-codex` model variant on ChatGPT-account auth — it 400s.
- Don't skip the log — the argument transcript is the most valuable artifact.
- Don't let Codex edit files. Read-only, always.
