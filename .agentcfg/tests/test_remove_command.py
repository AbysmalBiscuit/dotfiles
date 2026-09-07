"""`agentcfg remove`: retiring a key the picker can never offer.

The picker walks the live file, so it only ever proposes keys that are
present. Deleting one is the opposite direction and needs both sides cleared
at once, because whichever side keeps the key restores it on the next apply.
"""

import json

import pytest

import promote as entry
from engine.codecs import JsonCodec, TomlCodec
from engine.merge import merge
from engine.rules import RuleSet
from engine.writers import delete_paths

RULES = 'seed = [["enabledPlugins", "*"]]\nenforce = [["env", "*"]]\n'


def build(tmp_path, baseline, live, rules=RULES):
    source = tmp_path / "src" / "private_dot_claude"
    source.mkdir(parents=True)
    (source / ".settings.baseline.json").write_text(json.dumps(baseline), encoding="utf-8")
    (source / ".settings.rules.toml").write_text(rules, encoding="utf-8")
    target = tmp_path / "home" / ".claude"
    target.mkdir(parents=True)
    (target / "settings.json").write_text(json.dumps(live), encoding="utf-8")
    return tmp_path / "src", tmp_path / "home"


def read(root, home):
    return (
        json.loads((root / "private_dot_claude" / ".settings.baseline.json").read_text()),
        json.loads((home / ".claude" / "settings.json").read_text()),
    )


class _Ok:
    returncode = 0


class _Fails:
    returncode = 1


@pytest.fixture(autouse=True)
def no_subprocess(monkeypatch):
    """Nothing in this file may reach a real `claude` or `codex`."""
    calls = []

    def record(command, **_kwargs):
        calls.append(command)
        return _Ok()

    monkeypatch.setattr(entry.subprocess, "run", record)
    return calls


def test_clearing_one_side_is_not_enough(tmp_path):
    """Why remove writes twice: seed hands the live value straight back."""
    baseline = {"enabledPlugins": {"a@m": True, "b@m": True}}
    live = {"enabledPlugins": {"a@m": True, "b@m": True}}
    (tmp_path / "r.toml").write_text(RULES, encoding="utf-8")
    rules = RuleSet.load(tmp_path / "r.toml")

    del baseline["enabledPlugins"]["a@m"]
    assert "a@m" in merge(baseline, live, rules)["enabledPlugins"]
    del live["enabledPlugins"]["a@m"]
    assert "a@m" not in merge(baseline, live, rules)["enabledPlugins"]


def test_remove_clears_the_baseline_and_the_live_file(tmp_path):
    root, home = build(
        tmp_path,
        {"enabledPlugins": {"a@m": True, "b@m": True}},
        {"enabledPlugins": {"a@m": True, "b@m": True}},
    )
    assert entry.remove(["enabledPlugins.a@m"], root, home) == 0
    baseline, live = read(root, home)
    assert baseline["enabledPlugins"] == {"b@m": True}
    assert live["enabledPlugins"] == {"b@m": True}


def test_remove_prunes_the_container_it_empties(tmp_path):
    """An empty mapping is a leaf to lint, and it matches no pattern written
    for its members, so leaving one behind fails the next apply."""
    root, home = build(
        tmp_path, {"enabledPlugins": {"a@m": True}}, {"enabledPlugins": {"a@m": True}}
    )
    assert entry.remove(["enabledPlugins.a@m"], root, home) == 0
    baseline, live = read(root, home)
    assert "enabledPlugins" not in baseline
    assert "enabledPlugins" not in live


def test_remove_reaches_a_path_only_the_live_file_carries(tmp_path):
    root, home = build(tmp_path, {}, {"enabledPlugins": {"a@m": True}})
    assert entry.remove(["enabledPlugins.a@m"], root, home) == 0
    assert read(root, home)[1] == {}


def test_remove_leaves_everything_it_was_not_asked_about(tmp_path):
    root, home = build(
        tmp_path,
        {"env": {"X": "1"}, "enabledPlugins": {"a@m": True}},
        {"env": {"X": "1"}, "enabledPlugins": {"a@m": True}, "theme": "dark"},
    )
    entry.remove(["enabledPlugins.a@m"], root, home)
    baseline, live = read(root, home)
    assert baseline == {"env": {"X": "1"}}
    assert live == {"env": {"X": "1"}, "theme": "dark"}


def test_an_unknown_path_fails_rather_than_passing_quietly(tmp_path, capsys):
    """A typo that exits 0 would look exactly like a successful removal."""
    root, home = build(tmp_path, {}, {"enabledPlugins": {"a@m": True}})
    assert entry.remove(["enabledPlugins.typo@m"], root, home) == 1
    assert "no config carries this path" in capsys.readouterr().err


def test_dry_run_writes_nothing(tmp_path, no_subprocess):
    root, home = build(
        tmp_path, {"enabledPlugins": {"a@m": True}}, {"enabledPlugins": {"a@m": True}}
    )
    assert entry.remove(["--dry-run", "enabledPlugins.a@m"], root, home) == 0
    assert read(root, home) == (
        {"enabledPlugins": {"a@m": True}},
        {"enabledPlugins": {"a@m": True}},
    )
    assert no_subprocess == []


def test_the_uninstall_runs_for_a_plugin(tmp_path, no_subprocess):
    root, home = build(tmp_path, {}, {"enabledPlugins": {"a@m": True}})
    entry.remove(["enabledPlugins.a@m"], root, home)
    assert no_subprocess == [["claude", "plugin", "uninstall", "a@m"]]


def test_keep_installed_edits_the_config_and_stops_there(tmp_path, no_subprocess):
    root, home = build(tmp_path, {}, {"enabledPlugins": {"a@m": True}})
    entry.remove(["--keep-installed", "enabledPlugins.a@m"], root, home)
    assert no_subprocess == []
    assert read(root, home)[1] == {}


@pytest.mark.parametrize(
    "path,expected",
    [
        (("enabledPlugins", "a@m"), ["claude", "plugin", "uninstall", "a@m"]),
        (("enabledPlugins",), None),
        (("enabledPlugins", "a@m", "nested"), None),
        (("theme",), None),
    ],
)
def test_only_a_direct_member_is_an_uninstall(path, expected):
    """Removing a plugin retires it; editing a field inside one does not."""
    assert entry.uninstall_command(entry.CONFIGS[0], path) == expected


def test_a_failed_uninstall_is_reported_without_undoing_the_edit(
    tmp_path, monkeypatch, capsys
):
    """The config is already correct at that point. Reverting it would put the
    key back and leave the app loading a plugin the repo no longer lists."""
    monkeypatch.setattr(entry.subprocess, "run", lambda *_a, **_kw: _Fails())
    root, home = build(tmp_path, {}, {"enabledPlugins": {"a@m": True}})
    assert entry.remove(["enabledPlugins.a@m"], root, home) == 1
    assert "exited non-zero" in capsys.readouterr().err
    assert read(root, home)[1] == {}


def test_unloadable_rules_roll_the_files_back_and_skip_the_uninstall(
    tmp_path, no_subprocess, capsys
):
    """The validation gate is what makes the uninstall safe to run last."""
    root, home = build(
        tmp_path,
        {"enabledPlugins": {"a@m": True}},
        {"enabledPlugins": {"a@m": True}},
        rules="nonsense = [[",
    )
    before = read(root, home)
    assert entry.remove(["enabledPlugins.a@m"], root, home) == 1
    assert read(root, home) == before
    assert no_subprocess == []
    assert "rolled back" in capsys.readouterr().err


def test_json_layout_survives_a_removal(tmp_path):
    """The baseline is hand-reviewed in git, so a removal must not reformat it."""
    root, home = build(tmp_path, {"env": {"X": "1"}}, {"enabledPlugins": {"a@m": True}})
    baseline_path = root / "private_dot_claude" / ".settings.baseline.json"
    baseline_path.write_bytes(JsonCodec.dump({"env": {"X": "1"}, "theme": "dark"}))
    entry.remove(["enabledPlugins.a@m"], root, home)
    assert baseline_path.read_bytes() == JsonCodec.dump({"env": {"X": "1"}, "theme": "dark"})


def test_toml_removal_keeps_the_comments_around_it(tmp_path):
    """The codex baseline is hand-annotated; tomlkit is what preserves it."""
    path = tmp_path / "config.toml"
    path.write_text(
        "# why this server is here\n"
        "[mcp_servers.keep]\n"
        "url = \"https://keep\"\n"
        "\n"
        "[mcp_servers.drop]\n"
        "url = \"https://drop\"\n",
        encoding="utf-8",
    )
    delete_paths(path, TomlCodec, [("mcp_servers", "drop")])
    assert path.read_text(encoding="utf-8") == (
        "# why this server is here\n"
        "[mcp_servers.keep]\n"
        "url = \"https://keep\"\n"
        "\n"
    )


def test_delete_paths_leaves_a_file_it_changes_nothing_in_alone(tmp_path):
    path = tmp_path / "config.toml"
    original = "# header\n[a]\nb = 1\n"
    path.write_text(original, encoding="utf-8")
    assert delete_paths(path, TomlCodec, [("a", "missing")]) == []
    assert path.read_text(encoding="utf-8") == original


def offered(capsys):
    out = capsys.readouterr().out.splitlines()
    return dict(line.split("\t", 1) for line in out)


def test_complete_offers_containers_beside_their_members(tmp_path, capsys):
    """A container is what you remove to retire a whole plugin or server, so
    dropping it from the list would hide the only useful target."""
    root, home = build(tmp_path, {}, {"enabledPlugins": {"a@m": True, "b@m": True}})
    assert entry.complete([], root, home) == 0
    assert set(offered(capsys)) == {
        "enabledPlugins",
        "enabledPlugins.a@m",
        "enabledPlugins.b@m",
    }


def test_complete_counts_a_container_across_both_files(tmp_path, capsys):
    """Counting one side would understate what removing the container takes."""
    root, home = build(
        tmp_path, {"enabledPlugins": {"a@m": True}}, {"enabledPlugins": {"b@m": True}}
    )
    entry.complete([], root, home)
    assert offered(capsys)["enabledPlugins"].endswith("2 keys under it")


def test_complete_names_the_uninstall_a_member_would_trigger(tmp_path, capsys):
    root, home = build(tmp_path, {}, {"enabledPlugins": {"a@m": True}, "theme": "dark"})
    entry.complete([], root, home)
    shown = offered(capsys)
    assert shown["enabledPlugins.a@m"].endswith("uninstalls it")
    assert shown["theme"] == ".claude/settings.json"


def test_complete_filters_by_prefix_and_ignores_the_separator(tmp_path, capsys):
    """fish passes `--` so a half-typed flag cannot read as a path prefix."""
    root, home = build(tmp_path, {}, {"enabledPlugins": {"a@m": True}, "theme": "dark"})
    entry.complete(["--", "enabledPlugins."], root, home)
    assert list(offered(capsys)) == ["enabledPlugins.a@m"]


def test_complete_says_nothing_about_a_config_it_cannot_parse(tmp_path, capsys):
    """A shell runs this on a keypress. No candidates is a usable answer; a
    traceback pasted into the prompt is not."""
    root, home = build(tmp_path, {}, {"enabledPlugins": {"a@m": True}})
    (root / "private_dot_claude" / ".settings.baseline.json").write_text("{ broken")
    assert entry.complete([], root, home) == 0
    assert "enabledPlugins.a@m" in offered(capsys)


@pytest.mark.parametrize("flag", ["--help", "-h"])
def test_help_is_printed_rather_than_opening_the_picker(flag, capsys):
    """An unrecognised flag used to fall through to the interactive picker,
    which is the one thing `--help` must never do."""
    assert entry.main([flag]) == 0
    assert capsys.readouterr().out.startswith("usage: agentcfg")


def test_help_reaches_a_subcommand(capsys):
    assert entry.main(["remove", "--help"]) == 0
    assert "keep-installed" in capsys.readouterr().out


def test_help_names_every_config(capsys):
    """Written from CONFIGS, so adding one cannot leave this text behind."""
    entry.main(["--help"])
    out = capsys.readouterr().out
    for config in entry.CONFIGS:
        assert config.target in out


def test_a_help_token_does_not_hijack_completion(tmp_path, capsys):
    """The shell passes whatever is half-typed. `complete` answers first so a
    token that happens to read as a flag returns candidates, not a usage page."""
    root, home = build(tmp_path, {}, {"enabledPlugins": {"a@m": True}})
    entry.complete(["--", "--help"], root, home)
    assert capsys.readouterr().out == ""
