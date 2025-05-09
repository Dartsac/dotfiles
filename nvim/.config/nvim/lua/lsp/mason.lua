-- lua/lsp/mason.lua
local handlers = require("lsp.handlers")

-- only configure typescript‑tools when the module is available
local ok, ts = pcall(require, "typescript-tools")
if ok then
	ts.setup({
		on_attach = handlers.on_attach,
		capabilities = handlers.capabilities,
	})
end
