# ~/.config/fish/functions/dev.fish
function dev
    # Check if in tmux already
    if test -n "$TMUX"
        # Inside a tmux session: set up the panes
        tmux split-window -v -p 20
        set top_pane (tmux list-panes -F '#{pane_id} #{pane_top}' | sort -nk2 | head -n1 | awk '{print $1}')
        tmux send-keys -t $top_pane 'nvim .' C-m
    else
        # Create a new session with a good name
        set session_name (basename (pwd))
        tmux new-session -s $session_name -c (pwd) -n $session_name -A\; \
            send-keys 'nvim .' C-m \; \
            split-window -v -p 20 \;
    end
end
