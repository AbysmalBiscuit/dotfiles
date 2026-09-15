import importlib.util
from pathlib import Path

import pytest


class Herdr:
    """A pane layout that answers the calls restack makes of the real CLI."""

    def __init__(self, neighbors, tab="t1", moves=True):
        self.neighbors = neighbors
        self.tab = tab
        self.allows_moves = moves
        self.calls = []

    def __call__(self, *args):
        self.calls.append(args)
        if args[0] == "neighbor":
            found = self.neighbors.get(args[4], {}).get(args[2])
            return {"neighbor": {"neighbor_pane_id": found} if found else {}}
        if args[0] == "get":
            return {"pane": {"tab_id": self.tab}}
        if args[0] == "move":
            return {"move_result": {"changed": self.allows_moves}}
        return {}

    def moves(self):
        return [call for call in self.calls if call[0] == "move"]


@pytest.fixture
def restack():
    spec = importlib.util.spec_from_file_location("restack", Path(__file__).with_name("restack.py"))
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def side_by_side(**kwargs):
    return Herdr({"left": {"right": "right"}, "right": {"left": "left"}}, **kwargs)


def test_swaps_when_the_direction_has_a_neighbour(restack, monkeypatch):
    herdr = side_by_side()
    monkeypatch.setattr(restack, "herdr", herdr)

    restack.rearrange("left", "right")

    assert ("swap", "--direction", "left", "--pane", "right") in herdr.calls
    assert herdr.moves() == []


def test_down_lands_the_focused_pane_under_its_neighbour(restack, monkeypatch):
    herdr = side_by_side()
    monkeypatch.setattr(restack, "herdr", herdr)

    restack.rearrange("down", "right")

    assert herdr.moves() == [
        ("move", "right", "--new-tab", "--no-focus"),
        ("move", "right", "--tab", "t1", "--target-pane", "left", "--split", "down", "--focus"),
    ]


def test_up_moves_the_neighbour_because_a_split_only_lands_below(restack, monkeypatch):
    herdr = side_by_side()
    monkeypatch.setattr(restack, "herdr", herdr)

    restack.rearrange("up", "right")

    assert herdr.moves() == [
        ("move", "left", "--new-tab", "--no-focus"),
        ("move", "left", "--tab", "t1", "--target-pane", "right", "--split", "down", "--no-focus"),
    ]


def test_left_restacks_a_stacked_pair_side_by_side(restack, monkeypatch):
    herdr = Herdr({"top": {"down": "bottom"}, "bottom": {"up": "top"}})
    monkeypatch.setattr(restack, "herdr", herdr)

    restack.rearrange("left", "bottom")

    assert herdr.moves() == [
        ("move", "top", "--new-tab", "--no-focus"),
        ("move", "top", "--tab", "t1", "--target-pane", "bottom", "--split", "right", "--no-focus"),
    ]


def test_a_lone_pane_is_left_alone(restack, monkeypatch):
    herdr = Herdr({})
    monkeypatch.setattr(restack, "herdr", herdr)

    restack.rearrange("up", "only")

    assert herdr.moves() == []


def test_a_refused_first_move_is_not_followed_by_a_second(restack, monkeypatch):
    herdr = side_by_side(moves=False)
    monkeypatch.setattr(restack, "herdr", herdr)

    restack.rearrange("down", "right")

    assert herdr.moves() == [("move", "right", "--new-tab", "--no-focus")]
