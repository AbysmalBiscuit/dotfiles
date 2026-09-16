import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
LAUNCHER = REPO / "dot_local/bin/executable_chezmoi-agents"

pytestmark = pytest.mark.skipif(os.name == "nt", reason="fake agent CLIs are sh scripts")


def fake_agents(tmp_path: Path, failing: str = "") -> tuple[dict[str, str], Path]:
    log = tmp_path / "calls.log"
    binary = tmp_path / "bin"
    binary.mkdir()
    for name in ("claude", "codex"):
        script = binary / name
        script.write_text(
            f'#!/bin/sh\necho "{name} $*" >> "{log}"\n'
            f'[ "{name} $*" = "{failing}" ] && exit 3\nexit 0\n'
        )
        script.chmod(0o755)
    # Only the fakes are reachable, so the real CLIs never run.
    return {**os.environ, "PATH": str(binary)}, log


def update(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(LAUNCHER), "plugins", "update"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_update_refreshes_marketplace_then_reinstalls_each_plugin(tmp_path):
    env, log = fake_agents(tmp_path)

    result = update(env)

    assert result.returncode == 0, result.stderr
    assert log.read_text().splitlines() == [
        "claude plugin marketplace update devkit",
        "claude plugin update devkit@devkit",
        "claude plugin marketplace update mcpls",
        "claude plugin update mcpls@mcpls",
        "claude plugin marketplace update superpowers-marketplace",
        "claude plugin update superpowers@superpowers-marketplace",
        "codex plugin marketplace upgrade devkit",
        "codex plugin remove devkit@devkit",
        "codex plugin add devkit@devkit",
        "codex plugin marketplace upgrade mcpls",
        "codex plugin remove mcpls@mcpls",
        "codex plugin add mcpls@mcpls",
        "codex plugin marketplace upgrade superpowers-marketplace",
        "codex plugin remove superpowers@superpowers-marketplace",
        "codex plugin add superpowers@superpowers-marketplace",
    ]


def test_failed_codex_marketplace_upgrade_keeps_the_installed_plugin(tmp_path):
    env, log = fake_agents(tmp_path, failing="codex plugin marketplace upgrade mcpls")

    result = update(env)

    calls = log.read_text().splitlines()
    assert result.returncode == 3
    assert "codex plugin remove mcpls@mcpls" not in calls
    assert "codex plugin add superpowers@superpowers-marketplace" in calls
