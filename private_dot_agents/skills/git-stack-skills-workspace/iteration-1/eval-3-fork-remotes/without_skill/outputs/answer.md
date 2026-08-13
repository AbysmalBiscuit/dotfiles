# Fork workflow with git-stack: pull from `upstream`, push to `origin`

git-stack has exactly two remote settings for this. They're plain `git config` keys:

- `stack.pull-remote` — the upstream remote it pulls/rebases your **protected** branches (e.g. `main`) from.
- `stack.push-remote` — the remote it pushes your **development** (feature) branches to.

By default both fall back to `origin`. For a fork you point the pull-remote at `upstream` and the push-remote at your fork `origin`.

## 1. Configure the remotes

Set them once per repo (drop `--local`, or use `--global` if you want it for every repo):

```bash
git config --local stack.pull-remote upstream
git config --local stack.push-remote origin
```

Verify:

```bash
git config --get stack.pull-remote   # -> upstream
git config --get stack.push-remote   # -> origin
```

Make sure both remotes actually exist (`upstream` = main repo, `origin` = your fork):

```bash
git remote -v
```

## 2. Sync (pulls `main` from `upstream`)

```bash
git-stack --pull
```

This fetches your protected base branch(es) from `stack.pull-remote` (`upstream`), rebases your development branches onto the updated base, and also fetches `stack.push-remote` (`origin`) to prune stale remote branches. (`git sync` is the common alias for this.)

## 3. Push your ready branch (to `origin`)

```bash
git-stack --push
```

This force-pushes (with lease) every **ready** development branch to `stack.push-remote` (`origin`) and sets the upstream tracking branch — no need to type `git push --set-upstream --force-with-lease origin <branch>` yourself.

### What "ready" means (why a branch might not push)

A development branch is pushed only if:

- It is **not stacked on top of another development branch** (git-stack pushes the stack one branch at a time, bottom-up), and
- It has **no WIP commits** — a commit whose summary is exactly `WIP` or is prefixed with `WIP:`, `wip `, `draft:`, `Draft:`, etc.

Branches with `fixup!` commits are still considered ready (so reviewers can see intermediate states), so clean those up before merging.

If your branch isn't pushing, check `git-stack` (the default view) for a WIP marker, reword the offending commit, or confirm it isn't sitting on top of another unmerged dev branch.

## Reference: the two config keys

| Key | Meaning | Default |
|-----|---------|---------|
| `stack.pull-remote` | Upstream remote for pulling protected branches | `origin` |
| `stack.push-remote` | Development remote for pushing local branches | `origin` |

## TL;DR

```bash
git config --local stack.pull-remote upstream   # main repo
git config --local stack.push-remote origin      # your fork

git-stack --pull    # pull main from upstream, rebase your stack
git-stack --push    # push ready branch(es) to origin
```
