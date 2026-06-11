---
description: Start dev services for the current issue worktree, then validate the bug/fix in the browser via chrome-devtools
allowed-tools: Bash, Read, Glob, Grep, mcp__chrome-devtools__new_page, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__take_snapshot, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__click, mcp__chrome-devtools__fill, mcp__chrome-devtools__fill_form, mcp__chrome-devtools__evaluate_script, mcp__chrome-devtools__list_console_messages, mcp__chrome-devtools__get_console_message, mcp__chrome-devtools__list_network_requests, mcp__chrome-devtools__get_network_request, mcp__chrome-devtools__wait_for, mcp__chrome-devtools__list_pages, mcp__chrome-devtools__select_page, mcp__chrome-devtools__close_page, mcp__chrome-devtools__press_key, mcp__chrome-devtools__hover, mcp__chrome-devtools__type_text
---

# /validate-webapp

Start the dev services this issue/worktree needs, then drive the running app with
chrome-devtools to confirm the bug is fixed / the feature works.

Run from **inside the issue worktree** (e.g. `/home/lev/Git/adaptyv/eng-1234-...`).

## Input

`$ARGUMENTS` = optional: what to validate (e.g. "the BLI export button no longer 500s")
and/or which apps to start (e.g. `api lab-os`). If empty, derive both from the
issue context (step 1).

## Steps

### 1. Identify the issue + what to validate

- Detect the worktree and issue:

```bash
pwd && git rev-parse --abbrev-ref HEAD && git rev-parse --show-toplevel
```

- Extract `ISSUE_ID` from the branch name (`abc-123` pattern, uppercase it).
- Read `/home/lev/Git/adaptyv/ISSUE_SUMMARY_${ISSUE_ID}.md` if it exists — it has the
  apps in scope, the port slot, and the issue summary.
- Determine **what behavior to validate**: from `$ARGUMENTS` if given, else from the
  summary file + `git log`/`git diff origin/staging...HEAD --stat` (what did this
  branch change?). If still unclear, ask the user before starting anything.

### 2. Resolve apps in scope

From `$ARGUMENTS`, the summary's "Apps in scope", or the diff paths (`apps/<app>/...`).
Known apps and default base ports (slot 0):

| App | Base port | Launch (from app dir) |
|-----|-----------|-----------------------|
| api | 9100 | `bun nitro dev --port <PORT>` |
| lab-os | 4100 | `bun next dev --port <PORT>` |
| foundry-portal | 4200 | `bun next dev --port <PORT>` |
| website | 4300 | `bun next dev --port <PORT>` |
| plate-api | 8080 | `PORT=<PORT> bun dev` |

Always start the api if any webapp in scope talks to it.

### 3. Resolve ports

Priority order:

1. **Assigned slot**: `**Port slot:** N` line in the issue's `ISSUE_SUMMARY` file →
   port = base + N. Use the resolved ports from its "Ports" table when present.
2. **No slot assigned**: find the first free port per app by incrementing from the
   base, +1 at a time:

```bash
# first free port >= base
port=<BASE>; while ss -ltn "sport = :$port" | grep -q LISTEN; do port=$((port+1)); done; echo "$port"
```

3. Check nothing is **already listening** on the chosen ports — if a dev server for
   this same worktree is already up (verify via `ss -ltnp` / the process's cwd),
   reuse it instead of starting a second one.

> If the API ends up on a non-default port, the webapp must be pointed at it — the
> shared `../.env.local` hard-codes the API URL at port 9100. Override the API-URL
> env var when launching the webapp (check the app's env usage, e.g.
> `NEXT_PUBLIC_API_URL=http://localhost:<API_PORT>`). Skipping this gives
> false-negative validation results.

### 4. Start the services

Start each in-scope app as a **background** Bash task from its app dir inside the
worktree, e.g.:

```bash
cd <WORKTREE>/apps/api && bun nitro dev --port <API_PORT>
cd <WORKTREE>/apps/lab-os && bun next dev --port <LABOS_PORT>
```

Then wait for readiness — poll each port until it accepts connections (timeout ~120s):

```bash
for i in $(seq 1 60); do curl -sf -o /dev/null "http://localhost:<PORT>" && break; sleep 2; done
```

If a service fails to start, surface the exact error from its output and stop —
don't validate against a half-up stack.

### 5. Validate with chrome-devtools

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
- Services started + their ports (so the user can poke at them — leave them running)
- Any regressions or suspicious console/network noise spotted along the way

If validation FAILS, do **not** attempt a fix — report exactly what was observed vs
expected and stop.

## Notes

- Leave dev servers running after validation; tell the user which background tasks
  hold them.
- Never run `doppler` unless the user asks explicitly.
- If chrome-devtools MCP is unavailable, say so and stop — don't fake validation
  with curl alone.
