import pytest
from engine.lint import LintError, leaves, lint
from engine.rules import RuleSet


def rules_from(tmp_path, body):
    p = tmp_path / "rules.toml"
    p.write_text(body, encoding="utf-8")
    return RuleSet.load(p)


def test_leaves_treats_lists_as_atomic():
    data = {"a": {"b": 1}, "c": [1, 2, 3], "d": "x"}
    assert sorted(leaves(data)) == [
        (("a", "b"), 1),
        (("c",), [1, 2, 3]),
        (("d",), "x"),
    ]


def test_leaves_yields_empty_containers_as_leaves():
    assert sorted(leaves({"a": {}, "b": []})) == [(("a",), {}), (("b",), [])]


def test_baseline_leaf_on_ignore_is_rejected(tmp_path):
    rules = rules_from(tmp_path, 'ignore = [["projects", "*"]]')
    with pytest.raises(LintError, match="projects.foo"):
        lint({"projects": {"foo": {"trust_level": "trusted"}}}, rules)


def test_baseline_leaf_on_passthrough_is_rejected(tmp_path):
    rules = rules_from(tmp_path, 'enforce = [["model"]]')
    with pytest.raises(LintError, match="theme"):
        lint({"model": "opus", "theme": "dark"}, rules)


def test_union_on_non_list_is_rejected(tmp_path):
    rules = rules_from(tmp_path, 'union = [["permissions", "allow"]]')
    with pytest.raises(LintError, match="union.*list"):
        lint({"permissions": {"allow": "not-a-list"}}, rules)


def test_clean_baseline_passes(tmp_path):
    rules = rules_from(
        tmp_path,
        'enforce = [["permissions", "deny"]]\n'
        'union = [["permissions", "allow"]]\n'
        'seed = [["model"]]\n',
    )
    lint({"permissions": {"deny": ["a"], "allow": ["b"]}, "model": "opus"}, rules)
