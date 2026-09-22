import importlib.util
import json
import os
import tomllib
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
SORTER = REPO / ".chezmoiscripts" / "run_onchange_before_01-sort-tools.py.tmpl"


def load_sorter(source: Path, schema: dict, toml_text: str):
    """Import a fresh sorter bound to a fixture source directory."""
    data = source / ".chezmoidata"
    data.mkdir(parents=True, exist_ok=True)
    (data / ".tools.schema.json").write_text(json.dumps(schema), encoding="utf-8")
    (data / "tools.toml").write_text(toml_text, encoding="utf-8", newline="\n")
    (data / "wsl_tools.toml").write_text(
        "#:schema .tools.schema.json\n", encoding="utf-8", newline="\n"
    )
    previous = os.environ.get("CHEZMOI_SOURCE_DIR")
    os.environ["CHEZMOI_SOURCE_DIR"] = str(source)
    try:
        loader = SourceFileLoader("sorter_under_test", str(SORTER))
        spec = importlib.util.spec_from_loader("sorter_under_test", loader)
        assert spec is not None
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
    finally:
        if previous is None:
            os.environ.pop("CHEZMOI_SOURCE_DIR", None)
        else:
            os.environ["CHEZMOI_SOURCE_DIR"] = previous
    return module


def tool_schema(properties: dict) -> dict:
    return {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "type": "object",
        "definitions": {"tool": {"type": "object", "properties": properties}},
        "properties": {"tools": {"type": "array", "items": {"$ref": "#/definitions/tool"}}},
    }


BARE = {"lang": {"type": "string"}, "name": {"type": "string"}}


@pytest.mark.parametrize("enabled", [False, True])
def test_boolean_update_policy_survives_sort(tmp_path, enabled):
    module = load_sorter(
        tmp_path,
        tool_schema({**BARE, "update_on_apply": {"type": "boolean", "default": True}}),
        '[[tools]]\nname = "herdr"\n' + f"update_on_apply = {str(enabled).lower()}\n",
    )
    module.sort_file(module.TOOLS_TOML)
    tool = tomllib.loads(module.TOOLS_TOML.read_text())["tools"][0]
    assert tool.get("update_on_apply", True) is enabled


ARGUMENTS = {"type": "array", "items": {"type": "string", "minLength": 1}}

POLYMORPHIC_UPDATE = {
    "oneOf": [
        {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}},
        {
            "type": "object",
            "additionalProperties": False,
            "properties": {"default": ARGUMENTS, "windows": ARGUMENTS},
        },
    ]
}


def test_polymorphic_field_default_is_the_bare_branch(tmp_path):
    module = load_sorter(
        tmp_path,
        tool_schema({**BARE, "update": POLYMORPHIC_UPDATE}),
        '#:schema .tools.schema.json\n[[tools]]\nlang = "rust"\nname = "zzz"\n',
    )
    assert module.FIELD_DEFAULTS["update"] == []


def test_bare_argv_keeps_its_order(tmp_path):
    module = load_sorter(
        tmp_path,
        tool_schema({**BARE, "update": POLYMORPHIC_UPDATE}),
        '#:schema .tools.schema.json\n[[tools]]\nlang = "rust"\nname = "zzz"\n'
        'update = ["cargo", "install-update", "-a", "-g"]\n',
    )
    module.sort_file(module.TOOLS_TOML)
    assert '"cargo",\n    "install-update",\n    "-a",\n    "-g"' in (
        module.TOOLS_TOML.read_text(encoding="utf-8")
    )


def test_three_level_key_round_trips(tmp_path):
    schema = tool_schema(
        {
            **BARE,
            "completions": {
                "type": "object",
                "properties": {
                    "command": {"type": "string"},
                    "append": {
                        "type": "object",
                        "properties": {"fish": {"type": "string"}},
                    },
                },
            },
        }
    )
    module = load_sorter(
        tmp_path,
        schema,
        '#:schema .tools.schema.json\n[[tools]]\nlang = "rust"\nname = "zzz"\n'
        'completions.command = "zzz complete SHELL"\n'
        'completions.append.fish = "| tail -n +2"\n',
    )
    module.sort_file(module.TOOLS_TOML)
    text = module.TOOLS_TOML.read_text(encoding="utf-8")
    assert 'completions.append.fish = "| tail -n +2"' in text


def test_free_form_object_passes_through(tmp_path):
    schema = tool_schema(
        {
            **BARE,
            "shell_arg": {
                "type": "object",
                "additionalProperties": {"type": "string", "minLength": 1},
            },
        }
    )
    module = load_sorter(
        tmp_path,
        schema,
        '#:schema .tools.schema.json\n[[tools]]\nlang = "rust"\nname = "zzz"\n'
        'shell_arg.nu = "nushell"\nshell_arg.powershell = "power-shell"\n',
    )
    module.sort_file(module.TOOLS_TOML)
    text = module.TOOLS_TOML.read_text(encoding="utf-8")
    assert 'shell_arg.nu = "nushell"' in text
    assert 'shell_arg.powershell = "power-shell"' in text


def test_unknown_top_level_key_raises(tmp_path):
    module = load_sorter(
        tmp_path,
        tool_schema(BARE),
        '#:schema .tools.schema.json\n[[tools]]\nlang = "rust"\nname = "zzz"\n'
        'mystery_field = "x"\n',
    )
    with pytest.raises(ValueError, match="Unknown tool keys: mystery_field"):
        module.sort_file(module.TOOLS_TOML)


POLYMORPHIC_INSTALL = {
    "oneOf": [
        {"type": "string", "minLength": 1},
        {
            "type": "object",
            "additionalProperties": False,
            "properties": {"default": {"type": "string"}, "windows": {"type": "string"}},
        },
    ]
}


def test_single_key_table_collapses_to_the_bare_form(tmp_path):
    module = load_sorter(
        tmp_path,
        tool_schema({**BARE, "install": POLYMORPHIC_INSTALL}),
        '#:schema .tools.schema.json\n[[tools]]\nlang = "rust"\nname = "zzz"\n'
        'install.default = "cargo install zzz"\n',
    )
    module.sort_file(module.TOOLS_TOML)
    text = module.TOOLS_TOML.read_text(encoding="utf-8")
    assert 'install = "cargo install zzz"' in text
    assert "install.default" not in text


def test_empty_value_stays_a_table(tmp_path):
    module = load_sorter(
        tmp_path,
        tool_schema({**BARE, "install": POLYMORPHIC_INSTALL}),
        '#:schema .tools.schema.json\n[[tools]]\nlang = "go"\nname = "zzz"\ninstall.default = ""\n',
    )
    module.sort_file(module.TOOLS_TOML)
    assert 'install.default = ""' in module.TOOLS_TOML.read_text(encoding="utf-8")


def test_platform_table_survives_a_sort(tmp_path):
    module = load_sorter(
        tmp_path,
        tool_schema({**BARE, "install": POLYMORPHIC_INSTALL}),
        '#:schema .tools.schema.json\n[[tools]]\nlang = "go"\nname = "zzz"\n'
        'install.windows = "winget install Zzz"\n',
    )
    module.sort_file(module.TOOLS_TOML)
    text = module.TOOLS_TOML.read_text(encoding="utf-8")
    assert 'install.windows = "winget install Zzz"' in text
    assert "install.default" not in text


def test_modifier_only_table_is_rejected_by_the_schema():
    """completionsTable requires command, so a modifier-only table is invalid."""
    import json as _json
    import subprocess
    import tempfile

    schema_path = REPO / ".chezmoidata" / ".tools.schema.json"
    schema = _json.loads(schema_path.read_text(encoding="utf-8"))
    assert schema["definitions"]["completionsTable"]["required"] == ["command"]
    assert schema["definitions"]["initTable"]["required"] == ["command"]

    with tempfile.TemporaryDirectory() as directory:
        bad = Path(directory) / "bad.toml"
        bad.write_text(
            '[[tools]]\nlang = "rust"\nname = "zzz"\ncompletions.only_if_no = ["other"]\n',
            encoding="utf-8",
        )
        # The repo .taplo.toml's include list does not reach a temp directory,
        # so the schema is named here rather than through a #:schema directive.
        result = subprocess.run(
            [
                "taplo",
                "check",
                "--no-auto-config",
                "--schema",
                schema_path.as_uri(),
                str(bad),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    assert result.returncode != 0, result.stdout + result.stderr
    assert "schema validation failed" in result.stderr, result.stdout + result.stderr
