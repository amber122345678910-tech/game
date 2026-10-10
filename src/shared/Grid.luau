--!strict
-- Чистая математика сетки постройки (без Roblox API, тестируется в luau CLI).
-- Клетки: x ∈ [0, W-1], y ∈ [0, H-1], z ∈ [0, D-1]. Индекс 1-based.
-- z = 0 — передний ряд (ближе к лобби), y = 0 — слой на полу котлована.

local Config = require(script.Parent.Config)

export type Entry = {
	id: string,
	x: number,
	y: number,
	z: number,
	rot: number,
}

export type Rect = {
	x0: number,
	z0: number,
	x1: number,
	z1: number,
}

local Grid = {}

local W = Config.Grid.Width
local D = Config.Grid.Depth
local H = Config.Grid.Height
local CELL = Config.Grid.CellSize

Grid.W = W
Grid.D = D
Grid.H = H
Grid.CELL = CELL
Grid.COUNT = W * D * H
-- Минимальный угол сетки в локальных координатах участка.
Grid.ORIGIN_X = -W * CELL / 2
Grid.ORIGIN_Z = -D * CELL / 2
-- Слои 0..SURFACE-1 — под землёй (земля, которую можно копать); слой SURFACE лежит на поверхности
-- участка (локальная Y = 0). Локальная Y низа слоя y = (y - SURFACE) * CELL.
Grid.SURFACE = Config.Grid.Underground
local SURFACE = Grid.SURFACE

-- Локальная высота низа слоя y.
function Grid.layerBottom(y: number): number
	return (y - SURFACE) * CELL
end

function Grid.isUnderground(y: number): boolean
	return y < SURFACE
end

function Grid.inBounds(x: number, y: number, z: number): boolean
	return x >= 0 and x < W and y >= 0 and y < H and z >= 0 and z < D
		and x == math.floor(x) and y == math.floor(y) and z == math.floor(z)
end

function Grid.index(x: number, y: number, z: number): number
	return x + z * W + y * W * D + 1
end

function Grid.coords(index: number): (number, number, number)
	local i = index - 1
	local y = i // (W * D)
	local rem = i - y * W * D
	local z = rem // W
	local x = rem - z * W
	return x, y, z
end

-- Индекс колонки (x, z) для 2D-множеств.
function Grid.index2(x: number, z: number): number
	return x + z * W + 1
end

function Grid.coords2(index: number): (number, number)
	local i = index - 1
	local z = i // W
	return i - z * W, z
end

-- Центр клетки в локальных координатах участка.
function Grid.cellCenterLocal(x: number, y: number, z: number): (number, number, number)
	return Grid.ORIGIN_X + (x + 0.5) * CELL, (y - SURFACE + 0.5) * CELL, Grid.ORIGIN_Z + (z + 0.5) * CELL
end

-- Клетка, в которую попадает локальная точка (может быть вне границ — проверяйте inBounds).
function Grid.localToCell(lx: number, ly: number, lz: number): (number, number, number)
	return math.floor((lx - Grid.ORIGIN_X) / CELL), math.floor(ly / CELL) + SURFACE, math.floor((lz - Grid.ORIGIN_Z) / CELL)
end

-- Клетки, которые занимает блок с высотой heightCells, поставленный в (x, y, z).
function Grid.footprint(x: number, y: number, z: number, heightCells: number): { number }
	local cells = {}
	for dy = 0, heightCells - 1 do
		table.insert(cells, Grid.index(x, y + dy, z))
	end
	return cells
end

-- Самый верхний занятый слой в колонке или nil.
function Grid.columnTop(solid: { [number]: any }, x: number, z: number): number?
	for y = H - 1, 0, -1 do
		if solid[Grid.index(x, y, z)] then
			return y
		end
	end
	return nil
end

-- Есть ли над клеткой (x, y, z) хоть один блок.
function Grid.isCovered(solid: { [number]: any }, x: number, y: number, z: number): boolean
	for yy = math.max(y + 1, 0), H - 1 do
		if solid[Grid.index(x, yy, z)] then
			return true
		end
	end
	return false
end

local NEIGHBORS = {
	{ 1, 0, 0 },
	{ -1, 0, 0 },
	{ 0, 1, 0 },
	{ 0, -1, 0 },
	{ 0, 0, 1 },
	{ 0, 0, -1 },
}
Grid.NEIGHBORS = NEIGHBORS

-- Внешние пустые клетки: достижимые из-за границы сетки (бока над землёй и небо) через пустые
-- клетки. Под поверхностью края сетки — сплошная земля. Двери считаются сплошными.
function Grid.computeExterior(solid: { [number]: any }): { [number]: boolean }
	local exterior: { [number]: boolean } = {}
	local queue: { number } = {}
	local head = 1

	local function push(x: number, y: number, z: number)
		local i = Grid.index(x, y, z)
		if not solid[i] and not exterior[i] then
			exterior[i] = true
			table.insert(queue, i)
		end
	end

	for y = SURFACE, H - 1 do
		for x = 0, W - 1 do
			push(x, y, 0)
			push(x, y, D - 1)
		end
		for z = 0, D - 1 do
			push(0, y, z)
			push(W - 1, y, z)
		end
	end
	for x = 0, W - 1 do
		for z = 0, D - 1 do
			push(x, H - 1, z)
		end
	end

	while head <= #queue do
		local i = queue[head]
		head += 1
		local x, y, z = Grid.coords(i)
		for _, d in NEIGHBORS do
			local nx, ny, nz = x + d[1], y + d[2], z + d[3]
			if nx >= 0 and nx < W and ny >= 0 and ny < H and nz >= 0 and nz < D then
				push(nx, ny, nz)
			end
		end
	end
	return exterior
end

-- Внешние клетки, до которых кислота может дотечь по слоям 0..maxLayer (через бока сетки,
-- без неба): лужа поднимается от пола, поэтому дыры в крыше её не впускают.
function Grid.computeExteriorBelow(solid: { [number]: any }, maxLayer: number): { [number]: boolean }
	local exterior: { [number]: boolean } = {}
	local top = math.min(maxLayer, H - 1)
	if top < 0 then
		return exterior
	end
	local queue: { number } = {}
	local head = 1

	local function push(x: number, y: number, z: number)
		local i = Grid.index(x, y, z)
		if not solid[i] and not exterior[i] then
			exterior[i] = true
			table.insert(queue, i)
		end
	end

	-- лужа заходит с боков только над поверхностью, но стекает вниз в открытые ямы
	for y = SURFACE, top do
		for x = 0, W - 1 do
			push(x, y, 0)
			push(x, y, D - 1)
		end
		for z = 0, D - 1 do
			push(0, y, z)
			push(W - 1, y, z)
		end
	end
	while head <= #queue do
		local i = queue[head]
		head += 1
		local x, y, z = Grid.coords(i)
		for _, d in NEIGHBORS do
			local nx, ny, nz = x + d[1], y + d[2], z + d[3]
			if nx >= 0 and nx < W and ny >= 0 and ny <= top and nz >= 0 and nz < D then
				push(nx, ny, nz)
			end
		end
	end
	return exterior
end

-- Верхний затопленный слой при уровне лужи level (локальная Y, 0 = поверхность):
-- слои y, у которых низ ниже уровня. Без лужи — -1 (ничего не затоплено).
function Grid.submergedLayers(level: number): number
	if level <= 0 then
		return -1
	end
	return SURFACE + math.ceil(level / CELL) - 1
end

-- Внутренние клетки = пустые и не внешние (замкнутый объём бункера).
function Grid.computeInterior(solid: { [number]: any }, exterior: { [number]: boolean }?): { [number]: boolean }
	local ext = exterior or Grid.computeExterior(solid)
	local interior: { [number]: boolean } = {}
	for i = 1, Grid.COUNT do
		if not solid[i] and not ext[i] then
			interior[i] = true
		end
	end
	return interior
end

function Grid.countSet(set: { [number]: any }): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

-- Жадное объединение 2D-клеток (ключ index2) в прямоугольники (включительно).
-- Нужно, чтобы рисовать кислоту минимальным числом деталей.
function Grid.greedyRects(cells: { [number]: any }): { Rect }
	local used: { [number]: boolean } = {}
	local rects: { Rect } = {}
	for z = 0, D - 1 do
		for x = 0, W - 1 do
			local i = Grid.index2(x, z)
			if cells[i] and not used[i] then
				-- растягиваем по X
				local x1 = x
				while x1 + 1 < W and cells[Grid.index2(x1 + 1, z)] and not used[Grid.index2(x1 + 1, z)] do
					x1 += 1
				end
				-- растягиваем по Z, пока вся строка свободна
				local z1 = z
				local canGrow = true
				while canGrow and z1 + 1 < D do
					for xx = x, x1 do
						local j = Grid.index2(xx, z1 + 1)
						if not cells[j] or used[j] then
							canGrow = false
							break
						end
					end
					if canGrow then
						z1 += 1
					end
				end
				for zz = z, z1 do
					for xx = x, x1 do
						used[Grid.index2(xx, zz)] = true
					end
				end
				table.insert(rects, { x0 = x, z0 = z, x1 = x1, z1 = z1 })
			end
		end
	end
	return rects
end

-- Поворот двери по стене: полотно вдоль той оси, где по бокам стоят блоки.
-- rot 0/2 — полотно вдоль X (проход по Z), rot 1/3 — полотно вдоль Z (проход по X).
function Grid.autoDoorRot(solid: { [number]: any }, x: number, y: number, z: number, fallback: number): number
	local function at(nx: number, ny: number, nz: number): number
		if Grid.inBounds(nx, ny, nz) and solid[Grid.index(nx, ny, nz)] then
			return 1
		end
		return 0
	end
	local alongX, alongZ = 0, 0
	for dy = 0, 1 do
		alongX += at(x - 1, y + dy, z) + at(x + 1, y + dy, z)
		alongZ += at(x, y + dy, z - 1) + at(x, y + dy, z + 1)
	end
	if alongX > alongZ then
		return if fallback % 2 == 0 then fallback % 4 else 0
	elseif alongZ > alongX then
		return if fallback % 2 == 1 then fallback % 4 else 1
	end
	return fallback % 4
end

-- Поворот хранится как 0..3 (шаги по 90° вокруг Y).
function Grid.normalizeRot(rot: any): number
	if typeof(rot) ~= "number" or rot ~= rot then
		return 0
	end
	return math.floor(rot) % 4
end

-- Сериализация раскладки: "3|id,x,y,z,r;...|x,y,z;..." — высота y считается от поверхности
-- (0 = первый слой над землёй, -1 = верхний слой земли), чтобы сохранения не ломались,
-- если меняется число подземных слоёв.
function Grid.serialize(entries: { Entry }, dug: { number }?): string
	local parts = table.create(#entries)
	for _, e in entries do
		table.insert(parts, string.format("%s,%d,%d,%d,%d", e.id, e.x, e.y - SURFACE, e.z, e.rot))
	end
	local dugParts = {}
	for _, i in dug or {} do
		local x, y, z = Grid.coords(i)
		table.insert(dugParts, string.format("%d,%d,%d", x, y - SURFACE, z))
	end
	return "3|" .. table.concat(parts, ";") .. "|" .. table.concat(dugParts, ";")
end

-- Десериализация с проверкой: неизвестные блоки, выход за границы и пересечения отбрасываются.
-- Возвращает блоки и множество выкопанных клеток. Формат "1" (до подземелья) сдвигается на SURFACE.
function Grid.deserialize(data: any): ({ Entry }, { [number]: boolean })
	local result: { Entry } = {}
	local dug: { [number]: boolean } = {}
	if typeof(data) ~= "string" then
		return result, dug
	end
	local version, rest = string.match(data, "^(%d+)|(.*)$")
	if rest == nil or (version ~= "1" and version ~= "2" and version ~= "3") then
		return result, dug
	end
	local body = rest
	local yShift = 0
	if version == "1" then
		-- до подземелья: y от поверхности
		yShift = SURFACE
	elseif version == "2" then
		-- 3 подземных слоя, выкопанные клетки — индексами
		local OLD_SURFACE = 3
		yShift = SURFACE - OLD_SURFACE
		local entriesPart, dugPart = string.match(rest, "^(.-)|(.*)$")
		if entriesPart == nil or dugPart == nil then
			return result, dug
		end
		body = entriesPart
		for token in string.gmatch(dugPart, "%d+") do
			local i = tonumber(token)
			if i and i >= 1 then
				local x, y, z = Grid.coords(i)
				y += yShift
				if Grid.inBounds(x, y, z) and y < SURFACE then
					dug[Grid.index(x, y, z)] = true
				end
			end
		end
	else
		yShift = SURFACE
		local entriesPart, dugPart = string.match(rest, "^(.-)|(.*)$")
		if entriesPart == nil or dugPart == nil then
			return result, dug
		end
		body = entriesPart
		for sx, sy, sz in string.gmatch(dugPart, "(%-?%d+),(%-?%d+),(%-?%d+)") do
			local x, y, z = tonumber(sx), tonumber(sy), tonumber(sz)
			if x and y and z then
				y += SURFACE
				if Grid.inBounds(x, y, z) and y < SURFACE then
					dug[Grid.index(x, y, z)] = true
				end
			end
		end
	end
	local occupied: { [number]: boolean } = {}
	for chunk in string.gmatch(body, "[^;]+") do
		local id, sx, sy, sz, sr = string.match(chunk, "^([%w_]+),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
		if id and sx and sy and sz and sr then
			local def = Config.Blocks[id]
			local x, y, z, r = tonumber(sx), tonumber(sy), tonumber(sz), tonumber(sr)
			if y then
				y += yShift
			end
			if def and def.Category ~= "Terrain" and x and y and z and r then
				local top = y + def.HeightCells - 1
				if Grid.inBounds(x, y, z) and Grid.inBounds(x, top, z) then
					local cells = Grid.footprint(x, y, z, def.HeightCells)
					local free = true
					for _, c in cells do
						-- под землёй ставить можно только в выкопанные клетки
						local _, cy = Grid.coords(c)
						if occupied[c] or (cy < SURFACE and not dug[c]) then
							free = false
							break
						end
					end
					if free then
						for _, c in cells do
							occupied[c] = true
						end
						table.insert(result, { id = id, x = x, y = y, z = z, rot = Grid.normalizeRot(r) })
					end
				end
			end
		end
	end
	return result, dug
end

-- Подземные клетки, где по умолчанию лежит земля (кроме выкопанных).
function Grid.dirtCells(dug: { [number]: boolean }?): { number }
	local out: { number } = {}
	for y = 0, SURFACE - 1 do
		for z = 0, D - 1 do
			for x = 0, W - 1 do
				local i = Grid.index(x, y, z)
				if not (dug and dug[i]) then
					table.insert(out, i)
				end
			end
		end
	end
	return out
end

-- Подсчёт блоков по типам в раскладке.
function Grid.countBlocks(entries: { Entry }): { [string]: number }
	local counts: { [string]: number } = {}
	for _, e in entries do
		counts[e.id] = (counts[e.id] or 0) + 1
	end
	return counts
end

return Grid
