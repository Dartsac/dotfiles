-- Dictation card colors from the Dracula PRO palette that theme-sync
-- (repository root) writes outside this repository. No colors are stored
-- here: without that file the card keeps its own palette.

local M = {}
local HOME = os.getenv("HOME")

M.paletteFile = HOME .. "/.local/share/theme-sync/palette.json"
-- Ghostty reads its local override, where theme-sync writes the variant,
-- after the whole of its config.
M.ghosttyConfigs = { HOME .. "/.config/ghostty/config", HOME .. "/.config/ghostty/config.local.ghostty" }

-- Variant named by the last `theme =` line Ghostty reads:
-- "Dracula-Van-Helsing" -> "van-helsing"; none or unreadable -> "pro".
local function ghosttyVariant()
	local name
	for _, path in ipairs(M.ghosttyConfigs) do
		local f = io.open(path, "r")
		if f then
			for line in f:lines() do
				name = line:match("^%s*theme%s*=%s*(%S+)") or name
			end
			f:close()
		end
	end
	local variant = name and name:match("^[^-]+%-(.+)$")
	return variant and variant:lower() or "pro"
end

-- Named colors (name -> "#rrggbb") for Ghostty's variant, or nil when
-- theme-sync has not been run.
function M.palette()
	local data = hs.json.read(M.paletteFile)
	local variants = data and data.variants
	if not variants then
		return nil
	end
	return variants[ghosttyVariant()] or variants.pro
end

return M
