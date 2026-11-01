--!strict
-- StatsService (P25): per-round statistics of every participant (players AND bots) for the results
-- screen, MVP, rewards, quests and achievements. Fed by DamageService (Damaged/Healed/Parried/Dodged),
-- CharacterService (Died/Revived), ObjectiveService (SaveLit) and VerdictBoxService (Ended, optional).
-- Rows exist only between BeginRound and the next BeginRound/Reset; Finish() freezes them.
--
-- API (SPEC §17)
--   BeginRound(models, practice?)          new rows for these character models (bots get negative userIds)
--   Add(model, stat, amount)               stats: Damage, Healing, Kills, Downs, Parries, DodgesForced,
--                                          Saves, Revives, BoxesSurvived, BoxHits, Survived, Win
--   Get(model) -> RoundStatRow?            Rows() -> {RoundStatRow}       Mvp() -> number? (userId; <0 = bot)
--   Track(model)                           adds a row for a model that joined after BeginRound
--   Finish(winnerTeam?)                    marks Survived/Win events and freezes the rows
--   Score(row) -> number                   IsActive() -> boolean          Reset()
--   StatEvent: Signal(player, stat, amount, practice)   (real players only; fired on every Add)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal")) :: any
local RoundRules = require(Shared:WaitForChild("Round"):WaitForChild("RoundRules")) :: any

local StatsService = {}
StatsService.Priority = 25

StatsService.StatEvent = Signal.new()

type Row = {
	userId: number,
	name: string,
	team: string,
	kitId: string,
	damage: number,
	healing: number,
	kills: number,
	downs: number,
	parries: number,
	dodgesForced: number,
	saves: number,
	revives: number,
	survived: boolean,
}

local FIELDS: { [string]: string } = {
	Damage = "damage",
	Healing = "healing",
	Kills = "kills",
	Downs = "downs",
	Parries = "parries",
	DodgesForced = "dodgesForced",
	Saves = "saves",
	Revives = "revives",
}

local EVENT_ONLY: { [string]: boolean } = {
	BoxesSurvived = true,
	BoxHits = true,
	Win = true,
}

local CharacterService: any = nil
local DamageService: any = nil
local ObjectiveService: any = nil
local VerdictBoxService: any = nil
local RoundService: any = nil

local rows: { Row } = {}
local rowByModel: { [Model]: Row } = {}
local playerByModel: { [Model]: Player } = {}
local active = false
local frozen = false
local practice = false
local botIds = 0

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

local function connect(service: any, signalName: string, fn: (...any) -> ())
	if service == nil then
		return
	end
	local sig = service[signalName]
	if type(sig) == "table" and type(sig.Connect) == "function" then
		sig:Connect(function(...)
			local ok, err = pcall(fn, ...)
			if not ok then
				warn(("[StatsService] %s handler: %s"):format(signalName, tostring(err)))
			end
		end)
	end
end

local function teamOf(model: Model): string
	local team = model:GetAttribute("Team")
	return if type(team) == "string" then team else "?"
end

local function playerOf(model: Model): Player?
	if CharacterService and type(CharacterService.GetPlayer) == "function" then
		local ok, p = pcall(CharacterService.GetPlayer, model)
		if ok and p then
			return p
		end
	end
	local userId = model:GetAttribute("OwnerUserId")
	if type(userId) == "number" and userId > 0 then
		return Players:GetPlayerByUserId(userId)
	end
	return nil
end

local function makeRow(model: Model): Row
	local player = playerOf(model)
	local userId: number
	local name: string
	if player then
		userId = player.UserId
		name = player.DisplayName
		playerByModel[model] = player
	else
		local owner = model:GetAttribute("OwnerUserId")
		if type(owner) == "number" and owner > 0 then
			userId = owner
		else
			botIds += 1
			userId = -botIds
		end
		local display = model:GetAttribute("DisplayName")
		name = if type(display) == "string" then display else model.Name
	end
	local kitId = model:GetAttribute("KitId")
	return {
		userId = userId,
		name = name,
		team = teamOf(model),
		kitId = if type(kitId) == "string" then kitId else "",
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
end

function StatsService.Reset()
	table.clear(rows)
	table.clear(rowByModel)
	table.clear(playerByModel)
	active = false
	frozen = false
	practice = false
	botIds = 0
end

function StatsService.BeginRound(models: { Model }, isPractice: boolean?)
	StatsService.Reset()
	active = true
	practice = isPractice == true
	for _, model in models do
		StatsService.Track(model)
	end
end

function StatsService.Track(model: Model)
	if not active or frozen or rowByModel[model] ~= nil then
		return
	end
	local row = makeRow(model)
	-- a player who re-enters (should not happen) keeps one row
	for _, existing in rows do
		if existing.userId == row.userId and row.userId > 0 then
			rowByModel[model] = existing
			return
		end
	end
	table.insert(rows, row)
	rowByModel[model] = row
end

function StatsService.IsActive(): boolean
	return active and not frozen
end

function StatsService.Add(model: Model?, stat: string, amount: number?)
	if model == nil or not active or frozen then
		return
	end
	local row = rowByModel[model]
	if row == nil then
		return
	end
	local value = amount or 1
	if type(value) ~= "number" or value ~= value then
		return
	end
	local field = FIELDS[stat]
	if field then
		(row :: any)[field] += value
	elseif stat == "Survived" then
		row.survived = value > 0
	elseif not EVENT_ONLY[stat] then
		return
	end
	local player = playerByModel[model]
	if player and player.Parent then
		StatsService.StatEvent:Fire(player, stat, value, practice)
	end
end

function StatsService.Get(model: Model): Row?
	return rowByModel[model]
end

function StatsService.Rows(): { Row }
	local out: { Row } = {}
	for _, row in rows do
		table.insert(out, table.clone(row))
	end
	return out
end

function StatsService.Score(row: Row): number
	return RoundRules.Score(row)
end

function StatsService.Mvp(): number?
	return RoundRules.Mvp(rows)
end

-- Freezes the round: Survived for living humans was added by RoundService; Win events for the winners.
function StatsService.Finish(winnerTeam: string?)
	if not active or frozen then
		return
	end
	if winnerTeam == "Humans" or winnerTeam == "Monster" then
		for model, row in rowByModel do
			if row.team == winnerTeam then
				StatsService.Add(model, "Win", 1)
			end
		end
	end
	frozen = true
end

local function isEnemy(a: Model?, b: Model?): boolean
	if a == nil or b == nil or a == b then
		return false
	end
	return teamOf(a) ~= teamOf(b)
end

function StatsService.Init()
	CharacterService = tryService("CharacterService")
	DamageService = tryService("DamageService")
	ObjectiveService = tryService("ObjectiveService")
	VerdictBoxService = tryService("VerdictBoxService")
	RoundService = tryService("RoundService")
end

function StatsService.Start()
	connect(DamageService, "Damaged", function(info: any, result: any)
		if type(info) ~= "table" or type(result) ~= "table" then
			return
		end
		local attacker: Model? = info.Attacker
		local target: Model? = info.Target
		if not isEnemy(attacker, target) then
			return
		end
		local applied = tonumber(result.Applied) or 0
		if applied > 0 then
			StatsService.Add(attacker, "Damage", applied)
		end
		if result.Downed == true then
			StatsService.Add(attacker, "Downs", 1)
		end
	end)
	connect(DamageService, "Healed", function(target: Model?, amount: number?, source: Model?)
		if source and type(amount) == "number" and amount > 0 then
			StatsService.Add(source, "Healing", amount)
		end
	end)
	connect(DamageService, "Parried", function(defender: Model?, _attacker: Model?)
		StatsService.Add(defender, "Parries", 1)
	end)
	connect(DamageService, "Dodged", function(_monster: Model?, attacker: Model?)
		StatsService.Add(attacker, "DodgesForced", 1)
	end)
	connect(CharacterService, "Died", function(model: Model, killer: Model?)
		if killer and killer ~= model and isEnemy(killer, model) then
			StatsService.Add(killer, "Kills", 1)
		end
	end)
	connect(CharacterService, "Revived", function(_model: Model, by: Model?)
		if by then
			StatsService.Add(by, "Revives", 1)
		end
	end)
	connect(ObjectiveService, "SaveLit", function(_index: number, channelers: { Model }?)
		if type(channelers) == "table" then
			for _, model in channelers do
				StatsService.Add(model, "Saves", 1)
			end
		end
	end)
	connect(VerdictBoxService, "Ended", function(_boxId: any, victim: Model?, hits: number?, survived: boolean?)
		if victim and survived then
			StatsService.Add(victim, "BoxesSurvived", 1)
		end
		local h = tonumber(hits) or 0
		if h > 0 and RoundService and type(RoundService.GetMonster) == "function" then
			local ok, monster = pcall(RoundService.GetMonster)
			if ok and monster then
				StatsService.Add(monster, "BoxHits", h)
			end
		end
	end)
end

return StatsService
