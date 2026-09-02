#!/usr/bin/env python3
"""chezmoi modify script for ~/.codex/config.toml.

Reads the live file on stdin, merges .config.baseline.toml into it under
.config.rules.toml, writes the result to stdout. See
.superpowers/specs/2026-09-01-agent-config-merge-design.md.

Runs as a plain script rather than a Go template because its text does not
match modifyTemplateRx in internal/chezmoi/sourcestate.go.
"""

import os
import sys

sys.dont_write_bytecode = True  # chezmoi diff must not dirty the source tree

from pathlib import Path  # noqa: E402


def _source_root() -> Path:
    env = os.environ.get("CHEZMOI_SOURCE_DIR")
    if env:
        return Path(env)
    for candidate in Path(__file__).resolve().parents:
        if (candidate / ".agentcfg").is_dir():
            return candidate
    raise RuntimeError("cannot locate .agentcfg; set CHEZMOI_SOURCE_DIR")


sys.path.insert(0, str(_source_root() / ".agentcfg"))

from engine.cli import run  # noqa: E402  must follow the sys.path insert
from engine.codecs import TomlCodec  # noqa: E402

if __name__ == "__main__":
    sys.exit(
        run(
            script_file=__file__,
            baseline_name=".config.baseline.toml",
            rules_name=".config.rules.toml",
            codec=TomlCodec,
        )
    )
