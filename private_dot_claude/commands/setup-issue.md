---
description: Set up an isolated worktree to work on a Linear issue (worktree + env + bun install + session summary)
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
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
- `BRANCH` = `AbysmalBiscuit-claude/SLUG` (per global git convention).
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

### 5. Install deps

Run `bun install` in the relevant app dir(s) inside the worktree:

```bash
cd "$WORKTREE/apps/<app>" && bun install
```

Only the apps in scope — not the whole monorepo unless the issue is repo-wide.

### 6. Write the session summary

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

## Summary

{2-4 sentence plain-language summary of what the issue asks for}

## Relevant info

{key details from the Linear description + Notion: acceptance criteria, constraints,
linked PRs, affected files/modules, gotchas. Bullet points.}

## Suggested first steps

{ordered list of concrete starting actions for the new session}
```

### 7. Report back

Print, for the user to copy:

- the `cd "$WORKTREE"` command
- the summary file path
- branch name

Do **not** cd or open an editor — the user starts the new session themselves.

## Notes

- Never run `doppler` unless the user asks explicitly.
- If git, bun, or an MCP call fails, surface the exact error and ask — don't guess.
