-- lua/plugins/treesitter.lua
return {
	"nvim-treesitter/nvim-treesitter",
	dependencies = "nvim-treesitter/nvim-treesitter-context",
	build = ":TSUpdate",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local ok, ts = pcall(require, "nvim-treesitter.configs")
		if not ok then
			return
		end

		ts.setup({
			modules = {}, -- satisfy the stub
			sync_install = false, -- if you really want true, change it
			ensure_installed = {
				"bash",
				"c",
				"css",
				"scss",
				"fish",
				"html",
				"java",
				"javascript",
				"json",
				"lua",
				"markdown",
				"markdown_inline",
				"php",
				"python",
				"rust",
				"swift",
				"tsx",
				"typescript",
				"yaml",
			},
			ignore_install = { "phpdoc" },
			highlight = { enable = true, disable = { "css", "scss" } },
			auto_install = true,
			autopairs = { enable = true },
			indent = { enable = true, disable = { "python", "css" } },
		})
	end,
}
