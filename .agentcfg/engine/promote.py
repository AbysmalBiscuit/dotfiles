"""Turn the drift check into an editable worklist.

check.py names the live paths no rule owns. This module attaches each one's
value, screens what must never reach a public repo, and writes the choices
back into the baseline and the rules file.
"""

from __future__ import annotations

import math
import re
from collections import Counter
from collections.abc import Mapping
from dataclasses import dataclass

from engine.check import CheckReport, _get
from engine.rules import Strategy

UNCLASSIFIED = "unclassified"
LIVE_ONLY = "live-only"

# A segment naming a credential. The engine publishes into a public repo, so
# these are refused by default rather than merely warned about.
SECRET_SEGMENT = re.compile(
    r"(?:^|[._-])(?:token|secret|password|passwd|credential|bearer|apikey|api_key|key)"
    r"(?:$|[._-])|(?:_|^)(?:token|secret|key)s?$",
    re.IGNORECASE,
)

# Entropy alone flags too much. A value has to be long, dense, and free of the
# structure that marks a path, a URL, or prose before it counts as a secret.
_ENTROPY_FLOOR = 3.6
_LENGTH_FLOOR = 24
_STRUCTURED = re.compile(r"[\s/]|^https?://")


@dataclass(frozen=True)
class Candidate:
    """One live path the repo has no opinion about."""

    path: tuple[str, ...]
    value: object
    kind: str
    secret: str | None = None

    @property
    def blocked(self) -> bool:
        return self.secret is not None


def _shannon(text: str) -> float:
    counts = Counter(text)
    n = len(text)
    return -sum((c / n) * math.log2(c / n) for c in counts.values())


def screen(path: tuple[str, ...], value: object) -> str | None:
    """Why this value must not be written to a public repo, or None."""
    for segment in path:
        if SECRET_SEGMENT.search(segment):
            return f"path segment {segment!r} names a credential"
    for text in _strings(value):
        if (
            len(text) >= _LENGTH_FLOOR
            and not _STRUCTURED.search(text)
            and chr(92) not in text
            and _shannon(text) >= _ENTROPY_FLOOR
        ):
            return f"value looks like a high-entropy secret ({len(text)} chars)"
    return None


def _strings(value: object):
    if isinstance(value, str):
        yield value
    elif isinstance(value, Mapping):
        for sub in value.values():
            yield from _strings(sub)
    elif isinstance(value, list):
        for sub in value:
            yield from _strings(sub)


def candidates(live: Mapping, report: CheckReport) -> list[Candidate]:
    """Every path the report flagged, with its live value and screening verdict.

    unclassified paths carry a leaf; live-only paths carry the whole subtree
    the winning pattern claims, which is the unit the baseline stores.
    """
    found: list[Candidate] = []
    for kind, paths in ((UNCLASSIFIED, report.unclassified), (LIVE_ONLY, report.live_only)):
        for path in paths:
            value, present = _get(live, path)
            if not present:
                continue
            found.append(Candidate(path, value, kind, screen(path, value)))
    return found


DEFAULT_STRATEGY = {UNCLASSIFIED: Strategy.SEED, LIVE_ONLY: Strategy.ENFORCE}
