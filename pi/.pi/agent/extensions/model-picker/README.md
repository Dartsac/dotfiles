# Model + thinking picker

Global Pi extension. Run `/reload` after installing or changing it.

- **Command+M** in Ghostty opens the picker while Pi is idle. `/model-picker` is the only other advertised entry point. Option+M and F4 are not bound.
- Ghostty maps `super+m=text:\x1b[109;8u` to an internal Ctrl+Shift+Alt+M transport chord, registered by this extension. Native Super modifiers are not preserved by tmux; the bridge was verified through an isolated tmux terminal with Pi's modifyOtherKeys fallback enabled. The internal chord is unbound in the live tmux root table.
- Karabiner blocks Command+M outside Ghostty, but exempts `com.mitchellh.ghostty` so Ghostty can forward the shortcut instead of minimizing.
- After changes, reload Ghostty with Command+Shift+comma and Pi with `/reload`. Karabiner watches its configuration automatically.
- Type to search model IDs, provider IDs, and display names. Space-separated terms all have to match.
- Use Up/Down or PageUp/PageDown to navigate, then Enter to choose the model.
- Choose a supported thinking level; Enter applies the model and level to this session.
- Tab on the thinking screen returns to model selection with the search preserved.
- Escape (or the configured cancel key) cancels either screen without applying changes.
- Authenticated models are limited to the current scope when one is configured. A scoped thinking level supplies the initial selection; otherwise the current level is used, clamped to model capabilities.
- Non-reasoning models offer only `off`.

Pi records model/thinking changes in session history. This extension does not alter defaults for new sessions, credentials, or existing keybindings. Pi's built-in Ctrl+L model picker remains unchanged, but your current tmux configuration intercepts Ctrl+L for pane navigation. Shift+Tab still cycles thinking levels.

Implementation: `index.ts`. Regression tests: `picker.test.ts`, run through Pi's bundled jiti with the same host-package aliases as the extension loader. Also checked with TypeScript and Pi's actual extension loader.
