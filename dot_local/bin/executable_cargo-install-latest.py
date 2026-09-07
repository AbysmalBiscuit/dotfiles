#!/usr/bin/env python3
"""Install a crate from its newest release tag rather than from crates.io.

    cargo-install-latest REPO_URL [CARGO_ARGS...]
    cargo install-latest REPO_URL [CARGO_ARGS...]

Everything after the URL is forwarded to cargo untouched.
"""

from __future__ import annotations

import re
import subprocess
import shutil
import sys

from ocargo import run_cargo

PROG = "cargo-install-latest"

# cargo passes the subcommand name through as the first argument.
SUBCOMMAND = "install-latest"

# Anchored at both ends, so prereleases (4.0b1) and prose tags (last_autotools)
# don't outrank a real release.
RELEASE_TAG = re.compile(r"v?(\d+(?:\.\d+)*)\Z")

USAGE = f"""\
Install a crate from its newest release tag

Usage: {PROG} REPO_URL [CARGO_ARGS...]

Resolves the newest release tag in REPO_URL, then runs
`cargo install --git REPO_URL --tag TAG` with CARGO_ARGS appended.\
"""


def release_tags(repo: str) -> list[tuple[tuple[int, ...], str]]:
    """Every release tag on the remote, newest first."""
    git = shutil.which("git")
    if git is None:
        print(f"{PROG}: git not found on PATH", file=sys.stderr)
        raise SystemExit(127)

    result = subprocess.run(
        [git, "ls-remote", "--tags", "--refs", repo],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        print(f"{PROG}: could not read tags from {repo}", file=sys.stderr)
        raise SystemExit(result.returncode)

    tags: list[tuple[tuple[int, ...], str]] = []
    for line in result.stdout.splitlines():
        _, _, ref = line.partition("refs/tags/")
        match = RELEASE_TAG.fullmatch(ref.strip())
        if match:
            tags.append((tuple(int(part) for part in match.group(1).split(".")), ref.strip()))
    # Sorted here rather than by git, whose --sort=-v:refname orders a 'v' prefix
    # ahead of the numbers.
    return sorted(tags, reverse=True)


def main() -> int:
    argv = sys.argv[1:]
    if argv[:1] == [SUBCOMMAND]:
        argv = argv[1:]

    if not argv:
        print(USAGE, file=sys.stderr)
        return 2
    if argv[0] in {"-h", "--help"}:
        print(USAGE)
        return 0

    repo, *cargo_args = argv

    tags = release_tags(repo)
    if not tags:
        print(f"{PROG}: no release tag found in {repo}", file=sys.stderr)
        return 1
    tag = tags[0][1]

    print(f"{PROG}: installing {tag} from {repo}", flush=True)
    return run_cargo(["install", "--git", repo, "--tag", tag, *cargo_args])


if __name__ == "__main__":
    sys.exit(main())
