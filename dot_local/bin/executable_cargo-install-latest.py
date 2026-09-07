#!/usr/bin/env python3
"""Install a crate from its newest release tag rather than from crates.io.

For projects that publish real releases but no crate, such as fish, the closest
thing to `cargo install NAME` is a `--git` install pinned to the newest tag.
This resolves that tag against the remote and hands the rest to cargo:

    cargo-install-latest REPO_URL [CARGO_ARGS...]
    cargo install-latest REPO_URL [CARGO_ARGS...]

Every argument after the URL is forwarded untouched, so the caller keeps
control of --locked, --features, and which package in the workspace to build.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys

PROG = "cargo-install-latest"

# The name cargo passes as the first argument when a custom subcommand runs as
# `cargo install-latest`. Absent when the command is spelled out in full.
SUBCOMMAND = "install-latest"

# A release tag and nothing else. Anchoring both ends drops the prereleases
# (4.0b1), the release candidates, and the prose tags (last_autotools) that
# accumulate in a long-lived repository.
RELEASE_TAG = re.compile(r"v?(\d+(?:\.\d+)*)\Z")

# ocargo applies this machine's optimization flags and forwards everything else
# to cargo, so it stands in wherever it is installed.
CARGO_WRAPPERS = ("ocargo", "cargo")

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
    # Sorted here rather than with git's --sort=-v:refname so the ordering does
    # not change with the git version, and so a 'v' prefix doesn't reorder tags.
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

    cargo = next((path for name in CARGO_WRAPPERS if (path := shutil.which(name))), None)
    if cargo is None:
        print(f"{PROG}: cargo not found on PATH", file=sys.stderr)
        return 127

    command = [cargo, "install", "--git", repo, "--tag", tag, *cargo_args]
    print(f"{PROG}: {os.path.basename(cargo)} installing {tag} from {repo}", flush=True)
    try:
        return subprocess.run(command).returncode
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
