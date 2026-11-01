--!strict
-- RoundService (P50): the round state machine (SPEC §1.1) and everything that happens around it.
--   Waiting (< MinPlayers; a solo player may start PRACTICE vs bots)
--   -> Intermission (map vote, 3 random options) -> monster picked by QueueService -> map loaded
--   -> Intro (everyone spawned + frozen) -> Round (timer; FinalPhase at <= 30 % monster HP; Second Wind)
--   -> Collapse (overtime ring shrinking to CollapseMinRadius, True damage outside each second)
--   -> Ending (results, MVP, RoundEnded for rewards) -> cleanup (everyone back to the lobby) -> Intermission
-- Drives ReplicatedStorage.RoundState (Configuration, created in Init with every SPEC §4.1 attribute) and
-- broadcasts RoundEvents (SPEC §4.2). Pure rules live in Shared/Round/RoundRules (unit-tested in Lune).
-- The loop is crash-proof: any error inside a phase is logged, the match is cleaned up and the loop
-- returns to Waiting.
--
-- API (SPEC §17)
--   Phase() -> string, PhaseChanged: Signal(phase), RoundStarted: Signal(info), RoundEnded: Signal(result)
--   GetMonster() -> Model?, IsRoundCharacter(model) -> boolean, TriggerFinalPhase() -> boolean
--   StartPractice(player, side "Human"|"Monster", allies?) -> (boolean, errKey?), ForceNextMap(mapId) -> boolean
-- Extra: SkipPhase(), EndRound(winner?, reason?), ForceCollapse(), Abort(), IsPractice(), InMatch(),
--   State() -> Configuration, FinalPhaseStarted: Signal(monster)
-- RoundEnded result = { winner, reason, rows, mvpUserId, practice, durations = {round, collapse, total},
--   mapId, roundId, monsterUserId, humanUserIds }   (reason "Aborted" = stopped by Style Lab)
-- Extra RoundState attributes: Harmony (team damage multiplier), RoundId, MonsterName, FinalPreset,
--   LobbyPreset. Extra RoundEvents: "PlayerLeft" {name, team, userId}.
-- Requests registered: "Vote" (mapId or {mapId}), "StartPractice" (side or {side, allies}).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal")) :: any
local RoundRules = require(Shared:WaitForChild("Round"):WaitForChild("RoundRules")) :: any
local Registry = require(Shared:WaitForChild("Maps"):WaitForChild("Registry")) :: any

local RoundService = {}
RoundService.Priority = 50

RoundService.PhaseChanged = Signal.new()
RoundService.RoundStarted = Signal.new()
RoundService.RoundEnded = Signal.new()
RoundService.FinalPhaseStarted = Signal.new()

local TICK = 0.1
local STATE_DEFAULTS: { [string]: any } = {
	Phase = "Waiting",
	PhaseEndsAt = 0,
	MapId = "",
	VoteOptions = "",
	MonsterUserId = 0,
	MonsterKit = "",
	MonsterName = "",
	HumansAlive = 0,
	HumansTotal = 0,
	SavesLit = 0,
	SavesTotal = 0,
	FinalPhase = false,
	Winner = "",
	WinReason = "",
	Practice = false,
	TeamRevives = 0,
	CollapseRadius = 0,
	CollapseCenter = Vector3.new(0, 0, 0),
	Harmony = 1,
	RoundId = 0,
}

type Participant = {
	Player: Player?,
	Model: Model,
	Team: string,
	KitId: string,
	UserId: number,
	Name: string,
	IsBot: boolean,
}

type PracticeRequest = { Player: Player, Side: string, Allies: number? }

type Result = { winner: string, reason: string }

-- Services (resolved in Init)
local CharacterService: any = nil
local MapService: any = nil
local StatsService: any = nil
local QueueService: any = nil
local ObjectiveService: any = nil
local BotService: any = nil
local StatusService: any = nil
local DamageService: any = nil
local HazardService: any = nil
local VerdictBoxService: any = nil
local RequestService: any = nil

local roundStateInstance: Configuration? = nil
local random = Random.new()

local state = {
	Phase = "Waiting",
	PhaseEndsAt = 0,
	RoundId = 0,
	InMatch = false,
	Practice = false,
	PracticePlayer = nil :: Player?,
	PracticeSide = "Human",
	PracticeRequest = nil :: PracticeRequest?,
	MapInfo = nil :: any,
	Monster = nil :: Model?,
	MonsterPlayer = nil :: Player?,
	MonsterLeft = false,
	HumansLeftLast = false,
	PracticePlayerLeft = false,
	RoundModels = {} :: { [Model]: Participant },
	Participants = {} :: { [Player]: Participant },
	HumansAtStart = 0,
	FinalPhase = false,
	SecondWind = false,
	TimeUp = false,
	Result = nil :: Result?,
	LastHit = { victim = nil :: Model?, position = nil :: Vector3? },
	Votes = {} :: { [Player]: string },
	VoteOptions = {} :: { string },
	ForcedMap = nil :: string?,
	SkipRequested = false,
	AbortRequested = false,
	ForceCollapse = false,
	MatchStartedAt = 0,
	RoundStartedAt = 0,
	CollapseStartedAt = 0,
	FrozenFallback = {} :: { BasePart },
}

local voteBroadcastPending = false

-- Helpers ---------------------------------------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
end

local function tryService(name: string): any
	local module = (script.Parent :: Instance):FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
		warn(("[RoundService] could not use %s: %s"):format(name, tostring(result)))
	end
	return nil
end

local function call(service: any, method: string, ...: any): (boolean, any)
	if service == nil then
		return false, nil
	end
	local fn = service[method]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(("[RoundService] %s failed: %s"):format(method, tostring(result)))
	end
	return ok, result
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
				warn(("[RoundService] %s handler: %s"):format(signalName, tostring(err)))
			end
		end)
	end
end

local function ensureRoundState(): Configuration
	if roundStateInstance and roundStateInstance.Parent ~= nil then
		return roundStateInstance
	end
	local existing = ReplicatedStorage:FindFirstChild("RoundState")
	local cfg: Configuration
	if existing and existing:IsA("Configuration") then
		cfg = existing
	else
		cfg = Instance.new("Configuration")
		cfg.Name = "RoundState"
	end
	for key, value in STATE_DEFAULTS do
		if cfg:GetAttribute(key) == nil then
			cfg:SetAttribute(key, value)
		end
	end
	for _, key in { "GraphicsPreset", "FinalPreset", "LobbyPreset" } do
		if cfg:GetAttribute(key) == nil then
			cfg:SetAttribute(key, "")
		end
	end
	cfg.Parent = ReplicatedStorage
	roundStateInstance = cfg
	return cfg
end

local function setState(name: string, value: any)
	local rs = ensureRoundState()
	if rs:GetAttribute(name) ~= value then
		rs:SetAttribute(name, value)
	end
end

local function fireRoundEvent(name: string, data: any)
	local ok, err = pcall(Net.Server.FireAll, "RoundEvent", name, data)
	if not ok then
		warn("[RoundService] RoundEvent " .. name .. ": " .. tostring(err))
	end
end

local function notify(player: Player?, key: string, args: { any }?, style: string?)
	if player and player.Parent then
		pcall(Net.Server.Fire, "Notify", player, key, args, style)
	end
end

local function notifyAll(key: string, args: { any }?, style: string?)
	pcall(Net.Server.FireAll, "Notify", key, args, style)
end

local function isMatchPhase(): boolean
	return state.InMatch and (state.Phase == "Intro" or state.Phase == "Round" or state.Phase == "Collapse")
end

local function isFightPhase(): boolean
	return state.InMatch and (state.Phase == "Round" or state.Phase == "Collapse")
end

local function rootOf(model: Model?): BasePart?
	if model == nil then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function humanoidOf(model: Model?): Humanoid?
	if model == nil then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

local function nameOf(model: Model?): string
	if model == nil then
		return ""
	end
	local p = state.RoundModels[model]
	if p then
		return p.Name
	end
	local display = model:GetAttribute("DisplayName")
	return if type(display) == "string" then display else model.Name
end

local function isAlive(model: Model?): boolean
	if model == nil or CharacterService == nil then
		return false
	end
	local ok, alive = pcall(CharacterService.IsAlive, model)
	return ok and alive == true
end

local function heal(model: Model, amount: number)
	local ok = call(DamageService, "Heal", model, amount, nil)
	if not ok then
		local humanoid = humanoidOf(model)
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
		end
	end
end

-- Humans of the current match: (up list, downed list)
local function roundHumans(): ({ Model }, { Model })
	local up: { Model } = {}
	local downed: { Model } = {}
	for model, p in state.RoundModels do
		if p.Team == "Humans" and isAlive(model) then
			if model:GetAttribute("Downed") == true then
				table.insert(downed, model)
			else
				table.insert(up, model)
			end
		end
	end
	return up, downed
end

local function updateCounts()
	if not state.InMatch then
		return
	end
	local up, downed = roundHumans()
	setState("HumansAlive", #up + #downed)
end

local function phaseDuration(phase: string): number
	return RoundRules.PhaseDuration(phase, state.Practice)
end

local function setPhase(phase: string, duration: number)
	state.Phase = phase
	state.PhaseEndsAt = if duration > 0 then now() + duration else 0
	setState("Phase", phase)
	setState("PhaseEndsAt", state.PhaseEndsAt)
	fireRoundEvent("PhaseChanged", { phase = phase, endsAt = state.PhaseEndsAt })
	RoundService.PhaseChanged:Fire(phase)
end

-- Rules glue --------------------------------------------------------------------------------------------

local function snapshot(): any
	local monster = state.Monster
	local monsterAlive = false
	if monster and isAlive(monster) then
		local humanoid = humanoidOf(monster)
		monsterAlive = humanoid ~= nil and humanoid.Health > 0
	end
	local monsterLeft = state.MonsterLeft
	local mp = state.MonsterPlayer
	if mp and mp.Parent == nil then
		monsterLeft = true
	end
	local up, downed = roundHumans()
	local practiceHumanDead = false
	local pp = state.PracticePlayer
	if state.Practice and state.PracticeSide == "Human" and pp then
		local part = state.Participants[pp]
		practiceHumanDead = part == nil or not isAlive(part.Model)
	end
	return {
		MonsterAlive = monsterAlive,
		MonsterLeft = monsterLeft,
		HumansUp = #up,
		HumansDowned = #downed,
		HumansLeft = state.HumansLeftLast,
		TimeUp = state.TimeUp,
		PracticeHumanDead = practiceHumanDead,
	}
end

local function evaluate()
	if state.Result ~= nil or not isMatchPhase() then
		return
	end
	local winner, reason = RoundRules.Evaluate(snapshot())
	if winner then
		state.Result = { winner = winner, reason = reason }
	end
end

-- Nobody up -> downed humans can never be revived: they fall now.
local function checkWipe()
	if not isFightPhase() or state.Result ~= nil then
		return
	end
	local up, downed = roundHumans()
	if RoundRules.ShouldWipeDowned(#up, #downed) then
		for _, model in downed do
			call(CharacterService, "Kill", model, nil, "BleedOut")
		end
	end
end

local function checkSecondWind()
	if state.SecondWind or not isFightPhase() or state.Result ~= nil then
		return
	end
	local up = roundHumans()
	if RoundRules.ShouldSecondWind(state.HumansAtStart, #up, state.SecondWind) then
		state.SecondWind = true
		local model = up[1]
		local h = Config.Human
		call(StatusService, "Apply", model, "SecondWind", h.SecondWindDuration, {
			speed = h.SecondWindSpeedMult,
			damage = h.SecondWindDamageMult,
			mult = h.SecondWindDamageMult,
		})
		local humanoid = humanoidOf(model)
		if humanoid then
			heal(model, humanoid.MaxHealth * h.SecondWindHealFraction)
		end
		local p = state.RoundModels[model]
		fireRoundEvent("SecondWind", {
			userId = if p then p.UserId else 0,
			model = model,
			name = nameOf(model),
			duration = h.SecondWindDuration,
		})
	end
end

local function checkFinalPhase()
	if state.FinalPhase or not isFightPhase() then
		return
	end
	local humanoid = humanoidOf(state.Monster)
	if humanoid and RoundRules.ShouldTriggerFinalPhase(humanoid.Health, humanoid.MaxHealth, state.FinalPhase) then
		RoundService.TriggerFinalPhase()
	end
end

local function afterRosterChange()
	updateCounts()
	checkWipe()
	checkSecondWind()
	evaluate()
end

-- Freeze for the intro: StatusService "Stunned"; anchored roots if StatusService is missing.
local function freeze(models: { Model }, seconds: number)
	table.clear(state.FrozenFallback)
	for _, model in models do
		local ok = call(StatusService, "Apply", model, "Stunned", seconds)
		if not ok then
			local root = rootOf(model)
			if root then
				root.Anchored = true
				table.insert(state.FrozenFallback, root)
			end
		end
	end
end

local function unfreezeFallback()
	for _, root in state.FrozenFallback do
		if root.Parent ~= nil then
			root.Anchored = false
		end
	end
	table.clear(state.FrozenFallback)
end

-- Map vote --------------------------------------------------------------------------------------------------

local function voteCounts(): { [string]: number }
	return RoundRules.VoteCounts(state.VoteOptions, state.Votes)
end

local function broadcastVotes()
	fireRoundEvent("MapVote", { options = state.VoteOptions, votes = voteCounts() })
end

local function broadcastVotesSoon()
	if voteBroadcastPending then
		return
	end
	voteBroadcastPending = true
	task.delay(0.25, function()
		voteBroadcastPending = false
		if state.Phase == "Intermission" then
			broadcastVotes()
		end
	end)
end

local function onVote(player: Player, data: any): (boolean, string?)
	local mapId: any = data
	if type(data) == "table" then
		mapId = data.mapId
	end
	if type(mapId) ~= "string" or #mapId > 64 then
		return false, "round.vote.invalid"
	end
	if state.Phase ~= "Intermission" then
		return false, "round.vote.closed"
	end
	if table.find(state.VoteOptions, mapId) == nil then
		return false, "round.vote.invalid"
	end
	state.Votes[player] = mapId
	broadcastVotesSoon()
	return true, nil
end

local function chooseMap(practice: boolean): string
	local forced = state.ForcedMap
	if forced then
		state.ForcedMap = nil
		return forced
	end
	if not practice and #state.VoteOptions > 0 then
		local winner = RoundRules.VoteWinner(state.VoteOptions, state.Votes, random:NextNumber())
		if winner then
			return winner
		end
	end
	local _, options = call(MapService, "RandomOptions", 1)
	if type(options) == "table" and options[1] then
		return options[1]
	end
	return "TestArena"
end

-- Match lifecycle -------------------------------------------------------------------------------------------

local function resetMatchState()
	state.InMatch = false
	state.Practice = false
	state.PracticePlayer = nil
	state.PracticeSide = "Human"
	state.MapInfo = nil
	state.Monster = nil
	state.MonsterPlayer = nil
	state.MonsterLeft = false
	state.HumansLeftLast = false
	state.PracticePlayerLeft = false
	table.clear(state.RoundModels)
	table.clear(state.Participants)
	state.HumansAtStart = 0
	state.FinalPhase = false
	state.SecondWind = false
	state.TimeUp = false
	state.Result = nil
	state.LastHit = { victim = nil, position = nil }
	state.SkipRequested = false
	state.AbortRequested = false
	state.ForceCollapse = false
	table.clear(state.FrozenFallback)
end

local function resetRoundStateAttributes()
	for key, value in STATE_DEFAULTS do
		if key ~= "Phase" and key ~= "PhaseEndsAt" and key ~= "RoundId" then
			setState(key, value)
		end
	end
end

-- Everything back to the lobby. Safe to call at any time, any number of times.
local function cleanup()
	unfreezeFallback()
	call(HazardService, "Clear")
	call(VerdictBoxService, "CancelAll")
	call(BotService, "Clear")
	call(CharacterService, "DespawnTeam", "Humans")
	call(CharacterService, "DespawnTeam", "Monster")
	call(ObjectiveService, "Clear")
	call(MapService, "Unload")
	resetMatchState()
	resetRoundStateAttributes()
	for _, player in Players:GetPlayers() do
		local model = CharacterService and CharacterService.GetModel(player)
		local team = if model then CharacterService.GetTeam(model) else nil
		if model == nil or team ~= "Lobby" then
			local ok, err = pcall(CharacterService.SpawnLobby, player)
			if not ok then
				warn("[RoundService] lobby respawn failed: " .. tostring(err))
			end
		end
	end
end

local function addParticipant(model: Model, player: Player?, team: string, kitId: string)
	local display = model:GetAttribute("DisplayName")
	local participant: Participant = {
		Player = player,
		Model = model,
		Team = team,
		KitId = kitId,
		UserId = if player then player.UserId else 0,
		Name = if player then player.DisplayName elseif type(display) == "string" then display else model.Name,
		IsBot = player == nil,
	}
	state.RoundModels[model] = participant
	if player then
		state.Participants[player] = participant
	end
	if team == "Monster" then
		state.Monster = model
		state.MonsterPlayer = player
	end
end

local function spawnSlot(spawns: { CFrame }, index: number): CFrame
	local count = #spawns
	local base = spawns[((index - 1) % count) + 1]
	local ring = math.floor((index - 1) / count)
	if ring == 0 then
		return base
	end
	-- extra players beyond the map's spawn count: step sideways from the base spawn
	return base * CFrame.new(ring * 3.5 * (if ring % 2 == 0 then 1 else -1), 0, 0)
end

local function shuffled<T>(list: { T }): { T }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = random:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

local function waitPhase(stop: (() -> boolean)?): string
	while true do
		if stop and stop() then
			return "stop"
		end
		if state.AbortRequested then
			return "abort"
		end
		if state.SkipRequested then
			state.SkipRequested = false
			return "skip"
		end
		if state.PhaseEndsAt > 0 and now() >= state.PhaseEndsAt then
			return "timer"
		end
		task.wait(TICK)
	end
end

local function collapseDamage(center: Vector3, radius: number)
	local amount: number = Config.Round.CollapseDamagePerSecond
	for model, p in state.RoundModels do
		if p.Team == "Humans" and isAlive(model) then
			local root = rootOf(model)
			if root and RoundRules.IsOutside(root.Position, center, radius) then
				local ok = call(DamageService, "Apply", {
					Target = model,
					Amount = amount,
					Kind = "True",
					Ability = "Collapse",
					Color = "Purple",
					Dodgeable = false,
					Blockable = false,
					Position = root.Position,
				})
				if not ok then
					-- fallback while DamageService is missing
					local humanoid = humanoidOf(model)
					if humanoid then
						local hp = humanoid.Health - amount
						if hp <= 0 then
							call(CharacterService, "SetDowned", model, nil)
						else
							humanoid.Health = hp
						end
					end
				end
			end
		end
	end
end

type Setup = {
	MapId: string,
	Humans: { Model },
	HumanPlayers: { Player },
	Monster: Model?,
	MonsterKit: string,
}

-- Spawns everyone for a real round. Returns nil if the round cannot start.
local function setupRealMatch(info: any): Setup?
	local players: { Player } = {}
	for _, p in Players:GetPlayers() do
		table.insert(players, p)
	end
	if #players < Config.Round.MinPlayers then
		return nil
	end
	local monsterPlayer = state.MonsterPlayer
	if monsterPlayer == nil or monsterPlayer.Parent == nil then
		local _, chosen = call(QueueService, "ChooseMonster", players)
		monsterPlayer = chosen or players[random:NextInteger(1, #players)]
	end
	local mp = monsterPlayer :: Player
	local humanPlayers: { Player } = {}
	for _, p in players do
		if p ~= mp and p.Parent ~= nil then
			table.insert(humanPlayers, p)
		end
	end
	if #humanPlayers == 0 then
		return nil
	end
	local spawns = shuffled(info.HumanSpawns)
	local humans: { Model } = {}
	for i, p in humanPlayers do
		local kitId = CharacterService.EquippedKit(p, "Human")
		local model = CharacterService.SpawnPlayer(p, kitId, spawnSlot(spawns, i), {
			Team = "Humans",
			SkinId = CharacterService.EquippedSkin(p, kitId),
		})
		addParticipant(model, p, "Humans", kitId)
		table.insert(humans, model)
	end
	local monsterKit = CharacterService.EquippedKit(mp, "Monster")
	local kit = Kits.Get(monsterKit)
	local monster = CharacterService.SpawnPlayer(mp, monsterKit, info.MonsterSpawn, {
		Team = "Monster",
		SkinId = CharacterService.EquippedSkin(mp, monsterKit),
		MaxHealth = RoundRules.MonsterMaxHealth(kit.Stats, #humans),
	})
	addParticipant(monster, mp, "Monster", monsterKit)
	return {
		MapId = info.Id,
		Humans = humans,
		HumanPlayers = humanPlayers,
		Monster = monster,
		MonsterKit = monsterKit,
	}
end

-- Spawns the practice player + bots.
local function setupPracticeMatch(info: any, request: PracticeRequest): Setup?
	local player = request.Player
	if player.Parent == nil then
		return nil
	end
	local spawns = shuffled(info.HumanSpawns)
	local humans: { Model } = {}
	local humanPlayers: { Player } = {}
	local monster: Model? = nil
	local monsterKit = ""
	local botHumans: number = Config.Practice.BotHumans
	if request.Side == "Monster" then
		monsterKit = CharacterService.EquippedKit(player, "Monster")
		local kit = Kits.Get(monsterKit)
		local model = CharacterService.SpawnPlayer(player, monsterKit, info.MonsterSpawn, {
			Team = "Monster",
			SkinId = CharacterService.EquippedSkin(player, monsterKit),
			MaxHealth = RoundRules.MonsterMaxHealth(kit.Stats, botHumans),
		})
		addParticipant(model, player, "Monster", monsterKit)
		monster = model
		local _, bots = call(BotService, "SpawnPracticeBots", "Human", botHumans, { Spawns = spawns })
		if type(bots) == "table" then
			for _, bot in bots do
				addParticipant(bot, nil, "Humans", bot:GetAttribute("KitId") or "")
				table.insert(humans, bot)
			end
		end
	else
		local kitId = CharacterService.EquippedKit(player, "Human")
		local model = CharacterService.SpawnPlayer(player, kitId, spawns[1], {
			Team = "Humans",
			SkinId = CharacterService.EquippedSkin(player, kitId),
		})
		addParticipant(model, player, "Humans", kitId)
		table.insert(humans, model)
		table.insert(humanPlayers, player)
		local allies = request.Allies or (botHumans - 1)
		allies = math.clamp(math.floor(allies), 0, 5)
		if allies > 0 then
			local allySpawns: { CFrame } = {}
			for i = 2, #spawns do
				table.insert(allySpawns, spawns[i])
			end
			if #allySpawns == 0 then
				allySpawns = spawns
			end
			local _, bots = call(BotService, "SpawnPracticeBots", "Human", allies, { Spawns = allySpawns, ExcludeKits = { kitId } })
			if type(bots) == "table" then
				for _, bot in bots do
					addParticipant(bot, nil, "Humans", bot:GetAttribute("KitId") or "")
					table.insert(humans, bot)
				end
			end
		end
		local monsterBots: any = nil
		local okBots, result = call(BotService, "SpawnPracticeBots", "Monster", 1, {
			Spawns = { info.MonsterSpawn },
			HumanCount = #humans,
		})
		if okBots then
			monsterBots = result
		end
		if type(monsterBots) == "table" and monsterBots[1] then
			monster = monsterBots[1]
			monsterKit = monsterBots[1]:GetAttribute("KitId") or ""
			addParticipant(monsterBots[1], nil, "Monster", monsterKit)
		end
	end
	if monster == nil or #humans == 0 then
		return nil
	end
	return {
		MapId = info.Id,
		Humans = humans,
		HumanPlayers = humanPlayers,
		Monster = monster,
		MonsterKit = monsterKit,
	}
end

local function participantInfo(model: Model?): any
	if model == nil then
		return nil
	end
	local p = state.RoundModels[model]
	if p == nil then
		return nil
	end
	return { userId = p.UserId, kitId = p.KitId, name = p.Name, model = model, isBot = p.IsBot }
end

local function finishMatch(result: Result, setup: Setup)
	local winner, reason = result.winner, result.reason
	local roundModels: { Model } = {}
	for model in state.RoundModels do
		table.insert(roundModels, model)
	end
	-- stop combat, protect everyone during the results
	call(HazardService, "Clear")
	call(VerdictBoxService, "CancelAll")
	local endingTime = phaseDuration("Ending")
	for _, model in roundModels do
		if isAlive(model) then
			call(StatusService, "Apply", model, "Invulnerable", endingTime + 2)
		end
	end
	-- final stats
	for _, model in roundModels do
		local p = state.RoundModels[model]
		if p and p.Team == "Humans" and isAlive(model) then
			call(StatsService, "Add", model, "Survived", 1)
		end
	end
	call(StatsService, "Finish", if reason == "Aborted" then nil else winner)
	local _, rows = call(StatsService, "Rows")
	local _, mvp = call(StatsService, "Mvp")
	rows = if type(rows) == "table" then rows else {}

	setState("Winner", winner)
	setState("WinReason", reason)
	setState("FinalPhase", state.FinalPhase)
	setPhase("Ending", endingTime)

	local monsterRoot = rootOf(state.Monster)
	if state.LastHit.victim == nil and reason == "Defeated" and monsterRoot then
		state.LastHit = { victim = state.Monster, position = monsterRoot.Position }
	end
	fireRoundEvent("RoundEnd", {
		winner = winner,
		reason = reason,
		stats = rows,
		mvpUserId = mvp,
		lastHit = state.LastHit,
		practice = state.Practice,
		mapId = setup.MapId,
	})

	local t = now()
	local humanUserIds: { number } = {}
	for _, p in setup.HumanPlayers do
		table.insert(humanUserIds, p.UserId)
	end
	local monsterPlayer = state.MonsterPlayer
	local resultInfo = {
		winner = winner,
		reason = reason,
		rows = rows,
		mvpUserId = mvp,
		practice = state.Practice,
		durations = {
			round = if state.RoundStartedAt > 0 then t - state.RoundStartedAt else 0,
			collapse = if state.CollapseStartedAt > 0 then t - state.CollapseStartedAt else 0,
			total = t - state.MatchStartedAt,
		},
		mapId = setup.MapId,
		roundId = state.RoundId,
		monsterUserId = if monsterPlayer then monsterPlayer.UserId else 0,
		humanUserIds = humanUserIds,
	}
	RoundService.RoundEnded:Fire(resultInfo)

	if not state.Practice and reason ~= "Aborted" then
		local presentHumans: { Player } = {}
		for _, p in setup.HumanPlayers do
			if p.Parent ~= nil then
				table.insert(presentHumans, p)
			end
		end
		local mp = if monsterPlayer and monsterPlayer.Parent ~= nil then monsterPlayer else nil
		call(QueueService, "RecordRound", mp, presentHumans, { rows = rows, mvpUserId = mvp })
	end

	waitPhase()
end

-- One full match (Intro -> Round -> Collapse -> Ending -> cleanup). Returns the next loop step.
local function runMatch(practice: boolean): string
	local request: PracticeRequest? = nil
	if practice then
		request = state.PracticeRequest
		state.PracticeRequest = nil
		if request == nil or request.Player.Parent == nil then
			return "Waiting"
		end
	end
	resetMatchState()
	state.InMatch = true
	state.Practice = practice
	state.RoundId += 1
	state.MatchStartedAt = now()
	setState("RoundId", state.RoundId)
	setState("VoteOptions", "")
	setState("Practice", practice)
	setState("Winner", "")
	setState("WinReason", "")
	setState("FinalPhase", false)

	if practice then
		local req = request :: PracticeRequest
		state.PracticePlayer = req.Player
		state.PracticeSide = req.Side
		notify(req.Player, "round.practice.start", { Strings.L("round.practice.side." .. req.Side) }, "Info")
	else
		-- monster first (announced while the map builds)
		local players = Players:GetPlayers()
		local _, chosen = call(QueueService, "ChooseMonster", players)
		local mp: Player? = chosen
		if mp == nil and #players > 0 then
			mp = players[random:NextInteger(1, #players)]
		end
		state.MonsterPlayer = mp
		if mp then
			local kitId = CharacterService.EquippedKit(mp, "Monster")
			fireRoundEvent("MonsterChosen", { userId = mp.UserId, kitId = kitId, name = mp.DisplayName })
			notifyAll("round.notify.monsterChosen", { mp.DisplayName }, "Info")
		end
	end

	-- map
	local mapId = chooseMap(practice)
	local okLoad, info = call(MapService, "Load", mapId)
	if not okLoad or type(info) ~= "table" then
		notifyAll("round.notify.mapFailed", nil, "Warning")
		cleanup()
		return "Waiting"
	end
	state.MapInfo = info
	if info.Id ~= mapId then
		notifyAll("round.notify.mapFailed", nil, "Warning")
	end

	-- characters
	local setup: Setup? = nil
	if practice then
		setup = setupPracticeMatch(info, request :: PracticeRequest)
	else
		setup = setupRealMatch(info)
	end
	if setup == nil then
		notifyAll("round.notify.notEnough", nil, "Warning")
		cleanup()
		return "Waiting"
	end
	local s = setup :: Setup

	local allModels: { Model } = {}
	local humanKits: { string } = {}
	for model, p in state.RoundModels do
		table.insert(allModels, model)
		if p.Team == "Humans" then
			table.insert(humanKits, p.KitId)
		end
	end
	state.HumansAtStart = #s.Humans
	local harmony = RoundRules.HarmonyMultiplier(humanKits)
	local monsterKitDef = Kits.Get(s.MonsterKit)
	local monsterInfo = participantInfo(state.Monster)

	setState("MapId", info.Id)
	setState("MonsterUserId", if state.MonsterPlayer then state.MonsterPlayer.UserId else 0)
	setState("MonsterKit", s.MonsterKit)
	setState("MonsterName", if monsterInfo then monsterInfo.name else "")
	setState("HumansTotal", #s.Humans)
	setState("HumansAlive", #s.Humans)
	setState("TeamRevives", Config.Human.TeamRevives)
	setState("Harmony", harmony)
	setState("CollapseRadius", 0)
	setState("CollapseCenter", info.Center)

	call(StatsService, "BeginRound", allModels, practice)
	call(ObjectiveService, "Setup", info)

	local introTime = phaseDuration("Intro")
	freeze(allModels, introTime + 0.2)

	local humansInfo = {}
	for _, model in s.Humans do
		table.insert(humansInfo, participantInfo(model))
	end
	setPhase("Intro", introTime)
	fireRoundEvent("Intro", {
		mapId = info.Id,
		monster = monsterInfo,
		humans = humansInfo,
		practice = practice,
		introPath = info.IntroPath,
		center = info.Center,
		radius = info.Radius,
		music = info.Music,
		harmony = harmony,
		monsterTitle = if monsterKitDef then monsterKitDef.Title else nil,
	})
	for model, p in state.RoundModels do
		if p.Player then
			notify(p.Player, if p.Team == "Monster" then "round.notify.youAreMonster" else "round.notify.youAreHuman", nil, "Role")
		end
		local _ = model
	end
	if harmony > 1 then
		for _, p in s.HumanPlayers do
			notify(p, "round.notify.harmony", { math.floor((harmony - 1) * 100 + 0.5) }, "Info")
		end
	end
	RoundService.RoundStarted:Fire({
		roundId = state.RoundId,
		mapId = info.Id,
		practice = practice,
		monster = state.Monster,
		monsterPlayer = state.MonsterPlayer,
		humans = s.Humans,
		humanPlayers = s.HumanPlayers,
		harmony = harmony,
	})

	evaluate()
	local introEnd = waitPhase(function()
		evaluate()
		return state.Result ~= nil
	end)
	unfreezeFallback()

	-- Round
	if introEnd ~= "abort" and state.Result == nil then
		state.RoundStartedAt = now()
		setPhase("Round", phaseDuration("Round"))
		while true do
			evaluate()
			checkFinalPhase()
			if state.Result ~= nil or state.AbortRequested then
				break
			end
			if state.ForceCollapse or state.SkipRequested or now() >= state.PhaseEndsAt then
				state.ForceCollapse = false
				state.SkipRequested = false
				break
			end
			task.wait(TICK)
		end
	end

	-- Collapse (overtime)
	if state.Result == nil and not state.AbortRequested then
		local center: Vector3 = info.Center
		local startRadius: number = info.Radius
		state.CollapseStartedAt = now()
		setPhase("Collapse", phaseDuration("Collapse"))
		setState("CollapseCenter", center)
		setState("CollapseRadius", startRadius)
		fireRoundEvent("Collapse", {
			center = center,
			startRadius = startRadius,
			minRadius = Config.Round.CollapseMinRadius,
			startsAt = state.CollapseStartedAt,
			endsAt = state.PhaseEndsAt,
		})
		notifyAll("round.notify.collapse", nil, "Warning")
		local lastDamage = now()
		while true do
			evaluate()
			checkFinalPhase()
			if state.Result ~= nil or state.AbortRequested then
				break
			end
			local radius = RoundRules.CollapseRadius(now() - state.CollapseStartedAt, startRadius)
			setState("CollapseRadius", math.floor(radius * 100 + 0.5) / 100)
			if now() - lastDamage >= 1 then
				lastDamage = now()
				collapseDamage(center, radius)
			end
			if state.SkipRequested or now() >= state.PhaseEndsAt then
				state.SkipRequested = false
				state.TimeUp = true
				evaluate()
				break
			end
			task.wait(TICK)
		end
	end

	-- Ending
	if state.AbortRequested and state.Result == nil then
		-- practice player left / Style Lab abort: no results screen
		if state.Practice then
			notify(state.PracticePlayer, "round.practice.ended", nil, "Info")
		end
		cleanup()
		local count = #Players:GetPlayers()
		return RoundRules.Next("Ending", { Players = count, TimerDone = true })
	end
	local result: Result = state.Result or (function(): Result
		local up, downed = roundHumans()
		if #up + #downed > 0 then
			return { winner = "Humans", reason = "Survived" }
		end
		return { winner = "Monster", reason = "Eliminated" }
	end)()
	state.Result = result
	finishMatch(result, s)
	cleanup()
	local count = #Players:GetPlayers()
	return RoundRules.Next("Ending", { Players = count, TimerDone = true })
end

local function runWaiting(): string
	setPhase("Waiting", 0)
	while true do
		local count = #Players:GetPlayers()
		local pending = state.PracticeRequest
		if pending and pending.Player.Parent == nil then
			state.PracticeRequest = nil
			pending = nil
		end
		local nextPhase = RoundRules.Next("Waiting", {
			Players = count,
			TimerDone = false,
			PracticeRequested = pending ~= nil,
		})
		if nextPhase == "Intermission" then
			if pending then
				notify(pending.Player, "round.practice.busy", nil, "Warning")
				state.PracticeRequest = nil
			end
			return "Intermission"
		elseif nextPhase == "Intro" then
			return "Practice"
		end
		task.wait(0.25)
	end
end

local function runIntermission(): string
	local _, options = call(MapService, "RandomOptions", Config.Round.VoteOptions)
	state.VoteOptions = if type(options) == "table" then options else { "TestArena" }
	table.clear(state.Votes)
	state.SkipRequested = false
	setState("VoteOptions", table.concat(state.VoteOptions, ","))
	setState("MapId", state.ForcedMap or "")
	setPhase("Intermission", phaseDuration("Intermission"))
	broadcastVotes()
	while true do
		local count = #Players:GetPlayers()
		local timerDone = state.SkipRequested or now() >= state.PhaseEndsAt
		local nextPhase = RoundRules.Next("Intermission", { Players = count, TimerDone = timerDone })
		if nextPhase == "Waiting" then
			notifyAll("round.notify.notEnough", nil, "Warning")
			setState("VoteOptions", "")
			return "Waiting"
		elseif nextPhase == "Intro" then
			state.SkipRequested = false
			setState("VoteOptions", "")
			return "Match"
		end
		task.wait(0.2)
	end
end

local function mainLoop()
	local step = "Waiting"
	while true do
		local current = step
		local ok, result = xpcall(function(): string
			if current == "Intermission" then
				return runIntermission()
			elseif current == "Match" then
				return runMatch(false)
			elseif current == "Practice" then
				return runMatch(true)
			end
			return runWaiting()
		end, debug.traceback)
		if ok then
			step = result
		else
			warn("[RoundService] round loop error (recovering to Waiting):\n" .. tostring(result))
			local okClean, cleanErr = pcall(cleanup)
			if not okClean then
				warn("[RoundService] cleanup error: " .. tostring(cleanErr))
			end
			step = "Waiting"
			task.wait(1)
		end
	end
end

-- Event handlers --------------------------------------------------------------------------------------------

local function onDied(model: Model, killer: Model?, ability: string?)
	local p = state.RoundModels[model]
	if p == nil or not state.InMatch then
		return
	end
	local root = rootOf(model)
	state.LastHit = { victim = model, position = if root then root.Position else nil }
	if p.Team == "Humans" then
		state.HumansLeftLast = false
	end
	fireRoundEvent("Kill", {
		victim = model,
		killer = killer,
		ability = ability,
		victimName = p.Name,
		killerName = if killer then nameOf(killer) else "",
		victimTeam = p.Team,
		victimUserId = p.UserId,
	})
	afterRosterChange()
end

local function onDowned(model: Model, attacker: Model?)
	local p = state.RoundModels[model]
	if p == nil or not state.InMatch then
		return
	end
	fireRoundEvent("Downed", { victim = model, attacker = attacker, name = p.Name, userId = p.UserId })
	afterRosterChange()
end

local function onRevived(model: Model, by: Model?)
	local p = state.RoundModels[model]
	if p == nil or not state.InMatch then
		return
	end
	fireRoundEvent("Revived", { victim = model, by = by, name = p.Name, byName = nameOf(by) })
	updateCounts()
end

local function onDamaged(info: any, result: any)
	if not state.InMatch or type(info) ~= "table" then
		return
	end
	if info.Target == state.Monster and state.Monster ~= nil then
		if type(result) == "table" and result.Killed == true then
			local root = rootOf(state.Monster)
			state.LastHit = { victim = state.Monster, position = if root then root.Position else nil }
		end
		checkFinalPhase()
	end
end

local function onPlayerRemoving(player: Player)
	state.Votes[player] = nil
	local pending = state.PracticeRequest
	if pending and pending.Player == player then
		state.PracticeRequest = nil
	end
	local p = state.Participants[player]
	if p == nil or not state.InMatch then
		return
	end
	if state.Practice and player == state.PracticePlayer then
		state.PracticePlayerLeft = true
		state.AbortRequested = true
		return
	end
	if p.Team == "Monster" then
		state.MonsterLeft = true
	else
		state.HumansLeftLast = true
	end
	fireRoundEvent("PlayerLeft", { name = p.Name, team = p.Team, userId = p.UserId })
	-- let CharacterService despawn the body first, then re-evaluate
	task.defer(function()
		local ok, err = pcall(afterRosterChange)
		if not ok then
			warn("[RoundService] leave handling: " .. tostring(err))
		end
	end)
end

local function onPlayerAdded(player: Player)
	if state.InMatch then
		task.delay(2, function()
			if state.InMatch and player.Parent ~= nil and state.Participants[player] == nil then
				notify(player, "round.notify.lateJoin", nil, "Info")
			end
		end)
	end
end

-- Public API ------------------------------------------------------------------------------------------------

function RoundService.State(): Configuration
	return ensureRoundState()
end

function RoundService.Phase(): string
	return state.Phase
end

function RoundService.InMatch(): boolean
	return state.InMatch
end

function RoundService.IsPractice(): boolean
	return state.Practice
end

function RoundService.GetMonster(): Model?
	return state.Monster
end

function RoundService.IsRoundCharacter(model: Model?): boolean
	return model ~= nil and state.RoundModels[model] ~= nil
end

function RoundService.TriggerFinalPhase(): boolean
	if state.FinalPhase or not isFightPhase() then
		return false
	end
	local monster = state.Monster
	if monster == nil or not isAlive(monster) then
		return false
	end
	state.FinalPhase = true
	call(StatusService, "Apply", monster, "Invulnerable", Config.Round.FinalPhaseInvulnerable)
	call(StatusService, "Remove", monster, "Exhausted")
	local maxDodges = monster:GetAttribute("MaxDodges")
	if type(maxDodges) == "number" then
		monster:SetAttribute("Dodges", maxDodges)
	end
	monster:SetAttribute("Exhausted", 0)
	monster:SetAttribute("Ult", 100)
	monster:SetAttribute("FinalForm", true)
	setState("FinalPhase", true)
	fireRoundEvent("FinalPhase", {
		monster = monster,
		kitId = monster:GetAttribute("KitId"),
		duration = Config.Round.FinalPhaseInvulnerable,
	})
	notifyAll("round.notify.finalPhase", nil, "Danger")
	RoundService.FinalPhaseStarted:Fire(monster)
	return true
end

function RoundService.StartPractice(player: Player, side: string?, allies: number?): (boolean, string?)
	if not Config.Practice.Enabled then
		return false, "round.practice.disabled"
	end
	if BotService == nil then
		return false, "round.practice.unavailable"
	end
	if state.InMatch or state.Phase ~= "Waiting" or #Players:GetPlayers() >= Config.Round.MinPlayers then
		return false, "round.practice.busy"
	end
	local alliesCount: number? = nil
	if type(allies) == "number" and allies == allies then
		alliesCount = math.clamp(math.floor(allies), 0, 5)
	end
	state.PracticeRequest = {
		Player = player,
		Side = if side == "Monster" then "Monster" else "Human",
		Allies = alliesCount,
	}
	notify(player, "round.practice.queued", nil, "Info")
	return true, nil
end

function RoundService.ForceNextMap(mapId: string): boolean
	if type(mapId) ~= "string" or Registry.Get(mapId) == nil then
		return false
	end
	state.ForcedMap = mapId
	if not state.InMatch then
		setState("MapId", mapId)
	end
	local meta = Registry.Info(mapId)
	notifyAll("round.vote.nextMap", { if meta then Strings.Pick(meta.Name) else mapId }, "Info")
	return true
end

-- Ends the current timed phase now (Intermission -> start, Intro -> fight, Round -> Collapse, ...).
function RoundService.SkipPhase()
	if state.Phase ~= "Waiting" then
		state.SkipRequested = true
	end
end

function RoundService.ForceCollapse(): boolean
	if state.InMatch and state.Phase == "Round" then
		state.ForceCollapse = true
		return true
	end
	return false
end

function RoundService.EndRound(winner: string?, reason: string?): boolean
	if not isMatchPhase() or state.Result ~= nil then
		return false
	end
	local w = if winner == "Monster" then "Monster" else "Humans"
	state.Result = { winner = w, reason = if type(reason) == "string" and reason ~= "" then reason else "Aborted" }
	return true
end

-- Stops the match without a results screen (everyone back to the lobby).
function RoundService.Abort(): boolean
	if not state.InMatch then
		return false
	end
	state.AbortRequested = true
	return true
end

-- Requests ----------------------------------------------------------------------------------------------------

local function onStartPracticeRequest(player: Player, data: any): (boolean, string?)
	local side: any = data
	local allies: any = nil
	if type(data) == "table" then
		side = data.side
		allies = data.allies
	end
	if side ~= nil and side ~= "Human" and side ~= "Monster" then
		return false, "round.practice.unavailable"
	end
	return RoundService.StartPractice(player, side, if type(allies) == "number" then allies else nil)
end

-- Lifecycle -----------------------------------------------------------------------------------------------------

function RoundService.Init()
	ensureRoundState()
	CharacterService = tryService("CharacterService")
	MapService = tryService("MapService")
	StatsService = tryService("StatsService")
	QueueService = tryService("QueueService")
	ObjectiveService = tryService("ObjectiveService")
	BotService = tryService("BotService")
	StatusService = tryService("StatusService")
	DamageService = tryService("DamageService")
	HazardService = tryService("HazardService")
	VerdictBoxService = tryService("VerdictBoxService")
	RequestService = tryService("RequestService")
	if RequestService and type(RequestService.Register) == "function" then
		for action, handler in { Vote = onVote, StartPractice = onStartPracticeRequest } :: { [string]: any } do
			local ok, err = pcall(RequestService.Register, action, handler)
			if not ok then
				warn("[RoundService] request " .. action .. " registration failed: " .. tostring(err))
			end
		end
	end
end

function RoundService.Start()
	if CharacterService == nil or MapService == nil then
		warn("[RoundService] CharacterService/MapService missing — round loop disabled")
		return
	end
	connect(CharacterService, "Died", onDied)
	connect(CharacterService, "Downed", onDowned)
	connect(CharacterService, "Revived", onRevived)
	connect(DamageService, "Damaged", onDamaged)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Players.PlayerAdded:Connect(onPlayerAdded)
	task.spawn(mainLoop)
end

return RoundService
