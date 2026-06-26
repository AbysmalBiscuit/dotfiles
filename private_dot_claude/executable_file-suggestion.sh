#!/bin/bash
# Custom @ file-path autocomplete for Claude Code.
# Receives {"query": "<typed text>"} on stdin; prints matching paths,
# one per line. Searches gitignored files too (--no-ignore-vcs).
# Queries containing glob characters (* ? [ ]) are matched as globs:
# "*.sh" matches by filename, "hooks/*.sh" against the full path at any
# depth. Anything else is a literal substring match against the full
# path, so "hooks/worktree" works too.
#
# Home- or absolute-rooted queries ("~/.local", "/etc/ho") are treated as
# path completion instead: fd otherwise only searches the current directory, so
# an absolute path never matches as a substring and the hidden leading-dot
# entries under it would never appear. These complete one path segment inside
# the named directory and show everything there (ignored files included), so
# "~/.local" lists ".local" and siblings starting with ".local", and
# "~/.local/" lists its children. Relative queries always go through the glob /
# substring search below, so deep fuzzy matches ("skills/plugin-settings") keep
# working.
#
# .git and node_modules are excluded from the broad search to keep it un-noisy,
# but the exclude is dropped when the query itself names that directory, so a
# relative ".git/" or "node_modules/foo" can still be navigated.
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
common=(--no-ignore-vcs --hidden --max-results 15)
[[ $query != *.git* ]]         && common+=(--exclude .git)
[[ $query != *node_modules* ]] && common+=(--exclude node_modules)
win=
case "$OSTYPE" in
  msys*|cygwin*|win32) win=1; common+=(--path-separator //) ;;
esac
# Home/absolute path completion: list a single segment (--max-depth 1) inside
# the named directory, under relaxed ignores so hidden and ignored entries show.
navcommon=(--no-ignore --hidden --max-results 15 --max-depth 1)
[[ $win ]] && navcommon+=(--path-separator //)
case $query in
  '~'|'~/'*|/*)
    abs=$query tilde=
    case $abs in
      '~')   abs=$HOME/ tilde=1 ;;
      '~/'*) abs=$HOME/${abs#'~/'} tilde=1 ;;
    esac
    case $abs in
      */) root=${abs%/} base= ;;
      *)  root=${abs%/*} base=${abs##*/} ;;
    esac
    [[ -z $root ]] && root=/
    [[ -d $root ]] || exit 0
    case $base in
      '')         glob='*' ;;
      *[\*\?\[]*) glob=$base ;;
      *)          glob="$base"'*' ;;
    esac
    if [[ $tilde ]]; then
      home="$HOME/"
      fd "${navcommon[@]}" --glob "$glob" "$root" |
        while IFS= read -r p; do printf '%s\n' "${p/#"$home"/'~/'}"; done
    else
      fd "${navcommon[@]}" --glob "$glob" "$root"
    fi
    exit 0 ;;
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
