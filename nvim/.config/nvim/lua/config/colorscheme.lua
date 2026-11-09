-- Dracula Pro, following Ghostty's active theme, plus this config's highlight
-- overrides. Plain nvim_set_hl (formerly Colorbuddy, which cost ~5 ms on every
-- start for the same result: it also clears each group and sets fg/bg/style).
local M = {}

local GHOSTTY_CONFIG = "~/.config/ghostty/config"

local THEMES = {
	["Dracula-Pro"] = "dracula_pro",
	["Dracula-Alucard"] = "dracula_pro_alucard",
	["Dracula-Blade"] = "dracula_pro_blade",
	["Dracula-Buffy"] = "dracula_pro_buffy",
	["Dracula-Lincoln"] = "dracula_pro_lincoln",
	["Dracula-Morbius"] = "dracula_pro_morbius",
	["Dracula-Van-Helsing"] = "dracula_pro_van_helsing",
}

---@return string?
local function ghostty_theme()
	local ok, lines = pcall(vim.fn.readfile, vim.fn.expand(GHOSTTY_CONFIG))
	if not ok then
		return
	end
	-- The last `theme =` line, the one Ghostty uses (as does tmux's
	-- update-tmux-colors.sh).
	local found
	for _, line in ipairs(lines) do
		found = line:match("^theme%s*=%s*(.+)$") or found
	end
	return found and vim.trim(found)
end

function M.setup()
	-- Always load a Dracula palette, even outside Ghostty or with an
	-- unrecognized terminal theme, before applying palette-based highlights.
	vim.cmd.colorscheme(THEMES[ghostty_theme() or ""] or "dracula_pro")

	local p = vim.g["dracula_pro#palette"]
	local c = {
		fg = p.fg[1],
		bg_dark = p.bgdark[1],
		bg_darker = p.bgdarker[1],
		selection = p.selection[1],
		cyan = p.cyan[1],
		orange = p.orange[1],
		purple = p.purple[1],
		red = p.red[1],
		yellow = p.yellow[1],
		light_yellow = p.color_11,
		highlight = "#554158",
		highlight_definition = "#569473",
	}

	local groups = {
		Error = { fg = c.red },
		Warning = { fg = c.orange },
		Information = { fg = c.purple },
		Hint = { fg = c.cyan },

		Normal = {}, -- clear background (and foreground): the terminal's show through
		CursorLine = { bg = c.bg_dark },
		CursorLineNr = { fg = c.yellow, bg = c.bg_darker },

		ErrorMsg = { fg = c.bg_darker, bg = c.red, bold = true },
		WarningMsg = { fg = c.bg_darker, bg = c.light_yellow, bold = true },

		IlluminatedWordText = { bg = c.highlight, bold = true, italic = true },
		IlluminatedWordRead = { bg = c.highlight, bold = true, italic = true },
		IlluminatedWordWrite = { bg = c.highlight_definition, bold = true, italic = true },

		TelescopePromptCounter = { fg = c.fg },

		DiagnosticVirtualTextError = { fg = c.bg_darker, bg = c.red, bold = true },
		DiagnosticVirtualTextWarn = { fg = c.bg_darker, bg = c.orange, bold = true },
		DiagnosticVirtualTextInfo = { fg = c.bg_darker, bg = c.purple },
		DiagnosticVirtualTextHint = { fg = c.bg_darker, bg = c.cyan },
		DiagnosticUnderlineError = { fg = c.red, undercurl = true, bold = true, italic = true },
	}
	for name, hl in pairs(groups) do
		vim.api.nvim_set_hl(0, name, hl)
	end

	local visual = { bg = c.selection, reverse = true, bold = true }
	vim.api.nvim_set_hl(0, "Visual", visual)
	-- Re-apply the Visual group in case it's overwritten.
	vim.api.nvim_create_autocmd({ "ModeChanged", "WinEnter", "VimEnter" }, {
		group = vim.api.nvim_create_augroup("_visual_mode_highlight", { clear = true }),
		callback = function()
			vim.api.nvim_set_hl(0, "Visual", visual)
		end,
	})
end

return M
