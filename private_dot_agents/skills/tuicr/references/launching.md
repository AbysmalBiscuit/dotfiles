# Launching tuicr in a pane

`scripts/tuicr_pane.py --help` lists the arguments and the `TUICR_PANE_DIRECTION` and `TUICR_PANE_SIZE` overrides for pane placement.

## Multiplexer detection

The script picks the multiplexer from the environment:

| Variable | Multiplexer | Default pane |
|----------|-------------|--------------|
| `$TMUX` | tmux | above the agent, 80% of the window |
| `$ZELLIJ` | zellij | stacked |
| `$HERDR_ENV=1` | Herdr | split to the right |
| `$CMUX_WORKSPACE_ID` | cmux | split to the right |

When several are set, the script uses the innermost one it can identify. cmux is a GUI terminal, so any other multiplexer found runs inside it. When it cannot tell, it exits naming what it found; rerun with `--mux tmux|zellij|herdr|cmux` naming the one the agent runs in. Inside cmux `$TERM_PROGRAM` reads `ghostty`, so `$CMUX_WORKSPACE_ID` is the reliable marker.

## Script exit messages

| Message or symptom | Cause and action |
|--------------------|------------------|
| `No multiplexer found` | Tell the user you are waiting for them to run the printed `tuicr` command, then attach with `tuicr review list` |
| `Found several multiplexers` | Rerun with `--mux` |
| `tuicr did not start in Herdr pane` | The script printed the pane's last output; usually tuicr is missing from the pane shell's PATH or rejected the scope |
| `tuicr not found on PATH` | Tell the user to install tuicr |
| `Not a git or jj repository` | Ask the user for the correct repo directory |
| Script still waiting, tuicr pane gone | The user closed a tmux, zellij or cmux pane by hand, so the exit signal never arrives; stop the script and read comments |

In cmux the script prints the surface ref; `cmux close-surface --surface <ref>` force-closes the pane.

## Windows

Herdr is the only backend tested on Windows. Run the script with the Python on PATH (`python3`, `python` or `py`) and pass Windows repo paths (`C:/...`).

Each Herdr pane runs the user's Windows shell (nushell, PowerShell), so the script types a plain `tuicr` command that parses the same in every shell: arguments with characters outside letters, digits and `_./:+-` go in single quotes, and an argument containing a single quote is refused. Herdr on Windows reports only the shell as a pane's foreground process, so the script finds tuicr among the shell's child processes through PowerShell's `Get-CimInstance`.

## Keybindings to relay to the user

Every multiplexer: quit tuicr with `:q`.

- tmux: switch panes with `Ctrl-b` then arrows, resize with `Ctrl-b` then `Ctrl-arrow`, zoom with `Ctrl-b` then `z`.
- zellij: switch panes with `Alt` + arrows, resize with `Ctrl-n` then arrows, fullscreen with `Alt-f`, cycle stacked panes with `Alt` + `[` / `]`.
- cmux: click a pane or `cmux focus-pane --pane <ref>`; `cmux read-screen --surface <ref>` reads a pane without focusing it.
- Herdr: click a pane to select it; `herdr pane read <pane> --source visible` reads it without focusing (the script prints the pane ID).
