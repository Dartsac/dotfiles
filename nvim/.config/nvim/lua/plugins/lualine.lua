return {
	{
		"nvim-lualine/lualine.nvim",
		dependencies = {
			"echasnovski/mini.nvim",
		},
		config = function()
			local status_ok, lualine = pcall(require, "lualine")
			if not status_ok then
				return
			end

			local hide_in_width = function()
				return vim.fn.winwidth(0) > 80
			end

			-- cool function for progress
			local progress = function()
				local current_line = vim.fn.line(".")
				local total_lines = vim.fn.line("$")
				local chars = { "__", "▁▁", "▂▂", "▃▃", "▄▄", "▅▅", "▆▆", "▇▇", "██" }
				local line_ratio = current_line / total_lines
				local index = math.ceil(line_ratio * #chars)
				return chars[index]
			end

			lualine.setup({
				options = {
					icons_enabled = true,
					theme = "auto", -- Allows mode-specific background color
					section_separators = { left = "", right = "" },
					component_separators = { left = "", right = "" },
					disabled_filetypes = { "dashboard", "NvimTree", "Outline" },
					always_divide_middle = true,
				},
				sections = {
					lualine_a = {
						{
							"branch",
							color = function()
								return {
									fg = vim.fn.mode() == "n" and "#F8F8F2" or nil, -- White in normal mode
									gui = "bold", -- Always bold
								}
							end,
							icons_enabled = true,
							icon = "",
						},
					},
					lualine_b = {
						{
							"mode",
							fmt = function(str)
								return "-- " .. str .. " --"
							end,
							color = function()
								return { fg = vim.fn.mode() == "n" and "#F8F8F2" or nil } -- White in normal mode, default otherwise
							end,
						},
					},
					lualine_c = {},
					lualine_x = {
						{
							"diagnostics",
							sources = { "nvim_diagnostic" },
							symbols = { error = " ", warn = " ", info = " ", hint = " " },
						},
						{
							"diff",
							colored = false,
							symbols = { added = " ", modified = " ", removed = " " },
							cond = hide_in_width,
							color = { fg = "#F8F8F2" },
						},
						{
							"encoding",
							color = { fg = "#F8F8F2" },
						},
						{
							"filetype",
							colored = true,
							color = { fg = "#F8F8F2" },
						},
					},
					lualine_y = {
						{
							"location",
							padding = 0,
							color = function()
								return { fg = vim.fn.mode() == "n" and "#F8F8F2" or nil }
							end,
						},
					},
					lualine_z = {
						{
							progress,
							color = function()
								return { fg = vim.fn.mode() == "n" and "#F8F8F2" or nil } -- White in normal mode, default otherwise
							end,
						},
					},
				},
				inactive_sections = {
					lualine_a = {},
					lualine_b = {},
					lualine_c = { "filename" },
					lualine_x = { "location" },
					lualine_y = {},
					lualine_z = {},
				},
				tabline = {},
				extensions = {},
			})
		end,
	},
}
