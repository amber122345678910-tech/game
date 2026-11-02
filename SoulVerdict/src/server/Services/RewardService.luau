--!strict
-- RewardService (P75): turns RoundService.RoundEnded into progression (SPEC §1.6, §12). For every real player
-- row of a rewarded round (not "Aborted"; bots and players who left are skipped), in ONE profile update:
--   lifetime Stats totals (practice rounds only count Stats.PracticeRounds), first-win-of-day flag,
--   EXP/G from Rewards.Compute (+ level-ups and their G), kit mastery (MasteryService), round quest progress
--   (QuestService, after flushing buffered stat progress) — then single-round + lifetime achievements
--   (AchievementService.Evaluate) and finally RoundEvent "Rewards" to that player:
--     { exp, gold, items = {{key, exp, gold, count?}}, levelUp: boolean, levels, newLevel, level, expInto,
--       expToNext, unlocked = {string}, questProgress = {{id, key, progress, goal, param, completed}},
--       mastery = {kitId, from, to, exp, into, need}?, firstWin: boolean, practice: boolean, practiceMult }
--   item keys are Strings keys ("prog.reward.*", count = {1}); unlocked ids: "title:<id>", "trail:<id>",
--   "skin:<kitId>:<skinId>", "achievement:<id>". Toasts: level up, mastery level, quest completions, achievements.
-- Verdict Box stats (BoxesSurvived / BoxHits) are event-only in StatsService, so they are counted here from
-- StatsService.StatEvent between RoundStarted and RoundEnded.
--
-- API: none beyond SPEC (consumes RoundEnded / StatEvent). Process(result, resolvePlayer?) is exposed for
-- tests/tools (resolvePlayer(userId) -> Player? replaces Players:GetPlayerByUserId).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Progression = Shared:WaitForChild("Progression")
local Rewards = require(Progression:WaitForChild("Rewards")) :: any
local Levels = require(Progression:WaitForChild("Levels")) :: any
local Mastery = require(Progression:WaitForChild("Mastery")) :: any

local RewardService = {}
RewardService.Priority = 75

local STAT_CAP = 100000 -- per-round sanity cap for lifetime counters

local DataService: any = nil
local RoundService: any = nil
local StatsService: any = nil
local QuestService: any = nil
local AchievementService: any = nil
local MasteryService: any = nil

local boxStats: { [number]: { BoxesSurvived: number, BoxHits: number } } = {}

local function tryService(name: string): any
	local module = (script.Parent :: Instance):FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function notify(player: Player, key: string, args: { any }?, style: string?)
	if player.Parent then
		pcall(Net.Server.Fire, "Notify", player, key, args, style)
	end
end

local function n(v: any): number
	if type(v) == "number" and v == v then
		return math.clamp(math.floor(v), 0, STAT_CAP)
	end
	return 0
end

local function addStat(stats: any, key: string, amount: number)
	stats[key] = (stats[key] or 0) + amount
end

-- Lifetime totals (mutates). Practice rounds never feed the real record / leaderboards.
local function applyStats(profile: any, ctx: any)
	local s = profile.Stats
	if ctx.practice then
		addStat(s, "PracticeRounds", 1)
		return
	end
	local row = ctx.row
	addStat(s, "Rounds", 1)
	addStat(s, if ctx.role == "Monster" then "MonsterRounds" else "HumanRounds", 1)
	if ctx.won then
		addStat(s, "Wins", 1)
		addStat(s, if ctx.role == "Monster" then "MonsterWins" else "HumanWins", 1)
	end
	addStat(s, "Kills", n(row.kills))
	addStat(s, "Downs", n(row.downs))
	addStat(s, "Damage", n(row.damage))
	addStat(s, "Healing", n(row.healing))
	addStat(s, "Parries", n(row.parries))
	addStat(s, "Dodges", n(row.dodgesForced))
	addStat(s, "Saves", n(row.saves))
	addStat(s, "Revives", n(row.revives))
	addStat(s, "BoxesSurvived", n(ctx.boxesSurvived))
	addStat(s, "BoxHits", n(ctx.boxHits))
	if ctx.mvp then
		addStat(s, "MVPs", 1)
	end
	if row.survived and ctx.role == "Human" then
		addStat(s, "Survived", 1)
	end
end

-- RoundEnded.monsterBroken: the humans pushed the monster to Config.Round.FinalPhaseHpFraction HP during the fight
-- (the Unshaken quest / achievement). Not RoundState.FinalPhase: the monster's own first ultimate also starts Phase 2.
local function monsterBroken(result: any): boolean
	return type(result) == "table" and result.monsterBroken == true
end

local function processPlayer(player: Player, row: any, result: any, broken: boolean)
	local profile = DataService.Get(player)
	if profile == nil then
		return
	end
	local questChanges: { any } = {}
	if QuestService and type(QuestService.Flush) == "function" then
		local ok, changes = pcall(QuestService.Flush, player)
		if ok and type(changes) == "table" then
			questChanges = changes
		end
	end
	local today = Rewards.Day(os.time())
	local box = boxStats[row.userId] or { BoxesSurvived = 0, BoxHits = 0 }
	local ctx = Rewards.Context(result, row, {
		monsterBroken = broken,
		boxesSurvived = box.BoxesSurvived,
		boxHits = box.BoxHits,
		firstWinAvailable = Rewards.FirstWinAvailable(profile, today),
	})
	local breakdown = Rewards.Compute(ctx)
	ctx.exp = breakdown.exp

	local packet: { [string]: any } = {
		exp = breakdown.exp,
		gold = breakdown.gold,
		items = breakdown.items,
		levelUp = false,
		levels = 0,
		unlocked = {},
		questProgress = {},
		firstWin = breakdown.firstWin,
		practice = breakdown.practice,
		practiceMult = if breakdown.practice then Config.Rewards.PracticeMult else 1,
	}
	local masteryResult: any = nil
	local fromLevel = profile.Level

	DataService.Update(player, function(p: any)
		applyStats(p, ctx)
		if breakdown.firstWin then
			p.Login.FirstWinDay = today
		end
		local grant = Rewards.Grant(p, breakdown.exp, breakdown.gold)
		if grant.LevelGold > 0 then
			table.insert(packet.items, { key = "prog.reward.levelUp", exp = 0, gold = grant.LevelGold })
			packet.gold += grant.LevelGold
		end
		packet.levelUp = grant.LevelsGained > 0
		packet.levels = grant.LevelsGained
		-- kit mastery: the round's EXP without the first-win bonus
		local kitExp = breakdown.exp - (if breakdown.firstWin then Config.Rewards.FirstWinOfDay.Exp else 0)
		if MasteryService and type(MasteryService.Add) == "function" then
			masteryResult = MasteryService.Add(p, row.kitId, kitExp)
		else
			masteryResult = Mastery.Apply(p, row.kitId, kitExp)
		end
		for _, reward in masteryResult.Rewards do
			if reward.Kind == "Gold" and reward.Amount then
				table.insert(
					packet.items,
					{ key = "prog.reward.mastery", exp = 0, gold = reward.Amount, count = reward.Level }
				)
				packet.gold += reward.Amount
				p.Stats.GoldEarned = (p.Stats.GoldEarned or 0) + reward.Amount
			end
		end
		if QuestService and type(QuestService.ApplyRound) == "function" then
			for _, change in QuestService.ApplyRound(p, player, ctx) do
				table.insert(questChanges, change)
			end
		end
	end)

	local now = DataService.Get(player) or profile
	packet.newLevel = now.Level
	packet.level = now.Level
	packet.expInto = now.Exp
	packet.expToNext = if now.Level >= Levels.MaxLevel then 0 else Levels.ExpToNext(now.Level)
	if masteryResult then
		local level, into, need = Mastery.Progress(masteryResult.Exp)
		packet.mastery = {
			kitId = masteryResult.KitId,
			from = masteryResult.From,
			to = level,
			exp = masteryResult.Exp,
			into = into,
			need = need,
		}
		if MasteryService and type(MasteryService.UnlockIds) == "function" then
			for _, id in MasteryService.UnlockIds(masteryResult) do
				table.insert(packet.unlocked, id)
			end
		end
	end

	local achieved: { string } = {}
	if AchievementService and type(AchievementService.Evaluate) == "function" then
		local ok, ids = pcall(AchievementService.Evaluate, player, ctx)
		if ok and type(ids) == "table" then
			achieved = ids
		end
	end
	for _, id in achieved do
		table.insert(packet.unlocked, "achievement:" .. id)
		table.insert(packet.unlocked, "title:" .. id)
	end
	if QuestService and type(QuestService.Summary) == "function" then
		packet.questProgress = QuestService.Summary(questChanges)
	end

	pcall(Net.Server.Fire, "RoundEvent", player, "Rewards", packet)

	if packet.levelUp then
		notify(player, "prog.notify.levelUp", { now.Level, Levels.GoldForLevels(fromLevel, now.Level) }, "Reward")
	end
	if MasteryService and type(MasteryService.Announce) == "function" and masteryResult then
		MasteryService.Announce(player, masteryResult)
	end
	if QuestService and type(QuestService.Announce) == "function" then
		QuestService.Announce(player, questChanges)
	end
end

local BOT_ID_BASE = -1000000 -- mirrors StatsService.BOT_ID_BASE (used when StatsService is unavailable)
local function isBotId(userId: number): boolean
	if StatsService and type(StatsService.IsBotId) == "function" then
		return StatsService.IsBotId(userId) == true
	end
	return userId <= BOT_ID_BASE
end

function RewardService.Process(result: any, resolvePlayer: ((number) -> Player?)?)
	if DataService == nil or not Rewards.ShouldReward(result) then
		return
	end
	local broken = monsterBroken(result)
	for _, row in result.rows do
		-- real players only — NOT "userId > 0": Studio test players (Test -> Local Server) have negative UserIds and
		-- must get their rewards too; bot rows use StatsService's id range (<= BOT_ID_BASE) and are skipped
		if type(row) == "table" and type(row.userId) == "number" and row.userId ~= 0 and not isBotId(row.userId) then
			local player = if resolvePlayer then resolvePlayer(row.userId) else Players:GetPlayerByUserId(row.userId)
			if player and DataService.Get(player) then
				local ok, err = pcall(processPlayer, player, row, result, broken)
				if not ok then
					warn(("[RewardService] rewards for %s failed: %s"):format(player.Name, tostring(err)))
				end
			end
		end
	end
	table.clear(boxStats)
end

function RewardService.Init()
	DataService = tryService("DataService")
	RoundService = tryService("RoundService")
	StatsService = tryService("StatsService")
	QuestService = tryService("QuestService")
	AchievementService = tryService("AchievementService")
	MasteryService = tryService("MasteryService")
end

function RewardService.Start()
	if RoundService and type(RoundService.RoundStarted) == "table" then
		RoundService.RoundStarted:Connect(function()
			table.clear(boxStats)
		end)
	end
	if StatsService and type(StatsService.StatEvent) == "table" then
		StatsService.StatEvent:Connect(function(player: Player, stat: string, amount: number)
			if stat ~= "BoxesSurvived" and stat ~= "BoxHits" then
				return
			end
			local entry = boxStats[player.UserId]
			if entry == nil then
				entry = { BoxesSurvived = 0, BoxHits = 0 }
				boxStats[player.UserId] = entry
			end
			if type(amount) == "number" and amount == amount and amount > 0 then
				local e: any = entry
				e[stat] += amount
			end
		end)
	end
	if RoundService and type(RoundService.RoundEnded) == "table" then
		RoundService.RoundEnded:Connect(function(result: any)
			local ok, err = pcall(RewardService.Process, result)
			if not ok then
				warn("[RewardService] " .. tostring(err))
			end
		end)
	else
		warn("[RewardService] RoundService.RoundEnded missing — no round rewards")
	end
end

return RewardService
