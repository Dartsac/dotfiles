-- Snacks explorer replaces nvim-tree. Only the explorer (and the picker it is
-- built on) is enabled: Telescope stays the picker for everything else, and
-- vim.ui.select is left alone (ui_select = false).
return {
	"folke/snacks.nvim",
	lazy = true,
	keys = {
		{
			"<leader>e",
			function()
				Snacks.explorer() -- Toggles: closes the explorer when it is open.
			end,
			desc = "Explorer",
		},
	},
	opts = function()
		return {
			explorer = { enabled = true, replace_netrw = false, trash = true },
			picker = {
				enabled = true,
				ui_select = false,
				sources = { explorer = require("config.explorer").source() },
			},
		}
	end,
	config = function(_, opts)
		require("snacks").setup(opts)
		local explorer = require("config.explorer")
		explorer.setup_highlights()
		explorer.install_delete_hook()
	end,
}
