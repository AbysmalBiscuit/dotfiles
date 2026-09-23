---
name: open-file-of
description: Use when the user asks to open, launch, preview, or view a file or directory in its default desktop application (editor, PDF viewer, image viewer, browser) rather than reading its contents into the conversation.
---

# Open File

Hand a file to the desktop's default application. This is **not** a request to read the file — do not Read it, summarize it, or explain it unless separately asked.

## Do This

```bash
open /absolute/path/to/file
```

That is the whole skill. One command, one file.

## Rules

1. **Resolve to an absolute path first.** If the user gave a relative path or a bare name, locate it with `fd` before opening.
2. **One `open` per target.** Multiple files → multiple calls, in one message.
3. **Ignore the exit code.** `open` returns nonzero (4 is common) even when the file opened fine — it reports on the handler chain, not on what appeared on screen. Never retry, never switch tools, never report failure based on it.
4. **Don't background it.** `open` returns immediately; `&` or `run_in_background` is wrong.
5. **Don't read the file.** Opening replaces reading, it doesn't precede it.
6. **Report in one line**: what you opened. Nothing else.

## Quick Reference

| Ask | Command |
|---|---|
| Open a file | `open /home/lev/notes.md` |
| Open a directory in the file manager | `open /home/lev/Git/project` |
| Open a URL | `open https://example.com` |
| Ambiguous name | `fd "notes.md"` → then `open <hit>` |

## Common Mistakes

- **Reading the file "for context" first.** The user wants it on screen, not in the transcript.
- **Treating a nonzero exit as failure.** It isn't one. Escalating to `explorer.exe`, `code`, or `wslpath` after a "failed" `open` opens the file a second time and wastes a turn.
- **Guessing at a path that doesn't exist.** Verify with `fd` before opening; if `fd` finds nothing, say so instead of running `open`.
- **Choosing an app.** `open` delegates to the system default. Don't substitute `code`, `vim`, or `xdg-open`-with-flags unless the user names the app.
