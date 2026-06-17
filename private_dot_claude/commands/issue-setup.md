---
description: Set up an isolated worktree to work on a Linear issue (worktree + env + bun install + session summary)
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, mcp__linear__get_issue, mcp__linear__get_user, mcp__linear__list_comments
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

Run these in order. Stop and ask the user if any step fails or is ambiguous.

Before step 1, invoke the **`checklist` skill** and create one task per numbered step
below (fetch issue → derive names → create worktree → symlink env → install deps →
allocate port slot → write summary → report back). Mark each `in_progress` before
starting it and `completed` once done, so progress stays visible throughout.

### 1. Fetch the Linear issue

- Parse the issue ID from `$ARGUMENTS` (strip a URL down to the `ABC-123` identifier).
- Use the Linear MCP `get_issue` tool to fetch: title, description, state, assignee,
  labels, URL, and any linked resources/attachments.
- Scan the description + comments for a **Notion link** (any `notion.so` / `notion.site`
  URL). If found, fetch it with the Notion MCP (`notion-fetch`) to enrich the summary.
  If no Notion link, skip silently.

### 2. Derive names

- `ISSUE_ID` = the canonical identifier, e.g. `ENG-1234`.
- `SLUG` = `ISSUE_ID` lowercased + short kebab title, e.g. `eng-1234-fix-bli-export`.
- `BRANCH` = `lev/SLUG` (per global git convention).
- `WORKTREE` = `/home/lev/Git/adaptyv/SLUG` (sibling of the monorepo, **not** inside it).

### 3. Create the worktree

From `/home/lev/Git/adaptyv/monorepo`:

```bash
git -C /home/lev/Git/adaptyv/monorepo fetch origin
git -C /home/lev/Git/adaptyv/monorepo worktree add -b "$BRANCH" "$WORKTREE" origin/staging
```

Branch off `origin/staging` (the default branch). If `$BRANCH` already exists, ask
the user whether to reuse it or pick a new name.

### 4. Symlink env vars

The shared env file lives at `/home/lev/Git/adaptyv/.env.local`. Symlink it into the
app(s) the issue touches. If unclear which app, infer from the issue text; if still
unclear, ask. Pattern:

```bash
ln -s /home/lev/Git/adaptyv/.env.local "$WORKTREE/apps/<app>/.env"
```

Do this for each relevant app (e.g. `apps/api`, `apps/lab-os`).

> Dev servers are normally launched through doppler (`dev_local`, see step 7); the
> symlink mainly serves tools/scripts that read `apps/<app>/.env` directly. If the
> issue touches **lab-os**, also add a dummy `WORKCELL_BLI_RUN_WORKFLOW_ID` to
> `apps/lab-os/.env.local` or its SSR errors on boot.

### 5. Install deps

Run `bun install` in the relevant app dir(s) inside the worktree:

```bash
cd "$WORKTREE/apps/<app>" && bun install
```

Only the apps in scope. Note: `bun install` in any workspace dir installs the **whole**
monorepo workspace (root + every app) in one shot — so a single `bun install` covers all
in-scope apps. Running it per-app is redundant but harmless.

### 6. Allocate a port slot (parallel-work safe)

Each worktree runs its dev servers on a distinct **port slot** so multiple worktrees can
run side-by-side without bind collisions. Slot 0 = the monorepo's defaults. Each issue
worktree gets the next free slot ≥ 1, and ports are `base + slot`.

Default bases (from `monorepo/CLAUDE.md`): lab-os `4100`, foundry-portal `4200`,
api `9100`, plate-api `8080`.

Pick the next free slot by scanning existing summaries for the `Port slot:` marker:

```bash
# slot 0 reserved for the monorepo; find lowest free slot >= 1
used=$(rg -oN 'Port slot:\*\* *([0-9]+)' -r '$1' /home/lev/Git/adaptyv/ISSUE_SUMMARY_*.md 2>/dev/null)
SLOT=1
while printf '%s\n' "$used" | grep -qx "$SLOT"; do SLOT=$((SLOT+1)); done
echo "Assigned port slot: $SLOT"
echo "  lab-os=$((4100+SLOT))  api=$((9100+SLOT))  plate-api=$((8080+SLOT))  foundry-portal=$((4200+SLOT))"
```

Record the chosen `SLOT` and resolved ports in the summary (step 7). The `Port slot:`
marker line **must** stay machine-readable (`**Port slot:** N`) so the next run's scan
finds it.

> **Caveat to flag:** the shared `../.env.local` hard-codes the API URL (default port
> 9100). If a worktree runs the API on a non-default port, lab-os won't reach it unless
> the API-URL env is overridden locally too. Slot ports prevent *bind* collisions;
> cross-app URL wiring is separate. Note this in the summary.

### 7. Write the session summary

Write to `/home/lev/Git/adaptyv/ISSUE_SUMMARY_${ISSUE_ID}.md` (parent dir, **outside**
both monorepo and worktree). This is the cold-start handoff for the next session.

Include:

```md
# {ISSUE_ID}: {title}

- **Linear:** {issue URL}
- **Notion:** {notion URL, or "none"}
- **Worktree:** {WORKTREE}
- **Branch:** {BRANCH}
- **Apps in scope:** {list}
- **State / assignee:** {state} / {assignee}
- **Port slot:** {SLOT}

## Ports (slot {SLOT})

Launch dev servers on these ports to avoid collisions with other worktrees:

Launch through doppler (`dev_local`) so secrets are injected (app→project mapping
is in `monorepo/doppler.yaml`):

| App | Port | Launch (doppler `dev_local`) |
|-----|------|--------|
| lab-os | {4100+SLOT} | `doppler run -p lab-os -c dev_local -- next dev -p {4100+SLOT}` |
| api | {9100+SLOT} | `SUPABASE_JWT_SECRET='super-secret-jwt-token-with-at-least-32-characters-long' doppler run -p api-foundry -c dev_local --preserve-env=SUPABASE_JWT_SECRET -- nitro dev --port {9100+SLOT}` |
| plate-api | {8080+SLOT} | see `monorepo/doppler.yaml` for the project; `PORT={8080+SLOT}` |
| foundry-portal | {4200+SLOT} | see `monorepo/doppler.yaml` for the project; `-p {4200+SLOT}` |

> Only list rows for apps in scope; drop the rest. If the API runs on a non-default
> port, override the API-URL env for lab-os too (see setup caveat).
>
> The `--preserve-env=SUPABASE_JWT_SECRET` keeps the minted-JWT secret matching the
> local Supabase container; `dev_local` already carries this value, so it's only
> strictly needed when pinning a non-default secret. **Skip-doppler fallback:**
> with the env symlinked, `cd apps/<app> && bun nitro dev` (or `bun next dev`) also
> works — simpler, but drifts from `dev_local`. **lab-os** needs a dummy
> `WORKCELL_BLI_RUN_WORKFLOW_ID` in `apps/lab-os/.env.local` or SSR errors.

## Summary

{2-4 sentence plain-language summary of what the issue asks for}

## Relevant info

{key details from the Linear description + Notion: acceptance criteria, constraints,
linked PRs, affected files/modules, gotchas. Bullet points.}

## Suggested first steps

{ordered list of concrete starting actions for the new session}

## Before committing (TS apps)

CI runs `oxlint --deny-warnings && oxfmt --check`. Before committing TS changes,
run oxfmt + oxlint on the modified files from the monorepo root:

    oxfmt --write <changed files>
    oxlint --fix <changed files>
```

### 8. Report back

Print, for the user to copy:

- the `cd "$WORKTREE"` command
- the summary file path
- branch name
- assigned port slot + resolved ports

Do **not** cd or open an editor — the user starts the new session themselves.

## Notes

- Use `doppler` with the `dev_local` config to launch dev servers (see step 7).
  Never use `doppler` with prod (`prd`) config.
- If git, bun, or an MCP call fails, surface the exact error and ask — don't guess.
