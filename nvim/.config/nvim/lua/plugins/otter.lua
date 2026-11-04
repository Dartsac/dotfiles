return {
	"jmbuhr/otter.nvim",
	ft = "markdown",
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	opts = {
		buffers = {
			-- FileType triggers the existing vim.lsp.enable() server setup.
			set_filetype = true,
			write_to_disk = false,
		},
	},
	init = function()
		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("_markdown_otter", { clear = true }),
			pattern = "markdown",
			desc = "Enable language servers in Markdown code fences",
			callback = function()
				-- Requiring the module lazy-loads and configures the plugin first.
				require("otter").activate()
			end,
		})
	end,
}
