import copy
import pytest
from engine.merge import merge
from engine.rules import RuleSet


def rules_from(tmp_path, body):
    p = tmp_path / "rules.toml"
    p.write_text(body, encoding="utf-8")
    return RuleSet.load(p)


def test_enforce_overwrites_live(tmp_path):
    rules = rules_from(tmp_path, 'enforce = [["permissions", "deny"]]')
    out = merge({"permissions": {"deny": ["a"]}}, {"permissions": {"deny": ["b"]}}, rules)
    assert out == {"permissions": {"deny": ["a"]}}


def test_enforce_at_member_granularity_keeps_live_only_siblings(tmp_path):
    rules = rules_from(tmp_path, 'enforce = [["env", "*"]]')
    out = merge({"env": {"A": "1"}}, {"env": {"A": "9", "B": "2"}}, rules)
    assert out == {"env": {"A": "1", "B": "2"}}


def test_seed_writes_when_absent(tmp_path):
    rules = rules_from(tmp_path, 'seed = [["model"]]')
    assert merge({"model": "opus"}, {}, rules) == {"model": "opus"}


def test_seed_respects_explicit_false(tmp_path):
    """A plugin disabled at runtime stays disabled. This is the semantic
    sprig merge got wrong: mergo treats false as empty and refills it."""
    rules = rules_from(tmp_path, 'seed = [["enabledPlugins", "*"]]')
    out = merge({"enabledPlugins": {"p": True}}, {"enabledPlugins": {"p": False}}, rules)
    assert out == {"enabledPlugins": {"p": False}}


def test_seed_respects_zero_and_empty_string(tmp_path):
    rules = rules_from(tmp_path, 'seed = [["a"], ["b"]]')
    assert merge({"a": 5, "b": "x"}, {"a": 0, "b": ""}, rules) == {"a": 0, "b": ""}


def test_seed_container_writes_members_live_lacks(tmp_path):
    """seed is per path, so a live table missing a curated member gains it.

    Returning the live table whole would drop voice.mode while the lint
    still reported it classified, which is the silent discard the whole
    design exists to prevent.
    """
    rules = rules_from(tmp_path, 'seed = [["voice"]]')
    out = merge(
        baseline={"voice": {"enabled": True, "mode": "hold"}},
        live={"voice": {"enabled": False}},
        rules=rules,
    )
    assert out == {"voice": {"enabled": False, "mode": "hold"}}


def test_union_appends_missing_only(tmp_path):
    rules = rules_from(tmp_path, 'union = [["permissions", "allow"]]')
    out = merge(
        {"permissions": {"allow": ["a", "b"]}},
        {"permissions": {"allow": ["b", "c"]}},
        rules,
    )
    assert out == {"permissions": {"allow": ["b", "c", "a"]}}


def test_ignore_and_passthrough_keep_live_and_drop_baseline(tmp_path):
    rules = rules_from(tmp_path, 'ignore = [["projects", "*"]]')
    out = merge({"projects": {"x": 1}, "other": 2}, {"projects": {"y": 3}}, rules)
    assert out == {"projects": {"y": 3}}


def test_key_order_is_live_then_baseline_only(tmp_path):
    rules = rules_from(tmp_path, 'enforce = [["a"], ["b"], ["c"], ["d"]]')
    out = merge({"d": 4, "a": 1}, {"c": 3, "b": 2}, rules)
    assert list(out) == ["c", "b", "d", "a"]


def test_inputs_are_not_mutated(tmp_path):
    rules = rules_from(tmp_path, 'enforce = [["env", "*"]]')
    baseline = {"env": {"A": "1"}}
    live = {"env": {"B": "2"}}
    before = copy.deepcopy(baseline), copy.deepcopy(live)
    merge(baseline, live, rules)
    assert (baseline, live) == before


def test_type_conflict_enforce_replaces_subtree(tmp_path):
    rules = rules_from(tmp_path, 'enforce = [["a"]]')
    assert merge({"a": "scalar"}, {"a": {"nested": 1}}, rules) == {"a": "scalar"}


def test_type_conflict_seed_keeps_live(tmp_path):
    rules = rules_from(tmp_path, 'seed = [["a"]]')
    assert merge({"a": "scalar"}, {"a": {"nested": 1}}, rules) == {"a": {"nested": 1}}


def test_union_on_non_list_live_raises(tmp_path):
    rules = rules_from(tmp_path, 'union = [["a"]]')
    with pytest.raises(TypeError, match="union"):
        merge({"a": [1]}, {"a": "scalar"}, rules)


def test_enforce_wildcard_table_descends_for_deeper_rule(tmp_path):
    """A rule below the claim depth forces a descent.

    Without this the enforce pattern deep-copies the baseline table, the
    seed rule on .enabled never runs, and a server the user disabled at
    runtime is silently re-enabled.
    """
    rules = rules_from(
        tmp_path,
        'enforce = [["mcp_servers", "*"]]\nseed = [["mcp_servers", "*", "enabled"]]\n',
    )
    out = merge(
        baseline={"mcp_servers": {"s": {"url": "a"}}},
        live={"mcp_servers": {"s": {"url": "b", "enabled": False, "timeout": 30}}},
        rules=rules,
    )
    assert out == {"mcp_servers": {"s": {"url": "a", "enabled": False, "timeout": 30}}}


def test_empty_baseline_container_is_a_leaf(tmp_path):
    """An empty mapping is a leaf, the same as it is to lint.leaves.

    Treating it as a container instead would descend past the enforce rule
    that claims it, and the ignore rule below would hand back the live
    members the baseline says to clear.
    """
    rules = rules_from(
        tmp_path, 'enforce = [["*"]]\n' 'ignore = [["b", "*"]]\n'
    )
    assert merge({"b": {}}, {"b": {"x": 1}}, rules) == {"b": {}}


def test_idempotent(tmp_path):
    rules = rules_from(
        tmp_path,
        'enforce = [["env", "*"]]\nseed = [["model"]]\nunion = [["allow"]]\n',
    )
    baseline = {"env": {"A": "1"}, "model": "opus", "allow": ["x"]}
    live = {"env": {"B": "2"}, "allow": ["y"]}
    once = merge(baseline, live, rules)
    twice = merge(baseline, once, rules)
    assert once == twice
    assert list(once) == list(twice)
