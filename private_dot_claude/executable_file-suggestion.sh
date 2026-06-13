#!/bin/bash
# Custom @ file-path autocomplete for Claude Code.
# Receives {"query": "<typed text>"} on stdin; prints matching paths,
# one per line. Searches gitignored files too (--no-ignore-vcs).
# Queries containing glob characters (* ? [ ]) are matched as globs:
# "*.sh" matches by filename, "hooks/*.sh" against the full path at any
# depth (fd anchors full-path globs, so a leading **/ is added unless
# the query already starts with ** or /). Anything else is a literal
# substring match against the full path, so "hooks/wt" works too.
query=$(jq -r '.query // empty')
common=(--no-ignore-vcs --hidden --exclude .git --exclude node_modules --max-results 15)
case $query in
  */*[\*\?\[]*|*[\*\?\[]*/*)
    [[ $query != \*\** && $query != /* ]] && query="**/$query"
    fd "${common[@]}" --full-path --glob "$query" ;;
  *[\*\?\[]*)
    fd "${common[@]}" --glob "$query" ;;
  *)
    fd "${common[@]}" --full-path --fixed-strings "$query" ;;
esac
