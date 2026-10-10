--!strict
-- Готовые бункеры для магазина. Раскладки генерируются кодом (чистые данные).

local Config = require(script.Parent.Config)
local Grid = require(script.Parent.Grid)

export type PrefabDef = {
	Id: string,
	Name: string,
	Description: string,
	Order: number,
	InnerW: number, -- внутренняя ширина (клетки)
	InnerD: number, -- внутренняя глубина (клетки)
	WallH: number, -- высота стен (клетки) = высота внутреннего пространства
	Thickness: number, -- толщина стен
	Wall: string,
	Roof: string,
	RoofTop: string?, -- дополнительный защитный слой поверх крыши
	Door: string,
	Free: boolean, -- бесплатно (один раз)
}

local Prefabs = {}

Prefabs.List = {
	{
		Id = "starter",
		Name = "Стартовая хижина",
		Description = "Простая деревянная хижина. Бесплатно один раз!",
		Order = 1,
		InnerW = 3,
		InnerD = 3,
		WallH = 2,
		Thickness = 1,
		Wall = "wood",
		Roof = "wood",
		RoofTop = nil,
		Door = "door_wood",
		Free = true,
	},
	{
		Id = "stone",
		Name = "Каменный бункер",
		Description = "Каменные стены неплохо держат град и кислоту. Железная дверь.",
		Order = 2,
		InnerW = 4,
		InnerD = 4,
		WallH = 3,
		Thickness = 1,
		Wall = "stone",
		Roof = "stone",
		RoofTop = nil,
		Door = "door_iron",
		Free = false,
	},
	{
		Id = "metal",
		Name = "Металлический бункер",
		Description = "Металл крепок против града, но кислота его разъедает! Железная дверь.",
		Order = 3,
		InnerW = 4,
		InnerD = 4,
		WallH = 3,
		Thickness = 1,
		Wall = "metal",
		Roof = "metal",
		RoofTop = nil,
		Door = "door_iron",
		Free = false,
	},
	{
		Id = "concrete",
		Name = "Бетонное убежище",
		Description = "Бетон с каменной защитой крыши и железной дверью.",
		Order = 4,
		InnerW = 4,
		InnerD = 4,
		WallH = 3,
		Thickness = 1,
		Wall = "concrete",
		Roof = "concrete",
		RoofTop = "stone",
		Door = "door_iron",
		Free = false,
	},
	{
		Id = "steel",
		Name = "Стальная крепость",
		Description = "Стальные стены, бетонная защита крыши и гермодверь.",
		Order = 5,
		InnerW = 5,
		InnerD = 5,
		WallH = 3,
		Thickness = 1,
		Wall = "steel",
		Roof = "steel",
		RoofTop = "concrete",
		Door = "door_blast",
		Free = false,
	},
	{
		Id = "titan",
		Name = "Титановое убежище",
		Description = "Двойные титановые стены и гермодверь. Переживёт что угодно.",
		Order = 6,
		InnerW = 4,
		InnerD = 4,
		WallH = 3,
		Thickness = 2,
		Wall = "titan",
		Roof = "titan",
		RoofTop = "titan",
		Door = "door_blast",
		Free = false,
	},
} :: { PrefabDef }

Prefabs.ById = {} :: { [string]: PrefabDef }
for _, def in Prefabs.List do
	Prefabs.ById[def.Id] = def
end

function Prefabs.get(id: any): PrefabDef?
	if typeof(id) ~= "string" then
		return nil
	end
	return Prefabs.ById[id]
end

-- Раскладка бункера: прямоугольная коробка по центру сетки, дверь в передней стене (z минимальный).
function Prefabs.layout(id: string): { Grid.Entry }
	local def = Prefabs.ById[id]
	assert(def, "Unknown prefab " .. tostring(id))
	local t = def.Thickness
	local ow = def.InnerW + 2 * t
	local od = def.InnerD + 2 * t
	local x0 = (Grid.W - ow) // 2
	local z0 = (Grid.D - od) // 2
	local doorX = x0 + ow // 2
	local entries: { Grid.Entry } = {}
	local used: { [number]: boolean } = {}

	local function add(blockId: string, x: number, y: number, z: number)
		local idx = Grid.index(x, y, z)
		if used[idx] then
			return
		end
		used[idx] = true
		table.insert(entries, { id = blockId, x = x, y = y, z = z, rot = 0 })
	end

	-- Дверь в наружном слое передней стены; проём во внутренних слоях остаётся пустым.
	local doorDef = Config.Blocks[def.Door]
	for dy = 0, doorDef.HeightCells - 1 do
		used[Grid.index(doorX, dy, z0)] = true
	end
	table.insert(entries, { id = def.Door, x = doorX, y = 0, z = z0, rot = 0 })
	for layer = 1, t - 1 do
		for dy = 0, doorDef.HeightCells - 1 do
			used[Grid.index(doorX, dy, z0 + layer)] = true -- проём
		end
	end

	-- Стены
	for y = 0, def.WallH - 1 do
		for x = x0, x0 + ow - 1 do
			for z = z0, z0 + od - 1 do
				local dx = math.min(x - x0, x0 + ow - 1 - x)
				local dz = math.min(z - z0, z0 + od - 1 - z)
				if math.min(dx, dz) < t then
					add(def.Wall, x, y, z)
				end
			end
		end
	end

	-- Крыша (и защитный слой)
	for x = x0, x0 + ow - 1 do
		for z = z0, z0 + od - 1 do
			add(def.Roof, x, def.WallH, z)
			if def.RoofTop and def.WallH + 1 + Grid.SURFACE < Grid.H then
				add(def.RoofTop, x, def.WallH + 1, z)
			end
		end
	end

	-- бункер стоит на поверхности участка (над подземными слоями)
	for _, e in entries do
		e.y += Grid.SURFACE
	end
	return entries
end

function Prefabs.blockCounts(id: string): { [string]: number }
	return Grid.countBlocks(Prefabs.layout(id))
end

-- Цена готового бункера = стоимость блоков со скидкой (стартовый — бесплатно).
function Prefabs.price(id: string): number
	local def = Prefabs.ById[id]
	if not def or def.Free then
		return 0
	end
	local total = 0
	for blockId, count in Prefabs.blockCounts(id) do
		total += Config.Blocks[blockId].Price * count
	end
	return math.floor(total * Config.Economy.PrefabDiscount)
end

-- Суммарное HP бункера (для карточки в магазине).
function Prefabs.totalHP(id: string): number
	local total = 0
	for blockId, count in Prefabs.blockCounts(id) do
		total += Config.Blocks[blockId].HP * count
	end
	return total
end

return Prefabs
