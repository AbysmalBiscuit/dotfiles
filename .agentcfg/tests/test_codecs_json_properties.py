"""Property tests for JsonCodec.

Kept separate from test_codecs_json.py so the example-based suite stays
runnable without Hypothesis installed.

JsonCodec.dump emits one canonical formatting, so arbitrary JSON text does
not round-trip byte for byte through it - a property claiming that would be
false. The real invariant is that dumping is a fixed point: once a plain
dict has gone through patch+dump once, doing it again from the loaded
result reproduces the exact same bytes. That is the no-change-apply
guarantee this task exists to protect.
"""

from __future__ import annotations

from hypothesis import event, given, settings, strategies as st

from engine.codecs import JsonCodec

ASCII_CHARS = "abcXYZ012 _-."
# Latin-1 supplement, CJK, and an astral-plane emoji (a UTF-16 surrogate
# pair) - the character class that json.dumps's default ensure_ascii=True
# would rewrite as \uXXXX escapes.
NON_ASCII_CHARS = "áéîõü中文日本語🤖🚀💥"


def biased_bool(true_out_of_5):
    """A boolean weighted true_out_of_5/5 true, instead of st.booleans' 50/50."""
    return st.sampled_from([True] * true_out_of_5 + [False] * (5 - true_out_of_5))


@st.composite
def json_text(draw, max_size=6):
    """A string drawn mostly from ASCII, with a non-ASCII character spliced
    in 3 times out of 5 so that non-ASCII content is common rather than
    incidental."""
    base = draw(st.text(alphabet=ASCII_CHARS, min_size=0, max_size=max_size))
    if draw(biased_bool(3)):
        extra = draw(st.sampled_from(NON_ASCII_CHARS))
        pos = draw(st.integers(min_value=0, max_value=len(base)))
        base = base[:pos] + extra + base[pos:]
    return base


json_key = json_text(max_size=6).filter(lambda s: s != "")

scalar = st.one_of(
    st.none(),
    st.booleans(),
    st.integers(min_value=-1000, max_value=1000),
    st.floats(allow_nan=False, allow_infinity=False, width=32),
    json_text(),
)

leaf_value = st.one_of(scalar, st.lists(scalar, max_size=4))


def plain_dict(values):
    return st.dictionaries(json_key, values, max_size=4)


@st.composite
def nested_dict(draw):
    """A plain dict with string keys and values that are strings, ints,
    floats, bools, None, lists of those, or nested dicts of the same shape -
    the shapes a real config file actually holds."""
    depth = draw(st.integers(min_value=0, max_value=2))
    values = leaf_value
    for _ in range(depth):
        values = st.one_of(leaf_value, plain_dict(values))
    return draw(plain_dict(values))


def has_non_ascii(value) -> bool:
    if isinstance(value, str):
        return any(ord(ch) > 127 for ch in value)
    if isinstance(value, dict):
        return any(has_non_ascii(k) or has_non_ascii(v) for k, v in value.items())
    if isinstance(value, list):
        return any(has_non_ascii(v) for v in value)
    return False


@given(nested_dict())
@settings(max_examples=300)
def test_dump_is_a_fixed_point(d):
    """dump(patch(empty(), d)) reproduces itself byte for byte on a second
    load/plain/patch/dump cycle - the guarantee that a no-change apply
    leaves the file untouched."""
    event("has non-ASCII" if has_non_ascii(d) else "ASCII only")

    once = JsonCodec.dump(JsonCodec.patch(JsonCodec.empty(), d))
    doc = JsonCodec.load(once)
    twice = JsonCodec.dump(JsonCodec.patch(doc, JsonCodec.plain(doc)))

    assert twice == once


@given(nested_dict())
@settings(max_examples=300)
def test_plain_patch_round_trip(d):
    """plain(patch(empty(), d)) == d: patch writes exactly the merged
    mapping, plain reads exactly what was written."""
    assert JsonCodec.plain(JsonCodec.patch(JsonCodec.empty(), d)) == d


@given(nested_dict())
@settings(max_examples=300)
def test_non_ascii_survives_dump(d):
    """Non-ASCII characters, astral-plane emoji included, come out of dump
    as themselves rather than as \\uXXXX escapes, and the fixed-point
    property from test_dump_is_a_fixed_point still holds for them."""
    contains_non_ascii = has_non_ascii(d)
    event("has non-ASCII" if contains_non_ascii else "ASCII only")

    once = JsonCodec.dump(JsonCodec.patch(JsonCodec.empty(), d))
    if contains_non_ascii:
        assert "\\u" not in once.decode("utf-8")

    doc = JsonCodec.load(once)
    twice = JsonCodec.dump(JsonCodec.patch(doc, JsonCodec.plain(doc)))
    assert twice == once
