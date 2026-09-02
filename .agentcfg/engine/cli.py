"""Entry point shared by both wrapper scripts."""

from __future__ import annotations

import sys
from pathlib import Path

from engine.check import classify
from engine.codecs import CodecError
from engine.lint import LintError, lint
from engine.merge import merge
from engine.paths import resolve
from engine.rules import RuleSet

EXIT_OK = 0
EXIT_DRIFT = 1
EXIT_ERROR = 2


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
        baseline = codec.plain(codec.load(baseline_path.read_bytes()))
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
    out = codec.dump(codec.patch(live_doc, result))

    if not out.strip():
        print(f"{target_name}: merge produced empty output, refusing to write", file=stderr)
        return EXIT_ERROR
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
