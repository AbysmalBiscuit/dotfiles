#!/usr/bin/env python3
"""Rebase the current branch on the latest base branch and push it.

Usage: rebase_latest_force_push.py [base-branch]

base-branch resolves in order: the argument, `git config base.branch`, staging,
the remote's default branch.

Runs the whole happy path unattended: fetch, rebase, push with lease. Stops
before anything ambiguous (conflicts, dirty tree, protected branch, rejected
push) and reports enough state for a caller to take over.

Last line of output is always: RLFP-RESULT: <STATUS>
  PUSHED          rebased and pushed
  UP-TO-DATE      already on latest base, remote already matches
  CONFLICT        rebase stopped on conflicts, rebase still IN PROGRESS
  DIRTY           uncommitted changes, nothing done
  IN-PROGRESS     a rebase/merge/cherry-pick was already running, nothing done
  NO-COMMITS      branch has no commits of its own, nothing to push
  PROTECTED       current branch is a protected branch, nothing done
  STACKED         branch sits on another unmerged branch, nothing done
  INSTALL-FAILED  a lockfile moved in the rebase and its install failed
  HOOK-MODIFIED   pre-push hook rewrote files, push failed, tree now dirty
  REJECTED        remote moved, lease refused the push
  PUSH-FAILED     push failed for another reason (hook failure, network, auth)
  ERROR           preflight failed (not a repo, detached HEAD, no such base)
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".agents" / "lib"))

from agentgit import (  # noqa: E402
    REMOTE,
    capture,
    conflicted_files,
    current_branch,
    dirty,
    git,
    git_dir,
    git_lines,
    in_repo,
    indent,
    is_protected,
    lease_refused,
    operation_in_progress,
    rebase_todo_remaining,
    ref_exists,
    repo_root,
    resolve_base,
    say,
    say_block,
    short_head,
    tail,
    upstream_ref,
)

# The installed dependency tree tracks whatever was last installed, so a moved
# lockfile is the signal to reinstall. Only a lockfile tracked at HEAD counts,
# which makes a repo with no package manager skip the install entirely. First
# match wins: a repo carrying two lockfiles gets the one listed first.
LOCKFILE_INSTALLS = (
    ("bun.lock", ("bun", "install")),
    ("bun.lockb", ("bun", "install")),
    ("pnpm-lock.yaml", ("pnpm", "install")),
    ("yarn.lock", ("yarn", "install")),
    ("package-lock.json", ("npm", "install")),
    ("uv.lock", ("uv", "sync")),
    ("poetry.lock", ("poetry", "install")),
)


def finish(status: str, code: int = 0) -> None:
    say(f"RLFP-RESULT: {status}")
    sys.exit(code)


def find_lockfile() -> tuple[str, tuple[str, ...], str]:
    """The lockfile tracked at HEAD, its install command, and its current blob sha."""
    for name, cmd in LOCKFILE_INSTALLS:
        if capture("git", "cat-file", "-e", f"HEAD:{name}")[0] == 0:
            return name, cmd, git("rev-parse", f"HEAD:{name}")
    return "", (), ""


def report_stack(branch: str, base_ref: str) -> None:
    """Refuse the rebase when the branch sits on other unmerged branches.

    Replaying a parent's commits onto the base gives them new SHAs, so the
    child's PR shows work belonging to the parent until the parent is rebased to
    match. Only parents still on the remote count; the fetch pruned merged ones.
    """
    refs = git_lines(
        "for-each-ref", "--merged", "HEAD", "--no-merged", base_ref,
        "--format=%(refname:short)", f"refs/remotes/{REMOTE}/",
    )
    parents = [
        r.removeprefix(f"{REMOTE}/")
        for r in refs
        if r.removeprefix(f"{REMOTE}/") not in (branch, "HEAD")
    ]
    if not parents:
        return

    nearest = max(parents, key=lambda p: int(git("rev-list", "--count", f"{base_ref}..{REMOTE}/{p}") or 0))
    say("")
    say(f"{branch} is stacked on {len(parents)} unmerged branch(es) on {REMOTE}:")
    for p in parents:
        say(f"  {p}")
    say("")
    say("rebasing onto " + base_ref + " would replay their commits under new SHAs and break")
    say("the dependent PR's diff. Rebase the whole stack instead:")
    say("  /rebase-propagate")
    say("")
    say("or rebase this branch onto its parent alone:")
    say(f"  /rebase-latest-force-push {nearest}")
    finish("STACKED", 7)


def run_install(lock_file: str, cmd: tuple[str, ...]) -> None:
    tool = cmd[0]
    say("")
    say(f"== {' '.join(cmd)} ({lock_file} moved in the rebase) ==")
    if not shutil.which(tool):
        say(f"{tool} is not on PATH — skipped; installed deps are stale against {lock_file}")
        return

    code, out = capture(*cmd)
    if code != 0:
        say(tail(out, 20))
        say("")
        say("the rebase succeeded and is committed; only the install failed.")
        say("fix the cause and re-run this script — it will resume at the push")
        finish("INSTALL-FAILED", 23)

    say(tail(out, 5))
    # A rewritten lockfile means the committed one does not survive a clean
    # install; the push would carry a tree nobody can reproduce.
    if dirty(lock_file):
        say("")
        say(f"warning: the install rewrote {lock_file} — commit it or investigate before pushing")


def main() -> None:
    if not in_repo():
        say(f"not inside a git repository: {Path.cwd()}")
        finish("ERROR", 3)
    os.chdir(repo_root())
    gitdir = git_dir()

    # An interrupted rebase leaves HEAD detached, so this has to come before the
    # detached-HEAD check or a mid-conflict re-run reports the wrong thing.
    marker = operation_in_progress(gitdir)
    if marker:
        say(f"an operation is already in progress ({marker}) — nothing done")
        say("")
        say(git("status", "--short", "--branch"))
        conflicted = conflicted_files()
        if conflicted:
            say("")
            say("conflicted files:")
            say_block(indent("\n".join(conflicted)))
            say("")
            say("resolve, 'git add', 'git rebase --continue', then re-run this script")
        finish("IN-PROGRESS", 4)

    branch = current_branch()
    if not branch:
        say(f"HEAD is detached at {short_head()}; check out a branch first")
        finish("ERROR", 3)

    if is_protected(branch):
        say(f"{branch} is a protected branch — refusing to rewrite and force-push it")
        say("")
        say(git("status", "--short", "--branch"))
        finish("PROTECTED", 6)

    if dirty():
        say(f"working tree has uncommitted changes on {branch}:")
        say("")
        say(git("status", "--short", "--untracked-files=no"))
        say("")
        say("commit or stash them, then re-run")
        finish("DIRTY", 5)

    say("== fetch ==")
    say_block(tail(capture("git", "fetch", "--prune", REMOTE)[1], 20))

    base = resolve_base(sys.argv[1] if len(sys.argv) > 1 else "")
    if not base:
        say(f"no base branch: {REMOTE} has no staging branch and no default branch")
        say("pass one as an argument, or set it for this repo:")
        say("  git config base.branch <branch>")
        finish("ERROR", 3)

    base_ref = f"{REMOTE}/{base}"
    if not ref_exists(f"refs/remotes/{base_ref}"):
        say(f"no such base branch: {base_ref}")
        finish("ERROR", 3)

    report_stack(branch, base_ref)

    say("")
    say(f"== rebase {branch} onto {base_ref} ==")
    say(f"base tip:   {git('log', '--oneline', '-1', base_ref)}")
    say(f"branch tip: {git('log', '--oneline', '-1', 'HEAD')}")
    say("commits to replay:")
    say_block(indent(git("log", "--oneline", f"{base_ref}..HEAD")))

    lock_file, install_cmd, lock_before = find_lockfile()

    code, rebase_out = capture("git", "rebase", base_ref)
    if code != 0:
        say(rebase_out)
        say("")
        say("conflicted files:")
        say_block(indent("\n".join(conflicted_files())))
        say("")
        say(f"stopped while applying: {git('log', '--oneline', '-1', 'REBASE_HEAD')}")
        say(f"still queued after this one: {rebase_todo_remaining(gitdir)} commit(s)")
        say("")
        say("the rebase is IN PROGRESS — resolve, 'git add', 'git rebase --continue',")
        say("then re-run this script to push (or 'git rebase --abort' to back out)")
        finish("CONFLICT", 10)
    say(rebase_out)

    if lock_file and git("rev-parse", f"HEAD:{lock_file}") != lock_before:
        run_install(lock_file, install_cmd)

    if git("rev-list", "--count", f"{base_ref}..HEAD") == "0":
        say("")
        say(f"{branch} has no commits of its own on top of {base_ref} — nothing to push")
        finish("NO-COMMITS", 0)

    upstream = upstream_ref()
    if upstream and git("rev-parse", "HEAD") == git("rev-parse", upstream):
        say("")
        say(f"{branch} already matches {upstream} — nothing to push")
        finish("UP-TO-DATE", 0)

    say("")
    say("== push ==")
    if upstream:
        push_cmd = ("git", "push", "--force-with-lease", "--force-if-includes", REMOTE, f"HEAD:{branch}")
    else:
        say(f"no upstream yet — publishing {branch}")
        push_cmd = ("git", "push", "--set-upstream", REMOTE, f"HEAD:{branch}")
    say(" ".join(push_cmd))

    code, push_out = capture(*push_cmd)
    if code == 0:
        say(push_out)
        say("")
        say(git("status", "--short", "--branch"))
        say(git("log", "--oneline", "-1", "HEAD"))
        finish("PUSHED", 0)

    say(push_out)
    say("")

    if dirty():
        say("the pre-push hook rewrote files — push aborted and the tree is now dirty:")
        say("")
        say(git("status", "--short", "--untracked-files=no"))
        say("")
        say("decide whether these belong in a new commit or amended into an existing one,")
        say("then re-run this script")
        finish("HOOK-MODIFIED", 22)

    if lease_refused(push_out):
        say("the remote moved since the last fetch — the lease refused the push")
        say(f"someone else may have pushed to {REMOTE}/{branch}; inspect before overriding")
        finish("REJECTED", 20)

    say("push failed — see the output above (pre-push hook, network, or auth)")
    finish("PUSH-FAILED", 21)


if __name__ == "__main__":
    main()
