---
description: Set up an isolated worktree to work on a Linear issue (worktree + env + bun install + session summary)
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, mcp__linear__get_issue, mcp__linear__get_user, mcp__linear__list_comments, mcp__linear__save_comment, mcp__plugin_sentry_sentry__search_issues, mcp__plugin_sentry_sentry__find_projects, mcp__plugin_sentry_sentry__execute_sentry_tool, mcp__plugin_sentry_sentry__get_sentry_resource
---

# /setup-issue

Bootstrap a fresh, isolated workspace for a Linear issue: create a git worktree,
wire up env vars, install deps, and write a session-summary file that a *new*
Claude session can pick up cold.

The user will **cd into the worktree and start a new session themselves** — so the
summary file is the handoff. Make it self-sufficient.

## Input

`$ARGUMENTS` = the Linear issue ID (e.g. `ENG-1234`) or a Linear issue URL.

If `$ARGUMENTS` is empty, ask the user for the issue ID/URL before doing anything.

## Steps

The steps are numbered for reference, **not** to force a strictly serial run — fan out
independent work concurrently (see "Parallel execution" below). Stop and ask the user
if any step fails or is ambiguous.

Before step 1, invoke the **`checklist` skill** and create one task per numbered step
below (fetch issue → find/assign Sentry issue → derive names → create worktree →
symlink env → install deps → write summary → report back). Mark
each `in_progress` before starting it and `completed` once done, so progress stays
visible throughout.

### Parallel execution

Only step 1 is a hard prerequisite for the rest; almost everything downstream is
independent. Run independent work concurrently rather than one step at a time —
batch the tool calls in a single message wherever a wave allows.

- **Wave A** — step 1 (fetch the Linear issue) alone. Everything else needs its
  content, so do this first.
- **Wave B** (after step 1, all concurrent) —
  - step 2: find/assign the Sentry issue (search → assign → Linear comment),
  - step 3: derive names (pure computation).
- **Wave C** (after step 3 produces `BRANCH`/`WORKTREE`) — step 4: create the
  worktree. This can run while the Sentry work from Wave B is still in flight.
- **Wave D** (after the worktree exists, concurrent) — step 5 (symlink env) and
  step 6 (`bun install`).
- **Wave E** — step 8 (write the summary) once the Sentry result and names are
  known; then step 9 (report back). Ports are not allocated at setup — devkit
  assigns them when the next session runs `devrun up` (step 7).

Long-running or independent calls (the Sentry search/assign, `bun install`, the Linear
comment) need not block each other — kick them off and collect results as they land.

### 1. Fetch the Linear issue

- Parse the issue ID from `$ARGUMENTS` (strip a URL down to the `ABC-123` identifier).
- Use the Linear MCP `get_issue` tool to fetch: title, description, state, assignee,
  labels, URL, and any linked resources/attachments.
- Scan the description + comments for a **Notion link** (any `notion.so` / `notion.site`
  URL). If found, fetch it with the Notion MCP (`notion-fetch`) to enrich the summary.
  If no Notion link, skip silently.

### 2. Find and assign a related Sentry issue

Check whether this Linear issue corresponds to a tracked Sentry issue, and if so,
take ownership of it and wire it into the paper trail.

- Search Sentry for a matching issue with `mcp__plugin_sentry_sentry__search_issues`,
  using signal from the Linear issue: the error message / exception text, an affected
  module or function name, or the in-scope app. Narrow to the right project first via
  `mcp__plugin_sentry_sentry__find_projects` if the search is noisy.
- **Judge relevance strictly.** Only proceed if a Sentry issue clearly matches the bug
  (same error message, stack frame, or affected component). If nothing clearly matches,
  skip silently — do not assign a loosely-related issue.
- If **exactly one** clearly-relevant issue is found:
  - Assign it to the user in Sentry (resolve the user's Sentry account; assign via
    `mcp__plugin_sentry_sentry__execute_sentry_tool`, updating the issue's assignee).
  - Link it back to Linear: add a comment on the Linear issue
    (`mcp__linear__save_comment`) containing the Sentry issue URL and short ID.
  - Record the Sentry issue URL + short ID for the summary (step 8) so the eventual
    GitHub PR can reference it.
- If **multiple** plausible candidates exist, list them with their URLs and ask the
  user which (if any) to claim before assigning anything.

### 3. Derive names

- `ISSUE_ID` = the canonical identifier, e.g. `ENG-1234`.
- `SLUG` = `ISSUE_ID` lowercased + short kebab title, e.g. `eng-1234-fix-bli-export`.
- `BRANCH` = `lev/SLUG` (per global git convention).
- `WORKTREE` = `/home/lev/Git/adaptyv/SLUG` (sibling of the monorepo, **not** inside it).

### 4. Create the worktree

From `/home/lev/Git/adaptyv/monorepo`:

```bash
git -C /home/lev/Git/adaptyv/monorepo fetch origin
git -C /home/lev/Git/adaptyv/monorepo worktree add -b "$BRANCH" "$WORKTREE" origin/staging
```

Branch off `origin/staging` (the default branch). If `$BRANCH` already exists, ask
the user whether to reuse it or pick a new name.

No per-worktree devkit config is needed: write-lock enforcement is on globally via
`[harness] enforce_writes = true` in `~/.config/devkit/config.toml`, so concurrent
agents and parallel subagents in this worktree are coordinated automatically.

### 5. Symlink env vars

The shared env file lives at `/home/lev/Git/adaptyv/.env.local`. Symlink it into the
app(s) the issue touches. If unclear which app, infer from the issue text; if still
unclear, ask. Pattern:

```bash
ln -s /home/lev/Git/adaptyv/.env.local "$WORKTREE/apps/<app>/.env"
```

Do this for each relevant app (e.g. `apps/api`, `apps/lab-os`).

> Dev servers run through `devrun` (step 7), which injects doppler `dev_local`
> secrets, the pinned JWT secret, and lab-os's dummy `WORKCELL_BLI_RUN_WORKFLOW_ID`
> from `~/.config/devkit/config.toml`. The symlink mainly serves tools/scripts that
> read `apps/<app>/.env` directly. Only when running a server *directly* (skip-doppler
> fallback) does lab-os need the dummy `WORKCELL_BLI_RUN_WORKFLOW_ID` in
> `apps/lab-os/.env.local` to avoid SSR errors on boot.

### 6. Install deps

Run `bun install` in the relevant app dir(s) inside the worktree:

```bash
cd "$WORKTREE/apps/<app>" && bun install
```

Only the apps in scope. Note: `bun install` in any workspace dir installs the **whole**
monorepo workspace (root + every app) in one shot — so a single `bun install` covers all
in-scope apps. Running it per-app is redundant but harmless.

### 7. Ports — handled by devkit (no allocation at setup)

**Do not assign ports here.** devkit owns port allocation: when the next session
runs `devrun up` in the worktree, it reserves a collision-free port per app from
the registry (bases and the app catalog live in `~/.config/devkit/config.toml`),
wraps each launch in doppler `dev_local`, and wires the API's URL into consumer
apps (lab-os, foundry-portal) via the config's `url_env` — so the old slot math
and the cross-app API-URL caveat are both obsolete.

Nothing runs at setup time. The summary (step 8) just tells the next session how to
start servers and read back the assigned ports. To inspect what's already in use
across worktrees at any point: `portm status`.

### 8. Write the session summary

Write to `/home/lev/Git/adaptyv/ISSUE_SUMMARY_${ISSUE_ID}.md` (parent dir, **outside**
both monorepo and worktree). This is the cold-start handoff for the next session.

Include:

```md
# {ISSUE_ID}: {title}

- **Linear:** {issue URL}
- **Notion:** {notion URL, or "none"}
- **Sentry:** {sentry issue URL + short ID, or "none"}
- **Worktree:** {WORKTREE}
- **Branch:** {BRANCH}
- **Apps in scope:** {list}
- **State / assignee:** {state} / {assignee}

> If a Sentry issue is linked above, the GitHub PR for this work **must** reference it
> — put the Sentry issue URL in the PR description (e.g. a `Fixes: {sentry URL}` line)
> so the error, the Linear issue, and the PR are all cross-linked.

## Running servers

Start dev servers with **devrun** — it allocates a collision-free port per app
from the registry, wraps each launch in doppler `dev_local`, pins the JWT secret,
and wires the API URL into lab-os/foundry-portal automatically. Pass no ports and
no doppler flags by hand:

```bash
devrun up                 # start every in-scope app for this worktree
devrun up api             # one app   (apps in scope: {list})
devrun status             # the ports devrun assigned + pids
devrun logs api           # tail output
devrun down               # stop this worktree's servers
```

Read the assigned ports/URLs back from `devrun status` after `up` — they are not
fixed numbers. `portm status` shows allocations across all worktrees.

> **Skip-doppler fallback** (no devrun, drop doppler from the loop): with the env
> symlinked, run the framework server directly, e.g.
> `cd apps/api && bun nitro dev` or `cd apps/lab-os && bun next dev`. In that mode
> lab-os needs a dummy `WORKCELL_BLI_RUN_WORKFLOW_ID` in `apps/lab-os/.env.local`.

## Summary

{2-4 sentence plain-language summary of what the issue asks for}

## Relevant info

{key details from the Linear description + Notion: acceptance criteria, constraints,
linked PRs, affected files/modules, gotchas. Bullet points.}

## Suggested first steps

{ordered list of concrete starting actions for the new session}

## Definition of done

The fix is not complete until it ships with **unit and/or integration tests that
reproduce the bug and fail without the fix** — they guard against this class of
regression recurring. Add the tests in the same PR as the code change. Prefer the
smallest test that exercises the broken path: a unit test on the faulty function,
or an integration test when the bug spans modules / IO / multiple apps. If the bug
genuinely can't be covered by an automated test, say so explicitly and explain why.

## Before committing (TS apps)

CI runs `oxlint --deny-warnings && oxfmt --check`. Before committing TS changes,
run oxfmt + oxlint on the modified files from the monorepo root:

    oxfmt --write <changed files>
    oxlint --fix <changed files>
```

### 9. Report back

Print, for the user to copy:

- the `cd "$WORKTREE"` command
- the summary file path
- branch name
- how to start servers: `devrun up`, then `devrun status` for the assigned ports

Do **not** cd or open an editor — the user starts the new session themselves.

## Notes

- Dev servers run through `devrun` (step 7), which uses doppler `dev_local` from
  the devkit config. Never run against the prod (`prd`) doppler config.
- Write-lock enforcement is on globally (`[harness] enforce_writes = true` in
  `~/.config/devkit/config.toml`) — concurrent agents and parallel subagents in the
  same worktree are blocked from clobbering each other's structured edits. This
  relies on the `devkit` plugin being enabled and `lockm` on `PATH`.
- If git, bun, or an MCP call fails, surface the exact error and ask — don't guess.
