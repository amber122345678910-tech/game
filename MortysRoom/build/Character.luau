--!nocheck
-- Morty as a StarterCharacter (classic R6 rig so standard animations work),
-- with rounded cosmetic parts welded on top of the invisible rig parts.
local U = require("./Util")
local Vector3, CFrame, Enum, Instance = U.Vector3, U.CFrame, U.Enum, U.Instance
local rgb, v = U.rgb, U.v

local Character = {}

local SKIN = rgb(250, 214, 178)
local SKIN_SHADE = rgb(236, 192, 156)
local HAIR = rgb(110, 68, 36)
local SHIRT = rgb(246, 222, 60)
local PANTS = rgb(52, 92, 160)
local SHOE = rgb(240, 240, 240)

local function rigPart(model, name, size, cf, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Transparency = 1
	p.CanCollide = collide
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = SKIN
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
	m.MaxVelocity = 0.1
	m.Parent = parentPart
	return m
end

local function cosmetic(limb, name, cf, size, color, kind, group)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
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
	p:SetAttribute("BodyGroup", group)
	p.Parent = limb.Parent
	local w = Instance.new("Weld")
	w.Name = "CosmeticWeld"
	w.Part0 = limb
	w.Part1 = p
	w.C0 = limb.CFrame:Inverse() * cf
	w.C1 = CFrame.new()
	w.Parent = p
	return p
end

function Character.build(parent, animateSource)
	local model = Instance.new("Model")
	model.Name = "StarterCharacter"

	local o = CFrame.new(0, 3, 0)
	local hrp = rigPart(model, "HumanoidRootPart", v(2, 2, 1), o, false)
	local torso = rigPart(model, "Torso", v(2, 2, 1), o, true)
	local head = rigPart(model, "Head", v(2, 1, 1), o * CFrame.new(0, 1.5, 0), true)
	local la = rigPart(model, "Left Arm", v(1, 2, 1), o * CFrame.new(-1.5, 0, 0), false)
	local ra = rigPart(model, "Right Arm", v(1, 2, 1), o * CFrame.new(1.5, 0, 0), false)
	local ll = rigPart(model, "Left Leg", v(1, 2, 1), o * CFrame.new(-0.5, -2, 0), false)
	local rl = rigPart(model, "Right Leg", v(1, 2, 1), o * CFrame.new(0.5, -2, 0), false)

	motor(hrp, "RootJoint", hrp, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor(torso, "Neck", torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor(torso, "Right Shoulder", torso, ra, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor(torso, "Left Shoulder", torso, la, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor(torso, "Right Hip", torso, rl, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor(torso, "Left Hip", torso, ll, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))

	-- cosmetic body ---------------------------------------------------------
	local tc = torso.CFrame
	cosmetic(torso, "Shirt", tc * CFrame.new(0, 0.12, 0), v(1.8, 1.85, 1.08), SHIRT, "ellipsoid", "Body")
	cosmetic(torso, "Hem", tc * CFrame.new(0, -0.62, 0), v(1.72, 0.32, 1.02), SHIRT, "ellipsoid", "Body")
	cosmetic(torso, "Hips", tc * CFrame.new(0, -0.82, 0), v(1.62, 0.7, 0.98), PANTS, "ellipsoid", "Body")
	cosmetic(torso, "Neck", tc * CFrame.new(0, 1.05, 0) * CFrame.Angles(0, 0, math.rad(90)), v(0.4, 0.5, 0.5), SKIN, "cylinder", "Head")

	local hc = head.CFrame * CFrame.new(0, 0.42, 0)
	cosmetic(head, "HeadCore", hc, v(2.0, 1.8, 1.7), SKIN, "ellipsoid", "Head")
	cosmetic(head, "Hair", hc * CFrame.new(0, 0.34, 0.07), v(2.08, 1.35, 1.75), HAIR, "ellipsoid", "Head")
	cosmetic(head, "EarL", hc * CFrame.new(-1.0, -0.05, 0.05), v(0.28, 0.42, 0.3), SKIN, "ellipsoid", "Head")
	cosmetic(head, "EarR", hc * CFrame.new(1.0, -0.05, 0.05), v(0.28, 0.42, 0.3), SKIN, "ellipsoid", "Head")
	cosmetic(head, "EyeL", hc * CFrame.new(-0.4, 0.04, -0.72), v(0.6, 0.6, 0.3), rgb(255, 255, 255), "ellipsoid", "Head")
	cosmetic(head, "EyeR", hc * CFrame.new(0.4, 0.04, -0.72), v(0.6, 0.6, 0.3), rgb(255, 255, 255), "ellipsoid", "Head")
	cosmetic(head, "PupilL", hc * CFrame.new(-0.36, 0.02, -0.87), v(0.12, 0.12, 0.06), rgb(20, 20, 20), "ellipsoid", "Head")
	cosmetic(head, "PupilR", hc * CFrame.new(0.36, 0.02, -0.87), v(0.12, 0.12, 0.06), rgb(20, 20, 20), "ellipsoid", "Head")
	cosmetic(head, "Nose", hc * CFrame.new(0, -0.24, -0.84), v(0.16, 0.14, 0.12), SKIN_SHADE, "ellipsoid", "Head")
	cosmetic(head, "Mouth", hc * CFrame.new(0, -0.52, -0.73), v(0.36, 0.06, 0.08), rgb(90, 40, 40), "ellipsoid", "Head")

	local function arm(limb, side)
		local c = limb.CFrame * CFrame.new(-side * 0.38, 0, 0)
		local up = CFrame.Angles(0, 0, math.rad(90))
		cosmetic(limb, "Sleeve", c * CFrame.new(0, 0.62, 0) * up, v(0.75, 0.72, 0.72), SHIRT, "cylinder", "Arms")
		cosmetic(limb, "SleeveTop", c * CFrame.new(0, 0.95, 0), v(0.72, 0.4, 0.72), SHIRT, "ellipsoid", "Arms")
		cosmetic(limb, "Arm", c * CFrame.new(0, -0.18, 0) * up, v(1.3, 0.46, 0.46), SKIN, "cylinder", "Arms")
		cosmetic(limb, "Hand", c * CFrame.new(0, -0.92, 0), v(0.52, 0.58, 0.48), SKIN, "ellipsoid", "Arms")
	end
	arm(la, -1)
	arm(ra, 1)

	local function leg(limb)
		local c = limb.CFrame
		local up = CFrame.Angles(0, 0, math.rad(90))
		cosmetic(limb, "Pants", c * CFrame.new(0, 0.18, 0) * up, v(1.62, 0.74, 0.74), PANTS, "cylinder", "Legs")
		cosmetic(limb, "Shoe", c * CFrame.new(0, -0.78, -0.12), v(0.74, 0.46, 1.06), SHOE, "ellipsoid", "Legs")
		cosmetic(limb, "Sole", c * CFrame.new(0, -0.95, -0.1), v(0.7, 0.1, 1.0), rgb(200, 200, 200), "box", "Legs")
	end
	leg(ll)
	leg(rl)

	-- humanoid ----------------------------------------------------------------
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R6
	hum.HipHeight = 0
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = hum

	local animate = Instance.new("LocalScript")
	animate.Name = "Animate"
	animate.Source = animateSource
	animate.Parent = model

	model.PrimaryPart = hrp
	model.Parent = parent
	return model
end

return Character
