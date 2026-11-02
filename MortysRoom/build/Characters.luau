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
	cosmetic(torso, "Shirt", tc * CFrame.new(0, 0.12 * s, 0), v(1.8, 1.85, 1.08) * s, spec.shirt, "ellipsoid", Enum.Material.Fabric)
	cosmetic(torso, "Hips", tc * CFrame.new(0, -0.8 * s, 0), v(1.62, 0.72, 0.98) * s, spec.pants, "ellipsoid", Enum.Material.Fabric)
	cosmetic(torso, "Neck", tc * CFrame.new(0, 1.05 * s, 0) * up, v(0.4, 0.5, 0.5) * s, skin, "cylinder")
	if spec.collar then
		cosmetic(torso, "Collar", tc * CFrame.new(0, 0.9 * s, 0), v(1.0, 0.3, 0.75) * s, spec.collar, "ellipsoid", Enum.Material.Fabric)
	end
	if spec.coat then
		-- lab coat: back + two front flaps that leave the shirt visible, plus a long tail
		local coat = spec.coat
		cosmetic(torso, "CoatBack", tc * CFrame.new(0, -0.1 * s, 0.32 * s), v(1.95, 2.1, 0.5) * s, coat, "box", Enum.Material.Fabric)
		cosmetic(torso, "CoatL", tc * CFrame.new(-0.62 * s, -0.1 * s, -0.4 * s) * CFrame.Angles(0, math.rad(10), 0), v(0.72, 2.1, 0.32) * s, coat, "box", Enum.Material.Fabric)
		cosmetic(torso, "CoatR", tc * CFrame.new(0.62 * s, -0.1 * s, -0.4 * s) * CFrame.Angles(0, math.rad(-10), 0), v(0.72, 2.1, 0.32) * s, coat, "box", Enum.Material.Fabric)
		cosmetic(torso, "CoatShoulders", tc * CFrame.new(0, 0.75 * s, 0), v(2.15, 0.65, 1.2) * s, coat, "ellipsoid", Enum.Material.Fabric)
		cosmetic(torso, "LapelL", tc * CFrame.new(-0.3 * s, 0.55 * s, -0.56 * s) * CFrame.Angles(0, 0, math.rad(-18)), v(0.22, 0.8, 0.06) * s, rgb(230, 230, 226), "box", Enum.Material.Fabric)
		cosmetic(torso, "LapelR", tc * CFrame.new(0.3 * s, 0.55 * s, -0.56 * s) * CFrame.Angles(0, 0, math.rad(18)), v(0.22, 0.8, 0.06) * s, rgb(230, 230, 226), "box", Enum.Material.Fabric)
		cosmetic(torso, "TailBack", tc * CFrame.new(0, -1.75 * s, 0.38 * s), v(1.9, 1.5, 0.12) * s, coat, "box", Enum.Material.Fabric)
		cosmetic(torso, "TailL", tc * CFrame.new(-0.72 * s, -1.75 * s, -0.12 * s), v(0.5, 1.5, 0.9) * s, coat, "box", Enum.Material.Fabric)
		cosmetic(torso, "TailR", tc * CFrame.new(0.72 * s, -1.75 * s, -0.12 * s), v(0.5, 1.5, 0.9) * s, coat, "box", Enum.Material.Fabric)
		cosmetic(torso, "Pocket", tc * CFrame.new(-0.62 * s, 0.25 * s, -0.58 * s), v(0.4, 0.3, 0.04) * s, rgb(225, 225, 222), "box", Enum.Material.Fabric)
		cosmetic(torso, "Pen", tc * CFrame.new(-0.55 * s, 0.42 * s, -0.6 * s), v(0.05, 0.3, 0.05) * s, rgb(40, 80, 200), "box")
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

	-- arms ------------------------------------------------------------------
	local function arm(limb, side)
		local c = limb.CFrame * CFrame.new(-side * 0.36 * s, 0, 0)
		local sleeve = spec.sleeveColor or spec.shirt
		if spec.sleeves == "long" then
			cosmetic(limb, "Sleeve", c * CFrame.new(0, 0.1 * s, 0) * up, v(1.75, 0.66, 0.66) * s, sleeve, "cylinder", Enum.Material.Fabric)
			cosmetic(limb, "SleeveTop", c * CFrame.new(0, 0.95 * s, 0), v(0.68, 0.42, 0.68) * s, sleeve, "ellipsoid", Enum.Material.Fabric)
			cosmetic(limb, "Cuff", c * CFrame.new(0, -0.72 * s, 0) * up, v(0.12, 0.6, 0.6) * s, spec.cuff or sleeve, "cylinder", Enum.Material.Fabric)
		else
			cosmetic(limb, "Sleeve", c * CFrame.new(0, 0.62 * s, 0) * up, v(0.75, 0.72, 0.72) * s, sleeve, "cylinder", Enum.Material.Fabric)
			cosmetic(limb, "SleeveTop", c * CFrame.new(0, 0.95 * s, 0), v(0.72, 0.4, 0.72) * s, sleeve, "ellipsoid", Enum.Material.Fabric)
			cosmetic(limb, "Arm", c * CFrame.new(0, -0.18 * s, 0) * up, v(1.3, 0.46, 0.46) * s, skin, "cylinder")
		end
		cosmetic(limb, "Hand", c * CFrame.new(0, -0.95 * s, 0), v(0.52, 0.58, 0.48) * s, skin, "ellipsoid")
	end
	arm(la, -1)
	arm(ra, 1)

	local function leg(limb)
		local c = limb.CFrame
		cosmetic(limb, "Pants", c * CFrame.new(0, 0.18 * s, 0) * up, v(1.62, 0.74, 0.74) * s, spec.pants, "cylinder", Enum.Material.Fabric)
		cosmetic(limb, "Shoe", c * CFrame.new(0, -0.78 * s, -0.12 * s), v(0.74, 0.46, 1.06) * s, spec.shoes, "ellipsoid", Enum.Material.Leather)
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
