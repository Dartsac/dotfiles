function multiplexer --description 'Print the multiplexer that applies here: herdr or tmux'
    # Inside a pane, the multiplexer that owns it. Outside one, the Default
    # multiplexer (DEFAULT_MULTIPLEXER, from the machine-local config-local.fish)
    # when it is installed, else tmux, else herdr. With neither installed, it
    # says so and fails, and so does the shortcut that asked. Neovim's
    # lua/config/multiplexer.lua (the nvim package) follows this rule: change
    # both.
    if test "$HERDR_ENV" = 1
        echo herdr
    else if test -n "$TMUX"
        echo tmux
    else
        # `command`: functions/tmux.fish and functions/herdr.fish always exist.
        for candidate in $DEFAULT_MULTIPLEXER tmux herdr
            if contains -- $candidate tmux herdr; and command -q $candidate
                echo $candidate
                return
            end
        end
        echo "no multiplexer installed: install tmux to use this" >&2
        return 1
    end
end
