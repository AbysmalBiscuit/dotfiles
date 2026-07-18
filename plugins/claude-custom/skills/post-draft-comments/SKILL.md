---
name: post-draft-comments
description: "Post the draft PR-review comments identified this session as a pending GitHub review, each rewritten in my voice via $write Use when the user invokes $post-draft-comments or asks for this workflow."
---

# $post-draft-comments

Take the draft review comments you identified earlier in **this session** and post them
as **inline comments on a single GitHub pending review** — so I can open the PR, read
each one in context next to the code, and keep, edit, or delete the ones that matter.

A *pending* review (not individual published comments) is the whole point: the comments
are visible only to me until I submit the review, and GitHub lets me drop any of them
inline before submitting. Never publish or submit the review yourself.

## Where the comments come from

In priority order:

1. **This session's context** — the findings you already surfaced while reviewing
   (the default; this command is meant to run in the same session as the review).
2. **A file passed in `<USER_INPUT>`** — e.g. a `findings.json`, a pr-crucible ledger, or
   a markdown list, if I point you at one.

If you can't find any draft comments in either place, **stop and say so** — don't invent
findings to fill a review.

## Each comment needs

- `path` — repo-relative file
- `line` — the line in the **new** file (the `RIGHT` side of the diff); add `start_line`
  for a multi-line range
- `body` — the comment text, **after** the rewrite step below

A comment whose line isn't part of the PR diff will be rejected by the API. Collect those
separately and report them at the end rather than dropping them silently.

## Steps

Invoke the **`checklist` skill** first and track these. Stop and ask me if any step is
ambiguous — never publish, never submit, never force anything.

### 1. Resolve the PR

- Target PR = `<USER_INPUT>` if it's a number/URL, else infer from the current branch:
  `gh pr view --json number,headRefOid,url,baseRefName`.
- Capture `owner/repo` (`gh repo view --json nameWithOwner`) and the head SHA
  (`headRefOid`) — the pending review must be pinned to that commit.
- If no PR exists for the branch, stop and tell me.

### 2. Gather the draft comments

- Pull them from session context (or the `<USER_INPUT>` file).
- For each, confirm `path` + `line` map to a line in the PR diff. Use
  `gh pr diff <pr>` to verify. Park any that don't map onto an out-of-diff list.

### 3. Learn my voice

Infer my writing style from **how I write in this conversation** — my chat messages,
phrasing, punctuation, and the corrections I've made. That's the source of truth.

Do **not** sample my PR review comments from GitHub to learn voice: most of those were
LLM-written and would teach you the wrong register.

Target what you can see directly from me: short, often lowercase starts, direct asks, no
preamble, no "Great work!", no hedging, no AI slop.

### 4. Rewrite each comment with $write

For **every** draft comment, invoke the **`write` skill** to produce the final `body`:

- BLUF — lead with the point (the bug, the ask, the risk), not a windup.
- Match the voice from step 3. Terse. No AI slop, no "It looks like", no "Consider
  perhaps", no bullet-point essays for a one-line nit.
- Keep it a *review comment*: what's wrong / what to change, and why if it isn't obvious.
- Preserve any concrete detail (line refs, values, function names) from the original draft.

Do **not** post the raw draft text. Every comment passes through `$write`.

### 5. Show me the batch before posting

List the final comments — `path:line` + rewritten body — and the out-of-diff parkees.
This is the gate. Wait for my go-ahead. If I edit any wording, take it.

### 6. Post the comments

First check whether I already have a **pending** review on this PR:

```bash
gh api "repos/<owner>/<repo>/pulls/<n>/reviews" \
  --jq '.[] | select(.state=="PENDING" and .user.login=="<me>") | .node_id'
```

**If a pending review exists**, append the new comments to it — don't start a second
review. Add each as a thread on its line via GraphQL, using the existing review's id:

```bash
gh api graphql -f query='
  mutation($reviewId:ID!, $path:String!, $line:Int!, $body:String!) {
    addPullRequestReviewThread(input:{
      pullRequestReviewId:$reviewId, path:$path, line:$line, side:RIGHT, body:$body
    }) { thread { id } }
  }' -f reviewId="<node_id>" -f path="src/foo.ts" -F line=42 -f body="..."
```

(Add `startLine` to the input for a multi-line range.)

**If no pending review exists**, create one with the whole batch — **omit the `event`
field** so GitHub leaves it PENDING (a draft) rather than publishing/submitting:

```bash
cat > /tmp/review-payload.json <<'JSON'
{
  "commit_id": "<headRefOid>",
  "comments": [
    { "path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "..." },
    { "path": "src/bar.ts", "start_line": 10, "line": 14, "side": "RIGHT", "body": "..." }
  ]
}
JSON

gh api "repos/<owner>/<repo>/pulls/<n>/reviews" --method POST --input /tmp/review-payload.json
```

- If a comment is rejected for an unmatched line, drop that one, retry, and report it in
  the out-of-diff list — don't fail the whole batch.

### 7. Report

Give me:

- The PR URL and a note that the review is **pending** (draft, not submitted).
- Count posted vs. count parked (out-of-diff), with the parked ones listed so I can
  place them manually.
- A one-line reminder: open the PR's *Files changed* tab to review the pending comments,
  then keep/delete each and submit when ready.

## Guardrails

- **Never** add an `event` (`APPROVE` / `REQUEST_CHANGES` / `COMMENT`) — that submits the
  review. This command only ever *drafts*.
- **Never** invent comments to pad the review.
- **Never** force-push, amend, or touch the branch.
- One pending review per PR. If one already exists, append to it (step 6) — never open a
  second pending review.
