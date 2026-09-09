import json
import shutil
import subprocess
import tomllib
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize(
    "template",
    [
        "run_onchange_after_90-generate-shell-completions.sh.tmpl",
        "windows/run_onchange_after_90-generate-shell-completions.ps1.tmpl",
    ],
)
def test_starship_generates_nushell_completions(tmp_path, template):
    if not shutil.which("chezmoi") or not shutil.which("starship"):
        pytest.skip("chezmoi and starship are required")
    source = tmp_path / "source"
    source.mkdir()
    destination = tmp_path / "home"
    destination.mkdir()
    tools = tomllib.loads((REPO / ".chezmoidata/tools.toml").read_text())
    starship = next(tool for tool in tools["tools"] if tool["name"] == "starship")
    (source / ".chezmoidata.json").write_text(
        json.dumps(
            {
                "tools": [starship],
                "has": {"starship": True, "nu": True, "bash": True},
                "is_wsl": False,
            }
        )
    )
    (source / "generator.tmpl").write_bytes((REPO / ".chezmoiscripts" / template).read_bytes())
    config = tmp_path / "chezmoi.toml"
    config.write_text(
        f"sourceDir = {json.dumps(str(source))}\ndestDir = {json.dumps(str(destination))}\n"
    )
    result = subprocess.run(
        ["chezmoi", "--config", str(config), "cat", str(destination / "generator")],
        capture_output=True,
        text=True,
        check=True,
    )
    (tmp_path / "rendered-generator").write_text(result.stdout, newline="\n")
    assert "starship completions nushell" in result.stdout
    assert "starship init nushell" not in result.stdout
    other_shell = "powershell" if template.startswith("windows/") else "bash"
    assert f"starship init {other_shell} --print-full-init" in result.stdout
