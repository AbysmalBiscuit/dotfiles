#!/bin/bash

DEV="0"
CACHE_DIR="$HOME/.cache/ccstatusline-usage"
CACHE_FILE="$CACHE_DIR/ccstatusline-usage.txt"
# SESSION_BAR_CACHE="$CACHE_DIR/session_bar.txt"
# WEEKLY_BAR_CACHE="$CACHE_DIR/weekly_bar.txt"
# SESSION_RESET_CACHE="$CACHE_DIR/session_reset.txt"
# WEEKLY_RESET_CACHE="$CACHE_DIR/weekly_reset.txt"
# RESPONSE_CACHE="$CACHE_DIR/ccstatusline-response.json"
LOCK_FILE="$CACHE_DIR/ccstatusline-usage.lock"

mkdir -p "$CACHE_DIR"

if [[ "$DEV" == "1" ]]; then
    if [[ -f "$CACHE_FILE" ]]; then
        rm "$CACHE_FILE"
    fi
    if [[ -f "$LOCK_FILE" ]]; then
        rm "$LOCK_FILE"
    fi
fi

# function load_caches {
#     if [[ -f "$SESSION_BAR_CACHE" ]]; then
#         SESSION_BAR=$(cat "$SESSION_BAR_CACHE" || exit 1)
#     fi
#     if [[ -f "$WEEKLY_BAR_CACHE" ]]; then
#         WEEKLY_BAR=$(cat "$WEEKLY_BAR_CACHE" || exit 1)
#     fi
#     if [[ -f "$SESSION_RESET_CACHE" ]]; then
#         SESSION_RESET=$(cat "$SESSION_RESET_CACHE" || exit 1)
#     fi
#     if [[ -f "$WEEKLY_RESET_CACHE" ]]; then
#         WEEKLY_RESET=$(cat "$WEEKLY_RESET_CACHE" || exit 1)
#     fi
# }

# Use cache if < 180 seconds old
if [[ -f "$CACHE_FILE" ]]; then
    AGE=$(($(date +%s) - $(stat -c '%Y' "$CACHE_FILE")))
    [[ $AGE -lt 180 ]] && cat "$CACHE_FILE" && exit 0
fi

# Rate limit: only try API once per 30 seconds
if [[ -f "$LOCK_FILE" ]]; then
    LOCK_AGE=$(($(date +%s) - $(stat -c '%Y' "$LOCK_FILE")))
    if [[ $LOCK_AGE -lt 30 ]]; then
        [[ -f "$CACHE_FILE" ]] && cat "$CACHE_FILE" && exit 0
        echo "[Timeout]" && exit 1
    fi
fi
touch "$LOCK_FILE"

TOKEN="$(jq -r '.claudeAiOauth.accessToken // empty' ~/.claude/.credentials.json 2>/dev/null)"
if [[ -z "$TOKEN" ]]; then
    [[ -f "$CACHE_FILE" ]] && cat "$CACHE_FILE" && exit 0
    echo "[No credentials]"
    exit 1
fi

if [[ "$DEV" == "1" ]]; then
    RESPONSE='{"five_hour":{"utilization":100.0,"resets_at":"2026-01-21T13:00:00.381581+00:00"},"seven_day":{"utilization":60.0,"resets_at":"2026-01-26T14:00:00.381606+00:00"},"seven_day_oauth_apps":null,"seven_day_opus":null,"seven_day_sonnet":null,"iguana_necktie":null,"extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null}}'
else
    RESPONSE=$(curl -s --max-time 5 "https://api.anthropic.com/api/oauth/usage" -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)
fi

if [[ -z "$RESPONSE" ]]; then
    [[ -f "$CACHE_FILE" ]] && cat "$CACHE_FILE" && exit 0
    echo "[API Error]"
    exit 1
fi

SESSION=$(echo "$RESPONSE" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
WEEKLY=$(echo "$RESPONSE" | jq -r '.seven_day.utilization // empty' 2>/dev/null)

# If API failed, use stale cache or show error
if [[ -z "$SESSION" || -z "$WEEKLY" ]]; then
    [[ -f "$CACHE_FILE" ]] && cat "$CACHE_FILE" && exit 0
    echo "[Parse Error]"
    exit 1
fi

SESSION_INT=${SESSION%.*}
WEEKLY_INT=${WEEKLY%.*}

# Function to generate progress bar
make_bar() {
    local pct="$1"
    local width=15
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    printf "["
    for ((i = 0; i < filled; i++)); do printf "█"; done
    for ((i = 0; i < empty; i++)); do printf "░"; done
    printf "]"
}

SESSION_BAR=$(make_bar "$SESSION_INT")
WEEKLY_BAR=$(make_bar "$WEEKLY_INT")

# Handle reset times
NOW=$(date +%s)
MIDNIGHT_TONIGHT=$(date -d "tomorrow 00:00" +%s)
MIDNIGHT_TOMORROW=$(date -d "tomorrow +1 day 00:00" +%s)
SESSION_RESET=$(date -d "$(echo "$RESPONSE" | jq -r '.five_hour.resets_at')" +%s)
WEEKLY_RESET=$(date -d "$(echo "$RESPONSE" | jq -r '.seven_day.resets_at')" +%s)

function time_until_reset() {
    SECONDS_LEFT=$(($1 - NOW))
    if [ "$SECONDS_LEFT" -le 0 ]; then
        echo "0h 0m"
    else
        DAYS=$((SECONDS_LEFT / 86400))
        HOURS=$(((SECONDS_LEFT % 86400) / 3600))
        MINS=$(((SECONDS_LEFT % 3600) / 60))

        if [ "$DAYS" -gt 0 ]; then
            echo "${DAYS}d ${HOURS}h ${MINS}m"
        else
            echo "0d ${HOURS}h ${MINS}m"
        fi
    fi
}

IS_MAXED=false
if ((WEEKLY_INT >= 100)); then IS_MAXED=true; fi

if [ "$IS_MAXED" = true ]; then
    SESSION_FMT=$(date -d "@$SESSION_RESET" "+%a, %Y-%m-%d %Hh")
elif [ "$SESSION_RESET" -lt "$MIDNIGHT_TONIGHT" ]; then
    # Resets Today
    SESSION_FMT="Today @ ""$(date -d "@$SESSION_RESET" "+%Hh")"
elif [ "$SESSION_RESET" -lt "$MIDNIGHT_TOMORROW" ]; then
    # Resets Tomorrow
    SESSION_FMT="Today @ "$(date -d "@$SESSION_RESET" "%H")
else
    # Resets further in the future
    SESSION_FMT=$(date -d "@$SESSION_RESET" "+%a, %Y-%m-%d %Hh")
fi

SESSION_PAD=$(printf "%5s" "$SESSION")
WEEKLY_PAD=$(printf "%5s" "$WEEKLY")

WEEKLY_FMT=$(date -d "@$WEEKLY_RESET" "+%a, %Y-%m-%d %Hh")
SESSION_FMT=$(printf "%-19s" "$SESSION_FMT")

SESSION_UNTIL_RESET=$(time_until_reset "$SESSION_RESET")
WEEKLY_UNTIL_RESET=$(time_until_reset "$WEEKLY_RESET")

echo -e "Session: $SESSION_BAR ${SESSION_PAD}% | Reset: ${SESSION_FMT} (in ${SESSION_UNTIL_RESET})\nWeekly:  $WEEKLY_BAR ${WEEKLY_PAD}% | Reset: ${WEEKLY_FMT} (in ${WEEKLY_UNTIL_RESET})" | tee "$CACHE_FILE"
