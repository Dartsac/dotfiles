-- Away alerts for herdr: an agent is done or needs input while Ghostty is not
-- in front. herdr's away-alert plugin
-- (~/.config/herdr/away-alert) decides when one is due and opens
--   hammerspoon://herdr-alert?title=…&body=…&workspace=…&pane=…&bin=…&socket=…
-- This posts it with a sound and Ghostty's icon. Clicking it brings Ghostty
-- forward and focuses that agent in herdr. Unused on machines without herdr.
local M = {}

local GHOSTTY = "com.mitchellh.ghostty"

-- Run herdr commands one after another, against the server that sent the alert.
local function herdr(params, commands)
	local args = table.remove(commands, 1)
	if not args then
		return
	end
	local task = hs.task.new(params.bin, function()
		herdr(params, commands)
	end, args)
	if params.socket and params.socket ~= "" then
		local env = task:environment()
		env.HERDR_SOCKET_PATH = params.socket
		task:setEnvironment(env)
	end
	task:start()
end

local function focus_agent(params)
	hs.application.launchOrFocusByBundleID(GHOSTTY)
	if not params.bin or params.bin == "" then
		return
	end
	local commands = {}
	if params.workspace and params.workspace ~= "" then
		table.insert(commands, { "workspace", "focus", params.workspace })
	end
	if params.pane and params.pane ~= "" then
		table.insert(commands, { "agent", "focus", params.pane })
	end
	herdr(params, commands)
end

hs.urlevent.bind("herdr-alert", function(_, params)
	hs.notify
		.new(function()
			focus_agent(params)
		end, {
			title = params.title or "herdr",
			informativeText = params.body or "",
			soundName = hs.notify.defaultNotificationSound,
			contentImage = hs.image.imageFromAppBundle(GHOSTTY),
			withdrawAfter = 0, -- stays in Notification Center until dismissed
		})
		:send()
end)

return M
