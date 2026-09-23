import os

from . import claude_code, codex

SOURCES = {mod.NAME: mod for mod in (claude_code, codex)}
LABELS = {mod.NAME: mod.LABEL for mod in (claude_code, codex)}


def resolve(names: list[str] | None):
    if not names:
        return list(SOURCES.values())
    picked = []
    for name in names:
        key = name.strip().lower()
        for short, mod in SOURCES.items():
            if key in (short, mod.LABEL):
                picked.append(mod)
                break
        else:
            raise SystemExit(f"unknown source {name!r}; expected one of {sorted(SOURCES)}")
    return picked


def current_harness() -> str:
    """Which CLI this process runs under, as a source name.

    Claude Code always exports CLAUDECODE. Codex exports no marker that is reliably
    present, so its detection is best-effort and HISTORY_HARNESS overrides both.
    """
    override = os.environ.get("HISTORY_HARNESS")
    if override:
        return override.strip().lower()[:2]
    if os.environ.get("CLAUDECODE"):
        return claude_code.NAME
    if os.environ.get("CODEX_SANDBOX") or os.environ.get("CODEX_HOME"):
        return codex.NAME
    return claude_code.NAME


def current_session() -> str | None:
    """The session this process belongs to, when the harness exposes it.

    Only Claude Code publishes one, so a Codex process reports none even if a stale
    CLAUDE_CODE_SESSION_ID is still in the environment.
    """
    override = os.environ.get("HISTORY_SESSION")
    if override:
        return override
    if current_harness() == claude_code.NAME:
        return os.environ.get("CLAUDE_CODE_SESSION_ID") or None
    return None
