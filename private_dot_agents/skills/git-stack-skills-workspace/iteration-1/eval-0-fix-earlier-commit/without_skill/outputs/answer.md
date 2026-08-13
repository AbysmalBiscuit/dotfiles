# Folding a working-tree fix into the earliest commit of your stack

Good news: this is exactly what `git-stack amend` is built for. It can meld your
already-fixed working tree into *any* commit in the stack (not just `HEAD`) and
then automatically rebases the commits stacked on top of it. From its own help:

> When you amend a commit that has descendants, those descendants are rebased on
> top of the amended version of the commit, unless doing so would result in
> merge conflicts.

So you do **not** need to do a manual interactive rebase. One targeted amend
handles the rewrite *and* restacks the two commits above it.

Your `git-stack` version here is `0.10.20`, whose subcommands are
`previous`, `next`, `reword`, `amend`, `sync`, `run`. Invoke them as
`git-stack <sub>` (or `git stack <sub>`). If you've run
`git-stack alias --register`, the short aliases `git amend / git next /
git prev / git reword / git sync` also work — I'll note those inline.

---

## Step 0 — Identify the earliest commit's SHA

The "earliest" commit is the oldest one on your branch, i.e. the first commit
above your protected base (`main`). Get its SHA:

```bash
# Visual: the stack as git-stack sees it (oldest at the bottom, above main)
git-stack --show-commits all

# Or plain git, oldest line is your target:
git log --oneline --reverse main..HEAD
```

Copy the short SHA of that oldest commit. I'll call it `<OLDEST>` below.

---

## Step 1 — Stage *only* the fix

Your working tree already has the corrected `fetchUser` -> `getUser` rename.
Stage exactly the file(s) you fixed so nothing unrelated gets swept in:

```bash
git add path/to/the/fixed/file.rs        # use the real path(s)
git status                                # sanity-check what's staged
```

(If the rename fix is genuinely the *only* change in your working tree, you can
skip `git add` and pass `--all` to the amend in the next step instead.)

---

## Step 2 — Preview the amend with a dry run (nothing is rewritten)

`-n` / `--dry-run` shows what would happen without touching history. Always do
this first:

```bash
git-stack amend --dry-run <OLDEST>
```

Read the output: it should show the fix folding into `<OLDEST>` and the two
descendant commits being replayed on top. If it instead warns about conflicts
(see "If it can't rebase cleanly" below), stop and handle that first.

---

## Step 3 — Do the amend (this is the history-rewriting step — run it yourself)

```bash
git-stack amend <OLDEST>
```

What this does:
- Melds your staged change into commit `<OLDEST>`, reusing its existing message.
- Rebases the two commits stacked above it onto the rewritten commit.
- Automatically takes a `git-branch-stash` backup snapshot first, so the prior
  state is recoverable if anything looks wrong.

Equivalent forms:
- `git amend <OLDEST>` — if you registered the aliases.
- `git-stack amend --all <OLDEST>` — stage + amend in one shot, *only* if the
  rename fix is the sole change in your working tree (skips Step 1's `git add`).

> Note: `git-stack` refuses to amend a *protected* commit (e.g. anything on
> `main`). Make sure `<OLDEST>` is your own first feature commit, not the base.

---

## Step 4 — Verify the stack is intact

```bash
git-stack --show-commits all      # confirm 3 commits, correct order, fix in the first
git log -p <OLDEST> -1            # confirm getUser is now in the earliest commit
git status                        # working tree should be clean
```

Optionally run your test/build across the whole restacked stack:

```bash
git-stack run -- <your build/test command>
```

---

## If it can't rebase cleanly (conflicts)

Because the two upper commits also touch code near the rename, the auto-rebase
*may* hit a conflict. If so, `git-stack amend` will tell you rather than leave a
mess. You then resolve it like any rebase:

```bash
# fix conflicts in the listed files, then:
git add <resolved files>
git rebase --continue
```

If you'd rather bail out entirely and return to the pre-amend state, restore the
snapshot git-stack saved:

```bash
git branch-stash pop        # restores the backup taken in Step 3
```

---

## TL;DR

```bash
git log --oneline --reverse main..HEAD     # find <OLDEST> = the earliest commit
git add path/to/fixed/file                  # stage just the rename fix
git-stack amend --dry-run <OLDEST>          # preview (no rewrite)
git-stack amend <OLDEST>                     # fold fix in + auto-restack the 2 above
git-stack --show-commits all                # verify
```

The single `git-stack amend <OLDEST>` is the whole trick: it rewrites the
earliest commit and carries the two stacked commits along for you.

*(Per your request, I have not run any of the history-rewriting commands against
your repo — this is the plan only. Steps 0, 2, and 4 are read-only/safe; Step 3
is the one that rewrites history.)*
