--!nocheck
-- Контактный лист моделей из src/shared/Models.luau (docs/STYLE.md §12, п. 2–3):
-- пять архетипов питомцев анфас, в 3/4 и сзади, все питомцы, знаки редкости, силуэты (тест 64 px),
-- питомцы в игровом масштабе рядом с болванкой игрока, коконы, банка, подстанция, 6 громоотводов,
-- фульгуриты, тучка удара и осколки (рецепты StrikeController), шаровая молния (EventFX).
-- Запуск из LightningCatchers/: .tools/lune run tools/preview/models_sheet.luau OUT.rbxmx [папка shared]
-- Потом: cd tools/preview && ../../.tools/lune run dump_scene.luau OUT.json OUT.rbxmx
--        && node render.mjs OUT.json PREFIX OUT_cams.json 1280 720
-- Камеры пишутся в OUT_cams.json рядом с .rbxmx. Печатает число деталей, шаров и неона у каждой модели.
-- Второй аргумент — другая папка shared (например, копия «до» для сравнения): тогда недостающие
-- рецепты рисуются по-старому (тучка из шаров, осколок из брусков и шара, шаровая молния из сфер).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Loader = require("../lib/loader")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local SHARED = process.args[2] or "src/shared"
local Models = Loader.load(SHARED .. "/Models")
local Pets = Loader.load(SHARED .. "/Pets")
local Fulgurite = Loader.load(SHARED .. "/Fulgurite")

local out = process.args[1] or "models_sheet.rbxmx"
local root = Instance.new("Model")
root.Name = "Sheet"

-- Весь лист развёрнут на 180°: солнце рендера (ClockTime 14) светит модели спереди-сбоку,
-- а не в спину. Координаты ниже — «как будто перёд моделей смотрит на камеру из −Z».
local G = CFrame.Angles(0, math.pi, 0)

local function count(inst)
	local n, balls, neon = 0, 0, 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			n += 1
			if d:IsA("Part") and d.Shape == Enum.PartType.Ball then
				balls += 1
			end
			if d.Material == Enum.Material.Neon then
				neon += 1
			end
		end
	end
	return n, balls, neon
end

-- Переставить модель (в Lune нет PivotTo): сдвигаем все детали
local function place(inst, cf)
	inst.Parent = root
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = G * cf * d.CFrame
			d.Anchored = true
		end
	end
	return inst
end

local function block(name, cf, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = G * cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Parent = root
	return p
end

local cams = {}
local function cam(name, pos, look, fov, clock)
	local p = G * Vector3.new(pos[1], pos[2], pos[3])
	local l = G * Vector3.new(look[1], look[2], look[3])
	table.insert(cams, { name = name, pos = { p.X, p.Y, p.Z }, look = { l.X, l.Y, l.Z }, fov = fov or 50, clockTime = clock or 14 })
end
local report = {}

-- пол-подложка
block("Floor", CFrame.new(-40, -0.5, 10), Vector3.new(380, 1, 60), Color3.fromRGB(70, 74, 92))

-- A. Пять архетипов (по одному на форму), x ≈ 0
local heroes = { "iskorka", "tuchka", "luchik", "kapelka", "iney" }
for i, kind in heroes do
	place(Models.pet(kind), CFrame.new((i - 3) * 3.3, 1.6, 0) * CFrame.Angles(0, math.rad(8), 0))
end
cam("archetypes", { 0, 2.6, -11.5 }, { 0, 1.6, 0 }, 48)
cam("archetypes34", { -7, 4.4, -7.5 }, { -0.5, 1.5, 0 }, 44)
cam("archetypesback", { 1.5, 3.4, 9.5 }, { 0, 1.5, 0 }, 44)
-- игровой масштаб: камера в 12 стадах, как за спиной игрока (FOV 70)
cam("archetypes12", { 0, 5.5, -12 }, { 0, 1.6, 0 }, 70)
-- крупные планы (как 3D-превью в окнах: вылупление, карточка питомца)
for i, kind in heroes do
	local x = (i - 3) * 3.3
	cam("close_" .. kind, { x - 1.6, 2.6, -5.2 }, { x, 1.75, 0 }, 30)
end

-- B. Все питомцы (по коконам и редкости), x ≈ 34
local kinds = {}
for _, cid in Pets.CocoonOrder do
	for _, e in Pets.Cocoons[cid].Pool do
		table.insert(kinds, e.kind)
	end
end
table.insert(kinds, 7, "gromik")
for i, kind in kinds do
	local col = (i - 1) % 7
	local row = (i - 1) // 7
	local m = Models.pet(kind)
	local n, balls, neon = count(m)
	table.insert(report, string.format("pet %-11s %-8s %-9s parts=%2d balls=%d neon=%d", kind, Pets.Kinds[kind].Shape, Pets.Kinds[kind].Rarity, n, balls, neon))
	place(m, CFrame.new(34 + (col - 3) * 3.4, 1.7, row * 4.4) * CFrame.Angles(0, math.rad(-10), 0))
end
cam("pets", { 34, 8.5, -12.5 }, { 34, 1.6, 4.4 }, 52)

-- C. Знаки редкости: обычный, редкий, эпический, легендарный ×2, мифический ×2, x ≈ 66
local marks = { "iskorka", "tuchka", "sharovik", "zarnitsa", "carmolniya", "perunchik", "polyarnik" }
for i, kind in marks do
	place(Models.pet(kind), CFrame.new(66 + (i - 4) * 3.2, 1.7, 0) * CFrame.Angles(0, math.rad(10), 0))
end
cam("rarity", { 66, 3.2, -10 }, { 66, 1.8, 0 }, 46)
for i, kind in marks do
	local x = 66 + (i - 4) * 3.2
	cam("mark_" .. kind, { x - 1.4, 2.7, -5.4 }, { x, 1.9, 0 }, 32)
end

-- D. Силуэты (тест 64 px): архетипы чёрным на светлой стене, x ≈ 96
block("SilWall", CFrame.new(96, 3, 3), Vector3.new(26, 8, 0.5), Color3.fromRGB(250, 250, 250))
for i, kind in heroes do
	local m = Models.pet(kind)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = Color3.fromRGB(10, 10, 14)
			d.Material = Enum.Material.SmoothPlastic
			d.Reflectance = 0
			if d.Transparency < 1 then
				d.Transparency = 0
			end
		end
	end
	place(m, CFrame.new(96 + (i - 3) * 3.6, 2, 0))
end
cam("silhouette", { 96, 2, -11.5 }, { 96, 2, 0 }, 48)

-- E. Игровой масштаб: болванка игрока (≈5 стадов), банка, громоотвод и питомцы на орбите; камера в 12 стадах, x ≈ 126
local P = Vector3.new(126, 0, 0)
local skin, shirt, pants = Color3.fromRGB(240, 200, 160), Color3.fromRGB(70, 120, 200), Color3.fromRGB(50, 54, 70)
block("Dummy", CFrame.new(P + Vector3.new(0, 3, 0)), Vector3.new(2, 2, 1), shirt)
block("Dummy", CFrame.new(P + Vector3.new(0, 4.6, 0)), Vector3.new(1.2, 1.2, 1.2), skin)
block("Dummy", CFrame.new(P + Vector3.new(-0.5, 1, 0)), Vector3.new(1, 2, 1), pants)
block("Dummy", CFrame.new(P + Vector3.new(0.5, 1, 0)), Vector3.new(1, 2, 1), pants)
block("Dummy", CFrame.new(P + Vector3.new(-1.5, 3, 0)), Vector3.new(1, 2, 1), skin)
block("Dummy", CFrame.new(P + Vector3.new(1.5, 3, 0)), Vector3.new(1, 2, 1), skin)
place(Models.jar(), CFrame.new(P + Vector3.new(0, 3, 0.95)) * CFrame.Angles(0, math.pi, 0))
place(Models.rod(2), CFrame.new(P + Vector3.new(1.5, 1.6, -0.5)) * CFrame.Angles(math.rad(-8), 0, math.rad(-6)))
local orbitPets = { { "iskorka", -3.6, 2.9, -1.6 }, { "luchik", 3.4, 3.4, -2.2 }, { "tuchka", -1.2, 3.1, -4.2 }, { "iney", 2.0, 2.6, 2.8 } }
for _, e in orbitPets do
	local pos = P + Vector3.new(e[2], e[3], e[4])
	place(Models.pet(e[1]), CFrame.new(pos) * CFrame.Angles(0, math.rad(e[2] * 6), 0))
end
cam("petsgame", { 126, 6.2, -12.5 }, { 126, 2.8, 0 }, 70)

-- F. Коконы, банка, подстанция, x ≈ −34
for i, id in Pets.CocoonOrder do
	local m = Models.cocoon(id)
	local n, balls, neon = count(m)
	table.insert(report, string.format("cocoon %-7s parts=%2d balls=%d neon=%d", id, n, balls, neon))
	place(m, CFrame.new(-34 + (i - 2) * 4.2 - 3, 0, 0) * CFrame.Angles(0, math.rad(-15), 0))
end
place(Models.jar(), CFrame.new(-29, 1.4, 0) * CFrame.Angles(0, math.rad(200), 0))
place(Models.station(), CFrame.new(-22, 0, 2) * CFrame.Angles(0, math.rad(180), 0))
cam("cocoons", { -32, 4.8, -10 }, { -32, 1.9, 0 }, 52)
cam("cocoonclose", { -36.5, 3.6, -7.5 }, { -35, 1.9, 0 }, 44)
cam("jar", { -27.6, 2.4, 4.6 }, { -29, 1.4, 0 }, 40)

-- G. Громоотводы, x ≈ −62
for t = 0, 5 do
	local tool = Models.rod(t)
	local n, balls, neon = count(tool)
	table.insert(report, string.format("rod %d parts=%2d balls=%d neon=%d", t, n, balls, neon))
	place(tool, CFrame.new(-62 + (t - 2.5) * 2.4, 1.3, 0) * CFrame.Angles(0, math.rad(20), 0))
end
cam("rods", { -62, 5.5, -13.5 }, { -62, 5.2, 0 }, 48)
cam("rodheads", { -62, 7.8, -7.5 }, { -62, 7.6, 0 }, 46)

-- H. Фульгуриты (разные seed, цвета, мутации), x ≈ −112
local list = {
	{ seed = 11, color = "blue" },
	{ seed = 27, color = "purple" },
	{ seed = 305, color = "green" },
	{ seed = 4242, color = "red" },
	{ seed = 999, color = "gold" },
	{ seed = 123456, color = "blue", mut = "golden" },
	{ seed = 77, color = "rainbow", mut = "rainbow" },
	{ seed = 31337, color = "black", mut = "perun" },
	{ seed = 2024, color = "purple", mut = "night" },
	{ seed = 5, color = "green" },
}
for i, f in list do
	local spec = Fulgurite.generate(f.seed, f.color, f.mut)
	local glass = Fulgurite.glassColor(f.color, f.mut)
	local m = Models.fulgurite(spec, glass)
	local n, balls, neon = count(m)
	place(m, CFrame.new(-112 + (i - 5.5) * 5.6, 0, 0))
	table.insert(report, string.format("fulg %2d: %-7s %-9s %-7s spec=%d model=%d balls=%d neon=%d h=%.1f", i, spec.ShapeName, spec.Rarity, f.color, #spec.Parts, n, balls, neon, spec.Height))
end
cam("fulg", { -112, 9, -24 }, { -112, 2.6, 0 }, 56)
cam("fulgclose", { -126, 5.2, -10.5 }, { -126, 2.8, 0 }, 46)

-- I. Тучка удара (вид снизу-сбоку, как с острова) и осколки на земле, x ≈ −170
local OLD = {
	cloud = {
		{ Name = "Cloud", Kind = "Ball", CFrame = CFrame.new(0, 0, 0), Size = Vector3.new(10, 10, 10), Tone = "core" },
		{ Name = "Cloud", Kind = "Ball", CFrame = CFrame.new(4.2, -0.9, 1.6), Size = Vector3.new(7.5, 7.5, 7.5), Tone = "core" },
		{ Name = "Cloud", Kind = "Ball", CFrame = CFrame.new(-3.8, -0.6, -1.9), Size = Vector3.new(8, 8, 8), Tone = "core" },
		{ Name = "CloudCore", Kind = "Ball", CFrame = CFrame.new(0, -1, 0), Size = Vector3.new(3, 3, 3), Tone = "glow" },
	},
	shard = {
		{ Name = "Shard", Kind = "Block", CFrame = CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0.3, 0.12), Size = Vector3.new(0.55, 1.7, 0.55), Tone = "glass" },
		{ Name = "Shard", Kind = "Block", CFrame = CFrame.new(0.38, 0.55, 0.12) * CFrame.Angles(0.25, 0.8, -0.55), Size = Vector3.new(0.45, 1.15, 0.45), Tone = "glass" },
		{ Name = "Shard", Kind = "Block", CFrame = CFrame.new(-0.32, 0.45, -0.22) * CFrame.Angles(-0.3, 0.4, 0.6), Size = Vector3.new(0.4, 0.95, 0.4), Tone = "glass" },
		{ Name = "Shard", Kind = "Ball", CFrame = CFrame.new(0, 0.55, 0), Size = Vector3.new(0.6, 0.6, 0.6), Tone = "glow" },
	},
}
local function recipe(parts, cf, tones)
	for _, r in parts do
		local p
		if r.Kind == "CornerWedge" then
			p = Instance.new("CornerWedgePart")
		else
			p = Instance.new("Part")
			if r.Kind == "Ball" then
				p.Shape = Enum.PartType.Ball
			end
		end
		p.Name = r.Name
		p.Anchored = true
		p.Size = r.Size
		p.CFrame = G * cf * r.CFrame
		local t = tones[r.Tone]
		p.Color = t[1]
		p.Material = t[2]
		p.Transparency = t[3] or 0
		p.Reflectance = t[4] or 0
		p.Parent = root
	end
end
-- цвета тучи зоны 1 (STYLE §3.2: ядро, брюхо, кромка) и они же за миг до удара
local cloudTones = {
	core = { Color3.fromRGB(52, 53, 78), Enum.Material.SmoothPlastic },
	belly = { Color3.fromRGB(70, 76, 100), Enum.Material.SmoothPlastic },
	edge = { Color3.fromRGB(106, 112, 148), Enum.Material.SmoothPlastic },
	glow = { Color3.fromRGB(150, 220, 255), Enum.Material.Neon },
}
local glowTones = {
	core = { Color3.fromRGB(52, 53, 78):Lerp(Color3.fromRGB(110, 200, 255), 0.45), Enum.Material.SmoothPlastic },
	belly = { Color3.fromRGB(70, 76, 100), Enum.Material.SmoothPlastic },
	edge = { Color3.fromRGB(106, 112, 148), Enum.Material.SmoothPlastic },
	glow = { Color3.fromRGB(200, 240, 255), Enum.Material.Neon },
}
local cloudParts = if Models.strikeCloudRecipe then Models.strikeCloudRecipe() else OLD.cloud
local shardParts = if Models.shardRecipe then Models.shardRecipe() else OLD.shard
recipe(cloudParts, CFrame.new(-176, 18, 10), cloudTones)
recipe(cloudParts, CFrame.new(-160, 18, 14) * CFrame.Angles(0, math.rad(70), 0), glowTones)
local shardTones = {
	glass = { Color3.fromRGB(150, 235, 255), Enum.Material.Glass, 0.25, 0.15 },
	glow = { Color3.fromRGB(120, 230, 255), Enum.Material.Neon, 0.15 },
}
for i = 0, 2 do
	recipe(shardParts, CFrame.new(-172 + i * 3, 0, -2 + (i % 2) * 1.5) * CFrame.Angles(0, i * 1.7, 0), shardTones)
end
-- кольцо удара на земле для масштаба
local ringDisk = Instance.new("Part")
ringDisk.Name = "RingDisk"
ringDisk.Shape = Enum.PartType.Cylinder
ringDisk.Anchored = true
ringDisk.Size = Vector3.new(0.2, 12, 12)
ringDisk.CFrame = G * CFrame.new(-176, 0.1, 10) * CFrame.Angles(0, 0, math.pi / 2)
ringDisk.Color = Color3.fromRGB(110, 200, 255)
ringDisk.Material = Enum.Material.Neon
ringDisk.Transparency = 0.55
ringDisk.Parent = root
cam("strike", { -168, 3, -14 }, { -170, 13, 12 }, 62)
cam("shards", { -169, 3.2, -8 }, { -169, 0.6, -1 }, 46)

-- J. Шаровая молния, x ≈ −210
local bl
if Models.ballLightning then
	bl = Models.ballLightning()
else
	-- как было: ядро, оболочка, ForceField-сияние и 4 шара на орбите
	bl = Instance.new("Model")
	local function sphere(name, d, color, material, tr)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(d, d, d)
		p.Color = color
		p.Material = material
		p.Transparency = tr
		p.CFrame = CFrame.new()
		p.Parent = bl
	end
	sphere("Core", 5, Color3.fromRGB(255, 248, 225), Enum.Material.Neon, 0)
	sphere("Shell", 8.5, Color3.fromRGB(255, 196, 70), Enum.Material.Neon, 0.55)
	sphere("Glow", 12.5, Color3.fromRGB(255, 196, 70), Enum.Material.ForceField, 0.35)
	for i = 1, 4 do
		sphere("Orbiter" .. i, 1.3, Color3.fromRGB(255, 236, 150), Enum.Material.Neon, 0)
	end
end
local orbitI = 0
for _, d in bl:GetChildren() do
	if string.sub(d.Name, 1, 7) == "Orbiter" then
		orbitI += 1
		local a = orbitI * math.pi / 2 + 0.4
		d.CFrame = CFrame.new(math.cos(a) * 6.4, math.sin(a * 1.3) * 2, math.sin(a) * 6.4) * d.CFrame.Rotation
	end
end
place(bl, CFrame.new(-210, 12, 6) * CFrame.Angles(0.3, 0.5, 0))
cam("ball", { -210, 9, -14 }, { -210, 12, 6 }, 55)

fs.writeFile(out, roblox.serializeModel({ root }, true))
for _, s in report do
	print(s)
end
local camFile = string.gsub(out, "%.rbxmx$", "") .. "_cams.json"
fs.writeFile(camFile, serde.encode("json", cams))
print("wrote " .. out .. " and " .. camFile)
