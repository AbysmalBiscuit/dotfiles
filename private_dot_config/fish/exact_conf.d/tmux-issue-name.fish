# Rename the tmux window to #<pr>[<LINEAR-ID>] whenever the directory changes
# (covers cd, zoxide z, pushd, and shell startup). The gh PR lookup is
# backgrounded so it never blocks the prompt; tmux-issue-name bails fast when
# not in tmux or not in an issue worktree.
function __tmux_issue_name --on-variable PWD
    status is-interactive; or return
    set -q TMUX; or return
    command tmux-issue-name $PWD &
    disown
end
