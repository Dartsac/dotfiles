return {
	"tjdevries/colorbuddy.nvim", -- Add the dependency for colorbuddy
	lazy = false,
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
-- local cb = require("colorbuddy.init")
--
-- -- Color.new(name, value)
-- -- Group.new(name, foreground, background, style<bold, italic, underline, undercurl, reverse, NONE>, special<used for underlining or similar effects>)
--
-- -- Loading the colorscheme using vim.cmd but then using colorbuddy to override colors and groups
-- local colorscheme = "dracula_pro_buffy"
-- local status_ok, err = pcall(function()
-- 	vim.cmd("colorscheme " .. colorscheme)
-- end)
-- if not status_ok then
-- 	vim.notify("Failed to load colorscheme: " .. colorscheme .. "\n" .. err, vim.log.levels.ERROR)
-- 	return
-- end
--
-- local Color = cb.Color
-- local colors = cb.colors
-- local Group = cb.Group
-- local groups = cb.groups
-- local styles = cb.styles
--
-- -- Color.new("fg", "#F8F8F2")
-- -- Color.new("bglighter", "#REDACTED")
-- -- Color.new("bglight", "#REDACTED")
-- Color.new("thisBg", "#REDACTED")
-- Color.new("thisBgDark", "#REDACTED")
-- Color.new("thisBgDarker", "#REDACTED")
-- -- Color.new("comment", "#BD93F9")
-- -- Color.new("thisSelection", "#REDACTED")
-- Color.new("thisSelection", "#REDACTED")
-- -- Color.new("subtle", "#REDACTED")
-- Color.new("thisCyan", "#REDACTED")
-- Color.new("thisBlue", "#REDACTED")
-- -- Color.new("green", "#REDACTED")
-- -- Color.new("orange", "#REDACTED")
-- -- Color.new("pink", "#REDACTED")
-- -- Color.new("purple", "#REDACTED")
-- Color.new("thisRed", "#REDACTED")
-- Color.new("thisYellow", "#REDACTED")
-- Color.new("thisLightYellow", "#f4d88c")
-- Color.new("thisDraculaWarnLine", "#REDACTED")
--
-- Group.new("Error", colors.thisRed)
-- Group.new("Warning", colors.thisDraculaWarnLine)
-- Group.new("Information", colors.thisBlue)
-- Group.new("Hint", colors.thisCyan)
--
-- Group.new("CursorLine", colors.none, colors.thisBgDark, styles.NONE, colors.thisSelection)
-- Group.new("CursorLineNr", colors.thisYellow, colors.thisBgDarker, styles.NONE, colors.thisSelection)
--
-- Group.new("ErrorMsg", colors.thisBgDarker, colors.thisRed, styles.bold)
-- Group.new("WarningMsg", colors.thisBgDarker, colors.thisLightYellow, styles.bold)
--
-- -- highlight color handling
-- Group.new("IlluminatedWordText", colors.none, colors.thisSelection, styles.bold)
-- Group.new("IlluminatedWordRead", colors.none, colors.thisSelection, styles.bold)
-- Group.new("IlluminatedWordWrite", colors.none, colors.thisSelection, styles.bold)
--
-- local cError = groups.Error.fg
-- local cInfo = groups.Information.fg
-- local cWarn = groups.Warning.fg
-- local cHint = groups.Hint.fg
--
-- Group.new("DiagnosticVirtualTextError", colors.thisBgDarker, cError, styles.bold)
-- Group.new("DiagnosticVirtualTextWarn", colors.thisBgDarker, cWarn, styles.bold)
-- Group.new("DiagnosticVirtualTextInfo", colors.thisBgDarker, cInfo, styles.NONE)
-- Group.new("DiagnosticVirtualTextHint", colors.thisBgDarker, cHint, styles.NONE)
--
-- Group.new("DiagnosticUnderlineError", colors.thisRed, colors.none, styles.undercurl + styles.bold + styles.italic)
--
-- -- Highlight group for Visual mode
-- vim.cmd("highlight Visual guibg=#REDACTED guifg=NONE gui=reverse,bold")
--
-- -- Autocommand group for visual mode and cursor highlights
-- vim.api.nvim_create_augroup("_visual_mode_highlight", { clear = true })
--
-- -- Ensure Visual group is applied consistently on mode and window changes
-- vim.api.nvim_create_autocmd({ "ModeChanged", "WinEnter", "VimEnter" }, {
-- 	group = "_visual_mode_highlight",
-- 	pattern = { "*" },
-- 	callback = function()
-- 		vim.cmd("highlight Visual guibg=#REDACTED guifg=NONE gui=reverse,bold")
-- 	end,
-- })
--
-- -- Disable vim-illuminate in visual mode and clear all highlights
-- vim.api.nvim_create_autocmd("ModeChanged", {
-- 	group = vim.api.nvim_create_augroup("DebugIlluminateVisualMode", { clear = true }),
-- 	pattern = { "*:v", "*:V", "*:<C-v>" },
-- 	callback = function()
-- 		vim.cmd("IlluminatePauseBuf")
-- 	end,
-- })
--
-- vim.api.nvim_create_autocmd("ModeChanged", {
-- 	group = vim.api.nvim_create_augroup("DebugIlluminateNormalMode", { clear = true }),
-- 	pattern = { "v:*", "V:*", "<C-v>:*" },
-- 	callback = function()
-- 		vim.cmd("IlluminateResumeBuf")
-- 	end,
-- })
