import argparse
import json
import os
import subprocess

# `pane move --split` names only `right` and `down`, so landing a pane ahead of
# its partner moves the partner instead and lets it land behind.
SPLITS = {"up": "down", "down": "down", "left": "right", "right": "right"}

PERPENDICULAR = {
    "up": ("left", "right"),
    "down": ("left", "right"),
    "left": ("up", "down"),
    "right": ("up", "down"),
}


def herdr(*args):
    result = subprocess.run(
        [os.environ.get("HERDR_BIN_PATH", "herdr"), "pane", *args],
        check=True,
        capture_output=True,
        text=True,
        timeout=5,
    )
    return json.loads(result.stdout)["result"] if result.stdout.strip() else {}


def neighbor(pane, direction):
    found = herdr("neighbor", "--direction", direction, "--pane", pane)
    return found["neighbor"].get("neighbor_pane_id")


def plan(direction, pane, partner):
    if direction in ("down", "right"):
        return pane, partner, SPLITS[direction]
    return partner, pane, SPLITS[direction]


def restack(direction, pane, partner):
    mover, target, split = plan(direction, pane, partner)
    tab = herdr("get", mover)["pane"]["tab_id"]
    # `move --tab <its own tab>` answers SameTab before it reads --target-pane.
    # A throwaway tab is the way back in, and it closes itself behind the pane.
    if not herdr("move", mover, "--new-tab", "--no-focus")["move_result"]["changed"]:
        return
    focus = "--focus" if mover == pane else "--no-focus"
    herdr("move", mover, "--tab", tab, "--target-pane", target, "--split", split, focus)


def rearrange(direction, pane):
    if neighbor(pane, direction):
        herdr("swap", "--direction", direction, "--pane", pane)
        return
    for side in PERPENDICULAR[direction]:
        partner = neighbor(pane, side)
        if partner:
            restack(direction, pane, partner)
            return


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Swap the focused pane with its neighbour, or restack it against one."
    )
    parser.add_argument("direction", choices=("left", "down", "up", "right"))
    parser.add_argument("--pane", default=os.environ.get("HERDR_ACTIVE_PANE_ID"))
    args = parser.parse_args()
    rearrange(args.direction, args.pane)
