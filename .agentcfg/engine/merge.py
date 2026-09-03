"""Build a new mapping from a curated baseline and whatever the app wrote.

Both inputs are read-only. false, 0, and "" are ordinary values that seed
leaves alone.
"""

from __future__ import annotations

import copy
from collections.abc import Mapping

from engine.lint import descends
from engine.rules import RuleSet, Strategy, score


def merge(baseline: Mapping, live: Mapping, rules: RuleSet) -> dict:
    return _merge_level(baseline, live, rules, ())


def _merge_level(
    baseline: Mapping, live: Mapping, rules: RuleSet, prefix: tuple[str, ...]
) -> dict:
    out: dict = {}

    for key in live:
        path = (*prefix, key)
        if rules.resolve(path) is Strategy.REMOVE:
            continue
        if key in baseline:
            value = _combine(baseline[key], live[key], rules, path)
        elif descends(live[key]):
            # Descend even with nothing curated here, or a remove rule deeper
            # in a live-only table never runs. With no removals below, this
            # rebuilds exactly what a deep copy would have produced.
            value = _merge_level({}, live[key], rules, path)
        else:
            value = copy.deepcopy(live[key])
        # An enforced empty baseline table means "this table exists and is
        # empty", so only prune where remove emptied it.
        if value == {} and descends(live[key]) and all(
            rules.removes((*path, member)) for member in live[key]
        ):
            continue
        out[key] = value

    for key in baseline:
        if key in live:
            continue
        path = (*prefix, key)
        written = _write_only(baseline[key], rules, path)
        if written is not _NOTHING:
            out[key] = written

    return out


class _Nothing:
    pass


_NOTHING = _Nothing()


def _combine(base_value, live_value, rules: RuleSet, path: tuple[str, ...]):
    """Resolve one key present on both sides."""
    if descends(base_value) and isinstance(live_value, Mapping):
        strategy = rules.resolve(path)
        # enforce owns the whole subtree when a rule claims it at this exact
        # depth. seed always descends: it is defined per path, so a live
        # table missing a curated member gains that member.
        if strategy is Strategy.ENFORCE and _claims_exactly(rules, path):
            return copy.deepcopy(base_value)
        return _merge_level(base_value, live_value, rules, path)

    strategy = rules.resolve(path)

    if strategy is Strategy.ENFORCE:
        return copy.deepcopy(base_value)
    if strategy is Strategy.UNION:
        if not isinstance(live_value, list) or not isinstance(base_value, list):
            raise TypeError(f"{'.'.join(path)}: union requires lists on both sides")
        merged = list(live_value)
        merged.extend(item for item in base_value if item not in merged)
        return merged
    return copy.deepcopy(live_value)


def _claims_exactly(rules: RuleSet, path: tuple[str, ...]) -> bool:
    """True when a pattern names this path at its full depth and nothing below.

    ["statusLine"] claims the whole statusLine object; ["env", "*"] does not
    claim env itself, so env descends and live-only members survive. A pattern that
    reaches below the path cancels the claim: ["mcp_servers", "*"] enforce
    alongside ["mcp_servers", "*", "enabled"] seed has to descend into each
    server, or the deeper rule never runs and the live toggle is overwritten.
    """
    matches = rules.patterns_for(path)
    if not matches or len(matches[0][2]) != len(path):
        return False
    return not any(
        len(pattern) > len(path) and score(list(pattern[: len(path)]), path) is not None
        for _, pattern in rules.patterns
    )


def _write_only(base_value, rules: RuleSet, path: tuple[str, ...]):
    """Resolve a baseline key absent from live."""
    if rules.resolve(path) is Strategy.REMOVE:
        return _NOTHING
    if descends(base_value):
        written = {}
        for key, value in base_value.items():
            sub = _write_only(value, rules, (*path, key))
            if sub is not _NOTHING:
                written[key] = sub
        return written if written else _NOTHING

    strategy = rules.resolve(path)
    if strategy in (Strategy.ENFORCE, Strategy.SEED, Strategy.UNION):
        return copy.deepcopy(base_value)
    return _NOTHING
