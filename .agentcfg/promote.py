#!/usr/bin/env python3
"""Assign a merge strategy to every live config key no rule covers.

chezmoi cannot surface this drift on its own. Under a modify_ script the
target is computed from the live file, so on any seed, ignore, or passthrough
path the target equals live by construction and the comparison goes quiet.
This walks what the check finds and writes your choices into the baseline and
rules files.

    python .agentcfg/promote.py            pick interactively
    python .agentcfg/promote.py --list     print the candidates and exit
"""

from __future__ import annotations

import os
import sys

sys.dont_write_bytecode = True

from pathlib import Path  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))

from engine.check import classify  # noqa: E402
from engine.codecs import JsonCodec, TomlCodec  # noqa: E402
from engine.lint import LintError, lint  # noqa: E402
from engine.picker import pick  # noqa: E402
from engine.promote import LIVE_ONLY, candidates  # noqa: E402
from engine.rules import RuleSet, Strategy  # noqa: E402
from engine.writers import append_rules, write_json_baseline, write_toml_baseline  # noqa: E402


class Config:
    def __init__(self, target, source_dir, baseline, rules, codec, writer):
        self.target = target
        self.source_dir = source_dir
        self.baseline = baseline
        self.rules = rules
        self.codec = codec
        self.writer = writer


CONFIGS = [
    Config(".claude/settings.json", "private_dot_claude", ".settings.baseline.json",
           ".settings.rules.toml", JsonCodec, write_json_baseline),
    Config(".codex/config.toml", "dot_codex", ".config.baseline.toml",
           ".config.rules.toml", TomlCodec, write_toml_baseline),
]


def _repo_root() -> Path:
    env = os.environ.get("CHEZMOI_SOURCE_DIR")
    return Path(env) if env else Path(__file__).resolve().parent.parent


def _dest_root() -> Path:
    env = os.environ.get("CHEZMOI_DEST_DIR")
    return Path(env) if env else Path(os.path.expanduser("~"))


def _value(live, path):
    cursor = live
    for segment in path:
        cursor = cursor[segment]
    return cursor


def apply_choices(config, source, live, choices, found) -> str:
    """Write the choices, restoring both files if the result fails to validate."""
    baseline_path = source / config.baseline
    rules_path = source / config.rules
    before = (baseline_path.read_bytes(), rules_path.read_bytes())

    kinds = {item.path: item.kind for item in found}
    additions = [(path, _value(live, path)) for path, strategy in choices.items()
                 if strategy is not Strategy.IGNORE]
    # A live-only path already matches a rule and is merely missing from the
    # baseline. Appending a second pattern for it risks a load-time tie.
    new_rules = [(strategy, path) for path, strategy in choices.items()
                 if kinds[path] != LIVE_ONLY]

    if additions:
        config.writer(baseline_path, additions)
    if new_rules:
        append_rules(rules_path, new_rules)

    try:
        rules = RuleSet.load(rules_path)
        baseline = config.codec.plain(config.codec.load(baseline_path.read_bytes()))
        lint(baseline, rules)
    except Exception as exc:
        baseline_path.write_bytes(before[0])
        rules_path.write_bytes(before[1])
        return f"  rolled back, the result did not validate: {exc}"
    return f"  wrote {len(additions)} baseline value(s), {len(new_rules)} rule(s)"


def main(argv) -> int:
    list_only = "--list" in argv
    root, home = _repo_root(), _dest_root()
    touched = 0

    for config in CONFIGS:
        source = root / config.source_dir
        target = home / config.target
        if not target.exists():
            print(f"{config.target}: not present, skipping")
            continue

        rules = RuleSet.load(source / config.rules)
        baseline = config.codec.plain(config.codec.load((source / config.baseline).read_bytes()))
        live = config.codec.plain(config.codec.load(target.read_bytes()))
        found = candidates(live, classify(live, baseline, rules))

        if not found:
            print(f"{config.target}: nothing unclassified")
            continue
        if list_only:
            print(f"{config.target}: {len(found)} candidate(s)")
            for item in found:
                flag = f"   [secret: {item.secret}]" if item.blocked else ""
                print(f"  {item.kind:12} {'.'.join(item.path)}{flag}")
            continue

        choices = pick(found, f"{config.target}  ({len(found)} unclassified)")
        if choices is None:
            print(f"{config.target}: aborted, nothing written")
            continue
        if not choices:
            print(f"{config.target}: nothing selected")
            continue
        print(f"{config.target}:")
        print(apply_choices(config, source, live, choices, found))
        touched += 1

    if touched:
        print(f"\nReview with: git -C {root} diff")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
