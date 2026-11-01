--!strict
-- AchievementService (P74): unlocks achievements (pure rules: Shared/Progression/Achievements) and their titles.
-- * Lifetime achievements are re-checked whenever a profile changes (DataService.Changed, coalesced) and on load
--   (retroactive unlocks after new achievements ship).
-- * Single-round feats are checked by RewardService via Evaluate(player, ctx) after the round's stats were applied.
-- Each unlock: profile.Achievements[id] = true, title granted, + Gold (by rarity, counted in Stats.GoldEarned),
-- Notify "prog.notify.achievement" {name} with style "Achievement" (hidden ones too, they are revealed now).
--
-- API: Evaluate(player, ctx?) -> {string}   grants every newly satisfied achievement, returns their ids

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local Achievements = require(Shared:WaitForChild("Progression"):WaitForChild("Achievements")) :: any

local AchievementService = {}
AchievementService.Priority = 74

local DataService: any = nil
local RequestService: any = nil
local evaluating: { [Player]: boolean } = {}

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

local function textFor(player: Player, key: string): string
	if RequestService and type(RequestService.TextFor) == "function" then
		local ok, s = pcall(RequestService.TextFor, player, key)
		if ok and type(s) == "string" then
			return s
		end
	end
	return key
end

function AchievementService.Evaluate(player: Player, ctx: any?): { string }
	if DataService == nil or evaluating[player] then
		return {}
	end
	local profile = DataService.Get(player)
	if profile == nil then
		return {}
	end
	local ids = Achievements.Check(profile, ctx)
	if #ids == 0 then
		return {}
	end
	evaluating[player] = true
	local granted: { string } = {}
	DataService.Update(player, function(p: any)
		for _, id in ids do
			if Achievements.Grant(p, id) then
				local def = Achievements.Get(id)
				p.Stats.GoldEarned = (p.Stats.GoldEarned or 0) + (if def then def.Gold else 0)
				table.insert(granted, id)
			end
		end
	end)
	evaluating[player] = nil
	for _, id in granted do
		pcall(
			Net.Server.Fire,
			"Notify",
			player,
			"prog.notify.achievement",
			{ textFor(player, Achievements.NameKey(id)) },
			"Achievement"
		)
	end
	return granted
end

function AchievementService.Init()
	DataService = tryService("DataService")
	RequestService = tryService("RequestService")
end

function AchievementService.Start()
	if DataService == nil then
		return
	end
	local function safeEvaluate(player: Player)
		local ok, err = pcall(AchievementService.Evaluate, player, nil)
		if not ok then
			warn("[AchievementService] " .. tostring(err))
		end
	end
	DataService.Loaded:Connect(function(player: Player)
		task.delay(6, function()
			if player.Parent then
				safeEvaluate(player)
			end
		end)
	end)
	DataService.Changed:Connect(safeEvaluate)
end

return AchievementService
