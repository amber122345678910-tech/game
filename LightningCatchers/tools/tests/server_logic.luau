--!nocheck
-- Тесты чистых помощников сервера (src/server/Lib/ServerLogic.luau).
-- Запуск из LightningCatchers/: .tools/lune run tools/tests/server_logic.luau
local process = require("@lune/process")
local Loader = require("../lib/loader")
local T = require("./lib")

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local L = Loader.load("src/server/Lib/ServerLogic")
local Config = Loader.load("src/shared/Config")
local Strikes = Loader.load("src/shared/Strikes")
local Zones = Loader.load("src/shared/Zones")

T.test("isFinite / isInteger", function()
	T.truthy(L.isFinite(1.5))
	T.falsy(L.isFinite(0 / 0), "NaN")
	T.falsy(L.isFinite(math.huge), "inf")
	T.falsy(L.isFinite(-math.huge), "-inf")
	T.falsy(L.isFinite("1"), "строка")
	T.falsy(L.isFinite(nil), "nil")
	T.truthy(L.isInteger(3))
	T.falsy(L.isInteger(3.5))
	T.falsy(L.isInteger(math.huge))
end)

T.test("stochasticRound сохраняет среднее", function()
	T.eq(L.stochasticRound(2.3, 0.2), 3)
	T.eq(L.stochasticRound(2.3, 0.5), 2)
	T.eq(L.stochasticRound(4, 0), 4)
	T.eq(L.stochasticRound(4, 0.999), 4)
	local sum = 0
	for i = 0, 999 do
		sum += L.stochasticRound(1.15, (i + 0.5) / 1000)
	end
	T.near(sum / 1000, 1.15, 0.002, "среднее")
end)

T.test("jitter в пределах ±share", function()
	T.near(L.jitter(1.6, 0.25, 0), 1.2, 1e-9)
	T.near(L.jitter(1.6, 0.25, 0.5), 1.6, 1e-9)
	T.near(L.jitter(1.6, 0.25, 1), 2.0, 1e-9)
end)

T.test("ведро токенов", function()
	local b = L.newBucket(8, 0)
	for i = 1, 8 do
		T.truthy(L.take(b, 8, 8, 0), "токен " .. i)
	end
	T.falsy(L.take(b, 8, 8, 0), "9-й сразу")
	-- через 0.5 с накопилось 4
	for i = 1, 4 do
		T.truthy(L.take(b, 8, 8, 0.5), "после паузы " .. i)
	end
	T.falsy(L.take(b, 8, 8, 0.5))
	-- не больше ёмкости даже после долгой паузы
	local n = 0
	while L.take(b, 8, 8, 100) do
		n += 1
	end
	T.eq(n, 8, "ёмкость")
	-- время назад (смена часов) не даёт токенов
	local c = L.newBucket(1, 10)
	T.truthy(L.take(c, 1, 1, 10))
	T.falsy(L.take(c, 1, 1, 5))
end)

local function riskZero()
	return 0
end
local function riskOne()
	return 1
end

T.test("банка без перегрузки: лишнее теряется", function()
	local r = L.addToJar(20, 10, 25, false, 1.5, riskOne, 0, 0.5)
	T.eq(r.After, 25)
	T.eq(r.Added, 5)
	T.eq(r.Lost, 5)
	T.falsy(r.Burst, "без перегрузки не лопается")
end)

T.test("перегрузка без риска", function()
	local r = L.addToJar(20, 10, 25, true, 1.5, riskZero, 0, 0.5)
	T.eq(r.After, 30)
	T.eq(r.Added, 10)
	T.eq(r.Lost, 0)
	T.falsy(r.Burst)
end)

T.test("перегрузка: банка лопнула — остаётся половина", function()
	local r = L.addToJar(20, 10, 25, true, 1.5, riskOne, 0.5, 0.5)
	T.truthy(r.Burst)
	T.eq(r.Added, 10)
	T.eq(r.After, 15)
	T.eq(r.Lost, 15)
end)

T.test("риск считается по заполнению после поимки", function()
	local seen
	L.addToJar(20, 10, 25, true, 1.5, function(fill)
		seen = fill
		return 0
	end, 0, 0.5)
	T.near(seen, 1.2, 1e-9)
	-- реальная формула: 5% + 30% × 0.4 = 17%
	T.near(Strikes.overchargeRisk(1.2, 0), 0.17, 1e-9)
	local burst = L.addToJar(20, 10, 25, true, 1.5, function(f)
		return Strikes.overchargeRisk(f, 0)
	end, 0.169, 0.5)
	T.truthy(burst.Burst, "roll ниже риска")
	local safe = L.addToJar(20, 10, 25, true, 1.5, function(f)
		return Strikes.overchargeRisk(f, 0)
	end, 0.171, 0.5)
	T.falsy(safe.Burst, "roll выше риска")
end)

T.test("до 100% риска нет", function()
	local r = L.addToJar(10, 10, 25, true, 1.5, function(f)
		return Strikes.overchargeRisk(f, 0)
	end, 0, 0.5)
	T.falsy(r.Burst)
	T.eq(r.After, 20)
end)

T.test("полная перегруженная банка: ничего не добавляется и не лопается", function()
	local r = L.addToJar(37.5, 5, 25, true, 1.5, riskOne, 0, 0.5)
	T.eq(r.Added, 0)
	T.eq(r.Lost, 5)
	T.eq(r.After, 37.5)
	T.falsy(r.Burst)
end)

T.test("перегрузил на острове 2 и ушёл на остров 1: заряд не пропадает", function()
	local r = L.addToJar(30, 5, 25, false, 1.5, riskOne, 0, 0.5)
	T.eq(r.After, 30, "заряд сохранён")
	T.eq(r.Added, 0)
	T.eq(r.Lost, 5)
end)

T.test("отрицательный заряд игнорируется", function()
	local r = L.addToJar(10, -5, 25, true, 1.5, riskOne, 0, 0.5)
	T.eq(r.After, 10)
	T.eq(r.Added, 0)
	T.eq(r.Lost, 0)
end)

T.test("координаты на мосту", function()
	local a, b = Vector3.new(0, 0, 0), Vector3.new(100, 10, 0)
	local along, side, length = L.bridgeCoords(Vector3.new(50, 5, 3), a, b)
	T.near(along, 50, 1e-6)
	T.near(side, 3, 1e-6)
	T.near(length, 100, 1e-6)
	local p = L.bridgePoint(a, b, 50)
	T.near(p.Y, 5, 1e-6, "высота по наклону")
	T.near(L.bridgePoint(a, b, -20).X, 0, 1e-6, "не раньше начала")
	T.near(L.bridgePoint(a, b, 500).X, 100, 1e-6, "не дальше конца")
end)

T.test("барьеры на мостах стоят на 78% пути, отброс остаётся на мосту", function()
	for z = 2, #Config.Zones do
		local g = Zones.Geo[z]
		local gateAlong, gateSide, length = L.bridgeCoords(g.Gate, g.BridgeStart, g.BridgeEnd)
		T.near(gateAlong / length, 0.78, 1e-4, "барьер " .. z)
		T.near(gateSide, 0, 1e-3)
		local back = L.bridgePoint(g.BridgeStart, g.BridgeEnd, gateAlong - Config.Server.GatePushBack)
		T.eq(Zones.zoneAt(back), nil, "точка отброса на мосту " .. z)
		local backAlong = L.bridgeCoords(back, g.BridgeStart, g.BridgeEnd)
		T.truthy(backAlong < gateAlong, "перед барьером " .. z)
	end
end)

T.test("точки появления на своих островах", function()
	for z = 1, #Config.Zones do
		T.eq(Zones.zoneAt(Zones.spawnFor(z)), z, "остров " .. z)
	end
	T.eq(Zones.zoneAt(Zones.spawnFor(0)), 0, "хаб")
end)

T.test("подстанции достижимы и не в игровой зоне", function()
	for z = 1, #Config.Zones do
		local g = Zones.Geo[z]
		T.eq(Zones.zoneAt(g.SellPad), z, "подстанция на острове " .. z)
		T.falsy(Zones.inPlayArea(z, g.SellPad), "кольца не на подстанции " .. z)
	end
end)

T.test("первое кольцо новичка перед точкой появления помещается", function()
	-- так же, как StrikeService.placeAhead: 6 стадов к центру острова от точки появления,
	-- у края — сдвиг внутрь игровой зоны
	local r = Config.Catch.RingRadius
	for z = 1, #Config.Zones do
		local g = Zones.Geo[z]
		local spawn = Zones.spawnFor(z)
		local dir = (Vector3.new(g.Center.X, spawn.Y, g.Center.Z) - spawn).Unit
		local p = Zones.clampToPlay(z, spawn + dir * Config.Server.FirstStrikeAhead, r)
		T.truthy(L.flatDist(p, g.Center) <= Config.Zones[z].PlayRadius - r + 1e-3, "в игровой зоне " .. z)
		T.truthy(L.flatDist(p, g.SellPad) >= Zones.SellPadRadius + r + Config.Catch.MinRingGap, "не на подстанции " .. z)
		T.truthy(L.flatDist(p, spawn) <= r + 0.01, "у ног игрока " .. z)
	end
	-- новичок (остров 1) сразу стоит внутри кольца
	local spawn1 = Zones.spawnFor(1)
	local g1 = Zones.Geo[1]
	local dir1 = (Vector3.new(g1.Center.X, spawn1.Y, g1.Center.Z) - spawn1).Unit
	local p1 = Zones.clampToPlay(1, spawn1 + dir1 * Config.Server.FirstStrikeAhead, r)
	T.truthy(L.flatDist(p1, spawn1) < r, "новичок внутри первого кольца")
end)

T.test("кольцо: радиус и высота", function()
	local c = Vector3.new(0, 0, 0)
	T.truthy(L.inRing(Vector3.new(7, 3, 0), c, 7, 16))
	T.falsy(L.inRing(Vector3.new(7.01, 3, 0), c, 7, 16))
	T.falsy(L.inRing(Vector3.new(0, 17, 0), c, 7, 16), "слишком высоко")
end)

T.test("бегущее кольцо", function()
	T.eq(L.runnerShare(10, 12, 10), 0)
	T.eq(L.runnerShare(10, 12, 11), 0.5)
	T.eq(L.runnerShare(10, 12, 13), 1, "после удара стоит на месте")
	T.eq(L.runnerShare(10, 10, 10), 1, "нулевой путь")
	-- путь бегущего короче, чем можно добежать
	for z = 1, #Config.Zones do
		local w = Config.Zones[z].Warning
		T.truthy(Config.Catch.RunnerSpeed * w < 18 * w * Config.Server.ReachShare, "зона " .. z)
	end
end)

T.test("правдоподобие нажатия", function()
	local now, spawn = 100, 97
	T.truthy(L.tapPlausible(99.9, now, spawn, 1.2, 0.15))
	T.truthy(L.tapPlausible(100.1, now, spawn, 1.2, 0.15), "поправка задержки")
	T.falsy(L.tapPlausible(100.2, now, spawn, 1.2, 0.15), "из будущего")
	T.falsy(L.tapPlausible(98.7, now, spawn, 1.2, 0.15), "слишком старое")
	T.falsy(L.tapPlausible(96.9, 97.5, spawn, 1.2, 0.15), "раньше появления кольца")
end)

T.test("какой удар оценивать: ближайший неоценённый", function()
	local hits = { 10, 10.5, 10.85 } -- вилка
	local judged = {}
	local function open(i)
		return not judged[i]
	end
	T.eq(L.nearestHit(hits, 10.02, open, 1), 1)
	T.eq(L.nearestHit(hits, 10.86, open, 2), 3, "клиент назвал 2, но нажатие ближе к 3")
	judged[1] = true
	T.eq(L.nearestHit(hits, 10.86, open, 2), 3, "пропустил второй — оценивается третий")
	T.eq(L.nearestHit(hits, 10.6, open, 3), 2)
	T.eq(L.nearestHit(hits, 10.675, open, 3), 3, "ровно посередине — номер клиента")
	T.eq(L.nearestHit(hits, 10.675, open, 1), 2, "посередине без подсказки — более ранний")
	judged[2] = true
	judged[3] = true
	T.eq(L.nearestHit(hits, 10.86, open, 3), nil, "все оценены")
end)

T.test("комбо", function()
	T.eq(L.nextCombo(3, "perfect"), 4)
	T.eq(L.nextCombo(3, "good"), 3)
	T.eq(L.nextCombo(3, "miss"), 0)
	T.eq(L.nextCombo(3, "zap"), 0)
end)

T.test("окна оценки укладываются в ожидание нажатия", function()
	-- самое позднее ХОРОШО должно успеть прийти до того, как сервер решит удар без нажатия
	local _, good = Strikes.windows(30, 40)
	T.truthy(good < Config.Catch.LatencyGrace, "окно ХОРОШО < LatencyGrace")
	T.truthy(Config.Catch.LatencyGrace <= Config.Catch.MaxTapAge, "LatencyGrace <= MaxTapAge")
end)

print(string.format("server_logic: %d passed, %d failed", T.passed, T.failed))
if T.failed > 0 then
	process.exit(1)
end
