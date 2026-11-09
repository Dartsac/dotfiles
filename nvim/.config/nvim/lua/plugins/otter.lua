return {
	"jmbuhr/otter.nvim",
	-- Loaded before FileType for Markdown files: see plugins/markdown.lua.
	event = { "BufReadPre *.md,*.markdown", "BufNewFile *.md,*.markdown" },
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
			callback = function(args)
				-- LSP hover/signature floats are unnamed scratch buffers with
				-- filetype=markdown. Otter derives its hidden buffer names from the
				-- main buffer's path, so every float maps to the same name and the
				-- second one fails with E95. Only attach to real files.
				if vim.bo[args.buf].buftype ~= "" or vim.api.nvim_buf_get_name(args.buf) == "" then
					return
				end
				-- Requiring the module lazy-loads and configures the plugin first.
				require("otter").activate()
			end,
		})
	end,
}
