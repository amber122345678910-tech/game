# UNDERTALE: SOUL VERDICT — Technical & Design Specification (v0.1)

This document is the single source of truth for every contributor (human or agent).
If code and this spec disagree, fix one of them in the same change and say so.

Working title: **UNDERTALE: SOUL VERDICT** (an original, non-commercial Undertale-AU fan game).
Genre: asymmetric 1-vs-N battle (1 Monster = a Sans AU, N Humans = fallen children with SOUL traits).
It is NOT a copy of any existing Roblox game: kits, maps, UI, systems and numbers are original.
Only Undertale's own mechanic language is reused (SOUL colours, KR, blue/orange rules, battle box).
No Robux monetisation of any kind. No ripped sprites/music.

---------------------------------------------------------------------------------------------------
## 0. Hard constraints (read first)

1. **Everything is code.** We cannot upload assets (meshes, textures, images, animations, sounds).
   Visuals are built from Parts (Block/Ball/Cylinder/Wedge/CornerWedge), `SpecialMesh` (Sphere/Head/
   Cylinder/Wedge/Brick), Neon + Bloom, `Highlight`, lights, `ParticleEmitter`/`Beam`/`Trail` with
   built-in textures only, `Atmosphere`, post-effects, GUI objects (Frame/TextLabel/UIStroke/
   UIGradient/UICorner/CanvasGroup/Path2D).
2. **Animations are procedural**: client code writes `Motor6D.Transform` every frame from data-defined
   keyframe clips (see §8). No `Animation` assets, no `Animator`, no `Humanoid:LoadAnimation`.
3. **Lighting**: `Lighting.Technology` is deprecated & not scriptable. `Lighting.LightingStyle` (Realistic) and
   `Lighting.PrioritizeLightingQuality` (true) are set in the place file (default.project.json); game scripts can
   READ them but cannot WRITE them (capability PluginOrOpenCloud). Graphics presets never touch them.
4. **Offline verifiability**: shared "builder" modules (rigs, props, maps, graphics presets, UI
   themes, kit data, hazard geometry, animation clips) MUST be runnable under **Lune** (no engine
   services). Rules for those modules:
   - require other modules only via `require(script.Parent.X)` / `require(script.Parent.Parent.X.Y)`
     (relative `script` paths). Never `game:GetService(...)` at module top level.
   - only use datatypes Lune provides: `Instance.new`, `CFrame`, `Vector3`, `Vector2`, `Color3`,
     `BrickColor`, `UDim`, `UDim2`, `Enum`, `NumberSequence(Keypoint)`, `ColorSequence(Keypoint)`,
     `NumberRange`, `Rect`, `Font`, `PhysicalProperties`, `math`, `string`, `table`, `task` (no-op ok).
   - no `workspace`, `game`, `RunService`, `TweenService` etc. inside builder functions. If a builder
     needs randomness use `Random.new(seed)` — NOTE: Lune lacks `Random`; use the shared
     `Util/Rng.luau` (deterministic LCG) instead.
5. **Style**: Luau, `--!strict` first line in every file, tabs for indentation, no deprecated APIs
   (`wait/spawn/delay` → `task.*`; no `BodyVelocity/BodyGyro/BodyPosition` → `LinearVelocity`,
   `AlignOrientation`, `AlignPosition`; no `Humanoid:LoadAnimation`; no `FindPartOnRay` → `workspace:Raycast`;
   no `RenderStepped` → `RunService.PreRender`/`BindToRenderStep`; no `Instance.new(class, parent)` 2-arg form;
   no `TweenPosition/TweenSize` → `TweenService`). Set `Parent` LAST after configuring instances.
6. **All user-facing text** goes through `Shared/Strings.luau` (English + Russian), see §13.

---------------------------------------------------------------------------------------------------
## 1. Game design summary

### 1.1 Round flow (server `RoundService`)
```
Waiting (≥2 players needed; solo player may start PRACTICE vs bots)
  → Intermission (25 s): map vote (3 random maps), loadout changes, monster pick at the end
  → Intro (7 s): map built, players spawned & frozen, cinematic flyover + VS splash
  → Round (240 s): fight
       Phase 2 (code: FinalPhase) when the monster casts its FIRST ultimate of the round; if its HP reaches
       ≤ 30 % first, Phase 2 starts by itself (own music, new visuals, faster dodge regen; see §1.2)
       Collapse (overtime 40 s) when timer hits 0 and both sides alive: a closing ring of void
  → Ending (10 s): kill-cam/slow-mo on last hit (client), results + rewards
  → back to Intermission
```
Win conditions:
- **Monster** wins when no human is alive (downed humans who bleed out count as dead).
- **Humans** win when Monster HP reaches 0, OR when Collapse ends with ≥1 human alive ("SURVIVED").
- Monster leaves → Humans win (no penalty to anyone). All humans leave → Monster wins.

### 1.2 Monster core (all Sans kits)
- **HP** = `Kit.Stats.MaxHP + Kit.Stats.HPPerHuman * humansAtStart`.
- **Dodges** (visible meter, `Dodges`/`MaxDodges` attributes): while `Dodges ≥ 1` every *dodgeable*
  incoming hit is negated ("MISS"), consumes 1 dodge, monster plays a lazy side-step.
  Regen: +1 dodge every `Config.Monster.DodgeRegenInterval` s after `DodgeRegenDelay` s without dodging.
  When dodges reach 0 → **EXHAUSTED** for `Config.Monster.ExhaustTime` s (no regen, takes
  `ExhaustDamageMult` damage, sweat VFX), then dodges refill to `MaxDodges`.
  Not dodgeable: hits while Stunned/Exhausted, ultimates, `Undodgeable` hits (e.g. Determination ult).
- **KR (Karma)**: monster hits add KR to humans (`KR` attribute, cap 40). KR drains HP over time,
  faster with more KR, **cannot reduce HP below 1**. Landing a hit removes `Config.KR.CleanseOnHit` KR
  from the attacker (rewards aggression).
- **Ultimate** meter `Ult` 0..100: +damage dealt, +time. Ult ability needs 100. The first ultimate of a
  round also starts Phase 2 (below); later ones are normal ultimates.
- **Verdict Box** (slot F, every monster): pulls one human's SOUL into a 2D Undertale-style bullet-hell
  box for ~7 s (see §11). Signature feature of the game.
- **Phase 2** (player-facing name; in code `FinalPhase` / `TriggerFinalPhase` / `FinalForm` / `Theme_<kit>_Final`),
  once per round, Round/Collapse only. Started by the monster's FIRST ultimate: AbilityService calls
  `RoundService.TriggerFinalPhase("Ult", caster)` while the cast commits (after validation, before the bar is
  spent); the ultimate itself still runs as the transformation's opening move and the bar stays spent.
  Safety net (unchanged): if HP reaches ≤30 % before any ultimate, it starts by itself (`"Hp"`, ult set to 100);
  until Phase 2 the monster cannot drop below 1 HP. Admin / Style Lab may force it (ult set to 100).
  Effects: 1.2 s invulnerable transformation (blocks hits only, never moving or casting), eye blazes, dodges
  refilled, Exhausted cleared, dodge regen ×`Config.Monster.FinalPhaseDodgeRegenMult`, music switch to
  `Theme_<kit>_Final`, map lighting switches to the map's `FinalPreset`.

### 1.3 Human core (all SOUL classes)
- HP per class 95–150. **Guard** meter for blocking (`Guard`/`MaxGuard`).
- **Dash** (Shift): `Config.Human.DashCharges` charges, i-frames `DashIFrames`.
- **Block/Parry** (hold F): frontal hits reduced by `BlockReduction`; the first `ParryWindow` s of a
  block is a **perfect parry**: negates the hit, stuns melee attackers `ParryStun` s, +Guard, +Ult.
  Guard ≤ 0 → Guard Break stun.
- **Ultimate** (R) meter: +damage, +healing, +SAVE points, +time.
- **Downed**: at 0 HP a human is *Downed* (crawls, SOUL cracked) for `Config.Human.DownedTime` s.
  Allies revive with a `ProximityPrompt` hold (`ReviveHoldTime`), using the team revive budget
  (`Config.Human.TeamRevives` per round). Any monster damage on a downed human kills them.
- **Second Wind**: when exactly one human remains alive (not downed) for the first time: +40 % move
  speed, +25 % damage, heal 35 % for 12 s.
- **Harmony**: +4 % team damage for every distinct SOUL class in the team beyond the first (cap +20 %).

### 1.4 Objectives — SAVE points
Each map defines 3 SAVE stars. A human channels by standing within `SaveRadius` for `SaveChannelTime`
(more humans = faster, contested if monster within radius → pause). When lit: all humans heal
`SaveHeal`, +`SaveUlt` ult, monster `MaxDodges` −1 for the rest of the round.
All 3 lit → **DETERMINATION SURGE** (`SurgeDuration` s): humans +15 % damage, ult +50, monster
becomes Exhausted immediately.

### 1.5 Fair monster queue (QueueService)
Each player has `MonsterChance` (weight, starts 1). Each round played as human: +1 (+1 extra if they
were MVP-less participant who dealt ≥ 200 damage). Chosen by weighted random among players whose
`RolePreference` ≠ "Human". Pity: anyone with `RoundsSinceMonster ≥ Config.Queue.PityRounds` is chosen
first. Chosen player resets to 1. Everybody's % is shown in the lobby HUD.
Role preference: "Either" | "Monster" (weight ×1.5) | "Human" (never chosen unless nobody else).

### 1.6 Progression (all free)
- **EXP/LV**: `ExpToNext(lv) = 100 + 60*(lv-1)`. **G** (gold) currency.
- Kits unlocked with G (some free). Skins (palette variants) bought with G; a **daily shop** offers
  4 rotating skins (deterministic per UTC day). Titles from achievements and **kit mastery**
  (kit EXP → mastery levels 1–10, cosmetic rewards: titles, trail colours).
- **Quests**: 3 quests per 12-hour window (deterministic from user id + window index), rerollable once.
- **Achievements**, **leaderboards** (Wins, LV) on lobby boards, **daily login streak** (soft decay).
- Round recap card: damage, dodges forced, parries, saves, revives, MVP.

### 1.7 Kits (v0.1 roster)
Monsters: `ClassicSans` (The Judge, control), `FellSans` (The Executioner, aggression),
`EclipseSans` (The Void Wanderer — original AU, traps/portals).
Humans (one per SOUL): `Determination` (red, knife DPS), `Patience` (cyan, stealth),
`Bravery` (orange, bruiser), `Integrity` (blue, mobility), `Perseverance` (purple, control/utility),
`Kindness` (green, healer), `Justice` (yellow, ranged).
Full ability lists live in `src/shared/Kits/**` (data) — that data is authoritative for UI and logic.

### 1.8 Controls
| Action | KB/M | Gamepad | Touch |
|---|---|---|---|
| Basic attack | M1 | R2 | button |
| Ability Q/E/R/T | Q/E/R/T | X / Y / B / DPadUp | buttons |
| Monster Verdict Box / Human Block | F | L1 (hold) | button |
| Monster Ultimate | G | L2+R2 | button |
| Human Ultimate | R | L2+R2 | button |
| Dash / Mobility | Shift | ButtonB? (see InputController) | button |
| Camera lock toggle | Ctrl / Alt | R3 | — |
| Emote wheel | B | DPadDown | button in menu |
| Menu | M / Tab | Start | top button |
Slots in data: `"M1" | "Q" | "E" | "R" | "T" | "F" | "G" | "Shift"`.
Humans use M1,Q,E,R(ult),F(block — built-in, not in kit data),Shift(dash — built-in).
Monsters use M1,Q,E,R,T,F(Verdict Box — built-in per kit pattern set),G(ult),Shift(kit mobility ability).

---------------------------------------------------------------------------------------------------
## 2. Project layout (Rojo 7, `default.project.json`)

```
SoulVerdict/
  default.project.json          Rojo tree (services + properties)
  README.md                     Russian user guide (how to open/test/publish)
  docs/SPEC.md                  this file
  src/shared/   -> ReplicatedStorage.Shared       (ModuleScripts, runnable in Lune where noted)
  src/server/   -> ServerScriptService.Server     (Main.server.luau + Services/ + Kits/)
  src/client/   -> StarterPlayer.StarterPlayerScripts.Client (Main.client.luau + Controllers/ + UI/ + Kits/ + VFX/)
  tools/        Lune harness, tests, checks, preview renderer (not shipped)
  previews/     generated PNG renders (committed, shown to the owner)
  SoulVerdict.rbxl  built place (committed)
```
File naming: `X.server.luau` → Script, `X.client.luau` → LocalScript, other `.luau` → ModuleScript,
`init.luau` makes the folder itself a ModuleScript. Folder names = instance names.

### 2.1 Shared module map (ReplicatedStorage.Shared)
```
Config.luau            all tunables (numbers only, no logic)                         [Lune-safe]
Types.luau             exported Luau types used across the codebase                 [Lune-safe]
Net.luau               remote names + thin wrappers (server/client)                 [NOT Lune-safe; lazy services]
Strings.luau           localisation table + L(key, ...) formatter                   [Lune-safe]
Util/Signal.luau, Trove.luau, Spring.luau, MathUtil.luau, TableUtil.luau, Rng.luau, Geometry.luau [Lune-safe]
Kits/init.luau         registry: Kits.Get(id), Kits.All(), Kits.ForRole(role)       [Lune-safe]
Kits/Monsters/*.luau, Kits/Humans/*.luau   kit data (see §6)                         [Lune-safe]
Combat/HazardDefs.luau deterministic hazard geometry (server hit tests + client visuals) [Lune-safe]
Combat/Teams.luau      team helpers (pure, take Models)                              [Lune-safe]
Rigs/PartKit.luau      primitive builders                                            [Lune-safe]
Rigs/RigBuilder.luau   builds a character Model from a blueprint                     [Lune-safe]
Rigs/Skeletons.luau    base skeleton definitions per family                          [Lune-safe]
Rigs/Blueprints/*.luau ClassicSans, FellSans, EclipseSans, HumanBase + 7 SOUL outfits, Dummy [Lune-safe]
Rigs/Props/*.luau      Bone, GasterBlaster(styles), Soul (heart), Weapons, SaveStar, VerdictBox3D [Lune-safe]
Rigs/RigStyles.luau    character style variants (Toon/Classic/Soft/Glow)             [Lune-safe]
Rigs/Skins.luau        palette variants per kit                                      [Lune-safe]
Anim/Joints.luau       joint names, families, masks                                  [Lune-safe]
Anim/Clips/Skeleton.luau, Anim/Clips/Human.luau, Anim/Clips/Kits/*.luau              [Lune-safe]
Maps/MapKit.luau       map building helpers                                          [Lune-safe]
Maps/Registry.luau     list of maps + metadata                                       [Lune-safe]
Maps/*.luau            HallOfVerdicts, SnowdinCrossroads, WaterfallGrotto, VoidRift, CoreReactor, Lobby [Lune-safe]
Graphics/Presets.luau  lighting/post presets                                         [Lune-safe]
Graphics/Apply.luau    apply a preset to a Lighting instance (+ children)            [Lune-safe]
Progression/Levels.luau, Quests.luau, Achievements.luau, Shop.luau, Mastery.luau     [Lune-safe]
VerdictBox/Patterns.luau  2D bullet patterns per monster style                        [Lune-safe]
```

---------------------------------------------------------------------------------------------------
## 3. Coordinate & unit conventions
- Studs. Y up. Forward = −Z (`CFrame.LookVector`). Right = +X.
- `CFrame.Angles(rx, ry, rz)` = Rx·Ry·Rz (radians). Positive X rotation swings a hanging limb
  **forward** (and tilts a head **back/up**). Positive Z rotation raises the **right** arm sideways
  (for the left arm, raising sideways is **negative** Z). Positive Y turns **left**.
- `Part.Shape = Cylinder` has its axis along the part's **X** axis (`Size.X` = length).
- Ellipsoids: a Block `Part` with a child `SpecialMesh` (`MeshType = Sphere`) fills the part size.
- Server time: `workspace:GetServerTimeNow()` on both server and client. All `t0`/`EndsAt`
  values in packets/attributes are server time.

---------------------------------------------------------------------------------------------------
## 4. Networking (`Shared/Net.luau`)

Remotes live in `ReplicatedStorage.Remotes` (Folder) and are created by the server at startup
(`Net.Server.Init()`); clients use `Net.Client.*` which `WaitForChild`s lazily.

```lua
-- RemoteEvents (reliable)
"Cast"          C→S  (abilityId: string, payload: CastPayload)
"Block"         C→S  (isBlocking: boolean)
"Dash"          C→S  (direction: Vector3)
"Request"       C→S  (action: string, data: any)        -- menus: EquipKit, Buy, Vote, SetRolePref, ClaimQuest, RerollQuest, SetSetting, StartPractice, StyleLab, Emote, Ready
"BoxReport"     C→S  (boxId: number, hits: number, finished: boolean)   -- Verdict Box victim reports
"AbilityFx"     S→C  (packet: AbilityFxPacket)
"Hazard"        S→C  (packet: HazardPacket)
"HazardEnd"     S→C  (hazardId: number)
"DamageFx"      S→C  (packet: DamageFxPacket)
"ForceMove"     S→C  (packet: ForceMovePacket)          -- only to the target character's owner
"Cooldown"      S→C  (abilityId: string, endsAt: number) -- only to caster
"RoundEvent"    S→C  (name: string, data: any)          -- see §4.2
"Notify"        S→C  (key: string, args: {any}?, style: string?)
"Profile"       S→C  (profile: ProfileView)              -- full replace of the client's profile view
"BoxStart"      S→C  (packet: BoxPacket)                 -- to all; victim plays, others watch
"BoxEnd"        S→C  (boxId: number, result: {hits: number, survived: boolean, reason: string?})  -- reason: Duration|MonsterGone|VictimGone|Cancelled
-- RemoteFunctions
"GetProfile"    C→S  () -> ProfileView
-- UnreliableRemoteEvents (≤ 900 bytes, may drop)
"Aim"           C→S (aimPoint: Vector3) / S→C (character: Model, aimPoint: Vector3) at ≤ 10 Hz
"BoxSoul"       C→S (boxId: number, x: number, y: number) / S→C (boxId, x, y, hits) at ≤ 15 Hz  -- box px (VerdictBox/Sim), hits = accepted so far
```
API:
```lua
Net.Server.Init()                                   -- creates remotes (call once, first thing)
Net.Server.On(name, fn(player, ...))                -- OnServerEvent; payloads MUST be type-checked by handler
Net.Server.OnInvoke(name, fn(player, ...) -> ...)
Net.Server.Fire(name, player, ...) ; Net.Server.FireAll(name, ...) ; Net.Server.FireExcept(name, player, ...)
Net.Server.FireList(name, players: {Player}, ...)
Net.Client.On(name, fn(...)) ; Net.Client.Fire(name, ...) ; Net.Client.Invoke(name, ...) -> ...
```

### 4.1 Replicated state via attributes
`ReplicatedStorage.RoundState` (Configuration, created by server) attributes:
| attribute | type | meaning |
|---|---|---|
| Phase | string | "Waiting" "Intermission" "Intro" "Round" "Collapse" "Ending" |
| PhaseEndsAt | number | server time |
| MapId | string | current/next map |
| VoteOptions | string | comma-separated 3 map ids during intermission |
| MonsterUserId | number | 0 if none / bot |
| MonsterKit | string | kit id |
| HumansAlive, HumansTotal | number | |
| SavesLit, SavesTotal | number | |
| FinalPhase | boolean | the monster's Phase 2 is on (§1.2) |
| Winner | string | "", "Monster", "Humans" |
| WinReason | string | "Defeated", "Survived", "Eliminated", "Left" |
| Practice | boolean | practice round with bots |
| TeamRevives | number | remaining revives |
| GraphicsPreset | string | map default preset id (clients may override locally) |
| CollapseRadius | number | current safe radius during Collapse (0 otherwise) |
| CollapseCenter | Vector3 | |

**Player** attributes: `Level`, `Exp`, `Gold`, `MonsterChance` (0..1 share for display),
`RolePreference`, `EquippedHuman`, `EquippedMonster`, `Title`, `Role` ("Lobby"|"Human"|"Monster"|"Spectator").

**Character Model** attributes (set by server on spawn, updated live):
| attribute | type | notes |
|---|---|---|
| KitId | string | |
| Team | string | "Humans" / "Monster" / "Lobby" |
| RigFamily | string | "Skeleton" / "Human" |
| SkinId | string | |
| IsBot | boolean | |
| OwnerUserId | number | 0 for bots |
| KR | number | humans |
| Dodges, MaxDodges | number | monster |
| Exhausted | number | server time when exhaustion ends (0 = not) |
| Guard, MaxGuard | number | humans |
| DashCharges | number | humans |
| Ult | number | 0..100 |
| Blocking | boolean | |
| Downed | boolean | |
| Dead | boolean | |
| SoulMode | string | "Red" (normal) / "Blue" (heavy gravity) / "Boxed" (in Verdict Box) |
| Status_<Name> | number | server time when status ends (see §7.4); absent/0 = inactive |
| Buff_DamageMult | number | current multiplier (computed by StatusService) |
| Invisible | boolean | stealth (Patience) |
| FinalForm | boolean | monster Phase 2 visuals |
HP uses `Humanoid.Health/MaxHealth` (server-authoritative; replicated by engine).

### 4.2 RoundEvent names
`"PhaseChanged" {phase, endsAt}`, `"MapVote" {options, votes}`, `"MonsterChosen" {userId, kitId, name}`,
`"Intro" {mapId, monster, humans: {{userId, kitId, name}}}`, `"Kill" {victim, killer, ability, victimName, killerName}`,
`"Downed" {victim}`, `"Revived" {victim, by}`, `"SaveLit" {index, by}`, `"Surge" {}`,
`"FinalPhase" {monster, kitId, duration, cause: "Ult"|"Hp"|"Forced"}` (the monster's Phase 2),
`"SecondWind" {userId}`, `"Collapse" {}`, `"RoundEnd" {winner, reason, stats: {RoundStatRow}, mvpUserId, lastHit: {victim: Model?, position: Vector3?}}`,
`"Rewards" {exp, gold, levelUp: boolean, unlocked: {string}, questProgress}`.

---------------------------------------------------------------------------------------------------
## 5. Characters & rigs

### 5.1 Rig contract (built by `Rigs/RigBuilder.luau`)
A character is a `Model` with `PrimaryPart = HumanoidRootPart` and these **physics parts**
(R15 naming; Transparency 1; Massless false; CanQuery true; CanTouch true):
`HumanoidRootPart` (CanCollide false, Size 2×2×1),
`LowerTorso`, `UpperTorso`, `Head` (CanCollide true), and limbs
`LeftUpperArm, LeftLowerArm, LeftHand, RightUpperArm, RightLowerArm, RightHand,
 LeftUpperLeg, LeftLowerLeg, LeftFoot, RightUpperLeg, RightLowerLeg, RightFoot` (CanCollide false).

**Motor6Ds** (parented to Part1, `Name` exactly as below, C0/C1 rotation = identity so Transform
rotations are in world-aligned axes in rest pose):
| Motor6D | Part0 → Part1 |
|---|---|
| Root | HumanoidRootPart → LowerTorso |
| Waist | LowerTorso → UpperTorso |
| Neck | UpperTorso → Head |
| LeftShoulder / RightShoulder | UpperTorso → Left/RightUpperArm |
| LeftElbow / RightElbow | UpperArm → LowerArm |
| LeftWrist / RightWrist | LowerArm → Hand |
| LeftHip / RightHip | LowerTorso → Left/RightUpperLeg |
| LeftKnee / RightKnee | UpperLeg → LowerLeg |
| LeftAnkle / RightAnkle | LowerLeg → Foot |

**Visual parts** are children of the limb they follow, attached with `WeldConstraint`
(Part0 = limb, Part1 = visual), and have `Massless=true, CanCollide=false, CanQuery=false,
CanTouch=false, Anchored=false`. Every visual part has attribute `Role` ∈
`"Skin" "Bone" "Cloth" "ClothAlt" "Trim" "Accent" "Eye" "Glow" "Hair" "Metal" "Weapon" "Detail" "Dark"`
— used by `RigStyles` and skins. Tiny details set `CastShadow=false`.

**Named Attachments** (VFX anchor points):
| Attachment | on part | purpose |
|---|---|---|
| RootAttachment | HumanoidRootPart | standard |
| LeftEye, RightEye | Head | eye glow / flames (Sans: pupils) |
| Mouth | Head | |
| HeadTop | Head | above-head UI |
| Chest | UpperTorso | SOUL heart position |
| Back | UpperTorso | |
| LeftGrip, RightGrip | Left/RightHand | weapons, casting |
| LeftFootAttachment, RightFootAttachment | feet | dust/trails |

Sans rigs additionally have visual parts named `LeftPupil`, `RightPupil` (white Neon, Role "Eye")
under `Head`. Weapons are a `Model` named `Weapon` welded to `RightGrip`'s parent (RightHand).

**Humanoid**: `RigType = R15`, `HipHeight` computed so the feet touch the ground,
`AutomaticScalingEnabled = false`, `BreakJointsOnDeath = false`, `RequiresNeck = false`,
`DisplayDistanceType = None`, `HealthDisplayType = AlwaysOff`, `UseJumpPower = true`.
No `Animator`, no `Animate`/`Health` scripts.

Model attributes set by RigBuilder: `RigFamily`, `BlueprintId`, `RigScale`, `SkinId`.

### 5.2 Builder API
```lua
RigBuilder.Build(blueprintId: string, opts: { Skin: string?, Name: string?, Style: string? }?) -> Model
  -- built at rest pose with HumanoidRootPart at CFrame.new(0, hrpHeight, 0) facing -Z. Parent = nil.
RigBuilder.GetJointNames() -> {string}
RigBuilder.Blueprints() -> {string}
PartKit.* -- see Rigs/PartKit.luau header (Ellipsoid, Ball, Box, Cyl, CylBetween, Wedge, CornerWedge,
           -- Bone, Ring, OnEllipsoid, Weld, Attach, Light)
```
Blueprint module shape:
```lua
return {
  Id = "ClassicSans", Family = "Skeleton", Scale = 1.0,
  Skeleton = "Skeleton" | "Human",           -- base from Rigs/Skeletons.luau (optional overrides below)
  Overrides = { [limbName] = { Size = Vector3?, Joint = Vector3? } }?,
  Palette = { [key] = Color3 },               -- default palette; Skins.luau may override keys
  Build = function(rig: RigContext) end,      -- add visual parts (rig.Limb(name), rig.Palette, rig.Add(...))
}
```

### 5.3 Props (`Rigs/Props/*`)
```lua
Bone.Build(length: number, thickness: number, color: Color3, material: Enum.Material?) -> Model  -- axis along local Y, PrimaryPart "Shaft", Anchored true
GasterBlaster.Build(style: "Classic"|"Fell"|"Eclipse", scale: number?) -> Model
  -- PrimaryPart "Core" (Anchored), facing -Z; child Model "Jaw" pivoting on Attachment "JawHinge" in Core;
  -- Attachment "Muzzle" in Core at mouth; parts with Role "Eye" for glow; total ≤ 90 parts
Soul.Build(color: Color3, size: number?) -> Model   -- 3D heart, Neon, PrimaryPart "Core", faces -Z
Soul.BuildBroken(color, size) -> Model              -- two halves for shatter VFX ("LeftHalf","RightHalf")
Weapons.Build(id: string, palette?) -> Model        -- "RealKnife","ToyKnife","ToughGlove","BalletShoes","Notebook","BurntPan","EmptyGun","BoneSword"
SaveStar.Build() -> Model                           -- glowing SAVE star (PrimaryPart "Star"), Anchored
VerdictBox3D.Build() -> Model                       -- 3D floating battle box (black faces + white edges), Part "Screen" with SurfaceGui-ready face (Front)
```

### 5.4 Rig styles & skins
`RigStyles.Apply(model: Model, styleId: string)` client-side only; styles: `"Classic"` (SmoothPlastic),
`"Toon"` (Classic + black outline `Highlight`, FillTransparency 1), `"Soft"` (Fabric clothes),
`"Glow"` (stronger neon accents, eye lights). `Skins.Get(kitId, skinId) -> {palette overrides, name}`.

---------------------------------------------------------------------------------------------------
## 6. Kit data (`Shared/Kits/**`) — authoritative ability roster
Types in `Types.luau` (`KitDef`, `AbilityDef`). Each kit file returns a `KitDef`.
`Numbers` tables hold tunables used by server logic AND shown in UI tooltips (`{Damage=..}`).
Server logic must read numbers from the kit data, not hard-code them.

---------------------------------------------------------------------------------------------------
## 7. Combat (server-authoritative)

### 7.1 Services (src/server/Services)
```
AbilityService   receives "Cast", validates, runs kit handlers, cooldowns, FX broadcast; also CastAs(model,...) for bots
DamageService    the only place that changes Humanoid.Health; dodge/block/parry/KR/downed/kill
StatusService    timed statuses + derived stats (WalkSpeed/JumpPower/damage mults) + KR/dodge/guard/ult regen ticks
HazardService    spawns hazards, samples HazardDefs every Heartbeat, applies hits, broadcasts packets
MovementService  ForceMove routing (to owner client or server-applied for bots), teleports, dashes
```
Service module shape (server and client controllers alike):
```lua
local X = {}
function X.Init() end   -- no yields, no cross-service calls except storing references
function X.Start() end  -- connect events, start loops
return X
```
`Main.server.luau` requires every module in `Services/`, calls all `Init()` then all `Start()`
(order given by a list in Main). Same for `Main.client.luau` with `Controllers/`.

### 7.2 Ability execution
1. Client `CombatController` reads input → checks local cooldown/state → plays predicted animation
   (`AnimController.Play`) and kit `Predict` (optional) → `Net.Client.Fire("Cast", abilityId, payload)`.
   `CastPayload = { aim: Vector3, dir: Vector3, charge: number?, target: Model?, castId: number }`.
2. Server `AbilityService` validates: caster alive, not Downed/Boxed/Stunned/Silenced, ability exists in
   caster's kit, cooldown ready, ult ≥ 100 if `Ult`, `charge ∈ [0,1]`, `aim` within `Range+10` of caster
   (clamp), rate-limit. Then sets cooldown (fires "Cooldown" to caster), increments Ult cost, broadcasts
   `AbilityFx {phase="Start"}` to all, and runs `ServerKits[kitId].Abilities[abilityId](ctx)` in `task.spawn` + pcall.
   A Monster-team ultimate during Round/Collapse while `RoundState.FinalPhase` is false first calls
   `RoundService.TriggerFinalPhase("Ult", caster)` (before the bar is set to 0; the Start packet then carries
   `data.phase2 = true`): the monster's first ultimate opens its Phase 2 (§1.2). Players and bots share this path.
3. Kit server logic calls `ctx` helpers (below) which handle damage, hazards and FX broadcasts.

### 7.3 CastContext (server, passed to kit handlers)
```lua
ctx.Caster: Model ; ctx.Player: Player? ; ctx.Root: BasePart ; ctx.Humanoid: Humanoid
ctx.Kit: KitDef ; ctx.Ability: AbilityDef ; ctx.N: {[string]: number} (= Ability.Numbers)
ctx.CastId: number ; ctx.Aim: Vector3 (clamped) ; ctx.AimDir: Vector3 (unit) ; ctx.FlatDir: Vector3 (unit, y=0)
ctx.Charge: number (0..1) ; ctx.Target: Model? (validated enemy) ; ctx.StartTime: number
ctx:Wait(seconds): boolean            -- yields; false if caster died/downed/stunned/boxed meanwhile (then return)
ctx:Alive(): boolean
ctx:Fx(phase: string, data: {[string]: any}?)                -- AbilityFx broadcast to all clients
ctx:Melee(spec: MeleeSpec): {Model}                          -- box hitbox in front of caster now; applies damage
ctx:Hazard(hazardType: string, params: {[string]: any}): number  -- returns hazard id
ctx:Damage(target: Model, info: DamageInfo): DamageResult    -- Attacker/Ability auto-filled
ctx:Heal(target: Model, amount: number)
ctx:Status(target: Model, name: string, duration: number, data: {[string]: any}?)
ctx:ForceMove(target: Model, packet: ForceMovePacket)
ctx:Teleport(cframe: CFrame)                                 -- caster teleport (validated, broadcast)
ctx:Enemies(): {Model} ; ctx:Allies(includeSelf: boolean?): {Model}
ctx:EnemiesInRadius(pos: Vector3, radius: number): {Model}
ctx:NearestEnemy(pos: Vector3, maxDist: number, cone: Vector3?, coneDot: number?): Model?
ctx:AddUlt(model: Model, amount: number)
ctx:Projectile(spec) -> number   -- convenience wrapper over hazard "Projectile"
```
`MeleeSpec = { Offset: CFrame (relative to root), Size: Vector3, Damage: number, KR: number?, Stun: number?,
Knockback: number? (studs/s along FlatDir), Kind: "Melee", Dodgeable: boolean?, Blockable: boolean?,
MaxTargets: number?, Fx: string? (hit FX name) }`.

### 7.4 Statuses (`StatusService`)
Names: `Stunned` (no move/act), `Rooted` (no move), `Slowed` (data.mult), `Silenced` (no abilities),
`Blue` (heavy gravity: JumpPower ×0.35, extra downward force on client), `Invulnerable`,
`Invisible`, `Rage` (data.damage, data.speed), `DamageUp` (data.mult), `DamageDown` (data.mult),
`Shielded` (data.amount absorb), `Hasted` (data.mult), `Marked`, `Exhausted`, `IFrames`, `Boxed`,
`SecondWind`, `Surge`, `Undodgeable` (attacker's hits ignore dodges).
`StatusService.Apply(model, name, duration, data?)`, `.Remove(model, name)`, `.Has(model, name) -> boolean`,
`.Get(model, name) -> (endsAt, data)?`, `.DamageMult(model) -> number`, `.IncomingMult(model) -> number`.
Writes `Status_<Name>` attributes (end time) so clients can show icons & animations.
StatusService alone writes `Humanoid.WalkSpeed/JumpPower` (recomputed from kit base stats × modifiers).

### 7.5 Damage (`DamageService.Apply(info: DamageInfo): DamageResult`)
```lua
DamageInfo = { Attacker: Model?, Target: Model, Amount: number,
  Kind: "Melee"|"Projectile"|"Beam"|"Area"|"True"|"Box",
  Ability: string?, Color: "White"|"Blue"|"Orange"|"Red"|"Purple"|"Yellow"|"Green"|"Cyan"?,
  KR: number?, Dodgeable: boolean?, Blockable: boolean?, Stun: number?, Knockback: Vector3?,
  Undodgeable: boolean?, Position: Vector3?, Silent: boolean? }
DamageResult = { Applied: number, Dodged: boolean, Blocked: boolean, Parried: boolean,
  Killed: boolean, Downed: boolean, Absorbed: number }
```
Pipeline: validity (alive, not Invulnerable/IFrames/Boxed, different teams) → colour rule for hazards
(Blue: only if target horizontal speed > `Config.Combat.MoveThreshold`; Orange: only if ≤) →
monster dodge → human block/parry → multipliers (attacker DamageMult × Harmony × Surge; target IncomingMult ×
Exhausted mult) → Shielded absorb → apply health (humans: ≤0 → Downed or dead if already Downed / no revives;
monster: ≤0 → round end; FinalPhase check) → KR add (humans) → stun/knockback → stats/ult →
broadcast `DamageFx`.

`DamageFxPacket = { target: Model, attacker: Model?, amount: number, kind: string, color: string?,
dodged: boolean?, blocked: boolean?, parried: boolean?, crit: boolean?, pos: Vector3, kr: number? }`.

### 7.6 Hazards (`Shared/Combat/HazardDefs.luau`)
A hazard is fully described by a packet; server and clients compute the same geometry from `(params, t)`.
```lua
HazardPacket = { id: number, type: string, t0: number, owner: Model?, team: string, params: {[string]: any} }
HazardDefs[type] = {
  Duration: (params) -> number,                       -- seconds after t0 when it ends
  Volumes: (params, t: number) -> {Volume},           -- active damaging volumes at time t (t = now - t0)
  HitPolicy: (params) -> { Once: boolean, Interval: number? },
}
Volume = { Shape: "Box"|"Ball"|"Capsule"|"Cylinder"|"Ring", CFrame: CFrame, Size: Vector3, Key: number? }   -- Ball: Size.X diameter; Capsule: Size.X diameter, Size.Y TOTAL length tip-to-tip incl. caps (axis = CFrame.UpVector); Cylinder/Ring: see Combat/HitTest.luau
-- (added by the combat core) Shape also "Cylinder" (Size.X diameter, Size.Y height, axis UpVector) and "Ring"
-- (annulus: Size.X outer diameter, Size.Y height, Size.Z band thickness); Capsule Size.Y is tip-to-tip.
-- Volume.Key + HitPolicy.PerKey: Once/Interval tracked per (target, Key) (Rain drops). Every param, default and
-- the exact geometry per type: header of src/shared/Combat/HazardDefs.luau (authoritative for client visuals).
```
Core hazard types (all have `delay` = telegraph time before damage, `color`, `damage`, `kr`):
| type | params |
|---|---|
| BlasterBeam | origin: CFrame (blaster at muzzle, looking along beam), length, width, delay, duration, tick, style |
| BoneLine | origin: CFrame (row centre, looking along travel), count, spacing, height, speed, distance, delay, boneThickness |
| BoneSpikes | center: Vector3, radius, count, height, delay, rise, hold, ring: boolean |
| BoneProjectile | origin: CFrame, speed, length, maxDist, delay, spin, thickness |
| Projectile | origin: CFrame, speed, radius, maxDist, delay, gravity?, visual: string (registered client visual) |
| Shockwave | center: Vector3, maxRadius, speed, height, thickness, delay |
| Orb | center: Vector3, radius, delay, duration, pullStrength, implodeDamage |
| Zone | center: Vector3, radius, height, delay, duration, tick, effect: "Damage"|"Heal"|"Slow"|"Mark", amount, visual: string |
| Rain | center: Vector3, radius, count, interval, delay, fallHeight, size, visual |
Hit testing uses character capsules (radius 1.1, height 5 × RigScale) from `HumanoidRootPart`,
scaled by `Config.Combat.HazardForgiveness` (favour the dodger).
Client `HazardVisuals` renders every type from the same params with telegraphs (ground decal-like neon rings,
warning lines) in the colour rule. Kits may register custom visual variants via `params.style`/`params.visual`.

### 7.7 ForceMove
```lua
ForceMovePacket = { kind: "Impulse"|"Pull"|"Lift"|"Slam"|"Dash"|"Teleport"|"Root",
  velocity: Vector3?, target: Vector3?, duration: number?, cframe: CFrame?, height: number? }
```
Server sends to the owner client of the target (who has network ownership). For bots (server-owned)
`MovementService` applies it server-side. Client `MovementController` implements with `LinearVelocity`/
`AlignPosition` on an Attachment in the root (created on demand, destroyed after).

---------------------------------------------------------------------------------------------------
## 8. Animation (client `Controllers/AnimController.luau`)
Clip data (`Shared/Anim/Clips/*.luau`):
```lua
Clip = { Length: number, Loop: boolean?, Priority: number? (1 base, 2 action, 3 hit/stun, 4 death),
  Mask: "Full"|"Upper"|"Lower"|"Arms"|"Head"?, Speed: number?,
  Keys: { { t: number, Ease: ("Linear"|"Sine"|"Quad"|"Cubic"|"Back"|"Elastic"|"Bounce"|"Expo")?, Dir: ("In"|"Out"|"InOut")?,
            Pose: { [jointName]: { number } } } },   -- {rxDeg, ryDeg, rzDeg} or {rx,ry,rz, px,py,pz} (translation, studs)
  Events: { { t: number, Name: string } }? }          -- markers delivered to listeners (e.g. "Hit", "Step")
```
Family clip sets: `Skeleton` and `Human`, each MUST provide: `Idle, Walk, Run, Jump, Fall, Land, Dash,
Stunned, Downed, Block, Parry, Dodge, Hit, Death, Victory, Emote_Wave, Emote_Shrug, Emote_Sit, Emote_Laugh`
plus generic action clips: `Cast, CastUp, CastForward, Summon, Point, Slam, Throw, Spin, Leap, Charge,
Slash1, Slash2, Slash3, Slash4, Punch1, Punch2, Punch3, Punch4, Kick1, Kick2, Kick3, Shoot, Reload,
Heal, Guard, Taunt`. Kit-specific clips in `Anim/Clips/Kits/<KitId>.luau` override/extend.

API:
```lua
AnimController.Play(character: Model, clip: string, opts: { Speed: number?, FadeIn: number?, FadeOut: number?,
   Weight: number?, Loop: boolean? }?) -> { Stop: (fade: number?) -> (), Ended: Signal }
AnimController.Stop(character: Model, clip: string, fade: number?)
AnimController.SetAim(character: Model, point: Vector3?)   -- upper-body/head aim layer
AnimController.HitStop(character: Model, duration: number)  -- freeze pose briefly
```
Automatic layers: locomotion blend by speed (Idle/Walk/Run), air (Jump/Fall/Land), status loops
(`Stunned`, `Downed`, `Blocking`, `Status_Blue` wobble), breathing, head look-at, lean into acceleration,
per-joint critically damped springs. Runs for every character in workspace on every client
(`RunService.PreSimulation`), distance-based LOD (>120 studs: 15 Hz, no springs).

---------------------------------------------------------------------------------------------------
## 9. Client architecture (src/client)
```
Main.client.luau            bootstrap: requires Controllers (Init all → Start all), mounts UI
Controllers/
  InputController           unified actions (KB/M, gamepad, touch); emits Signals; rebinding-ready
  CameraController          custom third-person shoulder camera (Scriptable), lock toggle, collision,
                            spring follow, shake, FOV kicks, intro flyover, spectate & kill-cam modes
  CombatController          ability input → prediction → Net "Cast"; local cooldowns; aim raycast
  AnimController            §8
  MovementController        ForceMove, dash, blue-soul gravity, character facing (AlignOrientation)
  HazardVisuals             renders HazardPackets (§7.6)
  FxController              dispatches AbilityFx/DamageFx to client kits & VFX lib; damage numbers
  SoundController           named sound registry (built-in rbxasset sounds + owner-provided ids)
  GraphicsController        applies Graphics preset (map default or user override), quality scaling
  RigStyleController        applies RigStyles to all characters
  SpectateController        spectating alive players after death
  VerdictBoxController      2D bullet-hell mini-game for the victim + 3D mirror for watchers (§11)
  StateController           wraps RoundState/Profile into Signals for UI (single source for UI data)
VFX/                        Lib (Slash, Sparks, Shockwave, Flash, Dust, Afterimage, Ring, Telegraph,
                            Beam, Shatter, Text), CameraShake, ScreenFX, DamageNumbers
Kits/<KitId>.luau           client effects per kit (§9.1)
UI/                         ThemeService, Themes, UIKit, Icons, UIRoot, Screens/*, Hud/*
```
### 9.1 Client kit module
```lua
return {
  Effects = { [abilityId] = function(fx: FxContext, packet: AbilityFxPacket) end },   -- all clients, all phases
  Predict = { [abilityId] = function(fx: FxContext, input: CastPayload) end }?,       -- caster only, immediate
  Indicator = { [abilityId] = function(fx: FxContext) -> { Update: (aim: Vector3, charge: number) -> (), Destroy: () -> () } }?,
  OnCharacter = function(fx: FxContext, character: Model) end?,                        -- passive visuals on spawn
}
AbilityFxPacket = { caster: Model, kit: string, ability: string, phase: string, castId: number, t0: number,
  aim: Vector3?, dir: Vector3?, charge: number?, data: {[string]: any}? }
```
`FxContext`: `fx.Character, fx.IsLocal, fx.Now(), fx.Anim (AnimController), fx.VFX (VFX Lib),
fx.Shake(intensity, duration), fx.Flash(color, alpha, duration), fx.Sound(name, at?, opts?),
fx.Debris(instance, seconds), fx.Delay(seconds, fn), fx.Attachment(character, name) -> Attachment?,
fx.Part(character, name) -> BasePart?, fx.EyeGlow(character, side: "Left"|"Right"|"Both", color: Color3?, on: boolean)`.

---------------------------------------------------------------------------------------------------
## 10. UI (src/client/UI)
- `ThemeService.Current() -> Theme`, `ThemeService.Changed: Signal`, `ThemeService.Set(id)`.
- Themes (`UI/Themes.luau`): `"Classic"` (Undertale black/white pixel, PressStart2P/Arcade, heart cursor,
  orange button outlines), `"Royal"` (Judgement-hall gold & navy, Garamond/Bodoni titles),
  `"Void"` (glass panels, blur, cyan/blue glow, Michroma/Sarpanch), `"Fell"` (black/crimson, sharp
  slanted panels, Oswald). HUD styles: `"Battle"` (UT battle-box) and `"Modern"`.
- `UIKit` components are pure builders: `UIKit.Panel(props) -> Frame`, `UIKit.Button(props) -> TextButton`,
  `UIKit.Label`, `UIKit.Title`, `UIKit.Bar(props) -> {Frame, Set(value, max, kr?)}`, `UIKit.Icon(name, color, size)`,
  `UIKit.Heart(color, size)` (pixel heart), `UIKit.Tooltip`, `UIKit.Tabs`, `UIKit.List`, `UIKit.Modal`,
  `UIKit.Viewport(model, opts)`. Every builder takes `theme` explicitly or uses `ThemeService.Current()`.
- Screens: `Screens/Title, Play/Loadout, Shop, Quests, Profile, Settings, StyleLab, Results`.
  HUD: `Hud/LobbyHud (intermission, map vote, monster chances), RoundHud (HP/KR/Guard/Dodges/Ult bars),
  AbilityBar, BossBar (monster), KillFeed, IntroSplash, Objectives, SpectateHud, MobileControls,
  Notifications, Nameplates`.
- Each screen module: `Create(theme: Theme, deps: ScreenDeps) -> ScreenHandle` with
  `{ Root: GuiObject, Destroy: () -> () }`; must be buildable in Lune for previews when deps are mocks.
- **Style Lab** (owner / Studio / private-server owner): live switch of Graphics preset, Map (server),
  Menu theme, HUD style, Rig style, Skin, camera style, particle density, Photo mode.
  This exists so the owner can compare variants and pick defaults.

---------------------------------------------------------------------------------------------------
## 11. Verdict Box (signature mechanic)
Monster slot F, cooldown 40 s, range 28, needs line-of-sight to a human in a 35° cone.
1. Server: validates target, sets target `Status_Boxed` + `Invulnerable` (to everything except box),
   `SoulMode="Boxed"`, freezes target, spawns `VerdictBox3D` above them (server-side anchored model),
   picks `seed` and `patternSet` (kit's `VerdictBox` field), fires `BoxStart {boxId, victim, monster,
   seed, patternSet, duration, t0, damagePerHit, krPerHit}` to all. **t0 = server open +
   `Config.VerdictBox.IntroTime` (0.8 s)**: the victim's entry transition plays before the deterministic
   timeline starts (t = now − t0 on every client, negative until then). The fight still lasts `duration`
   (BoxEnd at t0 + duration); the statuses cover IntroTime + duration (+0.25 s); hit acceptance, bot hits and
   the end are all measured from t0. `VerdictBoxService.Get` also returns `opened`.
2. Victim client — ENTRY transition (`UI/VerdictBoxEntry`, started the moment BoxStart arrives): pull-in
   ~0.65 s (camera pushed toward the victim's chest/SOUL: FOV ×0.5, ≤45 % of the distance, 10° roll, blur +
   desaturation; a dark iris closes from the screen edges onto the chest, pale streaks rush inward, the red
   SOUL heart appears at the chest), ~0.1 s full black with the heart, then a SHARP white flash (full white
   ~2 frames, fades in 0.25 s) revealing the battle box. The flash lands on t0 when the packet arrives in time
   (one-way latency ≤ 0.4 s: the pull-in takes what is left, ≥ 0.3 s); a late packet runs the shortest
   transition and a very late one is compressed so the flash has faded ≥ 0.2 s before the first attack (box
   time `introEnd`). The SOUL is not simulated before the box is revealed (`Sim.SkipTo`: no unseen hits).
   The camera is post-processed in render step `SV_VerdictBoxEntry` (Camera + 2, right after CameraController)
   and put back exactly afterwards (from the black on). Reduced Motion: no zoom/roll/iris/streaks — the
   screen darkens, black, the same flash. Audio: the InputController "Box" context is pushed with the first
   frame of the pull-in → SoundController switches to the `VerdictBox` music with a 0.15 s fade (its ids are
   checked at client start via `SoundController.Prewarm("VerdictBox")`; back out of the box: 1.0 s fade);
   a quiet `Implode` at the start, `BoxOpen` at the flash. The touch controls appear with the box.
   Then the full-screen overlay (black, battle box in the middle, heart soul, colour rules, gravity
   "blue mode" sections, Undertale-like dialogue line at start), deterministic patterns from seed;
   movement: WASD/arrows/left stick/touch-drag; reports hits via `BoxReport` (incremental) and
   `BoxSoul` position at 15 Hz.
3. Watchers: SurfaceGui on the 3D box shows the same patterns + the relayed heart position (before t0: the
   empty dialogue box).
4. Server: applies `damagePerHit`/`krPerHit` per reported hit (rate-limited to 1 per 0.45 s; none before
   t0 + introEnd − 0.35 s latency slack, i.e. never while the box flashes in; min HP 1 inside box), ends at
   t0 + duration: removes statuses, `BoxEnd`. Survived with ≤1 hit → victim gets `DamageUp 1.2` for 6 s and
   +25 ult. Bots auto-resolve (random 1–4 hits at box times after introEnd + 0.3 s).

---------------------------------------------------------------------------------------------------
## 12. Data & progression (server)
`DataService` (DataStore `"SoulVerdict_Profiles_v1"`, key `"u_<userId>"`, session-locked via `UpdateAsync`,
autosave 120 s, `BindToClose`, retries with backoff; Studio without API access → in-memory with warning).
Profile schema (`Types.Profile`), versioned with `Migrate()`.
Services: `RewardService`, `QuestService`, `AchievementService`, `ShopService`, `LeaderboardService`
(OrderedDataStores "SV_Wins_v1", "SV_Level_v1"), `MasteryService` — all consume `StatsService` events.

---------------------------------------------------------------------------------------------------
## 13. Localisation
`Strings.luau` exports `Strings.L(key: string, ...any) -> string` and `Strings.SetLanguage("en"|"ru")`,
`Strings.Language()`. Keys are dotted (`"menu.play"`). Every table entry has both `en` and `ru`.
Default language: player's `LocaleId` starting with "ru" → ru, else en; overridable in Settings.
Kit/ability names live in kit data as `{en=..., ru=...}` (use `Strings.Pick(tbl)`).

---------------------------------------------------------------------------------------------------
## 14. Performance budgets
- Character rig ≤ 220 parts. Gaster Blaster ≤ 90 parts. Map ≤ 6000 parts, ≤ 60 dynamic lights.
- Hazard sampling: O(hazards × targets) per Heartbeat; ≤ 40 simultaneous hazards.
- Client VFX: pool frequently created parts; every transient instance has a lifetime (Debris).
- Highlights ≤ 20 at once (engine limit 31).
- Particle density scaled by Settings and `UserGameSettings().SavedQualityLevel` if readable.

---------------------------------------------------------------------------------------------------
## 15. Verification (tools/)
- `tools/check.sh`: luau compile check of every file (Lune), selene lint, API-dump checker
  (`tools/checks/apicheck.py`), contract checker, Lune unit tests, build + place verification.
- `tools/preview/`: renders rigs/props/maps (three.js, headless Chromium) and GUI screens (HTML) to PNG.

---------------------------------------------------------------------------------------------------
## 16. Bootstrap & service wiring (added)
- `src/server/Main.server.luau` auto-loads every ModuleScript in `src/server/Services/` (sorted by optional
  numeric `Priority`, default 100, then name), calls `Init()` on all, then `Start()` on all (each in its own thread).
- `src/client/Main.client.luau` does the same for `src/client/Controllers/`. The UI is mounted by
  `Controllers/UIController.luau`.
- **Services/controllers require other services/controllers ONLY inside `Init()` or functions** (never at module
  top level) to avoid cyclic requires. Shared modules may be required at top level.
- Cross-service events use `Util/Signal` fields on the owning service (e.g. `DamageService.Damaged`).
- Server kit logic: `src/server/Kits/<KitId>.luau` returns `{ Abilities = { [abilityId] = function(ctx) end },
  OnSpawn = function(model, ctxFactory)?, OnDespawn = function(model)? }`; loaded lazily by AbilityService.
- Client kit effects: `src/client/Kits/<KitId>.luau` (SPEC §9.1); loaded lazily by FxController.

---------------------------------------------------------------------------------------------------
## 17. Server service APIs (authoritative signatures; `Priority` = load order, lower first)
All signals are `Util/Signal` instances. "Model" = character model. Teams: "Humans", "Monster", "Lobby", "Dummy".
Characters without a KitDef (training dummies) have `KitId = "Dummy"`, `Team = "Dummy"` (enemy of everyone).

**DataService** (P5) — `Get(player) -> Profile?`, `WaitFor(player, timeout?) -> Profile?`, `Update(player, fn(profile))`,
`Replicate(player)` (fires "Profile" + sets Player attributes), `IsReady(player) -> boolean`, `Loaded: Signal(player, profile)`.
**RequestService** (P6) — handles Net "Request": `Register(action: string, handler(player, data) -> (boolean, string?))`;
rate-limited; on failure sends `Notify(errKey)`. Actions: EquipKit, EquipSkin, Buy, ClaimQuest, RerollQuest, SetSetting,
SetRolePref, SetTitle, Vote, StartPractice, TryKit, StyleLab, Emote.
**StatusService** (P10) — SPEC §7.4. Also `RecomputeMovement(model)`, `ClearAll(model)`.
**MovementService** (P12) — `Send(target: Model, packet: ForceMovePacket)`, `Teleport(model, cframe)`,
`Dash(model, dir: Vector3, distance, time)`.
**DamageService** (P15) — `Apply(info) -> DamageResult`, `Heal(target, amount, source: Model?) -> number`,
`AddKR(target, amount)`, `Damaged: Signal(info, result)`, `Healed: Signal(target, amount, source)`,
`Parried: Signal(defender, attacker)`, `Dodged: Signal(monster, attacker)`.
**HazardService** (P15) — `Spawn(owner: Model?, team: string, hazardType: string, params) -> number`, `Remove(id)`,
`Clear()`, `HazardHit: Signal(id, target, result)`.
**CharacterService** (P20) — `SpawnPlayer(player, kitId, cframe, opts {Team, SkinId?, MaxHealth?}) -> Model`,
`SpawnBot(kitId, cframe, opts {Team, Name?, SkinId?, MaxHealth?, Blueprint?}) -> Model`, `SpawnLobby(player, kitOverride?) -> Model?`,
`Despawn(model)`, `DespawnTeam(team)`, `GetPlayer(model) -> Player?`, `GetModel(player) -> Model?`, `GetKit(model) -> KitDef?`,
`IsAlive(model)` (not Dead; Downed counts as alive), `IsUp(model)` (alive and not Downed), `GetAll(team?) -> {Model}`,
`SetDowned(model, attacker?)`, `Kill(model, attacker?, ability?)`, `Revive(model, by?)`,
`Spawned: Signal(model, player?)`, `Died: Signal(model, killer?, ability?)`, `Downed: Signal(model, attacker?)`, `Revived: Signal(model, by?)`.
**MapService** (P20) — `LoadLobby() -> MapInfo`, `Load(mapId) -> MapInfo`, `Current() -> MapInfo?`, `Lobby() -> MapInfo?`, `Unload()`,
`RandomOptions(n) -> {string}`.
**StatsService** (P25) — `BeginRound(models)`, `Add(model, stat, amount)`, `Get(model) -> RoundStatRow?`, `Rows() -> {RoundStatRow}`,
`Mvp() -> number?`, `StatEvent: Signal(player, stat, amount)` (stats: Damage, Healing, Kills, Downs, Parries, DodgesForced,
Saves, Revives, BoxesSurvived, BoxHits, Survived, Win).
**AbilityService** (P30) — handles Net "Cast"/"Block"/"Dash"; `CastAs(model, abilityId, payload) -> boolean` (bots),
`SetCooldown(model, abilityId, seconds)`, `GetCooldowns(model) -> {[string]: number}`, `ResetCooldowns(model)`,
`ScaleCooldowns(model, mult, duration)`, `Casted: Signal(model, abilityId)`. Pseudo-ability `"VerdictBox"` (monster slot F)
is routed to VerdictBoxService.Start(monster, target) with `Config.VerdictBox.Cooldown`.
**VerdictBoxService** (P35) — `Start(monster, victim) -> boolean`, `IsBoxed(model) -> boolean`, `CancelAll()`, `Ended: Signal(boxId, victim, hits, survived)`.
**QueueService** (P40) — `ChooseMonster(players: {Player}) -> Player?`, `Chances() -> {[number]: number}` (userId -> share 0..1),
`RecordRound(monsterPlayer?, humanPlayers, stats)`.
**ObjectiveService** (P45) — `Setup(mapInfo)`, `Clear()`, `SaveLit: Signal(index, players)`, `Surge: Signal()`.
**RoundService** (P50) — `Phase() -> string`, `PhaseChanged: Signal(phase)`, `RoundStarted: Signal(info)`,
`RoundEnded: Signal(result {winner, reason, rows, mvpUserId, practice, durations})`, `GetMonster() -> Model?`,
`IsRoundCharacter(model) -> boolean`, `TriggerFinalPhase(cause?: "Ult"|"Hp", caster?: Model) -> boolean` (Phase 2, §1.2:
"Ult" needs caster = the round's monster and keeps its ult bar; nil = forced), `FinalPhaseStarted: Signal(monster, cause)`,
`StartPractice(player, side)`, `ForceNextMap(mapId)`.
**BotService** (P60) — `SpawnPracticeBots(side, count)`, `SpawnDummies(cframes)`, `Clear()`.
**RewardService, QuestService, AchievementService, ShopService, MasteryService, LeaderboardService, LoginService** (P70+) —
consume RoundService.RoundEnded / StatsService.StatEvent; no public API needed beyond what RequestService routes.
**StyleLabService** (P80) — owner/Studio-only "StyleLab" requests (SetMap, StartRound, SpawnDummy, GiveUlt, SetPhase).

---------------------------------------------------------------------------------------------------
## 18. HD meshes (optional quality tier, client-side)
Smooth sculpted meshes (Sans skulls, Gaster Blaster skulls/jaws, hood/jacket shells) are generated OFFLINE
(`tools/meshgen/`, Python SDF → marching cubes → decimation → vertex colours) and shipped as Lune-safe data
modules `src/shared/Meshes/<Name>.luau` (+ `assets/meshes/<Name>.obj` for manual Studio import).
At runtime the CLIENT builds them with `AssetService:CreateEditableMesh()` + `CreateMeshPartAsync(Content.fromObject(em))`
(requires the owner to enable *Game Settings → Security → Allow Mesh / Image APIs*). If unavailable, the
part-built model stays (zero gameplay difference).
Contract for rig/prop builders:
- Parts that an HD mesh replaces get attribute `HDGroup = "<GroupName>"` (e.g. "Skull", "Jaw", "Hood").
- The anchor is an `Attachment` named `HD_<GroupName>` on the limb/part the group belongs to, positioned at the
  group's bounding-box centre, oriented so its -Z (LookVector) is the model's forward, with attribute
  `HDSize` (Vector3 bounding size in studs at scale 1) and `HDMesh` (string mesh name, e.g. "SansSkullClassic").
- Client `VFX/HDMesh.luau`: `HDMesh.Available() -> boolean`, `HDMesh.ApplyToModel(model)` (hides HDGroup parts locally via
  `LocalTransparencyModifier = 1`, welds the MeshPart at the anchor, scaled to HDSize × model RigScale),
  `HDMesh.Create(meshName) -> MeshPart?` (cached EditableMesh per name).
Mesh names: SansSkullClassic, SansSkullFell, SansSkullEclipse, BlasterSkullClassic, BlasterJawClassic,
BlasterSkullFell, BlasterJawFell, BlasterSkullEclipse, BlasterJawEclipse, SansHoodClassic (optional).

---------------------------------------------------------------------------------------------------
## 19. Engine facts that constrain the code (from docs/research/engine.md)
- Write `Motor6D.Transform` in `RunService.PreSimulation` (Animator overwrites earlier). No Animator is created.
- `StarterPlayer.AvatarJointUpgrade = Disabled` (place file) so Motor6Ds are not replaced; AnimController must still
  tolerate `AnimationConstraint` joints (same `Transform` semantics) if they ever appear.
- Never name an Attachment with "Rig" in it (R15 Humanoid:BuildRigFromAttachments could rebuild joints).
- Disable `FallingDown` and `Ragdoll` humanoid states where the humanoid is simulated (client for players, server for bots).
- `StarterCharacterScripts` contains empty `Animate` and `Health` scripts to suppress Roblox defaults.
- `Enum.Font` is legacy — use `FontFace` (`Font.new("rbxasset://fonts/families/<Family>.json", weight, style)` or
  `Font.fromEnum`). Gotham is gone (maps to Montserrat). Arcade = PressStart2P.
- `UserInputService.PreferredInput` (Touch/Gamepad/KeyboardAndMouse) exists for device detection.
- UnreliableRemoteEvent payloads: keep ≤ 900 bytes.
- Highlights: up to 255 per client (each still costs GPU; keep ≤ 30 visible).
- Light Range is clamped to 120. Neon and particles do not light surroundings — add PointLights.
- ParticleEmitter.LightInfluence defaults to 0 via Instance.new. Beam with empty Texture renders as a solid strip.
- Built-in particle textures (safe on all platforms): `rbxasset://textures/particles/{sparkles_main,smoke_main,fire_main,
  fire_sparks_main,explosion01_core_main,explosion01_implosion_main,explosion01_shockwave_main,explosion01_smoke_main,
  forcefield_glow_main,forcefield_vortex_main}.dds`.
- EditableMesh is client-only, beta, needs owner verification + "Allow Mesh / Image APIs". HD tier also supports owner-imported
  MeshParts placed in `ReplicatedStorage.SV_Meshes` (names = SPEC §18 mesh names), which work without verification.

---------------------------------------------------------------------------------------------------
## 20. Client controller APIs (authoritative; `Priority` = load order)
**InputController** (P5) — `Action: Signal(action, state: "Begin"|"End", input: InputObject?)`;
actions: "M1","Q","E","R","T","F","G","Shift","Jump","Menu","Emote","CameraLock","Interact","Back","Confirm".
`IsDown(action)`, `Device() -> "KeyboardMouse"|"Gamepad"|"Touch"`, `DeviceChanged: Signal(device)`,
`PushContext(name)` / `PopContext(name)` (contexts "Menu","Box","Dead" suppress combat actions),
`CombatEnabled() -> boolean`, `KeyLabel(action) -> string`, `BindTouchButton(action, button: GuiButton) -> () -> ()`.
**StateController** (P8) — `Round() -> {[string]: any}` (RoundState attribute snapshot), `RoundChanged: Signal(attr, value)`,
`Phase()`, `TimeLeft()`, `Now()` (server time), `Profile() -> ProfileView?`, `ProfileChanged: Signal(profile)`,
`OnRoundEvent(name, fn) -> RBXScriptConnection-like`, `RoundEvent: Signal(name, data)`, `Notify: Signal(key, args, style)`,
`LocalCharacter() -> Model?`, `CharacterChanged: Signal(model?)`, `Role() -> string`, `Request(action, data)`,
`Leaderboards() -> {Wins: {{name, value}}, Level: {...}}`, `KitOf(model) -> KitDef?`, `IsEnemy(model) -> boolean`.
**CameraController** (P15) — custom Scriptable camera: `SetMode("Follow"|"Intro"|"Spectate"|"KillCam"|"Menu"|"Photo")`,
`PlayIntro(path: {CFrame}, duration)`, `Spectate(model)`, `KillCam(position, duration)`, `Shake(intensity, duration)`,
`Kick(fovDelta, duration)`, `AimRay() -> (Vector3, Vector3)`, `AimPoint(maxDist?) -> Vector3`, `SetLock(on)`,
`LockEnabled()`, `Focus(model?)`. Reads `VFX/CameraShake` offsets each frame.
**AnimController** (P20) — SPEC §8.
**MovementController** (P22) — `Facing(on)`, `ApplyForceMove(packet)`, `IsDashing()`; handles Net "ForceMove",
double jump, blue-soul gravity, local dash prediction, AlignOrientation facing toward camera yaw when locked.
**SoundController** (P10) — `Play(name, at?: Vector3|BasePart|Attachment, opts?) -> Sound?`, `PlayMusic(key, fadeTime?)`,
`StopMusic(fadeTime?)`, `SetVolumes(music, sfx)`, `Register(name, soundId | {ids}, opts)`, `Prewarm(name)` (checks an
entry's candidates ahead of time in the background, next candidate after a bad one; VerdictBoxController prewarms
"VerdictBox" at Start), `BOX_FADE_IN` 0.15 / `BOX_FADE_OUT` 1.0 (music fades of the "Box" context); registry of built-in rbxasset
sounds + owner-provided ids in `Shared/Audio.luau`. Every entry has CANDIDATES `Audio.Candidates(name)` = normalized,
de-duplicated `{Id, ...Ids}` (best first; `SoundDef.Ids: {string}?`); an entry without candidates is silent and never warns.
- Id checks: each id is probed at most once with `ContentProvider:PreloadAsync({sound}, cb)`: `AssetFetchStatus.Success` =
  good; Failure / TimedOut / no final answer within `PROBE_TIMEOUT` (10 s) = bad; a Sound that reports IsLoaded with
  TimeLength 0, or a music deck that does not load a checked id within `LOAD_TIMEOUT` (15 s), = bad. Built-in rbxasset://
  files are trusted. Every bad id warns once: `[Sound] audio id failed to load: <id> (<entry>)`. SFX/UI play the first
  candidate not known bad (an untested one optimistically; a background batch probes SFX/UI after Start, 3 at a time) and
  switch the pool's SoundId when it turns bad; music waits for its first GOOD candidate (the old track keeps playing).
  An entry whose candidates all failed is dead: plays follow its Fallback chain.
- Music selection, pure `MusicFor(round, ctx)` with `ctx.Usable(key)` (= a candidate along the Fallback chain that is not
  dead; default: has candidates in Shared/Audio): Waiting/Intermission `Lobby`; Intro/Round/Collapse the first usable of
  `Theme_<RoundState.MonsterKit>`, the map track; while FinalPhase `Theme_<kit>_Final`, `Theme_<kit>`, `<map>_Final`
  (-> FinalPhase), `FinalPhase`, the map track (nothing usable -> the map track, silent); Ending the Victory/Defeat
  stinger; Box `VerdictBox`; lobby viewers `Lobby`; `PreviewMusic` > `SetMusicOverride` > everything. A key that dies
  re-runs the selection. Theme keys: `Audio.MonsterTheme(kitId, final?)`, kits with themes `Audio.ThemeKits`.
- Test / admin API: `ActiveId(name) -> string?` (the id in use; music: the playing deck's), `Status(name) ->
  "ok"|"pending"|"dead"|"empty"`, `PreviewMusic(key?)` (sticky test override; nil = automatic again), `NowPlaying() ->
  {Key, Entry, Id, Status, Index, Count, Preview, Playing}`, `IdState(id)`; pure helpers `PickCandidate(candidates,
  stateOf)`, `ResolveChain(name, defOf, stateOf, candidatesOf?)`, `ArenaMusicOrder(round)`. Admin panel TEST -> MUSIC
  (client only) previews the 6 themes, Lobby, VerdictBox and FinalPhase and shows key -> entry, id and status.
**FxController** (P30) — dispatches AbilityFx/DamageFx/Hazard packets to client kits/HazardVisuals/VFX; builds FxContext.
**CombatController** (P35) — input → Cast/Block/Dash; local cooldowns `Cooldowns() -> {[abilityId]: endsAt}`,
`CooldownChanged: Signal(abilityId, endsAt)`, `Charge() -> (abilityId?, 0..1)`, ammo/combo state for HUD.
**VerdictBoxController** (P40; victim entry transition §11.2 via `UI/VerdictBoxEntry`: `Stages(start, t0, introEnd,
reduced?)`, `At(stages, now)`, `CameraPose`, `CameraFx`, `Runner`), **SpectateController** (P45), **GraphicsController**
(P12), **RigStyleController** (P50).
**UIController** (P90) — mounts UIRoot, title screen, menus, results; calls `Hud.Mount(screenGui, deps)` once
(`src/client/UI/Hud/init.luau` owns per-phase HUD visibility).
UI deps table passed to screens/HUD: `{ Theme = ThemeService, State = StateController, Input = InputController,
Camera = CameraController, Sound = SoundController, Combat = CombatController, Graphics = GraphicsController,
UI = UIController, Kits = Kits, Strings = Strings }` (any may be nil under Lune previews).
- (verified) Attachments whose names END WITH "RigAttachment" trigger R15 BuildRigFromAttachments — never use that suffix.
- (verified) Use `BadgeService:AwardBadgeAsync`, `Player:LoadCharacterAsync` (we don't load characters this way), AudioPlayer.Volume 0–10.
- (verified) `UIShadow` (BlurRadius, Spread, Offset, Inset, Mode, ZIndex, ShowBehindParent) exists — feature-detect with pcall.
- (verified) `TweenService:SmoothDamp(current, target, velocity, smoothTime, maxSpeed?, dt?)` exists.
- (verified) DataStore budgets: per-server StandardRead/Write `60 + n×40`; per-experience Read `300 + CCU×40`, Write `300 + CCU×20`.
- (verified) `Lighting.ClockTime` is NotReplicated but writes propagate via TimeOfDay; client-only ClockTime is overwritten by later server changes.
- (verified) Built-in character sounds list: docs/research/builtin_sounds.txt.
