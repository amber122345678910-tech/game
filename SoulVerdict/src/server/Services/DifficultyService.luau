--!strict
-- DifficultyService (P20): per-player difficulty (owner: newcomers were lost against the Sans). SPEC §7.5.
-- Each player picks Easy / Normal / Hard in Settings (profile setting "Difficulty", ProfileSchema enum, default
-- Config.Defaults.Difficulty = "Easy"). It only changes what THAT player suffers, so mixed lobbies stay fair:
--   * a DamageService "Before" hook scales monster damage to that human (Config.Difficulty.DamageTaken; Verdict
--     Box hits included) and the KR it gains (Config.Difficulty.KR); environment damage (the closing ring) and
--     damage dealt BY that player are untouched; human bots are untouched
--   * practice bots pace their abilities by the easiest difficulty among the real players in the server
--     (BotService asks BotPace(); Config.Difficulty.BotPace multiplies a bot's own cooldown wait)
--   * the Player attribute "Difficulty" mirrors the effective setting (client HintController reads it)
--
-- API
--   DifficultyService.Of(player) -> "Easy" | "Normal" | "Hard"
--   DifficultyService.DamageFactor(level) -> number ; KRFactor(level) -> number   (pure, Config-driven)
--   DifficultyService.BotPace() -> number
--   DifficultyService.Hook(info, result, state)      the DamageService "Before" hook (exposed for tests)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local ProfileSchema = require(Shared:WaitForChild("Progression"):WaitForChild("ProfileSchema")) :: any

local DifficultyService = {}
DifficultyService.Priority = 20

local DataService: any = nil
local DamageService: any = nil

local LEVELS = { Easy = true, Normal = true, Hard = true }
local RANK = { Easy = 1, Normal = 2, Hard = 3 }

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

local function playerOf(model: Instance): Player?
	local ok, player = pcall(function()
		return Players:GetPlayerFromCharacter(model :: any)
	end)
	if ok then
		return player
	end
	local okList, list = pcall(function()
		return Players:GetPlayers()
	end)
	if okList and type(list) == "table" then
		for _, p in list do
			if p.Character == model then
				return p
			end
		end
	end
	return nil
end

local function defaultLevel(): string
	local d = Config.Defaults and Config.Defaults.Difficulty
	return if type(d) == "string" and LEVELS[d] then d else "Normal"
end

function DifficultyService.DamageFactor(level: string?): number
	local t = Config.Difficulty and Config.Difficulty.DamageTaken
	local f = t and level and t[level]
	return if type(f) == "number" then f else 1
end

function DifficultyService.KRFactor(level: string?): number
	local t = Config.Difficulty and Config.Difficulty.KR
	local f = t and level and t[level]
	return if type(f) == "number" then f else 1
end

function DifficultyService.Of(player: Player?): string
	if player == nil then
		return "Normal"
	end
	if DataService and type(DataService.Get) == "function" then
		local ok, profile = pcall(DataService.Get, player)
		if ok and type(profile) == "table" then
			local okS, settings = pcall(ProfileSchema.EffectiveSettings, profile)
			local level = okS and type(settings) == "table" and settings.Difficulty or nil
			if type(level) == "string" and LEVELS[level] then
				return level
			end
		end
	end
	local attr = player:GetAttribute("Difficulty")
	if type(attr) == "string" and LEVELS[attr] then
		return attr
	end
	return defaultLevel()
end

-- The easiest level among the real players in the server (practice is usually solo): bots go easy on newcomers.
function DifficultyService.BotPace(): number
	local easiest: string? = nil
	for _, player in Players:GetPlayers() do
		local level = DifficultyService.Of(player)
		if easiest == nil or RANK[level] < RANK[easiest] then
			easiest = level
		end
	end
	local t = Config.Difficulty and Config.Difficulty.BotPace
	local pace = t and easiest and t[easiest]
	return if type(pace) == "number" and pace > 0 then pace else 1
end

-- DamageService "Before" hook: scale what a monster does to a REAL human player by that player's difficulty.
function DifficultyService.Hook(info: any, _result: any, state: any): boolean?
	if type(state) ~= "table" or type(info) ~= "table" then
		return nil
	end
	if state.TargetTeam ~= "Humans" and state.TargetTeam ~= "Human" then
		return nil
	end
	local fromMonster = state.AttackerTeam == "Monster" or state.Kind == "Box"
	if not fromMonster then
		return nil
	end
	local target = info.Target
	if typeof(target) ~= "Instance" then
		return nil
	end
	local player = playerOf(target)
	if player == nil then
		return nil -- bots and dummies are not scaled
	end
	local level = DifficultyService.Of(player)
	if level == "Normal" then
		return nil
	end
	if type(state.Amount) == "number" then
		state.Amount *= DifficultyService.DamageFactor(level)
	end
	state.KRMult = (if type(state.KRMult) == "number" then state.KRMult else 1) * DifficultyService.KRFactor(level)
	return nil
end

local function mirror(player: Player)
	player:SetAttribute("Difficulty", DifficultyService.Of(player))
end

function DifficultyService.Init()
	DataService = tryService("DataService")
	DamageService = tryService("DamageService")
end

function DifficultyService.Start()
	if DamageService and type(DamageService.AddHook) == "function" then
		DamageService.AddHook("Before", DifficultyService.Hook)
	else
		warn("[DifficultyService] DamageService missing: difficulty does not scale damage")
	end
	if DataService then
		if DataService.Loaded and DataService.Loaded.Connect then
			DataService.Loaded:Connect(function(player: Player)
				mirror(player)
			end)
		end
		if DataService.Changed and DataService.Changed.Connect then
			DataService.Changed:Connect(function(player: Player)
				mirror(player)
			end)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(mirror, player)
	end
end

return DifficultyService
