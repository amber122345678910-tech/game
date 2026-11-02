--!nocheck
-- loading_timeline: what the PLAY / PRACTICE loading screen does over time, measured on the real code. Drives
-- UIController (UIController._Harness, the same fakes as tools/lune/tests/loading_screen.spec.luau) with the real
-- overlay (src/client/UI/Overlays/Loading) on a 60 fps fake frame loop, records how black the screen is, when the
-- head shows, every SetMusicOverride (key + fade) and the events (black, request, Intro, refusal, light), and writes
-- an HTML page with one SVG lane per flow (+ the previous rule's reveal as a dashed marker).
--
-- Usage (project root):
--   lune run tools/preview/gui/loading_timeline.luau --out /tmp/loading_timeline.html
--   node -e "const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await
--     b.newPage({viewport:{width:1400,height:900}});await p.goto('file:///tmp/loading_timeline.html');
--     await p.screenshot({path:'previews/ui/loading_timeline.png',fullPage:true});await b.close()})()"
local fs = require("@lune/fs")
local process = require("@lune/process")
local Loader = require("../../lune/loader")

local out = "loading_timeline.html"
for i, a in process.args do
	if a == "--out" and process.args[i + 1] then
		out = process.args[i + 1]
	end
end

local DT = 1 / 60
local roblox = Loader.roblox

-- one fresh UIController + overlay with fakes (see the spec's controllerRig)
local function newRig()
	Loader.reset()
	Loader.isServer = false
	Loader.quietWarnings = true
	local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
	Strings.SetLanguage("en")
	local Loading = Loader.requirePath("src/client/UI/Overlays/Loading")
	local UI = Loader.requirePath("src/client/Controllers/UIController")
	local rig = { now = 0, Loading = Loading, UI = UI, music = {}, requests = {} }
	local driver = { delays = {} }
	driver.Connect = function(step)
		driver.step = step
		return function()
			driver.step = nil
		end
	end
	driver.Viewport = function()
		return roblox.Vector2.new(860, 400)
	end
	driver.Delay = function() end
	rig.driver = driver
	local sound = {
		Play = function()
			return { Playing = false }
		end,
		Stop = function() end,
		Duck = function() end,
		SetMusicOverride = function(key, fade)
			table.insert(rig.music, { t = rig.now - (rig.origin or 0), key = key, fade = fade })
		end,
	}
	local handlers = {}
	local state = { phase = "Waiting", role = "Lobby" }
	state.Notify = {
		Connect = function(_, fn)
			local c = {}
			handlers[c] = fn
			function c:Disconnect()
				handlers[c] = nil
			end
			return c
		end,
		Fire = function(_, ...)
			for _, fn in table.clone(handlers) do
				fn(...)
			end
		end,
	}
	state.Phase = function()
		return state.phase
	end
	state.Role = function()
		return state.role
	end
	state.Request = function(action)
		table.insert(rig.requests, { action = action, t = rig.now - (rig.origin or 0) })
	end
	state.LocalCharacter = function()
		return state.character
	end
	rig.state = state
	local screens = {}
	local root = {
		IsInitialized = function()
			return true
		end,
		Push = function(module)
			local h = { Root = {}, Module = module }
			table.insert(screens, h)
			return h
		end,
		Pop = function()
			table.remove(screens)
			return true
		end,
		Clear = function()
			table.clear(screens)
		end,
		Top = function()
			return screens[#screens]
		end,
		Toast = function() end,
	}
	UI._Harness({
		UIRoot = root,
		Sound = sound,
		State = state,
		ShowOpts = { Driver = driver, Parent = roblox.Instance.new("Folder") },
		Clock = function()
			return rig.now
		end,
	})
	function rig.spawn()
		local model = roblox.Instance.new("Model")
		local part = roblox.Instance.new("Part")
		part.Name = "HumanoidRootPart"
		part.Position = roblox.Vector3.new(0, 3, 0)
		part.Parent = model
		model.PrimaryPart = part
		state.character = model
	end
	-- runs the overlay the press just started, recording a lane; onStep(t) runs before every frame
	function rig.record(lane, press, onStep)
		rig.origin = rig.now
		rig.music = {}
		rig.requests = {}
		lane.samples, lane.events = {}, {}
		local function event(label)
			table.insert(lane.events, { t = rig.now - rig.origin, label = label })
		end
		press()
		local handle = Loading.Active()
		local covered, open = false, UI.IsOpen()
		table.insert(lane.samples, { t = 0, black = 0, content = 0 })
		while handle and not handle.Done and rig.now - rig.origin < 12 do
			rig.now += DT
			if onStep then
				onStep(rig.now - rig.origin, event)
			end
			if driver.step then
				driver.step(DT)
			end
			local seq = handle.Sequence
			local plain = handle.View.Plain
			table.insert(lane.samples, {
				t = rig.now - rig.origin,
				black = if handle.Done then 0 else seq.Backdrop,
				content = if handle.Done or plain then 0 else seq.Content,
			})
			local coveredNow = handle.Covered and not covered
			local closedNow = open and not UI.IsOpen()
			covered = covered or coveredNow
			open = open and not closedNow
			if coveredNow and closedNow then
				event("black + menus closed")
			elseif coveredNow then
				event("black")
			elseif closedNow then
				event("menus closed")
			end
		end
		event("lit")
		lane.music = rig.music
		lane.requests = rig.requests
		rig.music, rig.requests = {}, {} -- later music changes (the next lane's setup) are not this lane's
		lane.length = rig.now - rig.origin
	end
	return rig
end

local lanes = {}

-- 1 + 2: the session's first PLAY, then PLAY again from a Title reopened in the lobby
do
	local rig = newRig()
	rig.spawn()
	rig.UI.Open("Title")
	local first = { title = "First PLAY of the session", sub = "owner's flow, unchanged", before = 4.55 }
	rig.record(first, function()
		rig.UI.Play()
	end)
	first.autoKey = "Lobby"
	table.insert(lanes, first)
	rig.UI.Open("Title")
	local later = { title = "PLAY from a reopened Title", sub = "phones: the only way back", before = 4.55 }
	rig.record(later, function()
		rig.UI.Play()
	end)
	later.autoKey = "Lobby"
	table.insert(lanes, later)
end

-- 3: PRACTICE, the round's Intro arrives 1.5 s after the press (map built on the server)
local INTRO_AT = 1.5
do
	local RoundRules = Loader.require("ReplicatedStorage.Shared.Round.RoundRules")
	local introLength = RoundRules.PhaseDuration("Intro", true)
	local rig = newRig()
	rig.spawn()
	rig.UI.Open("Title")
	-- the previous rule: cue at max(MinVisible - lead, ready + settle), reveal a whole lead later
	local oldDone = math.max(4 - 2, INTRO_AT + 0.3) + 2 + 0.55
	local lane = {
		title = "PRACTICE",
		sub = ("the round's Intro starts at %.1f s"):format(INTRO_AT),
		before = oldDone,
		intro = { INTRO_AT, INTRO_AT + introLength },
	}
	rig.record(lane, function()
		rig.UI.Practice("Human")
	end, function(t, event)
		if t >= INTRO_AT and rig.state.phase == "Waiting" then
			rig.state.phase = "Intro"
			rig.state.role = "Human"
			event("Intro")
		end
	end)
	lane.autoKey = "Round theme"
	table.insert(lanes, lane)
end

-- 4: PRACTICE refused (a round is about to start: "busy") 0.5 s after the press
do
	local rig = newRig()
	rig.spawn()
	rig.UI.Open("Title")
	local lane = { title = "PRACTICE refused", sub = "server answers busy at 0.5 s", before = 4.55 }
	local fired = false
	rig.record(lane, function()
		rig.UI.Practice("Human")
	end, function(t, event)
		if not fired and t >= 0.5 then
			fired = true
			rig.state.Notify:Fire("round.practice.busy", nil, "Warning")
			event("refused")
		end
	end)
	lane.autoKey = "Lobby"
	table.insert(lanes, lane)
end

------------------------------------------------------------------------------------------------ SVG
local W, LEFT, RIGHT, SPAN = 1400, 300, 1360, 8
local LANE_H, TOP = 168, 96
local function x(t)
	return LEFT + (RIGHT - LEFT) * math.clamp(t, 0, SPAN) / SPAN
end
local COLORS = {
	Menu = "#5b8def",
	Silence = "#c9ccd3",
	Lobby = "#3fae6a",
	["Round theme"] = "#e0663a",
}
local parts = {}
local function add(s, ...)
	table.insert(parts, if select("#", ...) > 0 then string.format(s, ...) else s)
end
local H = TOP + LANE_H * #lanes + 84
add('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" font-family="Segoe UI, Arial, sans-serif">', W, H)
add('<rect width="100%%" height="100%%" fill="#f6f6f3"/>')
add('<text x="40" y="44" font-size="26" font-weight="700" fill="#1b1d22">Loading screen over time (measured, 60 fps)</text>')
add(
	'<text x="40" y="72" font-size="15" fill="#555a63">black area = how dark the screen is; gold line = the spinning '
		.. "head + LOADING; bar = music override (crossfades shaded); dashed red = when the light came back before "
		.. "this fix</text>"
)
for s = 0, SPAN do
	add('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="#e1e2de" stroke-width="1"/>', x(s), TOP - 8, x(s), H - 58)
	add('<text x="%.1f" y="%d" font-size="13" fill="#7a7f88" text-anchor="middle">%d s</text>', x(s), H - 40, s)
end
for i, lane in lanes do
	local y0 = TOP + (i - 1) * LANE_H
	local bandTop, bandH = y0 + 34, 64
	local musicY = bandTop + bandH + 14
	add('<text x="40" y="%d" font-size="19" font-weight="700" fill="#1b1d22">%s</text>', y0 + 60, lane.title)
	add('<text x="40" y="%d" font-size="14" fill="#6a6f78">%s</text>', y0 + 82, lane.sub)
	add(
		'<text x="40" y="%d" font-size="14" fill="#1b1d22">light back at <tspan font-weight="700">%.2f s</tspan></text>',
		y0 + 106,
		lane.length
	)
	if lane.before and math.abs(lane.before - lane.length) > 0.05 then
		add('<text x="40" y="%d" font-size="14" fill="#c0392b">before: %.2f s</text>', y0 + 126, lane.before)
	end
	add('<rect x="%d" y="%d" width="%d" height="%d" fill="#ffffff" stroke="#d5d6d2"/>', LEFT, bandTop, RIGHT - LEFT, bandH)
	if lane.intro then
		local a, b = x(lane.intro[1]), x(lane.intro[2])
		add('<rect x="%.1f" y="%d" width="%.1f" height="%d" fill="#ffb347" opacity="0.28"/>', a, bandTop, b - a, bandH)
		add(
			'<text x="%.1f" y="%d" font-size="13" fill="#a35a00">practice Intro: VS splash, 3-2-1 (%.0f s)</text>',
			math.max(a, x(lane.length)) + 6,
			bandTop + bandH - 10,
			lane.intro[2] - lane.intro[1]
		)
	end
	-- black level (area) and the head (line)
	local poly = { ("%.1f,%d"):format(x(0), bandTop + bandH) }
	local head = {}
	for _, s in lane.samples do
		table.insert(poly, ("%.1f,%.1f"):format(x(s.t), bandTop + bandH - s.black * bandH))
		table.insert(head, ("%.1f,%.1f"):format(x(s.t), bandTop + bandH - s.content * (bandH - 8) - 4))
	end
	table.insert(poly, ("%.1f,%d"):format(x(lane.length), bandTop + bandH))
	add('<polygon points="%s" fill="#111317" opacity="0.92"/>', table.concat(poly, " "))
	add('<polyline points="%s" fill="none" stroke="#f3c242" stroke-width="2.5"/>', table.concat(head, " "))
	-- events
	local placed = {} -- label boxes {row, x0, x1}: a label goes to the lowest row where it overlaps nothing
	local function marker(t, label, color)
		local px = x(t)
		local x0, x1 = px, px + 8 + #label * 6.8
		local row = 0
		local clash = true
		while clash do
			clash = false
			for _, p in placed do
				if p[1] == row and x0 < p[3] and p[2] < x1 then
					clash = true
					row += 1
					break
				end
			end
		end
		table.insert(placed, { row, x0, x1 })
		add('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="%s" stroke-width="1.5"/>', px, bandTop - 4, px, bandTop + bandH, color)
		add('<text x="%.1f" y="%d" font-size="12.5" fill="%s">%s</text>', px + 3, bandTop - 8 - row * 14, color, label)
	end
	for _, e in lane.events do
		marker(e.t, ("%s %.2f"):format(e.label, e.t), if e.label == "refused" then "#c0392b" else "#2d3440")
	end
	for _, r in lane.requests do
		marker(r.t, ("request %.2f"):format(r.t), "#6b4bd6")
	end
	if lane.before and math.abs(lane.before - lane.length) > 0.05 then
		local bx = x(lane.before)
		add(
			'<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="#c0392b" stroke-width="2" stroke-dasharray="6,4"/>',
			bx,
			bandTop - 4,
			bx,
			musicY + 18
		)
		add('<text x="%.1f" y="%d" font-size="12.5" fill="#c0392b">before</text>', bx + 4, bandTop + 14)
	end
	-- music: Menu until the first change, then each override (nil = automatic: the lobby / round track)
	local current = "Menu"
	local from = 0
	local segments = {}
	for _, m in lane.music do
		local key = m.key or lane.autoKey
		local last = segments[#segments]
		if last and last.to > m.t then
			last.to = m.t -- a crossfade cut short by the next change
		end
		table.insert(segments, { from = from, to = m.t, key = current })
		table.insert(segments, { from = m.t, to = m.t + (m.fade or 1.6), key = key, fadeFrom = current })
		current = key
		from = m.t + (m.fade or 1.6)
	end
	table.insert(segments, { from = from, to = SPAN, key = current })
	for k, seg in segments do
		if seg.to > seg.from then
			local a, b = x(seg.from), x(seg.to)
			if seg.fadeFrom then
				local id = ("g%d_%d"):format(i, k)
				add(
					'<defs><linearGradient id="%s"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>',
					id,
					COLORS[seg.fadeFrom] or "#999",
					COLORS[seg.key] or "#999"
				)
				add('<rect x="%.1f" y="%d" width="%.1f" height="18" fill="url(#%s)"/>', a, musicY, b - a, id)
			else
				add('<rect x="%.1f" y="%d" width="%.1f" height="18" fill="%s"/>', a, musicY, b - a, COLORS[seg.key] or "#999")
				if b - a > 60 then
					add('<text x="%.1f" y="%d" font-size="12.5" fill="#ffffff" font-weight="600">%s</text>', a + 6, musicY + 13, seg.key)
				end
			end
		end
	end
end
-- legend
do
	local lx = LEFT
	for _, key in { "Menu", "Silence", "Lobby", "Round theme" } do
		add('<rect x="%d" y="%d" width="16" height="12" fill="%s"/>', lx, H - 22, COLORS[key])
		add('<text x="%d" y="%d" font-size="13" fill="#555a63">%s</text>', lx + 22, H - 12, key)
		lx += 40 + #key * 8
	end
	add('<text x="%d" y="%d" font-size="13" fill="#555a63">music override: Title "Menu" -> "Silence" into the black -> automatic (lobby / round track)</text>', lx + 10, H - 12)
end
add("</svg>")
local html = '<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;background:#f6f6f3}</style></head><body>'
	.. table.concat(parts, "\n")
	.. "</body></html>"
fs.writeFile(out, html)
for _, lane in lanes do
	print(("%-28s light back at %.2f s (before %.2f s), music: %s"):format(
		lane.title,
		lane.length,
		lane.before or lane.length,
		(function()
			local s = {}
			for _, m in lane.music do
				table.insert(s, ("%s@%.2f"):format(m.key or "auto", m.t))
			end
			return table.concat(s, " ")
		end)()
	))
end
print("wrote " .. out)
