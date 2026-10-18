--!nocheck
-- Симуляция баланса: виртуальный игрок ловит молнии, сдаёт банку и покупает улучшения
-- по формулам из Config/Economy. Печатает, когда открываются острова и перезапуск.
-- Запуск: lune run tools/tests/balance.luau [skill]   (skill: 0.6 слабый, 1 средний, 1.3 сильный)
local process = require("@lune/process")
local Loader = require("../lib/loader")
local Config = Loader.load("src/shared/Config")
local Economy = Loader.load("src/shared/Economy")
local PlayerData = Loader.load("src/shared/PlayerData")

local skill = tonumber(process.args[1]) or 1

local Sim = {}

-- Ожидаемый множитель цвета в зоне
local function avgColorMult(zone)
	local total, sum = 0, 0
	for id, w in Config.Zones[zone].ColorWeights do
		total += w
		sum += w * Config.Colors[id].Mult
	end
	return sum / total
end

-- Модель игрока: доля пойманных колец и доля ИДЕАЛЬНО
local function catchModel(d, zone)
	local z = Config.Zones[zone]
	local speed = Economy.walkSpeed(d.Upgrades.Boots)
	local rate = (1 / z.Interval) * Economy.rateMult(d.Upgrades.Magnet)
	local maxActive = z.MaxActive + Economy.extraRings(d.Upgrades.Magnet)
	rate = math.min(rate, maxActive / z.Warning)
	-- сколько колец успевает поймать: ограничено скоростью перемещения (~среднее расстояние 16 стадов)
	local reachPerSec = 1 / (16 / speed + 0.6)
	local caughtPerSec = math.min(rate * 0.8, reachPerSec) * skill * 0.62
	local perfectShare = math.clamp(0.35 * skill + 0.05 * math.floor(d.Upgrades.Rod / 5), 0.05, 0.8)
	local avgCombo = math.clamp(4 * skill, 1, 25)
	return caughtPerSec, perfectShare, avgCombo
end

local function chargePerSecond(d, zone)
	local caught, perfectShare, avgCombo = catchModel(d, zone)
	local perCatch = Config.Zones[zone].BaseCharge
		* avgColorMult(zone)
		* (perfectShare * Config.Catch.PerfectMult + (1 - perfectShare) * Config.Catch.GoodMult)
		* (1 + Config.Catch.ComboStep * avgCombo)
		* Economy.rodMult(d.Upgrades.Rod)
	return caught * perCatch
end

local SELL_TRIP = 9 -- секунд: дойти до подстанции и вернуться

-- Доход в секунду с учётом походов на подстанцию
local function voltsPerSecond(d, zone, mult)
	local cps = chargePerSecond(d, zone)
	local cap = Economy.jarCapacity(d.Upgrades.Jar)
	local fillTime = cap / math.max(cps, 1e-9)
	local trip = if d.Drone then Config.Drone.TripTime else SELL_TRIP
	return cap * mult / (fillTime + trip)
end

function Sim.run(maxMinutes, verbose)
	local d = PlayerData.default()
	local zone = 1
	local t = 0
	local purchases = {}
	local milestones = {}
	local mult = Economy.multiplier(d, { friends = 0 })
	local log = {}
	local function note(text)
		table.insert(log, string.format("%6.1f мин  %s", t / 60, text))
	end
	local STEP = 3
	local nextReport = 0
	while t < maxMinutes * 60 do
		if verbose and t >= nextReport then
			nextReport += 300
			note(string.format("доход %s/мин (остров %d, Rod %d Jar %d Boots %d Magnet %d)", tostring(math.floor(voltsPerSecond(d, zone, mult) * 60)), zone, d.Upgrades.Rod, d.Upgrades.Jar, d.Upgrades.Boots, d.Upgrades.Magnet))
		end
		t += STEP
		local v = voltsPerSecond(d, zone, mult) * STEP
		d.Volts += v
		d.TotalVolts += v
		-- покупки: остров, если по карману; иначе лучшее улучшение по отдаче
		local bought = true
		while bought do
			bought = false
			local nextZone = d.Zone + 1
			if Config.Zones[nextZone] and d.Volts >= Economy.zoneCost(nextZone) then
				d.Volts -= Economy.zoneCost(nextZone)
				d.Zone = nextZone
				zone = nextZone
				milestones["zone" .. nextZone] = t
				note("ОСТРОВ " .. nextZone .. " " .. Config.Zones[nextZone].Name)
				bought = true
				continue
			end
			if not d.Drone and d.Zone >= Config.Drone.FromZone and d.Volts >= Config.Drone.Cost then
				d.Volts -= Config.Drone.Cost
				d.Drone = true
				note("Тесла-дрон")
				bought = true
				continue
			end
			local base = voltsPerSecond(d, zone, mult)
			local best, bestScore, bestCost = nil, 0, 0
			for _, id in Config.UpgradeOrder do
				local cost = Economy.upgradeCost(id, d.Upgrades[id])
				if cost and cost <= d.Volts then
					d.Upgrades[id] += 1
					local gain = voltsPerSecond(d, zone, mult) - base
					d.Upgrades[id] -= 1
					local score = gain / cost
					if id == "Insulation" then
						score = 0
					end
					if score > bestScore then
						best, bestScore, bestCost = id, score, cost
					end
				end
			end
			-- копить на остров, если до него меньше 2 минут
			local nz = Config.Zones[d.Zone + 1]
			if best and nz then
				local remaining = Economy.zoneCost(d.Zone + 1) - d.Volts
				if remaining / math.max(base, 1e-9) < 120 and bestCost > remaining * 0.3 then
					best = nil
				end
			end
			if best then
				d.Volts -= bestCost
				d.Upgrades[best] += 1
				table.insert(purchases, t)
				bought = true
			end
		end
		-- перезапуск
		if not milestones.rebirth and Economy.canRebirth(d) then
			milestones.rebirth = t
			note(string.format("ПЕРЕЗАПУСК доступен (Вольт %s)", tostring(math.floor(d.Volts))))
		end
	end
	local function countBefore(sec)
		local n = 0
		for _, pt in purchases do
			if pt <= sec then
				n += 1
			end
		end
		return n
	end
	if verbose then
		for _, l in log do
			print(l)
		end
		print(string.format("Покупок: за 1 мин %d, за 5 мин %d, за 15 мин %d, за 60 мин %d", countBefore(60), countBefore(300), countBefore(900), countBefore(3600)))
		local u = d.Upgrades
		print(string.format("Итог: Rod %d Jar %d Boots %d Magnet %d Ins %d, доход %.0f/мин", u.Rod, u.Jar, u.Boots, u.Magnet, u.Insulation, voltsPerSecond(d, zone, mult) * 60))
	end
	return milestones, countBefore
end

print(string.format("=== Симуляция, навык %.2f ===", skill))
local m, countBefore = Sim.run(240, true)

-- Проверки целей (мягкие: печатаем предупреждения)
local targets = {
	{ "zone2", 4, 10 },
	{ "zone3", 15, 32 },
	{ "zone4", 35, 70 },
	{ "zone5", 70, 130 },
	{ "rebirth", 60, 150 },
}
local ok = true
if skill == 1 then
	for _, tg in targets do
		local v = m[tg[1]]
		local mins = v and v / 60
		if not mins or mins < tg[2] or mins > tg[3] then
			ok = false
			print(string.format("ВНЕ ЦЕЛИ: %s = %s мин (цель %d–%d)", tg[1], mins and string.format("%.1f", mins) or "нет", tg[2], tg[3]))
		end
	end
	local p5 = countBefore(300)
	if p5 < 6 or p5 > 18 then
		ok = false
		print("ВНЕ ЦЕЛИ: покупок за 5 минут = " .. p5 .. " (цель 6–18)")
	end
	print(if ok then "Баланс в целевых рамках" else "Баланс требует подстройки")
end
