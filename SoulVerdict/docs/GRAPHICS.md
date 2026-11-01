# Graphics: presets, runtime control, weather, rig styles

Design note for the owner and for map/VFX authors. Code lives in:

| File | What it does |
|---|---|
| `src/shared/Graphics/Presets.luau` | 20 lighting presets (data) + `Presets.Resolve` (which one is on screen) |
| `src/shared/Graphics/Apply.luau` | applies a preset to `Lighting` (+ `SV_*` children), Terrain clouds, `Workspace.GlobalWind`; `Snapshot`, `Lerp`, `ForQuality` |
| `src/client/Controllers/GraphicsController.luau` | client runtime: map preset, final phase, overrides, smooth transitions, quality tiers, Reduced Motion |
| `src/client/VFX/Ambient.luau` | camera-following weather particles (snow, embers, dust, fireflies, ...) |
| `src/shared/Rigs/RigStyles.luau` | character style variants: Classic / Toon / Soft / Glow |
| `src/shared/Graphics/EnvExport.luau`, `tools/lune/dump_env.luau` | preset -> environment JSON for the offline preview renderer |
| `src/shared/Strings/Graphics.luau` | UI strings (en/ru) for graphics settings |

Everything is built from script-writable properties and built-in content only: the default skybox, built-in
particle textures (`rbxasset://textures/particles/*.dds`), Neon + Bloom, Atmosphere, Clouds and post effects.
No asset ids anywhere.

## 1. How the active preset is chosen

`GraphicsController` (client, Priority 12) decides with `Presets.Resolve`:

1. **Pushed overrides** win, highest `priority` first (the newest wins a tie), shown exactly as pushed:
   - Eclipse Sans' ultimate (client kit code, on human clients only):
     `GraphicsController.PushTimed("EclipseUlt", "EclipseDark", 8, GraphicsController.PRIORITY.Gameplay, 0.8, 1.2)`
   - Style Lab: `GraphicsController.PushOverride("StyleLab", id, GraphicsController.PRIORITY.StyleLab, 0.8)` and
     `PopOverride("StyleLab")` to go back.
   - Priorities: `User = 0`, `StyleLab = 50`, `Gameplay = 100`, `Cinematic = 200`.
2. Else the **player's own choice** from Settings: `GraphicsController.SetOverride(id)`.
   `nil` or `"MapDefault"` follows the map (the default, `Config.Defaults.GraphicsPreset`).
3. Else the **map preset**: `ReplicatedStorage.RoundState` attribute `GraphicsPreset` (set by the server from
   `MapDef.Preset`). If it is missing, `MapId` is mapped with `Presets.ForMap`.
4. Else `Lobby`.

While `RoundState.FinalPhase` is true, steps 2–4 switch to the `"<Id>Final"` variant when it exists. The server may
also set an explicit `RoundState.FinalPreset` attribute; when it does, that wins for the map preset.

Every change cross-fades over about 1.5 s (smoothstep). `Apply.Lerp` blends numbers, Color3 and Vector3 values.
Booleans and enums switch at the halfway point. `ClockTime` takes the shortest way around the clock, so the fade
from GoldenHall to EclipseDark looks like a fast sunset, not a trip through noon. An effect that is on in only one
of the two presets fades through its neutral value (for example Bloom intensity 0), so nothing pops.
The per-frame `PreRender` connection exists only while a transition is running.

Saved settings are read from `StateController.Profile().Settings` when it exists. The keys are `GraphicsPreset`,
`ParticleDensity` and `GraphicsQuality` (`"Auto"|"Low"|"Medium"|"High"|"Ultra"`). The Settings screen can also call
`SetOverride`, `SetParticleDensity` and `SetQualityOverride` directly.

## 2. Quality tiers

`GraphicsController.Quality()` returns `"Low" | "Medium" | "High" | "Ultra"`. `Changed(quality)` fires when the tier
or `ParticleScale()` changes, so VFX can scale their particle counts.

- **Hint:** `UserGameSettings.SavedQualityLevel` (read in a pcall). Levels 1–3 map to Low, 4–6 to Medium, 7–8 to High
  and 9–10 to Ultra. "Automatic" tells us nothing, so the game starts at High, or Medium on touch-only devices.
- **Measured:** a smoothed frame time. Below 28 FPS for 4 s steps down one tier. Above 55 FPS for 25 s steps back
  up, but never above the player's own Roblox setting. Measuring pauses while the window is unfocused.

| Tier | Post effects | Particles (`ParticleScale`) |
|---|---|---|
| Low | no DOF, no SunRays, no Clouds, Bloom size ×0.55 and intensity ×0.75, half the stars | 0.35 |
| Medium | no DOF, SunRays ×0.8, Bloom size ×0.8 | 0.65 |
| High | as authored | 1.0 |
| Ultra | as authored | 1.25 |

`ParticleScale()` = tier scale × the player's density setting (0..2) × 0.7 when Reduced Motion is on.

**Reduced Motion** (`GuiService.ReducedMotionEnabled`): weather particles are fewer and slower
(`ParticleEmitter.TimeScale` 0.6). `GraphicsController.ReducedMotion()` and `ReducedMotionChanged` are there so that
camera shake, screen flashes and other VFX can respect it too.

## 3. The presets

The sun direction comes from the G3D model Roblox inherited (`EnvExport.SunDirection`): the sun rises at **+X** (east)
at 6:00 and sets at **−X** (west) at 18:00. In Studio, `Lighting:GetSunDirection()` is the ground truth.

| Preset | Mood | Intended map | Key light | Weather |
|---|---|---|---|---|
| **Lobby** | Cozy save-room warmth: soft afternoon light, gentle haze, a few motes | Lobby | sun 35° from −X | Dust 0.6 |
| **GoldenHall** | Judgement-hall golden hour: amber shafts through tall windows, deep warm shadows, floating dust | HallOfVerdicts | sun 10° from −X | Dust |
| GoldenHallFinal | Sun on the horizon: darker, desaturated gold, cold cyan shadows, blazing highlights | HallOfVerdicts (final) | sun 2° from −X | Dust 1.4 |
| **SnowNight** | Snowdin night: cold blue moonlight, stars, soft snowfall; warm windows in contrast | SnowdinCrossroads | moon 27° | Snow |
| SnowNightFinal | Whiteout: the blizzard closes in, colder, darker, howling wind | SnowdinCrossroads (final) | moon 31° | Blizzard |
| **WaterfallGlow** | Dark cavern in bioluminescence: cyan glow, teal mist over water, sparkling crystal ceiling | WaterfallGrotto | dim moon | Fireflies |
| WaterfallGlowFinal | The echoes bloom violet: deeper dark, magenta-cyan glow, rising spores | WaterfallGrotto (final) | dim moon | Spores |
| **VoidAbyss** | A dream rift in an endless deep-blue void: drifting stars, cold side light, blazing neon cracks | VoidRift | moon 37° from +X | VoidMotes |
| VoidAbyssFinal | Red shift: crimson void, hot magenta glow, red stars; the light swings to −X during the fade | VoidRift (final) | moon 37° from −X | RiftMotes |
| **CoreInferno** | Industrial heat: orange-red glare through hazy air, silhouetted machinery, rising embers | CoreReactor | sun 17° from −X | Embers |
| CoreInfernoFinal | Meltdown: red-alert light, choking haze, a storm of embers | CoreReactor (final) | sun 1° from −X | Embers 1.6 |
| **BloodFell** | Crimson dusk of a crueler underground: blood-red sky, black silhouettes, falling ash | any map / a future Underfell map | sun 3° from −X | Ash |
| BloodFellFinal | The red sun drowns: near-black crimson, heavy ash, searing highlights | (final) | sun 0.4° | Ash 1.7 |
| **Dreamscape** | Soft pastel dawn: pink-lavender sky, wide gentle bloom, floating glimmers; lighter, hopeful | any map / event | sun 8° from +X (dawn) | Glimmer |
| DreamscapeFinal | Lucid dusk: violet, cooler pastels, sharper contrast | (final) | sun 2° from −X | Glimmer 1.4 |
| **Monochrome** | High-contrast black-and-white "old film": hard light, deep blacks, film dust | any map (style) | sun 49° | Dust 0.8 |
| MonochromeFinal | The film burns: crushed blacks, blown highlights, faint blood-red cast | (final) | sun 49° | Ash |
| **EclipseDark** | Total eclipse: the world goes almost black; only glowing attacks and nearby silhouettes remain | Eclipse Sans' ultimate (humans) | none | VoidMotes 0.7 |
| **Performance** | Clean, flat, fast: neutral daylight, no shadows, minimal post, maximum readability | any map (setting) | sun 67° | none |
| PerformanceFinal | Performance with a warm red final-phase tint (still cheap) | (final) | sun 67° | none |

Rules that apply to every preset:
- Gameplay readability never depends on shadows, DOF or SunRays. Attacks read through Neon, silhouette and colour.
- Bloom is moderate on purpose. Dark presets keep Intensity at 0.6–0.75 with Threshold ≥ 0.88, so a white, cyan or
  orange bone keeps its shape instead of becoming a blob. This was checked with the preview renderer.
- `Performance` turns off GlobalShadows, DOF, SunRays and Clouds. Bloom is kept only for the Neon pop.
- The blue ("don't move") and orange ("keep moving") attack colours must stay readable in every look. No preset
  goes below Saturation −0.85, so Monochrome keeps a ghost of colour (a test enforces this).

## 4. Notes for map builders, per preset

- **HallOfVerdicts / GoldenHall:** the sun stands about 10° above the **−X** horizon, so put the tall windows in the
  **−X wall**. Long beams then cross the hall toward +X, and SunRays fire when the camera looks at the windows.
  Floor: Marble or SmoothPlastic in gold or cream, which `EnvironmentSpecularScale` 0.85 makes glossy. Avoid big
  white Neon: the gold Bloom threshold is 1.05, which is aimed at highlights. The final phase drops the sun to 2°,
  so the beams go almost horizontal.
- **SnowdinCrossroads / SnowNight:** windows and lamps are warm PointLights (`rgb(255,170,90)`, Brightness 2, Range
  20). Use Shadows only on 2–4 key lights. The cold ambient and the blue moon make them pop. Use Snow or Glacier
  terrain; icy surfaces catch the specular light.
- **WaterfallGrotto / WaterfallGlow:** most of a cavern is "indoor", so the teal `Ambient` sets the mood. Use Neon
  mushrooms and crystals in cyan or teal, each with a small PointLight (Range 8–12, Shadows off), because Neon does
  not light its surroundings. Water: terrain Water, or SmoothPlastic with `Reflectance` 0.2–0.4. Leave a few gaps in
  the ceiling: the stars (StarCount 5000) and the CeilingStars weather sparkle like crystals.
- **VoidRift / VoidAbyss:** black or navy SmoothPlastic islands with thin Neon cracks in cyan or violet. Float the
  arena: the deep-blue Atmosphere with Haze 4 swallows the edges. The moon side-lights from +X, and the final phase
  swings it to −X.
- **CoreReactor / CoreInferno:** dark DiamondPlate or Metal machinery against orange Neon lava, with PointLights
  `rgb(255,120,40)` near the lava. `ColorShift_Bottom` adds a faint under-glow on surfaces facing away from the sun.
- **Lobby:** warm and readable. Interiors can rely on `Ambient (96,80,64)`.

## 5. Ambient weather (`VFX/Ambient.luau`)

Each weather is 1–3 invisible, anchored, non-collidable volume parts parented to `Workspace.CurrentCamera`.
They are re-centred on the camera every frame and pushed a little along the view direction. Particles live in
world space, so moving through snow gives real parallax. Mist volumes follow the floor under the camera (a raycast
4 times a second). Switching weather stops the old emitters and lets their particles finish; the new weather starts
with a pre-filled burst. Rates are capped at 400/s per emitter (the engine limit; 100/s on mobile).

| Id | Look | Textures |
|---|---|---|
| Snow | soft flakes drifting on GlobalWind, rare glints, low mist | implosion glow dot, sparkles, smoke |
| Blizzard | dense streaking flakes (VelocityParallel, negative Squash), blowing gusts, mist | glow dot, smoke |
| Embers | rising yellow, orange and red sparks, quick flickers, low heat haze | glow dot, sparkles, smoke |
| Ash | grey irregular flakes plus a few glowing cinders | glow dot |
| Dust | warm motes, additive and lit, so they shine in sun shafts and vanish in shade; tiny glints | glow dot, sparkles |
| Fireflies | blinking cyan bioluminescence, twinkling ceiling stars, teal ground mist | glow dot, sparkles, smoke |
| Spores | rising cyan-to-violet spores, violet ceiling stars and mist | glow dot, sparkles, smoke |
| VoidMotes | dark floating motes, rare bright blue stars, dark ground wisps | glow dot, sparkles, dark smoke |
| RiftMotes | red-shifted VoidMotes | same |
| Glimmer | pastel twinkles and soft dots, pink mist | sparkles, glow dot, smoke |
| Rain | fast soft streaks plus low spray mist | glow dot (squashed), smoke |

API: `Ambient.Set(id?, density?, {TimeScale?})`, `Ambient.Stop()`, `Ambient.Current()`, `Ambient.Ids()`, and
`Ambient.Build(id, density, timeScale)`, a pure builder that the tests use.

## 6. Rig styles (`Rigs/RigStyles.luau`)

`RigStyles.Apply(model, id)` works on the visual parts' `Role` attribute (SPEC §5.1). It always reverts first, so it
is idempotent. Originals are stored in `SV_Orig*` attributes. Revert keeps a newer value if something else, such as a
skin recolour, changed the property after the style did.

| Style | Effect |
|---|---|
| Classic | every part becomes SmoothPlastic, except Neon, Glass and ForceField; no outline |
| Toon (default) | Classic plus one black outline `Highlight` (FillTransparency 1, OutlineTransparency 0, DepthMode Occluded) |
| Soft | Cloth, ClothAlt and Trim become Fabric; Skin and Bone become SmoothPlastic; Metal gets Reflectance 0.12 |
| Glow | Classic plus brighter Neon on Accent, Eye and Glow parts, and up to 2 small PointLights on glowing Eye parts (pupils first) |

`RigStyles.SetOutlineVisible(model, false)` hides the Toon outline. Use it for stealth (Invisible / Patience),
otherwise the outline gives the hidden player away.

## 7. Preview export

`lune run tools/lune/dump_env.luau <presetId> [--out env.json]`, `--all <dir>` or `--list` converts presets into the
environment JSON of `tools/preview/render.mjs` (`--env`). The value semantics follow the renderer's header in
`tools/preview/scene/env.js`:

- `sun.dir` is the direction toward the sun, or toward the moon at night.
- `sun.intensity` is 0.45 × Brightness × a horizon fade.
- `bloom` is Neon-only: strength = Intensity × 1.5, threshold = (Threshold − 0.8) × 0.5.
- `exposure` = 2^ExposureCompensation.
- `saturation` and `contrast` are ColorCorrection offsets.
- `fog` approximates Atmosphere Density, Offset and Haze.

All of this is an approximation for comparing looks. Final tuning happens in Studio.

## 8. What the owner sets once in Studio

1. **Explorer > Lighting > Properties:** `LightingStyle = Realistic` and `PrioritizeLightingQuality = true`. Scripts
   cannot write either property (capability PluginOrOpenCloud). The Rojo project file sets them for `rojo build`, but
   `rojo serve` does not apply them.
2. **Studio Settings > Rendering > Editor Quality Level = maximum**, then compare presets in the Style Lab. Also check
   on a phone or in the Device Emulator: shadows are off below quality level 4.
3. Do not add a Sky, Atmosphere or Clouds of your own. The client moves foreign Sky, Atmosphere and ColorGrading
   into `Lighting.SV_Stash` and disables foreign Clouds, so they would have no effect. Extra Bloom or ColorCorrection
   effects would stack with ours.
4. The server must not write Lighting properties. `ClockTime` is local per client, and replicated `TimeOfDay` writes
   would fight the client.
5. Optional: enable Terrain `Decoration` (grass sways with GlobalWind) in Studio. It is not scriptable.

## 9. Verification

```
lune run tools/lune/run_tests.luau graphics    # 19 tests: every preset applies to a Lune Lighting (names,
                                               # types and enums validated), API-dump writability, idempotency,
                                               # Snapshot round-trip, Lerp over all 400 pairs, quality, Resolve rules,
                                               # EnvExport ranges + JSON, RigStyles apply/revert, Ambient builder,
                                               # strings, and GraphicsController + Ambient runtime logic driven
                                               # with mocked services (RoundState, PreRender frames, FPS, Reduced Motion)
                                               # and RigStyles on every real RigBuilder blueprint
lune run tools/lune/dump_env.luau --all /tmp/env && node tools/preview/render.mjs --in <scene.json> --env /tmp/env/GoldenHall.json
```

Known approximations: the moon direction (assumed opposite the sun, tilted by latitude), the Atmosphere-to-fog
mapping, and bloom calibration in the preview renderer. Whether the default skybox darkens at night is assumed from
observed engine behaviour.
