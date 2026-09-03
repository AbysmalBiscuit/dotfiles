"""Path-segment patterns mapped to merge strategies."""

from __future__ import annotations

import enum
import tomllib
from dataclasses import dataclass
from pathlib import Path

WILDCARD = "*"


class Strategy(str, enum.Enum):
    ENFORCE = "enforce"
    SEED = "seed"
    UNION = "union"
    IGNORE = "ignore"
    REMOVE = "remove"
    PASSTHROUGH = "passthrough"


DECLARABLE = (
    Strategy.ENFORCE,
    Strategy.SEED,
    Strategy.UNION,
    Strategy.IGNORE,
    Strategy.REMOVE,
)


def score(pattern: list[str], path: tuple[str, ...]) -> tuple[int, int] | None:
    """Rank a matching pattern: segments consumed, then literal segments.

    Returns None when the pattern does not match. A pattern longer than the
    path never matches; a pattern shorter than the path matches its prefix,
    which is how ["env", "*"] governs every leaf under env.
    """
    if len(pattern) > len(path):
        return None
    for pat_seg, path_seg in zip(pattern, path):
        if pat_seg != WILDCARD and pat_seg != path_seg:
            return None
    return (len(pattern), sum(1 for s in pattern if s != WILDCARD))


def _ties(a: tuple[str, ...], b: tuple[str, ...]) -> bool:
    """True when two patterns always score equally on the paths both match.

    Checked once at load rather than per path, so a tie is caught even on a
    live-only path the baseline never mentions and the lint never walks.
    """
    if len(a) != len(b):
        return False
    literals = lambda pattern: sum(1 for s in pattern if s != WILDCARD)
    if literals(a) != literals(b):
        return False
    return all(x == WILDCARD or y == WILDCARD or x == y for x, y in zip(a, b))


@dataclass(frozen=True)
class RuleSet:
    patterns: tuple[tuple[Strategy, tuple[str, ...]], ...]

    @classmethod
    def load(cls, path: Path) -> RuleSet:
        raw = tomllib.loads(path.read_text(encoding="utf-8"))
        declarable = {s.value for s in DECLARABLE}
        collected: list[tuple[Strategy, tuple[str, ...]]] = []
        for key, value in raw.items():
            if key not in declarable:
                raise ValueError(
                    f"unknown strategy {key!r} in {path}; "
                    f"expected one of {sorted(declarable)}"
                )
            for pattern in value:
                if not isinstance(pattern, list):
                    raise ValueError(
                        f"{path}: pattern in {key!r} must be a list of strings, "
                        f"got {pattern!r}"
                    )
                for segment in pattern:
                    if not isinstance(segment, str):
                        raise ValueError(
                            f"{path}: pattern in {key!r} contains non-string segment, "
                            f"got {segment!r}"
                        )
                collected.append((Strategy(key), tuple(pattern)))
        for i, (strategy_a, pattern_a) in enumerate(collected):
            for strategy_b, pattern_b in collected[i + 1 :]:
                if strategy_a is not strategy_b and _ties(pattern_a, pattern_b):
                    raise ValueError(
                        f"{path}: {list(pattern_a)} and {list(pattern_b)} score "
                        f"equally on every path they both match but declare "
                        f"{strategy_a.value} and {strategy_b.value}; make one "
                        "deeper or more literal"
                    )
        return cls(patterns=tuple(collected))

    def patterns_for(
        self, path: tuple[str, ...]
    ) -> list[tuple[tuple[int, int], Strategy, tuple[str, ...]]]:
        """Every matching pattern with its score, best first."""
        matches = []
        for strategy, pattern in self.patterns:
            s = score(list(pattern), path)
            if s is not None:
                matches.append((s, strategy, pattern))
        matches.sort(key=lambda m: m[0], reverse=True)
        return matches

    def resolve(self, path: tuple[str, ...]) -> Strategy:
        matches = self.patterns_for(path)
        if not matches:
            return Strategy.PASSTHROUGH
        return matches[0][1]

    def removes(self, path: tuple[str, ...]) -> bool:
        """True when this path, or a container above it, resolves to remove.

        A deeper pattern outscores a remove rule on an ancestor, so resolving
        the leaf alone would miss it: ["plugins", "*", "enabled"] wins on
        plugins.x.enabled even where ["plugins", "x"] is declared removed.
        """
        return any(
            self.resolve(path[:depth]) is Strategy.REMOVE
            for depth in range(1, len(path) + 1)
        )
