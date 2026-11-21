# The date the greeting last showed. It shows once a day: when this file holds
# another date, or there is no file yet (a new machine).
set last_run_file ~/.config/fish/fish_greeting_last_run

function fish_greeting
    set -l today (date +%Y-%m-%d)
    set -l last_run
    test -r $last_run_file; and read last_run <$last_run_file
    if test "$last_run" != $today
        echo "                       .,,uod8b8bou,,."
        echo "              ..,uod8bbbbbbbbbbbbbbbbrpft?l!i:."
        echo "         ,=m8bbbbbbbbbbbbbbbrpft?!||||||||||||||"
        echo "         !...:!tvbbbrpft||||||||||!!^^\"\"'   ||||"
        echo "         !.......:!?|||||!!^^\"\"'            ||||"
        echo "         !.........||||                     ||||"
        echo "         !.........||||  ##                 ||||"
        echo "         !.........||||                     ||||"
        echo "         !.........||||$(_greeting_hello 21)||||"
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
        echo $today >$last_run_file
    end
end

function _greeting_hello --argument-names width
    # "hello, <name>" centred in `width` columns: greeting_name from
    # config-local.fish, otherwise the user's login name.
    set -l name $USER
    set -q greeting_name; and set name $greeting_name
    set -l hello (string shorten --max $width -- "hello, $name")
    set -l length (string length --visible -- $hello)
    string pad --right --width $width -- (string pad --width (math "$length + floor(($width - $length) / 2)") -- $hello)
end

# Homebrew, from whichever prefix holds it (Apple Silicon, Intel Mac, Linux)
# or the one HOMEBREW_PREFIX names (set by a parent shell): the variables
# `brew shellenv` exports, set without starting brew, per shell rather than as
# universal variables. Unlike `brew shellenv`, PATH entries already present
# stay where they are: moving Homebrew to the front in a nested shell would
# put it ahead of a virtualenv or a project's own tools.
if not set -q HOMEBREW_PREFIX
    for prefix in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew
        if test -x $prefix/bin/brew
            set -gx HOMEBREW_PREFIX $prefix
            break
        end
    end
end
if set -q HOMEBREW_PREFIX
    set -q HOMEBREW_CELLAR; or set -gx HOMEBREW_CELLAR $HOMEBREW_PREFIX/Cellar
    if not set -q HOMEBREW_REPOSITORY
        # Intel Macs and Linux keep Homebrew's own repository in a subfolder.
        set -gx HOMEBREW_REPOSITORY $HOMEBREW_PREFIX
        test -d $HOMEBREW_PREFIX/Homebrew; and set HOMEBREW_REPOSITORY $HOMEBREW_PREFIX/Homebrew
    end
    fish_add_path --path $HOMEBREW_PREFIX/bin $HOMEBREW_PREFIX/sbin
    # An empty entry (a trailing colon) keeps info's own folders.
    set -q INFOPATH; or set -gx INFOPATH ''
    contains -- $HOMEBREW_PREFIX/share/info $INFOPATH
    or set -gx INFOPATH $HOMEBREW_PREFIX/share/info $INFOPATH
end
set -gx HOMEBREW_NO_ASK 1

# fish_add_path skips entries already present, so nested shells (tmux, Neovim)
# don't stack duplicates, and folders that don't exist. --path edits $PATH
# only, never the universal fish_user_paths.
fish_add_path --path ~/bin
fish_add_path --path ~/.local/bin

# prompt_pwd shortens each parent folder to one letter.
set -g fish_prompt_pwd_dir_length 1

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
# multiplexer.fish): the pane's own, else the Default multiplexer, else tmux.
# With none installed, `multiplexer` says so and fails: no case matches, so
# the shortcut does nothing and fails too (a switch that matches nothing
# keeps the status of its command substitution). A herdr workspace
# corresponds to a per-project tmux session, so ks closes the workspace.
# `dev` lives in functions/dev.fish.
function ke --description 'stop the multiplexer server and every pane in it; start empty next time'
    switch (multiplexer)
        case herdr
            # herdr would restore the layout on its next start; this forgets it.
            python3 ~/.config/herdr/scripts/stop-fresh.py
        case tmux
            tmux kill-server $argv
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
            tmux kill-session $argv
    end
end
# (not `ls`: that name is taken by the eza alias, and without eza it would
# turn `ls`, `la`, `ll` and `lla` into tmux commands)
function tls --description 'list sessions (herdr: workspaces)'
    switch (multiplexer)
        case herdr
            herdr workspace list | jq -r '.result.workspaces[].label'
        case tmux
            tmux list-sessions -f '#s' $argv
    end
end
function a --description 'attach to the multiplexer'
    switch (multiplexer)
        case herdr
            command herdr $argv
        case tmux
            tmux a $argv
    end
end
function d --description 'detach from the multiplexer'
    switch (multiplexer)
        case herdr
            # herdr has no detach command; only its client can detach.
            echo "d: detach from herdr with Ctrl-t d" >&2
            return 1
        case tmux
            tmux detach $argv
    end
end

# aliases
alias la "ls -A"
alias ll "ls -l"
alias lla "ll -A"
alias lg lazygit
alias g git

# eza in place of ls. Interactive conveniences only: defining these costs
# ~80 ms in every non-interactive `fish -c` (Neovim's system(), scripts).
if status is-interactive; and command -q eza
    # ld — lists only directories (no files)
    alias ld "eza -lD"
    # lf — lists only files (no directories)
    # (-f already excludes directories; a `| grep` here would receive $argv)
    alias lf "eza -lf --color=always"
    # lh — lists only hidden files (no directories)
    alias lh "eza -dl .* --group-directories-first"
    # ll — lists everything with directories first
    alias ll "eza -al --icons=always --group-directories-first"
    # ls — lists only files sorted by size
    alias ls "eza -alfr --icons=always --color=always --sort=size"
    # lt — lists everything sorted by time updated
    alias lt "eza -alr --sort=modified"
end

function v
    if test (count $argv) -eq 0
        nvim
    else
        env NVIM_NO_HARPOON=1 nvim $argv
    end
end

if command -q nvim
    alias vim nvim
    set -gx EDITOR nvim
end

bind \cf sessionizer

# Go and bun, where installed. Appended (after /usr/bin, Homebrew): anything
# `go install` or `bun install -g` drops there can't stand in for a system
# command. --move also re-orders shells that inherited the old order (open
# tmux panes).
if command -q go
    set -q GOPATH; or set -gx GOPATH $HOME/go
    fish_add_path --path --append --move $GOPATH/bin
end
if test -d ~/.bun
    set -gx BUN_INSTALL ~/.bun
    fish_add_path --path --append --move $BUN_INSTALL/bin
end

# NVM (nvm.fish, in functions/): once it has installed a Node
function __nvm_auto_use --on-variable PWD --description 'Run `nvm use` when entering a directory with .nvmrc'
    status --is-command-substitution; and return

    if test -f .nvmrc; and test -r .nvmrc; and test -d "$nvm_data"
        nvm use
    end
end

# Tide's prompt settings are universal variables. A machine that has none yet
# gets tide-theme.fish: Tide's Lean style in the free Dracula colors.
set -q tide_left_prompt_items
or source (dirname (status --current-filename))/tide-theme.fish

# This machine's own settings (config-local.example.fish shows some), kept
# out of git.
set LOCAL_CONFIG (dirname (status --current-filename))/config-local.fish
if test -f $LOCAL_CONFIG
    source $LOCAL_CONFIG
end

# Only absolute PATH entries: a relative one (bin, node_modules/.bin) is a
# different folder in every directory, so any project could stand in for a
# real command. Also drops ones inherited from an older shell or tmux server.
# A project's own tools: `use project_bins` in its .envrc (direnv/direnvrc).
set -gx PATH (string match -- '/*' $PATH)
command -qv direnv && direnv hook fish | source

# fzf started from this shell (zoxide's `zi`, a bare `fzf`): Tab and Shift-Tab
# move down and up, as Ctrl-j/k do. A machine that sets fzf's default options
# itself (FZF_DEFAULT_OPTS or FZF_DEFAULT_OPTS_FILE, here or in config-local.fish)
# keeps them. This repo's own pickers pass the same binding themselves.
if not set -q FZF_DEFAULT_OPTS; and not set -q FZF_DEFAULT_OPTS_FILE
    set -gx FZF_DEFAULT_OPTS '--bind=tab:down,btab:up'
end

# zoxide: `z <name>` jumps to a frequently used folder, `zi` picks one with fzf.
# (Replaces the jethrokuan/z plugin; its history was imported on 2026-11-05.)
if status is-interactive; and command -qv zoxide
    # zoxide copies fish's own cd. An older zoxide (Ubuntu's) reads it from
    # $__fish_data_dir, where fish 4.1 and newer no longer keep it, and
    # warns; this copies it from fish itself, as a newer zoxide does.
    if not functions -q __zoxide_cd_internal; and status list-files functions/cd.fish &>/dev/null
        status get-file functions/cd.fish | string replace --regex -- '^function cd\s' 'function __zoxide_cd_internal ' | source
    end
    zoxide init fish | source
    # `zo <name>`: open the matching folder in Finder, or the file manager on
    # Linux (z's old `zo` command)
    function zo --description 'Open a zoxide match in the file manager'
        set -l dir (zoxide query -- $argv); or return
        if test (uname) = Darwin
            open $dir
        else
            xdg-open $dir
        end
    end
end
