-- lua/plugins/colorscheme.lua
return {
	"tjdevries/colorbuddy.nvim", -- Add the dependency for colorbuddy
	lazy = false,
	priority = 1000,
	config = function()
		local cb = require("colorbuddy.init")

		local ghostty_config_path = vim.fn.expand("~/.config/ghostty/config")

		local function get_active_ghostty_theme(path)
			local ok, lines = pcall(vim.fn.readfile, path)
			if not ok then
				return
			end
			for _, line in ipairs(lines) do
				local theme = line:match("^theme%s*=%s*(.+)$")
				if theme then
					return theme
				end
			end
			return nil
		end

		local function get_vim_colorscheme(ghostty_theme)
			local theme_map = {
				["Dracula-Pro"] = "dracula_pro",
				["Dracula-Alucard"] = "dracula_pro_alucard",
				["Dracula-Blade"] = "dracula_pro_blade",
				["Dracula-Buffy"] = "dracula_pro_buffy",
				["Dracula-Lincoln"] = "dracula_pro_lincoln",
				["Dracula-Morbius"] = "dracula_pro_morbius",
				["Dracula-Van-Helsing"] = "dracula_pro_van_helsing",
			}
			return theme_map[ghostty_theme] or nil
		end

		local ghostty_theme = get_active_ghostty_theme(ghostty_config_path)
		if ghostty_theme then
			local vim_colorscheme = get_vim_colorscheme(ghostty_theme)
			if vim_colorscheme then
				vim.cmd("colorscheme " .. vim_colorscheme)
			else
				print("No matching Vim color scheme for Ghostty theme:", ghostty_theme)
			end
		else
			print("No active Ghostty theme found.")
		end

		local Color = cb.Color
		local Group = cb.Group
		local colors = cb.colors
		local groups = cb.groups
		local styles = cb.styles

		local dracula_colors = vim.g["dracula_pro#palette"]
		-- Define colors
		Color.new("thisFg", dracula_colors.fg[1])

		Color.new("thisBgLighter", dracula_colors.bglighter[1])
		Color.new("thisBgLight", dracula_colors.bglight[1])
		Color.new("thisBg", dracula_colors.bg[1])
		Color.new("thisBgDark", dracula_colors.bgdark[1])
		Color.new("thisBgDarker", dracula_colors.bgdarker[1])

		Color.new("thisComment", dracula_colors.comment[1])
		Color.new("thisSelection", dracula_colors.selection[1])
		Color.new("thisSubtle", dracula_colors.subtle[1])

		Color.new("thisCyan", dracula_colors.cyan[1])
		Color.new("thisGreen", dracula_colors.green[1])
		Color.new("thisOrange", dracula_colors.orange[1])
		Color.new("thisPink", dracula_colors.pink[1])
		Color.new("thisPurple", dracula_colors.purple[1])
		Color.new("thisRed", dracula_colors.red[1])
		Color.new("thisYellow", dracula_colors.yellow[1])

		Color.new("thisLightCyan", vim.g["dracula_pro#palette"].color_14)
		Color.new("thisLightGreen", vim.g["dracula_pro#palette"].color_10)
		Color.new("thisLightPink", vim.g["dracula_pro#palette"].color_13)
		Color.new("thisLightPurple", vim.g["dracula_pro#palette"].color_12)
		Color.new("thisLightRed", vim.g["dracula_pro#palette"].color_9)
		Color.new("thisLightYellow", vim.g["dracula_pro#palette"].color_11)

		Color.new("thisHighlight", "#554158")
		Color.new("thisHighlightDefinition", "#569473")

		-- Define groups
		Group.new("Error", colors.thisRed)
		Group.new("Warning", colors.thisOrange)
		Group.new("Information", colors.thisPurple)
		Group.new("Hint", colors.thisCyan)

		-- sets the background to clear
		Group.new("Normal", colors.none, colors.none, styles.NONE)
		Group.new("CursorLine", colors.none, colors.thisBgDark, styles.NONE, colors.thisSelection)
		Group.new("CursorLineNr", colors.thisYellow, colors.thisBgDarker, styles.NONE, colors.thisSelection)

		Group.new("ErrorMsg", colors.thisBgDarker, colors.thisRed, styles.bold)
		Group.new("WarningMsg", colors.thisBgDarker, colors.thisLightYellow, styles.bold)

		Group.new("IlluminatedWordText", colors.none, colors.thisHighlight, styles.bold + styles.italic)
		Group.new("IlluminatedWordRead", colors.none, colors.thisHighlight, styles.bold + styles.italic)
		Group.new("IlluminatedWordWrite", colors.none, colors.thisHighlightDefinition, styles.bold + styles.italic)

		Group.new("TelescopePromptCounter", colors.thisFg, colors.none, styles.NONE)

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
		Group.new("Visual", colors.none, colors.thisSelection, styles.reverse + styles.bold)

		-- Autocommand group for visual mode and cursor highlights
		vim.api.nvim_create_augroup("_visual_mode_highlight", { clear = true })
		vim.api.nvim_create_autocmd({ "ModeChanged", "WinEnter", "VimEnter" }, {
			group = "_visual_mode_highlight",
			pattern = { "*" },
			callback = function()
				-- Re-apply the Visual group in case it's overwritten
				Group.new("Visual", colors.none, colors.thisSelection, styles.reverse + styles.bold)
			end,
		})
	end,
}
