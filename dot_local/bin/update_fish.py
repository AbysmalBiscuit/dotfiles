"""Build fish from its newest release tag and lay down a matching data directory.

A cargo-installed fish leaves `__fish_data_dir` empty: the variable is filled
from DATADIR, a compile-time override that only the CMake build sets. Fish does
not need it, since it autoloads from assets embedded in the binary, but
third-party init snippets read files out of that tree. zoxide's `cd` wrapper is
one, and it fails on every startup without it.

So DATADIR is baked in here and the share/ tree from the same tag is copied to
where it points. Both come from one checkout, so the scripts on disk can never
drift from the binary reading them.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from cargo_install_latest import release_tags

PROG = "update-fish"

REPO = "https://github.com/fish-shell/fish-shell"

CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
CHECKOUT = CACHE_HOME / "fish_shell_repo"

# Plays the role /usr/share plays for a packaged fish: the build appends "fish"
# to DATADIR, so the data directory itself lands one level below this. Kept out
# of ~/.cache/fish proper so it cannot collide with the completions fish and the
# completion generator both write there.
DATA_ROOT = CACHE_HOME / "fish" / "share"

# ocargo applies this machine's optimization flags and forwards the rest.
CARGO_WRAPPERS = ("ocargo", "cargo")


def run(command: list[str], **kwargs) -> None:
    result = subprocess.run(command, **kwargs)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def sync_checkout(tag: str) -> None:
    """Puts CHECKOUT on the given tag, cloning it shallowly if it is not there."""
    if (CHECKOUT / ".git").is_dir():
        run(["git", "-C", str(CHECKOUT), "fetch", "--depth", "1", "origin", "tag", tag])
        run(["git", "-C", str(CHECKOUT), "checkout", "--force", "--detach", tag])
    else:
        CHECKOUT.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--depth", "1", "--branch", tag, REPO, str(CHECKOUT)])


def install(tag: str) -> None:
    cargo = next((path for name in CARGO_WRAPPERS if (path := shutil.which(name))), None)
    if cargo is None:
        print(f"{PROG}: cargo not found on PATH", file=sys.stderr)
        raise SystemExit(127)

    print(f"{PROG}: building {tag} with DATADIR={DATA_ROOT}", flush=True)
    run(
        [cargo, "install", "--force", "--locked", "--path", str(CHECKOUT)],
        env=dict(os.environ, DATADIR=str(DATA_ROOT)),
    )


def lay_down_share() -> Path:
    """Replaces the data directory with this tag's share tree.

    Replaced rather than copied over, so files a release drops don't linger and
    read as functions fish still ships.
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

    tags = release_tags(REPO)
    if not tags:
        print(f"{PROG}: no release tag found in {REPO}", file=sys.stderr)
        return 1
    tag = tags[0][1]

    try:
        sync_checkout(tag)
        install(tag)
    except KeyboardInterrupt:
        return 130

    data_dir = lay_down_share()
    print(f"{PROG}: fish {tag} installed, __fish_data_dir is {data_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
