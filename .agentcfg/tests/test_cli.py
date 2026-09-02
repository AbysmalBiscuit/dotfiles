import io
import json
import pytest
from engine.cli import run
from engine.codecs import JsonCodec


@pytest.fixture
def config(tmp_path, monkeypatch):
    source = tmp_path / "src"
    script_dir = source / "private_dot_claude"
    script_dir.mkdir(parents=True)
    (source / ".agentcfg").mkdir()
    (script_dir / ".settings.baseline.json").write_text(
        json.dumps({"model": "opus"}, indent=2) + "\n", encoding="utf-8"
    )
    (script_dir / ".settings.rules.toml").write_text(
        'seed = [["model"]]\n', encoding="utf-8"
    )
    monkeypatch.setenv("CHEZMOI_SOURCE_DIR", str(source))
    monkeypatch.setenv(
        "CHEZMOI_SOURCE_FILE", "private_dot_claude/modify_settings.json.py"
    )
    monkeypatch.setenv("CHEZMOI_DEST_DIR", str(tmp_path / "home"))
    return script_dir


def invoke(config, stdin: bytes, argv=()):
    out, err = io.BytesIO(), io.StringIO()
    code = run(
        script_file=str(config / "modify_settings.json.py"),
        baseline_name=".settings.baseline.json",
        rules_name=".settings.rules.toml",
        codec=JsonCodec,
        argv=list(argv),
        stdin=io.BytesIO(stdin),
        stdout=out,
        stderr=err,
    )
    return code, out.getvalue(), err.getvalue()


def test_guard_empty_stdin_writes_full_baseline(config):
    """No special case: {} goes through the merge like any other live file."""
    code, out, err = invoke(config, b"")
    assert code == 0
    assert json.loads(out) == {"model": "opus"}


def test_merge_path_exits_zero_with_drift(config):
    """Drift is reported on stderr. A non-zero exit would abort the apply."""
    live = json.dumps({"model": "sonnet", "novel": 1}, indent=2).encode() + b"\n"
    code, out, err = invoke(config, live)
    assert code == 0
    assert json.loads(out)["novel"] == 1
    assert "unclassified" in err


def test_guard_unparseable_writes_nothing_and_exits_nonzero(config):
    code, out, err = invoke(config, b"{not json")
    assert code != 0
    assert out == b""
    assert "cannot parse JSON" in err


def test_no_change_is_byte_identical(config):
    live = json.dumps({"model": "sonnet"}, indent=2).encode() + b"\n"
    code, out, err = invoke(config, live)
    assert code == 0
    assert out == live


def test_check_mode_writes_nothing_to_stdout(config):
    live = json.dumps({"model": "sonnet", "novel": 1}, indent=2).encode() + b"\n"
    code, out, err = invoke(config, live, argv=["--check"])
    assert out == b""
    assert code == 1
    assert "novel" in err


def test_lint_failure_exits_two(config):
    (config / ".settings.rules.toml").write_text("", encoding="utf-8")
    code, out, err = invoke(config, b'{"model": "sonnet"}\n')
    assert code == 2
    assert out == b""


def test_guard_empty_output_refuses_to_write(config):
    """chezmoi writes modifier stdout with overwrite:true.

    An engine bug that serialized to nothing would truncate the live config
    to zero bytes, so the CLI checks its own output before writing. No real
    codec can produce this, hence the stub.
    """

    class EmptyCodec(JsonCodec):
        @staticmethod
        def dump(data):
            return b""

    out_buf, err_buf = io.BytesIO(), io.StringIO()
    code = run(
        script_file=str(config / "modify_settings.json.py"),
        baseline_name=".settings.baseline.json",
        rules_name=".settings.rules.toml",
        codec=EmptyCodec,
        argv=[],
        stdin=io.BytesIO(b'{"model": "sonnet"}\n'),
        stdout=out_buf,
        stderr=err_buf,
    )
    assert code == 2
    assert out_buf.getvalue() == b""
    assert "refusing to write" in err_buf.getvalue()
