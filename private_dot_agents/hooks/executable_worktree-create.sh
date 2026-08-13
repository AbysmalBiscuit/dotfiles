#!/usr/bin/env bash
# Claude Code WorktreeCreate hook.
# Places the worktree in a SIBLING dir outside the repo root so editors that
# recursively scan the project (e.g. Godot) don't see a second project copy
# and reimport everything. stdout MUST be the worktree path only.
set -euo pipefail

NAME=$(jq -r .name)
ROOT=$(git rev-parse --show-toplevel)
PROJECT=$(basename "$ROOT")
DIR="$(dirname "$ROOT")/${PROJECT}-worktrees/${NAME}"

git worktree add "$DIR" -b "$NAME" >&2

# Re-implement .worktreeinclude (the hook replaces the default, which skips it).
# One path or glob per line; blank lines and #-comments ignored. Paths are
# relative to repo root; directory structure is preserved into the worktree.
if [ -f "$ROOT/.worktreeinclude" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                       # strip trailing comment
    line="$(echo "$line" | xargs 2>/dev/null || true)"  # trim whitespace
    [ -z "$line" ] && continue
    ( cd "$ROOT" && shopt -s globstar nullglob dotglob
      for match in $line; do
        [ -e "$match" ] || continue
        mkdir -p "$DIR/$(dirname "$match")" >&2
        cp -r "$match" "$DIR/$match" >&2 2>/dev/null || true
      done )
  done < "$ROOT/.worktreeinclude"
fi

echo "$DIR"
