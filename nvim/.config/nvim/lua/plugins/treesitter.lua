-- lua/plugins/treesitter.lua
return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	dependencies = "nvim-treesitter/nvim-treesitter-context",
	build = ":TSUpdate",
	lazy = false, -- The rewritten main branch does not support lazy-loading.
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
		-- Parsers are built on this machine, which needs the tree-sitter CLI, a C
		-- compiler and curl. Without them, none are installed and Neovim's own
		-- parsers (C, Lua, Markdown, Vim script, Vim help, queries) still work.
		local can_build = vim.fn.executable("tree-sitter") == 1
			and vim.fn.executable(vim.env.CC or "cc") == 1
			and vim.fn.executable("curl") == 1
		if not can_build then
			return
		end
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
			-- The summary ("Installed 19/19 languages") says when a first start's
			-- parsers are ready.
			require("nvim-treesitter").install(to_install, { summary = true })
		end
	end,
}
