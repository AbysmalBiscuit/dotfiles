# Fixing the earliest commit in your stack with `git-stack`

## What your stack looks like

```
main                                      feat: add util module        (protected base)
 └─ feature-a   feat(user): add fetchUser   ← the commit you need to fix
     └─ (567271d) refactor: extract helpers
         └─ feature-b  WIP: refactor helpers
             └─ feature-c  feat: new feature on top
```

The bad rename lives in `user.rs` on the **`feature-a`** commit (`feat(user): add fetchUser`).
The two commits stacked on top (`feature-b`, `feature-c`) just carry `user.rs` forward unchanged, so they reference `fetchUser` only because they inherit it — none of them re-define the line. That is exactly the case where `git-stack amend` rebases cleanly.

## The key idea

`git-stack amend` melds your working-tree change into a commit **and then rebases every descendant on top of the amended version automatically** — no manual `rebase --onto`, no re-pointing branches. You do not squash a fixup yourself; one `amend` does the whole job.

Because the fix changes a line the upper commits don't touch, the restack carries `getUser` up through `feature-b` and `feature-c` without conflicts.

## Exact command plan

> Run these from the repo root. Replace `user.rs` with the real path if different.
> `--dry-run` previews without rewriting anything — use it first to confirm the plan.

### Step 0 — make sure your edit is only in the working tree, not committed yet

```bash
git-stack --format graph        # confirm the stack shape and which branch is the base
git status                      # confirm user.rs (getUser fix) shows as a working-tree change
```

If your edit is currently sitting on top of the tip (you were on `feature-c` when you fixed it), park it so you can move it down to the base commit:

```bash
git stash push -- user.rs       # set the fix aside
```

### Step 1 — land on the earliest commit (`feature-a`)

```bash
git switch feature-a
```

(Equivalently, navigate the stack: `git-stack previous --branch` until you reach `feature-a`. `git-stack previous`/`git-stack next` walk the stack.)

### Step 2 — reapply the fix here (only if you stashed it)

```bash
git stash pop                   # skip if your edit was already in the working tree on feature-a
```

Confirm `user.rs` now reads `pub fn getUser() {}`.

### Step 3 — preview, then amend the earliest commit

```bash
git add user.rs
git-stack amend --dry-run       # preview: shows feature-a rewritten + feature-b/feature-c restacked
git-stack amend                 # do it: melds the fix into feature-a, rebases descendants
```

- `amend` defaults to the current commit (`HEAD`), which is now `feature-a` — that's why Step 1 matters.
- It reuses the existing commit message by default. The descendants are rebased on top of the amended commit automatically.
- Shortcut for Steps 1–3 without switching branches: stage the fix and target the commit directly with `git-stack amend feature-a` (the `[REV]` argument). Switching first, as above, is the more predictable route.

### Step 4 — (optional) fix the commit subject too

The message still says `add fetchUser`. To match the renamed function:

```bash
git-stack reword feature-a -m "feat(user): add getUser"
```

`reword` also restacks descendants automatically.

### Step 5 — verify

```bash
git-stack --format graph
git grep -n getUser feature-a feature-b feature-c    # all three should now show getUser
git grep -n fetchUser feature-a feature-b feature-c  # should return nothing
```

## Notes / caveats

- **The `WIP` commit (`feature-b`) is fine here.** `git-stack` treats `WIP:` commits as "not ready to push," but that status does **not** stop `amend`/`reword` from rebasing it during the restack — it's carried along like any other commit. (It just won't be pushed later until you drop the `WIP` prefix.)
- **If a descendant *did* conflict** (it doesn't in this stack, since they don't touch that line), `git-stack` would pause and leave the rest of the stack intact for you to resolve, rather than silently rebasing past it.
- **Nothing is pushed** by any of the above. Publishing the corrected stack is a separate `git-stack --push` step, done only when you're ready.
- Everything except the bare `git-stack amend` / `git-stack reword` is read-only; run the `--dry-run` first if you want to see the rewrite before committing to it.
