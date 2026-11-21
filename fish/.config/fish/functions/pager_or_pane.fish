function pager_or_pane --argument-names direction --description 'Ctrl-j/k: move down or up in the completion pager, else to the pane below or above'
    # direction: down or up. In the pager, the completion moved to is written
    # into the command line, as Tab and Shift-Tab do.
    if commandline --paging-mode
        commandline -f $direction-line
        return
    end
    # Outside a multiplexer's pane, nothing: no multiplexer to move in.
    test "$HERDR_ENV" = 1; or set -q TMUX; or return
    switch (multiplexer)
        case tmux
            set -l flag -D
            test $direction = up; and set flag -U
            # The tmux function: pane-clarity routes the move (functions/tmux.fish).
            tmux select-pane -t $TMUX_PANE $flag
        case herdr
            # From this pane, as Neovim does, not from global focus. herdr's
            # reply, JSON, would land on the command line.
            herdr pane focus --direction $direction --pane $HERDR_PANE_ID >/dev/null
    end
end
