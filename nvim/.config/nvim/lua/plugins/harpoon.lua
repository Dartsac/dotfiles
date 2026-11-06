return {
	{
		"ThePrimeagen/harpoon",
		branch = "harpoon2",
		lazy = true,
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
		init = function()
			-- Reviewed removal of entries whose files are missing (lists them and
			-- asks first). Deletions made in the Snacks explorer clean up on their
			-- own: lua/config/harpoon_cleanup.lua.
			vim.api.nvim_create_user_command("HarpoonCleanMissing", function()
				require("config.harpoon_cleanup").clean_missing()
			end, { desc = "Review and remove Harpoon entries whose files are missing" })
		end,
		config = function(_, opts)
			local harpoon = require("harpoon")
			harpoon:setup(opts)
		end,
		opts = {
			menu = { width = vim.api.nvim_win_get_width(0) - 4 },
			settings = { save_on_toggle = true },
		},
	},
}
