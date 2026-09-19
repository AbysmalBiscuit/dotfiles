"""Preserve live hook entries selected by enforce_ignore.hook_commands."""

from __future__ import annotations

import copy
from collections.abc import Mapping
from fnmatch import fnmatchcase


def is_hook_event(path: tuple[str, ...]) -> bool:
    return len(path) == 2 and path[0] == "hooks" and path[1] != "state"


def ignored_groups(groups: object, patterns: tuple[str, ...]) -> list[dict]:
    """Keep matching entries with their group's matcher and other metadata."""
    if not patterns or not isinstance(groups, list):
        return []
    kept = []
    for group in groups:
        if not isinstance(group, Mapping) or not isinstance(group.get("hooks"), list):
            continue
        hooks = [
            hook
            for hook in group["hooks"]
            if isinstance(hook, Mapping)
            and any(
                isinstance(command := hook.get(key), str) and fnmatchcase(command, pattern)
                for key in ("command", "command_windows")
                for pattern in patterns
            )
        ]
        if hooks:
            kept.append(copy.deepcopy({**group, "hooks": hooks}))
    return kept
