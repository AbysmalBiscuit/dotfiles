#!/usr/bin/env python3
"""Run every *.test.py against a copy of the plugin under its installed names.

The tests and agent_guard.py find sibling directories by installed name, which
the chezmoi source spells with exact_ and dot_ prefixes. The installed plugin
has none, so the same command works in both places.
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PLUGIN = Path(__file__).resolve().parent.parent


def installed_name(source_name: str) -> str:
    name = source_name.removeprefix("exact_")
    return "." + name.removeprefix("dot_") if name.startswith("dot_") else name


def lay_out(destination: Path) -> None:
    for entry in PLUGIN.iterdir():
        target = destination / installed_name(entry.name)
        if entry.is_dir():
            shutil.copytree(entry, target, ignore=shutil.ignore_patterns("__pycache__"))
        else:
            shutil.copy2(entry, target)


def main() -> int:
    failed: list[str] = []
    with tempfile.TemporaryDirectory(prefix="agent-guard-tests-") as base:
        plugin = Path(base)
        lay_out(plugin)
        for test in sorted((plugin / "tests").glob("*.test.py")):
            print(f"== {test.name}", flush=True)
            if subprocess.run([sys.executable, str(test)], check=False).returncode:
                failed.append(test.name)

    print(f"\n{len(failed)} failed" + (f": {', '.join(failed)}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
