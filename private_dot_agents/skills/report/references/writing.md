# Writing the body

## Cold reader

The reader has never opened this repo. Naming a function without showing it, or
citing a bug without its surrounding lines, sends them off to open the file,
which defeats the report. Every claim lands on the page.

- **Show the code you name.** When a sentence turns on a function, branch, or
  config value, paste those exact lines beside it, in a `<pre>` or a
  `<details class="code">` for long dumps. The `⎘` permalink points at the source;
  it does not stand in for showing it.
- **Frame before you cite.** One line first: what file, what it does, why it
  matters here. Nobody hits code cold.
- **Define on first use.** Domain terms, acronyms, env vars, table names,
  function roles. A clause is enough: "`reconcile()` (the nightly job that
  re-syncs balances)".
- **Give the starting state** before the specific point: what the system does,
  where the code lives, what the normal path looks like. Orient, then dive.
- **Trace the path.** "The handler calls `verify()`, which reads `token_store`"
  beats "the token is verified." Name every hop with its real symbol.
- **Show rather than assert.** Print the loop and point at the line instead of
  calling the retry logic wrong. The evidence carries the claim.

## Prose

Active voice, positive form, real nouns and real numbers, one tense per section,
specific headings (`Ingestion retries`, not `Details`). Cut `actually`, `simply`,
`basically`, `just`, `clearly`. Periods and commas carry the sentence; `check`
fails on an em-dash outside code.

## Gate

`report.py check` owns the mechanical half. Confirm the half it cannot see, or
go back and fix what fails:

- [ ] TL;DR compresses the whole report; a reader could stop there and be right
- [ ] Every cited function, branch, or value is shown, framed, and defined
- [ ] Every claim carries a path, number, date, or quote; no vague filler
- [ ] Each diagram earns its space: real symbol names, one idea, load-bearing
      numbers on the nodes
- [ ] Method & limitations names what was quoted or assumed, not just what was read
- [ ] Bottom line states the conclusion, recommendation, or next step
- [ ] Cold-reader test: a teammate who has never opened this repo follows it end
      to end without leaving the page
