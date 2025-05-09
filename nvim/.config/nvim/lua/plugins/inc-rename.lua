return {
	{
		"smjonas/inc-rename.nvim",
		event = "BufReadPre",
		config = function()
			local status_ok, rename = pcall(require, "inc_rename")
			if not status_ok then
				return
			end

			rename.setup({})

			vim.keymap.set("n", "<leader>r", function()
				return ":IncRename " .. vim.fn.expand("<cword>")
			end, { expr = true, desc = "Incremental rename", noremap = true })
		end,
	},
}
