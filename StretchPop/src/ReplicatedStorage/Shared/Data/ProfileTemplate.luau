--!strict
-- STRETCH-POP · Шаблон профиля и санитайзер данных из DataStore.
-- Любые данные из хранилища считаются недоверенными: каждое поле проверяется по типу и диапазону,
-- отсутствующие поля (старые версии профиля) получают значения по умолчанию — это и есть миграция.

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local GloveConfig = require(Shared.Config.GloveConfig)
local LevelConfig = require(Shared.Config.LevelConfig)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local BuddyConfig = require(Shared.Config.BuddyConfig)

local DATA_VERSION = 1
local MAX_NUMBER = 1e15

local ProfileTemplate = {
	DataVersion = DATA_VERSION,
}

local function newLocation(): Types.LocationProgress
	return { Tier = 0, Rebirths = 0, BestSpeed = 0, BestCombo = 0 }
end

function ProfileTemplate.NewLocation(): Types.LocationProgress
	return newLocation()
end

function ProfileTemplate.Create(nowUnix: number): Types.PlayerProfile
	return {
		DataVersion = DATA_VERSION,
		Coins = 0,
		Stats = { Elasticity = 0, SpringPower = 0, SmashMass = 0 },
		Gloves = {
			Owned = { [GloveConfig.DefaultGlove] = true },
			Equipped = GloveConfig.DefaultGlove,
		},
		Buddies = { Inventory = {}, Equipped = {}, NextUid = 1 },
		Locations = { [LevelConfig.DefaultLocation] = newLocation() },
		ActiveLocation = LevelConfig.DefaultLocation,
		TotalRebirths = 0,
		Records = {
			TopSpeed = 0,
			LongestCombo = 0,
			WallsSmashed = 0,
			ChestsOpened = 0,
			LootEarned = 0,
			CapsulesOpened = 0,
			PinatasPopped = 0,
		},
		FirstJoinUnix = nowUnix,
		LastJoinUnix = nowUnix,
		PlaySeconds = 0,
	}
end

local function readNumber(value: any, fallback: number, minValue: number, maxValue: number, integer: boolean): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	local clamped = math.clamp(value, minValue, maxValue)
	if integer then
		clamped = math.floor(clamped)
	end
	return clamped
end

local function readStat(value: any): number
	return readNumber(value, 0, 0, PhysicsConfig.StatUpgrade.MaxLevel, true)
end

function ProfileTemplate.Sanitize(raw: any, nowUnix: number): Types.PlayerProfile
	local profile = ProfileTemplate.Create(nowUnix)
	if type(raw) ~= "table" then
		return profile
	end

	profile.Coins = readNumber(raw.Coins, 0, 0, MAX_NUMBER, true)
	profile.TotalRebirths = readNumber(raw.TotalRebirths, 0, 0, MAX_NUMBER, true)
	profile.FirstJoinUnix = readNumber(raw.FirstJoinUnix, nowUnix, 0, MAX_NUMBER, true)
	profile.LastJoinUnix = nowUnix
	profile.PlaySeconds = readNumber(raw.PlaySeconds, 0, 0, MAX_NUMBER, false)

	local stats = raw.Stats
	if type(stats) == "table" then
		profile.Stats.Elasticity = readStat(stats.Elasticity)
		profile.Stats.SpringPower = readStat(stats.SpringPower)
		profile.Stats.SmashMass = readStat(stats.SmashMass)
	end

	local gloves = raw.Gloves
	if type(gloves) == "table" then
		local owned = gloves.Owned
		if type(owned) == "table" then
			for id, isOwned in owned do
				if type(id) == "string" and isOwned == true and GloveConfig.Exists(id) then
					profile.Gloves.Owned[id] = true
				end
			end
		end
		local equipped = gloves.Equipped
		if type(equipped) == "string" and profile.Gloves.Owned[equipped] then
			profile.Gloves.Equipped = equipped
		end
	end

	local locations = raw.Locations
	if type(locations) == "table" then
		for locationId, progress in locations do
			if type(locationId) == "string" and LevelConfig.Locations[locationId] ~= nil and type(progress) == "table" then
				profile.Locations[locationId] = {
					Tier = readNumber(progress.Tier, 0, 0, 10000, true),
					Rebirths = readNumber(progress.Rebirths, 0, 0, MAX_NUMBER, true),
					BestSpeed = readNumber(progress.BestSpeed, 0, 0, 100000, false),
					BestCombo = readNumber(progress.BestCombo, 0, 0, 100000, true),
				}
			end
		end
	end

	local active = raw.ActiveLocation
	if type(active) == "string" and LevelConfig.Locations[active] ~= nil then
		profile.ActiveLocation = active
	end
	if profile.Locations[profile.ActiveLocation] == nil then
		profile.Locations[profile.ActiveLocation] = newLocation()
	end

	local records = raw.Records
	if type(records) == "table" then
		profile.Records.TopSpeed = readNumber(records.TopSpeed, 0, 0, 100000, false)
		profile.Records.LongestCombo = readNumber(records.LongestCombo, 0, 0, 100000, true)
		profile.Records.WallsSmashed = readNumber(records.WallsSmashed, 0, 0, MAX_NUMBER, true)
		profile.Records.ChestsOpened = readNumber(records.ChestsOpened, 0, 0, MAX_NUMBER, true)
		profile.Records.LootEarned = readNumber(records.LootEarned, 0, 0, MAX_NUMBER, true)
		profile.Records.CapsulesOpened = readNumber(records.CapsulesOpened, 0, 0, MAX_NUMBER, true)
		profile.Records.PinatasPopped = readNumber(records.PinatasPopped, 0, 0, MAX_NUMBER, true)
	end

	-- Бадди: только известные id/мутации, потолок инвентаря, экипировка — существующие уникальные uid
	local buddies = raw.Buddies
	if type(buddies) == "table" then
		local inventory = buddies.Inventory
		local count = 0
		local highest = 0
		if type(inventory) == "table" then
			for uid, entry in inventory do
				if count >= BuddyConfig.MaxInventory then
					break
				end
				if type(uid) == "string" and #uid <= 16 and type(entry) == "table" and type(entry.BuddyId) == "string" then
					local mutation = BuddyConfig.ToMutation(entry.Mutation)
					if BuddyConfig.Get(entry.BuddyId) and mutation then
						profile.Buddies.Inventory[uid] = {
							BuddyId = entry.BuddyId,
							Mutation = mutation,
							Obtained = readNumber(entry.Obtained, nowUnix, 0, MAX_NUMBER, true),
						}
						count += 1
						local numeric = tonumber(string.match(uid, "^b(%d+)$"))
						if numeric and numeric > highest then
							highest = numeric
						end
					end
				end
			end
		end
		local equipped = buddies.Equipped
		if type(equipped) == "table" then
			local seen: { [string]: boolean } = {}
			for _, uid in equipped do
				if type(uid) == "string" and profile.Buddies.Inventory[uid] and not seen[uid] and #profile.Buddies.Equipped < BuddyConfig.MaxEquipped then
					seen[uid] = true
					table.insert(profile.Buddies.Equipped, uid)
				end
			end
		end
		profile.Buddies.NextUid = math.max(readNumber(buddies.NextUid, 1, 1, MAX_NUMBER, true), highest + 1)
	end

	return profile
end

-- Прогресс локации с гарантией существования записи.
function ProfileTemplate.GetLocation(profile: Types.PlayerProfile, locationId: string): Types.LocationProgress
	local progress = profile.Locations[locationId]
	if progress == nil then
		progress = newLocation()
		profile.Locations[locationId] = progress
	end
	return progress
end

-- Экипированные бадди профиля в формате для StretchPhysics.Derive / атрибута EquippedBuddies
function ProfileTemplate.EquippedBuddies(profile: Types.PlayerProfile): { BuddyConfig.EquippedBuddy }
	local result: { BuddyConfig.EquippedBuddy } = {}
	for _, uid in profile.Buddies.Equipped do
		local instance = profile.Buddies.Inventory[uid]
		if instance then
			table.insert(result, { BuddyId = instance.BuddyId, Mutation = instance.Mutation })
		end
	end
	return result
end

function ProfileTemplate.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: any do
		copy[key] = ProfileTemplate.DeepCopy(item)
	end
	return (copy :: any) :: T
end

return ProfileTemplate
