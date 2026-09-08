"""Generate per-target rule schemas from the official agent config schemas.

A rule pattern is a list of key names, so constraining it needs the *names* of
another schema's properties as a string enum. JSON Schema has no operator that
produces that: $ref substitutes a schema for validating a value, and
propertyNames only applies to an object instance. So the key constraints cannot
reference the official schemas; they are derived from them here instead.

Run after an upstream schema changes:

    python3 .agentcfg/schema/generate.py
"""

from __future__ import annotations

import copy
import json
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

WILDCARD = "*"
MAX_DEPTH = 4
"""Segments to constrain. Covers the deepest pattern in use, tui.keymap.editor.x."""

BASE_SCHEMA = "agentcfg-rules.json"
HERE = Path(__file__).parent

Schema = dict[str, Any]


@dataclass(frozen=True)
class Target:
    slug: str
    target_file: str
    url: str


TARGETS = (
    Target(
        slug="claude",
        target_file="settings.json",
        url="https://json.schemastore.org/claude-code-settings.json",
    ),
    Target(
        slug="codex",
        target_file="config.toml",
        url="https://developers.openai.com/codex/config-schema.json",
    ),
)


@dataclass(frozen=True)
class Members:
    """What a schema node says about the keys directly under it."""

    properties: Schema
    free_form: Any
    closed: bool


def _deref(node: Any, root: Schema, seen: frozenset[str] = frozenset()) -> Schema:
    """Follow local $ref chains. A dangling or cyclic ref yields no members."""
    while isinstance(node, dict) and "$ref" in node:
        ref = node["$ref"]
        if not isinstance(ref, str) or not ref.startswith("#/") or ref in seen:
            return {}
        seen = seen | {ref}
        cursor: Any = root
        for raw in ref[2:].split("/"):
            part = raw.replace("~1", "/").replace("~0", "~")
            if not isinstance(cursor, dict) or part not in cursor:
                return {}
            cursor = cursor[part]
        node = cursor
    return node if isinstance(node, dict) else {}


def _members(node: Any, root: Schema, budget: int = 8) -> Members:
    """Read the keys under a node, flattening composition to find them.

    Upstream wraps most tables in allOf/$ref rather than spelling properties
    out inline, and a key valid in any anyOf branch is a key the rules may
    name. closed tracks additionalProperties being literally false, the only
    case where a name outside the list is certainly wrong.
    """
    resolved = _deref(node, root)
    if budget <= 0:
        return Members({}, None, False)

    properties: Schema = {}
    free_form: Any = None
    closed = False

    for keyword in ("allOf", "anyOf", "oneOf"):
        branches = resolved.get(keyword)
        if not isinstance(branches, list):
            continue
        for branch in branches:
            found = _members(branch, root, budget - 1)
            properties.update(found.properties)
            if found.free_form is not None and free_form is None:
                free_form = found.free_form
            closed = closed or found.closed

    own = resolved.get("properties")
    if isinstance(own, dict):
        properties.update(own)

    additional = resolved.get("additionalProperties")
    if isinstance(additional, dict):
        free_form = additional
    elif additional is False:
        closed = True

    return Members(properties, free_form, closed)


def _segment(names: list[str], closed: bool, target_file: str) -> Schema:
    """The schema for one path segment.

    An open table offers the same candidates as a closed one, but behind an
    anyOf branch that any string satisfies. Rejecting a name there would red-
    line working rules: schemastore lists 340 env vars and every other one is
    still a legal env var, and the settings.json root documents fewer keys
    than Claude actually accepts.
    """
    enum: Schema = {"enum": [*names, WILDCARD]}
    if closed:
        enum["description"] = (
            f"A key {target_file} declares at this depth, or {WILDCARD!r} for any key."
        )
        return enum
    return {
        "description": (
            f"A key {target_file} declares at this depth, {WILDCARD!r} for any "
            "key, or any other name: the official schema leaves this table "
            "open, so the listed keys are completion candidates, not the limit."
        ),
        "anyOf": [enum, {"type": "string", "minLength": 1}],
    }


def _constraint(node: Any, root: Schema, depth: int, target_file: str) -> Schema | None:
    """Constrain the segments from `depth` on, or None where nothing is known.

    A table with named properties pins the segment at this index to one of
    them. A map keyed by arbitrary names pins nothing at its own index and
    shifts its value's constraint one index right, which is what turns
    mcp_servers into mcp_servers.<any name>.enabled.
    """
    if depth >= MAX_DEPTH:
        return None

    members = _members(node, root)

    if members.properties:
        names = sorted(members.properties)
        constraint: Schema = {
            "prefixItems": [
                *([True] * depth),
                _segment(names, members.closed, target_file),
            ]
        }
        branches = []
        for name in names:
            child = _constraint(members.properties[name], root, depth + 1, target_file)
            if child is not None:
                branches.append(
                    {
                        "if": {"prefixItems": [*([True] * depth), {"const": name}]},
                        "then": child,
                    }
                )
        if branches:
            constraint["allOf"] = branches
        return constraint

    if members.free_form is not None:
        return _constraint(members.free_form, root, depth + 1, target_file)

    return None


def build(target: Target, upstream: Schema, base: Schema) -> Schema:
    """Fold the key constraints into a copy of the shared rule grammar.

    The grammar is inlined rather than $ref'd: a relative $ref resolves against
    $id, not against the file, so an editor would try to fetch the base over
    the network and fail on a schema that only exists in this checkout.
    """
    path = _constraint(upstream, upstream, 0, target.target_file)
    if path is None:
        raise SystemExit(f"{target.slug}: upstream schema exposes no properties")

    schema = copy.deepcopy(base)
    schema["$id"] = (
        "https://raw.githubusercontent.com/AbysmalBiscuit/dotfiles/main"
        f"/.agentcfg/schema/agentcfg-rules-{target.slug}.json"
    )
    schema["title"] = f"agentcfg rule set for {target.target_file}"
    schema["description"] = (
        f"{base['description']}\n\n"
        f"Every path segment is also checked against the keys {target.url} "
        f"declares for {target.target_file}, down to depth {MAX_DEPTH}; "
        "anything deeper is free-form. A table keyed by arbitrary names "
        "(mcp_servers, plugins, marketplaces) constrains nothing at its own "
        "index and checks the index after it against the value's keys, so the "
        '"enabled" in ["mcp_servers", "*", "enabled"] is checked. Where '
        "the official schema leaves a table open, its keys are offered as "
        "completion candidates without rejecting anything else.\n\n"
        f"Generated by .agentcfg/schema/generate.py from {BASE_SCHEMA}. "
        "Edit those, never this file."
    )

    schema["$defs"]["patternList"]["items"] = {
        "allOf": [{"$ref": "#/$defs/pattern"}, {"$ref": "#/$defs/path"}]
    }
    schema["properties"]["order"]["items"] = {
        "allOf": [schema["properties"]["order"]["items"], {"$ref": "#/$defs/path"}]
    }
    schema["$defs"]["path"] = {
        "title": "config path",
        "description": (
            f"Key segments into {target.target_file}, each checked against the "
            "keys the official schema declares at that depth."
        ),
        **path,
    }
    return schema


def main() -> None:
    base = json.loads((HERE / BASE_SCHEMA).read_text(encoding="utf-8"))
    for target in TARGETS:
        with urllib.request.urlopen(target.url) as response:  # noqa: S310
            upstream = json.load(response)
        out = HERE / f"agentcfg-rules-{target.slug}.json"
        out.write_text(json.dumps(build(target, upstream, base), indent=2) + "\n", encoding="utf-8")
        print(f"{out.name}: {out.stat().st_size:,} bytes from {target.url}")


if __name__ == "__main__":
    main()
