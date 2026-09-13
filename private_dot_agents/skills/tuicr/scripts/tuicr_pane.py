#!/usr/bin/env python3
"""Open tuicr in a pane of the current multiplexer, wait for it to exit, then close the pane.

Supports tmux, zellij, Herdr and cmux, detected from $TMUX, $ZELLIJ, $HERDR_ENV=1 and $CMUX_WORKSPACE_ID.

Environment:
  TUICR_PANE_DIRECTION  tmux: up|down, zellij: stacked|down|right, herdr: right|down, cmux: right|left|up|down (first is the default)
  TUICR_PANE_SIZE       tmux pane height in percent of the window (default: 80)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Callable

DIRECTIONS = {
    "tmux": ("up", "down"),
    "zellij": ("stacked", "down", "right"),
    "herdr": ("right", "down"),
    "cmux": ("right", "left", "up", "down"),
}

HERDR_START_TIMEOUT_SECONDS = 15


def log(message: str) -> None:
    print(f"[tuicr] {message}", flush=True)


def run(*argv: str) -> str:
    return subprocess.run(argv, check=True, capture_output=True, text=True).stdout


def succeeds(*argv: str) -> bool:
    return subprocess.run(argv, capture_output=True).returncode == 0


def detect_mux() -> str | None:
    found = [
        name
        for name, present in (
            ("tmux", bool(os.environ.get("TMUX"))),
            ("zellij", bool(os.environ.get("ZELLIJ"))),
            ("herdr", os.environ.get("HERDR_ENV") == "1"),
            ("cmux", bool(os.environ.get("CMUX_WORKSPACE_ID"))),
        )
        if present
    ]
    # cmux is a GUI terminal app, so any other multiplexer found runs inside it.
    if len(found) > 1 and "cmux" in found:
        found.remove("cmux")
    if len(found) > 1:
        sys.exit(f"Found several multiplexers ({', '.join(found)}) and cannot tell which is innermost. Pass --mux with the one this agent runs in.")
    return found[0] if found else None


def is_repo(path: str) -> bool:
    if shutil.which("git") and succeeds("git", "-C", path, "rev-parse", "--git-dir"):
        return True
    return bool(shutil.which("jj")) and succeeds("jj", "--repository", path, "--ignore-working-copy", "root")


def pane_direction(mux: str) -> str:
    allowed = DIRECTIONS[mux]
    direction = os.environ.get("TUICR_PANE_DIRECTION", allowed[0])
    if direction not in allowed:
        log(f"Unknown TUICR_PANE_DIRECTION '{direction}' for {mux}; using '{allowed[0]}'")
        return allowed[0]
    return direction


def wait_for_file(path: Path) -> None:
    while not path.exists():
        time.sleep(0.5)


def open_tmux(repo: str, tuicr: str, args: list[str], direction: str) -> None:
    height = int(run("tmux", "display-message", "-p", "#{window_height}"))
    lines = height * int(os.environ.get("TUICR_PANE_SIZE", "80")) // 100
    channel = f"tuicr-{os.getpid()}"
    command = f"cd {shlex.quote(repo)} && {shlex.join([tuicr, *args])}; tmux wait-for -S {channel}"
    above = ["-b"] if direction == "up" else []
    pane = run("tmux", "split-window", "-d", "-P", "-F", "#{pane_id}", *above, "-l", str(lines), "-c", repo, command).strip()
    run("tmux", "select-pane", "-t", pane)
    log(f"tuicr is running in tmux pane {pane}")
    run("tmux", "wait-for", channel)


def open_zellij(repo: str, tuicr: str, args: list[str], direction: str) -> None:
    with tempfile.TemporaryDirectory(prefix="tuicr-") as tmp:
        done = Path(tmp) / "done"
        script = f"cd {shlex.quote(repo)} && {shlex.join([tuicr, *args])}; echo done > {shlex.quote(str(done))}"
        placement = ["--stacked"] if direction == "stacked" else ["--direction", direction]
        run("zellij", "run", "--close-on-exit", "--name", "tuicr", *placement, "--", "sh", "-c", script)
        log("tuicr is running in a zellij pane")
        wait_for_file(done)


def open_cmux(repo: str, tuicr: str, args: list[str], direction: str) -> None:
    created = run("cmux", "new-pane", "--type", "terminal", "--direction", direction, "--focus", "true")
    match = re.search(r"surface:\d+", created)
    if not match:
        sys.exit(f"Could not read the new surface id from cmux: {created}")
    surface = match.group()
    with tempfile.TemporaryDirectory(prefix="tuicr-") as tmp:
        done = Path(tmp) / "done"
        # The pane runs the user's login shell; this line parses the same in bash, zsh and fish.
        line = f"cd {shlex.quote(repo)} && {shlex.join([tuicr, *args])}; true > {shlex.quote(str(done))}; exit\n"
        run("cmux", "send", "--surface", surface, line)
        log(f"tuicr is running in cmux {surface}; force-close it with: cmux close-surface --surface {surface}")
        wait_for_file(done)


# Characters every pane shell (nushell, PowerShell, bash, zsh, fish) reads as part of a plain word.
BARE_WORD = re.compile(r"[\w./:+-]+")


def herdr_command_line(args: list[str]) -> str:
    words = ["tuicr"]
    for arg in args:
        if BARE_WORD.fullmatch(arg):
            words.append(arg)
        elif "'" in arg:
            sys.exit(f"A Herdr pane shell may not be POSIX, so tuicr arguments cannot contain a single quote: {arg}")
        else:
            # Single quotes are literal in nushell, PowerShell and POSIX shells alike.
            words.append(f"'{arg}'")
    return " ".join(words)


def is_tuicr(process_name: str) -> bool:
    return Path(process_name).stem.lower() == "tuicr"


def herdr_pane_runs_tuicr(herdr: str, pane: str) -> bool | None:
    """Whether tuicr runs in the pane's shell, or None once the pane is gone."""
    result = subprocess.run([herdr, "pane", "process-info", "--pane", pane], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    info = json.loads(result.stdout)["result"]["process_info"]
    if any(is_tuicr(process["name"]) for process in info["foreground_processes"]):
        return True
    if os.name != "nt":
        return False
    # Herdr on Windows lists only the shell as the foreground process, so look for tuicr among the shell's children.
    children = run("powershell", "-NoProfile", "-Command", f"(Get-CimInstance Win32_Process -Filter ParentProcessId={info['shell_pid']}).Name")
    return any(is_tuicr(name) for name in children.split())


def open_herdr(repo: str, tuicr: str, args: list[str], direction: str) -> None:
    herdr = shutil.which("herdr") or sys.exit("herdr not found on PATH")
    split = json.loads(run(herdr, "pane", "split", "--current", "--direction", direction, "--cwd", repo, "--focus"))
    pane = split["result"]["pane"]["pane_id"]
    try:
        # `pane run` types into the pane's interactive shell, which finds tuicr on its own PATH.
        run(herdr, "pane", "run", pane, herdr_command_line(args))
        deadline = time.monotonic() + HERDR_START_TIMEOUT_SECONDS
        while not herdr_pane_runs_tuicr(herdr, pane):
            if time.monotonic() > deadline:
                output = subprocess.run([herdr, "pane", "read", pane, "--source", "recent", "--lines", "20"], capture_output=True, text=True).stdout
                sys.exit(f"tuicr did not start in Herdr pane {pane}. Pane output:\n{output}")
            time.sleep(0.5)
        log(f"tuicr is running in Herdr pane {pane}")
        while herdr_pane_runs_tuicr(herdr, pane):
            time.sleep(1)
    finally:
        subprocess.run([herdr, "pane", "close", pane], capture_output=True)


OPENERS: dict[str, Callable[[str, str, list[str], str], None]] = {
    "tmux": open_tmux,
    "zellij": open_zellij,
    "herdr": open_herdr,
    "cmux": open_cmux,
}


def main() -> None:
    argv = sys.argv[1:]
    separator = argv.index("--") if "--" in argv else len(argv)
    parser = argparse.ArgumentParser(
        usage="%(prog)s [--mux NAME] [repo] -- <tuicr args>",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("repo", nargs="?", default=".", help="git or jj repository to review (default: current directory)")
    parser.add_argument("--mux", choices=OPENERS, help="multiplexer to use instead of detecting it")
    options = parser.parse_args(argv[:separator])
    tuicr_args = argv[separator + 1 :]

    tuicr = shutil.which("tuicr") or sys.exit("tuicr not found on PATH. Install it first.")
    repo = os.path.abspath(options.repo)
    if not os.path.isdir(repo):
        sys.exit(f"Directory not found: {repo}")
    if not is_repo(repo):
        sys.exit(f"Not a git or jj repository: {repo}")

    mux = options.mux or detect_mux()
    if mux is None:
        command = shlex.join(["tuicr", *tuicr_args])
        sys.exit(f"No multiplexer found ($TMUX, $ZELLIJ, $HERDR_ENV, $CMUX_WORKSPACE_ID are unset). Ask the user to run `{command}` in {repo}, then attach with `tuicr review list --repo {repo}`.")

    direction = pane_direction(mux)
    log(f"Opening tuicr in a {mux} pane ({direction}) at {repo}")
    try:
        OPENERS[mux](repo, tuicr, tuicr_args, direction)
    except subprocess.CalledProcessError as error:
        sys.exit(f"{shlex.join(error.cmd)} failed with exit {error.returncode}: {(error.stderr or '').strip()}")
    except KeyboardInterrupt:
        sys.exit(130)
    log(f"tuicr exited. Read the review with: tuicr review comments --repo {repo} --session <slug>")


if __name__ == "__main__":
    main()
