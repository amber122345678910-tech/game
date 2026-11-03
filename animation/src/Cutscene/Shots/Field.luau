--!strict
-- The battlefield: a frozen snowfield with cracked ice, a rubble crater, the
-- trench Rika's beam carves, ruined city blocks in the distance, mist plates
-- that follow the camera and falling snow.
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local Paint = require(script.Parent.Parent.Paint)
local Util = require(script.Parent.Parent.Util)

local Field = {}

local V = Vector3.new
local C = CFrame.new

-- reference positions (studs)
Field.RYU = V(-31, 0, -117) -- where Ryu stands for most of the fight
Field.YUTA = V(36, 0, -134)
Field.RIKA = V(25, 0, -119)
Field.CRATER = V(-6, 0, -146)

export type Handles = {
	mist: { [string]: Builder.PartSpec },
	snow: Builder.PartSpec,
}

local function rubble(scene: Builder.Scene, r: Util.Rng, center: Vector3, radius: number, n: number, size: number, cols: { Color3 }, mat: string)
	for i = 1, n do
		local a = Util.randRange(r, 0, math.pi * 2)
		local d = radius * math.sqrt(Util.rand(r))
		local s = size * Util.randRange(r, 0.4, 1.5)
		local p = center + V(math.cos(a) * d, s * 0.25, math.sin(a) * d)
		local shape = if i % 3 == 0 then "Wedge" else "Block"
		Builder.part(scene, "Field", V(s * Util.randRange(r, 0.7, 1.6), s * Util.randRange(r, 0.4, 1.0), s * Util.randRange(r, 0.7, 1.4)), C(p) * CFrame.Angles(Util.randRange(r, -0.6, 0.6), Util.randRange(r, 0, 6.28), Util.randRange(r, -0.6, 0.6)), cols[(i % #cols) + 1], { shape = shape, material = mat, name = "Rubble" })
	end
end

local function cracks(scene: Builder.Scene, r: Util.Rng, center: Vector3, n: number, len: number, col: Color3)
	for _ = 1, n do
		local a = Util.randRange(r, 0, math.pi * 2)
		local p = center + V(Util.randRange(r, -20, 20), 0.06, Util.randRange(r, -20, 20))
		local segs = math.floor(Util.randRange(r, 3, 7))
		for _ = 1, segs do
			a += Util.randRange(r, -0.7, 0.7)
			local l = len * Util.randRange(r, 0.4, 1.0)
			local q = p + V(math.cos(a) * l, 0, math.sin(a) * l)
			local mid = (p + q) / 2
			Builder.part(scene, "Field", V(l, 0.05, Util.randRange(r, 0.08, 0.22)), C(mid) * CFrame.Angles(0, -a, 0), col, { material = "SmoothPlastic", castShadow = false, name = "Crack" })
			p = q
		end
	end
end

-- soft mist painting for a camera plate (canvas units = 1/10 stud)
local function mistPlate(scene: Builder.Scene, name: string, w: number, h: number, seed: number, paint: (Paint.Canvas, Util.Rng) -> ()): Builder.PartSpec
	local c = Paint.canvas(1, 0, 0)
	paint(c, Util.rng(seed))
	local p = Builder.part(scene, "Mist", V(w / 10, h / 10, 0.05), C(), Color3.new(1, 1, 1), {
		transparency = 1,
		castShadow = false,
		fx = true,
		name = name,
		gui = { face = "Front", canvas = Vector2.new(w, h), lightInfluence = 0, elems = c.elems },
	})
	return p
end

function Field.build(scene: Builder.Scene)
	local st = scene.style
	local pal = st.color
	Builder.model(scene, "Field", false)
	Builder.model(scene, "Mist", false)
	local r = Util.rng(4242)

	-- snow ground and ice sheets
	Builder.part(scene, "Field", V(3000, 4, 3000), C(0, -2, -600), pal.snow, { material = st.material.ground, castShadow = false, name = "Ground" })
	for i = 1, 14 do
		local p = V(Util.randRange(r, -90, 80), 0.02, Util.randRange(r, -220, -60))
		local s = V(Util.randRange(r, 20, 60), 0.06, Util.randRange(r, 14, 40))
		Builder.part(scene, "Field", s, C(p) * CFrame.Angles(0, Util.randRange(r, 0, 6.28), 0), Util.mix(pal.ice, pal.snow, Util.randRange(r, 0, 0.5)), { material = "Glacier", castShadow = false, name = "IceSheet" })
	end
	cracks(scene, r, V(-15, 0, -125), 26, 5, pal.crack)
	cracks(scene, r, V(20, 0, -140), 16, 6, pal.crack)
	-- crater of broken ice and rock in front of Ryu
	local cr = Field.CRATER
	Builder.part(scene, "Field", V(1, 26, 26), C(cr + V(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), pal.rubble, { shape = "Cylinder", material = "Slate", castShadow = false, name = "CraterFloor" })
	rubble(scene, r, cr, 13, 70, 2.2, { pal.rubble, pal.rubbleLight, pal.iceDark }, "Slate")
	rubble(scene, r, cr, 15, 30, 1.6, { pal.ice, pal.snow }, "Glacier")
	-- trench carved by Rika's beam (seen from above), running at Ryu
	local t0, t1 = V(70, 0, -60), Field.RYU + V(6, 0, -4)
	local dir = (t1 - t0)
	for i = 0, 26 do
		local f = i / 26
		local p = t0 + dir * f
		local side = dir:Cross(V(0, 1, 0)).Unit
		for sgn = -1, 1, 2 do
			local q = p + side * sgn * Util.randRange(r, 2.2, 3.2)
			local s = Util.randRange(r, 1.0, 2.2)
			Builder.part(scene, "Field", V(s * 1.4, s * 0.7, s), C(q + V(0, s * 0.25, 0)) * CFrame.Angles(Util.randRange(r, -0.5, 0.5), Util.randRange(r, 0, 6.28), Util.randRange(r, -0.5, 0.5)), if i % 2 == 0 then pal.rubble else pal.iceDark, { material = "Slate", name = "TrenchRubble" })
		end
	end
	local mid = (t0 + t1) / 2
	Builder.part(scene, "Field", V(dir.Magnitude, 0.1, 4.2), C(mid + V(0, 0.05, 0)) * CFrame.Angles(0, -math.atan2(dir.Z, dir.X), 0), pal.crack, { material = "Slate", castShadow = false, name = "TrenchFloor" })
	scene.data.trench = { from = t0, to = t1 }

	-- broken building west of Ryu (behind him in the finale), outside the wide shot
	local b0 = Field.RYU + V(-46, 0, 0)
	for i = 0, 5 do
		local z = -16 + i * 7
		local h = 18 + (i % 3) * 5
		Builder.part(scene, "Field", V(4, h, 5.6), C(b0 + V(0, h / 2, z)), pal.concrete, { material = "Concrete", name = "Ruin" })
		Builder.part(scene, "Field", V(4.4, h * 0.42, 1.4), C(b0 + V(0, h * 0.6, z + 3.5)), pal.concreteDark, { material = "Concrete", name = "RuinWindow" })
	end
	Builder.part(scene, "Field", V(5, 3, 46), C(b0 + V(0, 22, 1.5)) * CFrame.Angles(math.rad(4), 0, 0), pal.concreteDark, { material = "Concrete", name = "RuinBeam" })

	-- mist plates (placed in front of the camera by the shots)
	local mist: { [string]: Builder.PartSpec } = {}
	mist.wisps = mistPlate(scene, "MistWisps", 1600, 900, 11, function(c, rr)
		for _ = 1, 22 do
			local w = Util.randRange(rr, 300, 700)
			c:blob(Util.randRange(rr, 0, 1600), Util.randRange(rr, 80, 880), w, w * Util.randRange(rr, 0.12, 0.25), pal.fogLight, Util.randRange(rr, 0.25, 0.45))
		end
	end)
	mist.low = mistPlate(scene, "MistLow", 1600, 900, 12, function(c, rr)
		for _ = 1, 26 do
			local w = Util.randRange(rr, 320, 760)
			c:blob(Util.randRange(rr, 0, 1600), Util.randRange(rr, 560, 920), w, w * Util.randRange(rr, 0.15, 0.3), pal.fogLight, Util.randRange(rr, 0.4, 0.65))
		end
	end)
	mist.heavy = mistPlate(scene, "MistHeavy", 1600, 900, 13, function(c, rr)
		c:box(0, 0, 1600, 900, pal.fogLight, 0.55)
		for _ = 1, 30 do
			local w = Util.randRange(rr, 300, 800)
			c:blob(Util.randRange(rr, 0, 1600), Util.randRange(rr, 0, 900), w, w * Util.randRange(rr, 0.2, 0.4), Color3.new(1, 1, 1), Util.randRange(rr, 0.3, 0.6))
		end
	end)
	mist.pink = mistPlate(scene, "MistPink", 1600, 900, 14, function(c, rr)
		for _ = 1, 22 do
			local w = Util.randRange(rr, 300, 700)
			c:blob(Util.randRange(rr, 400, 1600), Util.randRange(rr, 100, 800), w, w * Util.randRange(rr, 0.2, 0.4), pal.ePink, Util.randRange(rr, 0.2, 0.4))
		end
		for _ = 1, 14 do
			local w = Util.randRange(rr, 300, 700)
			c:blob(Util.randRange(rr, 0, 1600), Util.randRange(rr, 300, 900), w, w * Util.randRange(rr, 0.15, 0.3), pal.fogLight, Util.randRange(rr, 0.3, 0.5))
		end
	end)
	local snow = Builder.part(scene, "Mist", V(60, 2, 60), C(), Color3.new(1, 1, 1), { transparency = 1, castShadow = false, fx = true, name = "SnowBox" })
	Builder.emitter(scene, "Snow", "snow", snow, Color3.fromRGB(235, 240, 250), 1, 1)
	scene.data.field = { mist = mist, snow = snow } :: Handles
end

-- Put a mist plate in front of the camera so it fills the frame.
-- depth: distance from the camera; drift: sideways motion in studs/s
function Field.mist(ctx: Timeline.Ctx, name: string, depth: number, drift: number?, yShift: number?)
	local h: Handles = ctx.scene.data.field
	local p = h.mist[name]
	local cam = ctx.frame.camera
	local fov = ctx.frame.fov
	local need = 2 * depth * math.tan(math.rad(fov) / 2) * 1.15 -- frame height to cover
	local scale = need / p.size.Y
	local x = (drift or 0) * ctx.t
	ctx:place(p, cam * C(x, (yShift or 0) * need, -depth) * CFrame.Angles(0, math.pi, 0))
	ctx:prop(p, { s = V(p.size.X * scale, p.size.Y * scale, 0.05) })
end

-- falling snow around the camera
function Field.snow(ctx: Timeline.Ctx, rate: number?)
	local h: Handles = ctx.scene.data.field
	local cam = ctx.frame.camera
	ctx:place(h.snow, C(cam.Position + cam.LookVector * 24 + V(0, 16, 0)))
	ctx:emit("Snow", rate or 120)
end

return Field
