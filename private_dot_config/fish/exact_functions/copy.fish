function copy --description 'Copy to clipboard'
    if test -f $argv[1]; and test (count $argv) -eq 1
        cat $argv[1] | fish_clipboard_copy
    else
        fish_clipboard_copy $argv
    end
end
