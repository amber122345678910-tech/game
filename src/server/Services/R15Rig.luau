--!strict
-- Процедурный R15-риг из обычных деталей (размеры и суставы — как у стандартного Block Rig Roblox),
-- чтобы на нём играли анимации Roblox (Zombie-пак). Масштаб и цвета — под каждого пациента.

local R15Rig = {}

local SIZES: { [string]: Vector3 } = {
	HumanoidRootPart = Vector3.new(2, 2, 1),
	LowerTorso = Vector3.new(2, 0.4, 1),
	UpperTorso = Vector3.new(2, 1.6, 1),
	Head = Vector3.new(1.2, 1.2, 1.2),
	LeftUpperArm = Vector3.new(1, 1.1687, 1),
	LeftLowerArm = Vector3.new(1, 1.0519, 1),
	LeftHand = Vector3.new(1, 0.3, 1),
	RightUpperArm = Vector3.new(1, 1.1687, 1),
	RightLowerArm = Vector3.new(1, 1.0519, 1),
	RightHand = Vector3.new(1, 0.3, 1),
	LeftUpperLeg = Vector3.new(1, 1.2166, 1),
	LeftLowerLeg = Vector3.new(1, 1.1931, 1),
	LeftFoot = Vector3.new(1, 0.3, 1),
	RightUpperLeg = Vector3.new(1, 1.2166, 1),
	RightLowerLeg = Vector3.new(1, 1.1931, 1),
	RightFoot = Vector3.new(1, 0.3, 1),
}

local OFFSETS: { [string]: Vector3 } = {
	HumanoidRootPart = Vector3.new(0, 0, 0),
	LowerTorso = Vector3.new(0, -0.8, 0),
	UpperTorso = Vector3.new(0, 0.2, 0),
	Head = Vector3.new(0, 1.5, 0),
	LeftUpperArm = Vector3.new(-1.5, 0.3687, 0),
	LeftLowerArm = Vector3.new(-1.5, -0.2241, 0),
	LeftHand = Vector3.new(-1.5, -0.85, 0),
	RightUpperArm = Vector3.new(1.5, 0.3687, 0),
	RightLowerArm = Vector3.new(1.5, -0.2241, 0),
	RightHand = Vector3.new(1.5, -0.85, 0),
	LeftUpperLeg = Vector3.new(-0.5, -1.4208, 0),
	LeftLowerLeg = Vector3.new(-0.5, -2.2009, 0),
	LeftFoot = Vector3.new(-0.5, -2.85, 0),
	RightUpperLeg = Vector3.new(0.5, -1.4208, 0),
	RightLowerLeg = Vector3.new(0.5, -2.2009, 0),
	RightFoot = Vector3.new(0.5, -2.85, 0),
}

local ATTACHMENTS: { [string]: { { any } } } = {
	HumanoidRootPart = { { "RootRigAttachment", Vector3.new(0, -1, 0) }, { "RootAttachment", Vector3.zero } },
	LowerTorso = {
		{ "RootRigAttachment", Vector3.new(0, -0.2, 0) },
		{ "WaistRigAttachment", Vector3.new(0, 0.2, 0) },
		{ "LeftHipRigAttachment", Vector3.new(-0.5, -0.2, 0) },
		{ "RightHipRigAttachment", Vector3.new(0.5, -0.2, 0) },
		{ "WaistCenterAttachment", Vector3.new(0, -0.2, 0) },
	},
	UpperTorso = {
		{ "WaistRigAttachment", Vector3.new(0, -0.8, 0) },
		{ "NeckRigAttachment", Vector3.new(0, 0.8, 0) },
		{ "LeftShoulderRigAttachment", Vector3.new(-1, 0.563, 0) },
		{ "RightShoulderRigAttachment", Vector3.new(1, 0.563, 0) },
		{ "BodyFrontAttachment", Vector3.new(0, -0.2, -0.5) },
		{ "NeckAttachment", Vector3.new(0, 0.8, 0) },
	},
	Head = {
		{ "NeckRigAttachment", Vector3.new(0, -0.5, 0) },
		{ "FaceCenterAttachment", Vector3.zero },
		{ "FaceFrontAttachment", Vector3.new(0, 0, -0.6) },
		{ "HatAttachment", Vector3.new(0, 0.6, 0) },
	},
	LeftUpperArm = { { "LeftShoulderRigAttachment", Vector3.new(0.5, 0.3943, 0) }, { "LeftElbowRigAttachment", Vector3.new(0, -0.3341, 0) } },
	LeftLowerArm = { { "LeftElbowRigAttachment", Vector3.new(0, 0.2587, 0) }, { "LeftWristRigAttachment", Vector3.new(0, -0.5009, 0) } },
	LeftHand = { { "LeftWristRigAttachment", Vector3.new(0, 0.125, 0) }, { "LeftGripAttachment", Vector3.new(0, -0.15, 0) } },
	RightUpperArm = { { "RightShoulderRigAttachment", Vector3.new(-0.5, 0.3943, 0) }, { "RightElbowRigAttachment", Vector3.new(0, -0.3341, 0) } },
	RightLowerArm = { { "RightElbowRigAttachment", Vector3.new(0, 0.2587, 0) }, { "RightWristRigAttachment", Vector3.new(0, -0.5009, 0) } },
	RightHand = { { "RightWristRigAttachment", Vector3.new(0, 0.125, 0) }, { "RightGripAttachment", Vector3.new(0, -0.15, 0) } },
	LeftUpperLeg = { { "LeftHipRigAttachment", Vector3.new(0, 0.4208, 0) }, { "LeftKneeRigAttachment", Vector3.new(0, -0.4011, 0) } },
	LeftLowerLeg = { { "LeftKneeRigAttachment", Vector3.new(0, 0.379, 0) }, { "LeftAnkleRigAttachment", Vector3.new(0, -0.5472, 0) } },
	LeftFoot = { { "LeftAnkleRigAttachment", Vector3.new(0, 0.1019, 0) }, { "LeftFootAttachment", Vector3.new(0, -0.15, 0) } },
	RightUpperLeg = { { "RightHipRigAttachment", Vector3.new(0, 0.4208, 0) }, { "RightKneeRigAttachment", Vector3.new(0, -0.4011, 0) } },
	RightLowerLeg = { { "RightKneeRigAttachment", Vector3.new(0, 0.379, 0) }, { "RightAnkleRigAttachment", Vector3.new(0, -0.5472, 0) } },
	RightFoot = { { "RightAnkleRigAttachment", Vector3.new(0, 0.1019, 0) }, { "RightFootAttachment", Vector3.new(0, -0.15, 0) } },
}

local JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso" },
	{ "Waist", "LowerTorso", "UpperTorso" },
	{ "Neck", "UpperTorso", "Head" },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm" },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm" },
	{ "LeftWrist", "LeftLowerArm", "LeftHand" },
	{ "RightShoulder", "UpperTorso", "RightUpperArm" },
	{ "RightElbow", "RightUpperArm", "RightLowerArm" },
	{ "RightWrist", "RightLowerArm", "RightHand" },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg" },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot" },
	{ "RightHip", "LowerTorso", "RightUpperLeg" },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg" },
	{ "RightAnkle", "RightLowerLeg", "RightFoot" },
}

local HEAD_PARTS: { [string]: boolean } = { Head = true }
local LIMB_PARTS: { [string]: boolean } = {
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

export type RigOptions = {
	Name: string,
	Scale: Vector3,
	Body: Color3,
	Head: Color3,
	Accent: Color3,
	Material: Enum.Material,
}

-- Строит риг; возвращает модель (не припаркованную) и таблицу частей
function R15Rig.build(opts: RigOptions, rootCFrame: CFrame): (Model, { [string]: BasePart }, Humanoid)
	local s = opts.Scale
	local model = Instance.new("Model")
	model.Name = opts.Name
	local parts: { [string]: BasePart } = {}
	for partName, size in SIZES do
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = size * s
		p.CFrame = rootCFrame * CFrame.new(OFFSETS[partName] * s)
		p.Anchored = false
		p.CanCollide = partName == "HumanoidRootPart"
		p.CanQuery = partName ~= "HumanoidRootPart"
		p.CanTouch = false
		p.CastShadow = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = opts.Material
		if HEAD_PARTS[partName] then
			p.Color = opts.Head
		elseif LIMB_PARTS[partName] then
			p.Color = if partName == "LeftHand" or partName == "RightHand" then opts.Head else opts.Body
		else
			p.Color = opts.Body
		end
		if partName == "HumanoidRootPart" then
			p.Transparency = 1
			p.RootPriority = 1
			p.CanQuery = false
		end
		for _, a in ATTACHMENTS[partName] do
			local att = Instance.new("Attachment")
			att.Name = a[1] :: string
			att.Position = (a[2] :: Vector3) * s
			att.Parent = p
		end
		p.Parent = model
		parts[partName] = p
	end
	for _, j in JOINTS do
		local jointName, p0Name, p1Name = j[1], j[2], j[3]
		local p0, p1 = parts[p0Name], parts[p1Name]
		local a0 = p0:FindFirstChild(jointName .. "RigAttachment") :: Attachment
		local a1 = p1:FindFirstChild(jointName .. "RigAttachment") :: Attachment
		local m = Instance.new("Motor6D")
		m.Name = jointName
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = a0.CFrame
		m.C1 = a1.CFrame
		m.Parent = p1
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2 * s.Y
	humanoid.AutomaticScalingEnabled = false
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayName = ""
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.AutoRotate = true
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	model.PrimaryPart = parts.HumanoidRootPart
	return model, parts, humanoid
end

-- Аксессуары из деталей: фонарь, повязка, шаль, мешок, фонарик, "полая" грудь, манекен, большие руки
function R15Rig.addAccessory(kind: string, parts: { [string]: BasePart }, accent: Color3, scale: Vector3)
	local head = parts.Head
	local torso = parts.UpperTorso
	local function weld(p: BasePart, to: BasePart, offset: CFrame)
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = to.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = to
		w.Part1 = p
		w.Parent = p
		p.Parent = to.Parent
	end
	if kind == "Lantern" then
		local hand = parts.RightHand
		local lantern = Instance.new("Part")
		lantern.Name = "Lantern"
		lantern.Size = Vector3.new(0.8, 1.2, 0.8)
		lantern.Color = accent
		lantern.Material = Enum.Material.Neon
		weld(lantern, hand, CFrame.new(0, -1.2, 0))
		local light = Instance.new("PointLight")
		light.Color = accent
		light.Range = 14
		light.Brightness = 1.4
		light.Shadows = true
		light.Parent = lantern
	elseif kind == "Blindfold" then
		local band = Instance.new("Part")
		band.Name = "Blindfold"
		band.Size = Vector3.new(1.3 * scale.X, 0.3 * scale.Y, 1.3 * scale.Z)
		band.Color = accent
		band.Material = Enum.Material.Fabric
		weld(band, head, CFrame.new(0, 0.1 * scale.Y, 0))
	elseif kind == "Shawl" then
		local shawl = Instance.new("Part")
		shawl.Name = "Shawl"
		shawl.Size = Vector3.new(2.4 * scale.X, 1.2 * scale.Y, 1.3 * scale.Z)
		shawl.Color = accent
		shawl.Material = Enum.Material.Fabric
		weld(shawl, torso, CFrame.new(0, 0.5 * scale.Y, 0))
		local hood = Instance.new("Part")
		hood.Name = "Hood"
		hood.Size = Vector3.new(1.5 * scale.X, 1.3 * scale.Y, 1.4 * scale.Z)
		hood.Color = accent
		hood.Material = Enum.Material.Fabric
		weld(hood, head, CFrame.new(0, 0.15 * scale.Y, 0.15 * scale.Z))
	elseif kind == "Sack" then
		local sack = Instance.new("Part")
		sack.Name = "Sack"
		sack.Size = Vector3.new(1.8 * scale.X, 2 * scale.Y, 1.2 * scale.Z)
		sack.Color = accent
		sack.Material = Enum.Material.Fabric
		weld(sack, torso, CFrame.new(0, 0.2 * scale.Y, 1.1 * scale.Z))
	elseif kind == "Flashlight" then
		local hand = parts.RightHand
		local torch = Instance.new("Part")
		torch.Name = "Torch"
		torch.Size = Vector3.new(0.5, 0.5, 1.4)
		torch.Color = Color3.fromRGB(40, 40, 44)
		torch.Material = Enum.Material.Metal
		weld(torch, hand, CFrame.new(0, -0.2, -0.6))
		local lens = Instance.new("Part")
		lens.Name = "Lens"
		lens.Size = Vector3.new(0.55, 0.55, 0.15)
		lens.Color = accent
		lens.Material = Enum.Material.Neon
		weld(lens, torch, CFrame.new(0, 0, -0.75))
		local spot = Instance.new("SpotLight")
		spot.Name = "Beam"
		spot.Face = Enum.NormalId.Front
		spot.Angle = 40
		spot.Range = 45
		spot.Brightness = 3
		spot.Color = accent
		spot.Shadows = true
		spot.Enabled = false
		spot.Parent = lens
	elseif kind == "Hollow" then
		local hole = Instance.new("Part")
		hole.Name = "Hollow"
		hole.Size = Vector3.new(1.2 * scale.X, 1.1 * scale.Y, 0.3)
		hole.Color = accent
		hole.Material = Enum.Material.Neon
		weld(hole, torso, CFrame.new(0, 0, -0.45 * scale.Z))
		local light = Instance.new("PointLight")
		light.Color = accent
		light.Range = 10
		light.Brightness = 0.8
		light.Parent = hole
	elseif kind == "Mannequin" then
		-- без лица: гладкая голова чуть больше
		head.Material = Enum.Material.SmoothPlastic
		local neck = Instance.new("Part")
		neck.Name = "Stand"
		neck.Size = Vector3.new(0.4, 0.6, 0.4)
		neck.Color = accent
		neck.Material = Enum.Material.Metal
		weld(neck, parts.LowerTorso, CFrame.new(0, -0.1, 0))
	elseif kind == "BigHands" then
		for _, name in { "LeftHand", "RightHand" } do
			local h = parts[name]
			h.Size = Vector3.new(1.4 * scale.X, 0.6 * scale.Y, 1.4 * scale.Z)
		end
	end
end

-- Простое "лицо": два тёмных глаза (без текстур)
function R15Rig.addEyes(parts: { [string]: BasePart }, color: Color3, scale: Vector3, glow: boolean)
	local head = parts.Head
	for _, x in { -0.28, 0.28 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.2, 0.28, 0.1) * Vector3.new(scale.X, scale.Y, 1)
		eye.Color = color
		eye.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
		eye.Anchored = false
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.CFrame = head.CFrame * CFrame.new(x * scale.X, 0.1 * scale.Y, -0.6 * scale.Z)
		local w = Instance.new("WeldConstraint")
		w.Part0 = head
		w.Part1 = eye
		w.Parent = eye
		eye.Parent = head.Parent
	end
end

return R15Rig
