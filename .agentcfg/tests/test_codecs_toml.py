from pathlib import Path
import pytest
from engine.codecs import CodecError, TomlCodec

FIXTURE = Path(__file__).parent / "fixtures" / "codex_config.toml"


def test_round_trip_is_byte_identical():
    raw = FIXTURE.read_bytes()
    assert TomlCodec.dump(TomlCodec.load(raw)) == raw


def test_schema_comment_survives():
    raw = b'#:schema https://example.com/s.json\nmodel = "x"\n'
    assert TomlCodec.dump(TomlCodec.load(raw)) == raw


def test_backslash_table_key_is_one_segment():
    raw = b"[projects.'c:\\users\\lev\\.codex']\ntrust_level = \"trusted\"\n"
    doc = TomlCodec.load(raw)
    assert list(doc["projects"]) == ["c:\\users\\lev\\.codex"]


def test_embedded_colon_table_key_is_one_segment():
    key = "devkit@devkit:hooks/hooks-codex.json:session_start:0:0"
    raw = f'[hooks.state."{key}"]\ntrusted_hash = "abc"\n'.encode()
    doc = TomlCodec.load(raw)
    assert list(doc["hooks"]["state"]) == [key]


def test_array_of_tables_survives():
    raw = b'[[hooks.SessionEnd]]\nhooks = [\n    { type = "command" },\n]\n'
    assert TomlCodec.dump(TomlCodec.load(raw)) == raw


def test_added_subtable_placement():
    """Pin tomlkit's placement of a programmatically added sub-table.

    This is the roughest edge in the dependency. The assertion records what
    tomlkit actually does so a version bump that changes it fails loudly.
    """
    raw = b'[marketplaces.devkit]\nsource = "a"\n\n[plugins]\n'
    doc = TomlCodec.load(raw)
    doc["marketplaces"]["superpowers"] = {"source": "b"}
    out = TomlCodec.dump(doc).decode()
    assert out.index("[marketplaces.devkit]") < out.index("superpowers")
    assert out.index("superpowers") < out.index("[plugins]")


def test_malformed_input_raises_codec_error():
    with pytest.raises(CodecError):
        TomlCodec.load(b"[unclosed\n")


def test_plain_strips_tomlkit_types():
    doc = TomlCodec.load(b"a = true\n")
    assert TomlCodec.plain(doc) == {"a": True}
    assert type(TomlCodec.plain(doc)["a"]) is bool


def test_merge_output_patched_back_is_byte_identical():
    """A no-change merge must not reformat the file.

    `tomlkit.dumps` regenerates every header, blank line, and comment position
    when handed a plain dict, so the CLI patches the merged mapping back into
    the parsed document rather than dumping it. This is the test that pins it.
    """
    raw = FIXTURE.read_bytes()
    doc = TomlCodec.load(raw)
    assert TomlCodec.dump(TomlCodec.patch(doc, TomlCodec.plain(doc))) == raw


def test_patch_replaces_a_scalar_and_keeps_everything_else():
    raw = b'#:schema x\nmodel = "a"\n\n[tui]\nnotifications = true\n'
    doc = TomlCodec.load(raw)
    TomlCodec.patch(doc, {"model": "b", "tui": {"notifications": True}})
    assert TomlCodec.dump(doc) == raw.replace(b'"a"', b'"b"')
