# dotfiles

## Install

```sh
./install                 # list the packages on offer
./install direnv eza      # stow them into your home directory
```

`./install` creates shared directories such as `~/.config` first, so stow
never links one whole into a package, stows each package with the flags it
needs, and names each dependency you have not installed, with an install
hint. It also names any file the tool would read instead of the package's. It
never installs software and never replaces a real file: when one is
in the way, it stops with stow's message. Owner packages (herdr, pi,
hammerspoon) need `--force`. Undo with `stow -D <package>`.

Each package declares its description, role, platforms and dependencies in
`<package>/README.package.json`; stow never links a package's top-level
`README.*`. `./install --help` describes the fields.

### Standalone check

`.tests/standalone.py` proves each package works alone: it copies this
working tree, runs `./install <package>` into an empty home directory with
only the package's declared dependencies on PATH, starts the tool, and fails
on any error. It also removes each dependency in turn and checks that
`./install` names it with its hint, and starts a tool that has optional
dependencies (Neovim) once more with only the required ones. The dependencies
must be installed where it runs.

```sh
python3 .tests/standalone.py        # every package it covers
python3 .tests/standalone.py eza    # one package
.tests/linux.sh                     # the same on Ubuntu, in Docker
```

GitHub Actions runs it on macOS and Ubuntu on every push
(`.github/workflows/standalone.yml`), with `./install`'s own tests
(`.tests/test_install.py`). `.tests/linux.sh` runs that Ubuntu job on a Mac:
the Ubuntu release the workflow names and the same dependencies
(`.tests/ubuntu-deps.sh`). Tool versions there differ from Homebrew's, so run
it before pushing a change that Linux could take differently.

A new package gets a `README.package.json`, a check in `.tests/standalone.py`
and its dependencies in the workflow and `.tests/ubuntu-deps.sh`; a test fails
until an offered package has its check.

Some tools read `~/Library/Application Support/<tool>` on macOS and ignore
`~/.config/<tool>`, whatever `XDG_CONFIG_HOME` says (eza does). Such a package
links that path to its `.config` directory and lists it under
`platform_paths` in its manifest, so `./install` stows it on macOS only. The
standalone check is what shows whether a tool needs this.

lazygit reads `~/.config/lazygit` on macOS too, but only while
`~/Library/Application Support/lazygit` holds no `config.yml`, and lazygit
creates an empty one there the first time it runs without a config. The
lazygit package lists that file under `overridden_by` in its manifest, so
`./install lazygit` names it when it exists. Move it away then; lazygit keeps
its state, such as `state.yml`, in that folder, so leave the rest.

## gnu stow naming convention

    1.	Root Directory: Your dotfiles directory contains subdirectories for each package (e.g., nvim, tmux).
    2.	Relative Paths: Files and directories within each package should mimic the structure of their intended target locations in the filesystem.
    3.	Target: `.stowrc` sets the target to your home directory, so `stow <package>` links into `~` wherever you cloned the repository. Pass --target to link elsewhere.
    4.	Only packages: everything else at the root is a file or a hidden directory (tests live in `.tests/`), so `stow */` links packages only.

| dotfile                               | gnu stow                                    |
| ------------------------------------- | ------------------------------------------- |
| ~/.config/nvim                        | nvim/.config/nvim                           |
| ~/.config/lazygit                     | lazygit/.config/lazygit                     |
| ~/.gitconfig                          | git/.gitconfig                              |

| Command                         | Effect                                                                            |
| ------------------------------- | --------------------------------------------------------------------------------- |
| stow tmux                       | Creates ~/.config/tmux symlink pointing to tmux/.config/tmux in your clone.       |
| stow -D tmux                    | Removes the symlink ~/.config/tmux.                                               |
| stow --target=/custom/path nvim | Creates symlinks for nvim package in /custom/path.                                |
| stow --simulate tmux            | Simulates creating symlinks for the tmux package without actually making changes. |
| stow --no-folding pi            | Links each file in pi/.pi/agent into ~/.pi/agent, keeping the directories real.   |

## Pi

`pi/` holds the Pi settings, extensions and theme template for the Personal
machine. Stow it with `--no-folding`, which `./install` passes for you (pi is
an owner package, hence `--force`):

```sh
./install --force pi    # or: stow --no-folding pi
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
node .tests/pi-extensions.mjs          # every test; add a name to narrow, e.g. focus
node .tests/pi-extensions.mjs --types  # type-check instead (needs tsc)
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
