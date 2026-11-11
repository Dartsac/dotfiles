# dotfiles

## gnu stow naming convention

    1.	Root Directory: Your dotfiles directory contains subdirectories for each package (e.g., nvim, tmux).
    2.	Relative Paths: Files and directories within each package should mimic the structure of their intended target locations in the filesystem.
    3.	Target: Symlinks are created in the parent directory of the specified --target or the default (~).

| dotfile                               | gnu stow                                    |
| ------------------------------------- | ------------------------------------------- |
| ~/.config/nvim                        | nvim/.config/nvim                           |
| ~/Library/Application Support/lazygit | lazygit/Library/Application Support/lazygit |
| ~/.gitconfig                          | git/.gitconfig                              |

| Command                         | Effect                                                                            |
| ------------------------------- | --------------------------------------------------------------------------------- |
| stow tmux                       | Creates ~/.config/tmux symlink pointing to ~/dotfiles/tmux/.config/tmux.          |
| stow -D tmux                    | Removes the symlink ~/.config/tmux.                                               |
| stow --target=/custom/path nvim | Creates symlinks for nvim package in /custom/path.                                |
| stow --simulate tmux            | Simulates creating symlinks for the tmux package without actually making changes. |

## Dracula PRO theme

Dracula PRO is a paid theme, so its colors are not in this repository. Put the
downloaded package (v2.2 or newer) in
`~/Documents/Resources/Themes/Dracula Packages/dracula-pro-v<version>`, or set
`DRACULA_PRO_DIR` to its path, then run:

```sh
~/dotfiles/theme-sync
```

It installs the package's Ghostty and Neovim themes, writes the palette the
Hammerspoon dictation card reads, and writes herdr's `config.toml` from
`herdr/.config/herdr/config.base.toml`. Run it again after downloading a new
package, editing `config.base.toml`, or switching the Ghostty theme variant.
`theme-sync --check` reports what would change without writing.
