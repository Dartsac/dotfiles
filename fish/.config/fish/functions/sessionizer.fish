function sessionizer --description 'Open or switch to a project in the multiplexer that applies here'
    switch (multiplexer)
        case herdr
            # Inside herdr this focuses or creates the workspace; outside it
            # also starts the default session if needed and attaches to it.
            python3 ~/.config/herdr/scripts/project-picker.py --attach $argv
        case tmux
            tmux-sessionizer.sh $argv
    end
    commandline -f repaint 2>/dev/null
end
