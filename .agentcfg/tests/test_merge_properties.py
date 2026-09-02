"""Property tests for merge, over a fixed universe of path shapes.

Independently random dicts almost never share a key path with each other or
with the rule patterns, so the generators here draw baseline, live, and rule
patterns from the same small pool of paths (`POOL`) instead of generating
freely. That is what makes the properties exercise real strategy resolution
instead of passing vacuously on shapeless inputs.
"""

from __future__ import annotations

from collections.abc import Mapping

from hypothesis import given, event, settings, strategies as st

from engine.lint import leaves
from engine.merge import merge
from engine.rules import RuleSet, Strategy

MEMBERS = ["a", "b", "c"]

scalar = st.one_of(
    st.booleans(),
    st.integers(min_value=-3, max_value=3),
    st.text(alphabet="xyz", min_size=0, max_size=3),
)


def member_dict(value_strategy):
    return st.dictionaries(st.sampled_from(MEMBERS), value_strategy, max_size=3)


list_value = st.lists(st.sampled_from(["p", "q", "r"]), max_size=3, unique=True)

mcp_server_fields = st.fixed_dictionaries(
    # "enabled" is required (not optional) so the seed/enforce leaf that the
    # wildcard-table-descend hazard is about is reliably present to test.
    {"enabled": st.booleans()},
    optional={
        "url": st.text(alphabet="xyz", min_size=0, max_size=3),
        "timeout": st.integers(min_value=0, max_value=60),
    },
)

model_value = st.one_of(scalar, member_dict(scalar))

_ABSENT = object()


def biased_bool(true_out_of_5):
    """A boolean weighted true_out_of_5/5 true, instead of st.booleans' 50/50."""
    return st.sampled_from([True] * true_out_of_5 + [False] * (5 - true_out_of_5))


@st.composite
def mcp_servers_pair(draw):
    """baseline["mcp_servers"] and live["mcp_servers"], sharing member names.

    Independently random dicts almost never name the same server, so the
    ["mcp_servers", "*", "enabled"] seed rule would almost never see both a
    baseline and a live value to choose between. Sharing the member-name
    draw forces that overlap; each side's fields (including "enabled") are
    still drawn independently, so they agree or diverge realistically.
    """
    base_present = draw(st.booleans())
    live_present = draw(st.booleans())
    names = (
        draw(st.lists(st.sampled_from(MEMBERS), min_size=1, max_size=2, unique=True))
        if base_present or live_present
        else []
    )
    baseline_val, live_val = {}, {}
    for name in names:
        if base_present:
            baseline_val[name] = draw(mcp_server_fields)
        if live_present:
            live_val[name] = draw(mcp_server_fields)
    return (
        baseline_val if base_present else _ABSENT,
        live_val if live_present else _ABSENT,
    )


# Fixed pattern universe. Chosen so that no two patterns tie under
# rules._ties regardless of which strategies are assigned to them: they
# differ pairwise either in length, in literal-segment count, or in a
# literal segment at the same position. That lets rule_set() below build a
# RuleSet directly (bypassing RuleSet.load's file/tie validation, which the
# brief says callers may assume already holds) from any subset with any
# per-pattern strategy choice.
MODEL = ("model",)
ALLOW = ("permissions", "allow")
DENY = ("permissions", "deny")
ENV_STAR = ("env", "*")
MCP_STAR = ("mcp_servers", "*")
MCP_ENABLED = ("mcp_servers", "*", "enabled")
PROJECTS_STAR = ("projects", "*")
PLUGINS_STAR = ("enabledPlugins", "*")

SCALAR_STRATEGIES = [Strategy.ENFORCE, Strategy.SEED, Strategy.IGNORE]
LIST_STRATEGIES = [Strategy.ENFORCE, Strategy.SEED, Strategy.UNION, Strategy.IGNORE]

STRATEGY_CHOICES = {
    MODEL: SCALAR_STRATEGIES,
    ALLOW: LIST_STRATEGIES,
    DENY: LIST_STRATEGIES,
    ENV_STAR: SCALAR_STRATEGIES,
    # No IGNORE: this pattern's job in the pool is to exercise the
    # wildcard-table-descend hazard, which only arises for enforce/seed.
    MCP_STAR: [Strategy.ENFORCE, Strategy.SEED],
    MCP_ENABLED: SCALAR_STRATEGIES,
    PROJECTS_STAR: SCALAR_STRATEGIES,
    PLUGINS_STAR: SCALAR_STRATEGIES,
}

POOL = list(STRATEGY_CHOICES)

# Patterns central to the wildcard-table-descend hazard are included more
# often than a flat coin flip would, so the two rules land in the same
# generated rule set often enough to matter.
INCLUDE_WEIGHT = {MCP_STAR: 4, MCP_ENABLED: 4}


@st.composite
def rule_set(draw):
    patterns = []
    for pattern in POOL:
        if draw(biased_bool(INCLUDE_WEIGHT.get(pattern, 3))):
            strategy = draw(st.sampled_from(STRATEGY_CHOICES[pattern]))
            patterns.append((strategy, pattern))
    return RuleSet(patterns=tuple(patterns))


@st.composite
def config_without_mcp(draw):
    out = {}
    if draw(st.booleans()):
        out["model"] = draw(model_value)

    perms = {}
    if draw(st.booleans()):
        perms["allow"] = draw(list_value)
    if draw(st.booleans()):
        perms["deny"] = draw(list_value)
    if perms:
        out["permissions"] = perms

    if draw(st.booleans()):
        out["env"] = draw(member_dict(scalar))
    if draw(st.booleans()):
        out["projects"] = draw(member_dict(scalar))
    if draw(st.booleans()):
        out["enabledPlugins"] = draw(member_dict(st.booleans()))
    # "misc" matches no pattern in POOL: exercises the passthrough default.
    if draw(st.booleans()):
        out["misc"] = draw(member_dict(scalar))

    return out


@st.composite
def baseline_live_rules(draw):
    baseline, live = draw(config_without_mcp()), draw(config_without_mcp())
    mcp_baseline, mcp_live = draw(mcp_servers_pair())
    if mcp_baseline is not _ABSENT:
        baseline["mcp_servers"] = mcp_baseline
    if mcp_live is not _ABSENT:
        live["mcp_servers"] = mcp_live
    return baseline, live, draw(rule_set())


_MISSING = object()


def get_path(data, path):
    cur = data
    for segment in path:
        if not isinstance(cur, Mapping) or segment not in cur:
            return _MISSING
        cur = cur[segment]
    return cur


def reachable(baseline, live, path):
    """False when a type conflict on a strict ancestor of `path` shadows it.

    merge only descends into a shared key when both sides hold a mapping
    there; if live holds a scalar where baseline holds a table, that whole
    subtree is resolved as one leaf at the ancestor's own path, and no rule
    declared below the conflict ever runs. Dominance can only be asserted
    for a leaf the descent actually reaches.
    """
    cur_live = live
    for segment in path[:-1]:
        if not isinstance(cur_live, Mapping) or segment not in cur_live:
            return True  # absent from live here: _write_only reaches every leaf below correctly
        cur_live = cur_live[segment]
        if not isinstance(cur_live, Mapping):
            return False
    return True


@given(baseline_live_rules())
@settings(max_examples=500)
def test_merge_is_idempotent(data):
    """merge(baseline, merge(baseline, live, rules), rules) == merge(baseline, live, rules).

    This is what makes a second `chezmoi apply` a no-op.
    """
    baseline, live, rules = data
    once = merge(baseline, live, rules)
    twice = merge(baseline, once, rules)

    event("baseline changed something" if once != live else "no-op merge")
    assert once == twice


@given(baseline_live_rules())
@settings(max_examples=500)
def test_enforce_dominates_baseline(data):
    """Every baseline path that resolves to enforce holds its baseline value
    in the merged result, whatever live said."""
    baseline, live, rules = data
    merged = merge(baseline, live, rules)

    saw_enforce_leaf = False
    saw_hazard_leaf = False
    for path, value in leaves(baseline):
        if rules.resolve(path) is not Strategy.ENFORCE or not reachable(baseline, live, path):
            continue
        saw_enforce_leaf = True
        if len(path) == 3 and path[0] == "mcp_servers" and path[2] == "enabled":
            saw_hazard_leaf = True
        assert get_path(merged, path) == value

    event("enforce leaf present" if saw_enforce_leaf else "no enforce leaf")
    event(
        "mcp_servers.*.enabled enforced under a shallower table rule"
        if saw_hazard_leaf
        else "no mcp_servers.*.enabled hazard leaf"
    )
