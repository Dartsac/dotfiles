-- nvim --headless -u NONE -i NONE -l tests/explorer_icons.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local explorer = require("config.explorer")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local picker = { opts = { icons = { files = {} }, formatters = { file = {} } } }
local original = { "normal", "SnacksPickerDirectoryIcon", virtual = true }
package.loaded["snacks.picker.format"] = {
	filename = function()
		return { vim.deepcopy(original) }
	end,
	file = function()
		return { { "tree", "SnacksPickerTree", virtual = true }, vim.deepcopy(original), { "name" } }
	end,
}
_G.Snacks = { picker = { util = { align = function(icon, width)
	return icon .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(icon)))
end } } }
local function icon(open)
	return explorer.format({ file = root, dir = true, open = open }, picker)[2][1]
end
local ok, err = pcall(function()
	assert(explorer.source().format == explorer.format)
	assert(icon(false) == " ")
	assert(icon(true) == " ")
	vim.fn.writefile({}, root .. "/.hidden")
	assert(icon(false) == "normal", "hidden children make a directory nonempty")
	assert(icon(true) == "normal")
	vim.fn.delete(root .. "/.hidden")
	assert(icon(true) == " ", "emptiness must update after deletion")
	picker.opts.icons.files.enabled = false
	assert(icon(false) == "normal")
	picker.opts.icons.files.enabled = true
	assert(explorer.format({ file = root, dir = false }, picker)[2][1] == "normal")
	vim.fn.delete(root, "d")
	assert(icon(false) == "normal", "unreadable/missing directories retain the default icon")
end)
vim.fn.delete(root, "rf")
assert(ok, err)
print("explorer icons: OK")
