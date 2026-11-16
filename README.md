# dotfiles

A terminal setup built around fish, Neovim, tmux and Ghostty, in the free
Dracula theme. Each package on offer works alone: take the ones you want, and
each starts cleanly on a fresh machine with only its own dependencies
installed.

## Quick start

You need git, Python 3 and [GNU Stow](https://www.gnu.org/software/stow/)
(`brew install stow`, or `sudo apt install stow`). Clone the repository into
any folder:

```sh
git clone https://github.com/Dartsac/dotfiles.git ~/src/dotfiles
cd ~/src/dotfiles
./install               # list the packages on offer
./install fish tmux     # stow them into your home directory
```

`./install` creates shared directories such as `~/.config` first, so stow
never links one whole into a package, stows each package with the flags it
needs, and names each dependency you have not installed, with an install
hint. It also names any file the tool would read instead of the package's. It
never installs software and never replaces a real file: when one is
in the way, it stops with stow's message. `./install --help` says more.

Then start the tool. Each package sets itself up on first start: Neovim
installs its plugins, tmux clones its plugin manager and plugins, and fish
applies its Tide prompt.

To uninstall a package, run `stow -D <package>` from the clone. It removes
the package's links and leaves the folders `./install` created.

Plain `stow <package>` from the clone works too: `.stowrc` sets the target to
your home directory wherever you cloned. Create `~/.config` first if it does
not exist, or stow links the whole of it into the package. Stow karabiner
with `--no-folding`, and eza on Linux with `./install`, which leaves out its
macOS-only `Library` folder.

## Packages

macOS is the primary platform: the owner uses it every day. The core packages
(fish, nvim, tmux, lazygit, direnv, eza and ghostty) are also promised on
Linux. On every push, GitHub Actions stows each package on offer alone and
checks that it works, on macOS and, for the core packages, on Ubuntu.

| Package                 | What it configures                                                                              | Platforms    | Needs                 | Optional dependencies             |
| ----------------------- | ----------------------------------------------------------------------------------------------- | ------------ | --------------------- | --------------------------------- |
| `fish`                  | Tide prompt in Dracula colors, Homebrew on PATH, eza aliases, multiplexer shortcuts             | macOS, Linux | `fish`                | `tmux`, `eza`, `zoxide`, `direnv` |
| `nvim`                  | Neovim: free Dracula theme, LSP, Telescope search, Markdown and Obsidian notes                  | macOS, Linux | `nvim`, `git`         | `rg`, `curl`, `tree-sitter`, `cc` |
| `tmux`                  | Free Dracula status line, Neovim-aware pane keys, session save and restore, Ctrl-f projects     | macOS, Linux | `tmux`, `git`, `python3` | `fzf`                         |
| `lazygit`               | Ctrl-Space selects, the mouse stays with the terminal, white text                               | macOS, Linux | `lazygit`, `git`      | —                                 |
| `direnv`                | `use project_bins`: a project's own bin and node_modules/.bin folders on PATH                   | macOS, Linux | `direnv`              | —                                 |
| `eza`                   | eza's theme: file icons, such as a document icon for PlantUML files                             | macOS, Linux | `eza`                 | —                                 |
| `ghostty`               | Free Dracula theme, Hack Nerd Font, a translucent window, macOS-style keys                      | macOS, Linux | `ghostty`             | Hack Nerd Font Mono               |
| `karabiner` (optional)  | Karabiner-Elements rules: Ctrl+[ to Escape, Ctrl+Backspace deletes a word                       | macOS        | `karabiner_cli`       | —                                 |

Packages never require each other: one uses another's tool when it is
installed. fish's multiplexer shortcuts use tmux, and without it say quietly
that no multiplexer is installed. For each dependency you lack, `./install`
prints how to install it; for an optional one, also what it adds. Some need
a version newer than a distribution may ship (Neovim 0.12, tmux 3.2, fish 4),
and the hint says so.

Each package declares its description, role, platforms and dependencies in
`<package>/README.package.json`, which `./install` reads; a test keeps this
table's platforms and dependencies in step with them.

### karabiner is optional

karabiner is optional, and macOS only. It ships rules, not a profile:
`./install karabiner` (or `stow --no-folding karabiner`) links them into
`~/.config/karabiner/assets/complex_modifications`, and Karabiner-Elements
offers them under Settings, Complex Modifications, Add predefined rule.
`~/.config/karabiner` stays a folder of your own, so the profile Karabiner
writes there, `karabiner.json`, stays yours, and one you already have stays
as it was.

### lazygit on macOS

lazygit reads `~/.config/lazygit` on macOS too, but only while
`~/Library/Application Support/lazygit` holds no `config.yml`, and lazygit
creates an empty one there the first time it runs without a config.
`./install lazygit` names that file when it exists. Move it away then;
lazygit keeps its state, such as `state.yml`, in that folder, so leave the
rest.

### fish

`FISH.md` covers the fish package: its one directory link, the Tide prompt's
settings, the vendored plugins, and a machine that used this config before it
had a local override.

## Local overrides

Your own settings go in a local override: a file beside the tracked config
that the tool reads after it, so a setting there wins. Copy the example
beside it and uncomment what you need:

| Package   | Local override                           | Example beside it                                         |
| --------- | ---------------------------------------- | --------------------------------------------------------- |
| `fish`    | `~/.config/fish/config-local.fish`       | `fish/.config/fish/config-local.example.fish`             |
| `nvim`    | `~/.config/nvim/lua/config/local.lua`    | `nvim/.config/nvim/lua/config/local.example.lua`          |
| `tmux`    | `~/.config/tmux/tmux.local.conf`         | `tmux/.config/tmux/tmux.local.example.conf`               |
| `tmux`    | `~/.config/tmux/projects.local.txt`      | `tmux/.config/tmux/projects.local.example.txt`            |
| `ghostty` | `~/.config/ghostty/config.local.ghostty` | `ghostty/.config/ghostty/config.local.example.ghostty`    |

They hold what is one person's or one machine's: the name fish's greeting says
hello to, the default multiplexer, a pinned Python, Neovim's notes vault and
Python, the projects tmux's sessionizer (prefix Ctrl-f) offers, extra keys.
Each example says what goes in it.

Overrides are never committed. `~/.config/<tool>` is a link into your clone,
so an override sits in the clone beside the tracked files, and `.gitignore`
keeps it out of git: every `*.local.*` file except the examples, and fish's
and Neovim's by name. lazygit, direnv, eza and karabiner have no override:
change their files in your clone.

## Owner packages

These are the owner's own: kept here for the owner's machines, not offered.
They rely on the owner's agent tools, local Pi packages and herdr plugins,
which an adopter cannot reproduce. `./install` lists them apart and refuses
them without `--force`.

| Package       | What it is                                                     | Platforms |
| ------------- | -------------------------------------------------------------- | --------- |
| `herdr`       | herdr, the owner's agent-aware multiplexer                     | macOS     |
| `pi`          | Pi, the owner's coding agent: settings, extensions and theme   | macOS     |
| `hammerspoon` | Hammerspoon: the dictation card, and away alerts for herdr     | macOS     |

### Dictation

The hammerspoon package holds a dictation feature you can copy. Tap a spare
key to start recording and again to stop. A small card at the top of the
screen shows the microphone's level and where the text will go: the app and
window, or NO TEXT FIELD. When you stop, the recording goes to Deepgram's
Nova-3 model, with long pauses shortened, and the transcript is pasted into
the focused text field; the clipboard is restored afterwards. With no text
field focused, nothing is sent: the recording stays on disk, and Shift with
the same key transcribes it to the clipboard. A minute of silence stops it.

It needs:

- macOS and [Hammerspoon](https://www.hammerspoon.org), with the Microphone
  and Accessibility permissions. The feature is `dictation.lua`,
  `dictation_target.lua`, `dictation_theme.lua` and `deepgram_stream.py`,
  started by `Dictation = require("dictation")`: the files find each other in
  whichever folder Hammerspoon reads its config from.
- A key that sends F18. Karabiner-Elements can map a spare one. `CONFIG` at
  the top of `hammerspoon/.config/hammerspoon/dictation.lua` changes the key,
  hold-to-talk, the language and words to favour.
- A Python virtual environment at `~/.dictation-venv` with `sounddevice`
  installed, which records the microphone
  (`hammerspoon/.config/hammerspoon/deepgram_stream.py`).
- A Deepgram API key in `~/.config/deepgram/api_key`. Deepgram charges for
  transcription.

The card takes Dracula PRO's colors when `theme-sync` has written them, and
its own otherwise.

## Owner setup

How the owner's machines are set up. An adopter needs none of this.

The owner works on two Macs, and the clone is at `~/dotfiles` on both, which
owner packages assume. The Personal machine, where agents are allowed, stows
every package, owner packages with `--force`:

```sh
./install fish nvim tmux lazygit direnv eza ghostty karabiner
./install --force herdr pi hammerspoon
```

The Work machine allows no AI tools: Pi is not there, and tmux, not herdr, is
its multiplexer.

Each machine has its local overrides, made from the examples: the greeting's
name, Perl's `local::lib`, the notes vault, Neovim's automatic
`lazy-lock.json` commit, and the projects list that tmux's sessionizer (and
herdr's project picker, where herdr is) offers. Only the Personal machine's
overrides name herdr as the default multiplexer and give Ghostty the Command+M
chord for Pi's model picker. On the Work machine the overrides are written by
hand. Karabiner's profile, with the machine's device, stays on each machine.
Hammerspoon reads `~/.config/hammerspoon` because its `MJConfigFile` setting
points there; the first lines of `hammerspoon/.config/hammerspoon/init.lua`
give the command. Then `theme-sync` puts Dracula PRO over the free theme.

### Dracula PRO and theme-sync

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
  `themes/vim/colors`. If one is missing, `theme-sync` names it and does not
  try an older version. The free Dracula theme then stays: it writes no app
  theme and no local override, and fills templates with the free theme's
  colors. What an earlier run left stays, and `theme-sync` names it: see
  "Back to the free theme" below.

It installs the package's Ghostty and Neovim themes, writes the palette the
Hammerspoon dictation card reads, fills in the templates listed in
`theme-templates.txt`, and installs a git pre-commit hook that refuses commits
containing the theme's color values (the same hook runs the Pi extension
tests and `theme-sync`'s own tests, and lints staged Python: see Lint). Run it again after downloading a new
package, editing a template, or switching the Ghostty theme variant.

The tracked configs of Ghostty, tmux and fish's Tide prompt use the free
Dracula theme. `theme-sync` puts Dracula PRO over it in each one's local
override, in a block of its own after the file's opening comment:

| Local override                            | Block                                                     |
| ----------------------------------------- | --------------------------------------------------------- |
| `~/.config/ghostty/config.local.ghostty`  | `theme = Dracula-Pro`, the variant                        |
| `~/.config/tmux/tmux.local.conf`          | tmux's colors, from `dracula-pro.conf.template`           |
| `~/.config/fish/config-local.fish`        | Tide's colors, from `tide-dracula-pro.fish.template`      |

Each run rewrites the block and keeps every other line, so a setting after
the block wins over it. A package that is not stowed is left alone. To switch
variants, change the block's `theme =` line, or add one after the block, then
run `theme-sync` and reload each app. theme-sync and Neovim take the variant
from Ghostty's last `theme =` line.
`theme-sync --check` reports what would change without writing.
`theme-sync --check-history` fails if any commit holds one of the theme's
color values.

On macOS it also generates Herdr's state-colored character fonts into
`~/Library/Fonts/HerdrSpritesPixel-*.ttf`. The source fonts in
`herdr/.config/herdr/faces/fonts/` contain only outlines; the generated ones
contain palette colors and never belong in git. This step needs Python
`fonttools`, or `uv` to supply it. Ghostty's local override maps the sprite
codepoints to that font (`config.local.example.ghostty` shows the line), so
the pixel-aligned characters keep state colors beside text in the workspace's
color: a space and its agents share one distinct Dracula PRO hue.
The font's name ends in a tag that changes with the drawings, because a
running Ghostty does not reload a changed font under a name it has loaded.

To theme another app:

1. Write its config in this repository with color names in double braces, such
   as `{{orange}}` or `{{bgdark}}`. `theme-sync --names` lists the names. For a
   shade between two colors, `{{comment+foreground:40}}` is `comment` with 40%
   `foreground` mixed in.
2. Add a `template -> target` line to `theme-templates.txt`. The target must be
   outside this repository or ignored by git. For an offered package, whose
   tracked config carries the free theme, add `template >> local override`
   instead: the template holds only the settings Dracula PRO changes.
3. Run `theme-sync`.

#### Back to the free theme

`theme-sync` never takes Dracula PRO out again. Run without a theme package,
it names what an earlier run left that still shows it. To go back (a later
run with a theme package writes it all again):

- Ghostty: delete the block in `config.local.ghostty`, and any
  `theme = Dracula-…` line of your own there. Reload.
- tmux: delete the block in `tmux.local.conf`. Reload with prefix r.
- fish: delete the block in `config-local.fish`. New shells then show Tide's
  own colors again. Where those are not the free theme's (a machine that had
  Dracula PRO before `theme-sync` wrote the block, or that ran
  `tide configure`), `source ~/.config/fish/tide-theme.fish` sets them all to
  the free theme's.
- Neovim: delete `~/.local/share/nvim/site/pack/themes/start/dracula-pro`.
  While that folder is there Neovim uses Dracula PRO, whatever Ghostty names.

Tried on fresh machines with a made-up theme package: after each step the
tool showed the free theme (Ghostty's background, tmux's pane borders and
current window after a reload and after a restart, Tide's prompt character,
Neovim's colorscheme), and `theme-sync` named nothing left. With only
Ghostty's block deleted, Neovim stayed on Dracula PRO until its folder went.

### Pi

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

## Working on this repository

### Package layout

A package is a folder that mirrors where its files go in your home directory:

| In your home directory     | In the repository               |
| -------------------------- | ------------------------------- |
| `~/.config/nvim`           | `nvim/.config/nvim`             |
| `~/.config/lazygit`        | `lazygit/.config/lazygit`       |
| `~/.pi/agent/settings.json`| `pi/.pi/agent/settings.json`    |

Everything else at the root is a file or a hidden directory (tests live in
`.tests/`), so `stow */` links packages only. `stow --simulate <package>`
shows what stow would do without doing it; pass `--target` to link somewhere
other than your home directory.

`./install --help` describes the fields of `README.package.json`. A new
package gets one, a check in `.tests/standalone.py`, its dependencies in
`.github/workflows/standalone.yml` and `.tests/ubuntu-deps.sh`, and a row in
the catalog above; a test fails until an offered package has its check and
its row.

Some tools read `~/Library/Application Support/<tool>` on macOS and ignore
`~/.config/<tool>`, whatever `XDG_CONFIG_HOME` says (eza does). Such a package
links that path to its `.config` directory and lists it under
`platform_paths` in its manifest, so `./install` stows it on macOS only. The
standalone check is what shows whether a tool needs this. A file the tool
reads instead of the package's, as lazygit's on macOS, goes under
`overridden_by`.

### Standalone check

`.tests/standalone.py` proves each package works alone: it copies this
working tree, runs `./install <package>` into an empty home directory with
only the package's declared dependencies on PATH, starts the tool, and fails
on any error. It also removes each dependency in turn and checks that
`./install` names it with its hint, and starts a tool that has optional
dependencies once more with only the required ones. For Ghostty, tmux, fish
and Neovim it then runs `theme-sync` with a made-up Dracula PRO package
(`.tests/synthetic_theme.py`) and checks that the tool shows its colors
and still keeps the local override's own settings. The dependencies must be
installed where it runs: a font in your own font folder (`~/Library/Fonts`,
`~/.local/share/fonts`), since one installed for every user cannot be hidden.
Nor can a command that an app keeps in a folder of its own, as `Ghostty.app`
keeps `ghostty` on macOS: the check skips removing that one, and says so
under the package's `ok`. It never starts Karabiner, and says so under the
package's `ok`: `karabiner_cli` validates the rules instead.

```sh
python3 .tests/standalone.py        # every package it covers
python3 .tests/standalone.py eza    # one package
.tests/linux.sh                     # the same on Ubuntu, in Docker
.tests/all.sh                       # every suite this checkout holds
```

`.tests/all.sh` runs the lint, the tests below (also on a bare PATH with the
system's Python, as a commit from a GUI git client runs them), this check, and
each package's own tests where a checkout has them. It names every suite it
skips; `.tests/all.sh nvim` runs the suites with that word in their name.

GitHub Actions runs it on macOS and Ubuntu on every push
(`.github/workflows/standalone.yml`), with `./install`'s own tests and this
README's catalog (`.tests/test_install.py`), `theme-sync`'s and its pre-commit hook's
(`.tests/test_theme_sync.py`) and the check's (`.tests/test_standalone.py`:
git on its machines never reaches your credentials); the macOS job runs those
tests once more on a bare PATH.
`.tests/linux.sh` runs that Ubuntu job on a Mac: the Ubuntu
release the workflow names and the same dependencies
(`.tests/ubuntu-deps.sh`). Tool versions there differ from Homebrew's, so run
it before pushing a change that Linux could take differently.

### Lint

The repository's Python passes `ruff check`. `ruff.toml` has the rules: names
that are unused or undefined, and syntax that Python 3.9, macOS's own, cannot
read. GitHub Actions runs it on every push (`.github/workflows/lint.yml`). The
pre-commit hook runs it on the staged files where ruff is installed
(`brew install ruff`), and lets the commit through where it is not. The hook's
tests run in both workflows: with ruff in `lint.yml`, without it in
`standalone.yml`.

Herdr's own Python tests stay out of git, so neither workflow sees them. When
a Herdr file is staged the hook checks them itself, before it runs them: with
ruff, and by loading each with `/usr/bin/python3`, which fails on a module
that Python 3.9 does not have.

## License

MIT: see `LICENSE`.
