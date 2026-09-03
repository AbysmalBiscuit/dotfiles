import json
import shutil
from pathlib import Path

import pytest

import promote as entry
from engine.check import CheckReport, classify
from engine.codecs import JsonCodec
from engine.promote import LIVE_ONLY, UNCLASSIFIED, candidates, screen
from engine.rules import RuleSet, Strategy
from engine.writers import append_rules, write_json_baseline, write_toml_baseline

REPO = Path(__file__).resolve().parents[2]


def rules_from(tmp_path, body):
    path = tmp_path / "rules.toml"
    path.write_text(body, encoding="utf-8")
    return RuleSet.load(path)


@pytest.mark.parametrize(
    "path,value",
    [
        (("env", "GITHUB_TOKEN"), "x"),
        (("mcp_servers", "s", "bearer_token"), "x"),
        (("a",), "sk-ant-9fQ2xZk4Lm8vTr1bNw7yHgPjUe3dQ"),
    ],
)
def test_screen_refuses_credentials(path, value):
    assert screen(path, value) is not None


@pytest.mark.parametrize(
    "path,value",
    [
        (("env", "TEMP"), "C:/Users/Lev/AppData/Temp"),
        (("$schema",), "https://json.schemastore.org/claude-code-settings.json"),
        (("attribution", "commit"), "Co-Authored-By: Claude Opus 5"),
        (("enabledPlugins", "devkit@devkit"), True),
    ],
)
def test_screen_allows_ordinary_values(path, value):
    """Entropy alone flags too much. A path, a URL, and prose all clear the
    length floor, so structure has to veto before entropy is consulted."""
    assert screen(path, value) is None


def test_candidates_separate_unclassified_from_live_only(tmp_path):
    """The two kinds want different writes: a live-only path already matches a
    rule and needs only its value, an unclassified path needs both."""
    rules = rules_from(tmp_path, 'seed = [["enabledPlugins", "*"]]')
    live = {"enabledPlugins": {"new@mkt": True}, "strayKey": 1}
    found = {item.path: item for item in candidates(live, classify(live, {}, rules))}
    assert found[("enabledPlugins", "new@mkt")].kind == LIVE_ONLY
    assert found[("strayKey",)].kind == UNCLASSIFIED


def test_json_write_touches_only_the_added_key(tmp_path):
    """The sort guard ignores objects inside arrays, because element order
    there is data. Sorting them anyway would bury the change in churn."""
    source = REPO / "private_dot_claude" / ".settings.baseline.json"
    target = tmp_path / "baseline.json"
    shutil.copy(source, target)

    write_json_baseline(target, [])
    assert target.read_bytes() == source.read_bytes()

    write_json_baseline(target, [(("enabledPlugins", "zzz@mkt"), True)])
    before = source.read_text(encoding="utf-8").splitlines()
    after = target.read_text(encoding="utf-8").splitlines()
    assert len(after) == len(before) + 1
    assert json.loads(target.read_text(encoding="utf-8"))["enabledPlugins"]["zzz@mkt"] is True


def test_toml_scalar_lands_above_the_first_table(tmp_path):
    """A bare assignment written below a [section] header reparses as a member
    of that section: valid TOML, silently the wrong config."""
    target = tmp_path / "baseline.toml"
    target.write_text('model = "a"\n\n[tui]\nvim = true\n', encoding="utf-8")
    write_toml_baseline(target, [(("approvals",), "never")])
    import tomllib

    assert tomllib.loads(target.read_text(encoding="utf-8")) == {
        "model": "a",
        "approvals": "never",
        "tui": {"vim": True},
    }


def test_rules_append_keeps_comments_and_grouping(tmp_path):
    """tomlkit would reflow these files. They are hand-grouped with several
    patterns to a line and carry comments explaining single entries."""
    target = tmp_path / "rules.toml"
    target.write_text(
        "# header comment\nseed = [\n"
        '  ["model"], ["theme"],\n'
        "  # why this one is here\n"
        '  ["editorMode"],\n]\n',
        encoding="utf-8",
    )
    append_rules(target, [(Strategy.SEED, ("newKey",))])
    text = target.read_text(encoding="utf-8")
    assert "# header comment" in text
    assert "# why this one is here" in text
    assert '["model"], ["theme"],' in text
    assert RuleSet.load(target).resolve(("newKey",)) is Strategy.SEED


def test_rules_append_creates_a_missing_block(tmp_path):
    target = tmp_path / "rules.toml"
    target.write_text('seed = [\n  ["model"],\n]\n', encoding="utf-8")
    append_rules(target, [(Strategy.IGNORE, ("noisy",))])
    assert RuleSet.load(target).resolve(("noisy",)) is Strategy.IGNORE


def test_apply_rolls_back_when_the_result_will_not_load(tmp_path):
    """A choice can produce a rule set that no longer loads, and a half-written
    pair of files is worse than no write. Both are restored byte for byte."""
    import promote

    source = tmp_path / "private_dot_claude"
    source.mkdir()
    baseline = source / ".settings.baseline.json"
    rules = source / ".settings.rules.toml"
    baseline.write_text('{\n  "model": "opus"\n}\n', encoding="utf-8")
    rules.write_text('seed = [\n  ["model"],\n]\n', encoding="utf-8")
    before = baseline.read_bytes(), rules.read_bytes()

    config = promote.Config(
        ".claude/settings.json", "private_dot_claude", ".settings.baseline.json",
        ".settings.rules.toml", JsonCodec, write_json_baseline,
    )
    from engine.promote import Candidate

    found = [Candidate(("model",), "opus", UNCLASSIFIED)]
    message = promote.apply_choices(
        config, source, {"model": "opus"}, {("model",): Strategy.IGNORE}, found
    )

    assert "rolled back" in message
    assert (baseline.read_bytes(), rules.read_bytes()) == before


@pytest.mark.parametrize(
    "args,expected",
    [
        ("/usr/bin/chezmoi apply --dry-run", True),
        ("/usr/bin/chezmoi apply -n", True),
        ("/usr/bin/chezmoi apply -nv", True),
        ("/usr/bin/chezmoi apply", False),
        ("/usr/bin/chezmoi apply -v", False),
        ("/usr/bin/chezmoi apply --exclude=scripts", False),
        ("", False),
    ],
)
def test_dry_run_reads_chezmoi_argv(args, expected):
    assert entry.dry_run(args) is expected
