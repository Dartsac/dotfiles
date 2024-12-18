return {
	"lewis6991/gitsigns.nvim",
	event = { "BufReadPost", "BufWritePost", "BufNewFile" },
	config = function()
		local status_ok, gitsigns = pcall(require, "gitsigns")
		if not status_ok then
			return
		end

		local icons = require("config.icons")

		gitsigns.setup({
			signs = {
				add = { text = icons.ui.BoldLineMiddle },
				delete = { text = icons.ui.Triangle },
			},
			signs_staged = {
				add = { text = icons.ui.BoldLineMiddle },
				delete = { text = icons.ui.Triangle },
			},
			signs_staged_enable = false,
			attach_to_untracked = true,
			watch_gitdir = {
				interval = 1000,
				follow_files = true,
			},
			current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
			update_debounce = 200,
			max_file_length = 40000,
			preview_config = {
				border = "rounded",
				style = "minimal",
				relative = "cursor",
				row = 0,
				col = 1,
			},
			current_line_blame = false,
			show_deleted = false,
		})
	end,
}
