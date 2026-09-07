#!/usr/bin/env python3
"""Rebase the current branch onto the latest base branch and propagate the
result down its stack of dependent PRs.

Usage: rebase_propagate.py [base-branch]
       rebase_propagate.py --dupes        read-only: run only the duplicate PR scan

base-branch resolves in order: the argument, `git config base.branch`, staging,
the remote's default branch.

The stack is discovered from GitHub: every open PR whose base is a branch in the
stack becomes a child, recursively. Each branch is rebased onto its new parent,
then every branch is pushed. Nothing is pushed until all rebases succeed, so a
conflict leaves the remote untouched and the run resumable.

Duplicate PRs are classified but never closed. That call is left to the caller.

Last line of output is always: RP-RESULT: <STATUS>
  PROPAGATED     every branch rebased and pushed
  NOTHING-TO-DO  already on latest base, remotes already match
  CONFLICT       stopped on conflicts, rebase IN PROGRESS, nothing pushed
  DIRTY          uncommitted changes, nothing done
  IN-PROGRESS    a rebase/merge was already running, nothing done
  PROTECTED      current branch is a protected branch, nothing done
  REJECTED       remote moved, lease refused a push
  HOOK-MODIFIED  pre-push hook rewrote files, push failed, tree now dirty
  PUSH-FAILED    push failed for another reason
  DUPES-ONLY     --dupes was passed; only the duplicate scan ran
  ERROR          preflight failed
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".agents" / "lib"))

from agentgit import (  # noqa: E402
    REMOTE,
    capture,
    conflicted_files,
    current_branch,
    dirty,
    gh_json,
    git,
    git_dir,
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
)

MAX_DEPTH = 10
# '-' stands in for an empty field so a row always has four of them.
EMPTY = "-"

# Statuses that end the run for good; anything else leaves the state file for a
# resumed run to pick up.
TERMINAL = ("PROPAGATED", "NOTHING-TO-DO", "DIRTY", "PROTECTED", "ERROR")


class Run:
    """One propagate run: the branch stack, its state file, and how it ends."""

    def __init__(self, dupes_only: bool, state: Path):
        self.dupes_only = dupes_only
        self.state = state
        self.stack: list[str] = []
        self.parent_of: dict[str, str] = {}
        self.pr_of: dict[str, int] = {}

    def finish(self, status: str, code: int = 0) -> None:
        if status in TERMINAL and not self.dupes_only:
            self.state.unlink(missing_ok=True)
        say(f"RP-RESULT: {status}")
        sys.exit(code)

    # ------------------------------------------------------------ state file

    def write_state(self, root: str, base: str) -> None:
        rows = [f"#root\t{root}\t{base}"]
        for b in self.stack:
            rows.append(
                "\t".join(
                    [
                        b,
                        git("rev-parse", b),
                        self.parent_of.get(b, EMPTY),
                        str(self.pr_of.get(b, EMPTY)),
                    ]
                )
            )
        self.state.write_text("\n".join(rows) + "\n")

    def read_state(self) -> list[list[str]]:
        try:
            text = self.state.read_text()
        except OSError:
            return []
        return [line.split("\t") for line in text.splitlines() if line]

    def old_tip(self, branch: str) -> str:
        """The branch's tip as recorded when the run started, or empty."""
        for row in self.read_state():
            if row[0] == branch:
                return row[1]
        return ""

    def load_stack_from_state(self) -> None:
        for row in self.read_state():
            if row[0].startswith("#") or not row[0]:
                continue
            branch, _tip, parent, pr = (row + [EMPTY, EMPTY, EMPTY])[:4]
            self.stack.append(branch)
            if parent != EMPTY:
                self.parent_of[branch] = parent
            if pr != EMPTY:
                self.pr_of[branch] = int(pr)

    # ------------------------------------------------------------ discovery

    def discover(self, root: str) -> None:
        """Walk open PRs down from `root`, recording each child's parent and number."""
        self.stack = [root]
        frontier = [root]
        for _ in range(MAX_DEPTH):
            if not frontier:
                break
            nxt: list[str] = []
            for b in frontier:
                kids = gh_json(
                    "pr", "list", "--base", b, "--state", "open",
                    "--limit", "50", "--json", "number,headRefName",
                ) or []
                for kid in kids:
                    head = kid.get("headRefName") or ""
                    number = kid.get("number")
                    if not head or head in self.parent_of or head == root:
                        continue
                    if not ref_exists(f"refs/heads/{head}"):
                        say(
                            f"note: PR #{number} targets {b} from {head}, "
                            f"but there is no local branch {head} — skipping it"
                        )
                        continue
                    self.parent_of[head] = b
                    self.pr_of[head] = number
                    self.stack.append(head)
                    nxt.append(head)
            frontier = nxt

        root_prs = gh_json(
            "pr", "list", "--head", root, "--state", "open", "--limit", "10", "--json", "number"
        ) or []
        if root_prs:
            self.pr_of[root] = root_prs[0]["number"]

    # ------------------------------------------------------------ dupes

    def scan_dupes(self) -> None:
        say("")
        say("== duplicate PR scan ==")
        dupes = 0
        for b in self.stack:
            rows = gh_json(
                "pr", "list", "--head", b, "--state", "open", "--limit", "20",
                "--json", "number,title,baseRefName,author,url",
            ) or []
            if len(rows) < 2:
                continue
            keep = self.pr_of.get(b) or min(r["number"] for r in rows)
            kept = next((r for r in rows if r["number"] == keep), None)
            keep_base = (kept or {}).get("baseRefName")
            keep_title = (kept or {}).get("title")
            for r in rows:
                if r["number"] == keep:
                    continue
                dupes += 1
                login = (r.get("author") or {}).get("login", "")
                is_bot = login.startswith("github-actions") or login.endswith("[bot]")
                same = r.get("baseRefName") == keep_base and r.get("title") == keep_title
                verdict = "CLEAR-DUPE" if same and is_bot else "AMBIGUOUS"
                say(
                    f"{verdict}  #{r['number']} ({login}) '{r.get('title')}' "
                    f"{b} -> {r.get('baseRefName')}   duplicate of #{keep}"
                )
                say(f"          {r.get('url')}")
        say(f"RP-DUPES: {dupes}")

    # ------------------------------------------------------------ rebase

    def rebase_all(self, base: str, root: str, gitdir: str) -> None:
        say("")
        say("== rebase ==")
        for b in self.stack:
            if b == root:
                new_parent = f"{REMOTE}/{base}"
                old_parent = ""
            else:
                new_parent = self.parent_of[b]
                old_parent = self.old_tip(new_parent)

            if capture("git", "merge-base", "--is-ancestor", new_parent, b)[0] == 0:
                say(f"{b}: already on top of {new_parent} — skipping")
                continue

            if old_parent:
                say(f"{b}: rebase --onto {new_parent} {old_parent[:9]} (its old parent tip)")
                code, out = capture("git", "rebase", "--onto", new_parent, old_parent, b)
            else:
                say(f"{b}: rebase onto {new_parent}")
                code, out = capture("git", "rebase", new_parent, b)

            if code != 0:
                self.report_conflict(b, out, gitdir)
            say(f"  ok: {git('log', '--oneline', '-1', b)}")

    def report_conflict(self, branch: str, out: str, gitdir: str) -> None:
        say(out)
        say("")
        say(f"conflicted files on {branch}:")
        say_block(indent("\n".join(conflicted_files())))
        say("")
        say(f"stopped while applying: {git('log', '--oneline', '-1', 'REBASE_HEAD')}")
        if Path(gitdir, "rebase-merge", "git-rebase-todo").is_file():
            say(f"still queued on {branch}: {rebase_todo_remaining(gitdir)} commit(s)")
        waiting = self.stack[self.stack.index(branch) + 1:]
        say(f"branches still waiting behind it: {' '.join(waiting) or 'none'}")
        say("")
        say("NOTHING HAS BEEN PUSHED — the remote is untouched.")
        say("resolve, 'git add', 'git rebase --continue', then re-run this script;")
        say("it resumes from here and pushes the whole stack once every rebase lands.")
        say("('git rebase --abort' backs out this branch only; re-running then restarts.)")
        self.finish("CONFLICT", 10)

    # ------------------------------------------------------------ push

    def push_all(self) -> None:
        say("")
        say("== push ==")
        pushed: list[str] = []
        for b in self.stack:
            if git("rev-parse", b) == git("rev-parse", f"{REMOTE}/{b}"):
                say(f"{b}: remote already matches — skipping")
                continue
            if ref_exists(f"refs/remotes/{REMOTE}/{b}"):
                cmd = ("git", "push", "--force-with-lease", "--force-if-includes", REMOTE, f"{b}:{b}")
            else:
                cmd = ("git", "push", "--set-upstream", REMOTE, f"{b}:{b}")
            code, out = capture(*cmd)
            say(f"{b}: {' '.join(tail(out, 2).splitlines())}")
            if code != 0:
                say("")
                say(out)
                say("")
                say(f"pushed so far: {' '.join(pushed) or 'none'}")
                if dirty():
                    say(f"the pre-push hook rewrote files on {b} — tree is now dirty:")
                    say(git("status", "--short", "--untracked-files=no"))
                    self.finish("HOOK-MODIFIED", 22)
                if lease_refused(out):
                    say(f"the remote moved since the fetch — the lease refused the push to {b}")
                    self.finish("REJECTED", 20)
                self.finish("PUSH-FAILED", 21)
            pushed.append(b)


def main() -> None:
    args = sys.argv[1:]
    dupes_only = bool(args) and args[0] == "--dupes"
    if dupes_only:
        args = args[1:]

    if not in_repo():
        say(f"not inside a git repository: {Path.cwd()}")
        say("RP-RESULT: ERROR")
        sys.exit(3)
    os.chdir(repo_root())
    gitdir = git_dir()
    run = Run(dupes_only, Path(gitdir, "rebase-propagate.state"))

    # ------------------------------------------------------------- preflight

    marker = operation_in_progress(gitdir)
    if marker and not dupes_only:
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
        run.finish("IN-PROGRESS", 4)

    here = current_branch()
    if not here:
        say(f"HEAD is detached at {short_head()}; check out a branch first")
        run.finish("ERROR", 3)

    # A resumed run must re-root on the branch the original run started from.
    # After 'git rebase --continue' HEAD sits on whichever child was mid-replay,
    # and re-rooting there would silently drop its ancestors from the push.
    rows = run.read_state()
    branches_in_state = [r[0] for r in rows if not r[0].startswith("#")]
    resume = bool(rows) and any(r[0] == "#root" for r in rows) and here in branches_in_state
    if resume:
        root_row = next(r for r in rows if r[0] == "#root")
        root = root_row[1]
        if not ref_exists(f"refs/heads/{root}"):
            say(f"state file names root '{root}', which no longer exists — discarding it")
            run.state.unlink(missing_ok=True)
            resume = False
            root = here
    else:
        run.state.unlink(missing_ok=True)
        root = here

    if is_protected(root) and not dupes_only:
        say(f"{root} is a protected branch — refusing to rewrite and force-push it")
        run.finish("PROTECTED", 6)

    if not dupes_only and dirty():
        say(f"working tree has uncommitted changes on {root}:")
        say("")
        say(git("status", "--short", "--untracked-files=no"))
        say("")
        say("commit or stash them, then re-run")
        run.finish("DIRTY", 5)

    if not dupes_only:
        say("== fetch ==")
        say_block(tail(capture("git", "fetch", "--prune", REMOTE)[1], 20))

    explicit = args[0] if args else ""
    if resume:
        explicit = next(r for r in rows if r[0] == "#root")[2]
    base = resolve_base(explicit)
    if not base:
        say(f"no base branch: {REMOTE} has no staging branch and no default branch")
        say("pass one as an argument, or set it for this repo:")
        say("  git config base.branch <branch>")
        run.finish("ERROR", 3)

    if not ref_exists(f"refs/remotes/{REMOTE}/{base}"):
        say(f"no such base branch: {REMOTE}/{base}")
        run.finish("ERROR", 3)

    # ------------------------------------------------------------- stack

    # Probe repo resolution, not just auth: an authenticated gh still fails to
    # list PRs when the remote is not a GitHub repo, and that must not look like
    # an empty stack.
    repo = gh_json("repo", "view", "--json", "nameWithOwner") or {}
    gh_ok = bool(repo.get("nameWithOwner"))

    if resume:
        run.load_stack_from_state()
    elif gh_ok:
        run.discover(root)
    else:
        run.stack = [root]
        say("NOTE: gh could not resolve a GitHub repo for this remote (unavailable,")
        say("      unauthenticated, or not a GitHub remote). No PR stack was discovered,")
        say(f"      so ONLY {root} was handled. Dependent PRs, if any, were NOT propagated.")

    say("")
    say("== stack ==")
    say(f"base: {REMOTE}/{base}  ({git('log', '--oneline', '-1', f'{REMOTE}/{base}')})")
    for b in run.stack:
        parent = run.parent_of.get(b, f"{REMOTE}/{base}")
        pr = f"  (PR #{run.pr_of[b]})" if b in run.pr_of else ""
        say(f"  {b} -> {parent}{pr}")

    if dupes_only:
        if not gh_ok:
            run.finish("ERROR", 3)
        run.scan_dupes()
        run.finish("DUPES-ONLY", 0)

    # ------------------------------------------------------------- old tips

    if resume:
        say("")
        say(f"resuming the run started on {root} (old tips come from the state file)")
    else:
        run.write_state(root, base)

    run.rebase_all(base, root, gitdir)

    if capture("git", "switch", "--quiet", root)[0] != 0:
        run.finish("ERROR", 3)

    run.push_all()

    if gh_ok:
        run.scan_dupes()

    say("")
    say("== result ==")
    for b in run.stack:
        pr = f"  (PR #{run.pr_of[b]})" if b in run.pr_of else ""
        say(f"  {b}  {git('log', '--oneline', '-1', b)}{pr}")
    say(f"on branch: {current_branch()}")
    run.finish("PROPAGATED", 0)


if __name__ == "__main__":
    main()
