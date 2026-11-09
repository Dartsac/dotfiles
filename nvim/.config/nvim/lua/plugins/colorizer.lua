return {
	"NvChad/nvim-colorizer.lua",
	enabled = true,
	-- Loaded only for files it colours (the filetypes below), before their
	-- FileType; `ft` covers those buffers without a matching file name.
	event = {
		"BufReadPre *.css,*.scss,*.html,*.htm,*.js,*.mjs,*.cjs,*.ts,*.mts,*.cts,*.lua",
		"BufNewFile *.css,*.scss,*.html,*.htm,*.js,*.mjs,*.cjs,*.ts,*.mts,*.cts,*.lua",
	},
	ft = { "css", "scss", "html", "javascript", "typescript", "lua" },
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
