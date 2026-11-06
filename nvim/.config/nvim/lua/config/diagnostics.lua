-- Copy diagnostics for investigation elsewhere: location, severity, source,
-- code and message. Surrounding source text is never included, and nothing
-- leaves the machine; the text only goes to registers.
local M = {}

local SEVERITY = { "ERROR", "WARN", "INFO", "HINT" }

---@param diagnostic vim.Diagnostic
---@param path string
---@return string
function M.format(diagnostic, path)
	local provenance = {}
	if diagnostic.source and diagnostic.source ~= "" then
		provenance[#provenance + 1] = diagnostic.source
	end
	if diagnostic.code ~= nil and diagnostic.code ~= "" then
		provenance[#provenance + 1] = tostring(diagnostic.code)
	end
	local header = string.format(
		"%s:%d:%d: %s",
		path,
		diagnostic.lnum + 1,
		diagnostic.col + 1,
		SEVERITY[diagnostic.severity] or "UNKNOWN"
	)
	if #provenance > 0 then
		header = header .. " [" .. table.concat(provenance, " ") .. "]"
	end
	local message = vim.trim(diagnostic.message or ""):gsub("\r", "")
	return header .. " " .. message
end

--- Diagnostics under the cursor; if none, all diagnostics on the cursor line.
---@param bufnr integer
---@param cursor { [1]: integer, [2]: integer } (1-based row, 0-based col)
---@return vim.Diagnostic[]
function M.at_cursor(bufnr, cursor)
	local row, col = cursor[1] - 1, cursor[2]
	local on_line = vim.diagnostic.get(bufnr, { lnum = row })
	local under = vim.tbl_filter(function(d)
		local end_lnum = d.end_lnum or d.lnum
		local end_col = d.end_col or d.col
		local after_start = row > d.lnum or col >= d.col
		local before_end = row < end_lnum or col < math.max(end_col, d.col + 1)
		return after_start and before_end
	end, on_line)
	local chosen = #under > 0 and under or on_line
	table.sort(chosen, function(a, b)
		if a.severity ~= b.severity then
			return a.severity < b.severity
		end
		return a.col < b.col
	end)
	return chosen
end

--- Copy the diagnostics at the cursor to the unnamed and clipboard registers.
---@return string|nil text
function M.copy()
	local bufnr = vim.api.nvim_get_current_buf()
	local diagnostics = M.at_cursor(bufnr, vim.api.nvim_win_get_cursor(0))
	if #diagnostics == 0 then
		vim.notify("No diagnostics on this line", vim.log.levels.INFO)
		return nil
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	local path = name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"
	local lines = vim.tbl_map(function(d)
		return M.format(d, path)
	end, diagnostics)
	local text = table.concat(lines, "\n")
	vim.fn.setreg('"', text, "l")
	pcall(vim.fn.setreg, "+", text, "l") -- No clipboard provider: the unnamed register still has it.
	vim.notify(("Copied %d diagnostic%s"):format(#lines, #lines == 1 and "" or "s"), vim.log.levels.INFO)
	return text
end

return M
