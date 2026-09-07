---
name: validate-webapp-vw
description: Start dev services for the current issue worktree, then validate the bug/fix in the browser via chrome-devtools
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__chrome-devtools__new_page, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__take_snapshot, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__click, mcp__chrome-devtools__fill, mcp__chrome-devtools__fill_form, mcp__chrome-devtools__evaluate_script, mcp__chrome-devtools__list_console_messages, mcp__chrome-devtools__get_console_message, mcp__chrome-devtools__list_network_requests, mcp__chrome-devtools__get_network_request, mcp__chrome-devtools__wait_for, mcp__chrome-devtools__list_pages, mcp__chrome-devtools__select_page, mcp__chrome-devtools__close_page, mcp__chrome-devtools__press_key, mcp__chrome-devtools__hover, mcp__chrome-devtools__type_text
---
# /validate-webapp

Start the dev services this issue/worktree needs via **devrun**, then drive the
running app with chrome-devtools to confirm the bug is fixed / the feature works.

Run from **inside the issue worktree**. devrun keys everything off the current
worktree, so `cd` into it first (or pass `-C <worktree>` to every devrun call).

## Input

`$ARGUMENTS` = optional: what to validate (e.g. "the export button no longer 500s")
and/or which apps to start. If empty, derive both from the recon output below.

## What already happened

`~/.agents/skills/validate-webapp/scripts/validate_webapp_context.py` has **already
run**, read-only. It resolved the worktree, the issue id, the session summary, the tree
state, the base branch and what this branch changed, then reported which dev servers are
already tracked and what `devrun up` would start. Its output is below. It started
nothing.

It ends with `IC-SERVERS: <STATE>` and `IC-RESULT: <STATUS>`. Do not re-run `pwd`,
`git status`, `git log`, `git diff`, `devkit config show`, or `devrun status` to
orient yourself.

---

!`python3 ~/.agents/skills/validate-webapp/scripts/validate_webapp_context.py "$ARGUMENTS" 2>&1 || true`

---

## Act on the result

| `IC-RESULT` | What to do |
|---|---|
| `READY` | Summary and diff are above. Work the steps below. |
| `NO-SUMMARY` | No handoff file. Derive what to validate from `$ARGUMENTS` and the diff above. If both are thin, ask before starting anything. |
| `NOT-ISSUE-WORKTREE` | No issue id resolved. Ask which issue this is, then re-run with it as the argument. Stop. |
| `PROTECTED` | You're on a base branch. Report it and ask which worktree they meant. Stop. |
| `ERROR` | Report the message and stop. |

`IC-SERVERS` decides whether step 2 has anything to do:

| `IC-SERVERS` | Meaning |
|---|---|
| `UP` | Servers are already running for this worktree. Skip step 2 and read the ports from the table above. |
| `PARTIAL` | Fewer servers than apps in scope. Bring up the missing ones. |
| `DOWN` | Nothing running. Step 2 in full. The dry-run block above shows what `devrun up` will start. |
| `UNKNOWN` | `devrun status` failed. Read its error above, fix the cause, and don't validate until servers are confirmed up. |

## Steps

### 1. Decide what to validate

From `$ARGUMENTS` if given, else from the summary and the diff in the recon output.
If it's still unclear what behavior should be different, ask the user before starting
anything. Never invent an acceptance criterion the issue doesn't state.

### 2. Start the services

Only when `IC-SERVERS` is `DOWN` or `PARTIAL`:

```bash
devrun up [apps...]      # omit apps to auto-detect from the diff
```

Apps come from `$ARGUMENTS`, the summary's "Apps in scope", or the record's app list in
the recon output. Omit them entirely to let devrun infer from the diff.
`devkit config apps` lists the ids the project defines.

devrun handles what the steps used to do by hand:

- allocates a collision-free port per app (slot-based per worktree),
- injects the project's dev secrets and env exactly as the devkit config declares,
  never a production config,
- wires the API base URL into every consumer app (so a non-default API port is no
  longer a false-negative trap),
- pulls in a dependent provider app automatically when a webapp needs it,
- **blocks until each app is ready** (~120s), printing a `[role] app :port` line with
  the readiness verdict.

If an app fails to become ready, devrun prints the tail of its log. Inspect it and
**stop** — don't validate against a half-up stack:

```bash
devrun logs <app>        # add -f to follow
```

### 3. Resolve the URLs to validate

Read the resolved ports from the `up` output or the recon's `== servers ==` table — the
webapp URL is `http://localhost:<PORT>` for the app's row. Navigate directly to the
route the issue concerns when known.



Read the resolved ports from the `up` output or `devrun status` — the webapp URL is
`http://localhost:<PORT>` for the app's row. Navigate directly to the route the
issue concerns when known.

### 4. Validate with chrome-devtools

- Open a new page (`new_page`) at the webapp URL (`http://localhost:<WEBAPP_PORT>/...`),
  navigating directly to the route the issue concerns when known.
- Reproduce the scenario from the issue: take a snapshot, interact (click/fill/type)
  through the flow the bug describes.
- Confirm the **fixed** behavior, and check for regressions while there:
  - UI state matches expectation (snapshot/screenshot evidence)
  - `list_console_messages` — no new errors
  - `list_network_requests` — relevant API calls succeed (no 4xx/5xx where the bug
    was a failure)
- If the expected behavior is ambiguous, validate against the acceptance criteria in
  the ISSUE_SUMMARY / Linear description.

### 5. Report

Print a verdict the user can act on:

- **PASS / FAIL** per validated behavior, with evidence (screenshot, console output,
  network status codes — not just "it works")
- Services started + their ports (from `devrun status`), so the user can poke at them
- Any regressions or suspicious console/network noise spotted along the way

If validation FAILS, do **not** attempt a fix — report exactly what was observed vs
expected and stop.

## Notes

- Leave dev servers running after validation — devrun tracks them per worktree. Stop
  them with `devrun down` (releases the ports) when the user is done.
- devrun injects the project's dev secrets itself — don't invoke the secrets tool by
  hand, and never point it at a production config.
- If chrome-devtools MCP is unavailable, say so and stop — don't fake validation
  with curl alone.
