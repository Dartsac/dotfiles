return {
	"nvim-treesitter/nvim-treesitter",
	dependencies = "nvim-treesitter/nvim-treesitter-context",
	build = ":TSUpdate",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local status_ok, configs = pcall(require, "nvim-treesitter.configs")
		if not status_ok then
			return
		end

		configs.setup({
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
			}, -- one of "all" or a list of languages
			ignore_install = { "phpdoc" }, -- List of parsers to ignore installing
			highlight = {
				enable = true, -- false will disable the whole extension
				disable = { "css", "scss" }, -- list of language that will be disabled
			},
			auto_install = true,
			autopairs = {
				enable = true,
			},
			indent = { enable = true, disable = { "python", "css" } },
		})
	end,
}
