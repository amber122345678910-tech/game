--!nocheck
-- Юнит-тесты чистой логики (Grid, Prefabs, Config). Запуск: lune run tools/tests/run.luau
local Loader = require("../lib/loader")
local Config = Loader.load("src/shared/Config")
local Grid = Loader.load("src/shared/Grid")
local Prefabs = Loader.load("src/shared/Prefabs")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. "\n  " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

local S = Grid.SURFACE

-- Строит "solid" карту из раскладки (с землёй под участком)
local function solidFrom(entries)
	local solid = {}
	for _, cell in Grid.dirtCells(nil) do
		solid[cell] = true
	end
	for _, e in entries do
		local def = Config.Blocks[e.id]
		for _, c in Grid.footprint(e.x, e.y, e.z, def.HeightCells) do
			solid[c] = e
		end
	end
	return solid
end

test("index/coords roundtrip", function()
	for i = 1, Grid.COUNT do
		local x, y, z = Grid.coords(i)
		truthy(Grid.inBounds(x, y, z), "in bounds " .. i)
		eq(Grid.index(x, y, z), i, "roundtrip " .. i)
	end
	eq(Grid.index(0, 0, 0), 1)
	eq(Grid.index(Grid.W - 1, Grid.H - 1, Grid.D - 1), Grid.COUNT)
end)

test("index2/coords2 roundtrip", function()
	for x = 0, Grid.W - 1 do
		for z = 0, Grid.D - 1 do
			local cx, cz = Grid.coords2(Grid.index2(x, z))
			eq(cx, x)
			eq(cz, z)
		end
	end
end)

test("inBounds rejects fractions and out-of-range", function()
	truthy(not Grid.inBounds(-1, 0, 0))
	truthy(not Grid.inBounds(0, Grid.H, 0))
	truthy(not Grid.inBounds(0.5, 0, 0))
	truthy(not Grid.inBounds(0 / 0, 0, 0))
	truthy(not Grid.inBounds(math.huge, 0, 0))
end)

test("cellCenterLocal / localToCell consistent", function()
	for _, c in { { 0, 0, 0 }, { 5, 3, 7 }, { Grid.W - 1, Grid.H - 1, Grid.D - 1 } } do
		local lx, ly, lz = Grid.cellCenterLocal(c[1], c[2], c[3])
		local x, y, z = Grid.localToCell(lx, ly, lz)
		eq(x, c[1])
		eq(y, c[2])
		eq(z, c[3])
	end
	local lx = Grid.cellCenterLocal(0, 0, 0)
	eq(lx, Grid.ORIGIN_X + Grid.CELL / 2, "first cell center")
	eq(Grid.ORIGIN_X, -24, "grid origin x")
end)

test("empty grid: everything exterior, no interior", function()
	local ext = Grid.computeExterior({})
	eq(Grid.countSet(ext), Grid.COUNT)
	eq(Grid.countSet(Grid.computeInterior({}, ext)), 0)
end)

test("closed box has interior; hole in roof opens it", function()
	local solid = {}
	-- коробка 5x5 снаружи, стены высотой 3, крыша на y=3, внутри 3x3x3
	for y = 0, 3 do
		for x = 3, 7 do
			for z = 3, 7 do
				local edge = x == 3 or x == 7 or z == 3 or z == 7
				if y == 3 or edge then
					solid[Grid.index(x, y, z)] = true
				end
			end
		end
	end
	local interior = Grid.computeInterior(solid)
	eq(Grid.countSet(interior), 27, "3x3x3 interior")
	truthy(interior[Grid.index(5, 0, 5)], "center is interior")
	solid[Grid.index(5, 3, 5)] = nil
	eq(Grid.countSet(Grid.computeInterior(solid)), 0, "roof hole -> no interior")
end)

test("columnTop and isCovered", function()
	local solid = { [Grid.index(2, 0, 2)] = true, [Grid.index(2, 4, 2)] = true }
	eq(Grid.columnTop(solid, 2, 2), 4)
	eq(Grid.columnTop(solid, 3, 3), nil)
	truthy(Grid.isCovered(solid, 2, 1, 2))
	truthy(not Grid.isCovered(solid, 2, 4, 2))
end)

test("greedyRects covers exactly the set", function()
	local cells = {}
	local count = 0
	for x = 0, Grid.W - 1 do
		for z = 0, Grid.D - 1 do
			if not (x >= 3 and x <= 7 and z >= 4 and z <= 8) and (x + z) % 7 ~= 0 then
				cells[Grid.index2(x, z)] = true
				count += 1
			end
		end
	end
	local rects = Grid.greedyRects(cells)
	local covered = {}
	local total = 0
	for _, r in rects do
		for x = r.x0, r.x1 do
			for z = r.z0, r.z1 do
				local i = Grid.index2(x, z)
				truthy(cells[i], "rect covers non-member")
				truthy(not covered[i], "overlap")
				covered[i] = true
				total += 1
			end
		end
	end
	eq(total, count, "coverage")
	-- полный квадрат = 1 прямоугольник
	local full = {}
	for x = 0, Grid.W - 1 do
		for z = 0, Grid.D - 1 do
			full[Grid.index2(x, z)] = true
		end
	end
	eq(#Grid.greedyRects(full), 1, "full rect")
end)

test("serialize/deserialize roundtrip and validation", function()
	local entries = {
		{ id = "wood", x = 0, y = S, z = 0, rot = 0 },
		{ id = "door_iron", x = 5, y = S, z = 2, rot = 3 },
		{ id = "titan", x = 11, y = Grid.H - 1, z = 11, rot = 1 },
		{ id = "stone", x = 4, y = 1, z = 4, rot = 0 }, -- под землёй, в выкопанной клетке
	}
	local s = Grid.serialize(entries, { Grid.index(4, 1, 4), Grid.index(4, 2, 4) })
	local back, dug = Grid.deserialize(s)
	eq(#back, 4)
	truthy(dug[Grid.index(4, 1, 4)] and dug[Grid.index(4, 2, 4)], "dug cells roundtrip")
	eq(#Grid.dirtCells(dug), Grid.W * Grid.D * S - 2, "dirt minus dug")
	-- под землёй в невыкопанной клетке блок не ставится; землю из сохранения не принимаем
	eq(#Grid.deserialize("3|stone,1,-1,1,0;dirt,2,0,2,0|"), 0, "no blocks in solid ground")
	-- старый формат "2" (3 подземных слоя, клетки индексами) переносится на текущую глубину
	local old, oldDug = Grid.deserialize("2|wood,0,3,0,0;stone,4,1,4,0|197")
	eq(#old, 2, "v2 entries kept")
	eq(old[1].y, S, "v2 surface block stays on the surface")
	eq(old[2].y, S - 2, "v2 underground block keeps its depth")
	truthy(oldDug[Grid.index(4, S - 2, 4)], "v2 dug cell moved")
	for i, e in entries do
		eq(back[i].id, e.id)
		eq(back[i].x, e.x)
		eq(back[i].y, e.y)
		eq(back[i].z, e.z)
		eq(back[i].rot, e.rot)
	end
	-- мусор и пересечения отбрасываются
	-- старый формат "1": блоки поднимаются на поверхность
	local junk = "1|wood,0,0,0,0;evil,1,1,1,0;wood,0,0,0,0;wood,99,0,0,0;door_wood,1,9,1,0;stone,2,0,2,7;;garbage"
	local parsed = Grid.deserialize(junk)
	eq(#parsed, 2, "only valid entries")
	eq(parsed[1].y, S, "v1 shifted to surface")
	eq(parsed[2].rot, 3, "rot normalized")
	eq(#Grid.deserialize(nil), 0)
	eq(#Grid.deserialize("9|wood,0,0,0,0|"), 0, "unknown version")
	eq(#Grid.deserialize(""), 0)
end)

test("all prefabs: valid, enclosed, door on boundary, fit grid", function()
	for _, def in Prefabs.List do
		local layout = Prefabs.layout(def.Id)
		local s = Grid.serialize(layout)
		eq(#Grid.deserialize(s), #layout, def.Id .. " roundtrip without drops")
		local solid = solidFrom(layout)
		local interior = Grid.computeInterior(solid)
		eq(Grid.countSet(interior), def.InnerW * def.InnerD * def.WallH + (def.Thickness - 1) * 2, def.Id .. " interior volume")
		local doors = 0
		for _, e in layout do
			if Config.Blocks[e.id].IsDoor then
				doors += 1
				-- клетка за дверью внутри бункера должна быть внутренней (или проёмом)
				local behind = Grid.index(e.x, S, e.z + def.Thickness)
				truthy(interior[behind], def.Id .. " door leads inside")
			end
		end
		eq(doors, 1, def.Id .. " exactly one door")
		truthy(Prefabs.price(def.Id) >= 0)
		if def.Free then
			eq(Prefabs.price(def.Id), 0)
		end
	end
end)

test("prefab prices increase with tier", function()
	local last = -1
	for _, def in Prefabs.List do
		local p = Prefabs.price(def.Id)
		truthy(p > last, def.Id .. " price should increase: " .. p)
		last = p
	end
end)

test("storm params sane for all levels", function()
	for level = 1, Config.Economy.MaxLevel do
		local p = Config.stormParams(level)
		truthy(p.PoolMax > 0 and p.PoolMax < Config.Plot.PitDepth, "pool below rim")
		truthy(p.HailRate > 0 and p.HailRate <= 45)
		truthy(Config.extraDisasterCount(level) >= 1 and Config.extraDisasterCount(level) <= #Config.ExtraDisasters)
		truthy(p.BaseReward > 0)
	end
	eq(Config.stormParams(0).Level, 1, "clamp low")
	eq(Config.stormParams(1e9).Level, Config.Economy.MaxLevel, "clamp high")
	eq(Config.computeReward(1, false, 1, 0), 0, "no reward at zero progress")
	truthy(Config.computeReward(1, true, 1, 1) > Config.computeReward(1, true, 0, 1), "bunker HP bonus")
end)

test("starter shack survives level 1 acid without door leak", function()
	local p = Config.stormParams(1)
	truthy(p.PoolMax <= Config.Blocks.door_wood.Seal, "level 1 pool not above wooden door seal")
	local p3 = Config.stormParams(3)
	truthy(p3.PoolMax > Config.Blocks.door_wood.Seal, "level 3 leaks through wooden door")
	truthy(Config.stormParams(12).PoolMax <= Config.Blocks.door_blast.Seal, "blast door holds max pool")
end)

test("block defs consistent", function()
	for id, def in Config.Blocks do
		eq(def.Id, id, "id matches key")
		truthy(def.HP > 0 and (def.Price > 0 or def.Category == "Terrain"))
		truthy(def.HeightCells == (if def.IsDoor then 2 else 1), id .. " height")
		truthy(#id <= 32)
		truthy(string.match(id, "^[%w_]+$") ~= nil, id .. " serializable id")
	end
	eq(#Config.BlockOrder, 10)
end)

local StormSim = Loader.load("src/shared/StormSim")

local function withDirt()
	local cells = {}
	for _, cell in Grid.dirtCells(nil) do
		local x, y, z = Grid.coords(cell)
		cells[cell] = StormSim.newBlock("dirt", x, y, z, 0)
	end
	return cells
end

local function boxBlocks()
	local cells, records = withDirt(), {}
	for _, e in Prefabs.layout("stone") do
		local b = StormSim.newBlock(e.id, e.x, e.y, e.z, e.rot)
		for _, c in b.cells do
			cells[c] = b
		end
		table.insert(records, b)
	end
	return cells, records
end

test("flood: sealed bunker below door seal does not leak", function()
	local cells, records = boxBlocks()
	local ext = Grid.computeExterior(cells)
	local interior = Grid.computeInterior(cells, ext)
	local doors = StormSim.boundaryDoors(records, interior, cells)
	eq(#doors, 1, "one boundary door")
	local level = 5 -- железная дверь держит 7
	local res = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(level)), level, true, 6.5, 0)
	eq(res.rate, 0, "no leak")
	truthy(not res.breach and not res.roofLeak)
end)

test("flood: roof hole is a roof leak, not a breach", function()
	local cells, records = boxBlocks()
	local interior = Grid.computeInterior(cells)
	local doors = StormSim.boundaryDoors(records, interior, cells)
	-- ломаем один блок крыши
	local roof
	for _, r in records do
		if r.y == S + 3 and not roof and interior[Grid.index(r.x, S + 2, r.z)] then
			roof = r
		end
	end
	StormSim.applyDamage(cells, records, roof, 1e9)
	local ext = Grid.computeExterior(cells)
	local level = 3
	local res = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(level)), level, true, 10, 0)
	truthy(res.roofLeak, "roof leak detected")
	truthy(not res.breach, "not a breach")
	eq(res.rate, Config.Storm.RoofLeakRate, "only rain drips in")
	eq(res.cap, 10 * Config.Storm.RoofLeakCap, "cap from rain amount")
	local resDry = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(level)), level, false, 10, 0)
	eq(resDry.rate, 0, "no rain -> nothing drips")
end)

test("flood: wall hole below acid level is a breach", function()
	local cells, records = boxBlocks()
	local interior = Grid.computeInterior(cells)
	local doors = StormSim.boundaryDoors(records, interior, cells)
	local wall
	for _, r in records do
		if r.y == S and not r.def.IsDoor and not wall then
			for _, d in Grid.NEIGHBORS do
				local nx, ny, nz = r.x + d[1], r.y + d[2], r.z + d[3]
				if Grid.inBounds(nx, ny, nz) and interior[Grid.index(nx, ny, nz)] then
					wall = r
				end
			end
		end
	end
	StormSim.applyDamage(cells, records, wall, 1e9)
	local ext = Grid.computeExterior(cells)
	local res = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(2)), 2, true, 10, 0)
	truthy(res.breach, "breach")
	truthy(res.rate >= Config.Storm.BreachRate)
	eq(res.cap, 2, "fills up to outside level")
	-- та же дыра, но кислоты нет — пробоины нет
	local dry = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(0)), 0, true, 10, 0)
	truthy(not dry.breach, "no acid -> no breach")
end)

test("flood: damaged wooden door leaks more", function()
	local cells, records = withDirt(), {}
	for _, e in Prefabs.layout("starter") do
		local b = StormSim.newBlock(e.id, e.x, e.y, e.z, e.rot)
		for _, c in b.cells do
			cells[c] = b
		end
		table.insert(records, b)
	end
	local ext = Grid.computeExterior(cells)
	local interior = Grid.computeInterior(cells, ext)
	local doors = StormSim.boundaryDoors(records, interior, cells)
	local sub = Grid.computeExteriorBelow(cells, Grid.submergedLayers(4))
	local healthy = StormSim.flood(doors, interior, cells, sub, 4, true, 4, 0)
	truthy(healthy.rate > 0, "4 > seal 3.5 leaks")
	doors[1].hp = doors[1].maxHp * 0.25
	local damaged = StormSim.flood(doors, interior, cells, sub, 4, true, 4, 0)
	truthy(damaged.rate > healthy.rate, "damaged door leaks more")
end)

test("computeExteriorBelow respects layers and ignores sky", function()
	local cells = boxBlocks()
	local below0 = Grid.computeExteriorBelow(cells, S)
	truthy(Grid.countSet(below0) > 0, "surface layer floods")
	for i in below0 do
		local _, y = Grid.coords(i)
		eq(y, S, "only the surface layer (ground is solid)")
	end
	eq(Grid.countSet(Grid.computeExteriorBelow(cells, -1)), 0, "no acid -> empty")
	eq(Grid.submergedLayers(0), -1)
	eq(Grid.submergedLayers(0.1), S)
	eq(Grid.submergedLayers(4), S)
	eq(Grid.submergedLayers(4.01), S + 1)
end)

test("hail player damage: exposed direct hit vs roof tremor", function()
	local p = Config.stormParams(5)
	local cells = boxBlocks()
	-- под открытым небом рядом с ударом
	eq(StormSim.hailPlayerDamage(p, {}, nil, 0, 0, 0, false, 1, 3, 1), p.HailPlayerDamage)
	eq(StormSim.hailPlayerDamage(p, {}, nil, 0, 0, 0, false, 10, 3, 10), 0, "far away")
	-- внутри бункера: удар по крыше рядом даёт немного урона
	local roof = cells[Grid.index(5, S + 3, 5)]
	truthy(roof ~= nil, "roof block exists")
	local lx, _, lz = Grid.cellCenterLocal(5, S, 5)
	local tremor = StormSim.hailPlayerDamage(p, cells, roof, 16, lx, lz, false, lx, 3, lz)
	truthy(tremor > 0 and tremor < p.HailDamage, "tremor is a fraction of block damage")
end)

test("door auto-rotation follows the wall", function()
	local solid = {}
	-- стена вдоль X: блоки слева и справа от двери
	solid[Grid.index(4, 0, 3)] = true
	solid[Grid.index(6, 0, 3)] = true
	solid[Grid.index(4, 1, 3)] = true
	solid[Grid.index(6, 1, 3)] = true
	eq(Grid.autoDoorRot(solid, 5, 0, 3, 1) % 2, 0, "wall along X -> rot 0/2")
	local solid2 = {}
	solid2[Grid.index(3, 0, 4)] = true
	solid2[Grid.index(3, 0, 6)] = true
	eq(Grid.autoDoorRot(solid2, 3, 0, 5, 0) % 2, 1, "wall along Z -> rot 1/3")
	eq(Grid.autoDoorRot({}, 3, 0, 5, 2), 2, "no walls -> keep player's rotation")
end)

test("player in the door recess counts as inside the bunker", function()
	local cells = withDirt()
	local records = {}
	for _, e in Prefabs.layout("starter") do
		local b = StormSim.newBlock(e.id, e.x, e.y, e.z, e.rot)
		for _, c in b.cells do
			cells[c] = b
		end
		table.insert(records, b)
	end
	local interior = Grid.computeInterior(cells)
	local door
	for _, r in records do
		if r.def.IsDoor then
			door = r
		end
	end
	local lx, _, lz = Grid.cellCenterLocal(door.x, door.y, door.z)
	-- изнутри (z больше центра двери, внутренность бункера с +Z)
	local inside = StormSim.playerCellIndex(cells, lx, 3, lz + 1.2)
	truthy(inside and interior[inside], "inner recess is interior")
	local outside = StormSim.playerCellIndex(cells, lx, 3, lz - 1.2)
	truthy(outside and not interior[outside], "outer recess is outside")
	-- урон от уличной лужи у двери изнутри не идёт
	local p = Config.stormParams(1)
	local dmg = StormSim.playerAcidDamage(p, true, cells, interior, lx, 3, lz + 1.2, 2.5, 0, 1)
	eq(dmg, 0, "no outside pool damage inside the recess")
end)

test("inner doors (closet/airlock) are not boundary doors and don't leak", function()
	local cells, records = withDirt(), {}
	local function add(id, x, y, z)
		local b = StormSim.newBlock(id, x, y, z, 0)
		for _, c in b.cells do
			cells[c] = b
		end
		table.insert(records, b)
	end
	for _, e in Prefabs.layout("starter") do
		add(e.id, e.x, e.y, e.z)
	end
	-- дверь внутри комнаты (по бокам внутренность)
	add("door_wood", 5, S, 6)
	local interior = Grid.computeInterior(cells)
	local doors = StormSim.boundaryDoors(records, interior, cells)
	eq(#doors, 1, "only the outer door is a boundary door")
	local level = 4
	local res = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(level)), level, true, 4, 0)
	eq(#res.leaking, 1, "one leaking door")
end)

test("underground room: dug cells under a roof are interior and safe from wind/meteors", function()
	local cells, records = withDirt(), {}
	-- выкапываем 2x2x2 под поверхностью и накрываем крышей на уровне земли
	for x = 4, 5 do
		for z = 4, 5 do
			for y = S - 2, S - 1 do
				cells[Grid.index(x, y, z)] = nil
			end
			local b = StormSim.newBlock("concrete", x, S, z, 0)
			cells[b.cells[1]] = b
			table.insert(records, b)
		end
	end
	local interior = Grid.computeInterior(cells)
	eq(Grid.countSet(interior), 8, "dug room is interior")
	-- открываем крышу — комната становится улицей
	local roof = records[1]
	StormSim.applyDamage(cells, records, roof, 1e9)
	eq(Grid.countSet(Grid.computeInterior(cells)), 0, "open pit is not a bunker")
	-- земля неразрушима
	local dirt = cells[Grid.index(0, 0, 0)]
	truthy(not StormSim.applyDamage(cells, records, dirt, 1e9) and cells[Grid.index(0, 0, 0)] == dirt, "dirt is indestructible")
	-- метеорит останавливается землёй
	local hits = StormSim.meteorHits(cells, 0, 0)
	eq(#hits, 0, "meteor on bare ground hits no blocks")
	-- урон игроку под землёй от урагана и метеорита — ноль
	local p = Config.stormParams(10)
	local lx, _, lz = Grid.cellCenterLocal(5, S - 2, 5)
	local ply = Grid.layerBottom(S - 2) + 3
	eq(StormSim.windPlayerDamage(p, cells, interior, lx, ply, lz, 1), 0, "wind can't reach underground")
end)

test("new disasters: wind hits the windward side, quake hits tall blocks harder", function()
	local cells, records = boxBlocks()
	local interior = Grid.computeInterior(cells)
	local targets = StormSim.windTargets(records, cells, interior, 1, 0)
	truthy(#targets > 0, "wind hits something")
	local minX = math.huge
	for _, r in records do
		minX = math.min(minX, r.x)
	end
	for _, r in targets do
		-- ветер дует в +X: страдает западная стена и крыша сверху не прикрыта с запада
		truthy(r.x == minX or r.y > S, "windward side or above the box")
	end
	local p = Config.stormParams(5)
	local low = StormSim.newBlock("stone", 0, S, 0, 0)
	local high = StormSim.newBlock("stone", 0, S + 4, 0, 0)
	truthy(StormSim.quakeDamage(p, high) > StormSim.quakeDamage(p, low), "higher block shakes more")
	truthy(StormSim.windFactor(Config.Blocks.wood) > StormSim.windFactor(Config.Blocks.titan), "wood blows away easier than titan")
end)

-- Регрессия баланса (та же логика StormSim, что на сервере)
_G.__BALANCE_LIB = true
local Balance = require("./balance")
local function survives(prefab, level)
	local r = Balance.worst(prefab, level)
	return r.survived, r
end
test("balance: starter shack survives level 1 (first experience)", function()
	local ok, r1 = survives("starter", 1)
	truthy(ok, "starter must survive level 1 (hp " .. r1.playerHP .. ")")
	truthy(r1.dmg.hail > 0, "hail should hurt the player a bit through a wooden roof")
	truthy(r1.playerHP > 50, "level 1 should be comfortable")
end)
test("balance: starter shack can't hold level 3 (teaches upgrades)", function()
	local ok = survives("starter", 3)
	truthy(not ok, "starter shack should fall by level 3")
	local _, r2 = survives("starter", 2)
	truthy(r2.firstLeak ~= nil or r2.breach or not r2.survived, "level 2 should already hurt the starter shack")
end)
test("balance: mid and top bunkers", function()
	truthy((survives("stone", 4)), "stone bunker (iron door) survives level 4")
	truthy((survives("concrete", 4)), "concrete bunker survives level 4")
	truthy((survives("steel", 12)), "steel fortress survives level 12")
	truthy((survives("titan", 18)), "titan shelter survives level 18")
end)

print(string.format("Tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
