---
name: commit-push-reply-cpr
description: use when wrapping up working on code reviews
disable-model-invocation: true
user-invocable: true
argument-hint: "Code review"
---
1. Commit using conventional commits. One commit per logical feature.

2. Push

3. Reply to code review if it came from PR comments. When replying, if inline comments were addressed, the replies should be posted as direct replies to the inline comments. When posting replies, never use `#NUMBER`, unless you mean to cross-link other PRs/GitHub issues.

