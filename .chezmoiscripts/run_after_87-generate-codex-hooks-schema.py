#!/usr/bin/env python3
"""Generate the JSON schema for Codex hooks.json files from the Codex source.

Codex publishes a schema only for the `[hooks]` table of config.toml. That
definition leaves unknown events open and admits `state`, a key only
config.toml accepts. A hooks.json holds an optional description beside the
event map, and Codex rejects any other top-level key. The schema written here
takes the event names and handler definitions from upstream on every apply and
closes both objects, so a misspelled event or stray key is flagged.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.request
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Iterator

SOURCE_URL = "https://api.github.com/repos/openai/codex/contents/codex-rs/core/config.schema.json"
TIMEOUT_SECONDS = 30
DEFINITION_PREFIX = "#/definitions/"
MATCHER_GROUP = "MatcherGroup"


def warn(message: str) -> None:
    print(f"codex-hooks-schema: {message}", file=sys.stderr)


def schema_path() -> Path:
    config_home = os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config"
    return Path(config_home) / "schemas" / "codex-hooks.json"


def fetch_config_schema() -> dict[str, Any]:
    headers = {
        "Accept": "application/vnd.github.raw+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("CHEZMOI_GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(SOURCE_URL, headers=headers)  # noqa: S310
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:  # noqa: S310
        return json.load(response)


def references(node: object) -> Iterator[str]:
    if isinstance(node, dict):
        ref = node.get("$ref")
        if isinstance(ref, str) and ref.startswith(DEFINITION_PREFIX):
            yield ref.removeprefix(DEFINITION_PREFIX)
        for value in node.values():
            yield from references(value)
    elif isinstance(node, list):
        for item in node:
            yield from references(item)


def reachable_definitions(definitions: dict[str, Any], root: str) -> dict[str, Any]:
    found: dict[str, Any] = {}
    pending = [root]
    while pending:
        name = pending.pop()
        if name not in found:
            found[name] = definitions[name]
            pending.extend(references(found[name]))
    return dict(sorted(found.items()))


def build_schema(config_schema: dict[str, Any]) -> dict[str, Any]:
    definitions = config_schema["definitions"]
    events = {
        name: event
        for name, event in definitions["HooksToml"]["properties"].items()
        if event.get("items", {}).get("$ref") == DEFINITION_PREFIX + MATCHER_GROUP
    }
    if not events:
        msg = "HooksToml lists no hook events"
        raise ValueError(msg)

    return {
        "$schema": config_schema["$schema"],
        "title": "Codex hooks.json",
        "description": "Codex lifecycle hooks, generated from the Codex config schema.",
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "description": {"type": "string"},
            "hooks": {
                "type": "object",
                "additionalProperties": False,
                "properties": events,
            },
        },
        "definitions": reachable_definitions(definitions, MATCHER_GROUP),
    }


def main() -> int:
    try:
        schema = build_schema(fetch_config_schema())
    except (OSError, ValueError, KeyError, AttributeError) as error:
        warn(f"kept the existing schema, could not build one from {SOURCE_URL}: {error}")
        return 0

    rendered = json.dumps(schema, indent=2) + "\n"
    path = schema_path()
    if path.is_file() and path.read_text(encoding="utf-8") == rendered:
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(rendered, encoding="utf-8")
    print(f"codex-hooks-schema: wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
