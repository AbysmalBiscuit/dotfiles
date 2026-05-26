function strip-svg --description 'Removes SVG code from HTML'
    fish_clipboard_paste | htmlq --remove-nodes path,circle,rect | string replace --regex --all '<svg (id=".+?" )?(class=".+?" )?.+?>' '<svg $1$2>'
end

# strip-svg
