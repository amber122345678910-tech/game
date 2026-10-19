--!nocheck
-- Сборщик рига (Lune): скелет R15 из невидимых «костей» + Motor6D, видимые детали привариваются к костям.
--
-- СИСТЕМА КООРДИНАТ ПЕРСОНАЖА («char space»): начало — на земле между стопами,
-- +X — вправо от персонажа, +Y — вверх, -Z — вперёд (куда смотрит персонаж). Поза покоя: руки вниз,
-- ладони к бёдрам. Все кости в покое имеют нулевой поворот, поэтому оси Transform любого сустава
-- совпадают с осями персонажа в позе покоя.
--
-- Имена суставов как в R15: Root, Waist, Neck, Left/RightShoulder, Elbow, Wrist, Hip, Knee, Ankle.
-- KeyframeSequence хранит позы по имени Part1 (LowerTorso, UpperTorso, Head, RightUpperArm, ...).

local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local Rig = {}
Rig.__index = Rig

-- Мотор (имя сустава) -> {родительская кость, дочерняя кость}
Rig.MOTORS = {
	Root = { "HumanoidRootPart", "LowerTorso" },
	Waist = { "LowerTorso", "UpperTorso" },
	Neck = { "UpperTorso", "Head" },
	RightShoulder = { "UpperTorso", "RightUpperArm" },
	RightElbow = { "RightUpperArm", "RightLowerArm" },
	RightWrist = { "RightLowerArm", "RightHand" },
	LeftShoulder = { "UpperTorso", "LeftUpperArm" },
	LeftElbow = { "LeftUpperArm", "LeftLowerArm" },
	LeftWrist = { "LeftLowerArm", "LeftHand" },
	RightHip = { "LowerTorso", "RightUpperLeg" },
	RightKnee = { "RightUpperLeg", "RightLowerLeg" },
	RightAnkle = { "RightLowerLeg", "RightFoot" },
	LeftHip = { "LowerTorso", "LeftUpperLeg" },
	LeftKnee = { "LeftUpperLeg", "LeftLowerLeg" },
	LeftAnkle = { "LeftLowerLeg", "LeftFoot" },
}

Rig.FINGERS = { "Index", "Middle", "Ring", "Pinky", "Thumb" }

-- Пропорции по умолчанию (≈ R15 «блочный» аватар, рост ~5.2 студа).
Rig.DEFAULT = {
	hipX = 0.5, -- половина расстояния между тазобедренными суставами
	hipY = 2.1, -- высота тазобедренного сустава
	kneeY = 1.05,
	ankleY = 0.2,
	footLen = 1.0, -- длина стопы (от пятки до носка)
	footFwd = 0.65, -- насколько носок впереди лодыжки
	footW = 0.9,
	pelvisY = 2.35, -- центр HumanoidRootPart и опора Root
	waistY = 2.55,
	neckY = 4.0,
	shoulderX = 1.5,
	shoulderY = 3.85,
	upperArm = 1.05,
	lowerArm = 1.0,
	handLen = 0.35,
	handW = 0.9, -- ширина кисти вперёд-назад (ось Z)
	torsoW = 2.0,
	torsoD = 1.0,
	headH = 1.2,
	fingers = false,
	fingerLen1 = 0.22,
	fingerLen2 = 0.2,
	thumbLen1 = 0.2,
	thumbLen2 = 0.18,
}

local function v(x, y, z)
	return Vector3.new(x, y, z)
end

local function material(m)
	if type(m) == "string" then
		return Enum.Material[m]
	end
	return m or Enum.Material.SmoothPlastic
end

local function newPart(name, size, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

function Rig.new(name: string, prop: { [string]: any }?)
	local self = setmetatable({}, Rig)
	local P = table.clone(Rig.DEFAULT)
	for k, val in prop or {} do
		P[k] = val
	end
	self.name = name
	self.P = P
	self.model = Instance.new("Model")
	self.model.Name = name
	self.bones = {} -- имя -> Part
	self.rest = {} -- имя -> CFrame в char space
	self.motors = {} -- имя Part1 -> Motor6D
	self.motorParent = {} -- имя Part1 -> имя Part0
	self.pivots = {} -- имя Part1 -> Vector3 (опора сустава в char space)
	self.face = {} -- конфигурация лицевых каналов (см. Pose.luau)
	self.lengths = {}
	self.visuals = {}
	self.count = 0

	local bonesFolder = self.model
	local hrp = newPart("HumanoidRootPart", v(2, 2, 1), CFrame.new(0, P.pelvisY, 0))
	hrp.Anchored = true
	hrp.Transparency = 1
	hrp.CanQuery = false
	hrp.Parent = bonesFolder
	self.bones.HumanoidRootPart = hrp
	self.rest.HumanoidRootPart = hrp.CFrame
	self.model.PrimaryPart = hrp

	local function bone(boneName, parentName, motorName, pivot, center, size)
		local cf = CFrame.new(center)
		local p = newPart(boneName, size, cf)
		p.Transparency = 1
		p.Parent = bonesFolder
		self.bones[boneName] = p
		self.rest[boneName] = cf
		local parent = self.bones[parentName]
		local m = Instance.new("Motor6D")
		m.Name = motorName
		m.Part0 = parent
		m.Part1 = p
		m.C0 = self.rest[parentName]:Inverse() * CFrame.new(pivot)
		m.C1 = cf:Inverse() * CFrame.new(pivot)
		m.Parent = p
		self.motors[boneName] = m
		self.motorParent[boneName] = parentName
		self.pivots[boneName] = pivot
		return p
	end
	self._bone = bone

	local legLen1 = P.hipY - P.kneeY
	local legLen2 = P.kneeY - P.ankleY
	bone("LowerTorso", "HumanoidRootPart", "Root", v(0, P.pelvisY, 0), v(0, (P.hipY + P.waistY) / 2, 0), v(P.torsoW, math.max(P.waistY - P.hipY, 0.2) + 0.2, P.torsoD))
	bone("UpperTorso", "LowerTorso", "Waist", v(0, P.waistY, 0), v(0, (P.waistY + P.neckY) / 2, 0), v(P.torsoW, P.neckY - P.waistY, P.torsoD))
	bone("Head", "UpperTorso", "Neck", v(0, P.neckY, 0), v(0, P.neckY + P.headH / 2, 0), v(P.headH, P.headH, P.headH))
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local sx = s * P.shoulderX
		local elbowY = P.shoulderY - P.upperArm
		local wristY = elbowY - P.lowerArm
		bone(side .. "UpperArm", "UpperTorso", side .. "Shoulder", v(sx, P.shoulderY, 0), v(sx, P.shoulderY - P.upperArm / 2, 0), v(0.5, P.upperArm, 0.5))
		bone(side .. "LowerArm", side .. "UpperArm", side .. "Elbow", v(sx, elbowY, 0), v(sx, elbowY - P.lowerArm / 2, 0), v(0.45, P.lowerArm, 0.45))
		bone(side .. "Hand", side .. "LowerArm", side .. "Wrist", v(sx, wristY, 0), v(sx, wristY - P.handLen / 2, 0), v(0.3, P.handLen, P.handW))
		local hx = s * P.hipX
		bone(side .. "UpperLeg", "LowerTorso", side .. "Hip", v(hx, P.hipY, 0), v(hx, P.hipY - legLen1 / 2, 0), v(0.6, legLen1, 0.6))
		bone(side .. "LowerLeg", side .. "UpperLeg", side .. "Knee", v(hx, P.kneeY, 0), v(hx, P.kneeY - legLen2 / 2, 0), v(0.5, legLen2, 0.5))
		bone(side .. "Foot", side .. "LowerLeg", side .. "Ankle", v(hx, P.ankleY, 0), v(hx, P.ankleY / 2, -(P.footFwd - (P.footLen - P.footFwd)) / 2), v(P.footW * 0.6, math.max(P.ankleY, 0.2), P.footLen))

		if P.fingers then
			-- Пальцы: основания на нижнем крае ладони, указательный спереди (-Z), мизинец сзади.
			local baseY = wristY - P.handLen
			local zs = { Index = -0.36, Middle = -0.12, Ring = 0.12, Pinky = 0.34 }
			for _, f in { "Index", "Middle", "Ring", "Pinky" } do
				local z = zs[f] * P.handW
				local len1 = P.fingerLen1 * (if f == "Pinky" then 0.8 elseif f == "Middle" then 1.08 else 1)
				local len2 = P.fingerLen2 * (if f == "Pinky" then 0.8 elseif f == "Middle" then 1.08 else 1)
				bone(side .. f .. "1", side .. "Hand", side .. f .. "1", v(sx, baseY, z), v(sx, baseY - len1 / 2, z), v(0.14, len1, 0.14))
				bone(side .. f .. "2", side .. f .. "1", side .. f .. "2", v(sx, baseY - len1, z), v(sx, baseY - len1 - len2 / 2, z), v(0.13, len2, 0.13))
			end
			-- Большой палец: от передней части ладони вниз-вперёд (ось вдоль -Y, отклонение задаёт поза).
			local tz = -0.5 * P.handW
			local ty = wristY - P.handLen * 0.35
			bone(side .. "Thumb1", side .. "Hand", side .. "Thumb1", v(sx, ty, tz), v(sx, ty - P.thumbLen1 / 2, tz), v(0.15, P.thumbLen1, 0.15))
			bone(side .. "Thumb2", side .. "Thumb1", side .. "Thumb2", v(sx, ty - P.thumbLen1, tz), v(sx, ty - P.thumbLen1 - P.thumbLen2 / 2, tz), v(0.14, P.thumbLen2, 0.14))
		end
	end

	-- Длины сегментов для IK.
	self.lengths.upperArm = P.upperArm
	self.lengths.lowerArm = P.lowerArm
	self.lengths.upperLeg = legLen1
	self.lengths.lowerLeg = legLen2

	local ctrl = Instance.new("AnimationController")
	ctrl.Name = "AnimationController"
	ctrl.Parent = self.model
	local animator = Instance.new("Animator")
	animator.Parent = ctrl
	return self
end

-- Дополнительный сустав (челюсть, брови, уши, очки, предмет в руке...).
-- pivot — опора сустава, center — центр кости (по умолчанию = pivot), всё в char space.
function Rig:joint(name: string, parentBone: string, pivot, center, size)
	assert(self.bones[parentBone], "unknown parent bone " .. parentBone)
	assert(not self.bones[name], "bone exists " .. name)
	return self._bone(name, parentBone, name, pivot, center or pivot, size or v(0.2, 0.2, 0.2))
end

-- Видимая деталь, приваренная к кости. spec:
--   shape = "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge" (по умолчанию Block)
--   mesh  = "Sphere" | "Head" | "Cylinder" | "Brick" | "Wedge" | nil  (SpecialMesh, заполняет Size детали)
--   cf    = CFrame в char space  (или pos = Vector3 + rot = Vector3 градусы XYZ)
--   size, color (Color3), material (строка/Enum), transparency, reflectance, castShadow, name
function Rig:part(boneName: string, spec)
	local bone = self.bones[boneName]
	assert(bone, "unknown bone " .. tostring(boneName))
	local cf = spec.cf
	if not cf then
		local r = spec.rot or v(0, 0, 0)
		cf = CFrame.new(spec.pos) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	end
	self.count += 1
	local p = newPart(spec.name or ("P" .. self.count), spec.size, cf)
	if spec.shape then
		p.Shape = Enum.PartType[spec.shape]
		p.Size = spec.size -- после смены формы размер мог быть изменён
	end
	p.Color = spec.color or Color3.new(0.6, 0.6, 0.6)
	p.Material = material(spec.material)
	p.Transparency = spec.transparency or 0
	p.Reflectance = spec.reflectance or 0
	p.CastShadow = if spec.castShadow == nil then true else spec.castShadow
	if spec.mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType[spec.mesh]
		if spec.meshScale then
			m.Scale = spec.meshScale
		end
		m.Parent = p
	end
	local w = Instance.new("Weld")
	w.Name = "W"
	w.Part0 = bone
	w.Part1 = p
	w.C0 = self.rest[boneName]:Inverse() * cf
	w.C1 = CFrame.new()
	w.Parent = p
	p.Parent = spec.parent or self:_visualFolder(boneName)
	table.insert(self.visuals, p)
	return p
end

function Rig:_visualFolder(boneName: string)
	local folder = self.model:FindFirstChild("Geometry")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Geometry"
		folder.Parent = self.model
	end
	local sub = folder:FindFirstChild(boneName)
	if not sub then
		sub = Instance.new("Folder")
		sub.Name = boneName
		sub.Parent = folder
	end
	return sub
end

-- Удобные обёртки. rot — градусы (XYZ).
function Rig:ellipsoid(bone, pos, size, color, mat, rot, extra)
	local spec = { pos = pos, size = size, color = color, material = mat, rot = rot, mesh = "Sphere" }
	for k, val in extra or {} do
		spec[k] = val
	end
	return self:part(bone, spec)
end

function Rig:box(bone, pos, size, color, mat, rot, extra)
	local spec = { pos = pos, size = size, color = color, material = mat, rot = rot }
	for k, val in extra or {} do
		spec[k] = val
	end
	return self:part(bone, spec)
end

function Rig:ball(bone, pos, diameter, color, mat, extra)
	local spec = { pos = pos, size = v(diameter, diameter, diameter), color = color, material = mat, shape = "Ball" }
	for k, val in extra or {} do
		spec[k] = val
	end
	return self:part(bone, spec)
end

-- Цилиндр вдоль оси axis ("X" | "Y" | "Z"), длина len, диаметр d (или Vector2 для эллиптического сечения через mesh).
function Rig:cyl(bone, pos, len, d, color, mat, axis, rot, extra)
	axis = axis or "Y"
	local base = CFrame.new()
	if axis == "Y" then
		base = CFrame.Angles(0, 0, math.pi / 2)
	elseif axis == "Z" then
		base = CFrame.Angles(0, math.pi / 2, 0)
	end
	local r = rot or v(0, 0, 0)
	local cf = CFrame.new(pos) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z)) * base
	local spec = { cf = cf, size = v(len, d, d), color = color, material = mat, shape = "Cylinder" }
	for k, val in extra or {} do
		spec[k] = val
	end
	return self:part(bone, spec)
end

-- Положение кости покоя (char space) и опора сустава.
function Rig:restOf(boneName: string)
	return self.rest[boneName]
end

function Rig:pivotOf(boneName: string)
	return self.pivots[boneName]
end

-- Поставить модель в мир: place — точка на земле + поворот (см. Config.place).
function Rig:finish(place)
	for _, d in self.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = place * d.CFrame
		end
	end
	self.model:SetAttribute("PartCount", #self.visuals)
	return self.model
end

return Rig
