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
		after = "mason.nvim",
		config = function()
			local servers = {
				"cssls",
				"html",
				"jsonls",
				"pyright",
				"lua_ls",
				"ts_ls",
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
		event = "BufReadPre",
		config = function()
			-- We'll do the main setup in lua/lsp/init.lua
			require("lsp").setup()
		end,
		dependencies = {
			{ "hrsh7th/cmp-nvim-lsp" }, -- For LSP capabilities
			-- { "nvimtools/none-ls.nvim" },
			-- { "jose-elias-alvarez/typescript.nvim" },
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
		"jose-elias-alvarez/typescript.nvim",
		lazy = true,
	},
}
