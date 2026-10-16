return {
	"NvChad/nvim-colorizer.lua",
	enabled = true,
	event = "BufReadPre",
	config = function()
		local status, colorizer = pcall(require, "colorizer")
		if not status then
			return
		end

		local css = {
			RGB = true, -- Enable #RGB hex codes
			RRGGBB = true, -- Enable #RRGGBB hex codes
			RRGGBBAA = true, -- Enable #RRGGBBAA hex codes
			rgb_fn = true, -- Enable CSS rgb() and rgba() functions
			hsl_fn = true, -- Enable CSS hsl() and hsla() functions
			names = true, -- Enable color names like 'Red', 'Blue', etc.
			mode = "background", -- Use background color for highlighting
		}
		colorizer.setup({
			filetypes = {
				"css",
				"scss",
				"html",
				"javascript",
				"typescript",
				"lua",
				css = css,
				scss = css,
			},
		})
	end,
}
