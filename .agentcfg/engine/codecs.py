"""Load and dump config files as bytes.

Bytes rather than str because Python's text-mode stdout on Windows would
translate every LF to CRLF and make chezmoi diff permanently non-empty.
"""

from __future__ import annotations

import json
from collections.abc import Mapping


class CodecError(Exception):
    pass


class JsonCodec:
    @staticmethod
    def load(raw: bytes) -> dict:
        try:
            data = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise CodecError(f"cannot parse JSON: {exc}") from exc
        if not isinstance(data, dict):
            raise CodecError(f"expected a mapping at the top level, got {type(data).__name__}")
        return data

    @staticmethod
    def plain(doc: dict) -> dict:
        return doc

    @staticmethod
    def patch(doc: dict, merged: Mapping) -> dict:
        return dict(merged)

    @staticmethod
    def dump(data: Mapping) -> bytes:
        return json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8") + b"\n"

    @staticmethod
    def empty() -> dict:
        return {}


import sys
from pathlib import Path

_VENDOR = Path(__file__).resolve().parent.parent / "vendor"
if str(_VENDOR) not in sys.path:
    sys.path.insert(0, str(_VENDOR))

import tomlkit  # noqa: E402  vendored, must follow the sys.path insert


def _unwrap(value):
    unwrap = getattr(value, "unwrap", None)
    return unwrap() if callable(unwrap) else value


def _patch_table(table, merged: Mapping) -> None:
    """Write plain values into a tomlkit table, keeping its layout.

    Assigning over an existing key keeps that key's position and trivia, so a
    no-change merge rewrites nothing and dumps byte-identically. The left side
    of the comparison is a value read back out of the tomlkit document, which
    may or may not be the same type as the right side's plain merged value,
    depending on which types the tomlkit version in use hands back wrapped.
    Unwrapping first makes the comparison correct either way.
    """
    for key in [k for k in table if k not in merged]:
        del table[key]
    for key, value in merged.items():
        if key not in table:
            table[key] = value
        elif isinstance(value, Mapping) and isinstance(table[key], Mapping):
            _patch_table(table[key], value)
        elif _unwrap(table[key]) != value:
            table[key] = value


class TomlCodec:
    @staticmethod
    def load(raw: bytes):
        try:
            return tomlkit.parse(raw.decode("utf-8"))
        except Exception as exc:
            raise CodecError(f"cannot parse TOML: {exc}") from exc

    @staticmethod
    def plain(doc) -> dict:
        return doc.unwrap()

    @staticmethod
    def patch(doc, merged: Mapping):
        _patch_table(doc, merged)
        return doc

    @staticmethod
    def dump(doc) -> bytes:
        return tomlkit.dumps(doc).encode("utf-8")

    @staticmethod
    def empty():
        return tomlkit.document()
