return {
	"echasnovski/mini.nvim",
	version = "*",
	event = "VeryLazy",
	config = function()
		local icons = require("mini.icons")

		local config = {
			style = "glyph",
			-- Every folder icon takes the explorer's muted structure colour
			-- (lua/config/explorer.lua), as in nvim-tree: special folders such
			-- as .git or docs keep their own glyph, not a colour of their own.
			default = { directory = { hl = "SnacksPickerDirectoryIcon" } },
			directory = {},
			extension = {
				puml = { glyph = "", hl = "MiniIconsBlue", name = "PlantUML" },
			},
		}
		icons.setup(config)
		-- Built-in folder names are only listable after setup; override their
		-- colour (mini.icons keeps the built-in glyph when only `hl` is given).
		for _, name in ipairs(icons.list("directory")) do
			config.directory[name] = { hl = "SnacksPickerDirectoryIcon" }
		end
		icons.setup(config)

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
