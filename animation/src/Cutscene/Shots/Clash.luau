--!strict
-- The clash of the two techniques, staged in an abstract dark void high above
-- the field: Ryu's cyan Granite Blast meets Rika's pink beam; white core,
-- radial rays, shards, yellow splashes, sparks. Also the full-screen 2D
-- beats (impact frame, speed lines, starburst) and the night-city wide shot.
--   3  5.733- 6.300 white-hot burst            4  6.300- 8.733 beams collide
--   5  8.733- 9.600 night city, clouds collide  8 12.100-15.233 radial clash
--  10 19.933-20.667 radial burst              11 20.667-20.700 impact frame
--  12 20.700-21.367 colour splashes           16 22.333-22.567 speed lines
--  25 35.100-35.600 pink streak               29 41.300-42.200 pink vs lightning
--  35 53.967-54.100 starburst
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local FX = require(script.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Util)
local Paint = require(script.Parent.Parent.Paint)
local Overlay = require(script.Parent.Overlay)

local Clash = {}

local V = Vector3.new
local C = CFrame.new
local O = V(0, 3000, 0) -- centre of the clash

type H = {
	walls: { Builder.PartSpec },
	cyan: FX.Beam,
	pink: FX.Beam,
	core: Builder.PartSpec,
	glow: Builder.PartSpec,
	glow2: Builder.PartSpec,
	ring: Builder.PartSpec,
	rays: FX.Rays,
	shardsC: FX.Burst,
	shardsP: FX.Burst,
	splash: FX.Burst,
	splash2: FX.Burst,
	bolts: FX.Bolt,
	sparks: Builder.PartSpec,
	city: { Builder.PartSpec },
	cityBack: Builder.PartSpec,
	cityGround: Builder.PartSpec,
	swarmC: FX.Burst,
	swarmP: FX.Burst,
}

-- Painted backdrop for the night-city shot: night sky glowing over the
-- horizon, two layers of skyline with lit windows (canvas px = 1/10 stud)
local CITY_W, CITY_H = 1600, 900
local function cityBackdrop(scene: Builder.Scene): Builder.PartSpec
	local hex = Util.hex
	local c = Paint.canvas(1, 0, 0)
	c:grad(0, 0, CITY_W, CITY_H, {
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, hex("#0B1440")),
			ColorSequenceKeypoint.new(0.24, hex("#1E3276")),
			ColorSequenceKeypoint.new(0.36, hex("#3A5CA4")),
			ColorSequenceKeypoint.new(0.5, hex("#22386E")),
			ColorSequenceKeypoint.new(1, hex("#141F3E")),
		}),
		rotation = 90,
	})
	-- thin clouds lit from below
	local r = Util.rng(919)
	for _ = 1, 9 do
		local w = Util.randRange(r, 260, 560)
		c:blob(Util.randRange(r, 0, CITY_W), Util.randRange(r, 110, 290), w, w * 0.14, hex("#3A5A9E"), 0.25)
	end
	local warm, cool = hex("#F4D9A2"), hex("#A8DCFF")
	local function skyline(y0: number, y1: number, wMin: number, wMax: number, col: Color3, winA: number, winP: number)
		local x = Util.randRange(r, -30, 0)
		while x < CITY_W do
			local w = Util.randRange(r, wMin, wMax)
			local top = Util.randRange(r, y0, y1)
			c:box(x, top, x + w, CITY_H, col)
			if Util.rand(r) < 0.3 then -- antenna / roof box
				c:box(x + w * 0.4, top - Util.randRange(r, 10, 30), x + w * 0.46, top, col)
			end
			-- window grid, some lit
			local cols = math.max(1, math.floor((w - 8) / 11))
			local rows = math.min(14, math.floor((CITY_H - top - 10) / 15))
			for row = 0, rows - 1 do
				for col2 = 0, cols - 1 do
					if Util.rand(r) < winP then
						local wx = x + 6 + col2 * 11 + 2.5
						local wy = top + 10 + row * 15 + 3.5
						c:rect(wx, wy, 5, 7, 0, if Util.rand(r) < 0.7 then warm else cool, 1 - winA * Util.randRange(r, 0.5, 1))
					end
				end
			end
			x += w + Util.randRange(r, 2, 14)
		end
	end
	-- the camera looks 7 degrees down: the horizon sits at 36% of the height
	skyline(250, 330, 30, 90, hex("#1A2A50"), 0.5, 0.16)
	skyline(300, 390, 50, 120, hex("#101A34"), 0.7, 0.14)
	return Builder.part(scene, "ClashCity", V(CITY_W / 10, CITY_H / 10, 0.05), C(), Color3.new(1, 1, 1), {
		transparency = 1,
		castShadow = false,
		fx = true,
		name = "CityBackdrop",
		gui = { face = "Front", canvas = Vector2.new(CITY_W, CITY_H), lightInfluence = 0, elems = c.elems },
	})
end

function Clash.build(scene: Builder.Scene)
	local pal = scene.style.color
	Overlay.build(scene)
	-- dark void: six walls (recoloured per shot)
	local walls = {}
	local S = 200
	for i, cf in
		{
			C(O + V(0, 0, -S / 2)),
			C(O + V(0, 0, S / 2)),
			C(O + V(-S / 2, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0),
			C(O + V(S / 2, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0),
			C(O + V(0, -S / 2, 0)) * CFrame.Angles(math.pi / 2, 0, 0),
			C(O + V(0, S / 2, 0)) * CFrame.Angles(math.pi / 2, 0, 0),
		}
	do
		walls[i] = Builder.fx(scene, "ClashVoid", "Block", V(S, S, 2), Color3.fromRGB(10, 26, 24), "SmoothPlastic", 0, "Void")
		walls[i].castShadow = false
		walls[i].cf = cf
	end
	local rays = FX.rays(scene, "Rays", { pal.eCyan, pal.ePink, pal.eWhite, pal.eYellow, pal.eMagenta }, 46, 5)
	local h: H = {
		walls = walls,
		cyan = FX.beam(scene, "CyanBeam", pal.eCyan, true),
		pink = FX.beam(scene, "PinkBeam", pal.ePink, true),
		core = FX.core(scene, "ClashCore", pal.eWhite),
		glow = FX.core(scene, "ClashGlow", pal.eCyan),
		glow2 = FX.core(scene, "ClashGlow2", pal.ePink),
		ring = FX.ring(scene, "ClashRing", pal.eWhite),
		rays = rays,
		shardsC = FX.burst(scene, "ShardsC", pal.eCyan, 30, "Wedge", 3),
		shardsP = FX.burst(scene, "ShardsP", pal.ePink, 30, "Wedge", 4),
		splash = FX.burst(scene, "Splash", pal.eYellow, 24, "Ellipsoid", 5),
		splash2 = FX.burst(scene, "Splash2", pal.eOrange, 14, "Ellipsoid", 6),
		bolts = FX.bolts(scene, "ClashBolts", pal.eYellow, 40),
		sparks = Builder.fx(scene, "ClashVoid", "Block", V(2, 2, 2), Color3.new(1, 1, 1), "SmoothPlastic", 1, "SparkBox"),
		city = {},
		cityBack = cityBackdrop(scene),
		cityGround = Builder.fx(scene, "ClashCity", "Block", V(400, 1, 300), Util.hex("#0A0F1C"), "Concrete", 0, "Streets"),
		swarmC = FX.burst(scene, "SwarmC", pal.eCyan, 60, "Wedge", 7),
		swarmP = FX.burst(scene, "SwarmP", pal.ePink, 60, "Wedge", 8),
	}
	Builder.emitter(scene, "ClashSparks", "sparks", h.sparks, pal.eRed, 1.6, 1.4)
	Builder.emitter(scene, "ClashShards", "shards", h.sparks, pal.eYellow, 1.3, 1.2)
	-- the two energy clouds light the city (shot 5)
	Builder.light(scene, "CityCyan", "Point", h.glow, pal.eCyan, 90)
	Builder.light(scene, "CityPink", "Point", h.glow2, pal.ePink, 90)
	-- night city blocks for shot 5, lit windows on the side facing the camera
	local r = Util.rng(808)
	local rw = Util.rng(809)
	local warm, cool = Util.hex("#F4D9A2"), Util.hex("#A8DCFF")
	for i = 1, 33 do
		local near = i > 22 -- third row, right under the camera: low blocks
		local w, hh, d = Util.randRange(r, 10, 24), if near then Util.randRange(r, 8, 16) else Util.randRange(r, 10, 34), Util.randRange(r, 10, 20)
		local c = Paint.canvas(10, 0, 0) -- drawn in studs, 10 canvas px per stud
		local cols, rows = math.floor((w - 1.4) / 2.6), math.floor((hh - 2) / 3.2)
		for row = 0, rows - 1 do
			for col = 0, cols - 1 do
				if Util.rand(rw) < 0.28 then
					local x = (w - cols * 2.6) / 2 + col * 2.6 + 1.3
					c:rect(x, 2 + row * 3.2, 1.2, 1.6, 0, if Util.rand(rw) < 0.7 then warm else cool, Util.randRange(rw, 0.05, 0.45))
				end
			end
		end
		h.city[i] = Builder.part(scene, "ClashCity", V(w, hh, d), C(), Util.mix(pal.city, pal.cityLight, Util.rand(r)), {
			material = "Concrete",
			castShadow = false,
			fx = true,
			name = "Building",
			gui = { face = "Front", canvas = Vector2.new(w * 10, hh * 10), lightInfluence = 0, elems = c.elems },
		})
	end
	scene.data.clash = h
end

-- camera shake on top of a camera CFrame
local function shake(cf: CFrame, t: number, amp: number, freq: number?): CFrame
	local f = freq or 18
	local x = Util.noise1(t * f, 1) * amp
	local y = Util.noise1(t * f, 2) * amp
	local r = Util.noise1(t * f * 0.7, 3) * amp * 0.6
	return cf * CFrame.Angles(math.rad(y * 3), math.rad(x * 3), math.rad(r * 3))
end
Clash.shake = shake

local function void(ctx: Timeline.Ctx, col: Color3)
	local h: H = ctx.scene.data.clash
	for _, w in h.walls do
		ctx:place(w, w.cf)
		ctx:prop(w, { c = col })
	end
	ctx:fog(0.15)
end

local function grade(ctx: Timeline.Ctx, contrast: number, sat: number, bright: number?)
	ctx:grade({ brightness = bright or 0, contrast = contrast, saturation = sat, tint = Color3.new(1, 1, 1) })
end

-- the collision point with both beams, core, rays and debris
local function clashCore(ctx: Timeline.Ctx, age: number, intensity: number, beams: boolean, raysK: number, splashK: number)
	local h: H = ctx.scene.data.clash
	local pal = ctx.scene.style.color
	if beams then
		FX.placeBeam(ctx, h.cyan, O + V(-140, -6, 10), O, 5.5, intensity)
		FX.placeBeam(ctx, h.pink, O + V(140, 8, -10), O, 5.5, intensity)
	end
	local pulse = 1 + math.sin(ctx.t * 37) * 0.08
	FX.placeCore(ctx, h.core, O, 4.2 * pulse * intensity, intensity)
	FX.placeCore(ctx, h.glow, O + V(-1.5, 0, 0), 7 * pulse, 0.45 * intensity)
	FX.placeCore(ctx, h.glow2, O + V(1.5, 0, 0), 6.5 * pulse, 0.4 * intensity)
	FX.placeRays(ctx, h.rays, O, ctx.frame.camera.Rotation, 34, 0.55, raysK, 14)
	local a = age % 0.9
	FX.placeBurst(ctx, h.shardsC, O, a, 70, 1.4, 0.8, V(-0.3, 0.5, 1), 1.0, 10)
	FX.placeBurst(ctx, h.shardsP, O, (age + 0.45) % 0.9, 70, 1.4, 0.8, V(0.3, 0.4, 1), 1.0, 10)
	if splashK > 0 then
		FX.placeBurst(ctx, h.splash, O, (age * 0.8) % 1.2, 40 * splashK, 3.2, 1.1, V(0, 0.3, 1), 1.2, 6)
		FX.placeBurst(ctx, h.splash2, O, (age * 0.8 + 0.5) % 1.2, 34 * splashK, 2.4, 1.0, nil, nil, 6)
	end
	ctx:place(h.sparks, C(O))
	ctx:emit("ClashSparks", 160 * intensity)
	ctx:emit("ClashShards", 60 * intensity)
	local _ = pal
end

-- 3: white-hot burst filling the screen
local function burst(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.clash
	void(ctx, Color3.fromRGB(14, 40, 34))
	local cam = Util.lookAt(O + V(-6, -4, 60), O)
	ctx:camera(shake(cam, ctx.t, 0.8), 70)
	ctx:focus(60, 0)
	clashCore(ctx, ctx.lt, 1, true, 1, 0.4)
	FX.placeCore(ctx, h.core, O, 10 + ctx.u * 30, 1 - ctx.u * 0.4)
	FX.placeRing(ctx, h.ring, O, V(0, 0, 1), 8 + ctx.u * 60, 1.2, 1 - ctx.u)
	ctx:flash(Color3.new(1, 1, 1), math.max(0, 0.9 - ctx.lt * 3))
	ctx:bloom(2.4)
	grade(ctx, 0.2, 0.25)
end

-- 4: the two beams grinding against each other
local function collide(ctx: Timeline.Ctx)
	void(ctx, Color3.fromRGB(12, 36, 30))
	local orbit = math.rad(-25 + ctx.u * 12)
	local eye = O + V(math.sin(orbit) * 55, 6, math.cos(orbit) * 55)
	ctx:camera(shake(Util.lookAt(eye, O + V(0, -2, 0)), ctx.t, 0.6), 62)
	ctx:focus(55, 0)
	clashCore(ctx, ctx.lt, 1, true, 0.8, 1)
	ctx:bloom(1.9)
	grade(ctx, 0.22, 0.3)
end

-- 5: wide night view, a cyan and a magenta cloud of energy colliding over a ruined city
local function city(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.clash
	ctx:fog(0.15) -- no void walls here: the painted sky fills the frame
	local base = O + V(0, -60, -30)
	-- high over the rooftops, looking 7 degrees down
	local cam = Util.lookAt(base + V(0, 46, 110), base + V(0, 30, -20))
	ctx:camera(cam * CFrame.new(ctx.u * 2, 0, 0), 50)
	ctx:focus(150, 0)
	-- painted sky and skyline behind the 3D blocks, filling the frame
	local depth = 180
	local need = 2 * depth * math.tan(math.rad(50) / 2) * 1.06
	local k = need / h.cityBack.size.Y
	ctx:place(h.cityBack, cam * C(0, 0, -depth) * CFrame.Angles(0, math.pi, 0))
	ctx:prop(h.cityBack, { s = V(h.cityBack.size.X * k, h.cityBack.size.Y * k, 0.05) })
	ctx:place(h.cityGround, C(base + V(0, -0.5, -20)))
	-- three rows of blocks (windows on their Front face, turned to the camera)
	local r = Util.rng(808)
	for i, b in h.city do
		local row = (i - 1) // 11
		local x = -95 + ((i - 1) % 11) * 19 + Util.randRange(r, -4, 4)
		local z = -30 + row * 35 + Util.randRange(r, -6, 6)
		ctx:place(b, C(base + V(x, b.size.Y / 2, z)) * CFrame.Angles(0, math.pi, 0))
	end
	-- two swarms flowing into each other
	local function swarm(bu: FX.Burst, from: Vector3, seed: number)
		local rr = Util.rng(seed)
		for i, p in bu.parts do
			local f = ((ctx.t * 0.7 + i / #bu.parts) % 1)
			local spread = V(Util.randRange(rr, -1, 1), Util.randRange(rr, -1, 1), Util.randRange(rr, -1, 1)) * 18
			local pos = from:Lerp(base + V(0, 40, 0), f) + spread * (1 - f * 0.6)
			local s = Util.randRange(rr, 1, 3.5)
			ctx:place(p, FX.along(pos, pos + V(1, Util.randRange(rr, -1, 1), 0.3)))
			ctx:prop(p, { s = V(s * 2.2, s, s * 0.4), t = f * 0.4 })
		end
	end
	swarm(h.swarmC, base + V(55, 44, 0), 1)
	swarm(h.swarmP, base + V(-55, 38, 0), 2)
	FX.placeCore(ctx, h.core, base + V(0, 40, 0), 5, 0.9)
	FX.placeCore(ctx, h.glow, base + V(26, 42, 4), 2.5, 0.5)
	FX.placeCore(ctx, h.glow2, base + V(-26, 40, 4), 2.5, 0.5)
	ctx:light("CityCyan", 6, nil, 90)
	ctx:light("CityPink", 6, nil, 90)
	ctx:bloom(2)
	grade(ctx, 0.15, 0.2, -0.03)
end

-- 8 / 10: head-on radial clash, rays shooting at the camera
local function radial(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.clash
	void(ctx, Color3.fromRGB(8, 12, 40))
	local cam = Util.lookAt(O + V(0, 0, 38 - ctx.u * 8), O)
	ctx:camera(shake(cam * CFrame.Angles(0, 0, ctx.t * 0.6), ctx.t, 0.9, 22), 75)
	ctx:focus(30, 0)
	clashCore(ctx, ctx.lt, 1, false, 1, 0.7)
	FX.placeRays(ctx, h.rays, O, ctx.frame.camera.Rotation, 50, 0.9, 1, 16, V(0, 0, 1))
	local fl = math.max(0, math.sin(ctx.t * 9)) ^ 8
	ctx:flash(Color3.new(1, 1, 1), fl * 0.5)
	ctx:bloom(2.2)
	grade(ctx, 0.25, 0.35)
end

local function impact(ctx: Timeline.Ctx)
	ctx:camera(C(O + V(0, 0, 40)), 70)
	ctx:alpha("impact", 1)
end

-- 12: colour splashes filling the frame
local function splashes(ctx: Timeline.Ctx)
	void(ctx, Color3.fromRGB(20, 18, 50))
	local cam = Util.lookAt(O + V(10, 4, 26), O)
	ctx:camera(shake(cam, ctx.t, 1.2, 25), 70)
	ctx:focus(26, 0)
	clashCore(ctx, ctx.lt + 0.3, 1, true, 1, 1.6)
	ctx:bloom(2.4)
	grade(ctx, 0.25, 0.4)
end

local function speedLines(ctx: Timeline.Ctx)
	void(ctx, Color3.fromRGB(40, 110, 220))
	ctx:camera(C(O + V(0, 0, 40)), 70)
	ctx:alpha("speed", 1)
	ctx:flash(Color3.fromRGB(70, 150, 255), 0.35)
end

-- 25: the pink beam whips past the camera
local function pinkStreak(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.clash
	void(ctx, Color3.fromRGB(26, 34, 80))
	local cam = C(O + V(0, 0, 30)) * CFrame.Angles(0, 0, math.rad(-20 + ctx.u * 25))
	ctx:camera(shake(cam, ctx.t, 1.5, 28), 70)
	ctx:focus(30, 0)
	local x = -6 + ctx.u * 10
	FX.placeBeam(ctx, h.pink, O + V(x - 4, -60, 0), O + V(x + 6, 60, 5), 5, 1, 2)
	ctx:alpha("streaks", 0.6)
	ctx:bloom(2)
end

-- 29: pink beam tangled with yellow lightning
local function pinkVsLightning(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.clash
	void(ctx, Color3.fromRGB(30, 14, 50))
	local cam = Util.lookAt(O + V(-20, 4, 44), O + V(8, 0, 0))
	ctx:camera(shake(cam, ctx.t, 0.8), 60)
	ctx:focus(44, 0)
	FX.placeBeam(ctx, h.pink, O + V(-140, 0, 0), O + V(20, 2, 0), 7, 1)
	local idx = 1
	for i = 1, 6 do
		local a = O + V(-60 + i * 8, (i % 2) * 6 - 3, 0)
		idx = FX.placeBolt(ctx, h.bolts, idx, a, a + V(30, math.sin(i) * 10, math.cos(i) * 6), 6, 0.25, 0.25, i + 10, 18)
	end
	FX.placeCore(ctx, h.core, O + V(20, 2, 0), 5 + ctx.u * 4, 1)
	ctx:place(h.sparks, C(O + V(20, 2, 0)))
	ctx:emit("ClashSparks", 200)
	ctx:bloom(2.2)
	grade(ctx, 0.2, 0.3)
end

local function starburst(ctx: Timeline.Ctx)
	ctx:camera(C(O + V(0, 0, 40)), 70)
	ctx:alpha("starburst", 1)
end

Clash.shots = {
	{ id = "03 burst", t0 = 5.733, t1 = 6.3, run = burst },
	{ id = "04 collide", t0 = 6.3, t1 = 8.733, run = collide },
	{ id = "05 city", t0 = 8.733, t1 = 9.6, run = city },
	{ id = "08 radial", t0 = 12.1, t1 = 15.233, run = radial },
	{ id = "10 burst", t0 = 19.933, t1 = 20.667, run = radial },
	{ id = "11 impact", t0 = 20.667, t1 = 20.7, run = impact },
	{ id = "12 splashes", t0 = 20.7, t1 = 21.367, run = splashes },
	{ id = "16 speed", t0 = 22.333, t1 = 22.567, run = speedLines },
	{ id = "25 streak", t0 = 35.1, t1 = 35.6, run = pinkStreak },
	{ id = "29 lightning", t0 = 41.3, t1 = 42.2, run = pinkVsLightning },
	{ id = "35 starburst", t0 = 53.967, t1 = 54.1, run = starburst },
} :: { Timeline.Shot }

return Clash
