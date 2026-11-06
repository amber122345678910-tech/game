--!strict
-- Art for Ryu's flashbacks in part 2 (see docs/part2_flashback.md).
--  2D overlays (design px 1113 x 626):
--   fbEye1..3     the huge line-art eye over the first flashback, traced off the
--                 reference; three drawings swapped ~10 times a second so the
--                 lines boil like hand-drawn ones
--   fbArcs1..3    the same eye much closer, over the second flashback
--   fbSmear       a whip smear between two moments of one shot
--   fbSmearDark   a dark smear crossing the frame
--   fbGlitch      horizontal streaks (the frame before the arm is torn off)
--   fbCrackA1..3  cracks spreading over the dark frame (34.0) in three steps
--   fbCrackB1..3  cracks spreading through the sky round Yuta (34.3)
--   tibEye2       "Thin Ice Breaker!": Yuta's eye behind shattered glass
--  painted backdrops: unlit plates kept behind the action, facing the camera
--   (teal sky, lavender with light streaks, cloud sky, dusk, navy hatching, night)
--  a key light riding next to the camera, so the characters read pale
--  the set: a dark roof with road markings, an apartment block and an elevated
--  road against the evening sky
local Builder = require(script.Parent.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Parent.Timeline)
local Paint = require(script.Parent.Parent.Parent.Paint)
local Util = require(script.Parent.Parent.Parent.Util)
local FlashData = require(script.Parent.FlashData)
local FX = require(script.Parent.Parent.Parent.FX)

local FlashArt = {}

local V = Vector3.new
local C = CFrame.new
local WHITE = Color3.new(1, 1, 1)
local GLOW = Color3.fromRGB(196, 222, 255)
local W, H = 1113, 626

local COARSE: Paint.StrokeOpts = { minStep = 8, maxStep = 60 }

-- Yuta's arm stretched out like rubber (31.3-32.0): a long flat band, pale
-- on the side the light falls on and dark brown in its own shadow, and a big
-- hand curling into a hook at the end
export type Arm = { light: { Builder.PartSpec }, dark: { Builder.PartSpec }, hand: { Builder.PartSpec } }

-- Rika's giant hand for the catch (35.6-36.7): forearm, palm, jointed
-- fingers that spread open or close into a fist, black claws
export type Claw = { parts: { Builder.PartSpec } }
-- Uro's arm torn off at the shoulder (42.9-44.7): bare arm, dark bracelet,
-- red nails, a bloody stump; and thin trails of blood
export type Severed = { parts: { Builder.PartSpec }, trail: { Builder.PartSpec } }

export type H = {
	plates: { [string]: Builder.PartSpec },
	key: Builder.PartSpec,
	rim: Builder.PartSpec,
	arm: Arm,
	claw: Claw,
	sev: Severed,
	shards: FX.Burst,
	halo: { Builder.PartSpec },
	smears: { Builder.PartSpec },
}

local function add(scene: Builder.Scene, c: Paint.Canvas, group: string)
	for _, e in c.elems do
		e.group = group
		table.insert(scene.overlay, e)
	end
end

-- give every element drawn since `n0` the transparency `a`
local function fadeFrom(c: Paint.Canvas, n0: number, a: number)
	for i = n0 + 1, #c.elems do
		c.elems[i].alpha = a
	end
end

-- a traced stroke (flat x, y, w list): points moved by up to `j` px, widths
-- scaled by `ws`; `glow` adds a soft wide halo under the line
local function traced(c: Paint.Canvas, flat: { number }, r: Util.Rng, j: number, ws: number, glow: boolean, col: Color3?)
	local pts: { { number } } = {}
	local wsz: { number } = {}
	for i = 1, #flat - 2, 3 do
		table.insert(pts, { flat[i] + Util.randRange(r, -j, j), flat[i + 1] + Util.randRange(r, -j, j) })
		table.insert(wsz, math.min(4.6, flat[i + 2] * 0.62) * ws * Util.randRange(r, 0.88, 1.12))
	end
	if #pts < 2 then
		return
	end
	if glow then
		local gw: { number } = {}
		for i, w in wsz do
			gw[i] = w * 2.2 + 4
		end
		local n0 = #c.elems
		c:stroke(pts, gw, GLOW, COARSE)
		fadeFrom(c, n0, 0.84)
	end
	c:stroke(pts, wsz, col or WHITE, COARSE)
end

-- a closed ring of a stroke
local function ring(c: Paint.Canvas, x: number, y: number, rr: number, w: number, col: Color3)
	local pts: { { number } } = {}
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2
		table.insert(pts, { x + math.cos(a) * rr, y + math.sin(a) * rr })
	end
	c:stroke(pts, w, col, { minStep = 4, maxStep = 30, closed = true })
end

-- the bright pupil of the line-art eye: a glowing disc, a ring, a swirl inside
local function pupil(c: Paint.Canvas, x: number, y: number, s: number, r: Util.Rng)
	local n0 = #c.elems
	c:blob(x, y, 110 * s, 110 * s, GLOW, 0.55, 8)
	fadeFrom(c, n0, 0.93)
	n0 = #c.elems
	c:circle(x, y, 40 * s, GLOW)
	fadeFrom(c, n0, 0.7)
	c:circle(x, y, 30 * s, WHITE, 0.04)
	local sw: { { number } } = {}
	local a0 = Util.randRange(r, 180, 230)
	for k = 0, 10 do
		local a = math.rad(a0 + k * 31)
		local rr = (5 + k * 1.15) * s
		table.insert(sw, { x + math.cos(a) * rr, y + math.sin(a) * rr })
	end
	c:stroke(sw, 3.4 * s, Color3.fromRGB(128, 142, 184), { minStep = 3, maxStep = 14 })
	ring(c, x, y, 35 * s, 2.6 * s, WHITE)
end

local function eyeOverlay(scene: Builder.Scene)
	-- the lower lid the lashes hang from (x -> y), read off the reference
	local lid = { { 318, 383 }, { 338, 402 }, { 360, 420 }, { 383, 435 }, { 407, 446 }, { 431, 452 }, { 456, 453 }, { 480, 451 }, { 505, 449 } }
	for v = 1, 3 do
		local c = Paint.canvas(1, 0, 0)
		local r = Util.rng(7300 + v * 131)
		Util.rand(r)
		local j = if v == 1 then 0.3 else 0.9
		for i, flat in FlashData.eye do
			traced(c, flat, r, j, 1, i <= 30)
		end
		for _, p in lid do
			local len = Util.randRange(r, 13, 20)
			local x = p[1] + Util.randRange(r, -1.5, 1.5)
			c:stroke({ { x, p[2] + 3 }, { x - len * 0.18, p[2] + 3 + len } }, { 2.6, 1.2 }, WHITE, { minStep = 3, maxStep = 20 })
		end
		pupil(c, 513, 312, 1, r)
		add(scene, c, "fbEye" .. v)
	end
end

local function arcsOverlay(scene: Builder.Scene)
	for v = 1, 3 do
		local c = Paint.canvas(1, 0, 0)
		local r = Util.rng(7700 + v * 173)
		Util.rand(r)
		local j = if v == 1 then 0.3 else 0.9
		for i, flat in FlashData.arcs do
			traced(c, flat, r, j, 1, i <= 24)
		end
		local n0 = #c.elems
		c:circle(552, 308, 22, GLOW)
		fadeFrom(c, n0, 0.8)
		ring(c, 552, 308, 11, 2.4, WHITE)
		c:circle(552, 308, 5, WHITE, 0.2)
		add(scene, c, "fbArcs" .. v)
	end
end

local function smearOverlay(scene: Builder.Scene)
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(7911)
	Util.rand(r)
	c:box(0, 0, W, H, Color3.fromRGB(226, 236, 248), 0.5)
	for _ = 1, 28 do
		local x, y = Util.randRange(r, -100, W + 100), Util.randRange(r, -60, H + 60)
		local len = Util.randRange(r, 260, 900)
		local th = Util.randRange(r, 8, 70)
		local col = Util.mix(WHITE, Color3.fromRGB(150, 190, 230), Util.rand(r))
		c:pill(x, y, len, th, -18 + Util.randRange(r, -6, 6), col, Util.randRange(r, 0.3, 0.75))
	end
	add(scene, c, "fbSmear")
end

-- a dark smear crossing the frame (something big rushing past the lens):
-- a soft brown-grey wash, darker through the middle
local function darkSmearOverlay(scene: Builder.Scene)
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(7921)
	Util.rand(r)
	c:box(0, 0, W, H, Color3.fromRGB(92, 80, 80), 0.55)
	for _ = 1, 10 do
		local x, y = Util.randRange(r, 0, W), Util.randRange(r, 0, H * 0.7)
		local col = Util.mix(Color3.fromRGB(64, 54, 56), Color3.fromRGB(150, 132, 126), Util.rand(r))
		c:blob(x, y, Util.randRange(r, 400, 900), Util.randRange(r, 160, 320), col, Util.randRange(r, 0.35, 0.6), 4)
	end
	add(scene, c, "fbSmearDark")
end

local function glitchOverlay(scene: Builder.Scene)
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(7933)
	Util.rand(r)
	c:box(0, 0, W, H, Color3.fromRGB(34, 36, 64), 0.3)
	for _ = 1, 46 do
		local y = Util.randRange(r, 0, H)
		local hh = Util.randRange(r, 2, 16)
		local col = Util.mix(Color3.fromRGB(28, 30, 58), Color3.fromRGB(170, 168, 222), Util.rand(r))
		c:rect(W / 2 + Util.randRange(r, -80, 80), y, W * Util.randRange(r, 0.8, 1.3), hh, 0, col, Util.randRange(r, 0.2, 0.55))
	end
	for _ = 1, 14 do
		local y = Util.randRange(r, 0, H * 0.4)
		c:rect(Util.randRange(r, 200, 900), y, Util.randRange(r, 200, 700), Util.randRange(r, 1.5, 5), 0, WHITE, Util.randRange(r, 0.1, 0.4))
	end
	add(scene, c, "fbGlitch")
end

-- jagged cracks from (cx, cy), grown in three steps (groups name..1..3);
-- `reach` scales their length, white shards sit along them
local function cracks(scene: Builder.Scene, name: string, cx: number, cy: number, reach: number, seed: number)
	local canv = { Paint.canvas(1, 0, 0), Paint.canvas(1, 0, 0), Paint.canvas(1, 0, 0) }
	local r = Util.rng(seed)
	Util.rand(r)
	local function crack(x0: number, y0: number, a0: number, n: number, w0: number, depth: number)
		local pts: { { number } } = { { x0, y0 } }
		local x, y, a = x0, y0, a0
		for _ = 1, n do
			a += Util.randRange(r, -0.45, 0.45)
			local step = Util.randRange(r, 28, 64) * reach
			x += math.cos(a) * step
			y += math.sin(a) * step
			table.insert(pts, { x, y })
		end
		-- split into three growth steps by distance from the centre
		for k = 1, #pts - 1 do
			local p, q = pts[k], pts[k + 1]
			local d = math.sqrt((q[1] - cx) ^ 2 + (q[2] - cy) ^ 2) / reach
			local g = if d < 160 then 1 elseif d < 330 then 2 else 3
			local w = w0 * (1 - (k - 1) / (#pts) * 0.6)
			canv[g]:stroke({ p, q }, { w, w * 0.85 }, WHITE, { minStep = 3, maxStep = 40 })
			if Util.rand(r) < 0.45 then
				local sx, sy = (p[1] + q[1]) / 2 + Util.randRange(r, -16, 16), (p[2] + q[2]) / 2 + Util.randRange(r, -16, 16)
				canv[g]:rect(sx, sy, Util.randRange(r, 5, 16), Util.randRange(r, 2, 6), Util.randRange(r, 0, 180), WHITE, Util.randRange(r, 0, 0.3))
			end
			if depth > 0 and Util.rand(r) < 0.18 then
				local _ = crack(q[1], q[2], a + Util.randRange(r, -1.1, 1.1), math.max(2, n - k - 1), w * 0.7, depth - 1)
			end
		end
		return pts
	end
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + Util.randRange(r, -0.3, 0.3)
		crack(cx, cy, a, math.floor(Util.randRange(r, 5, 8)), Util.randRange(r, 3.4, 5.2), 1)
	end
	for g = 1, 3 do
		add(scene, canv[g], name .. g)
	end
end

-- "Thin Ice Breaker!" (reference 44.7-45.8, one held drawing): Yuta's eye,
-- huge, white, a small dark pupil, seen through shattered black glass with
-- white panes, white cracks and lashes split into red and cyan
local function tibOverlay(scene: Builder.Scene)
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(7955)
	Util.rand(r)
	local black = Color3.fromRGB(9, 9, 12)
	c:box(-4, -4, W + 4, H + 4, black)
	-- far-left translucent pane and the grey bands crossing the frame
	c:rect(40, 313, 120, 700, 4, Color3.fromRGB(46, 46, 52), 0.2)
	c:rect(385, 118, 390, 78, -17, Color3.fromRGB(128, 126, 138), 0)
	c:rect(330, 205, 220, 34, -16, Color3.fromRGB(70, 70, 78), 0)
	c:rect(930, 170, 520, 110, 33, Color3.fromRGB(34, 34, 40), 0)
	c:rect(1010, 300, 360, 60, 33, Color3.fromRGB(56, 56, 64), 0)
	-- the bright pane at the top
	c:poly({ { 532, -4 }, { 772, -4 }, { 748, 150 }, { 700, 222 }, { 600, 250 }, { 476, 286 } }, Color3.fromRGB(222, 222, 230), black)
	c:poly({ { 600, -4 }, { 772, -4 }, { 748, 150 }, { 690, 140 } }, Color3.fromRGB(240, 240, 246), black)
	-- the bright pane bottom right
	c:poly({ { 902, 430 }, { 1117, 330 }, { 1117, 630 }, { 780, 630 } }, Color3.fromRGB(232, 232, 238), black)
	-- the eye: a big white almond, the upper lid heavy and dark
	local eyePts: { { number } } = {}
	local eyeW: { number } = {}
	for k = 0, 14 do
		local u = k / 14
		local x = 412 + u * 388
		table.insert(eyePts, { x, 342 + 40 * u - 8 * math.sin(u * math.pi) })
		table.insert(eyeW, 4 + 214 * math.sin(u * math.pi) ^ 0.75)
	end
	c:stroke(eyePts, eyeW, Color3.fromRGB(250, 250, 252), { minStep = 6, maxStep = 60 })
	c:stroke({ { 420, 352 }, { 470, 350 }, { 520, 360 } }, { 12, 40, 12 }, Color3.fromRGB(206, 208, 216), { minStep = 6, maxStep = 60 })
	-- pupil: small, dark, a light rim and a glint
	c:circle(548, 380, 17, Color3.fromRGB(170, 176, 196))
	c:circle(548, 380, 13, Color3.fromRGB(38, 40, 52))
	c:circle(544, 375, 4, WHITE)
	-- a dark shard across the white of the eye
	c:rect(510, 372, 16, 92, 12, Color3.fromRGB(52, 54, 64), 0)
	c:rect(498, 452, 12, 26, 30, Color3.fromRGB(84, 86, 96), 0)
	-- lashes in chromatic split: red, cyan, white
	local function lash(x: number, y: number, len: number, a: number)
		local dx, dy = math.cos(math.rad(a)) * len, math.sin(math.rad(a)) * len
		c:stroke({ { x - 2, y }, { x - 2 + dx, y + dy } }, { 2.2, 0.8 }, Color3.fromRGB(230, 70, 80), { minStep = 3, maxStep = 30 })
		c:stroke({ { x + 2, y }, { x + 2 + dx, y + dy } }, { 2.2, 0.8 }, Color3.fromRGB(70, 220, 230), { minStep = 3, maxStep = 30 })
		c:stroke({ { x, y }, { x + dx, y + dy } }, { 1.6, 0.6 }, Color3.fromRGB(240, 240, 246), { minStep = 3, maxStep = 30 })
	end
	for i = 1, 24 do
		local x = 430 + i * 15 + Util.randRange(r, -5, 5)
		local y = 486 + math.sin(i / 24 * math.pi) * 18 + Util.randRange(r, 0, 46)
		lash(x, y, Util.randRange(r, 14, 30), 120 + Util.randRange(r, -14, 14))
	end
	for i = 1, 9 do
		lash(372 + i * 12, 262 + i * 2 + Util.randRange(r, -6, 6), Util.randRange(r, 12, 22), 200 + Util.randRange(r, -10, 10))
	end
	-- cracks traced off the reference, with a faint red / cyan fringe
	for _, flat in FlashData.tib do
		local q: { number } = table.clone(flat)
		for i = 1, #q - 2, 3 do
			q[i] -= 1.5
		end
		traced(c, q, r, 0, 1, false, Color3.fromRGB(214, 90, 100))
		for i = 1, #q - 2, 3 do
			q[i] += 3
		end
		traced(c, q, r, 0, 1, false, Color3.fromRGB(90, 214, 224))
		traced(c, flat, r, 0, 0.8, false, WHITE)
	end
	-- small white shards scattered over the dark left
	for _ = 1, 30 do
		local x, y = Util.randRange(r, 30, 420), Util.randRange(r, 40, 580)
		c:rect(x, y, Util.randRange(r, 4, 14), Util.randRange(r, 6, 22), Util.randRange(r, 0, 180), Color3.fromRGB(236, 236, 244), Util.randRange(r, 0, 0.35))
	end
	add(scene, c, "tibEye2")
end

------------------------------------------------------------------------------
-- painted backdrops (canvas 1600 x 900)
------------------------------------------------------------------------------
local PW, PH = 1600, 900

-- the plate itself is invisible (only its painting shows): an opaque plate
-- right under the painting would fight it for depth far from the camera
local function plate(scene: Builder.Scene, name: string, c: Paint.Canvas): Builder.PartSpec
	Builder.model(scene, "P2FbSky", false)
	return Builder.part(scene, "P2FbSky", V(16, 9, 0.05), C(), WHITE, {
		fx = true,
		castShadow = false,
		transparency = 1,
		name = name,
		gui = { face = "Front", canvas = Vector2.new(PW, PH), lightInfluence = 0, elems = c.elems },
	})
end

-- a soft round glow: many layers, each fading out towards its edges, half
-- of them across and half along, so no ring shows
local FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1),
})
local function soft(c: Paint.Canvas, x: number, y: number, w: number, hh: number, col: Color3, alpha: number, layers: number)
	local per = 1 - (1 - alpha) ^ (1 / layers)
	for i = 0, layers - 1 do
		local f = 1 - i / layers * 0.7
		local e = c:rect(x, y, w * f, hh * f, 0, col, 1 - per, -1)
		e.grad = { transparency = FADE, rotation = if i % 2 == 0 then 90 else 0 }
	end
end

local function gradient(c: Paint.Canvas, top: Color3, bottom: Color3)
	c:box(-10, -10, PW + 10, PH + 10, bottom)
	c:grad(-10, -10, PW + 10, PH + 10, { color = ColorSequence.new(top, bottom), rotation = 90 })
end

local function teal(): Paint.Canvas
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(8101)
	Util.rand(r)
	gradient(c, Color3.fromRGB(70, 126, 152), Color3.fromRGB(92, 146, 168))
	-- a big pale glow off centre, the rest deep teal
	soft(c, 1000, 360, 1900, 1300, Color3.fromRGB(196, 204, 210), 0.9, 16)
	soft(c, 1080, 300, 1000, 700, Color3.fromRGB(226, 232, 236), 0.75, 12)
	soft(c, 180, 760, 1000, 700, Color3.fromRGB(48, 96, 128), 0.6, 10)
	for _ = 1, 16 do
		c:pill(Util.randRange(r, 0, PW), Util.randRange(r, 0, PH), Util.randRange(r, 200, 700), Util.randRange(r, 6, 26), Util.randRange(r, -30, -10), Color3.fromRGB(214, 232, 240), Util.randRange(r, 0.7, 0.9))
	end
	return c
end

local function lav(): Paint.Canvas
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(8111)
	Util.rand(r)
	gradient(c, Color3.fromRGB(96, 108, 186), Color3.fromRGB(82, 94, 168))
	soft(c, 1100, 420, 1400, 1000, Color3.fromRGB(112, 122, 198), 0.6, 10)
	-- vertical light streaks down the left third
	for _ = 1, 22 do
		local x = Util.randRange(r, 20, 640)
		local col = Util.mix(Color3.fromRGB(128, 146, 206), Color3.fromRGB(176, 192, 236), Util.rand(r))
		c:rect(x, PH / 2, Util.randRange(r, 8, 60), PH + 40, Util.randRange(r, -4, 4), col, Util.randRange(r, 0.35, 0.8))
	end
	return c
end

local function clouds(): Paint.Canvas
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(8121)
	Util.rand(r)
	gradient(c, Color3.fromRGB(124, 132, 186), Color3.fromRGB(140, 146, 198))
	soft(c, 800, 200, 1900, 800, Color3.fromRGB(150, 156, 206), 0.5, 10)
	-- banks of cloud low in the frame, dark with pinkish tops
	for _ = 1, 26 do
		local x, y = Util.randRange(r, -100, PW + 100), Util.randRange(r, 610, 900)
		local w, hh = Util.randRange(r, 260, 620), Util.randRange(r, 90, 200)
		c:blob(x, y, w, hh, Color3.fromRGB(80, 86, 154), 0.8, 3)
		c:blob(x + Util.randRange(r, -40, 40), y - hh * 0.32, w * 0.7, hh * 0.35, Color3.fromRGB(170, 150, 196), 0.45, 2)
	end
	for _ = 1, 10 do
		c:pill(Util.randRange(r, 0, PW), Util.randRange(r, 380, 640), Util.randRange(r, 300, 800), Util.randRange(r, 10, 30), Util.randRange(r, -6, 6), Color3.fromRGB(104, 110, 172), 0.6)
	end
	return c
end

local function dusk(): Paint.Canvas
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(8131)
	Util.rand(r)
	gradient(c, Color3.fromRGB(122, 116, 196), Color3.fromRGB(176, 166, 214))
	soft(c, 1200, 760, 1700, 800, Color3.fromRGB(196, 178, 218), 0.55, 10)
	for _ = 1, 12 do
		c:pill(Util.randRange(r, 0, PW), Util.randRange(r, 80, 500), Util.randRange(r, 300, 900), Util.randRange(r, 10, 34), Util.randRange(r, -8, 4), Color3.fromRGB(150, 140, 206), 0.6)
	end
	return c
end

local function navy(): Paint.Canvas
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(8141)
	Util.rand(r)
	gradient(c, Color3.fromRGB(44, 58, 92), Color3.fromRGB(58, 74, 104))
	soft(c, 800, 450, 1800, 1100, Color3.fromRGB(66, 82, 118), 0.5, 10)
	-- dense short hatching all over, like the painted night sky
	for _ = 1, 360 do
		local col = Util.mix(Color3.fromRGB(78, 98, 140), Color3.fromRGB(140, 160, 200), Util.rand(r))
		c:pill(Util.randRange(r, 0, PW), Util.randRange(r, 0, PH), Util.randRange(r, 14, 46), Util.randRange(r, 2, 4), Util.randRange(r, -70, -40), col, Util.randRange(r, 0.3, 0.7))
	end
	return c
end

-- a billowing cloud of dust on a clear background (it rolls in over a shot)
local function dust(): Paint.Canvas
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(8161)
	Util.rand(r)
	-- a broad diagonal mass from the lower left up to the right
	for _ = 1, 70 do
		local f = Util.rand(r)
		local x = Util.lerp(560, 1700, f) + Util.randRange(r, -160, 160)
		local y = Util.lerp(980, -80, f) + Util.randRange(r, -150, 150)
		local w = Util.randRange(r, 220, 520)
		local col = Util.mix(Color3.fromRGB(176, 168, 166), Color3.fromRGB(244, 240, 236), Util.rand(r))
		soft(c, x, y, w, w * Util.randRange(r, 0.6, 0.95), col, Util.randRange(r, 0.85, 0.98), 5)
	end
	-- darker folds and streaks of speed through it
	for _ = 1, 22 do
		local x, y = Util.randRange(r, 700, 1600), Util.randRange(r, 0, 900)
		c:pill(x, y, Util.randRange(r, 160, 420), Util.randRange(r, 12, 40), 35 + Util.randRange(r, -10, 10), Color3.fromRGB(90, 82, 86), Util.randRange(r, 0.35, 0.65))
	end
	for _ = 1, 26 do
		local x, y = Util.randRange(r, 600, 1650), Util.randRange(r, 0, 900)
		c:pill(x, y, Util.randRange(r, 200, 600), Util.randRange(r, 6, 16), 35 + Util.randRange(r, -6, 6), Color3.fromRGB(246, 242, 240), Util.randRange(r, 0.4, 0.7))
	end
	return c
end

local function night(): Paint.Canvas
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(8151)
	Util.rand(r)
	gradient(c, Color3.fromRGB(58, 58, 70), Color3.fromRGB(74, 72, 82))
	-- far buildings with a few lit windows
	local x = -20
	while x < PW + 40 do
		local w = Util.randRange(r, 60, 180)
		local top = Util.randRange(r, 360, 560)
		c:box(x, top, x + w, PH + 10, Color3.fromRGB(26, 26, 32))
		for _ = 1, math.floor(w / 18) do
			local wx, wy = Util.randRange(r, x + 6, x + w - 6), Util.randRange(r, top + 10, PH - 20)
			c:rect(wx, wy, 5, 4, 0, Color3.fromRGB(214, 186, 140), Util.randRange(r, 0.4, 0.8))
		end
		x += w + Util.randRange(r, 4, 30)
	end
	return c
end

-- Put a backdrop plate `dist` studs in front of the camera, filling the view
-- (call after ctx:camera). `roll` turns it in the picture plane, `sx`/`sy`
-- slide it (fractions of its size) so painted streaks drift past.
function FlashArt.backdrop(ctx: Timeline.Ctx, name: string, dist: number, roll: number?, sx: number?, sy: number?)
	local h: H = ctx.scene.data.flash
	local p = h.plates[name]
	assert(p, "unknown backdrop " .. name)
	local cam = ctx.frame.camera
	local hh = 2 * dist * math.tan(math.rad(ctx.frame.fov) / 2) * 1.3
	local grow = 1 + 0.8 * math.abs(math.sin(roll or 0))
	local ww = hh * 16 / 9 * grow
	hh *= grow
	local pos = cam.Position + cam.LookVector * dist + cam.RightVector * (sx or 0) * ww + cam.UpVector * (sy or 0) * hh
	ctx:place(p, Util.lookAt(pos, pos - cam.LookVector, cam.UpVector) * CFrame.Angles(0, 0, roll or 0))
	ctx:prop(p, { s = V(ww, hh, 0.05) })
end

-- the key light next to the camera (offset in camera space), and a rim light
function FlashArt.key(ctx: Timeline.Ctx, offset: Vector3, b: number, col: Color3?, range: number?)
	local h: H = ctx.scene.data.flash
	ctx:place(h.key, CFrame.new(ctx.frame.camera * offset))
	ctx:light("FbKey", b, col or WHITE, range or 60)
end
function FlashArt.rim(ctx: Timeline.Ctx, pos: Vector3, b: number, col: Color3?, range: number?)
	local h: H = ctx.scene.data.flash
	ctx:place(h.rim, CFrame.new(pos))
	ctx:light("FbRim", b, col or WHITE, range or 40)
end

-- smears of blood stuck to a bone: offsets (bone-local), each a flattened
-- ellipsoid `size` across, turned `rot` degrees in the bone's XY plane
function FlashArt.placeSmears(ctx: Timeline.Ctx, bone: CFrame, spots: { { number } }, col: Color3?)
	local h: H = ctx.scene.data.flash
	for i, part in h.smears do
		local sp = spots[i]
		if sp then
			ctx:place(part, bone * C(sp[1], sp[2], sp[3]) * CFrame.Angles(0, 0, math.rad(sp[6] or 0)))
			ctx:prop(part, { s = V(sp[4], sp[5], 0.06), c = col })
		end
	end
end

-- a thin glowing ring (a shockwave seen face on) round `center`, in the
-- plane facing `normal`
function FlashArt.placeHalo(ctx: Timeline.Ctx, center: Vector3, normal: Vector3, radius: number, width: number, k: number)
	if k <= 0.001 then
		return
	end
	local h: H = ctx.scene.data.flash
	local n = normal.Unit
	local a = n:Cross(V(0, 1, 0))
	if a.Magnitude < 0.1 then
		a = n:Cross(V(1, 0, 0))
	end
	a = a.Unit
	local b = n:Cross(a).Unit
	local m = #h.halo
	for i, part in h.halo do
		local a0, a1 = (i - 1) / m * math.pi * 2, i / m * math.pi * 2
		local p0 = center + (a * math.cos(a0) + b * math.sin(a0)) * radius
		local p1 = center + (a * math.cos(a1) + b * math.sin(a1)) * radius
		ctx:place(part, FX.along(p0, p1))
		ctx:prop(part, { s = V((p1 - p0).Magnitude * 1.15, width, width), t = 1 - k * 0.8 })
	end
end

-- the line art boils: a different drawing of the same lines ~10 times a second
function FlashArt.lines(ctx: Timeline.Ctx, base: string, a: number)
	local v = math.floor(ctx.t * 10) % 3 + 1
	ctx:alpha(base .. v, a)
end


------------------------------------------------------------------------------
-- Yuta's stretched arm
------------------------------------------------------------------------------
local ARM_SEGS = 30
local ARM_LIGHT = Color3.fromRGB(238, 226, 212)
local ARM_DARK = Color3.fromRGB(92, 60, 48)

local function buildArm(scene: Builder.Scene): Arm
	local a: Arm = { light = {}, dark = {}, hand = {} }
	for _ = 1, ARM_SEGS do
		local d = Builder.fx(scene, "P2FbArm", "Ellipsoid", V(1, 1, 1), ARM_DARK, "SmoothPlastic", 0, "ArmDark")
		local l = Builder.fx(scene, "P2FbArm", "Ellipsoid", V(1, 1, 1), ARM_LIGHT, "SmoothPlastic", 0, "ArmLight")
		d.castShadow = false
		l.castShadow = false
		table.insert(a.dark, d)
		table.insert(a.light, l)
	end
	-- palm, four fingers in two joints, thumb
	for i = 1, 11 do
		local p = Builder.fx(scene, "P2FbArm", "Ellipsoid", V(1, 1, 1), if i == 1 then ARM_LIGHT else Util.mix(ARM_LIGHT, ARM_DARK, 0.15), "SmoothPlastic", 0, "ArmHand")
		p.castShadow = false
		table.insert(a.hand, p)
	end
	return a
end

-- frame at the middle of a..b, X along the segment, Y towards `up`
local function alongUp(a: Vector3, b: Vector3, up: Vector3): CFrame
	local x = (b - a).Unit
	local y = up - x * up:Dot(x)
	if y.Magnitude < 1e-3 then
		y = x:Cross(V(0, 0, 1))
	end
	y = y.Unit
	local z = x:Cross(y).Unit
	return CFrame.fromMatrix((a + b) / 2, x, y, z)
end

-- Catmull-Rom through the control points, sampled at u in 0..1
local function spline(pts: { Vector3 }, u: number): Vector3
	local n = #pts
	local f = math.clamp(u, 0, 1) * (n - 1)
	local i = math.min(n - 1, math.floor(f) + 1)
	local t = f - (i - 1)
	local p0 = pts[math.max(1, i - 1)]
	local p1 = pts[i]
	local p2 = pts[i + 1]
	local p3 = pts[math.min(n, i + 2)]
	local t2, t3 = t * t, t * t * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end
FlashArt.spline = spline

-- Lay the arm through control points `pts` (shoulder first), `w0` wide at the
-- shoulder and `w1` at the wrist; `up` is where the light comes from; `curl`
-- (0..1) closes the hand into a hook
function FlashArt.placeArm(ctx: Timeline.Ctx, pts: { Vector3 }, w0: number, w1: number, up: Vector3, curl: number)
	local h: H = ctx.scene.data.flash
	local arm = h.arm
	local prev = spline(pts, 0)
	local last = CFrame.new(prev)
	for s = 1, ARM_SEGS do
		local u = s / ARM_SEGS
		local q = spline(pts, u)
		local len = (q - prev).Magnitude
		if len > 1e-3 then
			local w = Util.lerp(w0, w1, u) * (1 + 0.12 * math.sin(u * math.pi * 3))
			local cf = alongUp(prev, q, up)
			ctx:place(arm.light[s], cf * C(0, w * 0.1, 0))
			ctx:prop(arm.light[s], { s = V(len * 2.1, w * 0.46, w) })
			ctx:place(arm.dark[s], cf * C(0, -w * 0.12, 0))
			ctx:prop(arm.dark[s], { s = V(len * 2.1, w * 0.5, w * 1.05) })
			last = cf * C(len / 2, 0, 0)
		end
		prev = q
	end
	-- the hand: palm on along the arm, fingers bending round towards -Y
	local hw = w1 * 1.9
	local palm = last * C(hw * 0.5, 0, 0)
	ctx:place(arm.hand[1], palm)
	ctx:prop(arm.hand[1], { s = V(hw * 1.1, hw * 0.42, hw * 0.95) })
	for f = 1, 4 do
		local z = (f - 2.5) * hw * 0.22
		local base = palm * C(hw * 0.5, 0, z) * CFrame.Angles(0, 0, -math.rad(20 + 70 * curl))
		local l1 = hw * (if f == 1 or f == 4 then 0.42 else 0.5)
		ctx:place(arm.hand[1 + f], base * C(l1 / 2, 0, 0))
		ctx:prop(arm.hand[1 + f], { s = V(l1 * 1.1, hw * 0.2, hw * 0.2) })
		local tip = base * C(l1, 0, 0) * CFrame.Angles(0, 0, -math.rad(30 + 80 * curl))
		ctx:place(arm.hand[5 + f], tip * C(l1 * 0.4, 0, 0))
		ctx:prop(arm.hand[5 + f], { s = V(l1 * 0.9, hw * 0.18, hw * 0.18) })
	end
	local thumb = palm * C(hw * 0.1, -hw * 0.1, -hw * 0.55) * CFrame.Angles(0, math.rad(40), -math.rad(30 * curl))
	ctx:place(arm.hand[10], thumb * C(hw * 0.25, 0, 0))
	ctx:prop(arm.hand[10], { s = V(hw * 0.55, hw * 0.22, hw * 0.22) })
	ctx:place(arm.hand[11], palm * C(-hw * 0.45, 0, 0))
	ctx:prop(arm.hand[11], { s = V(hw * 0.5, hw * 0.4, hw * 0.75) })
end


------------------------------------------------------------------------------
-- Rika's hand for the catch
------------------------------------------------------------------------------
local BONE = Color3.fromRGB(236, 234, 238)
local BONE_SHADE = Color3.fromRGB(196, 194, 204)
local STRIPE = Color3.fromRGB(34, 32, 40)

local function buildClaw(scene: Builder.Scene): Claw
	local parts: { Builder.PartSpec } = {}
	local function p(shape: string, col: Color3, name: string)
		local q = Builder.fx(scene, "P2FbClaw", shape, V(1, 1, 1), col, "SmoothPlastic", 0, name)
		q.castShadow = false
		table.insert(parts, q)
	end
	p("Ellipsoid", BONE, "Forearm") -- 1
	p("Ellipsoid", BONE_SHADE, "Forearm") -- 2
	p("Ellipsoid", BONE, "Palm") -- 3
	for _ = 1, 4 do
		p("Ellipsoid", BONE, "Finger")
		p("Ellipsoid", BONE, "Finger")
		p("Ellipsoid", BONE_SHADE, "Finger")
		p("Wedge", STRIPE, "Claw")
	end -- 4..19
	p("Ellipsoid", BONE, "Thumb")
	p("Ellipsoid", BONE_SHADE, "Thumb")
	p("Wedge", STRIPE, "Claw") -- 20..22
	p("Ellipsoid", STRIPE, "Stripe")
	p("Ellipsoid", STRIPE, "Stripe") -- 23..24
	for _ = 1, 8 do
		p("Ellipsoid", STRIPE, "Crease")
	end -- 25..32: dark creases at the finger joints
	return { parts = parts }
end

-- Place the hand: `wrist` has the fingers pointing along -Y and the palm
-- facing +Z; `sc` is the hand length in studs; `open` 1 = fingers spread wide,
-- 0 = a fist
function FlashArt.placeClaw(ctx: Timeline.Ctx, wrist: CFrame, sc: number, open: number)
	local h: H = ctx.scene.data.flash
	local q = h.claw.parts
	local function put(i: number, cf: CFrame, size: Vector3)
		ctx:place(q[i], cf)
		ctx:prop(q[i], { s = size * sc })
	end
	-- forearm reaching back from the wrist (+Y)
	put(1, wrist * C(0, 1.3 * sc, 0), V(0.74, 2.7, 0.6))
	put(2, wrist * C(0.08 * sc, 1.25 * sc, -0.08 * sc), V(0.7, 2.6, 0.58))
	put(23, wrist * C(0, 0.8 * sc, 0) * CFrame.Angles(math.rad(18), 0, 0), V(0.77, 0.07, 0.63))
	put(24, wrist * C(0, 1.6 * sc, 0) * CFrame.Angles(math.rad(-12), 0, 0), V(0.76, 0.07, 0.62))
	local palm = wrist * C(0, -0.36 * sc, 0)
	put(3, palm, V(0.7, 0.5, 0.16))
	local curl = math.rad(8 + 64 * (1 - open))
	for f = 0, 3 do
		local x = (f - 1.5) * 0.22
		local spread = math.rad((f - 1.5) * -15 * (0.25 + open))
		local cf = palm * C(x * sc, -0.24 * sc, 0) * CFrame.Angles(curl * 0.6, 0, spread)
		local lens = { 0.62, 0.52, 0.42 }
		for si, len in lens do
			put(4 + f * 4 + si - 1, cf * C(0, -len / 2 * sc, 0), V(0.2 - si * 0.02, len + 0.08, 0.19 - si * 0.02))
			cf = cf * C(0, -len * sc, 0) * CFrame.Angles(curl, 0, 0)
			if si <= 2 then
				put(25 + f * 2 + si - 1, cf, V(0.21 - si * 0.02, 0.035, 0.2 - si * 0.02))
			end
		end
		put(4 + f * 4 + 3, cf * CFrame.Angles(math.pi, 0, 0) * C(0, 0.08 * sc, 0), V(0.12, 0.34, 0.16))
	end
	local tcf = palm * C(0.48 * sc, -0.02 * sc, 0.06 * sc) * CFrame.Angles(curl * 0.4, 0, math.rad(-50 + 25 * (1 - open)))
	put(20, tcf * C(0, -0.25 * sc, 0), V(0.2, 0.52, 0.2))
	tcf = tcf * C(0, -0.5 * sc, 0) * CFrame.Angles(curl * 0.7, 0, 0)
	put(21, tcf * C(0, -0.2 * sc, 0), V(0.17, 0.42, 0.17))
	put(22, tcf * C(0, -0.42 * sc, 0) * CFrame.Angles(math.pi, 0, 0), V(0.1, 0.28, 0.14))
end

------------------------------------------------------------------------------
-- Uro's severed arm and blood trails
------------------------------------------------------------------------------
local SKIN = Color3.fromRGB(240, 222, 214)

local function buildSevered(scene: Builder.Scene): Severed
	local parts: { Builder.PartSpec } = {}
	local function p(shape: string, col: Color3, name: string)
		local q = Builder.fx(scene, "P2FbSev", shape, V(1, 1, 1), col, "SmoothPlastic", 0, name)
		q.castShadow = false
		table.insert(parts, q)
	end
	p("Ellipsoid", SKIN, "UpperArm") -- 1
	p("Ellipsoid", SKIN, "Forearm") -- 2
	p("Cylinder", Color3.fromRGB(74, 32, 36), "Bracelet") -- 3
	p("Ellipsoid", SKIN, "Hand") -- 4
	for _ = 1, 4 do
		p("Ellipsoid", SKIN, "Finger")
		p("Ball", Color3.fromRGB(206, 64, 76), "Nail")
	end -- 5..12
	p("Ellipsoid", SKIN, "Thumb") -- 13
	p("Ellipsoid", Color3.fromRGB(150, 22, 34), "Stump") -- 14
	p("Ellipsoid", Color3.fromRGB(110, 14, 24), "Stump") -- 15
	local trail: { Builder.PartSpec } = {}
	for _ = 1, 24 do
		local q = Builder.fx(scene, "P2FbSev", "Ellipsoid", V(1, 1, 1), Color3.fromRGB(176, 20, 34), "SmoothPlastic", 0, "BloodTrail")
		q.castShadow = false
		table.insert(trail, q)
	end
	return { parts = parts, trail = trail }
end

-- Place the arm: `shoulder` at the torn end, the arm hanging along -Y,
-- the palm facing +Z, fingers slightly curled
function FlashArt.placeSevered(ctx: Timeline.Ctx, shoulder: CFrame, elbow: number)
	local h: H = ctx.scene.data.flash
	local q = h.sev.parts
	local function put(i: number, cf: CFrame, size: Vector3)
		ctx:place(q[i], cf)
		ctx:prop(q[i], { s = size })
	end
	put(14, shoulder * C(0, -0.05, 0), V(0.4, 0.16, 0.42))
	put(15, shoulder * C(0, 0.02, 0), V(0.3, 0.1, 0.3))
	put(1, shoulder * C(0, -0.5, 0), V(0.36, 1.08, 0.38))
	local el = shoulder * C(0, -0.96, 0) * CFrame.Angles(0, 0, math.rad(elbow))
	put(2, el * C(0, -0.44, 0), V(0.31, 0.98, 0.33))
	put(3, el * C(0, -0.76, 0) * CFrame.Angles(0, 0, math.pi / 2), V(0.16, 0.38, 0.38))
	local wr = el * C(0, -0.88, 0) * CFrame.Angles(math.rad(-12), 0, 0)
	put(4, wr * C(0, -0.2, 0), V(0.28, 0.4, 0.14))
	for f = 1, 4 do
		local x = (f - 2.5) * 0.066
		local fc = wr * C(x, -0.4, 0) * CFrame.Angles(math.rad(14), 0, math.rad((f - 2.5) * -8))
		put(3 + f * 2, fc * C(0, -0.13, 0), V(0.06, 0.28, 0.07))
		put(4 + f * 2, fc * C(0, -0.26, -0.02), V(0.05, 0.06, 0.04))
	end
	put(13, wr * C(-0.15, -0.2, -0.05) * CFrame.Angles(0, 0, math.rad(-28)), V(0.07, 0.24, 0.08))
end

-- Thin trails of blood: blobs strung along `points` (world), thinning out
function FlashArt.placeTrail(ctx: Timeline.Ctx, points: { Vector3 }, w: number, col: Color3?)
	local h: H = ctx.scene.data.flash
	local tr = h.sev.trail
	local n = #tr
	for i, part in tr do
		local u0, u1 = (i - 1) / n, i / n
		local a, b = spline(points, u0), spline(points, u1)
		local l = (b - a).Magnitude
		if l > 1e-3 then
			local ww = w * (1 - u0 * 0.7) * (0.7 + 0.3 * math.sin(i * 2.3))
			ctx:place(part, FX.along(a, b))
			ctx:prop(part, { s = V(l * 1.3, ww, ww), c = col })
		end
	end
end

------------------------------------------------------------------------------
-- the set (around origin O): a dark roof with road markings, an apartment
-- block with rows of windows, an elevated road on pillars, lower blocks
------------------------------------------------------------------------------
local function facade(w: number, hgt: number, seed: number): Paint.Canvas
	-- canvas px = 1/10 stud
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(seed)
	Util.rand(r)
	local pw, ph = w * 10, hgt * 10
	c:box(0, 0, pw, ph, Color3.fromRGB(112, 114, 134))
	local floors = math.floor(hgt / 3.2)
	for f = 0, floors - 1 do
		local y = ph - (f + 0.5) * 32
		c:rect(pw / 2, y + 12, pw, 6, 0, Color3.fromRGB(206, 208, 220))
		local x = 14
		while x < pw - 14 do
			local lit = Util.rand(r) < 0.16
			c:rect(x + 9, y - 3, 16, 17, 0, if lit then Color3.fromRGB(226, 204, 168) else Color3.fromRGB(34, 38, 52))
			x += 26
		end
	end
	return c
end

local function buildSet(scene: Builder.Scene, o: Vector3)
	local m = "P2FbSet"
	Builder.model(scene, m, false)
	local function block(size: Vector3, cf: CFrame, col: Color3, name: string, gui: Builder.GuiSpec?): Builder.PartSpec
		return Builder.part(scene, m, size, cf, col, { material = "Concrete", name = name, gui = gui })
	end
	-- the roof: dark, with an orange line and a dashed white one
	block(V(160, 4, 160), C(o + V(0, -14, 0)), Color3.fromRGB(70, 68, 80), "FbRoof")
	Builder.part(scene, m, V(0.5, 0.06, 160), C(o + V(7, -11.97, 0)), Color3.fromRGB(226, 134, 58), { material = "SmoothPlastic", castShadow = false, name = "FbLine" })
	for i = -8, 8 do
		Builder.part(scene, m, V(0.35, 0.06, 4), C(o + V(-6, -11.97, i * 9)), Color3.fromRGB(160, 160, 170), { material = "SmoothPlastic", castShadow = false, name = "FbDash" })
	end
	-- the apartment block behind, its windows painted on an invisible plate
	-- just in front of its face (+Z), so the painting never fights the wall
	local function facadePlate(size: Vector3, centre: Vector3, seed: number, name: string)
		block(size, C(centre), Color3.fromRGB(78, 80, 96), name)
		-- turned round so its Front face (the painted one) looks towards +Z
		Builder.part(scene, m, V(size.X, size.Y, 0.1), C(centre + V(0, 0, size.Z / 2 + 0.25)) * CFrame.Angles(0, math.pi, 0), WHITE, {
			material = "SmoothPlastic",
			transparency = 1,
			castShadow = false,
			name = name .. "Face",
			gui = { face = "Front", canvas = Vector2.new(size.X * 10, size.Y * 10), lightInfluence = 0.15, elems = facade(size.X, size.Y, seed).elems },
		})
	end
	facadePlate(V(70, 64, 16), o + V(-34, -12 + 32, -78), 8201, "FbApt")
	facadePlate(V(34, 40, 20), o + V(44, -12 + 20, -92), 8203, "FbBlock2")
	-- the elevated road across the middle distance, on pillars
	block(V(260, 2.4, 12), C(o + V(0, 6, -48)), Color3.fromRGB(64, 66, 80), "FbDeck")
	block(V(260, 1.4, 0.5), C(o + V(0, 7.9, -42.2)), Color3.fromRGB(96, 98, 114), "FbRailing")
	block(V(260, 1.4, 0.5), C(o + V(0, 7.9, -53.8)), Color3.fromRGB(96, 98, 114), "FbRailing")
	for i = -5, 5 do
		block(V(2.6, 18, 2.6), C(o + V(i * 24, -3, -48)), Color3.fromRGB(58, 60, 74), "FbPillar")
	end
	-- lower blocks round the roof
	local r = Util.rng(8221)
	Util.rand(r)
	for i = 1, 18 do
		local a = i / 18 * math.pi * 2 + Util.randRange(r, -0.12, 0.12)
		local d = Util.randRange(r, 95, 160)
		local hgt = Util.randRange(r, 8, 34)
		local w = Util.randRange(r, 14, 30)
		local p = o + V(math.cos(a) * d, -16 + hgt / 2, math.sin(a) * d)
		block(V(w, hgt, w * Util.randRange(r, 0.7, 1.3)), C(p) * CFrame.Angles(0, Util.randRange(r, 0, 1.5), 0), Util.mix(Color3.fromRGB(44, 44, 58), Color3.fromRGB(80, 80, 98), Util.rand(r)), "FbLow")
	end
end

function FlashArt.build(scene: Builder.Scene, origin: Vector3)
	eyeOverlay(scene)
	arcsOverlay(scene)
	smearOverlay(scene)
	darkSmearOverlay(scene)
	glitchOverlay(scene)
	cracks(scene, "fbCrackA", 560, 270, 1, 7971)
	cracks(scene, "fbCrackB", 640, 96, 1.15, 7983)
	tibOverlay(scene)
	local plates: { [string]: Builder.PartSpec } = {
		teal = plate(scene, "FbTeal", teal()),
		lav = plate(scene, "FbLav", lav()),
		clouds = plate(scene, "FbClouds", clouds()),
		dusk = plate(scene, "FbDusk", dusk()),
		navy = plate(scene, "FbNavy", navy()),
		night = plate(scene, "FbNight", night()),
		dust = plate(scene, "FbDust", dust()),
	}
	local key = Builder.fx(scene, "P2FbKey", "Ball", V(0.2, 0.2, 0.2), WHITE, "SmoothPlastic", 1, "FbKey")
	local rim = Builder.fx(scene, "P2FbKey", "Ball", V(0.2, 0.2, 0.2), WHITE, "SmoothPlastic", 1, "FbRim")
	Builder.light(scene, "FbKey", "Point", key, WHITE, 60)
	Builder.light(scene, "FbRim", "Point", rim, WHITE, 40)
	buildSet(scene, origin)
	local shards = FX.burst(scene, "FbShards", Color3.fromRGB(236, 242, 255), 34, "Wedge", 7991)
	local smears: { Builder.PartSpec } = {}
	for _ = 1, 12 do
		local q = Builder.fx(scene, "P2FbSmear", "Ellipsoid", V(1, 1, 1), Color3.fromRGB(120, 16, 26), "SmoothPlastic", 0, "BloodSmear")
		q.castShadow = false
		table.insert(smears, q)
	end
	local halo: { Builder.PartSpec } = {}
	for _ = 1, 28 do
		local q = Builder.fx(scene, "P2FbHalo", "Cylinder", V(1, 1, 1), Color3.fromRGB(236, 244, 255), "Neon", 0.2, "Halo")
		table.insert(halo, q)
	end
	scene.data.flash = {
		plates = plates,
		key = key,
		rim = rim,
		arm = buildArm(scene),
		claw = buildClaw(scene),
		sev = buildSevered(scene),
		shards = shards,
		halo = halo,
		smears = smears,
	} :: H
end

return FlashArt
