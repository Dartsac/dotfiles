local cb = require("colorbuddy.init")

-- Color.new(name, value)
-- Group.new(name, foreground, background, style<bold, italic, underline, undercurl, reverse, NONE>, special<used for underlining or similar effects>)

-- Loading the colorscheme using vim.cmd but then using colorbuddy to override colors and groups
local colorscheme = "dracula_pro_buffy"
local status_ok, err = pcall(function()
	vim.cmd("colorscheme " .. colorscheme)
end)
if not status_ok then
	vim.notify("Failed to load colorscheme: " .. colorscheme .. "\n" .. err, vim.log.levels.ERROR)
	return
end

local Color = cb.Color
local colors = cb.colors
local Group = cb.Group
local groups = cb.groups
local styles = cb.styles

-- Color.new("fg", "#F8F8F2")
-- Color.new("bglighter", "#463649")
-- Color.new("bglight", "#382B3B")
Color.new("thisBg", "#2A212C")
Color.new("thisBgDark", "#1C161D")
Color.new("thisBgDarker", "#0B0B0F")
-- Color.new("comment", "#9F70A9")
-- Color.new("thisSelection", "#454158")
Color.new("thisSelection", "#544158")
-- Color.new("subtle", "#424450")
Color.new("thisCyan", "#80FFEA")
Color.new("thisBlue", "#7970A9")
-- Color.new("green", "#8AFF80")
-- Color.new("orange", "#FFCA80")
-- Color.new("pink", "#FF80BF")
-- Color.new("purple", "#9580FF")
Color.new("thisRed", "#FF9580")
Color.new("thisYellow", "#FFFF80")
Color.new("thisLightYellow", "#f4d88c")
Color.new("thisDraculaWarnLine", "#ffca80")

Group.new("Error", colors.thisRed)
Group.new("Warning", colors.thisDraculaWarnLine)
Group.new("Information", colors.thisBlue)
Group.new("Hint", colors.thisCyan)

Group.new("CursorLine", colors.none, colors.thisBgDark, styles.NONE, colors.thisSelection)
Group.new("CursorLineNr", colors.thisYellow, colors.thisBgDarker, styles.NONE, colors.thisSelection)

Group.new("ErrorMsg", colors.thisBgDarker, colors.thisRed, styles.bold)
Group.new("WarningMsg", colors.thisBgDarker, colors.thisLightYellow, styles.bold)

-- highlight color handling
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

Group.new("DiagnosticUnderlineError", colors.thisRed, colors.none, styles.undercurl + styles.bold + styles.italic)

-- Highlight group for Visual mode
vim.cmd("highlight Visual guibg=#454158 guifg=NONE gui=reverse,bold")

-- Autocommand group for visual mode and cursor highlights
vim.api.nvim_create_augroup("_visual_mode_highlight", { clear = true })

-- Ensure Visual group is applied consistently on mode and window changes
vim.api.nvim_create_autocmd({ "ModeChanged", "WinEnter", "VimEnter" }, {
	group = "_visual_mode_highlight",
	pattern = { "*" },
	callback = function()
		vim.cmd("highlight Visual guibg=#454158 guifg=NONE gui=reverse,bold")
	end,
})

-- Disable vim-illuminate in visual mode and clear all highlights
vim.api.nvim_create_autocmd("ModeChanged", {
	group = vim.api.nvim_create_augroup("DebugIlluminateVisualMode", { clear = true }),
	pattern = { "*:v", "*:V", "*:<C-v>" },
	callback = function()
		vim.cmd("IlluminatePauseBuf")
	end,
})

vim.api.nvim_create_autocmd("ModeChanged", {
	group = vim.api.nvim_create_augroup("DebugIlluminateNormalMode", { clear = true }),
	pattern = { "v:*", "V:*", "<C-v>:*" },
	callback = function()
		vim.cmd("IlluminateResumeBuf")
	end,
})
