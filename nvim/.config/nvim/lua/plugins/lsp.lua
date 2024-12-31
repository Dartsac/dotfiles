-- lua/plugins/lsp.lua
return {
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

	{
		"williamboman/mason-lspconfig.nvim",
		dependencies = "williamboman/mason.nvim",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local servers = {
				"cssls",
				"html",
				"jsonls",
				"pyright",
				"lua_ls",
				"jdtls",
			}
			require("mason-lspconfig").setup({
				ensure_installed = servers,
				automatic_installation = true,
			})
		end,
	},

	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			-- We'll do the main setup in lua/lsp/init.lua
			require("lsp").setup()
		end,
		dependencies = {
			{ "hrsh7th/cmp-nvim-lsp" }, -- For LSP capabilities
			{
				"folke/lazydev.nvim",
				ft = "lua", -- only load on lua files
				cmd = "LadyDev",
				opts = {
					library = {
						-- See the configuration section for more details
						-- Load luvit types when the `vim.uv` word is found
						{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
						{ path = "LazyVim", words = { "LazyVim" } },
						{ path = "snacks.nvim", words = { "Snacks" } },
						{ path = "lazy.nvim", words = { "LazyVim" } },
					},
				},
			},
		},
	},

	{
		"nvimtools/none-ls.nvim",
		enabled = true,
		event = "BufReadPre",
		config = function()
			-- We'll handle this in lua/lsp/null-ls.lua
			require("lsp.null-ls").setup()
		end,
	},

	{
		"pmizio/typescript-tools.nvim",
		ft = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
		dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
		opts = {},
	},
}
