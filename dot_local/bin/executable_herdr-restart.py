#!/usr/bin/env python3
"""Stop the Herdr server and launch it again from the current terminal."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

PROG = "herdr-restart"

STATUS_LINE = re.compile(r"^(?P<name>[a-z0-9-]+):\s+(?P<state>.+?)\s+\(")


def fail(message: str) -> NoReturn:
    raise SystemExit(f"{PROG}: {message}")


def herdr(exe: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([exe, *args], capture_output=True, text=True, check=False)


def server_running(exe: str) -> bool:
    result = herdr(exe, "status", "server")
    return "status: running" in result.stdout


def stop_server(exe: str) -> None:
    if not server_running(exe):
        print(f"{PROG}: no server running", flush=True)
        return
    print(f"{PROG}: stopping the running server", flush=True)
    result = herdr(exe, "server", "stop")
    if result.returncode != 0 and server_running(exe):
        fail(f"server stop failed: {result.stderr.strip() or result.stdout.strip()}")


def installed_integrations(exe: str) -> list[str]:
    result = herdr(exe, "integration", "status")
    if result.returncode != 0:
        fail(f"integration status failed: {result.stderr.strip()}")
    names = []
    for line in result.stdout.splitlines():
        match = STATUS_LINE.match(line.strip())
        if match and not match["state"].startswith("not installed"):
            names.append(match["name"])
    return names


def refresh_integrations(exe: str) -> None:
    names = installed_integrations(exe)
    if not names:
        print(f"{PROG}: no agent manifests installed", flush=True)
        return
    print(f"{PROG}: refreshing agent manifests: {', '.join(names)}", flush=True)
    for name in names:
        result = herdr(exe, "integration", "install", name)
        if result.returncode != 0:
            print(
                f"{PROG}: {name}: {result.stderr.strip() or result.stdout.strip()}",
                file=sys.stderr,
            )
            continue
        if name == "codex":
            # Codex hooks are declared in config.toml, so the generated
            # hooks.json would shadow them.
            codex_home = Path(os.environ.get("CODEX_HOME") or "~/.codex").expanduser()
            (codex_home / "hooks.json").unlink(missing_ok=True)

    skill = herdr(exe, "--skill")
    if skill.returncode == 0:
        skill_file = Path.home() / ".agents" / "skills" / "herdr" / "SKILL.md"
        skill_file.parent.mkdir(parents=True, exist_ok=True)
        skill_file.write_text(skill.stdout, encoding="utf-8")


def main() -> NoReturn:
    parser = argparse.ArgumentParser(prog=PROG, description=__doc__)
    parser.add_argument(
        "-i",
        "--integrations",
        action="store_true",
        help="reinstall the installed agent-state manifests and skill while stopped",
    )
    args = parser.parse_args()

    if os.environ.get("HERDR_ENV") == "1":
        fail("run from a terminal outside Herdr; stopping the server ends its panes")
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        fail("an interactive terminal is required")

    exe = shutil.which("herdr")
    if exe is None:
        fail("herdr is not on PATH")

    stop_server(exe)
    if args.integrations:
        refresh_integrations(exe)

    print(f"{PROG}: launching Herdr from this terminal", flush=True)
    os.execv(exe, [exe])


if __name__ == "__main__":
    main()
