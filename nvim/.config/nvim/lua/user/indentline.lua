-- Indent Blankline (ibl) setup
local status_ok, ibl = pcall(require, "ibl")
if not status_ok then
	return
end

ibl.setup({
	indent = {
		char = "▏",
	},
	scope = {
		enabled = true,
		show_start = false,
		show_end = false,
	},
	exclude = {
		buftypes = { "terminal", "nofile" },
		filetypes = {
			"help",
			"startify",
			"dashboard",
			"packer",
			"neogitstatus",
			"NvimTree",
			"Trouble",
			"dbout",
		},
	},
})

-- Mini IndentScope setup
local status_ok_mini, indentscope = pcall(require, "mini.indentscope")
if not status_ok_mini then
	return
end

-- Disable mini.indentscope for excluded filetypes and buftypes
vim.api.nvim_create_autocmd("FileType", {
	pattern = {
		"help",
		"startify",
		"dashboard",
		"packer",
		"neogitstatus",
		"NvimTree",
		"Trouble",
		"dbout",
	},
	callback = function()
		vim.b.miniindentscope_disable = true
	end,
})

vim.api.nvim_create_autocmd("BufEnter", {
	callback = function()
		local excluded_buftypes = { "terminal", "nofile" }
		if vim.tbl_contains(excluded_buftypes, vim.bo.buftype) then
			vim.b.miniindentscope_disable = true
		end
	end,
})

-- Setup mini.indentscope with default options
indentscope.setup({
	draw = {
		delay = 0,
		animation = indentscope.gen_animation.none(),
	},
	mappings = {
		object_scope = "si",
		goto_top = "[i",
		goto_bottom = "]i",
	},
	options = {
		border = "both",
		indent_at_cursor = true,
		try_as_border = false,
	},
	symbol = "▏",
})
