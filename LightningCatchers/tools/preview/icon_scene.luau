--!nocheck
-- Сцена для иконки и обложки игры: ловец с наэлектризованными волосами поднимает громоотвод,
-- в него бьёт молния, вокруг питомцы-искрята и фульгуриты, под ногами светящееся кольцо.
-- Запуск из LightningCatchers/: .tools/lune run tools/preview/icon_scene.luau OUT.rbxmx
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("../lib/loader")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local M = Enum.Material

local Models = Loader.load("src/shared/Models")
local Fulgurite = Loader.load("src/shared/Fulgurite")
local BoltGeometry = Loader.load("src/shared/BoltGeometry")
local Geom = Loader.load("src/shared/Geom")
local Prng = Loader.load("src/shared/Prng")

local out = process.args[1] or "icon_scene.rbxmx"
local root = Instance.new("Model")
root.Name = "IconScene"

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function part(cf, size, color, material, shape, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CFrame = cf
	p.Size = size
	p.Color = color
	p.Material = material or M.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Transparency = transparency or 0
	p.Parent = root
	return p
end

local function wedge(cf, size, color, material)
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.CFrame = cf
	p.Size = size
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Parent = root
	return p
end

local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
end

-- поставить модель из Models (в Lune нет PivotTo)
local function place(inst, cf)
	inst.Parent = root
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = cf * d.CFrame
			d.Anchored = true
		end
	end
	return inst
end

local function cyl(a, b, d, color, material, transparency)
	local cf, len = Geom.axisCFrame(a, b)
	return part(cf, Vector3.new(len, d, d), color, material, Enum.PartType.Cylinder, transparency)
end

----------------------------------------------------------------------
-- Остров под ногами
----------------------------------------------------------------------
local GRASS = rgb(84, 170, 78)
part(CFrame.new(0, -1, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(2, 46, 46), GRASS, M.Grass, Enum.PartType.Cylinder)
part(CFrame.new(0, -2.6, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(1.4, 47, 47), rgb(110, 78, 52), M.Ground, Enum.PartType.Cylinder)
-- скалистое дно (перевёрнутый конус из слоёв)
for i = 1, 7 do
	local r = 44 - i * 5.6
	part(CFrame.new(0, -3.2 - i * 2.4, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(2.6, r, r), rgb(98 - i * 4, 96 - i * 4, 110 - i * 3), M.Slate, Enum.PartType.Cylinder)
end
-- трава и цветы
local rng = Prng.new(5)
for _ = 1, 70 do
	local a = rng:range(0, math.pi * 2)
	local d = rng:range(9, 21)
	local x, z = math.cos(a) * d, math.sin(a) * d
	local h = rng:range(0.5, 1.2)
	wedge(CFrame.new(x, h / 2, z) * CFrame.Angles(0, rng:range(0, 6), rng:range(-0.3, 0.3)), Vector3.new(0.15, h, 0.4), rgb(100, 190, 90), M.Grass)
end
for _ = 1, 24 do
	local a = rng:range(0, math.pi * 2)
	local d = rng:range(10, 20)
	local c = ({ rgb(255, 120, 170), rgb(255, 255, 255), rgb(180, 130, 255), rgb(255, 220, 90) })[rng:int(1, 4)]
	part(CFrame.new(math.cos(a) * d, 0.7, math.sin(a) * d), Vector3.new(0.5, 0.5, 0.5), c, M.SmoothPlastic, Enum.PartType.Ball)
end

----------------------------------------------------------------------
-- Кольцо под ногами
----------------------------------------------------------------------
local RING = rgb(110, 210, 255)
part(CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.05, 13.6, 13.6), rgb(40, 90, 170), M.SmoothPlastic, Enum.PartType.Cylinder, 0.5)
local segs = 36
for i = 1, segs do
	local a1, a2 = (i - 1) / segs * math.pi * 2, i / segs * math.pi * 2
	local r = 7
	cyl(Vector3.new(math.cos(a1) * r, 0.12, math.sin(a1) * r), Vector3.new(math.cos(a2) * r, 0.12, math.sin(a2) * r), 0.22, RING, M.Neon)
	local r2 = 9.5
	if i % 2 == 0 then
		cyl(Vector3.new(math.cos(a1) * r2, 0.1, math.sin(a1) * r2), Vector3.new(math.cos(a2) * r2, 0.1, math.sin(a2) * r2), 0.12, RING, M.Neon)
	end
end

----------------------------------------------------------------------
-- Ловец (блочный персонаж, смотрит на камеру = в сторону -Z)
----------------------------------------------------------------------
local SKIN = rgb(255, 212, 168)
local HOODIE = rgb(30, 130, 255)
local PANTS = rgb(40, 46, 80)
local SHOE = rgb(245, 245, 250)
local HAIR = rgb(255, 214, 60)

local body = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(12), 0)
-- ноги (лёгкая стойка)
part(body * CFrame.new(-0.55, 1, 0) * CFrame.Angles(0, 0, math.rad(-6)), Vector3.new(1, 2, 1), PANTS)
part(body * CFrame.new(0.55, 1, 0) * CFrame.Angles(0, 0, math.rad(6)), Vector3.new(1, 2, 1), PANTS)
part(body * CFrame.new(-0.62, 0.2, -0.15), Vector3.new(1.05, 0.4, 1.3), SHOE)
part(body * CFrame.new(0.62, 0.2, -0.15), Vector3.new(1.05, 0.4, 1.3), SHOE)
-- туловище и молния на груди
local torso = part(body * CFrame.new(0, 3, 0), Vector3.new(2, 2, 1), HOODIE)
local _ = torso
wedge(body * CFrame.new(0.15, 3.3, -0.52) * CFrame.Angles(0, 0, math.rad(-30)), Vector3.new(0.05, 0.9, 0.5), rgb(255, 230, 80), M.Neon)
wedge(body * CFrame.new(-0.1, 2.75, -0.52) * CFrame.Angles(0, 0, math.rad(150)), Vector3.new(0.05, 0.9, 0.5), rgb(255, 230, 80), M.Neon)
-- левая рука в сторону
part(body * CFrame.new(-1.75, 3.1, 0) * CFrame.Angles(0, 0, math.rad(-35)), Vector3.new(1, 2, 1), HOODIE)
part(body * CFrame.new(-2.35, 2.2, 0), Vector3.new(0.9, 0.7, 0.9), SKIN)
-- правая рука вверх (держит громоотвод)
local shoulder = body * CFrame.new(1.5, 3.8, 0)
part(shoulder * CFrame.new(0, 1, 0), Vector3.new(1, 2, 1), HOODIE)
local hand = shoulder * CFrame.new(0, 2.35, 0)
part(hand, Vector3.new(0.9, 0.7, 0.9), SKIN)
-- голова (чуть крупнее — милее) и лицо
local head = body * CFrame.new(0, 4.85, 0)
part(head, Vector3.new(1.7, 1.6, 1.6), SKIN)
for _, x in { -0.38, 0.38 } do
	part(head * CFrame.new(x, 0.12, -0.8), Vector3.new(0.34, 0.42, 0.1), rgb(20, 20, 30))
	part(head * CFrame.new(x + 0.06, 0.24, -0.86), Vector3.new(0.1, 0.12, 0.05), rgb(255, 255, 255))
end
-- открытый от восторга рот
part(head * CFrame.new(0, -0.38, -0.8), Vector3.new(0.5, 0.32, 0.1), rgb(120, 30, 40))
part(head * CFrame.new(0, -0.3, -0.83), Vector3.new(0.4, 0.08, 0.05), rgb(255, 255, 255))
-- румянец
part(head * CFrame.new(-0.62, -0.18, -0.81), Vector3.new(0.3, 0.16, 0.05), rgb(255, 150, 150))
part(head * CFrame.new(0.62, -0.18, -0.81), Vector3.new(0.3, 0.16, 0.05), rgb(255, 150, 150))
-- волосы дыбом (наэлектризованы)
local spikes = {
	{ 0, 1.25, 0, 0, 0, 0.0, 1.3 },
	{ -0.55, 1.1, 0.1, 0, 0, 0.45, 1.1 },
	{ 0.55, 1.1, 0.1, 0, 0, -0.45, 1.1 },
	{ -0.85, 0.75, 0.2, 0, 0, 0.95, 0.9 },
	{ 0.85, 0.75, 0.2, 0, 0, -0.95, 0.9 },
	{ 0, 1.0, 0.55, 0.5, 0, 0, 1.0 },
	{ -0.4, 1.05, -0.45, -0.45, 0, 0.3, 0.8 },
	{ 0.4, 1.05, -0.45, -0.45, 0, -0.3, 0.8 },
}
for _, s in spikes do
	local cf = head * CFrame.new(s[1], s[2], s[3]) * CFrame.Angles(s[4], s[5], s[6])
	wedge(cf * CFrame.new(0, 0, -0.18), Vector3.new(0.5, s[7], 0.36), HAIR)
	wedge(cf * CFrame.new(0, 0, 0.18) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.5, s[7], 0.36), HAIR)
end
part(head * CFrame.new(0, 0.82, 0.05), Vector3.new(1.75, 0.35, 1.65), HAIR)
-- искры у волос
for i = 1, 7 do
	local a = i / 7 * math.pi * 2
	part(head * CFrame.new(math.cos(a) * 1.4, 1.2 + math.sin(a * 2) * 0.3, math.sin(a) * 0.6), Vector3.new(0.18, 0.18, 0.18), rgb(255, 255, 200), M.Neon, Enum.PartType.Ball)
end

local faceLight = part(body * CFrame.new(0, 5, -4), Vector3.new(0.2, 0.2, 0.2), rgb(0, 0, 0), M.SmoothPlastic, nil, 1)
light(faceLight, rgb(200, 225, 255), 12, 2.5)

-- громоотвод в поднятой руке
local rod = Models.rod(3)
place(rod, hand * CFrame.new(0, -0.3, 0))
local tipPos
for _, d in rod:GetDescendants() do
	if d:IsA("BasePart") and d.Name == "Tip" then
		tipPos = d.CFrame.Position
	end
end
tipPos = tipPos or (hand * CFrame.new(0, 4.5, 0)).Position

-- банка за спиной, ярко светится
local jar = Models.jar()
place(jar, body * CFrame.new(0, 3.1, 1.05) * CFrame.Angles(0, math.pi, 0))
for _, d in jar:GetDescendants() do
	if d:IsA("BasePart") and d.Name == "Core" then
		d.Color = rgb(170, 235, 255)
		light(d, rgb(120, 210, 255), 14, 3)
	end
end

----------------------------------------------------------------------
-- Молния в громоотвод
----------------------------------------------------------------------
local from = Vector3.new(-9, 70, 14)
local boltSegs = BoltGeometry.build(4242, from, tipPos, 5)
for _, s in boltSegs do
	local w = s.Width * (if s.Branch then 1.1 else 1.8)
	cyl(s.A, s.B, w * 0.42, rgb(240, 248, 255), M.Neon)
	cyl(s.A, s.B, w * 1.25, rgb(90, 150, 255), M.Neon, 0.78)
end
-- фоновая молния (для драмы на иконке)
for _, s2 in BoltGeometry.build(777, Vector3.new(16, 46, 12), Vector3.new(10.5, 0.2, 9), 4) do
	local w = s2.Width * 1.3
	cyl(s2.A, s2.B, w * 0.4, rgb(235, 220, 255), M.Neon)
	cyl(s2.A, s2.B, w * 1.2, rgb(170, 110, 255), M.Neon, 0.78)
end
local glow = part(CFrame.new(tipPos), Vector3.new(1.0, 1.0, 1.0), rgb(255, 255, 255), M.Neon, Enum.PartType.Ball)
light(glow, rgb(170, 210, 255), 40, 6)
part(CFrame.new(tipPos), Vector3.new(2.4, 2.4, 2.4), rgb(140, 200, 255), M.Neon, Enum.PartType.Ball, 0.88)
-- мелкие разряды вокруг кончика
local r2 = Prng.new(77)
for i = 1, 6 do
	local a = i / 6 * math.pi * 2
	local p1 = tipPos
	local p2 = tipPos + Vector3.new(math.cos(a) * 2.2, r2:range(-1.2, 1.2), math.sin(a) * 2.2)
	local mid = (p1 + p2) / 2 + Vector3.new(r2:range(-0.5, 0.5), r2:range(-0.5, 0.5), r2:range(-0.5, 0.5))
	cyl(p1, mid, 0.12, rgb(220, 240, 255), M.Neon)
	cyl(mid, p2, 0.1, rgb(220, 240, 255), M.Neon)
end

----------------------------------------------------------------------
-- Питомцы
----------------------------------------------------------------------
place(Models.pet("luchik"), CFrame.new(-4.4, 5.2, -1.5) * CFrame.Angles(0, math.rad(20), math.rad(-8)))
place(Models.pet("iskorka"), CFrame.new(4.6, 3.4, -2.2) * CFrame.Angles(0, math.rad(-25), 0))
place(Models.pet("zarnitsa"), CFrame.new(-2.8, 8.6, 2.2) * CFrame.Angles(0, math.rad(10), 0))

----------------------------------------------------------------------
-- Фульгуриты по краям
----------------------------------------------------------------------
local fspots = {
	{ CFrame.new(-8.5, 0, -4) * CFrame.Angles(0, 0.4, 0), 31, "gold", "golden" },
	{ CFrame.new(8.5, 0, -3) * CFrame.Angles(0, -0.6, 0), 11, "purple", nil },
	{ CFrame.new(11, 0, 6) * CFrame.Angles(0, 0.2, 0), 57, "rainbow", "rainbow" },
	{ CFrame.new(-12, 0, 5), 23, "green", nil },
}
for _, f in fspots do
	local spec = Fulgurite.generate(f[2], f[3], f[4])
	place(Models.fulgurite(spec, Fulgurite.glassColor(f[3], f[4])), f[1])
end

----------------------------------------------------------------------
-- Тучи и дальние острова
----------------------------------------------------------------------
local cr = Prng.new(11)
for _ = 1, 46 do
	local x, z = cr:range(-60, 60), cr:range(-10, 70)
	local s = cr:range(14, 26)
	part(CFrame.new(x, cr:range(34, 48), z), Vector3.new(s, s, s), rgb(44, 48, 82), M.SmoothPlastic, Enum.PartType.Ball)
end
for i = 1, 3 do
	local c = Vector3.new(({ -55, 50, 15 })[i], ({ -6, 2, -14 })[i], ({ 70, 80, 110 })[i])
	local r = ({ 26, 22, 30 })[i]
	part(CFrame.new(c) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(2, r, r), ({ rgb(176, 124, 70), rgb(232, 204, 146), rgb(236, 242, 255) })[i], M.Grass, Enum.PartType.Cylinder)
	for k = 1, 4 do
		local rr = r - k * 5
		part(CFrame.new(c + Vector3.new(0, -1.5 - k * 2.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(2.4, rr, rr), rgb(80, 78, 96), M.Slate, Enum.PartType.Cylinder)
	end
end

fs.writeFile(out, roblox.serializeModel({ root }, true))
print("scene written: " .. out)
