"""Property tests for rules using Hypothesis."""

from hypothesis import given, strategies as st, example, settings
from engine.rules import RuleSet, Strategy, score, _ties

# Small alphabet for generating realistic segment names
segment_alphabet = st.sampled_from(["a", "b", "c", "x", "y", "z"])

# Broader alphabet including wildcards for independent pattern generation
pattern_segment = st.sampled_from(["a", "b", "c", "x", "y", "z", "*"])


@st.composite
def path_and_matching_patterns(draw):
    """Generate a path and two patterns that both match it.

    Patterns are derived from the path by choosing per-position whether to use
    the literal segment or a wildcard. This ensures both patterns match and
    reaches interesting tie/non-tie cases.
    """
    # Generate path: 1-5 segments
    path_length = draw(st.integers(min_value=1, max_value=5))
    path = tuple(draw(st.lists(segment_alphabet, min_size=path_length, max_size=path_length)))

    # Pattern a: for each position up to path length, choose literal or wildcard
    a_length = draw(st.integers(min_value=1, max_value=len(path)))
    a = tuple(path[i] if draw(st.booleans()) else "*" for i in range(a_length))

    # Pattern b: for each position up to path length, choose literal or wildcard
    b_length = draw(st.integers(min_value=1, max_value=len(path)))
    b = tuple(path[i] if draw(st.booleans()) else "*" for i in range(b_length))

    return path, a, b


@st.composite
def two_independent_patterns(draw):
    """Generate two independent patterns of the same length.

    Patterns are generated freely and independently, so differing literals at
    the same position are common. This tests the position-wise compatibility
    check in _ties.
    """
    length = draw(st.integers(min_value=1, max_value=5))
    a = tuple(draw(pattern_segment) for _ in range(length))
    b = tuple(draw(pattern_segment) for _ in range(length))
    return a, b


def construct_witness_path(a, b):
    """Construct a path that both patterns match, using literals from patterns.

    At each position, if one pattern has a literal, use it. If both are wildcards,
    use any literal from the alphabet. This ensures both patterns match.
    """
    path = []
    for seg_a, seg_b in zip(a, b):
        if seg_a != "*":
            path.append(seg_a)
        elif seg_b != "*":
            path.append(seg_b)
        else:
            path.append("a")
    return tuple(path)


@given(path_and_matching_patterns())
@example((("a",), ("a",), ("*",)))
@example((("a",), ("*",), ("a",)))
@example((("a", "b", "c"), ("a", "b"), ("a", "*")))
@example((("a", "b"), ("a", "*"), ("*", "b")))
def test_ties_invariant(data):
    """Bidirectional: _ties(a, b) iff they score identically on matching paths.

    Tests both directions:
    - If _ties(a, b) is False, they must score differently on any path both match.
    - If _ties(a, b) is True, they must score identically on any path both match.
    """
    path, a, b = data

    # Both patterns are guaranteed to match path by construction
    score_a = score(list(a), path)
    score_b = score(list(b), path)

    assert score_a is not None and score_b is not None

    # Forward direction: if they don't tie, they must score differently
    if not _ties(a, b):
        assert score_a != score_b

    # Converse direction: if they do tie, they must score the same
    if _ties(a, b):
        assert score_a == score_b


@given(two_independent_patterns())
@settings(max_examples=500)
def test_ties_position_compatibility(data):
    """When _ties(a, b) is True, both patterns score equally on some witness path.

    This tests the position-wise compatibility check, which is unreachable in the
    path-derived generator. It verifies that _ties correctly identifies patterns
    that CAN coexist with identical scores.
    """
    a, b = data

    if _ties(a, b):
        witness = construct_witness_path(a, b)
        score_a = score(list(a), witness)
        score_b = score(list(b), witness)

        assert score_a is not None, f"Pattern {a} did not match witness {witness}"
        assert score_b is not None, f"Pattern {b} did not match witness {witness}"
        assert score_a == score_b, (
            f"Patterns {a} and {b} claim to tie but scored {score_a} vs {score_b} "
            f"on witness {witness}"
        )


@given(path_and_matching_patterns())
def test_patterns_for_returns_ordered_results(data):
    """patterns_for returns matches in non-increasing score order.

    Build a minimal rule set from two patterns and verify they're ordered
    correctly by the score tuple.
    """
    path, a, b = data

    # Build a rule set with both patterns
    rs = RuleSet(patterns=((Strategy.ENFORCE, a), (Strategy.SEED, b)))

    matches = rs.patterns_for(path)

    # Verify non-increasing score order
    for i in range(len(matches) - 1):
        score_i = matches[i][0]
        score_next = matches[i + 1][0]
        assert score_i >= score_next, f"Score {score_i} is not >= {score_next}"
