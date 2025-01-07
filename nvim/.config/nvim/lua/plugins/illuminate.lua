return {
	{
		"RRethy/vim-illuminate",
		event = "CursorHold",
		config = function()
			local status_ok, illuminate = pcall(require, "illuminate")
			if status_ok then
				illuminate.configure({
					providers = { "lsp", "treesitter", "regex" },
					delay = 200,
					filetypes_denylist = { "NvimTree", "harpoon", "TelescopePrompt", "TelescopeResults" },
					filetypes_allowlist = {},
					modes_denylist = { "v", "V", "nov", "noV", "CTRL-V", "noCTRL-V" },
					modes_allowlist = {},
					providers_regex_syntax_denylist = {},
					providers_regex_syntax_allowlist = {},
					under_cursor = true,
					large_file_cutoff = nil,
					large_file_overrides = nil,
					min_count_to_highlight = 1,
				})
			end
		end,
	},
}
