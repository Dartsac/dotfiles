return {
	{
		"ThePrimeagen/harpoon",
		branch = "harpoon2",
		config = function(_, opts)
			local harpoon = require("harpoon")
			harpoon:setup(opts)
		end,
		opts = {
			menu = { width = vim.api.nvim_win_get_width(0) - 4 },
			settings = { save_on_toggle = true },
		},
		keys = {
			{
				"<leader>h",
				function()
					require("harpoon"):list():add()
				end,
				desc = "Harpoon File",
			},
			{
				"<leader>H",
				function()
					require("harpoon").ui:toggle_quick_menu(require("harpoon"):list())
				end,
				desc = "Harpoon Quick Menu",
			},
		},
	},
}
