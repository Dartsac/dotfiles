-- lua/lsp/init.lua
local M = {}

function M.setup()
	local lspconfig_status_ok, _ = pcall(require, "lspconfig")
	if not lspconfig_status_ok then
		return
	end

	-- Load handlers (capabilities, on_attach) first
	local handlers = require("lsp.handlers")
	handlers.setup()

	-- Mason and LSP server setup
	require("lsp.mason")

	-- Null-ls setup is already triggered by plugin config, but we can also
	-- call require("lsp.null-ls").setup() here if needed.
end

return M
