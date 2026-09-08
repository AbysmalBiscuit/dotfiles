# Shell-call collection

`scripts/shell_calls.py` records attempted shell tool calls for analysis of agent write patterns. It runs as a separate `PreToolUse` command for Claude Code and Codex, independently of agent-guard's checks and text-log level. It emits no permission decision and never executes the captured command.

The default destination is `~/Nextcloud/agent-guard/shell-calls`. WSL uses `/mnt/c/Users/Lev/Nextcloud/agent-guard/shell-calls`, sharing the Windows Nextcloud client with the cost statusline. `AGENT_GUARD_SHELL_LOG_DIR` selects another destination. The default Nextcloud directory must already exist; an unavailable destination produces a diagnostic without blocking the tool.

Records are immutable UTF-8 JSON files under `<harness>/<session>/<machine>/`. Session and machine directory names retain readable identifiers and a hash so identifiers remain distinct on case-insensitive filesystems. Resuming a session adds records to the same directory. Different machines write separate files, including when they resume the same session. A temporary file is renamed into place after writing; consumers read `*.json` and ignore temporary files.

Each record contains a schema version, unique event ID, UTC capture timestamp, harness, full session ID, available subagent and tool-call IDs, command, working directory, machine and OS, and the complete original hook payload. The payload preserves tool options, shell overrides, transcript references and other fields the harness supplies. Missing command, session or working-directory fields are identified in `capture_notes`.

`capture_stage` is `attempted`: a pre-execution hook does not establish that a command ran, succeeded, or changed a file. `shell` is populated only when supplied by the hook. A tool named `Bash` can contain PowerShell on Windows. `environment_hints` records only `SHELL`, `COMSPEC`, `MSYSTEM` and `WSL_DISTRO_NAME`; these describe the hook environment, not a confirmed interpreter for the recorded command.

Commands and payloads are stored in full, without truncation or redaction. The collector reads no transcripts, command outputs or general environment dump. Existing text logs are not imported because their shortened session IDs and interleaved input rows cannot establish reliable attribution.

Set `AGENT_GUARD_SHELL_LOG=0` to disable collection. `AGENT_GUARD_MACHINE_ID` overrides the default hostname plus OS flavor when machines otherwise share a name. These settings affect collection independently of the text log's `log` setting.

Hook registrations invoke `python3 ~/.agents/plugins/agent-guard/scripts/shell_calls.py --harness claude-code` or the same command with `--harness codex`. Codex uses its existing native Windows Python launcher through `command_windows`. The chezmoi Claude and Codex baselines retain the registrations for other computers. Reload or resume a harness that loaded its hook configuration before installation.

Run the collector tests with `python3 tests/shell_calls.test.py` from this plugin directory. They exercise the stdin hook entry point, concurrent calls, resumed-session grouping, full command preservation, failure handling and filesystem-safe identifiers. Run them with native Windows Python as well when changing file handling.
