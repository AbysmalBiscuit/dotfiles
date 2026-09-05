"""Which projects stay out of the index: a rule list, and in-tree marker files."""

import os
from pathlib import Path

from . import db

# A project holding one of these files, or sitting under a directory that holds one, is
# excluded. Unlike a rule they travel with the repository and survive losing the rule
# list. The `.local` variant is the one to leave out of version control.
MARKERS = (".history_exclude", ".history_exclude.local")

HEADER = """# One project directory per line. A directory covers everything beneath it.
# Transcripts whose working directory falls under a rule are never indexed.
# Manage with: ~/.agents/skills/history/hist.py exclude add|rm <path> --yes
#
# A .history_exclude file in a project, or above it, excludes it too, and is not
# listed here. Prefer one for anything that must stay out even if this file is lost.
"""


def default_path() -> Path:
    """Beside the index, so one directory holds everything this tool owns."""
    env = os.environ.get("HISTORY_EXCLUDE")
    if env:
        return Path(env).expanduser()
    return db.default_path().parent / "exclude"


def marker_above(project: str | None) -> str | None:
    """The nearest marker file at or above the project directory, as a path."""
    if not project:
        return None
    directory = Path(project).expanduser()
    for candidate in (directory, *directory.parents):
        for name in MARKERS:
            marker = candidate / name
            try:
                if marker.is_file():
                    return str(marker)
            except OSError:
                return None
    return None


def normalize(rule: str) -> str:
    """Absolute, `~` expanded, no trailing slash, so rules and projects compare directly."""
    text = rule.strip()
    if not text:
        return ""
    return str(Path(text).expanduser()).rstrip("/") or "/"


def load(path: Path | None = None) -> list[str]:
    path = Path(path) if path else default_path()
    try:
        body = path.read_text()
    except OSError:
        return []
    rules = []
    for line in body.splitlines():
        # Only a leading # is a comment; a path may legitimately contain one.
        if line.lstrip().startswith("#"):
            continue
        rule = normalize(line)
        if rule and rule not in rules:
            rules.append(rule)
    return rules


def save(rules: list[str], path: Path | None = None) -> None:
    path = Path(path) if path else default_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(HEADER + "".join(f"{rule}\n" for rule in rules))


def add(rule: str, path: Path | None = None) -> bool:
    rules = load(path)
    rule = normalize(rule)
    if rule in rules:
        return False
    save(sorted(rules + [rule]), path)
    return True


def remove(rule: str, path: Path | None = None) -> bool:
    rules = load(path)
    rule = normalize(rule)
    if rule not in rules:
        return False
    save([r for r in rules if r != rule], path)
    return True


def matches(project: str | None, rules: list[str]) -> str | None:
    """The rule covering this project, or None. A rule covers itself and everything below."""
    if not project:
        return None
    target = normalize(project)
    for rule in rules:
        rule = normalize(rule)
        if target == rule or target.startswith(rule.rstrip("/") + "/"):
            return rule
    return None
