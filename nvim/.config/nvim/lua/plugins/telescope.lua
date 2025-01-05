-- lua/plugins/telescope.lua
return {
	"nvim-telescope/telescope.nvim",
	tag = "0.1.8", -- or, branch = '0.1.x',
	cmd = "Telescope",
	keys = {
		{
			"<C-f>",
			function()
				local cwd = vim.fn.getcwd()
				require("telescope.builtin").find_files({ cwd = cwd })
			end,
			desc = "Find Files in CWD",
		},
		{ "<leader>fh", require("telescope.builtin").help_tags },
		{ "<Esc>O5F", require("config.telescope.multigrep") },
		{ "<leader>mf", require("config.telescope.multigrep_filesonly") },
	},
	dependencies = { "nvim-lua/plenary.nvim", lazy = true },
	config = function()
		local status_ok, telescope = pcall(require, "telescope")
		if not status_ok then
			return
		end

		local actions = require("telescope.actions")

		telescope.setup({
			defaults = {
				file_ignore_patterns = { "node_modules" },
				-- prompt_prefix = " ",
				-- selection_caret = " ",
				-- path_display = { "smart" },

				mappings = {
					i = {
						["<C-j>"] = actions.move_selection_next,
						["<C-k>"] = actions.move_selection_previous,
						["<Tab>"] = actions.move_selection_worse,
						["<S-Tab>"] = actions.move_selection_better,

						["<esc>"] = actions.close,
						["<CR>"] = actions.select_default,
					},
				},
			},
			pickers = {
				-- Default configuration for builtin pickers goes here:
				-- picker_name = {
				--   picker_config_key = value,
				--   ...
				-- }
				-- Now the picker_config_key will be applied every time you call this
				-- builtin picker
			},
			extensions = {
				-- Your extension configuration goes here:
				-- extension_name = {
				--   extension_config_key = value,
				-- }
				-- please take a look at the readme of the extension you want to configure
			},
		})
	end,
}
