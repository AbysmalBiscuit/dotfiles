# Herdr session attachment

`herdr-session` opens the current checkout in a full Herdr UI. `herdr-session new` offers an installed-agent picker; `herdr-session new claude` starts that agent directly and `herdr-session new shell` opens a shell tab. Existing clients keep their selected workspace and tab.

`herdr-session list` shows the current workspace's tabs, panes, agents, names, status, and directories. `list --json` returns the same rows as JSON. Outside Herdr, the workspace is matched to the current checkout or directory; inside a Herdr pane, it uses that pane's workspace. `--path /absolute/path` selects another checkout or directory. Listing does not start a server or change focus.

Agent choices use `~/.config/chezmoi/has.toml` and executables on `PATH`. An agent explicitly disabled in the file is excluded; unlisted agents are detected on `PATH`. `XDG_CONFIG_HOME` overrides the config directory. Run `herdr-session new --list-agents` to see the detected choices. The picker uses fzf when installed, with a numbered prompt as fallback. Canceling it creates nothing. Scripts must supply an agent or `shell`; arguments after `--` pass through to the agent.

Fish and Nushell completions suggest subcommands, options, directories, and detected agents. Fish loads its completion file automatically; Nushell loads it from `config.nu` when a shell starts.

If an agent starts with a question or approval screen, its tab stays open and the launcher attaches so you can respond. With `--no-attach` or inside Herdr, select the reported tab yourself. Repeated launches create separate tabs with unique agent names.

The launcher creates workspaces and tabs with `--no-focus`. A separate `herdr-session-client` binary selects its initial workspace or tab through its own client connection. Stock `herdr` handles server and CLI operations. Alacritree's `attach = "session"` setting is independent of this launcher.

Inside a Herdr pane, the launcher prepares the workspace or tab and returns. Use Herdr's navigation to select it. `--no-attach` also prepares without moving any client. `close` closes matching workspaces and their processes.

## Build

Install Git, stable Rust, and Zig 0.15.2, then run:

```fish
herdr-session-build-client
```

The build helper fetches the pinned Herdr commit, applies `startup-target.patch`, and installs `~/.local/bin/herdr-session-client`. On Windows, the filename ends in `.exe`. It leaves the stock binary and running servers in place. `--source /absolute/path/to/herdr` uses an unmodified local checkout at the pinned commit. `--output /absolute/path/to/binary` chooses another output; `HERDR_SESSION_CLIENT` selects it in the launcher.

The patch is based on Herdr v0.9.0, commit `b99002ac99b09e00b4ca692436cb15a6b0d676f1`. It adds `client --workspace ID` and `client --tab ID` using the existing endpoint navigation request. No server protocol changes are required.

## Maintain

Stock Herdr updates do not update this client. When upgrading the client base, update the build helper's pinned commit, rebase the patch, and run the isolated terminal verification against the intended stock server version:

```fish
python3 ~/.local/share/herdr-session/verify.py
python3 ~/.local/share/herdr-session/verify.py --git
```

Verification starts a disposable server with separate config and socket paths. It types into real attached clients to check their working directories and tab identities after opening, joining, and creating tabs. A local Claude stand-in presents startup questions to verify repeated launches without starting a real coding agent. Failure logs remain in the printed test directory. Remove the patch and client build once stock Herdr offers equivalent attachment targeting, after verifying the launcher against that API.
