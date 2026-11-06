-- Marksman handles Markdown navigation everywhere except the Obsidian vault,
-- where obsidian.nvim's own language server ("obsidian-ls") provides
-- definitions, references, symbols and link completion. Running both there
-- would duplicate every gd/gr/completion result.
return {
	root_dir = function(bufnr, on_dir)
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		if require("config.vault").contains(vim.api.nvim_buf_get_name(bufnr)) then
			return
		end
		-- Same markers as nvim-lspconfig; no marker means single-file mode.
		on_dir(vim.fs.root(bufnr, { ".marksman.toml", ".git" }))
	end,
}
