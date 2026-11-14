-- init.lua
vim.loader.enable()
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1

require("config.options")
require("config.autocommands")
require("config.lazy") -- also applies the colorscheme (plugins/colorscheme.lua)
require("config.colorscheme").ensure()
require("config.lockfile").setup() -- commits lazy-lock.json after plugin updates, where lua/config/local.lua asks
require("config.attach")
require("config.keymaps")

-- Python plugins use python3 from PATH, unless lua/config/local.lua names one.
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

-- This machine's own values: lua/config/local.lua, which git ignores, shaped
-- like lua/config/local.example.lua. Loaded last, so it wins over the tracked
-- config (environment variables such as $OBSIDIAN_VAULT still come first).
if vim.uv.fs_stat(vim.fn.stdpath("config") .. "/lua/config/local.lua") then
	require("config.local")
end
