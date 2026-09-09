-- lua/lsp/settings/lua_ls.lua
-- Formatting is handled by StyLua via null-ls. Neovim runtime and plugin
-- libraries are provided by lazydev.
return {
	settings = {
		Lua = {
			semantic = { enable = false },
			diagnostics = { globals = { "vim" } },
		},
	},
}
