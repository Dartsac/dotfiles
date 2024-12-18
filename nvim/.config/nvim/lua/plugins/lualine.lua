return {
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
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
					lualine_c = {
						{
							"filename",
							file_status = true, -- Displays file status (readonly status, modified status)
							newfile_status = false, -- Display new file status (new file means no write after created)
							path = 1,
							-- 0: Just the filename
							-- 1: Relative path
							-- 2: Absolute path
							-- 3: Absolute path, with tilde as the home directory
							-- 4: Filename and parent dir, with tilde as the home directory
							shorting_target = 40, -- Shortens path to leave 40 spaces in the window
							-- for other components. (terrible name, any suggestions?)
							symbols = {
								modified = "[+]", -- Text to show when the file is modified.
								readonly = "[-]", -- Text to show when the file is non-modifiable or readonly.
								unnamed = "[No Name]", -- Text to show for unnamed buffers.
								newfile = "[New]", -- Text to show for newly created file before first write
							},
							color = { fg = "#F8F8F2" },
						},
					},
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
					lualine_c = {},
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
