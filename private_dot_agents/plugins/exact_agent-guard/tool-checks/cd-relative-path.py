#!/usr/bin/env python3
"""agent-guard tool-check: a path read relative to a `cd` in the same command.

The permission analyzer resolves a command's file operands against the session's
working directory, not against a `cd` earlier in the same compound command. With
any Read() deny rule configured it cannot prove the unresolved path misses the
denied set, so `cd DIR && rg PAT relfile` stops and waits for a human every time.
The absolute form of the same read carries no such cost.

Fires only when the command after the `cd` is a file reader, so the `cd` exists
purely to shorten the path. A build or a test runner genuinely needs its working
directory and is left alone.
"""

import json
import os
import re
import shlex
import sys

# Readers whose operands name files. Their meaning survives moving the directory
# into the path, which is what makes the rewrite mechanical.
READERS = {"rg", "fd", "cat", "head", "tail", "wc", "ls", "stat", "du", "file", "nl", "sed", "awk"}
# Tools whose first operand is a pattern or a script rather than a path, so
# only the operands after it name files.
PATTERN_FIRST = {"rg", "fd", "sed", "awk"}
# An operand that names a file even when it isn't there to be stat'd: it holds
# a separator, starts a dotfile or a `./` prefix, or ends in an extension.
PATH_SHAPE = re.compile(r"[/\\]|^\.|\.[A-Za-z0-9_]{1,8}$")
# Options taking a separate operand, so the operand is not read as a path.
OPTS_WITH_VALUE = {
    "-e", "--regexp", "-g", "--glob", "-t", "--type", "-T", "--type-not",
    "-m", "--max-count", "-A", "--after-context", "-B", "--before-context",
    "-C", "--context", "-r", "--replace", "-f", "--file", "--pre",
    "--max-depth", "--iglob", "--sort", "--colors", "-d", "-E", "--exclude",
}
# fd hands everything after these to a child command, so the operands stop
# being paths and the shape is no longer mechanical.
EXEC_FLAGS = {"-x", "--exec", "-X", "--exec-batch"}
SPLIT = re.compile(r"\s*(?:\|\||&&|\||;)\s*")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z_0-9]*=")
# Words that leave the real command word still ahead.
KEYWORDS = {
    "do", "then", "else", "elif", "if", "while", "until", "done", "fi", "!",
    "sudo", "command", "env", "time", "timeout", "nice", "stdbuf", "nohup",
}


def leading_cd(command):
    """The directory a leading `cd` moves to, or None."""
    first = SPLIT.split(command, maxsplit=1)
    if len(first) < 2:
        return None
    try:
        tokens = shlex.split(first[0])
    except ValueError:
        return None
    if len(tokens) != 2 or tokens[0] != "cd":
        return None
    target = os.path.expanduser(tokens[1])
    return target if os.path.isabs(target) else None


def segment_operands(tokens, directory):
    """The relative paths one command would open, given the `cd` target."""
    name = tokens[0].rsplit("/", 1)[-1]
    if name not in READERS:
        return []

    operands, skip = [], False
    for token in tokens[1:]:
        if skip:
            skip = False
            continue
        if token in EXEC_FLAGS:
            return []
        if token in OPTS_WITH_VALUE:
            skip = True
            continue
        if token.startswith("-") and token != "-":
            continue
        operands.append(token)
    if name in PATTERN_FIRST and operands:
        operands = operands[1:]  # the first operand is the pattern

    # Existence is a hint, not a requirement. A command probing for a file that
    # is not there resolves no better than one reading a file that is, and on a
    # shell whose paths the checking process cannot stat, such as an MSYS
    # `/c/...` path under native Windows, nothing would ever resolve.
    return [
        operand for operand in operands
        if not os.path.isabs(operand)
        and (PATH_SHAPE.search(operand) or os.path.exists(os.path.join(directory, operand)))
    ]


def relative_operands(command, directory):
    """The first reader after the `cd` that opens a relative path, and its hits.

    Every command in the line is inspected, not just the one right after the
    `cd`: a `git` or a search buried later in a `&&` chain runs in the changed
    directory just the same.
    """
    for segment in SPLIT.split(command)[1:]:
        try:
            tokens = shlex.split(segment)
        except ValueError:
            continue
        # A loop or conditional body puts the real command a few words in, and
        # an env assignment does too.
        while tokens and (tokens[0] in KEYWORDS or ASSIGNMENT.match(tokens[0])):
            tokens = tokens[1:]
        if not tokens:
            continue
        if tokens[0].rsplit("/", 1)[-1] == "git":
            return "git", []
        hits = segment_operands(tokens, directory)
        if hits:
            return tokens[0].rsplit("/", 1)[-1], hits
    return "", []


def main():
    if (sys.argv[1] if len(sys.argv) > 1 else "") != "Bash":
        return 0
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 0
    command = str((payload.get("tool_input") or {}).get("command") or "")
    if not command.strip():
        return 0

    directory = leading_cd(command)
    if directory is None:
        return 0

    name, hits = relative_operands(command, directory)
    if name == "git":
        print(
            "agent-guard: git after a cd into another directory always stops for "
            "manual approval, because git runs that directory's hooks. Pass the "
            f"directory to git instead: `git -C {directory} ...`."
        )
        return 1
    if not hits:
        return 0

    example = os.path.join(directory, hits[0])
    print(
        f"agent-guard: `{hits[0]}` is relative to the `cd`, and the permission "
        "analyzer resolves paths against the session's working directory instead. "
        "With Read() deny rules configured it cannot clear an unresolved path, so "
        "this stops and waits for a human.\n\n"
        f"Drop the cd and write the path out: `{name} ... {example}`."
    )
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except BaseException:
        # A broken check degrades to silence rather than denying real work.
        sys.exit(0)
