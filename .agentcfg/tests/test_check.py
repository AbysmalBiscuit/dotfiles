from engine.check import classify
from engine.rules import RuleSet


def rules_from(tmp_path, body):
    p = tmp_path / "rules.toml"
    p.write_text(body, encoding="utf-8")
    return RuleSet.load(p)


def test_unclassified_lists_live_leaves_with_no_rule(tmp_path):
    rules = rules_from(tmp_path, 'enforce = [["a"]]')
    report = classify(live={"a": 1, "b": 2}, baseline={"a": 1}, rules=rules)
    assert report.unclassified == [("b",)]


def test_live_only_lists_wildcard_members_absent_from_baseline(tmp_path):
    rules = rules_from(tmp_path, 'enforce = [["mcp_servers", "*"]]')
    report = classify(
        live={"mcp_servers": {"known": 1, "archi": 2}},
        baseline={"mcp_servers": {"known": 1}},
        rules=rules,
    )
    assert report.live_only == [("mcp_servers", "archi")]


def test_live_only_names_the_claimed_member_once(tmp_path):
    """A server with four live keys is one live-only entry, not four."""
    rules = rules_from(tmp_path, 'enforce = [["mcp_servers", "*"]]')
    report = classify(
        live={"mcp_servers": {"archi": {"url": "u", "enabled": True}}},
        baseline={},
        rules=rules,
    )
    assert report.live_only == [("mcp_servers", "archi")]


def test_live_only_covers_exact_patterns(tmp_path):
    """A classified key the baseline has never carried is still live-only."""
    rules = rules_from(tmp_path, 'seed = [["tui"]]')
    report = classify(live={"tui": "compact"}, baseline={}, rules=rules)
    assert report.live_only == [("tui",)]


def test_live_only_covers_seed_wildcards(tmp_path):
    """A plugin installed at runtime is live-only under a seed wildcard.

    Restricting live-only to enforce and union would hide
    enabledPlugins."mattpocock-skills@...", which is one of the two drifts
    the migration exists to resolve.
    """
    rules = rules_from(tmp_path, 'seed = [["enabledPlugins", "*"]]')
    report = classify(
        live={"enabledPlugins": {"known": True, "novel": True}},
        baseline={"enabledPlugins": {"known": True}},
        rules=rules,
    )
    assert report.live_only == [("enabledPlugins", "novel")]


def test_seed_drift_lists_exact_pattern_differences(tmp_path):
    rules = rules_from(tmp_path, 'seed = [["model"]]')
    report = classify(live={"model": "sonnet"}, baseline={"model": "opus"}, rules=rules)
    assert report.seed_drift == [("model",)]


def test_seed_drift_ignores_wildcard_patterns(tmp_path):
    """Runtime toggles live under seed wildcards and diverge on purpose.

    Four plugins sit false live against true in the baseline because Lev
    turned them off. Reporting that on every apply forever trains him to
    ignore the line.
    """
    rules = rules_from(tmp_path, 'seed = [["plugins", "*"]]')
    report = classify(
        live={"plugins": {"p": False}},
        baseline={"plugins": {"p": True}},
        rules=rules,
    )
    assert report.seed_drift == []
    assert report.live_only == []


def test_ignore_is_silent(tmp_path):
    rules = rules_from(tmp_path, 'ignore = [["projects", "*"]]')
    report = classify(live={"projects": {"x": 1}}, baseline={}, rules=rules)
    assert report.is_clean()


def test_clean_report_has_no_summary(tmp_path):
    rules = rules_from(tmp_path, 'enforce = [["a"]]')
    report = classify(live={"a": 1}, baseline={"a": 1}, rules=rules)
    assert report.is_clean()
    assert report.summary("settings.json") == ""
