function mv-vid
    mkdir -p vid
    for ext in mp4 mov webm m4v mkv
        set files (fd --type file --max-depth 1 "\.$ext\$")
        if test (count $files) -gt 0
            for f in $files
                mv -n -t vid -- "$f"
            end
        end
    end
end
