# Set a variable to store the path to the file containing the last run date
set last_run_file ~/.config/fish/fish_greeting_last_run

function fish_greeting
    # Check if the file containing the last run date exists
    if test -e $last_run_file
        # Read the last run date from the file
        set -g last_run (cat $last_run_file)
    else
        # Set the last run date to today's date if the file doesn't exist
        set -g last_run (date +%Y-%m-%d)
    end
    # Check if the current date is the same as the last time the function was run
    if test (date +%Y-%m-%d) != $last_run
        echo "                       .,,uod8b8bou,,."
        echo "              ..,uod8bbbbbbbbbbbbbbbbrpft?l!i:."
        echo "         ,=m8bbbbbbbbbbbbbbbrpft?!||||||||||||||"
        echo "         !...:!tvbbbrpft||||||||||!!^^\"\"'   ||||"
        echo "         !.......:!?|||||!!^^\"\"'            ||||"
        echo "         !.........||||                     ||||"
        echo "         !.........||||  ##                 ||||"
        echo "         !.........||||                     ||||"
        echo "         !.........||||    hello, isaac     ||||"
        echo "         !.........||||                     ||||"
        echo "         !.........||||                     ||||"
        echo "         `.........||||                    ,||||"
        echo "          .;.......||||               _.-!!|||||"
        echo "   .,uodwbbbbb.....||||       _.-!!|||||||||!:'"
        echo "!ybbbbbbbbbbbbbbb..!|||:..-!!|||||||!iof68bbbbbb...."
        echo "!..ybbbbbbbbbbbbbbb!!||||||||!iof68bbbbbbrpft?!::   `."
        echo "!....ybbbbbbbbbbbbbbbaaitf68bbbbbbrpft?!:::::::::     `."
        echo "!......ybbbbbbbbbbbbbbbbbbrpft?!::::::;:!^\"`;:::       `."
        echo "!........ybbbbbbbbbbrpft?!::::::::::^''...::::::;         ibbbo."
        echo "`..........ybrpft?!::::::::::::::::::::::::;iof68bo.      wbbbbbo."
        echo "  `..........:::::::::::::::::::::::;iof688888888888b.     `ybbbp^'"
        echo "    `........::::::::::::::::;iof688888888888888888888b.     `"
        echo "      `......:::::::::;iof688888888888888888888888888b."
        echo "        `....:::;iof688888888888888888888888888888899ft!"
        # echo "          `..::!8888888888888888888888888888888899ft|!^\""
        # echo "            `' !!988888888888888888888888899ft|!^\""
        # echo "                `!!8888888888888888899ft|!^\""
        # echo "                  `!988888888899ft|!^\""
        # echo "                    `!9899ft|!^\""
        # Update the last run date to the current date
        echo (date +%Y-%m-%d) >$last_run_file
    end
end

# theme
set -g theme_color_scheme terminal-dark
set -g fish_prompt_pwd_dir_length 1
set -g theme_display_user yes
set -g theme_hide_hostname no
set -g theme_hostname always

# Improve tmux integration
set -g fish_escape_delay_ms 10

# Make tmux use fish by default
# `command -s` (not `status fish-path`): it gives the stable /opt/homebrew/bin
# link, not the versioned Cellar path that `brew upgrade fish` deletes.
set -gx SHELL (command -s fish)

# Use the default key bindings
set -g fish_key_bindings fish_default_key_bindings

# TMUX (`dev` lives in functions/dev.fish)
alias ke "tmux kill-server"
alias ks "tmux kill-session"
# (not `ls`: that name is taken by the eza alias on macOS, and on Linux it
# would turn `ls`, `la`, `ll` and `lla` into tmux commands)
alias tls "tmux list-sessions -f '#s'"
alias a "tmux a"
alias d "tmux detach"

# aliases
alias la "ls -A"
alias ll "ls -l"
alias lla "ll -A"
alias lg lazygit
alias g git

function v
    if test (count $argv) -eq 0
        nvim
    else
        env NVIM_NO_HARPOON=1 nvim $argv
    end
end

command -qv nvim && alias vim nvim

bind \cf "tmux-sessionizer.sh"

set -gx EDITOR nvim

# fish_add_path skips entries already present, so nested shells (tmux, Neovim)
# don't stack duplicates. --path edits $PATH only, never the universal
# fish_user_paths.
fish_add_path --path ~/bin
fish_add_path --path ~/.local/bin

# homebrew (exported per shell: a universal variable is rewritten to disk on
# every start)
set -gx HOMEBREW_NO_ASK 1

#Python@3.11 (universal, so it only needs setting once; rewriting it on every
# start costs ~30 ms)
contains /opt/homebrew/opt/python@3.11/libexec/bin $fish_user_paths
or set -Ux fish_user_paths /opt/homebrew/opt/python@3.11/libexec/bin $fish_user_paths

# Go
set -gx GOPATH $HOME/go
# Appended (after /usr/bin, Homebrew): anything `go install` drops here can't
# stand in for a system command. --move also re-orders shells that inherited
# the old order (open tmux panes).
fish_add_path --path --append --move $GOPATH/bin

# NVM
function __check_rvm --on-variable PWD --description 'Do nvm stuff'
    status --is-command-substitution; and return

    if test -f .nvmrc; and test -r .nvmrc
        nvm use
    else
    end
end

switch (uname)
    case Darwin
        source (dirname (status --current-filename))/config-osx.fish
    case Linux
        source (dirname (status --current-filename))/config-linux.fish
    case '*'
        source (dirname (status --current-filename))/config-windows.fish
end

set LOCAL_CONFIG (dirname (status --current-filename))/config-local.fish
if test -f $LOCAL_CONFIG
    source $LOCAL_CONFIG
end
# local::lib only exports variables; a shell started from another shell (Neovim,
# tmux, scripts) inherits them, so skip the ~13 ms perl start there.
if not set -q PERL_LOCAL_LIB_ROOT
    eval "$(perl -I$HOME/perl5/lib/perl5 -Mlocal::lib=$HOME/perl5)"
end

# bun
set --export BUN_INSTALL "$HOME/.bun"
fish_add_path --path --append --move $BUN_INSTALL/bin  # same reason as Go

# Only absolute PATH entries: a relative one (bin, node_modules/.bin) is a
# different folder in every directory, so any project could stand in for a
# real command. Also drops ones inherited from an older shell or tmux server.
# A project's own tools: `use project_bins` in its .envrc (direnv/direnvrc).
set -gx PATH (string match -- '/*' $PATH)
command -qv direnv && direnv hook fish | source
