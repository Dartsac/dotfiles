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
	-- Provenance in the float: always the source (tool), plus the rule/error code
	-- when the server supplies one. gl shows this; <leader>ly copies it.
	float = {
		style = "minimal",
		border = "rounded",
		source = true,
		suffix = function(diagnostic)
			if diagnostic.code == nil or diagnostic.code == "" then
				return ""
			end
			return string.format(" [%s]", diagnostic.code), "Comment"
		end,
	},
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
-- Formatting: policy and routing live in lua/lsp/formatting.lua so that
-- format-on-save, <leader>lf and the tooling report always agree.
-------------------------------------------------------------------------------
M.format = require("lsp.formatting").format

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
		{ "gl", vim.diagnostic.open_float, buffer = bufnr, desc = "Show Diagnostics (source, code)" },
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
