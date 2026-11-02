--!nocheck
-- Titan Speakerman 2.0, the black entity and the "curse hand".
-- Each is a rig: invisible bone parts joined by Motor6Ds (root anchored); the client animates Motor6D.Transform.
-- Joint axes are body aligned: X = right, Y = up, -Z = forward.
local U = require("./Util")
local Vector3, CFrame, Enum, Instance = U.Vector3, U.CFrame, U.Enum, U.Instance
local rgb, v = U.rgb, U.v
local M = Enum.Material

local Titan = {}

local GUN = rgb(58, 62, 70)
local DARK = rgb(26, 27, 31)
local SILVER = rgb(172, 177, 188)
local BLUE = rgb(70, 200, 255)

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

-- add a bone `name` attached to `parentName` with joint at C0 (in parent space); the bone's own centre sits
-- at `offset` from the joint (in joint space, i.e. C1 = CFrame.new(-offset))
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

-- cosmetic part welded to bone. `local` = CFrame relative to the bone.
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
			p[k] = val
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

-- marker attachment-like part on a bone (for effects)
function Rig:point(boneName, name, localCF)
	return self:add(boneName, name, localCF, v(0.5, 0.5, 0.5), rgb(255, 0, 255), M.SmoothPlastic, nil, { Transparency = 1 })
end

local AXIS_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis (local X) -> Z
local AXIS_Y = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis -> Y

----------------------------------------------------------------------------
-- Titan Speakerman 2.0 (about 67 studs tall). Root = pelvis centre, 30.4 above the feet.
----------------------------------------------------------------------------
function Titan.buildTitan(parent, groundCF)
	local rootCF = groundCF * CFrame.new(0, 30.4, 0)
	local r = Rig.new("TitanSpeakerman", parent, rootCF)
	r:bone("Pelvis", "Root", CFrame.new(), v(0, 0, 0), "Hips")
	r:bone("Torso", "Pelvis", CFrame.new(0, 2.5, 0), v(0, 9, 0), "Waist")
	r:bone("Head", "Torso", CFrame.new(0, 9.5, 0), v(0, 10.6, 0), "Neck")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:bone("UpperArm" .. s, "Torso", CFrame.new(side * 12.5, 6.0, 0), v(0, -5.5, 0), "Shoulder" .. s)
		r:bone("Forearm" .. s, "UpperArm" .. s, CFrame.new(0, -5.5, 0), v(0, -6, 0), "Elbow" .. s)
		r:bone("Hand" .. s, "Forearm" .. s, CFrame.new(0, -6, 0), v(0, -2.2, 0), "Wrist" .. s)
		r:bone("Thigh" .. s, "Pelvis", CFrame.new(side * 4.6, -2, 0), v(0, -6.5, 0), "Hip" .. s)
		r:bone("Shin" .. s, "Thigh" .. s, CFrame.new(0, -6.5, 0), v(0, -6.5, 0), "Knee" .. s)
		r:bone("Foot" .. s, "Shin" .. s, CFrame.new(0, -6.5, 0), v(0, -1.2, -1.6), "Ankle" .. s)
	end

	-- pelvis
	r:add("Pelvis", "PelvisArmor", CFrame.new(0, 0, 0), v(13, 6, 8.4), GUN)
	r:add("Pelvis", "Belt", CFrame.new(0, 2.2, 0), v(13.8, 1.5, 9), DARK)
	r:add("Pelvis", "Buckle", CFrame.new(0, 2.2, -4.6), v(2.4, 1.2, 0.4), BLUE, M.Neon)
	for _, side in { -1, 1 } do
		r:add("Pelvis", "Tasset", CFrame.new(side * 4.4, -1.5, -4.0) * CFrame.Angles(math.rad(-10), 0, side * math.rad(8)), v(4.6, 5, 0.9), SILVER)
	end

	-- torso: chest, abs, glowing core, shoulder speakers, jetpack
	r:add("Torso", "Chest", CFrame.new(0, 3.0, 0), v(21, 12.5, 11.5), GUN)
	r:add("Torso", "ChestTop", CFrame.new(0, 8.2, 0.5), v(17, 2.5, 10), DARK)
	r:add("Torso", "Abdomen", CFrame.new(0, -6.0, 0.4), v(14, 7.5, 9.2), DARK)
	for row = 0, 2 do
		for _, side in { -1, 1 } do
			r:add("Torso", "Ab" .. row .. side, CFrame.new(side * 2.6, -3.6 - row * 2.3, -4.4), v(4.4, 1.8, 0.8), GUN)
		end
	end
	for _, side in { -1, 1 } do
		r:add("Torso", "Pec", CFrame.new(side * 5.6, 5.0, -5.6) * CFrame.Angles(math.rad(8), side * math.rad(-12), 0), v(8, 5.4, 1.0), SILVER)
		r:add("Torso", "RibPlate", CFrame.new(side * 9.8, -0.5, -3.6) * CFrame.Angles(0, side * math.rad(-30), 0), v(1.0, 6, 5), DARK)
	end
	r:add("Torso", "CoreHousing", CFrame.new(0, 2.0, -5.8) * AXIS_Z, v(1.8, 7.2, 7.2), DARK, M.Metal, "cylinder")
	r:add("Torso", "CoreRing", CFrame.new(0, 2.0, -6.4) * AXIS_Z, v(0.5, 6.4, 6.4), BLUE, M.Neon, "cylinder")
	r:add("Torso", "CoreRingIn", CFrame.new(0, 2.0, -6.55) * AXIS_Z, v(0.5, 5.4, 5.4), DARK, M.Metal, "cylinder")
	local core = r:add("Torso", "Core", CFrame.new(0, 2.0, -6.6), v(4.4, 4.4, 2.6), rgb(150, 230, 255), M.Neon, "ellipsoid")
	core:SetAttribute("TitanCore", true)
	local coreLight = Instance.new("PointLight")
	coreLight.Name = "CoreLight"
	coreLight.Range = 40
	coreLight.Brightness = 2
	coreLight.Color = BLUE
	coreLight.Shadows = false
	coreLight.Parent = core
	r:add("Torso", "Collar", CFrame.new(0, 9.4, 0) * AXIS_Y, v(1.8, 8, 8), DARK, M.Metal, "cylinder")
	-- shoulder speaker pods
	for _, side in { -1, 1 } do
		local x = side * 12.8
		r:add("Torso", "PodBody", CFrame.new(x, 7.0, 0) * AXIS_Z, v(5.5, 9.6, 9.6), DARK, M.Metal, "cylinder")
		r:add("Torso", "PodRim", CFrame.new(x, 7.0, -2.9) * AXIS_Z, v(0.7, 9.8, 9.8), SILVER, M.Metal, "cylinder")
		r:add("Torso", "PodCone", CFrame.new(x, 7.0, -3.0), v(7.6, 7.6, 2.2), rgb(36, 36, 40), M.SmoothPlastic, "ellipsoid")
		r:add("Torso", "PodCap", CFrame.new(x, 7.0, -3.9), v(2.6, 2.6, 1.0), BLUE, M.Neon, "ellipsoid")
		r:add("Torso", "Pauldron", CFrame.new(x, 11.6, 0.4) * CFrame.Angles(0, 0, side * math.rad(-14)), v(11, 3.6, 10), GUN, M.Metal, "ellipsoid")
		r:point("Torso", "Pod" .. (if side < 0 then "L" else "R"), CFrame.new(x, 7.0, -4.5))
	end
	-- jetpack
	r:add("Torso", "Pack", CFrame.new(0, 1.5, 7.6), v(12, 13, 4.2), DARK)
	r:add("Torso", "PackStripe", CFrame.new(0, 5.5, 9.8), v(9, 0.6, 0.4), BLUE, M.Neon)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:add("Torso", "Thruster" .. s, CFrame.new(side * 4.2, -2.0, 10.4) * CFrame.Angles(math.rad(15), 0, 0) * AXIS_Y, v(9, 4.2, 4.2), GUN, M.Metal, "cylinder")
		local noz = r:add("Torso", "Nozzle" .. s, CFrame.new(side * 4.2, -6.4, 11.6) * CFrame.Angles(math.rad(15), 0, 0) * AXIS_Y, v(0.4, 3.4, 3.4), BLUE, M.Neon, "cylinder")
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Jet"
		pe.Texture = "rbxasset://textures/particles/fire_main.dds"
		pe.Color = U.ColorSequence.new(rgb(150, 230, 255), rgb(40, 90, 255))
		pe.LightEmission = 1
		pe.Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 3.2), U.NumberSequenceKeypoint.new(1, 0.6) })
		pe.Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.1), U.NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = U.NumberRange.new(0.3, 0.5)
		pe.Speed = U.NumberRange.new(40, 60)
		pe.Rate = 80
		pe.EmissionDirection = Enum.NormalId.Left
		pe.Enabled = false
		pe.Parent = noz
		local jl = Instance.new("PointLight")
		jl.Name = "JetLight"
		jl.Range = 30
		jl.Brightness = 0
		jl.Color = BLUE
		jl.Parent = noz
	end

	-- head: one big speaker cabinet (scaled up 25%)
	local HS = 1.25
	local function hs(cf)
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		return CFrame.new(x * HS, y * HS, z * HS, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	end
	local function hadd(name, cf, size, ...)
		return r:add("Head", name, hs(cf), size * HS, ...)
	end
	local function hpoint(name, cf)
		return r:point("Head", name, hs(cf))
	end
	hadd("Cabinet", CFrame.new(0, 0, 0), v(15, 16, 11), DARK)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			hadd("Edge", CFrame.new(sx * 7.4, 0, sz * 5.4), v(0.8, 16.2, 0.8), SILVER)
		end
	end
	hadd("TopPlate", CFrame.new(0, 8.1, 0), v(15.4, 0.6, 11.4), GUN)
	hadd("Rim", CFrame.new(0, -1.6, -5.5) * AXIS_Z, v(0.9, 12.4, 12.4), SILVER, M.Metal, "cylinder")
	hadd("Surround", CFrame.new(0, -1.6, -5.75) * AXIS_Z, v(0.5, 11.2, 11.2), rgb(46, 46, 50), M.Rubber, "cylinder")
	hadd("Cone", CFrame.new(0, -1.6, -5.7), v(9.6, 9.6, 2.4), rgb(20, 20, 22), M.SmoothPlastic, "ellipsoid")
	local eye = hadd("DustCap", CFrame.new(0, -1.6, -6.6), v(3.4, 3.4, 1.4), rgb(160, 235, 255), M.Neon, "ellipsoid")
	eye:SetAttribute("TitanEye", true)
	local eyeLight = Instance.new("PointLight")
	eyeLight.Name = "EyeLight"
	eyeLight.Range = 30
	eyeLight.Brightness = 1.5
	eyeLight.Color = BLUE
	eyeLight.Parent = eye
	hadd("Tweeter", CFrame.new(0, 5.6, -5.6) * AXIS_Z, v(0.7, 3.4, 3.4), SILVER, M.Metal, "cylinder")
	hadd("TweeterGlow", CFrame.new(0, 5.6, -5.9) * AXIS_Z, v(0.4, 1.8, 1.8), BLUE, M.Neon, "cylinder")
	hadd("LightBar", CFrame.new(0, 7.4, -5.55), v(10, 0.5, 0.3), BLUE, M.Neon)
	for _, side in { -1, 1 } do
		hadd("SideSpeaker", CFrame.new(side * 7.6, 2.0, 0) * CFrame.Angles(0, 0, 0), v(0.8, 4.4, 4.4), SILVER, M.Metal, "cylinder")
		hadd("SideGlow", CFrame.new(side * 7.95, 2.0, 0), v(0.3, 2.2, 2.2), BLUE, M.Neon, "cylinder")
	end
	hadd("Neck", CFrame.new(0, -9.2, 0) * AXIS_Y, v(4, 5.4, 5.4), GUN, M.Metal, "cylinder")
	hpoint("Mouth", CFrame.new(0, -1.6, -8))

	-- arms
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:add("UpperArm" .. s, "Upper", CFrame.new(0, 0, 0) * AXIS_Y, v(11, 5.4, 5.4), GUN, M.Metal, "cylinder")
		r:add("UpperArm" .. s, "Bicep", CFrame.new(side * 0.6, 0.5, -0.4), v(5.2, 7, 5.6), SILVER, M.Metal, "ellipsoid")
		r:add("UpperArm" .. s, "Elbow", CFrame.new(0, -5.5, 0), v(5.6, 5.6, 5.6), DARK, M.Metal, "ball")
		if s == "R" then
			-- sonic cannon forearm
			r:add("Forearm" .. s, "Cannon", CFrame.new(0, -0.5, 0) * AXIS_Y, v(12.5, 6.6, 6.6), GUN, M.Metal, "cylinder")
			r:add("Forearm" .. s, "CannonBand1", CFrame.new(0, 3.2, 0) * AXIS_Y, v(0.8, 7.2, 7.2), SILVER, M.Metal, "cylinder")
			r:add("Forearm" .. s, "CannonBand2", CFrame.new(0, -2.0, 0) * AXIS_Y, v(0.8, 7.2, 7.2), BLUE, M.Neon, "cylinder")
			r:add("Forearm" .. s, "MuzzleRim", CFrame.new(0, -6.6, 0) * AXIS_Y, v(0.8, 7.4, 7.4), SILVER, M.Metal, "cylinder")
			r:add("Forearm" .. s, "MuzzleCone", CFrame.new(0, -6.8, 0), v(5.4, 1.6, 5.4), rgb(20, 20, 24), M.SmoothPlastic, "ellipsoid")
			local m = r:add("Forearm" .. s, "MuzzleGlow", CFrame.new(0, -7.2, 0), v(2.4, 0.8, 2.4), rgb(170, 240, 255), M.Neon, "ellipsoid")
			m:SetAttribute("TitanMuzzle", true)
			r:point("Forearm" .. s, "Muzzle", CFrame.new(0, -8.5, 0))
		else
			r:add("Forearm" .. s, "Forearm", CFrame.new(0, 0, 0), v(6, 12, 6.2), GUN)
			r:add("Forearm" .. s, "Gauntlet", CFrame.new(0, -3.0, -0.4), v(6.6, 5, 6.8), SILVER)
			r:add("Forearm" .. s, "Glow", CFrame.new(side * 3.1, -1, 0), v(0.3, 7, 1.2), BLUE, M.Neon)
			r:add("Hand" .. s, "Fist", CFrame.new(0, 0, 0), v(5.2, 4.6, 5.2), GUN)
			r:add("Hand" .. s, "Knuckles", CFrame.new(0, -0.8, -2.6), v(4.8, 1.6, 0.8), SILVER)
			r:add("Hand" .. s, "Thumb", CFrame.new(-side * 2.6, 0.6, -1.2), v(1.4, 3, 1.6), DARK)
		end
	end

	-- legs
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:add("Thigh" .. s, "Thigh", CFrame.new(0, 0, 0), v(7.4, 13, 7.8), GUN)
		r:add("Thigh" .. s, "ThighPlate", CFrame.new(0, 1, -4.0) * CFrame.Angles(math.rad(-4), 0, 0), v(6, 9, 0.8), SILVER)
		r:add("Thigh" .. s, "Knee", CFrame.new(0, -6.5, -1.4), v(6.4, 6.4, 6.4), DARK, M.Metal, "ball")
		r:add("Shin" .. s, "Shin", CFrame.new(0, 0, 0.4), v(7.6, 13, 8.2), GUN)
		r:add("Shin" .. s, "ShinPlate", CFrame.new(0, 0.6, -4.1) * CFrame.Angles(math.rad(4), 0, 0), v(6.2, 11, 0.9), SILVER)
		r:add("Shin" .. s, "CalfGlow", CFrame.new(side * 3.85, -1, 1.5), v(0.3, 6, 1.2), BLUE, M.Neon)
		r:add("Foot" .. s, "Foot", CFrame.new(0, 0, 0), v(8.2, 2.4, 12.4), DARK)
		r:add("Foot" .. s, "Toe", CFrame.new(0, 0.6, -5.4), v(7.6, 1.6, 2.4), GUN)
	end
	r.model:SetAttribute("StandHeight", 30.4)
	return r.model
end

----------------------------------------------------------------------------
-- The entity: huge black shape inside a black cloud. Root at its feet.
----------------------------------------------------------------------------
function Titan.buildEntity(parent, groundCF)
	local BLACK = rgb(8, 8, 10)
	local BLACK2 = rgb(16, 14, 18)
	local RED = rgb(255, 30, 20)
	local r = Rig.new("Entity", parent, groundCF)
	r:bone("Body", "Root", CFrame.new(0, 40, 0), v(0, 30, 0), "Waist")
	r:bone("Head", "Body", CFrame.new(0, 34, 0), v(0, 14, 0), "Neck")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:bone("ArmA" .. s, "Body", CFrame.new(side * 22, 24, 0), v(0, -20, 0), "Shoulder" .. s)
		r:bone("ArmB" .. s, "ArmA" .. s, CFrame.new(0, -20, 0), v(0, -20, 0), "Elbow" .. s)
		r:bone("Claw" .. s, "ArmB" .. s, CFrame.new(0, -20, 0), v(0, -6, 0), "Wrist" .. s)
	end
	-- tendrils from the back
	for t = 1, 6 do
		local a = (t - 3.5) * 0.45
		local prev = "Body"
		local c0 = CFrame.new(math.sin(a) * 14, 10 + math.abs(t - 3.5) * 3, 10) * CFrame.Angles(math.rad(-50), a, 0)
		for k = 1, 5 do
			local name = "T" .. t .. "_" .. k
			r:bone(name, prev, if k == 1 then c0 else CFrame.new(0, 12, 0), v(0, 6, 0), name)
			r:add(name, "Seg", CFrame.new(0, 0, 0), v(5.5 - k * 0.7, 14, 5.5 - k * 0.7), BLACK2, M.SmoothPlastic, "ellipsoid")
			prev = name
		end
	end
	r:add("Body", "Chest", CFrame.new(0, 6, 0), v(46, 50, 32), BLACK, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Belly", CFrame.new(0, -18, 2), v(36, 34, 28), BLACK2, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Lump1", CFrame.new(-14, 20, 6), v(20, 18, 18), BLACK, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Lump2", CFrame.new(16, 22, 4), v(18, 16, 18), BLACK, M.SmoothPlastic, "ellipsoid")
	r:add("Body", "Crack", CFrame.new(0, 4, -15.6) * CFrame.Angles(0, 0, math.rad(8)), v(2.4, 26, 1.0), rgb(140, 10, 10), M.Neon)
	r:add("Head", "Skull", CFrame.new(0, 0, 0), v(24, 28, 24), BLACK, M.SmoothPlastic, "ellipsoid")
	r:add("Head", "Horn1", CFrame.new(-8, 12, 4) * CFrame.Angles(math.rad(-30), 0, math.rad(25)), v(4, 18, 4), BLACK2, M.SmoothPlastic, "ellipsoid")
	r:add("Head", "Horn2", CFrame.new(8, 12, 4) * CFrame.Angles(math.rad(-30), 0, math.rad(-25)), v(4, 18, 4), BLACK2, M.SmoothPlastic, "ellipsoid")
	for _, side in { -1, 1 } do
		local eye = r:add("Head", "Eye", CFrame.new(side * 5.5, 2, -11.2) * CFrame.Angles(0, 0, side * math.rad(-14)), v(5.2, 2.0, 1.6), RED, M.Neon, "ellipsoid")
		eye:SetAttribute("EntityEye", true)
		local l = Instance.new("PointLight")
		l.Name = "EntityEyeLight"
		l.Range = 40
		l.Brightness = 3
		l.Color = RED
		l.Parent = eye
	end
	r:add("Head", "Mouth", CFrame.new(0, -7, -11) , v(10, 1.2, 1.0), rgb(180, 20, 10), M.Neon, "ellipsoid")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		r:add("ArmA" .. s, "Upper", CFrame.new(0, 0, 0), v(9, 42, 9), BLACK, M.SmoothPlastic, "ellipsoid")
		r:add("ArmB" .. s, "Lower", CFrame.new(0, 0, 0), v(7.5, 42, 7.5), BLACK2, M.SmoothPlastic, "ellipsoid")
		for f = -1, 1 do
			r:add("Claw" .. s, "Finger" .. f, CFrame.new(f * 3, -5, -1) * CFrame.Angles(math.rad(-20), 0, f * math.rad(-12)), v(2.2, 16, 2.2), BLACK, M.SmoothPlastic, "ellipsoid")
		end
		r:add("Claw" .. s, "Palm", CFrame.new(0, 2, 0), v(10, 8, 6), BLACK2, M.SmoothPlastic, "ellipsoid")
	end
	-- black cloud emitters (switched on by the client)
	local cloudOffsets = {
		CFrame.new(0, 10, 0), CFrame.new(-30, 30, 0), CFrame.new(30, 30, 0), CFrame.new(0, 50, 10),
		CFrame.new(-20, 70, -6), CFrame.new(22, 64, -4), CFrame.new(0, 90, 0), CFrame.new(0, 30, -30),
	}
	for i, off in cloudOffsets do
		local p = r:point("Root", "Cloud" .. i, off)
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "BlackCloud"
		pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
		pe.Color = U.ColorSequence.new(rgb(6, 6, 8), rgb(20, 16, 22))
		pe.Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 26), U.NumberSequenceKeypoint.new(1, 70) })
		pe.Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 1), U.NumberSequenceKeypoint.new(0.15, 0.15), U.NumberSequenceKeypoint.new(0.8, 0.3), U.NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = U.NumberRange.new(6, 10)
		pe.Speed = U.NumberRange.new(3, 9)
		pe.SpreadAngle = U.Vector2.new(180, 180)
		pe.RotSpeed = U.NumberRange.new(-12, 12)
		pe.Rotation = U.NumberRange.new(0, 360)
		pe.Rate = 7
		pe.LightInfluence = 0.6
		pe.Acceleration = v(0, 1.5, 0)
		pe.Enabled = false
		pe.Parent = p
	end
	r.model:SetAttribute("Height", 150)
	return r.model
end

----------------------------------------------------------------------------
-- The curse's hand that knocks the saucer out of the sky (a dark blur).
----------------------------------------------------------------------------
function Titan.buildCurseHand(parent, cf)
	local m = U.model("CurseHand", parent)
	local BLACK = rgb(6, 6, 8)
	local root = U.marker(m, "Root", cf, v(1, 1, 1))
	m.PrimaryPart = root
	local function e(name, local_, size)
		local p = U.ellipsoid(m, name, cf * local_, size, BLACK, M.SmoothPlastic, { CanCollide = false, CastShadow = false, Transparency = 1 })
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

function Titan.build(planetRoot)
	local fight = U.model("Fight", planetRoot)
	-- park everything far below the desert until the client needs it
	Titan.buildTitan(fight, CFrame.new(6200, -2000, -200))
	Titan.buildEntity(fight, CFrame.new(6500, -2400, -400))
	Titan.buildCurseHand(fight, CFrame.new(6000, -2800, 0))
	return fight
end

return Titan
