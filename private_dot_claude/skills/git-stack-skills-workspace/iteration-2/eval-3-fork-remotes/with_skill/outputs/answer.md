# Fork workflow: pull from `upstream`, push to `origin`

git-stack separates the two remotes for exactly this case:

- `stack.pull-remote` — where shared protected branches (e.g. `main`) come from. git-stack rebases onto these but never rewrites them. Point this at `upstream`.
- `stack.push-remote` — where your feature branches go. git-stack assumes it owns these and force-pushes (with lease). Point this at `origin` (your fork).

## 1. Configure the remotes

```console
$ git config --add stack.pull-remote upstream     # pull shared/protected branches from upstream
$ git config --add stack.push-remote origin        # push your feature branches to your fork
```

Verify it took effect (look for the `pull-remote` / `push-remote` lines):

```console
$ git-stack --dump-config -
```

(One-time prerequisite: make sure both Git remotes actually exist — `git remote -v` should list `upstream` = the main repo and `origin` = your fork.)

## 2. Sync, then push your ready branch

```console
$ git-stack sync                 # pulls main from upstream, rebases your stack onto it,
                                 #   fetches origin to prune merged/deleted branches
$ git-stack --push -n            # dry-run: confirm WHICH branch(es) would push to origin
$ git-stack --push               # force-push (with lease) ready branch(es) to origin, sets upstream
```

`git-stack --push` only pushes branches it considers **ready**:

1. the branch sits directly on the protected base (it isn't stacked on another dev branch), and
2. it has no WIP commits (summary `WIP` or starting with `WIP:` / `draft:` / `Draft:` / `wip ` / `WIP `).

Branches with `fixup!` commits still count as ready. If your branch isn't pushing, run `git-stack --push -n` plus `git-stack --show-commits all` to spot a WIP marker or a branch that's stacked higher.

## 3. Open the PR (only if/when you want one)

The PR's base is the protected branch; the head is your branch on the fork:

```console
$ gh pr create --base main --head <your-branch> --title "feat(x): summary" --body "..."
```

For a branch stacked on another, set its base to the branch below it instead of `main`:

```console
$ gh pr create --base <lower-branch> --head <your-branch> --title "..." --body "..."
```

## Notes

- These `git config --add` commands write to the local repo config (`$REPO/.git/config`), so the fork setup applies only to this clone.
- `git config` (the unset variant) or editing `.git/config` reverts it; re-run `git-stack --dump-config -` to confirm.
- To adopt this for a whole team, move the config into a committed `$REPO/.gitconfig` instead.
