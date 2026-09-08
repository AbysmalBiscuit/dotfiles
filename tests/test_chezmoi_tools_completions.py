import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]


@pytest.fixture
def carapace_env(tmp_path):
    if not shutil.which("carapace") or not shutil.which("chezmoi"):
        pytest.skip("carapace and chezmoi are required")
    config = tmp_path / "config"
    (config / "chezmoi").mkdir(parents=True)
    (config / "chezmoi/chezmoi.toml").write_text(f"sourceDir = {json.dumps(str(tmp_path))}\n")
    data = tmp_path / ".chezmoidata"
    data.mkdir()
    (data / "tools.toml").write_text("""
[[tools]]
name = "completion-example"
lang = "rust"
desc = "Example tool"
[[tools]]
name = "completion-bundled"
lang = "rust"
install_command = "NONE: part of another tool"
""")
    binary = tmp_path / "bin"
    binary.mkdir()
    shutil.copyfile(REPO / "dot_local/bin/executable_chezmoi-tools", binary / "chezmoi-tools")
    (binary / "chezmoi-tools").chmod(0o755)
    shutil.copyfile(REPO / "dot_local/bin/chezmoi_plugin.py", binary / "chezmoi_plugin.py")
    spec = REPO / "private_dot_config/carapace/specs/chezmoi.yaml"
    if spec.exists():
        (config / "carapace/specs").mkdir(parents=True)
        shutil.copyfile(spec, config / "carapace/specs/chezmoi.yaml")
    (tmp_path / "completion-cwd-file").touch()
    return {
        **os.environ,
        "XDG_CONFIG_HOME": str(config),
        "PATH": str(binary) + os.pathsep + os.environ["PATH"],
    }


@pytest.mark.parametrize(
    "arguments",
    [
        [""],
        ["completion-example", ""],
        ["--dry-run", ""],
        ["--", ""],
    ],
)
def test_carapace_completes_installable_names(tmp_path, carapace_env, arguments):
    result = subprocess.run(
        ["carapace", "chezmoi", "nushell", "chezmoi", "tools", "install", *arguments],
        env=carapace_env,
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    values = {item["value"].rstrip() for item in json.loads(result.stdout)}
    assert values == {"completion-example"}


@pytest.mark.parametrize(
    ("arguments", "expected"),
    [
        (["tools", "install", "completion-cwd"], set()),
        (["tools", "install", "--d"], {"--dry-run"}),
        (["tools", "install", "--", "--d"], set()),
        (["tools", ""], {"install", "list", "missing"}),
        (["source-p"], {"source-path"}),
        (["agents", "remove", "--k"], {"--keep-installed"}),
    ],
)
def test_carapace_routes_plugins_and_builtins(tmp_path, carapace_env, arguments, expected):
    result = subprocess.run(
        ["carapace", "chezmoi", "nushell", "chezmoi", *arguments],
        env=carapace_env,
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    values = {item["value"].rstrip() for item in json.loads(result.stdout)}
    assert values == expected


@pytest.mark.parametrize("wsl", [False, True])
@pytest.mark.parametrize("names", [[], ["example-cli"]])
def test_complete_returns_only_installable_names_and_descriptions(tmp_path, wsl, names):
    source = tmp_path
    data = source / ".chezmoidata"
    data.mkdir()
    (data / "tools.toml").write_text("""
    [[tools]]
    name = "example-cli"
    lang = "rust"
    desc = "Example CLI"
    cmds = ["example"]
    [[tools]]
    name = "explicit"
    install_command = "touch MUST_NOT_RUN"
    desc = "Explicit\\tinstaller\\nwith details"
    [[tools]]
    name = "bundled"
    lang = "rust"
    install_command = "NONE: provided by another tool"
    [[tools]]
    name = "unsupported"
    lang = "go"
    """)
    (data / "wsl_tools.toml").write_text("""
    [[wsl_tools]]
    name = "wsl-example"
    install_command = "touch MUST_NOT_RUN"
    """)
    env = {**os.environ, "CHEZMOI_SOURCE_DIR": str(tmp_path)}
    env.pop("WSL_DISTRO_NAME", None)
    if wsl:
        env["WSL_DISTRO_NAME"] = "completion-test"
    result = subprocess.run(
        [sys.executable, str(REPO / "dot_local/bin/executable_chezmoi-tools"), "complete", *names],
        env=env,
        cwd=str(tmp_path),
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    rows = dict(line.split("\t", 1) for line in result.stdout.splitlines())
    expected = {
        "example-cli": "Example CLI",
        "explicit": "Explicit installer with details",
    }
    if wsl:
        expected["wsl-example"] = ""
    assert rows == expected
    assert not (source / "MUST_NOT_RUN").exists()
