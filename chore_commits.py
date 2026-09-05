#!/usr/bin/env python3
"""Commit externally-updated lockfiles in this repo as one chore commit each.

CHORE_COMMITS maps a repo-relative path to its commit subject and a parser
that reduces the file to {name: pinned entry}. Comparing that mapping against
HEAD produces the commit body, so the message names which plugins moved.
Add an entry, with a parser for its format, to cover another lockfile.

Each path is committed on its own with `git commit --only`, so unrelated
staged work stays in the index.
"""

import argparse
import json
import subprocess
import sys
import textwrap
import tomllib
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

BODY_WIDTH = 72


def parse_lazy_lock(text: str) -> dict[str, object]:
    """lazy.nvim: {"blink.cmp": {"branch": "main", "commit": "..."}}."""
    entries = json.loads(text)
    return dict(entries.items())


def parse_yazi_package(text: str) -> dict[str, object]:
    """yazi: [[plugin.deps]] and [[flavor.deps]] tables keyed by `use`."""
    sections = tomllib.loads(text)
    return {dep["use"]: dep for section in sections.values() for dep in section.get("deps", [])}


@dataclass(frozen=True)
class Lockfile:
    subject: str
    parse: Callable[[str], dict[str, object]]


CHORE_COMMITS = {
    "private_dot_config/exact_nvim/ext_lazy-lock.json": Lockfile(
        subject="chore(neovim): update plugins",
        parse=parse_lazy_lock,
    ),
    "private_dot_config/yazi/ext_package.toml": Lockfile(
        subject="chore(yazi): update packages",
        parse=parse_yazi_package,
    ),
}


def warn(message: str) -> None:
    print(f"chore-commits: {message}", file=sys.stderr)


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def repo_root() -> Path:
    here = Path(__file__).resolve().parent
    try:
        top = git(here, "rev-parse", "--show-toplevel")
    except (subprocess.CalledProcessError, OSError):
        warn(f"{here} is not a git repository")
        raise SystemExit(1) from None
    return Path(top.strip())


def is_dirty(repo: Path, path: str) -> bool:
    return bool(git(repo, "status", "--porcelain", "--", path).strip())


def parse_revision(repo: Path, path: str, lockfile: Lockfile) -> dict[str, object]:
    """Entries as of HEAD, empty when the path is new or unparsable there."""
    try:
        return lockfile.parse(git(repo, "show", f"HEAD:{path}"))
    except subprocess.CalledProcessError:
        return {}


def body(before: dict[str, object], after: dict[str, object]) -> str:
    """Added, removed and updated names, each list wrapped at the git width."""
    shared = before.keys() & after.keys()
    groups = (
        ("added", sorted(after.keys() - before.keys())),
        ("removed", sorted(before.keys() - after.keys())),
        ("updated", sorted(n for n in shared if before[n] != after[n])),
    )
    return "\n".join(
        textwrap.fill(
            f"{label}: {', '.join(names)}",
            width=BODY_WIDTH,
            break_long_words=False,
            break_on_hyphens=False,
        )
        for label, names in groups
        if names
    )


def message(repo: Path, path: str, lockfile: Lockfile) -> str:
    """Subject alone when the file cannot be read as its declared format."""
    try:
        after = lockfile.parse((repo / path).read_text())
    except (OSError, ValueError) as err:
        warn(f"{path}: unparsable, committing without a body ({err})")
        return lockfile.subject

    detail = body(parse_revision(repo, path, lockfile), after)
    return f"{lockfile.subject}\n\n{detail}" if detail else lockfile.subject


def commit(repo: Path, path: str, text: str) -> None:
    git(repo, "add", "--", path)
    git(repo, "commit", "--only", "--message", text, "--", path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="print the commit messages without committing",
    )
    args = parser.parse_args()

    repo = repo_root()
    committed = 0

    for path, lockfile in CHORE_COMMITS.items():
        try:
            dirty = is_dirty(repo, path)
        except subprocess.CalledProcessError as err:
            warn(f"{path}: {err.stderr.strip()}")
            return 1

        if not dirty:
            if not (repo / path).exists():
                warn(f"{path}: no such file, drop it from CHORE_COMMITS")
            continue

        text = message(repo, path, lockfile)

        if args.dry_run:
            print(f"--- {path}\n{text}\n")
            committed += 1
            continue

        try:
            commit(repo, path, text)
        except subprocess.CalledProcessError as err:
            warn(f"{path}: {err.stderr.strip() or err.stdout.strip()}")
            return 1

        print(f"--- {path}\n{text}\n")
        committed += 1

    if not committed:
        print("nothing to commit")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
