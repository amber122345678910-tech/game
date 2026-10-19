--!strict
-- Фульгуриты — стеклянные "скульптуры", которые оставляет молния. Каждый строится из seed,
-- поэтому у каждого игрока свои уникальные формы. Чистая логика: геометрия как список деталей.
-- Имена форм и мутаций — русские исходники и ключи словаря (переводы — в Strings/Shared.luau).

local Config = require(script.Parent.Config)
local Loc = require(script.Parent.Loc)
local Prng = require(script.Parent.Prng)
local Pets = require(script.Parent.Pets)
local Geom = require(script.Parent.Geom)

export type MutId = "golden" | "night" | "rainbow" | "perun"

export type PartSpec = {
	CFrame: CFrame, -- относительно основания (0,0,0) — низ фульгурита
	Size: Vector3,
	Kind: "glass" | "core" | "base" | "tip",
	Shape: "Block" | "Cylinder" | "Ball",
}

export type Spec = {
	Shape: string, -- id формы
	ShapeName: string, -- исходник для Loc.t
	Rarity: Pets.Rarity,
	Bonus: number, -- +доля Вольт
	Height: number,
	Parts: { PartSpec },
}

local Fulgurite = {}

Fulgurite.Shapes = { "bush", "crown", "spiral", "tree", "star" }
Fulgurite.ShapeNames = {
	bush = "Куст",
	crown = "Корона",
	spiral = "Спираль",
	tree = "Дерево",
	star = "Звезда",
} :: { [string]: string }

Fulgurite.Mutations = {
	golden = { Name = "Золотой", Color = Color3.fromRGB(255, 205, 70), Score = 1.5 },
	night = { Name = "Ночной", Color = Color3.fromRGB(90, 70, 200), Score = 1.2 },
	rainbow = { Name = "Радужный", Color = Color3.fromRGB(255, 140, 220), Score = 2.2 },
	perun = { Name = "Перунов", Color = Color3.fromRGB(255, 190, 60), Score = 4 },
} :: { [MutId]: { Name: string, Color: Color3, Score: number } }

Fulgurite.RarityBonus = {
	common = 0.03,
	rare = 0.08,
	epic = 0.2,
	legendary = 0.5,
	mythic = 1.2,
} :: { [Pets.Rarity]: number }

Fulgurite.MaxInventory = 100
Fulgurite.MaxEquipped = 3

-- Осколки за разбитый фульгурит по редкости (× ценность осколка острова, где он найден).
-- Общие для сервера (FulguriteService) и окна «Разбить», чтобы игрок заранее видел, сколько получит.
Fulgurite.ShatterShards = {
	common = 5,
	rare = 15,
	epic = 50,
	legendary = 200,
	mythic = 1000,
} :: { [Pets.Rarity]: number }

function Fulgurite.shatterValue(rarity: Pets.Rarity, zone: number): number
	local z = Config.Zones[math.clamp(math.floor(zone), 1, #Config.Zones)]
	return (Fulgurite.ShatterShards[rarity] or 0) * z.ShardValue
end

-- Радужный фульгурит (гарантирован каждому поймавшему Радужную молнию): редкость решает только форма —
-- чаще легендарный, иногда мифический (мутация «Радужный» очков не добавляет)
Fulgurite.RainbowScore = 5.3
Fulgurite.QualityScore = 1.6 -- сколько очков редкости даёт качество формы (0..1)

-- Выпал ли фульгурит при ИДЕАЛЬНОЙ поимке
function Fulgurite.rollDrop(color: Config.ColorId, roll: number, luck: number?): boolean
	local chance = Config.Colors[color].FulgChance * (1 + 0.5 * math.max(0, luck or 0))
	return roll < chance
end

-- Мутация. eventKind: "rainbow" | "perun" | nil
function Fulgurite.rollMutation(zone: number, roll: number, color: Config.ColorId): MutId?
	if color == "black" then
		return "perun"
	elseif color == "rainbow" then
		return "rainbow"
	end
	if roll < 0.04 then
		return "golden"
	elseif zone >= 4 and roll < 0.08 then
		return "night"
	end
	return nil
end

-- Редкость: цвет молнии + качество формы + мутация. Чёрная/Перунов — всегда мифический,
-- радужный — Fulgurite.RainbowScore + качество (мутация не считается).
function Fulgurite.rarityOf(color: Config.ColorId, quality: number, mut: MutId?): Pets.Rarity
	if color == "black" or mut == "perun" then
		return "mythic"
	end
	local score: number
	if color == "rainbow" then
		score = Fulgurite.RainbowScore + quality * Fulgurite.QualityScore
	else
		score = Config.Colors[color].Order + quality * Fulgurite.QualityScore
		if mut then
			score += Fulgurite.Mutations[mut].Score
		end
	end
	if score >= 6.6 then
		return "mythic"
	elseif score >= 5.2 then
		return "legendary"
	elseif score >= 4.0 then
		return "epic"
	elseif score >= 2.6 then
		return "rare"
	end
	return "common"
end

local MAX_PARTS = 60 -- ограничение числа деталей (телефоны)
local BASE_PARTS = 6 -- основание: 3 глыбы и лужица-шестиугольник из 3 брусков
local DIAMOND = CFrame.Angles(math.pi / 4, 0, 0) -- поворот бруска вокруг своей оси: ромбовидное сечение
local GEM_TILT = CFrame.Angles(math.rad(35.264), 0, math.rad(45)) -- куб на вершине (кончики)

-- Отрезок стекла: брусок с ромбовидным сечением (удлинён для нахлёста на изломе, без шаров-суставов)
-- и тонкая светящаяся сердцевина. roll — поворот грани вокруг оси отрезка (разные грани ловят свет)
local function segment(parts: { PartSpec }, a: Vector3, b: Vector3, thickness: number, roll: number?)
	local cf, len = Geom.axisCFrame(a, b)
	if len < 0.05 or #parts >= MAX_PARTS - 2 then
		return
	end
	local rcf = cf * DIAMOND * CFrame.Angles(roll or 0, 0, 0)
	table.insert(parts, { CFrame = rcf, Size = Vector3.new(len + thickness * 0.35, thickness, thickness), Kind = "glass", Shape = "Block" } :: PartSpec)
	if thickness >= 0.3 then
		table.insert(parts, {
			CFrame = rcf,
			Size = Vector3.new(len + thickness * 0.2, thickness * 0.3, thickness * 0.3),
			Kind = "core",
			Shape = "Block",
		} :: PartSpec)
	end
end

local function rotateAround(v: Vector3, axis: Vector3, angle: number): Vector3
	return (CFrame.fromAxisAngle(axis, angle) * CFrame.new(v)).Position
end

-- Перпендикуляр к направлению (для изломов «как у молнии»)
local function perpendicular(d: Vector3, rng: Prng.Prng): Vector3
	local r = Vector3.new(rng:range(-1, 1), rng:range(-0.3, 0.3), rng:range(-1, 1))
	local p = d:Cross(r)
	if p.Magnitude < 1e-3 then
		p = d:Cross(Vector3.xAxis)
	end
	return p.Unit
end

-- Ветка: ломаная с резкими изломами, сужается к кончику; может ветвиться (рекурсивно).
-- limit — сколько деталей разрешено набрать к концу этой ветки (бюджет делится между ветками).
local function branch(parts: { PartSpec }, rng: Prng.Prng, pos: Vector3, dir: Vector3, len: number, thick: number, depth: number, style: string, limit: number)
	local p = pos
	local d = dir.Unit
	local steps = if style == "spiral" then 5 else 4
	local side = if rng:chance(0.5) then 1 else -1
	local t = thick
	for i = 1, steps do
		if #parts >= math.min(limit, MAX_PARTS - 3) then
			break
		end
		if style == "spiral" then
			d = rotateAround(d, Vector3.yAxis, 0.75)
		end
		-- излом: в сторону, поочерёдно влево/вправо, с лёгкой тягой вверх
		local kink = perpendicular(d, rng) * rng:range(0.35, 0.75) * side
		side = -side
		local lift = Vector3.new(0, if style == "star" then 0.05 else 0.22, 0)
		local stepDir = (d + kink * (if style == "spiral" then 0.4 else 1) + lift).Unit
		local nextP = p + stepDir * (len / steps) * rng:range(0.8, 1.2)
		if nextP.Y < 0.4 then
			nextP = Vector3.new(nextP.X, 0.4 + rng:range(0, 0.3), nextP.Z)
		end
		segment(parts, p, nextP, t, (i % 2) * 0.35)
		p = nextP
		t = math.max(0.16, t * 0.82)
		if depth > 0 and #parts < limit - 8 and rng:chance(if style == "bush" then 0.6 else 0.45) then
			local sideDir = (d + perpendicular(d, rng) * rng:range(0.8, 1.3) + Vector3.new(0, rng:range(0.1, 0.6), 0)).Unit
			branch(parts, rng, p, sideDir, len * 0.6, t * 0.75, depth - 1, style, limit)
		end
	end
	-- светящийся кончик-кристалл (куб на вершине)
	if #parts < MAX_PARTS then
		table.insert(parts, { CFrame = CFrame.new(p) * CFrame.Angles(0, d.X * 3 + d.Z * 2, 0) * GEM_TILT, Size = Vector3.one * math.max(0.2, t * 0.95), Kind = "tip", Shape = "Block" } :: PartSpec)
	end
end

-- Сгенерировать фульгурит
function Fulgurite.generate(seed: number, color: Config.ColorId, mut: MutId?): Spec
	local rng = Prng.new(seed)
	-- порядок первых вызовов rng не менять: от него зависят форма, качество и редкость
	local shape = Fulgurite.Shapes[rng:int(1, #Fulgurite.Shapes)]
	local quality = rng:next()
	local rarity = Fulgurite.rarityOf(color, quality, mut)
	local rank = Pets.Rarities[rarity].Rank
	local parts: { PartSpec } = {}
	-- основание: тёмный оплавленный камень (3 глыбы) и лужица стекла — плоский шестиугольник
	local yaw = rng:range(0, math.pi * 2)
	table.insert(parts, { CFrame = CFrame.new(0, 0.3, 0) * CFrame.Angles(0, yaw, 0), Size = Vector3.new(2.8, 0.6, 2.3), Kind = "base", Shape = "Block" } :: PartSpec)
	table.insert(parts, { CFrame = CFrame.new(0.2, 0.32, 0.1) * CFrame.Angles(0.12, yaw + 0.8, -0.1), Size = Vector3.new(2.2, 0.6, 2.0), Kind = "base", Shape = "Block" } :: PartSpec)
	table.insert(parts, { CFrame = CFrame.new(-0.9, 0.25, -0.6) * CFrame.Angles(0.2, yaw + 2.1, 0.15), Size = Vector3.new(1.1, 0.7, 1.0), Kind = "base", Shape = "Block" } :: PartSpec)
	for q = 0, 2 do
		table.insert(parts, {
			CFrame = CFrame.new(0, 0.63, 0) * CFrame.Angles(0, yaw + 0.3 + q * math.pi / 3, 0),
			Size = Vector3.new(1.08, 0.12, 1.08 * math.sqrt(3) * (1 + 0.08 * (q - 1))),
			Kind = "glass",
			Shape = "Block",
		} :: PartSpec)
	end
	local depth = 1 + math.min(3, rank - 1)
	local height = 3.2 + rank * 0.55 + quality
	local function share(i: number, n: number): number
		return BASE_PARTS + math.floor((MAX_PARTS - BASE_PARTS) * i / n)
	end
	if shape == "crown" then
		local n = 4 + math.min(rank, 4)
		for i = 1, n do
			local a = (i / n) * math.pi * 2 + rng:range(-0.15, 0.15)
			local dir = Vector3.new(math.cos(a) * 0.6, 1, math.sin(a) * 0.6)
			branch(parts, rng, Vector3.new(math.cos(a) * 0.7, 0.55, math.sin(a) * 0.7), dir, height * rng:range(0.65, 0.8), 0.5, depth - 1, shape, share(i, n))
		end
	elseif shape == "star" then
		local n = 4 + math.min(rank, 3)
		for i = 1, n do
			local a = (i / n) * math.pi * 2 + rng:range(-0.2, 0.2)
			local dir = Vector3.new(math.cos(a), rng:range(0.45, 1.2), math.sin(a))
			branch(parts, rng, Vector3.new(0, 0.6, 0), dir, height * 0.7, 0.55, depth - 1, shape, share(i, n))
		end
		-- центральный столбик
		segment(parts, Vector3.new(0, 0.6, 0), Vector3.new(rng:range(-0.2, 0.2), height * 0.45, rng:range(-0.2, 0.2)), 0.6)
	elseif shape == "tree" then
		branch(parts, rng, Vector3.new(0, 0.55, 0), Vector3.yAxis, height, 0.85, depth, shape, share(1, 3))
		for i = 2, 3 do
			branch(parts, rng, Vector3.new(rng:range(-0.2, 0.2), height * 0.5, rng:range(-0.2, 0.2)), Vector3.new(rng:range(-1, 1), 0.8, rng:range(-1, 1)), height * 0.5, 0.5, depth - 1, shape, share(i, 3))
		end
	elseif shape == "spiral" then
		branch(parts, rng, Vector3.new(0.6, 0.55, 0), Vector3.new(0.35, 1, 0), height * 1.15, 0.65, depth - 1, shape, share(1, 2))
		branch(parts, rng, Vector3.new(-0.6, 0.55, 0), Vector3.new(-0.35, 1, 0), height * 0.95, 0.55, depth - 1, shape, share(2, 2))
	else -- bush
		local n = 2 + math.floor(rank / 2)
		for i = 1, n do
			branch(parts, rng, Vector3.new(rng:range(-0.6, 0.6), 0.55, rng:range(-0.6, 0.6)), Vector3.new(rng:range(-0.5, 0.5), 1, rng:range(-0.5, 0.5)), height * 0.75, 0.6, depth, shape, share(i, n))
		end
	end
	while #parts > MAX_PARTS do
		table.remove(parts)
	end
	return {
		Shape = shape,
		ShapeName = Fulgurite.ShapeNames[shape],
		Rarity = rarity,
		Bonus = Fulgurite.RarityBonus[rarity],
		Height = height,
		Parts = parts,
	}
end

-- Название сообщением (сервер → клиент, переводит клиент через Loc.render):
-- «Золотой фульгурит «Спираль»» / «Golden Spiral Fulgurite»
-- (string.lower/sub режут кириллицу по байтам, поэтому строки собираются целиком)
function Fulgurite.titleMsg(spec: Spec, mut: MutId?): Loc.Msg
	if mut then
		return Loc.msg("%s фульгурит «%s»", Fulgurite.Mutations[mut].Name, spec.ShapeName)
	end
	return Loc.msg("Фульгурит «%s»", spec.ShapeName)
end

-- Название для интерфейса на языке игрока (клиент)
function Fulgurite.title(spec: Spec, mut: MutId?): string
	return Loc.render(Fulgurite.titleMsg(spec, mut))
end

-- Цвет стекла
function Fulgurite.glassColor(color: Config.ColorId, mut: MutId?): Color3
	if mut then
		return Fulgurite.Mutations[mut].Color
	end
	return Config.Colors[color].Color
end

return Fulgurite
