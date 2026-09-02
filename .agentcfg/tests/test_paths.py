from pathlib import Path
import pytest
from engine.paths import resolve


def test_uses_chezmoi_env_when_set(tmp_path, monkeypatch):
    source = tmp_path / "src"
    (source / "private_dot_claude").mkdir(parents=True)
    monkeypatch.setenv("CHEZMOI_SOURCE_DIR", str(source))
    monkeypatch.setenv(
        "CHEZMOI_SOURCE_FILE", "private_dot_claude/modify_settings.json.py"
    )
    monkeypatch.setenv("CHEZMOI_DEST_DIR", str(tmp_path / "home"))

    paths = resolve("/some/temp/dir/928374.modify_settings.json.py")

    assert paths.source_root == source
    assert paths.script_dir == source / "private_dot_claude"
    assert paths.target_root == tmp_path / "home"


def test_falls_back_to_file_ancestor_walk(tmp_path, monkeypatch):
    for var in ("CHEZMOI_SOURCE_DIR", "CHEZMOI_SOURCE_FILE", "CHEZMOI_DEST_DIR"):
        monkeypatch.delenv(var, raising=False)
    source = tmp_path / "src"
    (source / ".agentcfg").mkdir(parents=True)
    script_dir = source / "private_dot_claude"
    script_dir.mkdir()
    script = script_dir / "modify_settings.json.py"
    script.write_text("")
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: tmp_path / "home"))

    paths = resolve(str(script))

    assert paths.source_root == source
    assert paths.script_dir == script_dir
    assert paths.target_root == tmp_path / "home"


def test_fallback_without_agentcfg_ancestor_raises(tmp_path, monkeypatch):
    for var in ("CHEZMOI_SOURCE_DIR", "CHEZMOI_SOURCE_FILE", "CHEZMOI_DEST_DIR"):
        monkeypatch.delenv(var, raising=False)
    script = tmp_path / "orphan.py"
    script.write_text("")

    with pytest.raises(RuntimeError, match="agentcfg"):
        resolve(str(script))
