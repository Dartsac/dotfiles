-- Core Telescope plug-in

local function harpoon_index(filepath)
	local ok, harpoon = pcall(require, "harpoon")
	if not ok then return nil end
	local rel = vim.fn.fnamemodify(filepath, ":.")
	for i, item in ipairs(harpoon:list().items) do
		if item.value == rel then return i end
	end
end

local function make_harpoon_entry(opts)
	local entry_display = require("telescope.pickers.entry_display")
	local make_entry = require("telescope.make_entry")
	local displayer = entry_display.create({
		separator = " ",
		items = { { width = 4 }, { remaining = true } },
	})
	local original = make_entry.gen_from_file(opts)
	return function(line)
		local entry = original(line)
		if not entry then return end
		entry.display = function(e)
			local index = harpoon_index(e.path)
			return displayer({
				{ index and ("󱡀 " .. index) or "    ", index and "WhichKeyIconBlue" or nil },
				e.value,
			})
		end
		return entry
	end
end

return {
	"nvim-telescope/telescope.nvim",
	branch = "master",
	cmd = "Telescope",
	keys = {
		{
			"<C-f>",
			function()
				require("telescope.builtin").find_files({
					cwd = vim.fn.getcwd(),
					entry_maker = make_harpoon_entry({}),
				})
			end,
			desc = "Find files in CWD",
		},
		{ "<leader>fh", require("telescope.builtin").help_tags },
		{ "<Esc>O5F", require("config.telescope.multigrep") },
		{ "<leader>mf", require("config.telescope.multigrep_filesonly") },
	},
	dependencies = {
		{ "nvim-lua/plenary.nvim" },
	},
	config = function()
		local ok, telescope = pcall(require, "telescope")
		if not ok then return end

		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")

		telescope.setup({
			defaults = {
				file_ignore_patterns = { "node_modules" },
				selection_strategy = "reset",
				sorting_strategy = "ascending",
				layout_config = {
					horizontal = { prompt_position = "top" },
				},
				mappings = {
					i = {
						["<C-j>"] = actions.move_selection_next,
						["<C-k>"] = actions.move_selection_previous,
						["<Tab>"] = actions.move_selection_worse,
						["<S-Tab>"] = actions.move_selection_better,
						["<esc>"] = actions.close,
						["<CR>"] = actions.select_default,
						["<C-h>"] = function(prompt_bufnr)
							local entry = action_state.get_selected_entry()
							if not entry then return end
							local filepath = entry.path or entry.filename
							if not filepath then return end
							local rel = vim.fn.fnamemodify(filepath, ":.")
							local list = require("harpoon"):list()
							local index = harpoon_index(filepath)
							if index then
								list:remove_at(index)
							else
								list:add({ value = rel, context = { row = 1, col = 0 } })
							end
							local picker = action_state.get_current_picker(prompt_bufnr)
							picker:refresh(picker.finder, { reset_prompt = false })
						end,
					},
				},
			},
		})
	end,
}
