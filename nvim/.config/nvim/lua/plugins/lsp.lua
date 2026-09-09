-- Unified LSP stack: Mason → mason-lspconfig → vim.lsp.config/enable.
--
-- nvim-lspconfig supplies the default config for each server (lsp/<name>.lua
-- on the runtimepath). Overrides live in lua/lsp/settings/<name>.lua and are
-- merged with vim.lsp.config(). mason-lspconfig installs the servers and
-- enables every Mason-installed one via vim.lsp.enable().

local servers = {
	"bashls",
	"cssls",
	"eslint",
	"html",
	"jsonls",
	"lua_ls",
	"marksman",
	"pyright",
	"ts_ls",
}

return {
	{
		"williamboman/mason.nvim",
		cmd = "Mason",
		opts = {
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
		},
	},

	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",
			{
				"folke/lazydev.nvim",
				ft = "lua",
				cmd = "LazyDev",
				opts = {
					library = {
						{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
					},
				},
			},
		},
	},

	{
		"williamboman/mason-lspconfig.nvim",
		dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local handlers = require("lsp.handlers")

			vim.lsp.config("*", { capabilities = handlers.capabilities })

			for _, name in ipairs(servers) do
				local path = "lua/lsp/settings/" .. name .. ".lua"
				if #vim.api.nvim_get_runtime_file(path, false) > 0 then
					vim.lsp.config(name, require("lsp.settings." .. name))
				end
			end

			require("mason-lspconfig").setup({
				ensure_installed = servers,
				-- Mason also installs tools that happen to have an lspconfig entry
				-- (stylua). Those are formatters run through null-ls, not servers.
				automatic_enable = { exclude = { "stylua" } },
			})
		end,
	},

	{
		"nvimtools/none-ls.nvim",
		dependencies = "neovim/nvim-lspconfig",
		event = "BufReadPre",
		config = function()
			require("lsp.null-ls").setup()
		end,
	},
}
