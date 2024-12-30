-- lua/lsp/handlers.lua
local M = {}

local status_cmp_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if not status_cmp_ok then
	return
end

local icons = require("config.icons")
local wk = require("which-key")

M.capabilities = cmp_nvim_lsp.default_capabilities(vim.lsp.protocol.make_client_capabilities())

function M.setup()
	local signs = {
		{ name = "DiagnosticSignError", text = icons.diagnostics.BoldError },
		{ name = "DiagnosticSignWarn", text = icons.diagnostics.BoldWarning },
		{ name = "DiagnosticSignHint", text = icons.diagnostics.BoldHint },
		{ name = "DiagnosticSignInfo", text = icons.diagnostics.BoldInformation },
	}

	for _, sign in ipairs(signs) do
		vim.fn.sign_define(sign.name, { texthl = sign.name, text = sign.text, numhl = "" })
	end

	local config = {
		virtual_text = true,
		signs = { active = signs },
		update_in_insert = true,
		severity_sort = true,
		float = {
			focusable = true,
			style = "minimal",
			border = "rounded",
			source = "always",
		},
	}

	vim.diagnostic.config(config)

	vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded" })
	vim.lsp.handlers["textDocument/signatureHelp"] =
		vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded" })
end

local function set_typescript_keymaps(bufnr)
	local ts_mappings = {
		{ "<leader>t", buffer = bufnr, group = "TypeScript Tools" },
		{ "<leader>ta", "<cmd>TSToolsAddMissingImports<CR>", buffer = bufnr, desc = "Add Missing Imports" },
		{ "<leader>tr", "<cmd>TSToolsRemoveUnused<CR>", buffer = bufnr, desc = "Remove Unused Imports" },
		{ "<leader>to", "<cmd>TSToolsOrganizeImports<CR>", buffer = bufnr, desc = "Organize Imports" },
		{ "<leader>ti", "<cmd>TSToolsSortImports<CR>", buffer = bufnr, desc = "Sort Imports" },
		{ "<leader>tu", "<cmd>TSToolsRemoveUnusedImports<CR>", buffer = bufnr, desc = "Remove Unused Imports" },
		{ "<leader>tf", "<cmd>TSToolsFixAll<CR>", buffer = bufnr, desc = "Fix All Errors" },
		{ "<leader>tg", "<cmd>TSToolsGoToSourceDefinition<CR>", buffer = bufnr, desc = "Go to Source Definition" },
		{ "<leader>tR", "<cmd>TSToolsRenameFile<CR>", buffer = bufnr, desc = "Rename File" },
		{ "<leader>tF", "<cmd>TSToolsFileReferences<CR>", buffer = bufnr, desc = "File References" },
	}
	wk.add(ts_mappings)
end

local function lsp_keymaps(client, bufnr)
	local common_mappings = {
		{ "K", "<cmd>lua vim.lsp.buf.hover()<CR>", buffer = bufnr, desc = "Hover Documentation" },
		{ "gD", "<cmd>lua vim.lsp.buf.declaration()<CR>", buffer = bufnr, desc = "Go to Declaration" },
		{ "gI", "<cmd>lua vim.lsp.buf.implementation()<CR>", buffer = bufnr, desc = "Go to Implementation" },
		{ "gd", "<cmd>lua vim.lsp.buf.definition()<CR>", buffer = bufnr, desc = "Go to Definition" },
		{ "gr", "<cmd>lua vim.lsp.buf.references()<CR>", buffer = bufnr, desc = "Find References" },
		{ "gl", "<cmd>lua vim.diagnostic.open_float()<CR>", buffer = bufnr, desc = "Open Diagnostics" },
	}
	wk.add(common_mappings)

	if client.name == "typescript-tools" then
		set_typescript_keymaps(bufnr)
	end
end

local function enable_formatting_on_save(bufnr)
	vim.api.nvim_create_autocmd("BufWritePre", {
		buffer = bufnr,
		callback = function()
			vim.lsp.buf.format()
		end,
	})
end

function M.on_attach(client, bufnr)
	if client.name == "lua_ls" or client.name == "cssls" or client.name == "typescript-tools" then
		client.server_capabilities.documentFormattingProvider = false
		client.server_capabilities.documentRangeFormattingProvider = false
	end

	lsp_keymaps(client, bufnr)

	if client.name == "typescript-tools" then
		set_typescript_keymaps(bufnr)
	end

	enable_formatting_on_save(bufnr)
end

-- Autocommand to dynamically set TypeScript-specific keymaps
vim.api.nvim_create_autocmd("BufEnter", {
	callback = function()
		local bufnr = vim.api.nvim_get_current_buf()
		local clients = vim.lsp.get_clients({ bufnr = bufnr })

		for _, client in ipairs(clients) do
			if client.name == "typescript-tools" then
				set_typescript_keymaps(bufnr)
				return
			end
		end
	end,
})

-- Autocommand for LSP attachment to ensure keymaps are applied dynamically
vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local bufnr = args.buf
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client and client.name == "typescript-tools" then
			set_typescript_keymaps(bufnr)
		end
	end,
})

return M
