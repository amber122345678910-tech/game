# Integration audit (cross-module runtime flows)

Owner: integration-audit agent (wave 2). Status: IN PROGRESS — this file is written incrementally.

Each flow was traced by reading the exact sender and receiver code (packet field names/types, attribute
names, signal names, Init/Start order, client `WaitForChild` on server-created instances, nil-safety).
Offline-checkable contracts are pinned by `tools/lune/tests/integration.spec.luau`.

| # | Flow | Status | Notes |
|---|---|---|---|
| 1 | Server boot (Net → services → lobby) | auditing | |
| 2 | Player join (profile → title → lobby) | pending | |
| 3 | Intermission → vote → monster → intro → round | pending | |
| 4 | Casting (input → Cast → kit → Fx/Hazard/Cooldown) | pending | |
| 5 | Block / Dash / VerdictBox inputs, ForceMove | pending | |
| 6 | Damage → attributes → HUD / downed / kill | pending | |
| 7 | Objectives, Surge / SecondWind / FinalPhase / Collapse | pending | |
| 8 | Round end → rewards → results → lobby | pending | |
| 9 | Settings & Style Lab | pending | |
| 10 | Practice / TryKit / bots | pending | |

## Findings log (appended while auditing)
- FIXED `src/client/Controllers/StateController.luau` readLeaderboards: LeaderboardService publishes
  `ReplicatedStorage.Leaderboards/<Board>` as a **StringValue whose Value is JSON**; the client only read folder
  attributes / per-entry children, so the lobby boards stayed empty. Now parses the StringValue JSON.
- FIXED `src/client/Controllers/CameraController.luau` readSettings: read `"CameraSensitivity"`, but the Settings
  screen + ProfileSchema whitelist use `"Sensitivity"` → the slider did nothing. Now reads `Sensitivity`.
- FIXED cast / hit clips played twice (`FxController` + `AnimController` both listen to AbilityFx "Start" and
  DamageFx). Nobody called `AnimController.MarkPredicted`, so the caster's predicted clip restarted on the server
  echo, and for everyone the two controllers' clip choices (kit overrides/windup speed vs plain `Clip`; directional
  Hit vs plain Hit) overrode each other. Now AnimController owns clips: `FxController.MarkPredicted` forwards to
  `AnimController.MarkPredicted`, `FxController.PlayCastClip` uses `AnimController.PlayAbility` (returns the clip
  name; `CombatController` stops that one on rollback) and FxController's own Start/Hit/Dodge/Parry clips are a
  fallback only when AnimController is missing. VFX/sounds/hit-stop unchanged.
- FIXED revive prompt (CharacterService `RevivePrompt`, key G) was shown to everyone: the monster saw "Revive" on
  downed humans and the prompt captured **G = the monster's ultimate** (InputController ignores gameProcessed
  input) whenever it stood next to a downed human; the victim saw its own prompt; texts were server-language only.
  New `src/client/Controllers/PromptController.luau` consumes the prompt's documented attributes (HumansOnly,
  VictimUserId, ActionKey, ObjectKey): hides it locally (MaxActivationDistance 0) for non-eligible viewers and
  re-localises it.
- FIXED intro freeze used status `Stunned` (`RoundService.freeze`): every client renders Stunned as stun stars +
  "Stun" sound + the dizzy Stunned pose, so the 7 s VS intro showed everyone dizzy. Now `Rooted` + `Silenced`
  (same lock: no move/jump/dash/abilities; casts are also suppressed client-side during Intro).
- ADDED Collapse wall: nothing rendered the server's `RoundState.CollapseCenter/CollapseRadius` in the world (only a
  HUD warning once you were already outside and taking True damage). New
  `src/client/Controllers/CollapseController.luau`: 48 translucent void wall segments + ground band at the safe
  radius during Phase "Collapse" (eased, non-colliding, CanQuery off, removed after the phase).
