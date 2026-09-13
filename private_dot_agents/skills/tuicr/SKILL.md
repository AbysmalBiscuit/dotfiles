---
name: tuicr
description: tuicr code review sessions. Read the user's review comments, add agent comments to a session, or open tuicr in a tmux, zellij, Herdr or cmux pane so the user can review changes.
---

# tuicr review workflow

The user reviews code in the tuicr TUI. You work through the `tuicr review` CLI: find the session, read the user's comments, and write your own only in the agent-review workflow.

## Pick the workflow

1. **User-led review of agent-generated changes.** The user reads the patch and writes comments in tuicr. Open or find the session, then read their comments once they say comments are ready, or poll while you wait. Every comment in the session stays the user's; your part is reading and acting on them.
2. **Agent review of a patch.** The user wants you to critique or summarize a patch. Inspect it and propose findings. Once the workflow and the target session are both clear, write findings into the session following [references/adding-comments.md](references/adding-comments.md). Ask first when either is ambiguous.

If the user's intent is ambiguous, ask which workflow they want.

## Attach to a session

1. Determine the repository directory from the user's request, the current working directory, or recent file operations. Ask if it is ambiguous.

2. List persisted sessions:

   ```bash
   tuicr review list --repo /path/to/repo   # checkout + its repo's PR sessions
   tuicr review list --repo owner/repo      # all sessions for a forge repo
   tuicr review list --all                  # every session across all repos
   ```

   A checkout path also surfaces PR sessions for that checkout's `origin` repo, and `owner/repo` matches local and PR sessions by forge coordinate. Each row carries a `kind` (`local` or `pr`) and a `slug`.

3. Choose the session:
   - Exactly one relevant session with `"active": true`: attach to it.
   - Several active, or the right one unclear: ask the user which slug to use.
   - The user gave a slug or session JSON path: use it directly.
   - PR review: pass the PR slug from the listing (e.g. `gh:owner/repo/pr/N`) to `--session`; it needs no `--repo`.
   - No active session: start one as below.

`"active": true` is a hint. On Windows a tuicr that was killed rather than quit stays marked active for up to 12 hours. If slug resolution fails, ask the user for the slug or repo path.

The CLI reads sessions with or without a multiplexer.

## Start a session

When no active session exists and the user needs an interactive review:

```bash
python3 <skill-directory>/scripts/tuicr_pane.py /path/to/repo -- <scope>
```

- `<scope>` is `-w` for uncommitted working-tree changes or `-r <revset>` for a commit range. Always pass one, so tuicr opens on exactly the changes under review.
- The script detects the multiplexer, opens a pane, blocks until tuicr exits, then closes the pane. Run it in the background, or with a timeout of at least 10 minutes, and capture the slug with `tuicr review list --repo /path/to/repo` while the user reviews.
- Pass the directory as given. The script accepts git and jj repositories, including jj workspaces with no `.git` directory.
- The user quits tuicr with `:q`.
- With no multiplexer, the script exits 1 and prints the `tuicr` command. Tell the user you are waiting for them to run it, then attach once they say it is ready.

For any other exit message, Windows, pane placement, or keybindings to relay to the user, read [references/launching.md](references/launching.md).

## Read user comments

After the user says comments are ready, or after the script returns, run:

```bash
tuicr review comments --repo /path/to/repo --session <slug>
```

The JSON gives each comment an `id`, a location, `content`, and a `comment_type` that sets your action:

- `issue`: blocking problem, fix first
- `suggestion`: implement, or explain why not
- `note`: answer or acknowledge
- `praise`: no action

While the user is still reviewing, poll about every 30 seconds and compare comment IDs with the previous result; read immediately when the user says comments are ready, and stop polling once they say the review is done. An empty result means the comments went to a different session or were never saved; ask the user which.

The review is handled when a fresh `tuicr review comments` run shows no comment ID you have not acted on or answered.

## When not to use

- The user only wants raw `git diff` output.
- The user asks for a review workflow outside tuicr.
- Remote PR review with no tuicr PR session involved.
