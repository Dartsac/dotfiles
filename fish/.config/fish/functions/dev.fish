# ~/.config/fish/functions/dev.fish
# Neovim on top, a shell in the bottom 20%, in the multiplexer that applies here.
function dev
    switch (multiplexer)
        case herdr
            if test "$HERDR_ENV" = 1
                # Inside herdr: split this pane
                herdr pane split --current --direction down --ratio 0.8 --focus >/dev/null
                and herdr pane run $HERDR_PANE_ID 'nvim .' >/dev/null
            else
                # Open this directory's workspace, laying it out only if new
                set -l opened (python3 ~/.config/herdr/scripts/project-picker.py --default-session --json (pwd))
                or return
                set -l root_pane (printf '%s' $opened | jq -r '.root_pane_id // empty')
                if test -n "$root_pane"
                    herdr pane run $root_pane v >/dev/null
                    and herdr pane split $root_pane --direction down --ratio 0.8 --focus >/dev/null
                end
                herdr
            end
        case tmux
            if test -n "$TMUX"
                # Inside a tmux session: set up the panes
                tmux split-window -v -p 20
                set top_pane (tmux list-panes -F '#{pane_id} #{pane_top}' | sort -nk2 | head -n1 | awk '{print $1}')
                tmux send-keys -t $top_pane 'nvim .' C-m
            else
                # Create a new session with a good name
                set session_name (basename (pwd))
                tmux new-session -s $session_name -c (pwd) -n $session_name -A\; \
                    send-keys v C-m \; \
                    split-window -v -p 20 \;
            end
    end
end
