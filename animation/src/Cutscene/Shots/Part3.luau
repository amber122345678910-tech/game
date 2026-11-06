--!strict
-- Part 3 ("Yuta vs. Ryu end fight scene pt. 3", 56.87 s). 0-2.633 replays the
-- end of part 2 (see Scene.build). Then: Rika's black shell crumbles to smoke
-- and Ryu tears free, bloody and grinning; a brawl of bare fists with a black
-- flash, intercut with a table of desserts that vanish one by one; Yuta grabs
-- Ryu by the collar: "Now we're done." Shot list: docs/part3_shots.md.
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local FX = require(script.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Util)
local Paint = require(script.Parent.Parent.Paint)
local Rig = require(script.Parent.Parent.Rig)
local Cast = require(script.Parent.Cast)
local Clash = require(script.Parent.Clash)
local Common = require(script.Parent.P2.Common)
local FlashArt = require(script.Parent.P2.FlashArt)

local Part3 = {}

local V = Vector3.new
local C = CFrame.new
local R = Rig.R

local WHITE = Color3.new(1, 1, 1)

local RYU = Common.RYU
local YUTA = Common.RYU + V(0.3, 0, -3.2) -- close quarters
local DESSERT = V(0, 3000, -900) -- the dessert table, far above the field

type Group = { Builder.PartSpec }
type P3 = {
	blackBolts: FX.Bolt,
	redBolts: FX.Bolt,
	bigSmoke: FX.Burst,
	steam: FX.Burst,
	flakes: FX.Burst,
	vanish: { [string]: Group },
	rikaParts: Group,
	fingers: Group,
	fist: Builder.PartSpec,
	hood: Builder.PartSpec,
	hoodFur: Group,
	columns: Group,
	flash: Builder.PartSpec,
	redGlow: Builder.PartSpec,
	void: Builder.PartSpec,
	slabs: Group,
	stones: Group,
	yBlood: Group,
	streaks: Group,
	yHand: Group,
	yHandRig: Group,
	yCollar: Group,
	lamp: Builder.PartSpec,
	redBack: Builder.PartSpec,
	redShards: FX.Burst,
	speed: Builder.PartSpec,
}

local function h2(ctx: Timeline.Ctx): Common.H
	return ctx.scene.data.p2
end
local function h3(ctx: Timeline.Ctx): P3
	return ctx.scene.data.p3
end

-- a random sequence per item: Park-Miller's first value barely changes
-- between nearby small seeds, so the seed is spread and two values skipped
local function rng(seed: number): Util.Rng
	local r = Util.rng(seed * 7919 + 101)
	Util.rand(r)
	Util.rand(r)
	return r
end

---------------------------------------------------------------------------
-- The blur behind a flying fist (reference 39.5-40.7): deep blue streaked
-- with long horizontal lines of lighter blue and white, three views wide so
-- it can stream past the whole shot (canvas px = 1/10 stud)
---------------------------------------------------------------------------
local SP_W, SP_H = 2400, 600
local function speedPlate(scene: Builder.Scene): Builder.PartSpec
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(3141)
	Util.rand(r)
	c:box(-10, -10, SP_W + 10, SP_H + 10, Color3.fromRGB(30, 46, 104))
	c:grad(-10, -10, SP_W + 10, SP_H + 10, { color = ColorSequence.new(Color3.fromRGB(58, 80, 150), Color3.fromRGB(24, 36, 86)), rotation = 90 })
	for _ = 1, 240 do
		local y = Util.randRange(r, 0, SP_H)
		local x = Util.randRange(r, -200, SP_W + 200)
		local len = Util.randRange(r, 120, 900)
		local th = Util.randRange(r, 2, 16)
		local f = Util.rand(r)
		local col = if f < 0.15 then Color3.fromRGB(236, 242, 255) elseif f < 0.55 then Color3.fromRGB(120, 150, 214) else Color3.fromRGB(70, 96, 170)
		c:pill(x, y, len, th, Util.randRange(r, -1.5, 1.5), col, Util.randRange(r, 0.1, 0.6))
	end
	Builder.model(scene, "P3Speed", false)
	return Builder.part(scene, "P3Speed", V(SP_W / 10, SP_H / 10, 0.05), C(), Color3.new(1, 1, 1), {
		fx = true,
		castShadow = false,
		transparency = 1,
		name = "SpeedPlate",
		gui = { face = "Front", canvas = Vector2.new(SP_W, SP_H), lightInfluence = 0, elems = c.elems },
	})
end

---------------------------------------------------------------------------
-- The backdrop of the black flash (reference 28.6-29.2): a black void torn
-- by huge red bursts of cursed energy, ragged like flames and splashes,
-- radiating from the two of them, with pink-white hot spots and red
-- lightning (canvas px = 1/10 stud)
---------------------------------------------------------------------------
local RB_W, RB_H = 1600, 900
local function redBackdrop(scene: Builder.Scene): Builder.PartSpec
	local c = Paint.canvas(1, 0, 0)
	c:box(-10, -10, RB_W + 10, RB_H + 10, Color3.fromRGB(6, 2, 4))
	local r = Util.rng(2718)
	Util.rand(r)
	local cx, cy = 760, 470
	local darkRed, red, hot = Color3.fromRGB(110, 8, 20), Color3.fromRGB(226, 26, 44), Color3.fromRGB(255, 210, 222)
	-- a deep red glow round the middle
	c:blob(cx, cy, 1100, 640, Color3.fromRGB(60, 4, 10), 0.4, 5)
	-- big ragged tongues of energy radiating outwards, two layers
	local function tongues(n: number, len0: number, len1: number, w0: number, col: Color3, curl: number)
		for _ = 1, n do
			local a = Util.randRange(r, 0, math.pi * 2)
			local len = Util.randRange(r, len0, len1)
			local start = Util.randRange(r, 60, 200)
			local bend = Util.randRange(r, -curl, curl)
			local pts: { { number } } = {}
			local ws: { number } = {}
			for k = 0, 4 do
				local f = k / 4
				local aa = a + bend * f * f
				local d = start + len * f
				table.insert(pts, { cx + math.cos(aa) * d, cy + math.sin(aa) * d * 0.72 })
				table.insert(ws, w0 * (1 - f) ^ 1.3 + 2)
			end
			c:stroke(pts, ws, col, { minStep = 10, maxStep = 40 })
		end
	end
	tongues(30, 380, 820, 120, darkRed, 0.7)
	tongues(34, 220, 560, 70, red, 0.9)
	-- big splashes towards the edges
	for _ = 1, 12 do
		local a = Util.randRange(r, 0, math.pi * 2)
		local d = Util.randRange(r, 420, 760)
		local x, y = cx + math.cos(a) * d, cy + math.sin(a) * d * 0.6
		c:blob(x, y, Util.randRange(r, 160, 320), Util.randRange(r, 90, 180), red, 0.7, 3)
		for _ = 1, 4 do
			local b = a + Util.randRange(r, -0.8, 0.8)
			local l = Util.randRange(r, 60, 180)
			c:stroke({ { x, y }, { x + math.cos(b) * l, y + math.sin(b) * l } }, { 26, 2 }, red, { minStep = 8, maxStep = 30 })
		end
	end
	-- red lightning
	for _ = 1, 14 do
		local x, y = Util.randRange(r, 0, RB_W), Util.randRange(r, 0, RB_H)
		local pts: { { number } } = { { x, y } }
		for _ = 1, 6 do
			x += Util.randRange(r, -90, 90)
			y += Util.randRange(r, -70, 70)
			table.insert(pts, { x, y })
		end
		c:stroke(pts, 4, Color3.fromRGB(255, 60, 70), { minStep = 6, maxStep = 40 })
	end
	-- pink-white hot spots
	for _ = 1, 16 do
		local a = Util.randRange(r, 0, math.pi * 2)
		local d = Util.randRange(r, 80, 640)
		c:blob(cx + math.cos(a) * d, cy + math.sin(a) * d * 0.65, Util.randRange(r, 40, 110), Util.randRange(r, 30, 70), hot, 0.85, 3)
	end
	c:blob(cx, cy, 300, 200, Color3.fromRGB(255, 120, 140), 0.35, 4)
	return Builder.part(scene, "P3Backdrop", V(RB_W / 10, RB_H / 10, 0.05), C(), Color3.new(1, 1, 1), {
		fx = true,
		castShadow = false,
		name = "RedBackdrop",
		gui = { face = "Front", canvas = Vector2.new(RB_W, RB_H), lightInfluence = 0, elems = c.elems },
	})
end

---------------------------------------------------------------------------
-- The dessert table, laid out as in the reference top view (+Z is "up" on
-- screen): the pink cake in the centre, a teapot, a cup and a two-tier stand
-- on the left, an ice-cream glass and a cup at the top, the cherry tart top
-- right, two plates of profiteroles bottom right. Off to the sides: the
-- strawberry sponge slice, cheesecake plates, a macaron tart, and a chocolate
-- cake with a row of cupcakes (for the dark shot).
---------------------------------------------------------------------------
local function dessertSet(scene: Builder.Scene): { [string]: Group }
	Builder.model(scene, "P3Desserts", false)
	local cream = Color3.fromRGB(250, 244, 232)
	local china = Color3.fromRGB(248, 248, 252)
	local gold = Color3.fromRGB(214, 176, 92)
	local silver = Color3.fromRGB(196, 200, 210)
	local sponge = Color3.fromRGB(244, 210, 146)
	local biscuit = Color3.fromRGB(206, 150, 86)
	local pink = Color3.fromRGB(244, 128, 170)
	local pinkDeep = Color3.fromRGB(220, 70, 120)
	local berry = Color3.fromRGB(214, 28, 50)
	local cherry = Color3.fromRGB(176, 18, 40)
	local choc = Color3.fromRGB(92, 52, 34)
	local tea = Color3.fromRGB(128, 26, 22)
	local lime = Color3.fromRGB(186, 222, 120)
	local yellow = Color3.fromRGB(250, 214, 96)
	local vanish: { [string]: Group } = {}
	local up = CFrame.Angles(0, 0, math.pi / 2) -- cylinders stand upright
	local function part(name: string, shape: string, size: Vector3, cf: CFrame, col: Color3, mat: string?, group: string?): Builder.PartSpec
		local p = Builder.part(scene, "P3Desserts", size, C(DESSERT) * cf, col, { shape = shape, material = mat or "SmoothPlastic", castShadow = size.Magnitude > 1.2, name = name })
		if group then
			local g = vanish[group]
			if not g then
				g = {}
				vanish[group] = g
			end
			table.insert(g, p)
		end
		return p
	end
	local function disc(name: string, x: number, y: number, z: number, d: number, h: number, col: Color3, mat: string?, group: string?): Builder.PartSpec
		return part(name, "Cylinder", V(h, d, d), C(x, y, z) * up, col, mat, group)
	end
	local function plate(x: number, z: number, r: number, group: string?)
		disc("PlateRim", x, 0.05, z, r * 2.12, 0.1, gold, nil, group)
		disc("Plate", x, 0.12, z, r * 2, 0.14, china, nil, group)
		disc("PlateWell", x, 0.17, z, r * 1.4, 0.06, Color3.fromRGB(240, 240, 246), nil, group)
	end
	local function cup(x: number, z: number)
		disc("SaucerRim", x, 0.05, z, 3.2, 0.08, gold)
		disc("Saucer", x, 0.1, z, 3.0, 0.12, china)
		disc("CupFoot", x, 0.3, z, 1.3, 0.3, china)
		disc("Cup", x, 0.95, z, 2.3, 1.0, china)
		disc("CupLip", x, 1.47, z, 2.42, 0.06, gold)
		disc("Tea", x, 1.4, z, 2.1, 0.06, tea)
		part("Handle", "Ellipsoid", V(0.3, 0.8, 0.6), C(x + 1.25, 1.0, z), china)
	end
	-- the cloth and a warm back wall
	part("Cloth", "Block", V(90, 1, 70), C(0, -0.5, 0), Color3.fromRGB(244, 238, 226), "Fabric")
	part("Wall", "Block", V(140, 40, 1), C(-20, 18, 26), Color3.fromRGB(250, 238, 200))
	for i = 0, 13 do
		local x = -64 + i * 2.6 + (i % 3) * 0.5
		part("Curtain", "Block", V(0.7 + (i % 2) * 0.6, 30, 0.2), C(x, 15, 25.4), Color3.fromRGB(252, 244, 214), "SmoothPlastic")
	end

	-- centre: the square pink cake with a macaron and a strawberry
	plate(0, 0, 3.6)
	local y = 0.2
	for _, l in { { h = 0.3, col = biscuit }, { h = 0.5, col = sponge }, { h = 0.2, col = berry }, { h = 0.7, col = pink }, { h = 0.12, col = pinkDeep } } do
		part("Slice", "Block", V(2.6, l.h, 2.6), C(0, y + l.h / 2, 0) * CFrame.Angles(0, math.rad(20), 0), l.col)
		y += l.h
	end
	disc("MacaronA", -0.4, y + 0.15, 0.3, 1.2, 0.26, pink)
	disc("MacaronCream", -0.4, y + 0.33, 0.3, 1.05, 0.12, cream)
	disc("MacaronB", -0.4, y + 0.5, 0.3, 1.2, 0.24, pink)
	part("Strawberry", "Ellipsoid", V(0.8, 0.9, 0.8), C(0.6, y + 0.4, -0.5), berry)
	part("Leaf", "Ellipsoid", V(0.5, 0.06, 0.25), C(0.6, y + 0.88, -0.5) * CFrame.Angles(0, 0.6, 0.2), Color3.fromRGB(90, 170, 80))
	for i = 1, 3 do
		part("Blueberry", "Ball", V(0.34, 0.32, 0.34), C(-0.9 + i * 0.5, y + 0.18, 0.95), Color3.fromRGB(60, 44, 120))
	end
	-- a green plate to the right of it
	part("GreenPlate", "Cylinder", V(0.14, 4.6, 4.6), C(-6.5, 0.1, 0.5) * up, lime)
	for i = 0, 2 do
		part("PetitFour", "Block", V(0.8, 0.5, 0.8), C(-6.5 + (i - 1) * 1.1, 0.42, 0.5) * CFrame.Angles(0, i, 0), ({ pink, cream, choc })[i + 1])
	end

	-- left: teapot, a cup, a two-tier stand (screen left is +X here)
	part("TeapotBody", "Ellipsoid", V(4.2, 3.2, 3.6), C(14, 1.8, -1), china)
	part("TeapotLid", "Ellipsoid", V(2, 0.8, 2), C(14, 3.4, -1), china)
	part("TeapotKnob", "Ball", V(0.5, 0.5, 0.5), C(14, 3.9, -1), silver, "Metal")
	part("TeapotSpout", "Cylinder", V(2.2, 0.5, 0.5), C(11.6, 2.2, -1) * CFrame.Angles(0, 0, math.rad(-35)), china)
	part("TeapotHandle", "Ellipsoid", V(0.4, 1.8, 1.0), C(16.2, 2.0, -1), china)
	cup(8, 4)
	part("StandPole", "Cylinder", V(4.6, 0.3, 0.3), C(12, 2.3, 8) * up, silver, "Metal")
	for t, tier in { { y = 0.4, r = 3.6 }, { y = 2.8, r = 2.6 } } do
		disc("TierRim", 12, tier.y - 0.04, 8, tier.r * 2.06, 0.08, gold)
		disc("Tier", 12, tier.y, 8, tier.r * 2, 0.12, china)
		local n = 7 - t * 2
		for i = 0, n - 1 do
			local a = i / n * math.pi * 2 + t
			local px, pz = 12 + math.cos(a) * tier.r * 0.6, 8 + math.sin(a) * tier.r * 0.6
			part("PetitFour", "Block", V(0.75, 0.5, 0.75), C(px, tier.y + 0.3, pz) * CFrame.Angles(0, a, 0), if i % 2 == 0 then sponge else choc)
			part("Icing", "Block", V(0.77, 0.1, 0.77), C(px, tier.y + 0.58, pz) * CFrame.Angles(0, a, 0), ({ pink, cream, lime })[(i + t) % 3 + 1])
		end
	end
	part("StandTop", "Ball", V(0.6, 0.6, 0.6), C(12, 4.7, 8), silver, "Metal")

	-- top: a tall parfait glass on a saucer (layers vanish top to bottom:
	-- scoop1 = the cream dome and the biscuit, then cream, chocolate, the
	-- last bits at the bottom) and a cup
	local glass = Color3.fromRGB(240, 246, 255)
	local gx, gz = -40, 18 -- on a side table by the wall (seen side on)
	disc("ParfaitSaucerRim", gx, 0.05, gz, 4.5, 0.08, silver)
	disc("ParfaitSaucer", gx, 0.12, gz, 4.3, 0.12, china)
	disc("ParfaitFoot", gx, 0.28, gz, 1.9, 0.2, glass, "Glass")
	part("ParfaitStem", "Cylinder", V(1.3, 0.34, 0.34), C(gx, 0.95, gz) * up, glass, "Glass")
	for i = 0, 7 do
		local f = i / 7
		local p = disc("ParfaitGlass", gx, 1.75 + f * 2.8, gz, 0.7 + f * 2.5, 0.42, Color3.fromRGB(196, 210, 232))
		p.transparency = 0.7
	end
	disc("ParfaitLip", gx, 4.6, gz, 3.3, 0.08, Color3.fromRGB(240, 246, 255), "Glass")
	local layers = {
		{ y0 = 1.65, y1 = 2.25, col = cream, g = "scoop4" },
		{ y0 = 2.25, y1 = 2.95, col = Color3.fromRGB(110, 66, 40), g = "scoop3" },
		{ y0 = 2.95, y1 = 3.75, col = cream, g = "scoop2" },
		{ y0 = 3.75, y1 = 4.45, col = Color3.fromRGB(236, 196, 120), g = "scoop2" },
	}
	for _, l in layers do
		local ym = (l.y0 + l.y1) / 2
		local f = (ym - 1.75) / 2.8
		disc("ParfaitLayer", gx, ym, gz, (0.7 + f * 2.5) * 0.86, l.y1 - l.y0, l.col, nil, l.g)
	end
	part("ParfaitDome", "Ellipsoid", V(2.4, 1.3, 2.4), C(gx, 4.75, gz), cream, nil, "scoop1")
	part("ParfaitBiscuit", "Ellipsoid", V(1.3, 0.9, 1.1), C(gx + 0.2, 5.4, gz) * CFrame.Angles(0.3, 0.4, 0.5), Color3.fromRGB(214, 150, 70), nil, "scoop1")
	part("ParfaitLeaf", "Ellipsoid", V(0.6, 0.08, 0.3), C(gx - 0.4, 5.55, gz - 0.2) * CFrame.Angles(0.2, 1, 0.3), Color3.fromRGB(110, 170, 80), nil, "scoop1")
	cup(-5, 11)

	-- top right: the cherry tart, in six sectors that can vanish one by one
	-- (sector 1 at 12 o'clock, then clockwise on screen: towards -X)
	plate(-11, 9, 4.4)
	disc("TartCrust", -11, 0.65, 9, 7.0, 0.9, biscuit, nil, "tartBase")
	disc("TartCream", -11, 1.15, 9, 6.4, 0.2, cream, nil, "tartBase")
	local function sectorOf(dx: number, dz: number): number
		local ang = math.deg(math.atan2(-dx, dz)) % 360 -- 0 at +Z, clockwise towards -X
		return math.floor(((ang + 30) % 360) / 60) + 1
	end
	local rr = Util.rng(31)
	for i = 1, 34 do
		local a = i * 2.4
		local d = math.sqrt(i / 34) * 2.7
		local dx, dz = math.cos(a) * d, math.sin(a) * d
		local g = "tart" .. sectorOf(dx, dz)
		part("Cherry", "Ball", V(0.8, 0.72, 0.8), C(-11 + dx, 1.55, 9 + dz) * CFrame.Angles(0, Util.randRange(rr, 0, 6), 0), cherry, nil, g)
		part("Shine", "Ball", V(0.18, 0.1, 0.12), C(-11 + dx - 0.15, 1.88, 9 + dz - 0.15), Color3.fromRGB(255, 200, 200), nil, g)
	end
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local dx, dz = math.cos(a) * 3.2, math.sin(a) * 3.2
		part("Piping", "Ball", V(0.55, 0.5, 0.55), C(-11 + dx, 1.4, 9 + dz), cream, nil, "tart" .. sectorOf(dx, dz))
	end

	-- bottom right: two plates of profiteroles
	for _, c in { { x = -8, z = -7 }, { x = -13, z = -10 } } do
		plate(c.x, c.z, 2.8)
		for i = 0, 3 do
			local a = i * 1.7
			local px, pz = c.x + math.cos(a) * 1.0, c.z + math.sin(a) * 1.0
			part("Puff", "Ball", V(1.2, 1.0, 1.2), C(px, 0.75, pz), Color3.fromRGB(214, 160, 96))
			part("PuffCream", "Ellipsoid", V(0.9, 0.3, 0.9), C(px, 1.05, pz), cream)
		end
		part("PuffTop", "Ball", V(1.1, 0.95, 1.1), C(c.x, 1.55, c.z), Color3.fromRGB(214, 160, 96))
		part("Sugar", "Ellipsoid", V(1.0, 0.25, 1.0), C(c.x, 2.0, c.z), Color3.fromRGB(252, 252, 252))
	end

	-- the strawberry sponge slice that vanishes in three vertical cuts
	-- (seen from -Z: screen left is +X, so cake1 is the +X third)
	plate(-52, 18, 3.0)
	for i = 1, 3 do
		local x = -52 + (2 - i) * 0.8
		local g = "cake" .. i
		local yy = 0.2
		for _, l in { { h = 0.6, col = sponge }, { h = 0.25, col = cream }, { h = 0.2, col = berry }, { h = 0.6, col = sponge }, { h = 0.35, col = cream } } do
			part("Sponge", "Block", V(0.8, l.h, 2.2), C(x, yy + l.h / 2, 18), l.col, nil, g)
			yy += l.h
		end
		part("CakeBerry", "Ellipsoid", V(0.6, 0.7, 0.6), C(x, yy + 0.3, 17.7), berry, nil, if i == 3 then "cake4" else g)
	end

	-- off to the side (+X, -Z): three plates of cheesecake / cake slices
	for i, c in { { x = 26, z = -14 }, { x = 31, z = -18 }, { x = 22, z = -20 } } do
		plate(c.x, c.z, 2.6)
		part("CheeseSlice", "Wedge", V(1.6, 1.1, 2.6), C(c.x, 0.75, c.z) * CFrame.Angles(0, i * 1.9, 0), if i == 2 then choc else Color3.fromRGB(250, 226, 160))
		part("SliceTop", "Wedge", V(1.62, 0.12, 2.62), C(c.x, 1.36, c.z) * CFrame.Angles(0, i * 1.9, 0), if i == 2 then pink else berry)
	end

	-- the macaron tart and a yellow cake (fast pan)
	plate(20, 4, 3.4)
	disc("MacTartCrust", 20, 0.6, 4, 5.2, 0.8, biscuit)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		disc("Macaron", 20 + math.cos(a) * 1.6, 1.25, 4 + math.sin(a) * 1.6, 1.0, 0.5, ({ pink, lime, yellow })[i % 3 + 1])
	end
	plate(25, 8, 3.0)
	part("YellowCake", "Block", V(2.2, 1.8, 2.2), C(25, 1.1, 8), yellow)
	part("YellowTop", "Ball", V(0.7, 0.6, 0.7), C(25, 2.25, 8), berry)

	-- in the dark: a chocolate cake with candles and a row of cupcakes
	disc("ChocCake", -26, 1.3, -6, 5, 2.4, choc)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		part("Candle", "Cylinder", V(1.2, 0.2, 0.2), C(-26 + math.cos(a) * 1.4, 3.1, -6 + math.sin(a) * 1.4) * up, cream)
		part("Flame", "Ball", V(0.22, 0.4, 0.22), C(-26 + math.cos(a) * 1.4, 3.85, -6 + math.sin(a) * 1.4), Color3.fromRGB(255, 200, 90), "Neon")
	end
	for i = 1, 4 do
		local x = -31 - (i - 1) * 2.6
		disc("Cupcake", x, 0.6, -6, 1.8, 1.1, Color3.fromRGB(246, 242, 232), nil, "cup" .. i)
		part("Frosting", "Ball", V(1.9, 1.4, 1.9), C(x, 1.55, -6), yellow, nil, "cup" .. i)
	end
	return vanish
end

function Part3.build(scene: Builder.Scene)
	local pal = scene.style.color
	local red = Color3.fromRGB(236, 34, 52)
	local h: P3 = {
		blackBolts = FX.bolts(scene, "P3BlackBolts", Color3.fromRGB(14, 4, 8), 40),
		redBolts = FX.bolts(scene, "P3RedBolts", red, 48),
		bigSmoke = FX.burst(scene, "P3Smoke", Color3.fromRGB(18, 16, 24), 30, "Ball", 81),
		steam = FX.burst(scene, "P3Steam", Color3.fromRGB(236, 240, 246), 16, "Ball", 82),
		flakes = FX.burst(scene, "P3Flakes", Color3.fromRGB(232, 234, 240), 30, "Block", 83),
		vanish = dessertSet(scene),
		rikaParts = {},
		fingers = {},
		fist = Builder.part(scene, "RyuLoose", V(0.52, 0.5, 0.46), C(0, -0.5, -0.05), pal.rSkin, { shape = "Ellipsoid", rig = "RyuLoose", bone = "RightHand", transparency = 1, castShadow = false, name = "Fist" }),
		hood = Builder.fx(scene, "P3Hood", "Ellipsoid", V(1.6, 1.7, 1.6), pal.rCoat, "Fabric", 0, "Hood"),
		hoodFur = {},
		columns = {},
		flash = FX.core(scene, "P3Flash", Color3.fromRGB(255, 252, 248)),
		redGlow = FX.core(scene, "P3RedGlow", red),
		void = Builder.fx(scene, "P3Void", "Block", V(1, 1, 1), Color3.new(0, 0, 0), "SmoothPlastic", 0, "Void"),
		slabs = {},
		stones = {},
		yBlood = {},
		streaks = {},
		yHand = {},
		yHandRig = {},
		yCollar = {},
		lamp = Builder.fx(scene, "P3Lamp", "Ball", V(0.2, 0.2, 0.2), Color3.new(1, 1, 1), "SmoothPlastic", 1, "Lamp"),
		redBack = redBackdrop(scene),
		speed = speedPlate(scene),
		redShards = FX.burst(scene, "P3RedShards", Color3.fromRGB(236, 30, 50), 30, "Wedge", 84),
	}
	Builder.light(scene, "P3Lamp", "Point", h.lamp, Color3.fromRGB(255, 238, 214), 30)
	for _, p in h.bigSmoke.parts do
		p.material = "SmoothPlastic"
	end
	for _, p in h.steam.parts do
		p.material = "SmoothPlastic"
	end
	for _, p in h.blackBolts.segs do
		p.material = "SmoothPlastic"
	end
	-- the red lightning and shards are all red (no white-hot segments)
	for _, p in h.redBolts.segs do
		p.color = red
	end
	for _, p in h.redShards.parts do
		p.color = Color3.fromRGB(220, 24, 44)
	end
	for i = 1, 12 do
		h.hoodFur[i] = Builder.fx(scene, "P3Hood", "Ellipsoid", V(0.3, 0.7, 0.3), pal.rFur, "Fabric", 0, "HoodFur")
	end
	for i = 1, 2 do
		h.columns[i] = Builder.fx(scene, "P3Air", "Cylinder", V(1, 1, 1), Color3.fromRGB(236, 244, 255), "Neon", 0.5, "AirColumn")
	end
	local r = Util.rng(404)
	for i = 1, 26 do
		local col = Util.mix(Color3.fromRGB(104, 112, 142), Color3.fromRGB(150, 158, 186), Util.rand(r))
		h.slabs[i] = Builder.fx(scene, "P3Slabs", "Block", V(1, 1, 1), col, "Concrete", 0, "Slab")
	end
	for i = 1, 18 do
		h.stones[i] = Builder.fx(scene, "P3Stones", "Block", V(1, 1, 1), Color3.fromRGB(70, 78, 112), "SmoothPlastic", 0, "Stone")
	end
	for i = 1, 6 do
		h.yBlood[i] = Builder.fx(scene, "P3YBlood", "Ellipsoid", V(1, 1, 1), Color3.fromRGB(140, 14, 24), "SmoothPlastic", 0, "Blood")
	end
	-- Yuta's right hand for the close-up at 14.1: palm, four fingers in three
	-- joints, a thumb in two, bruises round the wrist (the rig's own flat
	-- hand is hidden in that shot)
	local function handPart(shape: string, col: Color3, name: string)
		local q = Builder.fx(scene, "P3YHand", shape, V(1, 1, 1), col, "SmoothPlastic", 0, name)
		q.castShadow = false
		table.insert(h.yHand, q)
	end
	handPart("Block", pal.skin, "Palm") -- 1
	for _ = 1, 4 do
		for _ = 1, 3 do
			handPart("Block", pal.skin, "Finger")
		end
	end -- 2..13
	handPart("Block", pal.skin, "Thumb")
	handPart("Block", pal.skin, "Thumb") -- 14..15
	for i = 1, 4 do
		handPart("Block", if i % 2 == 0 then Color3.fromRGB(184, 142, 156) else Color3.fromRGB(198, 160, 168), "Bruise")
	end -- 16..19
	for i = 1, 16 do
		h.streaks[i] = Builder.fx(scene, "P3Streaks", "Ellipsoid", V(1, 1, 1), if i % 3 == 0 then Color3.fromRGB(100, 8, 18) else Color3.fromRGB(168, 18, 30), "SmoothPlastic", 0, "BloodStreak")
		h.streaks[i].castShadow = false
	end
	for _, p in scene.parts do
		if p.rig == "Yuta" and p.bone == "RightHand" then
			table.insert(h.yHandRig, p)
		elseif p.rig == "Yuta" and p.name == "CollarPanel" then
			table.insert(h.yCollar, p)
		end
		if p.rig == "Rika" then
			table.insert(h.rikaParts, p)
		elseif p.rig == "RyuLoose" and p.bone == "RightHand" and (p.name == "Finger" or p.name == "Thumb") then
			table.insert(h.fingers, p)
		end
	end
	scene.data.p3 = h
end

---------------------------------------------------------------------------
-- poses and helpers
-- Rig.R signs: torso / head: -x bends forward (looks down), +x leans back
-- (looks up); +y turns to the character's left; +z tilts to its left.
-- Arms and legs hang down: +x swings them forward; a right arm goes out
-- sideways with +z, a left arm with -z; elbows bend with +x, knees with -x.
---------------------------------------------------------------------------
local guard: Rig.Pose = {
	LowerTorso = R(-4, 0, 0),
	UpperTorso = R(-10, 0, 0),
	Head = R(-6, 0, 0),
	RightUpperArm = R(40, 0, 20),
	RightLowerArm = R(100, 0, 0),
	LeftUpperArm = R(50, 0, -20),
	LeftLowerArm = R(100, 0, 0),
	LeftUpperLeg = R(24, 0, -8),
	LeftLowerLeg = R(-24, 0, 0),
	RightUpperLeg = R(-18, 0, 8),
	RightLowerLeg = R(-6, 0, 0),
}

-- right straight, the whole body behind it
local punchR: Rig.Pose = {
	LowerTorso = R(-6, 20, 0),
	UpperTorso = R(-12, 26, 0),
	Head = R(-4, -24, 0),
	RightUpperArm = R(90, 0, 4),
	RightLowerArm = R(4, 0, 0),
	LeftUpperArm = R(40, 0, -24),
	LeftLowerArm = R(110, 0, 0),
	LeftUpperLeg = R(36, 0, -8),
	LeftLowerLeg = R(-36, 0, 0),
	RightUpperLeg = R(-28, 0, 8),
	RightLowerLeg = R(-10, 0, 0),
}

-- right arm drawn back for a big swing, the body turned away
local windupR: Rig.Pose = {
	LowerTorso = R(-4, -16, 0),
	UpperTorso = R(-8, -26, 0),
	Head = R(-6, 24, 0),
	RightUpperArm = R(-40, 0, 40),
	RightLowerArm = R(100, 0, 0),
	LeftUpperArm = R(60, 0, -14),
	LeftLowerArm = R(40, 0, 0),
	LeftUpperLeg = R(30, 0, -8),
	LeftLowerLeg = R(-30, 0, 0),
	RightUpperLeg = R(-24, 0, 8),
}

-- mirror a joint rotation / pose left <-> right (reflection across the X axis)
local function mirrorCF(cf: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end
local function mirror(p: Rig.Pose): Rig.Pose
	local out: Rig.Pose = {}
	for k, v in p do
		local key = if string.sub(k, 1, 4) == "Left" then "Right" .. string.sub(k, 5) elseif string.sub(k, 1, 5) == "Right" then "Left" .. string.sub(k, 6) else k
		out[key] = mirrorCF(v)
	end
	return out
end

-- a punch over time: wind-up, a fast strike that overshoots, a settle back
local function punchK(t: number, t0: number, dur: number): number
	local u = (t - t0) / dur
	if u < 0 then
		return 0
	elseif u < 0.35 then
		return -0.25 * Util.smoothstep(0, 0.35, u)
	elseif u < 0.55 then
		return -0.25 + 1.4 * Util.smoothstep(0.35, 0.55, u)
	end
	local s = u - 0.55
	return 1 + 0.15 * math.exp(-s * 10) * math.cos(s * 30) - 0.15 * Util.smoothstep(0.55, 1.2, u)
end
-- the same, timed so the blow lands exactly at `hit` (a punch `dur` long)
local function strikeK(t: number, hit: number, dur: number): number
	return punchK(t, hit - 0.55 * dur, dur)
end

local function punchPose(k: number, left: boolean?): Rig.Pose
	local p: Rig.Pose
	if k < 0 then
		p = Cast.mix(guard, windupR, -k * 4)
	else
		p = Cast.mix(guard, punchR, k)
	end
	return if left then mirror(p) else p
end

-- a hit: the head snaps away (pitch > 0 = thrown back, yaw > 0 = to his
-- left) with a little overshoot, the chest follows; dt = time since contact
local function hitPose(base: Rig.Pose, dt: number, yaw: number, pitch: number, roll: number?): Rig.Pose
	if dt < 0 then
		return base
	end
	local a = math.exp(-dt * 5) * math.sin(math.min(dt * 18, math.pi / 2)) + (1 - math.exp(-dt * 5)) * 0.6
	local p = Cast.add(base, "Head", R(pitch * a, yaw * a, (roll or 0) * a))
	return Cast.add(p, "UpperTorso", R(pitch * 0.3 * a, yaw * 0.35 * a, 0))
end

-- Ryu's face running with blood (painted on the face)
local function bloodFace(ctx: Timeline.Ctx)
	ctx:show("ryu:blood")
end

local function field(ctx: Timeline.Ctx, mist: string?)
	Common.sky(ctx, mist or "wisps", 30)
end

local function grade(ctx: Timeline.Ctx, b: number, c: number, s: number, tint: Color3?)
	Common.grade(ctx, b, c, s, tint)
end

local function shake(cf: CFrame, t: number, amp: number, f: number?): CFrame
	return Clash.shake(cf, t, amp, f)
end

-- camera from `eye` on `target`, optional shake, depth of field on the target
local function cam(ctx: Timeline.Ctx, eye: Vector3, target: Vector3, fov: number, amp: number?, dof: number?, up: Vector3?)
	local cf = Util.lookAt(eye, target, up)
	if amp and amp > 0 then
		cf = shake(cf, ctx.t, amp, 16)
	end
	ctx:camera(cf, fov)
	ctx:focus((target - eye).Magnitude, dof or 1)
end

local function yutaRoot(): CFrame
	return C(YUTA) * CFrame.Angles(0, math.pi, 0)
end

-- Ryu's open right hand closes into a fist (k 0..1)
local function fist(ctx: Timeline.Ctx, k: number)
	local h = h3(ctx)
	for _, p in h.fingers do
		ctx:prop(p, { t = math.clamp(k * 2 - 0.6, 0, 1) })
	end
	ctx:prop(h.fist, { t = 1 - math.clamp(k * 2 - 0.4, 0, 1) })
end

-- Ryu's right forearm sweeping across the frame in front of `focus`, from
-- screen left (s = 0) to screen right (s = 1); his body stays off screen
local function armAcross(ctx: Timeline.Ctx, camPos: Vector3, focus: Vector3, s: number, near: number, drop: number)
	local fwd = (focus - camPos).Unit
	local right = fwd:Cross(V(0, 1, 0)).Unit
	local target = focus - fwd * near + right * (s * 1.6 - 0.8) - V(0, drop, 0)
	local root = Util.lookAt(target, target + right) * CFrame.new(0, 0, 3)
	Common.rigAt(ctx, "RyuLoose", CFrame.new(root.Position.X, RYU.Y, root.Position.Z) * root.Rotation, punchR, "RightLowerArm", C(0, -0.5, 0), target)
	fist(ctx, 1)
end

-- Rika's limbs and skull fading out as they crumble (they stay white)
local function rikaFade(ctx: Timeline.Ctx, fade: number)
	if fade <= 0 then
		return
	end
	for _, p in h3(ctx).rikaParts do
		ctx:prop(p, { t = math.max(p.transparency, fade) })
	end
end

-- a churning mass of black smoke round a point (k = size, spread in studs)
local function smokeAround(ctx: Timeline.Ctx, c: Vector3, k: number, spread: number, seed: number, rise: number?, col: Color3?, alpha: number?)
	for i, p in h3(ctx).bigSmoke.parts do
		local rr = Util.rng(seed + i)
		local ph = (ctx.lt * (0.15 + Util.rand(rr) * 0.12) + Util.rand(rr)) % 1
		local d = V(Util.randRange(rr, -1, 1), Util.randRange(rr, -0.6, 1), Util.randRange(rr, -1, 1)).Unit
		local pos = c + d * (0.4 + Util.rand(rr) * spread) * (0.7 + ph * 0.5) + V(0, ph * (rise or 2), 0)
		local sz = (1.2 + Util.rand(rr) * 2.2) * k * (0.8 + ph * 0.5)
		ctx:place(p, C(pos) * CFrame.Angles(i, i * 2, 0))
		ctx:prop(p, { s = V(sz, sz * 0.8, sz), t = (alpha or 0.25) + ph * ph * (1 - (alpha or 0.25)) * 0.95, c = col })
	end
end

-- small dark stones tumbling past, flowing along `flow`
local function stonesAround(ctx: Timeline.Ctx, c: Vector3, spread: number, flow: Vector3, seed: number, size: number?)
	for i, p in h3(ctx).stones do
		local rr = Util.rng(seed + i * 7)
		local ph = (ctx.lt * (0.5 + Util.rand(rr) * 0.6) + Util.rand(rr)) % 1
		local off = V(Util.randRange(rr, -1, 1), Util.randRange(rr, -1, 1), Util.randRange(rr, -1, 1)) * spread
		local pos = c + off + flow * (ph - 0.5)
		local s = (size or 0.35) * Util.randRange(rr, 0.5, 1.6)
		ctx:place(p, C(pos) * CFrame.Angles(ph * 9 + i, i, ph * 5))
		ctx:prop(p, { s = V(s, s * 0.8, s * 0.9) })
	end
end

-- big slabs of the broken deck tilted every which way (floating a little)
local function slabField(ctx: Timeline.Ctx, c: Vector3, radius: number, seed: number, float: number, broken: number?)
	local b = broken or 1
	for i, p in h3(ctx).slabs do
		local rr = rng(seed + i * 13)
		local a = Util.randRange(rr, 0, math.pi * 2)
		local d = math.sqrt(Util.rand(rr)) * radius
		local y = Util.randRange(rr, -0.6, 0.8) + float * Util.rand(rr) * (1 + math.sin(ctx.t * 2 + i) * 0.1)
		local pos = c + V(math.cos(a) * d, Util.lerp(-0.45, y, b), math.sin(a) * d)
		local w = Util.randRange(rr, 3, 7)
		ctx:place(p, C(pos) * CFrame.Angles(Util.randRange(rr, -0.6, 0.6) * b, a, Util.randRange(rr, -0.5, 0.5) * b))
		ctx:prop(p, { s = V(w, Util.randRange(rr, 0.7, 1.4), w * Util.randRange(rr, 0.6, 1.1)) })
	end
end

-- blood flung off in streaks (not round drops): each drop stretched along
-- its flight, thinning as it flies; `dir` the main direction, age seconds
local function bloodStreaks(ctx: Timeline.Ctx, origin: Vector3, dir: Vector3, age: number, seed: number)
	if age < 0 or age > 2.4 then
		return
	end
	local d0 = dir.Unit
	for i, p in h3(ctx).streaks do
		local rr = rng(seed * 31 + i)
		local spread = V(Util.randRange(rr, -1, 1), Util.randRange(rr, -1, 1), Util.randRange(rr, -1, 1)) * 0.55
		local v = (d0 + spread).Unit * Util.randRange(rr, 4, 9)
		local life = Util.randRange(rr, 0.8, 2.2)
		if age < life then
			local slow = (1 - math.exp(-age * 2.2)) / 2.2
			local pos = origin + v * slow + V(0, -1.6 * age * age, 0)
			local vel = v * math.exp(-age * 2.2) + V(0, -3.2 * age, 0)
			local len = math.clamp(vel.Magnitude * 0.07, 0.12, 0.7) * (1 - age / life * 0.5)
			local w = Util.randRange(rr, 0.05, 0.11) * (1 - age / life * 0.6)
			ctx:place(p, FX.along(pos, pos + vel.Unit * len))
			ctx:prop(p, { s = V(len, w, w) })
		end
	end
end

-- how far a finger is clenched (0 open .. 1 tight) in a cramp: a slow
-- clench and release plus quick irregular twitches, different per finger
local function cramp(t: number, f: number): number
	local slow = 0.5 + 0.35 * Util.noise1(t * 2.4 + f * 1.7, 40 + f)
	local twitch = 0.28 * Util.noise1(t * 13 + f * 3.1, 50 + f) + 0.14 * Util.noise1(t * 29 + f * 1.3, 60 + f)
	return math.clamp(slow + twitch, 0, 1)
end

-- Yuta's right hand as a clawed, cramping hand on the hand bone `hb`
-- (fingers along -Y, curling towards +Z), bruises on the wrist
local function crampHand(ctx: Timeline.Ctx, hb: CFrame, forearm: CFrame, t: number)
	local h = h3(ctx)
	for _, p in h.yHandRig do
		ctx:prop(p, { t = 1 })
	end
	local q = h.yHand
	local function put(i: number, cf: CFrame, size: Vector3)
		ctx:place(q[i], cf)
		ctx:prop(q[i], { s = size })
	end
	local palm = hb * C(0, -0.2, 0) * CFrame.Angles(math.rad(-8 * cramp(t, 4)), 0, 0)
	put(1, palm, V(0.42, 0.36, 0.2))
	for f = 0, 3 do
		local c = cramp(t, f)
		local spread = math.rad((f - 1.5) * (6 + 10 * (1 - c)))
		local cf = palm * C((f - 1.5) * 0.1, -0.18, 0) * CFrame.Angles(math.rad(-(12 + 36 * c)), 0, spread)
		local lens = if f == 0 or f == 3 then { 0.14, 0.1, 0.09 } else { 0.16, 0.12, 0.1 }
		for s, len in lens do
			put(2 + f * 3 + s - 1, cf * C(0, -len / 2, 0), V(0.088 - s * 0.006, len + 0.03, 0.094 - s * 0.006))
			cf = cf * C(0, -len, 0) * CFrame.Angles(math.rad(-(16 + 52 * c) * (if s == 2 then 1.2 else 1)), 0, 0)
		end
	end
	-- the thumb on the -x side of the right hand, folding in with the cramp
	local tc = cramp(t, 5)
	local th = palm * C(-0.2, -0.02, -0.04) * CFrame.Angles(math.rad(-20 * tc), 0, math.rad(-40 + 25 * tc))
	put(14, th * C(0, -0.08, 0), V(0.1, 0.18, 0.1))
	th = th * C(0, -0.16, 0) * CFrame.Angles(math.rad(-30 * tc), 0, 0)
	put(15, th * C(0, -0.07, 0), V(0.09, 0.15, 0.09))
	-- bruises: dark bands round the wrist and a long smudge up the forearm
	-- (each just wider than the arm, so it shows as a stain on the skin)
	put(16, forearm * C(0, -0.84, 0), V(0.415, 0.14, 0.435))
	put(17, forearm * C(0.05, -0.7, -0.012), V(0.32, 0.16, 0.44))
	put(18, forearm * C(-0.06, -0.56, 0.012), V(0.3, 0.2, 0.44))
	put(19, forearm * C(0.04, -0.4, -0.012), V(0.26, 0.12, 0.44))
end

-- the front of Yuta's tall collar folded down out of a close-up of his face
local function collarOpen(ctx: Timeline.Ctx)
	for _, p in h3(ctx).yCollar do
		local z = p.cf.Position.Z
		if z < -0.3 then
			ctx:prop(p, { t = 1 })
		elseif z < 0 then
			ctx:prop(p, { s = V(p.size.X, p.size.Y * 0.5, p.size.Z) })
		end
	end
end

-- the painted speed blur streaming past behind a flying fist: placed in front
-- of the camera, sliding across the view (dir +1 = to the left, -1 = right)
local function speedBlur(ctx: Timeline.Ctx, fov: number, u: number, dir: number, f: Vector3)
	local h = h3(ctx)
	local dist = 12
	local vh = 2 * dist * math.tan(math.rad(fov) / 2) * 1.25
	local vw = vh * 16 / 9
	local slide = (0.9 - 1.8 * u) * vw * dir
	local cf = ctx.frame.camera
	local pos = cf.Position + cf.LookVector * dist + cf.RightVector * slide
	ctx:place(h.speed, Util.lookAt(pos, pos - cf.LookVector, cf.UpVector))
	ctx:prop(h.speed, { s = V(vw * 3, vh, 0.05) })
	Common.streamers(ctx, h2(ctx).streamers, f + cf.LookVector * 4, cf.RightVector * -dir, 3.0, 4.5, 260, 0.9)
end

-- a white flash of light at a point
local function flashAt(ctx: Timeline.Ctx, pos: Vector3, r: number, k: number)
	FX.placeCore(ctx, h3(ctx).flash, pos, r, k)
end

-- red-black lightning crackling round a centre
local function blackLightning(ctx: Timeline.Ctx, c: Vector3, radius: number, k: number, seed: number)
	local h = h3(ctx)
	local ri, bi = 1, 1
	for i = 1, 12 do
		local rr = rng(seed + i * 5 + math.floor(ctx.t * 18))
		local d = V(Util.randRange(rr, -1, 1), Util.randRange(rr, -0.8, 1), Util.randRange(rr, -1, 1)).Unit
		local a = c + d * Util.randRange(rr, 0.2, 0.9) * radius * 0.3
		local b = c + d * Util.randRange(rr, 0.6, 1.3) * radius * k
		ri = FX.placeBolt(ctx, h.redBolts, ri, a, b, 4, 0.35 * radius * 0.2, 0.09, seed + i, 18)
		if i % 2 == 0 then
			bi = FX.placeBolt(ctx, h.blackBolts, bi, a, c + d * radius * 0.9 * k + V(0, 0.3, 0), 4, 0.3 * radius * 0.2, 0.16, seed + i + 50, 18)
		end
	end
end

---------------------------------------------------------------------------
-- shots (compositions: docs/part3_frames.md)
---------------------------------------------------------------------------

-- 2.633: low and far behind Ryu, looking up: Rika looms over him facing the
-- camera, her right hand (screen left) clamped on his head, her other arm
-- out to the side, claws opening; Yuta at Ryu's side, hands on his belly.
-- Steam bursts from her jaws (3.6); her body tears apart into black smoke
-- (4.2-6.5) while her limbs and skull stay white. The camera tilts up.
local function rikaHold(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local t, u = ctx.t, ctx.u
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({
		UpperTorso = R(-8, 0, 0),
		Head = R(-22, 0, 0),
		RightUpperArm = R(8, 0, 80),
		RightLowerArm = R(24, 0, 0),
		LeftUpperArm = R(8, 0, -80),
		LeftLowerArm = R(24, 0, 0),
		LeftUpperLeg = R(8, 0, -6),
		RightUpperLeg = R(-6, 0, 6),
	}, t))
	local belly = (rb.UpperTorso * C(0.35, 0.35, -0.65)).Position
	Common.rigAt(ctx, "Yuta", C(RYU + V(2.4, 0, -0.4)) * CFrame.Angles(0, math.rad(105), 0), Cast.alive({
		UpperTorso = R(-18, 0, 0),
		Head = R(-12, 0, 0),
		LeftUpperArm = R(62, 0, 4),
		LeftLowerArm = R(26, 0, 0),
		RightUpperArm = R(56, 0, -6),
		RightLowerArm = R(36, 0, 0),
		LeftUpperLeg = R(26, 0, 0),
		LeftLowerLeg = R(-20, 0, 0),
		RightUpperLeg = R(-14, 0, 0),
	}, t), "LeftHand", C(0, -0.35, 0), belly)
	-- Rika writhes as her body tears apart: she heaves and twists, her head
	-- jerks down (3.35), snaps back with the burst of steam (3.6) and then
	-- thrashes from side to side screaming; her free arm swings up and out,
	-- the claw clenching and spreading; the arm on Ryu's head shudders
	local open = Util.smoothstep(4.5, 6.3, t)
	local jerk = Util.smoothstep(3.3, 3.42, t) * (1 - Util.smoothstep(3.55, 3.7, t))
	local snap = Util.smoothstep(3.55, 3.75, t)
	local thrash = Util.smoothstep(4.0, 4.6, t)
	local heave = math.sin((t - 2.633) * math.pi * 2 * 1.3)
	local n1 = Util.noise1(t * 2.2, 71)
	local n2 = Util.noise1(t * 3.1, 72)
	local n3 = Util.noise1(t * 9, 73)
	local swing = Util.smoothstep(3.9, 4.5, t) - 0.7 * Util.smoothstep(4.7, 5.4, t)
	local loom: Rig.Pose = {
		HumanoidRootPart = C(0.3 * n1 * thrash, 1.5 + 0.25 * heave, 0),
		LowerTorso = R(-30 + 4 * heave, 8 * n2 * thrash, 0),
		UpperTorso = R(-48 + 7 * heave - 10 * snap + 8 * thrash * n1, 14 * n2 * thrash, 10 * n1 * thrash),
		Head = R(34 - 18 * jerk - 30 * snap + 22 * thrash * n2 + 3 * n3, 22 * jerk + 34 * thrash * n1, -14 * jerk + 18 * thrash * n2),
		RightUpperArm = R(70 + 3 * n3 + 4 * heave, 0, 8 + 3 * n3),
		RightLowerArm = R(12 + 4 * n3, 0, 0),
		RightHand = R(30 + 5 * n3, 0, 0),
		LeftUpperArm = R(14 + 70 * swing + 12 * n2, 0, -58 - 34 * swing + 10 * n1),
		LeftLowerArm = R(70 - open * 30 - 30 * swing + 14 * n3, 0, 0),
		LeftHand = R(40 - open * 50 + 25 * math.max(0, Util.noise1(t * 6, 74)), 0, 0),
		LeftUpperLeg = R(30 + 10 * heave, 0, 10 + 14 * n1),
		LeftLowerLeg = R(-30 + 12 * n2, 0, -14),
		LeftFoot = R(-30 + 16 * n1, 0, -24),
	}
	local top = (rb.Head * C(0, 1.25, 0)).Position
	local kb = Common.rigAt(ctx, "Rika", C(RYU + V(2.5, 0, -6.5)) * CFrame.Angles(0, math.pi - 0.25, 0), loom, "RightHand", C(0, -1.3, 0), top + V(0, 0.4, 0))
	Common.rikaEye(ctx, kb, 1)
	ctx:gust(0.8 + 1.4 * thrash)
	-- steam bursting from her jaws, billowing off to the right
	local mouth = (kb.Head * C(0, 0.4, -1.9)).Position
	if t > 3.55 then
		FX.placeBurst(ctx, h.steam, mouth, (t - 3.55) % 1.4, 7, 2.8, 1.4, V(1, 0.3, 0.4), 0.5, -1.2)
	end
	-- the dark body tearing into black smoke
	local tear = Util.smoothstep(4.0, 6.4, t)
	smokeAround(ctx, kb.UpperTorso.Position + V(0, -1.0, -2.2), 0.5 + tear * 1.4, 2 + tear * 6, 700, 1.0)
	local rise = Util.smoothstep(2.633, 6.533, t)
	cam(ctx, RYU + V(5.0, 1.6, 21 + u * 1.2), RYU + V(3.2, 9.2 + rise * 3.6, -3), 35, 0.03 + 0.05 * thrash, 0.3)
	ctx:wind(1.3)
	grade(ctx, -0.04, 0.2, 0.05, Color3.fromRGB(200, 214, 245))
	field(ctx, "low")
end

-- 6.533: Ryu's bowed head close up (the fringe fills the frame, blood
-- below it); 7.3 his head comes up: blank white eyes, blood streaming down,
-- a bloody grin, the head tilted
local function ryuLifts(ctx: Timeline.Ctx)
	local t = ctx.t
	local lift = Util.smoothstep(7.28, 7.5, t)
	local breath = math.sin((t - 6.533) * 3) * 0.5 + 0.5
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({
		UpperTorso = R(-16 + lift * 10 - breath * 2, 0, 0),
		Head = R(-42 + lift * 44, lift * -6, lift * 12),
	}, t))
	Cast.expr(ctx, "ryu", "berserk")
	bloodFace(ctx)
	local head = rb.Head * C(0, 0.75, 0)
	local push = Util.smoothstep(6.533, 7.8, t)
	local eye = (C(RYU) * C(0.25, 4.9 + lift * 0.4, -3.1 + push * 0.5)).Position
	local cf = Util.lookAt(eye, head.Position + V(0, -0.15 + lift * 0.1, 0)) * CFrame.Angles(0, 0, math.rad(-8 * lift))
	ctx:camera(cf, 40)
	ctx:focus((head.Position - eye).Magnitude, 1)
	ctx:wind(1.2)
	grade(ctx, -0.14, 0.3, -0.05, Color3.fromRGB(215, 205, 225))
	field(ctx)
end

-- Rika for her close-ups: looming forward over the camera
local function rikaClose(ctx: Timeline.Ctx, nod: number, turn: number): { [string]: CFrame }
	return ctx:rig("Rika", C(RYU + V(0, 0, -7)) * CFrame.Angles(0, math.pi, 0), Cast.alive({
		HumanoidRootPart = C(0, 1.5, 0),
		UpperTorso = R(-30, 0, 0),
		Head = R(-18 + nod, turn, 0),
		RightUpperArm = R(30, 0, 20),
		LeftUpperArm = R(30, 0, -20),
		LeftUpperLeg = R(20, 0, 0),
	}, ctx.t))
end

-- 7.8: Rika's grinning skull from below, dark
local function rikaMask(ctx: Timeline.Ctx)
	local kb = rikaClose(ctx, 0, 0)
	local face = kb.Head * C(0, 1.0, -1.6)
	cam(ctx, face.Position + kb.Head.LookVector * 3.2 - kb.Head.UpVector * 1.6, face.Position + kb.Head.UpVector * 0.25, 50, 0.05, 1)
	ctx:place(h3(ctx).lamp, C(face.Position + kb.Head.LookVector * 5 - kb.Head.UpVector * 2))
	ctx:light("P3Lamp", 3, Color3.fromRGB(220, 230, 255), 24)
	grade(ctx, -0.12, 0.4, -0.2, Color3.fromRGB(170, 186, 240))
	ctx:fog(0.3)
end

-- 8.033: Ryu's fist smashes into her skull: a white flash, his black sleeve
-- a smear across the right of the frame
local function punchMask(ctx: Timeline.Ctx)
	local t = ctx.t
	local k = Util.smoothstep(8.033, 8.1, t)
	local snap = Util.smoothstep(8.1, 8.2, t)
	local kb = rikaClose(ctx, 25 * snap, 25 * snap)
	local face = (kb.Head * C(0, 1.0, -1.7)).Position
	Common.rigAt(ctx, "RyuLoose", C(RYU), Cast.mix(windupR, punchR, k), "RightHand", C(0, -0.4, 0), face + V(0, 0, 1.4 - k * 1.2))
	fist(ctx, 1)
	flashAt(ctx, face + V(1.4, 1.2, -1.6), 1.0 + k * 0.4, 0.75)
	cam(ctx, face + V(-3.0, -1.2, 2.2), face + V(0.9, -0.5, 1.6), 46, 0.6, 0.5)
	grade(ctx, -0.32, 0.4, -0.1, Color3.fromRGB(170, 180, 230))
	ctx:fog(0.5)
	ctx:bloom(1.4)
end

-- 8.2: Yuta's startled face (eyes wide, hair whipped by the blow's wind);
-- 8.4: closer and lower, his ringed left hand at his chin, Ryu's sleeve
-- rushing past in front of him
local function yutaStartle(ctx: Timeline.Ctx)
	local t = ctx.t
	local ring = t >= 8.4
	local yb = ctx:rig("Yuta", yutaRoot(), Cast.alive({
		UpperTorso = R(4, -10, 0),
		Head = R(4, -24 + (t - 8.2) * 30, 0),
		LeftUpperArm = R(if ring then 140 else 30, 0, if ring then 24 else -10),
		LeftLowerArm = R(if ring then 130 else 30, 0, 0),
		LeftHand = R(-10, 0, 0),
	}, t))
	Cast.expr(ctx, "yuta", "startle")
	local head = yb.Head * C(0, 0.55, 0)
	if not ring then
		cam(ctx, head:PointToWorldSpace(V(1.5, 0.55, -2.0)), head.Position + V(0, 0.05, 0), 42, 0.05, 1)
	else
		local camPos = head:PointToWorldSpace(V(-1.0, -0.15, -1.7))
		local focus = head:PointToWorldSpace(V(-0.45, -0.25, 0))
		cam(ctx, camPos, focus, 44, 0.1, 1)
		armAcross(ctx, camPos, focus, 0.2 + Util.smoothstep(8.4, 8.533, t) * 0.4, 0.35, 0.45)
	end
	ctx:gust(2.4)
	grade(ctx, 0.02, 0.26, 0.08, Color3.fromRGB(210, 222, 255))
	field(ctx)
end

-- 8.533: a whip pan after Ryu as he lunges; 8.85-10.5 the held side view in
-- slow motion: Rika's skull huge at the left (nearest the camera), her body
-- a torn mass of black smoke, her long right arm reaching across the top,
-- the other hand clawing low; Ryu in mid-air in the middle, his right fist
-- buried in her, one knee up; Yuta flung off to the right, back first, arms
-- up; drops of blood hanging between them
local function rikaPunched(ctx: Timeline.Ctx)
	local hh = h2(ctx)
	local t = ctx.t
	local slow = math.max(0, t - 8.85)
	local rroot = C(RYU + V(0, 3.2, slow * 0.25)) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(-12), 0, 0)
	local rpose = Cast.add(Cast.add(punchR, "RightUpperLeg", R(60, 0, 0)), "RightLowerLeg", R(-80, 0, 0))
	local rb = ctx:rig("RyuLoose", rroot, Cast.alive(rpose, t))
	fist(ctx, 1)
	Cast.expr(ctx, "ryu", "berserk")
	bloodFace(ctx)
	local f = (rb.RightHand * C(0, -0.4, 0)).Position
	local kb = ctx:rig("Rika", C(RYU + V(8, -4.6, 7.0)) * CFrame.Angles(0, math.rad(25), 0), Cast.alive({
		HumanoidRootPart = C(0, 1.2 + slow * 0.2, 0),
		LowerTorso = R(-10, 0, 0),
		UpperTorso = R(-14, 0, 6),
		Head = R(24, 10, 0),
		RightUpperArm = R(112, 0, 6),
		RightLowerArm = R(8, 0, 0),
		RightHand = R(-10, 0, 0),
		LeftUpperArm = R(26, 0, -12),
		LeftLowerArm = R(70, 0, 0),
		LeftHand = R(40, 0, 0),
		LeftUpperLeg = R(40, 0, 0),
		LeftLowerLeg = R(-50, 0, 0),
	}, t))
	smokeAround(ctx, kb.UpperTorso.Position + V(-3, 0.5, -2.0), 1.5, 4.5, 760, 0.6)
	local fly = math.max(0, t - 8.6)
	local yz = -4 - (1 - math.exp(-fly * 3)) * 7 - slow * 0.4
	ctx:rig("Yuta", C(RYU + V(0, 3.4, yz)) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(35), 0, 0), Cast.alive({
		UpperTorso = R(18, 0, 0),
		Head = R(20, 0, 0),
		RightUpperArm = R(150, 0, 20),
		RightLowerArm = R(30, 0, 0),
		LeftUpperArm = R(140, 0, -24),
		LeftLowerArm = R(40, 0, 0),
		LeftUpperLeg = R(30, 0, 0),
		LeftLowerLeg = R(-70, 0, 0),
		RightUpperLeg = R(-10, 0, 0),
		RightLowerLeg = R(-40, 0, 0),
	}, t))
	FX.placeBurst(ctx, hh.blood, f + V(0, 0.4, -1.2), 0.25 + slow * 0.12, 9, 0.3, 1.8, V(0, 0.35, -1), 0.9, 0.5)
	if t < 8.85 then
		local k = Util.smoothstep(8.533, 8.85, t)
		cam(ctx, rb.UpperTorso.Position + V(5, 0.3, -1.5 + k * 3), rb.UpperTorso.Position + V(0, 0, k * 1.5), 50, 0.5, 0.5)
	else
		cam(ctx, RYU + V(18, 4.4, -2.2 - slow * 0.3), RYU + V(0, 5.6, -2.2 - slow * 0.3), 52, 0.04, 0.4)
	end
	ctx:gust(1.6)
	ctx:wind(1.6)
	grade(ctx, -0.02, 0.22, 0.05, Color3.fromRGB(205, 218, 255))
	field(ctx, "low")
end

-- 10.5: right behind his left shoulder, deep in the fur: his face in
-- silhouette at the edge, looking away; 11.3 he turns his head back toward
-- us, tilted, blank eyes, a clenched bloody grin
local function ryuFur(ctx: Timeline.Ctx)
	local t = ctx.t
	local turn = Util.smoothstep(11.15, 11.45, t)
	local breath = math.sin((t - 10.5) * 2.4) * 2
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({
		UpperTorso = R(-6 + breath, 10 * turn, 0),
		Head = R(-18 + turn * 8, -40 + turn * 110, turn * -18),
	}, t))
	Cast.expr(ctx, "ryu", "berserk")
	bloodFace(ctx)
	local head = rb.Head * C(0, 0.75, 0)
	local eye = (C(RYU) * C(-3.0, 6.9, 2.2)).Position
	local look = head.Position + V(0.7 - turn * 0.5, -0.3, -0.5 + turn * 0.2)
	cam(ctx, eye, look, 34, 0, 1)
	ctx:focus((head.Position - eye).Magnitude, 1)
	ctx:wind(1.6)
	grade(ctx, -0.04, 0.26, 0, Color3.fromRGB(205, 218, 250))
	field(ctx)
end

-- 12.0: straight down on the concrete: Rika's skull drops past, she crashes
-- onto her back; her white limbs twitch and crumble into flakes in a churning
-- dark smoke ("Yuta!" - her voice, off screen)
local function rikaDown(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local t = ctx.t
	local base = RYU + V(-8, 0, 8)
	local fall = Util.smoothstep(12.0, 12.45, t)
	local twitch = math.sin(t * 21) * 7 * Util.smoothstep(12.5, 12.7, t) * (1 - Util.smoothstep(13.6, 14.1, t))
	ctx:rig("Rika", C(base + V(0, 1.0 + (1 - fall) * 14, 0)) * CFrame.Angles(math.rad(90), math.rad(20), 0), {
		UpperTorso = R(0, 0, 14),
		Head = R(-10, 30, 0),
		RightUpperArm = R(40 + twitch, 0, 70),
		RightLowerArm = R(50, 0, 0),
		RightHand = R(30 - twitch, 0, 0),
		LeftUpperArm = R(70 - twitch, 0, -80),
		LeftLowerArm = R(40, 0, 0),
		LeftHand = R(20, 0, 0),
		LeftUpperLeg = R(40, 0, 10),
		LeftLowerLeg = R(-40, 0, 0),
	})
	local gone = Util.smoothstep(12.6, 14.1, t)
	rikaFade(ctx, gone * 0.9)
	local c = base + V(0, 0, 4)
	smokeAround(ctx, c + V(0, 1, 0), 0.8 + gone * 1.0, 8, 800, 1, Color3.fromRGB(72, 80, 104), 0.45)
	if t > 12.5 then
		FX.placeBurst(ctx, h.flakes, c + V(0, 1.5, 0), (t - 12.5) % 1.2, 3, 0.35, 1.2, V(0, 1, 0), 0.9, -1)
	end
	local drift = (t - 12.0) * 0.8
	cam(ctx, c + V(1 + drift, 15, 0.01), c + V(drift, 0, 0), 50, 0, 0, V(0, 0, 1))
	grade(ctx, -0.2, 0.22, -0.15, Color3.fromRGB(160, 178, 235))
	ctx:fog(1.4)
end

-- 14.1: Yuta, his raised right hand trembling beside his head, fingers half
-- curled; eyes wide, mouth a little open, brows knit
local function yutaHand(ctx: Timeline.Ctx)
	local t = ctx.t
	-- the arm trembles, the hand jerks with the cramp; he stares at it, and
	-- at 14.9 his eyes go to Ryu (at us)
	local shk = Util.noise1(t * 11, 4) * 1.8 + Util.noise1(t * 23, 7) * 0.9
	local jerk = Util.noise1(t * 6, 9) * 4
	local look = Util.smoothstep(14.85, 15.0, t)
	local yb = ctx:rig("Yuta", yutaRoot(), Cast.alive({
		UpperTorso = R(-4, 6, 0),
		Head = R(-2 + 2 * look, 12 - 6 * look, 0),
		RightUpperArm = R(80 + shk, 0, 22 + shk * 0.5),
		RightLowerArm = R(80 + shk * 0.8, 0, 0),
		RightHand = R(-10 + jerk, shk, -20 + jerk * 0.5),
	}, t))
	Cast.expr(ctx, "yuta", if look < 0.5 then "lookHand" else "grit")
	collarOpen(ctx)
	crampHand(ctx, yb.RightHand, yb.RightLowerArm, t)
	local head = yb.Head * C(0, 0.55, 0)
	local side = yutaRoot():VectorToWorldSpace(V(1, 0, 0))
	-- 14.133-14.25 the camera slides in from the hand to the face
	local slide = 1 - Util.smoothstep(14.133, 14.3, t)
	local eye = (yutaRoot() * C(0.55 + 0.6 * slide, 4.9, -3.6)).Position
	cam(ctx, eye, head.Position + side * (0.55 + 0.4 * slide) + V(0, 0.05, 0), 40, 0.02, 1)
	ctx:wind(1.3)
	grade(ctx, 0.02, 0.22, 0.06, Color3.fromRGB(214, 224, 255))
	field(ctx)
end

-- 15.433: the kick. Over Yuta's shoulder (his head in the right foreground)
-- Ryu charges in roaring, left fist out; 15.6 the camera whips round him: his
-- fist at the lens, his fur, then 15.98 Yuta's foot snaps up under his chin
-- and his head is thrown back; 16.1 his upturned bloody face from below,
-- blood spraying; 16.233 the leg straight up; 16.3 low angle, frozen: head
-- back, hair up, Yuta's leg vertical, his hand on Ryu's chest, blood rising
-- feet planted for the blow (the run ends in this)
local kickStance: Rig.Pose = {
	LowerTorso = R(-6, 0, 0),
	UpperTorso = R(-8, 0, 0),
	LeftUpperLeg = R(30, 0, -8),
	LeftLowerLeg = R(-34, 0, 0),
	RightUpperLeg = R(-22, 0, 8),
	RightLowerLeg = R(-12, 0, 0),
}
-- kicked under the chin: head thrown back, chest out, the right fist
-- clenched at his belt, the left arm flung out behind
local kickStruck: Rig.Pose = {
	LowerTorso = R(4, 0, 0),
	UpperTorso = R(8, -10, 0),
	-- (the head pivots on the top of the neck, not its base: shifted forward
	-- and up, so it tips back above the shoulders instead of behind them)
	Head = C(0, 0.12, -0.32) * R(46, 8, 10),
	RightUpperArm = R(-10, 0, 16),
	RightLowerArm = R(60, 0, 0),
	LeftUpperArm = R(-26, 0, -8),
	LeftLowerArm = R(30, 0, 0),
	LeftUpperLeg = R(18, 0, -8),
	LeftLowerLeg = R(-22, 0, 0),
	RightUpperLeg = R(-12, 0, 8),
	RightLowerLeg = R(-10, 0, 0),
}

local function kick(ctx: Timeline.Ctx)
	local t = ctx.t
	local hit = 15.98
	local dt = t - hit
	-- the charge: the last running steps at Yuta; the run stops and the feet
	-- plant just before the blow (no running on the spot afterwards)
	local charge = math.max(0, hit - 0.1 - t)
	local rc = RYU + V(0, 0, -1.0 + charge * 3)
	local plant = Util.smoothstep(hit - 0.22, hit - 0.04, t)
	local legs = Cast.mix(Cast.run(math.min(t, hit - 0.12) * 2.5, 18), kickStance, plant)
	local swing = Util.smoothstep(15.6, 15.78, t)
	local charging = Cast.mix(Cast.mix(guard, legs, 0.75), mirror(punchR), swing)
	-- struck: the head snaps back (overshoot), chest out, right fist at the
	-- belt, left arm flung back; afterwards only breathing and the wind
	local back = if dt > 0 then Util.smoothstep(0, 0.1, dt) else 0
	local rpose = hitPose(Cast.mix(charging, kickStruck, back), dt, 6, 10, 6)
	local rb = ctx:rig("RyuLoose", C(rc), Cast.alive(rpose, t))
	Cast.expr(ctx, "ryu", if dt > 0 then "grit" else "roar")
	bloodFace(ctx)
	if dt > 0 then
		fist(ctx, 1)
	end
	local chin = (rb.Head * C(0, 0.12, -0.45)).Position
	-- Yuta stands in front of him as he comes; for the kick he steps to Ryu's
	-- left and turns side-on, his far (right) leg swinging straight up past
	-- Ryu's chin, his left arm across Ryu's stomach. A fixed spot: no sliding
	local kickK = Util.smoothstep(hit - 0.14, hit, t)
	-- (a high kick: the torso leans right back, away from the rising leg)
	local yp: Rig.Pose = {
		LowerTorso = R(6 * kickK, 0, 0),
		UpperTorso = R(40 * kickK - 4, 0, -6 * kickK),
		Head = R(-28 * kickK, 0, 10 * kickK),
		RightUpperLeg = R(20 + 150 * kickK, 0, 0),
		RightLowerLeg = R(-70 + 68 * kickK, 0, 0),
		RightFoot = R(-24 * kickK, 0, 0),
		LeftUpperLeg = R(-8 * kickK, 0, -4),
		LeftLowerLeg = R(-14, 0, 0),
		LeftUpperArm = R(30 - 14 * kickK, 0, 40 * kickK),
		LeftLowerArm = R(40 - 30 * kickK, 0, 0),
		RightUpperArm = R(150 - 110 * kickK, 0, 30 + 30 * kickK),
		RightLowerArm = R(40 + 30 * kickK, 0, 0),
	}
	local step = Util.smoothstep(hit - 0.3, hit - 0.02, t)
	local yA = RYU + V(-0.4, 0, -3.1)
	local yB = RYU + V(-2.25, 1.4 * kickK, -1.45)
	local ypos = yA:Lerp(yB, step)
	local ydir = V(0, 0, 1):Lerp(V(1, 0, -0.3).Unit, step)
	local yroot = Util.lookAt(ypos, ypos + ydir)
	local yb = ctx:rig("Yuta", yroot, Cast.alive(yp, t))
	Cast.expr(ctx, "yuta", "cold")
	if dt > 0 then
		bloodStreaks(ctx, chin + V(0, 0.1, -0.1), V(0.35, 1, -0.2), dt, 11)
	end
	local head = rb.Head * C(0, 0.75, 0)
	if t < 15.6 then
		-- over Yuta's right shoulder: his head big on the right, Ryu charging
		local yh = (yb.Head * C(0, 0.6, 0)).Position
		cam(ctx, yh + V(1.0, 0.3, -3.4), head.Position + V(0.6, -1.2, 0), 44, 0.1, 1)
	elseif t < 16.1 then
		-- whipping round him: face, fist, fur, the hit
		local a = math.rad(70 + 40 * Util.smoothstep(15.6, 16.05, t))
		local r = 5
		local eye = head.Position + V(math.sin(a) * r, -0.6, -math.cos(a) * r)
		cam(ctx, eye, head.Position + V(0, -0.8, -0.6), 50, if dt > 0 then 0.8 else 0.3, 0.8)
		if dt > 0 and dt < 0.08 then
			ctx:flash(WHITE, 0.25)
			ctx:alpha("fbSmear", 0.7)
		end
	elseif t < 16.233 then
		-- under the chin: the upturned face, blood spraying off (Yuta, who
		-- would stand in the way, is out of this close-up)
		ctx:rig("Yuta", C(RYU + V(0, -400, 0)), yp)
		local fc = rb.Head * C(0, 0.7, -0.45)
		ctx:camera(shake(Util.lookAt(fc.Position + fc.LookVector * 2.3 + fc.RightVector * 0.3, fc.Position, fc.UpVector), t, 0.2, 16), 40)
		ctx:focus(2.3, 1)
	elseif t < 16.3 then
		-- low in front, a little closer: the head thrown back, the leg up
		cam(ctx, rc + V(0.5, 1.4, -6.4), rc + V(-0.9, 4.3, 0), 32, 0.2, 0.6)
	else
		-- from below in front: the frozen moment, the camera drifting a touch
		local drift = (t - 16.3) * 0.1
		cam(ctx, rc + V(0.6, 1.6, -7.5) + V(-drift, 0, 0), rc + V(-0.9, 4.15, 0), 28, 0.03, 0.4) -- HOLDCAM
	end
	-- a soft key light by the camera, so they read bright against the sky
	FlashArt.key(ctx, V(0.6, 1.2, 0.8), 1.1, Color3.fromRGB(240, 244, 255), 30)
	ctx:gust(if dt > 0 then 2.4 * math.exp(-dt * 1.5) + 0.4 else 1.0)
	ctx:wind(1.5)
	grade(ctx, 0.02, 0.22, 0.12, Color3.fromRGB(214, 226, 255))
	field(ctx)
end

-- 17.633: Ryu's right arm against the sky ("I had no idea..."): the open
-- hand reaching (from the left edge), seen from below (18.1), the fingers
-- spread (18.3), clawing shut (18.9), a fist (19.133), and 19.567 the fist
-- slamming into Yuta's side, blood
local function ryuHand(ctx: Timeline.Ctx)
	local t = ctx.t
	if t >= 19.567 then
		local yb = ctx:rig("Yuta", yutaRoot(), Cast.alive({ UpperTorso = R(-24, 10, 0), Head = R(-20, 0, 0), RightUpperArm = R(30, 0, 30), RightLowerArm = R(60, 0, 0) }, t))
		local side = (yb.UpperTorso * C(-0.55, 0.2, -0.3)).Position
		local dig = Util.smoothstep(19.567, 19.65, t)
		Common.rigAt(ctx, "RyuLoose", C(RYU) * CFrame.Angles(0, math.rad(-25), 0), punchR, "RightHand", C(0, -0.4, 0), side + V(-0.6 + dig * 0.5, 0, 0.4 - dig * 0.3))
		fist(ctx, 1)
		FX.placeBurst(ctx, h2(ctx).blood, side + V(0.2, 0.1, 0.1), t - 19.6, 8, 0.25, 0.8, V(0.6, 0.4, 0.5), 0.6, 4)
		cam(ctx, side + V(-1.6, 0.5, 2.1), side + V(0, 0.1, 0), 48, 0.7, 1)
		ctx:gust(2)
		grade(ctx, 0.02, 0.26, 0.06)
		field(ctx)
		return
	end
	local closeK = Util.smoothstep(18.95, 19.13, t)
	local reach = Util.smoothstep(17.633, 18.9, t)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({
		UpperTorso = R(-6, 10, 0),
		RightUpperArm = R(72 + reach * 8, 0, 12),
		RightLowerArm = R(14 - reach * 8, 0, 0),
		RightHand = R(34 - reach * 30 - closeK * 10, 0, 0),
	}, t))
	fist(ctx, closeK)
	local hand = (rb.RightHand * C(0, -0.35, 0)).Position
	if t >= 18.1 and t < 18.3 then
		cam(ctx, hand + V(0.4, -2.0, -0.5), hand + V(0, 0, 0.3), 46, 0.05, 1, V(0, 0, 1))
	else
		local a = if t < 18.1 then 0 else 1
		cam(ctx, hand + V(1.8, -0.9 + a * 0.2, 0.1), hand + V(0, 0.05, 0.45 + a * 0.15), 44, if t >= 18.9 and t < 19.133 then 0.35 else 0.04, 1)
	end
	ctx:gust(0.8 + closeK)
	ctx:wind(1.4)
	grade(ctx, 0.02, 0.22, 0.06, Color3.fromRGB(210, 222, 255))
	field(ctx)
end

-- 19.9: Yuta doubled over Ryu's fist, facing us: eyes lost in the shadow of
-- his fringe, teeth clenched, blood from the mouth, right fist raised by his
-- head, ringed left hand low; Ryu's arm in at the bottom left; a slow push-in
local function bentOver(ctx: Timeline.Ctx)
	local t = ctx.t
	local sag = Util.smoothstep(20.3, 21.1, t)
	local yb = ctx:rig("Yuta", yutaRoot(), Cast.alive({
		LowerTorso = R(-8, 0, 0),
		UpperTorso = R(-24 - sag * 4, 0, 0),
		Head = R(-16, 0, 0),
		RightUpperArm = R(20, 0, 70 - sag * 6),
		RightLowerArm = R(0, 0, 120),
		LeftUpperArm = R(14, 0, -14),
		LeftLowerArm = R(40, 0, 0),
		LeftUpperLeg = R(20, 0, -6),
		LeftLowerLeg = R(-24, 0, 0),
	}, t))
	Cast.expr(ctx, "yuta", "shadow")
	ctx:show("yuta:blood")
	local belly = (yb.UpperTorso * C(-0.1, 0.25, -0.45)).Position
	Common.rigAt(ctx, "RyuLoose", C(YUTA + V(-3.0, 0, 0.6)) * CFrame.Angles(0, math.rad(-80), 0), punchR, "RightHand", C(0, -0.4, 0), belly)
	fist(ctx, 1)
	FX.placeBurst(ctx, h2(ctx).blood, (yb.Head * C(0, 0.25, -0.5)).Position, (t * 1.3) % 0.8, 1.2, 0.1, 0.8, V(0, -1, 0.2), 0.2, 9)
	local push = Util.smoothstep(19.9, 21.267, t)
	local eye = (yutaRoot() * C(-0.2, 4.0, -5.2 + push * 1.2)).Position
	cam(ctx, eye, (yb.UpperTorso * C(0, 1.1, 0)).Position, 44, 0.03, 1)
	ctx:wind(1.2)
	grade(ctx, 0.02, 0.28, 0.06, Color3.fromRGB(214, 224, 255))
	field(ctx)
end

-- 21.267: up under his bowed face (eyes in shadow, blood dripping from his
-- mouth); 22.4 his head comes up: eyes wide, teeth clenched
local function yutaLooksUp(ctx: Timeline.Ctx)
	local hh = h2(ctx)
	local t = ctx.t
	local up = t >= 22.4
	local yb = ctx:rig("Yuta", yutaRoot(), Cast.alive({
		UpperTorso = R(if up then -14 else -24, 0, 0),
		Head = R(if up then -4 else -16, 0, 0),
	}, t))
	Cast.expr(ctx, "yuta", if up then "grit" else "shadow")
	ctx:show("yuta:blood")
	local head = yb.Head * C(0, 0.55, 0)
	FX.placeBurst(ctx, hh.blood, (yb.Head * C(0, 0.05, -0.5)).Position, (t * 1.2) % 0.9, 1.0, 0.09, 0.9, V(0, -1, 0), 0.15, 12)
	if up then
		cam(ctx, head:PointToWorldSpace(V(0, -0.05, -1.45)), head.Position + V(0, -0.1, 0), 46, 0.03, 1)
	else
		cam(ctx, head:PointToWorldSpace(V(0.1, -0.85, -1.3)), head.Position + V(0, -0.25, 0), 50, 0.02, 1)
	end
	ctx:wind(1.1)
	grade(ctx, 0, 0.3, 0.04)
end

-- 23.033: high overhead, static: two small figures trading blows on the
-- cracked concrete, white flashes at the hits
local function topExchange(ctx: Timeline.Ctx)
	local t = ctx.t
	local y1 = strikeK(t, 23.13, 0.3)
	local r1 = strikeK(t, 23.4, 0.3)
	local y2 = strikeK(t, 23.62, 0.28)
	local r2 = strikeK(t, 23.93, 0.3)
	local y3 = strikeK(t, 24.15, 0.3)
	local yPose = if t < 23.5 then punchPose(y1) elseif t < 24.0 then punchPose(y2, true) else punchPose(y3)
	local rPose = if t < 23.7 then punchPose(r1) else punchPose(r2, true)
	local sway = math.sin(t * 9) * 0.3
	ctx:rig("RyuLoose", C(RYU + V(sway, 0, 0.3)) * CFrame.Angles(0, math.rad(-10), 0), Cast.alive(hitPose(rPose, t - 23.13, 30, 20), t))
	ctx:rig("Yuta", yutaRoot() * C(-sway, 0, 0.2), Cast.alive(hitPose(yPose, t - 23.4, -25, 15), t))
	for _, hit in { 23.13, 23.4, 23.93 } do
		if t >= hit and t < hit + 0.08 then
			flashAt(ctx, (RYU + YUTA) / 2 + V(0, 4.5, 0), 1.2, 1 - (t - hit) / 0.08)
		end
	end
	local mid = (RYU + YUTA) / 2
	cam(ctx, mid + V(-4, 30, 1.5), mid + V(-4, 0, 1.5), 34, 0, 0, V(1, 0, 0))
	ctx:wind(1.2)
	grade(ctx, -0.12, 0.22, 0.05, Color3.fromRGB(190, 206, 255))
	ctx:fog(0.6)
end

-- 24.233: Yuta's fist crushes Ryu's face (left edge of the frame), blood
-- bursting, held on the impact
local function faceSmash(ctx: Timeline.Ctx)
	local hh = h2(ctx)
	local t = ctx.t
	local hit = 24.24
	local dt = t - hit
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive(hitPose(guard, dt * 0.25, -35, 12, -10), t))
	Cast.expr(ctx, "ryu", "hit")
	bloodFace(ctx)
	local cheek = (rb.Head * C(-0.5, 0.75, -0.35)).Position
	Common.rigAt(ctx, "Yuta", yutaRoot() * CFrame.Angles(0, math.rad(-15), 0), punchR, "RightHand", C(0, -0.35, 0), cheek)
	FX.placeBurst(ctx, hh.blood, cheek + V(0.1, 0.1, -0.2), 0.12 + dt * 0.3, 10, 0.25, 1.2, V(-0.4, 0.4, -1), 0.8, 2)
	local face = (rb.Head * C(0, 0.7, -0.2)).Position
	cam(ctx, YUTA + V(1.7, 5.3, -0.4), face + V(-0.9, -0.2, 0), 44, 0.08, 1)
	ctx:gust(2.4)
	grade(ctx, 0.02, 0.3, 0.06)
	field(ctx)
end

-- 24.567: side on (Ryu left, Yuta right), a fast exchange: Yuta's fist
-- snaps Ryu's head back, Ryu lunges in swinging, Yuta lands twice more;
-- 25.6 the camera closes in as Ryu wheels round with a hook
local function sideExchange(ctx: Timeline.Ctx)
	local hh = h2(ctx)
	local t = ctx.t
	local y1 = strikeK(t, 24.6, 0.3)
	local r1 = strikeK(t, 24.88, 0.32)
	local y2 = strikeK(t, 25.06, 0.28)
	local y3 = strikeK(t, 25.43, 0.3)
	local r2 = strikeK(t, 25.66, 0.3)
	local yPose = if t < 24.85 then punchPose(math.max(y1, 0.7)) elseif t < 25.2 then punchPose(y2, true) else punchPose(y3)
	local rBase = if t < 25.3 then punchPose(r1) else punchPose(r2, true)
	local rp = hitPose(rBase, t - 24.6, 20, 30)
	if t > 25.06 then
		rp = hitPose(rBase, t - 25.06, -30, 10)
	end
	if t > 25.43 then
		rp = hitPose(rBase, t - 25.43, 15, 35)
	end
	local lunge = Util.smoothstep(24.75, 24.9, t) * (1 - Util.smoothstep(25.0, 25.3, t))
	local rb = ctx:rig("RyuLoose", C(RYU + V(0, 0, 0.7 - 0.8 * lunge)), Cast.alive(rp, t))
	Cast.expr(ctx, "ryu", "grit")
	bloodFace(ctx)
	ctx:rig("Yuta", yutaRoot(), Cast.alive(hitPose(yPose, t - 24.9, 25, 15), t))
	if t > 25.43 then
		FX.placeBurst(ctx, hh.blood, (rb.Head * C(0, 0.6, -0.5)).Position, t - 25.43, 8, 0.2, 0.8, V(0, 0.6, 1), 0.6, 6)
	end
	local mid = (RYU + YUTA) / 2 + V(0, 3.4, 0)
	local close = Util.smoothstep(25.55, 25.7, t)
	cam(ctx, mid + V(8.5 - close * 3, -0.7, 0.3), mid + V(0, 0.2, 0.3), 48, 0.15 + close * 0.3, 0.6)
	ctx:gust(1.6)
	grade(ctx, -0.04, 0.24, 0.06, Color3.fromRGB(200, 214, 255))
	field(ctx)
end

-- the void behind an effect: a black (or dark red) wall facing the camera
local function voidWall(ctx: Timeline.Ctx, at: Vector3, normal: Vector3, col: Color3)
	local h = h3(ctx)
	ctx:place(h.void, Util.lookAt(at, at + normal))
	ctx:prop(h.void, { s = V(600, 600, 1), c = col })
end

-- 25.7: Ryu's fist ground into Yuta's cheek (eyes wide, blood); 26.2 black:
-- a ragged red star of cursed energy; 26.9 red and black lightning, the two
-- dark against it; 27.45 a white flash; 27.95 Yuta (left, back to us) drives
-- into Ryu (right, grinning) inside red-black lightning on a red ground
local function blackFlash(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local t = ctx.t
	if t < 26.2 then
		-- Ryu's fist ground into Yuta's cheek
		local yb = ctx:rig("Yuta", yutaRoot(), Cast.alive(hitPose(guard, t - 25.84, -30, 8), t))
		Cast.expr(ctx, "yuta", "grit")
		ctx:show("yuta:blood")
		local cheek = (yb.Head * C(0.45, 0.45, -0.3)).Position
		Common.rigAt(ctx, "RyuLoose", C(RYU) * CFrame.Angles(0, math.rad(40), 0), mirror(punchR), "LeftHand", C(0, -0.4, 0), cheek)
		local head = yb.Head * C(0, 0.55, 0)
		cam(ctx, head:PointToWorldSpace(V(-1.1, 0.0, -2.0)), head:PointToWorldSpace(V(0.25, -0.05, 0)), 46, 0.5, 1)
		ctx:gust(2.5)
		grade(ctx, 0.02, 0.3, 0.06)
		field(ctx)
		return
	end
	local c = RYU + V(0, 60, -40)
	if t < 26.93 then
		-- black; red sparks (26.33); a ragged red star (26.53)
		ctx:camera(Util.lookAt(c + V(0, 0, 14), c), 50)
		ctx:focus(14, 0)
		voidWall(ctx, c + V(0, 0, -12), V(0, 0, 1), Color3.new(0, 0, 0))
		local ri = 1
		if t >= 26.53 then
			local k = Util.smoothstep(26.53, 26.7, t)
			for i = 1, 12 do
				local a = math.rad(i * 30 + (if i % 2 == 0 then 10 else 0) + math.sin(t * 7 + i) * 4)
				local len = (if i % 2 == 0 then 4.0 else 2.2) * (0.4 + 0.6 * k)
				ri = FX.placeBolt(ctx, h.redBolts, ri, c + V(math.cos(a), math.sin(a), 0) * 1.6, c + V(math.cos(a), math.sin(a), 0) * (1.6 + len), 4, 0.7, 0.55, i + 90, 14)
			end
		elseif t >= 26.33 then
			for i = 1, 8 do
				local rr = rng(i * 17 + math.floor(t * 20))
				local p0 = c + V(Util.randRange(rr, -7, 7), Util.randRange(rr, -4, 4), 0)
				ri = FX.placeBolt(ctx, h.redBolts, ri, p0, p0 + V(Util.randRange(rr, -2, 2), Util.randRange(rr, -2, 2), 0), 4, 0.6, 0.2, i + 120, 18)
			end
		end
		ctx:grade({ brightness = -0.1, contrast = 0.3, saturation = 0.3, tint = Color3.fromRGB(255, 200, 205) })
		ctx:bloom(0.4)
		ctx:fog(0)
		ctx:wind(0)
		return
	end
	-- the two of them (Yuta left, Ryu right) inside the black lightning
	local hit = 26.97
	local dt = t - hit
	local yb = ctx:rig("Yuta", yutaRoot() * C(0, 0, 0.3), Cast.alive(punchPose(math.max(0.9, strikeK(t, hit, 0.2))), t))
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive(hitPose(Cast.add(guard, "LeftUpperArm", R(40, 0, -30)), dt, 15, 12), t))
	Cast.expr(ctx, "ryu", "grit")
	Cast.expr(ctx, "yuta", "grit")
	bloodFace(ctx)
	ctx:show("yuta:blood")
	local mid = (yb.RightHand.Position + rb.UpperTorso.Position) / 2
	blackLightning(ctx, mid, 7, 1, 300)
	local back = RYU + V(0, 3, 10)
	if t < 27.2 then
		-- a red-black explosion, a pink-white core, the two black against it
		voidWall(ctx, back, V(0, 0, -1), Color3.new(0, 0, 0))
		FX.placeCore(ctx, h.redGlow, mid + V(-2.5, 0.5, 1.5), 1.0 + math.sin(t * 40) * 0.2, 0.7)
		flashAt(ctx, mid + V(1.5, 0.3, 2), 1.1, 0.75)
		cam(ctx, YUTA + V(-4.5, 4.2, -5.5), mid, 46, 0.4, 0.4)
		ctx:grade({ brightness = -0.3, contrast = 0.7, saturation = 0.3, tint = Color3.fromRGB(255, 150, 160) })
		if t < 26.985 then
			ctx:flash(WHITE, 0.9)
		end
	else
		-- 27.2: the black flash itself, from the front at the side: Yuta
		-- (left) with his right fist cocked high and his left hand driven
		-- into Ryu's chest, Ryu (right) grinning, both turned a little to us,
		-- hanging in a black void torn by red bursts of energy
		local B = RYU + V(0, 300, 0)
		local rroot = C(B) * CFrame.Angles(0, math.rad(35), 0)
		local rpose: Rig.Pose = {
			UpperTorso = R(10, 0, 0),
			Head = R(4, -18, 0),
			RightUpperArm = R(24, 0, 44),
			RightLowerArm = R(40, 0, 0),
			LeftUpperArm = R(34, 0, -34),
			LeftLowerArm = R(50, 0, 0),
			LeftUpperLeg = R(16, 0, -6),
			RightUpperLeg = R(-10, 0, 6),
		}
		local shove = math.sin(t * 23) * 1.2
		local rb2 = ctx:rig("RyuLoose", rroot, Cast.alive(Cast.add(rpose, "UpperTorso", R(shove, 0, 0)), t))
		local chest = (rb2.UpperTorso * C(0.1, 0.9, -0.6)).Position
		local ypose: Rig.Pose = {
			LowerTorso = R(-6, 0, 0),
			UpperTorso = R(-10, -14, 0),
			Head = R(-8, 12, 0),
			RightUpperArm = R(96, 0, 56),
			RightLowerArm = R(118, 0, 0),
			RightHand = R(-20, 0, 0),
			LeftUpperArm = R(84, 0, -4),
			LeftLowerArm = R(8, 0, 0),
			LeftHand = R(-60, 0, 0),
			LeftUpperLeg = R(30, 0, -6),
			LeftLowerLeg = R(-30, 0, 0),
			RightUpperLeg = R(-20, 0, 6),
		}
		local yroot = C(B + V(0.3, 0, -3.2)) * CFrame.Angles(0, math.pi - math.rad(35), 0)
		Common.rigAt(ctx, "Yuta", yroot, Cast.alive(ypose, t), "LeftHand", C(0, -0.3, -0.1), chest)
		-- the painted backdrop far behind them, breathing slowly
		local pulse = 0.5 * (1 + math.sin(t * 3.1) * 0.02)
		local eye = B + V(-6.2, 4.4, -1.5)
		local backAt = B + V(36, 4, -1.5)
		ctx:place(h.redBack, Util.lookAt(backAt, eye) * CFrame.Angles(0, 0, math.sin(t * 0.7) * 0.03))
		ctx:prop(h.redBack, { s = V(RB_W / 10 * pulse, RB_H / 10 * pulse, 0.05) })
		-- red shards of energy flying past between us and them
		FX.placeBurst(ctx, h.redShards, B + V(1.5, 2.2, -1.5), (t * 0.8) % 1.0, 18, 0.24, 1.0, V(0, 0.3, 0), 1.2, 0)
		-- a hard red rim light from behind
		ctx:place(h.lamp, C(B + V(5, 7, -1.5)))
		ctx:light("P3Lamp", 6, Color3.fromRGB(255, 50, 70), 30)
		local sharp = Util.smoothstep(28.3, 28.6, t)
		cam(ctx, eye, B + V(0, 4.4, -1.5), 46, 0.12, 1)
		Cast.expr(ctx, "ryu", "grin")
		Cast.expr(ctx, "yuta", "grit")
		bloodFace(ctx)
		ctx:show("yuta:blood")
		ctx:focus(if sharp < 1 then 0.6 + sharp * 7 else 8.2, 1)
		ctx:grade({ brightness = -0.02, contrast = 0.4, saturation = 0.25, tint = Color3.fromRGB(255, 226, 230) })
		-- the white flash fading through a pink blur into the picture
		local w = 1 - Util.smoothstep(27.85, 28.3, t)
		local pink = Util.smoothstep(27.9, 28.1, t) * (1 - Util.smoothstep(28.35, 28.6, t))
		local a = math.max(w, pink * 0.55)
		if a > 0.001 then
			local f = w / math.max(1e-3, w + pink)
			ctx:flash(Util.mix(Color3.fromRGB(255, 176, 196), Color3.fromRGB(255, 244, 246), f), a)
		end
		local _ = back
		local _2 = mid
	end
	ctx:gust(2.2)
	ctx:bloom(1.8)
	ctx:fog(0)
end

-- the dessert table under the camera (angle: a turn about the vertical)
local function tableCam(ctx: Timeline.Ctx, at: Vector3, from: Vector3, fov: number, angle: number)
	local rot = CFrame.Angles(0, math.rad(angle), 0)
	local rel = rot:VectorToWorldSpace(from - at)
	local topDown = math.abs(rel.Unit.Y) > 0.95
	local upv = if topDown then rot:VectorToWorldSpace(V(0, 0, 1)) else V(0, 1, 0)
	ctx:camera(Util.lookAt(DESSERT + at + rel, DESSERT + at, upv), fov)
	ctx:focus(rel.Magnitude, 1)
	ctx:fog(0)
	ctx:wind(0)
	ctx:bloom(1.2)
	grade(ctx, 0.08, 0.05, 0.1, Color3.fromRGB(255, 248, 236))
end

-- 29.167: the pink cake from above, close; the camera rises and the table
-- turns to show it all ("This is what dessert is like!")
local function desserts(ctx: Timeline.Ctx)
	local k = Util.smoothstep(29.8, 33.0, ctx.t)
	tableCam(ctx, V(0, 0.8, 1.5 * k), V(0.05, 7 + k * 12, 1.5 * k + 0.3), 46 + k * 6, 45 * k)
end

-- 33.167: low behind Yuta's right shoulder (his white back fills the left),
-- Ryu facing us: Yuta's fist into the abs, Ryu's fist past Yuta's shoulder,
-- Yuta's open hand at his chest, Yuta lunging in, a blow to the chest
local function bodyBlows(ctx: Timeline.Ctx)
	local t = ctx.t
	local y1 = strikeK(t, 33.22, 0.3)
	local r1 = strikeK(t, 33.36, 0.3)
	local y2 = strikeK(t, 33.84, 0.34)
	local yPose = if t < 33.42 then punchPose(y1) elseif t < 33.62 then Cast.add(punchPose(0.6, true), "LeftHand", R(-60, 0, 0)) else punchPose(y2)
	local lunge = Util.smoothstep(33.55, 33.72, t)
	local yb = ctx:rig("Yuta", yutaRoot() * C(0, 0, -0.5 * lunge), Cast.alive(yPose, t))
	local spread = Util.smoothstep(33.4, 33.5, t) * (1 - Util.smoothstep(33.62, 33.75, t))
	local rPose = Cast.mix(punchPose(r1), { UpperTorso = R(10, 0, 0), RightUpperArm = R(20, 0, 70), LeftUpperArm = R(20, 0, -70), RightLowerArm = R(30, 0, 0), LeftLowerArm = R(30, 0, 0) }, spread)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive(hitPose(hitPose(rPose, t - 33.22, 0, -14), t - 33.84, 10, -12), t))
	Cast.expr(ctx, "ryu", if spread > 0.5 then "grin" else "grit")
	bloodFace(ctx)
	local _ = yb
	cam(ctx, YUTA + V(-2.9, 3.4, -3.0), rb.UpperTorso.Position + V(-0.4, 0.5, 0), 50, 0.3, 0.6)
	ctx:gust(1.8)
	grade(ctx, -0.04, 0.26, 0.06, Color3.fromRGB(200, 214, 255))
	field(ctx)
end

-- 33.9: a fast pan at table height along the cakes, warm and glowing
local function dessertPan(ctx: Timeline.Ctx)
	local x = 30 - ctx.u * 18
	ctx:camera(Util.lookAt(DESSERT + V(x, 3.2, -3), DESSERT + V(x, 1.4, 5)), 40)
	ctx:focus(8, 1)
	ctx:fog(0)
	ctx:wind(0)
	ctx:bloom(1.4)
	grade(ctx, 0.14, 0.05, 0.1, Color3.fromRGB(255, 246, 228))
end

-- 34.9: Yuta (left, facing right) takes Ryu's fist in the face - Ryu's arm
-- and fur huge in the right foreground - then ducks under the next swing
local function ryuSwings(ctx: Timeline.Ctx)
	local t = ctx.t
	local r1 = strikeK(t, 34.95, 0.3)
	local r2 = strikeK(t, 35.36, 0.34)
	local duck = Util.smoothstep(35.22, 35.34, t) * (1 - Util.smoothstep(35.5, 35.66, t))
	local yp = Cast.add(Cast.add(hitPose(guard, t - 34.95, -30, 20), "UpperTorso", R(-30 * duck, 0, 12 * duck)), "LowerTorso", R(-14 * duck, 0, 0))
	yp = Cast.add(yp, "HumanoidRootPart", C(0, -0.8 * duck, 0))
	local yb = ctx:rig("Yuta", yutaRoot(), Cast.alive(yp, t))
	Cast.expr(ctx, "yuta", "grit")
	ctx:show("yuta:blood")
	local rPose = if t < 35.15 then punchPose(r1, true) else punchPose(r2)
	ctx:rig("RyuLoose", C(RYU + V(-1.0, 0, 0.6)) * CFrame.Angles(0, math.rad(10), 0), Cast.alive(rPose, t))
	local head = (yb.Head * C(0, 0.5, 0)).Position
	cam(ctx, YUTA + V(-7.0, 4.3, 2.2), YUTA + V(0, 4.1, 1.6), 46, if t > 35.0 and t < 35.2 then 0.6 else 0.15, 0.5)
	ctx:focus((head - (YUTA + V(-7.0, 4.3, 2.2))).Magnitude, 0.6)
	ctx:gust(2)
	grade(ctx, -0.02, 0.26, 0.06, Color3.fromRGB(205, 218, 255))
	field(ctx)
end

-- 35.667: the table from above in a fast blurred spin
local function cheeseSpin(ctx: Timeline.Ctx)
	tableCam(ctx, V(-6, 0.5, 5), V(-5.95, 11, 5.2), 50, -160 * Util.smoothstep(35.667, 36.8, ctx.t))
	grade(ctx, 0.16, 0.05, 0.12, Color3.fromRGB(255, 246, 225))
end

-- 36.8: a blur, then on the broken deck: tilted slabs all round, Yuta (left)
-- leaping in, Ryu (right) low and coiled; pillars of white air at the edges
local function rubble(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local hh = h2(ctx)
	local t = ctx.t
	local center = RYU + V(0, 0, -2.5)
	local hit = 36.95
	local dt = t - hit
	-- the deck is whole until Ryu's fist comes down; then it bursts into
	-- tilted slabs that go on rising slowly
	local broken = Util.smoothstep(hit, hit + 0.12, t)
	slabField(ctx, center + V(-1, 0, 0), 12, 500, 1.4 + math.max(0, dt) * 0.5, broken)
	-- Ryu (right) dives at the ground and drives his left fist into it, the
	-- right arm flung up behind him; then he stays crouched over the fist
	local dive = Util.smoothstep(36.8, hit, t)
	local air: Rig.Pose = {
		HumanoidRootPart = C(0, 0.9, 0),
		LowerTorso = R(-20, 0, 0),
		UpperTorso = R(-24, 0, 0),
		Head = R(10, 0, 0),
		LeftUpperArm = R(170, 0, -10),
		LeftLowerArm = R(30, 0, 0),
		RightUpperArm = R(-40, 0, 30),
		RightLowerArm = R(40, 0, 0),
		LeftUpperLeg = R(40, 0, -6),
		LeftLowerLeg = R(-70, 0, 0),
		RightUpperLeg = R(-30, 0, 6),
		RightLowerLeg = R(-50, 0, 0),
	}
	local smash: Rig.Pose = {
		HumanoidRootPart = C(0, -1.0, 0),
		LowerTorso = R(-38, 0, 0),
		UpperTorso = R(-34, 0, 0),
		Head = R(14, 0, 0),
		LeftUpperArm = R(112, 0, -6),
		LeftLowerArm = R(6, 0, 0),
		RightUpperArm = R(-70, 0, 36),
		RightLowerArm = R(30, 0, 0),
		LeftUpperLeg = R(84, 0, -8),
		LeftLowerLeg = R(-104, 0, 0),
		RightUpperLeg = R(-14, 0, 10),
		RightLowerLeg = R(-62, 0, 0),
	}
	local rpose = if t < hit then Cast.mix(air, smash, dive * dive * 0.35) else Cast.mix(smash, air, 0)
	local settle = if dt > 0 then math.exp(-dt * 7) * math.sin(dt * 30) * 0.12 else 0
	local rp = center + V(0, settle + 0.9 * broken, 2.4)
	local rb = ctx:rig("RyuLoose", C(rp) * CFrame.Angles(0, 0, 0), Cast.alive(rpose, t))
	local fistAt = (rb.LeftHand * C(0, -0.35, 0)).Position
	-- Yuta (left) springs back away from the blast: up and away, knee up
	local leap = Util.smoothstep(hit - 0.05, hit + 0.5, t)
	local ypose: Rig.Pose = {
		HumanoidRootPart = C(0, 0.4 + 1.0 * leap, 0),
		LowerTorso = R(8, 0, 0),
		UpperTorso = R(4, 0, 0),
		Head = R(-12, 0, 0),
		RightUpperArm = R(110, 0, 30),
		RightLowerArm = R(60, 0, 0),
		LeftUpperArm = R(30, 0, -50),
		LeftLowerArm = R(70, 0, 0),
		LeftUpperLeg = R(80, 0, -6),
		LeftLowerLeg = R(-90, 0, 0),
		RightUpperLeg = R(10, 0, 6),
		RightLowerLeg = R(-70, 0, 0),
	}
	local yp = center + V(0, 0.2 + 0.6 * broken, -4.3 - 1.2 * leap - math.max(0, dt) * 0.4)
	ctx:rig("Yuta", C(yp) * CFrame.Angles(0, math.pi, 0), Cast.alive(ypose, t))
	-- the blow: a flash at the fist, dust and chips flung up, columns of air
	if dt > 0 then
		flashAt(ctx, fistAt + V(0, 0.2, 0), 0.8, 1 - Util.smoothstep(0, 0.12, dt))
		FX.placeBurst(ctx, hh.dust, fistAt, dt, 9, 1.4, 1.4, V(0, 1, 0), 1.2, 1)
		FX.placeBurst(ctx, hh.debris, fistAt, dt, 12, 0.35, 1.6, V(0, 1, 0), 0.9, 6)
	end
	local cols = Util.smoothstep(hit, hit + 0.15, t)
	for i, col in h.columns do
		local sz = if i == 1 then -1 else 1
		local base = center + V(4, 0, sz * 13)
		ctx:place(col, C(base + V(0, 10, 0)) * CFrame.Angles(math.rad(sz * 18), 0, math.pi / 2))
		ctx:prop(col, { s = V(26 * cols, 2.4, 2.4), t = 1 - 0.55 * cols })
	end
	if t < 36.95 and t > 36.86 then
		ctx:alpha("fbSmear", 0.6)
	end
	cam(ctx, center + V(-13, 5.6, 0.4), center + V(0, 2.8, -0.2), 46, if dt > 0 and dt < 0.3 then 0.5 else 0.06, 0.4)
	FlashArt.key(ctx, V(0.5, 2, 1), 2.2, Color3.fromRGB(236, 242, 255), 60)
	ctx:gust(if dt > 0 then 2.2 * math.exp(-dt * 2) + 0.6 else 1.2)
	grade(ctx, -0.02, 0.24, 0.08, Color3.fromRGB(200, 214, 255))
	field(ctx, "low")
end

-- 37.8: the cherry tart from straight above, pulling back from the glazed
-- fruit to the whole tart on its plate
local function tartTop(ctx: Timeline.Ctx)
	local k = Util.smoothstep(37.8, 38.667, ctx.t)
	-- turning steadily (about 150 degrees over the shot) while pulling back
	tableCam(ctx, V(-11, 1.4, 9), V(-11, 3.4 + k * 8, 9.02), 44, -20 + (ctx.t - 37.8) * 170)
end

-- 38.667: from high above: the two locked together, spinning round each
-- other (clockwise) among blurred chunks of floating concrete
local function topSpin(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local t = ctx.t
	local c = RYU + V(0, 0, -1.6)
	local a = math.rad(270 + (t - 38.736) * 300)
	local d = V(math.cos(a), 0, math.sin(a))
	local grip: Rig.Pose = { UpperTorso = R(16, 0, 0), Head = R(-10, 0, 0), RightUpperArm = R(80, 0, 0), RightLowerArm = R(30, 0, 0), LeftUpperArm = R(80, 0, 0), LeftLowerArm = R(30, 0, 0), LeftUpperLeg = R(20, 0, 0), RightUpperLeg = R(-20, 0, 0) }
	local function face(p: Vector3, dir: Vector3): CFrame
		return Util.lookAt(p, p + V(dir.X, 0, dir.Z))
	end
	ctx:rig("Yuta", face(c + d * 1.4, -d), Cast.alive(grip, t))
	ctx:rig("RyuLoose", face(c - d * 1.4, d), Cast.alive(grip, t))
	for i, p in h.bigSmoke.parts do
		local rr = rng(1300 + i)
		local a2 = Util.randRange(rr, 0, math.pi * 2)
		local d2 = Util.randRange(rr, 4, 9)
		local pos = c + V(math.cos(a2) * d2, Util.randRange(rr, 8, 26), math.sin(a2) * d2)
		local s = Util.randRange(rr, 0.8, 2.4)
		ctx:place(p, C(pos) * CFrame.Angles(i, i, 0))
		ctx:prop(p, { s = V(s, s * 0.8, s), t = 0.55, c = Color3.fromRGB(70, 86, 140) })
	end
	-- the camera rolls too, so the cracked ground and the debris turn with them
	local roll = math.rad(-(t - 38.667) * 250)
	cam(ctx, c + V(0, 46, 0.01), c, 22, 0, 1, V(math.cos(roll), 0, math.sin(roll)))
	ctx:focus(46, 1)
	FlashArt.key(ctx, V(0, 0, 30), 3, Color3.fromRGB(236, 242, 255), 30)
	grade(ctx, 0.02, 0.2, 0.18, Color3.fromRGB(190, 206, 255))
	ctx:fog(0.5)
end

-- 39.5: Yuta's fist (white sleeve) driving right through blue speed lines;
-- 40.1: Ryu's fist (fur cuff) driving left
local function fists(ctx: Timeline.Ctx)
	local t = ctx.t
	local first = t < 40.1
	local t0 = if first then 39.5 else 40.1
	local u = (t - t0) / (if first then 0.6 else 0.633)
	-- the whole body flies along with the blow: the fist leads, the camera
	-- rides alongside it and the world streams past behind
	local travel = (t - t0) * 30
	local thrust = Util.smoothstep(0, 0.25, u)
	local f: Vector3
	local camCF: CFrame
	if first then
		local root = yutaRoot() * C(0, 14, -travel)
		local yb = ctx:rig("Yuta", root, Cast.mix(punchPose(-0.2), punchPose(1), thrust))
		f = (yb.RightHand * C(0, -0.3, 0)).Position
		-- side on to the forearm, so it crosses the frame and the fist
		-- leads to the right
		local dir = (f - yb.RightLowerArm.Position).Unit
		local side = dir:Cross(V(0, 1, 0)).Unit
		local look = -side
		if look:Cross(V(0, 1, 0)):Dot(dir) < 0 then
			side = -side
		end
		local mid = f - dir * (0.7 + 0.15 * (1 - thrust))
		camCF = Util.lookAt(mid + side * 4.2 + V(0, 0.2, 0), mid)
	else
		local root = C(RYU) * C(0, 14, -travel) * CFrame.Angles(0, math.rad(4 * math.sin(u * 6)), 0)
		local rb = ctx:rig("RyuLoose", root, Cast.mix(punchPose(-0.2), punchPose(1), thrust))
		fist(ctx, 1)
		f = (rb.RightHand * C(0, -0.35, 0)).Position
		camCF = Util.lookAt(f + V(-2.2, -0.2, 0.7), f + V(0, 0, 0.45))
	end
	ctx:camera(shake(camCF, t, 0.1, 16), if first then 28 else 40)
	ctx:focus(4, 1)
	-- the blur behind, streaming the opposite way to the fist
	speedBlur(ctx, if first then 28 else 40, u, if first then 1 else -1, f)
	FlashArt.key(ctx, V(0.5, 1.5, 1), 0.9, Color3.fromRGB(236, 242, 255), 20)
	ctx:alpha("hstreaks", 0.6)
	ctx:gust(2.4)
	ctx:wind(3)
	grade(ctx, -0.02, 0.24, 0.1, Color3.fromRGB(206, 218, 255))
	ctx:fog(0)
end

-- 40.733: the parfait from the side: its layers vanish from the top down
local function parfait(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local t = ctx.t
	for i, at in { 41.05, 41.1, 41.45, 41.65 } do
		for _, p in h.vanish["scoop" .. i] or {} do
			ctx:prop(p, { t = if t >= at then 1 else 0 })
		end
	end
	tableCam(ctx, V(-40, 2.9, 18), V(-40, 3.2, 10.2), 34, 0)
	grade(ctx, 0.14, 0.05, 0.12, Color3.fromRGB(255, 246, 222))
end

-- 41.75: the strawberry sponge slice: bites vanish from the left
local function spongeGone(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local t = ctx.t
	for i, at in { 42.15, 42.4, 42.55, 42.7 } do
		for _, p in h.vanish["cake" .. i] do
			ctx:prop(p, { t = if t >= at then 1 else 0 })
		end
	end
	tableCam(ctx, V(-52, 1.4, 18), V(-52, 1.9, 11.4), 32, 0)
	grade(ctx, 0.14, 0.05, 0.12, Color3.fromRGB(255, 246, 222))
end

-- 42.867: from just below, Ryu hurtling at us: the camera climbs his bare
-- torso to his face - a bloody grin, fists at his sides; stones fly past
local function ryuRises(ctx: Timeline.Ctx)
	local t = ctx.t
	local rp = RYU + V(0, 4, 0)
	ctx:rig("RyuLoose", C(rp), Cast.alive({
		UpperTorso = R(-8, 0, 0),
		Head = R(10, 0, 14),
		RightUpperArm = R(20, 0, 34),
		RightLowerArm = R(90, 0, 0),
		LeftUpperArm = R(20, 0, -34),
		LeftLowerArm = R(90, 0, 0),
		LeftUpperLeg = R(20, 0, 0),
		RightUpperLeg = R(-10, 0, 0),
	}, t))
	fist(ctx, 1)
	Cast.expr(ctx, "ryu", "grit")
	bloodFace(ctx)
	local k = Util.smoothstep(42.9, 43.95, t)
	stonesAround(ctx, rp + V(0, 4.5, -1.6), 2.2, V(0, 0, 8), 40)
	cam(ctx, rp + V(0.3, 2.0 + k * 2.6, -3.3), rp + V(0, 3.5 + k * 2.2, 0), 56, 0.1, 1)
	ctx:alpha("wind", 0.5)
	ctx:gust(2.2)
	grade(ctx, -0.04, 0.28, 0.08, Color3.fromRGB(196, 210, 255))
	field(ctx)
end

-- 44.0: Yuta in profile, flying right, his right fist out in front; stones
local function yutaProfile(ctx: Timeline.Ctx)
	local t = ctx.t
	local yp = YUTA + V(0, 3, ctx.u * 0.6)
	local yb = ctx:rig("Yuta", C(yp) * CFrame.Angles(0, math.pi, 0), Cast.alive({
		UpperTorso = R(-14, 0, 0),
		Head = R(4, 0, 0),
		RightUpperArm = R(86, 0, -4),
		RightLowerArm = R(16, 0, 0),
		LeftUpperArm = R(30, 0, -10),
		LeftLowerArm = R(100, 0, 0),
		LeftUpperLeg = R(30, 0, 0),
		LeftLowerLeg = R(-60, 0, 0),
		RightUpperLeg = R(-20, 0, 0),
		RightLowerLeg = R(-30, 0, 0),
	}, t))
	Cast.expr(ctx, "yuta", "grit")
	ctx:show("yuta:blood")
	local head = (yb.Head * C(0, 0.5, 0)).Position
	stonesAround(ctx, head + V(-1, -0.5, 1.5), 1.6, V(0, 0, -7), 70, 0.3)
	cam(ctx, head + V(-3.6, 0.0, 2.8), head + V(0, -0.6, 1.0), 44, 0.08, 1)
	ctx:focus(4.3, 1)
	ctx:alpha("hstreaks", 0.6)
	ctx:gust(2.2)
	grade(ctx, -0.04, 0.26, 0.08, Color3.fromRGB(196, 210, 255))
	field(ctx)
end

-- 45.133: black; the camera glides past a row of cupcakes and a chocolate
-- cake with candles in a pool of warm light, then black again
local function darkCupcakes(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local t = ctx.t
	local lit = Util.smoothstep(45.22, 45.3, t) * (1 - Util.smoothstep(45.44, 45.5, t))
	local x = -30 - (t - 45.133) * 14
	voidWall(ctx, DESSERT + V(-34, 0, -1), V(0, 0, -1), Color3.new(0, 0, 0))
	ctx:place(h.lamp, C(DESSERT + V(x - 1, 4.5, -10)))
	ctx:light("P3Lamp", 4 * lit, Color3.fromRGB(255, 240, 214), 14)
	ctx:camera(Util.lookAt(DESSERT + V(x, 2.2, -11), DESSERT + V(x - 1, 1.4, -6)), 40)
	ctx:focus(5.5, 1)
	ctx:fog(0)
	ctx:wind(0)
	grade(ctx, -1 + lit * 0.7, 0.45, 0.05, Color3.fromRGB(255, 226, 180))
end

-- 45.633: the cross counter, side on: Yuta (left) and Ryu (right) both turned
-- a little to us, each fist in the other's face, arms crossed; they freeze,
-- heads wrenched back; the shock wave shivers through hair and clothes
local function crossCounter(ctx: Timeline.Ctx)
	local hh = h2(ctx)
	local t = ctx.t
	local hit = 45.7
	local dt = t - hit
	local k = math.max(strikeK(t, hit, 0.3), if dt > 0 then 1 else 0)
	local rb = ctx:rig("RyuLoose", C(RYU) * CFrame.Angles(0, math.rad(35), 0), Cast.alive(hitPose(punchPose(k), dt * 0.4, -10, 16, -14), t))
	local yb = ctx:rig("Yuta", yutaRoot() * CFrame.Angles(0, math.rad(-35), 0), Cast.alive(hitPose(punchPose(k, true), dt * 0.4, 10, 14, 12), t))
	Cast.expr(ctx, "ryu", "hit")
	Cast.expr(ctx, "yuta", "grit")
	bloodFace(ctx)
	ctx:show("yuta:blood")
	FX.placeBurst(ctx, hh.blood, (rb.Head * C(0, 0.4, -0.5)).Position, 0.2 + math.max(0, dt) * 0.15, 6, 0.16, 1.6, V(0, 0.4, 1), 0.6, 1)
	slabField(ctx, RYU + V(10, -1, -1.5), 9, 600, 3)
	local mid = (rb.Head.Position + yb.Head.Position) / 2 + V(0, -1.0, 0)
	cam(ctx, mid + V(-6.0, 0.3, 0), mid, 46, if dt > 0 and dt < 0.4 then 0.5 else 0.12, 0.5)
	ctx:alpha("speed", 0.12)
	ctx:gust(if t > 46.4 then 1.4 + math.sin(t * 50) * 0.8 else 0.8)
	grade(ctx, -0.04, 0.3, 0.1, Color3.fromRGB(196, 210, 255))
	field(ctx)
end

-- 47.833: Ryu reeling, head thrown back to the side, eyes on us, blood
-- streaming; he straightens into a wide bloody grin ("Heh!") and swings his
-- right arm up and back for another blow
local function heh(ctx: Timeline.Ctx)
	local t = ctx.t
	local reel = 1 - Util.smoothstep(48.5, 48.95, t)
	local cock = Util.smoothstep(49.0, 49.5, t)
	local pose = Cast.add(Cast.add(guard, "Head", R(20 * reel, -18 * reel, -22 * reel + 10 * cock)), "UpperTorso", R(12 * reel, 0, 0))
	pose = Cast.mix(pose, Cast.add(windupR, "Head", R(4, -10, 10)), cock * 0.8)
	local rb = ctx:rig("RyuLoose", C(RYU + V(0.3 * reel, 0, 0.5 * reel)), Cast.alive(pose, t, if t > 48.8 and t < 49.3 then 0.8 else 0))
	Cast.expr(ctx, "ryu", if reel > 0.5 then "grit" elseif t > 48.8 and t < 49.3 then "heh" else "grin")
	bloodFace(ctx)
	local head = rb.Head * C(0, 0.7, 0)
	stonesAround(ctx, RYU + V(0.6, 3.6, -1.6), 0.5, V(1.5, 3, 0), 120, 0.16)
	cam(ctx, RYU + V(-0.3, 5.0, -2.9), head.Position + V(0.1, -0.55, 0), 46, 0.05, 1)
	ctx:wind(1.6)
	ctx:gust(0.6 + cock)
	grade(ctx, -0.04, 0.28, 0.06, Color3.fromRGB(205, 218, 255))
	field(ctx)
end

-- 49.6: his sleeve sweeps past the lens, then the fist (fur cuff) rushes
-- left through blue speed lines
local function ryuFist2(ctx: Timeline.Ctx)
	local t = ctx.t
	local u = (t - 49.6) / 1.0
	-- the whole body flies with the blow: the camera rides alongside the fist
	-- and the speed blur streams past behind (as at 40.1)
	local travel = (t - 49.6) * 30
	local thrust = Util.smoothstep(0.05, 0.3, u)
	local root = C(RYU) * C(0, 14, -travel) * CFrame.Angles(0, math.rad(3 * math.sin(u * 7)), 0)
	local pose = Cast.add(Cast.mix(punchPose(-0.2), punchPose(1), thrust), "RightUpperArm", R(-12 + 3 * math.sin(t * 17), 0, 0))
	local rb = ctx:rig("RyuLoose", root, pose)
	fist(ctx, 1)
	local f = (rb.RightHand * C(0, -0.35, 0)).Position
	local camCF: CFrame
	local fov = 42
	if t < 49.75 then
		-- his black sleeve smearing past right in front of the lens
		local fa = (rb.RightLowerArm * C(0, -0.4, 0)).Position
		camCF = Util.lookAt(fa + V(-1.0, 0.1, -0.4), fa + V(0, 0, 0.5))
		fov = 50
		ctx:alpha("fbSmear", 0.5)
	else
		camCF = Util.lookAt(f + V(-1.9, -0.25, -0.1), f + V(0, 0, 0.5))
	end
	ctx:camera(shake(camCF, t, 0.1, 16), fov)
	ctx:focus(2, 1)
	speedBlur(ctx, fov, u, -1, f)
	FlashArt.key(ctx, V(0.5, 1.5, 1), 0.9, Color3.fromRGB(236, 242, 255), 20)
	ctx:alpha("hstreaks", 0.6)
	ctx:gust(2.4)
	ctx:wind(3)
	grade(ctx, -0.02, 0.24, 0.1, Color3.fromRGB(206, 218, 255))
	ctx:fog(0)
end

-- 50.6: Yuta calm in the middle of radial speed lines, Ryu's fist coming at
-- him from the lower left; 51.45 he tips his head aside and the fist and
-- sleeve slide past his cheek; close on his face, then his eye; black
local function yutaDodge(ctx: Timeline.Ctx)
	local t = ctx.t
	local tip = Util.smoothstep(51.4, 51.62, t)
	local yb = ctx:rig("Yuta", yutaRoot(), Cast.alive({
		UpperTorso = R(-6, 0, -8 * tip),
		Head = R(-4, 0, -26 * tip),
		LeftUpperArm = R(30, 0, -10),
		LeftLowerArm = R(100, 0, 0),
		RightUpperArm = R(10, 0, 10),
		RightLowerArm = R(30, 0, 0),
	}, t))
	Cast.expr(ctx, "yuta", "cold")
	ctx:show("yuta:blood")
	local head = yb.Head * C(0, 0.55, 0)
	local fk = Util.smoothstep(50.6, 51.6, t)
	local target = head:PointToWorldSpace(V(-0.2 - fk * 0.4, -0.7 + fk * 0.6, -2.6 + fk * 2.9))
	Common.rigAt(ctx, "RyuLoose", yutaRoot() * C(0.8, -1.4, -4.2) * CFrame.Angles(0, math.pi, 0), punchPose(1), "RightHand", C(0, -0.35, 0), target)
	fist(ctx, 1)
	if t < 51.9 then
		cam(ctx, (yutaRoot() * C(0.3, 4.4, -5.6)).Position, head.Position + V(0, -0.6, 0), 42, 0.05, 1)
		ctx:alpha("speed", if t < 51.4 then 0.16 else 0.08)
	elseif t < 52.4 then
		local zoom = Util.smoothstep(52.2, 52.35, t)
		cam(ctx, head:PointToWorldSpace(V(0.05, -0.1, -1.7 + zoom * 1.1)), head:PointToWorldSpace(V(-0.15 * zoom, -0.05, 0)), 44, 0.04, 1)
	else
		cam(ctx, head:PointToWorldSpace(V(0, 0, -1)), head.Position, 40, 0, 1)
	end
	local dark = Util.smoothstep(52.35, 52.45, t)
	grade(ctx, -0.02 - dark, 0.26, 0.06, Color3.fromRGB(205, 218, 255))
	ctx:gust(0.6 + tip * 1.6)
	field(ctx)
end

-- Ryu's jacket hauled up over his head: a black hood, its fur hem on top
local function hood(ctx: Timeline.Ctx, head: CFrame, k: number)
	local h = h3(ctx)
	if k <= 0 then
		return
	end
	local base = head * C(0, 0.95 + 0.25 * k, 0.1)
	ctx:place(h.hood, base)
	ctx:prop(h.hood, { s = V(1.8, 1.0 + 1.1 * k, 1.8) })
	-- the white fur hem: a ring of tufts round the top
	for i, p in h.hoodFur do
		local a = i / #h.hoodFur * math.pi * 2
		ctx:place(p, base * C(math.cos(a) * 0.6, 0.55 + 0.5 * k, math.sin(a) * 0.6) * CFrame.Angles(math.sin(a) * 0.9, 0, -math.cos(a) * 0.9))
		ctx:prop(p, { s = V(0.42, 0.8, 0.42), c = Color3.fromRGB(240, 240, 244) })
	end
end

-- 52.867: Yuta's hands drag Ryu's jacket up over his head - the white fur
-- now on top; 53.8 the frame splits: in a slanted strip Ryu's eye, wide
local function hoodGrab(ctx: Timeline.Ctx)
	local t = ctx.t
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({ UpperTorso = R(-24, 0, 0), Head = R(-16, 0, 0), RightUpperArm = R(10, 0, 20), LeftUpperArm = R(10, 0, -20) }, t))
	local pull = Util.smoothstep(52.9, 53.4, t)
	hood(ctx, rb.Head, 0.5 + pull * 0.5)
	Cast.furLow(ctx, "RyuLoose", 1)
	local grip = rb.Head * C(0, 1.3 + pull * 0.2, 0)
	local yp: Rig.Pose = {
		UpperTorso = R(-6, 0, 0),
		RightUpperArm = R(110, 0, 20),
		RightLowerArm = R(40, 0, 0),
		RightHand = R(-30, 0, 0),
		LeftUpperArm = R(70, 0, -20),
		LeftLowerArm = R(90, 0, 0),
		LeftHand = R(-20, 0, 0),
	}
	Common.rigAt(ctx, "Yuta", yutaRoot(), yp, "RightHand", C(0, -0.3, 0), grip:PointToWorldSpace(V(0.7, 0, -0.2)))
	if t >= 53.8 then
		Cast.expr(ctx, "ryu", "shock")
		bloodFace(ctx)
		local face = rb.Head * C(0, 0.7, 0)
		cam(ctx, face:PointToWorldSpace(V(-2.0, 0.05, -0.75)), face:PointToWorldSpace(V(0, 0.05, -0.3)), 32, 0, 1)
		ctx:show("splitStrip")
	else
		-- Yuta's view: his two hands hauling the black cloth up, the fur on top
		local g = grip.Position
		cam(ctx, g + V(0.4, -0.5, -2.2), g + V(0, -0.35, 0), 46, 0.05, 1)
	end
	ctx:gust(0.8)
	grade(ctx, -0.04, 0.26, 0.06, Color3.fromRGB(205, 218, 255))
	field(ctx)
end

-- 55.0: Yuta's eye, calm, over his ringed left fist clenched in the cloth
-- over Ryu's head; "Now we're done." (55.07-56.53, lips barely moving)
local function done(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local t = ctx.t
	local yb = ctx:rig("Yuta", yutaRoot(), Cast.alive({
		UpperTorso = R(-8, 0, 0),
		Head = R(-14, 0, 0),
		LeftUpperArm = R(70, 0, 6),
		LeftLowerArm = R(60, 0, 30),
		LeftHand = R(10, 0, 0),
		RightUpperArm = R(40, 0, 10),
		RightLowerArm = R(60, 0, 0),
	}, t))
	local speaking = t >= 55.07 and t < 56.53
	Cast.expr(ctx, "yuta", if speaking and Util.noise1(t * 7.5, 5) > 0.1 then "talk" else "cold")
	ctx:show("yuta:blood")
	local hp = yb.Head * C(0, 0.55, 0)
	local fistP = (yb.LeftHand * C(0, -0.3, 0)).Position
	local d = (fistP - hp.Position).Unit
	-- Ryu's hooded head just beyond the fist: the black cloth gripped in the
	-- fist, the white fur hem of the jacket on top of his head
	local headC = fistP + d * 0.75
	local left = -hp.RightVector
	ctx:place(h.hood, Util.lookAt(fistP + d * 0.45, fistP + d * 2))
	ctx:prop(h.hood, { s = V(1.2, 1.1, 1.3) })
	for i, p in h.hoodFur do
		local a = i / #h.hoodFur * math.pi * 2
		local at = headC + left * math.cos(a) * 0.5 + d * math.sin(a) * 0.5 + V(0, 0.55, 0)
		ctx:place(p, CFrame.new(at) * CFrame.Angles(math.sin(a) * 0.8, a, -math.cos(a) * 0.8))
		ctx:prop(p, { s = V(0.45, 0.85, 0.45), c = Color3.fromRGB(240, 240, 244) })
	end
	-- beside his head, close to the fist, looking past it at Yuta's eye
	local eye = hp:PointToWorldSpace(V(-0.22, 0.02, -0.5))
	local camPos = headC + left * 1.0 - d * 0.35 + V(0, 0.1, 0)
	cam(ctx, camPos, eye:Lerp(fistP, 0.5), 50, 0, 1)
	ctx:focus((eye - camPos).Magnitude, 1)
	ctx:wind(1.1)
	grade(ctx, -0.06, 0.28, 0.05)
	field(ctx)
end

Part3.shots = {
	{ id = "P3 01 rika holds ryu", t0 = 2.633, t1 = 6.533, run = rikaHold },
	{ id = "P3 02 ryu lifts his head", t0 = 6.533, t1 = 7.8, run = ryuLifts },
	{ id = "P3 03 rika mask", t0 = 7.8, t1 = 8.033, run = rikaMask },
	{ id = "P3 04 punch into the mask", t0 = 8.033, t1 = 8.2, run = punchMask },
	{ id = "P3 05 yuta startled", t0 = 8.2, t1 = 8.533, run = yutaStartle },
	{ id = "P3 06 rika punched", t0 = 8.533, t1 = 10.5, run = rikaPunched },
	{ id = "P3 07 ryu in the fur", t0 = 10.5, t1 = 12.0, run = ryuFur },
	{ id = "P3 08 rika down", t0 = 12.0, t1 = 14.1, run = rikaDown },
	{ id = "P3 09 yuta hand", t0 = 14.1, t1 = 15.433, run = yutaHand },
	{ id = "P3 10 kick", t0 = 15.433, t1 = 17.633, run = kick },
	{ id = "P3 11 ryu hand", t0 = 17.633, t1 = 19.9, run = ryuHand },
	{ id = "P3 12 yuta bent over", t0 = 19.9, t1 = 21.267, run = bentOver },
	{ id = "P3 13 yuta looks up", t0 = 21.267, t1 = 23.033, run = yutaLooksUp },
	{ id = "P3 14 top exchange", t0 = 23.033, t1 = 24.233, run = topExchange },
	{ id = "P3 15 face smash", t0 = 24.233, t1 = 24.567, run = faceSmash },
	{ id = "P3 16 side exchange", t0 = 24.567, t1 = 25.833, run = sideExchange },
	{ id = "P3 17 black flash", t0 = 25.833, t1 = 29.167, run = blackFlash },
	{ id = "P3 18 desserts", t0 = 29.167, t1 = 33.167, run = desserts },
	{ id = "P3 19 body blows", t0 = 33.167, t1 = 33.9, run = bodyBlows },
	{ id = "P3 20 dessert pan", t0 = 33.9, t1 = 34.9, run = dessertPan },
	{ id = "P3 21 ryu swings", t0 = 34.9, t1 = 35.667, run = ryuSwings },
	{ id = "P3 22 table spin", t0 = 35.667, t1 = 36.8, run = cheeseSpin },
	{ id = "P3 23 rubble", t0 = 36.8, t1 = 37.8, run = rubble },
	{ id = "P3 24 tart", t0 = 37.8, t1 = 38.667, run = tartTop },
	{ id = "P3 25 top spin", t0 = 38.667, t1 = 39.5, run = topSpin },
	{ id = "P3 26 fists", t0 = 39.5, t1 = 40.733, run = fists },
	{ id = "P3 27 parfait", t0 = 40.733, t1 = 41.75, run = parfait },
	{ id = "P3 28 sponge", t0 = 41.75, t1 = 42.867, run = spongeGone },
	{ id = "P3 29 ryu rises", t0 = 42.867, t1 = 44.0, run = ryuRises },
	{ id = "P3 30 yuta profile", t0 = 44.0, t1 = 45.133, run = yutaProfile },
	{ id = "P3 31 dark cupcakes", t0 = 45.133, t1 = 45.633, run = darkCupcakes },
	{ id = "P3 32 cross counter", t0 = 45.633, t1 = 47.833, run = crossCounter },
	{ id = "P3 33 heh", t0 = 47.833, t1 = 49.6, run = heh },
	{ id = "P3 34 ryu fist", t0 = 49.6, t1 = 50.6, run = ryuFist2 },
	{ id = "P3 35 yuta dodges", t0 = 50.6, t1 = 52.867, run = yutaDodge },
	{ id = "P3 36 hood", t0 = 52.867, t1 = 55.0, run = hoodGrab },
	{ id = "P3 37 done", t0 = 55.0, t1 = 56.867, run = done },
} :: { Timeline.Shot }

return Part3
