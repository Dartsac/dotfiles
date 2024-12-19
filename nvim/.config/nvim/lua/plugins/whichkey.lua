return {
	{
		"folke/which-key.nvim",
		config = function()
			local wk = require("which-key")

			local function harpoon_desc(i)
				local ok, harpoon = pcall(require, "harpoon")
				if not ok then
					return "Harpoon to File " .. i
				end
				local list = harpoon:list()
				local items = list and list.items
				if items and items[i] then
					return items[i].value
				end
				return nil --[[ .. i ]]
			end

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
					local keys = mapping.keys or ""
					local num = keys:match("^<leader>(%d)$")
					if num then
						local ok, harpoon = pcall(require, "harpoon")
						if not ok then
							return true
						end
						local items = harpoon:list().items
						if not (items and items[tonumber(num)]) then
							return false
						end
					end
					return true
				end,
			})

			wk.add({
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
					mode = { "n", "v" },
				},
				{ "<leader>gl", "<cmd>lua require 'gitsigns'.blame_line()<cr>", desc = "Blame" },
				{ "<leader>gR", "<cmd>lua require 'gitsigns'.reset_buffer()<cr>", desc = "Reset Buffer" },
				{
					"<leader>gs",
					"<cmd>lua require 'gitsigns'.stage_hunk()<cr>",
					desc = "Stage Hunk",
					mode = { "n", "v" },
				},
				{ "<leader>gu", "<cmd>lua require 'gitsigns'.undo_stage_hunk()<cr>", desc = "Undo Stage Hunk" },
				{ "<leader>gd", "<cmd>Gitsigns diffthis HEAD<cr>", desc = "Git Diff" },
			})

			-- Define harpoon numeric keys only now that Harpoon is set up
			for i = 1, 5 do
				wk.add({
					{
						"<leader>" .. i,
						function()
							local ok, harpoon = pcall(require, "harpoon")
							if ok then
								harpoon:list():select(i)
							end
						end,
						desc = function()
							return harpoon_desc(i)
						end,
						mode = "n",
					},
				})
			end
		end,
	},
}
