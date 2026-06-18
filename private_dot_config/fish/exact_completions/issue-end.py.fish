# Completions for issue-end.py (hand-written; click 8.4's generated fish_source
# is broken — its formatter emits one field per line while the registration it
# generates expects packed records, so `string split` mis-parses). Static
# completion is also faster: no `uv` boot on every keypress.

function __issue_end_ids
    # Candidate issue ids / selectors for `status` and `clean`, pulled straight
    # from `git worktree list` (no uv, no network). Matches ENG-1234-style tokens
    # in branch names and worktree paths, mirroring issue-end.py's id derivation.
    git worktree list --porcelain 2>/dev/null \
        | string match -ra '[A-Za-z]+-[0-9]+' \
        | string upper \
        | sort -u
end

# No bare file completion for the command itself.
complete -c issue-end.py -f

# Global option: a path inside the target repo/worktree (wants a real dir).
complete -c issue-end.py -s C -l dir -rF -d "Path inside the target repo or any worktree"

# Subcommands — only before one has been chosen.
complete -c issue-end.py -n "not __fish_seen_subcommand_from status clean" \
    -a status -d "Read-only report of every issue worktree"
complete -c issue-end.py -n "not __fish_seen_subcommand_from status clean" \
    -a clean -d "Interactively remove FINISHED worktrees"

# Positional args for both subcommands: issue ids / worktree selectors.
complete -c issue-end.py -n "__fish_seen_subcommand_from status clean" \
    -a "(__issue_end_ids)" -d "issue worktree"

# `clean` flags.
complete -c issue-end.py -n "__fish_seen_subcommand_from clean" \
    -s y -l yes -d "Don't prompt per worktree; remove all finished"
complete -c issue-end.py -n "__fish_seen_subcommand_from clean" \
    -l force -d "Discard dirty trees (pass --force to cleanup)"
complete -c issue-end.py -n "__fish_seen_subcommand_from clean" \
    -l pr-only -d "Ignore the Linear gate (PR merged + clean tree)"
complete -c issue-end.py -n "__fish_seen_subcommand_from clean" \
    -l clean-worktree -d "Bypass the finished gate; remove the named worktrees"

# Help, anywhere.
complete -c issue-end.py -l help -d "Show help and exit"
