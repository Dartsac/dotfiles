-- lua/lsp/null-ls.lua
local M = {}

function M.setup()
	local null_ls = require("null-ls")
	local ts_code_actions = require("typescript.extensions.null-ls.code-actions")

	local formatting = null_ls.builtins.formatting
	-- local diagnostics = null_ls.builtins.diagnostics

	null_ls.setup({
		sources = {
			formatting.prettier.with({ extra_args = { "--no-semi", "--single-quote", "--jsx-single-quote" } }),
			formatting.black.with({ extra_args = { "--fast" } }),
			formatting.stylua,
			ts_code_actions,
		},
	})
end

return M