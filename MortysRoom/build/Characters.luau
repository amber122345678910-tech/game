--!nocheck
-- NPC puppets (R6 rig with rounded cosmetic parts). The root is anchored; the client animates the
-- Motor6D joints (RootJoint, Neck, Left/Right Shoulder, Left/Right Hip) to make them walk, sit, talk.
local U = require("./Util")
local Vector3, CFrame, Enum, Instance = U.Vector3, U.CFrame, U.Enum, U.Instance
local rgb, v = U.rgb, U.v

local Characters = {}

local function rigPart(model, name, size, cf, anchored)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Anchored = anchored == true
	p.Massless = not anchored
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function motor(parentPart, name, p0, p1, c0, c1)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1
	m.Parent = parentPart
	return m
end

-- scale only the position part of a CFrame
local function sc(cf, s)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(x * s, y * s, z * s, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

local function cosmetic(limb, name, cf, size, color, kind, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "ellipsoid" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	elseif kind == "cylinder" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Cylinder
		m.Parent = p
	end
	p:SetAttribute("Cosmetic", true)
	p.Parent = limb.Parent
	local w = Instance.new("Weld")
	w.Name = "W"
	w.Part0 = limb
	w.Part1 = p
	w.C0 = limb.CFrame:Inverse() * cf
	w.C1 = CFrame.new()
	w.Parent = p
	return p
end

--[[
	spec = {
		name, scale, skin, hair = function(add, headCF) ..., eyes = "round" | "rick" | "lashes",
		shirt, sleeves = "short" | "long", pants, shoes, coat (color or nil), collar (color or nil),
		headSize = Vector3
	}
]]
function Characters.build(parent, spec, rootCF)
	local s = spec.scale or 1
	local model = Instance.new("Model")
	model.Name = spec.name
	local o = rootCF

	local hrp = rigPart(model, "HumanoidRootPart", v(2, 2, 1) * s, o, true)
	local torso = rigPart(model, "Torso", v(2, 2, 1) * s, o)
	local head = rigPart(model, "Head", v(2, 1, 1) * s, o * CFrame.new(0, 1.5 * s, 0))
	local la = rigPart(model, "Left Arm", v(1, 2, 1) * s, o * CFrame.new(-1.5 * s, 0, 0))
	local ra = rigPart(model, "Right Arm", v(1, 2, 1) * s, o * CFrame.new(1.5 * s, 0, 0))
	local ll = rigPart(model, "Left Leg", v(1, 2, 1) * s, o * CFrame.new(-0.5 * s, -2 * s, 0))
	local rl = rigPart(model, "Right Leg", v(1, 2, 1) * s, o * CFrame.new(0.5 * s, -2 * s, 0))

	local R = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	motor(hrp, "RootJoint", hrp, torso, R, R)
	motor(torso, "Neck", torso, head, sc(CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), s), sc(CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), s))
	motor(torso, "Right Shoulder", torso, ra, sc(CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), s), sc(CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), s))
	motor(torso, "Left Shoulder", torso, la, sc(CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), s), sc(CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), s))
	motor(torso, "Right Hip", torso, rl, sc(CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), s), sc(CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), s))
	motor(torso, "Left Hip", torso, ll, sc(CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), s), sc(CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), s))

	local skin = spec.skin
	local skinShade = rgb(math.max(0, skin.R * 255 - 16), math.max(0, skin.G * 255 - 22), math.max(0, skin.B * 255 - 24))
	local up = CFrame.Angles(0, 0, math.rad(90))

	-- torso ---------------------------------------------------------------
	local tc = torso.CFrame
	cosmetic(torso, "Shirt", tc * CFrame.new(0, 0.12 * s, 0), v(1.8, 1.85, 1.08) * s, spec.shirt, "ellipsoid", Enum.Material.SmoothPlastic)
	cosmetic(torso, "Hips", tc * CFrame.new(0, -0.8 * s, 0), v(1.62, 0.72, 0.98) * s, spec.pants, "ellipsoid", Enum.Material.SmoothPlastic)
	cosmetic(torso, "Neck", tc * CFrame.new(0, 1.05 * s, 0) * up, v(0.4, 0.5, 0.5) * s, skin, "cylinder")
	if spec.collar then
		cosmetic(torso, "Collar", tc * CFrame.new(0, 0.9 * s, 0), v(1.0, 0.3, 0.75) * s, spec.collar, "ellipsoid", Enum.Material.SmoothPlastic)
	end
	if spec.coat then
		-- lab coat: back + two front flaps that leave the shirt visible, plus a long tail
		local coat = spec.coat
		cosmetic(torso, "CoatBack", tc * CFrame.new(0, -0.1 * s, 0.32 * s), v(1.95, 2.1, 0.5) * s, coat, "box", Enum.Material.SmoothPlastic)
		cosmetic(torso, "CoatL", tc * CFrame.new(-0.62 * s, -0.1 * s, -0.4 * s) * CFrame.Angles(0, math.rad(10), 0), v(0.72, 2.1, 0.32) * s, coat, "box", Enum.Material.SmoothPlastic)
		cosmetic(torso, "CoatR", tc * CFrame.new(0.62 * s, -0.1 * s, -0.4 * s) * CFrame.Angles(0, math.rad(-10), 0), v(0.72, 2.1, 0.32) * s, coat, "box", Enum.Material.SmoothPlastic)
		cosmetic(torso, "CoatShoulders", tc * CFrame.new(0, 0.75 * s, 0), v(2.15, 0.65, 1.2) * s, coat, "ellipsoid", Enum.Material.SmoothPlastic)
		cosmetic(torso, "LapelL", tc * CFrame.new(-0.3 * s, 0.55 * s, -0.56 * s) * CFrame.Angles(0, 0, math.rad(-18)), v(0.22, 0.8, 0.06) * s, rgb(230, 230, 226), "box", Enum.Material.SmoothPlastic)
		cosmetic(torso, "LapelR", tc * CFrame.new(0.3 * s, 0.55 * s, -0.56 * s) * CFrame.Angles(0, 0, math.rad(18)), v(0.22, 0.8, 0.06) * s, rgb(230, 230, 226), "box", Enum.Material.SmoothPlastic)
		cosmetic(torso, "TailBack", tc * CFrame.new(0, -1.75 * s, 0.38 * s), v(1.9, 1.5, 0.12) * s, coat, "box", Enum.Material.SmoothPlastic)
		cosmetic(torso, "TailL", tc * CFrame.new(-0.72 * s, -1.75 * s, -0.12 * s), v(0.5, 1.5, 0.9) * s, coat, "box", Enum.Material.SmoothPlastic)
		cosmetic(torso, "TailR", tc * CFrame.new(0.72 * s, -1.75 * s, -0.12 * s), v(0.5, 1.5, 0.9) * s, coat, "box", Enum.Material.SmoothPlastic)
		cosmetic(torso, "Pocket", tc * CFrame.new(-0.62 * s, 0.25 * s, -0.58 * s), v(0.4, 0.3, 0.04) * s, rgb(225, 225, 222), "box", Enum.Material.SmoothPlastic)
		cosmetic(torso, "Pen", tc * CFrame.new(-0.55 * s, 0.42 * s, -0.6 * s), v(0.05, 0.3, 0.05) * s, rgb(40, 80, 200), "box")
	end
	if spec.jacket then
		-- short jacket (agents' suits, Evil Morty)
		local jk = spec.jacket
		cosmetic(torso, "JacketBack", tc * CFrame.new(0, 0, 0.3 * s), v(1.96, 2.0, 0.5) * s, jk, "box")
		cosmetic(torso, "JacketL", tc * CFrame.new(-0.6 * s, 0, -0.4 * s) * CFrame.Angles(0, math.rad(9), 0), v(0.78, 2.0, 0.3) * s, jk, "box")
		cosmetic(torso, "JacketR", tc * CFrame.new(0.6 * s, 0, -0.4 * s) * CFrame.Angles(0, math.rad(-9), 0), v(0.78, 2.0, 0.3) * s, jk, "box")
		cosmetic(torso, "JacketShoulders", tc * CFrame.new(0, 0.72 * s, 0), v(2.12, 0.62, 1.16) * s, jk, "ellipsoid")
		cosmetic(torso, "JLapelL", tc * CFrame.new(-0.28 * s, 0.5 * s, -0.56 * s) * CFrame.Angles(0, 0, math.rad(-20)), v(0.2, 0.8, 0.05) * s, jk:Lerp(rgb(0, 0, 0), 0.35), "box")
		cosmetic(torso, "JLapelR", tc * CFrame.new(0.28 * s, 0.5 * s, -0.56 * s) * CFrame.Angles(0, 0, math.rad(20)), v(0.2, 0.8, 0.05) * s, jk:Lerp(rgb(0, 0, 0), 0.35), "box")
	end
	if spec.tie then
		cosmetic(torso, "Tie", tc * CFrame.new(0, 0.15 * s, -0.56 * s), v(0.22, 1.2, 0.05) * s, spec.tie, "box")
		cosmetic(torso, "TieKnot", tc * CFrame.new(0, 0.8 * s, -0.56 * s), v(0.26, 0.2, 0.08) * s, spec.tie, "box")
	end
	if spec.belt then
		cosmetic(torso, "Belt", tc * CFrame.new(0, -0.55 * s, 0), v(1.72, 0.22, 1.06) * s, spec.belt, "ellipsoid")
		cosmetic(torso, "Buckle", tc * CFrame.new(0, -0.55 * s, -0.53 * s), v(0.3, 0.2, 0.05) * s, rgb(200, 190, 150), "box", Enum.Material.Metal)
	end

	-- head ------------------------------------------------------------------
	local hs = spec.headSize or v(2.0, 1.8, 1.7)
	local hc = head.CFrame * CFrame.new(0, (hs.Y / 2 - 0.48) * s, 0)
	local function H(name, offset, size, color, kind, rot, material)
		local cf = hc * CFrame.new(offset * s)
		if rot then
			cf = cf * rot
		end
		return cosmetic(head, name, cf, size * s, color, kind or "ellipsoid", material)
	end
	if spec.customHead then
		spec.customHead(H, hs)
	else
	H("HeadCore", v(0, 0, 0), hs, skin)
	H("EarL", v(-hs.X / 2, -0.05, 0.05), v(0.28, 0.42, 0.3), skin)
	H("EarR", v(hs.X / 2, -0.05, 0.05), v(0.28, 0.42, 0.3), skin)
	local eyeY = spec.eyeY or 0.05
	local eyeX = spec.eyeX or 0.4
	local fz = -hs.Z / 2 + 0.12
	local eyeSize = spec.eyeSize or v(0.6, 0.6, 0.3)
	H("EyeL", v(-eyeX, eyeY, fz), eyeSize, rgb(255, 255, 255))
	H("EyeR", v(eyeX, eyeY, fz), eyeSize, rgb(255, 255, 255))
	local pupil = spec.pupil or 0.12
	H("PupilL", v(-eyeX + 0.04, eyeY - 0.02, fz - 0.15), v(pupil, pupil, 0.06), rgb(20, 20, 20))
	H("PupilR", v(eyeX - 0.04, eyeY - 0.02, fz - 0.15), v(pupil, pupil, 0.06), rgb(20, 20, 20))
	H("Nose", v(0, -0.24, fz - 0.06), spec.noseSize or v(0.16, 0.14, 0.12), skinShade)
	H("Mouth", v(0, -0.52, fz + 0.02), v(spec.mouthWidth or 0.4, 0.06, 0.08), rgb(90, 40, 40))
	if spec.eyes == "lashes" then
		H("LashL", v(-eyeX, eyeY + 0.3, fz - 0.06), v(0.55, 0.07, 0.08), rgb(30, 24, 24), "ellipsoid", CFrame.Angles(0, 0, math.rad(8)))
		H("LashR", v(eyeX, eyeY + 0.3, fz - 0.06), v(0.55, 0.07, 0.08), rgb(30, 24, 24), "ellipsoid", CFrame.Angles(0, 0, math.rad(-8)))
	elseif spec.eyes == "rick" then
		-- one long eyebrow + heavy lids
		H("Unibrow", v(0, eyeY + 0.36, fz - 0.04), v(1.25, 0.13, 0.12), spec.hairColor or rgb(150, 190, 210))
		H("LidL", v(-eyeX, eyeY + 0.16, fz - 0.07), v(0.58, 0.22, 0.2), skinShade)
		H("LidR", v(eyeX, eyeY + 0.16, fz - 0.07), v(0.58, 0.22, 0.2), skinShade)
		H("BagL", v(-eyeX, eyeY - 0.3, fz - 0.03), v(0.45, 0.06, 0.06), skinShade)
		H("BagR", v(eyeX, eyeY - 0.3, fz - 0.03), v(0.45, 0.06, 0.06), skinShade)
	elseif spec.eyes == "jerry" then
		H("BrowL", v(-eyeX, eyeY + 0.38, fz - 0.03), v(0.4, 0.08, 0.08), spec.hairColor, "ellipsoid", CFrame.Angles(0, 0, math.rad(-12)))
		H("BrowR", v(eyeX, eyeY + 0.38, fz - 0.03), v(0.4, 0.08, 0.08), spec.hairColor, "ellipsoid", CFrame.Angles(0, 0, math.rad(12)))
	end
	if spec.hair then
		spec.hair(H, hs)
	end
	if spec.faceExtra then
		spec.faceExtra(H, hs, fz, eyeX, eyeY)
	end
	end

	-- arms ------------------------------------------------------------------
	local function arm(limb, side)
		local c = limb.CFrame * CFrame.new(-side * 0.36 * s, 0, 0)
		local sleeve = spec.sleeveColor or spec.shirt
		if spec.sleeves == "long" then
			cosmetic(limb, "Sleeve", c * CFrame.new(0, 0.1 * s, 0) * up, v(1.75, 0.66, 0.66) * s, sleeve, "cylinder", Enum.Material.SmoothPlastic)
			cosmetic(limb, "SleeveTop", c * CFrame.new(0, 0.95 * s, 0), v(0.68, 0.42, 0.68) * s, sleeve, "ellipsoid", Enum.Material.SmoothPlastic)
			cosmetic(limb, "Cuff", c * CFrame.new(0, -0.72 * s, 0) * up, v(0.12, 0.6, 0.6) * s, spec.cuff or sleeve, "cylinder", Enum.Material.SmoothPlastic)
		else
			cosmetic(limb, "Sleeve", c * CFrame.new(0, 0.62 * s, 0) * up, v(0.75, 0.72, 0.72) * s, sleeve, "cylinder", Enum.Material.SmoothPlastic)
			cosmetic(limb, "SleeveTop", c * CFrame.new(0, 0.95 * s, 0), v(0.72, 0.4, 0.72) * s, sleeve, "ellipsoid", Enum.Material.SmoothPlastic)
			cosmetic(limb, "Arm", c * CFrame.new(0, -0.18 * s, 0) * up, v(1.3, 0.46, 0.46) * s, skin, "cylinder")
		end
		cosmetic(limb, "Hand", c * CFrame.new(0, -0.95 * s, 0), v(0.52, 0.58, 0.48) * s, spec.hands or skin, "ellipsoid")
	end
	arm(la, -1)
	arm(ra, 1)

	local function leg(limb)
		local c = limb.CFrame
		cosmetic(limb, "Pants", c * CFrame.new(0, 0.18 * s, 0) * up, v(1.62, 0.74, 0.74) * s, spec.pants, "cylinder", Enum.Material.SmoothPlastic)
		cosmetic(limb, "Shoe", c * CFrame.new(0, -0.78 * s, -0.12 * s), v(0.74, 0.46, 1.06) * s, spec.shoes, "ellipsoid", Enum.Material.SmoothPlastic)
	end
	leg(ll)
	leg(rl)

	model.PrimaryPart = hrp
	model:SetAttribute("Scale", s)
	model:SetAttribute("Outline", true)
	model.Parent = parent
	return model
end

-- Hair styles -----------------------------------------------------------------
Characters.Specs = {}

Characters.Specs.Rick = {
	name = "Rick",
	scale = 1.12,
	skin = rgb(242, 226, 204),
	shirt = rgb(176, 212, 230),
	sleeves = "long",
	sleeveColor = rgb(244, 244, 240),
	cuff = rgb(232, 232, 228),
	pants = rgb(122, 90, 62),
	shoes = rgb(70, 50, 36),
	coat = rgb(244, 244, 240),
	collar = rgb(176, 212, 230),
	headSize = v(1.9, 2.15, 1.8),
	eyes = "rick",
	eyeY = 0.0,
	eyeX = 0.38,
	pupil = 0.08,
	eyeSize = v(0.5, 0.5, 0.28),
	mouthWidth = 0.6,
	noseSize = v(0.2, 0.22, 0.16),
	hairColor = rgb(168, 214, 234),
}

Characters.Specs.Beth = {
	name = "Beth",
	scale = 1.06,
	skin = rgb(250, 216, 182),
	shirt = rgb(150, 38, 62),
	sleeves = "short",
	pants = rgb(236, 232, 222),
	shoes = rgb(60, 40, 40),
	headSize = v(1.9, 1.85, 1.7),
	eyes = "lashes",
	hairColor = rgb(240, 214, 140),
}

Characters.Specs.Jerry = {
	name = "Jerry",
	scale = 1.08,
	skin = rgb(250, 214, 178),
	shirt = rgb(98, 140, 78),
	collar = rgb(98, 140, 78),
	sleeves = "short",
	pants = rgb(190, 170, 122),
	shoes = rgb(96, 70, 48),
	headSize = v(1.95, 1.9, 1.75),
	eyes = "jerry",
	hairColor = rgb(122, 84, 52),
}

Characters.Specs.Summer = {
	name = "Summer",
	scale = 1.0,
	skin = rgb(250, 216, 184),
	shirt = rgb(236, 120, 160),
	sleeves = "short",
	pants = rgb(240, 238, 232),
	shoes = rgb(250, 250, 250),
	headSize = v(1.9, 1.8, 1.7),
	eyes = "lashes",
	hairColor = rgb(224, 112, 52),
}

-- per character hair (H(name, offset, size, color, kind, rot) adds a head cosmetic)
Characters.Specs.Rick.hair = function(H, hs)
	local c = Characters.Specs.Rick.hairColor
	H("HairBase", v(0, 0.45, 0.18), v(2.0, 1.5, 1.75), c)
	local dirs = {
		v(0, 1, 0.25), v(0.45, 0.9, 0.3), v(-0.45, 0.9, 0.3), v(0.8, 0.55, 0.35), v(-0.8, 0.55, 0.35),
		v(0.3, 0.65, 0.8), v(-0.3, 0.65, 0.8), v(0, 0.35, 1), v(0.95, 0.15, 0.45), v(-0.95, 0.15, 0.45),
		v(0.6, 0.35, 0.8), v(-0.6, 0.35, 0.8),
	}
	for i, d in dirs do
		local dir = d.Unit
		local pos = v(0, 0.35, 0.15) + dir * 1.05
		local rot = CFrame.lookAt(v(0, 0, 0), dir) - v(0, 0, 0)
		H("Spike" .. i, pos, v(0.5, 0.5, 1.45), c, "ellipsoid", rot)
	end
end

Characters.Specs.Beth.hair = function(H, hs)
	local c = Characters.Specs.Beth.hairColor
	H("HairTop", v(0, 0.36, 0.06), v(2.1, 1.4, 1.85), c)
	H("HairBack", v(0, -0.15, 0.32), v(2.15, 1.6, 1.4), c)
	H("HairSideL", v(-0.95, -0.4, 0.05), v(0.42, 1.1, 1.2), c)
	H("HairSideR", v(0.95, -0.4, 0.05), v(0.42, 1.1, 1.2), c)
	H("Bangs", v(0.25, 0.62, -0.62), v(1.3, 0.42, 0.5), c, "ellipsoid", CFrame.Angles(0, 0, math.rad(-12)))
end

Characters.Specs.Jerry.hair = function(H, hs)
	local c = Characters.Specs.Jerry.hairColor
	H("HairTop", v(0, 0.42, 0.08), v(2.05, 1.25, 1.85), c)
	H("HairPart", v(-0.35, 0.78, -0.35), v(1.0, 0.36, 0.8), c, "ellipsoid", CFrame.Angles(0, 0, math.rad(10)))
end

Characters.Specs.Summer.hair = function(H, hs)
	local c = Characters.Specs.Summer.hairColor
	H("HairTop", v(0, 0.38, 0.06), v(2.08, 1.4, 1.85), c)
	H("HairBack", v(0, -0.6, 0.45), v(1.9, 2.4, 1.0), c)
	H("HairSideL", v(-0.92, -0.55, 0.1), v(0.4, 1.6, 1.0), c)
	H("HairSideR", v(0.92, -0.55, 0.1), v(0.4, 1.6, 1.0), c)
	H("Band", v(0, 0.55, -0.1), v(2.12, 0.16, 1.9), rgb(255, 255, 255), "ellipsoid", CFrame.Angles(math.rad(-25), 0, 0))
end

Characters.Specs.Rick.belt = rgb(60, 42, 30)

-- Evil Morty: eyepatch over the right eye, two faces (evil + a blank, wide-eyed one shown later)
Characters.Specs.EvilMorty = {
	name = "EvilMorty",
	scale = 1.0,
	skin = rgb(250, 214, 178),
	shirt = rgb(246, 222, 60),
	sleeves = "long",
	sleeveColor = rgb(36, 40, 58),
	jacket = rgb(36, 40, 58),
	pants = rgb(52, 92, 160),
	shoes = rgb(240, 240, 240),
	belt = rgb(30, 30, 34),
	headSize = v(2.0, 1.8, 1.7),
	mouthWidth = 0.34,
	hairColor = rgb(110, 68, 36),
}
Characters.Specs.EvilMorty.hair = function(H, hs)
	H("Hair", v(0, 0.34, 0.07), v(2.08, 1.35, 1.75), rgb(110, 68, 36))
end
Characters.Specs.EvilMorty.faceExtra = function(H, hs, fz, eyeX, eyeY)
	local dark = rgb(60, 36, 24)
	local skinShade = rgb(234, 196, 160)
	-- evil face (default)
	H("LidL", v(-eyeX, eyeY + 0.17, fz - 0.08), v(0.62, 0.3, 0.22), skinShade).Name = "EvilLidL"
	H("BrowL", v(-eyeX, eyeY + 0.36, fz - 0.06), v(0.5, 0.1, 0.1), dark, "ellipsoid", CFrame.Angles(0, 0, math.rad(-22))).Name = "EvilBrowL"
	H("BrowR", v(eyeX, eyeY + 0.36, fz - 0.06), v(0.5, 0.1, 0.1), dark, "ellipsoid", CFrame.Angles(0, 0, math.rad(22))).Name = "EvilBrowR"
	H("Smirk", v(0.08, -0.5, fz - 0.01), v(0.34, 0.05, 0.08), rgb(90, 40, 40), "ellipsoid", CFrame.Angles(0, 0, math.rad(-8))).Name = "EvilSmirk"
	-- eyepatch + strap (stays on both faces)
	H("Patch", v(eyeX, eyeY, fz - 0.08), v(0.7, 0.66, 0.32), rgb(16, 16, 18))
	H("Strap", v(0, 0.16, 0), v(2.08, 0.12, 1.78), rgb(16, 16, 18), "ellipsoid", CFrame.Angles(0, 0, math.rad(-16)))
	-- blank face (hidden until the moment he changes)
	local function neutral(name, offset, size, color, rot)
		local p = H(name, offset, size, color, "ellipsoid", rot)
		p.Transparency = 1
		p:SetAttribute("NeutralFace", true)
		return p
	end
	neutral("WideEye", v(-eyeX, eyeY + 0.02, fz + 0.02), v(0.78, 0.8, 0.36), rgb(255, 255, 255))
	neutral("WidePupil", v(-eyeX, eyeY + 0.02, fz - 0.17), v(0.09, 0.09, 0.05), rgb(20, 20, 20))
	neutral("RaisedBrow", v(-eyeX, eyeY + 0.52, fz - 0.03), v(0.42, 0.07, 0.08), dark)
	neutral("OMouth", v(0, -0.52, fz + 0.0), v(0.14, 0.16, 0.08), rgb(90, 40, 40))
end

-- Rick Prime: colder, darker Rick
Characters.Specs.RickPrime = {
	name = "RickPrime",
	scale = 1.12,
	skin = rgb(226, 214, 200),
	shirt = rgb(90, 118, 146),
	sleeves = "long",
	sleeveColor = rgb(200, 202, 204),
	cuff = rgb(186, 188, 190),
	pants = rgb(70, 54, 42),
	shoes = rgb(30, 26, 24),
	coat = rgb(200, 202, 204),
	collar = rgb(90, 118, 146),
	belt = rgb(30, 26, 24),
	headSize = v(1.9, 2.15, 1.8),
	eyes = "rick",
	eyeY = 0.0,
	eyeX = 0.38,
	pupil = 0.06,
	eyeSize = v(0.48, 0.42, 0.28),
	mouthWidth = 0.55,
	noseSize = v(0.2, 0.22, 0.16),
	hairColor = rgb(138, 170, 188),
}
Characters.Specs.RickPrime.hair = Characters.Specs.Rick.hair

----------------------------------------------------------------------------
-- The Alliance: Cameramen, Speakermen, TV Men (black suits, white shirts, ties)
----------------------------------------------------------------------------
local function agentSpec(name: string, tie, head)
	return {
		name = name,
		scale = 1.15,
		skin = rgb(230, 210, 190),
		hands = rgb(26, 26, 30),
		shirt = rgb(244, 244, 244),
		sleeves = "long",
		sleeveColor = rgb(26, 26, 30),
		jacket = rgb(26, 26, 30),
		collar = rgb(244, 244, 244),
		tie = tie,
		pants = rgb(24, 24, 28),
		shoes = rgb(16, 16, 18),
		belt = rgb(10, 10, 12),
		headSize = v(2.0, 1.8, 1.7),
		customHead = head,
	}
end

local AXZ = CFrame.Angles(0, math.rad(90), 0)
Characters.Specs.Cameraman = agentSpec("Cameraman", rgb(20, 20, 24), function(H)
	H("CamBody", v(0, 0.05, 0.1), v(1.8, 1.45, 2.3), rgb(56, 56, 62), "box")
	H("CamTop", v(0, 0.9, 0.2), v(0.35, 0.35, 1.5), rgb(30, 30, 34), "box")
	H("CamBarrel", v(0, 0.05, -1.3), v(0.7, 1.15, 1.15), rgb(22, 22, 26), "cylinder", AXZ)
	H("CamRing", v(0, 0.05, -1.62), v(0.12, 1.24, 1.24), rgb(140, 140, 150), "cylinder", AXZ, Enum.Material.Metal)
	H("CamLens", v(0, 0.05, -1.68), v(0.06, 0.92, 0.92), rgb(30, 50, 90), "cylinder", AXZ, Enum.Material.Glass)
	H("CamRec", v(0.66, 0.55, -1.12), v(0.16, 0.16, 0.16), rgb(255, 40, 40), "ellipsoid", nil, Enum.Material.Neon).Name = "RecLight"
	H("CamSide", v(-1.0, 0.0, 0.3), v(0.25, 0.9, 1.2), rgb(40, 40, 46), "box")
end)
Characters.Specs.Speakerman = agentSpec("Speakerman", rgb(20, 20, 24), function(H)
	H("SpkBody", v(0, 0.15, 0), v(1.7, 2.1, 1.45), rgb(18, 18, 20), "box")
	H("SpkWoofer", v(0, -0.2, -0.74), v(0.12, 1.3, 1.3), rgb(50, 50, 56), "cylinder", AXZ)
	H("SpkCone", v(0, -0.2, -0.76), v(0.9, 0.9, 0.3), rgb(24, 24, 26), "ellipsoid")
	H("SpkTweeter", v(0, 0.72, -0.74), v(0.1, 0.45, 0.45), rgb(140, 140, 150), "cylinder", AXZ, Enum.Material.Metal)
end)
Characters.Specs.TVMan = agentSpec("TVMan", rgb(170, 26, 26), function(H)
	H("TVBody", v(0, 0.2, 0.05), v(2.6, 1.75, 0.45), rgb(18, 18, 20), "box")
	H("TVScreen", v(0, 0.2, -0.2), v(2.3, 1.45, 0.04), rgb(170, 210, 255), "box", nil, Enum.Material.Neon).Name = "Screen"
	H("TVStand", v(0, -0.75, 0.05), v(0.5, 0.3, 0.3), rgb(30, 30, 34), "box")
end)

-- a Skibidi toilet (enemy): white toilet with a singing head
function Characters.buildToilet(parent, cf, broken: boolean?)
	local m = Instance.new("Model")
	m.Name = "SkibidiToilet"
	local white = if broken then rgb(120, 118, 114) else rgb(244, 244, 240)
	local function add(name, local_, size, color, kind, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.Size = size
		p.CFrame = cf * local_
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if kind == "ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		elseif kind == "cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Parent = m
		return p
	end
	local root = add("Root", CFrame.new(), v(1, 1, 1), white)
	root.Transparency = 1
	m.PrimaryPart = root
	add("Base", CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), v(1.6, 2.2, 2.2), white, "cylinder")
	add("Bowl", CFrame.new(0, 2.0, -0.2), v(3.0, 1.8, 3.8), white, "ellipsoid")
	add("Seat", CFrame.new(0, 2.85, -0.2), v(3.1, 0.22, 3.9), rgb(230, 230, 226), "ellipsoid")
	add("Hole", CFrame.new(0, 2.92, -0.25), v(2.1, 0.1, 2.7), rgb(70, 130, 170), "ellipsoid")
	add("Tank", CFrame.new(0, 3.6, 1.75), v(3.0, 2.6, 1.1), white, "box")
	add("TankLid", CFrame.new(0, 4.95, 1.75), v(3.2, 0.2, 1.3), white, "box")
	add("Handle", CFrame.new(-1.0, 4.4, 1.15), v(0.5, 0.12, 0.2), rgb(170, 170, 176), "box", Enum.Material.Metal)
	-- the head
	local skin = if broken then rgb(150, 130, 116) else rgb(240, 208, 176)
	local head = add("Head", CFrame.new(0, 3.9, -0.3), v(1.8, 2.1, 1.8), skin, "ellipsoid")
	head:SetAttribute("ToiletHead", true)
	add("Hair", CFrame.new(0, 4.6, -0.2), v(1.86, 0.9, 1.84), rgb(60, 44, 32), "ellipsoid")
	add("EyeL", CFrame.new(-0.36, 4.15, -1.1), v(0.42, 0.42, 0.2), rgb(255, 255, 255), "ellipsoid")
	add("EyeR", CFrame.new(0.36, 4.15, -1.1), v(0.42, 0.42, 0.2), rgb(255, 255, 255), "ellipsoid")
	add("PupilL", CFrame.new(-0.36, 4.12, -1.2), v(0.14, 0.14, 0.06), rgb(20, 20, 20), "ellipsoid")
	add("PupilR", CFrame.new(0.36, 4.12, -1.2), v(0.14, 0.14, 0.06), rgb(20, 20, 20), "ellipsoid")
	add("BrowL", CFrame.new(-0.36, 4.45, -1.08) * CFrame.Angles(0, 0, math.rad(-15)), v(0.4, 0.08, 0.08), rgb(50, 36, 26), "ellipsoid")
	add("BrowR", CFrame.new(0.36, 4.45, -1.08) * CFrame.Angles(0, 0, math.rad(15)), v(0.4, 0.08, 0.08), rgb(50, 36, 26), "ellipsoid")
	add("Mouth", CFrame.new(0, 3.55, -1.05), v(0.6, 0.4, 0.2), rgb(80, 20, 24), "ellipsoid")
	if broken then
		root.CFrame = root.CFrame
		local sm = Instance.new("Smoke")
		sm.Color = rgb(40, 40, 40)
		sm.Opacity = 0.2
		sm.Size = 3
		sm.RiseVelocity = 3
		sm.Parent = head
	end
	m:SetAttribute("Broken", broken == true)
	m.Parent = parent
	return m
end

-- Templates the client clones (crowds of agents, toilets)
function Characters.buildTemplates(folder)
	local origin = CFrame.new(0, -5000, 0)
	for i, name in { "Cameraman", "Speakerman", "TVMan" } do
		local t = Characters.build(folder, Characters.Specs[name], origin * CFrame.new(i * 8, 3 * 1.15, 0))
		t:SetAttribute("Template", true)
	end
	Characters.buildToilet(folder, origin * CFrame.new(32, 0, 0), false)
	local broken = Characters.buildToilet(folder, origin * CFrame.new(40, 0, 0), true)
	broken.Name = "SkibidiToiletBroken"
end

function Characters.buildAll(workspace, seats)
	local cast = U.model("Cast", workspace)
	local function at(name)
		local m = seats:FindFirstChild(name)
		return m and m.CFrame or CFrame.new()
	end
	Characters.build(cast, Characters.Specs.Beth, at("Beth"))
	Characters.build(cast, Characters.Specs.Jerry, at("Jerry"))
	Characters.build(cast, Characters.Specs.Summer, at("Summer"))
	return cast
end

return Characters
