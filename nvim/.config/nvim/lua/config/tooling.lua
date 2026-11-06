-- Current-buffer tooling visibility: a compact statusline summary and the
-- detailed <leader>li report. Both read lsp/formatting.lua's route, the same
-- function format-on-save and <leader>lf use, so the report describes what a
-- format request will call. "Applicable" and "selected" describe eligibility;
-- neither proves a tool is installed or ran successfully.
--
-- The summary only queries in-memory client/source state. Executable lookups
-- (PATH searches) happen in the on-demand report, never in the statusline.
local formatting = require("lsp.formatting")

local M = {}

local NULL_LS = "null-ls"

local function is_file_buffer(bufnr)
	return vim.bo[bufnr].buftype == ""
end

local function names(list, key)
	return vim.tbl_map(function(item)
		return item[key or "name"]
	end, list)
end

local function null_ls_methods()
	local ok, methods = pcall(require, "null-ls.methods")
	if not ok then
		return nil
	end
	local internal = methods.internal
	return {
		{ "formatting", internal.FORMATTING },
		{ "range formatting", internal.RANGE_FORMATTING },
		{ "diagnostics", internal.DIAGNOSTICS },
		{ "diagnostics on open", internal.DIAGNOSTICS_ON_OPEN },
		{ "diagnostics on save", internal.DIAGNOSTICS_ON_SAVE },
		{ "code actions", internal.CODE_ACTION },
		{ "hover", internal.HOVER },
		{ "completion", internal.COMPLETION },
	}
end

--- What the formatting route will call, as short labels.
---@param route FormatRoute
---@return string[] labels, boolean via_null_ls
local function route_labels(route)
	if route.prefer_null_ls then
		local sources = names(formatting.null_ls_sources(route.bufnr))
		return #sources > 0 and sources or { NULL_LS }, true
	end
	return names(route.clients), false
end

---@class ToolingState
---@field clients string[] attached clients other than null-ls
---@field null_ls boolean null-ls attached
---@field formatters string[] selected formatting route labels
---@field via_null_ls boolean
---@field format_on_save boolean

---@param bufnr? integer
---@return ToolingState|nil nil for special (non-file) buffers
function M.state(bufnr)
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	if not is_file_buffer(bufnr) then
		return nil
	end
	local clients, null_ls = {}, false
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		if client.name == NULL_LS then
			null_ls = true
		else
			clients[#clients + 1] = client.name
		end
	end
	table.sort(clients)
	local formatters, via_null_ls = route_labels(formatting.route(bufnr))
	return {
		clients = clients,
		null_ls = null_ls,
		formatters = formatters,
		via_null_ls = via_null_ls,
		format_on_save = formatting.format_on_save(bufnr),
	}
end

local function truncate(text, max_width)
	if not max_width or vim.fn.strdisplaywidth(text) <= max_width then
		return text
	end
	if max_width <= 1 then
		return "…"
	end
	return vim.fn.strcharpart(text, 0, max_width - 1) .. "…"
end

--- Compact statusline text, e.g. `lua_ls │ fmt stylua` or `no LSP │ fmt none`.
---@param bufnr? integer
---@param max_width? integer truncate to this display width
---@return string
function M.summary(bufnr, max_width)
	local state = M.state(bufnr)
	if not state then
		return ""
	end
	local lsp = #state.clients > 0 and table.concat(state.clients, ",") or (state.null_ls and NULL_LS or "no LSP")
	local fmt = #state.formatters > 0 and table.concat(state.formatters, ",") or "none"
	local text = lsp .. " │ fmt " .. fmt
	if #state.formatters > 0 and not state.format_on_save then
		text = text .. " (save off)"
	end
	return truncate(text, max_width)
end

--- Statusline width budget for the current window; 0 hides the summary.
---@param winwidth integer
---@return integer
function M.summary_width(winwidth)
	if winwidth < 70 then
		return 0
	end
	return math.max(16, math.floor(winwidth * 0.3))
end

local function command_status(source)
	local opts = source.generator and source.generator.opts or {}
	local notes = {}
	if type(opts.command) == "string" then
		notes[#notes + 1] = vim.fn.executable(opts.command) == 1 and ("command " .. opts.command .. " found")
			or ("command " .. opts.command .. " NOT FOUND")
	end
	if source.generator and source.generator._failed then
		notes[#notes + 1] = "disabled after a failure"
	end
	return #notes > 0 and (" (" .. table.concat(notes, "; ") .. ")") or ""
end

local function client_line(client, bufnr)
	local root = client.root_dir and vim.fn.fnamemodify(client.root_dir, ":~") or "single file"
	local can_format = client:supports_method("textDocument/formatting", bufnr) and "can format" or "no formatting"
	return string.format("  • %s (id %d) — root: %s — %s", client.name, client.id, root, can_format)
end

---@param bufnr? integer
---@return string[]
function M.report_lines(bufnr)
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	local lines = {}
	local function add(line)
		lines[#lines + 1] = line or ""
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	add("Tooling for " .. (name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"))
	add(
		string.format(
			"filetype: %s   buftype: %s",
			vim.bo[bufnr].filetype ~= "" and vim.bo[bufnr].filetype or "(none)",
			vim.bo[bufnr].buftype ~= "" and vim.bo[bufnr].buftype or "(file)"
		)
	)
	if not is_file_buffer(bufnr) then
		add("")
		add("Special buffer: language tooling and format-on-save do not apply here.")
		return lines
	end

	local clients = vim.lsp.get_clients({ bufnr = bufnr })
	add("")
	add(("Attached clients (%d)"):format(#clients))
	if #clients == 0 then
		add("  none — no language server or null-ls client is attached to this buffer")
	end
	for _, client in ipairs(clients) do
		add(client_line(client, bufnr))
	end

	local methods = null_ls_methods()
	if methods then
		add("")
		add("null-ls applicable sources (registered for this filetype; not proof they ran)")
		for _, method in ipairs(methods) do
			local sources = formatting.null_ls_sources(bufnr, method[2])
			local described = vim.tbl_map(function(source)
				return source.name .. command_status(source)
			end, sources)
			add(("  %-20s %s"):format(method[1] .. ":", #described > 0 and table.concat(described, ", ") or "—"))
		end
	end

	local route = formatting.route(bufnr)
	local labels, via_null_ls = route_labels(route)
	add("")
	add("Formatting route (<leader>lf and format-on-save)")
	add("  policy: null-ls when it reports formatting support here; otherwise every")
	add("          attached client that can format (no retry if a formatter fails)")
	if #route.clients == 0 then
		add("  selected: none — no attached client can format this buffer")
	elseif via_null_ls then
		add("  selected: null-ls → " .. table.concat(labels, ", "))
	else
		add("  selected: " .. table.concat(labels, ", "))
		if #route.clients > 1 then
			add("  note: fallback allows all of these; each formats in turn")
		end
	end
	add(
		"  format on save: "
			.. (formatting.format_on_save(bufnr) and "enabled" or "disabled (b:disable_format_on_save)")
	)
	add("")
	add("More: :checkhealth vim.lsp (servers, logs)   q/<Esc> closes")
	return lines
end

--- Show the report for the current buffer in a scratch float.
function M.show_report()
	local source = vim.api.nvim_get_current_buf()
	local lines = M.report_lines(source)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "toolinginfo"
	local width = 0
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end
	width = math.max(40, math.min(width + 2, vim.o.columns - 4))
	local height = math.max(1, math.min(#lines, vim.o.lines - 6))
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " LSP / formatter info ",
		title_pos = "center",
	})
	vim.wo[win].wrap = false
	for _, key in ipairs({ "q", "<Esc>" }) do
		vim.keymap.set("n", key, function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end, { buffer = buf, nowait = true, desc = "Close tooling report" })
	end
	return win
end

return M
