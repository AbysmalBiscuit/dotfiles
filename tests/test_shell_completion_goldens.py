import json
import re
import shutil
import subprocess
import tomllib
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
GOLDEN_DIR = Path(__file__).parent / "goldens" / "shell-completions"
INVENTORY = REPO / ".chezmoidata/tools.toml"

TEMPLATES = {
    "sh": "run_onchange_after_90-generate-shell-completions.sh.tmpl",
    "ps1": "windows/run_onchange_after_90-generate-shell-completions.ps1.tmpl",
}

# lookPath/stat mtimes and missing-completion-file markers both track machine
# state rather than the inventory, so they never belong in a golden.
VOLATILE = re.compile(r"^# \S+:\d+$|^#(bash|fish|zsh|nu)$")

ALL_SHELLS = {"bash": True, "fish": True, "zsh": True, "nu": True, "powershell": True}

# Each case is a tool plus the `has` map that exercises its modifiers.
CASES = {
    "starship": {**ALL_SHELLS, "starship": True},
    "Jujutsu": {**ALL_SHELLS, "jj": True},
    "sk": {**ALL_SHELLS, "sk": True},
    "claude-squad": {**ALL_SHELLS, "claude_squad": True, "cs": True},
    "devkit": {
        **ALL_SHELLS,
        "devkit": True,
        "docm": True,
        "devrun": True,
        "issue": True,
        "lockm": True,
        "portm": True,
    },
    "carapace": {**ALL_SHELLS, "carapace": True},
    "fzf-no-sk": {**ALL_SHELLS, "fzf": True},
    "fzf-with-sk": {**ALL_SHELLS, "fzf": True, "sk": True},
    "fish-lsp": {**ALL_SHELLS, "fish_lsp": True},
    "zoxide": {**ALL_SHELLS, "zoxide": True},
}

# Case names that are not the tool name, because one tool needs two has maps.
TOOL_FOR_CASE = {"fzf-no-sk": "fzf", "fzf-with-sk": "fzf"}


def tool_entry(name: str) -> dict:
    tools = tomllib.loads(INVENTORY.read_text(encoding="utf-8"))["tools"]
    return next(tool for tool in tools if tool["name"] == name)


def render(tmp_path: Path, entry: dict, has: dict, template_key: str) -> str:
    source = tmp_path / "source"
    source.mkdir()
    destination = tmp_path / "home"
    destination.mkdir()
    (source / ".chezmoidata.json").write_text(
        json.dumps({"tools": [entry], "has": has, "is_wsl": False}), encoding="utf-8"
    )
    (source / "generator.tmpl").write_bytes(
        (REPO / ".chezmoiscripts" / TEMPLATES[template_key]).read_bytes()
    )
    config = tmp_path / "chezmoi.toml"
    config.write_text(
        f"sourceDir = {json.dumps(str(source))}\ndestDir = {json.dumps(str(destination))}\n",
        encoding="utf-8",
    )
    result = subprocess.run(
        ["chezmoi", "--config", str(config), "cat", str(destination / "generator")],
        capture_output=True,
        text=True,
        check=True,
    )
    return "\n".join(line for line in result.stdout.splitlines() if not VOLATILE.match(line))


@pytest.mark.parametrize("case", sorted(CASES))
@pytest.mark.parametrize("template_key", sorted(TEMPLATES))
def test_generator_output_matches_golden(tmp_path, case, template_key):
    name = TOOL_FOR_CASE.get(case, case)
    entry = tool_entry(name)
    # The display name is not always the executable: Jujutsu ships jj.
    executable = (entry.get("cmds") or [name])[0]
    if not shutil.which("chezmoi") or not shutil.which(executable):
        pytest.skip(f"chezmoi and {executable} are required")
    golden = GOLDEN_DIR / f"{case}.{template_key}.txt"
    rendered = render(tmp_path, entry, CASES[case], template_key)
    if not golden.exists():
        golden.parent.mkdir(parents=True, exist_ok=True)
        golden.write_text(rendered, encoding="utf-8", newline="\n")
        pytest.skip(f"captured {golden.name}")
    assert rendered == golden.read_text(encoding="utf-8")


def test_shell_arg_for_an_undeclared_shell_is_ignored(tmp_path):
    """A free-form map can name any shell; only declared ones generate."""
    if not shutil.which("chezmoi"):
        pytest.skip("chezmoi is required")
    entry = {
        "lang": "rust",
        "name": "probe",
        "cmds": ["probe"],
        "completions": {"command": "probe complete SHELL", "append": {"nu": " | ignored"}},
        "shells": ["bash"],
        "shell_arg": {"nu": "nushell"},
    }
    rendered = render(tmp_path, entry, {**ALL_SHELLS, "probe": True}, "sh")
    generated = [line for line in rendered.splitlines() if "probe complete" in line]
    assert generated == ["    probe complete bash </dev/null || true"]
    assert "ignored" not in rendered
