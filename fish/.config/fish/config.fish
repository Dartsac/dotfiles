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

# Syntax-highlighting colors (moved from conf.d/fish_frozen_theme.fish, which
# fish 4.3 generated for the universal -> global migration)
set -g fish_color_autosuggestion 555
set -g fish_color_cancel --reverse
set -g fish_color_command blue
set -g fish_color_comment red
set -g fish_color_cwd green
set -g fish_color_cwd_root red
set -g fish_color_end green
set -g fish_color_error brred
set -g fish_color_escape brcyan
set -g fish_color_history_current --bold
set -g fish_color_host normal
set -g fish_color_host_remote yellow
set -g fish_color_match --background=brblue
set -g fish_color_normal normal
set -g fish_color_operator brcyan
set -g fish_color_param cyan
set -g fish_color_quote yellow
set -g fish_color_redirection cyan --bold
set -g fish_color_search_match white --background=brblack
set -g fish_color_selection white --bold --background=brblack
set -g fish_color_status red
set -g fish_color_user brgreen
set -g fish_color_valid_path --underline
set -g fish_pager_color_completion normal
set -g fish_pager_color_description B3A06D --italics
set -g fish_pager_color_prefix normal --bold --underline
set -g fish_pager_color_progress brwhite --background=cyan
set -g fish_pager_color_selected_background --reverse

# Improve tmux integration
set -g fish_escape_delay_ms 10

# Make tmux use fish by default
# `command -s` (not `status fish-path`): it gives the stable /opt/homebrew/bin
# link, not the versioned Cellar path that `brew upgrade fish` deletes.
set -gx SHELL (command -s fish)

# Use the default key bindings
set -g fish_key_bindings fish_default_key_bindings

# Multiplexer shortcuts act on the multiplexer that applies here (functions/
# multiplexer.fish): the pane's own, else the Default multiplexer. A herdr
# session corresponds to a tmux session per project, so ks closes the
# workspace. `dev` lives in functions/dev.fish.
function ke --description 'stop the multiplexer server and every pane in it'
    switch (multiplexer)
        case herdr
            herdr server stop
        case tmux
            tmux kill-server
    end
end
function ks --description 'close the current session (herdr: workspace)'
    switch (multiplexer)
        case herdr
            if not set -q HERDR_WORKSPACE_ID
                echo "ks: run inside a herdr pane" >&2
                return 1
            end
            herdr workspace close $HERDR_WORKSPACE_ID >/dev/null
        case tmux
            tmux kill-session
    end
end
# (not `ls`: that name is taken by the eza alias on macOS, and on Linux it
# would turn `ls`, `la`, `ll` and `lla` into tmux commands)
function tls --description 'list sessions (herdr: workspaces)'
    switch (multiplexer)
        case herdr
            herdr workspace list | jq -r '.result.workspaces[].label'
        case tmux
            tmux list-sessions -f '#s'
    end
end
function a --description 'attach to the multiplexer'
    switch (multiplexer)
        case herdr
            herdr
        case tmux
            tmux a
    end
end
function d --description 'detach from the multiplexer'
    switch (multiplexer)
        case herdr
            # herdr has no detach command; only its client can detach.
            echo "d: detach from herdr with Ctrl-t d" >&2
            return 1
        case tmux
            tmux detach
    end
end

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

bind \cf sessionizer

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
function __nvm_auto_use --on-variable PWD --description 'Run `nvm use` when entering a directory with .nvmrc'
    status --is-command-substitution; and return

    if test -f .nvmrc; and test -r .nvmrc
        nvm use
    end
end

# Per-OS config; only config-osx.fish exists so far, so skip missing ones
# instead of erroring on every Linux/other start.
switch (uname)
    case Darwin
        set os_config config-osx.fish
    case Linux
        set os_config config-linux.fish
    case '*'
        set os_config config-windows.fish
end
set os_config (dirname (status --current-filename))/$os_config
test -f $os_config && source $os_config
set -e os_config

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

# zoxide: `z <name>` jumps to a frequently used folder, `zi` picks one with fzf.
# (Replaces the jethrokuan/z plugin; its history was imported on 2026-11-05.)
if status is-interactive; and command -qv zoxide
    zoxide init fish | source
    # `zo <name>`: open the matching folder in Finder (z's old `zo` command)
    function zo --description 'Open a zoxide match in Finder'
        set -l dir (zoxide query -- $argv); and open $dir
    end
end
