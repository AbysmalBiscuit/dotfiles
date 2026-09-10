#!/usr/bin/env python3
"""PreToolUse guard: typographic punctuation in the text a call would write.

Reads only what a call adds: a file written whole, an edit's replacement text,
a shell command carrying a heredoc or a script. An edit's `old_string`, a
patch's removed lines and every search pattern are where these characters
legitimately appear, since removing one means naming it first. An escape is
ASCII describing the character rather than being it, so `\\u2014` and `&mdash;`
pass. The interpunct asks instead of refusing: exit 2 hands it to the human.
"""

import json
import sys

EM_DASH = "\u2014"
EN_DASH = "\u2013"
INTERPUNCT = "\u00b7"

NAMES = {
    EM_DASH: "em dash (U+2014)",
    EN_DASH: "en dash (U+2013)",
    INTERPUNCT: "interpunct (U+00B7)",
}
REFUSED = (EM_DASH, EN_DASH)
ASKED = (INTERPUNCT,)

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


def report(text, characters):
    return [f"{NAMES[c]} in: {excerpt(text, c)}" for c in characters if c in text]


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

    refused = report(text, REFUSED)
    if refused:
        print("agent-guard: this call writes punctuation the unslop rules refuse.\n")
        print("\n".join(refused))
        print(
            "\nUse periods or commas only (no parentheses, no en dashes, no "
            "hyphen-as-dash substitutes). Em dashes are an AI tell, and reaching "
            "for parentheses instead just trades one tell for another. If a "
            "thought needs separation, end the sentence or use a comma. Write a "
            "range as `3 to 5`, and a hyphen only where a hyphen is meant. To "
            "write the character itself, escape it: \\u2014 in Python, JSON or "
            "JS, \\x{2014} in an rg pattern, &mdash; in HTML."
        )
        return 1

    asked = report(text, ASKED)
    if asked:
        print("agent-guard: this call writes punctuation only the human approves.\n")
        print("\n".join(asked))
        print(
            "\nAn interpunct stands where the human asked for one, so this call is "
            "theirs to allow. A comma, a slash or a hyphen separates just as well "
            "and needs no approval. To write the character itself, escape it: "
            "\\u00b7 in Python, JSON or JS, &middot; in HTML."
        )
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
