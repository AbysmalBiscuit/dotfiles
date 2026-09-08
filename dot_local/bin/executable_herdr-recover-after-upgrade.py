#!/usr/bin/env python3
"""Restart Herdr after an upgrade, then attach from the current terminal."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from typing import NoReturn


PROG = "herdr-recover-after-upgrade.py"


def main() -> NoReturn:
    if os.environ.get("HERDR_ENV") == "1":
        raise SystemExit(
            f"{PROG}: run from a terminal outside Herdr; stopping the server ends its panes"
        )
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise SystemExit(f"{PROG}: an interactive terminal is required")

    herdr = shutil.which("herdr")
    if herdr is None:
        raise SystemExit(f"{PROG}: herdr is not on PATH")

    print(f"{PROG}: stopping the running Herdr server", flush=True)
    stopped = subprocess.run([herdr, "server", "stop"], check=False)
    if stopped.returncode != 0:
        raise SystemExit(stopped.returncode)

    print(f"{PROG}: launching Herdr from this terminal", flush=True)
    os.execv(herdr, [herdr])


if __name__ == "__main__":
    main()
