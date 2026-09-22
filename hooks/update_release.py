#!/usr/bin/env python3
"""Install devkit or mcpls release binaries for the chezmoi tools updater."""

from __future__ import annotations

import argparse
import filecmp
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

DEVKIT_ALIASES = ("devrun", "docm", "issue", "lockm", "portm", "devrules", "devkit-mcp")
VERSION = re.compile(r"v?(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?")


def version_key(version: str) -> tuple[int, int, int, bool]:
    match = VERSION.fullmatch(version)
    if match is None:
        raise ValueError(f"cannot determine version from {version!r}; refusing to replace binary")
    return int(match[1]), int(match[2]), int(match[3]), match[4] is None


def release_tag(tool: str, installed: str | None) -> str | None:
    api = f"https://api.github.com/repos/AbysmalBiscuit/{tool}/releases/latest"
    with urllib.request.urlopen(api, timeout=120) as response:  # noqa: S310
        release = json.load(response)
    tag = release["tag_name"]
    latest = version_key(tag)
    if installed:
        result = subprocess.run(
            [installed, "--version"], capture_output=True, text=True, check=False, timeout=30
        )
        match = re.match(rf"^{tool}\s+(\S+)", result.stdout.strip())
        if result.returncode or match is None:
            raise ValueError(f"cannot determine installed {tool} version; refusing to replace it")
        if version_key(match[1]) >= latest:
            print(f"{tool}: keeping installed {match[1]}; latest release is {tag}")
            return None
    return tag


def replace_binary(source: Path, target: Path) -> None:
    if target.is_file() and filecmp.cmp(source, target, shallow=False):
        return
    try:
        source.replace(target)
    except PermissionError:
        backup = target.with_name(f"{target.stem}_old{target.suffix}")
        number = 0
        while backup.exists():
            number += 1
            backup = target.with_name(f"{target.stem}_old_{number}{target.suffix}")
        target.rename(backup)
        try:
            source.replace(target)
        except OSError:
            backup.rename(target)
            raise
        print(f"kept running binary at {backup}")


def update(tool: str) -> int:
    installed = shutil.which(tool)
    tag = release_tag(tool, installed)
    if tag is None:
        return 0
    destination = (
        Path(installed).resolve().parent
        if installed
        else Path(os.environ.get("CARGO_HOME", str(Path.home() / ".cargo"))) / "bin"
    )
    destination.mkdir(parents=True, exist_ok=True)
    windows = os.name == "nt"
    extension = "ps1" if windows else "sh"
    engine = (shutil.which("pwsh") or shutil.which("powershell")) if windows else shutil.which("sh")
    if engine is None:
        raise ValueError(f"no interpreter for the {extension} release installer")
    url = (
        f"https://github.com/AbysmalBiscuit/{tool}/releases/download/"
        f"{tag}/{tool}-installer.{extension}"
    )
    with tempfile.TemporaryDirectory(prefix=f".{tool}-update-", dir=destination) as temporary:
        staging = Path(temporary)
        installer = staging / f"installer.{extension}"
        with urllib.request.urlopen(url, timeout=120) as response:  # noqa: S310
            installer.write_bytes(response.read())
        payload = staging / "bin"
        env = dict(os.environ)
        env.pop(f"{tool.upper()}_INSTALL_DIR", None)
        env.pop("CARGO_DIST_FORCE_INSTALL_DIR", None)
        env[f"{tool.upper()}_UNMANAGED_INSTALL"] = str(payload)
        env[f"{tool.upper()}_NO_MODIFY_PATH"] = "1"
        command = (
            [engine, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"]
            if windows
            else [engine]
        )
        result = subprocess.run([*command, str(installer)], env=env, check=False)
        if result.returncode:
            return result.returncode
        suffix = ".exe" if windows else ""
        executable = payload / (tool + suffix)
        if not executable.is_file():
            raise ValueError(f"release installer did not produce {executable.name}")
        if tool == "devkit":
            if not (payload / ("devkitd" + suffix)).is_file():
                raise ValueError("release installer did not produce devkitd")
            for name in DEVKIT_ALIASES:
                alias = payload / (name + suffix)
                if not alias.exists():
                    alias.hardlink_to(executable)
        for binary in sorted(payload.iterdir()):
            replace_binary(binary, destination / binary.name)
    print(f"{tool}: release binaries installed; restart agent sessions to load them")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", choices=("devkit", "mcpls"))
    args = parser.parse_args()
    try:
        return update(args.tool)
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(f"{args.tool}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
