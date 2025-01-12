return {
	"nvim-tree/nvim-tree.lua",
	dependencies = {
		"echasnovski/mini.nvim",
	},
	cmd = { "NvimTreeToggle", "NvimTreeOpen" },
	config = function()
		local status_ok, nvim_tree = pcall(require, "nvim-tree")
		if not status_ok then
			return
		end

		local icons = require("config.icons")

		local function on_attach(bufnr)
			local api = require("nvim-tree.api")

			-- Helper function for key mappings
			local function opts(desc)
				return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
			end

			-- Bind `r` to raname a file
			vim.keymap.set("n", "r", function()
				api.fs.rename()
			end, opts("Rename File/Folder"))

			vim.keymap.set("n", "R", function()
				api.fs.rename_full()
			end, opts("Rename File/Folder"))

			-- Bind `d` to delete a file or folder
			vim.keymap.set("n", "d", function()
				local node = api.tree.get_node_under_cursor()
				if not node then
					return
				end
				api.fs.remove(node)
			end, opts("Delete File/Folder"))

			-- Bind `a` to add a file or folder
			vim.keymap.set("n", "a", function()
				api.fs.create()
			end, opts("Add File/Folder"))

			-- Open file or folder
			vim.keymap.set("n", "<CR>", function()
				local node = api.tree.get_node_under_cursor()
				if not node then
					return
				end
				if node.type == "directory" then
					api.node.open.edit() -- Expand or collapse the folder
				else
					api.node.open.edit() -- Open the file
					api.tree.close() -- Optionally close the tree after opening a file
				end
			end, opts("Open File or Folder"))

			-- Open file in a tmux vertical split
			vim.keymap.set("n", "v", function()
				local node = api.tree.get_node_under_cursor()
				if not node or not node.absolute_path then
					return
				end

				local filepath = node.absolute_path
				local cmd =
					string.format("tmux split-window -h 'NVIM_NO_HARPOON=1 nvim %s'", vim.fn.fnameescape(filepath))
				os.execute(cmd)

				api.tree.close() -- Close nvim-tree after splitting
			end, opts("Vertical Split in tmux"))

			-- Open file in a tmux horizontal split
			vim.keymap.set("n", "h", function()
				local node = api.tree.get_node_under_cursor()
				if not node or not node.absolute_path then
					return
				end

				local filepath = node.absolute_path
				local cmd =
					string.format("tmux split-window -v 'NVIM_NO_HARPOON=1 nvim %s'", vim.fn.fnameescape(filepath))
				os.execute(cmd)

				api.tree.close() -- Close nvim-tree after splitting
			end, opts("Horizontal Split in tmux"))
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
	end,
}
