--!strict
-- ProfileSchema: the persistent player profile (Types.Profile, SPEC §12) — defaults, versioned migration,
-- sanitising, settings validation, ownership/equip rules and the client view. Pure + Lune-safe.
--
--   ProfileSchema.Version                         current schema version (stored in Profile.Version)
--   ProfileSchema.Default() -> Profile            fresh profile: LV 1, 0 G, free kits (Unlock.Gold == 0) and
--                                                 "kitId:Default" for every kit unlocked, default equips
--   ProfileSchema.Migrate(data) -> (Profile, fresh)   nil / partial / old data -> current schema: version steps,
--                                                 deep reconcile with Default() (missing keys filled, unknown keys
--                                                 kept), then Sanitize. Never mutates `data`.
--   ProfileSchema.Sanitize(profile) -> profile    in place: types, ranges, ownership of equips, mastery rewards,
--                                                 achievement titles, quests, settings overrides
--   ProfileSchema.Settings() -> {[key]: SettingSpec}   whitelist (Config.Defaults + GraphicsQuality,
--                                                 Sensitivity, ColorblindPatterns, ReducedFlashes)
--   ProfileSchema.ValidateSetting(key, value) -> (ok, value', errKey?)   type + range/enum check, numbers rounded
--   ProfileSchema.EffectiveSettings(profile) -> {[key]: any}   defaults merged with the stored overrides
--   ProfileSchema.OwnsKit(profile, kitId) / OwnsSkin(profile, kitId, skinId) -> boolean
--   ProfileSchema.CanEquipKit(profile, kitId) -> (ok, errKey?, role?)
--   ProfileSchema.CanEquipSkin(profile, kitId, skinId) -> (ok, errKey?)
--   ProfileSchema.CanSetTitle(profile, titleId) -> (ok, errKey?)     "" = no title
--   ProfileSchema.CanEquipTrail(profile, trailId) -> (ok, errKey?)   "" = no trail
--   ProfileSchema.ParseRolePref(data) -> string?  "Either" | "Monster" | "Human" (string or {pref})
--   ProfileSchema.View(profile, ctx) -> ProfileView   deep copy + Settings (effective) + ShopToday + Meta
--        ctx = { Now: number (unix), Persistent: boolean? }
--        Meta = { Now, Day, ExpToNext, LevelProgress, MaxLevel, QuestWindowEndsAt, QuestRewards = {{exp, gold}},
--                 ShopEndsAt, FirstWinAvailable, StreakGold (today's), NextStreakGold, MasteryLevels,
--                 Achievements = n, AchievementsTotal = n, Persistent }
-- Stored settings are OVERRIDES only (a value equal to its default is not stored), so changing a default
-- in Config reaches every player who never touched that setting.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Kits = require(script.Parent.Parent.Kits)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local Levels = require(script.Parent.Levels)
local Mastery = require(script.Parent.Mastery)
local Quests = require(script.Parent.Quests)
local Achievements = require(script.Parent.Achievements)
local Titles = require(script.Parent.Titles)
local Shop = require(script.Parent.Shop)
local Rewards = require(script.Parent.Rewards)

type Profile = Types.Profile

export type SettingSpec = {
	Type: string, -- "number" | "boolean" | "enum" | "string"
	Default: any,
	Min: number?,
	Max: number?,
	Values: { string }?,
	Check: ((string) -> boolean)?,
}

local ProfileSchema = {}

ProfileSchema.Version = 1
ProfileSchema.MaxGold = 1e9
ProfileSchema.RolePrefs = { "Either", "Monster", "Human" }
ProfileSchema.StatKeys = {
	"Rounds",
	"Wins",
	"MonsterWins",
	"HumanWins",
	"MonsterRounds",
	"HumanRounds",
	"Kills",
	"Downs",
	"Damage",
	"Healing",
	"Parries",
	"Dodges",
	"Saves",
	"Revives",
	"BoxesSurvived",
	"BoxHits",
	"MVPs",
	"Survived",
	"PracticeRounds",
	"QuestsDone",
	"GoldEarned",
	"ExpEarned",
	"LoginDays",
}

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v < math.huge and v > -math.huge
end

local function int(v: any, default: number, min: number, max: number): number
	if not isNumber(v) then
		return default
	end
	return math.clamp(math.floor(v), min, max)
end

local function round3(v: number): number
	return math.floor(v * 1000 + 0.5) / 1000
end

-- Settings whitelist -----------------------------------------------------------------------------------

-- Optional siblings (validation lists only): a missing or broken module never breaks the profile code.
local function optionalRequire(folder: string, name: string): any
	local ok, result = pcall(function()
		return require((script.Parent.Parent :: any)[folder][name])
	end)
	return if ok then result else nil
end

local Presets = optionalRequire("Graphics", "Presets")
local RigStyles = optionalRequire("Rigs", "RigStyles")

local function rigStyleList(): { string }
	if RigStyles and type(RigStyles.List) == "function" then
		local ok, list = pcall(RigStyles.List)
		if ok and type(list) == "table" and #list > 0 then
			return list
		end
	end
	return { "Classic", "Toon", "Soft", "Glow" }
end

local function presetOk(id: string): boolean
	if id == "MapDefault" then
		return true
	end
	if Presets and type(Presets.Has) == "function" then
		local ok, has = pcall(Presets.Has, id)
		return ok and has == true
	end
	return #id <= 40 and string.match(id, "^[%w_]+$") ~= nil
end

local settingSpecs: { [string]: SettingSpec }? = nil

function ProfileSchema.Settings(): { [string]: SettingSpec }
	if settingSpecs then
		return settingSpecs
	end
	local D = Config.Defaults :: { [string]: any }
	local specs: { [string]: SettingSpec } = {
		GraphicsPreset = { Type = "string", Default = D.GraphicsPreset or "MapDefault", Check = presetOk },
		GraphicsQuality = { Type = "enum", Default = "Auto", Values = { "Auto", "Low", "Medium", "High", "Ultra" } },
		MenuTheme = { Type = "enum", Default = D.MenuTheme or "Classic", Values = { "Classic", "Royal", "Void", "Fell" } },
		HudStyle = { Type = "enum", Default = D.HudStyle or "Battle", Values = { "Battle", "Modern" } },
		RigStyle = { Type = "enum", Default = D.RigStyle or "Toon", Values = rigStyleList() },
		Language = { Type = "enum", Default = D.Language or "auto", Values = { "auto", "en", "ru" } },
		CameraShake = { Type = "number", Default = D.CameraShake or 1, Min = 0, Max = 2 },
		FieldOfView = { Type = "number", Default = D.FieldOfView or 72, Min = 50, Max = 100 },
		MusicVolume = { Type = "number", Default = D.MusicVolume or 0.6, Min = 0, Max = 1 },
		SfxVolume = { Type = "number", Default = D.SfxVolume or 0.8, Min = 0, Max = 1 },
		ParticleDensity = { Type = "number", Default = D.ParticleDensity or 1, Min = 0, Max = 2 },
		Sensitivity = { Type = "number", Default = 1, Min = 0.1, Max = 5 },
		DamageNumbers = { Type = "boolean", Default = if D.DamageNumbers == nil then true else D.DamageNumbers },
		CameraLock = { Type = "boolean", Default = if D.CameraLock == nil then true else D.CameraLock },
		ColorblindPatterns = { Type = "boolean", Default = false },
		ReducedFlashes = { Type = "boolean", Default = false },
	}
	-- any later Config.Defaults addition becomes settable automatically (validated by its default's type)
	for key, default in D do
		if specs[key] == nil then
			if type(default) == "boolean" then
				specs[key] = { Type = "boolean", Default = default }
			elseif type(default) == "number" then
				specs[key] = { Type = "number", Default = default, Min = math.min(0, default), Max = math.max(1, default * 4) }
			elseif type(default) == "string" then
				specs[key] = { Type = "string", Default = default }
			end
		end
	end
	settingSpecs = specs
	return specs
end

function ProfileSchema.ValidateSetting(key: any, value: any): (boolean, any, string?)
	if type(key) ~= "string" or #key > 32 then
		return false, nil, "prog.err.settingKey"
	end
	local spec = ProfileSchema.Settings()[key]
	if spec == nil then
		return false, nil, "prog.err.settingKey"
	end
	if spec.Type == "boolean" then
		if type(value) ~= "boolean" then
			return false, nil, "prog.err.settingValue"
		end
		return true, value, nil
	elseif spec.Type == "number" then
		if not isNumber(value) then
			return false, nil, "prog.err.settingValue"
		end
		local min, max = spec.Min or -1e6, spec.Max or 1e6
		if value < min or value > max then
			return false, nil, "prog.err.settingValue"
		end
		return true, round3(value), nil
	elseif spec.Type == "enum" then
		if type(value) ~= "string" or table.find(spec.Values or {}, value) == nil then
			return false, nil, "prog.err.settingValue"
		end
		return true, value, nil
	else
		if type(value) ~= "string" or #value > 40 or string.match(value, "^[%w_]+$") == nil then
			return false, nil, "prog.err.settingValue"
		end
		if spec.Check and not spec.Check(value) then
			return false, nil, "prog.err.settingValue"
		end
		return true, value, nil
	end
end

function ProfileSchema.EffectiveSettings(profile: any): { [string]: any }
	local out: { [string]: any } = {}
	for key, spec in ProfileSchema.Settings() do
		out[key] = spec.Default
	end
	if type(profile.Settings) == "table" then
		for key, value in profile.Settings do
			if out[key] ~= nil then
				out[key] = value
			end
		end
	end
	return out
end

-- Defaults / migration -----------------------------------------------------------------------------------

function ProfileSchema.Default(): Profile
	local unlocked: { [string]: boolean } = {}
	for _, kit in Kits.All() do
		if kit.Unlock.Gold == 0 then
			unlocked[kit.Id] = true
		end
		unlocked[kit.Id .. ":Default"] = true
	end
	local stats: { [string]: number } = {}
	for _, key in ProfileSchema.StatKeys do
		stats[key] = 0
	end
	local profile = {
		Version = ProfileSchema.Version,
		Level = 1,
		Exp = 0,
		Gold = 0,
		Stats = stats,
		Unlocked = unlocked,
		Equipped = { Human = Kits.DefaultHuman, Monster = Kits.DefaultMonster, Skins = {}, Title = "", Trail = "" },
		Mastery = {},
		MonsterChance = Config.Queue.BaseWeight,
		RoundsSinceMonster = 0,
		RolePreference = "Either",
		Quests = { Window = -1, List = {}, Rerolled = false },
		Achievements = {},
		Login = { LastDay = 0, Streak = 0, Best = 0, FirstWinDay = -1 },
		Settings = {},
		Titles = {},
		Created = 0,
		LastSeen = 0,
	}
	return profile :: any
end

-- Version steps: MIGRATIONS[v] upgrades a profile from version v to v + 1 (in place).
local MIGRATIONS: { [number]: (any) -> () } = {
	[0] = function(p: any)
		-- pre-release data: titles were stored as an array of ids
		if type(p.Titles) == "table" and #p.Titles > 0 then
			local map = {}
			for _, id in p.Titles do
				if type(id) == "string" then
					map[id] = true
				end
			end
			p.Titles = map
		end
	end,
}

function ProfileSchema.Migrate(data: any): (Profile, boolean)
	if type(data) ~= "table" then
		return ProfileSchema.Default(), true
	end
	local profile = TableUtil.deepCopy(data)
	local version = int(profile.Version, 0, 0, 1e6)
	while version < ProfileSchema.Version do
		local step = MIGRATIONS[version]
		if step then
			step(profile)
		end
		version += 1
	end
	-- the inner tables must be tables before reconcile can fill them
	for key, value in ProfileSchema.Default() :: any do
		if type(value) == "table" and type(profile[key]) ~= "table" then
			profile[key] = nil
		end
	end
	TableUtil.reconcile(profile, ProfileSchema.Default() :: any)
	profile.Version = math.max(version, ProfileSchema.Version) -- never downgrade newer data
	ProfileSchema.Sanitize(profile)
	return profile, false
end

-- Ownership rules --------------------------------------------------------------------------------------------

function ProfileSchema.OwnsKit(profile: any, kitId: string): boolean
	local kit = Kits.Get(kitId)
	if kit == nil then
		return false
	end
	return profile.Unlocked[kitId] == true or kit.Unlock.Gold == 0
end

function ProfileSchema.OwnsSkin(profile: any, kitId: string, skinId: string): boolean
	local skin = Kits.Skin(kitId, skinId)
	if skin == nil then
		return false
	end
	if skinId == "Default" or profile.Unlocked[kitId .. ":" .. skinId] == true then
		return true
	end
	if skin.Mastery ~= nil then
		return Mastery.Level(profile.Mastery[kitId] or 0) >= math.min(skin.Mastery, Mastery.MaxLevel)
	end
	return false
end

function ProfileSchema.CanEquipKit(profile: any, kitId: any): (boolean, string?, string?)
	if type(kitId) ~= "string" or Kits.Get(kitId) == nil then
		return false, "prog.err.unknownItem", nil
	end
	local kit = Kits.Get(kitId) :: any
	if not ProfileSchema.OwnsKit(profile, kitId) then
		return false, "prog.err.notOwned", nil
	end
	return true, nil, kit.Role
end

function ProfileSchema.CanEquipSkin(profile: any, kitId: any, skinId: any): (boolean, string?)
	if type(kitId) ~= "string" or type(skinId) ~= "string" or Kits.Skin(kitId, skinId) == nil then
		return false, "prog.err.unknownItem"
	end
	if not ProfileSchema.OwnsSkin(profile, kitId, skinId) then
		return false, "prog.err.notOwned"
	end
	return true, nil
end

function ProfileSchema.CanSetTitle(profile: any, titleId: any): (boolean, string?)
	if titleId == "" then
		return true, nil
	end
	if type(titleId) ~= "string" or not Titles.Has(titleId) then
		return false, "prog.err.unknownItem"
	end
	if profile.Titles[titleId] ~= true then
		return false, "prog.err.notOwned"
	end
	return true, nil
end

function ProfileSchema.CanEquipTrail(profile: any, trailId: any): (boolean, string?)
	if trailId == "" then
		return true, nil
	end
	if type(trailId) ~= "string" or Mastery.Trail(trailId) == nil then
		return false, "prog.err.unknownItem"
	end
	if profile.Unlocked["trail:" .. trailId] ~= true then
		return false, "prog.err.notOwned"
	end
	return true, nil
end

function ProfileSchema.ParseRolePref(data: any): string?
	local pref = data
	if type(data) == "table" then
		pref = data.pref or data.Pref or data.preference
	end
	if type(pref) == "string" and table.find(ProfileSchema.RolePrefs, pref) then
		return pref
	end
	return nil
end

-- Sanitise ------------------------------------------------------------------------------------------------------

local function boolMap(t: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(t) == "table" then
		for key, value in t do
			if type(key) == "string" and value == true and #key <= 64 then
				out[key] = true
			end
		end
	end
	return out
end

function ProfileSchema.Sanitize(profile: any): Profile
	profile.Level, profile.Exp = Levels.Clamp(profile.Level, profile.Exp)
	profile.Gold = int(profile.Gold, 0, 0, ProfileSchema.MaxGold)

	local stats: { [string]: number } = {}
	if type(profile.Stats) == "table" then
		for key, value in profile.Stats do
			if type(key) == "string" and isNumber(value) then
				stats[key] = math.max(0, value)
			end
		end
	end
	for _, key in ProfileSchema.StatKeys do
		stats[key] = stats[key] or 0
	end
	profile.Stats = stats

	profile.Unlocked = boolMap(profile.Unlocked)
	for _, kit in Kits.All() do
		if kit.Unlock.Gold == 0 then
			profile.Unlocked[kit.Id] = true
		end
		profile.Unlocked[kit.Id .. ":Default"] = true
	end
	profile.Titles = boolMap(profile.Titles)
	profile.Achievements = boolMap(profile.Achievements)
	for id in profile.Achievements do
		local def = Achievements.Get(id)
		if def then
			profile.Titles[def.Title] = true
		end
	end

	local mastery: { [string]: number } = {}
	if type(profile.Mastery) == "table" then
		for kitId, exp in profile.Mastery do
			if type(kitId) == "string" and isNumber(exp) and exp > 0 then
				mastery[kitId] = math.min(math.floor(exp), Mastery.MaxKitExp)
			end
		end
	end
	profile.Mastery = mastery
	Mastery.Reconcile(profile)

	local equipped = if type(profile.Equipped) == "table" then profile.Equipped else {}
	local human = Kits.Get(if type(equipped.Human) == "string" then equipped.Human else "")
	if human == nil or human.Role ~= "Human" or not ProfileSchema.OwnsKit(profile, human.Id) then
		equipped.Human = Kits.DefaultHuman
	end
	local monster = Kits.Get(if type(equipped.Monster) == "string" then equipped.Monster else "")
	if monster == nil or monster.Role ~= "Monster" or not ProfileSchema.OwnsKit(profile, monster.Id) then
		equipped.Monster = Kits.DefaultMonster
	end
	local skins: { [string]: string } = {}
	if type(equipped.Skins) == "table" then
		for kitId, skinId in equipped.Skins do
			if
				type(kitId) == "string"
				and type(skinId) == "string"
				and skinId ~= "Default"
				and ProfileSchema.OwnsSkin(profile, kitId, skinId)
			then
				skins[kitId] = skinId
			end
		end
	end
	equipped.Skins = skins
	if not ProfileSchema.CanSetTitle(profile, equipped.Title) then
		equipped.Title = ""
	end
	if not ProfileSchema.CanEquipTrail(profile, equipped.Trail) then
		equipped.Trail = ""
	end
	profile.Equipped = equipped

	profile.MonsterChance = if isNumber(profile.MonsterChance)
		then math.clamp(profile.MonsterChance, 0, 1000)
		else Config.Queue.BaseWeight
	profile.RoundsSinceMonster = int(profile.RoundsSinceMonster, 0, 0, 100000)
	if ProfileSchema.ParseRolePref(profile.RolePreference) == nil then
		profile.RolePreference = "Either"
	end

	local quests = if type(profile.Quests) == "table" then profile.Quests else {}
	quests.Window = int(quests.Window, -1, -1, 1e9)
	quests.List = Quests.SanitizeList(quests.List)
	quests.Rerolled = quests.Rerolled == true
	profile.Quests = quests

	local login = if type(profile.Login) == "table" then profile.Login else {}
	login.LastDay = int(login.LastDay, 0, 0, 1e7)
	login.Streak = int(login.Streak, 0, 0, 100000)
	login.Best = math.max(int(login.Best, 0, 0, 100000), login.Streak)
	login.FirstWinDay = int(login.FirstWinDay, -1, -1, 1e7)
	profile.Login = login

	local settings: { [string]: any } = {}
	local specs = ProfileSchema.Settings()
	if type(profile.Settings) == "table" then
		for key, value in profile.Settings do
			local ok, clean = ProfileSchema.ValidateSetting(key, value)
			if ok and clean ~= specs[key].Default then
				settings[key] = clean
			end
		end
	end
	profile.Settings = settings

	profile.Created = int(profile.Created, 0, 0, 1e12)
	profile.LastSeen = int(profile.LastSeen, 0, 0, 1e12)
	return profile
end

-- View -------------------------------------------------------------------------------------------------------------

function ProfileSchema.View(profile: any, ctx: { [string]: any }?): any
	local c = ctx or {}
	local now: number = if isNumber(c.Now) then c.Now else 0
	local view = TableUtil.deepCopy(profile)
	view.Settings = ProfileSchema.EffectiveSettings(profile)
	local day = Shop.Day(now)
	view.ShopToday = TableUtil.deepCopy(Shop.Daily(day))
	local questRewards = {}
	for i, state in profile.Quests.List do
		local exp, gold = Quests.RewardFor(state)
		questRewards[i] = { exp = exp, gold = gold }
	end
	local achieved = 0
	for _ in profile.Achievements do
		achieved += 1
	end
	local atMax = profile.Level >= Levels.MaxLevel
	view.Meta = {
		Now = now,
		Day = day,
		ExpToNext = if atMax then 0 else Levels.ExpToNext(profile.Level),
		LevelProgress = Levels.Progress(profile.Level, profile.Exp),
		MaxLevel = Levels.MaxLevel,
		QuestWindowEndsAt = Quests.WindowEndsAt(profile.Quests.Window),
		QuestRewards = questRewards,
		QuestRerollAvailable = not profile.Quests.Rerolled,
		ShopEndsAt = Shop.DayEndsAt(day),
		FirstWinAvailable = Rewards.FirstWinAvailable(profile, day),
		StreakGold = Rewards.StreakGold(math.max(1, profile.Login.Streak)),
		NextStreakGold = Rewards.StreakGold(profile.Login.Streak + 1),
		MasteryLevels = Mastery.LevelsOf(profile),
		Achievements = achieved,
		AchievementsTotal = Achievements.Count(),
		Persistent = c.Persistent ~= false,
	}
	return view
end

return ProfileSchema
