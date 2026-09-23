#!/usr/bin/env python3
"""Delete the targets .chezmoidisable lists from the home directory.

.chezmoiignore includes .chezmoidisable, so chezmoi stops applying those
targets, but it also never removes an ignored target, whether through an
exact_ directory or .chezmoiremove. This removes them instead. It runs on every
apply rather than on change so a disabled target that something else puts back
is removed again.
"""

import os
import shutil
import sys
from pathlib import Path, PurePosixPath


def warn(message: str) -> None:
    print(f"remove-disabled: {message}", file=sys.stderr)


def patterns(disable_file: Path) -> list[str]:
    lines = (line.strip() for line in disable_file.read_text(encoding="utf-8").splitlines())
    return [line for line in lines if line and not line.startswith("#")]


def is_home_relative(pattern: str) -> bool:
    path = PurePosixPath(pattern)
    return not path.is_absolute() and ".." not in path.parts and not pattern.startswith("!")


def remove(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()


def main() -> int:
    source_dir = os.environ.get("CHEZMOI_SOURCE_DIR")
    if not source_dir:
        warn("CHEZMOI_SOURCE_DIR is not set, so there is no .chezmoidisable to read")
        return 0
    disable_file = Path(source_dir) / ".chezmoidisable"
    if not disable_file.is_file():
        return 0

    home = Path.home()
    for pattern in patterns(disable_file):
        if not is_home_relative(pattern):
            warn(f"skipping {pattern!r}: entries must be paths inside the home directory")
            continue
        for path in sorted(home.glob(pattern), reverse=True):
            try:
                remove(path)
            except OSError as error:
                warn(f"could not remove {path}: {error}")
            else:
                print(f"remove-disabled: removed {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
