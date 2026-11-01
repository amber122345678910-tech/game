--!strict
-- MasteryService (P71): per-kit mastery on the server (pure rules in Shared/Progression/Mastery).
-- RewardService calls Add(...) INSIDE its DataService.Update after every round (kit EXP = the round's EXP
-- without the first-win bonus), then Announce(...) after the update. Rewards (titles, trails, the Mastery-10
-- legendary skins, gold) are granted by Mastery.Apply; the results screen lists them via RoundEvent "Rewards".
--
-- API: Add(profile, kitId, amount) -> MasteryResult          (mutates the profile; call inside Update)
--      Announce(player, result)                               Notify "prog.notify.masteryUp" {kitName, level}
--      Levels(player) -> {[kitId]: level}                      UnlockIds(result) -> {string}
-- UnlockIds: "title:<id>", "trail:<id>", "skin:<kitId>:<skinId>" for every reward that was new.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Mastery = require(Shared:WaitForChild("Progression"):WaitForChild("Mastery")) :: any

local MasteryService = {}
MasteryService.Priority = 71

local DataService: any = nil
local RequestService: any = nil

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

local function textFor(player: Player, localized: any): string
	if RequestService and type(RequestService.TextFor) == "function" then
		local ok, s = pcall(RequestService.TextFor, player, localized)
		if ok and type(s) == "string" then
			return s
		end
	end
	return if type(localized) == "table" then (localized.en or "") else tostring(localized)
end

function MasteryService.Add(profile: any, kitId: string, amount: number): any
	return Mastery.Apply(profile, kitId, amount)
end

function MasteryService.UnlockIds(result: any): { string }
	local out: { string } = {}
	if type(result) ~= "table" or type(result.Rewards) ~= "table" then
		return out
	end
	for _, reward in result.Rewards do
		if reward.Kind == "Title" then
			table.insert(out, "title:" .. reward.Id)
		elseif reward.Kind == "Trail" then
			table.insert(out, "trail:" .. reward.Id)
		elseif reward.Kind == "Skin" then
			table.insert(out, "skin:" .. reward.Id)
		end
	end
	return out
end

function MasteryService.Announce(player: Player, result: any)
	if type(result) ~= "table" or result.To <= result.From or player.Parent == nil then
		return
	end
	local kit = Kits.Get(result.KitId)
	local name = if kit then textFor(player, kit.Name) else result.KitId
	pcall(Net.Server.Fire, "Notify", player, "prog.notify.masteryUp", { name, result.To }, "Reward")
end

function MasteryService.Levels(player: Player): { [string]: number }
	local profile = if DataService then DataService.Get(player) else nil
	if profile == nil then
		return {}
	end
	return Mastery.LevelsOf(profile)
end

function MasteryService.Init()
	DataService = tryService("DataService")
	RequestService = tryService("RequestService")
end

function MasteryService.Start() end

return MasteryService
