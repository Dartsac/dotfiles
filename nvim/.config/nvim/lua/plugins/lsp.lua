-- Runtime: nvim-lspconfig defaults → vim.lsp.config/enable.
-- Installation: :Mason / :LspInstall loads Mason and mason-lspconfig.
-- Only the servers below are enabled; installation stays off the file-open path.

local servers = {
	"bashls",
	"cssls",
	"eslint",
	"harper_ls",
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
		init = function()
			-- Match Mason's default install root without loading its modules.
			local bin = vim.fn.stdpath("data") .. "/mason/bin"
			if not vim.tbl_contains(vim.split(vim.env.PATH or "", ":", { plain = true }), bin) then
				vim.env.PATH = bin .. ":" .. (vim.env.PATH or "")
			end
		end,
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
		config = function()
			local handlers = require("lsp.handlers")

			vim.lsp.config("*", { capabilities = handlers.capabilities })

			for _, name in ipairs(servers) do
				local path = "lua/lsp/settings/" .. name .. ".lua"
				if #vim.api.nvim_get_runtime_file(path, false) > 0 then
					vim.lsp.config(name, require("lsp.settings." .. name))
				end
			end

			vim.lsp.enable(servers)
		end,
	},

	{
		"williamboman/mason-lspconfig.nvim",
		cmd = { "Mason", "LspInstall", "LspUninstall" },
		dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
		opts = {
			-- Opening an installer command provisions missing configured servers.
			ensure_installed = servers,
			automatic_enable = false,
		},
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
