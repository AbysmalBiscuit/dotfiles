import importlib.util
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PLUGIN = REPO / "dot_local" / "bin" / "chezmoi_plugin.py"

_loader = SourceFileLoader("chezmoi_plugin", str(PLUGIN))
_spec = importlib.util.spec_from_loader("chezmoi_plugin", _loader)
assert _spec is not None
chezmoi_plugin = importlib.util.module_from_spec(_spec)
sys.modules["chezmoi_plugin"] = chezmoi_plugin
_loader.exec_module(chezmoi_plugin)


def test_bare_string_covers_every_platform(monkeypatch):
    monkeypatch.setattr(chezmoi_plugin, "platform_name", lambda: "linux")
    assert chezmoi_plugin.resolve_platform("cargo install rg") == "cargo install rg"


def test_exact_platform_key_wins(monkeypatch):
    monkeypatch.setattr(chezmoi_plugin, "platform_name", lambda: "windows")
    value = {"default": "cargo install go", "windows": "winget install GoLang.Go"}
    assert chezmoi_plugin.resolve_platform(value) == "winget install GoLang.Go"


def test_falls_back_to_default(monkeypatch):
    monkeypatch.setattr(chezmoi_plugin, "platform_name", lambda: "macos")
    value = {"default": "cargo install go", "windows": "winget install GoLang.Go"}
    assert chezmoi_plugin.resolve_platform(value) == "cargo install go"


def test_missing_platform_without_default_is_unset(monkeypatch):
    """go declares only a windows install, so Linux must derive from lang."""
    monkeypatch.setattr(chezmoi_plugin, "platform_name", lambda: "linux")
    assert chezmoi_plugin.resolve_platform({"windows": "winget install GoLang.Go"}) is None


def test_empty_value_is_a_disable_not_unset(monkeypatch):
    monkeypatch.setattr(chezmoi_plugin, "platform_name", lambda: "windows")
    assert chezmoi_plugin.resolve_platform({"default": ["codex", "update"], "windows": []}) == []


def test_absent_field_is_unset():
    assert chezmoi_plugin.resolve_platform(None) is None


def test_table_branch_uses_the_named_bare_key(monkeypatch):
    monkeypatch.setattr(chezmoi_plugin, "platform_name", lambda: "linux")
    value = {"command": "starship init SHELL", "exclude_shells": ["nu"]}
    assert chezmoi_plugin.resolve_platform(value, bare_key="command") == "starship init SHELL"
