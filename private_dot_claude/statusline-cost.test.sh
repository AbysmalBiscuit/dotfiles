#!/usr/bin/env bash
# Tests for statusline-cost.py. Run: bash ~/.claude/statusline-cost.test.sh
set -uo pipefail

SCRIPT="$HOME/.claude/statusline-cost.py"
PASS=0 FAIL=0
TESTROOT="$(mktemp -d)"
trap 'rm -rf "$TESTROOT"' EXIT

assert_eq() { # desc expected actual
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
    fi
}

# Fresh sync/cache/stub dirs per test; exports consumed by run_v2.
new_tmp() {
    T="$TESTROOT/t$((PASS + FAIL))-$RANDOM"
    SYNC="$T/sync" CACHE="$T/cache" STUB_DIR="$T/stub" COLLECT="$T/collectors"
    mkdir -p "$SYNC" "$CACHE" "$STUB_DIR" "$COLLECT"
    echo '{"daily": [], "totals": {}}' >"$STUB_DIR/daily.json"
    echo '{"session": [], "totals": {}}' >"$STUB_DIR/session.json"
    cat >"$T/ccusage-stub" <<STUB
#!/usr/bin/env bash
case "\$1" in
    daily)   cat "$STUB_DIR/daily.json" ;;
    session) cat "$STUB_DIR/session.json" ;;
esac
STUB
    chmod +x "$T/ccusage-stub"
}

# Env var paths must be native (C:/...) for Windows python — Git Bash
# converts command arguments but never environment variable values.
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }

run_v2() {
    AGENT_COST_SYNC_DIR="$(wp "$SYNC")" COST_CACHE_DIR="$(wp "$CACHE")" COST_MACHINE_ID="testbox-linux" \
    COST_CCUSAGE_BIN="$(wp "$T/ccusage-stub")" COST_COLLECTORS_DIR="$(wp "$COLLECT")" \
    COST_TODAY="2026-07-17" COST_TTL=9999 bash "$SCRIPT" "$@"
}

ledger() { jq -c "$1" "$SYNC/usage-testbox-linux.json"; }

# ---- Task 1: merge ledger ----

test_refresh_writes_rows_from_ccusage() {
    new_tmp
    cat >"$STUB_DIR/daily.json" <<'EOF'
{"daily": [
  {"period": "2026-07-17", "totalCost": 3.0, "agents": [
    {"agent": "claude", "totalCost": 2.0}, {"agent": "codex", "totalCost": 1.0}]}
], "totals": {}}
EOF
    run_v2 refresh
    assert_eq "rows from by-agent dump" \
        '[{"date":"2026-07-17","agent":"claude","cost":2},{"date":"2026-07-17","agent":"codex","cost":1}]' \
        "$(ledger '[.rows[] | {date, agent, cost}]')"
    assert_eq "machine id recorded" '"testbox-linux"' "$(ledger '.machine')"
}

test_merge_keeps_history_and_takes_max() {
    new_tmp
    cat >"$SYNC/usage-testbox-linux.json" <<'EOF'
{"machine": "testbox-linux", "generatedAt": "2026-07-01T00:00:00Z", "rows": [
  {"date": "2026-05-01", "agent": "claude", "cost": 50.0},
  {"date": "2026-07-17", "agent": "claude", "cost": 1.5}
]}
EOF
    cat >"$STUB_DIR/daily.json" <<'EOF'
{"daily": [
  {"period": "2026-07-17", "totalCost": 2.0, "agents": [{"agent": "claude", "totalCost": 2.0}]}
], "totals": {}}
EOF
    run_v2 refresh
    assert_eq "pruned history kept, today takes max" \
        '[{"date":"2026-05-01","agent":"claude","cost":50},{"date":"2026-07-17","agent":"claude","cost":2}]' \
        "$(ledger '[.rows[] | {date, agent, cost}]')"
}

test_merge_never_lowers_a_row() {
    new_tmp
    cat >"$SYNC/usage-testbox-linux.json" <<'EOF'
{"machine": "testbox-linux", "generatedAt": "2026-07-01T00:00:00Z", "rows": [
  {"date": "2026-07-17", "agent": "claude", "cost": 9.0}
]}
EOF
    cat >"$STUB_DIR/daily.json" <<'EOF'
{"daily": [
  {"period": "2026-07-17", "totalCost": 4.0, "agents": [{"agent": "claude", "totalCost": 4.0}]}
], "totals": {}}
EOF
    run_v2 refresh
    assert_eq "partial log deletion cannot lower a row" \
        '[{"date":"2026-07-17","agent":"claude","cost":9}]' \
        "$(ledger '[.rows[] | {date, agent, cost}]')"
}

test_empty_ccusage_is_noop() {
    new_tmp
    cat >"$SYNC/usage-testbox-linux.json" <<'EOF'
{"machine": "testbox-linux", "generatedAt": "2026-07-01T00:00:00Z", "rows": [
  {"date": "2026-05-01", "agent": "claude", "cost": 50.0}
]}
EOF
    : >"$STUB_DIR/daily.json"   # stub emits nothing (ccusage failure)
    run_v2 refresh
    assert_eq "empty ccusage output keeps ledger intact" \
        '[{"date":"2026-05-01","agent":"claude","cost":50}]' \
        "$(ledger '[.rows[] | {date, agent, cost}]')"
}

test_collector_rows_are_merged() {
    new_tmp
    cat >"$COLLECT/mytool" <<'EOF'
#!/usr/bin/env bash
echo '[{"date": "2026-07-17", "agent": "mytool", "cost": 0.7}]'
EOF
    chmod +x "$COLLECT/mytool"
    run_v2 refresh
    assert_eq "collector agent merged" \
        '[{"date":"2026-07-17","agent":"mytool","cost":0.7}]' \
        "$(ledger '[.rows[] | {date, agent, cost}]')"
}

# ---- Task 2: fleet aggregation + render ----
# 2026-07-17 is a Friday; week = Mon 2026-07-13 .. today.
# Expected: D=3 (2+1 today)
#           W=8 (D + 5.0 on Mon 07-13)
#           M=15 (W + 7.0 on Sun 07-12 from machine B — in month, NOT in week)
#           Y=25 (M + 10.0 on 06-30)
#           L=125 (Y + 100.0 on 2025-12-31)
seed_fleet() {
    new_tmp
    cat >"$STUB_DIR/daily.json" <<'EOF'
{"daily": [
  {"period": "2026-06-30", "totalCost": 10.0, "agents": [{"agent": "claude", "totalCost": 10.0}]},
  {"period": "2026-07-13", "totalCost": 5.0,  "agents": [{"agent": "claude", "totalCost": 5.0}]},
  {"period": "2026-07-17", "totalCost": 3.0,  "agents": [
    {"agent": "claude", "totalCost": 2.0}, {"agent": "codex", "totalCost": 1.0}]}
], "totals": {}}
EOF
    cat >"$SYNC/usage-otherbox-linux.json" <<'EOF'
{"machine": "otherbox-linux", "generatedAt": "2026-07-17T08:00:00Z", "rows": [
  {"date": "2025-12-31", "agent": "claude", "cost": 100.0},
  {"date": "2026-07-12", "agent": "claude", "cost": 7.0}
]}
EOF
    echo 'not json' >"$SYNC/usage-brokenbox-linux.json"
    cat >"$SYNC/usage-thirdbox-linux (conflicted copy 2026-07-16).json" <<'EOF'
{"machine": "thirdbox-linux", "generatedAt": "2026-07-16T00:00:00Z", "rows": [
  {"date": "2026-07-17", "agent": "claude", "cost": 99999.0}
]}
EOF
}

test_fleet_aggregation_line() {
    seed_fleet
    local line
    line="$(echo '{"session_id": "sid-1", "cost": {"total_cost_usd": 0.5}}' | run_v2)"
    assert_eq "aggregated line (corrupt + conflict files skipped)" \
        'S $0.50 │ D $3.00 │ W $8.00 │ M $15.00 │ Y $25.00 │ L $125.00' \
        "$line"
}

test_render_survives_missing_everything() {
    new_tmp
    rm -rf "$SYNC" "$CACHE" # neither dir exists; must not crash
    local line
    line="$(echo '{"cost": {"total_cost_usd": 1.25}}' | run_v2)"
    assert_eq "render with nothing on disk still prints" \
        'S $1.25 │ D $0.00 │ W $0.00 │ M $0.00 │ Y $0.00 │ L $0.00' \
        "$line"
}

# ---- Task 3: session slot ----
seed_session() {
    new_tmp
    cat >"$STUB_DIR/session.json" <<'EOF'
{"session": [{"agent": "claude", "period": "sid-1", "totalCost": 4.0}], "totals": {}}
EOF
    # refresh sees stdin counter at 0.5 for session sid-1
    run_v2 refresh "sid-1" "0.5"
}

s_slot() { echo "$1" | run_v2 | awk -F "$(printf ' \342\224\202 ')" '{print $1}'; }

test_session_live_growth() {
    seed_session
    assert_eq "live delta added to transcript baseline" 'S $4.30' \
        "$(s_slot '{"session_id": "sid-1", "cost": {"total_cost_usd": 0.8}}')"
}

test_session_resume_reset() {
    seed_session
    assert_eq "post-resume reset clamps to transcript value" 'S $4.00' \
        "$(s_slot '{"session_id": "sid-1", "cost": {"total_cost_usd": 0.1}}')"
}

test_session_clear_new_id() {
    seed_session
    assert_eq "unknown session id falls back to stdin" 'S $0.20' \
        "$(s_slot '{"session_id": "sid-NEW", "cost": {"total_cost_usd": 0.2}}')"
}

test_session_missing_cache_entry() {
    seed_session
    assert_eq "empty session id falls back to stdin" 'S $0.30' \
        "$(s_slot '{"cost": {"total_cost_usd": 0.3}}')"
}

test_session_zero_cost_falls_back_to_stdin() {
    new_tmp
    cat >"$STUB_DIR/session.json" <<'EOF'
{"session": [{"agent": "claude", "period": "sid-1", "totalCost": 0.0}], "totals": {}}
EOF
    run_v2 refresh "sid-1" "0.5"
    assert_eq "found-but-zero transcript cost falls back to stdin" 'S $0.80' \
        "$(s_slot '{"session_id": "sid-1", "cost": {"total_cost_usd": 0.8}}')"
}

# ---- Task 5: report ----
test_report_tables() {
    seed_fleet
    run_v2 refresh
    local out
    out="$(run_v2 report)"
    assert_eq "agent row: claude fleet lifetime" \
        'claude 2.00 7.00 14.00 24.00 124.00' \
        "$(awk '$1 == "claude" {print $1, $2, $3, $4, $5, $6}' <<<"$out")"
    assert_eq "agent row: codex" \
        'codex 1.00 1.00 1.00 1.00 1.00' \
        "$(awk '$1 == "codex" {print $1, $2, $3, $4, $5, $6}' <<<"$out")"
    assert_eq "machine row: otherbox" \
        'otherbox-linux 0.00 0.00 7.00 7.00 107.00' \
        "$(awk '$1 == "otherbox-linux" {print $1, $2, $3, $4, $5, $6}' <<<"$out")"
}

test_refresh_writes_rows_from_ccusage
test_merge_keeps_history_and_takes_max
test_merge_never_lowers_a_row
test_empty_ccusage_is_noop
test_collector_rows_are_merged
test_fleet_aggregation_line
test_render_survives_missing_everything
test_session_live_growth
test_session_resume_reset
test_session_clear_new_id
test_session_missing_cache_entry
test_session_zero_cost_falls_back_to_stdin

# ---- Final review: argv ceiling ----
test_big_ledger_renders() {
    new_tmp
    local big
    big="$(jq -cn '{machine: "bigbox-linux", generatedAt: "2026-07-01T00:00:00Z",
        rows: [range(0; 1500) | {date: "2020-01-01", agent: ("agent" + (. | tostring)), cost: 1}]}')"
    printf '%s' "$big" >"$SYNC/usage-bigbox-linux.json"
    cat >"$STUB_DIR/daily.json" <<'EOF'
{"daily": [
  {"period": "2026-07-17", "totalCost": 1.0, "agents": [{"agent": "claude", "totalCost": 1.0}]}
], "totals": {}}
EOF
    run_v2 refresh
    local line
    line="$(echo '{"session_id": "big-sid", "cost": {"total_cost_usd": 0.1}}' | run_v2)"
    assert_eq "big-ledger render starts with S \$ and contains L \$ (non-blank)" '1' \
        "$([[ "$line" == 'S $'* && "$line" == *'L $'* ]] && echo 1 || echo 0)"
    assert_eq "cache parses and lifetime total exceeds 1000" '1' \
        "$(jq -e '(.l // 0) > 1000' "$CACHE/cost.json" >/dev/null 2>&1 && echo 1 || echo 0)"
    assert_eq "bigbox ledger still parses" '1' \
        "$(jq -e '.rows | type == "array"' "$SYNC/usage-bigbox-linux.json" >/dev/null 2>&1 && echo 1 || echo 0)"
}

test_big_ledger_renders

# ---- Task 4: concurrency ----
test_parallel_refreshes_no_torn_files() {
    seed_fleet
    local i
    for i in $(seq 1 10); do run_v2 refresh & done
    wait
    assert_eq "ledger parses after 10 parallel refreshes" 'ok' \
        "$(jq -r 'if (.rows | type) == "array" then "ok" else "bad" end' \
            "$SYNC/usage-testbox-linux.json" 2>/dev/null || echo bad)"
    assert_eq "no tmp litter in sync dir" '' "$(ls "$SYNC"/*.tmp.* 2>/dev/null)"
    assert_eq "no tmp litter in cache dir" '' "$(ls "$CACHE"/*.tmp.* 2>/dev/null)"
    assert_eq "lock released" '' "$(ls -d "$CACHE/refresh.lock" 2>/dev/null)"
}

test_stale_lock_is_broken() {
    seed_fleet
    mkdir -p "$CACHE/refresh.lock"
    touch -d '10 minutes ago' "$CACHE/refresh.lock"
    run_v2 refresh
    assert_eq "refresh proceeded past a stale lock" 'ok' \
        "$(jq -r 'if .rows then "ok" else "bad" end' \
            "$SYNC/usage-testbox-linux.json" 2>/dev/null || echo bad)"
}

test_fresh_lock_skips_quietly() {
    seed_fleet
    rm -f "$SYNC/usage-testbox-linux.json"
    mkdir -p "$CACHE/refresh.lock" # held by a live peer
    run_v2 refresh
    assert_eq "held lock means no write, no error" 'absent' \
        "$([[ -f "$SYNC/usage-testbox-linux.json" ]] && echo present || echo absent)"
    rmdir "$CACHE/refresh.lock"
}

test_parallel_refreshes_no_torn_files
test_stale_lock_is_broken
test_fresh_lock_skips_quietly
test_report_tables

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
exit $((FAIL > 0))
