--!nocheck
-- Studio-readiness regressions (docs/STUDIO_REVIEW.md): behaviour that only differs when the place runs in
-- Roblox Studio — e.g. Test -> Local Server players have NEGATIVE UserIds (-1, -2, ...), so "userId > 0"
-- must never be used to tell players from bots.
-- Run: lune run tools/lune/run_tests.luau studio

local SERVICES = "ServerScriptService.Server.Services."

local function fakePlayer(userId)
	local attrs = {}
	return {
		Name = "Player" .. tostring(-userId),
		DisplayName = "Player" .. tostring(-userId),
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

local function row(userId, team)
	return {
		userId = userId,
		name = "P" .. tostring(userId),
		team = team or "Humans",
		kitId = if team == "Monster" then "ClassicSans" else "Determination",
		damage = 300,
		healing = 0,
		kills = 1,
		downs = 0,
		parries = 2,
		dodgesForced = 0,
		saves = 1,
		revives = 0,
		survived = true,
	}
end

-- runs fn with Players.GetPlayerByUserId mocked on the loader's shared Players mock, always restoring it
local function withPlayersLookup(moduleFn, lookup, fn)
	local playersMock = getfenv(moduleFn).game:GetService("Players")
	local original = rawget(playersMock, "GetPlayerByUserId")
	rawset(playersMock, "GetPlayerByUserId", function(_, id)
		return lookup(id)
	end)
	local ok, err = pcall(fn)
	rawset(playersMock, "GetPlayerByUserId", original)
	if not ok then
		error(err, 0)
	end
end

return {
	studio_bot_row_ids_never_collide_with_test_players = function(T, Loader)
		local Stats = Loader.require(SERVICES .. "StatsService")
		local Instance = Loader.roblox.Instance
		T.ok(type(Stats.BOT_ID_BASE) == "number" and Stats.BOT_ID_BASE <= -1000000, "bot id base far below 0")
		T.eq(Stats.IsBotId(-1), false, "Studio Player1 (-1) is not a bot")
		T.eq(Stats.IsBotId(-8), false, "Studio Player8 (-8) is not a bot")
		T.eq(Stats.IsBotId(12345), false, "real UserId is not a bot")
		T.eq(Stats.IsBotId(Stats.BOT_ID_BASE - 1), true, "bot row id")

		local player1 = fakePlayer(-1)
		local function model(name, owner, team, isBot)
			local m = Instance.new("Model")
			m.Name = name
			m:SetAttribute("OwnerUserId", owner)
			m:SetAttribute("Team", team)
			m:SetAttribute("KitId", if team == "Monster" then "FellSans" else "Determination")
			m:SetAttribute("IsBot", isBot)
			m:SetAttribute("DisplayName", name)
			return m
		end
		local me = model("Player1", -1, "Humans", false)
		local botA = model("BotA", 0, "Humans", true)
		local botB = model("BotB", 0, "Monster", true)
		withPlayersLookup(Stats.BeginRound, function(id)
			return if id == -1 then player1 else nil
		end, function()
			Stats.BeginRound({ me, botA, botB }, true)
			local rows = Stats.Rows()
			T.eq(#rows, 3, "one row per participant")
			local ids = {}
			for _, r in rows do
				ids[r.name] = r.userId
			end
			T.eq(ids.Player1, -1, "the Studio test player keeps its (negative) UserId")
			T.ok(Stats.IsBotId(ids.BotA) and Stats.IsBotId(ids.BotB), "bot rows use the bot id range")
			T.ok(ids.BotA ~= ids.BotB, "bot rows are distinct")
			T.ok(ids.BotA ~= -1 and ids.BotB ~= -1, "no bot row collides with Player1")
		end)
		Stats.Reset()
	end,

	studio_rewards_reach_negative_userid_players = function(T, Loader)
		local DS = Loader.require(SERVICES .. "DataService")
		local Net = Loader.require("ReplicatedStorage.Shared.Net")
		local Stats = Loader.require(SERVICES .. "StatsService")
		for _, name in { "RequestService", "MasteryService", "QuestService", "AchievementService", "RewardService" } do
			Loader.require(SERVICES .. name).Init()
		end
		local Reward = Loader.require(SERVICES .. "RewardService")
		local quiet = Loader.quietWarnings
		Loader.quietWarnings = true
		local ok, err = pcall(function()
			DS._TestSetup({ Store = nil, Mode = "Memory", JobId = "studio" })
			local p = fakePlayer(-2) -- Test -> Local Server "Player2"
			DS._StartSession(p)
			T.ok(DS.Get(p) ~= nil, "memory profile for a negative UserId")
			Net.Server.Fire = function() end -- no remotes offline (module is fresh per test: Loader.reset)
			local result = {
				winner = "Humans",
				reason = "Defeated",
				rows = { row(-2, "Humans"), row(Stats.BOT_ID_BASE - 1, "Monster") },
				mvpUserId = -2,
				practice = false,
				durations = { round = 200, collapse = 0, total = 230 },
				mapId = "TestArena",
				roundId = 1,
			}
			-- the resolver answers p for ANY id: the bot row must still be skipped by its id range
			Reward.Process(result, function()
				return p
			end)
			local profile = DS.Get(p)
			T.eq(profile.Stats.Rounds, 1, "the negative-UserId player was rewarded exactly once (bot row skipped)")
			T.eq(profile.Stats.Wins, 1, "win counted")
			T.ok(profile.Exp > 0 or profile.Level > 1, "exp granted")
			DS._ReleaseSession(p)
		end)
		Loader.quietWarnings = quiet
		T.ok(ok, "reward flow ran: " .. tostring(err))
	end,
}
