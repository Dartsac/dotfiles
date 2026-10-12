function tmux --wraps tmux --description 'tmux with transparent pane-clarity layout routing'
    set -l adapter "$HOME/.config/tmux/plugins/tmux-pane-clarity/bin/tmux"
    if test -x "$adapter"
        "$adapter" $argv
    else
        command tmux $argv
    end
end
