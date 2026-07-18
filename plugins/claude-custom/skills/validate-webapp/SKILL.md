---
name: validate-webapp
description: "Start dev services for the current issue worktree, then validate the bug or fix with browser automation. Use when the user invokes $validate-webapp or asks for this workflow."
---

# $validate-webapp

Start the dev services this issue/worktree needs via **devrun**, then drive the
running app with the available browser-automation skill to confirm the bug is fixed or the feature works.

Run from **inside the issue worktree** (e.g. `/home/lev/Git/adaptyv/eng-1234-...`).
devrun keys everything off the current worktree, so `cd` into it first (or pass
`-C <worktree>` to every devrun call).

## Input

`<USER_INPUT>` = optional: what to validate (e.g. "the BLI export button no longer 500s")
and/or which apps to start (e.g. `api lab-os`). If empty, derive both from the
issue context (step 1) and let devrun auto-detect the apps from the diff (step 2).

## Steps

### 1. Identify the issue + what to validate

- Detect the worktree and issue:

```bash
pwd && git rev-parse --abbrev-ref HEAD && git rev-parse --show-toplevel
```

- Extract `ISSUE_ID` from the branch name (`abc-123` pattern, uppercase it).
- Read `/home/lev/Git/adaptyv/ISSUE_SUMMARY_${ISSUE_ID}.md` if it exists — it has the
  apps in scope and the issue summary.
- Determine **what behavior to validate**: from `<USER_INPUT>` if given, else from the
  summary file + `git log`/`git diff origin/staging...HEAD --stat` (what did this
  branch change?). If still unclear, ask the user before starting anything.

### 2. Resolve apps in scope

Decide which app names to hand to devrun:

- From `<USER_INPUT>` (e.g. `api lab-os`), or the summary's "Apps in scope".
- Otherwise, **let devrun auto-detect** — `devrun up` with no app args infers the
  apps from the diff vs `origin/staging`.

You don't need to know ports, launch commands, or the API-URL wiring — devrun reads
all of that from the devkit config. To preview what it will run without starting
anything:

```bash
devrun up --dry-run [apps...]   # prints resolved [role] app :port, cwd, argv, env, log
```

`devrun up --help` lists the flags; an `unknown app` error means the name isn't in
the devkit catalog (check the dry-run output for valid names).

### 3. Start the services

First check whether servers for this worktree are already up — devrun tracks them,
and re-running `up` reuses the ports already reserved for the worktree:

```bash
devrun status            # tracked servers for THIS worktree (PORT/APP/ROLE/PID/LISTENING)
```

If nothing relevant is running, bring the apps up:

```bash
devrun up [apps...]      # omit apps to auto-detect from the diff
```

devrun handles what the steps used to do by hand:

- allocates a collision-free port per app (slot-based per worktree),
- wraps each launch in `doppler run -c dev_local` (local Supabase stack — never prd),
- wires the API base URL into every consumer app (so a non-default API port is no
  longer a false-negative trap),
- pulls in the dependent provider (e.g. `api`) automatically when a webapp needs it,
- **blocks until each app is ready** (~120s), printing a `[role] app :port` line with
  the readiness verdict.

If an app fails to become ready, devrun prints the tail of its log. Inspect it and
**stop** — don't validate against a half-up stack:

```bash
devrun logs <app>        # add -f to follow
```

### 4. Resolve the URLs to validate

Read the resolved ports from the `up` output or `devrun status` — the webapp URL is
`http://localhost:<PORT>` for the app's row. Navigate directly to the route the
issue concerns when known.

### 5. Validate with browser automation

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

### 6. Report

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
- devrun wraps every launch in `doppler run -c dev_local` automatically (local stack,
  never prd) — don't invoke `doppler` yourself.
- Prefer the `agent-browser` skill when available. If no browser automation is available,
  say so and stop; do not fake validation with curl alone.
