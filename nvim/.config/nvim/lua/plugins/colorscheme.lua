-- lua/plugins/colorscheme.lua
return {
	"tjdevries/colorbuddy.nvim", -- Add the dependency for colorbuddy
	lazy = false,
	-- event = "VimEnter",
	priority = 1000,
	config = function()
		local cb = require("colorbuddy.init")
		local colorscheme = "dracula_pro_buffy"
		local status_ok, err = pcall(function()
			vim.cmd("colorscheme " .. colorscheme)
		end)
		if not status_ok then
			vim.notify("Failed to load colorscheme: " .. colorscheme .. "\n" .. err, vim.log.levels.ERROR)
			return
		end

		local Color = cb.Color
		local Group = cb.Group
		local colors = cb.colors
		local groups = cb.groups
		local styles = cb.styles

		-- Define colors
		Color.new("thisBg", "#REDACTED")
		Color.new("thisBgDark", "#REDACTED")
		Color.new("thisBgDarker", "#REDACTED")
		Color.new("thisSelection", "#REDACTED")
		Color.new("thisCyan", "#REDACTED")
		Color.new("thisBlue", "#REDACTED")
		Color.new("thisRed", "#REDACTED")
		Color.new("thisYellow", "#REDACTED")
		Color.new("thisLightYellow", "#f4d88c")
		Color.new("thisDraculaWarnLine", "#REDACTED")

		-- Define groups
		Group.new("Error", colors.thisRed)
		Group.new("Warning", colors.thisDraculaWarnLine)
		Group.new("Information", colors.thisBlue)
		Group.new("Hint", colors.thisCyan)

		-- sets the background to clear
		Group.new("Normal", colors.none, colors.none, styles.NONE)
		Group.new("CursorLine", colors.none, colors.thisBgDark, styles.NONE, colors.thisSelection)
		Group.new("CursorLineNr", colors.thisYellow, colors.thisBgDarker, styles.NONE, colors.thisSelection)

		Group.new("ErrorMsg", colors.thisBgDarker, colors.thisRed, styles.bold)
		Group.new("WarningMsg", colors.thisBgDarker, colors.thisLightYellow, styles.bold)

		Group.new("IlluminatedWordText", colors.none, colors.thisSelection, styles.bold)
		Group.new("IlluminatedWordRead", colors.none, colors.thisSelection, styles.bold)
		Group.new("IlluminatedWordWrite", colors.none, colors.thisSelection, styles.bold)

		local cError = groups.Error.fg
		local cInfo = groups.Information.fg
		local cWarn = groups.Warning.fg
		local cHint = groups.Hint.fg

		Group.new("DiagnosticVirtualTextError", colors.thisBgDarker, cError, styles.bold)
		Group.new("DiagnosticVirtualTextWarn", colors.thisBgDarker, cWarn, styles.bold)
		Group.new("DiagnosticVirtualTextInfo", colors.thisBgDarker, cInfo, styles.NONE)
		Group.new("DiagnosticVirtualTextHint", colors.thisBgDarker, cHint, styles.NONE)

		Group.new(
			"DiagnosticUnderlineError",
			colors.thisRed,
			colors.none,
			styles.undercurl + styles.bold + styles.italic
		)

		-- Highlight group for Visual mode
		vim.cmd("highlight Visual guibg=#REDACTED guifg=NONE gui=reverse,bold")

		-- Autocommand group for visual mode and cursor highlights
		vim.api.nvim_create_augroup("_visual_mode_highlight", { clear = true })
		vim.api.nvim_create_autocmd({ "ModeChanged", "WinEnter", "VimEnter" }, {
			group = "_visual_mode_highlight",
			pattern = { "*" },
			callback = function()
				vim.cmd("highlight Visual guibg=#REDACTED guifg=NONE gui=reverse,bold")
			end,
		})
	end,
}
