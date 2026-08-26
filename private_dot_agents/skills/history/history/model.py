from dataclasses import dataclass, field


ROLES = ("user", "assistant", "thinking", "tool", "tool_result", "summary")

TOOL_TEXT_CAP = 2000


@dataclass
class Message:
    """One indexable unit of a transcript."""

    seq: int
    role: str
    text: str
    ts: str | None = None
    tool: str | None = None
    sidechain: bool = False


@dataclass
class SessionState:
    """Session-level facts discovered while parsing, carried across incremental runs."""

    session_id: str | None = None
    project: str | None = None
    branch: str | None = None
    title: str | None = None
    started: str | None = None
    ended: str | None = None
    extra: dict = field(default_factory=dict)


def cap(text: str, limit: int = TOOL_TEXT_CAP) -> str:
    text = text.strip()
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n[+{len(text) - limit} chars truncated]"
