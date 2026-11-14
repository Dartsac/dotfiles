-- An example of lua/config/local.lua, this machine's own values for this
-- Neovim config. Copy it to local.lua (git ignores that file) and uncomment
-- what you need. init.lua loads it last, so it can also change any option or
-- key the tracked config sets.

-- After lazy.nvim installs or updates plugins, commit lazy-lock.json by itself
-- in the clone this config is stowed from (not pushed). Off without this.
-- vim.g.commit_lazy_lockfile = true

-- An Obsidian vault: its notes get obsidian.nvim (instead of Marksman), and
-- <leader>dn and <leader>dg search it. No vault without this.
-- vim.g.obsidian_vault = "~/Documents/vault"

-- The Python that Python plugins use, with pynvim installed (otherwise
-- python3 from PATH).
-- vim.g.python3_host_prog = vim.fn.expand("~/.venvs/nvim/bin/python3")

-- PlantUML preview: Java and the PlantUML jar (otherwise `java` from PATH and
-- the jar bundled with plantuml-previewer.vim).
-- vim.g["plantuml_previewer#java_path"] = "/opt/homebrew/opt/openjdk/bin/java"
-- vim.g["plantuml_previewer#plantuml_jar_path"] = vim.fn.expand("~/tools/plantuml/plantuml.jar")
