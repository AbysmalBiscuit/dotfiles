"""Hook-specific handling: live entries preserved by enforce_ignore.hook_commands,
and baseline entries gated on an installed tool through `requires`."""

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


def drop_unmet_requires(baseline: Mapping, installed: Mapping[str, object]) -> dict:
    """Drop hook entries whose `requires` has_tool.toml key has no command; strip it from the rest.

    A group emptied this way goes too, so no bare matcher remains.
    """
    hooks = baseline.get("hooks")
    if not isinstance(hooks, Mapping):
        return dict(baseline)
    resolved = {}
    for event, groups in hooks.items():
        if not is_hook_event(("hooks", event)) or not isinstance(groups, list):
            resolved[event] = groups
            continue
        kept = []
        for group in groups:
            entries = group.get("hooks") if isinstance(group, Mapping) else None
            if not isinstance(entries, list) or not entries:
                kept.append(group)
                continue
            met = [
                {k: v for k, v in entry.items() if k != "requires"}
                if isinstance(entry, Mapping)
                else entry
                for entry in entries
                if not isinstance(entry, Mapping)
                or "requires" not in entry
                or installed.get(entry["requires"])
            ]
            if met:
                kept.append({**group, "hooks": met})
        resolved[event] = kept
    return {**baseline, "hooks": resolved}
