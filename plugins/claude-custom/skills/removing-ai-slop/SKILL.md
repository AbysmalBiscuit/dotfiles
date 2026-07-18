---
name: removing-ai-slop
description: Use when editing prose that reads as AI- or ChatGPT-generated, polishing LLM-drafted text before publishing, or when writing has inflated significance, buzzwords (delve, pivotal, tapestry, underscore, vibrant), promotional tone, formulaic "challenges/nevertheless" structure, em-dash or boldface overuse, curly quotes, or someone asks to "make this sound human" / "remove the AI slop".
---

# Removing AI Slop

## Overview

AI slop is **regression to the mean**: specific facts get smoothed into generic, inflated, relentlessly positive generality. "Inventor of the first train-coupling device" becomes "a revolutionary titan of industry" — louder and emptier at once.

So de-slopping is **not** swapping buzzwords for synonyms. Replacing "delve" with "explore" leaves the emptiness intact and only hides the tell. The job is to **restore the specific fact the slop is standing in for — or, if there is no fact underneath, cut the sentence.**

Modern models already catch the loudest tells ("stands as a testament", "more than just a building"). This skill exists for the parts that get missed: a repeatable pass so quality doesn't depend on luck, the full surface of tells (formatting and citation tells, not just prose), and three disciplines below that naive editing violates.

## When to use

- Editing or polishing any text drafted by an LLM before it ships
- Prose with inflated significance, promotional tone, or buzzword density
- "Make this sound human" / "this reads like ChatGPT" / "remove the AI slop"
- Reviewing a doc, article, report, README, or comment for AI tells

**When NOT to use:** short outbound messages (email/Slack/PR comments) → use `write`. Line-level tightening of already-clean prose → use `elements-of-style:writing-clearly-and-concisely`. Don't run this as a witch-hunt: these are *probabilistic* tells, not proof of anything, and human writers use every one of them legitimately.

## The method

1. **Read once for facts.** What does this text actually assert that's verifiable and specific? Hold that list.
2. **Pass through the tells below.** For each hit, classify it:
   - **Restore** — there's a real fact buried under the inflation → rewrite to state the fact plainly.
   - **Cut** — it's decoration with no fact underneath → delete it. Most slop is this.
3. **Never invent.** If a sentence has no fact under it and you don't have the real one, cut it — do not fabricate specifics, sources, or numbers to fill the hole. This is the cardinal rule.
4. **Re-scan your own output.** The most common failure is removing one flourish and writing a fresh one (a new sentimental closer, a new rule-of-three). Run the table over your rewrite too.
5. **Stop before it's choppy.** Don't strip so hard the prose turns robotic or loses genuinely specific content. Plain ≠ telegraphic.

## Tells reference

### Rhetoric & content
| Tell | Looks like | Fix |
|------|-----------|-----|
| Inflated significance / legacy | "marking a pivotal moment", "stands as a testament to", "part of a broader movement" | Cut, or restore the concrete fact |
| Promotional / travel-guide tone | "vibrant hub", "rich tapestry of", "nestled in the heart of", "boasts" | Cut the adjectives; state plainly |
| Superficial -ing analysis | sentence + ", underscoring its role…", ", fostering a love of…" | Cut the trailing clause |
| Vague attribution / weasel | "researchers note", "is widely regarded", "experts say" (one or zero sources) | Name the source or cut the claim |
| Overstated sourcing / notability | "featured in regional media", "maintains an active social media presence" | Cut unless it's a real, cited fact |
| Challenges/future formula | "Despite its success, X faces challenges… Nevertheless, X continues to thrive" | Delete the whole beat; keep only specifics |
| Sentimental closer | "…that resonates across generations", "a love that endures" | Cut; don't replace with another one |

### Language & grammar
| Tell | Looks like | Fix |
|------|-----------|-----|
| AI vocabulary | delve, pivotal, crucial, vibrant, tapestry, testament, underscore, showcase, foster, enhance, intricate, landscape, realm, navigate, garner, leverage, robust | Restore the plain word **and** check a real fact is being said |
| Copula avoidance | "serves as a", "stands as", "functions as" | → **is / are** |
| Marketing verbs | "features", "offers", "boasts" (meaning *has*) | → **has** |
| Negative parallelism | "not just X, but Y", "not X, but Y", "X rather than Y", "more than just" | Drop the frame; say Y directly |
| Rule of three | "adjective, adjective, and adjective"; three parallel phrases | Keep what's true; cut padding to one |
| Elegant variation | same thing renamed every mention to avoid repeating a word | Repeat the plain word |
| Hedge + intensifier stacks | "very", "perhaps", "tends to", "it's worth noting" | Cut |

### Structure & formatting
| Tell | Fix |
|------|-----|
| Title Case Headings | Sentence case |
| Boldface on every key phrase / "key takeaways" emphasis | Remove emphasis; let prose carry it |
| Inline-header vertical lists (`**Term:** description` for everything) | Convert to prose or a real list only where structure helps |
| Em-dash overuse for punched-up asides | Comma, parenthesis, colon, or split the sentence |
| Curly quotes/apostrophes `" " ' '` | Straight `" '` (unless the house style is curly) |
| Emoji decorating headings/bullets | Remove |
| "In conclusion" / restating the opening as a closer | Cut the summary |

### Citation & markup tells (LLM-generated source artifacts)
Delete or fix on sight — these are near-certain machine residue: `:contentReference[oaicite:N]`, `turn0search0`, `utm_source=chatgpt.com` / `openai` / `copilot.com`, `referrer=grok.com`, `【N†…】`, `[cite: N]`, placeholder fields (`INSERT_URL`, `2025-xx-xx`), and book/journal citations with no page number or a DOI/ISBN you can't verify. Don't trust a citation just because it's formatted correctly — LLMs fabricate plausible ones.

## Common mistakes

- **Synonym-swapping.** Trading "delve" for "explore" hides the tell without fixing the empty sentence. Restore the fact or cut.
- **Fabricating to fill the gap.** Inventing a collection size or a source to replace deleted decoration. Cut instead.
- **Reintroducing slop.** Writing a fresh sentimental closer or rule-of-three after deleting the old one. Re-scan your rewrite.
- **Over-correcting.** Stripping legitimate specifics or making prose choppy. These tells aren't crimes; keep real content.
- **Treating tells as proof.** A lone em-dash or curly quote means nothing. Density across categories is the signal — and even then it's about the writing, not an accusation.

## Red flags — stop

- You're reaching for a thesaurus instead of asking "what fact is this hiding?"
- You typed a specific number, name, or source that wasn't in the original or a checked reference.
- Your rewrite has its own grand closing sentence.
- You deleted a sentence that actually contained a concrete, verifiable fact.
