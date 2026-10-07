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

-- Строит "solid" карту из раскладки
local function solidFrom(entries)
	local solid = {}
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
		{ id = "wood", x = 0, y = 0, z = 0, rot = 0 },
		{ id = "door_iron", x = 5, y = 0, z = 2, rot = 3 },
		{ id = "titan", x = 11, y = 9, z = 11, rot = 1 },
	}
	local s = Grid.serialize(entries)
	local back = Grid.deserialize(s)
	eq(#back, 3)
	for i, e in entries do
		eq(back[i].id, e.id)
		eq(back[i].x, e.x)
		eq(back[i].y, e.y)
		eq(back[i].z, e.z)
		eq(back[i].rot, e.rot)
	end
	-- мусор и пересечения отбрасываются
	local junk = "1|wood,0,0,0,0;evil,1,1,1,0;wood,0,0,0,0;wood,99,0,0,0;door_wood,1,9,1,0;stone,2,0,2,7;;garbage"
	local parsed = Grid.deserialize(junk)
	eq(#parsed, 2, "only valid entries")
	eq(parsed[2].rot, 3, "rot normalized")
	eq(#Grid.deserialize(nil), 0)
	eq(#Grid.deserialize("2|wood,0,0,0,0"), 0, "unknown version")
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
				local behind = Grid.index(e.x, 0, e.z + def.Thickness)
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
		truthy(p.HailRate > 0 and p.HailRate <= 40)
		truthy(p.BaseReward > 0)
	end
	eq(Config.stormParams(0).Level, 1, "clamp low")
	eq(Config.stormParams(1e9).Level, Config.Economy.MaxLevel, "clamp high")
	eq(Config.computeReward(1, false, 1, 0), 0, "no reward at zero progress")
	truthy(Config.computeReward(1, true, 1, 1) > Config.computeReward(1, true, 0, 1), "bunker HP bonus")
end)

test("starter shack survives level 1 acid without door leak", function()
	local p = Config.stormParams(1)
	truthy(p.PoolMax < Config.Blocks.door_wood.Seal, "level 1 pool below wooden door seal")
	local p3 = Config.stormParams(3)
	truthy(p3.PoolMax > Config.Blocks.door_wood.Seal, "level 3 leaks through wooden door")
	truthy(Config.stormParams(12).PoolMax <= Config.Blocks.door_blast.Seal, "blast door holds max pool")
end)

test("block defs consistent", function()
	for id, def in Config.Blocks do
		eq(def.Id, id, "id matches key")
		truthy(def.HP > 0 and def.Price > 0)
		truthy(def.HeightCells == (if def.IsDoor then 2 else 1), id .. " height")
		truthy(#id <= 32)
		truthy(string.match(id, "^[%w_]+$") ~= nil, id .. " serializable id")
	end
	eq(#Config.BlockOrder, 10)
end)

local StormSim = Loader.load("src/shared/StormSim")

local function boxBlocks()
	local cells, records = {}, {}
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
	local doors = StormSim.boundaryDoors(records, interior)
	eq(#doors, 1, "one boundary door")
	local level = 5 -- железная дверь держит 7
	local res = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(level)), level, true, 6.5)
	eq(res.rate, 0, "no leak")
	truthy(not res.breach and not res.roofLeak)
end)

test("flood: roof hole is a roof leak, not a breach", function()
	local cells, records = boxBlocks()
	local interior = Grid.computeInterior(cells)
	local doors = StormSim.boundaryDoors(records, interior)
	-- ломаем один блок крыши
	local roof
	for _, r in records do
		if r.y == 3 and not roof and interior[Grid.index(r.x, 2, r.z)] then
			roof = r
		end
	end
	StormSim.applyDamage(cells, records, roof, 1e9)
	local ext = Grid.computeExterior(cells)
	local level = 3
	local res = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(level)), level, true, 10)
	truthy(res.roofLeak, "roof leak detected")
	truthy(not res.breach, "not a breach")
	eq(res.rate, Config.Storm.RoofLeakRate, "only rain drips in")
	eq(res.cap, 10 * Config.Storm.RoofLeakCap, "cap from rain amount")
	local resDry = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(level)), level, false, 10)
	eq(resDry.rate, 0, "no rain -> nothing drips")
end)

test("flood: wall hole below acid level is a breach", function()
	local cells, records = boxBlocks()
	local interior = Grid.computeInterior(cells)
	local doors = StormSim.boundaryDoors(records, interior)
	local wall
	for _, r in records do
		if r.y == 0 and not r.def.IsDoor and not wall then
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
	local res = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(2)), 2, true, 10)
	truthy(res.breach, "breach")
	truthy(res.rate >= Config.Storm.BreachRate)
	eq(res.cap, 2, "fills up to outside level")
	-- та же дыра, но кислоты нет — пробоины нет
	local dry = StormSim.flood(doors, interior, cells, Grid.computeExteriorBelow(cells, Grid.submergedLayers(0)), 0, true, 10)
	truthy(not dry.breach, "no acid -> no breach")
end)

test("flood: damaged wooden door leaks more", function()
	local cells, records = {}, {}
	for _, e in Prefabs.layout("starter") do
		local b = StormSim.newBlock(e.id, e.x, e.y, e.z, e.rot)
		for _, c in b.cells do
			cells[c] = b
		end
		table.insert(records, b)
	end
	local ext = Grid.computeExterior(cells)
	local interior = Grid.computeInterior(cells, ext)
	local doors = StormSim.boundaryDoors(records, interior)
	local sub = Grid.computeExteriorBelow(cells, Grid.submergedLayers(3.5))
	local healthy = StormSim.flood(doors, interior, cells, sub, 3.5, true, 3.5)
	truthy(healthy.rate > 0, "3.5 > seal 3 leaks")
	doors[1].hp = doors[1].maxHp * 0.25
	local damaged = StormSim.flood(doors, interior, cells, sub, 3.5, true, 3.5)
	truthy(damaged.rate > healthy.rate, "damaged door leaks more")
end)

test("computeExteriorBelow respects layers and ignores sky", function()
	local cells = boxBlocks()
	local below0 = Grid.computeExteriorBelow(cells, 0)
	for i in below0 do
		local _, y = Grid.coords(i)
		eq(y, 0, "only layer 0")
	end
	eq(Grid.countSet(Grid.computeExteriorBelow(cells, -1)), 0, "no acid -> empty")
	eq(Grid.submergedLayers(0), -1)
	eq(Grid.submergedLayers(0.1), 0)
	eq(Grid.submergedLayers(4), 0)
	eq(Grid.submergedLayers(4.01), 1)
end)

test("hail player damage: exposed direct hit vs roof tremor", function()
	local p = Config.stormParams(5)
	local cells = boxBlocks()
	-- под открытым небом рядом с ударом
	eq(StormSim.hailPlayerDamage(p, {}, nil, 0, 0, 0, false, 1, 3, 1), p.HailPlayerDamage)
	eq(StormSim.hailPlayerDamage(p, {}, nil, 0, 0, 0, false, 10, 3, 10), 0, "far away")
	-- внутри бункера: удар по крыше рядом даёт немного урона
	local roof = cells[Grid.index(5, 3, 5)]
	truthy(roof ~= nil, "roof block exists")
	local lx, _, lz = Grid.cellCenterLocal(5, 0, 5)
	local tremor = StormSim.hailPlayerDamage(p, cells, roof, 16, lx, lz, false, lx, 3, lz)
	truthy(tremor > 0 and tremor < p.HailDamage, "tremor is a fraction of block damage")
end)

-- Регрессия баланса (та же логика StormSim, что на сервере)
_G.__BALANCE_LIB = true
local Balance = require("./balance")
local function survives(prefab, level)
	local r = Balance.worst(prefab, level)
	return r.survived, r
end
test("balance: starter shack survives levels 1-2 (first experience)", function()
	for level = 1, 2 do
		local ok, r = survives("starter", level)
		truthy(ok, "starter must survive level " .. level .. " (hp " .. r.playerHP .. ")")
	end
	local _, r1 = survives("starter", 1)
	truthy(r1.dmg.hail > 0, "hail should hurt the player a bit through a wooden roof")
	truthy(r1.playerHP > 50, "level 1 should be comfortable")
end)
test("balance: wooden door leaks by level 3 (teaches door upgrade)", function()
	local _, r = survives("starter", 3)
	truthy(r.firstLeak ~= nil, "wooden door should leak at level 3")
end)
test("balance: mid and top bunkers", function()
	truthy((survives("stone", 5)), "stone bunker (iron door) survives level 5")
	truthy((survives("concrete", 6)), "concrete bunker survives level 6")
	truthy((survives("steel", 12)), "steel fortress survives level 12")
	truthy((survives("titan", 18)), "titan shelter survives level 18")
end)

print(string.format("Tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
