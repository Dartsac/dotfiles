function sessionizer --description 'Open or switch to a project in the multiplexer that applies here'
    switch (multiplexer)
        case herdr
            # Inside herdr this focuses or creates the workspace; outside it
            # also starts the default session if needed and attaches to it.
            python3 ~/.config/herdr/scripts/project-picker.py --attach $argv
        case tmux
            if command -q tmux-sessionizer.sh
                tmux-sessionizer.sh $argv
            else
                echo "sessionizer: tmux-sessionizer.sh is not on PATH" >&2
                false
            end
    end
    set -l result $status
    commandline -f repaint 2>/dev/null
    return $result
end
