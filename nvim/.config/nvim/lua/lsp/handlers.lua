-- lua/lsp/handlers.lua
-- Shared LSP behaviour: capabilities, diagnostics UI, keymaps, formatting.
-- Per-server settings live in lua/lsp/settings/<server>.lua and are applied
-- with vim.lsp.config() from lua/plugins/lsp.lua.
local M = {}

M.capabilities = require("cmp_nvim_lsp").default_capabilities()

local icons = require("config.icons")
local s = vim.diagnostic.severity
vim.diagnostic.config({
	virtual_text = true,
	update_in_insert = false,
	severity_sort = true,
	float = { style = "minimal", border = "rounded", source = "if_many" },
	signs = {
		text = {
			[s.ERROR] = icons.diagnostics.BoldError,
			[s.WARN] = icons.diagnostics.BoldWarning,
			[s.INFO] = icons.diagnostics.BoldInformation,
			[s.HINT] = icons.diagnostics.BoldHint,
		},
		numhl = {},
	},
})

-------------------------------------------------------------------------------
-- Formatting
-- null-ls is the preferred formatter. When it has no formatter for the buffer,
-- fall back to any LSP client that can format. Used by both format-on-save and
-- <leader>lf so the two always agree.
-------------------------------------------------------------------------------
local function null_ls_formats(bufnr)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = "null-ls" })) do
		if client:supports_method("textDocument/formatting", bufnr) then
			return true
		end
	end
	return false
end

---@param opts? { bufnr?: integer, async?: boolean }
function M.format(opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/formatting" }) == 0 then
		return
	end
	local prefer_null = null_ls_formats(bufnr)
	vim.lsp.buf.format({
		bufnr = bufnr,
		async = opts.async,
		filter = function(client)
			if prefer_null then
				return client.name == "null-ls"
			end
			return true
		end,
	})
end

local group = vim.api.nvim_create_augroup("_lsp", { clear = true })

vim.api.nvim_create_autocmd("BufWritePre", {
	group = group,
	desc = "Format on save",
	callback = function(args)
		if vim.b[args.buf].disable_format_on_save then
			return
		end
		M.format({ bufnr = args.buf })
	end,
})

-------------------------------------------------------------------------------
-- Keymaps
-------------------------------------------------------------------------------
local wk = require("which-key")

local function lsp_keymaps(bufnr)
	wk.add({
		{ "K", vim.lsp.buf.hover, buffer = bufnr, desc = "Hover Documentation" },
		{ "gD", vim.lsp.buf.declaration, buffer = bufnr, desc = "Go to Declaration" },
		{ "gI", vim.lsp.buf.implementation, buffer = bufnr, desc = "Go to Implementation" },
		{ "gd", vim.lsp.buf.definition, buffer = bufnr, desc = "Go to Definition" },
		{ "gr", vim.lsp.buf.references, buffer = bufnr, desc = "Find References" },
		{ "gl", vim.diagnostic.open_float, buffer = bufnr, desc = "Open Diagnostics" },
	})
end

-- ts_ls exposes its refactors as source code actions; run one without a picker.
local function ts_action(kind)
	return function()
		vim.lsp.buf.code_action({ context = { only = { kind }, diagnostics = {} }, apply = true })
	end
end

local function typescript_keymaps(bufnr)
	wk.add({
		{ "<leader>t", buffer = bufnr, group = "TypeScript" },
		{ "<leader>ta", ts_action("source.addMissingImports.ts"), buffer = bufnr, desc = "Add Missing Imports" },
		{ "<leader>tu", ts_action("source.removeUnusedImports.ts"), buffer = bufnr, desc = "Remove Unused Imports" },
		{ "<leader>tr", ts_action("source.removeUnused.ts"), buffer = bufnr, desc = "Remove Unused" },
		{ "<leader>to", ts_action("source.organizeImports.ts"), buffer = bufnr, desc = "Organize Imports" },
		{ "<leader>ti", ts_action("source.sortImports.ts"), buffer = bufnr, desc = "Sort Imports" },
		{ "<leader>tf", ts_action("source.fixAll.ts"), buffer = bufnr, desc = "Fix All" },
	})
end

vim.api.nvim_create_autocmd("LspAttach", {
	group = group,
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if not client then
			return
		end
		lsp_keymaps(args.buf)
		if client.name == "ts_ls" then
			typescript_keymaps(args.buf)
		end
	end,
})

return M
