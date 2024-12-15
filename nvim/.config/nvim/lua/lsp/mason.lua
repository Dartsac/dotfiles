-- lua/lsp/mason.lua
local lspconfig = require("lspconfig")
local handlers = require("lsp.handlers")

local servers = {
	"cssls",
	"html",
	"jsonls",
	"pyright",
	"lua_ls",
	"ts_ls",
	"jdtls",
}

for _, server in pairs(servers) do
	local opts = {
		on_attach = handlers.on_attach,
		capabilities = handlers.capabilities,
	}

	-- Try to load server-specific customizations from lsp/settings/
	server = vim.split(server, "@")[1]
	local require_ok, server_opts = pcall(require, "lsp.settings." .. server)
	if require_ok then
		opts = vim.tbl_deep_extend("force", server_opts, opts)
	end

	if server == "tsserver" then
		local ts_ok, typescript = pcall(require, "typescript")
		if ts_ok then
			typescript.setup({ server = opts })
		end
	else
		lspconfig[server].setup(opts)
	end
end
