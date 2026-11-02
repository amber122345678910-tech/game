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

## Follow-ups collected from agent reports (for the final integration pass)
- HazardVisuals: add a visual-only `skullScale` param for BlasterBeam so FellSans CrimsonBlaster can have a huge skull with a narrow beam (now skull size derives from beam width).
- CombatController: optional aim preview for press-cast Direction abilities (Fell has 5 Indicators that never show). Consider "hold to aim, release to cast" option in Settings.
- FellSans Lunge reads Humanoid.MoveDirection server-side (may not replicate) — falls back to aim; consider sending move dir in CastPayload.
- Kits done 02:55 UTC: FellSans, EclipseSans (EclipseSans data Numbers extended: Offset, ImplodeRadius, ArmTime, Fire*).
- Kits done 02:55 UTC: Patience, Bravery, Integrity, Perseverance, Kindness, Justice → ALL 10 KITS COMPLETE.
- Invisible humans (Patience stealth, Eclipse VoidStep) must be skipped by: BotService monster targeting, CombatController soft-target, VerdictBox target picking, nameplates for enemies.
- Leap distance constant (1.6) duplicated client/server (Bravery/Integrity leaps) → move to Config.
- Page hazard hook applies its own damage (i-frames consume page) — acceptable.
- Indicators only shown for Hold/Ground/Target/Ally aim modes; Direction press-casts have none (Fell, Justice).
- 03:10 UTC: Verdict Box complete (Sim, Patterns (Classic/Fell/Eclipse, 8 segments each), service, controller, view, previews/verdictbox).
- Integration audit fixed 7 seams (leaderboards JSON, Sensitivity key, double cast anims, revive prompt visibility/G key, intro "dizzy" freeze, Collapse ring visuals, StyleLab SetSkin). See docs/INTEGRATION.md.
- Remaining from audit: Emote (B) has no handler; own dash anim waits for server echo; title camera ignores Lobby MenuCamera marker; mid-match joiners get arena lighting/music; InvertY/QuickCast have no Settings UI.
- 03:30 UTC: Style board artifact published: https://claude.ai/artifact/CJgZH6jNp74GpkmuEJRHJy
  (owner picks saved in db collection "picks", doc id = owner's user id; read with ArtifactData list "picks").
  Source copy: docs/style_board.html (images from previews/). dump_model --style now applies RigStyles.
- Final polish workflow wf_b83a4615-efa running (gameplay/UX polish + Studio-readiness review).

## 04:00 UTC — release candidate
- Final polish done (QuickCast/hold-to-aim, InvertY, emote wheel + EmoteService, invisible-target filtering, huge Crimson
  skull, LeapArcFactor in Config, dash anim prediction, MenuCamera, lobby waiters keep lobby look/music, MapKit windows).
- Studio-readiness review: no High issues; 7 Medium fixed (Studio test rewards, Reset disabled, click-to-move off,
  test pollution, highlight budget...), R1-R3 fixed by lead (Tab/Start bindings, warn-once). See docs/STUDIO_REVIEW.md.
- tools/check.sh: 0 errors, 339 tests. tools/build.sh → SoulVerdict.rbxl (232 scripts, 2.4 MB).
- Next (needs owner): first Studio run (checklist in README), music/SFX ids, style picks on the board.

## 08:00 UTC — owner feedback: phone menu broken + needs an admin panel
- Owner published the game and played on a phone (landscape). Screenshot: Title, lobby HUD and touch buttons all
  overlapping, menu laid out for portrait. Reproduced offline with tools/preview/gui/composite.luau --legacy --stale
  (previews/ui/phone_before_*.png).
- Fixed (mobile-ui-fix): UIRoot layers on CoreUISafeInsets below the Roblox top bar, UI rebuilt on viewport size change
  (rotation) + LayoutChanged signal; UIController hides the HUD while a menu is open; Title phone layout with
  PRACTICE/ADMIN; LobbyHud phone layout; lobby PRACTICE opened a non-existent screen → UIController.Practice().
  Lead: UIKit cursor/text sizing uses utf8.len (Cyrillic tab labels). Previews: previews/ui/phone_after_*.png.
- Added (admin-panel): AdminService (owner/Studio/private-server owner/Config.Admins) + Screens/Admin (МАТЧ/Я/ПРОГРЕСС/ТЕСТ)
  + Hud/AdminButton (crown) + "/admin". Solo testing = practice rounds vs bots (no 1-player normal round by design).
  Previews: previews/ui/admin_*.png.
- README: admin panel section + how to republish over the existing game (Publish to Roblox As → Overwrite).
- Next: owner republishes and tests on the phone; send the first error/screenshot if anything is off.

## Audio (owner asked for music from the internet, e.g. a Fell song)
- roblox.com and free-audio sites are blocked by this environment's network policy (container and WebFetch), so no ID could
  be tested here. WebSearch-only research found public candidates; the owner sent two IDs himself.
- Runtime: Audio entries take candidate lists (`Ids`); SoundController probes each id (ContentProvider.PreloadAsync, 10 s
  timeout, TimeLength 0 check), plays the first good one, warns once per bad id. Per-monster themes Theme_<Kit>(_Final),
  CollapsePhase track (owner's 128611309933897), map tracks as fallback. Admin panel TEST -> MUSIC previews + live status.
- Filled: all music slots (owner's Fell remix 120838650095309 first) and 80 SFX/UI keys (Undertale uploads first,
  Roblox-licensed Pro Sound Effects / classic Roblox sounds as fallbacks). Crit falls back to Hit.
- tools/check.sh: 0 errors, 371 tests. Commits 8477bf2 (music), e7fffa0 (SFX).
- Next: owner republishes and listens on the phone; swap or re-level sounds he dislikes (volumes are unverified).

## Owner-driven batch (in progress) — resume notes
Owner's IDs are all in src/shared/Audio.luau (first candidate of each entry): Menu, Lobby, Shop, Theme_* (Classic/Fell/Eclipse,
phase 1 + 2), VerdictBox, CollapsePhase, UiClick/UiConfirm, SoulShatter/SoulBreak, Slam, BlasterFire. No defeat track (owner found
none; current APM candidates stay). Offered: on defeat play the soul shatter first, then the sting (waiting for his answer).
Running workflows (when they finish: tools/check.sh, tools/build.sh, commit + push, send previews + rbxl with a short RU summary):
- review-audio-loading-phase2 (wf_e0b13628-ccd): review -> verify -> fix for sound / loading / phase2.
- verdict-box-entry (wf_f65aaf80-120): pull-in + darken + sharp flash, instant box music, fair fight start; previews/verdictbox/entry.gif.
- sleepy-sans-shop (wf_d2216278-df6): pixel sleepy Sans in Screens/Shop (wakes, "zzz... oh. hi, kid. what do you want?") +
  3D sleeping Sans at the lobby ShopBooth (wakes when the player comes near); previews/ui/shop_keeper_*.png, previews/maps/lobby_shop_sans.png.
If a workflow died (usage limit): Workflow({scriptPath, resumeFromRunId}) re-runs only the unfinished agents (paths in the transcript).
Resume rule (quality): do not blindly re-run a dead agent's prompt. Re-run it as a CONTINUATION: same prompt plus "an earlier agent
was cut off mid-task; first read `git diff` / `git log -5` for your files, keep what is good, finish the rest, then run the tests".
Then run the adversarial review on the finished part before shipping (as done for audio/loading/phase2).

## 12:40 UTC — after the limit reset (continuation batch)
The 3 workflows above were cut off by the usage limit (partial work committed as WIP). Review findings saved in the session scratchpad
(review_findings.json). Now running (script continue-after-limit, one owner per file set, see its BASE text):
- wf_44df9ced-5b9: box+sound (finish Verdict Box entry + SoundController review fixes), loading (UIController/Loading review fixes)
- wf_e6443210-11b: shop-screen (pixel sleepy Sans in Shop), shop-booth (3D sleeping Sans at the lobby booth)
- wf_62219af1-12d: phase2 (ult no longer a reset button, Unshaken meaning, Classic eye, lobby viewers' call-outs)
Next: adversarial review of all of it, tools/check.sh, tools/build.sh, commit + push, send rbxl + previews with a RU summary.
- 13:05 UTC: phase2, box+sound and loading continuation agents DONE (434 tests, committed). Shop agents still running
  (wf_e6443210-11b). Review of the finished parts running: review-batch-2 (wf_811a40e5-d2c, review -> verify -> fix).
  After both: review the shop part, then check/build/commit/push/send.
- 13:20 UTC: shop agents DONE (436 tests, committed). Running: review-batch-2 (wf_811a40e5-d2c) and review-shop (wf_ef79027a-b92).
  After both: tools/check.sh, tools/build.sh, commit + push, send rbxl + summary (previews already sent).

## 17:50 UTC — shipped (commit 3b68011)
- Shipped to the owner: difficulty (Easy/Normal/Hard, DifficultyService + HintController), slimmer Sans (SansCommon) and
  Soft as the default rig style, global lighting dim (Apply.DIM), accessory-only human skins, every confirmed review fix
  (box re-entry, sound fallbacks/download gating, loading/menu camera + music, shop prices/G/booth perf, ult Phase 2
  invulnerability lifted on Exhausted). tools/check.sh: 0 errors. Also gave the owner ChatGPT prompts for the
  thumbnail/icon plus title and description options.
- Owner asked that further work be done by the lead directly (not by spawning many agents) to save the usage limit.
- Next: owner republishes and tests on the phone; possible follow-ups: English store description, further Sans art passes,
  HD skull meshes (owner imports assets/meshes into ReplicatedStorage/SV_Meshes, see README).
