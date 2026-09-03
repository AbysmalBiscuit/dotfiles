#!/usr/bin/env python3
"""This hook runs after `chezmoi apply`.

It does the following:
- Update various cli tools
"""

import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

HAS_FILE = Path.home() / ".config" / "chezmoi" / "has.toml"
TOOLS_FILE = Path(".chezmoidata") / "tools.toml"

REPO = "https://github.com/twpayne/chezmoi"
NOTES = (
    "Matches the installed chezmoi release exactly; "
    "hooks/upgrade_post_docm_pin_chezmoi.py repins it on every chezmoi upgrade."
)
COMMIT_TIMEOUT = 30
VERSION_RE = re.compile(r"^chezmoi version (v\S+?),")


def warn(message: str) -> None:
    print(f"apply-post: {message}", file=sys.stderr)


def load_toml(path: Path) -> dict[str, object] | None:
    try:
        with path.open("rb") as file:
            return tomllib.load(file)
    except (OSError, tomllib.TOMLDecodeError) as error:
        warn(f"could not read {path}: {error}")
        return None


def platform_name() -> str:
    if sys.platform == "win32":
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    return "linux"


def command_key(command: str) -> str:
    return re.sub(r"[-. ]", "_", command)


def tool_is_installed(tool: dict[str, object], installed: dict[str, object]) -> bool:
    commands = tool.get("cmds")
    if not isinstance(commands, list):
        commands = [tool.get("name")]

    return any(
        installed.get(command_key(command)) is True
        for command in commands
        if isinstance(command, str)
    )


def update_command(tool: dict[str, object]) -> list[str] | None:
    table = tool.get("update_command")
    if table is None:
        return None
    if not isinstance(table, dict):
        name = tool.get("name", "unknown tool")
        warn(f"{name} update_command must be a table")
        return None

    platform = platform_name()
    key = platform if platform in table else "default"
    command = table.get(key)
    if command is None or command == []:
        return None
    if not isinstance(command, list):
        name = tool.get("name", "unknown tool")
        warn(f"{name} update_command.{key} must be a string array")
        return None

    arguments: list[str] = []
    for argument in command:
        if not isinstance(argument, str) or not argument.strip():
            name = tool.get("name", "unknown tool")
            warn(f"{name} update_command.{key} must contain only non-empty strings")
            return None
        arguments.append(argument)
    return arguments


def update_cli_tools() -> None:
    installed = load_toml(HAS_FILE)
    config = load_toml(source_dir() / TOOLS_FILE)
    if installed is None or config is None:
        return

    tools = config.get("tools")
    if not isinstance(tools, list):
        warn(f"{source_dir() / TOOLS_FILE} does not contain a tools array")
        return

    for tool in tools:
        if not isinstance(tool, dict) or not tool_is_installed(tool, installed):
            continue

        command = update_command(tool)
        if command is None:
            continue

        name = tool.get("name", "unknown tool")
        try:
            completed = subprocess.run(command, shell=False, check=False)
        except OSError as error:
            warn(f"{name} update could not start: {error}")
            continue
        if completed.returncode != 0:
            warn(f"{name} update failed with exit code {completed.returncode}")


def source_dir() -> Path:
    return Path(
        os.environ.get("CHEZMOI_SOURCE_DIR") or Path(__file__).resolve().parent.parent
    )


def installed_tag(executable: str) -> str | None:
    out = subprocess.run(
        [executable, "--version"], capture_output=True, text=True, check=False
    )
    match = VERSION_RE.match(out.stdout.strip())
    return match.group(1) if match else None


def run(
    args: list[str], cwd: Path, timeout: int | None = None
) -> subprocess.CompletedProcess:
    return subprocess.run(
        args, cwd=cwd, capture_output=True, text=True, check=False, timeout=timeout
    )


def main() -> int:
    update_cli_tools()

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
        [
            "docm",
            "add",
            "chezmoi",
            "--project",
            "--eco",
            "git",
            "--repo",
            REPO,
            "--ref",
            tag,
            "--notes",
            NOTES,
        ],
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
            [
                "git",
                "commit",
                "--only",
                "devkit.toml",
                "-m",
                f"chore(devkit): pin chezmoi docs to {tag}",
            ],
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
