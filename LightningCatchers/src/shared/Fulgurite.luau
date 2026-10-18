--!strict
-- Фульгуриты — стеклянные "скульптуры", которые оставляет молния. Каждый строится из seed,
-- поэтому у каждого игрока свои уникальные формы. Чистая логика: геометрия как список деталей.

local Config = require(script.Parent.Config)
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
	ShapeName: string,
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

-- Редкость: цвет молнии + качество формы + мутация
function Fulgurite.rarityOf(color: Config.ColorId, quality: number, mut: MutId?): Pets.Rarity
	local score = Config.Colors[color].Order + quality * 1.6
	if mut then
		score += Fulgurite.Mutations[mut].Score
	end
	if color == "black" or mut == "perun" then
		return "mythic"
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

local function segment(parts: { PartSpec }, a: Vector3, b: Vector3, thickness: number)
	local cf, len = Geom.axisCFrame(a, b)
	if len < 0.05 then
		return
	end
	table.insert(parts, { CFrame = cf, Size = Vector3.new(len + thickness * 0.4, thickness, thickness), Kind = "glass", Shape = "Cylinder" } :: PartSpec)
	if thickness >= 0.35 then
		table.insert(parts, {
			CFrame = cf,
			Size = Vector3.new(len, thickness * 0.38, thickness * 0.38),
			Kind = "core",
			Shape = "Cylinder",
		} :: PartSpec)
	end
end

local function rotateAround(v: Vector3, axis: Vector3, angle: number): Vector3
	return (CFrame.fromAxisAngle(axis, angle) * CFrame.new(v)).Position
end

-- Ветка: рекурсивно, с сужением и случайными отклонениями
local function branch(parts: { PartSpec }, rng: Prng.Prng, pos: Vector3, dir: Vector3, len: number, thick: number, depth: number, style: string)
	local p = pos
	local d = dir.Unit
	local steps = if style == "spiral" then 5 else 3
	for i = 1, steps do
		local jitter = Vector3.new(rng:range(-0.45, 0.45), rng:range(-0.1, 0.25), rng:range(-0.45, 0.45))
		if style == "spiral" then
			d = rotateAround(d, Vector3.yAxis, 0.7)
			jitter *= 0.4
		end
		d = (d + jitter).Unit
		local nextP = p + d * (len / steps)
		segment(parts, p, nextP, thick * (1 - 0.12 * i))
		p = nextP
		if depth > 0 and #parts < 70 and rng:chance(if style == "bush" then 0.55 else 0.38) then
			local side = Vector3.new(rng:range(-1, 1), rng:range(0.2, 0.9), rng:range(-1, 1))
			branch(parts, rng, p, side, len * 0.62, thick * 0.66, depth - 1, style)
		end
	end
	-- светящийся кончик
	table.insert(parts, { CFrame = CFrame.new(p), Size = Vector3.one * math.max(0.3, thick * 0.9), Kind = "tip", Shape = "Ball" } :: PartSpec)
end

-- Сгенерировать фульгурит
function Fulgurite.generate(seed: number, color: Config.ColorId, mut: MutId?): Spec
	local rng = Prng.new(seed)
	local shape = Fulgurite.Shapes[rng:int(1, #Fulgurite.Shapes)]
	local quality = rng:next()
	local rarity = Fulgurite.rarityOf(color, quality, mut)
	local rank = Pets.Rarities[rarity].Rank
	local parts: { PartSpec } = {}
	-- основание: тёмный оплавленный камень
	table.insert(parts, { CFrame = CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.pi / 2), Size = Vector3.new(0.5, 3.4, 3.4), Kind = "base", Shape = "Cylinder" } :: PartSpec)
	local depth = 1 + math.min(3, rank - 1)
	local height = 3.2 + rank * 0.55 + quality
	if shape == "crown" then
		local n = 5 + rank
		for i = 1, n do
			local a = (i / n) * math.pi * 2
			local dir = Vector3.new(math.cos(a) * 0.55, 1, math.sin(a) * 0.55)
			branch(parts, rng, Vector3.new(math.cos(a) * 0.9, 0.5, math.sin(a) * 0.9), dir, height * 0.7, 0.45, depth - 1, shape)
		end
	elseif shape == "star" then
		local n = 4 + rank
		for i = 1, n do
			local a = (i / n) * math.pi * 2
			local dir = Vector3.new(math.cos(a), rng:range(0.5, 1.4), math.sin(a))
			branch(parts, rng, Vector3.new(0, 0.6, 0), dir, height * 0.65, 0.5, depth - 1, shape)
		end
	elseif shape == "tree" then
		branch(parts, rng, Vector3.new(0, 0.5, 0), Vector3.yAxis, height, 0.75, depth, shape)
		for _ = 1, 2 do
			branch(parts, rng, Vector3.new(0, height * 0.55, 0), Vector3.new(rng:range(-1, 1), 0.8, rng:range(-1, 1)), height * 0.5, 0.45, depth - 1, shape)
		end
	elseif shape == "spiral" then
		branch(parts, rng, Vector3.new(0.6, 0.5, 0), Vector3.new(0.3, 1, 0), height * 1.15, 0.6, depth - 1, shape)
		branch(parts, rng, Vector3.new(-0.6, 0.5, 0), Vector3.new(-0.3, 1, 0), height * 0.9, 0.5, depth - 1, shape)
	else -- bush
		for _ = 1, 2 + math.floor(rank / 2) do
			branch(parts, rng, Vector3.new(rng:range(-0.6, 0.6), 0.5, rng:range(-0.6, 0.6)), Vector3.new(rng:range(-0.5, 0.5), 1, rng:range(-0.5, 0.5)), height * 0.75, 0.55, depth, shape)
		end
	end
	-- ограничение числа деталей (телефоны)
	while #parts > 90 do
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

-- Название для интерфейса: "Золотой фульгурит «Спираль»"
-- (string.lower/sub режут кириллицу по байтам, поэтому строки собираются целиком)
function Fulgurite.title(spec: Spec, mut: MutId?): string
	if mut then
		return Fulgurite.Mutations[mut].Name .. " фульгурит «" .. spec.ShapeName .. "»"
	end
	return "Фульгурит «" .. spec.ShapeName .. "»"
end

-- Цвет стекла
function Fulgurite.glassColor(color: Config.ColorId, mut: MutId?): Color3
	if mut then
		return Fulgurite.Mutations[mut].Color
	end
	return Config.Colors[color].Color
end

return Fulgurite
