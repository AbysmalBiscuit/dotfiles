#!/usr/bin/env bash
# Claude Code / ccstatusline custom widget:
#   SESSION | WEEK | MONTH | YEAR | LIFETIME  API-equivalent cost.
#
# SESSION comes from the statusline stdin JSON (.cost.total_cost_usd) — the true
# current session, updated every render. WEEK/MONTH/YEAR/LIFETIME come from
# ccusage and are cached with a TTL, because recomputing them on every render
# would spawn a node process per keystroke. When the cache goes stale it is
# refreshed in a detached background process, so the line never blocks.
set -euo pipefail

CACHE_DIR="${HOME}/.claude/statusline-cache"
CACHE_FILE="${CACHE_DIR}/cost.json"
TTL=60 # seconds before cached WEEK/MONTH/YEAR/LIFETIME are refreshed
SEP=" │ "

# Labels for SESSION / WEEK / MONTH / YEAR / LIFETIME.
LABELS=(S W M Y L)
# Nerd Font alternative (needs a Nerd Font in your terminal): comment the line
# above and uncomment the next one, then paste glyphs between the quotes from a
# Nerd Font cheat sheet (https://www.nerdfonts.com/cheat-sheet) — e.g. clock /
# calendar-week / calendar / calendar-star / infinity.
# LABELS=('' '' '' '' '')

if command -v ccusage >/dev/null 2>&1; then
    CCUSAGE=(ccusage)
elif command -v bunx >/dev/null 2>&1; then
    CCUSAGE=(bunx ccusage@latest)
else
    CCUSAGE=(npx -y ccusage@latest)
fi

input="$(cat)"
session_cost="$(jq -r '.cost.total_cost_usd // 0' <<<"$input" 2>/dev/null || echo 0)"

mkdir -p "$CACHE_DIR"

refresh_cache() {
    local month week year
    year="$(date +%Y)"
    month="$("${CCUSAGE[@]}" monthly --json 2>/dev/null || true)"
    week="$("${CCUSAGE[@]}" weekly --json 2>/dev/null || true)"
    jq -n --arg yr "$year" --argjson m "${month:-null}" --argjson w "${week:-null}" '
        {
            week:     (($w.weekly  // []) | last // {} | .totalCost // 0),
            month:    (($m.monthly // []) | last // {} | .totalCost // 0),
            year:     (($m.monthly // []) | map(select(.period | startswith($yr))) | map(.totalCost) | add // 0),
            lifetime: ($m.totals.totalCost // 0)
        }' >"${CACHE_FILE}.tmp" 2>/dev/null &&
        mv -f "${CACHE_FILE}.tmp" "$CACHE_FILE" ||
        echo '{"week":0,"month":0,"year":0,"lifetime":0}' >"$CACHE_FILE"
}

if [[ ! -f "$CACHE_FILE" ]]; then
    refresh_cache # first run: fill synchronously
elif (($(date +%s) - $(stat -c %Y "$CACHE_FILE") >= TTL)); then
    (refresh_cache &) >/dev/null 2>&1 # stale: refresh detached, print current cache now
fi

read -r week month year lifetime < <(
    jq -r '"\(.week) \(.month) \(.year) \(.lifetime)"' "$CACHE_FILE" 2>/dev/null || echo "0 0 0 0"
)

# Cents below $1k; 3 significant figures with k/M/B/T above it.
awk -v s="$session_cost" -v w="${week:-0}" -v m="${month:-0}" \
    -v y="${year:-0}" -v l="${lifetime:-0}" -v sep="$SEP" \
    -v ls="${LABELS[0]}" -v lw="${LABELS[1]}" -v lm="${LABELS[2]}" \
    -v ly="${LABELS[3]}" -v ll="${LABELS[4]}" '
    function money(v,   a,sign,div,suf,scaled,dec) {
        a = v < 0 ? -v : v; sign = v < 0 ? "-" : "";
        if (a < 1000) return sprintf("$%s%.2f", sign, a);
        if      (a >= 1e12) { div = 1e12; suf = "T" }
        else if (a >= 1e9)  { div = 1e9;  suf = "B" }
        else if (a >= 1e6)  { div = 1e6;  suf = "M" }
        else                { div = 1e3;  suf = "k" }
        scaled = a / div;
        dec = scaled < 10 ? 2 : (scaled < 100 ? 1 : 0);
        return sprintf("$%s%.*f%s", sign, dec, scaled, suf);
    }
    BEGIN {
        printf "%s %s",      ls, money(s);
        printf "%s%s %s",    sep, lw, money(w);
        printf "%s%s %s",    sep, lm, money(m);
        printf "%s%s %s",    sep, ly, money(y);
        printf "%s%s %s\n",  sep, ll, money(l);
    }'
