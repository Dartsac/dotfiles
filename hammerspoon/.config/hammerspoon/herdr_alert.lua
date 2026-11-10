-- Away alerts for herdr: an agent is done or needs input while Ghostty is not
-- in front. herdr's away-alert plugin
-- (~/.config/herdr/away-alert) decides when one is due and opens
--   hammerspoon://herdr-alert?title=…&body=…&workspace=…&pane=…&bin=…&socket=…
-- This shows a card in the dictation HUD's pixel style, top-right on the
-- screen in use. It is silent: herdr plays its own sound for the same change
-- whenever Ghostty is not in front. Click the card to bring Ghostty forward
-- and focus that agent; click × to dismiss it. Cards stay until clicked, and
-- all clear when you switch to Ghostty yourself (herdr shows the state there).
local M = {}

local GHOSTTY = "com.mitchellh.ghostty"

local function rgb(hex, alpha)
	return {
		red = tonumber(hex:sub(1, 2), 16) / 255,
		green = tonumber(hex:sub(3, 4), 16) / 255,
		blue = tonumber(hex:sub(5, 6), 16) / 255,
		alpha = alpha or 1,
	}
end

local CARD = {
	w = 320,
	h = 64,
	px = 2, -- one "pixel" of the frame and status dot, as in the dictation HUD
	pad = 12,
	edgeOffset = 12, -- from the screen's top and right edges
	gap = 8, -- between stacked cards
	font = "Hack Nerd Font Mono",
	colors = { -- the dictation HUD's Sweetie-16-ish palette
		bg = rgb("1a1c2c", 0.96),
		border = rgb("f4f4f4"),
		hover = rgb("ffcd75"),
		text = rgb("f4f4f4"),
		subtext = rgb("94b0c2"),
		done = rgb("38b764"),
		blocked = rgb("e43b44"),
	},
}

local cards = {} -- shown cards, newest first: { canvas = …, pane = … }

local function placeAll()
	local f = hs.screen.mainScreen():frame()
	for i, card in ipairs(cards) do
		card.canvas:topLeft({
			x = math.floor(f.x + f.w - CARD.w - CARD.edgeOffset),
			y = math.floor(f.y + CARD.edgeOffset + (i - 1) * (CARD.h + CARD.gap)),
		})
	end
end

local function dismiss(card)
	for i, shown in ipairs(cards) do
		if shown == card then
			table.remove(cards, i)
			card.canvas:delete()
			placeAll()
			return
		end
	end
end

local function dismissAll()
	for _, card in ipairs(cards) do
		card.canvas:delete()
	end
	cards = {}
end

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

local function focusAgent(params)
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

local function build(params, accent)
	local px, pad, w, h = CARD.px, CARD.pad, CARD.w, CARD.h
	local c = hs.canvas.new({ x = 0, y = 0, w = w, h = h })
	c:level(hs.canvas.windowLevels.overlay)
	c:behavior({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" })
	c:clickActivating(false)

	local function rect(id, frame, color, track)
		c[#c + 1] = {
			id = id,
			type = "rectangle",
			action = "fill",
			antialias = false,
			frame = frame,
			fillColor = color,
			trackMouseUp = track,
			trackMouseEnterExit = track,
		}
	end
	local function text(id, frame, str, color, size, align, track)
		c[#c + 1] = {
			id = id,
			type = "text",
			frame = frame,
			text = hs.styledtext.new(str, {
				font = { name = CARD.font, size = size },
				color = color,
				paragraphStyle = { alignment = align or "left", lineBreak = "truncateTail" },
			}),
			trackMouseUp = track,
		}
	end

	-- Background plus a 1-pixel frame with the corners notched out. The
	-- background is the click target; the frame lights up on hover.
	rect("card", { x = px, y = px, w = w - 2 * px, h = h - 2 * px }, CARD.colors.bg, true)
	rect("frame", { x = px, y = 0, w = w - 2 * px, h = px }, CARD.colors.border)
	rect("frame", { x = px, y = h - px, w = w - 2 * px, h = px }, CARD.colors.border)
	rect("frame", { x = 0, y = px, w = px, h = h - 2 * px }, CARD.colors.border)
	rect("frame", { x = w - px, y = px, w = px, h = h - 2 * px }, CARD.colors.border)

	-- Status dot, title, workspace, and the dismiss button.
	rect("dot", { x = pad, y = pad + 4, w = 4 * px, h = 4 * px }, accent)
	local textX = pad + 4 * px + 10
	local textW = w - textX - pad - 18
	text("title", { x = textX, y = pad - 2, w = textW, h = 20 }, params.title or "herdr", CARD.colors.text, 14)
	text("body", { x = textX, y = pad + 20, w = textW, h = 18 }, params.body or "", CARD.colors.subtext, 12)
	text("close", { x = w - pad - 14, y = pad - 4, w = 16, h = 20 }, "×", CARD.colors.subtext, 16, "center", true)
	return c
end

local function show(params)
	local accent = (params.title or ""):find("needs input", 1, true) and CARD.colors.blocked or CARD.colors.done
	-- A newer alert for the same agent replaces its card.
	for _, card in ipairs(cards) do
		if params.pane and params.pane ~= "" and card.pane == params.pane then
			dismiss(card)
			break
		end
	end
	local card = { pane = params.pane, canvas = build(params, accent) }
	card.canvas:mouseCallback(function(c, message, id)
		if message == "mouseEnter" or message == "mouseExit" then
			local color = message == "mouseEnter" and CARD.colors.hover or CARD.colors.border
			for i = 1, #c do
				if c[i].id == "frame" then
					c[i].fillColor = color
				end
			end
		elseif message == "mouseUp" then
			dismiss(card)
			if id ~= "close" then
				focusAgent(params)
			end
		end
	end)
	table.insert(cards, 1, card)
	placeAll()
	card.canvas:show()
end

hs.urlevent.bind("herdr-alert", function(_, params)
	show(params)
end)

-- Back in Ghostty, herdr's own sidebar and toasts take over.
M.watcher = hs.application.watcher
	.new(function(_, event, app)
		if event == hs.application.watcher.activated and app and app:bundleID() == GHOSTTY then
			dismissAll()
		end
	end)
	:start()

return M
