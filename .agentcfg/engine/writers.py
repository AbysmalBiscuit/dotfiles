"""Write promoted values into the baselines and the rules files.

Every writer preserves what a hand-maintained file carries and the test
guards check: sorted keys in the JSON baseline, scalars before sub-tables in
the TOML baseline, and the comments and grouping in the rules files.
"""

from __future__ import annotations

import json
import sys
from collections.abc import Mapping, MutableMapping
from pathlib import Path

from engine.lint import descends
from engine.rules import Strategy

_VENDOR = Path(__file__).resolve().parent.parent / "vendor"
if str(_VENDOR) not in sys.path:
    sys.path.insert(0, str(_VENDOR))

import tomlkit  # noqa: E402  vendored, must follow the sys.path insert

# permissions rules match by category wherever they sit in the array, so the
# guard sorts them for readability and promote has to keep them that way.
_SORTED_ARRAYS = (("permissions", "allow"), ("permissions", "deny"))


def _set(data: dict, path: tuple[str, ...], value) -> None:
    cursor = data
    for segment in path[:-1]:
        nxt = cursor.get(segment)
        if not isinstance(nxt, dict):
            nxt = {}
            cursor[segment] = nxt
        cursor = nxt
    cursor[path[-1]] = value


def _canonical(value, in_array: bool = False):
    """Sort object keys everywhere the sort guard looks, and nowhere else.

    The guard does not descend into arrays, because element order there is
    data: hooks.* runs its entries in order. Sorting a dict inside one would
    reorder fields nothing asked about and bury the real change in churn.
    """
    if isinstance(value, dict):
        keys = value.keys() if in_array else sorted(value)
        return {key: _canonical(value[key], in_array) for key in keys}
    if isinstance(value, list):
        return [_canonical(item, True) for item in value]
    return value


def write_json_baseline(path: Path, additions) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    for target, value in additions:
        _set(data, target, value)
    for array_path in _SORTED_ARRAYS:
        cursor = data
        for segment in array_path[:-1]:
            cursor = cursor.get(segment) if isinstance(cursor, MutableMapping) else None
            if cursor is None:
                break
        if isinstance(cursor, MutableMapping) and isinstance(
            cursor.get(array_path[-1]), list
        ):
            cursor[array_path[-1]] = sorted(cursor[array_path[-1]])
    text = json.dumps(_canonical(data), indent=2, ensure_ascii=False) + "\n"
    path.write_text(text, encoding="utf-8", newline="\n")


def _is_table(item) -> bool:
    return isinstance(item, (dict, Mapping)) and not isinstance(item, str)


def _place(table, key: str, value) -> None:
    """Add key to a tomlkit table, keeping scalars ahead of sub-tables.

    TOML reparses a bare assignment written below a [section] header as a
    member of that section, so a scalar appended after one silently changes
    meaning. Rebuilding the table is the only ordering control tomlkit offers
    that does not reach into its private container API.
    """
    if key in table:
        table[key] = value
        return
    if _is_table(value) or not any(_is_table(v) for v in table.values()):
        table[key] = value
        return
    scalars = [(k, v) for k, v in table.items() if not _is_table(v)]
    tables = [(k, v) for k, v in table.items() if _is_table(v)]
    for existing, _ in scalars + tables:
        del table[existing]
    for k, v in scalars:
        table[k] = v
    table[key] = value
    for k, v in tables:
        table[k] = v


def write_toml_baseline(path: Path, additions) -> None:
    doc = tomlkit.parse(path.read_text(encoding="utf-8"))
    for target, value in additions:
        cursor = doc
        for segment in target[:-1]:
            if segment not in cursor or not _is_table(cursor[segment]):
                _place(cursor, segment, tomlkit.table())
            cursor = cursor[segment]
        _place(cursor, target[-1], value)
    path.write_text(tomlkit.dumps(doc), encoding="utf-8", newline="\n")


def _entry(pattern: tuple[str, ...]) -> str:
    return "  [" + ", ".join(json.dumps(segment) for segment in pattern) + "],"


def append_rules(path: Path, assignments) -> None:
    """Append patterns to their strategy blocks as plain text.

    tomlkit would reflow these files. They are hand-grouped, several patterns
    to a line in places, and carry comments explaining individual entries, so
    the text stays untouched apart from the inserted lines.
    """
    lines = path.read_text(encoding="utf-8").split("\n")
    for strategy, pattern in assignments:
        name = strategy.value if isinstance(strategy, Strategy) else str(strategy)
        header = f"{name} = ["
        start = next((i for i, line in enumerate(lines) if line.strip() == header), None)
        if start is None:
            if lines and lines[-1] == "":
                lines.pop()
            lines.extend([f"{name} = [", _entry(pattern), "]", ""])
            continue
        close = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == "]")
        lines.insert(close, _entry(pattern))
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")
