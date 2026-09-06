"""Shared helpers for the chezmoi-* plugin scripts beside this module.

chezmoi runs `chezmoi <name>` by looking for `chezmoi-<name>` on PATH, so those
scripts carry no extension and cannot be imported from each other. Python puts a
script's own directory first on sys.path, which is what makes this module
importable from all of them.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable

# How to run a rendered chezmoi script, keyed by the extension its template
# carries in .chezmoiscripts. -NonInteractive is deliberately absent: the secrets
# template opens an editor.
INTERPRETERS: dict[str, list[str]] = {
    ".ps1": ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"],
    ".sh": ["sh"],
}

SCRIPT_SUFFIX = ".ps1" if os.name == "nt" else ".sh"


class PluginError(Exception):
    """A failure worth reporting as a message rather than a traceback."""


def source_dir() -> Path:
    """Locate the chezmoi source directory.

    chezmoi exports CHEZMOI_SOURCE_DIR before dispatching a plugin, so the
    subprocess is only reached when a script is run under its own name.
    """
    if env := os.environ.get("CHEZMOI_SOURCE_DIR"):
        return Path(env)
    try:
        result = subprocess.run(
            ["chezmoi", "source-path"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as err:
        raise PluginError("cannot locate the chezmoi source directory") from err
    return Path(result.stdout.strip())


def render(template: Path) -> str:
    """Return a source template with its chezmoi template actions expanded."""
    if not template.is_file():
        raise PluginError(f"{template}: not found")
    result = subprocess.run(
        ["chezmoi", "execute-template"],
        input=template.read_text(encoding="utf-8"),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise PluginError(f"{template.name}: {result.stderr.strip()}")
    return result.stdout


def run_rendered(body: str, suffix: str = SCRIPT_SUFFIX) -> int:
    """Run a rendered chezmoi script from a temp file, returning its exit code."""
    interpreter = INTERPRETERS.get(suffix)
    if interpreter is None:
        raise PluginError(f"{suffix}: no interpreter for a rendered script")
    with tempfile.TemporaryDirectory() as directory:
        script = Path(directory) / f"chezmoi-plugin{suffix}"
        script.write_text(body, encoding="utf-8")
        return subprocess.run([*interpreter, str(script)], check=False).returncode


def chezmoi_init() -> int:
    """Regenerate the config file, which most rendered scripts feed data to."""
    return subprocess.run(["chezmoi", "init"], check=False).returncode


def run(entry_point: Callable[[], int]) -> int:
    """Report a PluginError as a message instead of letting it reach the top."""
    try:
        return entry_point()
    except PluginError as err:
        print(err, file=sys.stderr)
        return 1
