-- Run: nvim --headless -u NONE -i NONE -l tests/spelling.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/which-key.nvim")
vim.opt.spell = true
vim.opt.spelllang = "en_us"
vim.opt.iskeyword:append("-") -- Match the editor's word-boundary customization.
local spelling = require("config.spelling")

local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	assert(ok, name .. ": " .. tostring(err))
	print("PASS: " .. name)
end

local function line(text, col)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
	vim.api.nvim_win_set_cursor(0, { 1, col })
end

test("ten suggestions, each applying exactly its own label", function()
	local original = "This is teh example."
	for index = 1, 10 do
		line(original, 9) -- Within the misspelling, not at its first byte.
		local cursor = vim.api.nvim_win_get_cursor(0)
		local items = spelling.expand()
		assert(#items == 11 and items[index].key == tostring(index % 10))
		assert(items[11].key == "a")
		assert(vim.deep_equal(cursor, vim.api.nvim_win_get_cursor(0)))
		local register = vim.fn.getreg('"')
		items[index].action()
		assert(vim.api.nvim_get_current_line() == "This is " .. items[index].desc .. " example.")
		assert(vim.fn.getreg('"') == register)
	end
end)

test("spell boundaries work after punctuation and multibyte text", function()
	local prefix = "The café: "
	line(prefix .. "teh!", #prefix)
	local items = spelling.expand()
	assert(#items > 0)
	items[1].action()
	assert(vim.api.nvim_get_current_line() == prefix .. items[1].desc .. "!")
end)

test("capitalization suggestions use sentence context", function()
	line("This is correct. the end.", 17)
	local items = spelling.expand()
	assert(#items > 0 and items[1].desc:match("^%u"))
	items[1].action()
	assert(vim.api.nvim_get_current_line() == "This is correct. " .. items[1].desc .. " end.")
end)

local function replaces(text, col, original)
	line(text, col)
	local items = spelling.expand()
	assert(#items > 0, "no suggestions")
	items[1].action()
	local start = text:find(original, 1, true) - 1
	local expected = text:sub(1, start) .. items[1].desc .. text:sub(start + #original + 1)
	assert(vim.api.nvim_get_current_line() == expected, vim.api.nvim_get_current_line())
	return items
end

test("a correctly spelled word gets suggestions, as with native z=", function()
	local items = replaces("This is correct.", 8, "correct")
	assert(items[#items].key ~= "a") -- Nothing to add to the dictionary.
end)

test("the word under the cursor, not a later misspelling", function()
	replaces("This is teh example.", 0, "This")
end)

test("with 'spell' off, the word under the cursor still gets suggestions", function()
	vim.opt.spell = false
	local ok, err = pcall(function()
		local items = replaces("This is teh example.", 9, "teh")
		assert(items[#items].key == "a")
		replaces("This is correct.", 8, "correct")
		replaces("It's don't here.", 6, "don't")
	end)
	vim.opt.spell = true
	assert(ok, err)
end)

test("a line without words produces no entries", function()
	line("  -- 42 --", 3)
	assert(#spelling.expand() == 0)
end)

test("stale suggestions do not change edited text", function()
	line("This is teh example.", 8)
	local items = spelling.expand()
	line("This is new text.", 8)
	local notify, warning = vim.notify, nil
	vim.notify = function(message)
		warning = message
	end
	items[1].action()
	vim.notify = notify
	assert(warning and vim.api.nvim_get_current_line() == "This is new text.")
end)

test("add action saves the displayed word without changing text or cursor", function()
	local previous = vim.bo.spellfile
	local path = vim.fn.tempname() .. ".add"
	vim.bo.spellfile = path
	local text = "This is Zqxserializability."
	line(text, 10)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local items = spelling.expand()
	local add = items[#items]
	assert(add.key == "a" and add.desc:find("Zqxserializability", 1, true))
	add.action()
	assert(vim.fn.index(vim.fn.readfile(path), "Zqxserializability") >= 0)
	assert(vim.fn.spellbadword("Zqxserializability")[1] == "")
	assert(vim.api.nvim_get_current_line() == text)
	assert(vim.deep_equal(cursor, vim.api.nvim_win_get_cursor(0)))
	vim.bo.spellfile = previous
	vim.fn.delete(path)
	vim.fn.delete(path .. ".spl")
end)

test("counted commands retain the native path", function()
	local items
	vim.keymap.set("n", "<F5>", function()
		items = spelling.expand()
	end)
	vim.api.nvim_feedkeys(vim.keycode("2<F5>"), "xt", false)
	assert(items and #items == 0)
	vim.keymap.del("n", "<F5>")
	vim.cmd.normal({ args = { "l" }, bang = true }) -- Clear the previous command's count.
end)

test("which-key config installs the local adapter", function()
	local options
	package.loaded["which-key"] = {
		setup = function(opts)
			options = opts
		end,
		add = function() end,
	}
	dofile("lua/plugins/whichkey.lua")[1].config()
	local plugin = require("which-key.plugins.spelling")
	assert(options.plugins.spelling.enabled)
	assert(plugin.expand == spelling.expand)
	line("This is teh example.", 8)
	local items = plugin.expand()
	items[2].action()
	assert(vim.api.nvim_get_current_line() == "This is " .. items[2].desc .. " example.")
end)

print("All spelling tests passed")
