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
| stow --no-folding pi            | Links each file in pi/.pi/agent into ~/.pi/agent, keeping the directories real.   |

## Pi

`pi/` holds the Pi settings, extensions and theme template for the Personal
machine. Stow it with `--no-folding`:

```sh
stow --no-folding pi
```

Without `--no-folding`, stow may link a whole directory such as
`~/.pi/agent/extensions`, and Pi would then write runtime files into this
repository. Run it again after adding a file to the package.

On a new machine, also:

- Run `theme-sync`. It writes `~/.pi/agent/themes/dracula-pro.json` from the
  template beside it.
- Copy `~/.pi/agent/local-packages/` from a machine that has it.
  `settings.json` loads three customized packages from there. They are local
  Git repositories and are not part of this one.
- Log in to Pi. Credentials (`auth.json`), trusted folders (`trust.json`) and
  sessions stay on each machine.

Pi rewrites `settings.json` itself, for example when you change the model, so
expect small diffs there.

Extension tests sit beside each extension as `*.test.ts`. Run them against the
installed Pi with:

```sh
node tests/pi-extensions.mjs          # every test; add a name to narrow, e.g. focus
node tests/pi-extensions.mjs --types  # type-check instead (needs tsc)
```

The pre-commit hook runs the tests of each extension directory with staged
changes. An extension with tests needs its own directory (`name/index.ts`),
because Pi loads every top-level `extensions/*.ts` file as an extension.

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
containing the theme's color values (the same hook runs the Pi extension
tests and `theme-sync`'s own tests). Run it again after downloading a new
package, editing a template, or switching the Ghostty theme variant.
`theme-sync --check` reports what would change without writing.
`theme-sync --check-history` fails if any commit holds one of the theme's
color values.

On macOS it also generates Herdr's state-colored character fonts into
`~/Library/Fonts/HerdrSpritesPixel-*.ttf`. The source fonts in
`herdr/.config/herdr/faces/fonts/` contain only outlines; the generated ones
contain palette colors and never belong in git. This step needs Python
`fonttools`, or `uv` to supply it. Ghostty maps the sprite codepoints to that
font, so the pixel-aligned characters keep state colors beside text in the
workspace's color: a space and its agents share one distinct Dracula PRO hue.
The font's name ends in a tag that changes with the drawings, because a
running Ghostty does not reload a changed font under a name it has loaded;
see `herdr/.config/herdr/README.md` before changing a sprite.

To theme another app:

1. Write its config in this repository with color names in double braces, such
   as `{{orange}}` or `{{bgdark}}`. `theme-sync --names` lists the names. For a
   shade between two colors, `{{comment+foreground:40}}` is `comment` with 40%
   `foreground` mixed in.
2. Add a `template -> target` line to `theme-templates.txt`. The target must be
   outside this repository or ignored by git.
3. Run `theme-sync`.
