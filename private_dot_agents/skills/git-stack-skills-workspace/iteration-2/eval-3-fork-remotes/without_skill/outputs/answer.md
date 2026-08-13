# Fork workflow: pull from `upstream`, push to `origin`

`git-stack` has two separate remote settings, so this maps cleanly onto a fork:

- **pull-remote** — where the protected/main branch is synced *from* (your `upstream`).
- **push-remote** — where your feature branches are pushed *to* (your fork, `origin`).

## 1. Configure the remotes

Set these once in the repo (writes to `.git/config`):

```bash
git config stack.pull-remote upstream
git config stack.push-remote origin
```

(Use `git config --global ...` if you want the same default in every clone.)

Make sure the two remotes actually exist / point where you expect:

```bash
git remote -v
# upstream  https://github.com/ORG/repo.git   (the main repo)
# origin    https://github.com/YOU/repo.git    (your fork)
```

Confirm `git-stack` picked up the settings and that `main` is treated as protected
(it must be protected so it's used as the base and pulled, not pushed):

```bash
git-stack --protected          # list protected branches; main should be here
git-stack --protect main       # add it if it isn't
```

## 2. Sync main from upstream

This rebases your local branches on top of the latest protected branch pulled from
the **pull-remote** (`upstream`):

```bash
git-stack sync
# or, to pull + rebase the whole stack in one go:
git-stack --pull --rebase
```

## 3. Push your ready branch(es) to your fork

Once a branch is ready (no WIP/fixup commits holding it back), push it to the
**push-remote** (`origin`):

```bash
git-stack --push
```

Preview first if you want to see exactly what would be pushed and where:

```bash
git-stack --push --dry-run
```

`--push` pushes every *ready* branch in the current stack to `origin`, leaving the
upstream `main` untouched. From there you open PRs against `upstream`'s main as usual.

### Typical end-to-end

```bash
git config stack.pull-remote upstream
git config stack.push-remote origin

git-stack sync          # bring in latest upstream/main, rebase your work
git-stack --push        # push ready feature branches to origin (your fork)
```
