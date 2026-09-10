#!/usr/bin/env python3
"""PreToolUse guard: characters the house style keeps out of written text.

Reads only what a call adds: a file written whole, an edit's replacement text,
a shell command carrying a heredoc or a script. An edit's `old_string`, a
patch's removed lines and every search pattern are where these characters
legitimately appear, since removing one means naming it first. An escaped
codepoint describes the character without being it, so it passes, which is why
the rosters below are codepoints too. Banning one more is one line in REFUSED.
"""

import json
import sys
import unicodedata

# Refused outright. Append a codepoint to ban it.
REFUSED = (
    0x2014,  # em dash
    0x2013,  # en dash
    0x2026,  # ellipsis
    0x2192,  # rightwards arrow
    0x2190,  # leftwards arrow
    0x2194,  # left right arrow
    0x21D2,  # rightwards double arrow
    0x21D0,  # leftwards double arrow
    0x21D4,  # left right double arrow
    0x2191,  # upwards arrow
    0x2193,  # downwards arrow
)

# Handed to the human rather than refused. Append a codepoint to ask about it.
ASKED = (0x00B7,)  # interpunct

DEFAULT_FIX = "Write the ASCII word or symbol it stands in for."
FIXES = {
    0x2014: (
        "Use periods or commas only (no parentheses, no en dashes, no "
        "hyphen-as-dash substitutes). If a thought needs separation, end the "
        "sentence or use a comma."
    ),
    0x2013: "Write a range as `3 to 5`, and a hyphen only where a hyphen is meant.",
    0x2026: "Write the three periods, or end the sentence.",
    0x2192: "Write `to` or `becomes`, or the ASCII `->`.",
    0x2190: "Write the word, or the ASCII `<-`.",
    0x2194: "Write the word, or the ASCII `<->`.",
    0x21D2: "Write `implies` or `then`, or the ASCII `=>`.",
    0x21D0: "Write the word, or the ASCII `<=`.",
    0x21D4: "Write `if and only if`, or the ASCII `<=>`.",
    0x2191: "Name the key or the direction: `up`.",
    0x2193: "Name the key or the direction: `down`.",
    0x00B7: (
        "An interpunct is fine where the human asked for one. A comma, a slash "
        "or a hyphen separates just as well and needs no approval."
    ),
}

FINDING = "{name} (U+{code:04X}) in: {excerpt}\n  {fix}"
REFUSE_MESSAGE = (
    "agent-guard: this call writes characters the unslop rules refuse.\n\n"
    "{findings}\n\n"
    "Plain ASCII carries the same meaning, and these characters are an AI "
    "tell. To write one on purpose, escape it: {escapes} in Python, JSON or "
    "JS, `\\x{{...}}` on the same codepoint in an rg pattern."
)
ASK_MESSAGE = (
    "agent-guard: this call writes characters only the human approves.\n\n"
    "{findings}\n\n"
    "These stand where the human asked for them, so the call is theirs to "
    "allow. To write one without asking, escape it: {escapes}."
)

# stdout with this exit code asks; any other non-zero denies.
ASK_EXIT = 2

SHELL_TOOLS = {"Bash", "PowerShell", "exec_command", "shell_command", "shell"}


def added_lines(patch):
    """The `+` side of an apply_patch envelope, which is the only side written."""
    return "\n".join(
        line[1:] for line in patch.splitlines() if line.startswith("+")
    )


def text_field(source, *keys):
    for key in keys:
        value = source.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def written_text(tool, tool_input):
    """What this call would add, empty for a call that adds nothing."""
    if tool == "apply_patch":
        return added_lines(text_field(tool_input, "command", "cmd"))
    if tool in SHELL_TOOLS:
        return text_field(tool_input, "command", "cmd")
    if tool == "Write":
        return text_field(tool_input, "content")
    if tool == "Edit":
        return text_field(tool_input, "new_string")
    if tool == "MultiEdit":
        edits = tool_input.get("edits")
        if not isinstance(edits, list):
            return ""
        return "\n".join(
            text_field(edit, "new_string") for edit in edits if isinstance(edit, dict)
        )
    if tool == "NotebookEdit":
        return text_field(tool_input, "new_source")
    return ""


def excerpt(text, char, width=56):
    """The first occurrence in one line of context, so the agent can find it."""
    index = text.find(char)
    start, end = max(0, index - width // 2), min(len(text), index + width // 2)
    body = " ".join(text[start:end].split())
    return ("..." if start else "") + body + ("..." if end < len(text) else "")


def report(text, roster):
    """The roster's codepoints present in `text`, and a line about each."""
    found = [code for code in roster if chr(code) in text]
    listing = "\n".join(
        FINDING.format(
            name=unicodedata.name(chr(code), "unnamed character").lower(),
            code=code,
            excerpt=excerpt(text, chr(code)),
            fix=FIXES.get(code, DEFAULT_FIX),
        )
        for code in found
    )
    return found, listing


def escapes(found):
    return ", ".join("`\\u%04x`" % code for code in found)


def main():
    tool = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 0
    tool_input = payload.get("tool_input")
    text = written_text(tool, tool_input if isinstance(tool_input, dict) else {})
    if not text:
        return 0

    found, listing = report(text, REFUSED)
    if found:
        print(REFUSE_MESSAGE.format(findings=listing, escapes=escapes(found)))
        return 1

    found, listing = report(text, ASKED)
    if found:
        print(ASK_MESSAGE.format(findings=listing, escapes=escapes(found)))
        return ASK_EXIT
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except BaseException:
        # A broken check degrades to silence rather than denying real work.
        sys.exit(0)
