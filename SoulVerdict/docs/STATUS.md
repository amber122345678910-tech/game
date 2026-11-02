# Project status & resume plan (lead's notes)

Last updated: 2026-11-02 02:20 UTC (resumed after limit reset). Owner is asleep; usage limit at ~86% of the 5-hour window.
Resume after the limit resets (~02:00 UTC = 05:00 owner's time, UTC+3).

## Done (passing tools/check.sh as of 21:00 UTC)
- Foundation: SPEC, Types, Config, Net, Strings, Kits data (10 kits), Lune harness, bootstraps.
- Research: docs/research/*.md (graphics, genre, engine, undertale + verifications).
- Tooling/QA: tools/check.sh (compile, selene, apicheck, conventions, contracts, tests, place), Util libs.
- Rig core + 3D preview renderer (tools/preview/render.mjs, tools/lune/dump_model.luau), Dummy blueprint.
- UI core: Themes (Classic/Royal/Void/Fell), UIKit, Icons, Motion, UIRoot, Gallery + GUI renderer
  (tools/lune/dump_gui.luau, tools/preview/gui/render.mjs).
- Graphics: 20 presets, Apply, GraphicsController, Ambient weather, RigStyles, EnvExport.
- Server combat core (Ability/Damage/Status/Hazard/Movement services, CastContext, HazardDefs, HitTest,
  DamageMath) + server kits ClassicSans & Determination (+ Common M1 fallback for all kits).
- Round/character/map/queue/objective/stats/bot/stylelab services, Maps/Registry, TestArena.
- HD meshes: src/shared/Meshes/* (3 Sans skulls, 3 blaster skulls + jaws), assets/meshes/*.obj|glb,
  src/client/VFX/HDMesh.luau, docs/HD_MESHES.md.

## In progress at 21:55 UTC (wave 1b, launched 21:00; may be cut off by the usage limit)
| workflow | agents | owns |
|---|---|---|
| wf_89670014-61e | rigs-sans, rigs-humans | Rigs/Blueprints/{SansCommon,ClassicSans,FellSans,EclipseSans,HumanCommon,7 SOUL classes}, Rigs/Skins, Props/Weapons |
| wf_f0a7b275-f24 | animation, props | Anim/**, Controllers/AnimController, Services/AimService; Rigs/Props/* |
| wf_e6bf7b21-d13 | client-core, combat-client | Controllers/{Input,State,Camera,Sound,Movement,Spectate,RigStyle}, VFX/CameraShake, Shared/Audio; Controllers/{Combat,Fx,HazardVisuals}, VFX/{Lib,ScreenFX,DamageNumbers,Pool}, client Kits ClassicSans/Determination |
| wf_1ff9c197-0bf | data-progression, menus | Services/{Data,Request,Reward,Quest,Achievement,Shop,Mastery,Leaderboard,Login}, Shared/Progression/*; Controllers/UIController, UI/Screens/* |
| wf_279405c6-b55 | hud, maps-a | UI/Hud/*; Maps/{MapKit,Lobby,HallOfVerdicts,SnowdinCrossroads}, Controllers/LobbyController |
Journals: /root/.claude/projects/-home-user-game/f493f3e8-eb29-53b3-b677-a9d1a3d2561e/subagents/workflows/<id>/journal.jsonl

## Resume procedure
1. `cd SoulVerdict && export PATH=$PWD/.tools/cargo/bin:$PATH && tools/check.sh -q` — see what's broken/incomplete.
2. For every wave-1b agent that failed or didn't report: launch a CONTINUATION agent with the same ownership,
   told to inspect existing files, keep good work, finish the rest (as done at 21:00 for the first cut-off).
3. Wave 1c: VerdictBox (client mini-game + Patterns + server VerdictBoxService + 3D mirror), Maps B
   (WaterfallGrotto, VoidRift, CoreReactor), EclipseSans if unfinished.
4. Wave 2: kits FellSans, EclipseSans, Patience, Bravery, Integrity, Perseverance, Kindness, Justice
   (server src/server/Kits/<Kit>.luau + client src/client/Kits/<Kit>.luau), 4 agents × 2 kits.
5. Integration: full check, cross-module review (adversarial), fixes; build SoulVerdict.rbxl.
6. Deliverables: previews (characters/maps/menus/HUD), style board artifact for picking defaults, README (RU),
   send screenshots + summary to the owner, commit & push to branch ccr-94709699-94udct.

## Owner feedback so far
- Wants max quality everything, many style variants (menus/graphics/maps/characters) to choose from.
- Liked progress; asked for screenshots regularly. Sleep window: ~22:00–02:00 UTC.

## 02:20 UTC update
- Wave 1b finished (cut off at the end, but all deliverables exist): check.sh 0 errors, 196 scripts, 235 Lune tests.
  Previews: previews/characters, previews/props, previews/hud (27), previews/ui (36). Missing: SnowdinCrossroads.
- Running now (launched 02:15 UTC):
  - wf_8885cc8c-eb6: kit-fellsans, kit-eclipsesans
  - wf_78b0733a-ac8: kits-humans-a (Patience, Bravery, Integrity), kits-humans-b (Perseverance, Kindness, Justice)
  - wf_944ad1be-aa3: verdict-box, integration-audit (docs/INTEGRATION.md)
  - wf_cd0df11e-83b: maps-snow-waterfall, maps-void-core (+ previews of Hall/Lobby)
- Next: review results, fix leftovers, final check + build SoulVerdict.rbxl, style board artifact, screenshots + RU summary to owner.
