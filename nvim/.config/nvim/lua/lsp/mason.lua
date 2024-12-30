-- lua/lsp/mason.lua
local lspconfig = require("lspconfig")
local handlers = require("lsp.handlers")

local ts = require("typescript-tools")

ts.setup({
	on_attach = handlers.on_attach,
	capabilities = handlers.capabilities,
})

require("mason-lspconfig").setup_handlers({
	function(server_name)
		local opts = {
			on_attach = handlers.on_attach,
			capabilities = handlers.capabilities,
		}

		-- Try to load server-specific customizations from lsp/settings/
		server_name = vim.split(server_name, "@")[1]
		local require_ok, server_opts = pcall(require, "lsp.settings." .. server_name)
		if require_ok then
			opts = vim.tbl_deep_extend("force", server_opts, opts)
		end
		lspconfig[server_name].setup(opts)
	end,
})
