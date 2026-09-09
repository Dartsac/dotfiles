return {
	"smjonas/inc-rename.nvim",
	cmd = "IncRename",
	opts = {},
	keys = {
		{
			"<leader>r",
			function()
				return ":IncRename " .. vim.fn.expand("<cword>")
			end,
			expr = true,
			desc = "Incremental rename",
		},
	},
}
