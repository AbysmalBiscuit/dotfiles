#!/usr/bin/env python3
"""Download the Herdr preview for `chezmoi tools update herdr` without restarting."""

from __future__ import annotations

import hashlib
import json
import platform
import shutil
import stat
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

MANIFEST_URL = "https://herdr.dev/preview.json"
DOWNLOAD_TIMEOUT = 120
WINDOWS_FILES = (
    "herdr.exe",
    "conpty/conpty.dll",
    "conpty/x64/OpenConsole.exe",
    "conpty/arm64/OpenConsole.exe",
    "conpty/herdr-conpty.json",
)


def platform_target() -> str:
    system = {"Linux": "linux", "Darwin": "macos", "Windows": "windows"}.get(platform.system())
    machine = platform.machine().lower()
    architecture = {
        "amd64": "x86_64",
        "x86_64": "x86_64",
        "arm64": "aarch64",
        "aarch64": "aarch64",
    }.get(machine)
    if system is None or architecture is None:
        raise ValueError(f"unsupported platform: {platform.system()} {machine}")
    # Herdr ships an x86_64 Windows build for both native and ARM64 emulation.
    if system == "windows":
        architecture = "x86_64"
    return f"{system}-{architecture}"


def sha256(path: Path) -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def preview_asset(target: str) -> tuple[str, str]:
    request = urllib.request.Request(  # noqa: S310
        MANIFEST_URL, headers={"User-Agent": "chezmoi-herdr-update"}
    )
    with urllib.request.urlopen(request, timeout=DOWNLOAD_TIMEOUT) as response:  # noqa: S310
        manifest = json.load(response)
    if manifest["channel"] != "preview":
        raise ValueError("the preview manifest does not describe a preview release")
    asset = manifest["assets"].get(target)
    if asset is None:
        raise ValueError(f"no preview binary for {target}")
    url, checksum = asset["url"], asset["sha256"]
    if not isinstance(url, str) or not url.startswith(
        "https://github.com/herdrdev/herdr/releases/download/"
    ):
        raise ValueError("unexpected preview download URL")
    if (
        not isinstance(checksum, str)
        or len(checksum) != 64
        or any(c not in "0123456789abcdef" for c in checksum)
    ):
        raise ValueError("missing or invalid preview SHA-256")
    return url, checksum


def extract_windows(archive: Path, staging: Path) -> None:
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            relative = PurePosixPath(member.filename)
            if (
                relative.is_absolute()
                or ".." in relative.parts
                or "\\" in member.filename
                or ":" in member.filename
            ):
                raise ValueError(f"unsafe archive path: {member.filename}")
            if stat.S_ISLNK(member.external_attr >> 16):
                raise ValueError(f"archive contains a symlink: {member.filename}")
            if member.is_dir():
                continue
            if member.filename != "herdr.exe" and relative.parts[0] not in {
                "conpty",
                "THIRD-PARTY-NOTICES",
            }:
                continue
            destination = staging / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with package.open(member) as source, destination.open("wb") as output:
                shutil.copyfileobj(source, output)
    for relative in WINDOWS_FILES:
        if not (staging / relative).is_file():
            raise ValueError(f"Windows preview is missing {relative}")


def backup_name(target: Path) -> Path:
    backup = target.with_name(f"{target.stem}_old{target.suffix}")
    number = 0
    while backup.exists() or backup.is_symlink():
        number += 1
        backup = target.with_name(f"{target.stem}_old_{number}{target.suffix}")
    return backup


def payload_hashes(path: Path) -> dict[str, str]:
    if path.is_file():
        return {".": sha256(path)}
    return {
        file.relative_to(path).as_posix(): sha256(file)
        for file in path.rglob("*")
        if file.is_file()
    }


def install(staging: Path, executable: Path) -> bool:
    # Herdr rejects extra files inside conpty, so its backup stays outside it.
    sources = sorted(staging.iterdir())
    # Publish the executable after its companion files are in place.
    sources.sort(key=lambda path: path.name == executable.name)
    changes: list[tuple[Path, Path | None]] = []
    try:
        for source in sources:
            target = executable.parent / source.relative_to(staging)
            if target.exists() and payload_hashes(target) == payload_hashes(source):
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            backup = backup_name(target) if target.exists() else None
            if backup is not None:
                target.rename(backup)
            changes.append((target, backup))
            source.rename(target)
    except OSError:
        for target, backup in reversed(changes):
            if target.is_dir():
                shutil.rmtree(target)
            else:
                target.unlink(missing_ok=True)
            if backup is not None:
                backup.rename(target)
        raise
    for target, backup in changes:
        if backup is not None:
            print(f"herdr-update: kept {target.name} as {backup}")
    return bool(changes)


def update(executable: Path) -> None:
    target = platform_target()
    windows = target.startswith("windows-")
    url, checksum = preview_asset(target)
    if not windows and sha256(executable) == checksum:
        print("herdr-update: latest preview already installed")
        return
    with tempfile.TemporaryDirectory(prefix=".herdr-update-", dir=executable.parent) as temporary:
        directory = Path(temporary)
        archive = directory / "download"
        request = urllib.request.Request(  # noqa: S310
            url, headers={"User-Agent": "chezmoi-herdr-update"}
        )
        with (
            urllib.request.urlopen(request, timeout=DOWNLOAD_TIMEOUT) as source,  # noqa: S310
            archive.open("wb") as output,
        ):
            shutil.copyfileobj(source, output)
        if sha256(archive) != checksum:
            raise ValueError("downloaded preview failed SHA-256 verification")
        staging = directory / "staging"
        staging.mkdir()
        if windows:
            extract_windows(archive, staging)
        else:
            archive.rename(staging / executable.name)
            (staging / executable.name).chmod(0o755)
        if install(staging, executable):
            print("herdr-update: preview installed; run herdr-restart when ready")
        else:
            print("herdr-update: latest preview already installed")


def main() -> int:
    found = shutil.which("herdr")
    if found is None:
        print("herdr-update: herdr is not on PATH", file=sys.stderr)
        return 1
    try:
        executable = Path(found).resolve()
        lock = executable.parent / ".herdr-update.lock"
        try:
            lock.mkdir()
        except FileExistsError:
            raise ValueError(
                f"another update holds {lock}; remove it only if that updater has exited"
            ) from None
        try:
            update(executable)
        finally:
            lock.rmdir()
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
        print(f"herdr-update: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
