#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on 2021-01-23 10:51

@author: Lev Velykoivanenko (velykoivanenko.lev@gmail.com)
"""
import subprocess
import inspect
import time
import shlex
from pprint import pformat
from copy import deepcopy
from functools import partial

import sys
from typing import Any, Dict, List, Optional

from kitty.cli import CONFIG_HELP, parse_args
from kitty.cli_stub import RCOptions, ResizeCLIOptions, DiffCLIOptions

from kitty.constants import version, appname
# from kitty.key_encoding import CTRL, EventType, KeyEvent
from kitty.rc.base import command_for_name, parse_subcommand_cli
from kitty.remote_control import encode_send, parse_rc_args
from kitty.shell import main as smain
from kitty.utils import ScreenSize

from kittens.tui.handler import Handler
from kittens.tui.loop import Loop
from kittens.tui.operations import styled
from kittens.tui.loop import debug
from kittens.diff.config import init_config

global_opts = RCOptions()


def get_members(o):
    return [i for i in inspect.getmembers(o) if i[0] != "__globals__"]


class Resize(Handler):

    print_on_fail: Optional[str] = None

    def __init__(self, args, opts = None):
        self.args = args
        self.opts = opts
        self.buffer = list()
        self.buffer_history = list()
        self.buffer_bak = list()
        self.buffer_hist_index: int = 0

    def initialize(self) -> None:
        global global_opts
        global_opts = parse_rc_args(['kitty', '@resize-window'])[0]
        self.original_size = self.screen_size
        # self.cmd.set_cursor_visible(False)
        self.cmd.set_line_wrapping(True)
        self.draw_screen()
    
    def show_obj(self, o_name):
        # shlex.quote
        print = self.print
        try:
            members = get_members(eval(o_name))
            print("[")
            for m in members:
                print(m)
            print("]")
            # self.print(pformat(, indent=2, width=80))
            # self.print(get_members(exec(o_name)))
        except NameError as e:
            self.print(e)

    def on_text(self, text: str, in_bracketed_paste: bool = False) -> None:
        self.print(text, end="")
        self.buffer.append(text)

    def on_key(self, key_event):
        key = key_event[2]
        if key == "ENTER":
            text = "".join(self.buffer)
            if text.strip() == "":
                return
            self.buffer_history.append(self.buffer)
            self.buffer_hist_index = -1
            self.buffer = list()
            if text in ["q", "quit", "exit"]:
                self.quit_loop(0)
            else:
                self.cmd.clear_screen()
                self.print("Showing members for:", text)
                self.show_obj(text)
                self.redraw_buffer(clear=False)
        elif key == "BACKSPACE":
            if len(self.buffer) > 0:
                self.buffer.pop()
            self.redraw_buffer()
        elif key == "UP":
            if len(self.buffer_bak) == 0:
                self.buffer_bak = deepcopy(self.buffer)
            self.buffer_hist_index -= 1
            if -len(self.buffer_history) > self.buffer_hist_index:
                self.buffer_hist_index = -len(self.buffer_history)
                self.cmd.bell()
                return
            self.buffer = deepcopy(self.buffer_history[self.buffer_hist_index])
            self.redraw_buffer()
        elif key == "DOWN":
            self.buffer_hist_index += 1
            if self.buffer_hist_index == 0:
                self.buffer = deepcopy(self.buffer_bak)
                self.buffer_bak = list()
                self.buffer_hist_index = -1
            else:
                self.buffer = deepcopy(self.buffer_history[self.buffer_hist_index])
            self.redraw_buffer()

    def redraw_buffer(self, clear: bool = True):
        if clear:
            self.cmd.clear_screen()
        self.print("\rEnter object to inspect: " +
                   "".join(self.buffer), end="")

    def draw_screen(self):
        self.cmd.clear_screen()
        # attr = input("Enter object to inspect: ")
        print = self.print
        print("\rEnter object to inspect: ", end="")


def play_video(path):
    return subprocess.run(["mpv", "--vo=tct", "--really-quiet", path])


OPTIONS = partial('''\
--config
type=list
{config_help}


--override -o
type=list
Override individual configuration options, can be specified multiple times.
Syntax: :italic:`name=value`. For example: :italic:`-o background=gray`

'''.format, config_help = CONFIG_HELP.format(conf_name='vcat', appname=appname))


def main(args: List[str]) -> None:
    cli_opts, items = parse_args(
        ["--override", "font_size=1.0"], OPTIONS, '', '', 'vcat', result_class=DiffCLIOptions)
    opts = init_config(cli_opts)
    print(cli_opts)
    print(items)
    # play_video(args[1])
    # try:
    #     play_video(args[1])
    # except (KeyboardInterrupt, SystemExit):
    #     return

    opts = init_config(cli_opts)
    loop = Loop()
    handler = Resize(cli_opts, opts)
    try:
        loop.loop(handler)
    except KeyboardInterrupt:
        return
    if handler.print_on_fail:
        print(handler.print_on_fail, file=sys.stderr)
        input('Press Enter to quit')
    raise SystemExit(loop.return_code)
