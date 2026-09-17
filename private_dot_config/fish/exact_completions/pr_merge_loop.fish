function __pr_merge_loop_seen
    set -l words (commandline -xpc)[2..]
    for word in $argv
        contains -- $word $words; and return 0
    end
    return 1
end

set -l listing '__pr_merge_loop_seen queue list cancel'
set -l options '__pr_merge_loop_seen claude codex rebase squash merge -i --interval'

complete -c pr_merge_loop -f
complete -c pr_merge_loop -s h -l help -d 'Show help'
complete -c pr_merge_loop -n "not $listing" -s i -l interval -x -d 'Poll interval in seconds'
complete -c pr_merge_loop -n '__pr_merge_loop_seen cancel' -l all -d 'Cancel every pending job'

complete -c pr_merge_loop -n "not $listing; and not $options" -a queue -d 'Show pending PRs and recent outcomes'
complete -c pr_merge_loop -n "not $listing; and not $options" -a list -d 'Show pending PRs and recent outcomes'
complete -c pr_merge_loop -n "not $listing; and not $options" -a cancel -d "Drop this worktree's job"

set -l agent_seen '__pr_merge_loop_seen claude codex'
complete -c pr_merge_loop -n "not $listing; and not $agent_seen" -a claude -d 'Resolve conflicts with Claude Code'
complete -c pr_merge_loop -n "not $listing; and not $agent_seen" -a codex -d 'Resolve conflicts with Codex'

set -l method_seen '__pr_merge_loop_seen rebase squash merge'
complete -c pr_merge_loop -n "not $listing; and not $method_seen" -a rebase -d 'Rebase-merge the PR'
complete -c pr_merge_loop -n "not $listing; and not $method_seen" -a squash -d 'Squash-merge the PR'
complete -c pr_merge_loop -n "not $listing; and not $method_seen" -a merge -d 'Merge the PR with a merge commit'
