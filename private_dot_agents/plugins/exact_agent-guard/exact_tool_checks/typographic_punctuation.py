#!/usr/bin/env python3
"""PreToolUse guard: typographic punctuation in the text a call would write.

Em dash and en dash are the loudest tell that a model wrote a line, and they
reach a tree by three routes: a file written whole, an edit's replacement text,
and a shell command carrying a heredoc, a commit message or a one-off script.
All three are read from the call before it runs, so the character never lands
and no later pass has to hunt it back out.

Only the text a call adds is read. An edit's `old_string`, a patch's removed
lines, and every search or read are where these characters legitimately appear:
removing one means naming it first.

An escape is ASCII describing the character rather than the character itself, so
`\\u2014`, `\\x{2014}` and `&mdash;` all pass. That is what keeps a script that
strips em dashes writable while the literal stays refused.

The interpunct is the softer case. It is a real separator in a breadcrumb, a
changelog line and a units string, so it asks rather than refuses: exit 2 puts
the call in front of the human instead of turning it down on their behalf.
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
        print("agent-guard: this call writes punctuation AGENTS.md rules out.\n")
        print("\n".join(refused))
        print(
            "\nAn em or en dash never survives review, whatever it is separating. "
            "End the sentence, or use a comma; a hyphen only where a hyphen is "
            "meant, and a plain range as `3 to 5`. To write the character on "
            "purpose, escape it: \\u2014 in Python, JSON or JS, \\x{2014} in an "
            "rg pattern, &mdash; in HTML."
        )
        return 1

    asked = report(text, ASKED)
    if asked:
        print("agent-guard: this call writes punctuation that needs a human's say-so.\n")
        print("\n".join(asked))
        print(
            "\nAn interpunct is fine only where the human has approved it, so this "
            "call is theirs to allow. A comma, a slash or a hyphen separates just "
            "as well and needs no approval; \\u00b7 writes the character without "
            "being it."
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
