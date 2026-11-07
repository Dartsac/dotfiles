-- lua/lsp/formatting.lua
-- The one formatting policy, shared by format-on-save, <leader>lf and the
-- tooling report/statusline (so what is reported is what format() runs):
--
--   null-ls is preferred when it reports formatting support for the buffer.
--   Otherwise every attached client that can format is allowed, so more than
--   one fallback client may format. No retry happens if a formatter fails.
--
-- Dependency-free on purpose: the statusline can ask for the route without
-- loading the LSP keymap/handler module.
local M = {}

local METHOD = "textDocument/formatting"

--- How long a synchronous format (format-on-save) waits for each formatting
--- client before that client's edits are skipped. A ceiling, not a delay: a
--- running formatter answers in well under 100 ms. It applies per client, so
--- the fallback route with several formatting servers could wait up to this
--- long for each; the null-ls route is one client. Neovim's default (1000 ms)
--- was missed by prettierd's first answer after its daemon starts on a busy
--- machine. Ignored by async formats (<leader>lf).
M.TIMEOUT_MS = 3000

local function in_buffer(bufnr, fn)
	-- none-ls answers supports_method() for the *current* buffer's filetype, as
	-- vim.lsp.buf.format does when it runs. Evaluate in that buffer's context.
	if bufnr == vim.api.nvim_get_current_buf() then
		return fn()
	end
	return vim.api.nvim_buf_call(bufnr, fn)
end

---@class FormatRoute
---@field bufnr integer
---@field prefer_null_ls boolean null-ls reports formatting support for the buffer
---@field clients vim.lsp.Client[] clients format() will call, in call order
---@field filter fun(client: vim.lsp.Client): boolean

---@param bufnr? integer
---@return FormatRoute
function M.route(bufnr)
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	return in_buffer(bufnr, function()
		-- Same client query vim.lsp.buf.format() makes before applying the filter.
		local capable = vim.lsp.get_clients({ bufnr = bufnr, method = METHOD })
		local prefer_null_ls = false
		for _, client in ipairs(capable) do
			if client.name == "null-ls" then
				prefer_null_ls = true
			end
		end
		local function filter(client)
			if prefer_null_ls then
				return client.name == "null-ls"
			end
			return true
		end
		return {
			bufnr = bufnr,
			prefer_null_ls = prefer_null_ls,
			clients = vim.tbl_filter(filter, capable),
			filter = filter,
		}
	end)
end

--- null-ls sources registered for this buffer's filetype and method.
--- Applicable means eligible, not that the tool is installed or has run.
---@param bufnr integer
---@param method? string null-ls internal method (default: formatting)
---@return table[]
function M.null_ls_sources(bufnr, method)
	local ok, sources = pcall(require, "null-ls.sources")
	if not ok then
		return {}
	end
	method = method or require("null-ls.methods").internal.FORMATTING
	return sources.get_available(vim.bo[bufnr].filetype, method)
end

---@param bufnr integer
---@return boolean
function M.format_on_save(bufnr)
	return not vim.b[bufnr].disable_format_on_save
end

---@param opts? { bufnr?: integer, async?: boolean }
function M.format(opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local route = M.route(bufnr)
	if #route.clients == 0 then
		return
	end
	in_buffer(bufnr, function()
		vim.lsp.buf.format({
			bufnr = bufnr,
			async = opts.async,
			filter = route.filter,
			timeout_ms = M.TIMEOUT_MS,
		})
	end)
end

return M
