# Fish directory symlink

The intended installation is one directory symlink:

```text
~/.config/fish -> ~/dotfiles/fish/.config/fish
```

From `~/dotfiles`, `stow fish` creates this link when `~/.config/fish` does
not already exist. If it exists as a real directory, Stow can instead create
individual file links inside it. Re-running Stow alone does not migrate a
mixed directory containing local files.

## Migrating an existing installation

1. Back up `~/.config/fish` outside the repository, preserving symlinks.
2. Check that every existing symlink points to its corresponding file in
   `~/dotfiles/fish/.config/fish`. Investigate broken or unexpected links.
3. Copy real local files into the corresponding package directories. Do not
   overwrite different files. Preserve permissions and verify the copies.
4. Keep machine-local files ignored by Git. The repository ignores
   `config-local.fish`, `fish_variables`, `fish_greeting_last_run`, the local
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
