import os
import subprocess
import sys
from pathlib import Path

import pytest
from engine.codecs import JsonCodec, TomlCodec

REPO = Path(__file__).resolve().parents[2]


@pytest.fixture(
    params=[
        ("private_dot_claude", "modify_settings.json.py", ".settings", "json", JsonCodec),
        ("dot_codex", "modify_private_config.toml.py", ".config", "toml", TomlCodec),
    ]
)
def wrapper(request, tmp_path):
    folder, script, stem, extension, codec = request.param
    source = tmp_path / "src"
    config = source / folder
    config.mkdir(parents=True)
    baseline = {
        "hooks": {
            "SessionStart": [
                {
                    "hooks": [
                        {"type": "command", "command": "managed-session"},
                    ]
                }
            ],
            "Stop": [
                {
                    "hooks": [
                        {"type": "command", "command": "managed-stop"},
                    ]
                }
            ],
        }
    }
    (config / f"{stem}.baseline.{extension}").write_bytes(
        codec.dump(codec.patch(codec.empty(), baseline))
    )
    (config / f"{stem}.rules.toml").write_bytes((REPO / folder / f"{stem}.rules.toml").read_bytes())
    env = os.environ | {
        "CHEZMOI_SOURCE_DIR": str(source),
        "CHEZMOI_SOURCE_FILE": f"{folder}/{script}",
        "PYTHONPATH": str(REPO / ".agentcfg"),
        "PYTHONDONTWRITEBYTECODE": "1",
    }

    def invoke(live, *args, expected_exit=0):
        raw = live if isinstance(live, bytes) else codec.dump(codec.patch(codec.empty(), live))
        result = subprocess.run(
            [sys.executable, str(REPO / folder / script), *args],
            input=raw,
            capture_output=True,
            env=env,
            check=False,
        )
        assert result.returncode == expected_exit, result.stderr.decode()
        return result.stdout

    return invoke, codec, config / f"{stem}.baseline.{extension}", config / f"{stem}.rules.toml"


@pytest.mark.parametrize(
    "command",
    [
        {"command": "bash '/home/other/.claude/hooks/herdr-agent-state.sh' session"},
        {
            "command_windows": (
                'powershell -File "C:\\Users\\Other\\.codex\\herdr-agent-state.ps1" session'
            )
        },
    ],
)
def test_apply_enforces_hooks_but_preserves_live_herdr(wrapper, command):
    invoke, codec, _, _ = wrapper
    herdr = {"type": "command", **command, "timeout": 17, "async": True}
    live = {
        "hooks": {
            "SessionStart": [
                {
                    "matcher": "startup",
                    "hooks": [
                        {"type": "command", "command": "stale-session"},
                        herdr,
                    ],
                }
            ],
            "Stop": [{"hooks": [{"type": "command", "command": "stale-stop"}]}],
            "Notification": [
                {
                    "matcher": "*",
                    "hooks": [
                        herdr,
                        {"type": "command", "command": "unmanaged-notification"},
                    ],
                }
            ],
            "FutureEvent": [{"hooks": [{"type": "command", "command": "unmanaged"}]}],
        }
    }
    out = invoke(live)
    hooks = codec.plain(codec.load(out))["hooks"]
    assert hooks["SessionStart"] == [
        {"hooks": [{"type": "command", "command": "managed-session"}]},
        {"matcher": "startup", "hooks": [herdr]},
    ]
    assert hooks["Stop"] == [
        {"hooks": [{"type": "command", "command": "managed-stop"}]},
    ]
    assert hooks["Notification"] == [{"matcher": "*", "hooks": [herdr]}]
    assert not hooks.get("FutureEvent")
    assert invoke(out) == out
    assert invoke(out, "--check") == b""


def test_apply_does_not_invent_herdr_hooks(wrapper):
    invoke, codec, _, _ = wrapper
    out = codec.plain(codec.load(invoke({})))
    assert out["hooks"] == {
        "SessionStart": [{"hooks": [{"type": "command", "command": "managed-session"}]}],
        "Stop": [{"hooks": [{"type": "command", "command": "managed-stop"}]}],
    }


def test_baseline_cannot_reintroduce_machine_local_herdr_hooks(wrapper):
    invoke, codec, baseline_path, _ = wrapper
    baseline = {
        "hooks": {
            "Stop": [
                {
                    "hooks": [
                        {
                            "type": "command",
                            "command": "bash /old/home/herdr-agent-state.sh stop",
                        }
                    ]
                }
            ]
        }
    }
    baseline_path.write_bytes(codec.dump(codec.patch(codec.empty(), baseline)))
    assert invoke({}, expected_exit=2) == b""


def test_codex_hook_state_survives_apply(wrapper):
    invoke, codec, _, _ = wrapper
    if codec is not TomlCodec:
        pytest.skip("only Codex stores hook state")
    state = {"C:/Users/Other/.codex": {"enabled": True}}
    out = codec.plain(codec.load(invoke({"hooks": {"state": state}})))
    assert out["hooks"]["state"] == state


@pytest.mark.parametrize("field", ["command", "command_windows"])
def test_enforce_ignore_is_controlled_by_config(wrapper, field):
    invoke, codec, baseline_path, rules_path = wrapper
    rules_path.write_text(
        'enforce = [["hooks", "*"]]\n'
        '[enforce_ignore]\nhook_commands = ["*local-status-hook*", "another-tool *"]\n',
        encoding="utf-8",
    )
    custom = {"type": "command", field: "python /machine/local-status-hook.py stop"}
    another = {"type": "command", field: "another-tool report"}
    herdr = {"type": "command", "command": "bash /home/lev/herdr-agent-state.sh stop"}
    live = {"hooks": {"Stop": [{"matcher": "*", "hooks": [custom, herdr, another]}]}}
    out = invoke(live)
    assert codec.plain(codec.load(out))["hooks"]["Stop"] == [
        {"hooks": [{"type": "command", "command": "managed-stop"}]},
        {"matcher": "*", "hooks": [custom, another]},
    ]
    assert invoke(out) == out
    baseline_path.write_bytes(codec.dump(codec.patch(codec.empty(), live)))
    assert invoke({}, expected_exit=2) == b""


@pytest.mark.parametrize("table", ["", "[enforce_ignore]\nhook_commands = []\n"])
def test_no_implicit_herdr_exception(wrapper, table):
    invoke, codec, _, rules_path = wrapper
    rules_path.write_text('enforce = [["hooks", "*"]]\n' + table, encoding="utf-8")
    live = {
        "hooks": {
            "Stop": [
                {
                    "hooks": [
                        {
                            "type": "command",
                            "command": "bash /home/lev/herdr-agent-state.sh stop",
                        }
                    ]
                }
            ]
        }
    }
    assert codec.plain(codec.load(invoke(live)))["hooks"]["Stop"] == [
        {"hooks": [{"type": "command", "command": "managed-stop"}]},
    ]


@pytest.mark.parametrize(
    "table",
    [
        "enforce_ignore = []",
        '[enforce_ignore]\nhook_commands = "*tool*"',
        "[enforce_ignore]\nhook_commands = [1]",
        '[enforce_ignore]\nhook_commands = [""]',
        '[enforce_ignore]\nhook_command = ["*tool*"]',
    ],
)
def test_invalid_enforce_ignore_refuses_to_write(wrapper, table):
    invoke, _, _, rules_path = wrapper
    rules_path.write_text('enforce = [["hooks", "*"]]\n' + table, encoding="utf-8")
    assert invoke({}, expected_exit=2) == b""
