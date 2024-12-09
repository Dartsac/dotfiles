local servers = {
	"cssls",
	"html",
	"jsonls",
	"pyright",
	"lua_ls",
	"ts_ls",
	"jdtls",
}

local settings = {
	ui = {
		border = "none",
		icons = {
			package_installed = "✓",
			package_pending = "➜",
			package_uninstalled = "✗",
		},
	},
	log_level = vim.log.levels.INFO,
	max_concurrent_installers = 4,
}

require("mason").setup(settings)
require("mason-lspconfig").setup({
	ensure_installed = servers,
	automatic_installation = true,
})

local lspconfig_status_ok, lspconfig = pcall(require, "lspconfig")
if not lspconfig_status_ok then
	return
end

local opts = {}

-- This is passing the setting based on the name of the language server
-- Current options is jsonls, pyright, sumneko_lua
for _, server in pairs(servers) do
	opts = {
		-- passing these functions from handlers
		on_attach = require("user.lsp.handlers").on_attach,
		capabilities = require("user.lsp.handlers").capabilities,
	}

	server = vim.split(server, "@")[1]

	local require_ok, conf_opts = pcall(require, "user.lsp.settings." .. server)
	if require_ok then
		opts = vim.tbl_deep_extend("force", conf_opts, opts)
	end
	if server == "tsserver" then
		local ts_ok, ts = pcall(require, "typescript")
		if not ts_ok then
			return
		end
		ts.setup({
			server = opts,
		})
	else
		lspconfig[server].setup(opts)
	end
end

--TODO: I believe this is where I would add the typescript stuff here.
