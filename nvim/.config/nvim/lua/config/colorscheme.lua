-- The colorscheme, plus this config's highlight overrides. Plain nvim_set_hl
-- (formerly Colorbuddy, which cost ~5 ms on every start for the same result:
-- it also clears each group and sets fg/bg/style).
--
-- Dracula PRO when its package is installed (theme-sync puts it in Neovim's
-- site pack directory), in the variant Ghostty's active theme names;
-- otherwise the free Dracula theme (plugins/colorscheme.lua); otherwise
-- Neovim's default. Never stops startup. The overrides need the theme's
-- palette, so they apply only with one of the two Dracula themes.
local M = {}

local GHOSTTY_CONFIG = "~/.config/ghostty/config"

-- Ghostty theme name -> Dracula PRO colorscheme.
local PRO_THEMES = {
	["Dracula-Pro"] = "dracula-pro",
	["Dracula-Alucard"] = "dracula-pro-alucard",
	["Dracula-Blade"] = "dracula-pro-blade",
	["Dracula-Buffy"] = "dracula-pro-buffy",
	["Dracula-Lincoln"] = "dracula-pro-lincoln",
	["Dracula-Morbius"] = "dracula-pro-morbius",
	["Dracula-Van-Helsing"] = "dracula-pro-van-helsing",
}
local FREE_THEME = "dracula"

---@return string?
local function ghostty_theme()
	local ok, lines = pcall(vim.fn.readfile, vim.fn.expand(GHOSTTY_CONFIG))
	if not ok then
		return
	end
	-- The last `theme =` line, the one Ghostty uses.
	local found
	for _, line in ipairs(lines) do
		found = line:match("^theme%s*=%s*(.+)$") or found
	end
	return found and vim.trim(found)
end

--- Whether :colorscheme can find `name` (on 'runtimepath' or 'packpath'),
--- asked without trying it: a failed :colorscheme leaves an error message.
local function available(name)
	return vim.tbl_contains(vim.fn.getcompletion(name, "color"), name)
end

--- The colorschemes to try, best first.
local function candidates()
	local pro = PRO_THEMES[ghostty_theme() or ""] or "dracula-pro"
	-- Packages before v2.2 name their files with underscores.
	return { pro, (pro:gsub("-", "_")), FREE_THEME }
end

--- The palette of the active colorscheme, when it is a Dracula theme. Both
--- themes give it the same shape: name -> { "#rrggbb", cterm }, and color_N
--- -> "#rrggbb".
---@return table?
function M.palette()
	local name = vim.g.colors_name or ""
	if name:find("^dracula[-_]pro") then
		return vim.g["dracula_pro#palette"]
	elseif name == FREE_THEME then
		return vim.g["dracula#palette"]
	end
end

local function apply_overrides(p)
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

local applied = false

function M.setup()
	applied = true
	for _, name in ipairs(candidates()) do
		if available(name) and pcall(vim.cmd.colorscheme, name) then
			break
		end
	end
	local palette = M.palette()
	if palette then
		apply_overrides(palette)
	end
end

--- setup(), unless the free theme's plugin has already run it as it loaded.
--- Where that plugin is missing (its install failed), Dracula PRO may still
--- be installed.
function M.ensure()
	if not applied then
		M.setup()
	end
end

return M
