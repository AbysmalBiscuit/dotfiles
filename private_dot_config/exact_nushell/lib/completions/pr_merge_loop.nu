const PR_MERGE_LOOP_WORDS = [
    [value description group];
    [queue "Show pending PRs and recent outcomes" command]
    [list "Show pending PRs and recent outcomes" command]
    [cancel "Drop this worktree's job" command]
    [claude "Resolve conflicts with Claude Code" agent]
    [codex "Resolve conflicts with Codex" agent]
    [rebase "Rebase-merge the PR (default)" method]
    [squash "Squash-merge the PR" method]
    [merge "Merge the PR with a merge commit" method]
    [manual "Never merge; a person merges the PR" method]
]

def "nu-complete pr_merge_loop words" [context: string] {
    let typed = $context | split row " " | skip 1
    let used = $PR_MERGE_LOOP_WORDS | where value in $typed | get group
    if "command" in $used {
        return []
    }
    let has_options = ($used | is-not-empty) or ($typed | any {|word| $word in ["-i" "--interval" "--log"] })
    $PR_MERGE_LOOP_WORDS
    | where group not-in $used
    | where {|word| not ($has_options and $word.group == "command") }
    | select value description
}

# Keep the current worktree's PR rebased until it merges
export extern pr_merge_loop [
    ...words: string@"nu-complete pr_merge_loop words" # claude|codex, rebase|squash|merge, queue|list, cancel
    --interval(-i): int # Poll interval in seconds
    --log # Write the job's log
    --all # With cancel, cancel every pending job
    --help(-h) # Show help
]
