-- Unified LSP stack: Mason → mason‑lspconfig → lspconfig.
-- NOTE: the custom ‘lua_ls’ override has been removed; its settings now
-- live exclusively in lua/lsp/settings/lua_ls.lua to avoid duplication.

return {
	-------------------------------------------------------------------------
	-- Mason ----------------------------------------------------------------
	-------------------------------------------------------------------------
	{
		"williamboman/mason.nvim",
		cmd = "Mason",
		config = function()
			require("mason").setup({
				ui = {
					border = "none",
					icons = {
						package_installed = "✓",
						package_pending = "➜",
						package_uninstalled = "✗",
					},
				},
				log_level = vim.log.levels.INFO,
				max_concurrent_installers = 4,
			})
		end,
	},

	-------------------------------------------------------------------------
	-- mason‑lspconfig -------------------------------------------------------
	-------------------------------------------------------------------------
	{
		"williamboman/mason-lspconfig.nvim",
		dependencies = {
			"williamboman/mason.nvim",
			"neovim/nvim-lspconfig",
		},
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local servers = {
				-- core
				"bashls",
				"cssls",
				"eslint",
				"html",
				"jsonls",
				"lua_ls",
				"marksman",
				"pyright",
				-- language‑specific
				-- "jdtls",
			}

			local handlers = require("lsp.handlers")

			require("mason-lspconfig").setup({
				ensure_installed = servers,
				automatic_installation = true,
				automatic_enable = true,

				-- One generic handler plus per‑server overrides located
				-- in lua/lsp/settings/<server>.lua
				handlers = {
					function(name)
						local opts = {
							on_attach = handlers.on_attach,
							capabilities = handlers.capabilities,
						}

						local ok, custom = pcall(require, "lsp.settings." .. name)
						if ok then
							opts = vim.tbl_deep_extend("force", custom, opts)
						end

						require("lspconfig")[name].setup(opts)
					end,
				},
			})
		end,
	},

	-------------------------------------------------------------------------
	-- lspconfig (core) ------------------------------------------------------
	-------------------------------------------------------------------------
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",
			{
				"folke/lazydev.nvim",
				ft = "lua",
				cmd = "LadyDev",
				opts = {
					library = {
						{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
						{ path = "LazyVim", words = { "LazyVim" } },
						{ path = "snacks.nvim", words = { "Snacks" } },
						{ path = "lazy.nvim", words = { "LazyVim" } },
					},
				},
			},
		},
		config = function()
			-- All real LSP setup now happens in plugins/mason‑lspconfig above
			-- (kept here so :LspInfo still works before Mason loads).
		end,
	},

	-------------------------------------------------------------------------
	-- null‑ls ---------------------------------------------------------------
	-------------------------------------------------------------------------
	{
		"nvimtools/none-ls.nvim",
		dependencies = "neovim/nvim-lspconfig",
		event = "BufReadPre",
		config = function()
			require("lsp.null-ls").setup()
		end,
	},
}
