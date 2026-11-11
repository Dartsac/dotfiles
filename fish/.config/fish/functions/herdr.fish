function herdr --description 'Open this directory in Herdr; pass explicit CLI commands through'
    # Only bare interactive launches select a directory. API callers, options,
    # named sessions and remote launches retain the real CLI's semantics.
    if test (count $argv) -gt 0; or not status is-interactive
        command herdr $argv
        return $status
    end
    python3 "$HOME/.config/herdr/scripts/project-picker.py" --attach -- (pwd -P)
end
