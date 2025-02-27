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

# Better SSH agent handling in tmux
if status is-interactive
    and not set -q TMUX
    eval (ssh-agent -c) >/dev/null
end

# Make tmux use fish by default
set -gx SHELL (which fish)

# TMUX
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
            send-keys v C-m \; \
            split-window -v -p 20 \;
    end
end

alias ke "tmux kill-server"
alias ks "tmux kill-session"
alias ls "tmux list-sessions -f '#s'"
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

set -gx PATH bin $PATH
set -gx PATH ~/bin $PATH
set -gx PATH ~/.local/bin $PATH

#Python@3.11
set -Ux fish_user_paths /opt/homebrew/opt/python@3.11/libexec/bin $fish_user_paths

# NodeJS
set -gx PATH node_modules/.bin $PATH

# Go
set -g GOPATH $HOME/go
set -gx PATH $GOPATH/bin $PATH

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
eval "$(perl -I$HOME/perl5/lib/perl5 -Mlocal::lib=$HOME/perl5)"

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
