"""Parser for Codex CLI rollout transcripts (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl)."""

import json
import os
import re
from pathlib import Path

from ..model import Message, SessionState, cap
from . import jsonl

NAME = "cx"
LABEL = "codex"

# Codex injects instructions, environment, and plugin catalogs as user-role turns.
INJECTED_TAG = re.compile(r"^<[a-z][a-z0-9_]*>")
INJECTED_PREFIX = ("# AGENTS.md instructions", "Here is a list of plugin")

UUID_TAIL = re.compile(r"([0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})$")


def roots() -> list[Path]:
    env = os.environ.get("HISTORY_CODEX_DIR")
    base = Path(env) if env else Path.home() / ".codex" / "sessions"
    return [base] if base.is_dir() else []


def discover() -> list[Path]:
    return [p for root in roots() for p in root.rglob("*.jsonl")]


def probe_project(path: Path) -> str | None:
    """The rollout's working directory, taken from the session_meta record it opens with."""
    return jsonl.probe(path, lambda obj: (obj.get("payload") or {}).get("cwd"))


def session_id_for(path: Path) -> str | None:
    """Rollout filenames end in the session uuid: rollout-<timestamp>-<uuid>.jsonl."""
    match = UUID_TAIL.search(path.stem)
    return match.group(1) if match else None


def _is_injected(text: str) -> bool:
    return bool(INJECTED_TAG.match(text)) or text.startswith(INJECTED_PREFIX)


def _texts(blocks) -> list[str]:
    out = []
    for block in blocks or []:
        if isinstance(block, dict) and isinstance(block.get("text"), str):
            out.append(block["text"])
    return out


def _output_text(value) -> str:
    """Tool outputs arrive as a JSON-encoded content-block list, or as plain text."""
    if isinstance(value, dict):
        value = value.get("output", value.get("content", ""))
    if not isinstance(value, str):
        return str(value or "")
    stripped = value.lstrip()
    if stripped.startswith(("[", "{")):
        try:
            parsed = json.loads(stripped)
        except json.JSONDecodeError:
            return value
        if isinstance(parsed, list):
            joined = "\n".join(_texts(parsed))
            return joined or value
        if isinstance(parsed, dict):
            return _output_text(parsed) if "output" in parsed else value
    return value


def parse_line(obj: dict, state: SessionState, seq: int) -> list[Message]:
    kind = obj.get("type")
    payload = obj.get("payload") or {}
    ts = obj.get("timestamp") or payload.get("timestamp")

    if kind == "session_meta":
        state.session_id = payload.get("id") or state.session_id
        state.project = payload.get("cwd") or state.project
        git = payload.get("git") or {}
        state.branch = git.get("branch") or state.branch
        state.started = state.started or payload.get("timestamp")
        return []
    if kind == "turn_context":
        state.project = payload.get("cwd") or state.project
        return []
    if kind != "response_item":
        return []

    if ts:
        state.started = state.started or ts
        state.ended = ts

    ptype = payload.get("type")
    if ptype == "message":
        role = payload.get("role")
        if role not in ("user", "assistant"):
            return []
        out = []
        for text in _texts(payload.get("content")):
            text = text.strip()
            if not text or (role == "user" and _is_injected(text)):
                continue
            out.append(Message(seq, role, text, ts))
        return out
    if ptype in ("function_call", "custom_tool_call"):
        name = payload.get("name") or "tool"
        body = payload.get("arguments") or payload.get("input") or ""
        return [Message(seq, "tool", cap(f"{name} {body}"), ts, tool=name)]
    if ptype in ("function_call_output", "custom_tool_call_output"):
        text = _output_text(payload.get("output"))
        return [Message(seq, "tool_result", cap(text), ts)] if text.strip() else []
    return []
