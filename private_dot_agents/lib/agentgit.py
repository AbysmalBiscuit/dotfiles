"""Shared git/gh helpers for the recon scripts under `~/.agents`.

Every script built on this follows one contract: print a human-readable report
to stdout and end with a `<PREFIX>-RESULT: <STATUS>` line, so a skill can act on
the status without re-running the commands that produced the report.

Import it with the repo root on `sys.path`:

    sys.path.insert(0, str(Path.home() / ".agents" / "lib"))
    from agentgit import git, say, resolve_base
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

PROTECTED_BRANCHES = ("staging", "main", "master", "develop", "production", "release")
REMOTE = "origin"

# A git operation leaves one of these in $GIT_DIR while it is mid-flight.
OPERATION_MARKERS = (
    "rebase-merge",
    "rebase-apply",
    "MERGE_HEAD",
    "CHERRY_PICK_HEAD",
    "REVERT_HEAD",
)


def say(*parts: object) -> None:
    """Print one line. Carriage returns become newlines.

    git progress output overwrites a line with CR, which a terminal collapses
    but a captured transcript renders as one unreadable line.
    """
    print(" ".join(str(p) for p in parts).replace("\r", "\n"))


def say_block(text: str) -> None:
    """Print a multi-line block, or nothing at all when it is empty.

    Matches a shell pipeline into `sed` or `tail`, which emits nothing for empty
    input where `say("")` would emit a blank line.
    """
    if text:
        say(text)


def run(
    *args: str,
    merge_stderr: bool = False,
    cwd: str | os.PathLike[str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT if merge_stderr else subprocess.PIPE,
        text=True,
        cwd=cwd,
    )


def capture(*args: str) -> tuple[int, str]:
    """Exit code plus stdout and stderr interleaved, the way a terminal shows them.

    Trailing newlines are stripped, so the text can be printed with `say`
    without doubling the blank line at the end.
    """
    p = run(*args, merge_stderr=True)
    return p.returncode, p.stdout.rstrip("\n")


def git(*args: str) -> str:
    """Stdout of a git command with trailing newlines removed, as `$( )` gives it.

    Leading whitespace is preserved: the first column of `git status --porcelain`
    is a status flag, so " M file" and "M  file" mean different things.

    Empty string when the command fails, so callers that must tell "failed" from
    "succeeded with no output" apart use `git_ok` or `run` instead.
    """
    p = run("git", *args)
    return p.stdout.rstrip("\n") if p.returncode == 0 else ""


def git_ok(*args: str) -> bool:
    return run("git", *args).returncode == 0


def git_lines(*args: str) -> list[str]:
    return [line for line in git(*args).splitlines() if line]


def gh_json(*args: str):
    """Parsed JSON from a `gh` call, or None when gh is missing, fails, or is silent."""
    if not shutil.which("gh"):
        return None
    p = run("gh", *args)
    if p.returncode != 0 or not p.stdout.strip():
        return None
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        return None


def in_repo() -> bool:
    return git_ok("rev-parse", "--git-dir")


def repo_root() -> str:
    return git("rev-parse", "--show-toplevel")


def git_dir() -> str:
    return git("rev-parse", "--git-dir")


def current_branch() -> str:
    """The checked-out branch, or empty on a detached HEAD."""
    return git("symbolic-ref", "--quiet", "--short", "HEAD")


def short_head() -> str:
    return git("rev-parse", "--short", "HEAD")


def operation_in_progress(gitdir: str) -> str:
    """The in-flight operation's marker name, or empty when the tree is idle."""
    for marker in OPERATION_MARKERS:
        if Path(gitdir, marker).exists():
            return marker
    return ""


def is_protected(branch: str) -> bool:
    return branch in PROTECTED_BRANCHES


def dirty(*pathspec: str) -> str:
    """Porcelain status of tracked files, optionally narrowed to pathspecs."""
    args = ["status", "--porcelain", "--untracked-files=no"]
    if pathspec:
        args += ["--", *pathspec]
    return git(*args)


def untracked() -> list[str]:
    return git_lines("ls-files", "--others", "--exclude-standard")


def upstream_ref() -> str:
    """The branch's `@{upstream}`, or empty when it has never been pushed."""
    return git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")


def ref_exists(ref: str) -> bool:
    return git_ok("rev-parse", "--verify", "--quiet", ref)


def resolve_base(explicit: str = "", remote: str = REMOTE) -> str:
    """The base branch name with no remote prefix, or empty when none resolves.

    Resolution order: the explicit argument, `git config base.branch`, staging,
    then the remote's default branch.
    """
    base = explicit or git("config", "--get", "base.branch")
    if not base:
        if ref_exists(f"refs/remotes/{remote}/staging"):
            base = "staging"
        else:
            # git writes origin/HEAD once at clone time and fetch never revisits
            # it, so a missing or renamed default costs one round trip to fix.
            base = git("symbolic-ref", "--quiet", "--short", f"refs/remotes/{remote}/HEAD")
            if not base:
                run("git", "remote", "set-head", remote, "--auto")
                base = git("symbolic-ref", "--quiet", "--short", f"refs/remotes/{remote}/HEAD")
    return base.removeprefix(f"{remote}/")


_LEASE_REFUSED = re.compile(
    r"stale info|force-with-lease|force-if-includes|non-fast-forward|fetch first|rejected",
    re.IGNORECASE,
)


def lease_refused(push_output: str) -> bool:
    """Whether a failed push failed because the remote moved, not for another reason."""
    return bool(_LEASE_REFUSED.search(push_output))


def conflicted_files() -> list[str]:
    return git_lines("diff", "--name-only", "--diff-filter=U")


def rebase_todo_remaining(gitdir: str) -> str:
    """Commits still queued in an interrupted rebase, or "?" when unreadable."""
    todo = Path(gitdir, "rebase-merge", "git-rebase-todo")
    try:
        lines = todo.read_text().splitlines()
    except OSError:
        return "?"
    return str(sum(1 for ln in lines if ln.strip() and not ln.lstrip().startswith("#")))


def indent(text: str, prefix: str = "  ") -> str:
    """Prefix every line. Empty input stays empty, so callers can print it blindly."""
    return "\n".join(prefix + line for line in text.splitlines())


def tail(text: str, n: int) -> str:
    return "\n".join(text.splitlines()[-n:])
