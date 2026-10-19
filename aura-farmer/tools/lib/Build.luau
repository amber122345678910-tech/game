--!nocheck
-- Помощники для построения декораций (Lune). Все координаты — ЛОКАЛЬНЫЕ координаты декорации
-- (относительно Config.Sets[имя]); помощники сами переводят их в мир.
--
--   local B = Build.new("Beach", parentModel)
--   B:part{ name="Pier", pos=Vector3.new(0,5,-200), size=Vector3.new(10,1,200), color=..., material="WoodPlanks", rot=Vector3.new(0,15,0) }
--   B:terrain("Block", Vector3.new(0,-10,0), Vector3.new(800,20,600), "Sand")   -- объём будущего Terrain
--   B:light(part, "SpotLight", { Brightness=8, Range=40, Angle=45, Face="Bottom", Shadows=true, Color=... })

local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local Loader = require("./loader")
local Config = Loader.load("src/shared/Config")

local Build = {}
Build.__index = Build

function Build.new(setName: string, parent)
	local self = setmetatable({}, Build)
	self.set = setName
	self.origin = Config.Sets[setName]
	assert(self.origin, "unknown set " .. setName)
	self.model = parent
	self.count = 0
	return self
end

-- Локальный CFrame -> мировой. rot — градусы (порядок XYZ как CFrame.Angles).
function Build:cf(pos, rot)
	local r = rot or Vector3.zero
	return self.origin * CFrame.new(pos) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

function Build:world(pos)
	return (self.origin * CFrame.new(pos)).Position
end

local function mat(m)
	if type(m) == "string" then
		return Enum.Material[m]
	end
	return m or Enum.Material.SmoothPlastic
end

function Build:folder(name, parent)
	local f = Instance.new("Model")
	f.Name = name
	f.Parent = parent or self.model
	return f
end

-- spec: name, pos (+rot) или cf (ЛОКАЛЬНЫЙ CFrame), size, color, material, shape ("Block"|"Ball"|"Cylinder"|"Wedge"|"CornerWedge"),
--       mesh ("Sphere"|"Cylinder"|"Head"|"Brick"|"Wedge"), meshScale, transparency, reflectance,
--       castShadow (true), canCollide (false), parent
function Build:part(spec)
	self.count += 1
	local p = Instance.new("Part")
	p.Name = spec.name or ("Part" .. self.count)
	if spec.shape then
		p.Shape = Enum.PartType[spec.shape]
	end
	p.Size = spec.size or Vector3.new(1, 1, 1)
	if spec.cf then
		p.CFrame = self.origin * spec.cf
	else
		p.CFrame = self:cf(spec.pos or Vector3.zero, spec.rot)
	end
	p.Color = spec.color or Color3.new(0.7, 0.7, 0.7)
	p.Material = mat(spec.material)
	p.Transparency = spec.transparency or 0
	p.Reflectance = spec.reflectance or 0
	p.Anchored = true
	p.CanCollide = spec.canCollide or false
	p.CanTouch = false
	p.CanQuery = if spec.canQuery == nil then true else spec.canQuery
	p.CastShadow = if spec.castShadow == nil then true else spec.castShadow
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if spec.mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType[spec.mesh]
		if spec.meshScale then
			m.Scale = spec.meshScale
		end
		m.Parent = p
	end
	p.Parent = spec.parent or self.model
	return p
end

function Build:ellipsoid(pos, size, color, material, rot, extra)
	local spec = { pos = pos, size = size, color = color, material = material, rot = rot, mesh = "Sphere" }
	for k, v in extra or {} do
		spec[k] = v
	end
	return self:part(spec)
end

function Build:box(pos, size, color, material, rot, extra)
	local spec = { pos = pos, size = size, color = color, material = material, rot = rot }
	for k, v in extra or {} do
		spec[k] = v
	end
	return self:part(spec)
end

-- Цилиндр вдоль оси axis ("X" | "Y" | "Z") длиной len и диаметром d.
function Build:cyl(pos, len, d, color, material, axis, rot, extra)
	axis = axis or "Y"
	local base = CFrame.new()
	if axis == "Y" then
		base = CFrame.Angles(0, 0, math.pi / 2)
	elseif axis == "Z" then
		base = CFrame.Angles(0, math.pi / 2, 0)
	end
	local r = rot or Vector3.zero
	local cf = CFrame.new(pos) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z)) * base
	local spec = { cf = cf, size = Vector3.new(len, d, d), color = color, material = material, shape = "Cylinder" }
	for k, v in extra or {} do
		spec[k] = v
	end
	return self:part(spec)
end

function Build:ball(pos, d, color, material, extra)
	local spec = { pos = pos, size = Vector3.new(d, d, d), color = color, material = material, shape = "Ball" }
	for k, v in extra or {} do
		spec[k] = v
	end
	return self:part(spec)
end

-- Объём Terrain (строится сервером при запуске). shape: "Block" | "Ball" | "Cylinder" | "Wedge".
-- Для Ball размер = Vector3(d,d,d). Для Cylinder ось — Y (высота = size.Y, диаметр = size.X).
function Build:terrain(shape, pos, size, materialName, rot)
	local folder = self.model:FindFirstChild("TerrainVolumes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TerrainVolumes"
		folder.Parent = self.model
	end
	self.count += 1
	local p = Instance.new("Part")
	p.Name = materialName .. "_" .. shape
	p.Size = size
	p.CFrame = self:cf(pos, rot)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 1
	p.Locked = true
	p.Color = Color3.fromRGB(255, 0, 255)
	p:SetAttribute("TerrainShape", shape)
	p:SetAttribute("TerrainMaterial", materialName)
	p:SetAttribute("Order", self.count)
	p.Parent = folder
	return p
end

-- Источник света внутри детали. kind: "SpotLight" | "PointLight" | "SurfaceLight".
function Build:light(part, kind, props)
	local l = Instance.new(kind)
	for k, v in props or {} do
		if k == "Face" then
			l.Face = Enum.NormalId[v]
		else
			l[k] = v
		end
	end
	l.Parent = part
	return l
end

-- Текст на грани детали (SurfaceGui + TextLabel). face: "Front" | "Back" | "Left" | "Right" | "Top" | "Bottom".
function Build:text(part, face, text, props)
	props = props or {}
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId[face]
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = props.pixelsPerStud or 50
	g.LightInfluence = props.lightInfluence or 1
	g.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = roblox.UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = props.color or Color3.new(1, 1, 1)
	t.FontFace = props.font or roblox.Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	t.Parent = g
	return g, t
end

return Build
