-- lua/lsp/settings/lua_ls.lua
local handlers = require("lsp.handlers")

return {
	-- turn OFF the server’s own formatter – use StyLua via null‑ls
	on_attach = function(client, bufnr)
		client.server_capabilities.documentFormattingProvider = false
		handlers.on_attach(client, bufnr)
	end,

	settings = {
		Lua = {
			semantic = { enable = false },
			diagnostics = { globals = { "vim" } },
			workspace = {
				library = {
					[vim.fn.expand("$VIMRUNTIME/lua")] = true,
					[vim.fn.stdpath("config") .. "/lua"] = true,
				},
			},
		},
	},
}
