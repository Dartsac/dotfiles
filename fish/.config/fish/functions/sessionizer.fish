function sessionizer --description 'Open or switch to a project in the multiplexer that applies here'
    switch (multiplexer)
        case herdr
            # Inside herdr this focuses or creates the workspace; outside it
            # also starts the default session if needed and attaches to it.
            python3 ~/.config/herdr/scripts/project-picker.py --attach $argv
        case tmux
            # The tmux package's sessionizer, as prefix Ctrl-f runs it.
            set -l script ~/.config/tmux/scripts/sessionizer.py
            if test -x $script
                $script $argv
            else
                echo "sessionizer: stow the tmux package to pick a project ($script is missing)" >&2
                false
            end
    end
    set -l result $status
    commandline -f repaint 2>/dev/null
    return $result
end
