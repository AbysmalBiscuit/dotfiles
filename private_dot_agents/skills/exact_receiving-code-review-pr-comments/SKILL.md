---
name: receiving-code-review-pr-comments-rcrprc
description: use when receiving code review and you want the agent to redteam it first
disable-model-invocation: true
user-invocable: true
argument-hint: "Code review"
---

# receiving code review pr comments

1. Get PR review comments by running the following:

```bash
python3 ~/.agents/skills/receiving-code-review-pr-comments/scripts/fetch_pr_comments.py
```

2. Invoke `/superpowers:receiving-code-review` skill for code reviews posted as PR comments.

3. Redteam the code review.

Treat every finding as a claim to refute. Read the code it names and check the claim against the codebase — tests, callers, git history — until you can give a verdict:

- **Confirmed** — the code does what the reviewer says, and it is wrong for this codebase.
- **Refuted** — the code is right as-is; name the evidence.
- **Unverified** — you could not check it; name what it would take.

Done when every finding has a verdict backed by something you looked at, not by the reviewer's wording.

4. Then report one table, rows ordered by what to do first: blocking fixes, simple fixes, complex fixes, push-backs, open questions.

| # | Finding (file:line) | Verdict | Evidence | Action |

Action is one of **Fix** (one line on what changes), **Push back** (the technical reason), or **Ask** (the question for me).

Under the table, one line: which row numbers you would apply, or "none". Then stop and wait — I pick the rows to implement.
