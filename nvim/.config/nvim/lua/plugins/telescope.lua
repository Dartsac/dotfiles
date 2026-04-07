-- Core Telescope plug‑in
return {
	"nvim-telescope/telescope.nvim",
	branch = "master",
	cmd = "Telescope",
	keys = {
		{
			"<C-f>",
			function()
				require("telescope.builtin").find_files({ cwd = vim.fn.getcwd() })
			end,
			desc = "Find files in CWD",
		},
		{ "<leader>fh", require("telescope.builtin").help_tags },
		{ "<Esc>O5F", require("config.telescope.multigrep") },
		{ "<leader>mf", require("config.telescope.multigrep_filesonly") },
	},
	dependencies = {
		{ "nvim-lua/plenary.nvim" }, -- no need for extra lazy flags
	},
	config = function()
		local ok, telescope = pcall(require, "telescope")
		if not ok then
			return
		end

		local actions = require("telescope.actions")

		telescope.setup({
			defaults = {
				file_ignore_patterns = { "node_modules" },
				-- Show current position counter and consistent ordering
				selection_strategy = "reset",
				sorting_strategy = "ascending",
				layout_config = {
					horizontal = {
						prompt_position = "top",
					},
				},
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
		})
	end,
}
