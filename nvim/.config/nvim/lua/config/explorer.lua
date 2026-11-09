-- Snacks explorer integration: multiplexer split actions and the Harpoon delete hook.
local M = {}

--- Open the item under the cursor in a new tmux or herdr pane. The explorer
--- stays open, as it does after opening a file normally.
---@param direction "vertical"|"horizontal"
function M.pane_split(direction)
	return function(_, item)
		if not item or not item.file then
			return
		end
		require("config.multiplexer").split(item.file, direction)
	end
end

--- Keep Snacks' normal formatting, replacing only empty-directory icons.
function M.format(item, picker)
	local format = require("snacks.picker.format")
	local ret = format.file(item, picker)
	if not item.dir or not item.file or picker.opts.icons.files.enabled == false then
		return ret
	end

	-- Check the filesystem, not the filtered tree: hidden/ignored children count.
	-- Do not cache this result, so creating or deleting children updates the icon.
	local scan = vim.uv.fs_scandir(item.file)
	if not scan or vim.uv.fs_scandir_next(scan) then
		return ret
	end

	local filename = format.filename(item, picker)
	local original = filename[1]
	if original then
		for _, chunk in ipairs(ret) do
			if chunk.virtual and chunk[1] == original[1] and chunk[2] == original[2] then
				chunk[1] = Snacks.picker.util.align(
					item.open and "" or "",
					picker.opts.formatters.file.icon_width or 2
				)
				break
			end
		end
	end
	return ret
end

--- Explorer source options (merged into Snacks' `picker.sources.explorer`).
function M.source()
	return {
		-- Right-hand sidebar, following the current file; previews off until
		-- toggled with P (or <a-p>). The explorer stays open after a selection.
		layout = { preset = "sidebar", preview = false, layout = { position = "right" } },
		format = M.format,
		follow_file = true,
		git_status = true,
		diagnostics = true,
		auto_close = false,
		jump = { close = false },
		-- Names keep the normal text colour; git state shows as a coloured
		-- glyph (see M.highlights).
		formatters = { file = { git_status_hl = false } },
		actions = {
			pane_vertical = { action = M.pane_split("vertical"), desc = "Vertical pane split" },
			pane_horizontal = { action = M.pane_split("horizontal"), desc = "Horizontal pane split" },
		},
		win = {
			list = {
				keys = {
					-- | and _ open multiplexer splits, as in tmux and herdr themselves;
					-- H and <a-h> (Snacks' defaults) toggle hidden files.
					["|"] = { "pane_vertical", desc = "Vertical pane split" },
					["_"] = { "pane_horizontal", desc = "Horizontal pane split" },
					-- Leave Ctrl-j/k to window/pane navigation, as in every other window.
					["<c-j>"] = false,
					["<c-k>"] = false,
				},
			},
		},
	}
end

-- Colours ---------------------------------------------------------------
--
-- Modelled on nvim-tree's defaults (the editor background, a cursor-line band,
-- names in the normal text colour, git state as coloured glyphs) and ordered
-- by perceived lightness so importance and brightness agree:
--
--   tree guides  <  folder icons, hidden/ignored  <  folder names  <  git glyphs  <  file names
--   (NonText)       (Comment)                        (Directory)      (GitSigns*)     (Normal)
--
-- * Structure (guides, folder icons) uses the theme's low-chroma neutrals,
--   which share the folder-name hue: analogous, so it frames without competing.
-- * File names are never recoloured by git state (Snacks' default made
--   untracked names near-invisible); state is a coloured glyph instead, so
--   colour is never the only signal.
-- * Git colours reuse the sign column's groups: one meaning per colour.
-- * The selected row is the editor's own cursor-line band (as in nvim-tree),
--   not reverse video or the Visual band: every colour above keeps its
--   meaning and its contrast on it (Visual's lighter band took folder names
--   to about 3:1 and dimmed entries below it). The name is also bold there.
-- Only highlight groups are referenced, never palette values: the colours
-- follow whichever colorscheme is active.

local function resolved(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	return ok and hl or {}
end

--- Explorer highlight groups (applied with nvim_set_hl, overriding Snacks'
--- defaults). Snacks pickers are used only for the explorer in this config.
---@return table<string, vim.api.keyset.highlight>
function M.highlights()
	local comment = resolved("Comment").fg
	local band = resolved("CursorLine").bg or resolved("Visual").bg
	return {
		-- Same background as the editor, like nvim-tree.
		SnacksPicker = { link = "Normal" },
		SnacksPickerList = { link = "Normal" },
		SnacksPickerInput = { link = "Normal" },
		SnacksPickerBorder = comment and { fg = comment } or { link = "WinSeparator" },
		SnacksPickerListCursorLine = band and { bg = band, bold = true } or { link = "CursorLine" },
		-- Structure recedes.
		SnacksPickerTree = { link = "NonText" },
		SnacksPickerDirectoryIcon = { link = "Comment" }, -- via mini.icons (lua/plugins/mini.lua)
		SnacksPickerPathHidden = { link = "Comment" },
		SnacksPickerPathIgnored = comment and { fg = comment, italic = true } or { link = "Comment" },
		-- Git state: glyph colours shared with the sign column.
		SnacksPickerGitStatusAdded = { link = "GitSignsAdd" },
		SnacksPickerGitStatusUntracked = { link = "GitSignsAdd" },
		SnacksPickerGitStatusModified = { link = "GitSignsChange" },
		SnacksPickerGitStatusDeleted = { link = "GitSignsDelete" },
		SnacksPickerGitStatusIgnored = { link = "Comment" },
	}
end

function M.apply_highlights()
	for name, spec in pairs(M.highlights()) do
		vim.api.nvim_set_hl(0, name, spec)
	end
end

--- Apply now and after every colorscheme change.
function M.setup_highlights()
	M.apply_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("explorer_highlights", { clear = true }),
		callback = M.apply_highlights,
	})
end

function M.install_delete_hook()
	local ok, actions = pcall(require, "snacks.explorer.actions")
	if not ok then
		vim.notify("Snacks explorer actions unavailable: " .. tostring(actions), vim.log.levels.WARN)
		return false
	end
	return require("config.harpoon_cleanup").wrap_snacks_delete(actions)
end

return M
