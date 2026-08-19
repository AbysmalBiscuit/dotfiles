#!/usr/bin/env python3
"""Save and restore alacritree's open shell sessions, agents included.

Three subcommands, one shared model:

  record   a Claude Code hook: notes which agent session runs in which pane
  save     writes the open panes -- path plus agent -- to a timestamped file
  open     reopens paths, or a saved file picked with sk/fzf, resuming agents

Panes are identified by ALACRITREE_SESSION_ID, which alacritree exports into
every PTY and passes through WSLENV untranslated, so a pane running a Linux
shell records itself the same way a Windows one does.  Paths, by contrast, are
always stored in the Windows spelling: read from either side it names exactly
one directory, whereas a POSIX path leaves the reader guessing which distro it
belongs to.

Agent ids live in a ledger under alacritree's state directory rather than in
alacritree itself, one file per pane, grouped by the instance's socket -- pane
ids restart from zero with the app, so yesterday's pane 3 must not be mistaken
for today's.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

WSL_UNC = re.compile(r"^\\\\wsl(?:\.localhost|\$)\\([^\\]+)(\\.*)?$", re.IGNORECASE)
MNT_DRIVE = re.compile(r"^/mnt/([a-zA-Z])(/.*)?$")
LEDGER_MAX_AGE = 7 * 24 * 3600

IS_WINDOWS = os.name == "nt"
IS_WSL = not IS_WINDOWS and "microsoft" in os.uname().release.lower()


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    """A child process read as UTF-8, whatever the console code page says.

    Session titles carry box drawing and emoji, which the Windows default of
    cp1252 cannot decode.
    """
    return subprocess.run(
        cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", **kwargs
    )


def die(message: str) -> None:
    print(f"alacritree-session: {message}", file=sys.stderr)
    raise SystemExit(1)


def warn(message: str) -> None:
    print(f"alacritree-session: {message}", file=sys.stderr)


# --- locations ---------------------------------------------------------------


def appdata_dir() -> Path | None:
    """%APPDATA% as this machine can open it, or None where there is no Windows."""
    if IS_WINDOWS:
        appdata = os.environ.get("APPDATA")
        return Path(appdata) if appdata else None
    if not IS_WSL:
        return None
    # WSL inherits neither %APPDATA% nor a way to guess it, and asking cmd.exe
    # costs more than the rest of a hook run, so the answer is cached per boot.
    cache = Path(os.environ.get("TMPDIR", "/tmp")) / f"alacritree-appdata-{os.getuid()}"
    try:
        cached = cache.read_text(encoding="utf-8").strip()
        if cached:
            return Path(cached)
    except OSError:
        pass
    try:
        # cmd.exe refuses to run from a UNC cwd and warns before obeying.
        raw = run(["cmd.exe", "/c", "echo %APPDATA%"], cwd="/mnt/c", timeout=15).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    if not raw or raw.startswith("%"):
        return None
    here = native_path(raw)
    try:
        cache.write_text(here + "\n", encoding="utf-8")
    except OSError:
        pass
    return Path(here)


def state_dir() -> Path:
    """alacritree's own state directory, reachable from either side of WSL."""
    appdata = appdata_dir()
    if appdata:
        return appdata / "alacritree"
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return Path(base) / "alacritree"


def sessions_dir() -> Path:
    return state_dir() / "sessions"


def ledger_root() -> Path:
    return sessions_dir() / "agents"


def instance_key(socket: str | None) -> str:
    """A directory name for one alacritree instance, taken from its socket path."""
    leaf = re.split(r"[\\/]", socket or "unknown")[-1]
    return re.sub(r"[^A-Za-z0-9._-]", "-", leaf) or "unknown"


# --- path spellings ----------------------------------------------------------


def default_distro() -> str:
    if IS_WSL:
        name = os.environ.get("WSL_DISTRO_NAME")
        if name:
            return name
    # `wsl -e` without -d runs in the default distro, which names itself in
    # $WSL_DISTRO_NAME -- locale-independent, unlike parsing `wsl -l` for the
    # translated "(Default)" marker.
    out = run(["wsl.exe", "-e", "sh", "-c", "echo $WSL_DISTRO_NAME"]).stdout
    name = out.replace("\0", "").strip()
    if not name:
        die("no default WSL distro (is WSL installed and started?)")
    return name


def windows_path(requested: str) -> str:
    """The Windows spelling of a path, however it was typed.

    /mnt/<drive> belongs to Windows already; anything else absolute-POSIX lives
    in a distro's filesystem.
    """
    p = requested
    if p.startswith("//"):
        p = "\\\\" + p[2:]
    if p.startswith("\\\\"):
        return p.replace("/", "\\")
    drive = MNT_DRIVE.match(p)
    if drive:
        rest = drive.group(2) or "/"
        return (drive.group(1).upper() + ":" + rest).replace("/", "\\")
    if p.startswith("/"):
        distro = os.environ.get("WSL_DISTRO_NAME") if IS_WSL else None
        return "\\\\wsl.localhost\\" + (distro or default_distro()) + p.replace("/", "\\")
    if IS_WSL:
        done = run(["wslpath", "-w", p])
        if done.returncode == 0 and done.stdout.strip():
            return done.stdout.strip()
    return requested


def posix_path(win: str) -> str | None:
    """The in-distro spelling of a wsl.localhost path; None for a real Windows one."""
    m = WSL_UNC.match(win)
    if not m:
        return None
    return (m.group(2) or "\\").replace("\\", "/")


def native_path(win: str) -> str:
    """A stored Windows path as the machine running this script can open it."""
    if not IS_WSL:
        return win
    m = WSL_UNC.match(win)
    if m and m.group(1).lower() == os.environ.get("WSL_DISTRO_NAME", "").lower():
        return (m.group(2) or "\\").replace("\\", "/")
    done = run(["wslpath", "-u", win])
    return done.stdout.strip() if done.returncode == 0 and done.stdout.strip() else win


def normalize(p: str) -> str:
    return p.replace("/", "\\").rstrip("\\").lower()


def same_path(a: str, b: str) -> bool:
    return normalize(a) == normalize(b)


def under(child: str, parent: str) -> bool:
    c, p = normalize(child), normalize(parent)
    return c == p or c.startswith(p + "\\")


# --- talking to alacritree ---------------------------------------------------


class Client:
    """One run's connection to alacritree: every reply is JSON on stdout."""

    def __init__(self, socket: str | None) -> None:
        self.socket = socket or os.environ.get("ALACRITREE_SOCKET")
        self.exe = self._find_exe()
        self._worktrees: list[str] | None = None

    @staticmethod
    def _find_exe() -> str:
        # Set by alacritree in every PTY and path-translated into WSL, so a
        # pane can always reach the instance it belongs to.
        env = os.environ.get("ALACRITREE_EXE")
        if env and os.path.exists(env):
            return env
        name = "alacritree.exe" if IS_WINDOWS else "alacritree"
        beside = Path(__file__).resolve().parent / name
        if beside.exists():
            return str(beside)
        found = shutil.which("alacritree") or shutil.which("alacritree.exe")
        if not found:
            die("alacritree is neither next to this script nor on PATH")
        return found

    def call(self, *args: str) -> tuple[bool, dict, str]:
        cmd = [self.exe, "--json"]
        if self.socket:
            cmd += ["--socket", self.socket]
        cmd += list(args)
        done = run(cmd)
        try:
            data = json.loads(done.stdout or "")
        except (json.JSONDecodeError, ValueError):
            data = {}
        if not isinstance(data, dict):
            data = {}
        message = data.get("error") or ((done.stdout or "") + (done.stderr or "")).strip()
        return done.returncode == 0, data, message

    def worktrees(self) -> list[str]:
        """Every worktree the sidebar carries, fetched once for the whole run."""
        if self._worktrees is None:
            ok, data, _ = self.call("project", "list")
            self._worktrees = (
                [w["path"] for p in data.get("projects", []) for w in p.get("worktrees", [])]
                if ok
                else []
            )
        return self._worktrees

    def owner_of(self, directory: str) -> str | None:
        """The worktree a path belongs to: the longest known root it sits under.

        `session create` takes only a worktree root, so a path deeper in the
        tree needs this.
        """
        owners = [w for w in self.worktrees() if under(directory, w)]
        return max(owners, key=len) if owners else None

    def send_line(self, session_id: int, text: str) -> tuple[bool, str]:
        ok, _, err = self.call("session", "send-text", str(session_id), text, "--enter")
        return ok, err


def quote(path: str, posix: bool) -> str:
    if posix:
        return "'" + path.replace("'", "'\\''") + "'"
    return "'" + path.replace("'", "''") + "'"


# --- the ledger --------------------------------------------------------------


def cmd_record(args: argparse.Namespace) -> int:
    """Claude Code hook: note -- or drop -- the agent running in this pane."""
    pane = os.environ.get("ALACRITREE_SESSION_ID")
    if not pane:
        return 0
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    directory = ledger_root() / instance_key(os.environ.get("ALACRITREE_SOCKET"))
    entry = directory / f"{pane}.json"
    event = payload.get("hook_event_name", "")

    if event == "SessionEnd":
        entry.unlink(missing_ok=True)
        return 0
    if event == "SessionStart":
        prune_ledger(directory)

    agent = payload.get("session_id")
    # CwdChanged carries the destination in new_cwd; its base cwd field still
    # holds the directory being left.
    cwd = payload.get("new_cwd") or payload.get("cwd")
    if not agent or not cwd:
        return 0

    record = {"agent": agent, "cwd": windows_path(cwd), "pane": pane}
    try:
        directory.mkdir(parents=True, exist_ok=True)
        tmp = directory / f"{pane}.{os.getpid()}.tmp"
        tmp.write_text(json.dumps(record) + "\n", encoding="utf-8")
        tmp.replace(entry)
    except OSError:
        return 0
    return 0


def prune_ledger(keep: Path) -> None:
    """Instances that are gone leave a whole directory behind; nothing else clears it."""
    try:
        stale = [
            d
            for d in ledger_root().iterdir()
            if d.is_dir() and d != keep and time.time() - d.stat().st_mtime > LEDGER_MAX_AGE
        ]
    except OSError:
        return
    for d in stale:
        shutil.rmtree(d, ignore_errors=True)


def ledger_for(socket: str | None) -> dict[int, dict]:
    """The agent recorded in each pane of one instance, keyed by pane id.

    Without a socket to match, the newest instance directory is the best guess
    -- and the only candidate when a single alacritree is running.
    """
    root = ledger_root()
    directory = root / instance_key(socket) if socket else None
    if directory is None or not directory.is_dir():
        try:
            candidates = [d for d in root.iterdir() if d.is_dir()]
        except OSError:
            return {}
        if not candidates:
            return {}
        directory = max(candidates, key=lambda d: d.stat().st_mtime)

    entries: dict[int, dict] = {}
    for f in directory.glob("*.json"):
        try:
            entries[int(f.stem)] = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError, json.JSONDecodeError):
            continue
    return entries


# --- save --------------------------------------------------------------------


def cmd_save(args: argparse.Namespace) -> int:
    client = Client(args.socket)
    ok, data, err = client.call("session", "list")
    if not ok:
        die(f"session list failed: {err}")

    agents = ledger_for(client.socket)
    shells = [s for s in data.get("sessions", []) if s.get("kind") == "shell"]
    saved: list[dict] = []
    skipped = 0

    for s in shells:
        workspace = s.get("workspace")
        if not workspace:
            # A home-workspace pane reports no path, so there is nothing to
            # restore it to.
            skipped += 1
            continue
        entry = agents.get(s.get("id"))
        path = workspace
        # An agent may have wandered deeper than the worktree root, and resume
        # only finds a transcript from the directory it was filed under.
        if entry and entry.get("cwd") and os.path.isdir(native_path(entry["cwd"])):
            path = entry["cwd"]
        saved.append(
            {
                "path": path,
                "workspace": workspace,
                "title": s.get("title"),
                "agent": entry.get("agent") if entry else None,
            }
        )

    if not saved:
        die("no shell session has a workspace to save")

    directory = sessions_dir()
    directory.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    suffix = re.sub(r"[^\w.-]", "-", args.name) if args.name else None
    target = directory / (f"{stamp}-{suffix}.json" if suffix else f"{stamp}.json")
    target.write_text(
        json.dumps(
            {
                "saved_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "socket": client.socket,
                "sessions": saved,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    if skipped:
        warn(f"{skipped} session(s) in the home workspace have no path and were skipped")
    warn(f"saved {len(saved)} session(s), {sum(1 for s in saved if s['agent'])} with an agent")
    print(target)
    return 0


# --- open --------------------------------------------------------------------


def load_saved(path: Path) -> list[dict]:
    """One saved file, in either the JSON form or the older one-path-per-line one."""
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        return json.loads(text).get("sessions", [])
    return [{"path": line.strip(), "agent": None} for line in text.splitlines() if line.strip()]


def pick_saved() -> list[dict]:
    """The saved files, newest first, previewing what each one would reopen."""
    directory = sessions_dir()
    files = (
        sorted(
            (f for f in directory.glob("*") if f.suffix.lower() in (".json", ".txt")),
            key=lambda f: f.name,
            reverse=True,
        )
        if directory.is_dir()
        else []
    )
    if not files:
        die(f"no saved sessions yet -- run `alacritree-session save` first ({directory})")

    picker = shutil.which("sk") or shutil.which("fzf")
    if not picker:
        die("neither sk (skim) nor fzf is on PATH")

    # The picker runs from the sessions directory so the list shows bare names
    # and the preview, which inherits that directory, resolves them.
    preview = f'"{sys.executable}" "{os.path.abspath(__file__)}" show {{}}'
    # Only stdout is captured: the picker draws its interface on stderr, which
    # has to reach the terminal.
    done = subprocess.run(
        [
            picker,
            "--multi",
            "--prompt",
            "restore> ",
            "--header",
            "Tab selects several, Enter restores",
            "--preview",
            preview,
            "--preview-window",
            "right:60%",
        ],
        input="\n".join(f.name for f in files),
        stdout=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=str(directory),
    )
    chosen = [line.strip() for line in done.stdout.splitlines() if line.strip()]
    return [s for name in chosen for s in load_saved(directory / name)]


def cmd_show(args: argparse.Namespace) -> int:
    """Print a saved file -- this is the picker's preview command."""
    path = Path(args.file)
    if not path.is_absolute():
        path = sessions_dir() / path
    if not path.exists():
        print(f"missing: {args.file}")
        return 0
    for s in load_saved(path):
        mark = f"  [agent {s['agent'][:8]}]" if s.get("agent") else ""
        print(f"{s['path']}{mark}")
    return 0


def cmd_open(args: argparse.Namespace) -> int:
    client = Client(args.socket)

    targets = [{"path": p, "agent": None} for p in args.paths]
    if args.file:
        path = Path(args.file)
        targets += load_saved(path if path.is_absolute() else sessions_dir() / path)
    elif not targets and not args.restore and not sys.stdin.isatty():
        targets += [{"path": line.strip(), "agent": None} for line in sys.stdin if line.strip()]
    if args.restore or not (targets or args.file):
        targets += pick_saved()
    if not targets:
        die("nothing to open")

    failures = 0
    last_workspace: str | None = None

    for target in targets:
        requested = target["path"]
        agent = None if args.no_agents else target.get("agent")

        win = windows_path(requested)
        local = native_path(win)
        if not os.path.isdir(local):
            warn(f"{requested}: not a directory")
            failures += 1
            continue
        if not IS_WSL and not os.path.isabs(win):
            win = os.path.abspath(win)

        owner = client.owner_of(win)
        if owner:
            ok, data, err = client.call("session", "create", "--workspace", owner)
        elif args.worktrees_only:
            warn(f"{requested}: no project in the sidebar owns this directory")
            failures += 1
            continue
        else:
            ok, data, err = client.call("session", "create")

        if not ok:
            warn(f"{requested}: {err}")
            failures += 1
            continue

        session_id = data.get("session_id")
        last_workspace = owner or ""

        # A worktree session already starts at its root; only a home session or
        # a path deeper in the tree has somewhere left to go.
        if not owner or not same_path(owner, win):
            # A pane under a WSL worktree runs a Linux shell; the home
            # workspace runs the configured one, which reads Windows paths.
            inside = owner is not None and posix_path(owner) is not None
            spelling = posix_path(win) if inside else win
            sent, err = client.send_line(session_id, f"cd {quote(spelling, inside)}")
            if not sent:
                warn(f"session {session_id} opened but cd failed: {err}")

        if agent:
            sent, err = client.send_line(session_id, f"claude --resume {agent}")
            if not sent:
                warn(f"session {session_id} opened but resume failed: {err}")

        note = f"  agent {agent[:8]}" if agent else ""
        print(f"session {session_id}  {owner or 'home'}  {requested}{note}")

    if args.select and last_workspace is not None:
        ok, _, err = (
            client.call("workspace", "select", last_workspace)
            if last_workspace
            else client.call("workspace", "select")
        )
        if not ok:
            warn(f"could not focus the last workspace: {err}")

    return failures


# --- cli ---------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="alacritree-session",
        description="Save and restore alacritree's open shell sessions, agents included.",
    )
    parser.add_argument("--socket", help="talk to the instance on this socket")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("record", help="Claude Code hook: record this pane's agent")

    p_save = sub.add_parser("save", help="write the open sessions to a file")
    p_save.add_argument("--name", help="appended to the timestamp in the file name")

    p_open = sub.add_parser("open", help="open sessions, or restore a saved set")
    p_open.add_argument("paths", nargs="*", help="directories to open")
    p_open.add_argument("--restore", action="store_true", help="pick a saved file to reopen")
    p_open.add_argument("--file", help="reopen this saved file instead of picking one")
    p_open.add_argument(
        "--worktrees-only",
        action="store_true",
        help="fail a directory no project owns instead of using the home workspace",
    )
    p_open.add_argument("--select", action="store_true", help="focus the last workspace opened")
    p_open.add_argument(
        "--no-agents", action="store_true", help="open plain shells, resuming nothing"
    )

    p_show = sub.add_parser("show", help="print a saved file (the picker's preview)")
    p_show.add_argument("file")

    args = parser.parse_args()
    handlers = {"record": cmd_record, "save": cmd_save, "open": cmd_open, "show": cmd_show}
    return handlers[args.command](args)


if __name__ == "__main__":
    raise SystemExit(main())
