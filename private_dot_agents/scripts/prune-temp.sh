#!/usr/bin/env bash
# Prune Claude's temp directory by age.
#
# Nothing else cleans this path. Disk Cleanup and Storage Sense expand %TEMP%
# from the Windows environment, which still points at AppData/Local/Temp, so
# the directory Claude's settings.json redirects to would grow without bound.
# 7 days matches the LastAccess rule Windows applies to its own temp folder.
set -euo pipefail

TARGET="$HOME/AppData/Temp"
MAX_AGE_DAYS="${CLAUDE_TEMP_MAX_AGE_DAYS:-7}"

case "$TARGET" in
  */AppData/Temp) ;;
  *) exit 0 ;;
esac
[ -d "$TARGET" ] || exit 0

find "$TARGET" -mindepth 1 -type f -mtime "+$MAX_AGE_DAYS" -delete 2>/dev/null || true
find "$TARGET" -mindepth 1 -type d -empty -delete 2>/dev/null || true

exit 0
