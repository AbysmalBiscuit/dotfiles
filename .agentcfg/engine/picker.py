"""A keyboard picker for assigning a strategy to each drifted path.

Renders with ANSI escapes and reads single keys, so it runs on a bare Python
with nothing installed. The engine itself never imports this: chezmoi runs
the wrappers non-interactively and must never block on a terminal.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from collections.abc import Mapping

from engine.promote import DEFAULT_STRATEGY, Candidate
from engine.rules import Strategy

SKIP = None

_KEY_STRATEGY = {
    "s": Strategy.SEED,
    "e": Strategy.ENFORCE,
    "u": Strategy.UNION,
    "i": Strategy.IGNORE,
    "r": Strategy.REMOVE,
}

# A screened value may be left alone or deleted, never written to the repo.
_ALLOWED_WHEN_BLOCKED = (Strategy.IGNORE, Strategy.REMOVE)

_COLOUR = {
    Strategy.SEED: "\x1b[32m",
    Strategy.ENFORCE: "\x1b[35m",
    Strategy.UNION: "\x1b[36m",
    Strategy.IGNORE: "\x1b[33m",
    Strategy.REMOVE: "\x1b[31m",
}
_SEQUENCE = {
    b"[A": "up",
    b"[B": "down",
    b"[3~": "clear",
    b"OP": "help",
    b"[11~": "help",
    b"[[A": "help",
}

_DIM = "\x1b[2m"
_RED = "\x1b[31m"
_BOLD = "\x1b[1m"
_OFF = "\x1b[0m"


def _enable_ansi() -> None:
    if os.name != "nt":
        return
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32
        kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
    except Exception:
        pass


class _Reader:
    """Read one keypress, returning a name for the keys the picker binds."""

    def __enter__(self):
        if os.name == "nt":
            import msvcrt

            self._read = self._windows
            self._msvcrt = msvcrt
            return self
        import select
        import termios
        import tty

        self._fd = sys.stdin.fileno()
        self._saved = termios.tcgetattr(self._fd)
        tty.setraw(self._fd)
        self._select = select
        self._read = self._posix
        return self

    def __exit__(self, *exc):
        if os.name != "nt":
            import termios

            termios.tcsetattr(self._fd, termios.TCSADRAIN, self._saved)

    def _windows(self) -> str:
        ch = self._msvcrt.getch()
        if ch in (b"\x00", b"\xe0"):
            return {b"H": "up", b"P": "down", b"S": "clear", b";": "help"}.get(
                self._msvcrt.getch(), ""
            )
        return {b"\r": "enter", b"\x03": "quit", b"\x1b": "quit", b" ": "space",
                b"\x08": "clear"}.get(ch, ch.decode("latin-1", "ignore").lower())

    def _pending(self, count: int, timeout: float = 0.05) -> bytes:
        """Read up to count bytes that are already on their way.

        A lone Escape and the first byte of an arrow key are the same byte, so
        reading the rest unconditionally waits for keystrokes a lone Escape
        never sends. A terminal emits the whole sequence in one burst, so
        anything still absent after the timeout was never coming.
        """
        data = b""
        while len(data) < count and self._select.select([self._fd], [], [], timeout)[0]:
            chunk = os.read(self._fd, count - len(data))
            if not chunk:
                break
            data += chunk
        return data

    def _posix(self) -> str:
        ch = os.read(self._fd, 1)
        if ch == b"\x1b":
            rest = self._pending(2)
            # Terminals disagree about F1, and its three encodings run to
            # different lengths. Draining the tail keeps the leftover bytes
            # from arriving as separate keystrokes.
            if rest == b"[1":
                rest += self._pending(2)
            elif rest in (b"[[", b"[3"):
                rest += self._pending(1)
            return _SEQUENCE.get(rest, "quit")
        # Terminals disagree about backspace: DEL on most, ^H on a few.
        return {b"\r": "enter", b"\n": "enter", b"\x03": "quit", b" ": "space",
                b"\x7f": "clear", b"\x08": "clear"}.get(
            ch, ch.decode("latin-1", "ignore").lower()
        )

    def key(self) -> str:
        return self._read()


_HELP = (
    ("what each strategy does", (
        ("s  seed", "the repo fills this in only while the app has no value of its own"),
        ("e  enforce", "the repo owns it, and every apply overwrites what the app wrote"),
        ("u  union", "merge the two lists, the app's entries first; lists on both sides"),
        ("i  ignore", "the app owns it, never stored in the repo, never asked again"),
        ("r  remove", "delete it from the config on every apply, and keep it deleted"),
        ("   skip", "decide later; the path comes back as a candidate next run"),
    )),
    ("what a row means", (
        ("[ ]", "undecided, nothing is written for this path"),
        ("[e]", "decided; the mark is the first letter of the strategy"),
        ("[!]", "screened as a secret and still undecided; this repo is public"),
    )),
    ("keys", (
        ("space", "decide this row with its default strategy, or clear it"),
        ("backspace", "clear this row back to undecided; delete works too"),
        ("j k", "move down and up; the arrow keys work too"),
        ("a", "decide every row using its default strategy"),
        ("n", "clear every row back to undecided"),
        ("enter", "write the selected rows and leave"),
        ("q", "leave without writing anything"),
    )),
)


def _help_frame() -> str:
    width = max(len(key) for _, pairs in _HELP for key, _ in pairs)
    out = ["\x1b[H\x1b[J", f"{_BOLD}agentcfg{_OFF}", ""]
    for heading, pairs in _HELP:
        out.append(f"{_BOLD}{heading}{_OFF}")
        for key, text in pairs:
            out.append(f"  {key:<{width}}  {_DIM}{text}{_OFF}")
        out.append("")
    out.append(f"{_DIM}any key returns to the list{_OFF}")
    return "\r\n".join(out)


def preview(value: object, width: int) -> str:
    if isinstance(value, Mapping):
        text = "{" + ", ".join(sorted(value)[:3]) + ("..." if len(value) > 3 else "") + "}"
    elif isinstance(value, list):
        text = f"[{len(value)} items]"
    else:
        text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= width else text[: width - 1] + "\u2026"


def _render(title, rows, choices, cursor, top, height) -> str:
    columns = shutil.get_terminal_size((100, 30)).columns
    out = ["\x1b[H\x1b[J", f"{_BOLD}{title}{_OFF}", ""]
    for index in range(top, min(top + height, len(rows))):
        item = rows[index]
        chosen = choices[item.path]
        here = "\u276f" if index == cursor else " "
        # The mark carries the decision itself; screened rows stay red either
        # way so a secret never loses its warning once it is decided.
        if chosen is not SKIP:
            mark, tint = chosen.value[0], _RED if item.blocked else _COLOUR[chosen]
        elif item.blocked:
            mark, tint = "!", _RED
        else:
            mark, tint = " ", _DIM
        label = ".".join(item.path)
        tail = chosen.value if chosen else "skip"
        room = max(20, columns - len(label) - len(tail) - 12)
        out.append(f"{here} {tint}[{mark}] {label}  {preview(item.value, room)}  \u2192 {tail}{_OFF}")
    if len(rows) > height:
        out.append(f"{_DIM}  showing {top + 1}-{min(top + height, len(rows))} of {len(rows)}{_OFF}")
    blocked = sum(1 for item in rows if item.blocked)
    if blocked:
        out.append(f"{_RED}  {blocked} value(s) screened as secrets; they can only "
                   f"be ignored or removed{_OFF}")
    out.append("")
    out.append(f"{_DIM}space toggle  s/e/u/i/r strategy  bksp clear  a all  n none"
               f"  enter write  q quit{_OFF}  {_BOLD}? help{_OFF}")
    # Raw mode clears ONLCR, so a bare newline moves down without returning to
    # column 0 and every row lands further right than the one above it.
    return "\r\n".join(out)


def pick(candidates: list[Candidate], title: str) -> dict[tuple[str, ...], Strategy] | None:
    """Assign a strategy to each candidate. None means the user quit.

    Screened candidates accept ignore and nothing else, so a secret cannot
    reach the baseline through a keystroke.
    """
    if not candidates:
        return {}
    rows = sorted(candidates, key=lambda item: item.path)
    choices: dict[tuple[str, ...], Strategy | None] = {item.path: SKIP for item in rows}
    default = {item.path: Strategy.IGNORE if item.blocked else DEFAULT_STRATEGY[item.kind]
               for item in rows}
    cursor = top = 0
    _enable_ansi()
    try:
        # The frame draws box and arrow glyphs; a cp1252 stdout raises on them.
        # newline="" stops Windows turning the frame's \r\n into \r\r\n.
        sys.stdout.reconfigure(encoding="utf-8", newline="")
    except (AttributeError, OSError):
        pass
    height = max(5, shutil.get_terminal_size((100, 30)).lines - 8)

    showing_help = False

    with _Reader() as reader:
        while True:
            frame = _help_frame() if showing_help else _render(
                title, rows, choices, cursor, top, height
            )
            sys.stdout.write(frame)
            sys.stdout.flush()
            key = reader.key()

            if showing_help:
                showing_help = False
                continue

            item = rows[cursor]

            if key in ("?", "help"):
                showing_help = True
                continue
            if key in ("q", "quit"):
                sys.stdout.write("\x1b[H\x1b[J")
                return None
            if key == "enter":
                sys.stdout.write("\x1b[H\x1b[J")
                return {path: choice for path, choice in choices.items() if choice is not SKIP}
            if key in ("down", "j"):
                cursor = min(cursor + 1, len(rows) - 1)
            elif key in ("up", "k"):
                cursor = max(cursor - 1, 0)
            elif key == "space":
                choices[item.path] = SKIP if choices[item.path] else default[item.path]
            elif key == "clear":
                choices[item.path] = SKIP
            elif key in _KEY_STRATEGY:
                wanted = _KEY_STRATEGY[key]
                if not item.blocked or wanted in _ALLOWED_WHEN_BLOCKED:
                    choices[item.path] = wanted
            elif key == "a":
                for row in rows:
                    choices[row.path] = default[row.path]
            elif key == "n":
                for row in rows:
                    choices[row.path] = SKIP

            if cursor < top:
                top = cursor
            elif cursor >= top + height:
                top = cursor - height + 1
