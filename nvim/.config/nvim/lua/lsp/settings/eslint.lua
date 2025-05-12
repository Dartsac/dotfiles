-- Turn off eslint’s formatter so there is no clash with null‑ls.
local handlers = require("lsp.handlers")

return {
	on_attach = function(client, bufnr)
		client.server_capabilities.documentFormattingProvider = false
		handlers.on_attach(client, bufnr)
	end,
	settings = { format = { enable = false } },
}
