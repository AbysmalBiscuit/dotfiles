import fcntl
import json
import os
import pty
import select
import shlex
import shutil
import struct
import subprocess
import tempfile
import termios
import time
from contextlib import suppress
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERDR = shutil.which("herdr")
NVIM = shutil.which("nvim")
NAVIGATOR = os.environ.get(
    "NAVIGATOR_PATH", str(Path.home() / ".local/share/nvim/lazy/nvim-navigator")
)
if not HERDR or not NVIM or not Path(NAVIGATOR).is_dir():
    raise SystemExit(
        "Requires herdr, nvim, and nvim-navigator (override its path with NAVIGATOR_PATH)."
    )
work = Path(tempfile.mkdtemp(prefix="herdr-nav-test-"))
env = {k: v for k, v in os.environ.items() if not k.startswith(("HERDR_", "ALACRITREE_", "TMUX"))}
for kind in ("CONFIG", "DATA", "CACHE", "STATE"):
    env[f"XDG_{kind}_HOME"] = str(work / kind.lower())
env.update(
    TERM="xterm-256color",
    SHELL="/bin/bash",
    HERDR_CONFIG_PATH=str(work / "config.toml"),
    HERDR_SOCKET_PATH=str(work / "herdr.sock"),
    NVIM_LOG_FILE=str(work / "nvim.log"),
)
config = Path(
    os.environ.get("HERDR_NAV_TEST_CONFIG", ROOT / "private_dot_config/herdr/config.toml")
).read_text()
config = config.replace("onboarding = false", 'onboarding = false\ndefault_shell = "/bin/bash"')
config = config.replace("~/.config/herdr/navigate.py", str(work / "config/herdr/navigate.py"))
config = "\n".join(
    line[:-1] + " >> " + str(work / "navigation.log") + ' 2>&1"'
    if line.startswith("command = ")
    else line
    for line in config.splitlines()
)
(work / "config.toml").write_text(config)
(work / "config/herdr").mkdir(parents=True, exist_ok=True)
(work / "config/herdr/navigate.py").write_text(
    (ROOT / "private_dot_config/herdr/navigate.py").read_text()
)
# Loading the real Navigator spec without starting unrelated LazyVim plugins.
(work / "init.lua").write_text(
    f"""
vim.opt.rtp:prepend({json.dumps(NAVIGATOR)})
vim.opt.rtp:prepend({json.dumps(str(ROOT / "private_dot_config/exact_nvim"))})
LazyVim = {{ pick = function() return function() end end }}
local specs = dofile(
  {json.dumps(str(ROOT / "private_dot_config/exact_nvim/lua/plugins/editor.lua"))}
)
for _, spec in ipairs(specs) do
  if spec[1] == "craigmac/nvim-navigator" then
    spec.config()
    for _, key in ipairs(spec.keys) do
      vim.keymap.set(key.mode, key[1], key[2])
    end
  end
end
vim.cmd("vsplit")
vim.cmd("wincmd h")
"""
)
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))


def terminal():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


client = subprocess.Popen(
    [HERDR],
    stdin=slave,
    stdout=slave,
    stderr=slave,
    env=env,
    cwd=work,
    preexec_fn=terminal,  # noqa: PLW1509 -- This standalone test has no threads.
)
os.close(slave)


def pump(seconds=0.1):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if select.select([master], [], [], 0.02)[0]:
            try:
                data = os.read(master, 65536)
                with (work / "screen.log").open("ab") as log:
                    log.write(data)
                if b"\x1b[6n" in data:
                    os.write(master, b"\x1b[1;1R")
            except OSError:
                break


def api(*args):
    result = subprocess.run(
        [HERDR, *args], env=env, cwd=work, capture_output=True, text=True, timeout=5, check=False
    )
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)["result"] if result.stdout.strip() else {}


def until(check, message):
    last = None
    for _ in range(60):
        pump(0.1)
        try:
            last = check()
            if last:
                return last
        except (RuntimeError, subprocess.SubprocessError, ValueError):
            pass
    raise AssertionError(f"{message}: {last}; artifacts: {work}")


def nvim_expr(expression):
    result = subprocess.run(
        [NVIM, "--server", str(work / "nvim.sock"), "--remote-expr", expression],
        env=env,
        cwd=work,
        capture_output=True,
        text=True,
        timeout=3,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout.strip()


try:
    until(lambda: api("pane", "list"), "Herdr did not start")
    left = api("pane", "list")["panes"][0]["pane_id"]
    right = api("pane", "split", left, "--direction", "right", "--cwd", str(work), "--no-focus")[
        "pane"
    ]["pane_id"]
    api(
        "pane",
        "run",
        left,
        shlex.join(
            [NVIM, "-u", str(work / "init.lua"), "-i", "NONE", "--listen", str(work / "nvim.sock")]
        ),
    )
    until(lambda: nvim_expr('winnr("$")') == "2", "Neovim split setup failed")
    until(
        lambda: any(
            p["name"] == "nvim"
            for p in api("pane", "process-info", "--pane", left)["process_info"].get(
                "foreground_processes", []
            )
        ),
        "Neovim foreground detection failed",
    )
    pump(0.5)
    os.write(master, b"\x1b[1;5C")
    pump(0.5)
    until(
        lambda: nvim_expr("winnr()") == "2",
        "Ctrl+Right was consumed before reaching the Neovim split",
    )
    assert api("pane", "layout", "--pane", left)["layout"]["focused_pane_id"] == left
    print("PASS: first Ctrl+Right moves inside Neovim", flush=True)
    os.write(master, b"\x1b[1;5C")
    until(
        lambda: api("pane", "layout", "--pane", right)["layout"]["focused_pane_id"] == right,
        "Neovim edge did not focus the Herdr neighbor",
    )
    print("PASS: second Ctrl+Right hands off to the Herdr pane", flush=True)
    os.write(master, b"\x1b[1;5D")
    until(
        lambda: api("pane", "layout", "--pane", left)["layout"]["focused_pane_id"] == left,
        "Shell Ctrl+Left did not return to Neovim",
    )
    os.write(master, b"\x1b[1;5D")
    until(lambda: nvim_expr("winnr()") == "1", "Ctrl+Left did not resume Neovim split navigation")
    print("PASS: shell → Neovim → inner split", flush=True)
    bottom = api("pane", "split", left, "--direction", "down", "--cwd", str(work), "--no-focus")[
        "pane"
    ]["pane_id"]
    nvim_expr('execute("split | wincmd k")')
    top_window = nvim_expr("win_getid()")
    lower_window = nvim_expr('win_getid(winnr("j"))')
    assert top_window != lower_window
    os.write(master, b"\x1b[1;5B")
    until(lambda: nvim_expr("win_getid()") == lower_window, "Ctrl+Down skipped the Neovim split")
    assert api("pane", "layout", "--pane", left)["layout"]["focused_pane_id"] == left
    os.write(master, b"\x1b[1;5B")
    until(
        lambda: api("pane", "layout", "--pane", left)["layout"]["focused_pane_id"] == bottom,
        "Ctrl+Down did not hand off at the Neovim edge",
    )
    os.write(master, b"\x1b[1;5A")
    until(
        lambda: api("pane", "layout", "--pane", left)["layout"]["focused_pane_id"] == left,
        "Ctrl+Up did not return from the lower Herdr pane",
    )
    os.write(master, b"\x1b[1;5A")
    until(lambda: nvim_expr("win_getid()") == top_window, "Ctrl+Up did not move within Neovim")
    print("PASS: vertical navigation in both layers", flush=True)
    nvim_expr('execute("enew | terminal /bin/bash --noprofile --norc")')
    nvim_expr('execute("startinsert")')
    until(lambda: nvim_expr("mode()") == "t", "Neovim terminal mode did not start")
    os.write(master, b"\x1b[1;5B")
    until(
        lambda: nvim_expr("win_getid()") == lower_window,
        "Ctrl+Down failed from a Neovim terminal buffer",
    )
    print("PASS: navigation from a Neovim terminal buffer", flush=True)
finally:
    with suppress(RuntimeError, subprocess.SubprocessError, ValueError):
        api("server", "stop")
    try:
        pump(0.5)
        client.wait(timeout=4)
    except subprocess.TimeoutExpired:
        client.terminate()
        pump(0.5)
        client.wait(timeout=4)
    os.close(master)
    print(f"Artifacts: {work}", flush=True)
