#!/bin/bash

CACHE_DIR="$HOME/.cache/ccstatusline-usage"
CACHE_FILE_WEEKLY="$CACHE_DIR/ccstatusline-usage-weekly.txt"

[[ -f "$CACHE_FILE_WEEKLY" ]] && cat "$CACHE_FILE_WEEKLY" && exit 0
