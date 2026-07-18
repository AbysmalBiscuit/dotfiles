---
name: issue-setup
description: "Set up an isolated worktree to work on a Linear issue (worktree + install + session summary) Use when the user invokes $issue-setup or asks for this workflow."
---

# $issue-setup

Bootstrap a fresh, isolated workspace for a Linear issue. The mechanical work —
creating the worktree off the baseline, writing per-app prep files, running each
app's install/setup, and reserving ports — is done by **`issue setup`** (the devkit
binary), driven entirely by `~/.config/devkit/config.toml`. Your job is the parts the
binary can't: enriching from Linear/Notion/Sentry and writing a self-sufficient
cold-start handoff.

The user will **cd into the worktree and start a new session themselves** — so the
summary file is the handoff. Make it self-sufficient.

## Input

`<USER_INPUT>` = the Linear issue ID (e.g. `ENG-1234`) or a Linear issue URL.

If `<USER_INPUT>` is empty, ask the user for the issue ID/URL before doing anything.

## Steps

The steps are numbered for reference, **not** to force a strictly serial run — fan out
independent work concurrently (see "Parallel execution" below). Stop and ask the user
if any step fails or is ambiguous.

Before step 1, invoke the **`checklist` skill** and create one task per numbered step
below (fetch issue → find/assign Sentry issue → derive slug + apps → `issue setup` →
write summary → report back). Mark each `in_progress` before starting it and `completed`
once done, so progress stays visible throughout.

### Parallel execution

Only step 1 is a hard prerequisite for the rest. Run independent work concurrently
rather than one step at a time — batch the tool calls in a single message wherever a
wave allows.

- **Wave A** — step 1 (fetch the Linear issue) alone. Everything else needs its content.
- **Wave B** (after step 1, concurrent) —
  - step 2: find/assign the Sentry issue (search → assign → Linear comment),
  - step 3: derive the slug + in-scope apps (pure computation).
- **Wave C** (after step 3) — step 4: `issue setup`. This can run while the Sentry work
  from Wave B is still in flight.
- **Wave D** (after the worktree exists and the Sentry result + names are known) —
  step 5 (write the summary), then step 6 (report back).

### 1. Fetch the Linear issue

- Parse the issue ID from `<USER_INPUT>` (strip a URL down to the `ABC-123` identifier).
- Use the Linear MCP `get_issue` tool to fetch: title, description, state, assignee,
  labels, URL, and any linked resources/attachments.
- Scan the description + comments for a **Notion link** (any `notion.so` / `notion.site`
  URL). If found, fetch it with the Notion MCP (`notion-fetch`) to enrich the summary.
  If no Notion link, skip silently.

### 2. Find and assign a related Sentry issue

Check whether this Linear issue corresponds to a tracked Sentry issue, and if so,
take ownership of it and wire it into the paper trail.

- Search Sentry for a matching issue with the configured Sentry integration,
  using signal from the Linear issue: the error message / exception text, an affected
  module or function name, or the in-scope app. Narrow to the right project first via
  narrowing by project first if the search is noisy.
- **Judge relevance strictly.** Only proceed if a Sentry issue clearly matches the bug
  (same error message, stack frame, or affected component). If nothing clearly matches,
  skip silently — do not assign a loosely-related issue.
- If **exactly one** clearly-relevant issue is found:
  - Assign it to the user in Sentry (resolve the user's Sentry account; assign via
    the configured Sentry integration, updating the issue's assignee).
  - Link it back to Linear: add a comment on the Linear issue
    through the configured Linear integration containing the Sentry issue URL and short ID.
  - Record the Sentry issue URL + short ID for the summary (step 5) so the eventual
    GitHub PR can reference it.
- If **multiple** plausible candidates exist, list them with their URLs and ask the
  user which (if any) to claim before assigning anything.

### 3. Derive the slug and in-scope apps

`issue setup` composes the branch and worktree names from the config templates
(`branch = {{ prefix }}{{ issue | lower }}-{{ slug }}`,
`worktree_dir = {{ issue | lower }}-{{ slug }}`), so you supply only the raw parts:

- `ISSUE` = the canonical identifier, e.g. `ENG-1234`. Pass it verbatim — the template
  lowercases it.
- `SLUG` = a short kebab title **only**, e.g. `fix-bli-export`. Do **not** prepend the
  issue id; the templates already compose `<issue>-<slug>`.
- `APPS` = the comma-separated devkit app ids in scope for this issue. These are the apps
  that get prep files, `setup`$installs, and reserved ports. Inspect the catalog with
  `devrun config apps` if you're unsure which ids exist.

### 4. Create the worktree with `issue setup`

```bash
issue setup --issue "ENG-1234" --slug "fix-bli-export" --apps api,lab-os
```

This single command: fetches `origin`, creates the worktree at
`<worktree_root>/<issue>-<slug>` on a new `lev/<issue>-<slug>` branch off the configured
baseline (`origin/staging`), writes each app's `prep_files`, runs each app's `setup`
commands (e.g. `bun install` / `uv sync`), reserves a collision-free port per app, and
prints JSON `{issue, worktree, branch, ports}`. Read the worktree path, branch, and ports
out of that JSON for the summary — don't hardcode them.

- Preview first with `--dry-run`: it prints the would-be branch/worktree/ports without
  creating anything or reserving ports.
- If it bails with **"branch already exists"**, ask the user whether to reuse it or pick a
  new slug, then re-run. Never force.
- Nothing project-specific is hardcoded here — worktree root, baseline ref, installs, prep
  files, and port bases all come from `~/.config/devkit/config.toml`.

### 5. Write the session summary

Write to `~/Git/adaptyv/ISSUE_SUMMARY_${ISSUE_ID}.md` (the worktree's parent dir,
**outside** both monorepo and worktree — the same dir `issue end` later cleans). This is
the cold-start handoff for the next session.

Include:

```md
# {ISSUE_ID}: {title}

- **Linear:** {issue URL}
- **Notion:** {notion URL, or "none"}
- **Sentry:** {sentry issue URL + short ID, or "none"}
- **Worktree:** {worktree from `issue setup` JSON}
- **Branch:** {branch from `issue setup` JSON}
- **Apps in scope:** {APPS}
- **State / assignee:** {state} / {assignee}

> If a Sentry issue is linked above, the GitHub PR for this work **must** reference it
> — put the Sentry issue URL in the PR description (e.g. a `Fixes: {sentry URL}` line)
> so the error, the Linear issue, and the PR are all cross-linked.

## Running servers

`issue setup` already reserved a port per in-scope app (listed above). Start the
servers with **devrun** — it launches each app on its reserved port, wraps each launch
in doppler `dev_local`, pins the JWT secret, and wires the API URL into
lab-os/foundry-portal automatically. Pass no ports and no doppler flags by hand:

```bash
devrun up                 # start every in-scope app for this worktree
devrun up api             # one app   (apps in scope: {APPS})
devrun status             # the assigned ports + pids
devrun logs api           # tail output
devrun down               # stop this worktree's servers
```

Read live ports/URLs back from `devrun status`. `portm status` shows allocations across
all worktrees.

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
```bash
oxfmt --write <changed_files>
oxlint --fix <changed_files>
```
```

### 6. Report back

Print, for the user to copy:

- the `cd <worktree>` command (worktree from the `issue setup` JSON. If the path doesn't need to be quoted, remove the quotes.)
- the summary file path
- the branch name
- how to start servers: `devrun up`, then `devrun status` for the assigned ports

Do **not** cd or open an editor — the user starts the new session themselves.

## Notes

- Dev servers run through `devrun`, which uses doppler `dev_local` from the devkit
  config. Never run against the prod (`prd`) doppler config — devkit rejects it.
- Write-lock enforcement is on globally (`[harness] enforce_writes = true` in
  `~/.config/devkit/config.toml`) — concurrent agents and parallel subagents in the
  same worktree are blocked from clobbering each other's structured edits. This
  relies on the `devkit` plugin being enabled and `lockm` on `PATH`.
- If `issue setup`, git, or an MCP call fails, surface the exact error and ask — don't
  guess.
