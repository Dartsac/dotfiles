# ~/.pi

- **Source of truth.** The tracked config here (`agent/extensions`, `agent/settings.json`, `agent/themes`) is symlinked file by file from `~/dotfiles/pi`. Commit in `~/dotfiles`. After adding or moving a file there, run `stow --no-folding pi` from `~/dotfiles`.
- **Extension layout.** pi loads every top-level `agent/extensions/*.ts` as an extension, so an extension with tests lives in its own directory: `name/index.ts` beside `name/*.test.ts`.
- **Extension checks.** `node ~/dotfiles/.tests/pi-extensions.mjs` runs the tests against the installed pi; add `--types` to type-check, or a name to narrow (`… focus`). The pre-commit hook runs the tests of staged extension directories.
- **Live check.** To see an extension in a real session, run `pi --no-session --model claude-haiku-4-5:off` in tmux and read the pane with `tmux capture-pane`. Paste multi-line prompts with `tmux paste-buffer -p`.
