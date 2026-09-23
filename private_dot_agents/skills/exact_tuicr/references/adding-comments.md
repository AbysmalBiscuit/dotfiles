# Adding agent comments

Write comments into a session only in the agent-review workflow, after the user approves writing them into tuicr.

## Choosing the target and type

- Line comment when a specific file and line are known; add `--end-line` for a range.
- File comment (`--target-file` without `--line`) for file-scoped feedback.
- Review-level comment (no `--target-file`) only for a whole-review summary.
- `--side new` for added or unchanged lines, `--side old` for removed lines.
- `--type issue` for problems; `suggestion`, `note` or `praise` when that matches the intent better.
- Always pass `--username` naming the agent, so the user can tell your comments from theirs.

## Examples

```bash
tuicr review add --repo /path/to/repo --session <slug> \
  --target-file src/main.rs \
  --line 42 \
  --side new \
  --type issue \
  --username "<agent name>" \
  "Handle the empty case here."
```

```bash
tuicr review add --repo /path/to/repo --session <slug> \
  --target-file src/main.rs \
  --type suggestion \
  --username "<agent name>" \
  "Consider splitting this file-level concern into a helper."
```

For structured input, pass `--input` with literal JSON, `@path/to/file.json`, or `-` for stdin. Target types are `review`, `file`, `line` and `line_range`.
