# Integration audit — cross-module runtime flows

Audit of the runtime flows that cross module/agent boundaries (wave 2, 2026-11-02). Each flow was traced by
reading the exact sender and receiver code: packet field names/types, attribute names, signal names, function
signatures, Init/Start order, attributes set before parenting, client `WaitForChild` on server-created instances,
nil-safety. Contracts that can be checked offline are pinned by `tools/lune/tests/integration.spec.luau`
(12 tests); the generic ones (remote names/sides, `require` paths, exports, `Strings.L` keys) were already covered
by `tools/checks/contracts.py`.

Out of scope (owned by agents running in parallel): the 8 non-reference kits, the 4 new maps and everything
Verdict Box (`VerdictBoxService`, `VerdictBoxController`, `Shared/VerdictBox/**`, `UI/VerdictBoxView`).

## Flow status

| # | Flow | Status | Notes |
|---|---|---|---|
| 1 | Server boot: `Net.Server.Init` → services (Priority) → Request registration → `MapService.LoadLobby` → lobby spawns / dummies | OK | All Init before any Start; RequestService (P6) registers built-ins first, services replace them silently (`SetRolePref`, `TryKit`, `Vote`, `StartPractice`, `StyleLab`). `RoundState` is created in `RoundService.Init`, so every Start sees it. Lobby `MapInfo.HumanSpawns` / `DummySpawns` are translated to world space and used by `CharacterService.pickLobbySpawn` / `BotService.spawnLobbyDummies`. |
| 2 | Player join: profile → `Profile` / `GetProfile` → StateController → Title + Menu camera → lobby statues / boards | **fixed** | Leaderboard format mismatch (F1). `GetProfile` handler is set in `DataService.Start` (first Start); an earlier client invoke is queued by the engine and the handler waits ≤ 15 s for the load; `StateController` also takes the later `Profile` push. |
| 3 | Intermission → `MapVote` → `Request "Vote"` → `MonsterChosen` → `Intro` (introPath / splash) → Round | **fixed** | Vote payload (bare mapId) and `MapVote {options, votes}` match LobbyHud; `Intro` fields (`introPath`, `center`, `radius`, `monster/humans {userId, kitId, name, model, isBot}`) match CameraController.PlayIntro and IntroSplash. Intro freeze showed stun stars (F5). HUD per-phase visibility (`Hud.Visible`) agrees with the server phases. |
| 4 | Casting: Input → CombatController payload → `Cast` → AbilityService → kit → AbilityFx / Hazard / DamageFx / Cooldown → Fx / HazardVisuals / Anim / AbilityBar | **fixed** | Payload `{aim, dir, charge, target, castId}` matches `sanitizePayload`; rejected casts answer `Cooldown(abilityId, realEnd)` → client rollback. Every ClassicSans / Determination phase has a client handler (BoneWall "Wall" is drawn by HazardVisuals) — test `integration_reference_kit_phases_match`. Cast/hit clips were played twice (F3). FxContext fields used by kits all exist. |
| 5 | Block / Dash / Verdict Box inputs; ForceMove | OK | `Block(bool)` → `Blocking` + `BlockStart`; `Dash(Vector3)` → `DashCharges`, IFrames, MovementService (echo flag honoured by MovementController); F for monsters → pseudo-cast `"VerdictBox"` (AbilityService → VerdictBoxService). All 7 ForceMove kinds are handled client-side. |
| 6 | Damage → attributes → HUD / Nameplates / Anim; Downed → revive prompt; Kill → feed / death VFX / spectate | **fixed** | Attribute names (KR, Dodges, MaxDodges, Exhausted, Guard, MaxGuard, Ult, Downed, DownedEndsAt, Dead, FinalForm, SoulMode, Shield, Status_*, Cooldown_*) match `Hud/Data`. Every client-read attribute is written somewhere. Revive prompt captured the monster's G (F4). |
| 7 | SAVE stars, Surge / SecondWind / FinalPhase / Collapse | **fixed** | Star tag `SaveStar` + attributes (Index, Progress, Lit, Contested, Channelers, Radius) match HUD Objectives; RoundEvent payloads match Announcements; GraphicsController uses `GraphicsPreset` / `FinalPreset` / `FinalPhase`; SoundController switches on `Phase` / `MapId` / `FinalPhase`. No world visual for the Collapse ring (F6). |
| 8 | Round end → RewardService → `RoundEnd` + `Rewards` → Results → lobby | OK | `RoundEnd {winner, reason, stats (RoundStatRow), mvpUserId, lastHit, practice, mapId}` and `Rewards {exp, gold, items, levelUp, newLevel, expInto, expToNext, unlocked, questProgress, mastery}` match `Screens/Results`; ordering (RoundEnd before Rewards) is guaranteed on one remote; cleanup respawns everyone in the lobby. |
| 9 | Settings & Style Lab | **fixed** | Camera sensitivity key (F2), missing `SetSkin` Style Lab action (F7). Every key the Settings screen edits is whitelisted by `ProfileSchema.Settings`; `PushOverride/PopOverride` signatures match. |
| 10 | Practice / TryKit / bots | OK | `StartPractice` (bare side or `{side, allies}`), `TryKit` (`kitId` or `{kitId}`); BotService casts through `AbilityService.CastAs` with the same payload shape, reads HazardService records (`Def`, `Params`, `T0`, `Team`, `ActiveEnd`). |

## Issues found & fixed

| id | where | problem → fix |
|---|---|---|
| F1 | `src/client/Controllers/StateController.luau` `ReadBoard` | LeaderboardService publishes `ReplicatedStorage.Leaderboards/<Board>` as a **StringValue with JSON**; the client only read folder attributes / entry children → lobby boards always empty. Now parses the StringValue (pure `StateController.ReadBoard`, tested). |
| F2 | `src/client/Controllers/CameraController.luau` `readSettings` | read `"CameraSensitivity"`; the Settings screen + whitelist use `"Sensitivity"` → slider did nothing. Reads `Sensitivity`. |
| F3 | `FxController` (`MarkPredicted`, `PlayCastClip`, AbilityFx Start, DamageFx), `CombatController` (`cast`, `castVerdict`) | Fx and Anim controllers both played cast clips (AbilityFx "Start") and hit reactions (DamageFx); nobody called `AnimController.MarkPredicted`, so the caster's predicted clip restarted on the server echo and the two clip choices overrode each other. AnimController now owns clips; FxController forwards MarkPredicted, plays predictions through `AnimController.PlayAbility` and keeps its own clips only as a fallback. VFX/sound/hit-stop unchanged. |
| F4 | new `src/client/Controllers/PromptController.luau` | The server's revive ProximityPrompt (key **G**) carries `HumansOnly` / `VictimUserId` / `ActionKey` / `ObjectKey` "client hints" that nothing consumed: the monster saw "Revive" on downed humans and the prompt **swallowed G = the monster's ultimate** (InputController ignores gameProcessed input) whenever it stood next to a downed human; victims saw their own prompt; texts stayed in the server's language. Now hidden locally (MaxActivationDistance 0) for non-eligible viewers and re-localised. |
| F5 | `src/server/Services/RoundService.luau` `freeze` | Intro freeze used `Stunned` → stun stars + "Stun" sound + dizzy pose on every character during the VS intro. Now `Rooted` + `Silenced` (same lock). `round.spec` updated. |
| F6 | new `src/client/Controllers/CollapseController.luau` | Nothing drew the Collapse safe radius in the world (server deals True damage outside). Translucent void wall + ground band from `RoundState.CollapseCenter/CollapseRadius` during Phase "Collapse". |
| F7 | `src/server/Services/StyleLabService.luau` `SetSkin` | Style Lab skin cycler sends `{action = "SetSkin"}` for unowned skins; the action did not exist (warning toast). Added (lobby only, respawn in place with that skin, not saved). |

## Known risks / gaps (not fixed)

- **Verdict Box** (other agent): `VerdictBoxController` must `InputController.PushContext("Box")` for the victim
  (SoundController switches to the "VerdictBox" music and combat input is suppressed on that context) and pop it
  at `BoxEnd`. AbilityService broadcasts AbilityFx `{ability = "VerdictBox", phase = "Start", data.target}`.
- Kits written in parallel: until a server kit exists, AbilityService falls back to `Common.ComboStrike` for M1
  (Numbers.Damage1) and warns once for other abilities. Practice uses FellSans for the monster bot (round.spec), so
  practice depends on that kit being finished. Extend `REFERENCE_KITS` in `integration.spec.luau` once they land.
- `InvertY` (CameraController) and `QuickCast` (CombatController) are read but have no Settings UI and are not in
  the ProfileSchema whitelist (local defaults only).
- Emote (B / `InputController` "Emote") has no consumer: no emote wheel / `Request "Emote"` yet.
- The local dash clip plays on the server's AbilityFx echo (castId 0 cannot be marked predicted): ~ping delay.
- Players who join mid-match stay in the lobby but follow the arena's RoundState (graphics preset, music, the
  intro flyover camera).
- Title-screen camera orbits the local character; the lobby's `MenuCamera` marker is not used
  (`CameraController.SetMenuShot` is never called).
- `CameraController.setUiHidden` (photo mode) uses its fallback (hides every ScreenGui) because UIController has
  no `SetHidden`; harmless since UIController.PhotoMode also toggles its layers.

## First Studio test checklist (owner)

1. `tools/check.sh -q` (0 errors), `rojo build default.project.json -o SoulVerdict.rbxl`, open the place.
   Game Settings → Security: enable Studio API access if you want saving (otherwise profiles run in memory with a
   toast). Mesh/Image APIs only for HD meshes.
2. **Play (solo)**: Output shows `server started with N services` / `client started with N controllers` and no
   `Init failed` / `Start failed` lines. Title screen over a slow orbit; close it (Play) → camera follows you.
3. Lobby: SOUL statues on podiums, "Try on" prompts (E) swap your body; training dummies regenerate; leaderboards
   fill after ~2 min (or immediately in memory mode); Shop / Quests booths open screens.
4. Settings: change Sensitivity / FOV / music volume → applies immediately and persists after rejoin.
5. **Practice** (portal or LobbyHud button): VS intro plays — characters stand still with **no stun stars** —
   then "FIGHT". Cast every slot: the cast animation plays once (no restart ~100 ms later), cooldowns sweep on the
   ability bar, blasters / bones telegraph then hit.
6. Get downed: allies (bots) can revive you; as the monster (Style Lab → practice as Monster) stand next to a
   downed human: **no "Revive" prompt** and **G casts the ultimate**.
7. Style Lab (Studio only): GiveUlt, FinalPhase (music + lighting switch), Collapse → a **purple wall** shrinks
   around the arena and damages you outside; EndRound → kill-cam, Results card with rewards, back to the lobby.
8. Style Lab skin cycler on an unowned skin → your lobby body changes skin (no warning toast).
9. **Local Server, 2 players**: Intermission vote → monster banner → intro → round on both clients.

## Offline contract tests (`tools/lune/tests/integration.spec.luau`)

| test | pins |
|---|---|
| `integration_reference_kit_phases_match` | ClassicSans / Determination: every server AbilityFx phase has a client handler and vice versa; ability ids exist in kit data; every slotted ability has a server handler |
| `integration_round_events_have_consumers` | every RoundEvent fired is consumed on the client; no client listener for an event the server never fires |
| `integration_request_actions_are_registered` | every client `Request` action has a server handler (+ the SPEC §17 list) |
| `integration_stylelab_actions_exist` | Style Lab screen actions exist in StyleLabService |
| `integration_settings_keys_are_whitelisted` | Settings screen keys + controller-read keys vs `ProfileSchema.Settings` |
| `integration_roundstate_attributes_exist` | SPEC §4.1 attributes in `STATE_DEFAULTS`; client reads only known RoundState attributes |
| `integration_phase_names_are_valid` | client round-phase comparisons use real phase names |
| `integration_leaderboard_stringvalue_format` | LeaderboardService StringValue JSON → `StateController.ReadBoard` |
| `integration_revive_prompt_visibility` | PromptController eligibility + the CharacterService prompt attributes |
| `integration_collapse_ring_frames` | CollapseController segment frames (radius, facing, right-handed) |
| `integration_intro_freeze_is_not_stun` | RoundService intro freeze uses Rooted, not Stunned |
| `integration_cast_clips_single_owner` | FxController forwards MarkPredicted; AnimController API present |
