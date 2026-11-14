# Fish directory symlink

The intended installation is one directory symlink:

```text
~/.config/fish -> ~/dotfiles/fish/.config/fish
```

From `~/dotfiles`, `stow fish` creates this link when `~/.config/fish` does
not already exist. If it exists as a real directory, Stow can instead create
individual file links inside it. Re-running Stow alone does not migrate a
mixed directory containing local files.

On a new machine, the first start needs nothing else. Homebrew's tools are on
PATH wherever Homebrew is installed. Tide's prompt settings are universal
variables in `fish_variables`; while there are none, `config.fish` applies
`tide-theme.fish` (Tide's Lean style in the free Dracula colors), and
`tide configure` replaces them. This machine's own values (the greeting's
name, the Default multiplexer, a pinned Python, Perl's `local::lib`) go in
`config-local.fish`, which `config.fish` sources last.

## A machine that used this config before it had a local override

`config.fish` no longer sets up Perl's `local::lib` or the pinned Python.
After pulling, copy `config-local.example.fish` to `config-local.fish` (or
add to the one that is there) and uncomment the lines that machine needs.
Until then Perl modules in `~/perl5` are not found.

That setup also kept Homebrew, the pinned Python and other folders (such as
Homebrew's openjdk) in the universal variables `PATH` and `fish_user_paths`,
where they outlive the config that put them there. Nothing needs them now,
and clearing them is optional. To clear them:

1. List them: `set -S fish_user_paths; set -S -U PATH`. Add each folder you
   still want to `config-local.fish` with `fish_add_path --path`.
2. Expect a new order: `~/bin` and `~/.local/bin` then come before Homebrew,
   so a command in one of them wins over Homebrew's command of the same name.
3. Run `set -e -U PATH; set -e -U fish_user_paths` once, then restart the
   fish shells that are open: a shell started outside a multiplexer loses
   those folders from its PATH the moment the variables go.

## Plugins

Fisher, Tide and nvm.fish are tracked in this package (`fish_plugins` lists
them), so they need no install. Fisher keeps its record of what it installed
in universal variables, which a new machine does not have. There,
`fisher update` refuses to install over the tracked files, changes nothing in
the prompt, and deletes `fish_plugins`; restore it with
`git checkout fish/.config/fish/fish_plugins`. Update the plugins on a machine
whose fisher installed them, and commit the result.

## Migrating an existing installation

1. Back up `~/.config/fish` outside the repository, preserving symlinks.
2. Check that every existing symlink points to its corresponding file in
   `~/dotfiles/fish/.config/fish`. Investigate broken or unexpected links.
3. Copy real local files into the corresponding package directories. Do not
   overwrite different files. Preserve permissions and verify the copies.
4. Keep machine-local files ignored by Git. The repository ignores
   `config-local.fish` (the local override; `config-local.example.fish`
   shows its shape), `fish_variables`, `fish_greeting_last_run`, the local
   Fabric and Copilot completions, and the generated private Tide theme.
   New local files require their own ignore rules. Git ignore rules do not
   prevent Stow from linking files present on a machine.
5. Move the old directory outside `~/.config`, then run:

   ```sh
   cd ~/dotfiles
   stow --target="$HOME" fish
   ```

6. Check `~/.config/fish` is a directory symlink. Start a fresh Fish shell,
   enter `~/.config/fish`, and check `git rev-parse --show-toplevel`.
7. Reopen the Fish project in Neovim. Check Telescope can find `config.fish`
   and Harpoon can add and select it. Existing shells/editors can retain the
   old directory as their working directory; re-enter the new path or restart
   them. Harpoon lists are project-specific, so existing marks may need to be
   added again.

Local files now physically live inside the repository but are not committed.
Do not force-add generated files or private theme values. New shared config
files appear immediately through the directory link, but still require
`git add` and a commit to be tracked.

## Rollback

Unlink `~/.config/fish` (remove the symlink only), and restore the saved old
directory at that exact path. Its relative file symlinks work again there.
Preserve any local files changed since migration before restoring the backup.
