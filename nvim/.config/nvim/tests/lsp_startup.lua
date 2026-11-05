-- Run from the config directory:
-- nvim --headless -u NONE -i NONE -l tests/lsp_startup.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local specs = dofile("lua/plugins/lsp.lua")
local mason, runtime, installer = specs[1], specs[2], specs[3]
assert(mason.cmd == "Mason")
assert(installer.event == nil)
assert(vim.tbl_contains(installer.cmd, "Mason"))
assert(vim.tbl_contains(installer.cmd, "LspInstall"))
assert(installer.opts.automatic_enable == false)
for _, dependency in ipairs(runtime.dependencies) do
	assert(dependency ~= "williamboman/mason.nvim")
	assert(dependency ~= "williamboman/mason-lspconfig.nvim")
end

local path = vim.env.PATH
mason.init()
local configured_path = vim.env.PATH
assert(vim.startswith(configured_path, vim.fn.stdpath("data") .. "/mason/bin:"))
mason.init()
assert(vim.env.PATH == configured_path, "PATH must not accumulate duplicate entries")
vim.env.PATH = path
assert(not package.loaded.mason)
assert(not package.loaded["mason-lspconfig"])

local configurations, enabled = {}, nil
package.loaded["lsp.handlers"] = { capabilities = { test_capability = true } }
vim.lsp.config = function(name, config)
	configurations[name] = config
end
vim.lsp.enable = function(servers)
	enabled = servers
end
runtime.config()
assert(configurations["*"].capabilities.test_capability)
assert(configurations.lua_ls and configurations.pyright)
assert(vim.deep_equal(enabled, installer.opts.ensure_installed))
assert(vim.tbl_contains(enabled, "lua_ls"))
assert(not vim.tbl_contains(enabled, "stylua"))
assert(not package.loaded.mason)
assert(not package.loaded["mason-lspconfig"])
print("LSP startup regression tests passed")
