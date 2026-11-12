# Herdr directory-symlink migration

This migrates only `~/.config/herdr` and
`~/.config/herdr-automatic-rename`. It does not touch `herdr-app` or remove
`herdr-auto-title`. Automatic Rename keeps its default config path.

## Before stopping anything

Run the read-only check:

```sh
python3 ~/dotfiles/migrate-herdr.py
```

It lists running sessions, checks file conflicts and ignore rules, and verifies
that agent conversation paths referenced by saved layouts exist. It does not
prove every running agent has registered a resume reference or that every
integration will resume successfully. Save work, let agents finish active tools,
and record the session path/ID of each conversation you need to resume using
that agent's session-information UI.

Herdr restores saved layouts after a restart. It does not keep arbitrary
processes alive across a server stop. Supported agent integrations can resume
saved conversations; that is a new process, not uninterrupted execution.
Do not use the `ke` shortcut: it deletes the default session layout.

## Run outside Herdr

1. Save work in all panes and open a separate Ghostty window outside Herdr.
   This agent conversation will stop when its Herdr server stops.
2. List running sessions:

   ```sh
   herdr session list --json
   ```

3. Stop each running named session. At preparation time the named sessions
   `--list` and `herdr-live-check` were running. If they are still running:

   ```sh
   herdr session stop -- --list
   herdr session stop herdr-live-check
   ```

   Stop the default server too:

   ```sh
   herdr server stop
   ```

   Stop other running named sessions if the listing shows any. Do not delete
   sessions. Keep all Herdr clients closed during migration so none restarts
   a server. Do not use `stop-fresh.py` or `ke`.
4. Check again, then apply:

   ```sh
   python3 ~/dotfiles/migrate-herdr.py
   python3 ~/dotfiles/migrate-herdr.py --apply
   ```

   The script refuses to apply from a Herdr pane or while any session is
   running. It never stops servers itself. If it refuses, fix the reported
   issue instead of bypassing the checks.

The original directories are moved to a unique backup under
`~/.local/state/dotfiles-backups/herdr-*`. Saved layouts, named sessions,
plugins, and logs are copied into ignored paths in the package. Existing
repository files are not overwritten. Relative symlinks are recalculated:
links to local state follow that state into the package; links to external files
keep the same physical referent. Broken or cyclic links block migration, and
copied links are checked again before completion. Referenced agent conversation files
are also copied into the private backup; their original files are unchanged.
Socket files are not copied: Herdr recreates them when it starts. The original
backup keeps the old sockets, which are not live after a normal server stop.

## Reattach and verify

```sh
herdr
```

Reattach to any named sessions you use with `herdr session attach NAME`.
Check workspace layouts, then agent conversations. If an agent does not resume
automatically, use that agent's resume command and the saved session path/ID.

In a new Fish-config workspace, check Git status, Telescope, and Harpoon. In a
Herdr-config workspace, check the same navigation plus tab numbering and agent
task names. Both config paths should now be directory symlinks into dotfiles.
Review the diff and commit only migration files after these checks. Leave
unrelated existing changes out of that commit.

## Rollback

Stop all Herdr servers again. Read the backup's `manifest.json`, which gives
each source path, target path, and original directory location. Preserve any
newer local/session state first. Remove only the directory symlinks at the
source paths, then move the original directories back to those paths. Their
relative Stow links work again once restored to their original locations.
Do not blindly overwrite newer agent conversation files with backup copies.

A caught migration error restores already-moved source directories and removes
newly copied package files. A power loss or forced process kill can interrupt
that rollback; use the manifest and original directories to recover manually.

## Offline script tests

```sh
cd ~/dotfiles
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_migrate_herdr.py'
```
