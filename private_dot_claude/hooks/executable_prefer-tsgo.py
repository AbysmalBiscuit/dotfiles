#!/usr/bin/env python3
"""PreToolUse/Bash guard: routes TypeScript typechecking to tsgo.

tsgo (the native TypeScript port) checks the same project several times faster
than tsc, so it is the right tool for an iteration-loop typecheck. Two command
shapes reach the checker:

  * direct     — `tsc --noEmit`, `bunx tsc --noEmit`, `node_modules/.bin/tsc …`
  * via script — `bun run typecheck`, `turbo run typecheck`, `pnpm typecheck`

The script form is the one that hides the checker: `tsc --noEmit` lives in
package.json, never appears in the command, and a package runner puts
node_modules/.bin ahead of PATH — so a `tsc -> tsgo` symlink in PATH is never
consulted and the slow binary runs anyway. Both shapes are blocked here.

Denies rather than rewriting the command: tsgo is a preview compiler whose
diagnostics do not always match tsc's, and CI gates on tsc. A silent swap would
leave the transcript claiming one checker ran while the other did, so the
substitution stays visible and the result gets reported as tsgo.
"""

import json
import re
import shlex
import sys

# Pipes, lists, subshells, groups, redirections and process substitutions all
# start a fresh command position.
OPERATORS = re.compile(r"^[|&;()<>{}\n]+$")
# Wrappers that keep the next word in command position.
WRAPPERS = {
    "sudo", "command", "builtin", "exec", "env", "time", "timeout", "nice",
    "ionice", "stdbuf", "nohup", "xargs", "watch", "noglob", "then", "do",
    "else", "elif", "if", "while", "until", "!", "bunx", "npx", "dlx",
}
RUNNERS = {"bun", "npm", "pnpm", "yarn", "deno", "turbo"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
DURATION = re.compile(r"^\d+[smhd]?$")


def tokenize(cmd):
    lexer = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    return list(lexer)


def find_hit(cmd, depth=0):
    """Return ("script"|"direct", command_word) for a tsc-bound command."""
    if depth > 2:
        return None
    try:
        toks = tokenize(cmd)
    except ValueError:
        return regex_fallback(cmd)

    runner = None
    in_tsc = False
    cmd_pos = True
    shell = None

    for i, t in enumerate(toks):
        if OPERATORS.match(t):
            runner, in_tsc, cmd_pos, shell = None, False, True, None
            continue

        if cmd_pos:
            # Env assignments, wrapper options and their operands (timeout 10,
            # nice -n 5) leave us still looking for the real command word.
            if re.match(r"^[A-Za-z_][A-Za-z_0-9]*=", t):
                continue
            if t in WRAPPERS:
                continue
            if t.startswith("-") or DURATION.match(t):
                continue

            cmd_pos = False
            name = t.rsplit("/", 1)[-1]
            runner = name if name in RUNNERS else None
            in_tsc = name == "tsc"
            shell = name if name in SHELLS else None
            continue

        # `bash -c '<nested command>'` — scan the nested string too.
        if shell and t == "-c" and i + 1 < len(toks):
            hit = find_hit(toks[i + 1], depth + 1)
            if hit:
                return hit
            continue

        if runner and t == "typecheck":
            return ("script", runner)
        if in_tsc and t == "--noEmit":
            return ("direct", "tsc")

    return None


def regex_fallback(cmd):
    """Unbalanced quotes etc. — scan each shell segment for either shape."""
    for seg in re.split(r"[|;&\n(){}]+", cmd):
        if re.search(r"(?:^|\s|/)(bun|npm|pnpm|yarn|deno|turbo)\s+(?:run\s+)?typecheck\b", seg):
            return ("script", "a package runner")
        if re.search(r"(?:^|\s|/)tsc\b", seg) and "--noEmit" in seg:
            return ("direct", "tsc")
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    cmd = (payload.get("tool_input") or {}).get("command") or ""
    if not cmd or "tsgo" in cmd:
        return

    hit = find_hit(cmd)
    if not hit:
        return

    shape, word = hit
    if shape == "script":
        detail = (
            f"`{word} … typecheck` runs `tsc --noEmit` from package.json. The runner puts "
            "node_modules/.bin ahead of PATH, so the bundled tsc wins over any tsgo symlink "
            "and the slow checker runs regardless of what PATH says."
        )
    else:
        detail = "This invokes tsc directly; swap the binary and keep the flags."

    reason = (
        f"Use tsgo for typechecking, not tsc — it is several times faster on the same project. "
        f"{detail} Run `tsgo --noEmit` from the workspace directory instead (add "
        "`-p tsconfig.json` if that workspace's typecheck script passes it). "
        "Report the result as tsgo: it is a preview compiler whose diagnostics can differ "
        "from tsc's, and CI gates on tsc, so a clean tsgo run is not proof CI passes. "
        "Count errors over the whole output — never a `tail`, which truncates the count."
    )
    json.dump({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }, sys.stdout)


if __name__ == "__main__":
    main()
