import importlib.util
import os
import subprocess
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
BIN = REPO / "dot_local" / "bin"

for _name, _filename in (
    ("chezmoi_plugin", "chezmoi_plugin.py"),
    ("ocargo", "ocargo.py"),
    ("chezmoi_tools", "executable_chezmoi-tools"),
):
    _loader = SourceFileLoader(_name, str(BIN / _filename))
    _spec = importlib.util.spec_from_loader(_name, _loader)
    assert _spec is not None
    _module = importlib.util.module_from_spec(_spec)
    sys.modules[_name] = _module
    _loader.exec_module(_module)

chezmoi_tools = sys.modules["chezmoi_tools"]
PluginError = sys.modules["chezmoi_plugin"].PluginError


def tool(**overrides):
    base = {
        "name": "zzz",
        "lang": "rust",
        "cmds": ("zzz",),
        "desc": "",
        "install": None,
        "update": None,
        "provided_by": None,
    }
    return chezmoi_tools.Tool(**{**base, **overrides})


def test_provided_by_blocks_install():
    with pytest.raises(PluginError, match="ya: provided by yazi, install that instead"):
        chezmoi_tools.install_command_for(tool(name="ya", provided_by="yazi"))


def test_provided_by_blocks_derived_update():
    """uvx is lang=rust but ships with uv, so it must never get a cargo update."""
    with pytest.raises(PluginError, match="uvx: provided by uv"):
        chezmoi_tools.update_command_for(tool(name="uvx", provided_by="uv"))


def test_provided_by_names_an_absent_parent():
    """The parent need not be inventoried for the message to be useful."""
    with pytest.raises(PluginError, match="zzz: provided by nowhere, install that instead"):
        chezmoi_tools.install_command_for(tool(provided_by="nowhere"))


def test_install_falls_through_to_lang_when_the_platform_is_absent(monkeypatch):
    """go declares only a windows install; elsewhere the lang decides."""
    monkeypatch.setattr(sys.modules["chezmoi_plugin"], "platform_name", lambda: "linux")
    with pytest.raises(PluginError, match="no install command, and none follows from lang 'go'"):
        chezmoi_tools.install_command_for(
            tool(name="go", lang="go", install={"windows": "winget install GoLang.Go"})
        )


def test_declared_update_wins_over_derivation():
    assert chezmoi_tools.update_command_for(tool(update=["tuicr", "update"])) == ["tuicr", "update"]


def test_cli_update_runs_source_script_from_another_directory(tmp_path):
    source = tmp_path / "custom source with spaces"
    inventory = source / ".chezmoidata"
    inventory.mkdir(parents=True)
    hooks = source / "hooks"
    hooks.mkdir()
    (hooks / "update.py").write_text("import sys; print('updated ' + sys.argv[1])\n")
    (inventory / "tools.toml").write_text(
        '[[tools]]\nname = "example"\nlang = "python"\n'
        'update = ["python3", "${CHEZMOI_SOURCE_DIR}/hooks/update.py", "example"]\n'
    )
    result = subprocess.run(
        [sys.executable, str(BIN / "executable_chezmoi-tools"), "update", "example"],
        cwd=tmp_path,
        env={**os.environ, "CHEZMOI_SOURCE_DIR": str(source)},
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert "updated example" in result.stdout


def test_python_update_derives_from_lang():
    assert chezmoi_tools.update_command_for(tool(lang="python")) == ["uv", "tool", "upgrade", "zzz"]


def test_bun_update_derives_from_lang():
    assert chezmoi_tools.update_command_for(tool(lang="bun")) == ["bun", "update", "-g", "zzz"]


def test_rust_update_reuses_the_install_command():
    """cargo install reinstalls when a newer version exists, and the stored
    command already names the crate, which the tool name often does not."""
    resolved = chezmoi_tools.update_command_for(
        tool(lang="rust", install="cargo install --locked ripgrep")
    )
    assert resolved == ["ocargo", "install", "--locked", "ripgrep"]


def test_unknown_lang_without_a_declared_update_is_an_error():
    with pytest.raises(PluginError, match="no update, and none follows from lang 'go'"):
        chezmoi_tools.update_command_for(tool(lang="go"))


def test_bulk_skips_when_nothing_is_stale(monkeypatch):
    """cargo install-update -g with no packages is not a no-op."""
    calls = []
    monkeypatch.setattr(chezmoi_tools, "stale_cargo_packages", list)
    monkeypatch.setattr(chezmoi_tools, "run_cargo", lambda argv: calls.append(argv) or 0)
    assert chezmoi_tools.bulk_update_rust([]) == 0
    assert calls == []


def test_bulk_excludes_tools_with_a_declared_update(monkeypatch):
    calls = []
    monkeypatch.setattr(chezmoi_tools, "stale_cargo_packages", lambda: ["ripgrep", "tuicr"])
    monkeypatch.setattr(chezmoi_tools, "run_cargo", lambda argv: calls.append(argv) or 0)
    chezmoi_tools.bulk_update_rust(["tuicr"])
    assert calls == [["install-update", "-g", "ripgrep"]]


# Captured from `cargo install-update -l -g` with the commit hashes cut short.
# The registry and git tables use different column widths, which is why the
# parser reads the end of the line.
CARGO_LISTING = """    Polling registry 'https://index.crates.io/'......

Package               Installed  Latest     Needs update
cargo-nextest         v0.9.143   v0.9.145   Yes
delta                 v0.18.2    v0.18.2    No
skim                  v5.6.6     v5.7.0     Yes

    Polling 12 packages...

Package             Installed     Latest        Needs update
devkit              2450c4d52dce  dbafcb292baf  Yes
zccache             01f4fea2be76  01f4fea2be76  No
"""


def test_stale_packages_reads_both_cargo_tables(monkeypatch):
    """Yes ends the line, and git-installed crates only appear under -g."""
    seen = []
    monkeypatch.setattr(
        subprocess,
        "run",
        lambda argv, **_kwargs: (
            seen.append(argv)
            or subprocess.CompletedProcess(args=argv, returncode=0, stdout=CARGO_LISTING, stderr="")
        ),
    )
    assert chezmoi_tools.stale_cargo_packages() == ["cargo-nextest", "skim", "devkit"]
    assert seen == [["cargo", "install-update", "-l", "-g"]]


def test_stale_packages_reports_a_failed_listing(monkeypatch):
    """An empty listing from a failed cargo must not read as nothing to update."""
    monkeypatch.setattr(
        subprocess,
        "run",
        lambda argv, **_kwargs: subprocess.CompletedProcess(
            args=argv, returncode=101, stdout="", stderr="no such subcommand: install-update"
        ),
    )
    with pytest.raises(PluginError, match="cargo install-update"):
        chezmoi_tools.stale_cargo_packages()


def test_rust_update_runs_through_a_shell_when_the_install_needs_one():
    """rustup installs through a pipeline, which only a shell can run."""
    resolved = chezmoi_tools.update_command_for(
        tool(lang="rust", install="curl -sSf https://sh.rustup.rs | sh")
    )
    assert resolved[:2] in (["cmd.exe", "/c"], ["sh", "-c"])
    assert resolved[2] == "curl -sSf https://sh.rustup.rs | sh"


def test_rust_update_without_an_install_command_refuses():
    """A crate name is not a command name, so the name cannot be derived from."""
    with pytest.raises(PluginError, match="no update and no install command to reuse"):
        chezmoi_tools.update_command_for(tool(lang="rust"))


@pytest.mark.skipif(os.name != "nt", reason="batch wrappers are a Windows concern")
def test_run_update_spawns_through_a_batch_wrapper(tmp_path, monkeypatch):
    """~/.local/bin wrappers are .cmd files, which CreateProcess cannot start."""
    marker = tmp_path / "ran"
    wrapper = tmp_path / "fake-updater.cmd"
    wrapper.write_text(f'@echo ran > "{marker}"\n')
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    assert chezmoi_tools.run_update(tool(update=["fake-updater"]), dry_run=False) == 0
    assert marker.exists()
