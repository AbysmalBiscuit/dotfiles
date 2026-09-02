"""Reject rule sets that would silently discard curated values.

A baseline leaf resolving to ignore or passthrough is the failure this whole
design exists to prevent: the value sits in git looking authoritative while
the merge throws it away on every apply.
"""

from __future__ import annotations

from collections.abc import Iterator, Mapping

from engine.rules import RuleSet, Strategy


class LintError(Exception):
    pass


def descends(value: object) -> bool:
    """True when a value has members to walk into.

    Everything else is a leaf: a scalar, a list, and an empty mapping, which
    carries no member to classify. merge imports this so the engine cannot
    end up with two definitions of a leaf.
    """
    return isinstance(value, Mapping) and bool(value)


def leaves(data: Mapping) -> Iterator[tuple[tuple[str, ...], object]]:
    """Yield (path, value) for every leaf."""
    for key, value in data.items():
        if descends(value):
            for sub_path, sub_value in leaves(value):
                yield (key, *sub_path), sub_value
        else:
            yield (key,), value


def show(path: tuple[str, ...]) -> str:
    return ".".join(path)


def lint(baseline: Mapping, rules: RuleSet) -> None:
    for path, value in leaves(baseline):
        strategy = rules.resolve(path)

        if strategy in (Strategy.IGNORE, Strategy.PASSTHROUGH):
            raise LintError(
                f"{show(path)}: baseline value resolves to {strategy.value}, "
                "so the merge would discard it. Classify it as enforce, seed, "
                "or union, or remove it from the baseline."
            )

        if strategy is Strategy.UNION and not isinstance(value, list):
            raise LintError(
                f"{show(path)}: union requires a list in the baseline, "
                f"found {type(value).__name__}"
            )
