import json
import os
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]

WRAPPERS = [
    ("private_dot_claude/modify_settings.json.py", "tests/fixtures/claude_settings.json"),
    ("dot_codex/modify_private_config.toml.py", "tests/fixtures/codex_config.toml"),
]


@pytest.mark.parametrize("wrapper_rel,fixture_rel", WRAPPERS)
def test_wrapper_runs_from_tempdir(tmp_path, wrapper_rel, fixture_rel):
    """chezmoi copies the script to a temp file and sets no working directory.

    __file__ therefore points into the temp dir, and only the CHEZMOI_*
    variables can find the baseline. The source tree is copied into tmp_path
    so the assertions do not depend on the repo's real baseline, and so the
    __pycache__ check sees a tree pytest has not already imported from.
    """
    source = tmp_path / "src"
    shutil.copytree(
        REPO / ".agentcfg",
        source / ".agentcfg",
        ignore=shutil.ignore_patterns("__pycache__", "tests"),
    )
    wrapper_dir = source / Path(wrapper_rel).parent
    wrapper_dir.mkdir(parents=True)
    for name in (REPO / Path(wrapper_rel).parent).iterdir():
        if name.name.startswith(".") or name.name.startswith("modify_"):
            shutil.copy(name, wrapper_dir / name.name)

    temp_script = tmp_path / f"928374.{Path(wrapper_rel).name}"
    shutil.copy(REPO / wrapper_rel, temp_script)

    fixture = (REPO / ".agentcfg" / fixture_rel).read_bytes()

    env = os.environ | {
        "CHEZMOI_SOURCE_DIR": str(source),
        "CHEZMOI_SOURCE_FILE": wrapper_rel,
        "CHEZMOI_DEST_DIR": str(tmp_path / "home"),
    }

    result = subprocess.run(
        [sys.executable, str(temp_script)],
        input=fixture,
        capture_output=True,
        env=env,
        cwd=str(tmp_path),
    )

    assert result.returncode == 0, result.stderr.decode()
    assert result.stdout == fixture
    assert not list(source.rglob("__pycache__")), (
        "the wrapper wrote bytecode into the source tree; "
        "sys.dont_write_bytecode must be set before the engine imports"
    )


def _first_mismatch(actual, expected):
    """Return (position, actual_item, expected_item) at the first place the
    two sequences diverge, or None when they match. `expected` is supplied
    by the caller rather than computed here, since JSON objects and TOML
    tables sort by different rules (see the two tests below).
    """
    for position, (item, want) in enumerate(zip(actual, expected)):
        if item != want:
            return position, item, want
    return None


def _iter_json_objects(value, path=()):
    """Yield (path, keys) for every JSON object in value, in file order.

    Does not descend into arrays: element order there is meaningful data
    (hooks.* runs its entries in order), so a dict living inside a list
    keeps whatever key order it already has.
    """
    if isinstance(value, dict):
        yield path, list(value.keys())
        for key, sub_value in value.items():
            yield from _iter_json_objects(sub_value, path + (key,))


def test_claude_baseline_is_sorted():
    """Every object in the Claude baseline sorts its keys, at every depth,
    and so do permissions.allow and permissions.deny.

    A readability guard, not a correctness one: baseline key order reaches
    the merge output only where enforce copies a baseline container
    verbatim, and permission rules match by category regardless of their
    position in the array. Every other array keeps its order, which is
    data. The TOML baseline needs a different rule; see
    test_codex_baseline_is_sorted.
    """
    path = REPO / "private_dot_claude" / ".settings.baseline.json"
    baseline = json.loads(path.read_text(encoding="utf-8"))

    for obj_path, keys in _iter_json_objects(baseline):
        mismatch = _first_mismatch(keys, sorted(keys))
        if mismatch is None:
            continue
        position, actual, want = mismatch
        location = ".".join(obj_path) or "the root object"
        assert False, (
            f"{path.name}: object at {location!r} has key {actual!r} at "
            f"position {position}, expected {want!r} there. Fix: sort this "
            f"object's keys alphabetically."
        )

    for array_path in (("permissions", "allow"), ("permissions", "deny")):
        cursor = baseline
        for segment in array_path:
            cursor = cursor[segment]
        mismatch = _first_mismatch(cursor, sorted(cursor))
        if mismatch is None:
            continue
        position, actual, want = mismatch
        location = ".".join(array_path)
        assert False, (
            f"{path.name}: array {location!r} has entry {actual!r} at "
            f"position {position}, expected {want!r} there. Fix: sort this "
            f"array's entries alphabetically."
        )


def _is_toml_header_value(value):
    """True when a TOML key's value is a table or an array of tables.

    Such a value is normally written with header syntax, and inline forms
    like `key = [{a = 1}]` parse to the same shape. Either way it has to
    follow the table's bare assignments, so both count as a header here.
    """
    if isinstance(value, dict):
        return True
    return isinstance(value, list) and bool(value) and all(
        isinstance(item, dict) for item in value
    )


def _iter_toml_tables(table, path=()):
    """Yield (path, table) for every TOML table in table, in file order.

    Does not descend into array-of-tables entries, for the same reason
    _iter_json_objects does not descend into arrays: hooks.* runs its
    entries in order, so this rule reaches no further than the key that
    names the array.
    """
    if isinstance(table, dict):
        yield path, table
        for key, value in table.items():
            if isinstance(value, dict):
                yield from _iter_toml_tables(value, path + (key,))


def test_codex_baseline_is_sorted():
    """Within each table of the Codex baseline, scalar keys come first in
    alphabetical order, then sub-tables in alphabetical order.

    A plain alphabetical sort would corrupt this file. TOML requires a
    table's bare `key = value` assignments to precede its first [section]
    header, so sorting a scalar below a header moves that key into the
    section, which parses as valid TOML and is silently the wrong config.
    Ordering scalars first keeps a hand sort from producing that.

    The rule is what this checks. It cannot detect a key that was already
    swallowed, because the swallowed key and a legitimate member of that
    section are the same document; the parse holds nothing to tell them
    apart.
    """
    path = REPO / "dot_codex" / ".config.baseline.toml"
    baseline = tomllib.loads(path.read_text(encoding="utf-8"))

    for table_path, table in _iter_toml_tables(baseline):
        actual = list(table.keys())
        scalars = [k for k in actual if not _is_toml_header_value(table[k])]
        headers = [k for k in actual if _is_toml_header_value(table[k])]
        expected = sorted(scalars) + sorted(headers)
        mismatch = _first_mismatch(actual, expected)
        if mismatch is None:
            continue
        position, actual_key, want_key = mismatch
        location = ".".join(table_path) or "the root table"
        assert False, (
            f"{path.name}: table {location!r} has key {actual_key!r} at "
            f"position {position}, expected {want_key!r} there. Fix: order "
            f"this table as scalar-valued keys first (alphabetically), "
            f"then sub-tables (alphabetically). Not a plain alphabetical "
            f"sort, because a bare key = value assignment after a "
            f"[section] header in the same table gets silently reparsed as "
            f"belonging to that section."
        )
