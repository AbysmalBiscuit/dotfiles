# Rename the tmux window to #<pr>[<LINEAR-ID>] (or the cwd basename) whenever the
# directory changes — covers cd, zoxide z, pushd. The gh PR lookup is backgrounded
# so it never blocks the prompt; tmux-issue-name bails fast when not in tmux or
# not in an issue worktree.
function __tmux_issue_name --on-variable PWD
    status is-interactive; or return
    set -q TMUX; or return
    command tmux-issue-name $PWD &
    disown
end

# --on-variable PWD fires only when PWD changes (a cd), not for the initial PWD
# inherited by a fresh shell. Without this a new window/pane keeps tmux's default
# name ("bash") until the first cd, so name it once at startup — but only inside
# tmux, so a shell outside any tmux session never runs it.
set -q TMUX; and __tmux_issue_name
