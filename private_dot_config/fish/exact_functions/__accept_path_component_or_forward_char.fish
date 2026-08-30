# forward-path-component also jumps whole path components when the cursor is
# inside the line, so restrict it to accepting from a live autosuggestion.
# It is not pager-aware either, unlike forward-char, so the completion pager
# needs the fallback to keep right arrow moving the selection east.
function __accept_path_component_or_forward_char
    if commandline --paging-mode
        commandline -f forward-char
        return
    end

    set -l buffer (commandline | string collect)
    if test (commandline --cursor) -ge (string length -- "$buffer")
        and commandline --showing-suggestion
        commandline -f forward-path-component
    else
        commandline -f forward-char
    end
end
