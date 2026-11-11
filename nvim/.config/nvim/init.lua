-- init.lua
vim.loader.enable()
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1

require("config.options")
require("config.autocommands")
require("config.colorscheme").setup() -- before plugins, so they see its highlights
require("config.lazy")
require("config.lockfile").setup() -- commits lazy-lock.json after plugin updates
require("config.attach")
require("config.keymaps")

vim.g.python3_host_prog = "~/.venvs/nvim/bin/python3"
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
