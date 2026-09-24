"""Entry point shared by both wrapper scripts."""

from __future__ import annotations

import sys
import tomllib
from typing import TYPE_CHECKING

from engine.check import classify
from engine.codecs import CodecError
from engine.hooks import drop_unmet_requires
from engine.lint import LintError, lint
from engine.merge import merge
from engine.paths import resolve
from engine.rules import RuleSet

if TYPE_CHECKING:
    from pathlib import Path

EXIT_OK = 0
EXIT_DRIFT = 1
EXIT_ERROR = 2


def _installed_tools(target_root: Path) -> dict[str, object]:
    """has_tool.toml from the has-cache script; absent means nothing counts as installed."""
    try:
        text = (target_root / ".config" / "chezmoi" / "has_tool.toml").read_text(encoding="utf-8")
    except FileNotFoundError:
        return {}
    return tomllib.loads(text)


def run(
    script_file: str,
    baseline_name: str,
    rules_name: str,
    codec,
    argv: list[str] | None = None,
    stdin=None,
    stdout=None,
    stderr=None,
    lint_enabled: bool = True,
) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    stdin = stdin if stdin is not None else sys.stdin.buffer
    stdout = stdout if stdout is not None else sys.stdout.buffer
    stderr = stderr if stderr is not None else sys.stderr

    check_only = "--check" in argv
    paths = resolve(script_file)
    baseline_path = paths.script_dir / baseline_name
    rules_path = paths.script_dir / rules_name
    target_name = baseline_name.lstrip(".").replace(".baseline", "")

    try:
        baseline_raw = baseline_path.read_bytes()
        baseline = drop_unmet_requires(
            codec.plain(codec.load(baseline_raw)), _installed_tools(paths.target_root)
        )
        rules = RuleSet.load(rules_path)
        if lint_enabled:
            lint(baseline, rules)
    except (CodecError, LintError, ValueError, OSError) as exc:
        print(f"{target_name}: {exc}", file=stderr)
        return EXIT_ERROR

    raw = stdin.read()

    if not raw.strip():
        # chezmoi passes nil stdin when the target is absent. An empty mapping
        # goes through the merge like any other live file, so the rules and the
        # lint apply on a fresh machine too.
        live_doc = codec.empty()
    else:
        try:
            live_doc = codec.load(raw)
        except CodecError as exc:
            print(f"{target_name}: {exc}", file=stderr)
            return EXIT_ERROR

    live = codec.plain(live_doc)
    report = classify(live, baseline, rules)

    if check_only:
        if report.is_clean():
            return EXIT_OK
        print(report.detail(target_name), file=stderr)
        return EXIT_DRIFT

    # Patch back into the parsed document rather than dumping the plain
    # mapping. tomlkit regenerates layout when handed a plain dict, which
    # would make every apply rewrite the whole file.
    result = merge(baseline, live, rules)
    merged_doc = codec.reorder(codec.patch(live_doc, result), rules.order)
    dumped = codec.dump(merged_doc)

    if not dumped.strip():
        print(f"{target_name}: merge produced empty output, refusing to write", file=stderr)
        return EXIT_ERROR

    out = codec.carry_preamble(dumped, baseline_raw)
    try:
        codec.load(out)
    except CodecError as exc:
        print(f"{target_name}: merge output does not parse: {exc}", file=stderr)
        return EXIT_ERROR

    stdout.write(out)

    summary = report.summary(target_name)
    if summary:
        print(summary, file=stderr)
    return EXIT_OK
