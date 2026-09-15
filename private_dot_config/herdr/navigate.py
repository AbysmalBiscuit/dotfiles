import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path


def herdr(*args):
    result = subprocess.run(
        [os.environ.get("HERDR_BIN_PATH", "herdr"), "pane", *args],
        check=True,
        capture_output=True,
        text=True,
        timeout=5,
    )
    return json.loads(result.stdout)["result"] if result.stdout.strip() else {}


def alacritree(*args):
    executable = (
        os.environ.get("ALACRITREE_EXE")
        or shutil.which("alacritree")
        or shutil.which("alacritree.exe")
    )
    if not executable:
        return None
    done = subprocess.run(
        [executable, *args], capture_output=True, text=True, timeout=5, check=False
    )
    return done.stdout if done.returncode == 0 else None


def select(pane_id):
    # alacritree points herdr back at the row it has selected, so the row has
    # to move too. Attaching is the click: a pane holding a session activates it.
    listing = alacritree("multiplexer", "list", "--json")
    if not listing:
        return
    row = next(
        (
            pane["multiplexer"]
            for pane in json.loads(listing).get("panes", [])
            if pane.get("multiplexer", {}).get("pane_id") == pane_id
        ),
        None,
    )
    if row:
        alacritree("multiplexer", "attach", row["side"], row["terminal_id"])


def navigate(direction, edge=False):
    target = ["--current"] if edge else ["--pane", os.environ["HERDR_ACTIVE_PANE_ID"]]
    if not edge:
        info = herdr("process-info", *target)["process_info"]
        if any(
            Path(process["name"]).name in ("nvim", "nvim.exe")
            for process in info.get("foreground_processes", [])
        ):
            herdr("send-keys", info["pane_id"], f"ctrl+{direction}")
            return

    focus = herdr("focus", "--direction", direction, *target)["focus"]
    if focus["changed"]:
        if focus.get("focused_pane_id"):
            select(focus["focused_pane_id"])
        return
    if focus.get("reason") != "no_neighbor":
        return

    action = {"left": "FocusLeft", "right": "FocusRight"}.get(direction)
    if action and os.environ.get("ALACRITREE_SOCKET"):
        alacritree("action", action)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Navigate Neovim splits before Herdr panes.")
    parser.add_argument("direction", choices=("left", "down", "up", "right"))
    parser.add_argument("--edge", action="store_true")
    args = parser.parse_args()
    navigate(args.direction, args.edge)
