--!nocheck
-- Симуляция баланса: каждый готовый бункер против штормов разных уровней.
-- Использует ту же логику (StormSim), что и сервер. Игрок стоит в центре бункера.
-- Запуск: lune run tools/tests/balance.luau [--quiet]
local process = require("@lune/process")
local Loader = require("../lib/loader")
local Config = Loader.load("src/shared/Config")
local Grid = Loader.load("src/shared/Grid")
local Prefabs = Loader.load("src/shared/Prefabs")
local StormSim = Loader.load("src/shared/StormSim")

local quiet = table.find(process.args, "--quiet") ~= nil or _G.__BALANCE_LIB == true
local S = Config.Storm
local PIT = Config.Plot.PitHalfSize

local Balance = {}

local function lcg(seed)
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

-- Постройка готового бункера на земле участка.
function Balance.build(prefabId: string)
	local cells, records = {}, {}
	for _, cell in Grid.dirtCells(nil) do
		local x, y, z = Grid.coords(cell)
		cells[cell] = StormSim.newBlock("dirt", x, y, z, 0)
	end
	for _, e in Prefabs.layout(prefabId) do
		local b = StormSim.newBlock(e.id, e.x, e.y, e.z, e.rot)
		for _, c in b.cells do
			cells[c] = b
		end
		table.insert(records, b)
	end
	return cells, records
end

-- Фазы шторма как на сервере; дополнительные бедствия выбираются по сиду.
function Balance.phases(level: number, seed: number)
	local n = Config.extraDisasterCount(level)
	local extras = {}
	local list = Config.ExtraDisasters
	for i = 1, n do
		extras[list[(seed + i - 1) % #list + 1]] = true
	end
	local phases = { { "Prep", S.PrepTime }, { "Hail", S.HailTime } }
	if extras.Wind then
		table.insert(phases, { "Wind", S.WindTime })
	end
	if extras.Meteor then
		table.insert(phases, { "Meteor", S.MeteorTime })
	end
	table.insert(phases, { "Calm", S.CalmTime })
	table.insert(phases, { "Acid", S.AcidTime })
	if extras.Quake then
		table.insert(phases, { "Quake", S.QuakeTime })
	end
	table.insert(phases, { "Clear", S.ClearTime })
	return phases
end

local WIND_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Balance.simulate(prefabId: string, level: number, seed: number)
	local cells, records = Balance.build(prefabId)
	local exterior = Grid.computeExterior(cells)
	local interior = Grid.computeInterior(cells, exterior)
	local doors = StormSim.boundaryDoors(records, interior, cells)
	local startHP = 0
	for _, r in records do
		startHP += r.maxHp
	end
	local interiorBottom = 0
	-- игрок в центре внутреннего пространства на полу
	local best, bestD = nil, math.huge
	for cell in interior do
		local x, y, z = Grid.coords(cell)
		if y == Grid.SURFACE then
			local lx, _, lz = Grid.cellCenterLocal(x, y, z)
			local d = lx * lx + lz * lz
			if d < bestD then
				best, bestD = { lx, lz }, d
			end
		end
	end
	assert(best, prefabId .. " has no floor interior")
	local plx, ply, plz = best[1], Grid.layerBottom(Grid.SURFACE) + 3, best[2]
	local playerHP = 100

	local p = Config.stormParams(level)
	local rand = lcg(seed)
	local dt = 0.25
	local t = 0
	local phases = Balance.phases(level, seed)
	local wind = WIND_DIRS[seed % 4 + 1]
	local pending = {}
	local budget, meteorBudget = 0, 0
	local pool, inside = 0, interiorBottom
	local maxInside = 0
	local tick = 0
	local firstLeak = nil
	local breachSeen = false
	local dmg = { hail = 0, rain = 0, inside = 0, pool = 0, wind = 0, meteor = 0 }

	local function hurt(kind, amount)
		playerHP -= amount
		dmg[kind] += amount
	end

	local function applyHail(h)
		local cx, _, cz = Grid.localToCell(h.lx, 0, h.lz)
		if h.meteor then
			local impactY = 0
			if Grid.inBounds(cx, 0, cz) then
				local hits
				hits, impactY = StormSim.meteorHits(cells, cx, cz)
				for _, hit in hits do
					StormSim.applyDamage(cells, records, hit.rec, p.MeteorDamage * hit.mult)
				end
			end
			hurt("meteor", StormSim.meteorPlayerDamage(p, cells, h.lx, h.lz, impactY, plx, ply, plz))
			return
		end
		local damage = p.HailDamage * (if h.big then p.HailBigMult else 1)
		local hitRec, impactY = nil, 0
		if Grid.inBounds(cx, 0, cz) then
			local rec, y = StormSim.hailHit(cells, cx, cz)
			impactY = y
			if rec then
				hitRec = rec
				StormSim.applyDamage(cells, records, rec, damage)
			end
		end
		hurt("hail", StormSim.hailPlayerDamage(p, cells, hitRec, impactY, h.lx, h.lz, h.big, plx, ply, plz))
	end

	for _, ph in phases do
		local name, duration = ph[1], ph[2]
		local pt = 0
		tick = 0
		while pt < duration and playerHP > 0 do
			pt += dt
			t += dt
			if name == "Hail" then
				budget += p.HailRate * dt
				while budget >= 1 do
					budget -= 1
					local lx = -PIT + 1 + rand() * (2 * PIT - 2)
					local lz = -PIT + 1 + rand() * (2 * PIT - 2)
					table.insert(pending, { t = t + S.FallTime, lx = lx, lz = lz, big = rand() < p.HailBigChance })
				end
			elseif name == "Meteor" then
				meteorBudget += p.MeteorRate * dt
				while meteorBudget >= 1 do
					meteorBudget -= 1
					local half = -Grid.ORIGIN_X + 4
					local lx = -half + rand() * 2 * half
					local lz = -half + rand() * 2 * half
					table.insert(pending, { t = t + S.MeteorFallTime, lx = lx, lz = lz, big = true, meteor = true })
				end
			end
			local i = 1
			while i <= #pending do
				if pending[i].t <= t then
					applyHail(table.remove(pending, i))
				else
					i += 1
				end
			end
			if name == "Wind" or name == "Quake" then
				tick += dt
				if tick >= 1 then
					tick -= 1
					if name == "Wind" then
						for _, rec in StormSim.windTargets(records, cells, interior, wind[1], wind[2]) do
							StormSim.applyDamage(cells, records, rec, p.WindDps * StormSim.windFactor(rec.def))
						end
					else
						for _, rec in table.clone(records) do
							StormSim.applyDamage(cells, records, rec, StormSim.quakeDamage(p, rec))
						end
					end
				end
			end
			if name == "Wind" then
				local amount = StormSim.windPlayerDamage(p, cells, interior, plx, ply, plz, dt)
				if amount > 0 then
					hurt("wind", amount)
				end
			end
			if name == "Acid" or name == "Quake" then
				local raining = name == "Acid"
				if raining then
					pool = p.PoolMax * math.clamp(pt / p.PoolRiseTime, 0, 1)
				else
					pool = math.max(0, pool - S.QuakeDrainRate * dt)
				end
				if name == "Acid" then
					tick += dt
				end
				if tick >= 1 and raining then
					tick -= 1
					for _, rec in StormSim.rainTargets(cells) do
						StormSim.applyDamage(cells, records, rec, p.AcidRainDps * rec.def.AcidMult)
					end
				end
				if raining and pt % 1 < dt or (not raining and pt % 1 < dt) then
					for _, rec in StormSim.poolTargets(records, Grid.computeExteriorBelow(cells, Grid.submergedLayers(pool)), pool) do
						StormSim.applyDamage(cells, records, rec, p.PoolDps * rec.def.AcidMult)
					end
				end
				local sub = Grid.computeExteriorBelow(cells, Grid.submergedLayers(pool))
				local res = StormSim.flood(doors, interior, cells, sub, pool, raining, p.PoolMax, interiorBottom)
				if res.rate > 0 and inside < res.cap then
					inside = math.min(res.cap, inside + res.rate * dt)
				end
				if #res.leaking > 0 and not firstLeak then
					firstLeak = t
				end
				breachSeen = breachSeen or res.breach
				maxInside = math.max(maxInside, inside)
				-- урон игроку
				local amount, kind = StormSim.playerAcidDamage(p, raining, cells, interior, plx, ply, plz, pool, inside, dt)
				if amount > 0 then
					hurt(kind or "rain", amount)
				end
			elseif name == "Clear" then
				pool = math.max(0, pool - S.DrainRate * dt)
				inside = math.max(interiorBottom, inside - S.DrainRate * dt)
			end
		end
	end
	local hpNow = 0
	for _, r in records do
		hpNow += math.max(r.hp, 0)
	end
	return {
		survived = playerHP > 0,
		playerHP = math.max(0, playerHP),
		bunker = hpNow / startHP,
		maxInside = maxInside,
		firstLeak = firstLeak,
		breach = breachSeen,
		dmg = dmg,
	}
end

-- Наихудший из нескольких сидов
function Balance.worst(prefabId, level)
	local worst
	for seed = 1, 3 do
		local r = Balance.simulate(prefabId, level, seed * 7919)
		if not worst or r.playerHP < worst.playerHP then
			worst = r
		end
	end
	return worst
end

-- Таблица результатов: prefab -> level -> result (уровни 1..maxLevel)
function Balance.table(maxLevel)
	local out = {}
	for _, def in Prefabs.List do
		out[def.Id] = {}
		for level = 1, maxLevel do
			out[def.Id][level] = Balance.worst(def.Id, level)
		end
	end
	return out
end

-- Максимальный уровень подряд, который бункер проходит
function Balance.maxLevel(results)
	local maxOk = 0
	for level, r in results do
		if r.survived and level == maxOk + 1 then
			maxOk = level
		end
	end
	return maxOk
end

if not quiet then
	local results = Balance.table(18)
	print(string.format("%-9s | %-5s | %s", "bunker", "price", "level: playerHP/bunker% [L=leak B=breach]"))
	for _, def in Prefabs.List do
		local line = {}
		for level, r in results[def.Id] do
			local flags = (if r.firstLeak then "L" else "") .. (if r.breach then "B" else "")
			table.insert(line, string.format("%d:%s%d/%d%s", level, if r.survived then "" else "x", math.floor(r.playerHP), math.floor(r.bunker * 100), flags))
		end
		print(string.format("%-9s | %-5d | max %2d | %s", def.Id, Prefabs.price(def.Id), Balance.maxLevel(results[def.Id]), table.concat(line, " ")))
	end
	local r1 = results.starter[1]
	print(string.format("starter L1 damage: hail %.1f rain %.1f inside %.1f pool %.1f", r1.dmg.hail, r1.dmg.rain, r1.dmg.inside, r1.dmg.pool))
	local rewards = {}
	for _, l in { 1, 3, 5, 8, 10, 15 } do
		table.insert(rewards, string.format("L%d=%d", l, Config.computeReward(l, true, 1, 1)))
	end
	print("rewards (full bunker): " .. table.concat(rewards, " "))
end

return Balance
