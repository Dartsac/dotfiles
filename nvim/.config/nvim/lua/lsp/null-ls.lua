-- lua/lsp/null-ls.lua
local M = {}

function M.setup()
	local null_ls = require("null-ls")
	require("lsp.handlers") -- diagnostics UI, keymaps, format-on-save

	local formatting = null_ls.builtins.formatting
	local diagnostics = null_ls.builtins.diagnostics

	null_ls.setup({
		sources = {
			formatting.prettierd.with({ extra_args = { "--no-semi", "--single-quote", "--jsx-single-quote" } }),
			formatting.blackd.with({ extra_args = { "--fast" } }),
			formatting.stylua,
			formatting.fish_indent,

			diagnostics.fish,
		},
	})
end

return M
