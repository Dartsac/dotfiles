local miniicons = require("mini.icons")
local icon, hl = miniicons.get("file", "file.lua")

miniicons.setup({
	style = "glyph", -- Use glyph icons
	file = {
		-- Explicitly set the icon for 'init.lua'
		-- I like having init.lua with the same icon and hl as any other .lua file
		["init.lua"] = { glyph = icon, hl = hl }, -- Match the Lua file icon
	},
})

miniicons.mock_nvim_web_devicons()
