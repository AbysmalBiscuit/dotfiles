# .agentcfg/tests/test_codecs_json.py
from pathlib import Path
import pytest
from engine.codecs import CodecError, JsonCodec

FIXTURE = Path(__file__).parent / "fixtures" / "claude_settings.json"


def test_round_trip_is_byte_identical():
    raw = FIXTURE.read_bytes()
    assert JsonCodec.dump(JsonCodec.load(raw)) == raw


def test_non_ascii_is_not_escaped():
    data = {"pr": "\U0001f916 generated"}
    assert "\\u" not in JsonCodec.dump(data).decode("utf-8")


def test_dump_ends_with_single_lf():
    out = JsonCodec.dump({"a": 1})
    assert out.endswith(b"\n")
    assert not out.endswith(b"\r\n")
    assert not out.endswith(b"\n\n")


def test_malformed_input_raises_codec_error():
    with pytest.raises(CodecError):
        JsonCodec.load(b"{not json")


def test_non_mapping_input_raises_codec_error():
    with pytest.raises(CodecError, match="mapping"):
        JsonCodec.load(b"[1, 2, 3]")


def test_patch_round_trips_through_dump():
    """The CLI dumps `patch` output, never `merge` output directly."""
    raw = FIXTURE.read_bytes()
    doc = JsonCodec.load(raw)
    assert JsonCodec.dump(JsonCodec.patch(doc, JsonCodec.plain(doc))) == raw
