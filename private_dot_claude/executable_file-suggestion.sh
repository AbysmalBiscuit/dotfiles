#!/bin/bash
# Custom @ file-path autocomplete for Claude Code.
# Receives {"query": "<typed text>"} on stdin; prints matching paths,
# one per line. Searches gitignored files too (--no-ignore-vcs).
# Queries containing glob characters (* ? [ ]) are matched as globs:
# "*.sh" matches by filename, "hooks/*.sh" against the full path at any
# depth. Anything else is a literal substring match against the full
# path, so "hooks/worktree" works too.
#
# Windows (Git Bash) notes: fd matches and prints with the OS-native
# separator (a backslash), while the Claude Code UI speaks forward
# slashes. So on Windows we force forward-slash output via
# --path-separator (value "//" because MSYS rewrites a bare "/" argument
# into a Windows path; "//" survives and reaches fd as a single "/").
# Matching is also separator-aware: a literal query's slashes are
# translated to backslash, and a full-path glob is converted to a
# separator-agnostic regex because fd's glob engine cannot match
# path-separator globs against backslash paths.
query=$(jq -r '.query // empty')
common=(--no-ignore-vcs --hidden --exclude .git --exclude node_modules --max-results 15)
win=
case "$OSTYPE" in
  msys*|cygwin*|win32) win=1; common+=(--path-separator //) ;;
esac
case $query in
  */*[\*\?\[]*|*[\*\?\[]*/*)
    if [[ $win ]]; then
      re=${query//./\\.}; re=${re//\?/.}; re=${re//\*/.*}; re=${re//\//.}
      fd "${common[@]}" --full-path "$re"
    else
      [[ $query != \*\** && $query != /* ]] && query="**/$query"
      fd "${common[@]}" --full-path --glob "$query"
    fi ;;
  *[\*\?\[]*)
    fd "${common[@]}" --glob "$query" ;;
  *)
    [[ $win ]] && query=${query//\//\\}
    fd "${common[@]}" --full-path --fixed-strings "$query" ;;
esac
