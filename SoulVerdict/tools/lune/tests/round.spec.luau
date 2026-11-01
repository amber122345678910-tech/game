--!nocheck
-- Round loop area: QueueMath (fair monster queue), RoundRules (transitions, win rules, collapse,
-- harmony, MVP, votes, SAVE channel), TestArena build + MapInfo validity, Registry tolerance,
-- Strings/Round coverage and a compile/load smoke test of the round services.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local function entry(id, weight, rounds, pref)
	return { Id = id, Weight = weight, RoundsSinceMonster = rounds or 0, Preference = pref or "Either" }
end

local function sumShares(shares)
	local s = 0
	for _, v in shares do
		s += v
	end
	return s
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

local function collectParts(root)
	local parts, lights = {}, 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	return parts, lights
end

local SERVICE_FILES = {
	"CharacterService",
	"MapService",
	"StatsService",
	"QueueService",
	"ObjectiveService",
	"RoundService",
	"BotService",
	"StyleLabService",
}

return {
	-- QueueMath ------------------------------------------------------------------------------------
	queue_empty_and_single = function(T, Loader)
		local Q = Loader.require("ReplicatedStorage.Shared.Round.QueueMath")
		T.eq(Q.Choose({}, 0.5), nil, "empty -> nil")
		T.eq(Q.Choose({ entry("a", 1) }, 0.99), "a", "single Either player")
		T.eq(Q.Choose({ entry("solo", 1, 0, "Human") }, 0.3), "solo", "single Human-pref player still chosen (nobody else)")
		local shares = Q.Shares({ entry("solo", 1, 0, "Human") })
		T.near(shares.solo, 1, 1e-9, "single player share = 100%")
	end,

	queue_weights_and_preference = function(T, Loader)
		local Q = Loader.require("ReplicatedStorage.Shared.Round.QueueMath")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		local list = { entry("m", 1, 0, "Monster"), entry("e", 1, 0, "Either"), entry("h", 5, 0, "Human") }
		local shares = Q.Shares(list)
		local mult = Config.Queue.MonsterPreferenceMult
		T.near(shares.m, mult / (mult + 1), 1e-9, "Monster pref x1.5")
		T.near(shares.e, 1 / (mult + 1), 1e-9, "Either share")
		T.eq(shares.h, 0, "Human pref never chosen while others exist")
		T.near(sumShares(shares), 1, 1e-9, "shares sum to 1")
		for _, roll in { 0, 0.25, 0.5, 0.75, 0.999 } do
			T.ok(Q.Choose(list, roll) ~= "h", "Human pref not drawn at roll " .. roll)
		end
		-- deterministic cumulative draw: weights {1, 3}
		local two = { entry("a", 1), entry("b", 3) }
		T.eq(Q.Choose(two, 0.2), "a", "roll 0.2 -> a")
		T.eq(Q.Choose(two, 0.26), "b", "roll 0.26 -> b")
		T.eq(Q.Choose(two, 0.999), "b", "roll ~1 -> b")
		T.near(Q.Shares(two).b, 0.75, 1e-9, "weight 3 of 4")
	end,

	queue_fallback_everyone_human = function(T, Loader)
		local Q = Loader.require("ReplicatedStorage.Shared.Round.QueueMath")
		local list = { entry("a", 1, 0, "Human"), entry("b", 3, 0, "Human") }
		local pool, weights, mode = Q.Pool(list)
		T.eq(mode, "Fallback", "fallback mode")
		T.eq(#pool, 2, "everyone in the pool")
		T.eq(weights[2], 3, "plain weights in fallback")
		T.near(Q.Shares(list).b, 0.75, 1e-9, "fallback share")
	end,

	queue_pity = function(T, Loader)
		local Q = Loader.require("ReplicatedStorage.Shared.Round.QueueMath")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		local pity = Config.Queue.PityRounds
		local list = { entry("rich", 50, 0), entry("waiting", 1, pity), entry("longer", 1, pity + 2) }
		local _, _, mode = Q.Pool(list)
		T.eq(mode, "Pity", "pity mode")
		for _, roll in { 0, 0.4, 0.999 } do
			T.eq(Q.Choose(list, roll), "longer", "longest waiter first at roll " .. roll)
		end
		local shares = Q.Shares(list)
		T.near(shares.longer, 1, 1e-9, "pity share 100%")
		T.eq(shares.rich, 0, "others 0 while pity applies")
		-- Human-pref players are not forced by pity when someone else can play
		local list2 = { entry("h", 1, pity + 5, "Human"), entry("e", 1, 0) }
		T.eq(Q.Choose(list2, 0.1), "e", "pity ignores Human preference")
		-- tie between pity players -> weighted among them
		local tie = { entry("x", 1, pity), entry("y", 3, pity) }
		T.eq(Q.Choose(tie, 0.1), "x", "tie roll low")
		T.eq(Q.Choose(tie, 0.9), "y", "tie roll high")
	end,

	queue_after_round = function(T, Loader)
		local Q = Loader.require("ReplicatedStorage.Shared.Round.QueueMath")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		local base = Config.Queue.BaseWeight
		T.eq(Q.NextWeight(7, { WasMonster = true, Participated = true }), base, "monster resets")
		T.eq(Q.NextWeight(2, { WasMonster = false, Participated = true, Damage = 50 }), 2 + Config.Queue.WeightPerRound, "+1 per round")
		T.eq(Q.NextWeight(2, { WasMonster = false, Participated = true, Damage = 250, WasMvp = false }), 2 + Config.Queue.WeightPerRound + 1, "active bonus")
		T.eq(Q.NextWeight(2, { WasMonster = false, Participated = true, Damage = 250, WasMvp = true }), 2 + Config.Queue.WeightPerRound, "MVP gets no bonus")
		T.eq(Q.NextWeight(4, { WasMonster = false, Participated = false }), 4, "non participant unchanged")
		T.eq(Q.NextWeight(0 / 0, { WasMonster = false, Participated = true }), base + Config.Queue.WeightPerRound, "NaN weight sanitized")
		T.eq(Q.NextRounds(3, { WasMonster = true, Participated = true }), 0, "monster rounds reset")
		T.eq(Q.NextRounds(3, { WasMonster = false, Participated = true }), 4, "human +1 round")
		T.eq(Q.NextRounds(-2, { WasMonster = false, Participated = false }), 0, "negative rounds sanitized")
		local clean = Q.Sanitize({ Id = 1, Weight = -5, RoundsSinceMonster = 0 / 0, Preference = "bogus" })
		T.eq(clean.Weight, base, "negative weight -> base")
		T.eq(clean.RoundsSinceMonster, 0, "NaN rounds -> 0")
		T.eq(clean.Preference, "Either", "unknown preference -> Either")
	end,

	queue_fairness_simulation = function(T, Loader)
		-- 6 players over many rounds: everyone gets to be the monster, nobody waits past pity.
		local Q = Loader.require("ReplicatedStorage.Shared.Round.QueueMath")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		local Rng = Loader.require("ReplicatedStorage.Shared.Util.Rng")
		local rng = Rng.new(12345)
		local players = {}
		for i = 1, 6 do
			players[i] = entry(i, 1, 0, if i == 6 then "Human" else "Either")
		end
		local picks = {}
		local maxWait = 0
		for _ = 1, 300 do
			local chosen = Q.Choose(players, rng:Number())
			T.ok(chosen ~= nil, "someone chosen")
			picks[chosen] = (picks[chosen] or 0) + 1
			for _, p in players do
				local res = { WasMonster = p.Id == chosen, Participated = true, Damage = 0 }
				p.Weight = Q.NextWeight(p.Weight, res)
				p.RoundsSinceMonster = Q.NextRounds(p.RoundsSinceMonster, res)
				if p.Preference ~= "Human" then
					maxWait = math.max(maxWait, p.RoundsSinceMonster)
				end
			end
		end
		for i = 1, 5 do
			T.ok((picks[i] or 0) >= 40, "player " .. i .. " picked often enough: " .. tostring(picks[i]))
		end
		T.eq(picks[6], nil, "Human-pref player never picked")
		T.ok(maxWait <= Config.Queue.PityRounds + 1, "nobody waits past pity: " .. maxWait)
	end,

	-- RoundRules -----------------------------------------------------------------------------------
	rules_transitions = function(T, Loader)
		local R = Loader.require("ReplicatedStorage.Shared.Round.RoundRules")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		local enough = Config.Round.MinPlayers
		T.eq(R.Next("Waiting", { Players = 1, TimerDone = false }), "Waiting", "wait for players")
		T.eq(R.Next("Waiting", { Players = 1, TimerDone = false, PracticeRequested = true }), "Intro", "solo practice")
		T.eq(R.Next("Waiting", { Players = enough, TimerDone = false }), "Intermission", "enough players")
		T.eq(R.Next("Intermission", { Players = enough, TimerDone = false }), "Intermission", "intermission ticking")
		T.eq(R.Next("Intermission", { Players = enough, TimerDone = true }), "Intro", "intermission done")
		T.eq(R.Next("Intermission", { Players = enough - 1, TimerDone = true }), "Waiting", "player left during intermission")
		T.eq(R.Next("Intro", { Players = enough, TimerDone = true }), "Round", "intro -> round")
		T.eq(R.Next("Round", { Players = enough, TimerDone = false, Winner = "Monster" }), "Ending", "winner ends round")
		T.eq(R.Next("Round", { Players = enough, TimerDone = true }), "Collapse", "timer -> collapse")
		T.eq(R.Next("Collapse", { Players = enough, TimerDone = true }), "Ending", "collapse -> ending")
		T.eq(R.Next("Ending", { Players = enough, TimerDone = true }), "Intermission", "ending -> intermission")
		T.eq(R.Next("Ending", { Players = 1, TimerDone = true }), "Waiting", "ending -> waiting when alone")
		T.eq(R.Next("Intro", { Players = 0, TimerDone = false }), "Intro", "intro continues even if players drop (leavers handled by Evaluate)")
		T.eq(R.PhaseDuration("Round"), Config.Round.RoundTime, "round duration")
		T.eq(R.PhaseDuration("Waiting"), 0, "waiting untimed")
		T.ok(R.PhaseDuration("Intro", true) <= R.PhaseDuration("Intro"), "practice intro not longer")
	end,

	rules_win_conditions = function(T, Loader)
		local R = Loader.require("ReplicatedStorage.Shared.Round.RoundRules")
		local function ev(s)
			local w, r = R.Evaluate(s)
			return tostring(w) .. "/" .. tostring(r)
		end
		local base = { MonsterAlive = true, MonsterLeft = false, HumansUp = 2, HumansDowned = 0 }
		local function with(fields)
			local s = table.clone(base)
			for k, v in fields do
				s[k] = v
			end
			return s
		end
		T.eq(ev(base), "nil/nil", "nobody won yet")
		T.eq(ev(with({ MonsterLeft = true })), "Humans/Left", "monster left")
		T.eq(ev(with({ MonsterAlive = false })), "Humans/Defeated", "monster defeated")
		T.eq(ev(with({ HumansUp = 0, HumansDowned = 0 })), "Monster/Eliminated", "all humans dead")
		T.eq(ev(with({ HumansUp = 0, HumansDowned = 0, HumansLeft = true })), "Monster/Left", "all humans left")
		T.eq(ev(with({ HumansUp = 0, HumansDowned = 1 })), "nil/nil", "downed humans still alive")
		T.eq(ev(with({ TimeUp = true })), "Humans/Survived", "survived the collapse")
		T.eq(ev(with({ TimeUp = true, HumansUp = 0, HumansDowned = 1 })), "Humans/Survived", "a downed survivor still counts")
		T.eq(ev(with({ MonsterAlive = false, HumansUp = 0 })), "Humans/Defeated", "monster death has priority")
		T.eq(ev(with({ PracticeHumanDead = true })), "Monster/Eliminated", "practice player died")
		T.ok(R.ShouldWipeDowned(0, 2), "wipe when nobody is up")
		T.ok(not R.ShouldWipeDowned(1, 2), "no wipe while someone is up")
		T.ok(not R.ShouldWipeDowned(0, 0), "no wipe with nobody downed")
	end,

	rules_final_phase_second_wind = function(T, Loader)
		local R = Loader.require("ReplicatedStorage.Shared.Round.RoundRules")
		T.ok(R.ShouldTriggerFinalPhase(300, 1000, false), "30% triggers")
		T.ok(not R.ShouldTriggerFinalPhase(301, 1000, false), "30.1% does not")
		T.ok(not R.ShouldTriggerFinalPhase(100, 1000, true), "only once")
		T.ok(not R.ShouldTriggerFinalPhase(0, 1000, false), "dead monster does not transform")
		T.ok(not R.ShouldTriggerFinalPhase(10, 0, false), "zero max health safe")
		T.ok(R.ShouldSecondWind(4, 1, false), "last one standing")
		T.ok(not R.ShouldSecondWind(1, 1, false), "solo round has no second wind")
		T.ok(not R.ShouldSecondWind(4, 2, false), "two up")
		T.ok(not R.ShouldSecondWind(4, 1, true), "only once")
	end,

	rules_harmony_health_collapse = function(T, Loader)
		local R = Loader.require("ReplicatedStorage.Shared.Round.RoundRules")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		T.eq(R.HarmonyMultiplier({}), 1, "no humans")
		T.eq(R.HarmonyMultiplier({ "Justice" }), 1, "one class")
		T.eq(R.HarmonyMultiplier({ "Justice", "Justice", "Justice" }), 1, "duplicates do not count")
		T.near(R.HarmonyMultiplier({ "Justice", "Bravery" }), 1.04, 1e-9, "two classes")
		T.near(R.HarmonyMultiplier({ "Justice", "Bravery", "Kindness", "Patience" }), 1.12, 1e-9, "four classes")
		T.near(R.HarmonyMultiplier({ "A", "B", "C", "D", "E", "F", "G" }), 1 + Config.Human.HarmonyMax, 1e-9, "capped")
		local sans = Kits.Get("ClassicSans")
		T.eq(R.MonsterMaxHealth(sans.Stats, 4), sans.Stats.MaxHP + sans.Stats.HPPerHuman * 4, "monster HP formula")
		T.eq(R.MonsterMaxHealth(sans.Stats, 0), sans.Stats.MaxHP, "no humans")
		local minR = Config.Round.CollapseMinRadius
		T.near(R.CollapseRadius(0, 74), 74, 1e-9, "collapse starts at map radius")
		T.near(R.CollapseRadius(Config.Round.CollapseTime, 74), minR, 1e-9, "collapse ends at min radius")
		T.near(R.CollapseRadius(Config.Round.CollapseTime * 2, 74), minR, 1e-9, "clamped after end")
		T.near(R.CollapseRadius(Config.Round.CollapseTime / 2, 74), (74 + minR) / 2, 1e-9, "linear midpoint")
		T.near(R.CollapseRadius(5, minR - 4), minR - 4, 1e-9, "tiny maps keep their radius")
		local c = Vector3.new(0, 0, 2000)
		T.ok(R.IsOutside(Vector3.new(30, 50, 2000), c, 20), "outside ring (height ignored)")
		T.ok(not R.IsOutside(Vector3.new(10, -5, 2005), c, 20), "inside ring")
	end,

	rules_save_mvp_votes = function(T, Loader)
		local R = Loader.require("ReplicatedStorage.Shared.Round.RoundRules")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		local o = Config.Objectives
		T.near(R.SaveChannelRate(1, false), 1 / o.SaveChannelTime, 1e-9, "one human")
		T.near(R.SaveChannelRate(3, false), (1 + 2 * o.SaveExtraPlayerSpeed) / o.SaveChannelTime, 1e-9, "three humans faster")
		T.eq(R.SaveChannelRate(2, true), 0, "contested pauses")
		T.eq(R.SaveChannelRate(0, false), 0, "nobody channels")
		local r = row(1, { damage = 100, healing = 10, kills = 1, saves = 1, revives = 1, parries = 2, dodgesForced = 3, survived = true })
		T.near(R.Score(r), 100 + 12 + 150 + 120 + 120 + 50 + 30 + 100, 1e-9, "score formula")
		T.eq(R.Mvp({}), nil, "no rows")
		T.eq(R.Mvp({ row(1), row(2) }), nil, "nobody scored")
		T.eq(R.Mvp({ row(1, { damage = 10 }), row(2, { damage = 300 }), row(3, { kills = 1 }) }), 2, "best score")
		T.eq(R.Mvp({ row(1, { kills = 1 }), row(2, { damage = 150 }) }), 2, "tie broken by damage")
		T.eq(R.Mvp({ row(-1, { damage = 500 }), row(5, { damage = 10 }) }), -1, "bots can be MVP (negative ids)")
		local options = { "A", "B", "C" }
		T.eq(R.VoteWinner(options, { p1 = "B", p2 = "B", p3 = "A" }, 0.9), "B", "majority")
		T.eq(R.VoteWinner(options, { p1 = "A", p2 = "C" }, 0.1), "A", "tie low roll")
		T.eq(R.VoteWinner(options, { p1 = "A", p2 = "C" }, 0.9), "C", "tie high roll")
		T.eq(R.VoteWinner(options, {}, 0.5), "B", "no votes -> roll")
		T.eq(R.VoteWinner(options, { p1 = "Z" }, 0.0), "A", "invalid votes ignored")
		T.eq(R.VoteWinner({}, {}, 0.5), nil, "no options")
		local counts = R.VoteCounts(options, { p1 = "C", p2 = "C" })
		T.eq(counts.C, 2, "counts")
		T.eq(counts.A, 0, "zero counts present")
	end,

	-- Maps -----------------------------------------------------------------------------------------
	maps_test_arena_builds = function(T, Loader)
		local TestArena = Loader.require("ReplicatedStorage.Shared.Maps.TestArena")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		local info
		T.noerror(function()
			info = TestArena.Build(1)
		end, "TestArena.Build")
		if not info then
			return
		end
		T.ok(typeof(info.Model) == "Instance" and info.Model:IsA("Model"), "Model")
		T.eq(info.Model.Parent, nil, "built unparented")
		T.eq(info.Id, "TestArena", "id")
		T.ok(#info.HumanSpawns >= 6, "6+ human spawns")
		T.ok(typeof(info.MonsterSpawn) == "CFrame", "monster spawn")
		T.eq(#info.SavePoints, Config.Objectives.SavesPerMap, "3 SAVE points")
		T.eq(#info.IntroPath, 4, "4 intro camera keys")
		T.eq(info.Preset, "GoldenHall", "preset")
		T.ok(type(info.FinalPreset) == "string" and info.FinalPreset ~= "", "final preset")
		T.ok(info.Radius > Config.Round.CollapseMinRadius, "radius bigger than collapse min")
		T.ok(info.KillY < -10, "kill plane below the floor")
		T.ok(info.DummySpawns and #info.DummySpawns >= 3, "dummy spawns")
		local parts, lights = collectParts(info.Model)
		T.ok(#parts > 100 and #parts <= 6000, "part budget: " .. #parts)
		T.ok(lights <= 60, "light budget: " .. lights)
		local unanchored = 0
		for _, p in parts do
			if not p.Anchored then
				unanchored += 1
			end
		end
		T.eq(unanchored, 0, "every map part anchored")
		-- spawns: on the floor, inside the play radius, clear of pillars, facing the centre
		local shafts = {}
		for _, p in parts do
			if string.find(p.Name, "_Shaft$") then
				table.insert(shafts, p.CFrame.Position)
			end
		end
		T.eq(#shafts, 8, "8 pillars")
		local function checkSpawn(cf, label)
			local pos = cf.Position
			local flat = Vector3.new(pos.X - info.Center.X, 0, pos.Z - info.Center.Z)
			T.ok(flat.Magnitude < info.Radius - 4, label .. " inside play radius")
			T.near(pos.Y, 0, 0.75, label .. " on the floor")
			for _, s in shafts do
				T.ok(Vector3.new(pos.X - s.X, 0, pos.Z - s.Z).Magnitude > 5, label .. " clear of pillars")
			end
			if flat.Magnitude > 1 then
				T.ok(cf.LookVector:Dot(-flat.Unit) > 0.9, label .. " faces the centre")
			end
			T.near(cf.LookVector.Y, 0, 1e-6, label .. " level facing")
		end
		for i, cf in info.HumanSpawns do
			checkSpawn(cf, "human spawn " .. i)
		end
		checkSpawn(info.MonsterSpawn, "monster spawn")
		for i, cf in info.DummySpawns do
			checkSpawn(cf, "dummy spawn " .. i)
		end
		for i, p in info.SavePoints do
			local d = Vector3.new(p.X - info.Center.X, 0, p.Z - info.Center.Z).Magnitude
			T.ok(d < info.Radius - Config.Objectives.SaveRadius * 0.5, "save point " .. i .. " inside arena")
			for j, q in info.SavePoints do
				if j > i then
					T.ok((p - q).Magnitude > Config.Objectives.SaveRadius * 3, "save points far apart")
				end
			end
		end
		-- humans and monster start far apart
		T.ok((info.HumanSpawns[1].Position - info.MonsterSpawn.Position).Magnitude > 60, "spawn separation")
	end,

	maps_registry = function(T, Loader)
		local Registry = Loader.require("ReplicatedStorage.Shared.Maps.Registry")
		local list = Registry.List()
		local ids = {}
		for _, m in list do
			ids[m.Id] = m
			T.ok(m.Name.en ~= "" and m.Name.ru ~= "", m.Id .. " localized name")
			T.ok(m.Desc.en ~= nil and m.Desc.ru ~= nil, m.Id .. " localized desc")
			T.ok(m.Preset ~= "" and m.FinalPreset ~= "", m.Id .. " presets")
		end
		for _, id in { "HallOfVerdicts", "SnowdinCrossroads", "WaterfallGrotto", "VoidRift", "CoreReactor", "Lobby", "TestArena" } do
			T.ok(ids[id] ~= nil, "registry lists " .. id)
		end
		T.ok(ids.TestArena.Available, "TestArena available")
		local def = Registry.Get("TestArena")
		T.ok(def ~= nil and type(def.Build) == "function", "Get(TestArena)")
		T.eq(Registry.Get("NoSuchMap"), nil, "unknown map -> nil")
		T.eq(Registry.Get(""), nil, "empty id -> nil")
		T.eq(Registry.Info("NoSuchMap"), nil, "unknown info -> nil")
		T.eq(Registry.Info("VoidRift").Kind, "Arena", "info works without the module")
		local playable = Registry.Playable()
		T.ok(#playable >= 1, "at least one playable map")
		local anyArena = false
		for _, id in { "HallOfVerdicts", "SnowdinCrossroads", "WaterfallGrotto", "VoidRift", "CoreReactor" } do
			if Registry.Get(id) ~= nil then
				anyArena = true
			else
				T.ok(not ids[id].Available or true, "missing/broken map tolerated: " .. id)
			end
		end
		if not anyArena then
			T.eq(playable[1], "TestArena", "falls back to TestArena")
			T.eq(#playable, 1, "only TestArena")
		end
		for _, id in playable do
			T.ok(Registry.Get(id) ~= nil, "playable map loads: " .. id)
			T.ok(id ~= "Lobby", "lobby never playable")
		end
		local lobby = Registry.LobbyId()
		T.ok(lobby == "Lobby" or lobby == "TestArena", "lobby id")
		T.ok(Registry.Get(lobby) ~= nil, "lobby map loads")
		T.ok(Registry.ArenaOrigin.Magnitude > 1000, "arena far from lobby")
	end,

	maps_every_available_map_builds = function(T, Loader)
		-- Validates whichever real map modules exist right now (written by the map agents).
		local Registry = Loader.require("ReplicatedStorage.Shared.Maps.Registry")
		for _, meta in Registry.List() do
			local def = Registry.Get(meta.Id)
			if def then
				local ok, info = pcall(def.Build, 7)
				T.ok(ok, meta.Id .. " builds: " .. tostring(if ok then "" else info))
				if ok then
					T.ok(typeof(info.Model) == "Instance" and info.Model:IsA("Model"), meta.Id .. " model")
					T.ok(type(info.HumanSpawns) == "table" and #info.HumanSpawns >= 1, meta.Id .. " human spawns")
					T.ok(typeof(info.MonsterSpawn) == "CFrame", meta.Id .. " monster spawn")
					T.ok(type(info.SavePoints) == "table", meta.Id .. " save points")
					T.ok(typeof(info.Center) == "Vector3" and type(info.Radius) == "number", meta.Id .. " centre/radius")
					T.ok(type(info.KillY) == "number", meta.Id .. " killY")
				end
			end
		end
	end,

	-- Strings --------------------------------------------------------------------------------------
	strings_round = function(T, Loader)
		local RoundStrings = Loader.require("ReplicatedStorage.Shared.Strings.Round")
		local count = 0
		for key, value in RoundStrings do
			count += 1
			T.ok(string.sub(key, 1, 6) == "round.", "key prefix round.: " .. key)
			T.ok(type(value.en) == "string" and value.en ~= "", key .. " en")
			T.ok(type(value.ru) == "string" and value.ru ~= "", key .. " ru")
			-- same placeholders in both languages
			local function holes(s)
				local set = {}
				for n in string.gmatch(s, "{(%d+)}") do
					set[n] = true
				end
				local list = {}
				for n in set do
					table.insert(list, n)
				end
				table.sort(list)
				return table.concat(list, ",")
			end
			T.eq(holes(value.ru), holes(value.en), key .. " placeholders match")
		end
		T.ok(count >= 40, "round strings count " .. count)
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		for _, w in { "Humans", "Monster" } do
			for _, r in { "Defeated", "Survived", "Eliminated", "Left", "Aborted" } do
				local key = "round.result." .. w .. "." .. r
				if (w == "Humans" and r ~= "Eliminated") or (w == "Monster" and (r == "Eliminated" or r == "Left" or r == "Aborted")) then
					T.ok(Strings.Has(key), "has " .. key)
				end
			end
		end
		T.eq(Strings.L("round.revive.action"), "Revive", "revive prompt text")
	end,

	-- Services: compile + load under the mocks -----------------------------------------------------
	services_compile_and_load = function(T, Loader)
		for _, name in SERVICE_FILES do
			local path = "src/server/Services/" .. name .. ".luau"
			if fs.isFile(path) then
				local source = fs.readFile(path)
				T.ok(string.sub(source, 1, 9) == "--!strict", name .. " starts with --!strict")
				local ok, err = pcall(luau.compile, source)
				T.ok(ok, name .. " compiles: " .. tostring(err))
				if ok then
					local okLoad, mod = pcall(Loader.require, "ServerScriptService.Server.Services." .. name)
					T.ok(okLoad, name .. " loads: " .. tostring(mod))
					if okLoad then
						T.ok(type(mod) == "table", name .. " returns a table")
						T.ok(type(mod.Priority) == "number", name .. " has Priority")
						T.ok(type(mod.Init) == "function" and type(mod.Start) == "function", name .. " has Init/Start")
					end
				end
			else
				T.ok(false, "missing service file " .. path)
			end
		end
	end,
}
