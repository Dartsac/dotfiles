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

`theme-sync` finds the package this way:

- If `DRACULA_PRO_DIR` is set, it uses that folder and looks nowhere else. To
  set it permanently in fish, run `set -Ux DRACULA_PRO_DIR /path/to/package`.
- Otherwise it uses the folder with the highest version number among the
  `dracula-pro-v*` folders in `~/Documents/Resources/Themes/Dracula Packages`.
- The folder must contain `design/palette.md`, `themes/ghostty` and
  `themes/vim/colors`. If one is missing, `theme-sync` names it, leaves the
  installed app themes alone, and fills templates with stand-in colors. It
  does not try an older version.

It installs the package's Ghostty and Neovim themes, writes the palette the
Hammerspoon dictation card reads, fills in the templates listed in
`theme-templates.txt`, and installs a git pre-commit hook that refuses commits
containing the theme's color values. Run it again after downloading a new
package, editing a template, or switching the Ghostty theme variant.
`theme-sync --check` reports what would change without writing.

To theme another app:

1. Write its config in this repository with color names in double braces, such
   as `{{orange}}` or `{{bgdark}}`. `theme-sync --names` lists the names.
2. Add a `template -> target` line to `theme-templates.txt`. The target must be
   outside this repository or ignored by git.
3. Run `theme-sync`.
