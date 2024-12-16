return {
	"echasnovski/mini.nvim",
	version = "*",
	config = function()
		local icons = require("mini.icons")
		local icon, hl = icons.get("file", "file.lua")

		icons.setup({
			style = "glyph", -- Use glyph icons
			file = {
				["init.lua"] = { glyph = icon, hl = hl },
			},
		})
		icons.mock_nvim_web_devicons()

		-- Setup mini.indentscope
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
				indent_at_cursor = false,
				try_as_border = false,
			},
			symbol = "▏",
		})
	end,
}
