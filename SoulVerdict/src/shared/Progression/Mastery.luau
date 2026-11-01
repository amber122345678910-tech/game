--!strict
-- Mastery: per-kit mastery tracks (SPEC §1.6, genre idea 16). Pure + Lune-safe. Purely cosmetic rewards.
-- Kit EXP (the round EXP earned while playing that kit) -> mastery level 1..MasteryMaxLevel
-- (level = 1 + floor(exp / MasteryExpPerLevel)). Reward ladder, identical for every kit:
--   M2 +100 G   M3 title   M4 "Soul" trail   M5 +250 G   M6 title   M7 +400 G   M8 "Prism" trail
--   M9 +600 G   M10 title + every SkinDef with Mastery <= 10 (the legendary Mastery skins, e.g.
--   ClassicSans:Monochrome, EclipseSans:Aurora, Determination:Crimson). A skin with Mastery = N unlocks at MN.
-- Ids: titles "m_<KitId>_<level>" (text "prog.title.m_<KitId>_<level>"), trails "<KitId>:Soul" / "<KitId>:Prism"
-- (profile.Unlocked["trail:<trailId>"], text "prog.trail.Soul" / "prog.trail.Prism"), skins "kitId:skinId".
--
--   Mastery.Level(exp) -> number                 Mastery.ExpForLevel(level) -> number (exp at which it starts)
--   Mastery.Progress(exp) -> (level, into, need)  into/need inside the current level (need = 0 at max)
--   Mastery.TitleId(kitId, level) -> string      Mastery.TrailId(kitId, kind) -> string
--   Mastery.Trails() -> {[trailId]: TrailDef}    Mastery.Trail(trailId) -> TrailDef?
--   Mastery.RewardsAt(kitId, level) -> {Reward}  Mastery.RewardsBetween(kitId, fromLv, toLv) -> {Reward}
--   Mastery.Grant(profile, reward) -> boolean    true if newly granted (gold always "new")
--   Mastery.Apply(profile, kitId, amount) -> MasteryResult   adds kit EXP and grants every crossed reward
--   Mastery.Reconcile(profile) -> number          re-grants missing non-gold rewards of the current levels
--   Mastery.LevelsOf(profile) -> {[kitId]: level}
-- Reward = { Kind = "Gold"|"Title"|"Trail"|"Skin", Id = string?, Amount = number?, Level = number }
-- MasteryResult = { KitId, From, To, Exp, Rewards = {Reward} }

local Config = require(script.Parent.Parent.Config)
local Kits = require(script.Parent.Parent.Kits)

export type Reward = { Kind: string, Id: string?, Amount: number?, Level: number }
export type TrailDef = { Id: string, KitId: string, Kind: string, Level: number, Colors: { Color3 } }
export type MasteryResult = { KitId: string, From: number, To: number, Exp: number, Rewards: { Reward } }

local Mastery = {}

Mastery.MaxLevel = Config.Progression.MasteryMaxLevel :: number
Mastery.ExpPerLevel = Config.Progression.MasteryExpPerLevel :: number
Mastery.TitleLevels = { 3, 6, 10 }
Mastery.GoldLevels = { [2] = 100, [5] = 250, [7] = 400, [9] = 600 } :: { [number]: number }
Mastery.TrailLevels = { Soul = 4, Prism = 8 } :: { [string]: number }
Mastery.MaxKitExp = 1e7 -- sanity cap for stored kit EXP

-- Second colour of each kit's "Prism" trail (first colour = the kit's signature colour).
local PRISM: { [string]: Color3 } = {
	ClassicSans = Color3.fromRGB(90, 190, 255),
	FellSans = Color3.fromRGB(255, 190, 60),
	EclipseSans = Color3.fromRGB(255, 200, 90),
	Determination = Color3.fromRGB(255, 220, 110),
	Patience = Color3.fromRGB(200, 255, 255),
	Bravery = Color3.fromRGB(255, 230, 130),
	Integrity = Color3.fromRGB(210, 140, 255),
	Perseverance = Color3.fromRGB(255, 130, 220),
	Kindness = Color3.fromRGB(230, 255, 150),
	Justice = Color3.fromRGB(255, 150, 70),
}

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v < math.huge and v > -math.huge
end

function Mastery.Level(exp: number): number
	if not isNumber(exp) or exp <= 0 then
		return 1
	end
	return math.clamp(1 + math.floor(exp / Mastery.ExpPerLevel), 1, Mastery.MaxLevel)
end

function Mastery.ExpForLevel(level: number): number
	return (math.clamp(math.floor(level), 1, Mastery.MaxLevel) - 1) * Mastery.ExpPerLevel
end

function Mastery.Progress(exp: number): (number, number, number)
	local level = Mastery.Level(exp)
	if level >= Mastery.MaxLevel then
		return level, 0, 0
	end
	local e = if isNumber(exp) then math.max(0, exp) else 0
	return level, e - Mastery.ExpForLevel(level), Mastery.ExpPerLevel
end

function Mastery.TitleId(kitId: string, level: number): string
	return ("m_%s_%d"):format(kitId, level)
end

function Mastery.TrailId(kitId: string, kind: string): string
	return kitId .. ":" .. kind
end

local trails: { [string]: TrailDef }? = nil

function Mastery.Trails(): { [string]: TrailDef }
	if trails then
		return trails
	end
	local built: { [string]: TrailDef } = {}
	for _, kit in Kits.All() do
		local base: Color3 = kit.Color
		local soulId = Mastery.TrailId(kit.Id, "Soul")
		built[soulId] = {
			Id = soulId,
			KitId = kit.Id,
			Kind = "Soul",
			Level = Mastery.TrailLevels.Soul,
			Colors = { base, lerpColor(base, Color3.new(1, 1, 1), 0.6) },
		}
		local prismId = Mastery.TrailId(kit.Id, "Prism")
		built[prismId] = {
			Id = prismId,
			KitId = kit.Id,
			Kind = "Prism",
			Level = Mastery.TrailLevels.Prism,
			Colors = { base, PRISM[kit.Id] or Color3.new(1, 1, 1) },
		}
	end
	trails = built
	return built
end

function Mastery.Trail(trailId: string): TrailDef?
	return Mastery.Trails()[trailId]
end

function Mastery.RewardsAt(kitId: string, level: number): { Reward }
	local out: { Reward } = {}
	local kit = Kits.Get(kitId)
	if kit == nil or level < 2 or level > Mastery.MaxLevel then
		return out
	end
	local gold = Mastery.GoldLevels[level]
	if gold then
		table.insert(out, { Kind = "Gold", Amount = gold, Level = level })
	end
	if table.find(Mastery.TitleLevels, level) then
		table.insert(out, { Kind = "Title", Id = Mastery.TitleId(kitId, level), Level = level })
	end
	for kind, lv in Mastery.TrailLevels do
		if lv == level then
			table.insert(out, { Kind = "Trail", Id = Mastery.TrailId(kitId, kind), Level = level })
		end
	end
	for _, skin in kit.Skins do
		local need = skin.Mastery
		if need ~= nil and math.clamp(need, 2, Mastery.MaxLevel) == level then
			table.insert(out, { Kind = "Skin", Id = kitId .. ":" .. skin.Id, Level = level })
		end
	end
	return out
end

function Mastery.RewardsBetween(kitId: string, fromLevel: number, toLevel: number): { Reward }
	local out: { Reward } = {}
	for level = math.max(2, fromLevel + 1), math.min(toLevel, Mastery.MaxLevel) do
		for _, reward in Mastery.RewardsAt(kitId, level) do
			table.insert(out, reward)
		end
	end
	return out
end

-- Applies one reward to the profile. Returns true when something new was granted.
function Mastery.Grant(profile: any, reward: Reward): boolean
	if reward.Kind == "Gold" then
		profile.Gold = (profile.Gold or 0) + (reward.Amount or 0)
		return true
	end
	local id = reward.Id
	if id == nil then
		return false
	end
	if reward.Kind == "Title" then
		if profile.Titles[id] then
			return false
		end
		profile.Titles[id] = true
		return true
	elseif reward.Kind == "Trail" then
		local key = "trail:" .. id
		if profile.Unlocked[key] then
			return false
		end
		profile.Unlocked[key] = true
		return true
	elseif reward.Kind == "Skin" then
		if profile.Unlocked[id] then
			return false
		end
		profile.Unlocked[id] = true
		return true
	end
	return false
end

function Mastery.Apply(profile: any, kitId: string, amount: number): MasteryResult
	local before = profile.Mastery[kitId]
	local exp = if isNumber(before) then math.max(0, before) else 0
	local fromLevel = Mastery.Level(exp)
	local result: MasteryResult = { KitId = kitId, From = fromLevel, To = fromLevel, Exp = exp, Rewards = {} }
	if Kits.Get(kitId) == nil or not isNumber(amount) or amount <= 0 then
		return result
	end
	exp = math.min(Mastery.MaxKitExp, exp + math.floor(amount))
	profile.Mastery[kitId] = exp
	local toLevel = Mastery.Level(exp)
	result.To = toLevel
	result.Exp = exp
	for _, reward in Mastery.RewardsBetween(kitId, fromLevel, toLevel) do
		if Mastery.Grant(profile, reward) then
			table.insert(result.Rewards, reward)
		end
	end
	return result
end

-- Makes sure every cosmetic reward of the current mastery levels is present (never grants gold).
function Mastery.Reconcile(profile: any): number
	local granted = 0
	for kitId, exp in profile.Mastery do
		if type(kitId) == "string" and Kits.Get(kitId) then
			for _, reward in Mastery.RewardsBetween(kitId, 1, Mastery.Level(exp)) do
				if reward.Kind ~= "Gold" and Mastery.Grant(profile, reward) then
					granted += 1
				end
			end
		end
	end
	return granted
end

function Mastery.LevelsOf(profile: any): { [string]: number }
	local out: { [string]: number } = {}
	for _, kit in Kits.All() do
		out[kit.Id] = Mastery.Level(profile.Mastery and profile.Mastery[kit.Id] or 0)
	end
	return out
end

return Mastery
