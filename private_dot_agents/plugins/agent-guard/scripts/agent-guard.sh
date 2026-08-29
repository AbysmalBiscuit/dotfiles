#!/usr/bin/env bash
# Course-corrects coding agents in-flight by feeding convention violations back
# to the model. Dispatches on the hook event name in the payload on stdin, so a
# single entry point works for every hook it is registered under.
#
#   PostToolUse (Edit|Write|MultiEdit)  fast per-file ast-grep rules and
#                                       checks/ scripts, advisory
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

# Rules come in layers, each named by its directory in a tree: the tracked one
# first, then a machine-local overlay beside it that outranks it. Later roots add
# rules and tighten settings, and a tree opts in by creating one of these
# directories — nothing in the global install changes.
ROOT_NAMES=(.agents/plugins/agent-guard .agents/plugins/agent-guard.local)
CONFIG_ROOTS=("$CONFIG_DIR")

have() { command -v "$1" >/dev/null 2>&1; }

# A config.env alone is enough to be a root: a tree that wants only the global
# rules under its own settings still opts in by carrying the directory.
is_root() {
  [[ -d "$1" ]] && [[ -d "$1/rules" || -d "$1/checks" || -f "$1/sgconfig.yml" || -f "$1/config.env" ]]
}

# Walks every ancestor of the working directory, outermost first, so a nearer
# tree layers over a wider one — a checkout over the directory that holds every
# checkout of that project, over the global install. Deliberately not keyed on
# the git toplevel: worktrees of one repository share settings that belong in the
# directory above them rather than in the repository's own history.
# Depends on the working directory, so it runs after the payload's cwd is applied.
discover_roots() {
  local dir="$PWD" dirs=() root name i
  while :; do
    dirs+=("$dir")
    [[ "$dir" == "/" ]] && break
    dir="${dir%/*}"
    [[ -n "$dir" ]] || dir=/
  done
  for (( i = ${#dirs[@]} - 1; i >= 0; i-- )); do
    for name in "${ROOT_NAMES[@]}"; do
      root="${dirs[i]}/$name"
      [[ "$root" != "$CONFIG_DIR" ]] || continue
      is_root "$root" && CONFIG_ROOTS+=("$root")
    done
  done
  return 0
}

# Every root's config.env, in order, so a tree tunes extensions, ignore patterns
# and which checks run without editing the global install. Sourcing is what makes
# a root a root: a directory whose config.env you would not run is not one to
# open a shell in either.
load_config() {
  local dir
  for dir in "${CONFIG_ROOTS[@]}"; do
    [[ -f "$dir/config.env" ]] && . "$dir/config.env"
  done
  return 0
}

# A root ships either a full sgconfig.yml — required for custom languages, whose
# libraryPath resolves relative to it — or just a rules/ directory. Synthesise a
# config for the latter, cached in the state dir and refreshed when rules change.
sgconfig_for() {
  local root="$1" generated
  if [[ -f "$root/sgconfig.yml" ]]; then
    printf '%s' "$root/sgconfig.yml"
    return 0
  fi
  [[ -d "$root/rules" ]] || return 1
  generated="$STATE_DIR/generated/$(printf '%s' "$root" | tr -c 'A-Za-z0-9' '_').yml"
  mkdir -p "$(dirname "$generated")" 2>/dev/null
  [[ -f "$generated" && "$generated" -nt "$root/rules" ]] \
    || printf 'ruleDirs:\n  - %s\n' "$root/rules" > "$generated"
  printf '%s' "$generated"
}

# Reads whatever load_config resolved, so it runs after that.
resolve_settings() {
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
  # opt-in.
  SINGLE_CALLER="${AGENT_GUARD_SINGLE_CALLER:-0}"
  # Exports whose only consumer is their own test. A tree mid-migration, where a
  # parity test is deliberately the sole caller of the new path, turns this off.
  TEST_ONLY="${AGENT_GUARD_TEST_ONLY:-1}"

  # Which files the per-file rules run on. A repo adding rules for another
  # language widens this in its own config.env.
  EXT_RE="${AGENT_GUARD_EXTENSIONS:-\\.(ts|tsx|mts|cts)$}"

  # Generated code is duplicated by design; flagging it trains agents to ignore
  # the hook. Only the language-wide shapes are listed — a project names its own
  # generated directories through the additive knob below.
  IGNORE_RE="${AGENT_GUARD_IGNORE:-\\.gen\\.|/generated/|/__generated__/|\\.d\\.ts$}"
  # Appended rather than assigned, so a layer adds paths without restating the
  # defaults. Restating them by hand invites a stray leading '|', whose empty
  # alternation matches every path and silently disables the whole check.
  [[ -z "${AGENT_GUARD_IGNORE_EXTRA:-}" ]] || IGNORE_RE="$IGNORE_RE|$AGENT_GUARD_IGNORE_EXTRA"
}

# A hook that is silent when healthy is indistinguishable from one that is
# silently broken, so make the difference inspectable.
if [[ "${1:-}" == "doctor" ]]; then
  discover_roots
  load_config
  resolve_settings
  printf 'agent-guard doctor\n  extensions : %s\n  ignore     : %s\n  roots      :\n' \
    "$EXT_RE" "$IGNORE_RE"
  for root in "${CONFIG_ROOTS[@]}"; do
    printf '    %s\n      config   : %s\n      rules(own): %s\n      checks   : %s\n' \
      "$root" \
      "$(sgconfig_for "$root" 2>/dev/null || echo NONE)" \
      "$(ls "$root/rules"/*.yml 2>/dev/null | wc -l)" \
      "$(ls "$root/checks"/*.sh 2>/dev/null | wc -l)"
  done
  for t in jq ast-grep fallow git timeout sha256sum; do
    printf '  %-10s : %s\n' "$t" "$(command -v "$t" 2>/dev/null || echo 'not installed')"
  done
  printf '\n  jq missing      -> hook is fully inert\n'
  printf '  ast-grep missing -> per-file rules skipped (checks/ still run)\n'
  printf '  fallow missing   -> changeset duplication check skipped\n'
  printf '  timeout missing  -> fallow runs unbounded\n'
  printf '  sha256sum missing-> repeat-run caching disabled\n'
  printf '  only the global root listed -> nothing here opted in; the hook is inert\n'
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

# Conventions ast-grep cannot reach. Tree-sitter discards whitespace, so nothing
# about blank lines or vertical spacing is expressible as a rule; those live here
# instead. A root's checks/ holds bash scripts, each called with one file path and
# printing findings on stdout in the shape the ast-grep scan produces:
#
#   <2 spaces><file>:<line><2 spaces>[<rule-id>] <message>
#
# Run through bash rather than executed directly, because the executable bit does
# not survive a clone onto the team's Windows machines. Same latency budget as the
# rules: this fires on every edit.
run_checks() {
  local file="$1" root script out
  for root in "${CONFIG_ROOTS[@]}"; do
    [[ -d "$root/checks" ]] || continue
    for script in "$root/checks"/*.sh; do
      [[ -f "$script" ]] || continue
      out="$(bash "$script" "$file" 2>/dev/null)"
      [[ -n "$out" ]] && printf '%s\n' "$out"
    done
  done
  return 0
}

# Per-file syntactic rules. Must stay in the low milliseconds: this fires on
# every edit from every agent and subagent, so its cost multiplies.
check_file() {
  local file
  file="$(jq -r '.tool_input.file_path // empty' <<<"$PAYLOAD")"
  [[ -n "$file" && -f "$file" ]] || emit_silent
  [[ "$file" =~ $EXT_RE ]] || emit_silent

  # One scan per root rather than one merged config: each root's sgconfig resolves
  # its own ruleDirs and custom-language libraryPath relative to itself.
  local findings="" root config hits
  if have ast-grep; then
    for root in "${CONFIG_ROOTS[@]}"; do
      config="$(sgconfig_for "$root")" || continue
      hits="$(ast-grep scan -c "$config" --json=compact "$file" 2>/dev/null \
        | jq -r '
            (. // []) | .[]
            | "  \(.file):\(.range.start.line + 1)  [\(.ruleId | sub("-(typescript|tsx)$";""))] \(.message)"' 2>/dev/null)"
      [[ -n "$hits" ]] && findings+="$hits"$'\n'
    done
  fi
  hits="$(run_checks "$file")"
  [[ -n "$hits" ]] && findings+="$hits"$'\n'
  findings="$(printf '%s' "$findings" | grep -v '^[[:space:]]*$' | head -n "$MAX_FINDINGS")"
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

# Helpers extracted past the point of usefulness. Two shapes are reported, each
# behind its own switch: an export whose only consumer is its own test, and an
# export with exactly one real caller. Barrel re-exports do not count as
# consumers.
# Reference counting is name-based, so it is a heuristic, which is why this
# stays advisory: a same-named symbol elsewhere reads as a consumer.
find_over_extraction() {
  local changed="$1" seen_file="$2"
  [[ "$TEST_ONLY" == "1" || "$SINGLE_CALLER" == "1" ]] || return 0
  have ast-grep || return 0
  local out="" checked=0 file lang query names name refs testrefs otherrefs mark i

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    [[ "$file" =~ $IGNORE_RE ]] && continue
    [[ "$file" =~ (test|spec)\.|/tests?/|__tests__ ]] && continue
    case "$file" in *.tsx) lang=tsx ;; *.ts) lang=typescript ;; *) continue ;; esac
    # Last root wins, so a repo can replace the global query with its own.
    query=""
    for (( i = ${#CONFIG_ROOTS[@]} - 1; i >= 0; i-- )); do
      if [[ -f "${CONFIG_ROOTS[i]}/queries/exported-symbols-$lang.yml" ]]; then
        query="${CONFIG_ROOTS[i]}/queries/exported-symbols-$lang.yml"
        break
      fi
    done
    [[ -n "$query" ]] || continue

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
      if [[ "$TEST_ONLY" == "1" && "$otherrefs" -eq 0 && "$testrefs" -gt 0 ]]; then
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

discover_roots
load_config
resolve_settings

# Registered in user settings, so it is reachable from every project on the
# machine. Carrying an agent-guard directory somewhere above the working
# directory is the whole opt-in; with only the global root discovered there is
# nothing here to enforce, and the hook stays out of the way.
[[ "${#CONFIG_ROOTS[@]}" -gt 1 ]] || exit 0

case "$EVENT" in
  PostToolUse)       check_file ;;
  Stop|SubagentStop) check_changeset ;;
  *)                 emit_silent ;;
esac
