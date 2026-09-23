"""Cheap reads over a transcript's opening records, shared by the source parsers."""

import json
from pathlib import Path

# Both formats put the working directory in their first handful of records; Claude Code
# opens with UI state that carries none, so reading only line one is not enough.
PROBE_LINES = 40


def probe(path: Path, pick) -> str | None:
    """The first truthy value `pick` returns over the opening records, or None."""
    try:
        with path.open("rb") as fh:
            for _, raw in zip(range(PROBE_LINES), fh):
                try:
                    obj = json.loads(raw)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    continue
                if isinstance(obj, dict):
                    found = pick(obj)
                    if found:
                        return found
    except OSError:
        pass
    return None
