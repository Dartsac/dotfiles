-- lua/lsp/settings/cssls.lua
return {
	init_options = { provideFormatter = false },
	settings = {
		css = { validate = true, format = { enable = false } },
		scss = { validate = true, format = { enable = false } },
		less = { validate = true, format = { enable = false } },
	},
}
