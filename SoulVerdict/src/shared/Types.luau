--!strict
-- Shared type definitions. See docs/SPEC.md for the meaning of every field.
-- This module returns an empty table; it exists only for its exported types.

export type Localized = { en: string, ru: string }

export type Role = "Monster" | "Human"
export type Slot = "M1" | "Q" | "E" | "R" | "T" | "F" | "G" | "Shift"
export type AimMode = "Direction" | "Ground" | "Target" | "Self" | "Ally"
export type ColorRule = "White" | "Blue" | "Orange" | "Red" | "Purple" | "Yellow" | "Green" | "Cyan"

export type AbilityDef = {
	Id: string,
	Slot: Slot,
	Name: Localized,
	Desc: Localized,
	Icon: string, -- name in client UI/Icons.luau
	Cooldown: number,
	Ult: boolean?, -- requires Ult == 100, consumes it
	Hold: { MaxTime: number }?, -- hold-to-charge; client sends Cast on release with charge 0..1
	Range: number?,
	Aim: AimMode,
	Clip: string?, -- animation clip played on the caster at cast start
	Windup: number?, -- seconds before the effect (used for telegraph/prediction timing)
	Tags: { string }?, -- e.g. {"Projectile","KR","Mobility"} (UI badges)
	Numbers: { [string]: number }, -- tunables read by server logic & UI
	Combo: number?, -- for M1: number of hits in the combo
}

export type PassiveDef = {
	Id: string,
	Name: Localized,
	Desc: Localized,
	Icon: string,
}

export type KitStats = {
	MaxHP: number,
	HPPerHuman: number?, -- monsters only
	WalkSpeed: number,
	JumpPower: number,
	MaxDodges: number?, -- monsters only
	MaxGuard: number?, -- humans only
	DashCharges: number?, -- humans only (overrides Config)
	Scale: number?, -- rig scale multiplier
	DoubleJump: boolean?,
}

export type SkinDef = {
	Id: string,
	Name: Localized,
	Price: number, -- 0 = default/free
	Rarity: "Common" | "Rare" | "Epic" | "Legendary",
	Palette: { [string]: Color3 }, -- overrides blueprint palette keys
	Mastery: number?, -- unlocked by kit mastery level instead of gold
}

export type KitDef = {
	Id: string,
	Role: Role,
	Rig: string, -- blueprint id (Rigs/Blueprints)
	Family: "Skeleton" | "Human",
	Name: Localized,
	Title: Localized,
	Lore: Localized,
	Color: Color3, -- signature UI colour (SOUL colour for humans)
	Difficulty: number, -- 1..3
	Playstyle: Localized,
	Stats: KitStats,
	Passives: { PassiveDef },
	Abilities: { AbilityDef },
	VerdictBox: string?, -- monsters: pattern set id in VerdictBox/Patterns.luau
	Unlock: { Gold: number, Level: number? },
	Skins: { SkinDef },
	Order: number, -- sort order in menus
}

export type CastPayload = {
	aim: Vector3,
	dir: Vector3,
	charge: number?,
	target: Model?,
	castId: number,
}

export type AbilityFxPacket = {
	caster: Model,
	kit: string,
	ability: string,
	phase: string,
	castId: number,
	t0: number,
	aim: Vector3?,
	dir: Vector3?,
	charge: number?,
	data: { [string]: any }?,
}

export type HazardPacket = {
	id: number,
	type: string,
	t0: number,
	owner: Model?,
	team: string,
	params: { [string]: any },
}

export type Volume = {
	-- Cylinder: axis = CFrame.UpVector, Size.X = diameter, Size.Y = height.
	-- Ring: annulus like Cylinder (Size.X = outer diameter), Size.Z = band thickness. See Combat/HitTest.luau.
	Shape: "Box" | "Ball" | "Capsule" | "Cylinder" | "Ring",
	CFrame: CFrame,
	Size: Vector3,
	Key: number?, -- sub-element index (e.g. a Rain drop) used by HitPolicy.PerKey
}

export type HazardDef = {
	Duration: (params: { [string]: any }) -> number,
	Volumes: (params: { [string]: any }, t: number) -> { Volume },
	-- PerKey: Once/Interval are tracked per (target, Volume.Key) instead of per target
	HitPolicy: (params: { [string]: any }) -> { Once: boolean, Interval: number?, PerKey: boolean? },
}

export type DamageKind = "Melee" | "Projectile" | "Beam" | "Area" | "True" | "Box"

export type DamageInfo = {
	Attacker: Model?,
	Target: Model,
	Amount: number,
	Kind: DamageKind,
	Ability: string?,
	Color: ColorRule?,
	KR: number?,
	Dodgeable: boolean?,
	Blockable: boolean?,
	Stun: number?,
	Knockback: Vector3?,
	Undodgeable: boolean?,
	Position: Vector3?,
	Silent: boolean?,
	AttackerTeam: string?, -- team of the source when Attacker is nil/gone (hazards); defaults to Attacker's team
}

export type DamageResult = {
	Applied: number,
	Dodged: boolean,
	Blocked: boolean,
	Parried: boolean,
	Killed: boolean,
	Downed: boolean,
	Absorbed: number,
	-- why nothing was applied: "Invalid" | "Team" | "Immune" | "Color" | "Cancelled" (nil = processed)
	Reason: string?,
	KR: number?, -- KR added to the target
	GuardBroken: boolean?,
}

export type DamageFxPacket = {
	target: Model,
	attacker: Model?,
	amount: number,
	kind: string,
	color: string?,
	dodged: boolean?,
	blocked: boolean?,
	parried: boolean?,
	crit: boolean?,
	pos: Vector3,
	kr: number?,
	-- optional extras (DamageService): kind = "Heal" for heals
	ability: string?,
	absorbed: number?,
	killed: boolean?,
	downed: boolean?,
	guardBreak: boolean?,
	negated: string?, -- a kit hook negated the hit (e.g. "Afterimage", "Pirouette")
}

export type MeleeSpec = {
	Offset: CFrame,
	Size: Vector3,
	Damage: number,
	KR: number?,
	Stun: number?,
	Knockback: number?,
	Kind: DamageKind?,
	Dodgeable: boolean?,
	Blockable: boolean?,
	MaxTargets: number?,
	Fx: string?,
	Color: ColorRule?,
	Undodgeable: boolean?,
}

export type ForceMovePacket = {
	kind: "Impulse" | "Pull" | "Lift" | "Slam" | "Dash" | "Teleport" | "Root",
	velocity: Vector3?,
	target: Vector3?,
	duration: number?,
	cframe: CFrame?,
	height: number?,
}

export type BoxPacket = {
	boxId: number,
	victim: Model,
	monster: Model?,
	seed: number,
	patternSet: string,
	duration: number,
	t0: number,
	damagePerHit: number,
	krPerHit: number,
}

-- Animation
export type PoseValue = { number } -- {rx, ry, rz} degrees, optional {.., px, py, pz} studs
export type Pose = { [string]: PoseValue }
export type ClipKey = {
	t: number,
	Ease: string?,
	Dir: string?,
	Pose: Pose,
}
export type Clip = {
	Length: number,
	Loop: boolean?,
	Priority: number?,
	Mask: string?,
	Speed: number?,
	Keys: { ClipKey },
	Events: { { t: number, Name: string } }?,
}

-- Maps
export type MapInfo = {
	Id: string,
	Model: Model, -- the built map (parent nil until placed)
	HumanSpawns: { CFrame },
	MonsterSpawn: CFrame,
	SavePoints: { Vector3 },
	Center: Vector3, -- arena centre (Collapse ring centre)
	Radius: number, -- playable radius (Collapse start radius)
	KillY: number, -- below this Y characters die
	IntroPath: { CFrame }, -- camera keyframes for the intro flyover
	Preset: string, -- default graphics preset id
	FinalPreset: string, -- preset during FinalPhase
	Music: string, -- sound registry key
	DummySpawns: { CFrame }?, -- optional: training-dummy ground CFrames (lobby); spawn CFrames are GROUND points
}

export type MapDef = {
	Id: string,
	Name: Localized,
	Desc: Localized,
	Preset: string,
	FinalPreset: string,
	Music: string,
	Build: (seed: number?) -> MapInfo,
}

-- Graphics
export type GraphicsPreset = {
	Id: string,
	Name: Localized,
	Lighting: { [string]: any }, -- property -> value for Lighting
	Atmosphere: { [string]: any }?,
	Sky: { [string]: any }?,
	Bloom: { [string]: any }?,
	ColorCorrection: { [string]: any }?,
	SunRays: { [string]: any }?,
	DepthOfField: { [string]: any }?,
	ColorGrading: { [string]: any }?,
	Clouds: { [string]: any }?,
	Ambient: { Particles: string?, Density: number? }?, -- ambient weather id
	Desc: Localized?, -- short mood description (Style Lab / settings tooltip)
	GlobalWind: Vector3?, -- Workspace.GlobalWind while this preset is active (clouds, particles)
}

-- Profile (persistent data)
export type QuestState = { Id: string, Progress: number, Goal: number, Claimed: boolean }
export type Profile = {
	Version: number,
	Level: number,
	Exp: number,
	Gold: number,
	Stats: { [string]: number }, -- Rounds, Wins, MonsterWins, HumanWins, Kills, Downs, Damage, Healing, Parries, Dodges, Saves, Revives, BoxesSurvived, MVPs
	Unlocked: { [string]: boolean }, -- kit ids and "kitId:skinId"
	Equipped: { Human: string, Monster: string, Skins: { [string]: string }, Title: string },
	Mastery: { [string]: number }, -- kit id -> mastery exp
	MonsterChance: number,
	RoundsSinceMonster: number,
	RolePreference: "Either" | "Monster" | "Human",
	Quests: { Window: number, List: { QuestState }, Rerolled: boolean },
	Achievements: { [string]: boolean },
	Login: { LastDay: number, Streak: number },
	Settings: { [string]: any },
	Titles: { [string]: boolean },
}

export type ProfileView = Profile -- what the client receives

export type RoundStatRow = {
	userId: number,
	name: string,
	team: string,
	kitId: string,
	damage: number,
	healing: number,
	kills: number,
	downs: number,
	parries: number,
	dodgesForced: number,
	saves: number,
	revives: number,
	survived: boolean,
}

return {}
