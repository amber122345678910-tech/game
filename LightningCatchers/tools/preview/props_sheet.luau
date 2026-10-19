--!nocheck
-- Лист превью пропов и «кирпичиков» стиля (docs/STYLE.md §12, п. 2): деревья трёх типов, тополь, ель, куст,
-- камни, цветы, кристаллы, шип, кактус, пальма, фонарь, примитивы (GemCube, Pyramid4, SkewPlate, Zigzag, Lobe).
-- Запуск из LightningCatchers/: .tools/lune run tools/preview/props_sheet.luau OUT.rbxmx
-- Рядом пишет OUT_cams.json (виды: props_a, props_b, prims, props_top).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local P = require("../lib/props")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local rgb = B.rgb

local out = process.args[1] or "props_sheet.rbxmx"
local root = B.model(nil, "PropsSheet")

-- земля
B.block(root, CFrame.new(40, -0.5, 10), Vector3.new(140, 1, 60), rgb(96, 170, 74), { Material = Enum.Material.Grass, Name = "Ground" })

local meadow = { trunk = rgb(124, 84, 58), leafA = rgb(78, 158, 70), leafB = rgb(122, 186, 72), fruit = rgb(230, 70, 70), berries = rgb(220, 60, 80), rock = rgb(132, 128, 144) }
local hills = { trunk = rgb(110, 74, 58), leafA = rgb(214, 140, 60), rock = rgb(128, 98, 90), vein = rgb(255, 150, 70), copper = rgb(204, 116, 64) }
local ice = { needles = rgb(52, 120, 104), snow = rgb(246, 250, 255), trunk = rgb(124, 84, 58), rock = rgb(140, 156, 196) }
local eye = { rock = rgb(50, 42, 64), crack = rgb(186, 104, 255) }
local dunes = { cactus = rgb(84, 150, 96), cactusFlower = rgb(255, 120, 170), stone = rgb(204, 160, 112) }

local rng = B.rng(5)
local x = 0
local function at(dx)
	x += dx
	return Vector3.new(x, 0, 0)
end
-- ряд A: деревья
P.tree(root, at(0), rng, meadow, 1)
P.tree(root, at(12), rng, meadow, 1.15)
P.poplar(root, at(11), rng, meadow, 1)
P.windyTree(root, at(10), rng, meadow, 1)
P.deadTree(root, at(14), rng, hills, 1)
P.pine(root, at(10), rng, ice, 1.3)
P.pine(root, at(8), rng, ice, 1.0)
P.pine(root, at(6), rng, ice, 0.85)
P.palm(root, at(10), rng)
P.cactus(root, at(8), rng, dunes, 1)
P.cactus(root, at(6), rng, dunes, 1.1)
-- ряд B (z = 22): мелочь
x = 0
local function atB(dx)
	x += dx
	return Vector3.new(x, 0, 22)
end
P.bush(root, atB(0), rng, meadow, 1)
P.bush(root, atB(5), rng, meadow, 1.2)
P.rock(root, atB(6), rng, meadow, 1.2)
P.flagstone(root, atB(6), rng, meadow, 1)
P.veinRock(root, atB(7), rng, hills, 1.2)
P.basalt(root, atB(8), rng, eye, 1)
P.crystals(root, atB(8), rng, rgb(156, 206, 246), 1.2, rgb(200, 140, 255), nil)
P.crystals(root, atB(7), rng, rgb(150, 100, 230), 1.1, nil, rgb(62, 52, 82))
P.glassSpike(root, atB(7), rng, rgb(140, 240, 228), rgb(110, 240, 230), 1.2)
P.floatRock(root, atB(7) + Vector3.new(0, 4, 0), rng, eye, 1.2)
P.mushroom(root, atB(5), rng, rgb(220, 70, 60), 1.2)
P.lamp(root, atB(5), rng, rgb(255, 206, 140), 9)
P.flowerStrip(root, atB(6), rng, { rgb(255, 120, 160), rgb(255, 214, 90), rgb(250, 248, 255) }, 8, true)
for k = 1, 4 do
	P.tuft(root, atB(1.2), rng, rgb(96, 170, 74), 1, k == 1)
end
P.hayBales(root, atB(5), rng)
P.drift(root, atB(6), rng, rgb(232, 238, 252), 1)
P.snowman(root, atB(6), Vector3.new(0, 0, 1), rng)
-- ряд C (z = -16): примитивы
B.gem(root, Vector3.new(0, 1.2, -46), 1.6, 0, rgb(230, 70, 70), {})
B.pyramid4(root, Vector3.new(5, 0, -46), 4, 4, 0, rgb(80, 150, 120), {})
B.pyramid4(root, Vector3.new(11, 5, -46), 3, 3, 0.3, rgb(120, 110, 160), {}, true)
B.hexPrism(root, Vector3.new(17, 2, -46), 2, 4, 0.2, rgb(150, 140, 120), {})
B.hexPlate(root, Vector3.new(25, 0.5, -46), 4, 1, 0, 1, rng, rgb(123, 122, 172), {})
B.lobe(root, Vector3.new(34, 0, -46), 6, 3.2, rgb(136, 138, 189), rgb(150, 156, 206), {})
local sign = B.sign(root, B.facing(Vector3.new(46, 3, -46), Vector3.new(0, 0, 1)), 8, 2.4, { { Text = "Грозовой Луг" }, { Text = "остров 1" } }, { Underline = rgb(110, 200, 255) })
local _ = sign
B.zigzag(root, Vector3.new(54, 6, -46), Vector3.new(56, 0.5, -46), 3, 0.5, rgb(110, 200, 255), B.neon(), Vector3.new(0, 0, 1))
B.zigzag(root, Vector3.new(58, 0.1, -50), Vector3.new(70, 0.1, -42), 4, 0.6, rgb(204, 116, 64), {}, Vector3.yAxis, 0.05)

fs.writeFile(out, roblox.serializeModel({ root }, true))
local cams = {
	{ name = "props_a", pos = { 22, 8, -22 }, look = { 22, 5, 0 }, fov = 62, clockTime = 14 },
	{ name = "props_a2", pos = { 70, 8, -22 }, look = { 70, 5, 0 }, fov = 62, clockTime = 14 },
	{ name = "props_b", pos = { 30, 7, 40 }, look = { 30, 2, 22 }, fov = 66, clockTime = 14 },
	{ name = "props_b2", pos = { 75, 7, 40 }, look = { 75, 2, 22 }, fov = 66, clockTime = 14 },
	{ name = "prims", pos = { 36, 7, -28 }, look = { 36, 2, -46 }, fov = 66, clockTime = 14 },
	{ name = "props_top", pos = { 50, 60, 30 }, look = { 50, 0, 5 }, fov = 60, clockTime = 14 },
}
local camFile = string.gsub(out, "%.rbxmx$", "") .. "_cams.json"
fs.writeFile(camFile, serde.encode("json", cams))
print(string.format("%d деталей (шаров %d) -> %s, камеры -> %s", B.count, B.balls, out, camFile))
