#!/usr/bin/env python3
"""Render the superpowers skill sequence as an ASCII flowchart.

A memory aid for which skill to reach for, in what order, across a
development task. Order is derived from each skill's own trigger
description (brainstorming -> writing-plans -> ... -> finish).

Usage:
    superpowers-flow.py            # full flowchart (color if a TTY)
    superpowers-flow.py --no-color # plain ASCII, no ANSI
    superpowers-flow.py --next X   # what to reach for after skill X
"""
import argparse
import sys

# (skill, one-line trigger) in lifecycle order. None entries are phase headers.
PHASES = [
    ("PLAN", [
        ("brainstorming", "idea -> design spec  (gate: nothing built until approved)"),
        ("writing-plans", "spec -> step-by-step implementation plan"),
    ]),
    ("SET UP", [
        ("using-git-worktrees", "isolated workspace before you touch code"),
    ]),
    ("EXECUTE  (pick one)", [
        ("executing-plans", "separate session, review checkpoints between steps"),
        ("subagent-driven-development", "same session, independent tasks"),
        ("dispatching-parallel-agents", "2+ tasks, no shared state / no ordering"),
    ]),
    ("BUILD  (per feature/bugfix)", [
        ("test-driven-development", "test first -> watch fail -> minimal code -> refactor"),
        ("systematic-debugging", "any bug/test failure, BEFORE proposing a fix"),
    ]),
    ("REVIEW", [
        ("requesting-code-review", "completed a feature / before merge"),
        ("receiving-code-review", "verify feedback with rigor, no blind agreement"),
    ]),
    ("SHIP", [
        ("verification-before-completion", "run the commands; evidence before 'done'"),
        ("finishing-a-development-branch", "merge / PR / cleanup decision"),
    ]),
]

ALWAYS = ("using-superpowers", "every conversation, before any response")
META = ("writing-skills", "anytime you create / edit / verify a skill")

# Linear order for --next lookups.
LINEAR = [ALWAYS[0]] + [s for _, items in PHASES for s, _ in items]


class C:
    def __init__(self, on):
        self.head = "\033[1;36m" if on else ""
        self.skill = "\033[1;32m" if on else ""
        self.dim = "\033[2m" if on else ""
        self.arrow = "\033[1;33m" if on else ""
        self.off = "\033[0m" if on else ""


def render(c):
    out = []
    p = out.append
    p(f"{c.head}SUPERPOWERS SKILL ORDER{c.off}")
    p(f"{c.dim}{'=' * 23}{c.off}")
    p("")
    p(f"  [ {c.skill}{ALWAYS[0]}{c.off} ]  {c.dim}{ALWAYS[1]}{c.off}")
    p(f"           {c.arrow}|{c.off}")
    p(f"           {c.arrow}v{c.off}")

    for i, (phase, items) in enumerate(PHASES, 1):
        p(f"  +{'-' * 60}+")
        p(f"  | {c.head}{i}. {phase}{c.off}")
        p(f"  +{'-' * 60}+")
        for skill, desc in items:
            p(f"  |  {c.skill}{skill}{c.off}")
            p(f"  |      {c.dim}{desc}{c.off}")
        p(f"  +{'-' * 60}+")
        if phase.startswith("BUILD"):
            p(f"  {c.dim}     ^  TDD <-> debugging loop until green{c.off}")
        if i < len(PHASES):
            p(f"           {c.arrow}|{c.off}")
            p(f"           {c.arrow}v{c.off}")

    p("")
    p(f"  {c.dim}meta:{c.off} {c.skill}{META[0]}{c.off}  {c.dim}{META[1]}{c.off}")
    return "\n".join(out)


def show_next(name, c):
    if name not in LINEAR:
        print(f"unknown skill: {name}", file=sys.stderr)
        print(f"known: {', '.join(LINEAR)}", file=sys.stderr)
        return 1
    i = LINEAR.index(name)
    if i + 1 < len(LINEAR):
        nxt = LINEAR[i + 1]
        print(f"{c.skill}{name}{c.off} {c.arrow}->{c.off} {c.skill}{nxt}{c.off}")
    else:
        print(f"{c.skill}{name}{c.off} {c.dim}is the last step.{c.off}")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Render superpowers skill order.")
    ap.add_argument("--no-color", action="store_true", help="disable ANSI color")
    ap.add_argument("--next", metavar="SKILL", help="show the skill after SKILL")
    args = ap.parse_args()
    c = C(on=not args.no_color and sys.stdout.isatty())
    if args.next:
        return show_next(args.next, c)
    print(render(c))
    return 0


if __name__ == "__main__":
    sys.exit(main())
