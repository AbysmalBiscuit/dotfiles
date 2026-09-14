# ruff: noqa: PT009
"""Run with COMMIT_TEST_DEVKIT pointing to a devkit binary supporting split/on arguments."""

import difflib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).with_name("config.toml.tmpl")
HELPER = SOURCE.parents[2] / "dot_local/bin/executable_git-commit-patch.py"
DEVKIT = os.environ["COMMIT_TEST_DEVKIT"]


class CommitTasksTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="devkit-commit-task-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_CONFIG_NOSYSTEM="1",
            XDG_CONFIG_HOME=str(self.root / "config"),
            XDG_STATE_HOME=str(self.root / "state"),
            LOCALAPPDATA=str(self.root / "state"),
            DEVKIT_SKIP_AUTOLINK="1",
        )
        self.git("init", "-q")
        self.git("config", "user.name", "Task test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "commit.gpgSign", "false")
        self.git("config", "core.hooksPath", str(self.root / "hooks-disabled"))
        self.write("selected.txt", "base\n")
        self.write("unrelated.txt", "base\n")
        self.git("add", "--", "selected.txt", "unrelated.txt")
        self.git("commit", "-qm", "chore: initialize fixture")
        source = SOURCE.read_text()
        config = source[source.index("[tasks.commit]") : source.index("[templates]")]
        config += '\n[templates.variables]\ncommit_subject = ""\ncommit_body = ""\ncoauthors = ""\n'
        config += f"python = {json.dumps(sys.executable)}\n"
        config += f"git_commit_patch = {json.dumps(str(HELPER))}\n"
        self.write("devkit.toml", config)
        self.write("unrelated.txt", "someone else's staged content\n")
        self.git("add", "--", "unrelated.txt")
        self.original_head = self.git("rev-parse", "HEAD")
        self.unrelated_blob = self.git("rev-parse", ":unrelated.txt")

    def write(self, name: str, contents: str) -> None:
        (self.root / name).write_text(contents)

    def invoke(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            args, cwd=self.root, env=self.env, text=True, capture_output=True, check=False
        )

    def git(self, *args: str) -> str:
        result = self.invoke("git", *args)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result.stdout.strip()

    def task(
        self,
        name: str,
        *,
        files: list[str] | None = None,
        patch: Path | None = None,
        succeeds: bool = True,
    ) -> str:
        args = [
            DEVKIT,
            "run",
            "-C",
            str(self.root),
            "--config",
            str(self.root / "devkit.toml"),
            "task",
            name,
        ]
        if files is not None:
            args.extend(["--arg", "files=" + ",".join(files)])
        if patch is not None:
            args.extend(["--arg", "patch=" + str(patch)])
        if name in ("commit", "commit-write", "commit-amend", "commit-patch"):
            args.extend(["--arg", "commit_subject=fix: selected change"])
        result = self.invoke(*args)
        if succeeds:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stderr + result.stdout)
        return result.stdout + result.stderr

    def assert_unrelated_staged(self) -> None:
        self.assertEqual(self.git("rev-parse", ":unrelated.txt"), self.unrelated_blob)
        self.assertEqual(self.git("show", "HEAD:unrelated.txt"), "base")

    def test_selected_paths_preserve_unrelated_staging_and_literal_names(self) -> None:
        paths = ["selected.txt", "new file.txt", "star*.txt", "-flag.txt", "$(touch nope).txt"]
        for path in paths:
            self.write(path, "selected\n")
        self.write("star-other.txt", "unselected\n")
        self.task("commit", files=paths)
        self.assertEqual(
            self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").splitlines(),
            sorted(paths),
        )
        self.assert_unrelated_staged()
        self.assertEqual(self.git("diff", "--cached", "--name-only"), "unrelated.txt")
        self.assertFalse((self.root / "nope").exists())

    def test_path_list_has_no_fixed_slot_limit(self) -> None:
        paths = [f"new-{number:02}.txt" for number in range(24)]
        for path in paths:
            self.write(path, "new\n")
        self.task("commit", files=paths)
        self.assertEqual(
            self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").splitlines(),
            paths,
        )
        self.assert_unrelated_staged()

    def test_interleaved_stages_do_not_mix_commit_contents(self) -> None:
        self.write("agent-a.txt", "A\n")
        self.write("agent-b.txt", "B\n")
        for agent in ("a", "b"):
            self.task("commit-stage", files=[f"agent-{agent}.txt"])
        for agent in ("a", "b"):
            self.task("commit-write", files=[f"agent-{agent}.txt"])
            self.assertEqual(
                self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"),
                f"agent-{agent}.txt",
            )
        self.assert_unrelated_staged()

    def test_empty_selection_cannot_commit_existing_staging(self) -> None:
        for task in ("commit", "commit-write"):
            for files in ([], ["", ""]):
                with self.subTest(task=task, files=files):
                    self.task(task, files=files, succeeds=False)
                    self.assertEqual(self.git("rev-parse", "HEAD"), self.original_head)
                    self.assertEqual(self.git("diff", "--cached", "--name-only"), "unrelated.txt")
                    self.assert_unrelated_staged()

    def test_hook_failure_preserves_unrelated_staging(self) -> None:
        hooks = self.root / "hooks"
        hooks.mkdir()
        hook = hooks / "pre-commit"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        self.git("config", "core.hooksPath", str(hooks))
        self.write("selected.txt", "selected\n")
        self.task("commit", files=["selected.txt"], succeeds=False)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.original_head)
        self.assert_unrelated_staged()

    def test_amend_changes_message_without_committing_staged_content(self) -> None:
        tree = self.git("rev-parse", "HEAD^{tree}")
        self.task("commit-amend")
        self.assertEqual(self.git("rev-parse", "HEAD^{tree}"), tree)
        self.assertEqual(self.git("log", "-1", "--format=%B"), "fix: selected change")
        self.assert_unrelated_staged()

    def test_selected_deletion_is_committed(self) -> None:
        (self.root / "selected.txt").unlink()
        self.task("commit", files=["selected.txt"])
        self.assertEqual(
            self.git("diff-tree", "--no-commit-id", "--name-status", "-r", "HEAD"),
            "D\tselected.txt",
        )
        self.assert_unrelated_staged()

    def test_patch_task_commits_selected_hunk_and_preserves_staging(self) -> None:
        base = "".join(f"line {number}\n" for number in range(24))
        self.write("selected.txt", base)
        self.git("add", "--", "selected.txt")
        self.git("commit", "--only", "-qm", "chore: seed hunks", "--", "selected.txt")
        staged = base.replace("line 20\n", "another staged hunk\n")
        selected = base.replace("line 2\n", "selected hunk\n")
        working = staged.replace("line 2\n", "selected hunk\n").replace(
            "line 11\n", "unstaged hunk\n"
        )
        self.write("selected.txt", staged)
        self.git("add", "--", "selected.txt")
        self.write("selected.txt", working)
        patch = self.root / "selected patch.diff"
        patch.write_text(
            "".join(
                difflib.unified_diff(
                    base.splitlines(keepends=True),
                    selected.splitlines(keepends=True),
                    fromfile="a/selected.txt",
                    tofile="b/selected.txt",
                )
            )
        )
        self.task("commit-patch", patch=patch)
        self.assertEqual(self.git("show", "HEAD:selected.txt"), selected.strip())
        self.assertEqual(
            self.git("show", ":selected.txt"), staged.replace("line 2\n", "selected hunk\n").strip()
        )
        self.assertEqual((self.root / "selected.txt").read_text(), working)
        self.assertEqual(self.git("log", "-1", "--format=%B"), "fix: selected change")
        self.assert_unrelated_staged()


if __name__ == "__main__":
    unittest.main()
