# forward-path-component also jumps whole path components when the cursor is
# inside the line, so restrict it to accepting from a live autosuggestion.
function __accept_path_component_or_forward_char
    set -l buffer (commandline | string collect)
    if test (commandline --cursor) -ge (string length -- "$buffer")
        and commandline --showing-suggestion
        commandline -f forward-path-component
    else
        commandline -f forward-char
    end
end
