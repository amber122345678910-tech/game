--!strict
-- Цикл матча: лобби → отсчёт → (день → оповещение → ночь → рассвет) × N → итоги → лобби.
-- Готовность, голосование за сложность и пропуск оповещения, награды, табло рекордов.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Inmates = require(Shared:WaitForChild("Inmates"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Locale = require(Shared:WaitForChild("Locale"))

local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local HouseService = require(script.Parent:WaitForChild("HouseService"))
local AppleService = require(script.Parent:WaitForChild("AppleService"))
local ItemService = require(script.Parent:WaitForChild("ItemService"))
local InmateService = require(script.Parent:WaitForChild("InmateService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))

local RoundService = {}

export type Phase = "Lobby" | "Countdown" | "Day" | "Alert" | "Night" | "Dawn" | "Results"

local phase: Phase = "Lobby"
local phaseEnds = 0
local phaseLength = 0
local night = 0
local difficulty = Config.getDifficulty(nil)
local currentInmates: { string } = {}
local lastInmates: { string } = {}
local ready: { [Player]: boolean } = {}
local votes: { [Player]: string } = {}
local skipVotes: { [Player]: boolean } = {}
local participants: { [Player]: boolean } = {} -- кто играет в текущем матче
local nightsSurvivedBy: { [Player]: number } = {}
local rng = Random.new()
local stateDirty = true
local lastStateSent = 0
local leaderboardStore: OrderedDataStore? = nil
local leaderboardRows: { { Name: string, Nights: number } } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function setPhase(p: Phase, length: number)
	phase = p
	phaseLength = length
	phaseEnds = serverNow() + length
	stateDirty = true
	PlayerService.isMatchRunning = function()
		return phase == "Day" or phase == "Alert" or phase == "Night" or phase == "Dawn"
	end
	PlayerService.isNight = function()
		return phase == "Night" or phase == "Alert"
	end
	ItemService.ShopOpen = phase == "Day" or phase == "Dawn"
end

local function countReady(): number
	local n = 0
	for p, r in ready do
		if r and p.Parent == Players then
			n += 1
		end
	end
	return n
end

local function tallyVotes(): ({ [string]: number }, string)
	local counts: { [string]: number } = {}
	for _, d in Config.difficultyList() do
		counts[d.Id] = 0
	end
	for p, id in votes do
		if p.Parent == Players and counts[id] then
			counts[id] += 1
		end
	end
	local best = Config.DefaultDifficulty
	local bestN = -1
	for _, d in Config.difficultyList() do
		local n = counts[d.Id]
		if n > bestN or (n == bestN and d.Id == Config.DefaultDifficulty) then
			best = d.Id
			bestN = n
		end
	end
	if bestN <= 0 then
		best = Config.DefaultDifficulty
	end
	return counts, best
end

local function snapshot(): Remotes.StateSnapshot
	local counts = tallyVotes()
	local skip = 0
	for p, v in skipVotes do
		if v and p.Parent == Players then
			skip += 1
		end
	end
	return {
		Phase = phase,
		Night = night,
		Nights = difficulty.Nights,
		Difficulty = difficulty.Id,
		PhaseEnds = phaseEnds,
		PhaseLength = phaseLength,
		Cash = ItemService.Cash,
		Apples = AppleService.Apples,
		Trees = AppleService.treeCount(),
		Inmates = currentInmates,
		Alive = PlayerService.aliveCount(),
		Players = #Players:GetPlayers(),
		Ready = countReady(),
		Votes = counts,
		SkipVotes = skip,
		Upgrades = table.clone(ItemService.Upgrades),
		Prices = ItemService.prices(),
	}
end

local function broadcastState()
	stateDirty = false
	lastStateSent = os.clock()
	Remotes.State:FireAllClients(snapshot())
end

function RoundService.markDirty()
	stateDirty = true
end

----------------------------------------------------------------------
-- Матч
----------------------------------------------------------------------
local function inMatch(): boolean
	return phase == "Day" or phase == "Alert" or phase == "Night" or phase == "Dawn"
end

local function participantsAlive(): number
	local n = 0
	for p in participants do
		local rec = PlayerService.get(p)
		if p.Parent == Players and rec and (PlayerService.isAlive(rec) or rec.Status == "Downed") then
			n += 1
		end
	end
	return n
end

local function startMatch()
	local _, chosen = tallyVotes()
	difficulty = Config.getDifficulty(chosen)
	night = 0
	lastInmates = {}
	currentInmates = {}
	participants = {}
	nightsSurvivedBy = {}
	skipVotes = {}
	HouseService.resetMatch()
	AppleService.resetMatch()
	ItemService.resetMatch(difficulty)
	InmateService.clear()
	NoiseService.clear()
	local i = 0
	for _, p in Players:GetPlayers() do
		i += 1
		participants[p] = true
		nightsSurvivedBy[p] = 0
		PlayerService.spawnInHouse(p, i)
		ItemService.replicate(p)
	end
	Remotes.FX:FireAllClients("DayStart", { Night = 1 })
end

local function startDay()
	night += 1
	currentInmates = {}
	stateDirty = true
	HouseService.onDawn()
	setPhase("Day", if night == 1 then Config.Phases.FirstDay else Config.Phases.Day)
	-- вернуть забранных (Easy/Normal)
	if difficulty.ReturnTakenAtDawn then
		local i = 0
		for p in participants do
			i += 1
			local rec = PlayerService.get(p)
			if p.Parent == Players and rec and rec.Status == "Taken" then
				ItemService.clear(p)
				PlayerService.spawnInHouse(p, i)
				Remotes.Notify:FireClient(p, "N_Returned", "info")
			end
		end
	end
	Remotes.FX:FireAllClients("DayStart", { Night = night })
end

local function startAlert()
	skipVotes = {}
	local slots = Config.inmatesForNight(difficulty, night)
	local forceBoss = (difficulty.Id == "Hard" or difficulty.Id == "Nightmare") and night == difficulty.Nights
	currentInmates = Inmates.pickForNight(night, slots, lastInmates, forceBoss, rng)
	lastInmates = table.clone(currentInmates)
	setPhase("Alert", Config.Phases.Alert)
	local text = Locale.t("AlertEas") .. "\n"
	for _, id in currentInmates do
		local def = Inmates.get(id)
		if def then
			text ..= string.format("\n%s %s — %s\n%s\n", "PATIENT", def.Number, string.upper(Locale.inmateName(id)), Locale.inmateAlert(id))
		end
	end
	HouseService.setTV(true, text)
	Remotes.Alert:FireAllClients(currentInmates)
	ItemService.ShopOpen = false
end

local function startNight()
	setPhase("Night", Config.nightDuration(night))
	HouseService.setTV(false)
	InmateService.spawnForNight(night, currentInmates, difficulty)
	Remotes.FX:FireAllClients("NightStart", { Night = night, Inmates = currentInmates })
	-- телефон звонит ночью иногда (с 2-й ночи)
	if night >= 2 and rng:NextNumber() < 0.5 then
		task.delay(rng:NextNumber(20, 50), function()
			if phase == "Night" then
				HouseService.ringPhone(8)
			end
		end)
	end
end

local function rewardNight()
	for p in participants do
		local rec = PlayerService.get(p)
		if p.Parent == Players and rec and (PlayerService.isAlive(rec) or rec.Status == "Downed") then
			nightsSurvivedBy[p] = (nightsSurvivedBy[p] or 0) + 1
			local amber = difficulty.AmberPerNight
			DataService.addAmber(p, amber)
			DataService.addXp(p, Config.Progression.XpPerNight)
			DataService.recordNight(p)
			Remotes.Notify:FireClient(p, "N_NightSurvived", "success", { night, amber })
		end
	end
end

local function startDawn()
	setPhase("Dawn", Config.Phases.Dawn)
	InmateService.retreatAll()
	rewardNight()
	-- поднять поваленных на рассвете
	for p in participants do
		local rec = PlayerService.get(p)
		if p.Parent == Players and rec and rec.Status == "Downed" then
			PlayerService.revive(p, nil)
		end
	end
	Remotes.FX:FireAllClients("Dawn", { Night = night })
end

local function awardBadge(player: Player, key: string)
	local id = Config.Badges[key]
	if not id or id <= 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, id) then
				BadgeService:AwardBadgeAsync(player.UserId, id)
			end
		end)
	end)
end

local function submitRecord(player: Player, nights: number)
	local store = leaderboardStore
	if not store or nights <= 0 then
		return
	end
	local function transform(old: any): any
		local prev = if typeof(old) == "number" then old else 0
		return math.max(prev, nights)
	end
	task.spawn(function()
		pcall(function()
			store:UpdateAsync(tostring(player.UserId), transform :: any)
		end)
	end)
end

local function refreshLeaderboard()
	local store = leaderboardStore
	if not store then
		Remotes.Leaderboard:FireAllClients(leaderboardRows)
		return
	end
	task.spawn(function()
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, 10)
		end)
		if not ok then
			return
		end
		local rows = {}
		local okPage, page = pcall(function()
			return pages:GetCurrentPage()
		end)
		if not okPage then
			return
		end
		for _, entry in page do
			local userId = tonumber(entry.key)
			local name = "???"
			if userId then
				local okName, n = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				if okName then
					name = n
				end
			end
			table.insert(rows, { Name = name, Nights = entry.value })
		end
		leaderboardRows = rows
		Remotes.Leaderboard:FireAllClients(rows)
	end)
end

local function endMatch(won: boolean)
	InmateService.clear()
	HouseService.setTV(false)
	local survivors: { string } = {}
	for p in participants do
		if p.Parent ~= Players then
			continue
		end
		local rec = PlayerService.get(p)
		local nights = nightsSurvivedBy[p] or 0
		if rec and (PlayerService.isAlive(rec) or rec.Status == "Downed") then
			table.insert(survivors, p.DisplayName)
		end
		local amber = 0
		local xp = 0
		if won then
			amber = Config.Progression.AmberWinBase + math.floor(difficulty.AmberPerNight * difficulty.Nights / 2)
			xp = Config.Progression.XpWin
			DataService.addAmber(p, amber)
			DataService.addXp(p, xp)
			awardBadge(p, "FirstWin")
			if difficulty.Id == "Hard" then
				awardBadge(p, "WinHard")
			elseif difficulty.Id == "Nightmare" then
				awardBadge(p, "WinNightmare")
			end
		end
		if nights >= 1 then
			awardBadge(p, "FirstNight")
		end
		if nights >= 10 then
			awardBadge(p, "Survived10")
		end
		DataService.recordRun(p, nights, won)
		submitRecord(p, nights)
		Remotes.Result:FireClient(p, {
			Won = won,
			Night = nights,
			Nights = difficulty.Nights,
			Difficulty = difficulty.Id,
			AmberEarned = amber + difficulty.AmberPerNight * nights,
			XpEarned = xp + Config.Progression.XpPerNight * nights,
			Survivors = survivors,
		})
	end
	setPhase("Results", Config.Phases.Results)
	PlayerService.resetAllToLobby()
	ready = {}
	task.delay(2, refreshLeaderboard)
end

----------------------------------------------------------------------
-- Главный цикл
----------------------------------------------------------------------
local function step()
	local t = serverNow()
	if phase == "Lobby" then
		if #Players:GetPlayers() >= Config.Phases.LobbyMinPlayers and countReady() >= math.max(1, math.ceil(#Players:GetPlayers() / 2)) then
			setPhase("Countdown", Config.Phases.LobbyCountdown)
		end
	elseif phase == "Countdown" then
		local total = #Players:GetPlayers()
		local readyN = countReady()
		if readyN == 0 or total == 0 then
			setPhase("Lobby", 0)
		else
			-- все готовы: сокращаем отсчёт до 5 секунд (один раз)
			if readyN >= total and phaseEnds - t > 5 then
				phaseEnds = t + 5
				phaseLength = 5
				stateDirty = true
			end
			if t >= phaseEnds then
				startMatch()
				startDay()
			end
		end
	elseif phase == "Day" then
		if t >= phaseEnds then
			startAlert()
		end
	elseif phase == "Alert" then
		local players = #Players:GetPlayers()
		local skip = 0
		for p, v in skipVotes do
			if v and p.Parent == Players then
				skip += 1
			end
		end
		if t >= phaseEnds or (players > 0 and skip > players / 2) then
			startNight()
		end
	elseif phase == "Night" then
		if participantsAlive() == 0 then
			endMatch(false)
		elseif t >= phaseEnds then
			startDawn()
		end
	elseif phase == "Dawn" then
		if t >= phaseEnds then
			if night >= difficulty.Nights then
				endMatch(true)
			else
				startDay()
			end
		end
	elseif phase == "Results" then
		if t >= phaseEnds then
			setPhase("Lobby", 0)
		end
	end
	if inMatch() and participantsAlive() == 0 and phase ~= "Night" then
		endMatch(false)
	end
end

function RoundService.phase(): Phase
	return phase
end

function RoundService.init()
	pcall(function()
		if game.PlaceId ~= 0 then
			leaderboardStore = DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName .. (if RunService:IsStudio() then "_Studio" else ""))
		end
	end)
	setPhase("Lobby", 0)

	Remotes.Ready.OnServerEvent:Connect(function(player, value)
		if typeof(value) ~= "boolean" or inMatch() then
			return
		end
		ready[player] = value
		stateDirty = true
	end)
	HouseService.ReadyPadRequested:Connect(function(player)
		if inMatch() then
			return
		end
		ready[player] = not ready[player]
		stateDirty = true
	end)
	Remotes.VoteDifficulty.OnServerEvent:Connect(function(player, id)
		if typeof(id) ~= "string" or not Config.Difficulties[id] or inMatch() then
			return
		end
		votes[player] = id
		stateDirty = true
	end)
	Remotes.VoteSkipAlert.OnServerEvent:Connect(function(player)
		if phase == "Alert" then
			skipVotes[player] = true
			stateDirty = true
		end
	end)
	Remotes.BuyPerk.OnServerInvoke = function(player: Player, perkId: any): (boolean, string)
		if typeof(perkId) ~= "string" then
			return false, "N_CantNow"
		end
		return DataService.tryBuyPerk(player, perkId)
	end
	HouseService.PerksRequested:Connect(function(player)
		Remotes.FX:FireClient(player, "OpenPerks", nil)
	end)
	ItemService.Changed:Connect(function()
		stateDirty = true
	end)
	AppleService.Changed:Connect(function()
		stateDirty = true
	end)
	PlayerService.StatusChanged:Connect(function()
		stateDirty = true
	end)
	InmateService.Defeated:Connect(function()
		currentInmates = InmateService.activeIds()
		stateDirty = true
	end)
	-- Собиратель крадёт
	InmateService.lootAt = ItemService.nearestLoot
	InmateService.stealAt = function(pos: Vector3): boolean
		return ItemService.stealNear(pos, 4)
	end

	Players.PlayerAdded:Connect(function(player)
		stateDirty = true
		task.delay(1, function()
			if player.Parent == Players then
				Remotes.State:FireClient(player, snapshot())
				Remotes.Leaderboard:FireClient(player, leaderboardRows)
				if inMatch() then
					PlayerService.spectate(player)
				end
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
		votes[player] = nil
		skipVotes[player] = nil
		participants[player] = nil
		stateDirty = true
	end)

	refreshLeaderboard()

	task.spawn(function()
		local acc = 0
		while true do
			local dt = task.wait(0.2)
			acc += dt
			local ok, err = pcall(step)
			if not ok then
				warn("[Round] step failed: " .. tostring(err))
			end
			AppleService.tick(dt, inMatch())
			if stateDirty or os.clock() - lastStateSent > 2 then
				broadcastState()
			end
		end
	end)
end

return RoundService
