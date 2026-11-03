--!strict
-- Shared staging for part 2: where everybody stands, the effects every part 2
-- shot module uses, the extra rigs (Uro for the flashback, Ryu with his coat
-- slipped down) and small helpers (grade, sky, panel camera, roots).
local Builder = require(script.Parent.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Parent.Timeline)
local FX = require(script.Parent.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Parent.Util)
local Layout = require(script.Parent.Parent.Parent.Layout)
local Field = require(script.Parent.Parent.Field)
local Ryu = require(script.Parent.Parent.Parent.Art.Characters.Ryu)
local Uro = require(script.Parent.Parent.Parent.Art.Characters.Uro)

local Common = {}

local V = Vector3.new
local C = CFrame.new

-- Ryu fires at Yuta from 26 studs; they end up in each other's arms
Common.RYU = Field.RYU
Common.YUTA = Field.RYU + V(0, 0, -26)
-- the flashback rooftops (Sendai), far above the field, own purple sky
Common.FB = V(0, 3000, 900)

export type H = {
	blast: FX.Beam,
	blastCore: Builder.PartSpec,
	blastHalo: Builder.PartSpec,
	pinkGlow: Builder.PartSpec,
	debris: FX.Burst,
	shards: FX.Burst,
	streamers: FX.Burst,
	bands: { FX.CurvedBeam },
	rays: FX.Rays,
	comet: FX.Beam,
	palmGlow: Builder.PartSpec,
	pane: Builder.PartSpec,
	dust: FX.Burst,
	blood: FX.Burst,
	spray: FX.Burst,
	bolts: FX.Bolt,
	rikaBlood: { Builder.PartSpec },
	fbSky: { Builder.PartSpec },
	rings: { Builder.PartSpec },
	flames: FX.Burst,
	smoke: FX.Burst,
	rikaEye: Builder.PartSpec,
	shell: FX.Burst,
	uroArm: { upper: Builder.PartSpec, lower: Builder.PartSpec, band: Builder.PartSpec, hand: Builder.PartSpec },
}

function Common.build(scene: Builder.Scene)
	local pal = scene.style.color
	Uro.build(scene, "Uro")
	Ryu.build(scene, "RyuBare", true)
	local white = Color3.new(1, 1, 1)
	local cyanHot = Util.mix(pal.eCyan, white, 0.55)
	local h: H = {
		blast = FX.beam(scene, "GraniteBig", pal.eCyan, true),
		blastCore = FX.core(scene, "P2BlastCore", white),
		blastHalo = FX.core(scene, "P2BlastHalo", cyanHot),
		pinkGlow = FX.core(scene, "P2PinkGlow", pal.ePink),
		debris = FX.burst(scene, "P2Debris", pal.rubble, 40, "Block", 61),
		shards = FX.burst(scene, "P2Shards", pal.eCyan, 40, "Wedge", 62),
		streamers = FX.burst(scene, "P2Streamers", cyanHot, 48, "Block", 63),
		bands = {},
		rays = FX.rays(scene, "P2Rays", { pal.ePink, pal.eCyan, white, cyanHot }, 30, 64),
		comet = FX.beam(scene, "P2Comet", pal.eCyan, false),
		palmGlow = FX.core(scene, "P2PalmGlow", cyanHot),
		pane = FX.ring(scene, "P2Pane", Util.mix(pal.eCyan, white, 0.7)),
		dust = FX.burst(scene, "P2Dust", Util.mix(pal.snow, pal.fogDark, 0.25), 36, "Ball", 65),
		blood = FX.burst(scene, "P2Blood", pal.yBlood, 16, "Ball", 66),
		spray = FX.burst(scene, "P2Spray", pal.snow, 40, "Ball", 67),
		bolts = FX.bolts(scene, "P2Bolts", cyanHot, 40),
		rikaBlood = {},
		fbSky = {},
		rings = {},
		flames = FX.burst(scene, "P2Flames", Color3.fromRGB(255, 120, 40), 24, "Wedge", 69),
		smoke = FX.burst(scene, "P2Smoke", Color3.fromRGB(70, 66, 70), 16, "Ball", 70),
		rikaEye = FX.core(scene, "P2RikaEye", Color3.fromRGB(255, 40, 52)),
		shell = FX.burst(scene, "P2Shell", Color3.fromRGB(22, 22, 28), 34, "Wedge", 68),
		uroArm = {
			upper = Builder.fx(scene, "P2UroArm", "Block", V(0.36, 1.0, 0.38), pal.skin, "SmoothPlastic", 0, "UroArm"),
			lower = Builder.fx(scene, "P2UroArm", "Block", V(0.32, 0.9, 0.34), pal.skin, "SmoothPlastic", 0, "UroArm"),
			band = Builder.fx(scene, "P2UroArm", "Block", V(0.36, 0.12, 0.38), Color3.fromRGB(20, 20, 24), "SmoothPlastic", 0, "UroBand"),
			hand = Builder.fx(scene, "P2UroArm", "Block", V(0.3, 0.44, 0.16), pal.skin, "SmoothPlastic", 0, "UroHand"),
		},
	}
	for i = 1, 3 do
		h.rings[i] = FX.ring(scene, "P2Ring" .. i, Util.mix(pal.eCyan, white, 0.6))
	end
	-- the folded sky: broad bands of cyan and white
	for i = 1, 5 do
		h.bands[i] = FX.curvedBeam(scene, "P2Band" .. i, if i % 2 == 0 then white else pal.eCyan, 12)
	end
	-- rock, snow, dust and blood are matter, not light
	for i, p in h.flames.parts do
		if i % 3 == 0 then
			p.color = Color3.fromRGB(255, 205, 90)
		end
	end
	for _, bu in { h.debris, h.dust, h.spray, h.blood, h.shell, h.smoke } do
		for _, p in bu.parts do
			p.material = if bu == h.debris or bu == h.shell then "Slate" elseif bu == h.blood then "SmoothPlastic" else "Concrete"
		end
	end
	-- blood around Rika's mouth (flashback: she has just eaten Uro's arm)
	for i = 1, 7 do
		h.rikaBlood[i] = Builder.fx(scene, "P2RikaBlood", "Ball", V(1, 1, 1), pal.yBlood, "SmoothPlastic", 0, "Blood")
	end
	Common.buildFlashbackSet(scene)
	scene.data.p2 = h
end

-- Rooftops of a city at dusk for the flashback (static, far above the field)
function Common.buildFlashbackSet(scene: Builder.Scene)
	local pal = scene.style.color
	local o = Common.FB
	Builder.model(scene, "P2Flashback", false)
	local sky = Color3.fromRGB(122, 112, 176)
	-- a closed box of sky, darker towards the ground
	for _, w in {
		{ V(0, 60, -150), V(400, 260, 2) },
		{ V(0, 60, 150), V(400, 260, 2) },
		{ V(-150, 60, 0), V(2, 260, 400) },
		{ V(150, 60, 0), V(2, 260, 400) },
		{ V(0, 180, 0), V(400, 2, 400) },
	} do
		Builder.part(scene, "P2Flashback", w[2], C(o + w[1]), sky, { material = "SmoothPlastic", castShadow = false, name = "FbSky" })
	end
	Builder.part(scene, "P2Flashback", V(400, 2, 400), C(o + V(0, -41, 0)), Color3.fromRGB(46, 44, 70), { material = "Concrete", castShadow = false, name = "FbStreet" })
	-- rooftops: the fight happens on the roof at the centre
	local r = Util.rng(919)
	Builder.part(scene, "P2Flashback", V(46, 40, 40), C(o + V(0, -20, 0)), Color3.fromRGB(150, 150, 170), { material = "Concrete", name = "FbRoof" })
	Builder.part(scene, "P2Flashback", V(46, 1.2, 1), C(o + V(0, 0.6, -19.5)), Color3.fromRGB(90, 90, 110), { material = "Metal", name = "FbRail" })
	for i = 1, 24 do
		local a = i / 24 * math.pi * 2 + Util.randRange(r, -0.1, 0.1)
		local d = Util.randRange(r, 45, 120)
		local hgt = Util.randRange(r, 20, 75)
		local w = Util.randRange(r, 14, 30)
		local p = o + V(math.cos(a) * d, -40 + hgt / 2, math.sin(a) * d)
		local col = Util.mix(Color3.fromRGB(70, 66, 104), Color3.fromRGB(118, 112, 150), Util.rand(r))
		Builder.part(scene, "P2Flashback", V(w, hgt, w * Util.randRange(r, 0.7, 1.3)), C(p) * CFrame.Angles(0, Util.randRange(r, 0, 1.5), 0), col, { material = "Concrete", name = "FbBlock" })
	end
	local _ = pal
end

-- Ryu / Yuta roots for part 2 (Ryu looks down -Z at Yuta, Yuta looks +Z)
function Common.ryuRoot(yawOffset: number?): CFrame
	return C(Common.RYU) * CFrame.Angles(0, math.rad(yawOffset or 0), 0)
end
function Common.yutaRoot(yawOffset: number?): CFrame
	return C(Common.YUTA) * CFrame.Angles(0, math.rad(180 + (yawOffset or 0)), 0)
end

function Common.grade(ctx: Timeline.Ctx, b: number, c: number, s: number, tint: Color3?)
	ctx:grade({ brightness = b, contrast = c, saturation = s, tint = tint or Color3.fromRGB(232, 238, 255) })
end

-- falling snow and fog banks behind the characters (shots on the field)
function Common.sky(ctx: Timeline.Ctx, mistName: string?, depth: number?)
	Field.snow(ctx, 120)
	Field.mist(ctx, mistName or "low", depth or 34, 0.4)
	if mistName ~= "wisps" then
		Field.mist(ctx, "wisps", 70, -0.3, -0.08)
	end
end

-- Camera framing a rectangle of the painted close-up panels (reference px:
-- centre cx, cy and height hpx), e.g. Ryu's eyes full screen
function Common.panelCamera(ctx: Timeline.Ctx, cx: number, cy: number, hpx: number)
	local cam = Layout.CLOSE_CAM
	local target = Layout.worldAt(cam, Layout.CLOSE_FOV, Layout.FACE_DEPTH, cx, cy)
	local pos = target - cam.LookVector * Layout.FACE_DEPTH
	local fov = math.deg(2 * math.atan(math.tan(math.rad(Layout.CLOSE_FOV) / 2) * hpx / Layout.FRAME_H))
	ctx:camera(CFrame.new(pos) * cam.Rotation, fov)
	ctx:focus(Layout.FACE_DEPTH, 0)
end

-- Rika's eye glowing red (part 2 close-ups)
function Common.rikaEye(ctx: Timeline.Ctx, bones: { [string]: CFrame }, k: number?)
	local h: H = ctx.scene.data.p2
	FX.placeCore(ctx, h.rikaEye, (bones.Head * C(0.48, 1.55, -1.68)).Position, 0.2, k or 1)
end

-- Put a rig so that one of its bones (at an offset) lands on a world point:
-- solve once, then shift the root by the difference
function Common.rigAt(ctx: Timeline.Ctx, rig: string, root: CFrame, pose: any, bone: string, offset: CFrame, target: Vector3): { [string]: CFrame }
	local b = ctx:rig(rig, root, pose)
	local d = target - (b[bone] * offset).Position
	return ctx:rig(rig, CFrame.new(d) * root, pose)
end

-- Long thin energy streamers flowing past along `dir` around `center`
function Common.streamers(ctx: Timeline.Ctx, bu: FX.Burst, center: Vector3, dir: Vector3, spread: number, len: number, speed: number, k: number)
	local d = dir.Unit
	local side = d:Cross(V(0, 1, 0))
	if side.Magnitude < 0.1 then
		side = V(1, 0, 0)
	end
	side = side.Unit
	local up = side:Cross(d).Unit
	for i, p in bu.parts do
		local rr = Util.rng(bu.seed * 100 + i)
		local off = side * Util.randRange(rr, -spread, spread) + up * Util.randRange(rr, -spread * 0.6, spread * 0.6)
		local ph = (ctx.t * speed / 30 + Util.rand(rr)) % 1
		local pos = center + off + d * ((ph - 0.5) * 30)
		local l = len * Util.randRange(rr, 0.4, 1.2)
		ctx:place(p, FX.along(pos, pos + d * l))
		ctx:prop(p, { s = V(l, 0.07 * k, 0.07 * k), t = 1 - k * (1 - math.abs(ph - 0.5) * 1.6) })
	end
end

return Common
