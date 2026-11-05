# Interactive conveniences only: defining these costs ~80 ms in every
# non-interactive `fish -c` (Neovim's system(), scripts).
if status is-interactive; and type -q eza
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
