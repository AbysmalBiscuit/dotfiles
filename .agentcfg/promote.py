#!/usr/bin/env python3
"""Assign a merge strategy to every live config key no rule covers.

chezmoi cannot surface this drift on its own. Under a modify_ script the
target is computed from the live file, so on any seed, ignore, or passthrough
path the target equals live by construction and the comparison goes quiet.
This walks what the check finds and writes your choices into the baseline and
rules files.

    python .agentcfg/promote.py            pick interactively
    python .agentcfg/promote.py --list     print the candidates and exit

Without a terminal, or under a chezmoi dry run, it prints instead of picking.
"""

from __future__ import annotations

import os
import re
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
                 if strategy not in (Strategy.IGNORE, Strategy.REMOVE)]
    # A live-only path already matches a rule and is merely missing from the
    # baseline. Appending a second pattern for it risks a load-time tie.
    # remove is the exception: no existing rule can express a deletion.
    new_rules = [(strategy, path) for path, strategy in choices.items()
                 if strategy is Strategy.REMOVE or kinds[path] != LIVE_ONLY]

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


_DRY_RUN = re.compile(r"^(?:--dry-run|-[a-zA-Z]*n[a-zA-Z]*)$")


def dry_run(chezmoi_args: str) -> bool:
    """True when chezmoi's own argv asks for a dry run.

    Apply hooks fire under --dry-run as well, so a picker launched from one
    would seize a command the caller expected to change nothing. CHEZMOI_ARGS
    carries chezmoi's whole argv and is the only signal that separates the two.
    """
    return any(_DRY_RUN.match(arg) for arg in chezmoi_args.split())


def can_pick() -> bool:
    return (
        sys.stdin.isatty()
        and sys.stdout.isatty()
        and not dry_run(os.environ.get("CHEZMOI_ARGS", ""))
    )


# Every flag here takes a value. Reading one as valueless would turn its
# value into a phantom target; reading a valueless flag as taking one only
# drops a target, which costs at most a skipped run.
_VALUE_FLAGS = frozenset({
    "--age-recipient", "--age-recipient-file", "--cache", "--color",
    "--config", "--config-format", "--destination", "--exclude", "--include",
    "--mode", "--output", "--override-data", "--override-data-file",
    "--persistent-state", "--progress", "--refresh-externals", "--source",
    "--use-builtin-age", "--use-builtin-git", "--working-tree",
})
_VALUE_SHORTHANDS = frozenset("DRSWciox")


def _positionals(argv: list[str]) -> list[str]:
    """The tokens that are neither a flag nor the value of one."""
    out: list[str] = []
    expect_value = False
    literal = False
    for token in argv:
        if expect_value:
            expect_value = False
        elif literal or token == "-" or not token.startswith("-"):
            out.append(token)
        elif token == "--":
            literal = True
        elif token.startswith("--"):
            expect_value = "=" not in token and token in _VALUE_FLAGS
        else:
            cluster = token[1:]
            for index, letter in enumerate(cluster):
                if letter in _VALUE_SHORTHANDS:
                    expect_value = index == len(cluster) - 1
                    break
    return out


def apply_targets(chezmoi_args: str) -> list[str]:
    """The targets chezmoi was given, empty when it was given none.

    argv[0] is the executable and the first positional after it is the
    subcommand, so the targets start at the second.
    """
    return _positionals(chezmoi_args.split()[1:])[1:]


def in_scope(chezmoi_args: str, paths, home) -> bool:
    """True when the run could reach one of the config files.

    A targeted apply leaves every other file alone, so a picker that opens
    anyway seizes a command that was never about these configs. Anything
    unresolvable counts as in scope: skipping a run only defers the
    question to the next one.

    chezmoi joins its argv with single spaces and runs hooks from the home
    directory rather than the caller's, so a target carrying a space or one
    written relative to another directory does not survive the round trip.
    """
    argv = chezmoi_args.split()
    if "--source-path" in argv:
        return True
    targets = apply_targets(chezmoi_args)
    if not targets:
        return True
    for arg in targets:
        candidate = Path(os.path.expanduser(arg))
        if not candidate.is_absolute():
            candidate = home / candidate
        candidate = Path(os.path.normpath(candidate))
        if any(candidate == path or candidate in path.parents for path in paths):
            return True
    return False


def main(argv) -> int:
    root, home = _repo_root(), _dest_root()
    chezmoi_args = os.environ.get("CHEZMOI_ARGS", "")
    configs = [config for config in CONFIGS
               if in_scope(chezmoi_args, [home / config.target], home)]
    if not configs:
        return 0

    interactive = can_pick()
    list_only = "--list" in argv or not interactive
    touched = 0

    for config in configs:
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
            if not interactive:
                print("  run `agentcfg` to assign strategies")
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
