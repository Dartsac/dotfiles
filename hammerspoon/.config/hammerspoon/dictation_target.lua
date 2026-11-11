-- Where would dictated text go right now?
-- Reads the frontmost app's focused element through the Accessibility API.
-- Verified against Ghostty, VS Code, Discord, Claude, ChatGPT, Obsidian,
-- Chrome (Gmail), Safari, Notes and Messages.

local M = {}

-- Roles that accept typed or pasted text. Checked by role, not by whether
-- AXValue is settable: Ghostty's terminal reports AXValue as read-only.
local TEXT_ROLES = {
	AXTextArea = true,
	AXTextField = true,
	AXComboBox = true, -- e.g. the Google search box in Safari
	AXSearchField = true,
	AXSecureTextField = true,
}

local AX_TIMEOUT = 0.3 -- seconds; a hung app must not freeze Hammerspoon
-- Chromium and Electron apps report no focused element until accessibility is
-- switched on, and VS Code needs a moment after that. Until this many seconds
-- have passed, "no focused element" means "checking", not "no field".
local SETTLE_SECS = 1.0
-- A text element covering most of its window is a terminal or similar
-- full-window surface; outlining it would not point at anything.
local FULL_WINDOW_RATIO = 0.8

local woken = {} -- pid -> true once AXManualAccessibility was set
local lastPid, changedAt = nil, 0

local function area(r)
	return (r and r.w and r.h) and r.w * r.h or 0
end

-- Returns {
--   status = "field" | "none" | "checking",
--   app    = app name,
--   window = focused window title or nil,
--   frame  = {x, y, w, h} of the text field to outline, or nil,
-- }
function M.check()
	local app = hs.application.frontmostApplication()
	if not app then
		return { status = "none", app = "?" }
	end
	local pid, name = app:pid(), app:title()
	local axApp = hs.axuielement.applicationElement(app)
	local now = hs.timer.secondsSinceEpoch()
	if pid ~= lastPid then
		lastPid, changedAt = pid, now
	end
	local result = { status = "none", app = name }
	if not axApp then
		return result
	end
	axApp:setTimeout(AX_TIMEOUT)

	-- Window read through AX with the timeout above; hs.window would use the
	-- much longer global default.
	local win = axApp:attributeValue("AXFocusedWindow")
	local winFrame
	if win then
		win:setTimeout(AX_TIMEOUT)
		local title = win:attributeValue("AXTitle")
		result.window = (title and title ~= "") and title or nil
		winFrame = win:attributeValue("AXFrame")
	end

	if not woken[pid] then
		woken[pid] = true
		changedAt = now
		axApp:setAttributeValue("AXManualAccessibility", true) -- fails harmlessly in native apps
	end

	local el = axApp:attributeValue("AXFocusedUIElement")
	if not el then
		if now - changedAt < SETTLE_SECS then
			result.status = "checking"
		end
		return result
	end
	el:setTimeout(AX_TIMEOUT)
	if not TEXT_ROLES[el:attributeValue("AXRole") or ""] then
		return result
	end

	result.status = "field"
	local frame = el:attributeValue("AXFrame")
	if area(frame) > 0 and (area(winFrame) == 0 or area(frame) < area(winFrame) * FULL_WINDOW_RATIO) then
		result.frame = frame
	end
	return result
end

return M
