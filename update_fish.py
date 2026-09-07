#!/usr/bin/env python3
"""Build fish from its newest release tag and lay down a matching data directory.

Run by `chezmoi tools install fish`, which is its only caller.

DATADIR is a compile-time override only the CMake build sets, so a cargo-built
fish leaves __fish_data_dir empty. Fish autoloads from assets embedded in the
binary and does not need it, but third-party init snippets read files out of
that tree. Baking DATADIR in and copying share/ from the same checkout keeps
those scripts matched to the binary reading them.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PROG = "update-fish"

REPO = "https://github.com/fish-shell/fish-shell"

# Anchored at both ends, so prereleases (4.0b1) and prose tags (last_autotools)
# don't outrank a real release.
RELEASE_TAG = re.compile(r"(\d+(?:\.\d+)*)\Z")

CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
CHECKOUT = CACHE_HOME / "fish_shell_repo"

# The build appends "fish" to DATADIR, so the data directory lands one level
# below this. Kept out of ~/.cache/fish proper, where the completion generator
# writes.
DATA_ROOT = CACHE_HOME / "fish" / "share"


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, **kwargs)
    if result.returncode != 0:
        raise SystemExit(result.returncode)
    return result


def newest_tag() -> str:
    result = run(
        ["git", "ls-remote", "--tags", "--refs", REPO],
        capture_output=True,
        text=True,
    )
    tags = []
    for line in result.stdout.splitlines():
        _, _, ref = line.partition("refs/tags/")
        if match := RELEASE_TAG.fullmatch(ref.strip()):
            tags.append((tuple(int(p) for p in match.group(1).split(".")), ref.strip()))
    if not tags:
        print(f"{PROG}: no release tag found in {REPO}", file=sys.stderr)
        raise SystemExit(1)
    return max(tags)[1]


def sync_checkout(tag: str) -> None:
    """Puts CHECKOUT on the given tag, cloning it shallowly if it is not there."""
    if (CHECKOUT / ".git").is_dir():
        run(["git", "-C", str(CHECKOUT), "fetch", "--depth", "1", "origin", "tag", tag])
        run(["git", "-C", str(CHECKOUT), "checkout", "--force", "--detach", tag])
    else:
        CHECKOUT.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--depth", "1", "--branch", tag, REPO, str(CHECKOUT)])


def lay_down_share() -> Path:
    """Replaces the data directory with this tag's share tree.

    Replaced rather than merged, so a file dropped between releases cannot
    linger and read as a function fish still ships.
    """
    data_dir = DATA_ROOT / "fish"
    if data_dir.exists():
        shutil.rmtree(data_dir)
    data_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(CHECKOUT / "share", data_dir)
    return data_dir


def main() -> int:
    if not shutil.which("sphinx-build"):
        print(
            f"{PROG}: sphinx-build not found on PATH, which the man page build "
            "requires. Install it with `uv tool install sphinx`.",
            file=sys.stderr,
        )
        return 1

    cargo = shutil.which("ocargo") or shutil.which("cargo")
    if cargo is None:
        print(f"{PROG}: cargo not found on PATH", file=sys.stderr)
        return 127

    tag = newest_tag()
    try:
        sync_checkout(tag)
        print(f"{PROG}: building {tag} with DATADIR={DATA_ROOT}", flush=True)
        run(
            [cargo, "install", "--force", "--locked", "--path", str(CHECKOUT)],
            env=dict(os.environ, DATADIR=str(DATA_ROOT)),
        )
    except KeyboardInterrupt:
        return 130

    data_dir = lay_down_share()
    print(f"{PROG}: fish {tag} installed, __fish_data_dir is {data_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
