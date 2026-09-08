"""Exercise independent attachment through disposable server and PTY clients."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

parser = argparse.ArgumentParser()
parser.add_argument("--launcher", default=str(Path.home() / ".local/bin/herdr-session"))
parser.add_argument("--client")
parser.add_argument("--git", action="store_true")
args = parser.parse_args()

base = Path(tempfile.mkdtemp(prefix="hs-focus-"))
(base / "config/herdr").mkdir(parents=True)
(base / "config/herdr/config.toml").write_text(
    'onboarding = false\n[update]\nversion_check = false\nmanifest_check = false\n[terminal]\ndefault_shell = "/bin/sh"\n'
)
for directory in ("runtime", "state", "data", "a", "b"):
    (base / directory).mkdir()
env = {k: v for k, v in os.environ.items() if not k.startswith("HERDR_")}
env.update(
    XDG_CONFIG_HOME=str(base / "config"),
    XDG_RUNTIME_DIR=str(base / "runtime"),
    XDG_STATE_HOME=str(base / "state"),
    XDG_DATA_HOME=str(base / "data"),
    HERDR_SOCKET_PATH=str(base / "api.sock"),
    HERDR_DISABLE_SOUND="1",
    SHELL="/bin/sh",
    TERM="xterm-256color",
)
if args.client:
    env["HERDR_SESSION_CLIENT"] = args.client
exe = str(Path.home() / ".local/bin/herdr")
(base / "bin").mkdir()
fake_claude = base / "bin/claude"
fake_claude.write_text(
    "#!/bin/sh\n"
    "export HERDR_AGENT=claude\n"
    f'"{exe}" pane report-agent "$HERDR_PANE_ID" --source custom:startup-test '
    "--agent claude --state blocked >/dev/null\n"
    'printf "Startup question: type an answer\\n"\n'
    "while IFS= read -r answer; do\n"
    f'  printf "%s\\n" "$answer" >> "{base}/answer-$HERDR_PANE_ID"\n'
    "done\n"
)
fake_claude.chmod(0o755)
env["PATH"] = str(base / "bin") + os.pathsep + env["PATH"]
log = (base / "server-output").open("w")
server = subprocess.Popen(
    [exe, "server"], env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log
)
if args.git:
    subprocess.run(["git", "init", "--quiet", str(base / "a")], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(base / "a"),
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "-c",
            "core.hooksPath=/dev/null",
            "commit",
            "--quiet",
            "--no-gpg-sign",
            "--allow-empty",
            "-m",
            "test fixture",
        ],
        check=True,
    )
    (base / "b").rmdir()
    subprocess.run(
        [
            "git",
            "-C",
            str(base / "a"),
            "worktree",
            "add",
            "--quiet",
            "-b",
            "test-linked",
            str(base / "b"),
        ],
        check=True,
    )
clients = []
outputs = {}


def drain(seconds):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        ready, _, _ = select.select([fd for _, fd in clients], [], [], 0.05)
        for fd in ready:
            try:
                outputs[fd].extend(os.read(fd, 65536))
            except OSError:
                pass


def attach(folder, command="open", pick=False, agent="shell"):
    pid, fd = pty.fork()
    if pid == 0:
        kind = [agent] if command == "new" and not pick else []
        os.execve(
            args.launcher, ["herdr-session", command, *kind, "--path", str(base / folder)], env
        )
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
    clients.append((pid, fd))
    outputs[fd] = bytearray()
    drain(2)
    if pick:
        os.write(fd, b"shell")
        drain(0.5)
        os.write(fd, b"\r")
        deadline = time.monotonic() + 10
        while b"tab " not in outputs[fd] and time.monotonic() < deadline:
            drain(0.1)
        drain(2)
    elif command == "new" and agent != "shell":
        deadline = time.monotonic() + 10
        while b"tab " not in outputs[fd] and time.monotonic() < deadline:
            drain(0.1)
        drain(2)
    return fd


def cwd(fd, label):
    path = base / label
    os.write(fd, f"pwd > {path}\r".encode())
    drain(1)
    assert path.exists(), f"client did not accept input: {bytes(outputs[fd])[-3000:]!r}"
    return path.read_text().strip()


def tab(fd, label):
    path = base / label
    os.write(fd, f"echo $HERDR_TAB_ID > {path}\r".encode())
    drain(0.5)
    assert path.exists(), "client did not report its tab ID"
    value = path.read_text().strip()
    assert value, "missing HERDR_TAB_ID"
    return value


def tab_ids():
    result = subprocess.run(
        [exe, "tab", "list"], env=env, capture_output=True, text=True, check=True
    )
    return {item["tab_id"] for item in json.loads(result.stdout)["result"]["tabs"]}


try:
    for _ in range(100):
        if (base / "api.sock").exists():
            break
        if server.poll() is not None:
            raise RuntimeError((base / "server-output").read_text())
        time.sleep(0.05)
    assert (base / "api.sock").exists(), "server socket did not appear"
    a = attach("a")
    assert cwd(a, "a-before") == str(base / "a")
    a_tab = tab(a, "a-tab-before")
    b = attach("b")
    assert cwd(b, "b-result") == str(base / "b")
    actual = cwd(a, "a-after")
    assert actual == str(base / "a"), f"launching B moved A to {actual}"
    print("PASS: starting B preserved A")
    joined = attach("a")
    assert cwd(joined, "joined") == str(base / "a")
    assert cwd(b, "b-after-join") == str(base / "b")
    print("PASS: joining A preserved B")
    fresh = attach("a", "new")
    assert cwd(fresh, "fresh") == str(base / "a")
    assert cwd(b, "b-after-new") == str(base / "b")
    assert tab(fresh, "fresh-tab") != a_tab
    assert tab(a, "a-tab-after") == a_tab
    print("PASS: new tab in A preserved A and B, including tab identity")
    before = tab_ids()
    for folder, expected in (("a", 2), ("b", 1)):
        listed = subprocess.run(
            [args.launcher, "list", "--json", "--path", str(base / folder)],
            env=env,
            capture_output=True,
            text=True,
            check=True,
        )
        rows = json.loads(listed.stdout)
        assert len(rows) == expected, rows
        assert all(row["cwd"] == str(base / folder) for row in rows), rows
        assert all(row["agent"] == "shell" for row in rows), rows
    assert tab_ids() == before
    assert cwd(b, "b-after-list") == str(base / "b")
    assert tab(a, "a-tab-after-list") == a_tab
    print("PASS: list stayed within each workspace and preserved tabs and client focus")
    failed = subprocess.run(
        [args.launcher, "new", "invalid-test-agent", "--no-attach", "--path", str(base / "b")],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert failed.returncode == 1 and "not an installed, supported agent" in failed.stderr
    assert tab_ids() == before, "failed agent launch left a tab behind"
    assert cwd(b, "b-after-failure") == str(base / "b")
    assert tab(a, "a-tab-after-failure") == a_tab
    print("PASS: unavailable agent was rejected without creating a tab or changing focus")
    picked = attach("b", "new", pick=True)
    assert cwd(picked, "picked") == str(base / "b")
    assert tab(picked, "picked-tab") != tab(b, "b-tab-after-picker")
    assert tab(a, "a-tab-after-picker") == a_tab
    print("PASS: interactive picker opened the selected shell without moving other clients")
    for number in (1, 2):
        blocked = attach("a", "new", agent="claude")
        listed = subprocess.run(
            [exe, "agent", "list"], env=env, capture_output=True, text=True, check=True
        )
        agents = [
            item
            for item in json.loads(listed.stdout)["result"]["agents"]
            if item.get("agent") == "claude"
        ]
        assert len(agents) == number, (
            "startup question closed the agent tab",
            bytes(outputs[blocked])[-1000:],
        )
        assert len({item["name"] for item in agents}) == number, agents
        agent = next(item for item in agents if item["name"] == ("a" if number == 1 else "a-2"))
        answer_file = base / f"answer-{agent['pane_id']}"
        assert not answer_file.exists(), "startup question was answered automatically"
        os.write(blocked, f"answer-{number}\r".encode())
        drain(1)
        assert answer_file.read_text().strip() == f"answer-{number}"
        assert tab(a, f"a-tab-after-blocked-{number}") == a_tab
        assert cwd(b, f"b-after-blocked-{number}") == str(base / "b")
    print(
        "PASS: repeated agent launches preserve startup questions, unique names, and client focus"
    )
finally:
    for pid, fd in clients:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        os.close(fd)
        os.waitpid(pid, 0)
        (base / f"client-{pid}.log").write_bytes(outputs[fd])
    if server.poll() is None:
        subprocess.run([exe, "server", "stop"], env=env, capture_output=True, timeout=5)
        server.wait(timeout=5)
    print("Test artifacts:", base)
