# Studio-readiness review (runtime-only failure modes)

Adversarial review of what can only go wrong when the owner opens `SoulVerdict.rbxl` in Roblox Studio and presses
**Play** (solo) or **Test → Local Server (2–3 players)** — things the offline Lune harness cannot see (engine events,
replication, physics, CoreScripts, Studio test accounts, DataStore access, performance). Review date 2026-11-02.

Method: traced the boot (`Main.server` / `Main.client`), the solo flow (join → lobby spawn → Title → Practice →
intro → round → rewards → lobby) and the Local Server flow through the real code; grepped every engine API class
listed in the task (attributes, remotes, side-only APIs, collision groups, prompts, BillboardGuis, tweens,
BulkMoveTo, Highlights, lights, Sounds, fonts, built-in asset paths, web APIs with test UserIds); computed a
top-level `require` graph of all 230 modules (0 cycles); built every map under Lune and counted instances.

Severity: **High** = breaks a core flow in Studio, **Medium** = visible wrong behaviour / exploit, **Low** = polish,
noise or risk. Status: **fixed** (in this pass) or **reported** (file owned by the agent editing in parallel).

## Findings

| # | Sev | Where | Issue | Status |
|---|---|---|---|---|
| S1 | Medium | `src/server/Services/RewardService.luau:239`, `StatsService.luau:126,142,196`, `src/client/Controllers/SpectateController.luau:195` | **Test → Local Server players have NEGATIVE UserIds** (-1, -2, …). Rewards were only given to rows with `userId > 0`, so in multi-client Studio tests nobody got EXP/G/quests/achievements; bot stat rows used -1, -2, … and so **collided with Player1/Player2** (MVP bonus / reward credit could go to the wrong row). | **fixed**: bot rows now use ids ≤ `StatsService.BOT_ID_BASE` (-1 000 000) + `StatsService.IsBotId`; rewards accept any non-bot, non-zero id; OwnerUserId checks use `~= 0`. Tests: `studio.spec.luau` |
| S2 | Medium | `src/client/Main.client.luau` | Esc menu → **Reset Character** killed the custom character: the monster could forfeit a round instantly, a downed human could skip the bleed-out, intro-frozen bodies could die. | **fixed**: `StarterGui:SetCore("ResetButtonCallback", false)` (retried until the CoreScripts register it; lobby falls are already handled by the void watchdog) |
| S3 | Medium (tests) | `tools/lune/run_tests.luau`, `tools/lune/loader.luau`, specs `hud`, `ui_core`, `ui_screens`, `kit_humans_b`, `verdictbox`, `kit_fellsans` | **Test pollution**: `Loader.reset()` only clears the module cache — mock services, loader flags and the shared script env live for the whole run. `hud`/`ui_core`/`ui_screens` left `Loader.isServer = false` (+ quiet warnings) for **every later suite**; `verdictbox` left `Players.GetPlayers` mocked; `kit_humans_b` left `workspace`/`RaycastParams` fakes in the env. | **fixed**: each spec restores what it changes (pcall + restore); the runner now snapshots (`Loader.captureState`) and restores (`Loader.restoreState`) around every test and **fails the test that leaked**, naming the leaked keys — a leak can no longer cascade |
| S4 | Low (tests) | `tools/lune/tests/kit_fellsans.spec.luau` (`fell_all_hazards_plain_and_no_errors`) | The "no warnings" assertion was vacuous: it replaced `warn` in the script env, but modules call the loader's per-module `warn`. | **fixed**: `Loader.onWarn` collector hook; the test now really fails on any module warning (passes today) |

(continued below as the review proceeds)
