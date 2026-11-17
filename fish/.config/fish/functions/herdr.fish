function herdr --description 'Open this directory in Herdr; pass explicit CLI commands through'
    # Only bare interactive launches select a directory. API callers, options,
    # named sessions and remote launches retain the real CLI's semantics. So
    # does a bare launch over SSH, outside Herdr (the phone): it attaches, as
    # Herdr's own does, and opens no workspace for the folder SSH starts in.
    set -l over_ssh 0
    if set -q SSH_CONNECTION; and test "$HERDR_ENV" != 1
        set over_ssh 1
    end
    if test (count $argv) -gt 0; or not status is-interactive; or test $over_ssh = 1
        command herdr $argv
        return $status
    end
    python3 "$HOME/.config/herdr/scripts/project-picker.py" --attach -- (pwd -P)
end
