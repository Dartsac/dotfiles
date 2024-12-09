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
