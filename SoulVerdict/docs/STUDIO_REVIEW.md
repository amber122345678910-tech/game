# Studio-readiness review (runtime-only failure modes)

Adversarial review of what can only go wrong when the owner opens `SoulVerdict.rbxl` in Roblox Studio and presses
**Play** (solo) or **Test → Local Server (2–3 players)** — things the offline Lune harness cannot see (engine events,
replication, physics, CoreScripts, Studio test accounts, DataStore access, performance). Review date 2026-11-02.

**Method.** Traced the boot (`Main.server` / `Main.client`: Init/Start order, yields, WaitForChild targets) and the
solo flow (join → DataService → lobby body → Title → Practice → intro → round → RoundEnd/Rewards → cleanup → lobby)
and the Local Server flow through the real code; grepped every engine API class listed in the task (attributes,
remotes, side-only APIs, collision groups, prompts, Billboard/SurfaceGuis, tweens, BulkMoveTo, Highlights, lights,
Sounds, fonts, built-in asset paths, web APIs with test UserIds, random ranges, sort comparators); computed the
top-level `require` graph of all 232 modules (**0 cycles**); built every map and every rig under Lune and counted
instances; read the built `.rbxl` back to confirm the place-level properties.

Severity: **High** = breaks a core flow in Studio · **Medium** = visible wrong behaviour / exploit · **Low** =
polish, noise or risk · **Info** = measured, no action needed. Status: **fixed** (in this pass) or **reported**
(the file belongs to the agent editing in parallel, or it is a design decision for the lead). Line numbers of
reported items refer to the tree at review time; those files were still being edited.

No **High** issue was found: boot, lobby spawn, practice, round loop, rewards and cleanup all hold up when traced
against real engine semantics (details under "Verified OK").

## Findings

| # | Sev | Where | Issue | Status |
|---|---|---|---|---|
| S1 | Medium | `src/server/Services/RewardService.luau:249`, `StatsService.luau:82,127,143,147,195`, `src/client/Controllers/SpectateController.luau:195` | **Test → Local Server players have NEGATIVE UserIds** (-1, -2, …). Rewards were only given to stat rows with `userId > 0`, so in multi-client Studio tests nobody got EXP / G / quests / achievements (Results showed no rewards). Bot stat rows used -1, -2, … and therefore **collided with Player1 / Player2** (MVP bonus or reward credit could land on the wrong row in a 1-player Local Server practice). | **fixed** — bot rows use ids ≤ `StatsService.BOT_ID_BASE` (-1 000 000) (+ `StatsService.IsBotId`); rewards go to any non-zero, non-bot id that resolves to a Player; `OwnerUserId` checks use `~= 0` (bots carry 0). Tests: `tools/lune/tests/studio.spec.luau` |
| S2 | Medium | `src/client/Main.client.luau:23` | Esc menu → **Reset Character** killed the custom character outright: the monster could forfeit a round instantly, a downed human could skip the bleed-out, an intro-frozen body could die. | **fixed** — `StarterGui:SetCore("ResetButtonCallback", false)` (retried until the CoreScripts register it; lobby falls are already handled by CharacterService's void watchdog) |
| S3 | Medium | `default.project.json` (StarterPlayer) | `DevComputerMovementMode` / `DevTouchMovementMode` were `UserChoice`: a player whose Roblox settings say **Click to Move / Tap to Move** walks to the clicked point on every **M1 attack** (mouse locked at screen centre → walks toward the crosshair) and on every touch tap. | **fixed** — `KeyboardMouse` / `DynamicThumbstick` (verified in the built place) |
| S4 | Medium (tests) | `tools/lune/run_tests.luau`, `tools/lune/loader.luau`; specs `hud`, `ui_core`, `ui_screens`, `kit_humans_b`, `verdictbox` | **Test pollution**: `Loader.reset()` only clears the module cache; the mock services, the loader flags and the shared script env live for the whole run. `hud` / `ui_core` / `ui_screens` left `Loader.isServer = false` (+ quiet warnings) for **every later suite**; `verdictbox` left `Players.GetPlayers` mocked; `kit_humans_b` left `workspace` / `RaycastParams` fakes in the env (the `kit_humans_a` LocalPlayer case was already pcall-restored). | **fixed** — every spec restores what it changes (pcall + restore); the runner snapshots (`Loader.captureState`) and restores (`Loader.restoreState`) around **every** test and **fails the test that leaked**, naming the keys — a leak can no longer cascade into later suites |
| S5 | Low (tests) | `tools/lune/tests/kit_fellsans.spec.luau` (`fell_all_hazards_plain_and_no_errors`) | The "no warnings while casting every FellSans ability" assertion was vacuous: it replaced `warn` in the script env, but modules call the loader's per-module `warn`. | **fixed** — `Loader.onWarn` collector hook; the test now really fails on any module warning (passes today) |
| S6 | Low | `src/client/Controllers/RigStyleController.luau:34` | Highlight budget: the engine renders at most **31** Highlights; outlines (24) + FX hit highlights (10) + FellSans rage aura (1) could reach 35 → some silently vanish. | **fixed** — `MaxOutlines = 20` (20 + 10 + 1 = 31) |
| S7 | Low (tooling) | `tools/checks/apicheck.py:542` (+ fixture `tools/checks/fixtures/api_cases.luau`) | `check.sh` failed on the parallel agent's new `Nameplates.Visibility(u, …)` call: the `[mistake]` rule flagged every `.Visibility`, even a module function call. | **fixed** — typo rule skips calls (`X.Visibility(`); fixture covers both cases (selftest 41/41) |
| S8 | Info | `src/server/Services/MapService.luau:228,266` | Maps are built synchronously on the server: Lune counts **Lobby 1 972 parts / 24 lights**, HallOfVerdicts 3 527 / 28, SnowdinCrossroads **5 454** / 30, WaterfallGrotto 2 989 / 37, VoidRift 2 952 / 22, CoreReactor 2 936 / 22 (119 particles/s), TestArena 296 / 16; rigs 141–205 parts each. Expected Roblox cost ≈ 0.1–0.4 s per arena (one server hitch during the intermission, while players are in the lobby) + one replication burst. | **fixed (instrumented)** — in Studio every build prints `[MapService] Arena <Id>: N parts, L lights, built + placed in X s` (a `warn` above 0.5 s). Yielding inside `Build` would need MapKit changes (Lune-safe builders, owned by another agent) and re-entrancy guards in `LoadLobby`; not worth it unless that line says "slow" |
| R1 | Low | `src/client/Controllers/InputController.luau:172` | `Menu = { "M", "Tab" }`: **Tab** also toggles the Roblox player list (CoreGui PlayerList) — one key press opens our menu *and* the player list. The PlayerList and chat windows also overlap the custom HUD corners. | reported — drop `Tab`, or `SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)` if the team panel replaces it |
| R2 | Low | `src/client/Controllers/InputController.luau:140` | Gamepad `Menu = { "ButtonSelect", "ButtonStart" }`: **Start** also opens the Roblox system menu on consoles/pads. | reported — keep `ButtonSelect` only |
| R3 | Low | `src/client/Controllers/CombatController.luau:1221`, `src/client/UI/Hud/init.luau:685` | Per-frame `pcall(step)` / `pcall(piece.Tick)` + `warn` on failure: a persistent error prints ~60 lines/s (Output spam hides the first real error). HazardVisuals already ends the failing visual instead. | reported — warn once per message (or disable the piece after N failures) |
| R4 | Low | `src/client/Controllers/CameraController.luau:689` | Photo mode's `setUiHidden` fallback disables every ScreenGui in PlayerGui (UIController has no `SetHidden`). Works, but also hides guis owned by other systems. (Known from the integration audit.) | reported |
| R5 | Info | `src/client/Controllers/CameraController.luau:1285` | Scriptable camera vs the default PlayerModule: re-asserted only when the type changed; the CameraModule deactivates its controller (input, occlusion, transparency) while Scriptable, our RenderStep runs at `Camera + 1` (after it) and `Camera.Focus` is maintained — **no per-frame fight**. If the engine resets `CameraType` to Custom on a new character, at most one frame is affected and our CFrame still wins that frame. | OK |

## Verified OK (no change needed)

- **Boot**: `Net.Server.Init()` runs before any service; every service/controller has `Init` + `Start`; Inits do not
  yield (client remote waits are inside `task.spawn`); `GetProfile` invokes made before `OnServerInvoke` is set are
  queued by the engine; every `WaitForChild` target exists in the Rojo tree or is created by the server.
- **No side-API misuse**: no `DataStoreService` / `ServerStorage` / `SetNetworkOwner` / collision-group registration on
  the client, no `LocalPlayer` / `UserSettings` / `GuiService` / camera APIs on the server; all `Net.Server.Fire`
  targets are guarded Players.
- **Collision groups** are registered in `CharacterService.Init` (server, before any spawn) and replicate to clients.
- **CharacterAutoLoads = false flow**: first spawn = `CharacterService.onPlayerAdded` → `DataService.WaitFor(≤ 8 s)` →
  `SpawnLobby` (builds the lobby on demand if MapService has not started yet); lobby deaths respawn after
  `max(RespawnTime, 2.6 s)`; falls below the map's KillY (-20 … -60, far above `FallenPartsDestroyHeight` -400) are
  teleported back by the 4 Hz watchdog. Rigs carry a Humanoid + HumanoidRootPart (R15 names), so the default
  ControlModule drives them; StarterCharacterScripts overrides are never needed (no `LoadCharacter`).
- **ScreenGuis / BillboardGuis / SurfaceGuis** all set `ResetOnSpawn = false`; interactive/mirror SurfaceGuis live in
  PlayerGui with an `Adornee`; map boards are display-only SurfaceGuis under parts.
- **DataStore in Studio**: unpublished place (`PlaceId == 0`) → memory profiles without a single DataStore call;
  published without API access → one probe, then memory mode (warning once). `BindToClose` returns immediately in
  memory mode and waits ≤ 25 s in DataStore mode (below Studio's 30 s limit). Leaderboards fall back to server-local
  boards.
- **Assets**: every sound id is empty (silent) or a built-in `rbxasset://sounds/*` file; every texture is a built-in
  `rbxasset://textures/particles/*` / `MouseLockedCursor.png`; fonts (Merriweather, PressStart2P, GrenzeGotisch,
  Oswald, PatrickHand) are built-in families → no "Failed to load" spam. HD meshes fail soft (`warnOnce`).
- **Tweens** only touch tweenable types; **BulkMoveTo** lists are built in lockstep; **Highlights** are capped;
  random ranges are guarded against empty lists; sort comparators are strict.
- **Test accounts**: no thumbnail / group / friends / badge / gamepass web calls that would fail for negative ids.
- **Leaks**: per-character Troves (CharacterService, FxController, RigStyleController, AnimController) are cleaned on
  despawn via `AncestryChanged` (the correct signal: `Destroying` does not fire on clients for server-destroyed
  instances); VFX parts / damage numbers are pooled.

## First launch in Studio — checklist

1. `tools/check.sh -q` → 0 errors; `rojo build default.project.json -o SoulVerdict.rbxl`; open the file in Studio.
   (Optional) Game Settings → Security: *Enable Studio Access to API Services* (real saves) and *Allow Mesh / Image
   APIs* (HD meshes). Without them the game runs on memory profiles and part-built meshes — that is fine.
2. **Play** (solo). Output must show `[DataService] profiles: Memory` (or `DataStore`), `server started with N
   services` / `client started with M controllers` (N, M = files in `src/server/Services` and
   `src/client/Controllers`: 25 and 17 today), one `[MapService] Lobby Lobby: … parts` line, and **no**
   `Init failed` / `Start failed` / `Failed to load` lines.
3. Title screen over the lobby; press PLAY → camera follows you; walk, jump, `LeftCtrl` toggles the shoulder lock.
   Esc menu → "Reset Character" is greyed out (S2).
4. Lobby: statues on podiums (E "Try on" swaps your body), dummies at the training area take hits and regenerate,
   leaderboards fill (memory mode: immediately), Shop / Quests booths open their screens.
5. **Practice** (portal or lobby HUD button): one `[MapService] Arena …` line (note the seconds), VS intro with no
   stun stars, then FIGHT; cast every slot; bots move, cast and revive; get downed and revived.
6. Style Lab (Studio only): GiveUlt → ultimate; FinalPhase (music + lighting); Collapse → purple wall shrinks;
   EndRound → kill-cam → Results **with rewards** → back in the lobby.
7. **Test → Local Server, 2 players**: intermission vote → monster banner → intro → round on both windows; after
   the round **both** players get rewards (S1 — Studio test players have negative UserIds).
8. If something misbehaves only in Studio, check `Workspace.SignalBehavior` (the place leaves it at `Default`; the code
   is written to work with both Immediate and Deferred events) and the Output for the first error (later ones are
   often consequences).
9. Chat commands (`/practice`, `/skip`, `/final`, `/collapse`, `/end`, `/map <id> now`, `/dummy`, `/ult`) are
   TextChatService commands: if they do nothing, set `TextChatService.ChatVersion = TextChatService`.

## Changes made in this pass

- Code: `src/server/Services/StatsService.luau`, `RewardService.luau`, `MapService.luau`;
  `src/client/Main.client.luau`; `src/client/Controllers/SpectateController.luau`, `RigStyleController.luau`;
  `default.project.json` (StarterPlayer movement modes).
- Tooling/tests: `tools/lune/loader.luau` (`captureState` / `restoreState` / `onWarn`, `quietWarnings = false`
  default), `tools/lune/run_tests.luau` (per-test leak guard), `tools/checks/apicheck.py` (+ fixture), specs `hud`,
  `ui_core`, `ui_screens`, `kit_humans_b`, `verdictbox`, `kit_fellsans`; new `tools/lune/tests/studio.spec.luau`.
