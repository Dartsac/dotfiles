-- Commenting uses Neovim's built-in `gc` operator (gcc, gc{motion}, visual gc).
-- ts-context-commentstring makes 'commentstring' follow the treesitter node
-- under the cursor so JSX, Vue templates, embedded CSS, etc. comment correctly.
return {
	"JoosepAlviste/nvim-ts-context-commentstring",
	event = "BufReadPost",
	init = function()
		vim.g.skip_ts_context_commentstring_module = true
	end,
	config = function()
		require("ts_context_commentstring").setup({ enable_autocmd = false })

		local get_option = vim.filetype.get_option
		---@diagnostic disable-next-line: duplicate-set-field
		vim.filetype.get_option = function(filetype, option)
			if option == "commentstring" then
				return require("ts_context_commentstring.internal").calculate_commentstring()
					or get_option(filetype, option)
			end
			return get_option(filetype, option)
		end
	end,
}
