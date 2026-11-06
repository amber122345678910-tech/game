--!strict
-- STRETCH-POP · ProgressionService (сервер)
-- Прокачка трёх физических статов за монеты, покупка и экипировка перчаток, синхронизация профиля.
--
-- Каждый запрос клиента: проверка типов → лимит частоты (token bucket) → проверка профиля →
-- атомарная мутация через PlayerDataService.Update. Между проверкой баланса и списанием нет yield,
-- поэтому двойная покупка невозможна даже при залпе одинаковых запросов.
-- Цена уровня — StretchPhysics.UpgradeCost(уровень), потолок — PhysicsConfig.StatUpgrade.MaxLevel:
-- те же формулы показывает клиентский магазин, расхождений цены нет.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local GloveConfig = require(Shared.Config.GloveConfig)
local StretchPhysics = require(Shared.Physics.StretchPhysics)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)

local REQUEST_RATE = 6 -- запросов в секунду на игрока (прокачка + перчатки вместе)
local REQUEST_BURST = 10
local REJECT_REPLY_INTERVAL = 0.5 -- не отвечаем на флуд чаще этого (защита от усиления трафика)
local SYNC_DEBOUNCE = 0.5 -- изменения профиля копим и шлём одним снимком
local SYNC_REQUEST_COOLDOWN = 1

type Budget = {
	Tokens: number,
	At: number,
	LastRejectReply: number,
	LastSyncRequest: number,
}

local ProgressionService = {}

local budgets: { [Player]: Budget } = {}
local syncDue: { [Player]: number } = {}
local initialized = false

local function toStatName(value: unknown): Types.StatName?
	if value == "Elasticity" then
		return "Elasticity"
	elseif value == "SpringPower" then
		return "SpringPower"
	elseif value == "SmashMass" then
		return "SmashMass"
	end
	return nil
end

local function toGloveAction(value: unknown): Types.GloveActionKind?
	if value == "Buy" then
		return "Buy"
	elseif value == "Equip" then
		return "Equip"
	end
	return nil
end

function ProgressionService.ReadStat(stats: Types.PhysicalStats, stat: Types.StatName): number
	if stat == "Elasticity" then
		return stats.Elasticity
	elseif stat == "SpringPower" then
		return stats.SpringPower
	end
	return stats.SmashMass
end

local function writeStat(stats: Types.PhysicalStats, stat: Types.StatName, value: number)
	if stat == "Elasticity" then
		stats.Elasticity = value
	elseif stat == "SpringPower" then
		stats.SpringPower = value
	else
		stats.SmashMass = value
	end
end

local function getBudget(player: Player): Budget
	local budget = budgets[player]
	if budget == nil then
		budget = { Tokens = REQUEST_BURST, At = os.clock(), LastRejectReply = -math.huge, LastSyncRequest = -math.huge }
		budgets[player] = budget
	end
	return budget
end

-- Token bucket: true — запрос можно обрабатывать
local function allow(player: Player): boolean
	local budget = getBudget(player)
	local now = os.clock()
	budget.Tokens = math.min(REQUEST_BURST, budget.Tokens + (now - budget.At) * REQUEST_RATE)
	budget.At = now
	if budget.Tokens < 1 then
		return false
	end
	budget.Tokens -= 1
	return true
end

-- На флуд отвечаем не чаще раза в REJECT_REPLY_INTERVAL
local function mayReplyToFlood(player: Player): boolean
	local budget = getBudget(player)
	local now = os.clock()
	if now - budget.LastRejectReply < REJECT_REPLY_INTERVAL then
		return false
	end
	budget.LastRejectReply = now
	return true
end

function ProgressionService.BuildSnapshot(profile: Types.PlayerProfile): Types.ProfileSnapshot
	local owned: { string } = {}
	for gloveId, isOwned in profile.Gloves.Owned do
		if isOwned and GloveConfig.Exists(gloveId) then
			table.insert(owned, gloveId)
		end
	end
	table.sort(owned, function(a: string, b: string): boolean
		local priceA, priceB = GloveConfig.Get(a).Price, GloveConfig.Get(b).Price
		if priceA == priceB then
			return a < b
		end
		return priceA < priceB
	end)
	local locations: { [string]: Types.LocationProgress } = {}
	for locationId, progress in profile.Locations do
		locations[locationId] = {
			Tier = progress.Tier,
			Rebirths = progress.Rebirths,
			BestSpeed = progress.BestSpeed,
			BestCombo = progress.BestCombo,
		}
	end
	local records = profile.Records
	return {
		Coins = profile.Coins,
		Stats = {
			Elasticity = profile.Stats.Elasticity,
			SpringPower = profile.Stats.SpringPower,
			SmashMass = profile.Stats.SmashMass,
		},
		OwnedGloves = owned,
		EquippedGlove = profile.Gloves.Equipped,
		Records = {
			TopSpeed = records.TopSpeed,
			LongestCombo = records.LongestCombo,
			WallsSmashed = records.WallsSmashed,
			ChestsOpened = records.ChestsOpened,
			LootEarned = records.LootEarned,
		},
		Locations = locations,
		ActiveLocation = profile.ActiveLocation,
		TotalRebirths = profile.TotalRebirths,
		DataOffline = PlayerDataService.IsOffline(),
		ServerTime = workspace:GetServerTimeNow(),
	}
end

local function sendSnapshot(player: Player)
	syncDue[player] = nil
	local profile = PlayerDataService.Get(player)
	if profile and player.Parent == Players then
		Net.ProfileSync:FireClient(player, ProgressionService.BuildSnapshot(profile))
	end
end

local function queueSync(player: Player)
	if syncDue[player] == nil then
		syncDue[player] = os.clock() + SYNC_DEBOUNCE
	end
end

-- ── Прокачка статов ─────────────────────────────────────────────────────────

-- Возвращает (успех, причина, новый уровень). Публично — для тестов и будущих наград.
function ProgressionService.TryUpgrade(player: Player, stat: Types.StatName): (boolean, string, number)
	local profile = PlayerDataService.Get(player)
	if profile == nil then
		return false, "no_profile", 0
	end
	local level = ProgressionService.ReadStat(profile.Stats, stat)
	if level >= PhysicsConfig.StatUpgrade.MaxLevel then
		return false, "max_level", level
	end
	local cost = StretchPhysics.UpgradeCost(level)
	if profile.Coins < cost then
		return false, "not_enough_coins", level
	end
	PlayerDataService.Update(player, function(mutable: Types.PlayerProfile)
		mutable.Coins -= cost
		writeStat(mutable.Stats, stat, level + 1)
	end)
	return true, "upgraded", level + 1
end

local function onUpgradeStat(player: Player, rawStat: unknown)
	local stat = toStatName(rawStat)
	if stat == nil then
		return
	end
	if not allow(player) then
		if mayReplyToFlood(player) then
			Net.UpgradeStat:FireClient(player, stat, false, "rate_limited", -1, player:GetAttribute("Coins") or 0)
		end
		return
	end
	local accepted, reason, level = ProgressionService.TryUpgrade(player, stat)
	local profile = PlayerDataService.Get(player)
	Net.UpgradeStat:FireClient(player, stat, accepted, reason, level, if profile then profile.Coins else 0)
	if accepted then
		queueSync(player)
	end
end

-- ── Перчатки ────────────────────────────────────────────────────────────────

function ProgressionService.TryGloveAction(player: Player, action: Types.GloveActionKind, gloveId: string): (boolean, string)
	local profile = PlayerDataService.Get(player)
	if profile == nil then
		return false, "no_profile"
	end
	if not GloveConfig.Exists(gloveId) then
		return false, "unknown_glove"
	end
	local glove = GloveConfig.Get(gloveId)
	local owned = profile.Gloves.Owned[gloveId] == true
	if action == "Buy" then
		if owned then
			return false, "already_owned"
		end
		if profile.Coins < glove.Price then
			return false, "not_enough_coins"
		end
		PlayerDataService.Update(player, function(mutable: Types.PlayerProfile)
			mutable.Coins -= glove.Price
			mutable.Gloves.Owned[gloveId] = true
			mutable.Gloves.Equipped = gloveId -- купил — сразу надел
		end)
		return true, "bought"
	end
	if not owned then
		return false, "not_owned"
	end
	if profile.Gloves.Equipped ~= gloveId then
		PlayerDataService.Update(player, function(mutable: Types.PlayerProfile)
			mutable.Gloves.Equipped = gloveId
		end)
	end
	return true, "equipped"
end

local function onGloveAction(player: Player, rawAction: unknown, rawGloveId: unknown)
	local action = toGloveAction(rawAction)
	if action == nil or typeof(rawGloveId) ~= "string" or #rawGloveId == 0 or #rawGloveId > 32 then
		return
	end
	local gloveId: string = rawGloveId
	if not allow(player) then
		if mayReplyToFlood(player) then
			Net.GloveAction:FireClient(player, action, gloveId, false, "rate_limited")
		end
		return
	end
	local accepted, reason = ProgressionService.TryGloveAction(player, action, gloveId)
	Net.GloveAction:FireClient(player, action, gloveId, accepted, reason)
	if accepted then
		queueSync(player)
	end
end

-- ── Синхронизация ───────────────────────────────────────────────────────────

local function onSyncRequest(player: Player)
	local budget = getBudget(player)
	local now = os.clock()
	if now - budget.LastSyncRequest < SYNC_REQUEST_COOLDOWN then
		queueSync(player) -- частые запросы схлопываются в один отложенный снимок
		return
	end
	budget.LastSyncRequest = now
	sendSnapshot(player)
end

function ProgressionService.Init()
	if initialized then
		return
	end
	initialized = true

	Net.UpgradeStat.OnServerEvent:Connect(onUpgradeStat)
	Net.GloveAction.OnServerEvent:Connect(onGloveAction)
	Net.ProfileSync.OnServerEvent:Connect(onSyncRequest)

	PlayerDataService.ProfileLoaded:Connect(function(player: Player, _profile: Types.PlayerProfile)
		sendSnapshot(player)
	end)
	PlayerDataService.ProfileChanged:Connect(function(player: Player, _profile: Types.PlayerProfile)
		queueSync(player) -- лут, рекорды, ребёрты: один снимок на полсекунды, а не на каждый удар
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		budgets[player] = nil
		syncDue[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, due in syncDue do
			if now >= due then
				sendSnapshot(player)
			end
		end
	end)
end

return ProgressionService
