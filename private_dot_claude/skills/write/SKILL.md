---
name: write
description: Use when drafting or editing a message to a person — email, Slack, chat reply, PR/issue comment, or any short outbound prose. Applies BLUF and inverted-pyramid structure, runs an anti-AI-slop check, and defers to elements-of-style for line-level polish.
---

# Drafting Messages

Write messages a busy person can act on in one read. Structure for the reader's time, then strip anything that smells like AI filler, including em-dashes.

## 1. Lead with the bottom line (BLUF)

Put the conclusion, ask, or recommendation in the **first sentence** — before the context that justifies it (deductive, not inductive).

- Answer the 5 Ws: who, what, when, where, why.
- For a decision, state the recommended action and any second/third-order effects up front.
- Use active voice and direct statements.
- Email: tag the subject with intent in caps — `ACTION` (recipient must do something), `REQUEST` (needs approval), `INFO` (FYI only), `DECISION` (needs a call).

Bad: "Over the course of working on the project, we hit some data issues..."
Good: "Do you know who can convert our Oracle data to SQL Server? Hit a blocker on the new project."

## 2. Multi-paragraph → inverted pyramid

Most important first, then diminishing importance, trivia last.

- The reader can stop at any paragraph and still have the gist.
- Anyone could "cut from the bottom" without losing the point.
- Never bury the lead. If the key fact is in paragraph three, move it to sentence one.

## 3. Anti-AI-slop check

Cut these before sending:

- Throat-clearing openers: "I hope this finds you well", "I wanted to reach out", "Just circling back".
- LLM tells: "delve", "moreover", "furthermore", "it's worth noting", "I'd be happy to", "certainly".
- Hedging stacks: "I think it might possibly be a good idea to maybe..."
- Padding: rhetorical questions, em-dash asides that add nothing, a closing paragraph that restates the opening.
- Generic praise/empathy that any message could carry. Be concrete or cut it.

Test: read it aloud. If a sentence sounds like a corporate auto-reply, rewrite or delete it.

## 4. Polish

After structure and slop-cut, invoke `elements-of-style:writing-clearly-and-concisely` for line-level tightening (omit needless words, active voice, definite/concrete language).

## Related

- Presenting a recommendation or decision (not just a message)? Also use `staffwork`.
- The message asks someone to teach/clarify something? Shape the questions with `ask`.
