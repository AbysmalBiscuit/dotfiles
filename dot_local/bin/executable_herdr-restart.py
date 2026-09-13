#!/usr/bin/env python3
"""Stop the Herdr server and start a fresh one in its place.

The replacement restores the saved session: workspaces, tabs, panes, cwd, and
focus. Pane processes do not survive, because live handoff is the only path
that keeps them and it is Unix-only. Attach afterwards with `herdr`.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from typing import NoReturn

PROG = "herdr-restart"
SERVER_START_TIMEOUT = 15.0
SERVER_POLL = 0.1


def die(message: str) -> NoReturn:
    print(f"{PROG}: {message}", file=sys.stderr)
    raise SystemExit(1)


def warn(message: str) -> None:
    print(f"{PROG}: {message}", file=sys.stderr)


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        capture_output=True,
        check=False,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


class Herdr:
    """One run's connection to a Herdr server, default or named."""

    def __init__(self, session: str | None) -> None:
        self.exe = shutil.which("herdr") or die("herdr is not on PATH")
        self.session = session

    def argv(self, *args: str) -> list[str]:
        prefix = ["--session", self.session] if self.session else []
        return [self.exe, *prefix, *args]

    def call(self, *args: str) -> subprocess.CompletedProcess[str]:
        return run(self.argv(*args))

    def running(self) -> bool:
        return "status: running" in self.call("status", "server").stdout

    def update_manifests(self) -> None:
        """Refresh the agent detection manifests the next server will load."""
        done = self.call("server", "update-agent-manifests")
        sys.stdout.write(done.stdout)
        if done.returncode != 0:
            warn(f"manifest update failed: {done.stderr.strip() or 'unknown error'}")

    def stop(self) -> None:
        if not self.running():
            print(f"{PROG}: no server running")
            return
        done = self.call("server", "stop")
        if done.returncode != 0 and self.running():
            die(f"server stop failed: {done.stderr.strip() or done.stdout.strip()}")
        print(f"{PROG}: stopped")

    def start(self) -> None:
        # A restart outlives the terminal that asked for it, so the server is
        # spawned without a console of its own on Windows and in its own
        # session elsewhere.
        creationflags = 0
        if os.name == "nt":
            creationflags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
        subprocess.Popen(
            self.argv("server"),
            start_new_session=True,
            creationflags=creationflags,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + SERVER_START_TIMEOUT
        while time.monotonic() < deadline:
            if self.running():
                workspaces = self.call("workspace", "list").stdout.count('"workspace_id"')
                print(f"{PROG}: started, {workspaces} workspaces restored")
                return
            time.sleep(SERVER_POLL)
        die("the server did not come up in time")


def main() -> int:
    parser = argparse.ArgumentParser(prog=PROG, description=__doc__)
    parser.add_argument("--session", help="restart this named session instead of the default")
    parser.add_argument(
        "-m",
        "--manifests",
        action="store_true",
        help="fetch the latest agent detection manifests before restarting",
    )
    args = parser.parse_args()

    if os.environ.get("HERDR_ENV") == "1" and not args.session:
        die("run from a terminal outside Herdr; stopping the server ends its panes")

    herdr = Herdr(args.session)
    if args.manifests:
        herdr.update_manifests()
    herdr.stop()
    herdr.start()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
