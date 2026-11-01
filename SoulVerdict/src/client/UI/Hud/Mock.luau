--!strict
-- Hud/Mock: the HUD snapshot contract + mock scenarios for offline previews (tools/lune/dump_gui.luau) and
-- tests. Lune-safe. Every HUD piece renders from a Snapshot (built live by Hud/Data.luau at ~10 Hz).
--
--   Mock.Scenario(name?) -> Snapshot      names: Mock.Names (default "HumanRound")
--   Mock.Unit(kitId, name, opts?) -> Unit  fills MaxHP/MaxGuard/MaxDodges from kit data
--
-- Snapshot = {
--   Now, Phase, EndsAt, Practice, Role ("Lobby"|"Human"|"Monster"|"Spectator"), Device ("KeyboardMouse"|"Gamepad"|"Touch"),
--   MapId, VoteOptions {string}, Votes {[mapId]=n}, MyVote?, Chances {{Name, UserId, Chance (0..1), Pref, IsLocal, Pity?}},
--   PlayerCount, MinPlayers,
--   Me: Unit?, Monster: Unit?, Humans {Unit}, Spectating: Unit?,
--   Saves {{Index, Progress (0..1), Lit, Contested, Channelers, Position: Vector3?, Distance?, Screen: Vector2? (preview)}},
--   SavesLit, SavesTotal, HumansAlive, HumansTotal, TeamRevives, Harmony (multiplier), FinalPhase,
--   Collapse: {Radius, Center?, Distance, Outside}?,
--   Cooldowns {[abilityId]=endsAt}, Charge {Id, Value}?, Combo (current hit 0..n), Ammo {Count, Max, ReloadEndsAt}?,
--   Studious (local human sees monster cooldowns), Dead (local SOUL shattered), DeathAt?, Killer?,
--   -- preview-only payloads (live: pushed through events): Feed {FeedEntry}, Announcement {Kind, Title?, Line?, Color?},
--   Intro {MapId, Monster: Unit, Humans {Unit}, Count}, Chosen {Name, KitId, IsLocal}, Toasts {{Text, Kind, Icon}}
-- }
-- Unit = { Name, UserId, KitId, Team, Level, Title, IsLocal, IsBot, HP, MaxHP, KR, Shield, Guard, MaxGuard, Dash,
--   DashMax, DashNext (0..1), Dodges, MaxDodges, ExhaustedUntil, Ult, Downed, DownedEndsAt, Dead, Blocking, Invisible,
--   FinalForm, SoulMode, Statuses {[name]=endsAt}, Cooldowns {[abilityId]=endsAt}?, Model: Model? }
-- FeedEntry = { Kind ("Kill"|"Downed"|"Revived"|"Save"|"Surge"|"SecondWind"|"Left"|"Info"), A?, AColor?, B?, BColor?,
--   Icon?, Text?, Time }
local Style = require(script.Parent.Style)

local Mock = {}

export type Unit = { [string]: any }
export type Snapshot = { [string]: any }

Mock.Names = {
	"HumanRound",
	"MonsterRound",
	"MonsterExhausted",
	"Final",
	"Downed",
	"Dead",
	"Spectate",
	"Intro",
	"Lobby",
	"LobbyWaiting",
	"LobbyChosen",
	"Perseverance",
	"Justice",
	"Touch",
	"TouchMonster",
}

local NOW = 1000

function Mock.Unit(kitId: string, name: string, opts: { [string]: any }?): Unit
	local kit = Style.Kit(kitId)
	local stats = if kit then kit.Stats else {}
	local monster = kit ~= nil and kit.Role == "Monster"
	local config = Style.Config()
	local maxHp = if monster then (stats.MaxHP or 900) + (stats.HPPerHuman or 300) * 4 else (stats.MaxHP or 100)
	local u: Unit = {
		Name = name,
		UserId = 1000 + #name,
		KitId = kitId,
		Team = if monster then "Monster" else "Humans",
		Level = 7,
		Title = "",
		IsLocal = false,
		IsBot = false,
		HP = maxHp,
		MaxHP = maxHp,
		KR = 0,
		Shield = 0,
		Guard = stats.MaxGuard or 100,
		MaxGuard = stats.MaxGuard or 100,
		Dash = stats.DashCharges or (if config then config.Human.DashCharges else 2),
		DashMax = stats.DashCharges or (if config then config.Human.DashCharges else 2),
		DashNext = 0,
		Dodges = stats.MaxDodges or 6,
		MaxDodges = stats.MaxDodges or 6,
		ExhaustedUntil = 0,
		Ult = 0,
		Downed = false,
		DownedEndsAt = 0,
		Dead = false,
		Blocking = false,
		Invisible = false,
		FinalForm = false,
		SoulMode = "Red",
		Statuses = {},
	}
	if opts then
		for k, v in opts do
			u[k] = v
		end
	end
	return u
end

local function team(): { Unit }
	return {
		Mock.Unit("Determination", "NovaHeart", {
			IsLocal = true,
			Level = 12,
			Title = "Star Lighter",
			HP = 72,
			KR = 14,
			Guard = 64,
			Dash = 1,
			DashNext = 0.55,
			Ult = 87,
			Statuses = { Slowed = NOW + 2.4, DamageUp = NOW + 5.1 },
		}),
		Mock.Unit("Kindness", "kindcookie", { Level = 8, Title = "Kind Soul", HP = 118, Ult = 40 }),
		Mock.Unit(
			"Patience",
			"Ghostly_Owl",
			{ Level = 15, Title = "Night Owl", HP = 0, Downed = true, DownedEndsAt = NOW + 9.2 }
		),
		Mock.Unit("Bravery", "BraveBrick", { Level = 5, Title = "Bone Dodger", HP = 41, KR = 22, IsBot = true }),
	}
end

local function monster(opts: { [string]: any }?): Unit
	local m = Mock.Unit("ClassicSans", "SansMain_77", { Level = 21, Title = "Lazy Judge" })
	m.HP = math.floor(m.MaxHP * 0.68)
	m.Dodges = 5
	m.Ult = 40
	m.Cooldowns = {
		GasterBlaster = NOW + 5.2,
		BlueSoul = NOW + 0.0,
		BoneZone = NOW + 7.4,
		BoneWall = NOW + 2.1,
		Shortcut = NOW + 0,
		VerdictBox = NOW + 22,
	}
	if opts then
		for k, v in opts do
			m[k] = v
		end
	end
	return m
end

local function feed(): { { [string]: any } }
	local det = Style.KitColor("Determination")
	local kind = Style.KitColor("Kindness")
	local pat = Style.KitColor("Patience")
	local sans = Style.KitColor("ClassicSans")
	return {
		{ Kind = "Save", A = "kindcookie", AColor = kind, B = "1", Icon = "Star", Time = NOW - 21 },
		{
			Kind = "Kill",
			A = "SansMain_77",
			AColor = sans,
			B = "LittleFern",
			BColor = Style.KitColor("Integrity"),
			Icon = "Blaster",
			Time = NOW - 12,
		},
		{
			Kind = "Revived",
			A = "NovaHeart",
			AColor = det,
			B = "BraveBrick",
			BColor = Style.KitColor("Bravery"),
			Icon = "Heart",
			Time = NOW - 6,
		},
		{
			Kind = "Downed",
			A = "SansMain_77",
			AColor = sans,
			B = "Ghostly_Owl",
			BColor = pat,
			Icon = "BoneZone",
			Time = NOW - 2,
		},
	}
end

local function saves(): { { [string]: any } }
	return {
		{
			Index = 1,
			Progress = 1,
			Lit = true,
			Contested = false,
			Channelers = 0,
			Distance = 38,
			Screen = Vector2.new(0.27, 0.42),
		},
		{
			Index = 2,
			Progress = 0.62,
			Lit = false,
			Contested = false,
			Channelers = 2,
			Distance = 14,
			Screen = Vector2.new(0.64, 0.5),
		},
		{
			Index = 3,
			Progress = 0.18,
			Lit = false,
			Contested = true,
			Channelers = 1,
			Distance = 71,
			Screen = Vector2.new(1.3, 0.62),
		},
	}
end

local function base(): Snapshot
	local humans = team()
	return {
		Now = NOW,
		Phase = "Round",
		EndsAt = NOW + 204,
		Practice = false,
		Role = "Human",
		Device = "KeyboardMouse",
		MapId = "HallOfVerdicts",
		VoteOptions = {},
		Votes = {},
		Chances = {},
		PlayerCount = 5,
		MinPlayers = 2,
		Me = humans[1],
		Monster = monster(),
		Humans = humans,
		Saves = saves(),
		SavesLit = 1,
		SavesTotal = 3,
		HumansAlive = 3,
		HumansTotal = 4,
		TeamRevives = 2,
		Harmony = 1.12,
		FinalPhase = false,
		Collapse = nil,
		Cooldowns = { KnifeCombo = NOW + 0.12, LungingStrike = NOW + 4.2, Afterimage = NOW + 0 },
		Charge = nil,
		Combo = 2,
		Ammo = nil,
		Studious = false,
		Dead = false,
		Feed = feed(),
		Toasts = { { Text = "Quest complete: Parry 5 bones. +40 G", Kind = "Reward", Icon = "Gold" } },
	}
end

local function chances(): { { [string]: any } }
	return {
		{ Name = "Ghostly_Owl", UserId = 3, Chance = 0.31, Pref = "Monster", IsLocal = false, Pity = true },
		{ Name = "NovaHeart", UserId = 1, Chance = 0.22, Pref = "Either", IsLocal = true },
		{ Name = "kindcookie", UserId = 2, Chance = 0.17, Pref = "Either", IsLocal = false },
		{ Name = "SansMain_77", UserId = 5, Chance = 0.12, Pref = "Monster", IsLocal = false },
		{ Name = "BraveBrick", UserId = 4, Chance = 0.10, Pref = "Either", IsLocal = false },
		{ Name = "LittleFern", UserId = 6, Chance = 0.08, Pref = "Human", IsLocal = false },
	}
end

local BUILDERS: { [string]: () -> Snapshot } = {}

BUILDERS.HumanRound = base

BUILDERS.MonsterRound = function()
	local s = base()
	local m = monster({ IsLocal = true, Dodges = 3, Ult = 100, Statuses = { Rage = NOW + 6.5 } })
	s.Role = "Monster"
	s.Me = m
	s.Monster = m
	s.Humans[1].IsLocal = false
	s.Cooldowns = m.Cooldowns
	s.Charge = { Id = "GasterBlaster", Value = 0.65 }
	s.Combo = 3
	s.Toasts = { { Text = "Ghostly_Owl is down! Finish them.", Kind = "Info", Icon = "Skull" } }
	return s
end

BUILDERS.MonsterExhausted = function()
	local s = BUILDERS.MonsterRound()
	s.Me.Dodges = 0
	s.Me.ExhaustedUntil = NOW + 3.2
	s.Me.Statuses = { Exhausted = NOW + 3.2 }
	s.Announcement = { Kind = "Exhausted" }
	return s
end

BUILDERS.Final = function()
	local s = base()
	s.Phase = "Collapse"
	s.EndsAt = NOW + 23
	s.FinalPhase = true
	s.Monster.HP = math.floor(s.Monster.MaxHP * 0.22)
	s.Monster.FinalForm = true
	s.Monster.Dodges = s.Monster.MaxDodges
	s.SavesLit = 3
	for _, save in s.Saves do
		save.Lit = true
		save.Progress = 1
	end
	s.Collapse = { Radius = 31, Distance = 36, Outside = true }
	s.Me.Statuses = { Surge = NOW + 12, SecondWind = NOW + 8.5 }
	s.Me.HP = 64
	s.Announcement = { Kind = "FinalPhase" }
	return s
end

BUILDERS.Downed = function()
	local s = base()
	s.Me.HP = 0
	s.Me.KR = 0
	s.Me.Downed = true
	s.Me.DownedEndsAt = NOW + 8.4
	s.Me.Statuses = {}
	s.TeamRevives = 1
	return s
end

BUILDERS.Dead = function()
	local s = base()
	s.Me.HP = 0
	s.Me.Dead = true
	s.Dead = true
	s.DeathAt = NOW - 0.5
	s.Killer = "SansMain_77"
	s.Role = "Spectator"
	return s
end

BUILDERS.Spectate = function()
	local s = base()
	s.Me.HP = 0
	s.Me.Dead = true
	s.Role = "Spectator"
	s.Spectating = s.Humans[2]
	s.Feed = {}
	s.Toasts = {}
	return s
end

BUILDERS.Intro = function()
	local s = base()
	s.Phase = "Intro"
	s.EndsAt = NOW + 3
	for _, h in s.Humans do
		h.HP = h.MaxHP
		h.KR = 0
		h.Downed = false
	end
	s.Intro = { MapId = "HallOfVerdicts", Monster = s.Monster, Humans = s.Humans, Count = 3 }
	s.Feed = {}
	s.Toasts = {}
	return s
end

BUILDERS.Lobby = function()
	local s = base()
	s.Phase = "Intermission"
	s.EndsAt = NOW + 18
	s.Role = "Lobby"
	s.VoteOptions = { "HallOfVerdicts", "SnowdinCrossroads", "VoidRift" }
	s.Votes = { HallOfVerdicts = 3, SnowdinCrossroads = 1, VoidRift = 1 }
	s.MyVote = "HallOfVerdicts"
	s.Chances = chances()
	s.Me = nil
	s.Monster = nil
	s.Feed = {}
	s.Toasts = { { Text = "Daily login: day 3 streak! +30 G", Kind = "Reward", Icon = "Gold" } }
	return s
end

BUILDERS.LobbyWaiting = function()
	local s = BUILDERS.Lobby()
	s.Phase = "Waiting"
	s.EndsAt = 0
	s.PlayerCount = 1
	s.VoteOptions = {}
	s.Votes = {}
	s.MyVote = nil
	s.Chances = { { Name = "NovaHeart", UserId = 1, Chance = 1, Pref = "Either", IsLocal = true } }
	s.Toasts = {}
	return s
end

BUILDERS.LobbyChosen = function()
	local s = BUILDERS.Lobby()
	s.EndsAt = NOW + 1
	s.Chosen = { Name = "Ghostly_Owl", KitId = "FellSans", IsLocal = false }
	s.Toasts = {}
	return s
end

BUILDERS.Perseverance = function()
	local s = base()
	local me = Mock.Unit(
		"Perseverance",
		"NovaHeart",
		{ IsLocal = true, Level = 12, Title = "Star Lighter", HP = 88, Ult = 100, Guard = 100, Dash = 2 }
	)
	s.Me = me
	s.Humans[1] = me
	s.Studious = true
	s.Cooldowns = { NotebookSwat = NOW, SpellboundPages = NOW + 6.6, Rewrite = NOW + 11.3 }
	s.Combo = 1
	return s
end

BUILDERS.Justice = function()
	local s = base()
	local me = Mock.Unit(
		"Justice",
		"NovaHeart",
		{ IsLocal = true, Level = 12, HP = 101, Ult = 55, Shield = 25, Statuses = { Shielded = NOW + 4 } }
	)
	s.Me = me
	s.Humans[1] = me
	s.Cooldowns = { FanTheHammer = NOW + 3.4 }
	s.Ammo = { Count = 4, Max = 6, ReloadEndsAt = 0 }
	s.Combo = 0
	return s
end

BUILDERS.Touch = function()
	local s = base()
	s.Device = "Touch"
	s.Feed = { s.Feed[3], s.Feed[4] }
	s.Toasts = {}
	return s
end

BUILDERS.TouchMonster = function()
	local s = BUILDERS.MonsterRound()
	s.Device = "Touch"
	s.Feed = { s.Feed[4] }
	s.Toasts = {}
	return s
end

function Mock.Scenario(name: string?): Snapshot
	local builder = BUILDERS[name or "HumanRound"] or BUILDERS.HumanRound
	return builder()
end

function Mock.Has(name: string): boolean
	return BUILDERS[name] ~= nil
end

return Mock
