# Fork workflow: pull from `upstream`, push to `origin`

`git-stack` keeps two remotes separate, which is exactly the fork setup you want:

- **`stack.pull-remote`** — where the shared, protected branches (e.g. `main`) come from. `git-stack` never rewrites these. Point it at `upstream`.
- **`stack.push-remote`** — where your personal feature branches go. `git-stack` assumes it owns these and force-pushes (with lease). Point it at your fork, `origin`.

## 1. Configure the remotes (one-time)

```console
$ git config --add stack.pull-remote upstream     # pull protected branches (main) from the upstream repo
$ git config --add stack.push-remote origin        # push your feature branches to your fork
```

Verify it took effect:

```console
$ git-stack --dump-config -          # confirm pull-remote=upstream, push-remote=origin
```

## 2. Push your ready branch

```console
$ git-stack sync                 # pull main from upstream, rebase your stack onto it, prune merged branches
$ git-stack --push -n            # dry-run: shows which branch(es) WOULD push to origin
$ git-stack --push               # force-push (with lease) ready branches to origin, sets upstream
```

`git-stack sync` uses `stack.pull-remote` (`upstream`) for the protected branch, and `git-stack --push` uses `stack.push-remote` (`origin`) for your work — so the same loop honors both remotes automatically.

## Notes

- Always `sync` before pushing so you publish a clean, current stack.
- A branch is **ready** to push only when it (1) sits directly on the protected base (not stacked on another dev branch) and (2) has no WIP commits. `--push` skips anything not ready; use `git-stack --push -n` plus `git-stack --show-commits all` to see why a branch is held back.
- To open the PR afterward, base it on the upstream protected branch:
  ```console
  $ gh pr create --base main --head <your-branch> --title "..." --body "..."
  ```
