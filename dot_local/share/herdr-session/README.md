# Herdr session launcher

`herdr-session` opens the current checkout as a Herdr workspace, points Alacritree at it, and returns to the shell it ran in. `herdr-session new` offers an installed-agent picker; `herdr-session new claude` starts that agent directly and `herdr-session new shell` opens a shell tab. Existing Herdr clients keep their selected workspace and tab.

`herdr-session list` shows the current workspace's tabs, panes, agents, names, status, and directories. `list --json` returns the same rows as JSON. Outside Herdr, the workspace is matched to the current checkout or directory; inside a Herdr pane, it uses that pane's workspace. `--path /absolute/path` selects another checkout or directory. Listing does not start a server or change focus.

Agent choices use `~/.config/chezmoi/has.toml` and executables on `PATH`. An agent explicitly disabled in the file is excluded; unlisted agents are detected on `PATH`. `XDG_CONFIG_HOME` overrides the config directory. Run `herdr-session new --list-agents` to see the detected choices. The picker uses fzf when installed, with a numbered prompt as fallback. Canceling it creates nothing. Scripts must supply an agent or `shell`; arguments after `--` pass through to the agent.

Fish and Nushell completions suggest subcommands, options, directories, and detected agents. Fish loads its completion file automatically; Nushell loads it from `config.nu` when a shell starts.

If an agent starts with a question or approval screen, its tab stays open and the launcher names it and opens it in Alacritree, so the question is on screen. Repeated launches create separate tabs with unique agent names.

The launcher creates workspaces and tabs with `--no-focus`, inside a Herdr pane and outside one alike: the calling terminal keeps its own session and every attached Herdr client keeps the workspace and tab it was showing. Stock `herdr` serves every Herdr call. It then asks Alacritree, which lists a Herdr server's panes in its own sidebar, to open the reported tab, the same move as clicking that row. Alacritree notices new panes on its own schedule, so the launcher waits a moment for the pane and warns if it never appears. `--no-attach` leaves Alacritree alone, and an Alacritree that is absent or not running is not an error. `close` closes matching workspaces and their processes.

## Build

The launcher drives Alacritree over its CLI instead of shipping a client, so none of this is needed to run it. `herdr-session-build-client`, `startup-target.patch`, and the attachment checks in `verify.py` describe a launcher that took over its terminal, and are kept only until they are removed.

Install Git, stable Rust, and Zig 0.15.2, then run:

```fish
herdr-session-build-client
```

The build helper fetches the pinned Herdr commit, applies `startup-target.patch`, and installs `~/.local/bin/herdr-session-client`. On Windows, the filename ends in `.exe`. It leaves the stock binary and running servers in place. `--source /absolute/path/to/herdr` uses an unmodified local checkout at the pinned commit. `--output /absolute/path/to/binary` chooses another output; `HERDR_SESSION_CLIENT` selects it in the launcher.

The patch is based on Herdr v0.9.0, commit `b99002ac99b09e00b4ca692436cb15a6b0d676f1`. It adds `client --workspace ID` and `client --tab ID` using the existing endpoint navigation request. No server protocol changes are required.

### Windows cursor settling

`windows-cursor-settle.patch` is a separate server fix against the same pinned commit. It retires the previous cursor candidate after an idle interval before processing a new repaint burst. This prevents a transient repaint position above the Codex prompt from becoming the visible cursor. Linux and macOS bypass this settling path.

The client build helper does not apply this patch: replacing only the client cannot repair server cursor state. Check it with `git -C /absolute/path/to/herdr apply --check /absolute/path/to/windows-cursor-settle.patch`, apply it to an isolated checkout, and build the server using that checkout's build instructions. Keep the matching app-local ConPTY runtime beside a Windows build. Verify it in a separate named session before replacing the installed server; restarting the active server ends its pane processes.

## Maintain

Run `herdr-recover-after-upgrade.py` from an interactive terminal outside Herdr. It stops the server and its pane processes before launching Herdr again. Running it inside a pane would end the recovery process itself. Agent tool environments can also disable color in every new pane through inherited `NO_COLOR`.

Stock Herdr updates do not update this client. When upgrading the client base, update the build helper's pinned commit, rebase the patch, and run the isolated terminal verification against the intended stock server version:

```fish
python3 ~/.local/share/herdr-session/verify.py
python3 ~/.local/share/herdr-session/verify.py --git
```

Verification starts a disposable server with separate config and socket paths. It types into real attached clients to check their working directories and tab identities after opening, joining, and creating tabs, so it exercises the retired attachment path rather than the current launcher. A local Claude stand-in presents startup questions to verify repeated launches without starting a real coding agent. Failure logs remain in the printed test directory.
