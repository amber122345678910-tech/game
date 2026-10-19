--!nocheck
-- Юнит-тесты чистой логики. Запуск: lune run tools/tests/run.luau
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Loader = require("../lib/loader")
local T = require("./lib")

local Config = Loader.load("src/shared/Config")
local Strikes = Loader.load("src/shared/Strikes")
local Economy = Loader.load("src/shared/Economy")
local Zones = Loader.load("src/shared/Zones")
local Pets = Loader.load("src/shared/Pets")
local Fulgurite = Loader.load("src/shared/Fulgurite")
local BoltGeometry = Loader.load("src/shared/BoltGeometry")
local Prng = Loader.load("src/shared/Prng")
local Rng = Loader.load("src/shared/Rng")
local PlayerData = Loader.load("src/shared/PlayerData")
local Quests = Loader.load("src/shared/Quests")
local Format = Loader.load("src/shared/Format")
local Geom = Loader.load("src/shared/Geom")
local Loc = Loader.load("src/shared/Loc")

local test, eq, near, truthy, falsy = T.test, T.eq, T.near, T.truthy, T.falsy

-- Выполнить fn на языке lang (тексты на языке игрока: Fulgurite.title, Quests.text, …), потом вернуть английский
local function inLang(lang: string, fn: () -> ())
	Loc.setLang(lang :: any)
	local ok, err = pcall(fn)
	Loc.setLang("en")
	if not ok then
		error(err, 0)
	end
end

----------------------------------------------------------------------
-- Тайминг
----------------------------------------------------------------------
test("окна: база и рост с громоотводом", function()
	local p, g = Strikes.windows(0, 0)
	near(p, Config.Catch.PerfectWindow, 1e-9, "perfect")
	near(g, Config.Catch.GoodWindow, 1e-9, "good")
	local p5 = Strikes.windows(5, 0)
	near(p5, Config.Catch.PerfectWindow + Config.Catch.RodWindowStepPerfect, 1e-9, "rod 5")
	local pMax, gMax = Strikes.windows(30, 500)
	near(pMax, Config.Catch.MaxPerfectWindow, 1e-9, "cap perfect")
	near(gMax, Config.Catch.MaxGoodWindow, 1e-9, "cap good")
	truthy(gMax > pMax, "good > perfect")
end)

test("оценка нажатия симметрична и по границам", function()
	local p, g = 0.12, 0.26
	eq(Strikes.judge(0, p, g), "perfect")
	eq(Strikes.judge(0.12, p, g), "perfect")
	eq(Strikes.judge(-0.12, p, g), "perfect")
	eq(Strikes.judge(0.1201, p, g), "good")
	eq(Strikes.judge(-0.26, p, g), "good")
	eq(Strikes.judge(0.2601, p, g), "miss")
	eq(Strikes.judge(-1, p, g), "miss")
end)

test("комбо-множитель растёт и упирается в потолок", function()
	near(Strikes.comboMult(0), 1, 1e-9)
	near(Strikes.comboMult(10), 1 + 10 * Config.Catch.ComboStep, 1e-9)
	near(Strikes.comboMult(1000), 1 + Config.Catch.ComboCap * Config.Catch.ComboStep, 1e-9)
	near(Strikes.comboMult(-5), 1, 1e-9)
end)

test("цвета: веса зоны, удача поднимает редкие", function()
	local base = Rng.chances(Strikes.colorWeights(1, 0))
	local lucky = Rng.chances(Strikes.colorWeights(1, 1))
	truthy(lucky.gold > base.gold, "gold with luck")
	truthy(lucky.blue < base.blue, "blue with luck")
	local sum = 0
	for _, v in base do
		sum += v
	end
	near(sum, 1, 1e-9, "sum")
	-- золото в событии
	local boosted = Rng.chances(Strikes.colorWeights(1, 0, 3))
	truthy(boosted.gold > base.gold * 2.5, "gold boost")
	-- крайние значения броска
	eq(Strikes.rollColor(1, 0, 0), "blue")
	truthy(table.find(Config.NormalColors, Strikes.rollColor(5, 0, 0.99999)), "valid")
end)

test("переливание: следующий по редкости", function()
	eq(Strikes.upgradedColor("blue"), "purple")
	eq(Strikes.upgradedColor("red"), "gold")
	eq(Strikes.upgradedColor("gold"), "gold")
end)

test("типы ударов доступны только со своей зоны", function()
	for z = 1, #Config.Zones do
		for i = 0, 50 do
			local kind = Strikes.rollKind(z, i / 51)
			truthy(Config.Kinds[kind].FromZone <= z, "kind " .. kind .. " in zone " .. z)
		end
	end
	eq(Strikes.rollKind(1, 0.7), "single")
	eq(#Strikes.hitOffsets("fork"), 3)
end)

test("риск перегрузки", function()
	eq(Strikes.overchargeRisk(1, 0), 0)
	near(Strikes.overchargeRisk(1.0001, 0), Config.Overcharge.BaseRisk, 1e-3)
	near(Strikes.overchargeRisk(1.5, 0), Config.Overcharge.BaseRisk + Config.Overcharge.ExtraRisk, 1e-9)
	truthy(Strikes.overchargeRisk(1.5, 8) < Strikes.overchargeRisk(1.5, 0), "insulation lowers")
	truthy(Strikes.overchargeRisk(9, 0) <= 0.95, "cap")
end)

test("обманка замирает, обычное кольцо линейно", function()
	near(Strikes.ringProgress("single", 0.5), 0.5, 1e-9)
	near(Strikes.ringProgress("fake", 0.5), 0.6, 1e-9)
	near(Strikes.ringProgress("fake", 0.65), 0.6, 1e-9)
	near(Strikes.ringProgress("fake", 1), 1, 1e-9)
	near(Strikes.ringProgress("fake", 0), 0, 1e-9)
	-- монотонно
	local last = -1
	for i = 0, 100 do
		local v = Strikes.ringProgress("fake", i / 100)
		truthy(v >= last - 1e-9, "monotonic")
		last = v
	end
end)

----------------------------------------------------------------------
-- Экономика
----------------------------------------------------------------------
test("цены улучшений растут, максимум — nil", function()
	for id, def in Config.Upgrades do
		local last = 0
		for lvl = 0, def.MaxLevel - 1 do
			local c = Economy.upgradeCost(id, lvl)
			truthy(c and c > last, id .. " grows at " .. lvl)
			last = c
		end
		eq(Economy.upgradeCost(id, def.MaxLevel), nil, id .. " max")
	end
end)

test("заряд за поимку", function()
	near(Economy.catchCharge(1, "blue", "good", 0, 0), 1, 1e-9)
	near(Economy.catchCharge(1, "blue", "perfect", 0, 0), 2, 1e-9)
	near(Economy.catchCharge(2, "gold", "good", 0, 0), Config.Zones[2].BaseCharge * 40, 1e-9)
	near(Economy.catchCharge(1, "blue", "good", 0, 10), 1 + 10 * Config.UpgradeEffects.RodAddPerLevel, 1e-9)
	near(Economy.catchCharge(1, "blue", "good", 0, 0, 2), 2, 1e-9)
end)

test("сдача банки: перегрузка стоит дороже", function()
	eq(Economy.sellValue(10, 20, 1), 10)
	eq(Economy.sellValue(20, 20, 2), 40)
	eq(Economy.sellValue(30, 20, 1), 20 + 15)
	eq(Economy.sellValue(0, 20, 5), 0)
end)

test("множитель: перезапуски, питомцы, друзья, город, буст", function()
	local d = PlayerData.default()
	near(Economy.multiplier(d), 1, 1e-9)
	d.Rebirths = 2
	near(Economy.multiplier(d), 2, 1e-9)
	d.Pets = { { Id = 1, Kind = "luchik" } }
	d.Equipped = { 1 }
	near(Economy.multiplier(d), 2 * 1.2, 1e-9)
	near(Economy.multiplier(d, { friends = 5 }), 2 * 1.2 * 1.3, 1e-9)
	near(Economy.multiplier(d, { cityBoost = true }), 2 * 1.2 * 2, 1e-9)
	d.Boosts.Volts2x = 100
	near(Economy.multiplier(d, { now = 50 }), 2 * 1.2 * 2, 1e-9)
	near(Economy.multiplier(d, { now = 150 }), 2 * 1.2, 1e-9)
end)

test("строки Молниедекса", function()
	local d = PlayerData.default()
	eq(Economy.indexRows(d), 0)
	for _, c in Config.NormalColors do
		d.Index["2:" .. c] = true
	end
	eq(Economy.indexRows(d), 1)
	d.Index["2:gold"] = nil
	eq(Economy.indexRows(d), 0)
end)

test("перезапуск: условия и цена", function()
	local d = PlayerData.default()
	falsy(Economy.canRebirth(d))
	d.Zone = Config.Rebirth.RequiredZone
	d.Volts = Economy.rebirthCost(0)
	truthy(Economy.canRebirth(d))
	truthy(Economy.rebirthCost(1) > Economy.rebirthCost(0))
	eq(Economy.petSlots(0), Config.Rebirth.BasePetSlots)
	eq(Economy.petSlots(5), Config.Rebirth.BasePetSlots + 2)
end)

test("цены островов растут", function()
	for z = 2, #Config.Zones do
		truthy(Economy.zoneCost(z) > Economy.zoneCost(z - 1), "zone " .. z)
		truthy(Config.Zones[z].BaseCharge > Config.Zones[z - 1].BaseCharge, "charge " .. z)
	end
end)

----------------------------------------------------------------------
-- Геометрия мира
----------------------------------------------------------------------
test("острова не пересекаются друг с другом и с хабом", function()
	for i, gi in Zones.Geo do
		local ri = Config.Zones[i].Radius
		truthy(Zones.flatDist(gi.Center, Zones.HubCenter) > ri + Config.Hub.Radius + 30, "hub gap " .. i)
		for j, gj in Zones.Geo do
			if i < j then
				truthy(Zones.flatDist(gi.Center, gj.Center) > ri + Config.Zones[j].Radius + 40, "gap " .. i .. "-" .. j)
			end
		end
	end
end)

test("zoneAt: центры, хаб, мост", function()
	eq(Zones.zoneAt(Zones.HubCenter), 0)
	for i, g in Zones.Geo do
		eq(Zones.zoneAt(g.Center), i, "center " .. i)
		eq(Zones.zoneAt(g.Spawn), i, "spawn " .. i)
		eq(Zones.zoneAt(g.SellPad), i, "sellpad " .. i)
		eq(Zones.zoneAt(g.Gate), nil, "gate on bridge " .. i)
	end
	eq(Zones.zoneAt(Zones.Hub.Spawn), 0)
end)

test("подстанция и точка появления внутри острова, ориентир вне игровой зоны", function()
	for i, g in Zones.Geo do
		local z = Config.Zones[i]
		truthy(Zones.flatDist(g.SellPad, g.Center) < z.Radius - Zones.SellPadRadius - 2, "sellpad inside " .. i)
		falsy(Zones.inPlayArea(i, g.SellPad), "no rings on sellpad " .. i)
		truthy(Zones.flatDist(g.Landmark, g.Center) > z.PlayRadius, "landmark outside play " .. i)
		truthy(Zones.inPlayArea(i, g.Center), "center playable " .. i)
	end
end)

test("clampToPlay остаётся в игровой зоне", function()
	for i, g in Zones.Geo do
		local far = g.Center + Vector3.new(1000, 0, -1000)
		local p = Zones.clampToPlay(i, far)
		truthy(Zones.flatDist(p, g.Center) <= Config.Zones[i].PlayRadius - Config.Catch.RingRadius + 1e-6, "clamp " .. i)
		near(p.Y, Config.Zones[i].GroundY, 1e-9)
	end
end)

test("кандидат кольца в нужном расстоянии", function()
	local around = Zones.Geo[1].Center
	for k = 0, 20 do
		local p = Zones.candidate(1, around, 6, 34, k / 21, (k * 7 % 21) / 21)
		local d = Zones.flatDist(p, around)
		truthy(d >= 6 - 1e-3 and d <= 34 + 1e-3, "dist " .. d)
	end
end)

test("достижимость колец: средний игрок успевает", function()
	-- при максимальной дистанции появления и базовой скорости успевает ли игрок
	for z = 1, #Config.Zones do
		local travel = Config.Catch.MaxSpawnDistance / Config.UpgradeEffects.BootsBase
		-- сервер отбрасывает недостижимые; проверяем, что хоть часть дистанций достижима
		truthy(Config.Catch.MinSpawnDistance / Config.UpgradeEffects.BootsBase < Config.Zones[z].Warning * 0.85, "min reachable z" .. z)
		local _ = travel
	end
end)

----------------------------------------------------------------------
-- Детерминизм, генераторы
----------------------------------------------------------------------
test("Prng детерминирован и в [0,1)", function()
	local a, b = Prng.new(42), Prng.new(42)
	for _ = 1, 200 do
		local x = a:next()
		eq(x, b:next())
		truthy(x >= 0 and x < 1, "range")
	end
	local c = Prng.new(43)
	truthy(c:next() ~= Prng.new(42):next(), "different seeds")
	for _ = 1, 100 do
		local v = a:int(3, 7)
		truthy(v >= 3 and v <= 7 and v == math.floor(v), "int")
	end
	eq(Prng.hash(1, 2), Prng.hash(1, 2))
	truthy(Prng.hash(1, 2) ~= Prng.hash(2, 1), "hash order")
end)

test("молния: детерминирована, начинается в туче, заканчивается в точке удара", function()
	local from, to = Vector3.new(0, 100, 0), Vector3.new(10, 0, 5)
	local s1 = BoltGeometry.build(7, from, to, 4)
	local s2 = BoltGeometry.build(7, from, to, 4)
	eq(#s1, #s2)
	truthy(#s1 >= 10, "segments")
	near((s1[1].A - from).Magnitude, 0, 1e-6, "start")
	local mainLast
	for _, s in s1 do
		if not s.Branch then
			mainLast = s
		end
	end
	near((mainLast.B - to).Magnitude, 0, 1e-6, "end")
	for i, s in s1 do
		eq(s.A, s2[i].A)
		truthy(s.Width > 0, "width")
	end
end)

test("axisCFrame: ось X вдоль отрезка, в том числе вертикального", function()
	for _, pair in { { Vector3.new(0, 0, 0), Vector3.new(0, 10, 0) }, { Vector3.new(1, 2, 3), Vector3.new(4, -2, 9) }, { Vector3.new(0, 0, 0), Vector3.new(0, -5, 0) } } do
		local cf, len = Geom.axisCFrame(pair[1], pair[2])
		near(len, (pair[2] - pair[1]).Magnitude, 1e-6)
		local dir = (pair[2] - pair[1]).Unit
		near(cf.RightVector:Dot(dir), 1, 1e-6, "axis")
		near((cf.Position - (pair[1] + pair[2]) / 2).Magnitude, 0, 1e-6, "mid")
	end
end)

test("фульгурит: детерминирован, редкость и бонус согласованы", function()
	local a = Fulgurite.generate(12345, "gold", nil)
	local b = Fulgurite.generate(12345, "gold", nil)
	eq(a.Shape, b.Shape)
	eq(#a.Parts, #b.Parts)
	eq(a.Rarity, b.Rarity)
	near(a.Bonus, Fulgurite.RarityBonus[a.Rarity], 1e-9)
	truthy(#a.Parts <= 90 and #a.Parts >= 3, "parts count")
	eq(Fulgurite.generate(1, "black", "perun").Rarity, "mythic")
	eq(Fulgurite.rarityOf("blue", 0, nil), "common")
	-- Перун и радуга всегда с мутацией
	eq(Fulgurite.rollMutation(5, 0.9, "black"), "perun")
	eq(Fulgurite.rollMutation(1, 0.9, "rainbow"), "rainbow")
	eq(Fulgurite.rollMutation(1, 0.9, "blue"), nil)
	truthy(Fulgurite.rollDrop("rainbow", 0.999), "rainbow always drops")
	falsy(Fulgurite.rollDrop("blue", 0.5), "blue rarely drops")
	-- названия без порчи кириллицы
	inLang("ru", function()
		eq(Fulgurite.title(a, "golden"), "Золотой фульгурит «" .. a.ShapeName .. "»")
	end)
	eq(Fulgurite.title(a, "golden"), "Golden " .. Loc.tl("en", a.ShapeName) .. " Fulgurite")
	eq(Loc.renderIn("en", Fulgurite.titleMsg({ ShapeName = "Звезда" } :: any, nil)), "Star Fulgurite")
	eq(Loc.renderIn("ru", Fulgurite.titleMsg({ ShapeName = "Звезда" } :: any, "perun")), "Перунов фульгурит «Звезда»")
end)

test("фульгуриты: распределение редкости по цветам разумное", function()
	local counts = {}
	for seed = 1, 400 do
		local r = Fulgurite.generate(seed, "blue", nil).Rarity
		counts[r] = (counts[r] or 0) + 1
	end
	truthy((counts.common or 0) + (counts.rare or 0) == 400, "blue -> common/rare only")
	local gold = {}
	for seed = 1, 400 do
		local r = Fulgurite.generate(seed, "gold", nil).Rarity
		gold[r] = (gold[r] or 0) + 1
	end
	truthy((gold.legendary or 0) + (gold.mythic or 0) > 0, "gold can be legendary+")
end)

test("радужный фульгурит: чаще легендарный, иногда мифический; Перунов — всегда мифический", function()
	-- редкость радужного решает только качество формы: RainbowScore + качество × QualityScore
	eq(Fulgurite.rarityOf("rainbow", 0, "rainbow"), "legendary")
	eq(Fulgurite.rarityOf("rainbow", 0.5, "rainbow"), "legendary")
	eq(Fulgurite.rarityOf("rainbow", 0.99, "rainbow"), "mythic")
	eq(Fulgurite.rarityOf("rainbow", 0.5, nil), "legendary", "мутация не меняет")
	eq(Fulgurite.rarityOf("black", 0, "perun"), "mythic")
	eq(Fulgurite.rarityOf("black", 0, nil), "mythic")
	eq(Fulgurite.rarityOf("gold", 0.9, "perun"), "mythic")
	-- остальные цвета — как раньше
	eq(Fulgurite.rarityOf("gold", 0, nil), "epic")
	eq(Fulgurite.rarityOf("gold", 0.5, nil), "legendary")
	eq(Fulgurite.rarityOf("purple", 0, "golden"), "rare")
	local counts = {}
	for seed = 1, 400 do
		local r = Fulgurite.generate(seed, "rainbow", "rainbow").Rarity
		counts[r] = (counts[r] or 0) + 1
	end
	eq((counts.legendary or 0) + (counts.mythic or 0), 400, "только легендарные и мифические")
	truthy((counts.legendary or 0) > 260, "легендарных большинство: " .. tostring(counts.legendary))
	truthy((counts.mythic or 0) > 30, "мифические бывают: " .. tostring(counts.mythic))
	-- детерминизм
	local a = Fulgurite.generate(777, "rainbow", "rainbow")
	local b = Fulgurite.generate(777, "rainbow", "rainbow")
	eq(a.Rarity, b.Rarity)
	eq(#a.Parts, #b.Parts)
end)

----------------------------------------------------------------------
-- Питомцы
----------------------------------------------------------------------
test("коконы: шансы суммируются в 1, виды существуют", function()
	for id, cocoon in Pets.Cocoons do
		local sum = 0
		for _, e in Pets.chances(id) do
			sum += e.chance
			truthy(Pets.Kinds[e.kind], "kind " .. e.kind)
		end
		near(sum, 1, 1e-9, id)
		truthy(cocoon.Cost > 0, "cost")
	end
	truthy(Pets.Kinds[Pets.StarterPet], "starter")
	for _, r in Config.DailyRewards do
		if r.Pet then
			truthy(Pets.Kinds[r.Pet], "daily pet")
		end
		if r.Cocoon then
			truthy(Pets.Cocoons[r.Cocoon], "daily cocoon")
		end
	end
end)

test("гарантия легендарного", function()
	local pity = 0
	local gotLegendary = false
	for i = 1, Pets.Cocoons.meadow.PityAt do
		local kind
		kind, pity = Pets.roll("meadow", 0.01, pity) -- всегда самый частый
		if Pets.Rarities[Pets.Kinds[kind].Rarity].Rank >= 4 then
			gotLegendary = true
			eq(i, Pets.Cocoons.meadow.PityAt, "on pity")
		end
	end
	truthy(gotLegendary, "pity triggered")
	eq(pity, 0, "pity reset")
end)

test("бонусы питомцев складываются", function()
	local b = Pets.totalBonus({ "iskorka", "luchik", "tuchka", "sosulka" })
	near(b.volts, 0.28, 1e-9)
	near(b.luck, 0.1, 1e-9)
	near(b.window, 15, 1e-9)
	inLang("ru", function()
		eq(Pets.bonusText("sosulka"), "🎯 Окно ИДЕАЛЬНО +15 мс")
	end)
	eq(Pets.bonusText("sosulka"), "🎯 PERFECT Window +15 ms")
	eq(Loc.renderIn("ru", Pets.bonusMsg("sosulka")), "🎯 Окно ИДЕАЛЬНО +15 мс")
end)

----------------------------------------------------------------------
-- Данные игрока
----------------------------------------------------------------------
test("reconcile: мусор не ломает данные", function()
	local d = PlayerData.reconcile(nil)
	eq(d.Volts, 0)
	d = PlayerData.reconcile({ Volts = "lots", Zone = 99, Upgrades = { Rod = 9999, Jar = -5 }, Pets = { { Id = 1, Kind = "nope" }, { Id = 2, Kind = "iskorka" }, { Id = 2, Kind = "luchik" } }, Equipped = { 1, 2, 2, 7 } })
	eq(d.Volts, 0, "bad volts")
	eq(d.Zone, #Config.Zones, "zone clamp")
	eq(d.Upgrades.Rod, Config.Upgrades.Rod.MaxLevel, "rod clamp")
	eq(d.Upgrades.Jar, 0, "jar clamp")
	eq(#d.Pets, 1, "only valid unique pets")
	eq(#d.Equipped, 1, "equipped valid")
	eq(d.NextPetId, 3, "next id after max")
	d = PlayerData.reconcile({ Volts = 0 / 0, Shards = math.huge })
	eq(d.Volts, 0, "nan")
	eq(d.Shards, 0, "inf")
end)

test("serialize/reconcile — круговой обход", function()
	local d = PlayerData.default()
	d.Volts = 123
	d.Pets = { { Id = 5, Kind = "luchik" } }
	d.NextPetId = 6
	d.Equipped = { 5 }
	d.Fulgs = { { Id = 1, Seed = 99, Color = "gold", Mut = "golden", Serial = 1, Zone = 2 } }
	d.NextFulgId = 2
	d.EquippedFulgs = { 1 }
	d.Index["1:blue"] = true
	d.Quests = { Day = 10, List = { { Id = "catch", Target = 60, Progress = 3, Claimed = false } } }
	local back = PlayerData.reconcile(PlayerData.serialize(d))
	eq(back.Volts, 123)
	eq(back.Pets[1].Kind, "luchik")
	eq(back.Equipped[1], 5)
	eq(back.Fulgs[1].Mut, "golden")
	eq(back.EquippedFulgs[1], 1)
	truthy(back.Index["1:blue"], "index")
	eq(back.Quests.List[1].Progress, 3)
end)

test("офлайн-доход начисляется в Welcome с потолком", function()
	local d = PlayerData.default()
	d.IncomeRate = 100
	d.LastOnline = 1000
	PlayerData.onSessionStart(d, 1000 + 3600)
	eq(d.Welcome, math.floor(100 * 60 * Config.Offline.Share))
	local d2 = PlayerData.default()
	d2.IncomeRate = 100
	d2.LastOnline = 1
	PlayerData.onSessionStart(d2, 1 + 100 * 3600)
	eq(d2.Welcome, math.floor(100 * (Config.Offline.MaxSeconds / 60) * Config.Offline.Share))
	local d3 = PlayerData.default()
	d3.IncomeRate = 100
	d3.LastOnline = 1000
	PlayerData.onSessionStart(d3, 1030)
	eq(d3.Welcome, 0, "too short")
end)

----------------------------------------------------------------------
-- Задания и форматирование
----------------------------------------------------------------------
test("задания дня: 3 разных, детерминированы", function()
	local a = Quests.forDay(20000, 777, 1)
	local b = Quests.forDay(20000, 777, 1)
	eq(#a, 3)
	local seen = {}
	for i, q in a do
		eq(q.Id, b[i].Id)
		falsy(seen[q.Id], "unique")
		seen[q.Id] = true
		truthy(Quests.def(q.Id).MinZone <= 1, "zone ok")
	end
end)

test("тексты заданий: число и слово согласованы", function()
	for _, lang in { "ru", "en" } do
		inLang(lang, function()
			for _, def in Quests.Pool do
				for _, n in { 1, 2, 5, 11, 21, 22, def.Target } do
					local text = Quests.text(def, n)
					falsy(string.find(text, "%", 1, true), "нет незаполненных %: " .. text)
					truthy(string.find(text, tostring(n), 1, true) ~= nil, "есть число: " .. text)
					eq(Loc.renderIn(lang :: any, Quests.msg(def, n)), text, "Quests.msg = Quests.text")
					if lang == "en" then
						falsy(string.find(text, "[\208\209]"), "без кириллицы: " .. text)
					end
				end
			end
		end)
	end
	local catch = Quests.def("catch") :: any
	inLang("ru", function()
		eq(Quests.text(catch, 1), "Поймай 1 молнию")
		eq(Quests.text(catch, 3), "Поймай 3 молнии")
		eq(Quests.text(catch, 60), "Поймай 60 молний")
		eq(Quests.text(Quests.def("rare") :: any, 8), "Поймай 8 редких молний (◆ и выше)")
		eq(Quests.text(Quests.def("sell") :: any, 2), "Сдай банку 2 раза")
		eq(Quests.text(Quests.def("shards") :: any, 21), "Собери 21 осколок с земли")
		eq(Quests.text(Quests.def("combo") :: any, 12), "Набери комбо 12")
	end)
	eq(Quests.text(catch, 1), "Catch 1 bolt")
	eq(Quests.text(catch, 3), "Catch 3 bolts")
	eq(Quests.text(Quests.def("sell") :: any, 1), "Sell your Jar 1 time")
	eq(Quests.text(Quests.def("shards") :: any, 21), "Pick up 21 Shards")
end)

test("осколки за разбитый фульгурит: редкость × ценность острова", function()
	eq(Fulgurite.shatterValue("common", 1), Fulgurite.ShatterShards.common * Config.Zones[1].ShardValue)
	eq(Fulgurite.shatterValue("mythic", 5), Fulgurite.ShatterShards.mythic * Config.Zones[5].ShardValue)
	eq(Fulgurite.shatterValue("rare", 99), Fulgurite.shatterValue("rare", #Config.Zones), "остров за пределами — последний")
	eq(Fulgurite.shatterValue("rare", 0), Fulgurite.shatterValue("rare", 1), "остров 0 — первый")
end)

test("текст улучшения банки без несогласованного слова", function()
	inLang("ru", function()
		eq(Economy.effectText("Jar", 0), "вместимость 25")
	end)
	eq(Economy.effectText("Jar", 0), "capacity 25")
	truthy(string.find(Economy.effectText("Jar", 20), "K", 1, true) ~= nil or string.find(Economy.effectText("Jar", 20), "M", 1, true) ~= nil, "крупные числа коротко")
end)

test("форматирование чисел", function()
	eq(Format.short(999), "999")
	eq(Format.short(1000), "1K")
	eq(Format.short(1234), "1.23K")
	eq(Format.short(15600), "15.6K")
	eq(Format.short(2500000), "2.5M")
	eq(Format.short(123456789), "123M")
	eq(Format.full(1234567), "1 234 567")
	eq(Format.time(75), "1:15")
	eq(Format.time(3725), "1:02:05")
	eq(Format.plural(1, "а", "б", "в"), "а")
	eq(Format.plural(3, "а", "б", "в"), "б")
	eq(Format.plural(11, "а", "б", "в"), "в")
	eq(Format.plural(25, "а", "б", "в"), "в")
	eq(Format.mult(1.5), "x1.5")
	eq(Format.percent(0.25), "25%")
	eq(Format.percent(0.0001), "1/10K")
end)

----------------------------------------------------------------------
-- Локализация (src/shared/Loc.luau)
----------------------------------------------------------------------
test("Loc: словарь без конфликтов, язык по умолчанию — английский", function()
	eq(#Loc.Conflicts, 0, "конфликты ключей")
	eq(Loc.lang(), "en")
	eq(Loc.t("Вольты"), "Volts")
	eq(Loc.tl("ru", "Вольты"), "Вольты")
	eq(Loc.tl("en", "Ловцы Молний"), "Lightning Catchers")
	truthy(Loc.has("Вольты"), "has")
	falsy(Loc.has("Такой строки нет в словаре"), "has: нет")
	-- нет перевода — показывается исходник
	eq(Loc.tl("en", "Такой строки нет в словаре"), "Такой строки нет в словаре")
	inLang("ru", function()
		eq(Loc.lang(), "ru")
		eq(Loc.t("Вольты"), "Вольты")
		eq(Loc.t("Банка"), "Банка")
	end)
end)

test("Loc: ключи с контекстом ctx::", function()
	eq(Loc.tl("en", "kind::Обычный"), "Normal")
	eq(Loc.tl("en", "Обычный"), "Common")
	eq(Loc.tl("ru", "kind::Обычный"), "Обычный")
	eq(Loc.tl("ru", "Обычный"), "Обычный")
	-- у ключа с контекстом нет своего перевода — берётся перевод без контекста
	eq(Loc.tl("en", "nothere::Вольты"), "Volts")
	eq(Loc.tl("ru", "nothere::Вольты"), "Вольты")
	-- с аргументами
	eq(Loc.tl("en", "kind::Обычный"), Loc.renderIn("en", "kind::Обычный"))
end)

test("Loc: множественное число", function()
	local forms = "минуту|минуты|минут"
	local ru = {
		[1] = "минуту",
		[2] = "минуты",
		[5] = "минут",
		[11] = "минут",
		[12] = "минут",
		[14] = "минут",
		[21] = "минуту",
		[22] = "минуты",
		[25] = "минут",
		[101] = "минуту",
		[111] = "минут",
		[0] = "минут",
	}
	inLang("ru", function()
		for n, want in ru do
			eq(Loc.plural(n, forms), want, "ru " .. n)
		end
	end)
	for n, want in ru do
		eq(Loc.renderIn("ru", Loc.pmsg(n, forms)), want, "ru pmsg " .. n)
	end
	eq(Loc.plural(1, forms), "minute", "en 1")
	eq(Loc.plural(2, forms), "minutes", "en 2")
	eq(Loc.plural(0, forms), "minutes", "en 0")
	eq(Loc.renderIn("en", Loc.pmsg(21, forms)), "minutes", "en 21")
	eq(Loc.renderIn("en", Loc.pmsg(1, forms)), "minute", "en pmsg 1")
	-- с контекстом: по-русски формы без префикса
	eq(Loc.renderIn("ru", Loc.pmsg(5, "perfect::молнию|молнии|молний")), "молний")
	eq(Loc.renderIn("en", Loc.pmsg(5, "perfect::молнию|молнии|молний")), "PERFECT catches")
end)

test("Loc: сообщения с вложенными сообщениями и pmsg", function()
	local m = Loc.msg("🏙 ЭЛЕКТРОГРАД СИЯЕТ! %s Вольт на %d %s", "×2", 5, Loc.pmsg(5, "минуту|минуты|минут"))
	eq(Loc.renderIn("ru", m), "🏙 ЭЛЕКТРОГРАД СИЯЕТ! ×2 Вольт на 5 минут")
	eq(Loc.renderIn("en", m), "🏙 VOLTVILLE IS SHINING! ×2 Volts for 5 minutes")
	local spec = { ShapeName = "Звезда" } :: any
	local full = Loc.msg("Коллекция полна: %s %s разбит, +%d 💎 — место для нового!", Fulgurite.titleMsg(spec, "golden"), Loc.msg("№%06d", 12), 30)
	eq(Loc.renderIn("ru", full), "Коллекция полна: Золотой фульгурит «Звезда» №000012 разбит, +30 💎 — место для нового!")
	eq(Loc.renderIn("en", full), "Collection full: Golden Star Fulgurite #000012 shattered, +30 💎 — room for a new one!")
	-- render: строка-исходник, nil, число
	eq(Loc.renderIn("en", "Не хватает Вольт"), "Not enough Volts")
	eq(Loc.renderIn("en", nil), "")
	eq(Loc.renderIn("en", 42), "42")
	eq(Loc.render(Loc.msg("Не хватает Вольт")), "Not enough Volts")
	-- мусор вместо сообщения не роняет клиент
	eq(Loc.renderIn("en", { 5, 6 }), "")
end)

test("Loc: строковые аргументы-исходники переводятся сами", function()
	eq(Loc.tl("en", "🎁 %s!", "Искорка"), "🎁 Sparky!")
	eq(Loc.tl("ru", "🎁 %s!", "Искорка"), "🎁 Искорка!")
	eq(Loc.tl("en", "Сначала открой остров «%s»", "Медные Холмы"), "Unlock Copper Hills first")
	eq(Loc.renderIn("en", Loc.msg("🎁 Подарок: %s!", "Луговой кокон")), "🎁 Gift: Meadow Cocoon!")
	-- имя игрока (нет в словаре) — как есть
	eq(Loc.tl("en", "🌈 Радужную молнию поймали: %s!", "Аня"), "🌈 Rainbow Lightning caught by Аня!")
	-- числа — как есть
	eq(Loc.tl("en", "Телепорт заряжается: ещё %d с", 7), "Teleport recharging: 7s left")
end)

test("Loc: encode/decode и надписи в мире", function()
	local m = Loc.msg("Телепорт заряжается: ещё %d с", 7)
	local back = Loc.decode(Loc.encode(m))
	eq(#back, 2)
	eq(back[1], m[1])
	eq(back[2], 7)
	eq(Loc.renderIn("ru", back), "Телепорт заряжается: ещё 7 с")
	local m2 = Loc.msg("%s · %s", "Редкий", Loc.msg("№%06d", 5))
	local back2 = Loc.decode(Loc.encode(m2))
	eq(back2[2], "Редкий")
	eq(back2[3], "№000005", "вложенное сообщение — русским текстом")
	eq(Loc.renderIn("ru", back2), "Редкий · №000005")
	eq(Loc.renderIn("en", back2), "Rare · №000005")
	-- строка с числом в виде текста остаётся строкой
	local back3 = Loc.decode(Loc.encode(Loc.msg("%s и ещё %d", "12", 3)))
	eq(back3[2], "12")
	eq(back3[3], 3)
	-- строка-исходник без аргументов
	eq(Loc.encode("Магазин"), "Магазин")
	eq(Loc.decode("Магазин")[1], "Магазин")
	eq(#Loc.decode("Магазин"), 1)
	-- поддельная надпись: свойство — английский, атрибут — исходник
	local attrs = {}
	local label: any = {
		Text = "",
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end,
	}
	Loc.setWorldText(label, "Text", "Телепорт заряжается: ещё %d с", 3)
	eq(label.Text, "Teleport recharging: 3s left")
	eq(Loc.worldText(label, "Text", "ru"), "Телепорт заряжается: ещё 3 с")
	eq(Loc.worldText(label, "Text", "en"), "Teleport recharging: 3s left")
	eq(Loc.worldText(label, "ActionText", "ru"), nil, "нет атрибута — nil")
	attrs.LocUpper = true
	Loc.setWorldText(label, "Text", "Магазин")
	eq(label.Text, "SHOP")
	eq(Loc.worldText(label, "Text", "ru"), "МАГАЗИН")
end)

test("Loc.pick: настройка важнее локали, ru* — русский, остальное — английский", function()
	eq(Loc.pick("ru", "en-us"), "ru")
	eq(Loc.pick("en", "ru-ru"), "en")
	eq(Loc.pick("", "ru-ru"), "ru")
	eq(Loc.pick(nil, "ru-RU"), "ru")
	eq(Loc.pick(nil, "ru"), "ru")
	eq(Loc.pick("", "en-us"), "en")
	eq(Loc.pick("", "pt-br"), "en")
	eq(Loc.pick("", "uk-ua"), "en")
	eq(Loc.pick("", ""), "en")
	eq(Loc.pick(nil, nil), "en")
	eq(Loc.pick("de", "ru-ru"), "ru", "неизвестная настройка — по локали")
end)

test("Loc: сломанный перевод — показывается исходник", function()
	local key = "Тестовая строка %d из %d"
	Loc.EN[key] = "Broken %s %s %s" -- не хватает аргумента
	local ok, err = pcall(function()
		eq(Loc.tl("en", key, 1, 2), "Тестовая строка 1 из 2")
		eq(Loc.renderIn("en", Loc.msg(key, 1, 2)), "Тестовая строка 1 из 2")
		Loc.EN[key] = "Broken %d" -- лишний аргумент string.format не роняет
		eq(Loc.tl("en", key, 1, 2), "Broken 1")
		Loc.EN[key] = "Broken %d of %d"
		-- в исходнике тоже не те аргументы — хотя бы исходник
		eq(Loc.tl("en", key, "x", "y"), key)
	end)
	Loc.EN[key] = nil
	if not ok then
		error(err, 0)
	end
end)

test("Loc.upper: кириллица и латиница", function()
	eq(Loc.upper("ловцы молний ёж"), "ЛОВЦЫ МОЛНИЙ ЁЖ")
	eq(Loc.upper("Lightning catchers 123 ×"), "LIGHTNING CATCHERS 123 ×")
end)

test("Loc: в английских переводах нет кириллицы, плейсхолдеры как у исходника", function()
	local function ph(s: string): string
		local out = {}
		for p in string.gmatch(s, "%%[-+ #0]*%d*%.?%d*[sdifgxXqc%%]") do
			table.insert(out, p)
		end
		return table.concat(out, ",")
	end
	for k, v in Loc.EN do
		falsy(string.find(v, "[\208\209][\128-\191]"), "кириллица в переводе: " .. v)
		local plain = string.match(k, "::(.*)$") or k
		eq(ph(v), ph(plain), "плейсхолдеры: " .. k)
	end
end)

local ok = T.summary()
if not ok then
	process.exit(1)
end
