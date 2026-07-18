---
name: issue-setup-batch
description: "Set up worktrees for multiple Linear issues at once. Bugs get Sentry, Vercel, and PostHog reconnaissance; other issues get plain setup. Use when the user invokes $issue-setup-batch or provides multiple issue IDs or Linear URLs to bootstrap."
---

# Issue setup batch

Set up several Linear issues while serializing git/worktree mutations. This workflow
explicitly authorizes Codex sub-agents for read-only classification and reconnaissance.

## Input

`<USER_INPUT>` accepts Linear issue IDs and URLs separated by spaces, commas, or
newlines. `--dry-run` previews worktrees and ports without creating or mutating anything.

## Steps

### 1. Parse and classify

- Extract IDs matching `[A-Za-z]+-\d+` and `linear.app` URLs.
- Ignore surrounding punctuation and Markdown syntax; deduplicate by issue ID.
- If no issue parses, ask the user for the issue list.
- Fetch each issue and its comments through the configured Linear integration.
- Classify as a bug when labels or content show a defect, regression, exception,
  HTTP failure, previously working behavior that broke, or incorrect user-visible output.
- Classify feature requests, refactors, chores, documentation, and planned migrations as
  non-bugs unless evidence says otherwise.

Classification is read-only and may run concurrently in sub-agents.

### 2. Set up worktrees serially

Run setup for one issue at a time because `issue setup` performs git operations against
the shared repository:

- For bugs, invoke the `issue-setup-bug` skill with the canonical issue ID.
- For other issues, invoke the `issue-setup` skill with the canonical issue ID.
- With `--dry-run`, pass `--dry-run` to `issue setup`; skip assignments, comments,
  summary writes, and reconnaissance.
- Never force or reuse an existing branch without user approval. Mark that issue blocked.
- If several Sentry candidates are plausible, assign none and report their URLs.
- Continue with remaining independent issues after a blocked or failed issue.

### 3. Report

Return:

- A table with issue ID, title, classification, setup status, and reconnaissance sources.
- For every successful issue: worktree path, branch, summary path, and a copyable
  `cd <worktree>` command.
- For bugs: the leading hypothesis and confidence, or a plain statement that no source
  contained relevant evidence.
- For blocked/failed issues: the exact error or ambiguity and the decision needed.
- A reminder to run `devrun up` and `devrun status` inside each worktree, then invoke
  `issue-start` there.

Do not invent missing results or silently omit an issue.
