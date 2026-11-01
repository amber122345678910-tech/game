--!nocheck
-- Progression area: ProfileSchema (defaults, migration, sanitising, settings, equip rules, view), Levels,
-- Rewards (round rows -> EXP/G, grant, login streak), Quests (determinism, variety, tracking, reroll, rollover),
-- Shop (rotation determinism, featured discount, purchase rules), Mastery / Achievements / Titles,
-- Strings/Progression coverage, RequestService parsers + dispatch guards, DataService lock transforms and a
-- compile/load/Init smoke test of every progression service.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local SERVICES = {
	"DataService",
	"RequestService",
	"LoginService",
	"MasteryService",
	"ShopService",
	"QuestService",
	"AchievementService",
	"RewardService",
	"LeaderboardService",
}

local MY_FILES = {
	"src/shared/Progression/ProfileSchema.luau",
	"src/shared/Progression/Levels.luau",
	"src/shared/Progression/Quests.luau",
	"src/shared/Progression/Achievements.luau",
	"src/shared/Progression/Shop.luau",
	"src/shared/Progression/Mastery.luau",
	"src/shared/Progression/Titles.luau",
	"src/shared/Progression/Rewards.luau",
}

local function mod(Loader, name)
	return Loader.require("ReplicatedStorage.Shared.Progression." .. name)
end

local function shared(Loader, path)
	return Loader.require("ReplicatedStorage.Shared." .. path)
end

local function row(userId, fields)
	local r = {
		userId = userId,
		name = "P" .. tostring(userId),
		team = "Humans",
		kitId = "Determination",
		damage = 0,
		healing = 0,
		kills = 0,
		downs = 0,
		parries = 0,
		dodgesForced = 0,
		saves = 0,
		revives = 0,
		survived = false,
	}
	for k, v in fields or {} do
		r[k] = v
	end
	return r
end

local function result(fields)
	local r = {
		winner = "Humans",
		reason = "Defeated",
		rows = {},
		mvpUserId = nil,
		practice = false,
		durations = { round = 200, collapse = 0, total = 230 },
		mapId = "TestArena",
		roundId = 1,
	}
	for k, v in fields or {} do
		r[k] = v
	end
	return r
end

local function ids(list)
	local out = {}
	for _, q in list do
		table.insert(out, q.Id or q.Key)
	end
	return out
end

local function contains(list, value)
	return table.find(list, value) ~= nil
end

local function placeholders(s)
	local set = {}
	for n in string.gmatch(s, "{(%d+)}") do
		set[n] = true
	end
	local keys = {}
	for k in set do
		table.insert(keys, k)
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function fakePlayer(userId)
	local attrs = {}
	return {
		Name = "Tester" .. tostring(userId),
		DisplayName = "Tester",
		UserId = userId,
		Parent = {},
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end,
	}
end

return {
	-- ProfileSchema ------------------------------------------------------------------------------------
	schema_default = function(T, Loader)
		local Schema = mod(Loader, "ProfileSchema")
		local Kits = shared(Loader, "Kits")
		local p = Schema.Default()
		T.eq(p.Version, Schema.Version, "version")
		T.eq(p.Level, 1, "level")
		T.eq(p.Exp, 0, "exp")
		T.eq(p.Gold, 0, "gold")
		for _, kit in Kits.All() do
			T.eq(p.Unlocked[kit.Id] == true, kit.Unlock.Gold == 0, "free kit unlocked iff Unlock.Gold == 0: " .. kit.Id)
			T.ok(p.Unlocked[kit.Id .. ":Default"] == true, "default skin unlocked: " .. kit.Id)
		end
		T.eq(p.Equipped.Human, Kits.DefaultHuman, "default human")
		T.eq(p.Equipped.Monster, Kits.DefaultMonster, "default monster")
		T.eq(p.Equipped.Title, "", "no title")
		T.eq(p.MonsterChance, 1, "monster chance weight starts at 1")
		T.eq(p.RoundsSinceMonster, 0, "rounds since monster")
		T.eq(p.RolePreference, "Either", "role preference")
		for _, key in Schema.StatKeys do
			T.eq(p.Stats[key], 0, "stat " .. key)
		end
		local q = Schema.Default()
		q.Unlocked.Test = true
		T.ok(p.Unlocked.Test == nil, "defaults are independent tables")
	end,

	schema_migrate = function(T, Loader)
		local Schema = mod(Loader, "ProfileSchema")
		local TableUtil = shared(Loader, "Util.TableUtil")
		local fresh, isFresh = Schema.Migrate(nil)
		T.ok(isFresh, "nil -> fresh profile")
		T.eq(fresh.Level, 1, "fresh level")

		local old = {
			Version = 0,
			Level = 7,
			Exp = 50,
			Gold = 1234,
			Titles = { "first_round" },
			Achievements = { first_round = true },
			Stats = { Wins = 5 },
			Equipped = { Human = "Patience" },
			Unlocked = { Patience = true },
			Custom = "keep me",
		}
		local before = TableUtil.deepCopy(old)
		local m, wasFresh = Schema.Migrate(old)
		T.ok(not wasFresh, "old data is not fresh")
		T.ok(TableUtil.deepEquals(old, before), "Migrate never mutates its input")
		T.eq(m.Version, Schema.Version, "version bumped")
		T.eq(m.Level, 7, "level kept")
		T.eq(m.Gold, 1234, "gold kept")
		T.eq(m.Stats.Wins, 5, "stat kept")
		T.eq(m.Stats.Rounds, 0, "missing stat filled")
		T.ok(m.Titles.first_round == true, "v0 title array migrated to a map")
		T.eq(m.Equipped.Human, "Patience", "owned equip kept")
		T.eq(m.Equipped.Monster, "ClassicSans", "missing equip filled")
		T.eq(m.Custom, "keep me", "unknown keys preserved")
		T.ok(m.Unlocked.Determination and m.Unlocked["FellSans:Default"], "free kits + default skins reconciled")

		local bad = {
			Level = -4,
			Exp = 0 / 0,
			Gold = "lots",
			Stats = "nope",
			Unlocked = { Justice = "yes", Integrity = true },
			Equipped = {
				Human = "FellSans",
				Monster = "EclipseSans",
				Skins = { ClassicSans = "Judge", Determination = "Default", Patience = "Nope" },
				Title = "wins_100",
				Trail = "ClassicSans:Soul",
			},
			Mastery = { ClassicSans = -5, Bravery = "x" },
			MonsterChance = math.huge,
			RolePreference = "Spectator",
			Quests = { Window = "x", List = { { Id = "Nope" }, { Id = "Parries", Progress = 99, Goal = 5 }, 5 } },
			Login = { Streak = 3 },
			Settings = {
				MusicVolume = 3,
				SfxVolume = 0.5,
				Bogus = 1,
				MenuTheme = "Void",
				DamageNumbers = "yes",
				FieldOfView = 72,
			},
		}
		local s = Schema.Migrate(bad)
		T.eq(s.Level, 1, "negative level clamped")
		T.eq(s.Exp, 0, "NaN exp reset")
		T.eq(s.Gold, 0, "non-number gold reset")
		T.eq(s.Stats.Wins, 0, "non-table stats rebuilt")
		T.ok(s.Unlocked.Justice == nil, "non-true unlock dropped")
		T.ok(s.Unlocked.Integrity == true, "true unlock kept")
		T.eq(s.Equipped.Human, "Determination", "monster kit in the human slot reset")
		T.eq(s.Equipped.Monster, "ClassicSans", "unowned monster reset")
		T.ok(s.Equipped.Skins.ClassicSans == nil, "unowned skin unequipped")
		T.ok(s.Equipped.Skins.Determination == nil, "Default is not stored")
		T.ok(s.Equipped.Skins.Patience == nil, "unknown skin dropped")
		T.eq(s.Equipped.Title, "", "unowned title cleared")
		T.eq(s.Equipped.Trail, "", "unowned trail cleared")
		T.ok(s.Mastery.ClassicSans == nil and s.Mastery.Bravery == nil, "bad mastery values dropped")
		T.eq(s.MonsterChance, 1, "inf weight reset")
		T.eq(s.RolePreference, "Either", "bad role preference reset")
		T.eq(s.Quests.Window, -1, "bad window reset")
		T.eq(#s.Quests.List, 1, "invalid quests dropped")
		T.eq(s.Quests.List[1].Progress, 5, "progress clamped to the goal")
		T.eq(s.Login.Streak, 3, "streak kept")
		T.eq(s.Login.Best, 3, "best >= streak")
		T.ok(s.Settings.MusicVolume == nil, "out-of-range setting dropped")
		T.eq(s.Settings.SfxVolume, 0.5, "valid setting kept")
		T.ok(s.Settings.Bogus == nil, "unknown setting dropped")
		T.eq(s.Settings.MenuTheme, "Void", "enum setting kept")
		T.ok(s.Settings.DamageNumbers == nil, "wrong type dropped")
		T.ok(s.Settings.FieldOfView == nil, "value equal to the default is not stored")

		local newer = Schema.Migrate({ Version = 99, Level = 3 })
		T.eq(newer.Version, 99, "newer data is never downgraded")
		local again = Schema.Migrate(s)
		T.ok(TableUtil.deepEquals(again, s), "Migrate is idempotent")
	end,

	schema_settings_and_rules = function(T, Loader)
		local Schema = mod(Loader, "ProfileSchema")
		local Config = shared(Loader, "Config")
		local Presets = shared(Loader, "Graphics.Presets")
		local ok, v = Schema.ValidateSetting("MusicVolume", 0.5)
		T.ok(ok and v == 0.5, "volume ok")
		T.ok(not Schema.ValidateSetting("MusicVolume", 1.5), "volume range")
		T.ok(not Schema.ValidateSetting("MusicVolume", "loud"), "volume type")
		T.ok(not Schema.ValidateSetting("MusicVolume", 0 / 0), "volume NaN")
		ok, v = Schema.ValidateSetting("FieldOfView", 80.123456)
		T.eq(v, 80.123, "numbers rounded to 3 decimals")
		T.ok(Schema.ValidateSetting("MenuTheme", "Royal"), "theme ok")
		T.ok(not Schema.ValidateSetting("MenuTheme", "Pink"), "theme enum")
		T.ok(Schema.ValidateSetting("GraphicsPreset", "MapDefault"), "MapDefault preset")
		T.ok(Schema.ValidateSetting("GraphicsPreset", Presets.Ids()[1]), "real preset id")
		T.ok(not Schema.ValidateSetting("GraphicsPreset", "NoSuchPreset"), "unknown preset")
		T.ok(Schema.ValidateSetting("RigStyle", "Glow"), "rig style")
		T.ok(Schema.ValidateSetting("Language", "ru"), "language")
		T.ok(not Schema.ValidateSetting("Language", "de"), "language enum")
		T.ok(Schema.ValidateSetting("DamageNumbers", false), "boolean")
		T.ok(not Schema.ValidateSetting("DamageNumbers", 0), "boolean type")
		T.ok(not Schema.ValidateSetting("Bogus", 1), "unknown key")
		T.ok(not Schema.ValidateSetting(5, 1), "non-string key")
		for key in Config.Defaults do
			T.ok(Schema.Settings()[key] ~= nil, "whitelist covers Config.Defaults." .. key)
		end
		for _, key in { "GraphicsQuality", "Sensitivity" } do
			T.ok(Schema.Settings()[key] ~= nil, "whitelist covers the Settings screen key " .. key)
		end
		for key, spec in Schema.Settings() do
			T.ok(Schema.ValidateSetting(key, spec.Default), "default value validates: " .. key)
		end
		local p = Schema.Default()
		p.Settings.MusicVolume = 0.2
		local eff = Schema.EffectiveSettings(p)
		T.eq(eff.MusicVolume, 0.2, "override applied")
		T.eq(eff.SfxVolume, Config.Defaults.SfxVolume, "default filled")

		T.ok(Schema.CanEquipKit(p, "Determination"), "free kit equippable")
		T.eq(select(2, Schema.CanEquipKit(p, "Justice")), "prog.err.notOwned", "locked kit")
		T.eq(select(2, Schema.CanEquipKit(p, "Nope")), "prog.err.unknownItem", "unknown kit")
		T.eq(select(3, Schema.CanEquipKit(p, "ClassicSans")), "Monster", "role of the kit")
		T.ok(Schema.CanEquipSkin(p, "Determination", "Default"), "default skin")
		T.eq(select(2, Schema.CanEquipSkin(p, "Determination", "Storyshift")), "prog.err.notOwned", "unowned skin")
		T.ok(Schema.CanSetTitle(p, ""), "clearing the title")
		T.eq(select(2, Schema.CanSetTitle(p, "first_win")), "prog.err.notOwned", "unowned title")
		T.eq(select(2, Schema.CanSetTitle(p, "nope")), "prog.err.unknownItem", "unknown title")
		T.ok(Schema.CanEquipTrail(p, ""), "clearing the trail")
		T.eq(select(2, Schema.CanEquipTrail(p, "ClassicSans:Soul")), "prog.err.notOwned", "locked trail")
		T.eq(Schema.ParseRolePref("Monster"), "Monster", "pref string")
		T.eq(Schema.ParseRolePref({ pref = "Human" }), "Human", "pref table")
		T.ok(Schema.ParseRolePref("Spectator") == nil, "bad pref")
	end,

	schema_view = function(T, Loader)
		local Schema = mod(Loader, "ProfileSchema")
		local Quests = mod(Loader, "Quests")
		local Shop = mod(Loader, "Shop")
		local Achievements = mod(Loader, "Achievements")
		local p = Schema.Default()
		p.Quests = { Window = 5, List = Quests.Generate(1, 5), Rerolled = false }
		local now = 5 * 43200 + 100
		local v = Schema.View(p, { Now = now, Persistent = true })
		T.ok(v ~= p and v.Unlocked ~= p.Unlocked, "view is a deep copy")
		T.eq(#v.ShopToday.Offers, Shop.PerDay, "today's shop included")
		T.eq(v.ShopToday.Day, Shop.Day(now), "shop day")
		T.eq(v.Meta.ExpToNext, 100, "exp to next")
		T.eq(v.Meta.QuestWindowEndsAt, 6 * 43200, "quest window end")
		T.eq(#v.Meta.QuestRewards, 3, "quest rewards")
		T.ok(v.Settings.MusicVolume ~= nil, "effective settings")
		T.ok(v.Meta.Persistent == true, "persistent flag")
		T.eq(v.Meta.AchievementsTotal, Achievements.Count(), "achievement total")
		T.ok(v.Meta.FirstWinAvailable == true, "first win available")
		T.ok(p.ShopToday == nil and p.Meta == nil, "the stored profile never gets view fields")
		local function walk(t, depth)
			for _, value in t do
				T.ok(type(value) ~= "function", "view holds no functions")
				if type(value) == "table" and depth < 8 then
					walk(value, depth + 1)
				end
			end
		end
		walk(v, 0)
	end,

	-- Levels -------------------------------------------------------------------------------------------
	levels_math = function(T, Loader)
		local Levels = mod(Loader, "Levels")
		local Config = shared(Loader, "Config")
		T.eq(Levels.ExpToNext(1), Config.Progression.ExpBase, "LV1 -> 2")
		T.eq(Levels.ExpToNext(2), 160, "LV2 -> 3 = 100 + 60")
		T.eq(Levels.ExpToNext(10), 100 + 60 * 9, "LV10")
		T.eq(Levels.ExpToNext(Levels.MaxLevel), math.huge, "max level")
		for lv = 1, 80 do
			local total = Levels.TotalExp(lv, 7)
			local l2, e2 = Levels.FromTotal(total)
			T.eq(l2, lv, "FromTotal level " .. lv)
			T.eq(e2, 7, "FromTotal exp " .. lv)
		end
		local lv, exp, gained = Levels.Add(1, 90, 100 + 160 + 5)
		T.eq(lv, 3, "multi level-up")
		T.eq(exp, 95, "carry")
		T.eq(gained, 2, "levels gained")
		lv, exp, gained = Levels.Add(Levels.MaxLevel - 1, 0, 1e9)
		T.eq(lv, Levels.MaxLevel, "capped")
		T.eq(exp, 0, "no exp at max")
		T.eq(gained, 1, "one level to the cap")
		lv, exp, gained = Levels.Add(5, 10, -3)
		T.ok(lv == 5 and exp == 10 and gained == 0, "negative amounts ignored")
		lv, exp = Levels.Clamp(0 / 0, -1)
		T.ok(lv == 1 and exp == 0, "clamp NaN")
		local wantLv, wantExp = 2, 1000
		while wantExp >= Levels.ExpToNext(wantLv) do
			wantExp -= Levels.ExpToNext(wantLv)
			wantLv += 1
		end
		lv, exp = Levels.Clamp(2, 1000)
		T.ok(lv == wantLv and exp == wantExp and lv == 6 and exp == 0, "over-full bar carried into levels")
		T.eq(Levels.LevelUpGold(9), Config.Progression.LevelUpGold, "regular level gold")
		T.eq(Levels.LevelUpGold(10), Config.Progression.LevelUpGold * 5, "milestone level gold")
		T.eq(Levels.GoldForLevels(8, 10), Levels.LevelUpGold(9) + Levels.LevelUpGold(10), "gold for a range")
		T.near(Levels.Progress(1, 50), 0.5, 1e-9, "progress")
		T.eq(Levels.Progress(Levels.MaxLevel, 0), 1, "progress at max")
	end,

	-- Rewards ------------------------------------------------------------------------------------------
	rewards_from_rows = function(T, Loader)
		local Rewards = mod(Loader, "Rewards")
		local Config = shared(Loader, "Config")
		local R = Config.Rewards
		local function f(x)
			return math.floor(x + 1e-6)
		end
		local human = row(11, { damage = 500, kills = 1, saves = 2, revives = 1, parries = 3, survived = true })
		local monster = row(12, { team = "Monster", kitId = "ClassicSans", damage = 900, kills = 2 })
		local res = result({ winner = "Humans", reason = "Defeated", rows = { human, monster }, mvpUserId = 11 })
		local ctx = Rewards.Context(res, human, { firstWinAvailable = true })
		T.ok(ctx.won and ctx.role == "Human" and ctx.mvp, "context")
		local b = Rewards.Compute(ctx)
		local exp = R.Participation.Exp
			+ R.Win.Exp
			+ f(500 * R.PerDamage.Exp)
			+ R.Kill.Exp
			+ 2 * R.Save.Exp
			+ R.Revive.Exp
			+ 3 * R.Parry.Exp
			+ R.MVP.Exp
			+ R.FirstWinOfDay.Exp
		local gold = R.Participation.Gold
			+ R.Win.Gold
			+ f(500 * R.PerDamage.Gold)
			+ R.Kill.Gold
			+ 2 * R.Save.Gold
			+ R.Revive.Gold
			+ 3 * R.Parry.Gold
			+ R.MVP.Gold
			+ R.FirstWinOfDay.Gold
		T.eq(b.exp, exp, "winner exp")
		T.eq(b.gold, gold, "winner gold")
		T.ok(b.firstWin, "first win of the day")
		local sumE, sumG = 0, 0
		local keys = {}
		for _, item in b.items do
			sumE += item.exp
			sumG += item.gold
			keys[item.key] = item
		end
		T.ok(sumE == b.exp and sumG == b.gold, "items add up")
		T.eq(keys["prog.reward.damage"].count, 500, "item count")
		T.ok(keys["prog.reward.healing"] == nil, "zero items are omitted")

		local mctx = Rewards.Context(res, monster, { firstWinAvailable = true })
		local mb = Rewards.Compute(mctx)
		T.ok(not mctx.won and not mb.firstWin, "loser gets no win / first win")
		T.eq(mb.exp, R.Participation.Exp + f(900 * R.PerDamage.Exp) + 2 * R.Kill.Exp, "loser exp")

		local pres =
			result({ winner = "Humans", reason = "Defeated", rows = { human }, practice = true, mvpUserId = 11 })
		local pb = Rewards.Compute(Rewards.Context(pres, human, { firstWinAvailable = true }))
		T.ok(not pb.firstWin and pb.practice, "no first win in practice")
		local expected = 0
		for _, item in b.items do
			if item.key ~= "prog.reward.firstWin" then
				expected += f(item.exp * R.PracticeMult)
			end
		end
		T.eq(pb.exp, expected, "practice multiplier per item")

		local huge = row(13, { damage = 1e9, kills = 1000 })
		local hb = Rewards.Compute(Rewards.Context(result({ rows = { huge } }), huge))
		T.ok(
			hb.exp
				<= R.Participation.Exp
					+ R.Win.Exp
					+ Rewards.Caps.damage * R.PerDamage.Exp
					+ Rewards.Caps.kills * R.Kill.Exp,
			"caps"
		)

		local quit = result({ winner = "Humans", reason = "Left", rows = { human }, durations = { round = 12 } })
		T.ok(not Rewards.Context(quit, human).won, "instant leave is not a free win")
		local late = result({ winner = "Humans", reason = "Left", rows = { human }, durations = { round = 150 } })
		T.ok(Rewards.Context(late, human).won, "leaving mid-fight still counts as a win")
		T.ok(not Rewards.ShouldReward({ reason = "Aborted", rows = {} }), "aborted rounds give nothing")
		T.ok(Rewards.ShouldReward(res), "normal round")
		T.ok(not Rewards.ShouldReward(nil), "nil result")

		local a = row(1, { survived = true })
		local c = row(2, { survived = false })
		local lres = result({ winner = "Humans", reason = "Survived", rows = { a, c }, durations = { collapse = 30 } })
		local lctx = Rewards.Context(lres, a)
		T.ok(lctx.lastStanding and lctx.collapse, "last human standing + collapse")
		T.ok(not Rewards.Context(lres, c).lastStanding, "the fallen one is not last standing")
	end,

	rewards_grant_and_login = function(T, Loader)
		local Rewards = mod(Loader, "Rewards")
		local Levels = mod(Loader, "Levels")
		local Schema = mod(Loader, "ProfileSchema")
		local p = Schema.Default()
		local g = Rewards.Grant(p, 100 + 160 + 10, 50)
		T.eq(p.Level, 3, "grant levels")
		T.eq(p.Exp, 10, "grant exp")
		T.eq(g.LevelsGained, 2, "levels gained")
		T.eq(g.LevelGold, Levels.LevelUpGold(2) + Levels.LevelUpGold(3), "level gold")
		T.eq(p.Gold, 50 + g.LevelGold, "gold")
		T.eq(p.Stats.ExpEarned, 270, "exp earned")
		T.eq(p.Stats.GoldEarned, 50 + g.LevelGold, "gold earned")

		T.eq((Rewards.LoginStreak(0, 0, 100)), 1, "first login")
		local s, new = Rewards.LoginStreak(100, 5, 100)
		T.ok(s == 5 and not new, "same day")
		s, new = Rewards.LoginStreak(100, 5, 101)
		T.ok(s == 6 and new, "next day")
		T.eq((Rewards.LoginStreak(100, 10, 103)), 10 - 2 * Rewards.STREAK_DECAY + 1, "soft decay over 2 missed days")
		T.eq((Rewards.LoginStreak(100, 3, 120)), 1, "long absence floors at 1")
		s, new = Rewards.LoginStreak(100, 4, 99)
		T.ok(s == 4 and not new, "clock going backwards")
		T.eq(Rewards.StreakGold(1), 25, "day 1 gold")
		T.eq(Rewards.StreakGold(2), 40, "day 2 gold")
		T.eq(Rewards.StreakGold(6), 100, "cap")
		T.eq(Rewards.StreakGold(7), 200, "weekly bonus")
		T.eq(Rewards.StreakGold(8), 100, "after the bonus")
		T.eq(Rewards.StreakGold(14), 200, "second week bonus")
		local q = Schema.Default()
		T.ok(Rewards.FirstWinAvailable(q, 500), "first win available")
		q.Login.FirstWinDay = 500
		T.ok(not Rewards.FirstWinAvailable(q, 500), "used today")
		T.ok(Rewards.FirstWinAvailable(q, 501), "back tomorrow")
		T.eq(Rewards.Day(86400 * 3 + 5), 3, "UTC day")
	end,

	-- Quests -------------------------------------------------------------------------------------------
	quests_determinism_and_variety = function(T, Loader)
		local Quests = mod(Loader, "Quests")
		local Config = shared(Loader, "Config")
		local TableUtil = shared(Loader, "Util.TableUtil")
		T.ok(#Quests.Templates() >= 30, "30+ quest templates")
		local a = Quests.Generate(12345, 4000)
		local b = Quests.Generate(12345, 4000)
		T.ok(TableUtil.deepEquals(a, b), "same (user, window) -> same quests")
		T.eq(#a, Config.Quests.PerWindow, "quests per window")
		local seen = {}
		local monsterWindows = 0
		for w = 1, 300 do
			local list = Quests.Generate(777, w)
			T.eq(#list, 3, "three quests")
			local present = {}
			local hard = 0
			for _, q in list do
				local t = Quests.Get(q.Id)
				T.ok(t ~= nil, "known template")
				T.ok(not present[q.Id], "distinct quests")
				present[q.Id] = true
				T.ok(table.find(t.Goals, q.Goal) ~= nil, "goal from the template")
				T.ok(q.Progress == 0 and q.Claimed == false, "fresh state")
				if t.Difficulty >= 3 then
					hard += 1
				end
				if t.Role == "Monster" then
					monsterWindows += 1
				end
				seen[q.Id] = true
			end
			T.ok(hard <= 1, "at most one hard quest")
			T.eq(Quests.Get(list[1].Id).Role, "Any", "slot 1 = any role")
			T.eq(Quests.Get(list[2].Id).Role, "Human", "slot 2 = human")
		end
		local distinct = 0
		for _ in seen do
			distinct += 1
		end
		T.ok(distinct >= #Quests.Templates() - 2, "variety: " .. distinct .. " templates seen in 300 windows")
		T.ok(monsterWindows > 100 and monsterWindows < 260, "monster slot ~60 %: " .. monsterWindows)
		local same = 0
		for u = 1, 50 do
			if TableUtil.deepEquals(Quests.Generate(u, 9), Quests.Generate(u + 1000, 9)) then
				same += 1
			end
		end
		T.ok(same < 10, "different users get different quests")
		local changed = 0
		for w = 1, 50 do
			if not TableUtil.deepEquals(Quests.Generate(5, w), Quests.Generate(5, w + 1)) then
				changed += 1
			end
		end
		T.ok(changed >= 45, "consecutive windows differ")
		for w = 1, 100 do
			for _, q in Quests.Generate(5, w, { NoMonster = true }) do
				T.ok(Quests.Get(q.Id).Role ~= "Monster", "NoMonster respected")
			end
		end
		T.eq(Quests.Window(0), 0, "window 0")
		T.eq(Quests.Window(12 * 3600 - 1), 0, "window end")
		T.eq(Quests.Window(12 * 3600), 1, "window 1")
		T.eq(Quests.WindowEndsAt(1), 24 * 3600, "window ends at")
	end,

	quests_tracking = function(T, Loader)
		local Quests = mod(Loader, "Quests")
		local Rewards = mod(Loader, "Rewards")
		local function q(id, goal)
			return { Id = id, Progress = 0, Goal = goal, Claimed = false }
		end
		local list =
			{ q("Parries", 5), q("MonsterKills", 3), q("BoxCombo", 2), q("DealDamage", 800), q("WinRounds", 1) }
		T.eq(#Quests.TrackStat(list, "Kills", 2, "Human", false), 0, "role filter")
		Quests.TrackStat(list, "Kills", 2, "Monster", false)
		T.eq(list[2].Progress, 2, "monster kills")
		local ch = Quests.TrackStat(list, "Kills", 5, "Monster", true)
		T.eq(list[2].Progress, 3, "practice allowed + capped")
		T.ok(ch[1] and ch[1].Completed, "completion reported")
		T.eq(#Quests.TrackStat(list, "Kills", 1, "Monster", false), 0, "no progress past the goal")
		Quests.TrackStat(list, "Win", 1, "Human", true)
		T.eq(list[5].Progress, 0, "wins in practice don't count")
		Quests.TrackStat(list, "Win", 1, "Human", false)
		T.eq(list[5].Progress, 1, "real win counts")
		Quests.TrackStat(list, "BoxHits", 2, "Monster", false)
		T.eq(list[3].Progress, 0, "per-event threshold")
		Quests.TrackStat(list, "BoxHits", 4, "Monster", false)
		T.eq(list[3].Progress, 1, "per-event counts 1")
		Quests.TrackStat(list, "Damage", 12.34, "Human", false)
		T.near(list[4].Progress, 12.3, 1e-9, "fractional progress rounded to 0.1")
		T.eq(#Quests.TrackStat(list, "Damage", 0 / 0, "Human", false), 0, "NaN ignored")

		local rlist =
			{ q("PlayRounds", 2), q("BeMvp", 1), q("SwiftVerdict", 1), q("PracticeRound", 1), q("ParryRound", 1) }
		local r = row(5, { parries = 3 })
		local ctx = Rewards.Context(result({ winner = "Humans", reason = "Survived", rows = { r }, mvpUserId = 5 }), r)
		Quests.TrackRound(rlist, ctx)
		T.eq(rlist[1].Progress, 1, "played a round")
		T.eq(rlist[2].Progress, 1, "mvp")
		T.eq(rlist[3].Progress, 0, "monster quest ignores a human")
		T.eq(rlist[4].Progress, 0, "practice quest ignores real rounds")
		T.eq(rlist[5].Progress, 1, "parry threshold in one round")
		local pctx = Rewards.Context(result({ practice = true, rows = { r } }), r)
		Quests.TrackRound(rlist, pctx)
		T.eq(rlist[1].Progress, 1, "practice is not a played round")
		T.eq(rlist[4].Progress, 1, "practice quest")

		local e, g = Quests.Claim(rlist[2])
		T.ok(e and e > 0 and g and g > 0, "claim rewards")
		T.ok(rlist[2].Claimed, "claimed")
		T.ok(Quests.Claim(rlist[2]) == nil, "no double claim")
		T.ok(Quests.Claim(rlist[1]) == nil, "incomplete can't be claimed")
		local small = Quests.RewardFor({ Id = "Parries", Goal = 5 })
		local big = Quests.RewardFor({ Id = "Parries", Goal = 12 })
		T.ok(big > small, "bigger goal, bigger reward")

		local qs = { Window = 10, List = Quests.Generate(42, 10), Rerolled = false }
		local before = ids(qs.List)
		local ok = Quests.Reroll(qs, 3, 42, 10)
		T.ok(ok and qs.Rerolled, "reroll")
		T.ok(not contains(before, qs.List[3].Id), "rerolled into a new quest")
		T.eq(qs.List[1].Id, before[1], "other quests untouched")
		local ok2, err2 = Quests.Reroll(qs, 2, 42, 10)
		T.ok(not ok2 and err2 == "prog.err.rerollUsed", "one reroll per window")
		local qs2 = { Window = 10, List = Quests.Generate(42, 10), Rerolled = false }
		Quests.Reroll(qs2, 3, 42, 10)
		T.eq(qs2.List[3].Id, qs.List[3].Id, "reroll is deterministic")
		local qs3 = { Window = 10, List = { q("Parries", 5) }, Rerolled = false }
		qs3.List[1].Progress = 5
		T.eq(select(2, Quests.Reroll(qs3, 1, 42, 10)), "prog.err.questDone", "completed quests can't be rerolled")
		T.eq(select(2, Quests.Reroll(qs3, 1, 42, 11)), "prog.err.questExpired", "old window")

		local roll = {
			Window = 9,
			List = { { Id = "Parries", Progress = 5, Goal = 5, Claimed = false }, q("Saves", 2) },
			Rerolled = true,
		}
		local left = Quests.Refresh(roll, 42, 10)
		T.ok(left and #left == 1 and left[1].Id == "Parries", "unclaimed completed quests returned for auto-claim")
		T.ok(roll.Window == 10 and not roll.Rerolled and #roll.List == 3, "rolled over")
		T.ok(Quests.Refresh(roll, 42, 10) == nil, "same window: nothing to do")
		local clean = Quests.SanitizeList({ { Id = "Saves", Progress = -3, Goal = 777 }, "junk", { Id = "Nope" } })
		T.ok(#clean == 1 and clean[1].Goal == 2 and clean[1].Progress == 0, "sanitized list")
	end,

	-- Shop ---------------------------------------------------------------------------------------------
	shop_rotation = function(T, Loader)
		local Shop = mod(Loader, "Shop")
		local Kits = shared(Loader, "Kits")
		local TableUtil = shared(Loader, "Util.TableUtil")
		local catalog = Shop.Catalog()
		T.ok(#catalog >= Shop.PerDay, "catalog large enough")
		for _, item in catalog do
			local skin = Kits.Skin(item.KitId, item.SkinId)
			T.ok(skin and skin.Price > 0 and skin.Mastery == nil, "catalog = priced non-mastery skins: " .. item.Key)
		end
		local captured = {}
		for d = 20000, 20060 do
			captured[d] = TableUtil.deepCopy(Shop.Daily(d))
		end
		for d = 30000, 30020 do
			Shop.Daily(d) -- evicts the cache
		end
		for d = 20000, 20060 do
			T.ok(TableUtil.deepEquals(Shop.Daily(d), captured[d]), "deterministic day " .. d)
		end
		local appeared = {}
		local prevKeys = nil
		for d = 20000, 20060 do
			local s = Shop.Daily(d)
			T.eq(#s.Offers, Shop.PerDay, "offers per day")
			T.eq(s.EndsAt, (d + 1) * 86400, "ends at midnight UTC")
			local keys = {}
			local featured = 0
			local bestRank = 0
			local rank = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }
			for _, o in s.Offers do
				bestRank = math.max(bestRank, rank[o.Rarity])
			end
			for _, o in s.Offers do
				T.ok(not keys[o.Key], "distinct offers")
				keys[o.Key] = true
				appeared[o.Key] = true
				if o.Featured then
					featured += 1
					T.eq(o.Price, math.floor(o.BasePrice * 0.8 / 10 + 0.5) * 10, "featured -20 %")
					T.ok(o.Price < o.BasePrice, "featured is cheaper")
					T.eq(rank[o.Rarity], bestRank, "featured = rarest of the day")
				else
					T.eq(o.Price, o.BasePrice, "regular price")
				end
			end
			T.eq(featured, 1, "exactly one featured offer")
			if prevKeys and #catalog >= 3 * Shop.PerDay then
				for key in keys do
					T.ok(not prevKeys[key], "no repeat from yesterday on day " .. d .. ": " .. key)
				end
			end
			prevKeys = keys
		end
		for _, item in catalog do
			T.ok(appeared[item.Key], "every skin rotates in within 60 days: " .. item.Key)
		end
		local offer = Shop.Daily(20000).Offers[1]
		local price, isFeatured = Shop.PriceFor(offer.KitId, offer.SkinId, 20000)
		T.ok(price == offer.Price and isFeatured == offer.Featured, "PriceFor matches today's shop")
		T.ok(Shop.PriceFor("ClassicSans", "Monochrome", 20000) == nil, "mastery skins are not for sale")
	end,

	shop_purchase_rules = function(T, Loader)
		local Shop = mod(Loader, "Shop")
		local Schema = mod(Loader, "ProfileSchema")
		local Kits = shared(Loader, "Kits")
		local day = 20000
		local p = Schema.Default()
		local fell = { Kind = "Kit", KitId = "FellSans" }
		T.eq(select(2, Shop.CheckBuy(p, fell, day)), "prog.err.level", "kit level gate")
		p.Level = 3
		local ok, err, price = Shop.CheckBuy(p, fell, day)
		T.ok(not ok and err == "prog.err.gold" and price == 1200, "not enough gold reports the price")
		p.Gold = 5000
		ok, err, price = Shop.CheckBuy(p, fell, day)
		T.ok(ok and price == 1200, "kit purchasable")
		Shop.Apply(p, fell, price)
		T.eq(p.Gold, 3800, "gold spent")
		T.ok(p.Unlocked.FellSans and p.Unlocked["FellSans:Default"], "kit unlocked")
		T.eq(select(2, Shop.CheckBuy(p, fell, day)), "prog.err.owned", "already owned")
		T.eq(
			select(2, Shop.CheckBuy(p, { Kind = "Skin", KitId = "Patience", SkinId = "Frost" }, day)),
			"prog.err.needKit",
			"skin needs its kit"
		)
		T.eq(
			select(2, Shop.CheckBuy(p, { Kind = "Skin", KitId = "ClassicSans", SkinId = "Monochrome" }, day)),
			"prog.err.masteryOnly",
			"mastery skin"
		)
		T.eq(
			select(2, Shop.CheckBuy(p, { Kind = "Skin", KitId = "ClassicSans", SkinId = "Default" }, day)),
			"prog.err.owned",
			"default skin"
		)
		T.eq(
			select(2, Shop.CheckBuy(p, { Kind = "Skin", KitId = "Nope", SkinId = "X" }, day)),
			"prog.err.unknownItem",
			"unknown kit"
		)
		for _, kit in Kits.All() do
			p.Unlocked[kit.Id] = true
		end
		p.Gold = 100000
		for _, o in Shop.Daily(day).Offers do
			local okSkin, _, skinPrice = Shop.CheckBuy(p, { Kind = "Skin", KitId = o.KitId, SkinId = o.SkinId }, day)
			T.ok(okSkin and skinPrice == o.Price, "daily price applied: " .. o.Key)
		end
		local skinItem = Shop.ParseItem({ kitId = "FellSans", skinId = "Ash" })
		T.eq(skinItem.Kind, "Skin", "parse skin")
		T.eq(Shop.ParseItem({ KitId = "FellSans" }).Kind, "Kit", "parse kit (PascalCase)")
		T.ok(Shop.ParseItem({ kind = "Skin", kitId = "FellSans" }) == nil, "skin without id")
		T.ok(Shop.ParseItem("FellSans") == nil, "non-table")
		T.ok(Shop.ParseItem({ kitId = "../x" }) == nil, "bad characters")
		T.ok(Shop.ParseItem({ kind = "Robux", kitId = "FellSans" }) == nil, "unknown kind")
	end,

	-- Mastery / Achievements / Titles ----------------------------------------------------------------------
	mastery_rewards = function(T, Loader)
		local Mastery = mod(Loader, "Mastery")
		local Schema = mod(Loader, "ProfileSchema")
		local Kits = shared(Loader, "Kits")
		T.eq(Mastery.Level(0), 1, "level 1")
		T.eq(Mastery.Level(399), 1, "still 1")
		T.eq(Mastery.Level(400), 2, "level 2")
		T.eq(Mastery.Level(1e9), Mastery.MaxLevel, "cap")
		local p = Schema.Default()
		local r = Mastery.Apply(p, "Determination", 400 * 9 + 10)
		T.ok(r.From == 1 and r.To == 10, "1 -> 10")
		T.eq(p.Gold, 100 + 250 + 400 + 600, "mastery gold ladder")
		T.ok(p.Unlocked["Determination:Crimson"], "Mastery-10 legendary skin")
		T.ok(Schema.OwnsSkin(p, "Determination", "Crimson"), "owns it")
		T.ok(p.Titles.m_Determination_3 and p.Titles.m_Determination_6 and p.Titles.m_Determination_10, "titles")
		T.ok(p.Unlocked["trail:Determination:Soul"] and p.Unlocked["trail:Determination:Prism"], "trails")
		T.eq(#Mastery.Apply(p, "Determination", 5000).Rewards, 0, "nothing twice")
		T.eq(Mastery.Apply(p, "Nope", 500).To, 1, "unknown kit ignored")

		local q = Schema.Default()
		q.Mastery.ClassicSans = 3600
		Schema.Sanitize(q)
		T.ok(q.Unlocked["ClassicSans:Monochrome"], "Sanitize re-grants mastery skins")
		T.ok(q.Titles.m_ClassicSans_10, "and titles")
		T.eq(q.Gold, 0, "but never gold")
		for _, kit in Kits.All() do
			for _, skin in kit.Skins do
				if skin.Mastery then
					local found = false
					for _, reward in Mastery.RewardsBetween(kit.Id, 1, Mastery.MaxLevel) do
						if reward.Kind == "Skin" and reward.Id == kit.Id .. ":" .. skin.Id then
							found = true
						end
					end
					T.ok(found, "SkinDef.Mastery skin is a mastery reward: " .. kit.Id .. ":" .. skin.Id)
				end
			end
			for _, kind in { "Soul", "Prism" } do
				local trail = Mastery.Trail(Mastery.TrailId(kit.Id, kind))
				T.ok(trail and #trail.Colors == 2 and typeof(trail.Colors[1]) == "Color3", "trail " .. kit.Id .. kind)
			end
		end
	end,

	achievements_and_titles = function(T, Loader)
		local Achievements = mod(Loader, "Achievements")
		local Titles = mod(Loader, "Titles")
		local Schema = mod(Loader, "ProfileSchema")
		local Rewards = mod(Loader, "Rewards")
		local Kits = shared(Loader, "Kits")
		T.ok(Achievements.Count() >= 30, "30+ achievements")
		local p = Schema.Default()
		T.eq(#Achievements.Check(p), 0, "nothing at start")
		p.Stats.Rounds = 1
		p.Stats.Wins = 1
		local got = Achievements.Check(p)
		T.ok(contains(got, "first_round") and contains(got, "first_win"), "first round + first win")
		T.ok(not contains(got, "rounds_25"), "not yet 25")
		for _, id in got do
			T.ok(Achievements.Grant(p, id), "grant " .. id)
		end
		T.ok(p.Titles.first_round and p.Titles.first_win, "titles granted")
		T.eq(p.Gold, 2 * Achievements.GoldByRarity.Common, "gold by rarity")
		T.ok(not Achievements.Grant(p, "first_round"), "no double grant")
		T.eq(#Achievements.Check(p), 0, "nothing new")
		local v, goal = Achievements.Progress(p, "rounds_25")
		T.ok(v == 1 and goal == 25, "progress")
		p.Level = 10
		T.ok(contains(Achievements.Check(p), "level_10"), "level achievement")

		local hero = row(1, { damage = 0, survived = true })
		local res = result({
			winner = "Humans",
			reason = "Survived",
			rows = { hero, row(2), row(3, { team = "Monster", kitId = "ClassicSans" }) },
			durations = { collapse = 40 },
		})
		local feats = Achievements.Check(p, Rewards.Context(res, hero))
		T.ok(
			contains(feats, "pacifist") and contains(feats, "collapse_survivor") and contains(feats, "clutch"),
			"round feats"
		)
		local pres = result({ winner = "Humans", reason = "Survived", rows = { hero, row(2) }, practice = true })
		T.ok(not contains(Achievements.Check(p, Rewards.Context(pres, hero)), "pacifist"), "no feats in practice")
		local mon = row(9, { team = "Monster", kitId = "FellSans", kills = 3 })
		local mres = result({ winner = "Monster", reason = "Eliminated", rows = { mon, row(1), row(2) } })
		local mfeats = Achievements.Check(p, Rewards.Context(mres, mon, { finalPhase = false }))
		T.ok(contains(mfeats, "no_mercy") and contains(mfeats, "unshaken"), "monster feats")

		T.eq(#Titles.All(), Achievements.Count() + #Kits.All() * 3, "titles = achievements + 3 per kit")
		for _, t in Titles.All() do
			local text = Titles.Text(t.Id)
			T.ok(text.en ~= t.Id and text.en ~= "" and text.ru ~= "" and text.ru ~= t.Id, "title text " .. t.Id)
			T.eq(typeof(Titles.Color(t.Id)), "Color3", "title colour")
			T.ok(string.match(Titles.ColorHex(t.Id), "^#%x%x%x%x%x%x$") ~= nil, "hex colour")
			T.ok(Titles.RarityColor[t.Rarity] ~= nil, "rarity " .. t.Rarity)
		end
		for _, a in Achievements.List() do
			T.ok(Titles.Has(a.Title), "achievement title registered: " .. a.Id)
		end
	end,

	-- Strings ------------------------------------------------------------------------------------------
	strings_progression = function(T, Loader)
		local S = Loader.require("ReplicatedStorage.Shared.Strings.Progression")
		local Strings = shared(Loader, "Strings")
		local Quests = mod(Loader, "Quests")
		local Achievements = mod(Loader, "Achievements")
		local count = 0
		for key, v in S do
			count += 1
			T.eq(string.sub(key, 1, 5), "prog.", "prefix " .. key)
			T.ok(type(v.en) == "string" and v.en ~= "" and type(v.ru) == "string" and v.ru ~= "", "en+ru " .. key)
			T.eq(placeholders(v.ru), placeholders(v.en), "same placeholders in en/ru: " .. key)
		end
		T.ok(count > 200, "progression strings: " .. count)
		T.ok(Strings.Has("prog.quest.PlayRounds"), "merged into Strings")
		for _, t in Quests.Templates() do
			T.ok(S[Quests.TextKey(t.Id)] ~= nil, "quest text " .. t.Id)
		end
		for _, a in Achievements.List() do
			T.ok(S[Achievements.NameKey(a.Id)] and S[Achievements.DescKey(a.Id)], "achievement text " .. a.Id)
		end
		local files = table.clone(MY_FILES)
		for _, name in SERVICES do
			table.insert(files, "src/server/Services/" .. name .. ".luau")
		end
		for _, path in files do
			local source = fs.readFile(path)
			for key in string.gmatch(source, '"(prog%.[%w_%.]+)"') do
				if string.sub(key, -1) ~= "." then
					T.ok(S[key] ~= nil, "string key used in " .. path .. " exists: " .. key)
				end
			end
		end
	end,

	-- RequestService ------------------------------------------------------------------------------------
	request_parsers = function(T, Loader)
		local RS = Loader.require("ServerScriptService.Server.Services.RequestService")
		local Parse = RS.Parse
		T.eq(Parse.KitId("FellSans"), "FellSans", "kit string")
		T.eq(Parse.KitId({ kitId = "Patience" }), "Patience", "kit table")
		T.eq(Parse.KitId({ KitId = "Patience" }), "Patience", "kit PascalCase")
		T.ok(Parse.KitId("") == nil and Parse.KitId(5) == nil, "bad kit values")
		T.ok(Parse.KitId(string.rep("a", 41)) == nil, "too long")
		T.ok(Parse.KitId("bad id!") == nil, "bad characters")
		local k, s = Parse.Skin({ kitId = "FellSans", skinId = "Ash" })
		T.ok(k == "FellSans" and s == "Ash", "skin")
		T.ok(Parse.Skin({ kitId = "FellSans" }) == nil, "skin needs both ids")
		T.eq(Parse.Title(nil), "", "nil title clears")
		T.eq(Parse.Title({ titleId = "first_win" }), "first_win", "title table")
		T.ok(Parse.Title({ titleId = 5 }) == nil, "title type")
		T.eq(Parse.Trail("ClassicSans:Soul"), "ClassicSans:Soul", "trail id with colon")
		local key, value = Parse.Setting({ key = "MusicVolume", value = 0.3 })
		T.ok(key == "MusicVolume" and value == 0.3, "setting")
		T.ok(Parse.Setting({ value = 1 }) == nil and Parse.Setting("MusicVolume") == nil, "setting shape")
		T.eq(Parse.QuestIndex(2), 2, "quest index")
		T.eq(Parse.QuestIndex({ index = 3 }), 3, "quest index table")
		T.ok(Parse.QuestIndex(0) == nil and Parse.QuestIndex(1.5) == nil and Parse.QuestIndex(99) == nil, "index range")
		T.eq(select(2, Parse.QuestIndex({ id = "Parries" })), "Parries", "quest id")
		T.ok(RS.PayloadOk({ kitId = "X" }), "small table ok")
		T.ok(RS.PayloadOk(nil) and RS.PayloadOk(true) and RS.PayloadOk(3), "scalars ok")
		T.ok(not RS.PayloadOk({ a = { b = { c = { d = 1 } } } }), "too deep")
		T.ok(not RS.PayloadOk(string.rep("x", 500)), "string too long")
		local big = {}
		for i = 1, 20 do
			big["k" .. i] = i
		end
		T.ok(not RS.PayloadOk(big), "too many keys")
		T.ok(not RS.PayloadOk(roblox.Instance.new("Folder")), "instances rejected")
		T.ok(not RS.PayloadOk(0 / 0), "NaN rejected")
	end,

	request_dispatch = function(T, Loader)
		local RS = Loader.require("ServerScriptService.Server.Services.RequestService")
		T.noerror(RS.Init, "RequestService.Init")
		for _, action in
			{
				"EquipKit",
				"EquipSkin",
				"EquipTrail",
				"SetTitle",
				"SetSetting",
				"SetRolePref",
				"Buy",
				"ClaimQuest",
				"RerollQuest",
			}
		do
			T.ok(RS.Has(action), "built-in action " .. action)
		end
		local called = nil
		RS.Register("SetRolePref", function(_, data)
			called = data
			return true
		end)
		local p1 = fakePlayer(101)
		T.ok(RS.Dispatch(p1, "SetRolePref", "Monster"), "a service handler replaces the built-in")
		T.eq(called, "Monster", "handler got the payload")
		T.eq(select(2, RS.Dispatch(p1, 5, nil)), "prog.err.badRequest", "non-string action")
		local ok, err = RS.Dispatch(p1, "NoSuchAction", nil)
		T.ok(not ok and err == nil, "unknown actions are ignored")
		T.eq(
			select(2, RS.Dispatch(p1, "EquipKit", { a = { b = { c = { d = 1 } } } })),
			"prog.err.badRequest",
			"payload guard"
		)
		local p2 = fakePlayer(102)
		T.eq(select(2, RS.Dispatch(p2, "EquipKit", "Determination")), "prog.err.notReady", "no profile yet")
		T.eq(select(2, RS.Dispatch(p2, "EquipKit", "Determination")), "prog.err.rateLimited", "per-action gap")
		local p3 = fakePlayer(103)
		local limited = 0
		for i = 1, 40 do
			local action = "Spam" .. (i % 20)
			if i <= 20 then
				RS.Register(action, function()
					return true
				end)
			end
			local _, e = RS.Dispatch(p3, action, nil)
			if e == "prog.err.rateLimited" then
				limited += 1
			end
		end
		T.ok(limited >= 20, "token bucket limits bursts: " .. limited)
		RS.Register("Boom", function()
			error("handler exploded (expected in this test)")
		end)
		T.noerror(function()
			RS.Dispatch(fakePlayer(104), "Boom", nil)
		end, "handler errors are contained")
		local okFail, errFail = RS.Dispatch(fakePlayer(105), "EquipSkin", { kitId = "FellSans" })
		T.ok(not okFail and errFail == "prog.err.badRequest", "skin payload validated")
	end,

	-- DataService lock protocol -----------------------------------------------------------------------------
	data_lock_transforms = function(T, Loader)
		local DS = Loader.require("ServerScriptService.Server.Services.DataService")
		local Config = shared(Loader, "Config")
		local timeout = Config.Data.SessionLockTimeout
		local function args(extra)
			local a = { JobId = "A", Id = "s1", PlaceId = 1, Now = 10000, Timeout = timeout, Force = false }
			for k, v in extra or {} do
				a[k] = v
			end
			return a
		end
		local rec, holder = DS.AcquireTransform(nil, args())
		T.ok(rec and holder == nil and rec.Session.Id == "s1" and rec.Data == nil, "fresh key: lock taken, no data")
		rec = DS.AcquireTransform({ Version = 1, Level = 5 }, args())
		T.eq(rec.Data.Level, 5, "legacy bare profile normalised")
		local function stored(time, job)
			return { Data = { Level = 9 }, Session = { JobId = job or "B", Id = "s9", Time = time } }
		end
		rec, holder = DS.AcquireTransform(stored(9900), args())
		T.ok(rec == nil and holder and holder.JobId == "B", "live foreign lock blocks the load")
		rec = DS.AcquireTransform(stored(10000 - timeout - 1), args())
		T.ok(rec and rec.Session.JobId == "A" and rec.Data.Level == 9, "stale lock stolen, data kept")
		rec = DS.AcquireTransform(stored(9990), args({ Force = true }))
		T.ok(rec and rec.Session.Id == "s1", "force steal")
		rec = DS.AcquireTransform(stored(9990, "A"), args())
		T.ok(rec and rec.Session.Id == "s1", "a lock of this same server is taken over")

		local cur = { Data = { Level = 1 }, Session = { JobId = "A", Id = "s1", Time = 10000 } }
		local out, lost = DS.SaveTransform(
			cur,
			{ JobId = "A", Id = "s1", PlaceId = 1, Now = 10100, Release = false, Data = { Level = 2 } }
		)
		T.ok(
			out and not lost and out.Data.Level == 2 and out.Session.Time == 10100 and out.SavedAt == 10100,
			"autosave refreshes the lock"
		)
		out, lost = DS.SaveTransform(
			out,
			{ JobId = "A", Id = "s1", PlaceId = 1, Now = 10200, Release = true, Data = { Level = 3 } }
		)
		T.ok(out and not lost and out.Session == nil and out.Data.Level == 3, "release clears the lock")
		out, lost =
			DS.SaveTransform(stored(10150, "C"), { JobId = "A", Id = "s1", Now = 10300, Release = false, Data = {} })
		T.ok(out == nil and lost, "a stolen lock refuses our write")
		out, lost = DS.SaveTransform(
			{ Data = { Level = 7 } },
			{ JobId = "A", Id = "s1", Now = 10300, Release = true, Data = {} }
		)
		T.ok(out == nil and lost, "no lock = not ours")
	end,

	data_session_flow = function(T, Loader)
		local DS = Loader.require("ServerScriptService.Server.Services.DataService")
		local TableUtil = shared(Loader, "Util.TableUtil")
		local fake = { data = {}, calls = 0 }
		function fake:UpdateAsync(key, fn)
			self.calls += 1
			local old = self.data[key]
			local new = fn(if old ~= nil then TableUtil.deepCopy(old) else nil)
			if new ~= nil then
				self.data[key] = TableUtil.deepCopy(new)
			end
			return if new ~= nil then TableUtil.deepCopy(new) else nil
		end
		DS._TestSetup({ Store = fake, Mode = "DataStore", JobId = "J1" })

		local p = fakePlayer(501)
		DS._StartSession(p)
		local profile = DS.Get(p)
		T.ok(profile ~= nil and DS.IsReady(p) and DS.IsPersistent(p), "new player loaded")
		T.eq(profile.Level, 1, "default profile")
		T.ok(profile.Created > 0, "created stamp")
		T.eq(fake.data.u_501.Session.JobId, "J1", "lock taken")
		T.eq(p:GetAttribute("Level"), 1, "attributes replicated")
		T.eq(p:GetAttribute("EquippedHuman"), "Determination", "equipped attribute")
		DS.Update(p, function(pr)
			pr.Gold = 777
		end)
		T.ok(DS._Save(p), "autosave")
		T.eq(fake.data.u_501.Data.Gold, 777, "saved data")
		T.ok(fake.data.u_501.Session ~= nil, "autosave keeps the lock")
		DS._ReleaseSession(p)
		T.ok(fake.data.u_501.Session == nil, "release clears the lock")
		T.ok(DS.Get(p) == nil, "session dropped")

		local p2 = fakePlayer(501)
		DS._StartSession(p2)
		T.eq(DS.Get(p2).Gold, 777, "progress survives a rejoin")
		fake.data.u_501.Session = { JobId = "J2", Id = "other", Time = os.time() }
		fake.data.u_501.Data.Gold = 999
		DS.Update(p2, function(pr)
			pr.Gold = 1
		end)
		T.ok(not DS._Save(p2), "save refused after another server took the lock")
		T.ok(not DS.IsPersistent(p2), "session stops saving")
		DS._ReleaseSession(p2)
		T.eq(fake.data.u_501.Data.Gold, 999, "the newer server's data is never overwritten")

		fake.data.u_777 =
			{ Data = { Level = 4, Gold = 50 }, Session = { JobId = "dead", Id = "x", Time = os.time() - 10000 } }
		local p3 = fakePlayer(777)
		DS._StartSession(p3)
		T.ok(DS.Get(p3) and DS.Get(p3).Level == 4, "stale lock stolen, data loaded")
		T.eq(fake.data.u_777.Session.JobId, "J1", "lock is ours now")
		DS._ReleaseSession(p3)

		fake.data.u_888 = { Version = 1, Level = 6, Gold = 10 }
		local p4 = fakePlayer(888)
		DS._StartSession(p4)
		T.eq(DS.Get(p4).Level, 6, "legacy bare profile loads")
		DS._ReleaseSession(p4)
		T.eq(fake.data.u_888.Data.Level, 6, "and is re-saved in the record format")

		local before = fake.calls
		DS._TestSetup({ Store = fake, Mode = "Memory", JobId = "J1" })
		local p5 = fakePlayer(999)
		DS._StartSession(p5)
		T.ok(DS.Get(p5) ~= nil and not DS.IsPersistent(p5), "memory mode profile")
		DS._ReleaseSession(p5)
		T.eq(fake.calls, before, "memory mode never touches the DataStore")
		T.ok(fake.data.u_999 == nil, "nothing stored")
	end,

	reward_service_round = function(T, Loader)
		local base = "ServerScriptService.Server.Services."
		local DS = Loader.require(base .. "DataService")
		local Net = shared(Loader, "Net")
		local Config = shared(Loader, "Config")
		for _, name in { "RequestService", "MasteryService", "QuestService", "AchievementService", "RewardService" } do
			Loader.require(base .. name).Init()
		end
		local Reward = Loader.require(base .. "RewardService")
		local Rewards = mod(Loader, "Rewards")
		DS._TestSetup({ Store = nil, Mode = "Memory", JobId = "J1" })
		local p = fakePlayer(1201)
		DS._StartSession(p)
		T.ok(DS.Get(p) ~= nil, "memory profile")
		local fired = {}
		local original = Net.Server.Fire
		Net.Server.Fire = function(name, player, ...)
			table.insert(fired, { name = name, player = player, args = { ... } })
		end
		local me = row(1201, { damage = 640, kills = 1, saves = 1, parries = 4, survived = true })
		local res = result({
			winner = "Humans",
			reason = "Defeated",
			rows = { me, row(-1, { team = "Monster", kitId = "ClassicSans" }) },
			mvpUserId = 1201,
		})
		local ok, err = pcall(Reward.Process, res, function(userId)
			return if userId == 1201 then p else nil
		end)
		Net.Server.Fire = original
		T.ok(ok, "Process ran: " .. tostring(err))
		local profile = DS.Get(p)
		T.eq(profile.Stats.Rounds, 1, "round counted")
		T.eq(profile.Stats.Wins, 1, "win counted")
		T.eq(profile.Stats.HumanWins, 1, "human win counted")
		T.eq(profile.Stats.Damage, 640, "damage total")
		T.eq(profile.Stats.MVPs, 1, "mvp counted")
		T.ok(profile.Level >= 2, "levelled up: LV " .. profile.Level)
		T.ok((profile.Mastery.Determination or 0) > 0, "kit mastery exp")
		T.ok(profile.Achievements.first_round and profile.Achievements.first_win, "achievements unlocked")
		T.ok(profile.Titles.first_win, "achievement title")
		T.eq(profile.Login.FirstWinDay, Rewards.Day(os.time()), "first win of the day used")
		local packet = nil
		for _, f in fired do
			if f.name == "RoundEvent" and f.args[1] == "Rewards" then
				packet = f.args[2]
			end
		end
		T.ok(packet ~= nil, "Rewards packet sent")
		if packet then
			T.ok(packet.exp > 0 and packet.gold > 0 and packet.levelUp, "packet totals + level up")
			T.ok(packet.firstWin, "packet first win")
			local sumG = 0
			for _, item in packet.items do
				sumG += item.gold
			end
			T.eq(sumG, packet.gold, "packet items add up")
			T.ok(contains(packet.unlocked, "achievement:first_win"), "unlocked list")
			T.ok(packet.mastery and packet.mastery.kitId == "Determination", "mastery step")
			T.eq(packet.level, profile.Level, "packet level")
		end
		local gold = profile.Gold
		Net.Server.Fire = function() end
		Reward.Process(res, function(userId)
			return if userId == 1201 then p else nil
		end)
		Net.Server.Fire = original
		local again = DS.Get(p)
		T.eq(again.Stats.Rounds, 2, "second round counted")
		T.ok(again.Gold - gold < Config.Rewards.FirstWinOfDay.Gold + 200, "no second first-win bonus")
		Reward.Process(result({ reason = "Aborted", rows = { me } }), function()
			return p
		end)
		T.eq(DS.Get(p).Stats.Rounds, 2, "aborted rounds are ignored")
		DS._ReleaseSession(p)
	end,

	-- Services smoke test ------------------------------------------------------------------------------------
	services_compile_load_init = function(T, Loader)
		for _, name in SERVICES do
			local path = "src/server/Services/" .. name .. ".luau"
			T.ok(fs.isFile(path), name .. " exists")
			local source = fs.readFile(path)
			T.eq(string.sub(source, 1, 9), "--!strict", name .. " is strict")
			local ok, err = pcall(luau.compile, source)
			T.ok(ok, name .. " compiles: " .. tostring(err))
			local okLoad, svc = pcall(Loader.require, "ServerScriptService.Server.Services." .. name)
			T.ok(okLoad, name .. " loads: " .. tostring(svc))
			if okLoad then
				T.ok(type(svc.Priority) == "number", name .. " has Priority")
				T.ok(type(svc.Init) == "function" and type(svc.Start) == "function", name .. " has Init/Start")
				T.noerror(svc.Init, name .. ".Init under mocks")
			end
		end
		local DS = Loader.require("ServerScriptService.Server.Services.DataService")
		local RS = Loader.require("ServerScriptService.Server.Services.RequestService")
		T.ok(DS.Priority == 5 and RS.Priority == 6, "SPEC priorities P5 / P6")
		for _, name in SERVICES do
			if name ~= "DataService" and name ~= "RequestService" then
				T.ok(Loader.require("ServerScriptService.Server.Services." .. name).Priority >= 70, name .. " is P70+")
			end
		end
		T.ok(DS.Get(fakePlayer(1)) == nil and not DS.IsReady(fakePlayer(1)), "no profile before load")
		T.ok(not DS.Update(fakePlayer(1), function() end), "Update without a profile is a no-op")
	end,
}
