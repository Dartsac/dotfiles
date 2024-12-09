function dev
    if test -n "$TMUX"
        # Inside a tmux session: split and configure panes
        tmux split-window -v -p 20
        set top_pane (tmux list-panes -F '#{pane_id} #{pane_top}' | sort -nk2 | head -n1 | awk '{print $1}')
        tmux send-keys -t $top_pane 'nvim .' C-m
    else
        # Run your exact tmux command
        set selected_name (basename (pwd))
        tmux new-session -s $selected_name -c (pwd) -n $selected_name -A\; \
            send-keys 'v' C-m \; \
            split-window -v -p 20 \;
    end
end
