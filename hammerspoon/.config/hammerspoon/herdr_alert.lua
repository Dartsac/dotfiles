-- Away alerts for herdr: an agent is done or needs input while Ghostty is not
-- in front. herdr's away-alert plugin
-- (~/.config/herdr/away-alert) decides when one is due and opens
--   hammerspoon://herdr-alert?title=…&body=…&workspace=…&pane=…&socket=…
-- This shows a card in the dictation HUD's pixel style, top-right on the
-- screen in use. It is silent: herdr plays its own sound for the same change
-- whenever Ghostty is not in front. Click the card to bring forward the Ghostty
-- window attached to that agent's herdr session and focus the agent; click ×
-- to dismiss it. Cards stay until clicked, and all clear when you switch to
-- Ghostty yourself (herdr shows the state there).
local M = {}

local GHOSTTY = "com.mitchellh.ghostty"
local HOME = os.getenv("HOME")

-- Any program can open a hammerspoon:// link, so nothing in it chooses what
-- runs: herdr is found here, the socket must be one of herdr's under
-- ~/.config/herdr, and IDs must look like herdr IDs (w1, w1:p2).
local HERDR_PATHS = { HOME .. "/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr" }
local SOCKET_DIR = HOME .. "/.config/herdr/"

local function herdrBinary()
	for _, path in ipairs(HERDR_PATHS) do
		local permissions = hs.fs.attributes(path, "permissions")
		if permissions and permissions:sub(3, 3) == "x" then
			return path
		end
	end
end

local function trustedSocket(path)
	if not path or path:sub(1, #SOCKET_DIR) ~= SOCKET_DIR or path:find("..", 1, true) then
		return nil
	end
	local rest = path:sub(#SOCKET_DIR + 1)
	if rest == "herdr.sock" or rest:match("^sessions/[%w._-]+/herdr%.sock$") then
		return path
	end
end

local function herdrId(value)
	if value and (value:match("^%w+$") or value:match("^%w+:%w+$")) then
		return value
	end
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
		bg = { hex = "#1a1c2c", alpha = 0.96 },
		border = { hex = "#f4f4f4" },
		hover = { hex = "#ffcd75" },
		text = { hex = "#f4f4f4" },
		subtext = { hex = "#94b0c2" },
		done = { hex = "#38b764" },
		blocked = { hex = "#e43b44" },
	},
}

local cards = {} -- shown cards, newest first: { canvas = …, key = socket and pane }

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
local function herdr(binary, socket, commands)
	local args = table.remove(commands, 1)
	if not args then
		return
	end
	local task = hs.task.new(binary, function()
		herdr(binary, socket, commands)
	end, args)
	local env = task:environment()
	env.HERDR_SOCKET_PATH = socket
	task:setEnvironment(env)
	task:start()
end

-- The herdr client attached to a session is the process whose Unix socket is
-- connected to one of the endpoints `lsof -nP -U` lists under the session's
-- herdr-client.sock. Columns: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NAME.
function M.clientPid(lsofOutput, clientSocket)
	local endpoints, peers = {}, {}
	for line in lsofOutput:gmatch("[^\n]+") do
		local fields = {}
		for field in line:gmatch("%S+") do
			fields[#fields + 1] = field
		end
		local name = fields[#fields]
		if name == clientSocket then
			endpoints[fields[6]] = true
		elseif fields[1] == "herdr" and name and name:sub(1, 2) == "->" then
			table.insert(peers, { pid = tonumber(fields[2]), endpoint = name:sub(3) })
		end
	end
	for _, peer in ipairs(peers) do
		if endpoints[peer.endpoint] then
			return peer.pid
		end
	end
end

-- Raise the Ghostty window (and tab) showing this session: its terminal's
-- foreground process is the herdr client. If none is found, the Ghostty
-- window already brought forward stays.
local function focusSessionWindow(socket)
	local clientSocket = socket:gsub("herdr%.sock$", "herdr-client.sock")
	hs.task
		.new("/usr/sbin/lsof", function(_, stdout)
			local pid = M.clientPid(stdout or "", clientSocket)
			if pid then
				hs.osascript.applescript(
					('tell application "Ghostty" to focus (first terminal whose pid is %d)'):format(pid)
				)
			end
		end, { "-nP", "-U" })
		:start()
end

local function focusAgent(params)
	hs.application.launchOrFocusByBundleID(GHOSTTY)
	local binary, socket = herdrBinary(), trustedSocket(params.socket)
	if not binary or not socket then
		return
	end
	focusSessionWindow(socket)
	local commands = {}
	local workspace, pane = herdrId(params.workspace), herdrId(params.pane)
	if workspace then
		table.insert(commands, { "workspace", "focus", workspace })
	end
	if pane then
		table.insert(commands, { "agent", "focus", pane })
	end
	herdr(binary, socket, commands)
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
	-- A newer alert for the same agent replaces its card. Pane IDs are only
	-- unique within one herdr session, so the session's socket is part of the key.
	local key
	if params.pane and params.pane ~= "" then
		key = (params.socket or "") .. "\n" .. params.pane
	end
	for _, card in ipairs(cards) do
		if key and card.key == key then
			dismiss(card)
			break
		end
	end
	local card = { key = key, canvas = build(params, accent) }
	card.canvas:mouseCallback(function(canvas, message, id)
		if message == "mouseEnter" or message == "mouseExit" then
			local color = message == "mouseEnter" and CARD.colors.hover or CARD.colors.border
			for i = 1, #canvas do
				if canvas[i].id == "frame" then
					canvas[i].fillColor = color
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
