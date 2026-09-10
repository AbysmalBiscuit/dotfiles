#!/usr/bin/env python3
"""PreToolUse guard: characters the house style keeps out of written text.

The roster is banned_characters.txt beside this file, one character per line,
so adding one is pasting it. A character spelled in this source would refuse
every later edit to this source, hence the separate file. Only what a call adds
is read: a file written whole, an edit's replacement text, a shell command
carrying a heredoc. An edit's `old_string` and a patch's removed lines are
where these characters legitimately appear, since removing one names it first.
"""

import json
import pathlib
import sys
import unicodedata

ROSTER = pathlib.Path(__file__).with_name("banned_characters.txt")

DEFAULT_FIX = "Write the ASCII word or symbol it stands in for."

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


def load_roster(path=ROSTER):
    """Characters to refuse, characters to ask about, and the advice for each.

    A line is the character itself, then optional advice. `[ask]` opens the
    tier that reaches the human; `[refuse]` opens the tier that denies, and is
    where a file with no header starts. A missing roster bans nothing.
    """
    refused, asked, fixes, tier = [], [], {}, "refuse"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return (), (), {}
    for line in lines:
        entry = line.strip()
        if not entry or entry.startswith("#"):
            continue
        if entry.startswith("[") and entry.endswith("]"):
            tier = entry[1:-1].strip().lower()
            continue
        char, fix = entry[0], entry[1:].strip()
        (asked if tier == "ask" else refused).append(char)
        if fix:
            fixes[char] = fix
    return tuple(refused), tuple(asked), fixes


REFUSED, ASKED, FIXES = load_roster()


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


def report(text, roster, fixes):
    """The roster's characters present in `text`, and a line about each."""
    found = [char for char in roster if char in text]
    listing = "\n".join(
        FINDING.format(
            name=unicodedata.name(char, "unnamed character").lower(),
            code=ord(char),
            excerpt=excerpt(text, char),
            fix=fixes.get(char, DEFAULT_FIX),
        )
        for char in found
    )
    return found, listing


def escapes(found):
    return ", ".join("`\\u%04x`" % ord(char) for char in found)


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

    found, listing = report(text, REFUSED, FIXES)
    if found:
        print(REFUSE_MESSAGE.format(findings=listing, escapes=escapes(found)))
        return 1

    found, listing = report(text, ASKED, FIXES)
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
