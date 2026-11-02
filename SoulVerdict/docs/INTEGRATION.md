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
