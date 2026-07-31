function __cr_complete --description 'completions for `cr`, delegated to `claude -r`'
    set -l buf (commandline -cp)
    set -l rest (string replace -r '^\s*cr(\s+|$)' '' -- $buf)
    complete -C "claude -r $rest"
end
