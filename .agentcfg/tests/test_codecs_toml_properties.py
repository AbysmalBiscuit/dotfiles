"""Property tests for TomlCodec.

Unlike JsonCodec, dumping is not a fixed point here - tomlkit preserves
arbitrary source formatting, so the property that matters is stronger:
merging a document's own values back into itself must reproduce the exact
source bytes, comments, blank lines and all. That is the guarantee a
`chezmoi apply` with no config drift relies on.

The generator below emits TOML *source text* directly - it does not build
Python dicts and serialize them with tomlkit. Serializing dicts could only
ever produce tomlkit's own canonical formatting, which would make the
no-change round trip trivially true and never exercise layout preservation
at all (comment placement, blank lines, multi-line arrays, dotted keys).
Every document is assembled line by line from a single pool of globally
unique bare keys, so no two entries anywhere in a document - root keys,
table and array-of-table names, nested table bodies, inline-table keys -
can collide on the same name.
"""

from __future__ import annotations

import string

from hypothesis import event, given, settings, strategies as st

from engine.codecs import TomlCodec

STRING_ASCII = string.ascii_letters + string.digits + " _-.,!?"
# Latin-1 supplement, CJK, and astral-plane emoji (single Python code
# points, not UTF-16 surrogate pairs - TOML/UTF-8 needs no escaping for any
# of these).
STRING_NONASCII = "áéîõü中文日本語🤖🚀💥"
COMMENT_WORDS = [
    "note",
    "todo",
    "fixme",
    "keep this",
    "see docs",
    "important",
    "why: ordering",
    "非ASCII",
    "emoji 🚀",
]


def _bare_key():
    first = st.text(alphabet=string.ascii_lowercase, min_size=1, max_size=1)
    rest = st.text(alphabet=string.ascii_lowercase + string.digits + "_", min_size=1, max_size=5)
    return st.builds(lambda a, b: a + b, first, rest)


def _weighted(data, options):
    """Draw from a list of (weight, value) pairs; zero-weight entries drop out."""
    pool = [v for w, v in options for _ in range(w)]
    return data.draw(st.sampled_from(pool))


def _biased_bool(data, true_out_of, total):
    return data.draw(st.sampled_from([True] * true_out_of + [False] * (total - true_out_of)))


def _comment_text(data):
    return data.draw(st.sampled_from(COMMENT_WORDS))


class _KeyPool:
    """A single reservoir of globally-unique bare keys.

    Every key used anywhere in a generated document - root entries, table
    and array-of-table names, nested bodies, inline-table keys - is drawn
    from here exactly once, so entries in unrelated scopes can never
    collide on the same name (which would make the document invalid TOML,
    not merely differently formatted).

    Uniqueness comes from a zero-padded index suffix rather than
    Hypothesis's ``unique=True`` list constraint: two full keys can only be
    equal if their fixed-width suffixes are equal, which requires equal
    indices, which never happens across a single draw. This is a plain,
    retry-free draw instead of a filtered one, which is what ``unique=True``
    would otherwise need to satisfy on every element.
    """

    def __init__(self, data, size=80):
        bases = data.draw(st.lists(_bare_key(), min_size=size, max_size=size))
        self._keys = [f"{base}_{i:03d}" for i, base in enumerate(bases)]
        self._idx = 0

    def remaining(self):
        return len(self._keys) - self._idx

    def take(self):
        k = self._keys[self._idx]
        self._idx += 1
        return k

    def maybe_dotted(self, data):
        if self.remaining() >= 2 and _biased_bool(data, 1, 4):
            return f"{self.take()}.{self.take()}"
        return self.take()


def _toml_escape(s: str) -> str:
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        else:
            out.append(ch)
    return "".join(out)


def _gen_string(data):
    base = data.draw(st.text(alphabet=STRING_ASCII, min_size=0, max_size=8))
    extra = _weighted(data, [(3, "none"), (2, "quote"), (2, "backslash"), (2, "nonascii")])
    if extra != "none":
        ch = {"quote": '"', "backslash": "\\"}.get(extra) or data.draw(st.sampled_from(STRING_NONASCII))
        pos = data.draw(st.integers(min_value=0, max_value=len(base)))
        base = base[:pos] + ch + base[pos:]
    return '"' + _toml_escape(base) + '"'


def _gen_int(data):
    return str(data.draw(st.integers(min_value=-1_000_000, max_value=1_000_000)))


def _gen_float(data):
    n = data.draw(st.floats(min_value=-1e6, max_value=1e6, allow_nan=False, allow_infinity=False, width=32))
    s = repr(float(n))
    if "e" not in s and "E" not in s and "." not in s:
        s += ".0"
    return s


def _gen_bool(data):
    return "true" if data.draw(st.booleans()) else "false"


def _gen_array(data, pool, depth):
    n = data.draw(st.integers(min_value=0, max_value=4))
    items = [_gen_value(data, pool, depth + 1) for _ in range(n)]
    if items and data.draw(st.booleans()):
        lines = []
        for it in items:
            line = f"    {it},"
            if _biased_bool(data, 1, 5):
                line += f"  # {_comment_text(data)}"
            lines.append(line)
        return "[\n" + "\n".join(lines) + "\n]"
    return "[" + ", ".join(items) + "]"


def _gen_inline_table(data, pool, depth):
    n = min(data.draw(st.integers(min_value=0, max_value=3)), max(0, pool.remaining() - 1))
    keys = [pool.take() for _ in range(n)]
    if not keys:
        return "{}"
    parts = [f"{k} = {_gen_value(data, pool, depth + 1)}" for k in keys]
    return "{ " + ", ".join(parts) + " }"


def _gen_value(data, pool, depth):
    kind = _weighted(
        data,
        [
            (3, "string"),
            (2, "int"),
            (1, "float"),
            (4, "bool"),
            (2 if depth < 2 else 0, "array"),
            (2 if depth < 2 else 0, "inline_table"),
        ],
    )
    if kind == "string":
        return _gen_string(data)
    if kind == "int":
        return _gen_int(data)
    if kind == "float":
        return _gen_float(data)
    if kind == "bool":
        return _gen_bool(data)
    if kind == "array":
        return _gen_array(data, pool, depth)
    return _gen_inline_table(data, pool, depth)


def _gen_keyval_entry(data, pool, key):
    lines = []
    if _biased_bool(data, 1, 4):
        lines.append(f"# {_comment_text(data)}")
    line = f"{key} = {_gen_value(data, pool, 0)}"
    if _biased_bool(data, 1, 4):
        line += f"  # {_comment_text(data)}"
    lines.append(line)
    return lines


def _gen_entries(data, pool, n_min, n_max):
    """A run of key/value, standalone-comment, and blank-line lines."""
    lines = []
    n = data.draw(st.integers(min_value=n_min, max_value=n_max))
    for _ in range(n):
        if pool.remaining() < 1:
            break
        kind = _weighted(data, [(6, "keyval"), (2, "comment"), (1, "blank")])
        if kind == "comment":
            lines.append(f"# {_comment_text(data)}")
        elif kind == "blank":
            lines.append("")
        else:
            lines.extend(_gen_keyval_entry(data, pool, pool.maybe_dotted(data)))
    return lines


def _gen_table_block(path, data, pool):
    return [f"[{'.'.join(path)}]", *_gen_entries(data, pool, 0, 4)]


def _gen_aot_block(path, data, pool):
    header = "[[" + ".".join(path) + "]]"
    lines = []
    for row in range(data.draw(st.integers(min_value=1, max_value=3))):
        if row > 0 and _biased_bool(data, 1, 3):
            lines.append("")
        lines.append(header)
        lines.extend(_gen_entries(data, pool, 0, 3))
    return lines


@st.composite
def toml_text(draw):
    """A syntactically valid TOML document, assembled as source text with
    randomized layout: root-level (possibly dotted) keys, nested tables,
    arrays of tables, inline tables, multi-line arrays, comments in
    several positions, and blank lines between sections."""
    data = draw(st.data())
    pool = _KeyPool(data, size=80)
    lines = _gen_entries(data, pool, 0, 4)

    for section in range(data.draw(st.integers(min_value=1, max_value=3))):
        if lines and _biased_bool(data, 3, 5):
            lines.append("")
        if pool.remaining() < 1:
            break
        parent = pool.take()
        kind = _weighted(data, [(3, "table"), (2, "table_nested"), (2, "aot"), (2, "table_with_aot")])
        if kind == "table":
            lines.extend(_gen_table_block([parent], data, pool))
        elif kind == "table_nested":
            lines.extend(_gen_table_block([parent], data, pool))
            if pool.remaining() >= 1:
                child = pool.take()
                lines.append("")
                lines.extend(_gen_table_block([parent, child], data, pool))
        elif kind == "aot":
            lines.extend(_gen_aot_block([parent], data, pool))
        else:
            lines.extend(_gen_table_block([parent], data, pool))
            if pool.remaining() >= 1:
                child = pool.take()
                lines.append("")
                lines.extend(_gen_aot_block([parent, child], data, pool))

    text = "\n".join(lines)
    return text + "\n" if text and not text.endswith("\n") else text


def _tag_shape(raw: str) -> None:
    event("has array-of-tables" if "[[" in raw else "no array-of-tables")
    event("has comment" if "#" in raw else "no comment")
    event("has boolean" if (" true" in raw or " false" in raw) else "no boolean")


@given(toml_text())
@settings(max_examples=300)
def test_no_change_round_trip_is_byte_identical(raw):
    """dump(patch(load(raw), plain(load(raw)))) == raw.

    Merging a document's own values back into itself must rewrite nothing:
    no reordered keys, no dropped comments, no renumbered blank lines.
    """
    _tag_shape(raw)
    raw_bytes = raw.encode("utf-8")
    doc = TomlCodec.load(raw_bytes)
    assert TomlCodec.dump(TomlCodec.patch(doc, TomlCodec.plain(doc))) == raw_bytes


TOML_SCALAR = st.one_of(
    st.text(alphabet=STRING_ASCII + STRING_NONASCII, min_size=0, max_size=8),
    st.integers(min_value=-1_000_000, max_value=1_000_000),
    st.floats(min_value=-1e6, max_value=1e6, allow_nan=False, allow_infinity=False, width=32),
    st.booleans(),
)
TOML_LEAF = st.one_of(TOML_SCALAR, st.lists(TOML_SCALAR, max_size=4))
TOML_KEY = st.text(alphabet=STRING_ASCII + STRING_NONASCII, min_size=1, max_size=8)


@st.composite
def toml_plain_dict(draw):
    """A plain dict with the shapes TomlCodec.plain can actually produce:
    string/int/float/bool/list values, and nested dicts of the same shape
    (TOML, unlike JSON, has no null)."""
    depth = draw(st.integers(min_value=0, max_value=2))
    values = TOML_LEAF
    for _ in range(depth):
        values = st.one_of(TOML_LEAF, st.dictionaries(TOML_KEY, values, max_size=4))
    return draw(st.dictionaries(TOML_KEY, values, max_size=4))


def _assert_types_match(a, b):
    """Recursive companion to `==`: catches the type slips plain equality
    cannot, chiefly bool vs. int (`True == 1` in Python)."""
    assert type(a) is type(b), f"{a!r} ({type(a)}) vs {b!r} ({type(b)})"
    if isinstance(a, dict):
        for key in a:
            _assert_types_match(a[key], b[key])
    elif isinstance(a, list):
        for x, y in zip(a, b):
            _assert_types_match(x, y)


@given(toml_plain_dict())
@settings(max_examples=300)
def test_plain_patch_round_trip(d):
    """plain(patch(empty(), d)) == d: patch writes exactly the merged
    mapping, plain reads exactly what was written - types included, so a
    bool merged in cannot come back as an int."""
    result = TomlCodec.plain(TomlCodec.patch(TomlCodec.empty(), d))
    assert result == d
    _assert_types_match(result, d)
