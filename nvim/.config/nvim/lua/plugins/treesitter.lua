-- lua/plugins/treesitter.lua
return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	dependencies = "nvim-treesitter/nvim-treesitter-context",
	build = ":TSUpdate",
	event = { "BufReadPre", "BufNewFile" },
	init = function()
		local highlight_disabled = { css = true, scss = true }
		local indent_disabled = { python = true, css = true }

		vim.api.nvim_create_autocmd("FileType", {
			callback = function()
				local ft = vim.bo.filetype
				if not highlight_disabled[ft] then
					pcall(vim.treesitter.start)
				end
				if not indent_disabled[ft] then
					vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
			end,
		})
	end,
	config = function()
		local ensure_installed = {
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
		}
		local already_installed = require("nvim-treesitter").get_installed()
		local to_install = vim.iter(ensure_installed)
			:filter(function(p)
				return not vim.tbl_contains(already_installed, p)
			end)
			:totable()
		if #to_install > 0 then
			require("nvim-treesitter").install(to_install)
		end
	end,
}
