"""The remove strategy: paths the repo declares gone from the live config."""

import pytest

from engine.check import classify
from engine.lint import LintError, lint
from engine.merge import merge
from engine.rules import RuleSet, Strategy

SEED_MEMBERS = 'seed = [["plugins", "*", "enabled"]]\n'
REMOVE_OLD = 'remove = [["plugins", "old"]]\n'


def rules_from(tmp_path, body):
    path = tmp_path / "rules.toml"
    path.write_text(body, encoding="utf-8")
    return RuleSet.load(path)


def test_remove_is_declarable(tmp_path):
    rules = rules_from(tmp_path, REMOVE_OLD)
    assert rules.resolve(("plugins", "old")) is Strategy.REMOVE


def test_remove_drops_a_live_value(tmp_path):
    rules = rules_from(tmp_path, REMOVE_OLD)
    live = {"plugins": {"old": {"enabled": True}, "keep": {"enabled": True}}}
    assert merge({}, live, rules) == {"plugins": {"keep": {"enabled": True}}}


def test_remove_outranks_a_deeper_rule_on_its_members(tmp_path):
    """The container is skipped before anything descends into it.

    ["plugins", "*", "enabled"] scores higher on plugins.old.enabled than the
    remove rule two segments above it, so resolving the leaf alone would keep
    the member and leave the deletion half done. plugins held nothing else, so
    the prune cascades and takes the emptied table with it.
    """
    rules = rules_from(tmp_path, SEED_MEMBERS + REMOVE_OLD)
    assert merge({}, {"plugins": {"old": {"enabled": True}}}, rules) == {}


def test_remove_prunes_the_container_it_empties(tmp_path):
    """Removing every member takes the table with it, not a bare header."""
    rules = rules_from(tmp_path, 'remove = [["plugins", "old", "enabled"]]\n')
    live = {"plugins": {"old": {"enabled": True}, "keep": {"enabled": True}}}
    assert merge({}, live, rules) == {"plugins": {"keep": {"enabled": True}}}


def test_enforced_empty_table_survives_the_prune(tmp_path):
    """An enforced empty baseline table means the table exists and is empty.

    Only remove may delete a container; the prune must not mistake one for
    the other.
    """
    rules = rules_from(tmp_path, 'enforce = [["*"]]\nignore = [["b", "*"]]\n')
    assert merge({"b": {}}, {"b": {"x": 1}}, rules) == {"b": {}}


def test_remove_refuses_to_write_a_baseline_key(tmp_path):
    """A removed path absent from live stays absent, seed rule or not."""
    rules = rules_from(tmp_path, SEED_MEMBERS + REMOVE_OLD)
    assert merge({"plugins": {"old": {"enabled": True}}}, {}, rules) == {}


def test_remove_survives_a_second_pass(tmp_path):
    """Merging the output again changes nothing, so apply settles in one run."""
    rules = rules_from(tmp_path, SEED_MEMBERS + REMOVE_OLD)
    live = {"plugins": {"old": {"enabled": True}, "keep": {"enabled": True}}}
    once = merge({}, live, rules)
    assert merge({}, once, rules) == once


def test_lint_rejects_a_baseline_value_under_a_remove_rule(tmp_path):
    """The repo cannot both curate a value and declare its path gone."""
    rules = rules_from(tmp_path, SEED_MEMBERS + REMOVE_OLD)
    with pytest.raises(LintError, match="declare this path removed"):
        lint({"plugins": {"old": {"enabled": True}}}, rules)


def test_check_stays_quiet_about_a_removed_path(tmp_path):
    """A path on its way out is not drift worth reporting."""
    rules = rules_from(tmp_path, SEED_MEMBERS + REMOVE_OLD)
    assert classify({"plugins": {"old": {"enabled": True}}}, {}, rules).is_clean()
