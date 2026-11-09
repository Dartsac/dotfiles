return {
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		build = "cd app && yarn install",
		init = function()
			vim.g.mkdp_filetypes = { "markdown" }
		end,
		-- Loaded before FileType for Markdown files: see plugins/markdown.lua.
		event = { "BufReadPre *.md,*.markdown", "BufNewFile *.md,*.markdown" },
		ft = { "markdown" },
	},
}
