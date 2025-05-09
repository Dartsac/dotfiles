return {
	"numToStr/Comment.nvim",
	dependencies = { "JoosepAlviste/nvim-ts-context-commentstring" },
	event = "BufReadPost",
	config = function()
		require("ts_context_commentstring").setup({ enable_autocmd = false })

		---@diagnostic disable: missing-fields
		require("Comment").setup({
			padding = true,
			sticky = true,
			mappings = { basic = true, extra = false },
			toggler = { line = "gcc", block = "gbc" },
			opleader = { line = "gc", block = "gb" },
			extra = { above = "gcO", below = "gco", eol = "gcA" },

			-- keep ts‑context‑commentstring working
			pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),
		})
	end,
}
