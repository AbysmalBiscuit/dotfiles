#!/usr/bin/env bash
# PreToolUse/Bash guard: blocks the `rg -r<flags>` footgun.
#
# In ripgrep, `-r`/`--replace` takes the following characters as replacement
# text and only rewrites printed output (rg never edits files). Carrying over
# the grep habit, `rg -rn` is parsed as --replace=n and silently prints matches
# with `n` substituted instead of showing line numbers — no error, plausible
# wrong output. Same trap for -rl (-l), -rc (-c), and reversed clusters (-nr).
#
# Blocks a single-dash short-flag cluster that contains `r` and at least one
# other letter, but only when it is an argument to an `rg` command. Leaves the
# legitimate spaced forms `rg -r 'text' PAT` and `rg --replace 'text' PAT` alone,
# and ignores the word "rg" inside quoted strings (e.g. a commit message).

cmd=$(jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

read -r -a toks <<<"$cmd"
in_rg=0
expect_cmd=1
bad=""

for t in "${toks[@]}"; do
  case "$t" in
    '|'|'||'|'&&'|';'|'&'|'|&')
      in_rg=0; expect_cmd=1; continue ;;
  esac

  if [ "$expect_cmd" = 1 ]; then
    # Env assignments and command wrappers keep us in command position.
    case "$t" in
      [A-Za-z_]*=*) continue ;;
      sudo|command|time|nice|noglob|builtin|exec|env|xargs|then|do|else) continue ;;
    esac
    expect_cmd=0
    case "$t" in
      rg|*/rg) in_rg=1 ;;
      *)       in_rg=0 ;;
    esac
    continue
  fi

  if [ "$in_rg" = 1 ] && [ "${#t}" -ge 3 ] && [[ "$t" =~ ^-[a-zA-Z]*r[a-zA-Z]*$ ]]; then
    bad="$t"
    break
  fi
done

[ -z "$bad" ] && exit 0

reason="rg recurses by default and has no recursive flag. In '$bad', -r is --replace: it swallows the remaining letters as replacement text and silently prints matches with that text substituted instead of applying -n/-l/-c (rg never edits files, but the output is wrong and looks fine). Pass the flags separately: -n (line numbers), -l (files with matches), -c (count). For a real replacement use the spaced form: rg -r 'text' PATTERN or rg --replace 'text' PATTERN."

jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
