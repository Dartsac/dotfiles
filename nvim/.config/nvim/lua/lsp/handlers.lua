-- lua/lsp/handlers.lua
local M = {}

local status_cmp_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if not status_cmp_ok then
	return
end

local icons = require("config.icons")

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

local function lsp_keymaps(bufnr, isTsserver)
	local opts = { noremap = true, silent = true }
	local keymap = vim.api.nvim_buf_set_keymap

	keymap(bufnr, "n", "gD", "<cmd>lua vim.lsp.buf.declaration()<CR>", opts)
	keymap(bufnr, "n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>", opts)
	keymap(bufnr, "n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>", opts)
	keymap(bufnr, "n", "gI", "<cmd>lua vim.lsp.buf.implementation()<CR>", opts)
	keymap(bufnr, "n", "gr", "<cmd>lua vim.lsp.buf.references()<CR>", opts)
	keymap(bufnr, "n", "gl", "<cmd>lua vim.diagnostic.open_float()<CR>", opts)

	if isTsserver then
		keymap(bufnr, "n", "<leader>o", "<cmd>TypescriptAddMissingImports<CR>", opts)
		keymap(bufnr, "n", "<leader>r", "<cmd>TypescriptRemoveUnused<CR>", opts)
	end

	-- Format on save
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = vim.api.nvim_create_augroup("LspFormatting" .. bufnr, { clear = true }),
		buffer = bufnr,
		callback = function()
			if isTsserver then
				require("typescript").actions.organizeImports({ sync = true })
			end
			vim.lsp.buf.format({ async = false })
		end,
	})
end

function M.on_attach(client, bufnr)
	if client.name == "tsserver" then
		client.server_capabilities.documentFormattingProvider = false
		client.server_capabilities.semanticTokensProvider = nil
		lsp_keymaps(bufnr, true)
	elseif client.name == "lua_ls" then
		client.server_capabilities.documentFormattingProvider = false
		lsp_keymaps(bufnr, false)
	else
		lsp_keymaps(bufnr, false)
	end
end

return M
