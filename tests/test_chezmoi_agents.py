import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
LAUNCHER = REPO / "dot_local/bin/executable_chezmoi-agents"

# The harness update commands come from the tool inventory, so these assertions
# also cover tools.toml still declaring one for each agent CLI.
HARNESS_CALLS = [
    "claude upgrade",
    "codex update",
]

PLUGIN_CALLS = [
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

pytestmark = pytest.mark.skipif(os.name == "nt", reason="fake agent CLIs are sh scripts")


def fake_agents(
    tmp_path: Path,
    failing: str = "",
    names: tuple[str, ...] = ("claude", "codex"),
) -> tuple[dict[str, str], Path]:
    log = tmp_path / "calls.log"
    binary = tmp_path / "bin"
    binary.mkdir()
    for name in names:
        script = binary / name
        script.write_text(
            f'#!/bin/sh\necho "{name} $*" >> "{log}"\n'
            f'[ "{name} $*" = "{failing}" ] && exit 3\nexit 0\n'
        )
        script.chmod(0o755)
    log.touch()
    # Only the fakes are reachable, so the real CLIs never run, which also puts
    # chezmoi itself out of reach: the source directory has to come from the env.
    env = {**os.environ, "PATH": str(binary), "CHEZMOI_SOURCE_DIR": str(REPO)}
    return env, log


def launch(env: dict[str, str], *argv: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(LAUNCHER), *argv],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_update_refreshes_marketplace_then_reinstalls_each_plugin(tmp_path):
    env, log = fake_agents(tmp_path)

    result = launch(env, "plugins", "update")

    assert result.returncode == 0, result.stderr
    assert log.read_text().splitlines() == PLUGIN_CALLS


def test_failed_codex_marketplace_upgrade_keeps_the_installed_plugin(tmp_path):
    env, log = fake_agents(tmp_path, failing="codex plugin marketplace upgrade mcpls")

    result = launch(env, "plugins", "update")

    calls = log.read_text().splitlines()
    assert result.returncode == 3
    assert "codex plugin remove mcpls@mcpls" not in calls
    assert "codex plugin add superpowers@superpowers-marketplace" in calls


def test_update_upgrades_every_harness_before_touching_plugins(tmp_path):
    env, log = fake_agents(tmp_path)

    result = launch(env, "update")

    assert result.returncode == 0, result.stderr
    assert log.read_text().splitlines() == HARNESS_CALLS + PLUGIN_CALLS


def test_update_refreshes_plugins_even_when_a_harness_upgrade_fails(tmp_path):
    env, log = fake_agents(tmp_path, failing="claude upgrade")

    result = launch(env, "update")

    assert result.returncode == 3
    assert log.read_text().splitlines() == HARNESS_CALLS + PLUGIN_CALLS


def test_update_skips_an_agent_cli_that_is_not_installed(tmp_path):
    env, log = fake_agents(tmp_path, names=("claude",))

    result = launch(env, "update")

    calls = log.read_text().splitlines()
    assert result.returncode == 0, result.stderr
    assert not [call for call in calls if call.startswith("codex")]
    assert calls[0] == "claude upgrade"
