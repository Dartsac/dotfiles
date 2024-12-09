local status_ok, wk = pcall(require, "which-key")
if not status_ok then
	return
end

-- Configure which-key with the new options
wk.setup({
	preset = "helix",
	plugins = {
		marks = true,
		registers = true,
		spelling = {
			enabled = true,
			suggestions = 20,
		},
		presets = {
			operators = false,
			motions = false,
			text_objects = false,
			windows = false,
			nav = false,
			z = false,
			g = false,
		},
	},
	win = {
		border = "rounded",
		no_overlap = false,
		padding = { 1, 2 }, -- extra window padding [top/bottom, right/left]
		title = false,
		title_pos = "center",
		zindex = 1000,
	},
	icons = {
		mappings = true,
		colors = true,
	},
	-- ignore_missing = true,
	show_help = false,
	show_keys = false,
	disable = {
		buftypes = {},
		filetypes = { "TelescopePrompt" },
	},
})

-- Adding mappings using the new `wk.add()` format
wk.add({
	-- General mappings
	{ "<leader>F", "<cmd>Telescope live_grep theme=ivy<cr>", desc = "Find Text", mode = "n" },
	{ "<leader>P", "<cmd>lua require('telescope').extensions.projects.projects()<cr>", desc = "Projects", mode = "n" },
	{
		"<leader>b",
		"<cmd>lua require('telescope.builtin').buffers(require('telescope.themes').get_dropdown{previewer = false})<cr>",
		desc = "Buffers",
		mode = "n",
	},
	{ "<leader>c", "<cmd>Bdelete!<CR>", desc = "Close Buffer", mode = "n" },
	{ "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "Explorer", mode = "n" },
	{
		"<leader>f",
		"<cmd>lua require('telescope.builtin').find_files(require('telescope.themes').get_dropdown{previewer = false})<cr>",
		desc = "Find files",
		mode = "n",
	},
	{ "<leader>h", "<cmd>nohlsearch<CR>", desc = "No Highlight", mode = "n" },
	{ "<leader>q", "<cmd>q!<CR>", desc = "Quit", mode = "n" },
	{ "<leader>w", "<cmd>w!<CR>", desc = "Save", mode = "n" },

	-- LSP Group
	{ "<leader>l", group = "LSP" },
	{ "<leader>lI", "<cmd>LspInstallInfo<cr>", desc = "Installer Info", mode = "n" },
	{ "<leader>lS", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", desc = "Workspace Symbols", mode = "n" },
	{ "<leader>la", "<cmd>lua vim.lsp.buf.code_action()<cr>", desc = "Code Action", mode = "n" },
	{ "<leader>ld", "<cmd>Telescope diagnostics bufnr=0<cr>", desc = "Document Diagnostics", mode = "n" },
	{ "<leader>lf", "<cmd>lua vim.lsp.buf.format{async=true}<cr>", desc = "Format", mode = "n" },
	{ "<leader>lg", "<cmd>lua _LAZYGIT_TOGGLE()<CR>", desc = "Lazygit", mode = "n" },
	{ "<leader>li", "<cmd>LspInfo<cr>", desc = "Info", mode = "n" },
	{ "<leader>lj", "<cmd>lua vim.lsp.diagnostic.goto_next()<CR>", desc = "Next Diagnostic", mode = "n" },
	{ "<leader>lk", "<cmd>lua vim.lsp.diagnostic.goto_prev()<cr>", desc = "Prev Diagnostic", mode = "n" },
	{ "<leader>ll", "<cmd>lua vim.lsp.codelens.run()<cr>", desc = "CodeLens Action", mode = "n" },
	{ "<leader>lq", "<cmd>lua vim.diagnostic.setloclist()<cr>", desc = "Quickfix", mode = "n" },
	{ "<leader>lr", "<cmd>lua vim.lsp.buf.rename()<cr>", desc = "Rename", mode = "n" },
	{ "<leader>ls", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document Symbols", mode = "n" },
	{ "<leader>lw", "<cmd>Telescope diagnostics<cr>", desc = "Workspace Diagnostics", mode = "n" },

	-- Packer Group
	{ "<leader>p", group = "Packer" },
	{ "<leader>pS", "<cmd>PackerStatus<cr>", desc = "Status", mode = "n" },
	{ "<leader>pc", "<cmd>PackerCompile<cr>", desc = "Compile", mode = "n" },
	{ "<leader>pi", "<cmd>PackerInstall<cr>", desc = "Install", mode = "n" },
	{ "<leader>ps", "<cmd>PackerSync<cr>", desc = "Sync", mode = "n" },
	{ "<leader>pu", "<cmd>PackerUpdate<cr>", desc = "Update", mode = "n" },

	-- Search Group
	{ "<leader>s", group = "Search" },
	{ "<leader>sC", "<cmd>Telescope commands<cr>", desc = "Commands", mode = "n" },
	{ "<leader>sM", "<cmd>Telescope man_pages<cr>", desc = "Man Pages", mode = "n" },
	{ "<leader>sR", "<cmd>Telescope registers<cr>", desc = "Registers", mode = "n" },
	{ "<leader>sb", "<cmd>Telescope gi<cr>", desc = "Checkout branch", mode = "n" },
	{ "<leader>sc", "<cmd>Telescope colorscheme<cr>", desc = "Colorscheme", mode = "n" },
	{ "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Find Help", mode = "n" },
	{ "<leader>sk", "<cmd>Telescope keymaps<cr>", desc = "Keymaps", mode = "n" },
	{ "<leader>sr", "<cmd>Telescope oldfiles<cr>", desc = "Open Recent File", mode = "n" },

	-- Terminal Group
	{ "<leader>t", group = "Terminal" },
	{ "<leader>tf", "<cmd>ToggleTerm direction=float<cr>", desc = "Float", mode = "n" },
	{ "<leader>th", "<cmd>ToggleTerm size=10 direction=horizontal<cr>", desc = "Horizontal", mode = "n" },
	{ "<leader>tn", "<cmd>lua _NODE_TOGGLE()<cr>", desc = "Node", mode = "n" },
	{ "<leader>tp", "<cmd>lua _PYTHON_TOGGLE()<cr>", desc = "Python", mode = "n" },
	{ "<leader>tt", "<cmd>lua _HTOP_TOGGLE()<cr>", desc = "Htop", mode = "n" },
	{ "<leader>tu", "<cmd>lua _NCDU_TOGGLE()<cr>", desc = "NCDU", mode = "n" },
	{ "<leader>tv", "<cmd>ToggleTerm size=80 direction=vertical<cr>", desc = "Vertical", mode = "n" },

	-- Git signs
	{ "<leader>g", group = "Git" },
	{ "<leader>gj", "<cmd>lua require 'gitsigns'.next_hunk({navigation_message = false})<cr>", desc = "Next Hunk" },
	{ "<leader>gk", "<cmd>lua require 'gitsigns'.prev_hunk({navigation_message = false})<cr>", desc = "Prev Hunk" },
	{ "<leader>gp", "<cmd>lua require 'gitsigns'.preview_hunk()<cr>", desc = "Preview Hunk" },
	{ "<leader>gr", "<cmd>lua require 'gitsigns'.reset_hunk()<cr>", desc = "Reset Hunk" },
	{ "<leader>gl", "<cmd>lua require 'gitsigns'.blame_line()<cr>", desc = "Blame" },
	{ "<leader>gR", "<cmd>lua require 'gitsigns'.reset_buffer()<cr>", desc = "Reset Buffer" },
	{ "<leader>gs", "<cmd>lua require 'gitsigns'.stage_hunk()<cr>", desc = "Stage Hunk" },
	{ "<leader>gu", "<cmd>lua require 'gitsigns'.undo_stage_hunk()<cr>", desc = "Undo Stage Hunk" },
	{ "<leader>gd", "<cmd>Gitsigns diffthis HEAD<cr>", desc = "Git Diff" },
})
