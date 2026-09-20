-- Deepgram streaming dictation for Hammerspoon
-- Load from init.lua with:  dictation = require("dictation")

local M = {}
local HOME = os.getenv("HOME")

local CONFIG = {
	hotkeyMods = {}, -- e.g. {"ctrl", "alt", "cmd"} if your spare key sends a combo
	hotkeyKey = "f18", -- map your spare key to F18 (F13-F19 are unused by macOS)
	pushToTalk = false, -- true: hold key to talk; false: tap to start, tap to stop
	python = HOME .. "/.dictation-venv/bin/python",
	script = hs.configdir .. "/deepgram_stream.py",
	keyterms = "", -- comma-separated jargon to bias toward, e.g. "ServiceNow,CMDB"
	idleTimeout = "60", -- seconds of silence before auto-stop
	language = "en-US",
}

-- Floating 8-bit level meter shown only while dictating.
local function rgb(hex, alpha)
	return {
		red = tonumber(hex:sub(1, 2), 16) / 255,
		green = tonumber(hex:sub(3, 4), 16) / 255,
		blue = tonumber(hex:sub(5, 6), 16) / 255,
		alpha = alpha or 1,
	}
end

local HUD = {
	cols = 12, -- meter width, in columns
	rows = 6, -- meter height, in LED blocks
	blockW = 4,
	blockH = 3,
	gapX = 2,
	gapY = 1,
	px = 2, -- size of one "pixel" in the frame, status dot and REC text
	pad = 8,
	position = "top", -- "top" or "bottom" edge of the screen
	edgeOffset = 12, -- distance from that edge (bottom needs ~94 to clear the Dock)
	blinkSecs = 0.4,
	unlitAlpha = 0.18, -- how visible dark LED blocks are
	colors = { -- Sweetie-16-ish palette
		bg = rgb("1a1c2c", 0.96),
		border = rgb("f4f4f4"),
		low = rgb("38b764"),
		mid = rgb("ffcd75"),
		high = rgb("e43b44"),
		connecting = rgb("ef7d57"),
		listening = rgb("e43b44"),
		finishing = rgb("566c86"),
	},
}

-- 3x5 pixel glyphs
local GLYPHS = {
	R = { "110", "101", "110", "101", "101" },
	E = { "111", "100", "110", "100", "111" },
	C = { "011", "100", "100", "100", "011" },
}
local LABEL = "REC"

local task, buffer, lastChar = nil, "", nil
local hud, levels, lit, decayTimer, blinkTimer, hudState = nil, {}, {}, nil, nil, nil
local dotIdx, textIdx, blockIdx, blockColor = nil, {}, {}, {}

local function dims()
	local px = HUD.px
	local meterW = HUD.cols * HUD.blockW + (HUD.cols - 1) * HUD.gapX
	local meterH = HUD.rows * HUD.blockH + (HUD.rows - 1) * HUD.gapY
	local labelW = (#LABEL * 4 - 1) * px
	local w = px + HUD.pad + 3 * px + 2 * px + labelW + HUD.pad + meterW + HUD.pad + px
	local h = px + HUD.pad + meterH + HUD.pad + px
	return w, h, labelW
end

local function rowColor(r)
	if r <= HUD.rows * 0.5 then
		return HUD.colors.low
	elseif r <= HUD.rows * 0.84 then
		return HUD.colors.mid
	end
	return HUD.colors.high
end

local function withAlpha(c, a)
	return { red = c.red, green = c.green, blue = c.blue, alpha = a }
end

local function buildHud()
	local px = HUD.px
	local w, h, labelW = dims()
	local c = hs.canvas.new({ x = 0, y = 0, w = w, h = h })
	c:level(hs.canvas.windowLevels.overlay)
	c:behavior({ "canJoinAllSpaces", "stationary" })
	c:clickActivating(false)

	local function add(frame, color)
		c[#c + 1] = { type = "rectangle", action = "fill", antialias = false, frame = frame, fillColor = color }
		return #c
	end

	-- Background plus a 1-pixel frame with the corners notched out.
	add({ x = px, y = px, w = w - 2 * px, h = h - 2 * px }, HUD.colors.bg)
	add({ x = px, y = 0, w = w - 2 * px, h = px }, HUD.colors.border)
	add({ x = px, y = h - px, w = w - 2 * px, h = px }, HUD.colors.border)
	add({ x = 0, y = px, w = px, h = h - 2 * px }, HUD.colors.border)
	add({ x = w - px, y = px, w = px, h = h - 2 * px }, HUD.colors.border)

	-- Status dot and pixel-font label.
	local x = px + HUD.pad
	dotIdx = add({ x = x, y = (h - 3 * px) / 2, w = 3 * px, h = 3 * px }, HUD.colors.connecting)
	x = x + 5 * px
	local ty = (h - 5 * px) / 2
	textIdx = {}
	for i = 1, #LABEL do
		local glyph = GLYPHS[LABEL:sub(i, i)]
		for r = 1, 5 do
			for col = 1, 3 do
				if glyph[r]:sub(col, col) == "1" then
					local frame = { x = x + (col - 1) * px, y = ty + (r - 1) * px, w = px, h = px }
					table.insert(textIdx, add(frame, HUD.colors.connecting))
				end
			end
		end
		x = x + 4 * px
	end

	-- LED meter: columns of blocks, lit bottom-up.
	x = px + HUD.pad + 5 * px + labelW + HUD.pad
	local bottomY = h - px - HUD.pad - HUD.blockH
	blockIdx, blockColor = {}, {}
	for col = 1, HUD.cols do
		blockIdx[col] = {}
		for r = 1, HUD.rows do
			if col == 1 then
				blockColor[r] = { on = rowColor(r), off = withAlpha(rowColor(r), HUD.unlitAlpha) }
			end
			local frame = {
				x = x + (col - 1) * (HUD.blockW + HUD.gapX),
				y = bottomY - (r - 1) * (HUD.blockH + HUD.gapY),
				w = HUD.blockW,
				h = HUD.blockH,
			}
			blockIdx[col][r] = add(frame, blockColor[r].off)
		end
	end
	return c
end

-- Only touch blocks whose lit state changed.
local function drawBars()
	if not hud then
		return
	end
	for col = 1, HUD.cols do
		local n = math.floor((levels[col] or 0) * HUD.rows + 0.5)
		local was = lit[col] or 0
		if n ~= was then
			for r = math.min(n, was) + 1, math.max(n, was) do
				hud[blockIdx[col][r]].fillColor = r <= n and blockColor[r].on or blockColor[r].off
			end
			lit[col] = n
		end
	end
end

-- New levels enter on the right and scroll left.
local function pushLevel(v)
	table.insert(levels, v)
	while #levels > HUD.cols do
		table.remove(levels, 1)
	end
	drawBars()
end

local function setStatusColor(color)
	hud[dotIdx].fillColor = color
	for _, i in ipairs(textIdx) do
		hud[i].fillColor = color
	end
end

local function stopTimers()
	if decayTimer then
		decayTimer:stop()
		decayTimer = nil
	end
	if blinkTimer then
		blinkTimer:stop()
		blinkTimer = nil
	end
end

local function setState(state)
	hudState = state
	if not hud then
		hud = buildHud()
	end
	stopTimers()
	local color = HUD.colors[state]
	setStatusColor(color)
	if state == "connecting" then
		levels = {}
		drawBars()
		local w, h = dims()
		local f = hs.screen.mainScreen():frame()
		local y = HUD.position == "top" and (f.y + HUD.edgeOffset) or (f.y + f.h - h - HUD.edgeOffset)
		hud:topLeft({ x = math.floor(f.x + (f.w - w) / 2), y = math.floor(y) })
		hud:show()
	elseif state == "listening" then
		local on = true
		blinkTimer = hs.timer.doEvery(HUD.blinkSecs, function()
			on = not on
			hud[dotIdx].fillColor = on and color or HUD.colors.bg
		end)
	elseif state == "finishing" then
		-- Let the meter drain while the last words are finalized.
		decayTimer = hs.timer.doEvery(0.06, function()
			pushLevel(0)
		end)
	end
end

local function hideHud()
	hudState = nil
	stopTimers()
	if hud then
		hud:hide()
	end
end

-- Type text into the focused app. Any newlines are sent as Shift+Return so
-- chat apps don't send the message.
local function typeText(text)
	if lastChar and not lastChar:match("%s") and not text:match("^%s") then
		text = " " .. text
	end
	local first = true
	for part in (text .. "\n"):gmatch("(.-)\n") do
		if not first then
			hs.eventtap.keyStroke({ "shift" }, "return", 0)
		end
		if #part > 0 then
			hs.eventtap.keyStrokes(part)
		end
		first = false
	end
	lastChar = text:sub(-1)
end

local function handle(msg)
	if msg.level then
		if hudState ~= "finishing" then
			pushLevel(msg.level)
		end
	elseif msg.text then
		typeText(msg.text)
	elseif msg.event == "ready" then
		if hudState == "connecting" then
			setState("listening")
		end
	elseif msg.event == "idle_timeout" then
		hs.alert.show("Dictation stopped (silence)")
		setState("finishing")
	elseif msg.event == "error" then
		hs.alert.show("Dictation error: " .. tostring(msg.message), 4)
	end
end

local function onStream(_, stdout, stderr)
	if stdout and #stdout > 0 then
		buffer = buffer .. stdout
		while true do
			local nl = buffer:find("\n", 1, true)
			if not nl then
				break
			end
			local line = buffer:sub(1, nl - 1)
			buffer = buffer:sub(nl + 1)
			local ok, msg = pcall(hs.json.decode, line)
			if ok and msg then
				handle(msg)
			end
		end
	end
	if stderr and #stderr > 0 then
		print("[dictation] " .. stderr)
	end
	return true
end

local function onExit(code)
	task = nil
	hideHud()
	if code ~= 0 then
		print("[dictation] helper exited with code " .. tostring(code))
	end
end

function M.start()
	if task and task:isRunning() then
		return
	end
	buffer, lastChar = "", nil
	task = hs.task.new(CONFIG.python, onExit, onStream, { CONFIG.script })
	task:setEnvironment({
		HOME = HOME,
		PATH = "/usr/bin:/bin:/usr/sbin:/sbin",
		DICTATION_KEYTERMS = CONFIG.keyterms,
		DICTATION_IDLE_TIMEOUT = CONFIG.idleTimeout,
		DICTATION_LANGUAGE = CONFIG.language,
	})
	task:start()
	setState("connecting")
end

function M.stop()
	if task and task:isRunning() then
		setState("finishing")
		task:interrupt() -- SIGINT: helper flushes remaining audio, types last words, exits
	end
end

function M.toggle()
	if task and task:isRunning() then
		M.stop()
	else
		M.start()
	end
end

if CONFIG.pushToTalk then
	M.hotkey = hs.hotkey.bind(CONFIG.hotkeyMods, CONFIG.hotkeyKey, M.start, M.stop)
else
	M.hotkey = hs.hotkey.bind(CONFIG.hotkeyMods, CONFIG.hotkeyKey, M.toggle)
end

return M
