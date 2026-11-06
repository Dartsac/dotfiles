-- Harper: local English grammar/spelling for Markdown (notes, READMEs, docs).
-- It owns Markdown spelling feedback, so native 'spell' stays off there while
-- harper-ls is installed (see config/autocommands.lua). Other filetypes keep
-- their own spell settings and get no Harper diagnostics.
--
-- Low noise: hint severity, no virtual text for Harper (underline + sign; gl
-- shows the message and rule), no long-sentence style lint. Fixes and
-- dictionary additions are code actions (<leader>la), never automatic.
return {
	filetypes = { "markdown" },
	settings = {
		["harper-ls"] = {
			dialect = "American",
			diagnosticSeverity = "hint",
			isolateEnglish = false,
			markdown = { IgnoreLinkTitle = true },
			linters = {
				LongSentences = false,
			},
		},
	},
	on_attach = function(client)
		for _, pull in ipairs({ false, true }) do
			vim.diagnostic.config({ virtual_text = false }, vim.lsp.diagnostic.get_namespace(client.id, pull))
		end
	end,
}
