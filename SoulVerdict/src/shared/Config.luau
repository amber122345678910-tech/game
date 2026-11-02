--!strict
-- All gameplay tunables. Numbers only — no logic. Lune-safe.
-- Kit-specific numbers live in Shared/Kits/** (AbilityDef.Numbers / KitDef.Stats).

local Config = {}

Config.GameName = "SOUL VERDICT"
Config.Version = "0.1.0"

Config.Round = {
	MinPlayers = 2,
	IntermissionTime = 25,
	VoteOptions = 3,
	IntroTime = 7,
	RoundTime = 240,
	CollapseTime = 40,
	CollapseMinRadius = 14,
	CollapseDamagePerSecond = 9,
	EndingTime = 10,
	FinalPhaseHpFraction = 0.30,
	FinalPhaseInvulnerable = 1.2,
	MaxPlayers = 12,
	LateJoinSpectate = true,
}

Config.Monster = {
	DodgeRegenDelay = 3.0, -- seconds without dodging before regen starts
	DodgeRegenInterval = 2.0, -- seconds per dodge regenerated
	ExhaustTime = 5.0,
	ExhaustDamageMult = 1.15,
	FinalPhaseDodgeRegenMult = 1.5,
	MinDodges = 2, -- SAVE points cannot reduce MaxDodges below this
}

Config.Human = {
	DashCharges = 2,
	DashRecharge = 2.8, -- seconds per charge
	DashDistance = 16,
	DashTime = 0.2,
	DashIFrames = 0.15,
	BlockReduction = 0.7, -- 70 % of frontal damage blocked
	BlockAngleDot = 0.15, -- attacker must be in front (dot > this)
	ParryWindow = 0.2,
	ParryStun = 1.2,
	ParryGuardGain = 15,
	ParryUltGain = 8,
	MaxGuard = 100,
	GuardRegenPerSecond = 18,
	GuardRegenDelay = 1.2,
	GuardBreakStun = 1.6,
	BlockWalkSpeedMult = 0.55,
	DownedTime = 15,
	DownedWalkSpeed = 4,
	ReviveHoldTime = 2.5,
	ReviveHealthFraction = 0.35,
	TeamRevives = 3,
	SecondWindDuration = 12,
	SecondWindSpeedMult = 1.4,
	SecondWindDamageMult = 1.25,
	SecondWindHealFraction = 0.35,
	HarmonyPerClass = 0.04,
	HarmonyMax = 0.20,
	-- horizontal decay exponent k of "Impulse" ForceMoves: MovementController holds the horizontal speed at
	-- v0 x (1 - t / T)^k and the Bravery / Integrity leaps solve their launch speed with the same k
	LeapArcFactor = 1.6,
}

Config.KR = {
	Max = 40,
	DrainBase = 2.5, -- HP per second at KR 1
	DrainPerStack = 0.3, -- extra HP per second per KR stack
	CleanseOnHit = 3, -- KR removed from a human when they land a hit
	MinHealth = 1, -- KR can never drop HP below this
}

Config.Ult = {
	HumanPerDamage = 0.30, -- per point of damage dealt
	HumanPerHeal = 0.40,
	HumanPerSecond = 0.20,
	HumanPerSave = 20,
	HumanOnHitTaken = 0.10, -- per point of damage taken
	MonsterPerDamage = 0.22,
	MonsterPerSecond = 0.30,
}

Config.Combat = {
	MoveThreshold = 2.0, -- studs/s: above = "moving" for Blue/Orange rules
	HazardForgiveness = 0.85, -- scale of hazard volumes vs visuals (favour the dodger)
	MeleeLeniency = 1.0, -- extra studs added to melee boxes (favour the attacker)
	CharacterRadius = 1.1,
	CharacterHeight = 5.0,
	MaxAimRange = 160,
	AimSlack = 10,
	CastRateLimit = 0.08, -- min seconds between Cast requests
	ComboResetTime = 0.9,
	HitStopMelee = 0.06,
	HitStopHeavy = 0.12,
	FriendlyFire = false,
	StunWalkSpeed = 0,
}

Config.Objectives = {
	SavesPerMap = 3,
	SaveRadius = 7,
	SaveChannelTime = 5,
	SaveExtraPlayerSpeed = 0.5, -- each extra human channels +50 % faster
	SaveHeal = 25,
	SaveUlt = 20,
	SurgeDuration = 20,
	SurgeDamageMult = 1.15,
	SurgeUlt = 50,
}

Config.VerdictBox = {
	Cooldown = 40,
	Range = 28,
	ConeDot = 0.82, -- ~35 degrees
	Duration = 7,
	DamagePerHit = 5,
	KRPerHit = 3,
	MinHitInterval = 0.45,
	SurviveMaxHits = 1,
	SurviveDamageMult = 1.2,
	SurviveBuffTime = 6,
	SurviveUlt = 25,
	Height = 9, -- studs above the victim for the 3D box
	MonsterUltPerHit = 4,
	-- s from the box opening (server) to its timeline start t0 = open + IntroTime: the victim's entry transition
	-- (UI/VerdictBoxEntry: pull-in, black, flash) plays first; the fight still lasts Duration (BoxEnd at t0 + Duration)
	IntroTime = 0.8,
}

Config.Rewards = {
	Participation = { Exp = 30, Gold = 20 },
	Win = { Exp = 60, Gold = 40 },
	PerDamage = { Exp = 0.04, Gold = 0.02 },
	PerHealing = { Exp = 0.05, Gold = 0.03 },
	Kill = { Exp = 12, Gold = 10 },
	Save = { Exp = 10, Gold = 8 },
	Revive = { Exp = 10, Gold = 8 },
	Parry = { Exp = 2, Gold = 1 },
	MVP = { Exp = 25, Gold = 25 },
	PracticeMult = 0.25, -- practice rounds give reduced rewards
	FirstWinOfDay = { Exp = 100, Gold = 75 },
}

Config.Progression = {
	ExpBase = 100,
	ExpPerLevel = 60,
	MaxLevel = 200,
	MasteryExpPerLevel = 400,
	MasteryMaxLevel = 10,
	LevelUpGold = 15,
}

Config.Queue = {
	BaseWeight = 1,
	WeightPerRound = 1,
	ActiveBonusDamage = 200, -- extra +1 weight if dealt this much damage as human
	PityRounds = 6,
	MonsterPreferenceMult = 1.5,
}

Config.Quests = {
	PerWindow = 3,
	WindowHours = 12,
}

Config.Shop = {
	DailySkins = 4,
}

Config.Data = {
	StoreName = "SoulVerdict_Profiles_v1",
	KeyPrefix = "u_",
	AutosaveInterval = 120,
	SessionLockTimeout = 600,
	MaxRetries = 5,
	WinsBoard = "SV_Wins_v1",
	LevelBoard = "SV_Level_v1",
}

Config.Practice = {
	Enabled = true,
	BotHumans = 3,
	BotThinkRate = 0.15,
}

Config.StyleLab = {
	Enabled = true,
	AllowEveryone = false, -- true = every player can open Style Lab (testing builds only)
}

Config.Defaults = {
	GraphicsPreset = "MapDefault",
	MenuTheme = "Classic",
	HudStyle = "Battle",
	RigStyle = "Soft",
	Language = "auto",
	CameraShake = 1,
	FieldOfView = 72,
	MusicVolume = 0.6,
	SfxVolume = 0.8,
	ParticleDensity = 1,
	DamageNumbers = true,
	CameraLock = true,
	QuickCast = true, -- aimed abilities fire on press; false = hold to aim (indicator), release to cast
	InvertY = false, -- camera pitch inverted
}

Config.CollisionGroups = {
	Characters = "SV_Characters",
	Visual = "SV_Visual",
	Hazard = "SV_Hazard",
}

Config.Camera = {
	Distance = 11,
	MinDistance = 4,
	MaxDistance = 22,
	ShoulderOffset = Vector3.new(1.8, 1.6, 0),
	Sensitivity = 0.0035,
	TouchSensitivity = 0.006,
	GamepadSensitivity = 3.2,
	PitchMin = -70,
	PitchMax = 65,
	FollowStiffness = 28,
}

-- Emotes (EmoteService validates against these; Hud/EmoteWheel shows them). Clip names from Shared/Anim/Clips.
Config.Emote = {
	Cooldown = 1.2, -- seconds between accepted emote requests per player
	MaxLoopTime = 30, -- looping clips (Wave, Sit, Laugh, Cheer) end on their own after this long
	MoveSpeed = 2.5, -- studs/s of horizontal movement that cancels the emote
	Common = { "Emote_Wave", "Emote_Shrug", "Emote_Sit", "Emote_Laugh", "Taunt", "Victory" },
	Family = { Skeleton = { "Wink" } }, -- extras per RigFamily
}

-- Admin panel (server AdminService, client Screens/Admin): EXTRA admins by Roblox UserId. Studio, the place owner
-- (or the group owner, rank 255) and the private-server owner are always admins without being listed here.
-- Find a UserId in the profile link roblox.com/users/<UserId>/profile, e.g. Config.Admins = { 123456789, 987654321 }
Config.Admins = {} :: { number }

return Config
