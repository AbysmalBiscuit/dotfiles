# ruff: noqa: PT009

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).with_name("executable_git-commit-patch.py")


class PatchCommitTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_AUTHOR_NAME="Test",
            GIT_AUTHOR_EMAIL="test@example.invalid",
            GIT_COMMITTER_NAME="Test",
            GIT_COMMITTER_EMAIL="test@example.invalid",
        )
        self.git("init", "--initial-branch=main")
        self.patch = self.root / "selected.patch"

    def git(self, *args: str) -> bytes:
        result = subprocess.run(
            ["git", "-C", str(self.repo), *args],
            env=self.env,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result.stdout

    def run_helper(self) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            [sys.executable, str(HELPER), "--patch", str(self.patch), "--message", "fix: selected"],
            cwd=self.repo,
            env=self.env,
            capture_output=True,
            check=False,
        )

    def prepare_hunks(self) -> tuple[bytes, bytes, bytes, bytes]:
        base = b"".join(f"line {number}\n".encode() for number in range(40))
        selected = base.replace(b"line 2\n", b"selected\n")
        staged = base.replace(b"line 20\n", b"staged\n")
        working = selected.replace(b"line 20\n", b"staged\n").replace(b"line 35\n", b"unstaged\n")
        path = self.repo / "file.txt"
        path.write_bytes(base)
        self.git("add", "file.txt")
        self.git("commit", "-m", "initial")
        path.write_bytes(selected)
        self.patch.write_bytes(self.git("diff", "--binary", "HEAD", "--", "file.txt"))
        path.write_bytes(staged)
        self.git("add", "file.txt")
        path.write_bytes(working)
        return base, selected, staged, working

    def test_preserves_staged_and_unstaged_hunks_in_selected_file(self) -> None:
        _, selected, _, working = self.prepare_hunks()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(self.git("show", "HEAD:file.txt"), selected)
        self.assertEqual(
            self.git("show", ":file.txt"),
            selected.replace(b"line 20\n", b"staged\n"),
        )
        self.assertEqual((self.repo / "file.txt").read_bytes(), working)
        self.assertFalse((self.repo / ".git/index.lock").exists())

    def hook(self, name: str, body: str) -> Path:
        hooks = self.root / "custom-hooks"
        hooks.mkdir(exist_ok=True)
        self.git("config", "core.hooksPath", str(hooks))
        path = hooks / name
        path.write_text("#!/bin/sh\n" + body, encoding="utf-8", newline="\n")
        path.chmod(0o755)
        return path

    def test_rejects_hook_changing_candidate_without_publishing(self) -> None:
        _, _, _, working = self.prepare_hunks()
        (self.repo / "unrelated.txt").write_text("leave out\n")
        self.hook("pre-commit", "git add -- unrelated.txt\n")
        old_head = self.git("rev-parse", "HEAD")
        old_index = (self.repo / ".git/index").read_bytes()
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), old_head)
        self.assertEqual((self.repo / ".git/index").read_bytes(), old_index)
        self.assertEqual((self.repo / "file.txt").read_bytes(), working)
        self.assertIn(b"changed the selected tree", result.stderr)

    def test_overlap_refuses_before_commit_and_preserves_index_bytes(self) -> None:
        base, _, _, working = self.prepare_hunks()
        (self.repo / "file.txt").write_bytes(base.replace(b"line 2\n", b"other staged\n"))
        self.git("add", "file.txt")
        (self.repo / "file.txt").write_bytes(working)
        old_head = self.git("rev-parse", "HEAD")
        old_index = (self.repo / ".git/index").read_bytes()
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"overlaps staged changes", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), old_head)
        self.assertEqual((self.repo / ".git/index").read_bytes(), old_index)
        self.assertEqual((self.repo / "file.txt").read_bytes(), working)

    def test_hook_failure_preserves_existing_staging(self) -> None:
        self.prepare_hunks()
        self.hook("pre-commit", "echo expected-hook-rejection >&2\nexit 9\n")
        old_head = self.git("rev-parse", "HEAD")
        old_index = (self.repo / ".git/index").read_bytes()
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"expected-hook-rejection", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), old_head)
        self.assertEqual((self.repo / ".git/index").read_bytes(), old_index)
        self.assertFalse((self.repo / ".git/index.lock").exists())

    def test_forwards_existing_hooks_with_identity_cwd_arguments_and_stdin(self) -> None:
        self.prepare_hunks()
        log = self.root / "hooks.log"
        self.env["HOOK_LOG"] = str(log)
        pre = self.hook("pre-commit", 'printf "pre:%s:%s\\n" "$0" "$PWD" >> "$HOOK_LOG"\n')
        self.hook("commit-msg", 'printf "msg:%s\\n" "$1" >> "$HOOK_LOG"\n')
        self.hook(
            "reference-transaction",
            'printf "ref:%s\\n" "$1" >> "$HOOK_LOG"\ncat >> "$HOOK_LOG"\n',
        )
        self.hook("post-commit", 'printf "post\\n" >> "$HOOK_LOG"\n')
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        observed = log.read_text()
        self.assertIn(f"pre:{pre.as_posix()}:{self.repo.as_posix()}", observed)
        self.assertIn("COMMIT_EDITMSG", observed)
        self.assertIn("ref:prepared", observed)
        self.assertIn("ref:committed", observed)
        self.assertIn("refs/heads/main", observed)
        self.assertIn("post\n", observed)

    def test_unborn_branch_preserves_unrelated_new_staged_file(self) -> None:
        (self.repo / "selected.txt").write_text("selected\n")
        self.git("add", "selected.txt")
        self.patch.write_bytes(self.git("diff", "--cached", "--binary"))
        self.git("rm", "--cached", "selected.txt")
        (self.repo / "other.txt").write_text("other\n")
        self.git("add", "other.txt")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(self.git("ls-tree", "--name-only", "HEAD"), b"selected.txt\n")
        self.assertEqual(self.git("diff", "--cached", "--name-only"), b"other.txt\n")
        self.assertEqual((self.repo / "other.txt").read_text(), "other\n")

    def test_linked_worktree_uses_its_own_index(self) -> None:
        self.prepare_hunks()
        primary = self.repo
        original = (primary / ".git/index").read_bytes()
        linked = self.root / "linked"
        self.git("worktree", "add", "-b", "linked", str(linked))
        self.repo = linked
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual((primary / ".git/index").read_bytes(), original)
        self.assertIn(b"selected\n", self.git("show", "HEAD:file.txt"))

    def test_binary_deletion_and_quoted_paths(self) -> None:
        filename = "space 'quote';file.bin"
        (self.repo / filename).write_bytes(b"old\x00binary\n")
        (self.repo / "remove.txt").write_text("remove\n")
        self.git("add", "--", filename, "remove.txt")
        self.git("commit", "-m", "initial")
        (self.repo / filename).write_bytes(b"new\x00binary\n")
        (self.repo / "remove.txt").unlink()
        self.patch.write_bytes(self.git("diff", "--binary", "HEAD"))
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(self.git("show", f"HEAD:{filename}"), b"new\x00binary\n")
        self.assertEqual(self.git("ls-tree", "--name-only", "HEAD", "remove.txt"), b"")
        self.assertEqual((self.repo / filename).read_bytes(), b"new\x00binary\n")
        self.assertFalse((self.repo / "remove.txt").exists())

    def test_keeps_unrelated_assume_unchanged_and_intent_to_add_entries(self) -> None:
        self.prepare_hunks()
        (self.repo / "flagged.txt").write_text("tracked\n")
        self.git("add", "flagged.txt")
        self.git("commit", "--only", "-m", "flagged", "--", "flagged.txt")
        self.git("update-index", "--assume-unchanged", "flagged.txt")
        (self.repo / "intent.txt").write_text("not staged\n")
        self.git("add", "--intent-to-add", "intent.txt")
        old_flags = self.git("ls-files", "-v", "flagged.txt")
        old_intent = self.git("ls-files", "--debug", "intent.txt")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(self.git("ls-files", "-v", "flagged.txt"), old_flags)
        self.assertEqual(self.git("ls-files", "--debug", "intent.txt"), old_intent)
        self.assertNotIn(b"intent.txt", self.git("diff", "--cached", "--name-only"))

    def test_in_progress_operation_refuses_without_index_changes(self) -> None:
        self.prepare_hunks()
        old_index = (self.repo / ".git/index").read_bytes()
        merge_head = self.repo / ".git/MERGE_HEAD"
        merge_head.write_bytes(self.git("rev-parse", "HEAD"))
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"finish the existing Git operation", result.stderr)
        self.assertEqual((self.repo / ".git/index").read_bytes(), old_index)
        self.assertTrue(merge_head.exists())

    def test_existing_index_lock_is_never_removed(self) -> None:
        self.prepare_hunks()
        lock = self.repo / ".git/index.lock"
        lock.write_bytes(b"another owner")
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(lock.read_bytes(), b"another owner")

    def test_install_failure_retains_commit_and_index_recovery_files(self) -> None:
        _, selected, _, working = self.prepare_hunks()
        original = (self.repo / ".git/index").read_bytes()
        self.hook("post-commit", "mv .git/index .git/index.saved\nmkdir .git/index\n")
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"was created, but the index could not be installed", result.stderr)
        self.assertIn(b"Do not retry the commit", result.stderr)
        self.assertEqual(self.git("show", "HEAD:file.txt"), selected)
        [recovery] = (self.repo / ".git").glob("commit-patch-*")
        self.assertEqual((recovery / "original.index").read_bytes(), original)
        self.assertTrue((recovery / "replacement.index").is_file())
        self.assertTrue((self.repo / ".git/index.lock").is_file())
        self.assertEqual((self.repo / "file.txt").read_bytes(), working)

    def test_hook_moving_head_cannot_publish_the_selected_commit(self) -> None:
        self.prepare_hunks()
        self.git("commit", "--allow-empty", "--only", "-m", "marker")
        parent = self.git("rev-parse", "HEAD^")
        original = (self.repo / ".git/index").read_bytes()
        self.hook("pre-commit", "git update-ref HEAD HEAD^\n")
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), parent)
        self.assertEqual((self.repo / ".git/index").read_bytes(), original)

    def test_redirecting_environment_does_not_select_another_index(self) -> None:
        _, selected, _, _ = self.prepare_hunks()
        foreign = self.root / "foreign.index"
        self.env["GIT_INDEX_FILE"] = str(foreign)
        self.env["GIT_DIR"] = str(self.root / "missing.git")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        del self.env["GIT_DIR"]
        del self.env["GIT_INDEX_FILE"]
        self.assertEqual(self.git("show", "HEAD:file.txt"), selected)
        self.assertFalse(foreign.exists())

    def test_bad_patch_preserves_index_and_head(self) -> None:
        self.prepare_hunks()
        self.patch.write_text("not a patch\n")
        original = (self.repo / ".git/index").read_bytes()
        head = self.git("rev-parse", "HEAD")
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual((self.repo / ".git/index").read_bytes(), original)
        self.assertFalse((self.repo / ".git/index.lock").exists())

    def test_merge_driver_cannot_discard_conflicting_staged_hunks(self) -> None:
        base, _, _, working = self.prepare_hunks()
        (self.repo / "file.txt").write_bytes(base.replace(b"line 2\n", b"other staged\n"))
        self.git("add", "file.txt")
        (self.repo / "file.txt").write_bytes(working)
        original = (self.repo / ".git/index").read_bytes()
        head = self.git("rev-parse", "HEAD")
        for driver in ("ours", "union", "text"):
            with self.subTest(driver=driver):
                (self.repo / ".gitattributes").write_text(f"file.txt merge={driver}\n")
                if driver != "union":
                    self.git("config", f"merge.{driver}.driver", "true")
                result = self.run_helper()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"merge driver", result.stderr)
                self.assertEqual(self.git("rev-parse", "HEAD"), head)
                self.assertEqual((self.repo / ".git/index").read_bytes(), original)

    def test_hook_detaching_head_cannot_publish_on_another_reference(self) -> None:
        self.prepare_hunks()
        original = (self.repo / ".git/index").read_bytes()
        head = self.git("rev-parse", "HEAD")
        self.hook("pre-commit", 'git update-ref --no-deref HEAD "$(git rev-parse HEAD)"\n')
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"HEAD reference changed", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual(self.git("rev-parse", "refs/heads/main"), head)
        self.assertEqual((self.repo / ".git/index").read_bytes(), original)

    def test_attribute_check_uses_empty_index_fallback_like_merge_tree(self) -> None:
        self.prepare_hunks()
        attributes = self.repo / ".gitattributes"
        attributes.write_text("file.txt merge\n")
        self.git("add", ".gitattributes")
        attributes.unlink()
        global_attributes = self.root / "attributes"
        global_attributes.write_text("file.txt merge=ours\n")
        self.git("config", "core.attributesFile", str(global_attributes))
        self.git("config", "merge.ours.driver", "true")
        original = (self.repo / ".git/index").read_bytes()
        head = self.git("rev-parse", "HEAD")
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"merge driver", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual((self.repo / ".git/index").read_bytes(), original)

    def test_custom_default_merge_driver_is_refused(self) -> None:
        self.prepare_hunks()
        self.git("config", "merge.default", "ours")
        self.git("config", "merge.ours.driver", "true")
        original = (self.repo / ".git/index").read_bytes()
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"merge driver", result.stderr)
        self.assertEqual((self.repo / ".git/index").read_bytes(), original)

    def test_rewound_publication_failure_retains_index_recovery(self) -> None:
        self.prepare_hunks()
        original = (self.repo / ".git/index").read_bytes()
        self.env["EXPECTED_HEAD"] = self.git("rev-parse", "HEAD").decode().strip()
        self.hook(
            "reference-transaction",
            'if [ "$1" = committed ]; then\n'
            '  git -c core.hooksPath=/dev/null update-ref HEAD "$EXPECTED_HEAD"\n'
            '  rm -f "$GIT_INDEX_FILE"\n'
            '  mkdir "$GIT_INDEX_FILE"\n'
            "fi\n",
        )
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD").decode().strip(), self.env["EXPECTED_HEAD"])
        self.assertEqual((self.repo / ".git/index").read_bytes(), original)
        [recovery] = (self.repo / ".git").glob("commit-patch-*")
        self.assertTrue((recovery / "proposed").is_file())
        self.assertTrue((recovery / "replacement.index").is_file())
        self.assertTrue((self.repo / ".git/index.lock").is_file())

    def test_preserves_patch_whitespace_with_apply_fix_configured(self) -> None:
        _, selected, _, _ = self.prepare_hunks()
        selected = selected.replace(b"selected\n", b"selected  \n")
        (self.repo / "file.txt").write_bytes(selected)
        self.patch.write_bytes(self.git("diff", "--binary", "HEAD", "--", "file.txt"))
        self.git("config", "apply.whitespace", "fix")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(self.git("show", "HEAD:file.txt"), selected)


if __name__ == "__main__":
    unittest.main()
