function fish_user_key_bindings
    # Execute this once per mode that emacs bindings should be used in
    fish_default_key_bindings -M insert

    # Then execute the vi-bindings so they take precedence when there's a conflict.
    # Without --no-erase fish_vi_key_bindings will default to
    # resetting all bindings.
    # The argument specifies the initial mode (insert, "default" or visual).
    fish_vi_key_bindings --no-erase insert

    bind --mode insert right __accept_path_component_or_forward_char

    # Word kill on the delete keys. Alt is the window manager's prefix, so
    # alt-d never reaches the shell. The presets bind these to the token
    # variants; match ctrl-w and alt-d instead so both directions cut the same
    # unit the muscle memory expects.
    for mode in default insert
        bind --mode $mode ctrl-backspace backward-kill-path-component
        bind --mode $mode ctrl-delete kill-word
    end
end
