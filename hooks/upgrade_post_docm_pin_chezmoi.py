#!/usr/bin/env python3
"""Repin devkit's chezmoi docs checkout to the chezmoi release that is installed.

Runs as chezmoi's `hooks.upgrade.post`. chezmoi replaces its own executable in
place, so $CHEZMOI_EXECUTABLE resolves to the new binary while
$CHEZMOI_VERSION_VERSION still holds the version that was running when the
upgrade started.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = "https://github.com/twpayne/chezmoi"
NOTES = (
    "Matches the installed chezmoi release exactly; "
    "hooks/upgrade_post_docm_pin_chezmoi.py repins it on every chezmoi upgrade."
)
COMMIT_TIMEOUT = 30
VERSION_RE = re.compile(r"^chezmoi version (v\S+?),")


def warn(message: str) -> None:
    print(f"pin-chezmoi-docs: {message}", file=sys.stderr)


def source_dir() -> Path:
    return Path(os.environ.get("CHEZMOI_SOURCE_DIR") or Path(__file__).resolve().parent.parent)


def installed_tag(executable: str) -> str | None:
    out = subprocess.run([executable, "--version"], capture_output=True, text=True, check=False)
    match = VERSION_RE.match(out.stdout.strip())
    return match.group(1) if match else None


def run(args: list[str], cwd: Path, timeout: int | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=False, timeout=timeout)


def main() -> int:
    executable = os.environ.get("CHEZMOI_EXECUTABLE") or shutil.which("chezmoi")
    if not executable:
        warn("no chezmoi executable found")
        return 0

    tag = installed_tag(executable)
    if not tag:
        warn(f"could not parse a version tag out of `{executable} --version`")
        return 0

    if tag == os.environ.get("CHEZMOI_VERSION_VERSION"):
        return 0

    if not shutil.which("docm"):
        warn("docm is not installed")
        return 0

    src = source_dir()
    added = run(
        ["docm", "add", "chezmoi", "--project", "--eco", "git",
         "--repo", REPO, "--ref", tag, "--notes", NOTES],
        cwd=src,
    )
    if added.returncode != 0:
        warn(f"docm add failed: {added.stderr.strip()}")
        return 0

    synced = run(["docm", "sync", "chezmoi"], cwd=src)
    if synced.returncode != 0:
        warn(f"docm sync failed: {synced.stderr.strip()}")

    if run(["git", "diff", "--quiet", "--", "devkit.toml"], cwd=src).returncode == 0:
        return 0

    try:
        committed = run(
            ["git", "commit", "--only", "devkit.toml",
             "-m", f"chore(devkit): pin chezmoi docs to {tag}"],
            cwd=src,
            timeout=COMMIT_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        warn(f"git commit timed out after {COMMIT_TIMEOUT}s; is the gpg agent locked?")
        return 0
    if committed.returncode != 0:
        warn(f"git commit failed: {committed.stderr.strip()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
