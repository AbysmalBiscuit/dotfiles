#!/usr/bin/env bash
# Course-corrects coding agents in-flight by feeding convention violations back
# to the model. Dispatches on the hook event name in the payload on stdin, so a
# single entry point works for every hook it is registered under.
#
#   PostToolUse (Edit|Write|MultiEdit)  fast per-file ast-grep rules, advisory
#   Stop | SubagentStop                 fallow audit on the changeset, gating
#
# Always exits 0 and speaks through the hookSpecificOutput JSON contract, so a
# broken check degrades to silence rather than wedging the session.

set -uo pipefail

# Everything this hook needs lives beside it, so the whole directory relocates
# as one unit. Resolved through the symlink on PATH, not from it.
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
CONFIG_DIR="${AGENT_GUARD_CONFIG_DIR:-$(dirname "$(dirname "$SELF")")}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/agent-guard"
SGCONFIG="$CONFIG_DIR/sgconfig.yml"

[[ -f "$CONFIG_DIR/config.env" ]] && . "$CONFIG_DIR/config.env"

# Blocking is opt-in. A gate that is wrong once teaches every agent to route
# around it, so a rule earns the right to block only after it proves quiet.
BLOCK="${AGENT_GUARD_BLOCK:-0}"
MAX_BLOCKS="${AGENT_GUARD_MAX_BLOCKS:-2}"
USE_FALLOW="${AGENT_GUARD_FALLOW:-1}"
FALLOW_TIMEOUT="${AGENT_GUARD_FALLOW_TIMEOUT:-45}"
MAX_FINDINGS="${AGENT_GUARD_MAX_FINDINGS:-8}"
# Bound on symbols reference-counted per changeset, so a wide diff stays cheap.
MAX_SYMBOLS="${AGENT_GUARD_MAX_SYMBOLS:-40}"
# A function with one caller is often a fine module boundary, so that half is
# opt-in. The test-only-consumer case is the one that is nearly always wrong.
SINGLE_CALLER="${AGENT_GUARD_SINGLE_CALLER:-0}"

# Registered in user settings, so it would otherwise fire in every project on
# the machine. Only trees matching this run; widen it as the rules generalize.
SCOPE_RE="${AGENT_GUARD_SCOPE:-/adaptyv/}"
# Generated code is duplicated by design; flagging it trains agents to ignore
# the hook. Override with a project-specific regex in config.env.
IGNORE_RE="${AGENT_GUARD_IGNORE:-(db-types|api-client|modal-clients|plate-api-client)/|/types/supabase\\.ts$|/_shared/supabase\\.ts$|\\.gen\\.|/generated/|/__generated__/|\\.d\\.ts$}"

have() { command -v "$1" >/dev/null 2>&1; }

# A hook that is silent when healthy is indistinguishable from one that is
# silently broken, so make the difference inspectable.
if [[ "${1:-}" == "doctor" ]]; then
  printf 'agent-guard doctor\n  config dir : %s\n  sgconfig   : %s\n  scope      : %s\n' \
    "$CONFIG_DIR" \
    "$([[ -f "$SGCONFIG" ]] && echo present || echo MISSING)" \
    "$SCOPE_RE"
  printf '  rules      : %s\n' "$(ls "$CONFIG_DIR/rules"/*.yml 2>/dev/null | wc -l)"
  for t in jq ast-grep fallow git timeout sha256sum; do
    printf '  %-10s : %s\n' "$t" "$(command -v "$t" 2>/dev/null || echo 'not installed')"
  done
  printf '\n  jq missing      -> hook is fully inert\n'
  printf '  ast-grep missing -> per-file rules skipped\n'
  printf '  fallow missing   -> changeset duplication check skipped\n'
  printf '  timeout missing  -> fallow runs unbounded\n'
  printf '  sha256sum missing-> repeat-run caching disabled\n'
  exit 0
fi

emit_silent() { exit 0; }

# emit <event> <context> [deny-reason]; an empty reason stays advisory
emit() {
  local event="$1" context="$2" deny="${3:-}"
  if [[ -n "$deny" ]]; then
    jq -nc --arg e "$event" --arg c "$context" --arg r "$deny" \
      '{hookSpecificOutput:{hookEventName:$e,permissionDecision:"deny",permissionDecisionReason:$r,additionalContext:$c}}'
  else
    jq -nc --arg e "$event" --arg c "$context" \
      '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
  fi
  exit 0
}

# Per-file syntactic rules. Must stay in the low milliseconds: this fires on
# every edit from every agent and subagent, so its cost multiplies.
check_file() {
  local file
  file="$(jq -r '.tool_input.file_path // empty' <<<"$PAYLOAD")"
  [[ -n "$file" && -f "$file" ]] || emit_silent
  [[ "$file" =~ \.(ts|tsx|mts|cts)$ ]] || emit_silent
  have ast-grep || emit_silent
  [[ -f "$SGCONFIG" ]] || emit_silent

  local findings
  findings="$(ast-grep scan -c "$SGCONFIG" --json=compact "$file" 2>/dev/null \
    | jq -r --argjson n "$MAX_FINDINGS" '
        (. // []) | .[:$n] | .[]
        | "  \(.file):\(.range.start.line + 1)  [\(.ruleId | sub("-(typescript|tsx)$";""))] \(.message)"' 2>/dev/null)"
  [[ -n "$findings" ]] || emit_silent

  emit "PostToolUse" "agent-guard found convention violations in the file you just wrote. Fix them now rather than leaving them for review:

$findings

These come from this project's documented conventions. If a finding is genuinely wrong, say why instead of silently ignoring it."
}

# Duplication introduced by the changeset. Generated code is excluded: it is
# duplicated by design, and flagging it teaches agents to ignore the hook.
find_duplication() {
  local base="$1" seen_file="$2" raw groups new_prints
  [[ "$USE_FALLOW" == "1" ]] || return 0
  have fallow || return 0

  if have timeout; then
    raw="$(timeout "$FALLOW_TIMEOUT" fallow audit --base "$base" --format json 2>/dev/null)"
  else
    raw="$(fallow audit --base "$base" --format json 2>/dev/null)"
  fi
  [[ -n "$raw" ]] || return 0

  groups="$(jq -c --arg ig "$IGNORE_RE" '
      [.duplication.clone_groups[]?
       | select(.introduced == true)
       | select([.instances[].file | test($ig)] | any | not)]' <<<"$raw" 2>/dev/null)"
  [[ "$groups" == "[]" || -z "$groups" ]] && return 0

  new_prints="$(jq -r '.[].fingerprint' <<<"$groups" 2>/dev/null | grep -vxF -f "$seen_file" 2>/dev/null)"
  [[ -n "$new_prints" ]] || return 0
  printf '%s\n' "$new_prints" >> "$seen_file"

  jq -r --argjson n "$MAX_FINDINGS" '
      .[:$n] | .[]
      | "  \(.line_count) duplicated lines across \(.instances | length) sites (\(.fingerprint)):\n"
        + (.instances[:4] | map("    \(.file):\(.start_line)") | join("\n"))
        + (if (.instances | length) > 4 then "\n    ... and \((.instances | length) - 4) more" else "" end)' <<<"$groups" 2>/dev/null
}

# Helpers extracted past the point of usefulness. Two shapes are reported: an
# export whose only consumer is its own test, and an export with exactly one
# real caller. Barrel re-exports do not count as consumers.
# Reference counting is name-based, so it is a heuristic, which is why this
# stays advisory: a same-named symbol elsewhere reads as a consumer.
find_over_extraction() {
  local changed="$1" seen_file="$2"
  have ast-grep || return 0
  local out="" checked=0 file lang query names name refs testrefs otherrefs mark

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    [[ "$file" =~ $IGNORE_RE ]] && continue
    [[ "$file" =~ (test|spec)\.|/tests?/|__tests__ ]] && continue
    case "$file" in *.tsx) lang=tsx ;; *.ts) lang=typescript ;; *) continue ;; esac
    query="$CONFIG_DIR/queries/exported-symbols-$lang.yml"
    [[ -f "$query" ]] || continue

    names="$(ast-grep scan -r "$query" --json=compact "$file" 2>/dev/null \
             | jq -r '.[]?.metaVariables.single.NAME.text' 2>/dev/null | sort -u)"
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      [[ "$checked" -ge "$MAX_SYMBOLS" ]] && break 2
      checked=$((checked + 1))
      grep -qxF "$file:$name" "$seen_file" 2>/dev/null && continue

      refs="$(rg -l --type ts -- "\b$name\b" . 2>/dev/null | sed 's|^\./||' | grep -vxF "$file")"
      testrefs="$(printf '%s\n' "$refs" | grep -cE '(test|spec)\.|/tests?/|__tests__' 2>/dev/null || true)"
      # A barrel only forwards the symbol; it is not a consumer of it.
      otherrefs="$(printf '%s\n' "$refs" | grep -vE '(test|spec)\.|/tests?/|__tests__|/index\.tsx?$' 2>/dev/null | grep -c . || true)"

      mark=""
      if [[ "$otherrefs" -eq 0 && "$testrefs" -gt 0 ]]; then
        mark="  $file:$name is exported but consumed only by its test. Inline it, or drop the export and the test with it."
      elif [[ "$SINGLE_CALLER" == "1" && "$otherrefs" -eq 1 ]]; then
        mark="  $file:$name has exactly one caller. Inline it there unless the split earns its keep."
      fi
      [[ -n "$mark" ]] || continue
      printf '%s:%s\n' "$file" "$name" >> "$seen_file"
      out+="$mark"$'\n'
    done <<<"$names"
  done <<<"$changed"

  printf '%s' "$out"
}

# Cross-file analysis on the changeset. Only findings the changeset introduced
# are reported; inherited debt is not this agent's to answer for.
check_changeset() {
  have git || emit_silent
  git rev-parse --git-dir >/dev/null 2>&1 || emit_silent

  local base changed
  base="${AGENT_GUARD_BASE:-}"
  [[ -n "$base" ]] || base="$(git merge-base HEAD "$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo origin/HEAD)" 2>/dev/null)"
  [[ -n "$base" ]] || base="$(git rev-parse HEAD 2>/dev/null)"
  changed="$(git diff --name-only "$base" -- '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null | head -200)"
  [[ -n "$changed" ]] || emit_silent

  # Skip re-running when the changeset has not moved since the last report.
  local sdir fingerprint_now seen_file
  sdir="$STATE_DIR/$SESSION"; mkdir -p "$sdir" 2>/dev/null
  seen_file="$sdir/seen-fingerprints"; touch "$seen_file" 2>/dev/null
  if have sha256sum; then
    fingerprint_now="$(git diff "$base" -- '*.ts' '*.tsx' 2>/dev/null | sha256sum | cut -c1-16)"
  elif have cksum; then
    fingerprint_now="$(git diff "$base" -- '*.ts' '*.tsx' 2>/dev/null | cksum | tr -d ' ')"
  fi
  if [[ -n "${fingerprint_now:-}" ]]; then
    [[ -f "$sdir/last-diff" && "$(cat "$sdir/last-diff")" == "$fingerprint_now" ]] && emit_silent
    printf '%s' "$fingerprint_now" > "$sdir/last-diff"
  fi

  local who="This agent"; [[ -n "$AGENT_TYPE" ]] && who="Subagent '$AGENT_TYPE'"
  local context="" dupes extraction
  dupes="$(find_duplication "$base" "$seen_file")"
  extraction="$(find_over_extraction "$changed" "$seen_file")"

  if [[ -n "$dupes" ]]; then
    context+="$who introduced duplicated code rather than reusing what already exists:

$dupes

Consolidate against the existing implementation, or explain why a separate one is warranted. Run 'fallow dupes --trace <fingerprint>' for the full clone group.
"
  fi
  if [[ -n "$extraction" ]]; then
    [[ -n "$context" ]] && context+="
"
    context+="$who added helpers that carry their own abstraction cost without earning it:

$extraction
An indirection worth keeping has more than one caller, or a name that explains something the inlined code would not."
  fi
  [[ -n "$context" ]] || emit_silent

  local blocks=0
  [[ -f "$sdir/blocks" ]] && blocks="$(cat "$sdir/blocks")"
  if [[ "$BLOCK" == "1" && -n "$dupes" && "$blocks" -lt "$MAX_BLOCKS" ]]; then
    printf '%s' "$((blocks + 1))" > "$sdir/blocks"
    emit "$EVENT" "$context" "agent-guard: duplication introduced by this changeset is unresolved"
  fi
  emit "$EVENT" "$context"
}

have jq || exit 0
PAYLOAD="$(cat)"
[[ -z "$PAYLOAD" ]] && exit 0

EVENT="${1:-$(jq -r '.hook_event_name // empty' <<<"$PAYLOAD")}"
SESSION="$(jq -r '.session_id // "nosession"' <<<"$PAYLOAD")"
CWD="$(jq -r '.cwd // empty' <<<"$PAYLOAD")"
AGENT_TYPE="$(jq -r '.agent_type // empty' <<<"$PAYLOAD")"
[[ -n "$CWD" && -d "$CWD" ]] && cd "$CWD" 2>/dev/null
[[ "$PWD/" =~ $SCOPE_RE ]] || exit 0

case "$EVENT" in
  PostToolUse)       check_file ;;
  Stop|SubagentStop) check_changeset ;;
  *)                 emit_silent ;;
esac
