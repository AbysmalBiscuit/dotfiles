This is my chezmoi repo.

## Script validation

Before finishing script changes, run the language's supported syntax, lint, format, and type checks on the scripts and their tests. Fix findings before reporting completion. Resolve tools from `PATH` or Neovim's Mason bin directory.

- Python: `ruff check`, `ruff format --check`, and `pyrefly check`.
- TypeScript: Bun for execution/tests, `tsc7`/`tsgo` for type checking, and the configured linter/formatter.
- Nushell: `nu-check --debug` (require `true`; add `--as-module` for modules), `nu --ide-check <limit> <file>` diagnostics, and the configured Nushell formatter if available.
- Bash: `bash -n`, `shellcheck`, and `shfmt -d`.
- Zsh: `zsh -n` and a formatter that supports Zsh. ShellCheck does not support Zsh; verify the installed formatter's dialect support.
- Fish: `fish --no-execute`, `fish_indent --check`, and `fish-lsp` diagnostics through an LSP client.

## Git commits

Never commit unless I ask you to.

Commits are done using the `/commit` skill.

When you make commits, add only commit title.

- No commit body.
- No commit trailer.
- No commit attribution.
