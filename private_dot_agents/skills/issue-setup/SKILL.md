---
name: issue-setup-ise
description: Create a worktree + branch for a Linear issue with `issue setup`
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, mcp__linear__get_issue
---
# /issue-setup

Create an isolated worktree and branch for a Linear issue. The devkit binary
**`issue setup`** does the work — worktree off the baseline, per-app prep files,
installs — driven by `~/.config/devkit/config.toml`. You supply the issue id, a slug,
and the apps in scope.

## Input

`$ARGUMENTS` = the Linear issue ID (e.g. `ENG-1234`) or a Linear issue URL. If empty,
ask for it before doing anything.

## 1. Derive the slug and apps

- `ISSUE` — the identifier, e.g. `ENG-1234` (strip a URL down to it). Pass it verbatim;
  the config template lowercases it.
- `SLUG` — a short kebab title **only**, e.g. `fix-bli-export`. Fetch the issue title
  with Linear `get_issue` when you need it. Leave the issue id out — the templates
  compose `<issue>-<slug>`.
- `APPS` — comma-separated devkit app ids in scope, which decide the prep files and
  installs. `devrun config apps` lists the catalog.

## 2. Run `issue setup`

```bash
issue setup --issue "ENG-1234" --slug "fix-bli-export" --apps api,lab-os
```

It prints JSON `{issue, worktree, branch}`. Read the worktree path and branch out of
that JSON — don't hardcode them.

- On **"branch already exists"**, ask whether to reuse it or pick a new slug, then
  re-run. Never force.
- On any other failure, surface the exact error and ask.

## 3. Report back

Print, for the user to copy:

- the `cd <worktree>` command (unquoted when the path allows it)
- the branch name
- `devrun up` to start the in-scope apps, then `devrun status` to see them

The user cds in and starts the new session themselves — don't cd or open an editor.
