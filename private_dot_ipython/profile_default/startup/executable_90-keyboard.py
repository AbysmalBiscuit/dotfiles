#!/usr/bin/env python3
"""
Created on 2021-01-17 13:32

@author: Lev Velykoivanenko (velykoivanenko.lev@gmail.com)
"""

from IPython import get_ipython
from prompt_toolkit.enums import DEFAULT_BUFFER
from prompt_toolkit.keys import Keys
from prompt_toolkit.filters import HasFocus, HasSelection
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from IPython import InteractiveShell

ip: InteractiveShell | None = get_ipython()


def unindent(event):
    def _unindent(line):
        # Get length of leading whitespace
        len_indent: int = len(line) - len(line.lstrip(" "))
        # If there are no indents then there is nothing to do
        if len_indent > 0:
            # Default dedent is 4, so if there is no remainder, then dedent by 4
            dedent: int = len_indent % 4 or 4
            return line[dedent:]
        return line

    buf = event.current_buffer
    buf.transform_current_line(_unindent)


def control_space_complete(event):
    "Initialize autocompletion, or select the next completion."
    buff = event.app.current_buffer
    if buff.complete_state:
        buff.complete_next()
    else:
        buff.start_completion(select_first=False)


# def delete_before_cursor(event):
#     buff = event.app.current_buffer
#     buff.delete_before_cursor()


# Cursor movement functions
# def move_cursor_right(event):
#     buff = event.app.current_buffer
#     buff.cursor_right()


# def move_cursor_left(event):
#     buff = event.app.current_buffer
#     buff.cursor_left()


# def move_cursor_up(event):
#     buff = event.app.current_buffer
#     buff.cursor_up()


# def move_cursor_down(event):
#     buff = event.app.current_buffer
#     buff.cursor_down()


# Register the shortcut if IPython is using prompt_toolkit
if getattr(ip, "pt_app", None):
    registry = ip.pt_app.key_bindings
    # registry.add_binding(Keys.ControlSpace,
    #                      filter=(HasFocus(DEFAULT_BUFFER)))(control_space_complete)

    # Add binding for un-indenting with Shift+Tab
    registry.add_binding(Keys.BackTab, filter=(HasFocus(DEFAULT_BUFFER)))(unindent)

    # Add Backspace as removing a character
    # registry.add_binding(Keys.Backspace,
    #                      filter=(HasFocus(DEFAULT_BUFFER)))(delete_before_cursor)

    # Add binding for moving the cursor using Ctrl+{h,n,l,k}
    # registry.add_binding(Keys.ControlH,
    #                      filter=(HasFocus(DEFAULT_BUFFER)))(move_cursor_left)
    # registry.add_binding(Keys.ControlN,
    #                      filter=(HasFocus(DEFAULT_BUFFER)))(move_cursor_right)
    # registry.add_binding(Keys.ControlL,
    #                      filter=(HasFocus(DEFAULT_BUFFER)))(move_cursor_up)
    # registry.add_binding(Keys.ControlK,
    #                      filter=(HasFocus(DEFAULT_BUFFER)))(move_cursor_down)
