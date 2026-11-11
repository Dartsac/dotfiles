-- Dictation card colors from the Dracula PRO palette that theme-sync
-- (repository root) writes outside this repository. No colors are stored
-- here: without that file the card keeps its own palette.

local M = {}
local HOME = os.getenv("HOME")

M.paletteFile = HOME .. "/.local/share/theme-sync/palette.json"
M.ghosttyConfig = HOME .. "/.config/ghostty/config"

-- Variant named by Ghostty's last `theme =` line:
-- "Dracula-Van-Helsing" -> "van-helsing"; none or unreadable -> "pro".
local function ghosttyVariant()
	local f = io.open(M.ghosttyConfig, "r")
	if not f then
		return "pro"
	end
	local name
	for line in f:lines() do
		name = line:match("^%s*theme%s*=%s*(%S+)") or name
	end
	f:close()
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
