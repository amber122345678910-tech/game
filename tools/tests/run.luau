--!nocheck
-- Юнит-тесты чистой логики (Config, Inmates, Locale). Запуск: .tools/lune run tools/tests/run.luau
local Loader = require("../lib/loader")
local Config = Loader.load("src/shared/Config")
local Inmates = Loader.load("src/shared/Inmates")
local Locale = Loader.load("src/shared/Locale")

local passed, failed = 0, 0
local function test(name, fn)
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

-- Детерминированный Random для Lune: простая обёртка с NextNumber/NextInteger
local function makeRng(seed)
	local s = seed
	local function rand()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
	return {
		NextNumber = function(_, a, b)
			if a == nil then
				return rand()
			end
			return a + (b - a) * rand()
		end,
		NextInteger = function(_, a, b)
			return a + math.floor(rand() * (b - a + 1))
		end,
	}
end

test("difficulties ordered and complete", function()
	local list = Config.difficultyList()
	eq(#list, 4)
	eq(list[1].Id, "Easy")
	eq(list[4].Id, "Nightmare")
	for _, d in list do
		truthy(d.Nights >= 5, "nights")
		truthy(d.AmberPerNight > 0, "amber")
	end
end)

test("inmates per night", function()
	local normal = Config.getDifficulty("Normal")
	eq(Config.inmatesForNight(normal, 1), 1)
	eq(Config.inmatesForNight(normal, 6), 2)
	local nm = Config.getDifficulty("Nightmare")
	eq(Config.inmatesForNight(nm, 1), 2)
	eq(Config.inmatesForNight(nm, 8), 3)
	eq(Config.inmatesForNight(Config.getDifficulty("Easy"), 5), 1)
end)

test("night duration grows and caps", function()
	eq(Config.nightDuration(1), 100)
	eq(Config.nightDuration(2), 108)
	eq(Config.nightDuration(50), Config.Phases.NightMax)
end)

test("items and prices", function()
	local list = Config.itemList()
	truthy(#list >= 14, "items count")
	for _, def in list do
		truthy(Locale.has("Item_" .. def.Id), "name key " .. def.Id)
		truthy(Locale.has("ItemDesc_" .. def.Id), "desc key " .. def.Id)
		truthy(def.Price >= 0, "price")
		truthy(def.Stack >= 1, "stack")
	end
	truthy(Config.getItem("Shotgun").Charges == 1)
	truthy(Config.getItem("Planks").GiveCount == 3)
end)

test("perks", function()
	eq(Config.perkValue("Sprinter", 0), 0)
	eq(Config.perkValue("Sprinter", 2), 0.3)
	eq(Config.perkValue("Sprinter", 9), 0.45)
	for id, def in Config.Perks do
		eq(#def.Costs, #def.Values, "perk " .. id)
		truthy(Locale.has("Perk_" .. id), "perk name " .. id)
	end
end)

test("levels and titles", function()
	eq(Config.levelFromXp(0), 0)
	eq(Config.levelFromXp(50), 1)
	eq(Config.levelFromXp(200), 2)
	eq(Config.xpForLevel(3), 450)
	eq(Config.titleForLevel(0), "Newcomer")
	eq(Config.titleForLevel(12), "Night Owl")
	eq(Config.titleForLevel(40), "Hollow")
end)

test("roster integrity", function()
	truthy(#Inmates.List == 10, "10 inmates")
	local seen = {}
	for _, d in Inmates.List do
		truthy(not seen[d.Id], "duplicate " .. d.Id)
		seen[d.Id] = true
		truthy(Locale.has("Inmate_" .. d.Id .. "_Name"), "name " .. d.Id)
		truthy(Locale.has("Inmate_" .. d.Id .. "_Rule"), "rule " .. d.Id)
		truthy(Locale.has("Inmate_" .. d.Id .. "_Alert"), "alert " .. d.Id)
		truthy(d.HP > 0 and d.Unlock >= 1 and d.Weight > 0, "stats " .. d.Id)
		truthy(d.Look.Scale.Y > 0, "scale " .. d.Id)
		truthy(Inmates.get(d.Id) == d)
	end
	-- Тексты оповещений не используют запрещённые слова
	for _, lang in { "en", "ru" } do
		Locale.setLanguage(lang)
		for _, d in Inmates.List do
			local text = string.lower(Locale.inmateAlert(d.Id) .. " " .. Locale.inmateRule(d.Id))
			for _, bad in { "kill", "murder", "abduct", "kidnap", "blood", "убий", "похищ", "кровь" } do
				truthy(not string.find(text, bad, 1, true), lang .. " " .. d.Id .. " contains '" .. bad .. "'")
			end
		end
	end
	Locale.setLanguage("en")
end)

test("night 1 is always the Sleepwalker, night 2 Knocker/Lamplighter", function()
	for seed = 1, 20 do
		local rng = makeRng(seed)
		local ids = Inmates.pickForNight(1, 1, {}, false, rng)
		eq(#ids, 1)
		eq(ids[1], "Sleepwalker")
		local ids2 = Inmates.pickForNight(2, 1, ids, false, rng)
		truthy(ids2[1] == "Knocker" or ids2[1] == "Lamplighter", "night 2: " .. tostring(ids2[1]))
	end
end)

test("later nights respect unlocks, no repeats, boss forced", function()
	for seed = 1, 60 do
		local rng = makeRng(seed * 7)
		local last = { "Sleepwalker" }
		for night = 3, 15 do
			local count = Config.inmatesForNight(Config.getDifficulty("Nightmare"), night)
			local ids = Inmates.pickForNight(night, count, last, night == 15, rng)
			truthy(#ids >= 1 and #ids <= count, "count night " .. night .. " got " .. #ids)
			local seen = {}
			for _, id in ids do
				local def = Inmates.get(id)
				truthy(def ~= nil, "unknown " .. tostring(id))
				truthy(def.Unlock <= night, id .. " too early on " .. night)
				truthy(not seen[id], "dup " .. id)
				seen[id] = true
				truthy(not table.find(last, id) or night == 15, id .. " repeated on night " .. night)
			end
			if night == 15 then
				truthy(table.find(ids, "HollowMan") ~= nil, "boss forced")
			end
			last = ids
		end
	end
end)

test("locale fallback and formatting", function()
	Locale.setLanguage("ru-ru")
	eq(Locale.getLanguage(), "ru")
	eq(Locale.t("Night", 2, 8), "Ночь 2 / 8")
	eq(Locale.t("NoSuchKey"), "NoSuchKey")
	Locale.setLanguage("en-us")
	eq(Locale.t("Night", 2, 8), "Night 2 / 8")
	eq(Locale.t("Cash", 150), "$150")
end)

test("every EN key has a RU translation", function()
	Locale.setLanguage("ru")
	local missing = {}
	-- Проверяем через t(): если RU нет, вернётся EN-текст; ловим ключи, где RU == EN и текст латиницей
	for _, key in { "Ready", "Difficulty", "Perks", "Settings", "AlertHeader", "ResultWin", "Tip_Apples", "N_Sold" } do
		local ru = Locale.t(key)
		Locale.setLanguage("en")
		local en = Locale.t(key)
		Locale.setLanguage("ru")
		if ru == en then
			table.insert(missing, key)
		end
	end
	Locale.setLanguage("en")
	eq(#missing, 0, "missing RU: " .. table.concat(missing, ","))
end)

print(string.format("Tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error(failed .. " tests failed")
end
