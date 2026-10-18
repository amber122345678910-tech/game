--!nocheck
-- Контактный лист моделей из src/shared/Models.luau: все питомцы, коконы, 6 громоотводов, фульгуриты.
-- Запуск из LightningCatchers/: .tools/lune run tools/preview/models_sheet.luau OUT.rbxmx
-- Потом: cd tools/preview && lune run dump_scene.luau OUT.json OUT.rbxmx && node render.mjs OUT.json PREFIX cams.json
-- Камеры для листа печатаются в stdout (JSON) — их можно сохранить в cams.json.
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

local Models = Loader.load("src/shared/Models")
local Pets = Loader.load("src/shared/Pets")
local Fulgurite = Loader.load("src/shared/Fulgurite")
local Config = Loader.load("src/shared/Config")

local out = process.args[1] or "models_sheet.rbxmx"
local root = Instance.new("Model")
root.Name = "Sheet"

-- Переставить модель (в Lune нет PivotTo): сдвигаем все детали
local function place(inst, cf)
	inst.Parent = root
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = cf * d.CFrame
			d.Anchored = true
		end
	end
end

-- пол-подложка
local floor = Instance.new("Part")
floor.Name = "Floor"
floor.Anchored = true
floor.Size = Vector3.new(120, 1, 70)
floor.CFrame = CFrame.new(20, -0.5, 10)
floor.Color = Color3.fromRGB(70, 74, 92)
floor.Material = Enum.Material.SmoothPlastic
floor.Parent = root

local cams = {}

-- ряд 1: питомцы (по порядку коконов и редкости)
local kinds = {}
for _, cid in Pets.CocoonOrder do
	for _, e in Pets.Cocoons[cid].Pool do
		table.insert(kinds, e.kind)
	end
end
table.insert(kinds, 7, "gromik")
for i, kind in kinds do
	local col = (i - 1) % 11
	local row = (i - 1) // 11
	local m = Models.pet(kind)
	place(m, CFrame.new(col * 3.4, 1.6, row * 4.2) * CFrame.Angles(0, math.rad(-12), 0))
end
table.insert(cams, { name = "pets", pos = { 17, 4.5, -11 }, look = { 17, 2.2, 2.8 }, fov = 50 })
table.insert(cams, { name = "petsclose", pos = { 5.1, 2.6, -5.2 }, look = { 5.1, 1.7, 0 }, fov = 40 })

-- ряд 2: коконы и громоотводы
for i, id in Pets.CocoonOrder do
	place(Models.cocoon(id), CFrame.new((i - 1) * 4.5, 0, 14))
end
for t = 0, 5 do
	local tool = Models.rod(t)
	place(tool, CFrame.new(16 + t * 2.6, 1.3, 14))
end
place(Models.jar(), CFrame.new(33, 1.6, 14))
place(Models.station(), CFrame.new(40, 0, 15))
table.insert(cams, { name = "gear", pos = { 21, 5, 0 }, look = { 21, 3, 14 }, fov = 55 })

-- ряд 3: фульгуриты (разные seed, цвета, мутации)
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
local infos = {}
for i, f in list do
	local spec = Fulgurite.generate(f.seed, f.color, f.mut)
	local glass = Fulgurite.glassColor(f.color, f.mut)
	place(Models.fulgurite(spec, glass), CFrame.new((i - 1) * 6.5, 0, 28))
	table.insert(infos, string.format("%d: %s %s %s parts=%d h=%.1f", i, spec.ShapeName, spec.Rarity, f.color, #spec.Parts, spec.Height))
end
table.insert(cams, { name = "fulg", pos = { 29, 8, 46 }, look = { 29, 3.2, 28 }, fov = 55 })
table.insert(cams, { name = "fulgclose", pos = { 9.75, 5.5, 39 }, look = { 9.75, 3, 28 }, fov = 45 })

-- свет для превью
local lamp = Instance.new("Part")
lamp.Name = "Lamp"
lamp.Anchored = true
lamp.Transparency = 1
lamp.CFrame = CFrame.new(20, 14, 6)
lamp.Parent = root
local pl = Instance.new("PointLight")
pl.Range = 60
pl.Brightness = 1.2
pl.Color = Color3.fromRGB(255, 244, 230)
pl.Parent = lamp

fs.writeFile(out, roblox.serializeModel({ root }, true))
for _, s in infos do
	print(s)
end
local camFile = string.gsub(out, "%.rbxmx$", "") .. "_cams.json"
for _, c in cams do
	c.clockTime = 14
end
fs.writeFile(camFile, serde.encode("json", cams))
print("wrote " .. out .. " and " .. camFile)
