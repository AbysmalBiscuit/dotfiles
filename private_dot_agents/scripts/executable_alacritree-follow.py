#!/usr/bin/env python3
"""Follow an interactive agent's checkout in alacritree and herdr."""

import contextlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def run(args: list[str]) -> str | None:
    """Run a CLI with literal arguments and a bounded wait."""
    done = subprocess.run(  # noqa: S603
        args, capture_output=True, text=True, encoding="utf-8", timeout=5, check=False
    )
    return done.stdout.strip() if done.returncode == 0 else None


def background_session() -> bool:
    """Exclude Claude daemon sessions that inherit the foreground terminal."""
    pid = os.getpid()
    for _ in range(20):
        try:
            proc = Path("/proc") / str(pid)
            command = (proc / "cmdline").read_bytes().replace(b"\0", b" ")
            if b"claude daemon run" in command or b"bg-pty-host" in command:
                return True
            pid = int((proc / "stat").read_text().rsplit(")", 1)[1].split()[1])
            if pid <= 1:
                break
        except (OSError, ValueError, IndexError):
            break
    return False


def follow_alacritree(cwd: str, pane: str) -> None:
    """Move the sidebar entry, refreshing newly registered worktrees if needed."""
    executable = (
        os.environ.get("ALACRITREE_EXE")
        or shutil.which("alacritree")
        or shutil.which("alacritree.exe")
    )
    if not executable:
        return
    move = [executable, "session", "move", pane, cwd]
    if run(move) is not None:
        return
    gitdir = run(["git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"])
    if gitdir and run([executable, "project", "refresh", str(Path(gitdir).parent)]) is not None:
        run(move)


def follow_herdr(cwd: str, pane_id: str) -> None:
    """Move a live pane to the workspace registered for its checkout."""
    executable = os.environ.get("HERDR_BIN_PATH") or shutil.which("herdr")
    if not executable:
        return
    root = run(["git", "-C", cwd, "rev-parse", "--show-toplevel"])
    if not root:
        return

    def call(*args: str) -> dict:
        reply = run([executable, *args])
        if reply is None:
            return {}
        payload = json.loads(reply)
        return payload.get("result", {}) if isinstance(payload, dict) else {}

    # Herdr resolves an inherited pane ID through aliases after relocation.
    pane = call("pane", "get", pane_id).get("pane")
    if not pane:
        return
    listing = call("worktree", "list", "--cwd", root)
    entry = next(
        (
            worktree
            for worktree in listing.get("worktrees", [])
            if os.path.normcase(os.path.normpath(worktree["path"]))
            == os.path.normcase(os.path.normpath(root))
        ),
        None,
    )
    if entry is None:
        return
    workspace = entry.get("open_workspace_id")
    if not workspace:
        source = listing.get("source", {}).get("repo_root") or root
        opened = call("worktree", "open", "--cwd", source, "--path", root, "--no-focus")
        workspace = opened.get("workspace", {}).get("workspace_id")
    if workspace and workspace != pane["workspace_id"]:
        call(
            "pane",
            "move",
            pane["pane_id"],
            "--new-tab",
            "--workspace",
            workspace,
            "--no-focus",
        )


def main() -> None:
    """Consume a session-start or prompt hook from stdin."""
    pane = os.environ.get("ALACRITREE_SESSION_ID")
    herdr_pane = os.environ.get("HERDR_PANE_ID")
    if not (pane or herdr_pane) or background_session():
        return
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict) or payload.get("hook_event_name") not in (
        "SessionStart",
        "UserPromptSubmit",
    ):
        return
    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        return
    if herdr_pane:
        follow_herdr(cwd, herdr_pane)
    elif pane:
        follow_alacritree(cwd, pane)


if __name__ == "__main__":
    with contextlib.suppress(OSError, ValueError, subprocess.SubprocessError):
        main()
