#!/usr/bin/env bash
# Claude Code WorktreeRemove hook. Tears down what worktree-create.sh made.
set -euo pipefail

DIR=$(jq -r .worktree_path)
git worktree remove "$DIR" --force >&2 || rm -rf "$DIR" >&2
