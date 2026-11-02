--!nocheck
-- Titan Speakerman 2.0 (red suit, black speaker cluster with red cones), the black entity,
-- the curse's hand + head, tentacle beasts (infected Rick / Evil Morty), Astro toilet ships, mothership.
-- Rigs: invisible bone parts joined by Motor6Ds (root anchored); the client animates Motor6D.Transform.
-- Joint axes are body aligned: X = right, Y = up, -Z = forward.
local U = require("./Util")
local Vector3, CFrame, Enum, Instance = U.Vector3, U.CFrame, U.Enum, U.Instance
local rgb, v = U.rgb, U.v
local M = Enum.Material

local Titan = {}

----------------------------------------------------------------------------
-- tiny rig helpers
----------------------------------------------------------------------------
local Rig = {}
Rig.__index = Rig

function Rig.new(name, parent, rootCF)
	local self = setmetatable({}, Rig)
	self.model = Instance.new("Model")
	self.model.Name = name
	self.bones = {}
	local root = self:bonePart("Root", rootCF, true)
	self.model.PrimaryPart = root
	self.model.Parent = parent
	return self
end

function Rig:bonePart(name, cf, anchored)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = v(1, 1, 1)
	p.CFrame = cf
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Anchored = anchored == true
	p.Massless = not anchored
	p.Parent = self.model
	self.bones[name] = p
	return p
end

function Rig:bone(name, parentName, c0, offset, jointName)
	local parent = self.bones[parentName]
	local c1 = CFrame.new(-offset)
	local cf = parent.CFrame * c0 * c1:Inverse()
	local b = self:bonePart(name, cf, false)
	local m = Instance.new("Motor6D")
	m.Name = jointName or name
	m.Part0 = parent
	m.Part1 = b
	m.C0 = c0
	m.C1 = c1
	m.Parent = parent
	return b
end

function Rig:add(boneName, name, localCF, size, color, material, kind, props)
	local bone = self.bones[boneName]
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = bone.CFrame * localCF
	p.Color = color
	p.Material = material or M.Metal
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif kind == "cylinder" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Cylinder
		mesh.Parent = p
	elseif kind == "ball" then
		p.Shape = Enum.PartType.Ball
	end
	if props then
		for k, val in props do
			if k ~= "Attr" then
				p[k] = val
			end
		end
		if props.Attr then
			for ak, av in props.Attr do
				p:SetAttribute(ak, av)
			end
		end
	end
	if material == M.Neon then
		p.CastShadow = false
	end
	p.Parent = self.model
	local w = Instance.new("Weld")
	w.Name = "W"
	w.Part0 = bone
	w.Part1 = p
	w.C0 = localCF
	w.C1 = CFrame.new()
	w.Parent = p
	return p
end

function Rig:point(boneName, name, localCF)
	return self:add(boneName, name, localCF, v(0.5, 0.5, 0.5), rgb(255, 0, 255), M.SmoothPlastic, nil, { Transparency = 1 })
end

function Rig:emitter(part, name, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = name
	for k, val in props do
		pe[k] = val
	end
	pe.Parent = part
	return pe
end

local AXIS_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis (local X) -> Z
local AXIS_Y = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis -> Y

----------------------------------------------------------------------------
-- Titan Speakerman 2.0 (~70 studs tall). Root = pelvis centre, 30.4 above the feet.
----------------------------------------------------------------------------
local RED = rgb(164, 44, 34)
local RED_DARK = rgb(112, 28, 22)
local BLACK = rgb(18, 18, 20)
local METAL = rgb(52, 52, 58)
local STEEL = rgb(150, 150, 158)
local GLOW = rgb(255, 64, 28)
local GLOW_HOT = rgb(255, 170, 110)
local PANTS = rgb(26, 26, 30)

-- a speaker cone (rim + red glowing cone + hot centre) facing local -Z of `base`
local function cone(r, bone, name, base, d)
	r:add(bone, name .. "Rim", base * AXIS_Z, v(0.55, d * 1.22, d * 1.22), METAL, M.Metal, "cylinder")
	r:add(bone, name .. "Cone", base * CFrame.new(0, 0, -0.12) * AXIS_Z, v(0.4, d, d), GLOW, M.Neon, "cylinder")
	r:add(bone, name .. "Hot", base * CFrame.new(0, 0, -0.3), v(d * 0.34, d * 0.34, d * 0.2), GLOW_HOT, M.Neon, "ellipsoid")
end

local function cannon(r, side, attr)
	local s = if side < 0 then "L" else "R"
	local bone = "Forearm" .. s
	local tag = { Attr = { [attr] = true } }
	local x = side * 0.8
	r:add(bone, "CannonBody", CFrame.new(x, -4.6, -0.6), v(8, 14, 8.4), BLACK, M.Metal, nil, tag)
	r:add(bone, "CannonPlate", CFrame.new(x + side * 4.1, -4.6, -0.6), v(0.6, 11, 6), METAL, M.Metal, nil, tag)
	r:add(bone, "CannonStripe", CFrame.new(x, -4.6, -4.85), v(5.6, 9, 0.3), RED_DARK, M.SmoothPlastic, nil, tag)
	r:add(bone, "CannonBarrel", CFrame.new(x, -13.4, -0.6) * AXIS_Y, v(6.4, 6.2, 6.2), METAL, M.Metal, "cylinder", tag)
	r:add(bone, "CannonRing", CFrame.new(x, -11.4, -0.6) * AXIS_Y, v(1.2, 7.4, 7.4), BLACK, M.Metal, "cylinder", tag)
	r:add(bone, "MuzzleRim", CFrame.new(x, -16.8, -0.6) * AXIS_Y, v(1.0, 7.6, 7.6), BLACK, M.Metal, "cylinder", tag)
	local glow = r:add(bone, "MuzzleGlow", CFrame.new(x, -17.2, -0.6), v(5.6, 1.4, 5.6), GLOW, M.Neon, "ellipsoid", tag)
	glow:SetAttribute("TitanMuzzle", true)
	local ml = Instance.new("PointLight")
	ml.Name = "MuzzleLight"
	ml.Range = 26
	ml.Brightness = 1.5
	ml.Color = GLOW
	ml.Parent = glow
	-- the angular frame along the cannon
	r:add(bone, "FrameA", CFrame.new(x, -6.5, -5.4) * CFrame.Angles(math.rad(14), 0, 0), v(0.7, 10, 0.7), BLACK, M.Metal, nil, tag)
	r:add(bone, "FrameB", CFrame.new(x, -1.6, -6.2), v(0.7, 0.7, 3), BLACK, M.Metal, nil, tag)
	r:add(bone, "FrameC", CFrame.new(x, -11.4, -5.6), v(0.7, 0.7, 2.4), BLACK, M.Metal, nil, tag)
	r:add(bone, "FrameD", CFrame.new(x + side * 2, -6.5, -6.4) * CFrame.Angles(0, 0, side * math.rad(25)), v(0.6, 7, 0.6), BLACK, M.Metal, nil, tag)
	r:point(bone, if side < 0 then "MuzzleL" else "Muzzle", CFrame.new(x, -18.6, -0.6))
end

function Titan.buildTitan(parent, groundCF)
	local rootCF = groundCF * CFrame.new(0, 30.4, 0)
	local r = Rig.new("TitanSpeakerman", parent, rootCF)
	r:bone("Pelvis", "Root", CFrame.new(), v(0, 0, 0), "Hips")
	r:bone("Torso", "Pelvis", CFrame.new(0, 2.5, 0), v(0, 9, 0), "Waist")
	r:bone("Head", "Torso", CFrame.new(0, 9.5, 0), v(0, 8.6, 0), "Neck")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:bone("UpperArm" .. s, "Torso", CFrame.new(side * 12.5, 6.0, 0) * CFrame.Angles(0, 0, side * 0.12), v(0, -5.5, 0), "Shoulder" .. s)
		r:bone("Forearm" .. s, "UpperArm" .. s, CFrame.new(0, -5.5, 0), v(0, -6, 0), "Elbow" .. s)
		r:bone("Hand" .. s, "Forearm" .. s, CFrame.new(0, -6, 0), v(0, -2.2, 0), "Wrist" .. s)
		r:bone("Thigh" .. s, "Pelvis", CFrame.new(side * 4.6, -2, 0), v(0, -6.5, 0), "Hip" .. s)
		r:bone("Shin" .. s, "Thigh" .. s, CFrame.new(0, -6.5, 0), v(0, -6.5, 0), "Knee" .. s)
		r:bone("Foot" .. s, "Shin" .. s, CFrame.new(0, -6.5, 0), v(0, -1.2, -1.6), "Ankle" .. s)
	end

	-- pelvis: black pants + belt
	r:add("Pelvis", "Pants", CFrame.new(0, -0.6, 0), v(12.8, 6, 8.6), PANTS, M.SmoothPlastic)
	r:add("Pelvis", "Belt", CFrame.new(0, 2.3, 0), v(13.6, 1.6, 9.2), BLACK, M.Metal)
	r:add("Pelvis", "Buckle", CFrame.new(0, 2.3, -4.7), v(2.4, 1.3, 0.4), STEEL, M.Metal)

	-- torso: red jacket, black vest, harness, chest speaker with the glowing orb
	r:add("Torso", "Jacket", CFrame.new(0, 1.6, 0), v(20, 15, 11.6), RED, M.SmoothPlastic)
	r:add("Torso", "JacketLow", CFrame.new(0, -6.8, 0.2), v(16.4, 5.4, 10.4), RED, M.SmoothPlastic)
	r:add("Torso", "Vest", CFrame.new(0, -5.6, -0.1), v(13.8, 6.4, 10.8), BLACK, M.SmoothPlastic)
	for row = 0, 1 do
		r:add("Torso", "VestPlate" .. row, CFrame.new(0, -3.6 - row * 3, -5.5), v(11, 2.2, 0.6), METAL, M.Metal)
	end
	for _, side in { -1, 1 } do
		r:add("Torso", "Shoulder", CFrame.new(side * 9.6, 6.4, 0), v(10.4, 8.4, 12), RED, M.SmoothPlastic, "ellipsoid")
		r:add("Torso", "Lapel", CFrame.new(side * 2.8, 5.6, -5.9) * CFrame.Angles(0, 0, side * math.rad(18)), v(2.2, 8, 0.5), RED_DARK, M.SmoothPlastic)
		r:add("Torso", "Strap", CFrame.new(side * 6.4, 1.5, -6.0) * CFrame.Angles(0, 0, side * math.rad(-22)), v(1.5, 12.5, 0.6), BLACK, M.SmoothPlastic)
		r:add("Torso", "Crease", CFrame.new(side * 7.5, -1.5, -5.85) * CFrame.Angles(0, 0, side * math.rad(8)), v(0.4, 6, 0.3), RED_DARK, M.SmoothPlastic)
	end
	r:add("Torso", "Collar", CFrame.new(0, 9.1, 0.4), v(8.6, 2.2, 9.4), BLACK, M.SmoothPlastic)
	r:add("Torso", "ChestBox", CFrame.new(0, 2.4, -6.6), v(12.4, 7.6, 3.2), BLACK, M.Metal)
	local core = r:add("Torso", "Core", CFrame.new(0, 2.4, -8.4), v(6.2, 6.2, 4.4), GLOW, M.Neon, "ellipsoid")
	core:SetAttribute("TitanCore", true)
	local coreLight = Instance.new("PointLight")
	coreLight.Name = "CoreLight"
	coreLight.Range = 40
	coreLight.Brightness = 2
	coreLight.Color = GLOW
	coreLight.Parent = core
	r:add("Torso", "CoreHot", CFrame.new(0, 2.8, -10.3), v(2.4, 2.4, 1.2), GLOW_HOT, M.Neon, "ellipsoid")
	r:add("Torso", "CoreDome", CFrame.new(0, 2.4, -8.5), v(7, 7, 5.4), rgb(255, 200, 190), M.Glass, "ellipsoid", { Transparency = 0.65, CastShadow = false })
	for _, side in { -1, 1 } do
		cone(r, "Torso", "ChestCone" .. side, CFrame.new(side * 4.4, 2.4, -8.25), 2.4)
	end
	-- back frame + jets
	r:add("Torso", "Pack", CFrame.new(0, 2, 7.8), v(13, 13, 4.2), BLACK, M.Metal)
	for _, side in { -1, 1 } do
		local sname = if side < 0 then "L" else "R"
		r:add("Torso", "Strut", CFrame.new(side * 9, 9, 6.5) * CFrame.Angles(math.rad(-15), 0, side * math.rad(-30)), v(1.2, 12, 1.2), BLACK, M.Metal)
		r:add("Torso", "Thruster" .. sname, CFrame.new(side * 4.3, -2.2, 10.6) * CFrame.Angles(math.rad(15), 0, 0) * AXIS_Y, v(9, 4.2, 4.2), METAL, M.Metal, "cylinder")
		local noz = r:add("Torso", "Nozzle" .. sname, CFrame.new(side * 4.3, -6.6, 11.8) * CFrame.Angles(math.rad(15), 0, 0) * AXIS_Y, v(0.4, 3.4, 3.4), rgb(255, 120, 60), M.Neon, "cylinder")
		r:emitter(noz, "Jet", {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = U.ColorSequence.new(rgb(255, 200, 120), rgb(255, 60, 20)),
			LightEmission = 1,
			Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 3.2), U.NumberSequenceKeypoint.new(1, 0.6) }),
			Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.1), U.NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = U.NumberRange.new(0.3, 0.5),
			Speed = U.NumberRange.new(40, 60),
			Rate = 80,
			EmissionDirection = Enum.NormalId.Left,
			Enabled = false,
		})
		local jl = Instance.new("PointLight")
		jl.Name = "JetLight"
		jl.Range = 30
		jl.Brightness = 0
		jl.Color = rgb(255, 120, 60)
		jl.Parent = noz
	end
	-- huge speaker towers on the shoulders
	for _, side in { -1, 1 } do
		local sname = if side < 0 then "L" else "R"
		local tower = CFrame.new(side * 15, 14, 1.6) * CFrame.Angles(0, side * math.rad(-8), side * math.rad(-14))
		r:add("Torso", "Tower" .. sname, tower, v(6.8, 20, 6.8), BLACK, M.Metal, nil, { Attr = { ["Tower" .. sname] = true } })
		for i, yy in { 6, 0, -6 } do
			cone(r, "Torso", "TowerCone" .. sname .. i, tower * CFrame.new(0, yy, -3.5), 4.2)
		end
		local outer = CFrame.new(side * 20.5, 8.5, 3.4) * CFrame.Angles(0, side * math.rad(-20), side * math.rad(-30))
		r:add("Torso", "Outer" .. sname, outer, v(5.4, 14, 5.6), BLACK, M.Metal)
		for i, yy in { 3.5, -3.5 } do
			cone(r, "Torso", "OuterCone" .. sname .. i, outer * CFrame.new(0, yy, -2.9), 3.4)
		end
		r:add("Torso", "TowerCap" .. sname, tower * CFrame.new(0, 10.4, 0), v(7.4, 0.8, 7.4), METAL, M.Metal)
		r:point("Torso", "Pod" .. sname, tower * CFrame.new(0, 0, -4.5))
	end

	-- head: a cluster of speakers
	r:add("Head", "HeadMain", CFrame.new(0, 0, 0), v(9.6, 8.6, 7.6), BLACK, M.Metal)
	cone(r, "Head", "Main", CFrame.new(0, -0.3, -3.9), 6.4)
	local eye = r.model:FindFirstChild("MainHot")
	if eye then
		eye:SetAttribute("TitanEye", true)
		local el = Instance.new("PointLight")
		el.Name = "EyeLight"
		el.Range = 30
		el.Brightness = 1.5
		el.Color = GLOW
		el.Parent = eye
	end
	r:add("Head", "HeadTop", CFrame.new(0, 6.3, 0.4), v(6.2, 4.2, 6.2), BLACK, M.Metal)
	for i = 0, 2 do
		r:add("Head", "Grille" .. i, CFrame.new(0, 5.3 + i * 1.0, -2.8), v(4.8, 0.28, 0.3), STEEL, M.Metal)
	end
	r:add("Head", "CrestL", CFrame.new(-1.6, 10, 0.4) * CFrame.Angles(0, 0, math.rad(-35)), v(0.6, 5, 0.6), BLACK, M.Metal)
	r:add("Head", "CrestR", CFrame.new(1.6, 10, 0.4) * CFrame.Angles(0, 0, math.rad(35)), v(0.6, 5, 0.6), BLACK, M.Metal)
	r:add("Head", "CrestSpike", CFrame.new(0, 11.6, 0.4), v(0.5, 3.4, 0.5), BLACK, M.Metal)
	r:add("Head", "CrestBar", CFrame.new(0, 8.6, 0.4), v(6.4, 0.5, 0.5), BLACK, M.Metal)
	for _, side in { -1, 1 } do
		local sname = if side < 0 then "L" else "R"
		r:add("Head", "Side" .. sname, CFrame.new(side * 7.4, 0.8, 0.6), v(4.8, 9.4, 6), BLACK, M.Metal)
		for i, yy in { 2.4, -2.2 } do
			cone(r, "Head", "SideCone" .. sname .. i, CFrame.new(side * 7.4, 0.8 + yy, -2.45), 3.0)
		end
		r:add("Head", "Horn" .. sname, CFrame.new(side * 7.4, 7, 0.6) * CFrame.Angles(0, 0, side * math.rad(-20)), v(0.6, 4, 0.6), BLACK, M.Metal)
	end
	r:add("Head", "Jaw", CFrame.new(0, -6.1, -0.4), v(15, 4.4, 6.2), BLACK, M.Metal)
	for _, side in { -1, 1 } do
		cone(r, "Head", "JawCone" .. side, CFrame.new(side * 4.0, -6.1, -3.55), 3.4)
	end
	r:add("Head", "Tweeter", CFrame.new(0, -6.1, -3.65) * CFrame.Angles(0, 0, math.rad(45)), v(1.6, 1.6, 0.4), STEEL, M.Metal)
	r:add("Head", "NeckPost", CFrame.new(0, -8.6, 0.4) * AXIS_Y, v(3, 5.2, 5.2), METAL, M.Metal, "cylinder")
	r:point("Head", "Mouth", CFrame.new(0, -3, -6))

	-- arms: red sleeves, black gloves, two cannons
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:add("UpperArm" .. s, "Sleeve", CFrame.new(0, 0, 0) * AXIS_Y, v(11.6, 6.6, 6.6), RED, M.SmoothPlastic, "cylinder")
		r:add("UpperArm" .. s, "Bicep", CFrame.new(side * 0.4, 0.8, -0.2), v(6.8, 8.4, 7.0), RED, M.SmoothPlastic, "ellipsoid")
		r:add("UpperArm" .. s, "Elbow", CFrame.new(0, -5.5, 0), v(6.4, 5.4, 6.4), RED, M.SmoothPlastic, "ellipsoid")
		r:add("Forearm" .. s, "ForeSleeve", CFrame.new(0, 1.2, 0) * AXIS_Y, v(10, 6.2, 6.2), RED, M.SmoothPlastic, "cylinder")
		r:add("Forearm" .. s, "Cuff", CFrame.new(0, -4.4, 0) * AXIS_Y, v(1.8, 6.6, 6.6), BLACK, M.SmoothPlastic, "cylinder")
		r:add("Hand" .. s, "Glove", CFrame.new(0, 0, 0), v(5, 4.6, 5), BLACK, M.SmoothPlastic)
		r:add("Hand" .. s, "Fingers", CFrame.new(0, -2.7, -0.3), v(4.6, 1.8, 4.6), BLACK, M.SmoothPlastic)
		r:add("Hand" .. s, "Thumb", CFrame.new(-side * 2.6, 0.4, -1.4), v(1.4, 3, 1.6), BLACK, M.SmoothPlastic)
		cannon(r, side, if side < 0 then "LeftCannon" else "RightCannon")
	end

	-- legs: black pants, boots
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:add("Thigh" .. s, "Thigh", CFrame.new(0, 0, 0), v(7.8, 13, 8.2), PANTS, M.SmoothPlastic)
		r:add("Thigh" .. s, "Fold", CFrame.new(0, -2, -4.15), v(5.6, 0.4, 0.3), rgb(16, 16, 18), M.SmoothPlastic)
		r:add("Thigh" .. s, "Knee", CFrame.new(0, -6.5, -0.6), v(7.2, 5.6, 7.2), PANTS, M.SmoothPlastic, "ellipsoid")
		r:add("Shin" .. s, "Shin", CFrame.new(0, 0, 0.2), v(7.4, 13, 7.8), PANTS, M.SmoothPlastic)
		r:add("Shin" .. s, "Boot", CFrame.new(0, -4.6, 0.2), v(8, 4.4, 8.6), BLACK, M.SmoothPlastic)
		r:add("Foot" .. s, "Foot", CFrame.new(0, 0, 0), v(8.2, 2.4, 12.6), BLACK, M.SmoothPlastic)
		r:add("Foot" .. s, "Toe", CFrame.new(0, 0.5, -5.6), v(7.6, 1.6, 2.2), METAL, M.Metal)
	end

	-- battle damage (hidden until after the fight)
	local dmg = { Transparency = 1, Attr = { Damage = true } }
	r:add("Torso", "Burn1", CFrame.new(-9, 7.5, -5.4), v(6, 4, 2), rgb(30, 18, 14), M.SmoothPlastic, "ellipsoid", dmg)
	r:add("Torso", "Burn2", CFrame.new(5, -2, -5.9), v(4, 3, 1), rgb(30, 18, 14), M.SmoothPlastic, "ellipsoid", dmg)
	r:add("Torso", "Crack1", CFrame.new(0.6, 2.8, -10.8) * CFrame.Angles(0, 0, math.rad(30)), v(0.25, 5, 0.25), rgb(40, 10, 8), M.SmoothPlastic, nil, dmg)
	r:add("Torso", "Crack2", CFrame.new(-0.8, 1.8, -10.8) * CFrame.Angles(0, 0, math.rad(-50)), v(0.25, 3.5, 0.25), rgb(40, 10, 8), M.SmoothPlastic, nil, dmg)
	r:add("ForearmL", "TornSleeve", CFrame.new(0, -3.5, 0), v(6.8, 3, 6.8), rgb(80, 20, 16), M.SmoothPlastic, "ellipsoid", dmg)
	r:add("ForearmL", "Wire1", CFrame.new(1, -6, 0) * CFrame.Angles(0, 0, math.rad(20)), v(0.3, 4, 0.3), rgb(220, 60, 40), M.SmoothPlastic, nil, dmg)
	r:add("ForearmL", "Wire2", CFrame.new(-1, -6.5, 0.6) * CFrame.Angles(math.rad(25), 0, 0), v(0.3, 3.6, 0.3), rgb(230, 200, 60), M.SmoothPlastic, nil, dmg)
	local sparkPoint = r:point("ForearmL", "DamageSparks", CFrame.new(0, -6, 0))
	r:emitter(sparkPoint, "Sparks", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = U.ColorSequence.new(rgb(255, 200, 120)),
		LightEmission = 1,
		Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.6), U.NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = U.NumberRange.new(0.3, 0.7),
		Speed = U.NumberRange.new(10, 22),
		SpreadAngle = U.Vector2.new(60, 60),
		Acceleration = v(0, -50, 0),
		Rate = 25,
		Enabled = false,
	})
	local smokePoint = r:point("Torso", "DamageSmoke", CFrame.new(-10, 9, 0))
	r:emitter(smokePoint, "Smoke", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = U.ColorSequence.new(rgb(40, 38, 38)),
		Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 3), U.NumberSequenceKeypoint.new(1, 12) }),
		Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.4), U.NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = U.NumberRange.new(3, 5),
		Speed = U.NumberRange.new(4, 8),
		Rate = 10,
		Enabled = false,
	})
	r.model:SetAttribute("StandHeight", 30.4)
	return r.model
end

----------------------------------------------------------------------------
-- The entity: huge black shape inside a black cloud. Root at its feet.
----------------------------------------------------------------------------
function Titan.buildEntity(parent, groundCF)
	local BLACK2 = rgb(16, 14, 18)
	local ENT = rgb(8, 8, 10)
	local REDE = rgb(255, 30, 20)
	local r = Rig.new("Entity", parent, groundCF)
	r:bone("Body", "Root", CFrame.new(0, 40, 0), v(0, 30, 0), "Waist")
	r:bone("Head", "Body", CFrame.new(0, 34, 0), v(0, 14, 0), "Neck")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:bone("ArmA" .. s, "Body", CFrame.new(side * 22, 24, 0), v(0, -20, 0), "Shoulder" .. s)
		r:bone("ArmB" .. s, "ArmA" .. s, CFrame.new(0, -20, 0), v(0, -20, 0), "Elbow" .. s)
		r:bone("Claw" .. s, "ArmB" .. s, CFrame.new(0, -20, 0), v(0, -6, 0), "Wrist" .. s)
	end
	for t = 1, 6 do
		local a = (t - 3.5) * 0.45
		local prev = "Body"
		local c0 = CFrame.new(math.sin(a) * 14, 10 + math.abs(t - 3.5) * 3, 10) * CFrame.Angles(math.rad(-50), a, 0)
		for k = 1, 5 do
			local name = "T" .. t .. "_" .. k
			r:bone(name, prev, if k == 1 then c0 else CFrame.new(0, 6, 0), v(0, 6, 0), name)
			r:add(name, "Seg", CFrame.new(0, 0, 0), v(5.5 - k * 0.7, 14, 5.5 - k * 0.7), BLACK2, M.SmoothPlastic, "ellipsoid")
			prev = name
		end
	end
	r:add("Body", "Chest", CFrame.new(0, 6, 0), v(46, 50, 32), ENT, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Belly", CFrame.new(0, -18, 2), v(36, 34, 28), BLACK2, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Lump1", CFrame.new(-14, 20, 6), v(20, 18, 18), ENT, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Lump2", CFrame.new(16, 22, 4), v(18, 16, 18), ENT, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Crack", CFrame.new(0, 4, -15.6) * CFrame.Angles(0, 0, math.rad(8)), v(2.4, 26, 1.0), rgb(140, 10, 10), M.Neon)
	r:add("Head", "Skull", CFrame.new(0, 0, 0), v(24, 28, 24), ENT, M.SmoothPlastic, "ellipsoid", { Attr = { EntityHead = true } })
	r:add("Head", "Horn1", CFrame.new(-8, 12, 4) * CFrame.Angles(math.rad(-30), 0, math.rad(25)), v(4, 18, 4), BLACK2, M.SmoothPlastic, "ellipsoid", { Attr = { EntityHead = true } })
	r:add("Head", "Horn2", CFrame.new(8, 12, 4) * CFrame.Angles(math.rad(-30), 0, math.rad(-25)), v(4, 18, 4), BLACK2, M.SmoothPlastic, "ellipsoid", { Attr = { EntityHead = true } })
	for _, side in { -1, 1 } do
		local eye = r:add("Head", "Eye", CFrame.new(side * 5.5, 2, -11.2) * CFrame.Angles(0, 0, side * math.rad(14)), v(5.2, 2.0, 1.6), REDE, M.Neon, "ellipsoid", { Attr = { EntityHead = true } })
		eye:SetAttribute("EntityEye", true)
		local l = Instance.new("PointLight")
		l.Name = "EntityEyeLight"
		l.Range = 40
		l.Brightness = 3
		l.Color = REDE
		l.Parent = eye
	end
	r:add("Head", "Mouth", CFrame.new(0, -7, -11), v(10, 1.2, 1.0), rgb(180, 20, 10), M.Neon, "ellipsoid", { Attr = { EntityHead = true } })
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:add("ArmA" .. s, "Upper", CFrame.new(0, 0, 0), v(9, 42, 9), ENT, M.SmoothPlastic, "ellipsoid")
		r:add("ArmB" .. s, "Lower", CFrame.new(0, 0, 0), v(7.5, 42, 7.5), BLACK2, M.SmoothPlastic, "ellipsoid")
		for f = -1, 1 do
			r:add("Claw" .. s, "Finger" .. f, CFrame.new(f * 3, -5, -1) * CFrame.Angles(math.rad(-20), 0, f * math.rad(-12)), v(2.2, 16, 2.2), ENT, M.SmoothPlastic, "ellipsoid")
		end
		r:add("Claw" .. s, "Palm", CFrame.new(0, 2, 0), v(10, 8, 6), BLACK2, M.SmoothPlastic, "ellipsoid")
	end
	local cloudOffsets = {
		CFrame.new(0, 10, 0), CFrame.new(-30, 30, 0), CFrame.new(30, 30, 0), CFrame.new(0, 50, 10),
		CFrame.new(-20, 70, -6), CFrame.new(22, 64, -4), CFrame.new(0, 90, 0), CFrame.new(0, 30, -30),
	}
	for i, off in cloudOffsets do
		local p = r:point("Root", "Cloud" .. i, off)
		r:emitter(p, "BlackCloud", {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = U.ColorSequence.new(rgb(6, 6, 8), rgb(20, 16, 22)),
			Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 26), U.NumberSequenceKeypoint.new(1, 70) }),
			Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 1), U.NumberSequenceKeypoint.new(0.15, 0.15), U.NumberSequenceKeypoint.new(0.8, 0.3), U.NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = U.NumberRange.new(6, 10),
			Speed = U.NumberRange.new(3, 9),
			SpreadAngle = U.Vector2.new(180, 180),
			RotSpeed = U.NumberRange.new(-12, 12),
			Rotation = U.NumberRange.new(0, 360),
			Rate = 7,
			LightInfluence = 0.6,
			Acceleration = v(0, 1.5, 0),
			Enabled = false,
		})
	end
	r.model:SetAttribute("Height", 150)
	return r.model
end

----------------------------------------------------------------------------
-- Tentacle beasts (what infected Rick and Evil Morty turn into). Root at the feet, ~20 tall.
----------------------------------------------------------------------------
function Titan.buildBeast(parent, name, groundCF, kind)
	local B = rgb(10, 9, 12)
	local B2 = rgb(22, 18, 26)
	local r = Rig.new(name, parent, groundCF)
	r:bone("Body", "Root", CFrame.new(0, 10, 0), v(0, 4, 0), "Waist") -- body centre 14 above the feet
	r:bone("Head", "Body", CFrame.new(0, 6, 0), v(0, 3.4, 0), "Neck")
	r:add("Body", "Mass", CFrame.new(0, 0, 0), v(9, 12, 8), B, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Lump1", CFrame.new(-3.5, 3, 2), v(5, 5, 5), B2, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Lump2", CFrame.new(3.6, -2, 1.5), v(5, 6, 5), B2, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Base", CFrame.new(0, -5.5, 0), v(10, 4.5, 9), B, M.SmoothPlastic, "ellipsoid")
	r:add("Head", "Skull", CFrame.new(0, 0, 0), v(6.4, 6.4, 6), B, M.SmoothPlastic, "ellipsoid")
	for _, side in { -1, 1 } do
		r:add("Head", "Eye", CFrame.new(side * 1.4, 0.6, -2.85) * CFrame.Angles(0, 0, side * math.rad(16)), v(1.5, 0.7, 0.4), rgb(255, 30, 20), M.Neon, "ellipsoid")
	end
	r:add("Head", "Mouth", CFrame.new(0, -1.5, -2.8), v(3, 0.4, 0.4), rgb(160, 16, 10), M.Neon, "ellipsoid")
	if kind == "rick" then
		for i, d in { v(0, 1, 0.3), v(0.6, 0.8, 0.3), v(-0.6, 0.8, 0.3), v(0.9, 0.3, 0.5), v(-0.9, 0.3, 0.5), v(0, 0.4, 1) } do
			local dir = d.Unit
			r:add("Head", "Spike" .. i, CFrame.lookAt(dir * 3.4, dir * 6), v(1.4, 1.4, 4.6), B2, M.SmoothPlastic, "ellipsoid")
		end
	else
		r:add("Head", "HairCap", CFrame.new(0, 1.4, 0.3), v(6.8, 4.6, 6.4), rgb(26, 18, 14), M.SmoothPlastic, "ellipsoid")
		r:add("Head", "Patch", CFrame.new(1.4, 0.6, -2.9), v(1.8, 1.6, 0.5), rgb(0, 0, 0), M.SmoothPlastic, "ellipsoid")
	end
	-- tentacles: a chain of bones, +Y of each bone runs along the tentacle
	local count = 0
	local function tentacle(pos, dir, curl, segs, thick)
		count += 1
		local prev = "Body"
		local start = CFrame.lookAt(pos, pos + dir.Unit) * CFrame.Angles(-math.pi / 2, 0, 0)
		for k = 1, segs do
			local bn = "T" .. count .. "_" .. k
			local c0 = if k == 1 then start else CFrame.new(0, 2.1, 0) * CFrame.Angles(curl, 0, 0)
			r:bone(bn, prev, c0, v(0, 2.1, 0), bn)
			local w = thick * (1 - (k - 1) / (segs + 1))
			r:add(bn, "Seg", CFrame.new(0, 0, 0), v(w, 5, w), if k % 2 == 0 then B2 else B, M.SmoothPlastic, "ellipsoid")
			prev = bn
		end
	end
	-- T1..T4: legs that it runs on (curl outwards along the ground)
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local radial = v(math.cos(a), 0, math.sin(a))
		tentacle(radial * 3 + v(0, -5, 0), radial * 0.5 + v(0, -0.85, 0), 0.32, 6, 2.9)
	end
	-- T5..T8: arms that reach for Morty
	for _, d in { v(-0.75, 0.45, -0.5), v(0.75, 0.45, -0.5), v(-0.45, 0.85, 0.25), v(0.45, 0.85, 0.25) } do
		tentacle(v(d.X * 3.2, 3, d.Z * 2.4), d, -0.1, 6, 2.3)
	end
	for i, off in { CFrame.new(0, 4, 0), CFrame.new(0, 12, 0) } do
		local p = r:point("Root", "Fog" .. i, off)
		r:emitter(p, "BlackCloud", {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = U.ColorSequence.new(rgb(6, 6, 8)),
			Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 5), U.NumberSequenceKeypoint.new(1, 18) }),
			Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 1), U.NumberSequenceKeypoint.new(0.2, 0.25), U.NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = U.NumberRange.new(3, 5),
			Speed = U.NumberRange.new(2, 5),
			SpreadAngle = U.Vector2.new(180, 180),
			Rate = 14,
			LightInfluence = 0.6,
			Enabled = false,
		})
	end
	r.model:SetAttribute("Tentacles", count)
	return r.model
end

----------------------------------------------------------------------------
-- Tentacles hiding inside the fake bunker (they rise out of the hatch)
----------------------------------------------------------------------------
function Titan.buildPitTentacles(parent, cf)
	local B = rgb(12, 10, 14)
	local B2 = rgb(26, 20, 30)
	local r = Rig.new("PitTentacles", parent, cf)
	for t = 1, 5 do
		local a = t / 5 * math.pi * 2
		local dir = v(math.cos(a) * 0.25, 1, math.sin(a) * 0.25).Unit
		local pos = v(math.cos(a) * 0.9, 0, math.sin(a) * 0.9)
		local prev = "Root"
		for k = 1, 7 do
			local bn = "T" .. t .. "_" .. k
			local c0 = if k == 1 then CFrame.lookAt(pos, pos + dir) * CFrame.Angles(-math.pi / 2, 0, 0) else CFrame.new(0, 1.3, 0)
			r:bone(bn, prev, c0, v(0, 1.3, 0), bn)
			local w = 1.7 * (1 - (k - 1) / 9)
			r:add(bn, "Seg", CFrame.new(0, 0, 0), v(w, 3.1, w), if k % 2 == 0 then B2 else B, M.SmoothPlastic, "ellipsoid")
			if k == 7 then
				r:add(bn, "Tip", CFrame.new(0, 1.6, 0), v(0.5, 1.6, 0.5), rgb(120, 12, 10), M.Neon, "ellipsoid")
			end
			prev = bn
		end
	end
	local fog = r:point("Root", "Fog", CFrame.new(0, 1, 0))
	r:emitter(fog, "BlackCloud", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = U.ColorSequence.new(rgb(6, 6, 8)),
		Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 3), U.NumberSequenceKeypoint.new(1, 10) }),
		Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 1), U.NumberSequenceKeypoint.new(0.2, 0.3), U.NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = U.NumberRange.new(2, 3),
		Speed = U.NumberRange.new(2, 4),
		SpreadAngle = U.Vector2.new(60, 60),
		Rate = 16,
		Enabled = false,
	})
	return r.model
end

----------------------------------------------------------------------------
-- The curse's hand (knocks the saucer down) and its severed head (held by the Titan)
----------------------------------------------------------------------------
function Titan.buildCurseHand(parent, cf)
	local m = U.model("CurseHand", parent)
	local BLACK2 = rgb(6, 6, 8)
	local root = U.marker(m, "Root", cf, v(1, 1, 1))
	m.PrimaryPart = root
	local function e(name, local_, size)
		local p = U.ellipsoid(m, name, cf * local_, size, BLACK2, M.SmoothPlastic, { CanCollide = false, CastShadow = false, Transparency = 1 })
		p:SetAttribute("HandPart", true)
		return p
	end
	e("Palm", CFrame.new(0, 0, 0), v(30, 36, 12))
	e("Wrist", CFrame.new(0, -30, 4), v(20, 40, 12))
	for i = -2, 1 do
		e("Finger" .. i, CFrame.new(i * 7 + 3, 28, -2) * CFrame.Angles(math.rad(-8), 0, math.rad(-i * 6)), v(6, 28, 6))
	end
	e("Thumb", CFrame.new(-17, 6, -2) * CFrame.Angles(0, 0, math.rad(50)), v(7, 22, 7))
	return m
end

function Titan.buildCurseHead(parent, cf)
	local m = U.model("CurseHead", parent)
	local root = U.marker(m, "Root", cf, v(1, 1, 1))
	m.PrimaryPart = root
	local B = rgb(8, 8, 10)
	U.ellipsoid(m, "Skull", cf, v(8, 9.5, 8), B, M.SmoothPlastic, { CanCollide = false })
	U.ellipsoid(m, "HornL", cf * CFrame.new(-2.8, 4.4, 1.2) * CFrame.Angles(math.rad(-30), 0, math.rad(25)), v(1.4, 6, 1.4), rgb(18, 16, 20), M.SmoothPlastic, { CanCollide = false })
	U.ellipsoid(m, "HornR", cf * CFrame.new(2.8, 4.4, 1.2) * CFrame.Angles(math.rad(-30), 0, math.rad(-25)), v(1.4, 6, 1.4), rgb(18, 16, 20), M.SmoothPlastic, { CanCollide = false })
	for _, side in { -1, 1 } do
		local eye = U.ellipsoid(m, "Eye", cf * CFrame.new(side * 1.9, 0.8, -3.7) * CFrame.Angles(0, 0, side * math.rad(14)), v(1.8, 0.7, 0.5), rgb(255, 30, 20), M.Neon, { CanCollide = false })
		eye:SetAttribute("CurseEye", true)
	end
	U.ellipsoid(m, "Mouth", cf * CFrame.new(0, -2.4, -3.6), v(3.4, 0.4, 0.4), rgb(150, 16, 10), M.Neon, { CanCollide = false })
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Wisps"
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = U.ColorSequence.new(rgb(8, 8, 10))
	pe.Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 2), U.NumberSequenceKeypoint.new(1, 5) })
	pe.Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.5), U.NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = U.NumberRange.new(1.5, 3)
	pe.Speed = U.NumberRange.new(1, 3)
	pe.Rate = 8
	pe.Enabled = false
	pe.Parent = root
	return m
end

----------------------------------------------------------------------------
-- Astro toilet ships + mothership
----------------------------------------------------------------------------
function Titan.buildAstroShip(parent, name, cf)
	local m = U.model(name, parent)
	local root = U.marker(m, "Root", cf, v(1, 1, 1))
	m.PrimaryPart = root
	local hull = rgb(120, 112, 140)
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	U.ellipsoid(m, "Hull", L(0, 0, 0), v(24, 5.5, 24), hull, M.Metal, { CanCollide = false })
	U.ecyl(m, "Rim", L(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), v(1.2, 25, 25), rgb(70, 64, 86), M.Metal, { CanCollide = false })
	U.ellipsoid(m, "Belly", L(0, -2.2, 0), v(12, 3, 12), rgb(80, 74, 96), M.Metal, { CanCollide = false })
	local glow = U.ecyl(m, "Engine", L(0, -3.6, 0) * CFrame.Angles(0, 0, math.rad(90)), v(0.3, 8, 8), rgb(200, 120, 255), M.Neon, { CanCollide = false, CastShadow = false })
	local pl = Instance.new("PointLight")
	pl.Name = "ShipLight"
	pl.Range = 30
	pl.Brightness = 2
	pl.Color = rgb(200, 120, 255)
	pl.Parent = glow
	for i = 0, 9 do
		local a = i * math.pi * 2 / 10
		U.ball(m, "Light" .. i, (L(math.cos(a) * 12.2, 0, math.sin(a) * 12.2)).Position, 0.9, rgb(220, 160, 255), M.Neon, { CanCollide = false, CastShadow = false })
	end
	U.ellipsoid(m, "Dome", L(0, 2.6, 0), v(8, 5.5, 8), rgb(190, 220, 255), M.Glass, { CanCollide = false, Transparency = 0.5 })
	-- the pilot: a toilet with a space helmet
	U.ellipsoid(m, "PilotBowl", L(0, 2.2, 0.4), v(2.4, 1.4, 3), rgb(244, 244, 240), M.SmoothPlastic, { CanCollide = false })
	U.ellipsoid(m, "PilotHead", L(0, 3.4, 0.2), v(1.4, 1.6, 1.4), rgb(240, 208, 176), M.SmoothPlastic, { CanCollide = false })
	U.ball(m, "PilotHelmet", (L(0, 3.5, 0.2)).Position, 2.1, rgb(200, 230, 255), M.Glass, { CanCollide = false, Transparency = 0.6 })
	return m
end

function Titan.buildMothership(parent, cf)
	local m = U.model("Mothership", parent)
	local root = U.marker(m, "Root", cf, v(1, 1, 1))
	m.PrimaryPart = root
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	U.ellipsoid(m, "Disc", L(0, 0, 0), v(760, 90, 760), rgb(64, 60, 76), M.Metal, { CanCollide = false })
	U.ecyl(m, "Ring", L(0, 4, 0) * CFrame.Angles(0, 0, math.rad(90)), v(14, 790, 790), rgb(86, 80, 104), M.Metal, { CanCollide = false })
	U.ellipsoid(m, "Crown", L(0, 52, 0), v(300, 120, 300), rgb(76, 70, 92), M.Metal, { CanCollide = false })
	U.ellipsoid(m, "Under", L(0, -40, 0), v(320, 60, 320), rgb(54, 50, 66), M.Metal, { CanCollide = false })
	local core = U.ecyl(m, "BeamCore", L(0, -70, 0) * CFrame.Angles(0, 0, math.rad(90)), v(30, 90, 90), rgb(210, 120, 255), M.Neon, { CanCollide = false, CastShadow = false })
	core:SetAttribute("MotherCore", true)
	local pl = Instance.new("PointLight")
	pl.Name = "MotherLight"
	pl.Range = 60
	pl.Brightness = 4
	pl.Color = rgb(210, 120, 255)
	pl.Parent = core
	for i = 0, 31 do
		local a = i * math.pi * 2 / 32
		U.part(m, "Window" .. i, L(math.cos(a) * 386, 4, math.sin(a) * 386) * CFrame.Angles(0, -a, 0), v(6, 4, 18), rgb(230, 170, 255), M.Neon, { CanCollide = false, CastShadow = false })
	end
	return m
end

function Titan.build(planetRoot, world)
	local fight = U.model("Fight", planetRoot)
	-- park everything far below the desert until the client needs it
	Titan.buildTitan(fight, CFrame.new(6200, -2000, -200))
	Titan.buildEntity(fight, CFrame.new(6500, -2400, -400))
	Titan.buildCurseHand(fight, CFrame.new(6000, -2800, 0))
	Titan.buildCurseHead(fight, CFrame.new(6100, -2900, 0))
	Titan.buildBeast(fight, "RickBeast", CFrame.new(6150, -3000, 0), "rick")
	Titan.buildBeast(fight, "EvilBeast", CFrame.new(6200, -3000, 0), "morty")
	Titan.buildPitTentacles(fight, CFrame.new(6080, -3100, -20))
	local astro = U.model("Astro", world)
	for i = 1, 10 do
		Titan.buildAstroShip(astro, "AstroShip" .. i, CFrame.new(9000 + i * 40, -3000, -9000))
	end
	Titan.buildMothership(astro, CFrame.new(9000, -3600, -9000))
	return fight
end

return Titan
