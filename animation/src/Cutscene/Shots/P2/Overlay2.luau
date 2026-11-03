--!strict
-- Part 2 full-screen 2D layers (design px 1113 x 626, like Shots/Overlay):
--   p2star      white star flash on black (the Granite Blast fires)
--   p2swirl     blue energy swirl
--   p2crescent  white crescent of the blast front on black
--   fbLines     flashback line art: a huge eye and swirling lines
--   orangeFlare red-orange flame tongues from the top (Ryu senses danger)
--   eyeBlack    Ryu's eye alone in the dark, orange streaks
--   tibEye      "Thin Ice Breaker!": a giant white eye on black, bands, shards
--   timer17 / timer09 / timer00   the countdown display
--   crack1..3   cracks spreading from Yuta's palm on Ryu's chest
local Builder = require(script.Parent.Parent.Parent.Builder)
local Paint = require(script.Parent.Parent.Parent.Paint)
local Util = require(script.Parent.Parent.Parent.Util)

local Overlay2 = {}

local W, H = 1113, 626

-- full-screen strokes: coarse pills (a few per stroke), not face detail
local COARSE: Paint.StrokeOpts = { minStep = 12, maxStep = 90 }
local function stroke(c: Paint.Canvas, pts: { { number } }, w: { number } | number, col: Color3)
	c:stroke(pts, w, col, COARSE)
end

local function add(scene: Builder.Scene, c: Paint.Canvas, group: string, alpha: number?)
	for _, e in c.elems do
		e.group = group
		if alpha then
			e.alpha = 1 - (1 - e.alpha) * alpha
		end
		table.insert(scene.overlay, e)
	end
end

local function fade(a0: number, a1: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a0), NumberSequenceKeypoint.new(1, a1) })
end

-- seven-segment digit with its top-left corner at (x, y)
local SEGS: { [string]: string } = {
	["8"] = "abcdefg",
	["0"] = "abcdef",
	["1"] = "bc",
	["7"] = "abc",
	["9"] = "abcdfg",
}
local function digit(c: Paint.Canvas, ch: string, x: number, y: number, w: number, h: number, t: number, col: Color3)
	local segs = SEGS[ch] or ""
	local half = h / 2
	local function on(sg: string): boolean
		return string.find(segs, sg, 1, true) ~= nil
	end
	if on("a") then
		c:rect(x + w / 2, y + t / 2, w - t * 1.1, t, 0, col, 0, t / 2)
	end
	if on("g") then
		c:rect(x + w / 2, y + half, w - t * 1.1, t, 0, col, 0, t / 2)
	end
	if on("d") then
		c:rect(x + w / 2, y + h - t / 2, w - t * 1.1, t, 0, col, 0, t / 2)
	end
	if on("f") then
		c:rect(x + t / 2, y + half / 2, t, half - t * 1.1, 0, col, 0, t / 2)
	end
	if on("b") then
		c:rect(x + w - t / 2, y + half / 2, t, half - t * 1.1, 0, col, 0, t / 2)
	end
	if on("e") then
		c:rect(x + t / 2, y + half * 1.5, t, half - t * 1.1, 0, col, 0, t / 2)
	end
	if on("c") then
		c:rect(x + w - t / 2, y + half * 1.5, t, half - t * 1.1, 0, col, 0, t / 2)
	end
end

local function timer(scene: Builder.Scene, group: string, small: string, bg: Color3, fg: Color3, dim: Color3)
	local c = Paint.canvas(1, 0, 0)
	c:box(0, 0, W, H, bg)
	local y, h, w, t = 196, 236, 118, 26
	digit(c, "0", 120, y, w, h, t, fg)
	digit(c, "0", 292, y, w, h, t, fg)
	digit(c, "0", 434, y, w, h, t, fg)
	for _, x in { 262, 588 } do
		c:rect(x, y + h * 0.3, t * 0.9, t * 0.9, 0, fg, 0, 4)
		c:rect(x, y + h * 0.72, t * 0.9, t * 0.9, 0, fg, 0, 4)
	end
	-- smaller hundredths
	local sy, sh, sw, st = y + h * 0.36, h * 0.64, w * 0.72, t * 0.7
	for i = 1, 2 do
		digit(c, string.sub(small, i, i), 640 + (i - 1) * 110, sy, sw, sh, st, fg)
	end
	local _ = dim
	add(scene, c, group)
end

function Overlay2.build(scene: Builder.Scene)
	local white = Color3.new(1, 1, 1)
	local black = Color3.fromRGB(4, 5, 10)
	local r = Util.rng(2024)

	-- star flash: a 4-point star with thin rays, on black
	local c = Paint.canvas(1, 0, 0)
	c:box(0, 0, W, H, black)
	local cx, cy = 660, 300
	for i = 0, 15 do
		local a = i * 22.5 + Util.randRange(r, -4, 4)
		local len = if i % 4 == 0 then 260 else Util.randRange(r, 60, 140)
		local rad = math.rad(a)
		c:pill(cx + math.cos(rad) * len / 2, cy + math.sin(rad) * len / 2, len, if i % 4 == 0 then 7 else 3, a, white, 0.1)
	end
	c:circle(cx, cy, 34, Color3.fromRGB(220, 240, 255), 0.2)
	c:circle(cx, cy, 18, white)
	add(scene, c, "p2star")

	-- energy swirl: concentric arcs of cyan and white on deep blue
	c = Paint.canvas(1, 0, 0)
	c:grad(0, 0, W, H, {
		color = ColorSequence.new(Color3.fromRGB(40, 90, 200), Color3.fromRGB(10, 30, 110)),
		rotation = 90,
	})
	for i = 1, 7 do
		local rr = 40 + i * 52
		local pts = {}
		local a0 = Util.randRange(r, 0, 360)
		for k = 0, 10 do
			local a = math.rad(a0 + k * 26)
			table.insert(pts, { 560 + math.cos(a) * rr, 300 + math.sin(a) * rr * 0.8 })
		end
		local wsz = {}
		for k = 0, 10 do
			wsz[k + 1] = (if i % 2 == 0 then 22 else 12) * math.sin(k / 10 * math.pi) + 2
		end
		stroke(c, pts, wsz, if i % 2 == 0 then Color3.fromRGB(150, 235, 255) else white)
	end
	c:circle(560, 300, 60, white, 0.1)
	add(scene, c, "p2swirl")

	-- the blast front: a white crescent on black
	c = Paint.canvas(1, 0, 0)
	c:box(0, 0, W, H, black)
	local pts, wsz = {}, {}
	for k = 0, 12 do
		local a = math.rad(-70 + k * 11)
		table.insert(pts, { 470 + math.cos(a) * 170, 320 + math.sin(a) * 170 })
		wsz[k + 1] = 4 + 46 * math.sin(k / 12 * math.pi)
	end
	stroke(c, pts, wsz, white)
	add(scene, c, "p2crescent")

	-- flashback line art: a huge almond eye with a bright pupil, wrapped in
	-- swirling lines (white, semi-transparent; the 3D shot shows through)
	c = Paint.canvas(1, 0, 0)
	local ex, ey = 556, 330
	local upper, lower = {}, {}
	for k = 0, 16 do
		local u = k / 16
		local x = ex - 330 + u * 660
		local sx = math.sin(u * math.pi)
		table.insert(upper, { x, ey - 120 * sx - 10 * u })
		table.insert(lower, { x, ey + 70 * sx + 8 * u })
	end
	local lw = {}
	for k = 0, 16 do
		lw[k + 1] = 2 + 5 * math.sin(k / 16 * math.pi)
	end
	stroke(c, upper, lw, white)
	stroke(c, lower, lw, white)
	-- lashes / crease
	local crease = {}
	for k = 0, 12 do
		local u = k / 12
		table.insert(crease, { ex - 270 + u * 520, ey - 150 * math.sin(u * math.pi) - 20 })
	end
	stroke(c, crease, 2.5, white)
	-- iris rings and pupil
	for _, rr in { 70, 52 } do
		local ring = {}
		for k = 0, 24 do
			local a = k / 24 * math.pi * 2
			table.insert(ring, { ex + math.cos(a) * rr, ey - 20 + math.sin(a) * rr })
		end
		stroke(c, ring, if rr == 70 then 3 else 1.6, white)
	end
	c:circle(ex, ey - 20, 16, white)
	c:circle(ex, ey - 20, 34, white, 0.75)
	-- swirling wind lines
	for i = 1, 16 do
		local ln = {}
		local rr = Util.randRange(r, 260, 640)
		local a0 = Util.randRange(r, 0, math.pi * 2)
		local span = Util.randRange(r, 0.5, 1.3)
		local yk = Util.randRange(r, 0.45, 0.75)
		for k = 0, 8 do
			local a = a0 + span * k / 8
			table.insert(ln, { ex + math.cos(a) * rr, ey + math.sin(a) * rr * yk })
		end
		local ww = {}
		for k = 0, 8 do
			ww[k + 1] = 1 + (if i % 3 == 0 then 4 else 2.4) * math.sin(k / 8 * math.pi)
		end
		stroke(c, ln, ww, white)
	end
	add(scene, c, "fbLines", 0.8)

	-- red-orange flame tongues licking down from the top
	c = Paint.canvas(1, 0, 0)
	c:grad(0, 0, W, 300, { transparency = fade(0.25, 1), rotation = 90 }, Color3.fromRGB(255, 96, 40))
	for i = 1, 22 do
		local x = Util.randRange(r, -40, W + 40)
		local len = Util.randRange(r, 120, 320)
		local col = if i % 3 == 0 then Color3.fromRGB(255, 210, 90) else Color3.fromRGB(255, 110, 50)
		stroke(c, { { x, -10 }, { x + Util.randRange(r, -40, 40), len * 0.5 }, { x + Util.randRange(r, -60, 60), len } }, { 30, 18, 2 }, col)
	end
	add(scene, c, "orangeFlare", 0.85)

	-- Ryu's eye alone in the dark with orange streaks sweeping past
	c = Paint.canvas(1, 0, 0)
	c:box(0, 0, W, H, black)
	for i = 1, 9 do
		local y0 = Util.randRange(r, -80, 200)
		local col = if i % 2 == 0 then Color3.fromRGB(255, 150, 40) else Color3.fromRGB(255, 220, 110)
		stroke(c, { { -60, y0 }, { 160, y0 + 160 }, { 340, y0 + 420 } }, { 40, 60, 6 }, col)
	end
	local eye = {}
	local ew = {}
	for k = 0, 14 do
		local u = k / 14
		table.insert(eye, { 470 + u * 330, 330 - 4 * math.sin(u * math.pi) + 18 * u })
		ew[k + 1] = 8 + 84 * math.sin(u * math.pi) ^ 0.8
	end
	stroke(c, eye, ew, Color3.fromRGB(246, 242, 232))
	c:circle(630, 334, 10, black)
	stroke(c, { { 460, 290 }, { 640, 284 }, { 810, 310 } }, { 10, 16, 6 }, Color3.fromRGB(40, 36, 40))
	add(scene, c, "eyeBlack")

	-- "Thin Ice Breaker!": a giant white eye on black, grey bands, shards
	c = Paint.canvas(1, 0, 0)
	c:box(0, 0, W, H, black)
	for i = 1, 5 do
		local x0 = -200 + i * 230
		stroke(c, { { x0, -40 }, { x0 + 180, 300 }, { x0 + 300, H + 60 } }, { 60, 90, 60 }, Color3.fromRGB(70, 74, 86))
		stroke(c, { { x0 + 30, -40 }, { x0 + 200, 300 }, { x0 + 320, H + 60 } }, 2, Color3.fromRGB(210, 214, 226))
	end
	local te, tw = {}, {}
	for k = 0, 14 do
		local u = k / 14
		table.insert(te, { 360 + u * 520, 300 + 70 * u + 30 * math.sin(u * math.pi) })
		tw[k + 1] = 20 + 230 * math.sin(u * math.pi) ^ 0.7
	end
	stroke(c, te, tw, Color3.fromRGB(245, 247, 252))
	c:circle(560, 360, 14, black)
	for _ = 1, 26 do
		local x, y = Util.randRange(r, 0, W), Util.randRange(r, 0, H)
		c:poly({ { x, y }, { x + Util.randRange(r, 6, 18), y + Util.randRange(r, -4, 4) }, { x + Util.randRange(r, 0, 10), y + Util.randRange(r, 10, 26) } }, white, black)
	end
	add(scene, c, "tibEye")

	-- the countdown display
	timer(scene, "timer17", "17", black, Color3.fromRGB(226, 228, 232), Color3.fromRGB(22, 23, 28))
	timer(scene, "timer09", "09", black, Color3.fromRGB(226, 228, 232), Color3.fromRGB(22, 23, 28))
	timer(scene, "timer00", "00", Color3.fromRGB(232, 16, 20), Color3.fromRGB(14, 4, 6), Color3.fromRGB(205, 12, 16))

	-- cracks spreading from the palm (centre of the frame), three stages
	for stage = 1, 3 do
		c = Paint.canvas(1, 0, 0)
		local rr = Util.rng(77)
		local px, py = 560, 330
		for i = 1, 6 + stage * 4 do
			local a = Util.randRange(rr, 0, math.pi * 2)
			local len = (60 + stage * 90) * Util.randRange(rr, 0.5, 1.1)
			local pts2 = { { px, py } }
			local x, y = px, py
			for _ = 1, 4 do
				a += Util.randRange(rr, -0.5, 0.5)
				x += math.cos(a) * len / 4
				y += math.sin(a) * len / 4
				table.insert(pts2, { x, y })
			end
			stroke(c, pts2, { 5, 4, 3, 2, 1 }, Color3.fromRGB(235, 248, 255))
		end
		-- a ring of shards around the palm
		for i = 1, stage * 3 do
			local a = i / (stage * 3) * math.pi * 2
			local d = 60 + stage * 30
			local x, y = px + math.cos(a) * d, py + math.sin(a) * d * 0.8
			stroke(c, { { x, y }, { x + math.cos(a + 1.4) * 40, y + math.sin(a + 1.4) * 40 } }, { 3, 1 }, Color3.fromRGB(210, 236, 255))
		end
		add(scene, c, "crack" .. stage, 0.9)
	end
end

return Overlay2
