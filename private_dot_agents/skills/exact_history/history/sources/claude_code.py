"""Parser for Claude Code transcripts (~/.claude/projects/<slug>/<session>.jsonl)."""

import os
import re
from pathlib import Path

from ..model import Message, SessionState, cap
from . import jsonl

NAME = "cc"
LABEL = "claude-code"

SYSTEM_REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL)
COMMAND_NAME = re.compile(r"<command-name>(.*?)</command-name>", re.DOTALL)
COMMAND_ARGS = re.compile(r"<command-args>(.*?)</command-args>", re.DOTALL)
LOCAL_OUTPUT = re.compile(r"^<local-command-(stdout|stderr)>(.*)</local-command-\1>$", re.DOTALL)
ANSI = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]")

# Records carrying no conversational content: UI state, hook dumps, file snapshots.
SKIP_TYPES = {
    "attachment", "file-history-snapshot", "file-history-delta", "mode",
    "permission-mode", "last-prompt", "queue-operation", "pr-link", "system",
    "atis-latch", "fork-context-ref",
}


def roots() -> list[Path]:
    env = os.environ.get("HISTORY_CLAUDE_DIR")
    base = Path(env) if env else Path.home() / ".claude" / "projects"
    return [base] if base.is_dir() else []


def discover() -> list[Path]:
    return [p for root in roots() for p in root.rglob("*.jsonl")]


def probe_project(path: Path) -> str | None:
    """The transcript's working directory, without parsing the whole file.

    The opening records are UI state that carries no cwd, so this reads a few lines
    rather than only the first. The directory name is a lossy mangling of the same
    path and cannot be inverted, so it is not used here.
    """
    return jsonl.probe(path, lambda obj: obj.get("cwd"))


def session_id_for(path: Path) -> str | None:
    """Claude Code names each transcript after its session id."""
    return path.stem or None


def _clean(text: str) -> str:
    return SYSTEM_REMINDER.sub("", text).strip()


def _normalize_user(text: str) -> tuple[str, str]:
    """Unwrap the envelopes Claude Code puts around slash commands and their output.

    A typed `/unslop foo` is stored as a <command-name>/<command-args> pair, and shell
    output as <local-command-stdout>; both index better as what the user actually saw.
    """
    match = LOCAL_OUTPUT.match(text)
    if match:
        return "tool_result", ANSI.sub("", match.group(2)).strip()
    name = COMMAND_NAME.search(text)
    if name:
        args = COMMAND_ARGS.search(text)
        parts = [name.group(1).strip()]
        if args and args.group(1).strip():
            parts.append(args.group(1).strip())
        return "user", " ".join(parts)
    return "user", text


def _blocks(content) -> list:
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    if isinstance(content, list):
        return [b for b in content if isinstance(b, dict)]
    return []


def parse_line(obj: dict, state: SessionState, seq: int) -> list[Message]:
    kind = obj.get("type")
    if kind == "ai-title":
        state.title = obj.get("aiTitle") or state.title
        return []
    if kind in SKIP_TYPES or kind not in ("user", "assistant"):
        return []

    state.session_id = state.session_id or obj.get("sessionId")
    if obj.get("cwd"):
        state.project = obj["cwd"]
    branch = obj.get("gitBranch")
    if branch and branch != "HEAD":
        state.branch = branch

    ts = obj.get("timestamp")
    if ts:
        state.started = state.started or ts
        state.ended = ts

    side = bool(obj.get("isSidechain"))

    out: list[Message] = []
    speaker = "user" if kind == "user" else "assistant"
    if obj.get("isCompactSummary"):
        speaker = "summary"

    for block in _blocks((obj.get("message") or {}).get("content")):
        btype = block.get("type")
        if btype == "text":
            text = _clean(block.get("text") or "")
            if not text or obj.get("isMeta"):
                continue
            role = speaker
            if speaker == "user":
                role, text = _normalize_user(text)
            if text:
                out.append(Message(seq, role, text, ts, sidechain=side))
        elif btype == "thinking":
            text = (block.get("thinking") or "").strip()
            if text:
                out.append(Message(seq, "thinking", text, ts, sidechain=side))
        elif btype == "tool_use":
            name = block.get("name") or "tool"
            body = _render_input(block.get("input"))
            out.append(Message(seq, "tool", cap(f"{name} {body}"), ts, tool=name, sidechain=side))
        elif btype == "tool_result":
            text = _render_result(block.get("content"))
            if text:
                out.append(Message(seq, "tool_result", cap(text), ts, sidechain=side))
    return out


def _render_input(value) -> str:
    if not isinstance(value, dict):
        return str(value or "")
    parts = []
    for key, val in value.items():
        if isinstance(val, (dict, list)):
            val = str(val)
        parts.append(f"{key}={val}")
    return " ".join(parts)


def _render_result(content) -> str:
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        chunks = [
            b.get("text", "") for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        ]
        return "\n".join(c for c in chunks if c).strip()
    return ""
