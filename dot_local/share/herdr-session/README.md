# Herdr session launcher

`herdr-session` opens the current checkout as a Herdr workspace, points Alacritree at it, and returns to the shell it ran in. `herdr-session new` offers an installed-agent picker; `herdr-session new claude` starts that agent directly and `herdr-session new shell` opens a shell tab. Existing Herdr clients keep their selected workspace and tab.

`herdr-session list` shows the current workspace's tabs, panes, agents, names, status, and directories. `list --json` returns the same rows as JSON. Outside Herdr, the workspace is matched to the current checkout or directory; inside a Herdr pane, it uses that pane's workspace. `--path /absolute/path` selects another checkout or directory. Listing does not start a server or change focus.

Agent choices use `~/.config/chezmoi/has.toml` and executables on `PATH`. An agent explicitly disabled in the file is excluded; unlisted agents are detected on `PATH`. `XDG_CONFIG_HOME` overrides the config directory. Run `herdr-session new --list-agents` to see the detected choices. The picker uses fzf when installed, with a numbered prompt as fallback. Canceling it creates nothing. Scripts must supply an agent or `shell`; arguments after `--` pass through to the agent.

Fish and Nushell completions suggest subcommands, options, directories, and detected agents. Fish loads its completion file automatically; Nushell loads it from `config.nu` when a shell starts.

If an agent starts with a question or approval screen, its tab stays open and the launcher names it and opens it in Alacritree, so the question is on screen. Repeated launches create separate tabs with unique agent names.

The launcher creates workspaces and tabs with `--no-focus`, inside a Herdr pane and outside one alike: the calling terminal keeps its own session and every attached Herdr client keeps the workspace and tab it was showing. Stock `herdr` serves every Herdr call. It then asks Alacritree, which lists a Herdr server's panes in its own sidebar, to open the reported tab, the same move as clicking that row. Alacritree notices new panes on its own schedule, so the launcher waits a moment for the pane and warns if it never appears. `--no-attach` leaves Alacritree alone, and an Alacritree that is absent or not running is not an error. `close` closes matching workspaces and their processes.

## Windows cursor settling

`windows-cursor-settle.patch` is a server fix against Herdr v0.9.0, commit `b99002ac99b09e00b4ca692436cb15a6b0d676f1`. It retires the previous cursor candidate after an idle interval before processing a new repaint burst. This prevents a transient repaint position above the Codex prompt from becoming the visible cursor. Linux and macOS bypass this settling path.

Check it with `git -C /absolute/path/to/herdr apply --check /absolute/path/to/windows-cursor-settle.patch`, apply it to an isolated checkout, and build the server using that checkout's build instructions. Keep the matching app-local ConPTY runtime beside a Windows build. Verify it in a separate named session before replacing the installed server; restarting the active server ends its pane processes.

## Maintain

Run `herdr-recover-after-upgrade.py` from an interactive terminal outside Herdr. It stops the server and its pane processes before launching Herdr again. Running it inside a pane would end the recovery process itself. Agent tool environments can also disable color in every new pane through inherited `NO_COLOR`.
