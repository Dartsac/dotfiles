return {
	{
		"lukas-reineke/indent-blankline.nvim",
		config = function()
			local status_ok, ibl = pcall(require, "ibl")
			if not status_ok then
				return
			end

			ibl.setup({
				indent = {
					char = "▏",
				},
				scope = {
					enabled = false,
					show_start = false,
					show_end = false,
				},
				-- exclude = {
				-- 	buftypes = { "terminal", "nofile" },
				-- 	filetypes = {
				-- 		"help",
				-- 		"startify",
				-- 		"dashboard",
				-- 		"packer",
				-- 		"neogitstatus",
				-- 		"NvimTree",
				-- 		"Trouble",
				-- 		"dbout",
				-- 	},
				-- },
			})
		end,
	},
}
