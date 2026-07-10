function html2md --description 'Converts html files to Obsidian style markdown'
    set filename $argv[1]
    set outfile $argv[2]
    if test -z "$outfile"
        set outfile (string replace -r '(.+)\.htm.*$' '$1' "$filename")
    end
    if not string match -q -r '\.md$' "$outfile"
        set outfile "$outfile.md"
    end
    set mediadir (path change-extension '' "$outfile")_media
    pandoc -f html -t gfm-raw_html --wrap=none --strip-comments \
        --extract-media="$mediadir" "$filename" -o "$outfile"; or exit 1
    echo "Wrote '$outfile'"
end
