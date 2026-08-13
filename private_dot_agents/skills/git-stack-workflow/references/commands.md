# git-stack command & config reference

Grounded in `git-stack` 0.10.x. When in doubt, run `git-stack <cmd> --help`.

## Table of contents

- [Top-level command and flags](#top-level-command-and-flags)
- [Subcommands](#subcommands)
- [Configuration fields](#configuration-fields)
- [git-branch-stash](#git-branch-stash)

## Top-level command and flags

`git-stack` with no subcommand visualizes the stack. The big actions are flags,
not subcommands:

| Flag | Meaning |
|------|---------|
| `-r`, `--rebase` | Rebase the selected stacks onto their protected base; runs auto-fixup / auto-repair |
| `--pull` | Pull the parent (protected) branch and rebase onto it |
| `--push` | Push all "ready" development branches to `stack.push-remote` (see git-stack-publish) |
| `-s`, `--stack <STACK>` | Which stacks to include: `current`, `dependents`, `descendants`, `all` |
| `--base <BASE>` | Branch to evaluate from (default: most-recent protected branch) |
| `--onto <ONTO>` | Branch to rebase onto (default: `--base`) |
| `--fixup <FIXUP>` | Fixup handling: `ignore`, `move`, `squash` |
| `--repair` | Repair diverging branches (re-merge stacks split by a manual `git rebase`) |
| `-n`, `--dry-run` | Show what would happen without changing anything |
| `--format <FORMAT>` | Output: `silent`, `list`, `graph`, `debug` |
| `--show-commits <WHEN>` | `none`, `unprotected`, `all` |
| `--protected` | Report which branches are protected (pair with `-v`) |
| `--protect <GLOB>` | Append a protected-branch glob (gitignore syntax) to repo config |
| `--dump-config <FILE>` | Write current effective config (`-` for stdout) |
| `--color <WHEN>` | `auto`, `always`, `never` |
| `-v`, `--verbose` / `-q`, `--quiet` | Logging verbosity |

## Subcommands

`previous`, `next`, `reword`, `amend`, `sync`, `run`, `alias`.

### `git-stack sync`
Rebase local branches on top of pull remotes. Fetches `stack.push-remote` to
prune deleted remote branches; deletes merged dev branches. No auto operations.
- `-n, --dry-run`

### `git-stack next [NUM_COMMITS]` / `git-stack previous [NUM_COMMITS]`
Switch to a descendant (`next`) or ancestor (`previous`) commit. `NUM_COMMITS`
default 1.
- `-b, --branch` — jump to the next/previous *branch*, not just a commit
- `--stash` — stash the working tree before switching
- `--oldest` — on ambiguity, pick the oldest commit
- `--protected` — (`previous` only) traverse across protected commits

### `git-stack amend [REV]`
Meld staged changes into a commit (default `HEAD`). Descendants are rebased onto
the amended commit unless that would conflict.
- `-a, --all` — commit all changed files
- `-i, --interactive` — interactively choose changes
- `-e, --edit` — force editing the message
- `-m, --message <MSG>`

### `git-stack reword [REV]`
Rewrite a commit's message (default `HEAD`); descendants are rebased on top.
- `-m, --message <MSG>`

### `git-stack run <COMMAND> <ARG>...`
Run a command at each commit in the current stack, stopping at first failure.
- `--no-fail-fast` — keep going on failure
- `-s, --switch` — switch to the first commit that failed
- `-n, --dry-run`

### `git-stack alias`
- `--register` / `--unregister` — add/remove the short `git <cmd>` aliases
  (`git stack`, `git sync`, `git next`, `git prev`, `git reword`, `git amend`,
  `git run`).

## Configuration fields

Read from (in precedence order): `git -c`, `GIT_CONFIG`, `$REPO/.git/config`,
`$REPO/.gitconfig`, other `.gitconfig`. Inspect effective config with
`git-stack --dump-config -`.

| Field | Argument | Format | Description |
|-------|----------|--------|-------------|
| `stack.protected-branch` | — | multivar of globs | Branches matching these globs (gitignore syntax) are protected |
| `stack.protect-commit-count` | — | integer | Protect commits on a branch with `count`+ commits |
| `stack.protect-commit-age` | — | time delta (e.g. `10days`) | Protect commits older than this |
| `stack.auto-base-commit-count` | — | integer | Split off branches more than `count` commits from the implied base |
| `stack.stack` | `--stack` | `current`/`dependents`/`descendants`/`all` | Which stacks to operate on |
| `stack.push-remote` | — | string | Remote for pushing your local branches |
| `stack.pull-remote` | — | string | Upstream remote for pulling protected branches |
| `stack.show-format` | `--format` | `silent`/`list`/`graph`/`debug` | How to render the stack |
| `stack.show-stacked` | — | bool | Show branches stacked where possible |
| `stack.auto-fixup` | `--fixup` | `ignore`/`move`/`squash` | Default fixup action during `--rebase` |
| `stack.auto-repair` | — | bool | Run branch repair during `--rebase` |
| `stack.gpgSign` | — | bool | Sign commits (falls back to `commit.gpgSign`) |

### Common config recipes

```console
$ git-stack --protect 'release/*'                       # protect more branches locally
$ git config --add stack.pull-remote upstream           # fork workflow: pull from upstream
$ git config --add stack.push-remote origin             # ...push to your fork
$ git config stack.auto-fixup squash                    # always squash fixups on --rebase
```

When adopting `git-stack` as a team, move protected-branch config from
`$REPO/.git/config` into a committed `$REPO/.gitconfig`.

## git-branch-stash

`git-stack` snapshots branch state via `git-branch-stash` before any history
rewrite (file format: `.git/branch-stash`). It's like `git stash` but for *where
each branch points* rather than your working tree. See the **git-stack-recover**
skill for using it to undo.

| Command | Meaning |
|---------|---------|
| `git-branch-stash push` | Snapshot all branches (`-m` to annotate) |
| `git-branch-stash list` | List snapshots in a stack |
| `git-branch-stash apply` | Re-apply the last snapshot (keeps it) |
| `git-branch-stash pop` | Apply the last snapshot and delete it |
| `git-branch-stash drop` | Delete the last snapshot |
| `git-branch-stash clear` | Delete all snapshots |
| `git-branch-stash stacks` | List all snapshot stacks |

The `[STACK]` positional defaults to `recent`, **but `git-stack` stores its
automatic backups under the stack named `git-stack`**. To undo a `git-stack`
operation you must name that stack — e.g. `git-branch-stash pop git-stack`. See
the **git-stack-recover** skill.
