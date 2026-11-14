-- Markdown: hybrid rendering, list/table assistance, and navigation-first
-- Obsidian support for the one configured vault, if any. Buffer behaviour and
-- keys live in lua/config/markdown.lua (attached from
-- after/ftplugin/markdown.lua).
-- The browser preview stays in markdown-preview.lua; Harper and Marksman are
-- configured with the other language servers.
local vault = require("config.vault")

-- Markdown plugins load as a Markdown file is read, before its FileType. Loaded
-- by `ft` alone, lazy.nvim replays FileType for the buffer, so the ftplugins
-- run twice and Neovim's undo_ftplugin stops treesitter, which reloads the
-- regex syntax files (markdown, html, css…) only to start treesitter again.
-- `ft` stays as the fallback for buffers with no Markdown file name. The same
-- list is in otter.lua and markdown-preview.lua.
local markdown_open = { "BufReadPre *.md,*.markdown", "BufNewFile *.md,*.markdown" }

return {
	{
		"MeanderingProgrammer/render-markdown.nvim",
		event = markdown_open,
		ft = "markdown",
		dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" },
		opts = {
			file_types = { "markdown" },
			-- Rendered in normal/command mode; insert mode shows the raw source.
			-- The cursor line is always raw (anti-conceal). <leader>dr toggles a
			-- buffer between rendered and raw. 'conceallevel' is only changed
			-- in rendered Markdown windows, by the plugin's win_options.
			render_modes = { "n", "c", "t" },
			anti_conceal = { enabled = true },
			-- No external LaTeX converters in the render loop.
			latex = { enabled = false },
			completions = { lsp = { enabled = false } },
		},
		config = function(_, opts)
			-- With no completion integration enabled, render-markdown registers an
			-- nvim-cmp source on attach; its pcall(require, "cmp") makes lazy.nvim
			-- load nvim-cmp, LuaSnip and every snippet (~40 ms) as the first
			-- Markdown file opens. That source is not in cmp's sources
			-- (plugins/cmp.lua), so it would never be asked: skip registering it
			-- and leave cmp to load on InsertEnter.
			package.loaded["render-markdown.integ.cmp"] = { init = function() end }
			require("render-markdown").setup(opts)
		end,
	},

	{
		-- List continuation and nesting. Mappings are made by config.markdown
		-- (so they can be switched off per buffer and skip code fences).
		"bullets-vim/bullets.vim",
		event = markdown_open,
		ft = "markdown",
		init = function()
			vim.g.bullets_enabled_file_types = { "markdown" }
			vim.g.bullets_enable_in_empty_buffers = 0
			vim.g.bullets_set_mappings = 0
			vim.g.bullets_custom_mappings = {}
			-- Plain [ ]/[x] tasks with no cascading parent/child updates (the
			-- checkbox toggle is config.markdown's, not bullets').
			vim.g.bullets_nested_checkboxes = 0
			vim.g.bullets_checkbox_markers = " x"
			-- Keep to CommonMark lists and avoid churn with Prettier.
			vim.g.bullets_enable_roman_list = 0
			vim.g.bullets_max_alpha_characters = 0
			vim.g.bullets_pad_right = 0
			vim.g.bullets_auto_indent_after_colon = 0
			-- Enter on an empty item outdents it, or ends the list at the top level.
			vim.g.bullets_delete_last_bullet_if_empty = 2
		end,
	},

	{
		-- Automatic table alignment and cell helpers. Its own mappings are off;
		-- config.markdown maps the helpers under <leader>dt per buffer.
		"dhruvasagar/vim-table-mode",
		event = markdown_open,
		ft = "markdown",
		cmd = { "TableModeEnable", "TableModeDisable", "TableModeToggle", "TableModeRealign", "Tableize" },
		init = function()
			vim.g.table_mode_disable_mappings = 1
			vim.g.table_mode_disable_tableize_mappings = 1
			-- Markdown pipe tables: | a | b | / |---|---|.
			vim.g.table_mode_corner = "|"
			vim.g.table_mode_corner_corner = "|"
			vim.g.table_mode_header_fillchar = "-"
			vim.g.table_mode_verbose = 0
		end,
	},

	{
		"obsidian-nvim/obsidian.nvim",
		version = "*",
		dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
		-- Loaded only for notes in the vault (see init) and by the vault-only
		-- keys and the command.
		lazy = true,
		cmd = "Obsidian",
		init = function()
			-- No <CR>/<C-a>/<C-x>/]o/[o buffer keys; config.markdown provides keys.
			vim.g.obsidian_default_keymap = false
			-- The vault-only keys, where a vault is configured. Asked at VeryLazy,
			-- once the local override that names the vault has loaded.
			vim.api.nvim_create_autocmd("User", {
				pattern = "VeryLazy",
				once = true,
				callback = function()
					if not vault.path() then
						return
					end
					vim.keymap.set("n", "<leader>dn", "<cmd>Obsidian quick_switch<cr>", { desc = "Find Vault Note" })
					vim.keymap.set("n", "<leader>dg", "<cmd>Obsidian search<cr>", { desc = "Grep Vault Notes" })
				end,
			})
			-- Load for any Markdown file config.vault counts as a vault note,
			-- including one reached through a symlink from outside the vault.
			-- Marksman is excluded by the same test (lsp/settings/marksman.lua),
			-- so a vault note always has exactly one navigation provider.
			vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
				group = vim.api.nvim_create_augroup("obsidian_vault_load", { clear = true }),
				pattern = { "*.md", "*.markdown" },
				callback = function(ev)
					if vault.contains(ev.match) then
						require("lazy").load({ plugins = { "obsidian.nvim" } })
						return true -- loaded: remove this autocmd
					end
				end,
			})
		end,
		opts = function()
			local path = vault.path()
			if not path then
				-- Only :Obsidian loads it without a vault.
				error("No Obsidian vault: set vim.g.obsidian_vault in lua/config/local.lua", 0)
			end
			return {
				legacy_commands = false,
				workspaces = { { name = "vault", path = path } },
				picker = {
					name = "telescope.nvim",
					-- No note creation or tagging from pickers in this iteration.
					note_mappings = { new = "", insert_link = "<C-l>", bookmark = "" },
					tag_mappings = { tag_note = "", insert_tag = "<C-l>" },
				},
				-- Obsidian's defaults: [[wiki links]], shortest path. Never rewrite
				-- links silently; renames ask before updating references.
				link = { style = "wiki", format = "shortest", auto_update = false },
				completion = { min_chars = 2, create_new = false },
				-- Never inject IDs/properties into notes on save.
				frontmatter = { enabled = false },
				-- Rendering is render-markdown's job; no footer/statusline extras.
				ui = { enable = false },
				footer = { enabled = false },
				statusline = { enabled = false },
				-- Out of scope this iteration: creation workflows, sync, slides.
				daily_notes = { enabled = false },
				templates = { enabled = false },
				unique_note = { enabled = false },
				slides = { enabled = false },
				sync = { enabled = false },
				checkbox = { enabled = false },
			}
		end,
		config = function(_, opts)
			require("obsidian").setup(opts)
			-- Embedded-note rendering (![[note]] previews) is deferred; obsidian.nvim
			-- has no option for it, so make its per-buffer attach a no-op.
			local ok, embed = pcall(require, "obsidian.embed")
			if ok and type(embed.attach) == "function" then
				embed.attach = function() end
			end
		end,
	},
}
