-- Deepgram record-then-transcribe dictation for Hammerspoon
-- Load from init.lua with:  dictation = require("dictation")
--
-- While recording, the card shows where the text will go (app and window, or
-- NO TEXT FIELD) and an outline marks the focused text field. Stopping with no
-- text field focused sends nothing to Deepgram: the audio is kept on disk and
-- the kept-recording hotkey transcribes it to the clipboard.

local target = require("dictation_target")

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
	keptMods = { "shift" }, -- hotkey that transcribes the kept recording to the clipboard
	keptKey = "f18",
	keptPath = HOME .. "/.cache/dictation/kept.wav",
	targetPollSecs = 0.3, -- how often the card rechecks where the text would go
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
	maxW = 360, -- the card grows to fit the target line up to this width
	lineGap = 6, -- between the meter row and the target line
	lineH = 15,
	font = "Menlo",
	textSize = 11,
	outlinePad = 3, -- gap between the text field and its outline
	outlineWidth = 2,
	unlitAlpha = 0.18, -- how visible dark LED blocks are
	colors = { -- Sweetie-16-ish palette
		bg = rgb("1a1c2c"),
		border = rgb("f4f4f4"),
		low = rgb("38b764"),
		mid = rgb("ffcd75"),
		high = rgb("e43b44"),
		connecting = rgb("ef7d57"),
		listening = rgb("e43b44"),
		finishing = rgb("566c86"),
		text = rgb("f4f4f4"),
		checking = rgb("94b0c2"),
		warn = rgb("e43b44"),
		outline = rgb("ffcd75"),
	},
}

-- 3x5 pixel glyphs
local GLYPHS = {
	R = { "110", "101", "110", "101", "101" },
	E = { "111", "100", "110", "100", "111" },
	C = { "011", "100", "100", "100", "011" },
}
local LABEL = "REC"

local task, buffer = nil, ""
local deliver = "paste" -- "paste" for live dictation, "copy" for the kept recording
local hud, levels, lit, decayTimer, blinkTimer, hudState = nil, {}, {}, nil, nil, nil
local dotIdx, textIdx, blockIdx, blockColor = nil, {}, {}, {}
local borderIdx, targetIdx, hudW, hudScreen = {}, nil, nil, nil
local outline, targetTimer, shownTarget = nil, nil, nil

-- Card size. rowW is the REC + meter row; the card is at least that wide and
-- grows (up to maxW) to fit a target line textW pixels wide.
local function dims(textW)
	local px = HUD.px
	local meterW = HUD.cols * HUD.blockW + (HUD.cols - 1) * HUD.gapX
	local meterH = HUD.rows * HUD.blockH + (HUD.rows - 1) * HUD.gapY
	local labelW = (#LABEL * 4 - 1) * px
	local rowW = px + HUD.pad + 3 * px + 2 * px + labelW + HUD.pad + meterW + HUD.pad + px
	-- +4: canvas text renders slightly wider than getTextDrawingSize reports
	local fit = math.ceil((textW or 0) + 4 + 2 * (px + HUD.pad))
	local w = math.min(math.max(rowW, fit), HUD.maxW)
	local h = px + HUD.pad + meterH + HUD.lineGap + HUD.lineH + HUD.pad + px
	return w, h, labelW, meterH, rowW, meterW
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

local function buildHud(w)
	local px = HUD.px
	local minW, h, labelW, meterH, _, meterW = dims()
	w = math.max(w or minW, minW)
	-- Centre REC + meter; the status dot hangs to the left of REC.
	local gx = math.floor((w - (labelW + HUD.pad + meterW)) / 2)
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
	borderIdx = {
		add({ x = px, y = 0, w = w - 2 * px, h = px }, HUD.colors.border),
		add({ x = px, y = h - px, w = w - 2 * px, h = px }, HUD.colors.border),
		add({ x = 0, y = px, w = px, h = h - 2 * px }, HUD.colors.border),
		add({ x = w - px, y = px, w = px, h = h - 2 * px }, HUD.colors.border),
	}

	-- Status dot and pixel-font label, centred on the meter row.
	local rowTop = px + HUD.pad
	local rowMid = rowTop + meterH / 2
	local x = gx - 5 * px
	dotIdx = add({ x = x, y = rowMid - 1.5 * px, w = 3 * px, h = 3 * px }, HUD.colors.connecting)
	x = x + 5 * px
	local ty = rowMid - 2.5 * px
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
	x = gx + labelW + HUD.pad
	local bottomY = rowTop + meterH - HUD.blockH
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

	-- Target line: where the text will go.
	c[#c + 1] = {
		type = "text",
		text = "",
		textFont = HUD.font,
		textSize = HUD.textSize,
		textColor = HUD.colors.checking,
		textLineBreak = "truncateTail",
		textAlignment = "center",
		frame = { x = px + HUD.pad, y = rowTop + meterH + HUD.lineGap, w = w - 2 * (px + HUD.pad), h = HUD.lineH },
	}
	targetIdx = #c
	return c, w
end

local function placeHud()
	local _, h = dims()
	local f = hudScreen
	local y = HUD.position == "top" and (f.y + HUD.edgeOffset) or (f.y + f.h - h - HUD.edgeOffset)
	hud:topLeft({ x = math.floor(f.x + (f.w - hudW) / 2), y = math.floor(y) })
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
	if not hud then
		return
	end
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
		hud, hudW = buildHud()
	end
	stopTimers()
	local color = HUD.colors[state]
	setStatusColor(color)
	if state == "connecting" then
		levels = {}
		drawBars()
		hudScreen = hs.screen.mainScreen():frame()
		placeHud()
		hud:show()
	elseif state == "listening" then
		local on = true
		blinkTimer = hs.timer.doEvery(HUD.blinkSecs, function()
			on = not on
			hud[dotIdx].fillColor = on and color or HUD.colors.bg
		end)
	elseif state == "finishing" then
		-- Let the meter drain while the complete recording is transcribed.
		decayTimer = hs.timer.doEvery(0.06, function()
			pushLevel(0)
		end)
	end
end

-- Outline around the focused text field; nil hides it.
local function showOutline(frame)
	if not frame then
		if outline then
			outline:hide()
		end
		return
	end
	local pad, sw = HUD.outlinePad + HUD.outlineWidth, HUD.outlineWidth
	local f = { x = frame.x - pad, y = frame.y - pad, w = frame.w + 2 * pad, h = frame.h + 2 * pad }
	if not outline then
		outline = hs.canvas.new(f)
		outline:level(hs.canvas.windowLevels.overlay)
		outline:behavior({ "canJoinAllSpaces", "stationary" })
		outline:clickActivating(false)
		outline[1] = { type = "rectangle", action = "stroke", strokeColor = HUD.colors.outline, strokeWidth = sw }
	else
		outline:frame(f)
	end
	-- Inset by half the stroke so the whole line is inside the canvas.
	outline[1].frame = { x = sw / 2, y = sw / 2, w = f.w - sw, h = f.h - sw }
	outline:show()
end

-- Short card line. The window title is only added when there is no outline
-- (Ghostty and other terminals), where it names the herdr pane or tab.
local function targetLabel(t)
	if t.status == "checking" then
		return "… " .. t.app, HUD.colors.checking
	elseif t.status == "none" then
		return "NO TEXT FIELD · " .. t.app, HUD.colors.warn
	elseif not t.frame and t.window then
		return "→ " .. t.app .. " · " .. t.window, HUD.colors.text
	end
	return "→ " .. t.app, HUD.colors.text
end

-- Rebuild the card at a new width, keeping its state, meter and position.
local function resizeHud(textW)
	local w = dims(textW)
	if w == hudW then
		return
	end
	local showing = hud:isShowing()
	hud:delete()
	hud, hudW = buildHud(w)
	lit = {}
	drawBars()
	if hudState then
		setStatusColor(HUD.colors[hudState])
	end
	if hudScreen then
		placeHud()
	end
	if showing then
		hud:show()
	end
end

-- Card line, card border and field outline for a target.check() result.
local function showTarget(t)
	if not hud then
		return
	end
	local text, color = targetLabel(t)
	local f = t.status == "field" and t.frame or nil
	-- %g, not %d: Messages and other Apple apps report half-point frames.
	local key = text .. (f and string.format("|%g,%g,%g,%g", f.x, f.y, f.w, f.h) or "")
	if key == shownTarget then
		return
	end
	shownTarget = key
	local size = hs.drawing.getTextDrawingSize(text, { font = HUD.font, size = HUD.textSize })
	resizeHud(size and size.w or 0)
	hud[targetIdx].text = text
	hud[targetIdx].textColor = color
	local border = t.status == "none" and HUD.colors.warn or HUD.colors.border
	for _, i in ipairs(borderIdx) do
		hud[i].fillColor = border
	end
	showOutline(f)
end

local function checkTarget()
	local ok, t = pcall(target.check)
	if not ok then
		print("[dictation] target check failed: " .. tostring(t))
		return { status = "none", app = "?" }
	end
	return t
end

-- Display only: an error here is logged and must never block stopping.
local function refreshTarget(t)
	local ok, err = pcall(showTarget, t or checkTarget())
	if not ok then
		print("[dictation] target display failed: " .. tostring(err))
	end
end

local function startTargetPoll()
	shownTarget = nil
	refreshTarget()
	targetTimer = hs.timer.doEvery(CONFIG.targetPollSecs, function()
		refreshTarget()
	end)
end

local function stopTargetPoll()
	if targetTimer then
		targetTimer:stop()
		targetTimer = nil
	end
end

local function hideHud()
	hudState = nil
	stopTimers()
	stopTargetPoll()
	showOutline(nil)
	if hud then
		hud:hide()
	end
end

-- Paste text into the focused app, then restore the previous clipboard.
-- The transcript is marked transient so clipboard managers skip it.
local PASTE_RESTORE_SECS = 0.5

local function pasteText(text)
	local saved = hs.pasteboard.readAllData()
	hs.pasteboard.writeAllData({
		["public.utf8-plain-text"] = text,
		["org.nspasteboard.TransientType"] = "",
	})
	local ours = hs.pasteboard.changeCount()
	hs.eventtap.keyStroke({ "cmd" }, "v", 0)
	hs.timer.doAfter(PASTE_RESTORE_SECS, function()
		if hs.pasteboard.changeCount() ~= ours then
			return -- something else was copied meanwhile; leave it alone
		end
		if saved and next(saved) then
			hs.pasteboard.writeAllData(saved)
		else
			hs.pasteboard.clearContents()
		end
	end)
end

local MOD_SYMBOLS = { shift = "⇧", ctrl = "⌃", alt = "⌥", cmd = "⌘" }

local function keptKeyLabel()
	local label = ""
	for _, mod in ipairs(CONFIG.keptMods) do
		label = label .. (MOD_SYMBOLS[mod] or mod)
	end
	return label .. CONFIG.keptKey:upper()
end

local function copyText(text)
	hs.pasteboard.setContents(text)
	hs.alert.show("Kept dictation copied to the clipboard")
end

local function handle(msg)
	if msg.level then
		if hudState ~= "finishing" then
			pushLevel(msg.level)
		end
	elseif msg.text then
		if deliver == "copy" then
			copyText(msg.text)
		else
			pasteText(msg.text)
		end
	elseif msg.event == "ready" then
		if hudState == "connecting" then
			setState("listening")
		end
	elseif msg.event == "kept" then
		hs.alert.show("No text field: nothing sent.\n" .. keptKeyLabel() .. " transcribes it to the clipboard.", 4)
	elseif msg.event == "idle_timeout" then
		hs.alert.show("Dictation stopped (silence)")
		M.stop()
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

local function runHelper(args)
	buffer = ""
	task = hs.task.new(CONFIG.python, onExit, onStream, args)
	task:setEnvironment({
		HOME = HOME,
		PATH = "/usr/bin:/bin:/usr/sbin:/sbin",
		DICTATION_KEYTERMS = CONFIG.keyterms,
		DICTATION_IDLE_TIMEOUT = CONFIG.idleTimeout,
		DICTATION_LANGUAGE = CONFIG.language,
		DICTATION_KEPT_PATH = CONFIG.keptPath,
	})
	task:start()
end

function M.start()
	if task and task:isRunning() then
		return
	end
	deliver = "paste"
	runHelper({ CONFIG.script })
	setState("connecting")
	startTargetPoll()
end

-- Decide from a fresh check: paste into a text field, or keep the audio unsent.
function M.stop()
	if not (task and task:isRunning()) or hudState == "finishing" or deliver ~= "paste" then
		return
	end
	stopTargetPoll()
	local t = checkTarget()
	-- Signal the helper before touching the display, so stopping always works.
	if t.status == "field" then
		task:interrupt() -- SIGINT: transcribe everything and paste
	else
		task:terminate() -- SIGTERM: save the audio to keptPath, send nothing
	end
	refreshTarget(t)
	setState("finishing")
end

function M.transcribeKept()
	if task and task:isRunning() then
		return
	end
	if not hs.fs.attributes(CONFIG.keptPath) then
		hs.alert.show("No kept dictation")
		return
	end
	deliver = "copy"
	runHelper({ CONFIG.script, "--kept" })
	hs.alert.show("Transcribing kept dictation…")
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
M.keptHotkey = hs.hotkey.bind(CONFIG.keptMods, CONFIG.keptKey, M.transcribeKept)

return M
