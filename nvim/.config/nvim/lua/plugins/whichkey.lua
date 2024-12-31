-- lua/plugins/whichkey.lua
return {
	{
		"folke/which-key.nvim",
		config = function()
			local wk = require("which-key")

			wk.setup({
				preset = "helix",
				plugins = {
					marks = true,
					registers = true,
					spelling = { enabled = true, suggestions = 20 },
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
					padding = { 1, 2 },
					title = false,
					title_pos = "center",
					zindex = 1000,
				},
				icons = { mappings = true, colors = true },
				show_help = false,
				show_keys = false,
				disable = { buftypes = {}, filetypes = { "TelescopePrompt" } },
				filter = function(mapping)
					return mapping.desc and mapping.desc ~= ""
				end,
			})

			wk.add({
				-- Dynamically add harpooned files using the expand function
				{
					"<leader>",
					group = "Harpoon",
					expand = function()
						local ok, harpoon = pcall(require, "harpoon")
						if not ok then
							return {}
						end

						local marks = harpoon:list().items
						local ret = {}

						for i, _ in ipairs(marks) do
							ret[i] = {
								tostring(i),
								function()
									harpoon:list():select(i)
								end,
								desc = marks[i].value,
								icon = { icon = "󱡀", hl = "WhichKeyIconBlue" },
							}
							if i > 1 then
								ret[i]["hidden"] = true
							end
						end

						return ret
					end,
				},
				-- General mappings
				{
					"<leader>b",
					"<cmd>lua require('telescope.builtin').buffers(require('telescope.themes').get_dropdown{previewer = false})<cr>",
					desc = "Buffers",
					mode = "n",
				},
				{ "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "Explorer", mode = "n" },
				{ "<leader>n", "<cmd>nohlsearch<CR>", desc = "No Highlight", mode = "n" },
				{ "<leader>q", "<cmd>q!<CR>", desc = "Quit", mode = "n" },
				{ "<leader>w", "<cmd>w!<CR>", desc = "Save", mode = "n" },
				{ "<leader>m", "<cmd>messages<CR>", desc = "Messages", mode = { "n", "v" } },

				-- Lazy
				{ "<leader>L", "<cmd>Lazy<cr>", desc = "Lazy", mode = "n" },

				-- LSP Group
				{ "<leader>l", group = "LSP" },
				{ "<leader>M", "<cmd>Mason<cr>", desc = "Mason", mode = "n" },
				{
					"<leader>lS",
					"<cmd>Telescope lsp_dynamic_workspace_symbols<cr>",
					desc = "Workspace Symbols",
					mode = "n",
				},
				{ "<leader>la", "<cmd>lua vim.lsp.buf.code_action()<cr>", desc = "Code Action", mode = "n" },
				{ "<leader>ld", "<cmd>Telescope diagnostics bufnr=0<cr>", desc = "Document Diagnostics", mode = "n" },
				{ "<leader>lf", "<cmd>lua vim.lsp.buf.format{async=true}<cr>", desc = "Format", mode = "n" },
				{ "<leader>li", "<cmd>LspInfo<cr>", desc = "Info", mode = "n" },
				{ "<leader>lj", "<cmd>lua vim.lsp.diagnostic.goto_next()<CR>", desc = "Next Diagnostic", mode = "n" },
				{ "<leader>lk", "<cmd>lua vim.lsp.diagnostic.goto_prev()<cr>", desc = "Prev Diagnostic", mode = "n" },
				{ "<leader>ll", "<cmd>lua vim.lsp.codelens.run()<cr>", desc = "CodeLens Action", mode = "n" },
				{ "<leader>lq", "<cmd>lua vim.diagnostic.setloclist()<cr>", desc = "Quickfix", mode = "n" },
				{ "<leader>lr", "<cmd>lua vim.lsp.buf.rename()<cr>", desc = "Rename", mode = "n" },
				{ "<leader>ls", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document Symbols", mode = "n" },
				{ "<leader>lw", "<cmd>Telescope diagnostics<cr>", desc = "Workspace Diagnostics", mode = "n" },

				-- Search Group
				{ "<leader>s", group = "Search" },
				{ "<leader>sC", "<cmd>Telescope commands<cr>", desc = "Commands", mode = "n" },
				{ "<leader>sM", "<cmd>Telescope man_pages<cr>", desc = "Man Pages", mode = "n" },
				{ "<leader>sR", "<cmd>Telescope registers<cr>", desc = "Registers", mode = "n" },
				{ "<leader>sb", "<cmd>Telescope git_branches<cr>", desc = "Checkout branch", mode = "n" },
				{ "<leader>sc", "<cmd>Telescope colorscheme<cr>", desc = "Colorscheme", mode = "n" },
				{ "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Find Help", mode = "n" },
				{ "<leader>sk", "<cmd>Telescope keymaps<cr>", desc = "Keymaps", mode = "n" },
				{ "<leader>sr", "<cmd>Telescope oldfiles<cr>", desc = "Open Recent File", mode = "n" },

				-- Git signs
				{ "<leader>g", group = "Git" },
				{
					"<leader>gj",
					"<cmd>lua require 'gitsigns'.next_hunk({navigation_message = false})<cr>",
					desc = "Next Hunk",
				},
				{
					"<leader>gk",
					"<cmd>lua require 'gitsigns'.prev_hunk({navigation_message = false})<cr>",
					desc = "Prev Hunk",
				},
				{ "<leader>gp", "<cmd>lua require 'gitsigns'.preview_hunk()<cr>", desc = "Preview Hunk" },
				{
					"<leader>gr",
					"<cmd>lua require 'gitsigns'.reset_hunk()<cr>",
					desc = "Reset Hunk",
					mode = { "n" },
				},
				{
					"<leader>gr",
					function()
						require("gitsigns").reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
					end,
					desc = "Reset Selected Hunk",
					mode = { "v" },
				},
				{ "<leader>gl", "<cmd>lua require 'gitsigns'.blame_line()<cr>", desc = "Blame" },
				{ "<leader>gR", "<cmd>lua require 'gitsigns'.reset_buffer()<cr>", desc = "Reset Buffer" },
				{
					"<leader>gs",
					"<cmd>lua require 'gitsigns'.stage_hunk()<cr>",
					desc = "Stage Hunk",
					mode = { "n" },
				},
				{
					"<leader>gs",
					function()
						require("gitsigns").stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
					end,
					desc = "Stage Selected Hunk",
					mode = { "v" },
				},
				{ "<leader>gu", "<cmd>lua require 'gitsigns'.undo_stage_hunk()<cr>", desc = "Undo Stage Hunk" },
				{ "<leader>gd", "<cmd>Gitsigns diffthis HEAD<cr>", desc = "Git Diff" },
			})
		end,
	},
}
