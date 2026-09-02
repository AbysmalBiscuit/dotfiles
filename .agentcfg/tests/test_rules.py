import pytest
from engine.rules import RuleSet, Strategy, score


def write_rules(tmp_path, body):
    p = tmp_path / "rules.toml"
    p.write_text(body, encoding="utf-8")
    return p


def test_exact_pattern_resolves(tmp_path):
    rs = RuleSet.load(write_rules(tmp_path, 'enforce = [["permissions", "deny"]]'))
    assert rs.resolve(("permissions", "deny")) == Strategy.ENFORCE


def test_unmatched_path_is_passthrough(tmp_path):
    rs = RuleSet.load(write_rules(tmp_path, 'enforce = [["permissions", "deny"]]'))
    assert rs.resolve(("model",)) == Strategy.PASSTHROUGH


def test_wildcard_matches_one_segment(tmp_path):
    rs = RuleSet.load(write_rules(tmp_path, 'enforce = [["env", "*"]]'))
    assert rs.resolve(("env", "PATH")) == Strategy.ENFORCE
    assert rs.resolve(("env",)) == Strategy.PASSTHROUGH


def test_deeper_pattern_beats_shallower(tmp_path):
    """mcp_servers.* and mcp_servers.*.enabled tie on literal count.

    Segments consumed is the primary key, so the deeper pattern wins and
    mcp_servers.foo.enabled resolves to seed, not enforce.
    """
    rs = RuleSet.load(
        write_rules(
            tmp_path,
            'enforce = [["mcp_servers", "*"]]\nseed = [["mcp_servers", "*", "enabled"]]\n',
        )
    )
    assert rs.resolve(("mcp_servers", "foo", "enabled")) == Strategy.SEED
    assert rs.resolve(("mcp_servers", "foo", "url")) == Strategy.ENFORCE


def test_literal_beats_wildcard_at_equal_depth(tmp_path):
    rs = RuleSet.load(
        write_rules(tmp_path, 'enforce = [["env", "*"]]\nignore = [["env", "TEMP"]]\n')
    )
    assert rs.resolve(("env", "TEMP")) == Strategy.IGNORE
    assert rs.resolve(("env", "OTHER")) == Strategy.ENFORCE


def test_segment_with_dots_and_backslashes_is_one_segment(tmp_path):
    rs = RuleSet.load(write_rules(tmp_path, 'ignore = [["hooks", "state", "*"]]'))
    key = "devkit@devkit:hooks/hooks-codex.json:session_start:0:0"
    assert rs.resolve(("hooks", "state", key)) == Strategy.IGNORE
    assert rs.resolve(("hooks", "state", r"C:\Users\Lev\.codex")) == Strategy.IGNORE


def test_patterns_that_tie_on_different_strategies_are_rejected(tmp_path):
    with pytest.raises(ValueError, match="score equally"):
        RuleSet.load(
            write_rules(tmp_path, 'enforce = [["a", "*"]]\nseed = [["*", "b"]]\n')
        )


def test_patterns_that_tie_on_the_same_strategy_are_fine(tmp_path):
    rs = RuleSet.load(write_rules(tmp_path, 'enforce = [["a", "*"], ["*", "b"]]\n'))
    assert rs.resolve(("a", "b")) == Strategy.ENFORCE


def test_unknown_strategy_key_raises(tmp_path):
    with pytest.raises(ValueError, match="unknown strategy"):
        RuleSet.load(write_rules(tmp_path, 'enfroce = [["model"]]'))


@pytest.mark.parametrize(
    "pattern,path,expected",
    [
        (["a", "b"], ("a", "b"), (2, 2)),
        (["a", "*"], ("a", "b"), (2, 1)),
        (["a"], ("a", "b"), (1, 1)),
        (["a", "b"], ("a",), None),
        (["a", "c"], ("a", "b"), None),
    ],
)
def test_score(pattern, path, expected):
    assert score(pattern, path) == expected


def test_pattern_must_be_a_list(tmp_path):
    """Pattern as a bare string (missing inner brackets) is caught at load."""
    with pytest.raises(ValueError, match="must be a list of strings"):
        RuleSet.load(write_rules(tmp_path, 'enforce = ["model"]'))


def test_pattern_segments_must_be_strings(tmp_path):
    """Pattern segments must be strings, not numbers or other types."""
    with pytest.raises(ValueError, match="non-string segment"):
        RuleSet.load(write_rules(tmp_path, 'enforce = [[1, 2]]'))


def test_patterns_for_returns_all_matches_ordered_by_score(tmp_path):
    """patterns_for() returns all matching patterns with scores, best first."""
    rs = RuleSet.load(
        write_rules(
            tmp_path,
            'enforce = [["a", "*"]]\nseed = [["a", "b", "c"]]\nignore = [["a", "b"]]\n',
        )
    )
    matches = rs.patterns_for(("a", "b", "c"))
    assert matches == [
        ((3, 3), Strategy.SEED, ("a", "b", "c")),
        ((2, 2), Strategy.IGNORE, ("a", "b")),
        ((2, 1), Strategy.ENFORCE, ("a", "*")),
    ]
