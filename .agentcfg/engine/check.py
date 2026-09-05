"""Report the drift that a successful merge makes invisible.

seed, ignore, and passthrough all make the target equal the live file, so
chezmoi diff goes quiet. These three classes are what it stops showing.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field

from engine.lint import leaves, show
from engine.rules import RuleSet, Strategy


@dataclass
class CheckReport:
    unclassified: list[tuple[str, ...]] = field(default_factory=list)
    live_only: list[tuple[str, ...]] = field(default_factory=list)
    seed_drift: list[tuple[str, ...]] = field(default_factory=list)

    def is_clean(self) -> bool:
        return not (self.unclassified or self.live_only or self.seed_drift)

    def summary(self, name: str) -> str:
        if self.is_clean():
            return ""
        return (
            f"{name}: {len(self.unclassified)} unclassified, "
            f"{len(self.live_only)} live-only, "
            f"{len(self.seed_drift)} seed drift (--check to list)"
        )

    def detail(self, name: str) -> str:
        lines = [f"{name}:"]
        for label, paths in (
            ("unclassified", self.unclassified),
            ("live-only", self.live_only),
            ("seed drift", self.seed_drift),
        ):
            for path in paths:
                lines.append(f"  {label}: {show(path)}")
        return "\n".join(lines)


def _get(data: Mapping, path: tuple[str, ...]):
    cursor = data
    for segment in path:
        if not isinstance(cursor, Mapping) or segment not in cursor:
            return None, False
        cursor = cursor[segment]
    return cursor, True


def classify(live: Mapping, baseline: Mapping, rules: RuleSet) -> CheckReport:
    report = CheckReport()
    for path, live_value in leaves(live):
        # A remove rule on an ancestor covers a leaf that matches no pattern of
        # its own, so this outranks the empty-match case below.
        if rules.removes(path):
            continue

        # An empty match list is what resolve() reports as PASSTHROUGH. Taking
        # the winning pattern from the same list that decided the strategy is
        # what keeps the two in step: every branch that reads the pattern is one
        # the empty case already returned from.
        matches = rules.patterns_for(path)
        if not matches:
            report.unclassified.append(path)
            continue
        _, strategy, pattern = matches[0]

        if strategy is Strategy.PASSTHROUGH:
            report.unclassified.append(path)
            continue
        if strategy is Strategy.IGNORE:
            continue

        base_value, in_baseline = _get(baseline, path)
        if not in_baseline:
            # Classified but absent from the baseline: the merge writes the
            # live value through and chezmoi diff stays quiet, so this is the
            # only place it surfaces. Report the member the pattern claims,
            # not the leaf underneath it: extraKnownMarketplaces.x, not
            # extraKnownMarketplaces.x.source.repo.
            claimed = path[: len(pattern)]
            if claimed not in report.live_only:
                report.live_only.append(claimed)
        elif (
            strategy is Strategy.SEED
            and "*" not in pattern
            and base_value != live_value
        ):
            report.seed_drift.append(path)
    return report
