function multiplexer --description 'Print the multiplexer that applies here: herdr or tmux'
    # Inside a pane, the multiplexer that owns it. Outside one, the Default
    # multiplexer: DEFAULT_MULTIPLEXER from the machine-local config-local.fish,
    # or tmux when unset (as on the Work machine).
    if test "$HERDR_ENV" = 1
        echo herdr
    else if test -n "$TMUX"
        echo tmux
    else if test "$DEFAULT_MULTIPLEXER" = herdr
        echo herdr
    else
        echo tmux
    end
end
