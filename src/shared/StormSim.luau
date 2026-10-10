--!strict
-- Чистая логика шторма (без Roblox-сервисов): какие блоки бьёт град, что разъедает кислота,
-- как быстро кислота затекает внутрь бункера. Используется сервером (StormService)
-- и тестами баланса (tools/tests), поэтому её можно проверить без запуска Roblox.

local Config = require(script.Parent.Config)
local Grid = require(script.Parent.Grid)

-- Блок на сетке участка (сервер хранит в нём ещё и деталь part).
export type Block = {
	id: string,
	def: Config.BlockDef,
	x: number,
	y: number,
	z: number,
	rot: number,
	hp: number,
	maxHp: number,
	cells: { number },
	alive: boolean,
	part: any,
	tintBucket: number,
}

export type FloodResult = {
	rate: number, -- скорость подъёма кислоты внутри (стады/сек)
	cap: number, -- максимум, до которого может подняться кислота внутри
	leaking: { Block }, -- двери, через которые сейчас течёт
	breach: boolean, -- пробоина ниже уровня кислоты
	roofLeak: boolean, -- дыра выше уровня кислоты (затекает дождь)
}

local StormSim = {}

-- Новый блок (без детали) — для тестов и загрузки.
function StormSim.newBlock(id: string, x: number, y: number, z: number, rot: number): Block
	local def = Config.Blocks[id]
	return {
		id = id,
		def = def,
		x = x,
		y = y,
		z = z,
		rot = rot,
		hp = def.HP,
		maxHp = def.HP,
		cells = Grid.footprint(x, y, z, def.HeightCells),
		alive = true,
		part = nil,
		tintBucket = 4,
	}
end

-- Куда попадёт градина в колонке сетки (cx, cz): верхний блок и высота удара.
function StormSim.hailHit(cells: { [number]: Block }, cx: number, cz: number): (Block?, number)
	local top = Grid.columnTop(cells, cx, cz)
	if top then
		return cells[Grid.index(cx, top, cz)], Grid.layerBottom(top + 1)
	end
	return nil, Grid.layerBottom(0)
end

-- Верхние блоки всех колонок, которые разъедает кислотный дождь.
function StormSim.rainTargets(cells: { [number]: Block }): { Block }
	local targets: { Block } = {}
	for x = 0, Grid.W - 1 do
		for z = 0, Grid.D - 1 do
			local top = Grid.columnTop(cells, x, z)
			if top then
				local rec = cells[Grid.index(x, top, z)]
				if rec and rec.def.AcidMult > 0 then
					table.insert(targets, rec)
				end
			end
		end
	end
	return targets
end

-- Затопленные блоки, которые касаются кислоты снаружи (лужа поднимается до level).
function StormSim.poolTargets(records: { Block }, exterior: { [number]: boolean }, level: number): { Block }
	local targets: { Block } = {}
	if level <= 0 then
		return targets
	end
	for _, rec in records do
		if rec.alive and rec.def.AcidMult > 0 and Grid.layerBottom(rec.y) < level then
			local wet = false
			for _, cell in rec.cells do
				local x, y, z = Grid.coords(cell)
				if Grid.layerBottom(y) < level then
					for _, d in Grid.NEIGHBORS do
						local nx, ny, nz = x + d[1], y + d[2], z + d[3]
						if ny >= 0 and ny < Grid.H then
							if nx < 0 or nx >= Grid.W or nz < 0 or nz >= Grid.D then
								-- край сетки над землёй = поле котлована, там тоже кислота
								wet = ny >= Grid.SURFACE
							elseif Grid.layerBottom(ny) < level and exterior[Grid.index(nx, ny, nz)] then
								wet = true
							end
						end
						if wet then
							break
						end
					end
				end
				if wet then
					break
				end
			end
			if wet then
				table.insert(targets, rec)
			end
		end
	end
	return targets
end

-- Двери, отделяющие внутренний объём бункера от улицы: с одной стороны (по горизонтали)
-- внутренность, с другой — улица (пустая не внутренняя клетка или край сетки).
-- Внутренние двери (тамбур, чулан) не считаются — у них внутренность с обеих сторон.
function StormSim.boundaryDoors(records: { Block }, interior: { [number]: boolean }, cells: { [number]: Block }): { Block }
	local doors: { Block } = {}
	for _, rec in records do
		if rec.def.IsDoor then
			local touchesInside, touchesOutside = false, false
			for _, cell in rec.cells do
				local x, y, z = Grid.coords(cell)
				for _, d in Grid.NEIGHBORS do
					if d[2] == 0 then
						local nx, nz = x + d[1], z + d[3]
						if not Grid.inBounds(nx, y, nz) then
							touchesOutside = true -- край сетки = поле котлована
						else
							local i = Grid.index(nx, y, nz)
							if interior[i] then
								touchesInside = true
							elseif cells[i] == nil then
								touchesOutside = true
							end
						end
					end
				end
			end
			if touchesInside and touchesOutside then
				table.insert(doors, rec)
			end
		end
	end
	return doors
end

-- С какой стороны двери улица: есть ли у двери соседняя клетка, куда дотекает лужа.
local function doorFacesPool(rec: Block, submerged: { [number]: boolean }, level: number): boolean
	for _, cell in rec.cells do
		local x, y, z = Grid.coords(cell)
		if Grid.layerBottom(y) < level then
			for _, d in Grid.NEIGHBORS do
				if d[2] == 0 then
					local nx, nz = x + d[1], z + d[3]
					local outside = not Grid.inBounds(nx, y, nz) and y >= Grid.SURFACE
					if outside or (Grid.inBounds(nx, y, nz) and submerged[Grid.index(nx, y, nz)]) then
						return true
					end
				end
			end
		end
	end
	return false
end
StormSim.doorFacesPool = doorFacesPool

-- Насколько дверь сейчас держит кислоту (повреждённая держит хуже).
function StormSim.doorSeal(rec: Block): number
	local frac = math.max(rec.hp, 0) / rec.maxHp
	return rec.def.Seal * math.sqrt(frac)
end

-- Скорость затопления бункера.
-- interior — внутренние клетки на начало шторма;
-- cells — текущие блоки (для поиска дыр в крыше);
-- submerged — внешние клетки, куда дотекает лужа (Grid.computeExteriorBelow).
function StormSim.flood(
	doors: { Block },
	interior: { [number]: boolean },
	cells: { [number]: Block },
	submerged: { [number]: boolean },
	level: number,
	acidRaining: boolean,
	poolMax: number,
	interiorBottom: number
): FloodResult
	local S = Config.Storm
	local rate = 0
	local cap = 0
	local leaking: { Block } = {}
	for _, rec in doors do
		if rec.alive and doorFacesPool(rec, submerged, level) then
			local excess = level - Grid.layerBottom(rec.y) - StormSim.doorSeal(rec)
			if excess > 0 then
				rate += excess * S.DoorLeakFactor
				cap = level
				table.insert(leaking, rec)
			end
		end
	end
	local breach, roofLeak = false, false
	local checkedColumns: { [number]: boolean } = {}
	for cell in interior do
		if submerged[cell] then
			breach = true
		end
		-- дождь капает внутрь, только если над внутренним пространством открыто небо
		local x, y, z = Grid.coords(cell)
		local column = Grid.index2(x, z)
		if not roofLeak and not checkedColumns[column] then
			checkedColumns[column] = true
			if not Grid.isCovered(cells, x, y, z) then
				roofLeak = true
			end
		end
		if breach and roofLeak then
			break
		end
	end
	if breach then
		-- пробоина ниже уровня лужи: кислота хлынет внутрь
		rate += S.BreachRate
		cap = level
	end
	if roofLeak and acidRaining then
		-- дыра выше лужи: внутрь капает только дождь
		rate += S.RoofLeakRate
		cap = math.max(cap, interiorBottom + poolMax * S.RoofLeakCap)
	end
	return { rate = rate, cap = cap, leaking = leaking, breach = breach, roofLeak = roofLeak }
end

-- Урон игроку от одной градины.
-- Под открытым небом — прямое попадание рядом; под крышей — часть удара по крыше рядом с игроком.
function StormSim.hailPlayerDamage(
	p: Config.StormParams,
	cells: { [number]: Block },
	hitRec: Block?,
	impactY: number,
	hlx: number,
	hlz: number,
	big: boolean,
	plx: number,
	ply: number,
	plz: number
): number
	local covered = StormSim.isCovered(cells, plx, ply, plz)
	local dx, dz = plx - hlx, plz - hlz
	local dist = math.sqrt(dx * dx + dz * dz)
	if not covered then
		local radius = p.HailHitRadius * (if big then 1.5 else 1)
		if dist <= radius and ply + 3 >= impactY then
			return p.HailPlayerDamage * (if big then 2 else 1)
		end
		return 0
	end
	local tremor = Config.Storm.HailTremorRadius
	if hitRec and dist <= tremor and impactY >= ply then
		local damage = p.HailDamage * (if big then p.HailBigMult else 1)
		return damage * hitRec.def.HailTransfer * (1 - dist / (tremor + 1))
	end
	return 0
end

-- Урон игроку от кислоты за шаг dt. Возвращает урон и его источник.
function StormSim.playerAcidDamage(
	p: Config.StormParams,
	acidRaining: boolean,
	cells: { [number]: Block },
	interior: { [number]: boolean },
	plx: number,
	ply: number,
	plz: number,
	pool: number,
	inside: number,
	dt: number
): (number, string?)
	local S = Config.Storm
	local total = 0
	local kind: string? = nil
	local feet = ply - 3
	if acidRaining and not StormSim.isCovered(cells, plx, ply, plz) then
		total += p.AcidRainPlayerDps * dt
		kind = "rain"
	end
	local cell = StormSim.playerCellIndex(cells, plx, ply, plz)
	local inBunker = cell ~= nil and interior[cell] == true
	if inBunker then
		if inside - feet > S.InsideDamageDepth then
			total += p.InsidePlayerDps * dt
			kind = "inside"
		end
	elseif pool - feet > 0.5 then
		total += p.PoolPlayerDps * dt
		kind = "pool"
	end
	return total, kind
end

-- Клетка игрока по локальной позиции корня персонажа (корень ~3 стада над полом).
function StormSim.playerCell(lx: number, ly: number, lz: number): (number, number, number)
	return Grid.localToCell(lx, ly - 1.5, lz)
end

-- Индекс клетки игрока с учётом ниши двери: полотно стоит посередине клетки, поэтому
-- игрок у двери изнутри относится к соседней внутренней клетке, а снаружи — к внешней.
function StormSim.playerCellIndex(cells: { [number]: Block }, lx: number, ly: number, lz: number): number?
	local cx, cy, cz = StormSim.playerCell(lx, ly, lz)
	cy = math.max(cy, 0)
	if not Grid.inBounds(cx, cy, cz) then
		return nil
	end
	local index = Grid.index(cx, cy, cz)
	local rec = cells[index]
	if rec and rec.def.IsDoor then
		local clx, _, clz = Grid.cellCenterLocal(rec.x, rec.y, rec.z)
		local dx, dz = 0, 0
		if rec.rot % 2 == 0 then
			dz = if lz >= clz then 1 else -1
		else
			dx = if lx >= clx then 1 else -1
		end
		if Grid.inBounds(cx + dx, cy, cz + dz) then
			return Grid.index(cx + dx, cy, cz + dz)
		end
	end
	return index
end

-- Накрыт ли игрок блоками сверху. Вне сетки (поля котлована) — не накрыт.
function StormSim.isCovered(cells: { [number]: Block }, lx: number, ly: number, lz: number): (boolean, number?, number?)
	local cx, cy, cz = StormSim.playerCell(lx, ly, lz)
	if cx < 0 or cx >= Grid.W or cz < 0 or cz >= Grid.D then
		return false, nil, nil
	end
	return Grid.isCovered(cells, cx, math.max(cy, 0), cz), cx, cz
end

-- Урон блоку без побочных эффектов (для тестов). Возвращает true, если блок разрушен.
function StormSim.applyDamage(cells: { [number]: Block }, records: { Block }, rec: Block, amount: number): boolean
	if not rec.alive or amount <= 0 or rec.def.Indestructible then
		return false
	end
	rec.hp -= amount
	if rec.hp > 0 then
		return false
	end
	rec.alive = false
	for _, c in rec.cells do
		if cells[c] == rec then
			cells[c] = nil
		end
	end
	local i = table.find(records, rec)
	if i then
		table.remove(records, i)
	end
	return true
end

----------------------------------------------------------------------
-- Новые бедствия
----------------------------------------------------------------------

-- Насколько материал "лёгкий" для урагана (дерево и стекло сдувает сильнее, титан почти нет).
function StormSim.windFactor(def: Config.BlockDef): number
	return math.clamp(100 / def.HP, 0.2, 1.5)
end

-- Ураган дует в направлении (dx, dz): страдают наземные блоки, у которых с наветренной стороны
-- пусто (улица или край сетки). Подземные блоки и стены, прикрытые соседями, не страдают.
function StormSim.windTargets(
	records: { Block },
	cells: { [number]: Block },
	interior: { [number]: boolean },
	dx: number,
	dz: number
): { Block }
	local targets: { Block } = {}
	for _, rec in records do
		if rec.alive and not rec.def.Indestructible and rec.y >= Grid.SURFACE then
			for _, cell in rec.cells do
				local x, y, z = Grid.coords(cell)
				local wx, wz = x - dx, z - dz -- откуда дует ветер
				local exposed = false
				if not Grid.inBounds(wx, y, wz) then
					exposed = true
				else
					local i = Grid.index(wx, y, wz)
					exposed = cells[i] == nil and not interior[i]
				end
				if exposed then
					table.insert(targets, rec)
					break
				end
			end
		end
	end
	return targets
end

-- Урон урагана игроку: под открытым небом на поверхности (в бункере и под землёй безопасно).
function StormSim.windPlayerDamage(
	p: Config.StormParams,
	cells: { [number]: Block },
	interior: { [number]: boolean },
	plx: number,
	ply: number,
	plz: number,
	dt: number
): number
	local _, cy = StormSim.playerCell(plx, ply, plz)
	if cy < Grid.SURFACE then
		return 0
	end
	local cell = StormSim.playerCellIndex(cells, plx, ply, plz)
	if cell and interior[cell] then
		return 0
	end
	return p.WindPlayerDps * dt
end

-- Землетрясение: чем выше блок над землёй, тем сильнее трясёт; подземные почти не страдают.
function StormSim.quakeDamage(p: Config.StormParams, rec: Block): number
	if rec.def.Indestructible then
		return 0
	end
	if rec.y < Grid.SURFACE then
		return p.QuakeDps * 0.2
	end
	return p.QuakeDps * (1 + 0.25 * (rec.y - Grid.SURFACE))
end

export type MeteorHit = { rec: Block, mult: number }

-- Метеорит в колонку (cx, cz): верхний блок получает полный урон, два блока под ним —
-- половину и четверть (пробивает крышу), верхние блоки соседних колонок — 40%.
-- Земля останавливает метеорит. Возвращает поражённые блоки и высоту удара.
function StormSim.meteorHits(cells: { [number]: Block }, cx: number, cz: number): ({ MeteorHit }, number)
	local hits: { MeteorHit } = {}
	local seen: { [Block]: boolean } = {}
	local function add(rec: Block, mult: number)
		if not seen[rec] and not rec.def.Indestructible then
			seen[rec] = true
			table.insert(hits, { rec = rec, mult = mult })
		end
	end
	local top = Grid.columnTop(cells, cx, cz)
	local impactY = Grid.layerBottom(0)
	if top then
		impactY = Grid.layerBottom(top + 1)
		local mults = { 1, 0.5, 0.25 }
		local depth = 1
		local y = top
		while y >= 0 and depth <= #mults do
			local rec = cells[Grid.index(cx, y, cz)]
			if rec then
				if rec.def.Indestructible then
					break
				end
				if not seen[rec] then
					add(rec, mults[depth])
					depth += 1
				end
			end
			y -= 1
		end
	end
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local nx, nz = cx + d[1], cz + d[2]
		if nx >= 0 and nx < Grid.W and nz >= 0 and nz < Grid.D then
			local nTop = Grid.columnTop(cells, nx, nz)
			if nTop then
				local rec = cells[Grid.index(nx, nTop, nz)]
				if rec then
					add(rec, 0.4)
				end
			end
		end
	end
	return hits, impactY
end

-- Урон игроку от метеорита: взрыв рядом. Под крышей — гораздо меньше, под землёй — ничего.
function StormSim.meteorPlayerDamage(
	p: Config.StormParams,
	cells: { [number]: Block },
	mlx: number,
	mlz: number,
	impactY: number,
	plx: number,
	ply: number,
	plz: number
): number
	local radius = Config.Storm.MeteorRadius
	local dx, dz = plx - mlx, plz - mlz
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist > radius then
		return 0
	end
	local falloff = 1 - dist / (radius + 1)
	local covered = StormSim.isCovered(cells, plx, ply, plz)
	if not covered then
		return p.MeteorPlayerDamage * falloff
	end
	local _, cy = StormSim.playerCell(plx, ply, plz)
	if cy < Grid.SURFACE then
		return 0
	end
	if impactY >= ply then
		return p.MeteorPlayerDamage * 0.25 * falloff
	end
	return 0
end

return StormSim
