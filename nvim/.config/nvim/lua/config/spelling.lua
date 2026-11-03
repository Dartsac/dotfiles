-- Local adapter for which-key's spelling popup. Apply the displayed text,
-- rather than asking native z= to calculate a second, potentially different list.
local M = {}
local SUGGESTIONS = 10 -- One key each: 1-9, then 0.

function M.expand()
	-- Preserve native counted commands such as 1z=.
	if vim.v.count > 0 then
		return {}
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(win)
	-- Like native z=: the word under (or else after) the cursor, misspelled or
	-- not, with 'spell' on or off. Letters only, not 'iskeyword' (which joins
	-- words with "-" here); any non-ASCII character counts as a letter.
	local text = vim.api.nvim_get_current_line()
	local word, col
	local from = 0
	repeat
		local match = vim.fn.matchstrpos(text, [[\v(\a|[^\x01-\x7f])+('(\a|[^\x01-\x7f])+)*]], from)
		if match[2] < 0 then
			return {}
		end
		word, col, from = match[1], match[2], match[3]
	until from > cursor[2]
	-- With 'spell' on, spellbadword() moves to the misspelling under/after the
	-- cursor. If that is this word, use its spelling boundaries and sentence
	-- capitalization instead.
	local bad = vim.fn.spellbadword()
	local found = vim.api.nvim_win_get_cursor(win)
	vim.api.nvim_win_set_cursor(win, cursor)
	local caps = false
	if bad[1] ~= "" and found[1] == cursor[1] and found[2] >= col and found[2] < col + #word then
		word, col, caps = bad[1], found[2], bad[2] == "caps"
	end

	local row = cursor[1] - 1
	local start = { cursor[1], col }
	local tick = vim.api.nvim_buf_get_changedtick(bufnr)
	local function unchanged()
		if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_buf_get_changedtick(bufnr) ~= tick then
			vim.notify("Text changed. Open spelling suggestions again.", vim.log.levels.WARN)
			return false
		end
		return true
	end
	local function shown()
		return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr
	end
	local items = {}
	for i, suggestion in ipairs(vim.fn.spellsuggest(word, SUGGESTIONS, caps and 1 or 0)) do
		items[#items + 1] = {
			key = tostring(i % 10),
			desc = suggestion,
			action = function()
				if not unchanged() then
					return
				end
				vim.api.nvim_buf_set_text(bufnr, row, col, row, col + #word, { suggestion })
				if shown() then
					vim.api.nvim_win_set_cursor(win, start)
				end
			end,
		}
	end
	if vim.fn.spellbadword(word)[1] == "" then
		return items -- Nothing to add: the dictionary knows it.
	end
	items[#items + 1] = {
		key = "a",
		desc = 'Add "' .. word .. '" to dictionary',
		action = function()
			if not unchanged() or not shown() then
				return
			end
			vim.api.nvim_win_call(win, function()
				local current = vim.api.nvim_win_get_cursor(win)
				vim.api.nvim_win_set_cursor(win, start)
				local ok, err = pcall(vim.cmd.normal, { args = { "zg" }, bang = true })
				vim.api.nvim_win_set_cursor(win, current)
				if not ok then
					vim.notify(tostring(err), vim.log.levels.ERROR)
				end
			end)
		end,
	}
	return items
end

return M
