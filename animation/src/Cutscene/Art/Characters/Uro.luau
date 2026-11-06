--!strict
-- Uro Takako (part 2 flashbacks, seen up close): slim, very long lilac-pink
-- hair that streams in the wind, pale skin, a pale sleeveless top, black
-- shorts, bare arms and legs, bare feet, dark red-brown bracelets on both
-- wrists, red nails, a gold ring in her ear. R15 skeleton, face painted on
-- with expression groups (uro:eyes:open / shut, uro:mouth:closed / open).
-- The long hair is not on the rig: Uro.placeHair lays its strands out every
-- frame along the way the wind blows (Uro.hair builds the parts).
local Builder = require(script.Parent.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Parent.Timeline)
local Rig = require(script.Parent.Parent.Parent.Rig)
local Paint = require(script.Parent.Parent.Parent.Paint)
local Util = require(script.Parent.Parent.Parent.Util)

local R = Rig.R
local V = Vector3.new
local C = CFrame.new

local Uro = {}

Uro.dims = {
	hip = 2.4,
	hipX = 0.36,
	waist = 0.45,
	neck = 1.26,
	shoulderY = 1.1,
	shoulderX = 0.74,
	upperArm = 0.96,
	lowerArm = 0.88,
	upperLeg = 1.16,
	lowerLeg = 1.12,
}

Uro.PINK = Color3.fromRGB(232, 160, 212)
Uro.PINK_DARK = Color3.fromRGB(190, 118, 176)
Uro.PINK_LIGHT = Color3.fromRGB(250, 206, 236)
local TOP = Color3.fromRGB(232, 232, 240)
local BLACK = Color3.fromRGB(30, 28, 36)
local BAND = Color3.fromRGB(74, 32, 36)
local GOLD = Color3.fromRGB(226, 186, 92)
local NAIL = Color3.fromRGB(206, 64, 76)

function Uro.build(scene: Builder.Scene, rigName: string): Rig.RigDef
	local def = Rig.humanoid(Uro.dims)
	Builder.rig(scene, rigName, def, rigName)
	Builder.model(scene, rigName, scene.style.outline ~= nil)
	local k = Builder.kit(scene, rigName, rigName)
	local pal = scene.style.color
	local skin = Color3.fromRGB(240, 222, 214)

	-- hips: black shorts; a slim waist; a pale sleeveless top
	k.addColor("LowerTorso", "Ellipsoid", V(1.2, 0.74, 0.74), C(0, 0.12, 0), BLACK, "cloth", "Shorts")
	k.addColor("UpperTorso", "Ellipsoid", V(0.9, 0.7, 0.6), C(0, 0.22, 0), skin, "skin", "Waist")
	k.addColor("UpperTorso", "Ellipsoid", V(1.24, 1.08, 0.74), C(0, 0.78, 0), TOP, "cloth", "Top")
	k.addColor("UpperTorso", "Ellipsoid", V(0.5, 0.36, 0.3), C(0, 1.3, 0), skin, "skin", "Neck")
	for _, sx in { -1, 1 } do
		k.addColor("UpperTorso", "Ball", V(0.42, 0.42, 0.42), C(sx * 0.66, 1.1, 0), skin, "skin", "Shoulder")
	end

	-- head: painted face with expression groups
	local face = Paint.canvas(4.0, 0, 0)
	local line = pal.line
	local white = Color3.fromRGB(252, 252, 254)
	local iris = Color3.fromRGB(176, 78, 136)
	for _, sx in { -1, 1 } do
		local cx = 50 + sx * 17
		face:setGroup("uro:eyes:open")
		face:ellipse(cx, 52, 7, 6.6, 0, white)
		face:ellipse(cx - sx * 0.8, 53, 4.6, 5.6, 0, iris)
		face:circle(cx - sx * 0.8, 53.4, 2.2, Color3.fromRGB(64, 22, 44))
		face:circle(cx + sx * 1.4, 50.6, 1.3, white)
		face:stroke({ { cx - 8.5, 47.5 }, { cx, 45.4 }, { cx + 8.5, 47 } }, { 1.6, 2.6, 1.4 }, line)
		face:stroke({ { cx - 6, 57.6 }, { cx, 58.6 }, { cx + 6, 57.4 } }, { 0.4, 0.8, 0.4 }, line)
		-- shut tight with pain: a curved line, creases at the corner
		face:setGroup("uro:eyes:shut")
		face:stroke({ { cx - 8, 52.5 }, { cx, 55 }, { cx + 8, 52 } }, { 1.4, 2.4, 1.2 }, line)
		face:stroke({ { cx + sx * 7, 49 }, { cx + sx * 10, 47.5 } }, { 0.8, 0.4 }, line)
		face:stroke({ { cx + sx * 7, 55.5 }, { cx + sx * 10, 57 } }, { 0.8, 0.4 }, line)
		-- brows (always)
		face:setGroup(nil)
		face:stroke({ { cx - 7, 39 }, { cx, 37.6 }, { cx + 7, 39.4 } }, { 0.8, 1.3, 0.6 }, Uro.PINK_DARK)
	end
	face:setGroup(nil)
	face:stroke({ { 50, 62 }, { 50.6, 68 } }, { 0.4, 0.6 }, Color3.fromRGB(206, 170, 168))
	face:setGroup("uro:mouth:closed")
	face:stroke({ { 45, 78 }, { 50, 79 }, { 55, 78 } }, { 0.6, 1, 0.6 }, Color3.fromRGB(160, 70, 90))
	face:setGroup("uro:mouth:open")
	face:ellipse(50, 79, 6, 3.2, 0, Color3.fromRGB(96, 30, 44))
	face:stroke({ { 44.6, 77.4 }, { 50, 76.6 }, { 55.4, 77.4 } }, { 1.4, 1.8, 1.4 }, white)
	face:setGroup(nil)
	Builder.part(scene, rigName, V(0.9, 1.0, 0.9), C(0, 0.6, 0), skin, {
		shape = "Block",
		material = scene.style.material.skin,
		rig = rigName,
		bone = "Head",
		name = "Head",
		gui = { face = "Front", canvas = Vector2.new(400, 432), lightInfluence = scene.style.face.lightInfluence, elems = face.elems },
	})
	k.addColor("Head", "Ellipsoid", V(0.92, 0.5, 0.9), C(0, 0.16, -0.02), skin, "skin", "Jaw")
	-- hair: a rounded cap, a fringe swept to one side, locks framing the face
	k.addColor("Head", "Ellipsoid", V(1.1, 0.7, 1.12), C(0, 1.06, 0.06), Uro.PINK, "hair", "HairTop")
	k.addColor("Head", "Ellipsoid", V(0.98, 0.3, 0.3), C(0.06, 0.96, -0.44) * R(0, 0, -6), Uro.PINK, "hair", "Fringe")
	for _, sx in { -1, 1 } do
		Builder.flex(k.addColor("Head", "Ellipsoid", V(0.2, 1.3, 0.42), C(sx * 0.5, 0.42, -0.14), Uro.PINK, "hair", "SideHair"), 6, V(0, 0.6, 0))
	end
	-- a gold ring in the left ear
	k.addColor("Head", "Ball", V(0.16, 0.16, 0.06), C(-0.48, 0.42, 0.02), GOLD, "metal", "Earring")

	-- bare arms, dark bracelets at the wrists, red nails
	for _, side in { "Left", "Right" } do
		k.addColor(side .. "UpperArm", "Ellipsoid", V(0.34, 1.08, 0.36), C(0, -0.46, 0), skin, "skin", "Arm")
		k.addColor(side .. "LowerArm", "Ellipsoid", V(0.3, 0.98, 0.32), C(0, -0.42, 0), skin, "skin", "Forearm")
		k.addColor(side .. "LowerArm", "Cylinder", V(0.16, 0.38, 0.38), C(0, -0.74, 0) * R(0, 0, 90), BAND, "cloth", "Bracelet")
		k.addColor(side .. "Hand", "Ellipsoid", V(0.28, 0.4, 0.14), C(0, -0.2, 0), skin, "skin", "Hand")
		for f = 1, 4 do
			local x = (f - 2.5) * 0.065
			k.addColor(side .. "Hand", "Ellipsoid", V(0.06, 0.26, 0.07), C(x, -0.48, 0), skin, "skin", "Finger")
			k.addColor(side .. "Hand", "Ball", V(0.05, 0.06, 0.04), C(x, -0.6, -0.02), NAIL, "skin", "Nail")
		end
		k.addColor(side .. "Hand", "Ellipsoid", V(0.07, 0.22, 0.08), C(if side == "Left" then 0.15 else -0.15, -0.22, -0.05) * R(0, 0, if side == "Left" then 25 else -25), skin, "skin", "Thumb")
	end
	-- long bare legs and bare feet
	for _, side in { "Left", "Right" } do
		k.addColor(side .. "UpperLeg", "Ellipsoid", V(0.46, 1.26, 0.48), C(0, -0.56, 0), skin, "skin", "Thigh")
		k.addColor(side .. "LowerLeg", "Ellipsoid", V(0.36, 1.2, 0.38), C(0, -0.55, 0), skin, "skin", "Shin")
		k.addColor(side .. "Foot", "Ellipsoid", V(0.3, 0.2, 0.72), C(0, -0.05, -0.16), skin, "skin", "Foot")
	end
	return def
end

------------------------------------------------------------------------------
-- the long hair: strands of segments laid out each frame
------------------------------------------------------------------------------
export type Hair = { strands: { { Builder.PartSpec } }, roots: { Vector3 }, seeds: { number } }

local N_STRANDS, N_SEGS = 14, 9

function Uro.hair(scene: Builder.Scene, name: string): Hair
	local strands: { { Builder.PartSpec } } = {}
	local roots: { Vector3 } = {}
	local seeds: { number } = {}
	local r = Util.rng(6611)
	Util.rand(r)
	for i = 1, N_STRANDS do
		local f = (i - 1) / (N_STRANDS - 1)
		-- roots across the back and top of the head (head-local)
		table.insert(roots, V((f - 0.5) * 0.9, 0.72 + math.sin(f * math.pi) * 0.3, 0.3 + math.sin(f * math.pi) * 0.12))
		table.insert(seeds, Util.rand(r) * 10)
		local list: { Builder.PartSpec } = {}
		local col = if i % 4 == 0 then Uro.PINK_DARK elseif i % 5 == 2 then Uro.PINK_LIGHT else Uro.PINK
		for s = 1, N_SEGS do
			local p = Builder.fx(scene, name, "Ellipsoid", V(1, 1, 1), if s == N_SEGS and i % 2 == 0 then Uro.PINK_DARK else col, "SmoothPlastic", 0, "HairStrand")
			p.castShadow = false
			table.insert(list, p)
		end
		table.insert(strands, list)
	end
	return { strands = strands, roots = roots, seeds = seeds }
end

-- CFrame whose X axis runs from a to b (as FX.along; kept here so the
-- character module does not depend on the effects module)
local function along(a: Vector3, b: Vector3): CFrame
	local d = b - a
	local l = d.Magnitude
	if l < 1e-4 then
		return C(a)
	end
	local x = d / l
	local up = if math.abs(x.Y) > 0.95 then V(1, 0, 0) else V(0, 1, 0)
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	local m = (a + b) / 2
	return CFrame.new(m.X, m.Y, m.Z, x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z)
end

-- Lay the hair out: it leaves the head downwards and bends into `flow` (the
-- way the wind / the fall blows it, world space; its length sets how far the
-- hair reaches, ~4-6 studs), waving along its length; `spread` fans the
-- strands apart sideways, `k` (0..1) how strongly it streams
function Uro.placeHair(ctx: Timeline.Ctx, hair: Hair, head: CFrame, flow: Vector3, spread: number?, k: number?)
	local t = ctx.t
	local len = flow.Magnitude
	local fd = if len > 1e-3 then flow / len else V(0, -1, 0)
	local strength = k or 1
	local side = fd:Cross(head.LookVector)
	if side.Magnitude < 0.1 then
		side = head.RightVector
	end
	side = side.Unit
	local normal = side:Cross(fd).Unit
	local down = -head.UpVector * 0.7 + head.LookVector * -0.3
	for i, list in hair.strands do
		local f = (i - 1) / (#hair.strands - 1)
		local ph = hair.seeds[i]
		local p = head:PointToWorldSpace(hair.roots[i])
		local segLen = len / N_SEGS * (0.85 + 0.3 * math.sin(ph * 3.1) ^ 2)
		local fan = (f - 0.5) * (spread or 1)
		for s, part in list do
			local g = (s - 1) / (N_SEGS - 1)
			local bend = math.min(1, (s - 0.5) / 2.2) * strength
			local wave = math.sin(t * 9 - s * 0.85 + ph) * (0.25 + 0.35 * g) + math.sin(t * 15.3 - s * 1.4 + ph * 2) * 0.1
			local dir = down:Lerp(fd, bend) + side * (fan * (0.35 + g) + wave * 0.5) + normal * (wave * 0.55 * g)
			local q = p + dir.Unit * segLen
			local w = 0.58 * (1 - g * 0.6) + 0.06
			ctx:place(part, along(p, q))
			ctx:prop(part, { s = V(segLen * 1.6, w, w * 0.4) })
			p = q
		end
	end
end

Uro.poses = {
	-- mid-air, grappling: knees up, one arm grabbing forward
	grapple = {
		LowerTorso = R(10, 0, 0),
		UpperTorso = R(-14, 0, 0),
		Head = R(-6, 0, 0),
		LeftUpperArm = R(70, 0, -20),
		LeftLowerArm = R(40, 0, 0),
		RightUpperArm = R(100, 0, 30),
		RightLowerArm = R(30, 0, 0),
		LeftUpperLeg = R(60, 0, -8),
		LeftLowerLeg = R(-90, 0, 0),
		RightUpperLeg = R(10, 0, 10),
		RightLowerLeg = R(-70, 0, 0),
	} :: Rig.Pose,
	-- clinging round someone's head: both arms forward and in
	cling = {
		UpperTorso = R(-16, 0, 0),
		Head = R(-14, 0, 0),
		LeftUpperArm = R(96, 0, 26),
		LeftLowerArm = R(84, 0, 0),
		RightUpperArm = R(96, 0, -26),
		RightLowerArm = R(84, 0, 0),
		LeftUpperLeg = R(40, 0, -10),
		LeftLowerLeg = R(-70, 0, 0),
		RightUpperLeg = R(20, 0, 10),
		RightLowerLeg = R(-90, 0, 0),
	} :: Rig.Pose,
	-- floating, knees folded under her, both arms pushing forward palms out
	push = {
		LowerTorso = R(0, 0, 0),
		UpperTorso = R(-6, 0, 0),
		Head = R(-4, 0, 0),
		LeftUpperArm = R(94, 0, 10),
		LeftLowerArm = R(6, 0, 0),
		LeftHand = R(-70, 0, 0),
		RightUpperArm = R(92, 0, -10),
		RightLowerArm = R(6, 0, 0),
		RightHand = R(-70, 0, 0),
		LeftUpperLeg = R(60, 0, -6),
		LeftLowerLeg = R(-120, 0, 0),
		RightUpperLeg = R(40, 0, 6),
		RightLowerLeg = R(-130, 0, 0),
	} :: Rig.Pose,
	-- crouched in mid-air, arms in (falling, bracing)
	crouch = {
		LowerTorso = R(20, 0, 0),
		UpperTorso = R(24, 0, 0),
		Head = R(-10, 0, 0),
		LeftUpperArm = R(40, 0, -30),
		LeftLowerArm = R(90, 0, 0),
		RightUpperArm = R(60, 0, 40),
		RightLowerArm = R(80, 0, 0),
		LeftUpperLeg = R(100, 0, -10),
		LeftLowerLeg = R(-130, 0, 0),
		RightUpperLeg = R(80, 0, 10),
		RightLowerLeg = R(-120, 0, 0),
	} :: Rig.Pose,
	-- tumbling: limbs flung out
	flung = {
		LowerTorso = R(-20, 0, 0),
		UpperTorso = R(-20, 0, 10),
		Head = R(-25, 0, 0),
		LeftUpperArm = R(150, 0, -50),
		LeftLowerArm = R(20, 0, 0),
		RightUpperArm = R(120, 0, 60),
		RightLowerArm = R(30, 0, 0),
		LeftUpperLeg = R(50, 0, -20),
		LeftLowerLeg = R(-40, 0, 0),
		RightUpperLeg = R(-20, 0, 20),
		RightLowerLeg = R(-70, 0, 0),
	} :: Rig.Pose,
	-- caught by one arm (the left, held up), the body hanging, kicking
	hang = {
		LowerTorso = R(-10, 0, 0),
		UpperTorso = R(-10, 0, -8),
		Head = R(-26, 0, 10),
		LeftUpperArm = R(176, 0, -16),
		LeftLowerArm = R(10, 0, 0),
		RightUpperArm = R(40, 0, 50),
		RightLowerArm = R(60, 0, 0),
		LeftUpperLeg = R(40, 0, -10),
		LeftLowerLeg = R(-80, 0, 0),
		RightUpperLeg = R(-10, 0, 10),
		RightLowerLeg = R(-50, 0, 0),
	} :: Rig.Pose,
	-- head thrown back in pain, the bitten shoulder hunched up
	pain = {
		LowerTorso = R(-10, 0, 0),
		UpperTorso = R(-30, 0, 10),
		Head = R(-40, 20, 10),
		LeftUpperArm = R(160, 0, -40),
		LeftLowerArm = R(20, 0, 0),
		RightUpperArm = R(30, 0, 50),
		RightLowerArm = R(70, 0, 0),
		LeftUpperLeg = R(30, 0, -10),
		LeftLowerLeg = R(-60, 0, 0),
		RightUpperLeg = R(10, 0, 10),
		RightLowerLeg = R(-40, 0, 0),
	} :: Rig.Pose,
}

return Uro
