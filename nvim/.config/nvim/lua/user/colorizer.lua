local status, colorizer = pcall(require, "colorizer")
if not status then
	return
end

colorizer.setup({
	"*",
	css = {
		RGB = true, -- Enable #RGB hex codes
		RRGGBB = true, -- Enable #RRGGBB hex codes
		RRGGBBAA = true, -- Enable #RRGGBBAA hex codes
		rgb_fn = true, -- Enable CSS rgb() and rgba() functions
		hsl_fn = true, -- Enable CSS hsl() and hsla() functions
		names = true, -- Enable color names like 'Red', 'Blue', etc.
		mode = "background", -- Use background color for highlighting
	},
	scss = {
		RGB = true, -- Enable #RGB hex codes
		RRGGBB = true, -- Enable #RRGGBB hex codes
		RRGGBBAA = true, -- Enable #RRGGBBAA hex codes
		rgb_fn = true, -- Enable CSS rgb() and rgba() functions
		hsl_fn = true, -- Enable CSS hsl() and hsla() functions
		names = true, -- Enable color names like 'Red', 'Blue', etc.
		mode = "background", -- Use background color for highlighting
	},
})
