#!/usr/bin/env python3
"""Git pager that enables delta's side-by-side view on wide terminals.

Delta has no width threshold of its own: `side-by-side` is a plain boolean read
from git config, so the choice has to be made before delta starts. Below the
threshold, and whenever the width cannot be determined, this runs plain delta.

Environment:
    DELTA_SIDE_BY_SIDE_MIN_COLUMNS  threshold in columns (default 170)
"""

from __future__ import annotations

import os
import subprocess
import sys

DEFAULT_MIN_COLUMNS: int = 170


def terminal_columns() -> int:
    """Width of the terminal delta will draw into, or 0 if there isn't one."""
    for stream in (sys.stdout, sys.stderr):
        try:
            return os.get_terminal_size(stream.fileno()).columns
        except (OSError, ValueError, AttributeError):
            continue
    try:
        with open("/dev/tty", "rb", buffering=0) as tty:
            return os.get_terminal_size(tty.fileno()).columns
    except OSError:
        return 0


def min_columns() -> int:
    raw = os.environ.get("DELTA_SIDE_BY_SIDE_MIN_COLUMNS", "")
    try:
        return int(raw)
    except ValueError:
        return DEFAULT_MIN_COLUMNS


def configured_features() -> list[str]:
    try:
        result = subprocess.run(
            ["git", "config", "--get", "delta.features"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return []
    return result.stdout.split()


def main() -> None:
    args = ["delta", *sys.argv[1:]]
    if terminal_columns() >= min_columns():
        # Delta's builtin side-by-side feature sets its own line-number styles
        # and the last feature wins, so the configured ones are re-appended.
        features = " ".join(["side-by-side", *configured_features()])
        args[1:1] = ["--features", features]

    # Windows has no exec: os.execvp detaches delta and returns straight away,
    # so whoever invoked the pager sees it finish before a byte is written.
    # Waiting on a child behaves the same way everywhere.
    try:
        sys.exit(subprocess.run(args, check=False).returncode)
    except KeyboardInterrupt:
        sys.exit(130)


if __name__ == "__main__":
    main()
