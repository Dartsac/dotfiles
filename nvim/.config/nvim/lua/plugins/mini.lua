return {
	"echasnovski/mini.nvim",
	version = "*",
	event = "VeryLazy",
	config = function()
		local icons = require("mini.icons")

		icons.setup({
			style = "glyph",
			extension = {
				puml = { glyph = "", hl = "MiniIconsBlue", name = "PlantUML" },
			},
		})

		icons.mock_nvim_web_devicons()

		-- Setup mini.indentscope
		local status_ok_mini, indentscope = pcall(require, "mini.indentscope")
		if not status_ok_mini then
			return
		end

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
