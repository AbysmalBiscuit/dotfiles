# Value completions for the selectors `issue end` takes: the issue ids, branch
# names and worktree paths of this repository's issue worktrees. The
# clap-generated script covers every flag and subcommand but leaves the
# positional to bare file completion, so none of those ever appear.

function __devkit_issue_id -a worktree branch
    # devkit's own precedence: the `issue setup` record holds whatever the
    # tracker actually calls the issue, and the branch/directory scan is the
    # fallback for a worktree made by a plain `git worktree add`.
    set -l record $worktree/.devkit/issue.toml
    if test -f $record
        set -l recorded (string match -gr '^\s*issue\s*=\s*"([^"]+)"' <$record)
        if test -n "$recorded"
            echo $recorded
            return
        end
    end
    # A `pr-<number>` run is the PR-checkout marker rather than an id, so the
    # lookahead skips it and the scan carries on to a real id later in the name.
    for source in $branch (path basename $worktree)
        set -l found (string match -gr '(?i)(?<![a-z])(?!pr-[0-9])([a-z]+-[0-9]+)' -- $source)
        if test -n "$found"
            string upper $found
            return
        end
    end
end

function __devkit_issue_emit -a worktree branch
    # A baseline is not an issue worktree, and `end` never takes one.
    test -f $worktree/.devkit/baseline.toml; and return
    set -l id (__devkit_issue_id $worktree "$branch")
    set -l label $branch
    test -n "$label"; or set label (path basename $worktree)
    test -n "$id"; and printf '%s\t%s\n' $id $label
    test -n "$branch"; and printf '%s\t%s\n' $branch (path basename $worktree)
    printf '%s\t%s\n' $worktree $label
end

function __devkit_issue_selectors
    # Offline and fork-light on purpose: this runs on a keypress, so it reads
    # git and the record files rather than calling `issue status`, which goes
    # out to GitHub and the tracker.
    set -l worktree
    set -l branch
    # git lists the primary checkout first and it is never an issue worktree.
    set -l main 1
    git worktree list --porcelain 2>/dev/null | while read -l line
        switch $line
            case 'worktree *'
                set worktree (string replace 'worktree ' '' -- $line)
                set branch ''
            case 'branch *'
                set branch (string replace -r '^branch refs/heads/' '' -- $line)
            case ''
                if test $main -eq 1
                    set main 0
                else if test -n "$worktree"
                    __devkit_issue_emit $worktree "$branch"
                end
                set worktree ''
        end
    end
end

complete -c issue -n '__fish_seen_subcommand_from end' \
    -a '(__devkit_issue_selectors)' -d "issue worktree"
