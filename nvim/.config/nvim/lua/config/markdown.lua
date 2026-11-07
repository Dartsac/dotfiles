-- Per-buffer Markdown behaviour, attached from after/ftplugin/markdown.lua.
-- Works for any Markdown buffer (README/docs, harness Ctrl-G files, vault
-- notes); vault-only extras are added when the file is inside the vault.
--
-- Assistance (automatic list continuation, automatic table alignment) is on
-- by default and can be switched off per buffer: <leader>da (both) or
-- <leader>dtt (tables only). Inside fenced code blocks, Enter is never
-- treated as list continuation.
local M = {}

---@param names string[] lazy.nvim plugin names
local function ensure_plugins(names)
	local ok, lazy = pcall(require, "lazy")
	if ok then
		pcall(lazy.load, { plugins = names })
	end
end

-------------------------------------------------------------------------------
-- Code-fence detection
-------------------------------------------------------------------------------

--- Whether (row, col) (0-based) is inside a fenced or indented code block.
---@param bufnr integer
---@param row integer
---@return boolean
function M.in_code_block(bufnr, row)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
	if ok and parser then
		local tree = parser:parse({ row, row + 1 })[1]
		if not tree then
			return false
		end
		local query = vim.treesitter.query.parse("markdown", "[(fenced_code_block) (indented_code_block)] @code")
		for _, node in query:iter_captures(tree:root(), bufnr, row, row + 1) do
			local start_row, _, end_row, end_col = node:range()
			-- end is exclusive: a block ending at column 0 stops on the line before.
			if start_row <= row and (row < end_row or (row == end_row and end_col > 0)) then
				return true
			end
		end
		return false
	end
	-- No parser: count fence lines above.
	local inside = false
	for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, row, false)) do
		if line:match("^%s*```") or line:match("^%s*~~~") then
			inside = not inside
		end
	end
	return inside
end

-------------------------------------------------------------------------------
-- Assistance state and mappings
-------------------------------------------------------------------------------

local function lists_on(bufnr)
	return vim.b[bufnr].markdown_lists ~= false
end

local function tables_on(bufnr)
	return vim.b[bufnr].markdown_tables ~= false
end

-- Native fallbacks, used when assistance does not apply.
vim.keymap.set("i", "<Plug>(markdown-native-cr)", function()
	local ok, npairs = pcall(require, "nvim-autopairs")
	if ok and type(npairs.completion_confirm) == "function" then
		return npairs.completion_confirm()
	end
	return vim.keycode("<CR>")
end, { expr = true, replace_keycodes = false, desc = "Newline (autopairs-aware)" })
vim.keymap.set("n", "<Plug>(markdown-native-o)", "o", { noremap = true })
vim.keymap.set("i", "<Plug>(markdown-native-bar)", "|", { noremap = true })

--- Whether a line is a list item (bullet, number or task), possibly empty.
---@param line string
---@return boolean
function M.is_list_item(line)
	return line:match("^%s*[-*+]%s") ~= nil
		or line:match("^%s*[-*+]$") ~= nil
		or line:match("^%s*%d+[.)]%s") ~= nil
		or line:match("^%s*%d+[.)]$") ~= nil
end

-- bullets.vim only edits the buffer directly for a list item with the cursor
-- at the end of the line. Elsewhere it queues its newline with
-- feedkeys("\<CR>", "n"), which lands *after* any keys already pending (a
-- macro, `.` repeat, pasted or fast input). Those cases use the native
-- newline instead.
local function continue_list(bufnr, insert)
	if not lists_on(bufnr) then
		return false
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_get_current_line()
	if not M.is_list_item(line) or (insert and cursor[2] < #line) then
		return false
	end
	return not M.in_code_block(bufnr, cursor[1] - 1)
end

--- Enter in insert mode: continue lists outside code blocks.
function M.insert_cr()
	if continue_list(vim.api.nvim_get_current_buf(), true) then
		return "<Plug>(bullets-newline)"
	end
	return "<Plug>(markdown-native-cr)"
end

function M.normal_o()
	if vim.v.count == 0 and continue_list(vim.api.nvim_get_current_buf(), false) then
		return "<Plug>(bullets-newline)"
	end
	return "<Plug>(markdown-native-o)"
end

--- A table delimiter row such as `|---|:--:|`.
---@param line string
---@return boolean
function M.is_delimiter_row(line)
	return line:match("^%s*|[%s:|-]*|%s*$") ~= nil and line:find("-", 1, true) ~= nil
end

--- `|` in insert mode: align the table as you type, outside code blocks.
function M.insert_bar()
	local bufnr = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1
	if tables_on(bufnr) and not M.in_code_block(bufnr, row) then
		-- table-mode leaves the cursor after the first `|` when it realigns a
		-- delimiter row (|---|---|); continue at the end of the row instead.
		local line = vim.api.nvim_get_current_line()
		local at_end = vim.api.nvim_win_get_cursor(0)[2] >= #line
		if at_end and M.is_delimiter_row(line .. "|") then
			return "<Plug>(table-mode-tableize)<End>"
		end
		return "<Plug>(table-mode-tableize)"
	end
	return "<Plug>(markdown-native-bar)"
end

local function set_table_mode(bufnr, enabled)
	if enabled then
		ensure_plugins({ "vim-table-mode" })
	end
	if vim.fn.exists(":TableModeEnable") ~= 2 then
		return
	end
	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd(enabled and "silent TableModeEnable" or "silent TableModeDisable")
	end)
end

---@param bufnr integer
---@param opts { lists?: boolean, tables?: boolean }
function M.set_assistance(bufnr, opts)
	if opts.lists ~= nil then
		vim.b[bufnr].markdown_lists = opts.lists
	end
	if opts.tables ~= nil then
		vim.b[bufnr].markdown_tables = opts.tables
		set_table_mode(bufnr, opts.tables)
	end
end

local function report_assistance(bufnr)
	local function state(on)
		return on and "on" or "off"
	end
	vim.notify(
		("Markdown assistance: lists %s, tables %s"):format(state(lists_on(bufnr)), state(tables_on(bufnr))),
		vim.log.levels.INFO
	)
end

function M.toggle_assistance()
	local bufnr = vim.api.nvim_get_current_buf()
	local enable = not (lists_on(bufnr) or tables_on(bufnr))
	M.set_assistance(bufnr, { lists = enable, tables = enable })
	report_assistance(bufnr)
end

function M.toggle_tables()
	local bufnr = vim.api.nvim_get_current_buf()
	M.set_assistance(bufnr, { tables = not tables_on(bufnr) })
	report_assistance(bufnr)
end

-------------------------------------------------------------------------------
-- Checkboxes: explicit, ordinary [ ] <-> [x], one line at a time
-------------------------------------------------------------------------------

local LIST_PREFIXES = { "^(%s*[-*+]%s+)", "^(%s*%d+[.)]%s+)" }

--- New text for a toggled line, or nil when the line is not a list item.
--- `[ ]` -> `[x]`, `[x]`/`[X]` -> `[ ]`, plain list item -> `[ ] ` added.
--- Other markers (e.g. `[-]`, `[>]`) are left alone.
---@param line string
---@return string|nil
function M.toggle_checkbox_text(line)
	for _, prefix in ipairs(LIST_PREFIXES) do
		local lead, mark, rest = line:match(prefix .. "%[(.)%](.*)$")
		if lead then
			if mark == " " then
				return lead .. "[x]" .. rest
			elseif mark == "x" or mark == "X" then
				return lead .. "[ ]" .. rest
			end
			return nil
		end
		lead = line:match(prefix)
		if lead then
			return lead .. "[ ] " .. line:sub(#lead + 1)
		end
	end
	return nil
end

---@param first? integer 1-based first line (default: cursor line)
---@param last? integer 1-based last line
function M.toggle_checkbox(first, last)
	local bufnr = vim.api.nvim_get_current_buf()
	first = first or vim.api.nvim_win_get_cursor(0)[1]
	last = last or first
	local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
	local changed = 0
	for i, line in ipairs(lines) do
		local toggled = M.toggle_checkbox_text(line)
		if toggled then
			lines[i] = toggled
			changed = changed + 1
		end
	end
	if changed == 0 then
		vim.notify("No list item to toggle here", vim.log.levels.INFO)
		return 0
	end
	vim.api.nvim_buf_set_lines(bufnr, first - 1, last, false, lines)
	return changed
end

-------------------------------------------------------------------------------
-- Headings
-------------------------------------------------------------------------------

---@class MarkdownHeading
---@field level integer
---@field text string
---@field lnum integer 1-based

---@param bufnr integer
---@return MarkdownHeading[]
function M.headings(bufnr)
	local headings = {}
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
	if ok and parser then
		local tree = parser:parse()[1]
		local query = vim.treesitter.query.parse("markdown", "(atx_heading) @heading (setext_heading) @heading")
		for _, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
			local row = node:range()
			local text = vim.treesitter.get_node_text(node, bufnr)
			local first = vim.split(text, "\n")[1]
			local level
			if node:type() == "atx_heading" then
				local hashes = first:match("^%s*(#+)")
				level = hashes and #hashes or 1
				first = first:gsub("^%s*#+%s*", ""):gsub("%s+#+%s*$", "")
			else
				level = text:match("\n%s*=+%s*$") and 1 or 2
			end
			headings[#headings + 1] = { level = level, text = vim.trim(first), lnum = row + 1 }
		end
		table.sort(headings, function(a, b)
			return a.lnum < b.lnum
		end)
		return headings
	end
	local fenced = false
	for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
		if line:match("^%s*```") or line:match("^%s*~~~") then
			fenced = not fenced
		elseif not fenced then
			local hashes, text = line:match("^%s*(#+)%s+(.-)%s*#*%s*$")
			if hashes and #hashes <= 6 then
				headings[#headings + 1] = { level = #hashes, text = text, lnum = lnum }
			end
		end
	end
	return headings
end

function M.pick_heading()
	local bufnr = vim.api.nvim_get_current_buf()
	local headings = M.headings(bufnr)
	if #headings == 0 then
		vim.notify("No headings in this buffer", vim.log.levels.INFO)
		return
	end
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local filename = vim.api.nvim_buf_get_name(bufnr)
	pickers
		.new({}, {
			prompt_title = "Headings",
			finder = finders.new_table({
				results = headings,
				entry_maker = function(heading)
					local display = string.rep("  ", heading.level - 1)
						.. string.rep("#", heading.level)
						.. " "
						.. heading.text
					return {
						value = heading,
						display = display,
						ordinal = heading.text,
						lnum = heading.lnum,
						filename = filename,
						bufnr = bufnr,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.grep_previewer({}),
			-- Telescope's own select goes to the entry's buffer (not merely the
			-- current window's), so a resumed picker still jumps into the note
			-- the headings came from, and splits/tabs work as elsewhere.
			attach_mappings = function()
				local function prepare()
					local entry = action_state.get_selected_entry()
					-- A wiped buffer: reopen by file name instead.
					if entry and entry.bufnr and not vim.api.nvim_buf_is_valid(entry.bufnr) then
						entry.bufnr = nil
					end
				end
				local function open_fold()
					vim.cmd("normal! zv")
				end
				for _, select in ipairs({
					actions.select_default,
					actions.select_horizontal,
					actions.select_vertical,
					actions.select_tab,
				}) do
					select:enhance({ pre = prepare, post = open_fold })
				end
				return true
			end,
		})
		:find()
end

-------------------------------------------------------------------------------
-- Links
-------------------------------------------------------------------------------

---@class MarkdownLink
---@field kind "markdown"|"wiki"|"url"|"reference"
---@field target? string
---@field anchor? string
---@field label? string reference label (kind "reference")

--- Classify a link destination: a URL (any scheme) or a local path with an
--- optional #anchor. Strips a "title" and <angle brackets>.
---@param raw string
---@return MarkdownLink
function M.classify_target(raw)
	local target = vim.trim(raw)
	target = target:match("^<([^>]*)>") or target:gsub('%s+["\'(].*$', "")
	if target:match("^%a[%w+.-]*:") then
		return { kind = "url", target = target }
	end
	local path, anchor = target:match("^(.-)#(.*)$")
	return { kind = "markdown", target = path or target, anchor = anchor }
end

local function normalize_label(label)
	return vim.trim(label):gsub("%s+", " "):lower()
end

local function fence_of(line)
	local marks, rest = line:match("^%s*(```+)(.*)$")
	if not marks then
		marks, rest = line:match("^%s*(~~~+)(.*)$")
	end
	return marks, rest
end

--- Rows (1-based) of `lines` inside fenced code blocks, fence lines included.
--- CommonMark: a fence is 3+ backticks (no backtick in its info string) or
--- tildes; it closes on the same character at least as long with nothing
--- after, and an unclosed fence runs to the end of the document.
---@param lines string[]
---@return table<integer, true>
function M.fenced_rows(lines)
	local rows, open = {}, nil
	for i, line in ipairs(lines) do
		local marks, rest = fence_of(line)
		if open then
			rows[i] = true
			if marks and marks:sub(1, 1) == open:sub(1, 1) and #marks >= #open and vim.trim(rest) == "" then
				open = nil
			end
		elseif marks and not (marks:sub(1, 1) == "`" and rest:find("`", 1, true)) then
			rows[i] = true
			open = marks
		end
	end
	return rows
end

--- The destination of reference `label` from the definitions in `lines`
--- (`[label]: target "title"`; labels match case-insensitively). Definitions
--- inside code blocks are examples, not definitions, and are skipped.
---@param lines string[]
---@param label string
---@param in_code? fun(row: integer): boolean 1-based row is code (default: fenced_rows)
---@return table|nil link classified as by classify_target
function M.resolve_reference(lines, label, in_code)
	local wanted = normalize_label(label)
	if not in_code then
		local fenced = M.fenced_rows(lines)
		in_code = function(row)
			return fenced[row] == true
		end
	end
	for row, line in ipairs(lines) do
		local found, rest = line:match("^ ? ? ?%[([^%]]+)%]:%s*(.*)$")
		if found and normalize_label(found) == wanted and rest ~= "" and not in_code(row) then
			local destination = rest:match("^<[^>]*>") or rest:match("^%S+")
			return M.classify_target(destination)
		end
	end
	return nil
end

--- The link under the cursor column (0-based), if any.
---@param line string
---@param col integer
---@return MarkdownLink|nil
function M.link_at(line, col)
	local pos = col + 1
	local function covers(s, e)
		return s and pos >= s and pos <= e
	end
	-- [[target#heading|alias]]
	local init = 1
	while true do
		local s, e, inner = line:find("%[%[(.-)%]%]", init)
		if not s then
			break
		end
		if covers(s, e) then
			local target = inner:gsub("|.*$", "")
			local name, anchor = target:match("^(.-)#(.*)$")
			return { kind = "wiki", target = name or target, anchor = anchor }
		end
		init = e + 1
	end
	-- [text](target "title") and <target>
	-- (An <angle-bracket> destination may contain parentheses.)
	for _, pattern in ipairs({ "%[[^%]]-%]%((%s*<[^>]*>[^)]*)%)", "%[[^%]]-%]%((.-)%)", "<([^>%s]+)>" }) do
		init = 1
		while true do
			local s, e, inner = line:find(pattern, init)
			if not s then
				break
			end
			if covers(s, e) then
				return M.classify_target(inner)
			end
			init = e + 1
		end
	end
	-- Reference links, resolved later against the buffer's definitions:
	-- `[label]: target` (a definition line), `[text][label]`, `[label][]`,
	-- and the shortcut form `[label]`.
	local def_s, def_e, def_label = line:find("^ ? ? ?%[([^%]]+)%]:")
	if covers(def_s, def_e) or (def_s and pos > def_e) then
		return { kind = "reference", label = def_label }
	end
	init = 1
	while true do
		local s, e, text, label = line:find("%[([^%]]*)%]%[([^%]]*)%]", init)
		if not s then
			break
		end
		if covers(s, e) then
			return { kind = "reference", label = label ~= "" and label or text }
		end
		init = e + 1
	end
	init = 1
	while true do
		local s, e, label = line:find("%[([^%]]+)%]", init)
		if not s then
			break
		end
		local after = line:sub(e + 1, e + 1)
		if covers(s, e) and after ~= "(" and after ~= "[" and line:sub(s - 1, s - 1) ~= "]" then
			return { kind = "reference", label = label }
		end
		init = e + 1
	end
	-- bare URL
	init = 1
	while true do
		local s, e = line:find("https?://[^%s<>%)%]]+", init)
		if not s then
			break
		end
		if covers(s, e) then
			return { kind = "url", target = line:sub(s, e) }
		end
		init = e + 1
	end
	return nil
end

local function slug(text)
	return (text:lower():gsub("[^%w%s%-_]", ""):gsub("%s+", "-"))
end

local function open_local(link, bufnr)
	local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
	local target = link.target:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end)
	local path
	if target == "" then
		path = vim.api.nvim_buf_get_name(bufnr)
	else
		path = target:sub(1, 1) == "/" and target or vim.fs.normalize(dir .. "/" .. target)
		if link.kind == "wiki" and not vim.uv.fs_stat(path) and vim.uv.fs_stat(path .. ".md") then
			path = path .. ".md"
		end
	end
	if not vim.uv.fs_stat(path) then
		vim.notify("Link target not found: " .. target, vim.log.levels.WARN)
		return false
	end
	if path ~= vim.api.nvim_buf_get_name(bufnr) then
		vim.cmd.edit(vim.fn.fnameescape(path))
	end
	if link.anchor and link.anchor ~= "" then
		local wanted = slug(link.anchor)
		for _, heading in ipairs(M.headings(0)) do
			if slug(heading.text) == wanted or heading.text == link.anchor then
				vim.api.nvim_win_set_cursor(0, { heading.lnum, 0 })
				break
			end
		end
	end
	return true
end

--- Follow the link under the cursor: URLs open externally; vault notes use
--- obsidian.nvim; other files use the language server (Marksman) when one can
--- resolve definitions, and otherwise a direct relative-path open.
function M.follow_link()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local link = M.link_at(vim.api.nvim_get_current_line(), cursor[2])
	if link and link.kind == "reference" then
		-- Bracketed text in a code block is an example, not a reference, on the
		-- cursor line and on definition lines alike (Treesitter's Markdown
		-- parse, so fences inside lists and quotes count too).
		local function in_code(row)
			return M.in_code_block(bufnr, row - 1)
		end
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		link = not in_code(cursor[1]) and M.resolve_reference(lines, link.label, in_code) or nil
	end
	local has_definition = #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/definition" }) > 0
	if not link then
		-- Nothing recognised (or a reference without a definition here): the
		-- language server may still know, e.g. Marksman across files.
		local function none()
			vim.notify("No link under the cursor", vim.log.levels.INFO)
		end
		if has_definition then
			M.lsp_definition(bufnr, none)
		else
			none()
		end
		return
	end
	if link.kind == "url" then
		vim.ui.open(link.target)
	elseif vim.b[bufnr].obsidian_buffer then
		vim.cmd("Obsidian follow_link")
	elseif has_definition then
		M.lsp_definition(bufnr, function()
			open_local(link, bufnr)
		end)
	else
		open_local(link, bufnr)
	end
end

--- Jump to the first definition any client returns; call `fallback` when none
--- does (e.g. Marksman in single-file mode cannot see other files).
---@param bufnr integer
---@param fallback fun()
function M.lsp_definition(bufnr, fallback)
	local win = vim.api.nvim_get_current_win()
	vim.lsp.buf_request_all(bufnr, "textDocument/definition", function(client)
		return vim.lsp.util.make_position_params(win, client.offset_encoding)
	end, function(results)
		for client_id, response in pairs(results) do
			local result = response.result
			if result and not vim.tbl_isempty(result) then
				local location = vim.islist(result) and result[1] or result
				local client = vim.lsp.get_client_by_id(client_id)
				vim.lsp.util.show_document(location, client and client.offset_encoding or "utf-16", { focus = true })
				return
			end
		end
		fallback()
	end)
end

M._open_local = open_local

-------------------------------------------------------------------------------
-- Attach
-------------------------------------------------------------------------------

-- Buffer-local maps made by attach(), so detach() can remove exactly those.
local attached_maps = {}

local function map(bufnr, mode, lhs, rhs, desc, extra)
	local opts = vim.tbl_extend("force", { buffer = bufnr, silent = true, desc = desc }, extra or {})
	vim.keymap.set(mode, lhs, rhs, opts)
	attached_maps[bufnr] = attached_maps[bufnr] or {}
	table.insert(attached_maps[bufnr], { mode, lhs })
end

--- Undo attach() when the buffer stops being Markdown (b:undo_ftplugin).
---@param bufnr integer
function M.detach(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		attached_maps[bufnr] = nil
		return
	end
	for _, entry in ipairs(attached_maps[bufnr] or {}) do
		pcall(vim.keymap.del, entry[1], entry[2], { buffer = bufnr })
	end
	attached_maps[bufnr] = nil
	if vim.b[bufnr].table_mode_active == 1 then
		set_table_mode(bufnr, false)
	end
	if vim.b[bufnr].markdown_vault_save_off then
		vim.b[bufnr].disable_format_on_save = nil
		vim.b[bufnr].markdown_vault_save_off = nil
	end
	vim.b[bufnr].markdown_attached = nil
end

---@param bufnr? integer
function M.attach(bufnr)
	if bufnr == nil or bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	if vim.b[bufnr].markdown_attached then
		return
	end
	vim.b[bufnr].markdown_attached = true
	vim.b[bufnr].undo_ftplugin = (vim.b[bufnr].undo_ftplugin or "")
		.. ("\n lua require('config.markdown').detach(%d)"):format(bufnr)
	ensure_plugins({ "bullets.vim", "vim-table-mode", "render-markdown.nvim" })

	-- Assistance, on by default.
	local expr = { expr = true, remap = true }
	map(bufnr, "i", "<CR>", M.insert_cr, "Newline / continue list", expr)
	map(bufnr, "n", "o", M.normal_o, "Open line / continue list", expr)
	map(bufnr, "i", "|", M.insert_bar, "Table separator (auto-align)", expr)
	set_table_mode(bufnr, tables_on(bufnr))

	-- Table cells (work whenever the cursor is in a table).
	map(bufnr, "n", "]|", "<Plug>(table-mode-motion-right)", "Next table cell", { remap = true })
	map(bufnr, "n", "[|", "<Plug>(table-mode-motion-left)", "Previous table cell", { remap = true })
	map(bufnr, "n", "}|", "<Plug>(table-mode-motion-down)", "Table cell below", { remap = true })
	map(bufnr, "n", "{|", "<Plug>(table-mode-motion-up)", "Table cell above", { remap = true })
	map(bufnr, { "o", "x" }, "a|", "<Plug>(table-mode-cell-text-object-a)", "Around table cell", { remap = true })
	map(bufnr, { "o", "x" }, "i|", "<Plug>(table-mode-cell-text-object-i)", "Inside table cell", { remap = true })
	map(bufnr, "n", "gN", "<Plug>(bullets-renumber)", "Renumber list", { remap = true })
	map(bufnr, "x", "gN", "<Plug>(bullets-renumber)", "Renumber selected list", { remap = true })

	-- <leader>d: Markdown group.
	map(bufnr, "n", "<leader>dr", function()
		require("render-markdown").buf_toggle()
	end, "Toggle Rendered/Raw View")
	map(bufnr, "n", "<leader>dh", M.pick_heading, "Go to Heading")
	map(bufnr, "n", "<leader>df", M.follow_link, "Follow Link")
	map(bufnr, "n", "<leader>dx", function()
		M.toggle_checkbox()
	end, "Toggle Checkbox")
	map(bufnr, "x", "<leader>dx", function()
		local a, b = vim.fn.line("v"), vim.fn.line(".")
		vim.cmd("normal! \27")
		M.toggle_checkbox(math.min(a, b), math.max(a, b))
	end, "Toggle Checkboxes")
	map(bufnr, "n", "<leader>da", M.toggle_assistance, "Toggle List/Table Assistance")
	map(bufnr, "n", "<leader>dtt", M.toggle_tables, "Toggle Table Assistance")
	map(bufnr, "n", "<leader>dtr", "<Plug>(table-mode-realign)", "Realign Table", { remap = true })
	map(bufnr, "n", "<leader>dtd", "<Plug>(table-mode-delete-row)", "Delete Row", { remap = true })
	map(bufnr, "n", "<leader>dtD", "<Plug>(table-mode-delete-column)", "Delete Column", { remap = true })
	map(bufnr, "n", "<leader>dti", "<Plug>(table-mode-insert-column-after)", "Insert Column After", { remap = true })
	map(bufnr, "n", "<leader>dtI", "<Plug>(table-mode-insert-column-before)", "Insert Column Before", { remap = true })
	map(bufnr, { "n", "x" }, "<leader>dtf", "<Plug>(table-mode-tableize)", "Format as Table", { remap = true })

	if require("config.vault").contains(vim.api.nvim_buf_get_name(bufnr)) then
		map(bufnr, "n", "<leader>db", "<cmd>Obsidian backlinks<cr>", "Backlinks (vault)")
		-- Vault notes are also edited in Obsidian, which never reformats them;
		-- Prettier on save would rewrite whole notes (list markers, blank lines,
		-- tables). No format-on-save here: <leader>lf formats when asked. An
		-- explicit b:disable_format_on_save set before this is left alone.
		if vim.b[bufnr].disable_format_on_save == nil then
			vim.b[bufnr].disable_format_on_save = true
			vim.b[bufnr].markdown_vault_save_off = true
		end
	end

	local ok, wk = pcall(require, "which-key")
	if ok then
		wk.add({ { "<leader>dt", group = "Table", buffer = bufnr } })
	end
end

return M
