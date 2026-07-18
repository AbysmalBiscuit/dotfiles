---
name: validate-tdd
description: "Validate that the TDD tests added for this fix/feature actually exercise the bug end-to-end and prove the fix — not ceremony unit tests that pass regardless Use when the user invokes $validate-tdd or asks for this workflow."
---

# $validate-tdd

Audit the tests added for the current feature/branch/bugfix and decide, with evidence,
whether each one **proves the fix** or is **ceremony** — a narrow unit test that passes
no matter what and therefore protects nothing.

The rubric is the **Testing** section of the applicable repository `AGENTS.md` and user
instructions. The single
most important property, and the one that can't be faked by reading the test, is:

> **A test that passes both before AND after the fix proves nothing.**
> A regression test earns its place only if it goes RED when the fix is absent and
> GREEN when it's present — and goes RED *for the right reason* (the bug, not a compile
> or setup error).

So this command doesn't just read the tests and reason about them — it **reverts the
source fix, re-runs the tests, and observes**. That's the whole point. If you skip the
revert you've validated nothing.

## Input

`<USER_INPUT>` = optional base ref/branch to diff against (e.g. `main`, `origin/main`, a
tag, a commit). If empty, auto-detect the base: the merge-base with `main` (or
`master`), falling back to comparing the working tree + staged changes if the branch
has no commits yet.

## Steps

Before step 1, invoke the `checklist` skill. Seed the plan with one item per numbered
step below; once step 3 enumerates the tests, add one item per test under audit. Keep
exactly one item `in_progress`, and mark it `completed` only once its evidence is in hand.

Stop and ask the user if anything is ambiguous. Never leave the tree in a reverted state.

### 1. Scope the change

Establish the diff and split it into **test changes** and **source (production)
changes** — you need both: the tests are what you're auditing, the source is what you'll
revert to force RED.

Resolve `BASE` first: if `<USER_INPUT>` is non-empty, use it verbatim; otherwise auto-detect.
Then diff:

```bash
# BASE = <USER_INPUT> if given, else the merge-base with main/master
BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master)
git diff --stat "$BASE"...HEAD          # committed on the branch
git status --short                       # plus anything staged/unstaged
```

- **Test paths** = added/modified files matching the project's test convention
  (`*.test.*`, `*.spec.*`, `test_*.py`, `*_test.go`, files under `tests/`, etc.).
- **Source paths** = everything else that's production code.

Snapshot the current state so you can guarantee restoration later regardless of which
revert path you take:

```bash
git stash create   # returns a commit sha capturing the dirty tree; note it, don't drop it
```

If there are **no source changes** (tests only) or **no test changes** (fix only), say so
and ask the user what they intend — there's nothing to cross-check otherwise.

### 2. Establish intent — what bug/behavior is under test?

State, in one or two sentences, the actual broken behavior this work fixes. Draw it from
commit messages, the branch name, the linked Linear/issue, and the diff itself. You need
this to judge whether a test *reproduces the real failure* versus asserting something
adjacent and safe. If you can't articulate the bug, ask the user before continuing.

### 3. Read each test against the rubric (static pass)

For every added/modified test, judge it on the criteria that don't need execution yet.
These are the tells that separate a real regression test from ceremony:

- **Entry point.** Does it drive the real entry point the bug surfaced at — the HTTP
  endpoint, the CLI invocation, the UI action, the queue handler — sending the payload
  through validation/auth/serialization the way the bug did? Or does it reach past all
  that and call the one leaf function that was changed, in isolation? A 400 on a `PATCH`
  should be tested by *sending that PATCH*, not by unit-testing the validator in a vacuum.
- **Reproduces the real failure.** Does the assertion pin the *behavior a user would
  observe* (the response, the persisted state, the emitted event)? Or only an internal
  detail of the changed line?
- **Not scoped to the one changed line.** A test that imports the exact helper that was
  edited and asserts its new return value is the classic ceremony pattern — it moves in
  lockstep with the implementation and can never catch a regression that reintroduces the
  bug through a different path.

Note your provisional read per test (`looks real` / `smells like ceremony` /
`unsure`) — step 4 is what confirms or overturns it.

### 4. Prove RED — revert the fix and re-run (the decisive step)

This is the check that can't be argued around. For the test(s) tied to a given source
change:

1. **Baseline GREEN.** Run the audited tests as-is; confirm they pass. Record the command
   and output.

2. **Revert the source fix only** (never the tests). Prefer a precise, reversible git
   operation over hand-editing:

   ```bash
   git checkout "$BASE" -- <source-paths>     # restore production code to pre-fix state
   ```

   If the fix is entangled with unrelated changes in the same file, hand-patch just the
   fix lines back to their broken form with Edit instead. Either way, keep the test files
   exactly as written.

3. **Re-run the same tests.** Observe what happens:
   - **Goes RED, asserting the bug** → the test discriminates. Confirm the failure is the
     *behavioral* assertion firing (expected X, got the old buggy Y), **not** a compile
     error, import error, or fixture blowup from the revert. A RED for the wrong reason is
     not proof.
   - **Stays GREEN** → **ceremony.** The test cannot tell the fixed code from the broken
     code. This is exactly the failure mode the user cares about. Flag it.

4. **Restore and re-confirm GREEN.**

   ```bash
   git checkout HEAD -- <source-paths>        # or reverse your hand-patch
   ```

   Re-run; confirm GREEN again. If the tree was dirty, make sure your stash snapshot from
   step 1 is intact — the working tree must end exactly as you found it. **Never finish
   with the fix reverted.**

Report both runs (RED-when-reverted, GREEN-when-restored) as the evidence for each test,
per the user's rule: *if the code is already fixed, prove RED anyway — revert, confirm
fail, restore, confirm pass, report both.*

### 5. Verdict + report

For each audited test, give a verdict backed by the step-4 evidence:

| Verdict | Meaning |
|---|---|
| **PROVES-FIX** | Goes RED (right reason) without the fix, GREEN with it, and drives the real entry point end-to-end. |
| **CEREMONY** | Stays GREEN with the fix reverted, or only exercises the changed line in isolation. Protects nothing. |
| **WEAK** | Discriminates (goes RED) but bypasses the entry point / asserts an internal detail — catches *this* regression but not a re-introduction via another path. |
| **INCONCLUSIVE** | Couldn't force a clean RED (entangled revert, flaky, setup error). Say why. |

Then output:

- A one-line summary: `N tests audited — X prove the fix, Y ceremony, Z weak`.
- Per test: the verdict, the two runs (reverted → RED/GREEN, restored → GREEN), and for
  anything not PROVES-FIX, **a concrete rewrite**: which entry point to call instead, the
  real payload to send, and the user-observable assertion to make. Don't just label it
  ceremony — show the test that would earn its place.
- If the whole change shipped without a test that reproduces the bug end-to-end, say so
  plainly. That's the headline, not a footnote.
