-- lua/lsp/handlers.lua
local M = {}

local cmp_nvim_lsp = require("cmp_nvim_lsp")
M.capabilities = cmp_nvim_lsp.default_capabilities(vim.lsp.protocol.make_client_capabilities())

local has_ui, lspui = pcall(require, "lspconfig.ui.windows")
if has_ui then
	lspui.default_options.border = "rounded"
end

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

function M.setup() end

vim.lsp.handlers["textDocument/hover"] = vim.lsp.buf.hover
vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.buf.signature_help

local wk = require("which-key")

local function set_typescript_keymaps(bufnr)
	wk.add({
		{ "<leader>t", buffer = bufnr, group = "TypeScript Tools" },
		{
			"<leader>ta",
			"<cmd>TSToolsAddMissingImports<CR>",
			buffer = bufnr,
			desc = "Add Missing Imports",
		},
		{
			"<leader>tr",
			"<cmd>TSToolsRemoveUnused<CR>",
			buffer = bufnr,
			desc = "Remove Unused Imports",
		},
		{ "<leader>to", "<cmd>TSToolsOrganizeImports<CR>", buffer = bufnr, desc = "Organize Imports" },
		{ "<leader>ti", "<cmd>TSToolsSortImports<CR>", buffer = bufnr, desc = "Sort Imports" },
		{
			"<leader>tu",
			"<cmd>TSToolsRemoveUnusedImports<CR>",
			buffer = bufnr,
			desc = "Remove Unused Imports",
		},
		{ "<leader>tf", "<cmd>TSToolsFixAll<CR>", buffer = bufnr, desc = "Fix All Errors" },
		{
			"<leader>tg",
			"<cmd>TSToolsGoToSourceDefinition<CR>",
			buffer = bufnr,
			desc = "Go to Source Definition",
		},
		{ "<leader>tR", "<cmd>TSToolsRenameFile<CR>", buffer = bufnr, desc = "Rename File" },
		{ "<leader>tF", "<cmd>TSToolsFileReferences<CR>", buffer = bufnr, desc = "File References" },
	})
end

local function lsp_keymaps(client, bufnr)
	wk.add({
		{ "K", "<cmd>lua vim.lsp.buf.hover()<CR>", buffer = bufnr, desc = "Hover Documentation" },
		{ "gD", "<cmd>lua vim.lsp.buf.declaration()<CR>", buffer = bufnr, desc = "Go to Declaration" },
		{ "gI", "<cmd>lua vim.lsp.buf.implementation()<CR>", buffer = bufnr, desc = "Go to Implementation" },
		{ "gd", "<cmd>lua vim.lsp.buf.definition()<CR>", buffer = bufnr, desc = "Go to Definition" },
		{ "gr", "<cmd>lua vim.lsp.buf.references()<CR>", buffer = bufnr, desc = "Find References" },
		{ "gl", "<cmd>lua vim.diagnostic.open_float()<CR>", buffer = bufnr, desc = "Open Diagnostics" },
	})

	if client.name == "typescript-tools" then
		set_typescript_keymaps(bufnr)
	end
end

local function enable_formatting_on_save(bufnr)
	if vim.b[bufnr].format_on_save_registered then
		return
	end
	vim.b[bufnr].format_on_save_registered = true

	vim.api.nvim_create_autocmd("BufWritePre", {
		buffer = bufnr,
		callback = function()
			vim.lsp.buf.format({
				filter = function(client)
					return client.name == "null-ls"
				end,
			})
		end,
	})
end

function M.on_attach(client, bufnr)
	lsp_keymaps(client, bufnr)
	enable_formatting_on_save(bufnr)
end

vim.api.nvim_create_autocmd("BufEnter", {
	callback = function()
		local bufnr = vim.api.nvim_get_current_buf()
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			if client.name == "typescript-tools" then
				set_typescript_keymaps(bufnr)
				break
			end
		end
	end,
})

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client and client.name == "typescript-tools" then
			set_typescript_keymaps(args.buf)
		end
	end,
})

return M
