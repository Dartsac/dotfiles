local status_ok, nvim_tree = pcall(require, "nvim-tree")
if not status_ok then
	return
end

local icons = require("user.icons")
require("user.miniicons")

local function on_attach(bufnr)
	-- Helper function for key mappings
	local function opts(desc)
		return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
	end

	-- Bind keys manually
	vim.keymap.set("n", "v", function()
		local api = require("nvim-tree.api")
		local node = api.tree.get_node_under_cursor()
		if not node or not node.absolute_path then
			--[[ print("Invalid node or missing absolute_path") ]]
			return
		end

		local filepath = node.absolute_path
		--[[ print("tmux_vsplit triggered for file: " .. filepath) ]]

		-- Open file in a tmux vertical split
		local cmd = string.format("tmux split-window -h 'nvim %s'", vim.fn.fnameescape(filepath))
		os.execute(cmd)

		-- close nvim-tree after splitting
		api.tree.close()
	end, opts("Vertical Split in tmux"))

	vim.keymap.set("n", "h", function()
		local api = require("nvim-tree.api")
		local node = api.tree.get_node_under_cursor()
		if not node or not node.absolute_path then
			return
		end

		local filepath = node.absolute_path

		-- Open file in a tmux horizontal split
		local cmd = string.format("tmux split-window -v 'nvim %s'", vim.fn.fnameescape(filepath))
		os.execute(cmd)

		-- close nvim-tree after splitting
		api.tree.close()
	end, opts("Horizontal Split in tmux"))

	-- Add any additional custom key mappings as needed
end

nvim_tree.setup({
	on_attach = on_attach,
	update_focused_file = {
		enable = true,
		update_cwd = true,
	},
	actions = {
		open_file = { quit_on_open = true },
	},
	renderer = {
		root_folder_modifier = ":t",
		icons = {
			show = {
				file = true,
				folder = true,
				folder_arrow = true,
				git = true,
			},
			glyphs = {
				default = "",
				symlink = "",
				folder = {
					arrow_open = "",
					arrow_closed = "",
					default = "",
					open = "",
					empty = "",
					empty_open = "",
					symlink = "",
					symlink_open = "",
				},
				git = {
					unstaged = "",
					staged = "S",
					unmerged = "",
					renamed = "➜",
					untracked = "U",
					deleted = "",
					ignored = "◌",
				},
			},
		},
	},
	diagnostics = {
		enable = true,
		show_on_dirs = true,
		icons = {
			hint = icons.diagnostics.BoldHint,
			info = icons.diagnostics.BoldInformation,
			warning = icons.diagnostics.BoldWarning,
			error = icons.diagnostics.BoldError,
		},
	},
	view = {
		width = 30,
		side = "right",
	},
})

vim.api.nvim_set_keymap(
	"n", -- Normal mode
	"+", -- Increase size
	[[:lua if require("nvim-tree.view").is_visible() then vim.cmd("NvimTreeResize +5") end<CR>]],
	{ noremap = true, silent = true }
)

vim.api.nvim_set_keymap(
	"n", -- Normal mode
	"=", -- Decrease size
	[[:lua if require("nvim-tree.view").is_visible() then vim.cmd("NvimTreeResize -5") end<CR>]],
	{ noremap = true, silent = true }
)
