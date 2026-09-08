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
    if focus["changed"] or focus.get("reason") != "no_neighbor":
        return

    action = {"left": "FocusLeft", "right": "FocusRight"}.get(direction)
    if action and os.environ.get("ALACRITREE_SOCKET"):
        executable = (
            os.environ.get("ALACRITREE_EXE")
            or shutil.which("alacritree")
            or shutil.which("alacritree.exe")
        )
        if executable:
            subprocess.run([executable, "action", action], check=True, timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Navigate Neovim splits before Herdr panes.")
    parser.add_argument("direction", choices=("left", "down", "up", "right"))
    parser.add_argument("--edge", action="store_true")
    args = parser.parse_args()
    navigate(args.direction, args.edge)
