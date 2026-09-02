"""Locate the source tree from inside a chezmoi modify script.

chezmoi runs modify scripts from a temp copy with no working directory set,
so neither __file__ nor cwd points anywhere useful. The CHEZMOI_* variables
are the reliable answer; the ancestor walk covers running --check by hand.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Paths:
    source_root: Path
    script_dir: Path
    target_root: Path


def resolve(script_file: str) -> Paths:
    source_dir = os.environ.get("CHEZMOI_SOURCE_DIR")
    source_file = os.environ.get("CHEZMOI_SOURCE_FILE")

    if source_dir and source_file:
        source_root = Path(source_dir)
        script_dir = source_root / Path(source_file).parent
    else:
        script_path = Path(script_file).resolve()
        source_root = _walk_to_agentcfg(script_path)
        script_dir = script_path.parent

    dest_dir = os.environ.get("CHEZMOI_DEST_DIR")
    target_root = Path(dest_dir) if dest_dir else Path.home()

    return Paths(source_root=source_root, script_dir=script_dir, target_root=target_root)


def _walk_to_agentcfg(script_path: Path) -> Path:
    for candidate in script_path.parents:
        if (candidate / ".agentcfg").is_dir():
            return candidate
    raise RuntimeError(
        f"no .agentcfg ancestor of {script_path}; set CHEZMOI_SOURCE_DIR "
        "and CHEZMOI_SOURCE_FILE to run outside chezmoi"
    )
