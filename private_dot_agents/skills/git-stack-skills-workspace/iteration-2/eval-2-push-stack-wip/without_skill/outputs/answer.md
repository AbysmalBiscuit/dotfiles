# Pushing your stack and opening PRs with git-stack + gh

Short version: in its **current state, `git-stack --push` will push only `feature-a`.**
`feature-b`'s tip commit is titled `WIP: refactor helpers`, and git-stack treats a
`WIP`-prefixed commit as "not ready". That holds back `feature-b` *and* everything
stacked on top of it (`feature-c`). You need to drop the `WIP:` prefix first, and you
also need a remote configured (this repo currently has none).

---

## What git-stack actually does on push

`git-stack --push` walks your stack and pushes only the branches it marks **`(ready)`**.
A branch is held back (not ready) when:

- its tip commit summary starts with **`WIP`** (work-in-progress), or
- it contains **`fixup!` / `squash!`** commits (unsquashed fixups), or
- it sits **above** another not-ready branch in the stack (a child can't be pushed
  past a parent that's being withheld).

You can see exactly this in the read-only stack view (no changes made):

```
main (no remote) feat: add util module
⌽ feature-a (ready)   feat(user): add fetchUser
⌽ 567271d            refactor: extract helpers
⌽ feature-b           WIP: refactor helpers      <- not ready (WIP)
⌽ feature-c           feat: new feature on top   <- not ready (above feature-b)
```

Only `feature-a` carries the `(ready)` marker. So today:

| Branch     | Pushed by `git-stack --push`? | Why |
|------------|-------------------------------|-----|
| feature-a  | ✅ yes                        | ready |
| feature-b  | ❌ no                         | tip commit is `WIP: refactor helpers` |
| feature-c  | ❌ no                         | stacked on top of the held-back feature-b |

This is a safety feature, not a bug: git-stack assumes a `WIP` commit isn't meant to
be shared yet.

---

## The plan (nothing here pushes until the explicit final steps)

### Step 0 — Prerequisites (one-time)

This sandbox has **no git remote**, so push has nowhere to go. Verify / set it up:

```bash
git remote -v                      # currently empty
gh auth status                     # confirm gh is logged in
# if no remote yet, point it at your GitHub repo, e.g.:
# git remote add origin git@github.com:<you>/<repo>.git
```

Confirm `main` is the protected/base branch git-stack measures from
(it is — `git-stack --protected` prints `main`).

### Step 1 — Inspect, don't mutate

```bash
git-stack                          # render the stack + ready/not-ready markers
git-stack --push --dry-run         # show exactly what a push WOULD do
```

The dry run will confirm only `feature-a` is eligible.

### Step 2 — Make feature-b "ready" by dropping the WIP prefix

The `WIP:` title is the only thing keeping `feature-b` (and therefore `feature-c`)
back. If that commit is actually finished, just reword it to a real message:

```bash
git switch feature-b               # land on feature-b's tip commit
git-stack reword                   # rewrite 'WIP: refactor helpers' -> e.g. 'refactor: extract helpers'
```

After rewording, re-check:

```bash
git-stack                          # feature-b and feature-c should now show (ready)
```

git-stack will automatically keep `feature-c` restacked on the rewritten `feature-b`,
so the stack stays intact.

> If the work on `feature-b` genuinely isn't done, **leave the WIP in place** — then
> accept that only `feature-a` gets pushed now, and push the rest later once it's
> ready. Don't strip a WIP marker just to force a push.

### Step 3 — Push the ready branches

```bash
git-stack --push --dry-run         # final preview: all three should now be listed
git-stack --push                   # actually push (force-with-lease per branch)
```

This pushes each branch to its own remote branch of the same name. git-stack
force-pushes safely (lease-protected) because rebasing a stack rewrites history.

### Step 4 — Open stacked PRs with gh (one per branch, correct bases)

GitHub doesn't understand stacks, so each PR must point its **base** at the branch
below it, not at `main`:

```bash
# bottom of the stack targets main
gh pr create --base main      --head feature-a --fill

# each higher PR targets the branch beneath it
gh pr create --base feature-a --head feature-b --fill
gh pr create --base feature-b --head feature-c --fill
```

`--fill` seeds title/body from the commits; add `--web` or `--draft` as you like.
Reviewers then see each PR's diff scoped to just that branch's changes.

> Stacking caveat: when `feature-a` merges into `main`, update `feature-b`'s PR base
> to `main` (GitHub often retargets automatically), then sync/rebase the stack with
> `git-stack --pull` / `git-stack --push` and the rest follows.

---

## TL;DR

1. `git-stack --push` pushes only `(ready)` branches; today that's **just `feature-a`**.
2. `feature-b` is withheld because its tip is `WIP: refactor helpers`; `feature-c` is
   withheld because it's stacked above `feature-b`.
3. Add a remote, `git-stack reword` the WIP commit into a real message, confirm all
   three show `(ready)` via `git-stack --push --dry-run`, then `git-stack --push`.
4. Open one PR per branch with `gh pr create`, each based on the branch below it.
