--!strict
-- STRETCH-POP · ProgressionService (сервер)
-- Прокачка трёх физических статов за монеты, покупка и экипировка перчаток, гача-капсулы
-- с бадди (вылупление, экипировка, отпуск, крафт мутаций 3 → 1), синхронизация профиля.
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
local BuddyConfig = require(Shared.Config.BuddyConfig)
local ProfileTemplate = require(Shared.Data.ProfileTemplate)
local StretchPhysics = require(Shared.Physics.StretchPhysics)
local Net = require(Shared.Net)

local PlayerDataService = require(script.Parent.PlayerDataService)

local REQUEST_RATE = 6 -- запросов в секунду на игрока (прокачка + перчатки вместе)
local REQUEST_BURST = 10
local REJECT_REPLY_INTERVAL = 0.5 -- не отвечаем на флуд чаще этого (защита от усиления трафика)
local SYNC_DEBOUNCE = 0.5 -- изменения профиля копим и шлём одним снимком
local SYNC_REQUEST_COOLDOWN = 1
local HATCH_COOLDOWN = 1.1 -- анимация вылупления ~2.4 с; чаще одного открытия в секунду нельзя

type Budget = {
	Tokens: number,
	At: number,
	LastRejectReply: number,
	LastSyncRequest: number,
	LastHatch: number,
}

local ProgressionService = {}

local budgets: { [Player]: Budget } = {}
local syncDue: { [Player]: number } = {}
local initialized = false
local rng = Random.new()

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

local function toBuddyAction(value: unknown): Types.BuddyActionKind?
	if value == "Equip" then
		return "Equip"
	elseif value == "Unequip" then
		return "Unequip"
	elseif value == "Release" then
		return "Release"
	elseif value == "Craft" then
		return "Craft"
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
		budget = { Tokens = REQUEST_BURST, At = os.clock(), LastRejectReply = -math.huge, LastSyncRequest = -math.huge, LastHatch = -math.huge }
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

local function isEquipped(profile: Types.PlayerProfile, uid: string): boolean
	return table.find(profile.Buddies.Equipped, uid) ~= nil
end

local function inventoryCount(profile: Types.PlayerProfile): number
	local count = 0
	for _ in profile.Buddies.Inventory do
		count += 1
	end
	return count
end

local function buddySnapshots(profile: Types.PlayerProfile): { Types.BuddySnapshot }
	local list: { Types.BuddySnapshot } = {}
	for uid, instance in profile.Buddies.Inventory do
		if BuddyConfig.Get(instance.BuddyId) then
			table.insert(list, { Uid = uid, BuddyId = instance.BuddyId, Mutation = instance.Mutation, Equipped = isEquipped(profile, uid) })
		end
	end
	-- экипированные → редкость ↓ → мутация ↓ → id → uid: стабильный порядок для витрины
	table.sort(list, function(a: Types.BuddySnapshot, b: Types.BuddySnapshot): boolean
		if a.Equipped ~= b.Equipped then
			return a.Equipped
		end
		local defA, defB = BuddyConfig.Get(a.BuddyId), BuddyConfig.Get(b.BuddyId)
		local rarityA = if defA then BuddyConfig.Rarities[defA.Rarity].Order else 0
		local rarityB = if defB then BuddyConfig.Rarities[defB.Rarity].Order else 0
		if rarityA ~= rarityB then
			return rarityA > rarityB
		end
		local mutationA, mutationB = BuddyConfig.Mutations[a.Mutation].Order, BuddyConfig.Mutations[b.Mutation].Order
		if mutationA ~= mutationB then
			return mutationA > mutationB
		end
		if a.BuddyId ~= b.BuddyId then
			return a.BuddyId < b.BuddyId
		end
		return a.Uid < b.Uid
	end)
	return list
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
		Buddies = buddySnapshots(profile),
		Records = {
			TopSpeed = records.TopSpeed,
			LongestCombo = records.LongestCombo,
			WallsSmashed = records.WallsSmashed,
			ChestsOpened = records.ChestsOpened,
			LootEarned = records.LootEarned,
			CapsulesOpened = records.CapsulesOpened,
			PinatasPopped = records.PinatasPopped,
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

-- ── Гача-капсулы и бадди ─────────────────────────────────────────────────────

-- Открыть капсулу: (успех, причина, выпавший бадди). Ролл — на сервере, шанс мутации растёт с тиром локации.
function ProgressionService.TryHatch(player: Player, capsuleId: string): (boolean, string, Types.BuddySnapshot?)
	local capsule = BuddyConfig.Capsules[capsuleId]
	if capsule == nil then
		return false, "unknown_capsule", nil
	end
	local profile = PlayerDataService.Get(player)
	if profile == nil then
		return false, "no_profile", nil
	end
	if inventoryCount(profile) >= BuddyConfig.MaxInventory then
		return false, "inventory_full", nil
	end
	if profile.Coins < capsule.Price then
		return false, "not_enough_coins", nil
	end
	local tier = ProfileTemplate.GetLocation(profile, profile.ActiveLocation).Tier
	local buddyId = BuddyConfig.RollBuddy(capsuleId, rng)
	local mutation = BuddyConfig.RollMutation(tier, capsuleId, rng)
	local uid = "b" .. profile.Buddies.NextUid
	local equipped = false
	PlayerDataService.Update(player, function(mutable: Types.PlayerProfile)
		mutable.Coins -= capsule.Price
		mutable.Buddies.Inventory[uid] = { BuddyId = buddyId, Mutation = mutation, Obtained = os.time() }
		mutable.Buddies.NextUid += 1
		mutable.Records.CapsulesOpened += 1
		if #mutable.Buddies.Equipped < BuddyConfig.MaxEquipped then
			table.insert(mutable.Buddies.Equipped, uid)
			equipped = true
		end
	end)
	return true, "hatched", { Uid = uid, BuddyId = buddyId, Mutation = mutation, Equipped = equipped }
end

local function handleHatch(player: Player, capsuleId: string)
	local budget = getBudget(player)
	local now = os.clock()
	if not allow(player) or now - budget.LastHatch < HATCH_COOLDOWN then
		if mayReplyToFlood(player) then
			Net.HatchCapsule:FireClient(player, capsuleId, false, "rate_limited", nil)
		end
		return
	end
	local accepted, reason, buddy = ProgressionService.TryHatch(player, capsuleId)
	if accepted then
		budget.LastHatch = now
		queueSync(player)
	end
	Net.HatchCapsule:FireClient(player, capsuleId, accepted, reason, buddy)
end

local function onHatchRequest(player: Player, rawCapsuleId: unknown)
	if typeof(rawCapsuleId) ~= "string" or BuddyConfig.Capsules[rawCapsuleId] == nil then
		return
	end
	handleHatch(player, rawCapsuleId)
end

-- (успех, причина, uid результата)
function ProgressionService.TryBuddyAction(player: Player, action: Types.BuddyActionKind, a: string, b: string?): (boolean, string, string?)
	local profile = PlayerDataService.Get(player)
	if profile == nil then
		return false, "no_profile", nil
	end
	local buddies = profile.Buddies

	if action == "Craft" then
		local mutation = BuddyConfig.ToMutation(b)
		if BuddyConfig.Get(a) == nil or mutation == nil then
			return false, "unknown_buddy", nil
		end
		local nextMutation = BuddyConfig.NextMutation(mutation)
		if nextMutation == nil then
			return false, "max_mutation", nil
		end
		-- сначала тратим неэкипированных; среди равных — самых старых по uid
		local candidates: { string } = {}
		for uid, instance in buddies.Inventory do
			if instance.BuddyId == a and instance.Mutation == mutation then
				table.insert(candidates, uid)
			end
		end
		if #candidates < BuddyConfig.CraftCount then
			return false, "not_enough_copies", nil
		end
		table.sort(candidates, function(x: string, y: string): boolean
			local ex, ey = isEquipped(profile, x), isEquipped(profile, y)
			if ex ~= ey then
				return not ex
			end
			return (tonumber(x:sub(2)) or 0) < (tonumber(y:sub(2)) or 0)
		end)
		local newUid = "b" .. buddies.NextUid
		PlayerDataService.Update(player, function(mutable: Types.PlayerProfile)
			local inventory = mutable.Buddies
			local slot: number? = nil
			for index = 1, BuddyConfig.CraftCount do
				local uid = candidates[index]
				inventory.Inventory[uid] = nil
				local position = table.find(inventory.Equipped, uid)
				if position then
					table.remove(inventory.Equipped, position)
					slot = if slot then math.min(slot, position) else position
				end
			end
			inventory.Inventory[newUid] = { BuddyId = a, Mutation = nextMutation, Obtained = os.time() }
			inventory.NextUid += 1
			if slot then
				table.insert(inventory.Equipped, math.min(slot, #inventory.Equipped + 1), newUid)
			end
		end)
		return true, "crafted", newUid
	end

	local instance = buddies.Inventory[a]
	if instance == nil then
		return false, "not_owned", nil
	end
	if action == "Equip" then
		if isEquipped(profile, a) then
			return true, "equipped", a
		end
		if #buddies.Equipped >= BuddyConfig.MaxEquipped then
			return false, "slots_full", nil
		end
		PlayerDataService.Update(player, function(mutable: Types.PlayerProfile)
			table.insert(mutable.Buddies.Equipped, a)
		end)
		return true, "equipped", a
	elseif action == "Unequip" then
		local position = table.find(buddies.Equipped, a)
		if position then
			PlayerDataService.Update(player, function(mutable: Types.PlayerProfile)
				local index = table.find(mutable.Buddies.Equipped, a)
				if index then
					table.remove(mutable.Buddies.Equipped, index)
				end
			end)
		end
		return true, "unequipped", a
	end
	-- Release: бадди уходит, игрок получает монеты
	local refund = BuddyConfig.ReleaseValue(instance.BuddyId, instance.Mutation)
	PlayerDataService.Update(player, function(mutable: Types.PlayerProfile)
		mutable.Buddies.Inventory[a] = nil
		local index = table.find(mutable.Buddies.Equipped, a)
		if index then
			table.remove(mutable.Buddies.Equipped, index)
		end
		mutable.Coins += refund
	end)
	return true, "released", a
end

local function onBuddyAction(player: Player, rawAction: unknown, rawA: unknown, rawB: unknown)
	local action = toBuddyAction(rawAction)
	if action == nil or typeof(rawA) ~= "string" or #rawA == 0 or #rawA > 32 then
		return
	end
	if rawB ~= nil and (typeof(rawB) ~= "string" or #rawB > 32) then
		return
	end
	local a: string = rawA
	local b: string? = if typeof(rawB) == "string" then rawB else nil
	if not allow(player) then
		if mayReplyToFlood(player) then
			Net.BuddyAction:FireClient(player, action, false, "rate_limited", nil)
		end
		return
	end
	local accepted, reason, uid = ProgressionService.TryBuddyAction(player, action, a, b)
	Net.BuddyAction:FireClient(player, action, accepted, reason, uid)
	if accepted then
		queueSync(player)
	end
end

-- Автоматы на Капсульной площади: подошёл, зажал E (или тапнул) — капсула открывается
function ProgressionService.BindCapsuleMachines(machines: { [string]: BasePart })
	for capsuleId, body in machines do
		local prompt = body:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player: Player)
				handleHatch(player, capsuleId)
			end)
		end
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
	Net.HatchCapsule.OnServerEvent:Connect(onHatchRequest)
	Net.BuddyAction.OnServerEvent:Connect(onBuddyAction)

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
