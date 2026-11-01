# Roblox visual quality at maximum, 2025–2026: research report for a code-only Rojo/Luau project with no asset uploads

**Date:** 2026-11-01. **Engine baseline:** Studio/API 0.745.0.7451137.

**How this was sourced**
- `create.roblox.com` and `devforum.roblox.com` are blocked by this session's network allowlist (the hosts don't resolve). To fetch those pages directly, someone has to allow both hosts in the session's network settings.
- To work around that, I read Roblox's official docs from its own GitHub mirror, sparse-cloned from `Roblox/creator-docs` (commit c8f5276, 2026-10-29, `STUDIO_VERSION` 0.745.0.7451137).
- I also read the engine API dump, the Studio reflection metadata and the content manifest from the `MaximumADHD/Roblox-Client-Tracker` mirror. Built-in texture files were inspected directly.
- DevForum facts come only from search-result snippets. They are marked `[DF]` and are lower confidence.

## 0. Source key

Abbreviations used below:
- **CD** = `https://github.com/Roblox/creator-docs/blob/main/content/en-us/`. The same pages are at `https://create.roblox.com/docs/<same path, no extension>`.
- **CDR** = `https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/`

| Tag | Source |
|---|---|
| API | https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json (security, capabilities, defaults for new instances) |
| RM | https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml (Studio slider UIMinimum/UIMaximum; scripts may go past these unless the engine clamps) |
| MAN | https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/rbxManifest.txt (files shipped in `content/`) |
| TEX | https://github.com/MaximumADHD/Roblox-Client-Tracker/tree/roblox/textures |
| L | CDR `classes/Lighting.yaml` |
| LG | CD `environment/lighting.md` |
| ATM | CD `environment/atmosphere.md`, CDR `classes/Atmosphere.yaml` |
| PP | CD `environment/post-processing-effects.md`, CDR `classes/{PostEffect,BloomEffect,BlurEffect,ColorCorrectionEffect,ColorGradingEffect,DepthOfFieldEffect,SunRaysEffect}.yaml` |
| SKY | CD `environment/skybox.md`, CDR `classes/Sky.yaml` |
| CLD | CD `environment/clouds.md`, CDR `classes/Clouds.yaml` |
| MAT | CD `parts/materials.md`; MATE = CDR `enums/Material.yaml`; BP = CDR `classes/BasePart.yaml` |
| MV / SA | CDR `classes/MaterialVariant.yaml` / `classes/SurfaceAppearance.yaml` |
| LS | CD `effects/light-sources.md`, CDR `classes/{Light,PointLight,SpotLight,SurfaceLight}.yaml` |
| PEM / BM / TR | CDR `classes/ParticleEmitter.yaml` / `classes/Beam.yaml` / CD `effects/trails.md` |
| HL | CD `effects/highlighting.md`, CDR `classes/Highlight.yaml` |
| QL | CDR `enums/QualityLevel.yaml`, `enums/SavedQualitySetting.yaml`, `enums/GraphicsOptimizationMode.yaml` |
| UGS / DM | CDR `classes/UserGameSettings.yaml` / `classes/DataModel.yaml` (GraphicsQualityChangeRequest) |
| IMP / MPT | CD `performance-optimization/improve.md` / `performance-optimization/microprofiler/tag-table.md` |
| TER / CTM | CDR `classes/Terrain.yaml` / CD `parts/custom-terrain-materials.md` |
| EI | CDR `classes/{EditableImage,EditableMesh,AssetService}.yaml`, `datatypes/Content.yaml` |
| GEO | CDR `classes/GeometryService.yaml` |
| CAM / GS | CDR `classes/Camera.yaml` / `classes/GuiService.yaml` |
| TUT | CD `tutorials/use-case-tutorials/lighting/enhance-indoor-environments.md`, `.../enhance-outdoor-environments.md` |
| MCP / IMPT / MG / TG | CD `studio/mcp.md` / `studio/importer.md` / `studio/material-generator.md` / `studio/texture-generator.md` |
| AUD / PRIV | CD `audio/assets.md` / CD `projects/assets/privacy.md` |
| RDOM | https://github.com/rojo-rbx/rbx-dom/issues/665 (fetched) |
| R1127 | https://github.com/rojo-rbx/rojo/issues/1127 (fetched) |
| [DF] UL | https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512 |
| [DF] ELR | https://devforum.roblox.com/t/extended-light-ranges-doubling-the-limit-to-120/3954367 |
| [DF] HL255 | https://devforum.roblox.com/t/lights-camera-more-highlights/4061534 , https://devforum.roblox.com/t/weekly-recap-november-10-14-2025/4071175 |
| [DF] 4K | https://devforum.roblox.com/t/studio-beta-4k-texture-rendering/4144950 , https://devforum.roblox.com/t/4k-texture-rendering/4316229 |
| [DF] COMPAT | https://devforum.roblox.com/t/compatibility-lighting-becomes-retro-tone-mapping-sunset-migration/3128560 |
| [DF] TECH | https://devforum.roblox.com/t/why-are-technology-and-streaming-not-scriptable/1533655 , https://devforum.roblox.com/t/lightingstyle-is-not-a-valid-member-of-lighting/3908044 |
| [DF] FIBA / FIB3 | https://devforum.roblox.com/t/future-is-bright-on-android-is-fully-rolled-out-client-beta/3235808 , https://devforum.roblox.com/t/future-is-bright-phase-3-released/878634 |
| [DF] QLOBS | https://devforum.roblox.com/t/its-2023-please-give-us-discrete-graphics-options/2239284 |
| [DF] NEON | https://devforum.roblox.com/t/neon-parts-dont-glow-is-not-the-rendering/3276740 , https://devforum.roblox.com/t/glowing-textures-effect/1986111 |
| [DF] UISH | https://devforum.roblox.com/t/release-notes-for-715/4556577 |

---

## 1. Lighting

### 1.1 The lighting tech choice: Technology is replaced by LightingStyle and PrioritizeLightingQuality

**What changed**
- `Lighting.Technology` (enum `Technology`: Legacy (deprecated), Voxel, Compatibility, ShadowMap, Future, Unified (deprecated)) is **deprecated**. It is "non-scriptable and only modifiable in Studio", with read and write both `RobloxScriptSecurity` [L, API].
- It is replaced by two properties [L, API]:
  - `Lighting.LightingStyle`, enum `LightingStyle` = `Realistic` (0) or `Soft` (1).
  - `Lighting.PrioritizeLightingQuality` (bool).
- Timeline [DF UL]: Studio beta in Jan 2025, "fully live" in Jul 2025.

**Mapping from the old setting** [DF UL, L]

| Old Technology | LightingStyle | PrioritizeLightingQuality |
|---|---|---|
| Future | Realistic | true |
| ShadowMap | Soft | true (Soft with this enabled uses shadow maps, not voxels [L]) |
| Voxel | Soft | false |
| (new combination) | Realistic | false: currently Future lighting with a shorter shading distance [DF UL] |

- Compatibility was retired in 2024. It became Voxel plus `ColorGradingEffect.TonemapperPreset = Retro` [DF COMPAT, PP].

**What each setting does**
- `Realistic` gives "the most advanced and realistic lighting and shadows". `Soft` gives "a flat, retro-Roblox look" [LG].
- Local lights only get "precise shadows, illumination, and specular highlights" under Realistic [TUT].
- `PrioritizeLightingQuality = true`: as the quality level drops, the engine keeps advanced shadows and high-quality shaders at close range and gives up view distance first. `false` keeps view distance instead. Docs: "If lighting and shadows are very important to the artistic feel of your game, set this to `true`" [LG].

**Who can write it (API 0.745)**
- `LightingStyle` and `PrioritizeLightingQuality`: security None/None, capabilities Read = `Environment`, **Write = `PluginOrOpenCloud`** [API].
- So game Scripts and LocalScripts **can read but cannot write** them. They fail with "lacking capability PluginOrOpenCloud" [RDOM].
- Plugins, Studio-side tools and place files can set them.
- Earlier (2025) reports of "LightingStyle is not a valid member" and "you cannot edit these properties at runtime" are now outdated for reading [DF TECH, RDOM].
- **Practical consequence:** you cannot switch lighting style per area or per player at runtime. Pick one style per place.

**Rojo notes**
- `rojo build` serializes both properties correctly [RDOM].
- `rojo serve` (7.7.x) **does not apply them** through `$properties` on Lighting; this issue is still open as of 2026-09-23 [RDOM].
- A related "Cannot change Parent of type Lighting" error when syncing Lighting properties was closed as fixed in Jan 2026; the workaround was to disable the plugin's sync fallback [R1127].
- Recommendation: the owner sets these two properties once by hand in Studio (Explorer > Lighting > Properties). They persist in the place. Alternatively, ship via `rojo build`.

**Default caveats**
- The API default for a new Lighting instance is `Realistic` / `true` [API].
- An official tutorial instead says "Studio begins every game with Soft" [TUT].
- Community reports say migrated places came up as Realistic unexpectedly [DF UL].
- So always set both explicitly.

### 1.2 Lighting properties

Columns: API default for a new instance, Studio slider range from [RM], writable at runtime (all of these are, except where noted).

| Property | Type | Default | UI range | Notes |
|---|---|---|---|---|
| Ambient | Color3 | 0.5,0.5,0.5 (doc: place default 0,0,0) | – | Light colour in sky-occluded (indoor) areas. If GlobalShadows is false, Ambient applies everywhere [L]. |
| OutdoorAmbient | Color3 | 0.5,0.5,0.5 (doc 127,127,127) | – | Effectively clamped to at least Ambient per channel [L]. |
| Brightness | float | 1 | 0–10 | Strength of the sun/moon light [L]. |
| ExposureCompensation | float | 0 | slider −3..3; docs say range −5..5 | Applied before tonemapping. +1 doubles exposure. Brightens without washing out shadows, unlike Brightness (tutorial uses 0.5 indoors) [L, TUT]. |
| EnvironmentDiffuseScale | float | 0 | 0–1 | Ambient light from the sky/environment. When you raise it, lower Ambient/OutdoorAmbient [L]. |
| EnvironmentSpecularScale | float | 0 | 0–1 | Environment reflections; key for metals. With 0, metalness maps do nothing [L, MV]. |
| GlobalShadows | bool | false | – | The voxel note in the docs is 4×4×4-stud voxels; that applies to the Voxel path [L]. |
| ShadowSoftness | float | 0.5 (doc says 0.2) | 0–1 | 0 = hard, 1 = soft. Class doc: ShadowMap/Future only. Guide: only valid on Realistic [L, LG]. |
| ClockTime | float | 14 | 0–24 | Tagged **NotReplicated** [API]: set it on the client, or set `TimeOfDay` (string, replicates) on the server [L]. |
| GeographicLatitude | float | 41.73 | 0–360 | Moves the sun/moon path; does not change ClockTime [LG]. |
| ColorShift_Top / _Bottom | Color3 | 0,0,0 | – | Tint on sun-facing / away-facing surfaces. The Bottom tint is hard to see while GlobalShadows is on [L]. |
| FogColor / FogStart / FogEnd | – | – | – | **Hidden and unused when an Atmosphere exists** [L]. |
| ExtendLightRangeTo120 | RolloutState | – | – | NotScriptable and unused; light Range is **always clamped to 120** [L]. |
| ShadowColor, Outlines | – | – | – | Deprecated, no effect [L]. |

Methods [L]: `GetSunDirection()`, `GetMoonDirection()`, `SetMinutesAfterMidnight()`, `GetMinutesAfterMidnight()`. Event: `LightingChanged`.

**Official guidance for the most realistic PBR look** (stated for metalness maps) [MV, SA]: EnvironmentSpecularScale = 1, EnvironmentDiffuseScale = 1, and Ambient and OutdoorAmbient = (0,0,0).

**Official tutorial example values** [TUT]:
- Indoor: Ambient 83,70,57; ExposureCompensation 0.5; Atmosphere.Density 0.5; SunRays Intensity 0.023 and Spread 0.266; ColorCorrection Contrast 0.05 and Saturation 0.1; ClockTime 15.6 with GeographicLatitude 323.
- Outdoor: ClockTime 17; Ambient and OutdoorAmbient 156,136,176; Atmosphere Density 0.272, Haze 1, Color 85,78,54.

### 1.3 Recent changes to note (2025–2026)
- Unified Lighting is live (Jul 2025), and LightingStyle/PrioritizeLightingQuality became plugin-writable in v740 (~Sep 2026) [DF UL, RDOM].
- Light range limit doubled from 60 to 120 studs (around Sep 2025) [DF ELR, L].
- Highlight limit raised from 31 to 255 (Nov 2025) [DF HL255, HL].
- 4K texture rendering: Studio beta Jan 2026 (File > Beta Features), then live. It covers MeshPart, SurfaceAppearance, Texture, Decal and MaterialVariant, and base material textures were upgraded to 4K [DF 4K].
- `ColorGradingEffect` (tonemapper presets) was added as part of the 2024 Compatibility sunset [DF COMPAT, PP].
- Expanded Terrain: up to 62 custom terrain materials per place [CTM].
- `UIShadow` (UI drop/inset shadows) is documented [CDR `classes/UIShadow.yaml`]. As of release notes ~715 (spring 2026) it was still "pending" [DF UISH]. **Whether it is live is UNVERIFIED.**
- **No** built-in SSR, volumetric fog/lights, or user-controllable light attenuation exists. Attenuation is still a feature request (Oct 2026) [DF search]. The only post-effect classes in API 0.745 are Bloom, Blur, ColorCorrection, ColorGrading, DepthOfField and SunRays [API].

---

## 2. Post-processing, sky, atmosphere, clouds

**General rules** [PP]
- All of these are fully scriptable and can be created with `Instance.new` at runtime [API].
- Post effects work only when parented to `Lighting` (everyone sees them) or `Workspace.CurrentCamera` (that client only; useful for per-player blur and status tints).
- They do not affect GUI.
- Some "work differently or not at all" at low quality levels.

| Class | Properties: default (UI range) | Stacking and notes |
|---|---|---|
| Atmosphere (in Lighting) | Density 0.395 (0–1); Offset 0 (0–1); Color 200,170,108; Decay 92,60,14; Glare 0 (0–10); Haze 0 (0–10) [API, RM] | Glare needs Haze > 0. Decay needs Haze and Glare > 0. Density does not directly affect the skybox. Low Offset lets the sky "ghost" through geometry; high Offset reveals LOD popping [ATM]. (An "Atmosphere Height" slider appears in RM but not in the API; not available.) |
| Sky (in Lighting) | SkyboxBk/Dn/Ft/Lf/Rt/Up (default `rbxasset://textures/sky/sky512_*.tex`); `*Content` variants; SkyboxOrientation Vector3; CelestialBodiesShown true; SunAngularSize 21 (clamped 0–60); MoonAngularSize 11; SunTextureId `rbxasset://sky/sun.jpg`; MoonTextureId `rbxasset://sky/moon.jpg`; StarCount 3000 [API, SKY] | Size 0 hides only the sun or moon. SkyboxOrientation is cheap on all platforms and does not rotate celestial bodies or clouds [SKY]. |
| Clouds (**must be under Workspace.Terrain**) | Cover 0.5 (0–1); Density 0.7 (0–1); Color white; Enabled [API, RM, CLD] | Colour is heavily influenced by Lighting and Atmosphere. Driven by `Workspace.GlobalWind` [CLD]. |
| BloomEffect | Intensity 0.4 (0–1); Size 24 (0–56 px); Threshold 0.95 (0.8–4) [API, RM] | "Similar to applying Neon to everything". Multiple instances compose. Size 0 removes the bleed [PP]. |
| BlurEffect | Size 24 (0–56) | Only one applies; the largest Size wins [PP]. |
| ColorCorrectionEffect | Brightness 0 (−1..1); Contrast 0 (−1..1); Saturation 0 (−1..1; −1 = fully grey); TintColor (multiplicative) [API, RM, PP] | Multiple instances compose [PP]. |
| ColorGradingEffect | TonemapperPreset = Default (post-2019 vivid) or Retro (pre-2019) | **Lighting only**; only the most recently parented one applies [PP]. |
| DepthOfFieldEffect | FarIntensity 0.75 (0–1); NearIntensity 0.75 (0–1); FocusDistance 0.05 (0–200 studs); InFocusRadius 10 (0–50) [API, RM] | May render differently on low-end devices [PP]. |
| SunRaysEffect | Intensity 0.25 (0–1); Spread 1 (0–1; behaviour outside 0–1 is undefined) | "May not render on low-end devices" [PP]. |

### 2.1 Sky textures available without uploading [MAN]
- `rbxasset://textures/sky/sky512_{bk,dn,ft,lf,rt,up}.tex`: the default sky.
- `rbxasset://textures/sky/indoor512_{bk,dn,ft,lf,rt,up}.tex`: a second built-in cubemap. These live in `PlatformContent/pc/`, so **presence on mobile is UNVERIFIED**.
- `rbxasset://sky/sun.jpg` and `rbxasset://sky/moon.jpg`.
- For a pure black void, four options:
  - (a) `CelestialBodiesShown = false` plus a black, high-density, zero-Offset Atmosphere.
  - (b) Set all six faces to `rbxasset://textures/blackBkg_square.png` (24×24 dark grey-alpha PNG in client content [MAN, TEX]). **UNVERIFIED** that it renders as a solid black sky.
  - (c) Enclose the arena in black SmoothPlastic parts with `CastShadow = false`. This is the most robust.
  - (d) Open Use sky images from the Creator Store (see §8).

### 2.2 Presets (starting points)

These values are my own picks within the documented ranges. They are **not official**, so tune them in Studio at Editor Quality Level max and on a phone.

```lua
local rgb = Color3.fromRGB
return {
 GoldenHall = { -- Judgement-hall sunset through windows
  Lighting={ClockTime=17.4,GeographicLatitude=35,Brightness=3,ExposureCompensation=0.2,Ambient=rgb(55,40,28),OutdoorAmbient=rgb(150,115,80),
   ColorShift_Top=rgb(255,190,120),ColorShift_Bottom=rgb(30,18,8),EnvironmentDiffuseScale=0.6,EnvironmentSpecularScale=1,ShadowSoftness=0.12,GlobalShadows=true},
  Atmosphere={Density=0.32,Offset=0.2,Color=rgb(255,196,140),Decay=rgb(130,75,35),Glare=1.2,Haze=1.8},
  Sky={CelestialBodiesShown=true,SunAngularSize=14,StarCount=0},
  Bloom={Intensity=0.55,Size=32,Threshold=1.1}, SunRays={Intensity=0.12,Spread=0.55},
  CC={Brightness=0.02,Contrast=0.12,Saturation=0.12,TintColor=rgb(255,238,215)},
  DOF={FarIntensity=0.2,NearIntensity=0,FocusDistance=30,InFocusRadius=40}},
 DarkVoid = { -- boss arena; arena lit only by local lights
  Lighting={ClockTime=0,Brightness=0,ExposureCompensation=0,Ambient=rgb(8,8,12),OutdoorAmbient=rgb(8,8,12),ColorShift_Top=rgb(0,0,0),
   EnvironmentDiffuseScale=0,EnvironmentSpecularScale=0.4,ShadowSoftness=0.05,GlobalShadows=true},
  Atmosphere={Density=0.55,Offset=0,Color=rgb(0,0,0),Decay=rgb(0,0,0),Glare=0,Haze=0},
  Sky={CelestialBodiesShown=false,StarCount=0},
  Bloom={Intensity=1,Size=40,Threshold=0.9}, CC={Contrast=0.25,Saturation=-0.1}},
  -- key light: SpotLight top-down, Brightness 4, Range 60, Angle 60, Shadows=true
 BloodHell = {
  Lighting={ClockTime=18.1,GeographicLatitude=20,Brightness=2.2,ExposureCompensation=0.15,Ambient=rgb(50,8,6),OutdoorAmbient=rgb(110,25,18),
   ColorShift_Top=rgb(255,70,30),ColorShift_Bottom=rgb(60,0,0),EnvironmentDiffuseScale=0.5,EnvironmentSpecularScale=0.8,ShadowSoftness=0.25,GlobalShadows=true},
  Atmosphere={Density=0.45,Offset=0.1,Color=rgb(190,45,30),Decay=rgb(70,0,0),Glare=3,Haze=4},
  Sky={CelestialBodiesShown=true,SunAngularSize=28,StarCount=0}, Clouds={Cover=0.75,Density=0.55,Color=rgb(110,25,20)},
  Bloom={Intensity=0.8,Size=30,Threshold=1.0}, SunRays={Intensity=0.2,Spread=0.8},
  CC={Brightness=-0.02,Contrast=0.2,Saturation=0.3,TintColor=rgb(255,205,195)}},
 SnowNight = { -- Snowdin-like
  Lighting={ClockTime=1.5,GeographicLatitude=60,Brightness=1.5,ExposureCompensation=0.35,Ambient=rgb(22,28,42),OutdoorAmbient=rgb(65,80,115),
   ColorShift_Top=rgb(150,180,255),ColorShift_Bottom=rgb(10,15,30),EnvironmentDiffuseScale=1,EnvironmentSpecularScale=1,ShadowSoftness=0.35,GlobalShadows=true},
  Atmosphere={Density=0.38,Offset=0.12,Color=rgb(165,185,225),Decay=rgb(55,75,120),Glare=0.2,Haze=1.6},
  Sky={CelestialBodiesShown=true,StarCount=4000,MoonAngularSize=14}, Clouds={Cover=0.55,Density=0.25,Color=rgb(200,215,255)},
  Bloom={Intensity=0.45,Size=26,Threshold=1.15}, CC={Contrast=0.1,Saturation=-0.2,TintColor=rgb(225,235,255)},
  DOF={FarIntensity=0.3,NearIntensity=0,FocusDistance=40,InFocusRadius=50}, GlobalWind=Vector3.new(6,0,2)},
  -- warm window PointLights rgb(255,170,90), Brightness 2, Range 20, Shadows=true for contrast
 Mono = { -- monochrome, high contrast
  Lighting={ClockTime=13,Brightness=2.5,ExposureCompensation=0.3,Ambient=rgb(0,0,0),OutdoorAmbient=rgb(30,30,30),
   EnvironmentDiffuseScale=0,EnvironmentSpecularScale=0.5,ShadowSoftness=0,GlobalShadows=true},
  Atmosphere={Density=0.25,Offset=0,Color=rgb(255,255,255),Decay=rgb(0,0,0),Glare=0,Haze=0},
  Bloom={Intensity=0.6,Size=18,Threshold=0.95}, CC={Brightness=0.03,Contrast=0.6,Saturation=-1}},
}
```

- Switch presets with `TweenService` (Color3 and number properties tween fine).
- Apply on the client for per-player or per-area looks. Post effects under Camera are per-client [PP].

---

## 3. Materials

**Enum.Material** [API, MATE]
- Part-only: Plastic, SmoothPlastic, Neon, Wood, Marble, Granite, Pebble, CorrodedMetal, DiamondPlate, Foil, Metal, Fabric, Glass, ForceField, Cardboard, Carpet, CeramicTiles, ClayRoofTiles, RoofShingles, Leather, Plaster, Rubber.
- Part and terrain: WoodPlanks, Basalt, Slate, CrackedLava, Concrete, Limestone, Pavement, Brick, Cobblestone, Rock, Sandstone, Grass, LeafyGrass, Sand, Snow, Mud, Ground, Asphalt, Salt, Ice, Glacier.
- Terrain-only: Air, Water.

**Behaviour**
- Neon "appear[s] to glow" [CD `parts/index.md`]. It glows through bloom.
- Community reports [DF NEON]:
  - Default bloom applies even without a BloomEffect instance.
  - Darker Neon colours glow less; white glows most.
  - Neon glow shows through parts with Transparency ≥ ~0.62.
  - Treat these as UNVERIFIED.
- Neon (like particles) does **not** light its surroundings. Add a PointLight or SurfaceLight. The particle doc states this explicitly for LightEmission [PEM]; for Neon this is widely observed but UNVERIFIED in the docs.
- Glass on moderate settings adds some reflectiveness and perspective distortion, strongest on spheres. **Semi-transparent parts behind Glass are not visible.** Refraction is **not supported on mobile** [BP, MATE].
- ForceField: properly needs a MeshPart with wide UVs and a high-contrast TextureID [MATE]. On plain parts it still shows the animated forcefield look (observed; UNVERIFIED in docs).
- `BasePart.Reflectance` (0–1) reflects the sky. It is ignored by some materials and not rendered on fully transparent parts [BP, RM].
- `BasePart.CastShadow`: docs recommend leaving it on in general [BP]. However, **fully transparent parts still cast shadows**, because they are assumed to carry decals. Set `CastShadow = false` on invisible hitboxes [MPT].
- With EnvironmentSpecularScale = 1, Metal, Foil, DiamondPlate, Marble and Ice show the strongest environment reflections [L, TUT].
- Base material textures were upgraded to 4K in 2026 [DF 4K].

**MaterialService and MaterialVariant** [API, MV, MAT]
- A MaterialVariant only works as a descendant of MaterialService.
- It applies globally (set as an override; the override name properties are `NotScriptable`) or per part through `BasePart.MaterialVariant` (a string name).

What a script can and cannot set [API]:
- `Instance.new("MaterialVariant")` is allowed.
- **`BaseMaterial` has write = PluginSecurity.**
- **`ColorMap`, `NormalMap`, `RoughnessMap` and `MetalnessMap`, plus their `*Content` and `EmissiveMaskContent` versions, have read and write = PluginSecurity.**
- Script-writable: `StudsPerTile` (UI 0.1–20), `EmissiveStrength` (UI 0–40), `EmissiveTint`, `CustomPhysicalProperties`.
- `MaterialPattern` (Regular/Organic) is read-only to scripts.
- **So a runtime script cannot build a useful MaterialVariant.** Author it in Rojo model files instead; file serialization bypasses script security (UNVERIFIED per property, but standard Rojo behaviour).

Using Roblox's own texture IDs instead of uploading:
- Point the maps at Roblox's **own texture asset IDs** published in the materials guide [MAT].
- Images, Decals and Meshes are created **Open Use by default**, meaning usable by any game [PRIV].
- Examples (ColorMap / Normal / Metalness / Roughness):
  - Marble: 9439430596 / 9439431240 / – / 9439431383
  - Metal: 9920574687 / 9873295432 / 9873318201 / 9873318890
  - CorrodedMetal: 9920589327 / 9439548484 / 9439548749 / 9439556441
  - Concrete: 9920484153 / 9466554006 / – / 9466554186
  - Brick: 9920482813 / 9438453152 / – / 9438453413
  - Ice: 9920555943 / 9467301039 / – / 9467301203
  - Snow: 9920620284 / 9439632006 / – / 9439632145
  - CrackedLava: 9920484943 / 9438508790 / – / 9438509046
  - WoodPlanks: 9920626778 / 9439650689 / – / 9439658127
- The full current table plus the pre-2022 set is in [MAT].
- Plastic, SmoothPlastic, Neon and ForceField textures are bundled with the client and have no asset IDs [MAT].
- Use case: the same textures at a different StudsPerTile, or mixing one material's normal map with another's colour, for an exclusive look.

---

## 4. Lights [API, RM, LS, L, IMP]

**Properties**
- `Light` base class: `Brightness` (default 1, UI 0–40), `Color`, `Enabled`, `Shadows`.
- `PointLight.Range`.
- `SpotLight` and `SurfaceLight`: `Range`, `Angle` (0–180), `Face` (NormalId).
- Range is clamped to 120 studs [L, DF ELR].
- A light must be a **direct child** of a BasePart or an Attachment in Workspace. On an Attachment, a SurfaceLight behaves like a SpotLight, and `Face` picks the axis (−Z = front).
- Brightness does not extend Range [LS].

**Per lighting mode**
- Under Realistic (Future), local lights are per-pixel, give specular highlights, and cast shadows when `Shadows = true` [TUT].
- Under Soft, local lights do not produce shadows like the sun does [TUT].
- One community report says Soft with PrioritizeLightingQuality on needed GlobalShadows enabled for lights to show [DF UL].

**Quality and performance**
- Shadow maps and scene shadows are **not computed below quality level 4**. The voxel light grid is used at lower levels [MPT, IMP].
- Expense grows with the number and density of shadow-casting lights and small shadowed parts.
- Mitigations [IMP]:
  - Turn off `Light.Shadows` where not needed.
  - Limit Range and Angle.
  - Use fewer lights.
  - Disable lights outside the current room or range.
  - Turn off CastShadow on small or far parts and on moving objects.
- There is no documented hard limit on light count. UNVERIFIED.

**Mobile** [DF FIBA, DF FIB3]
- Future lighting on Android requires Vulkan.
- It reportedly appears at in-game graphics ≥ 4/10.
- Unsupported devices fall back to ShadowMap or Voxel.
- Treat details as UNVERIFIED.

---

## 5. Particles, beams, trails, Highlight, and glow without textures

### 5.1 Built-in textures (shipped in client `content/`) [MAN, TEX; dimensions and alpha inspected]

Particle sprites under `rbxasset://textures/particles/`. These are the textures used by the legacy Fire, Smoke, Sparkles, Explosion and ForceField effects, so they are present on all platforms (high confidence):

| Path | Size | Look |
|---|---|---|
| `sparkles_main.dds` | 128 | 8-point white star (ParticleEmitter default [API]) |
| `smoke_main.dds` | 128 | grey puffy cloud |
| `fire_main.dds` | 256 | noisy dark-yellow flame; use additive |
| `fire_sparks_main.dds` | 64 | faint specks |
| `explosion01_core_main.dds` | 256 | orange fire puff (coloured) |
| `explosion01_implosion_main.dds` | 256 | **soft white radial glow ball**; the best generic glow dot |
| `explosion01_shockwave_main.dds` | 256 | **soft ring**; for impact or shockwave rings |
| `explosion01_smoke_main.dds` | 256 | dark smoke puff |
| `forcefield_glow_main.dds` | 256 | very faint bluish disc |
| `forcefield_vortex_main.dds` | 128 | thin white ring with sparkles; magic circle |

- The `*_color` and `*_alpha` files (128×32) are colour/alpha ramps, not sprites.
- `SquareParticle.png` (256, hard square) is also there.

Other client textures under `rbxasset://textures/`. **Mobile availability is UNVERIFIED** (the manifest is from Windows Studio):
- `glow.png`: 256, soft starburst flare.
- `whiteCircle.png`: 512, hard disc.
- `smallWhiteCircle.png`.
- `gradient.png`: 512, white with alpha 0 → 255 → 0 vertically. Ideal for **soft-edged Beam and Trail strips**.
- `explosion.png`: 128.
- `sparkle.png`: 32.
- `Blank.png`.
- `blackBkg_square.png` / `blackBkg_round.png`.
- `noise.dds`.

Flipbooks:
- The engine message says "Particle texture must be 1024 by 1024 to use flipbooks". The docs say the size must be an exact multiple of the layout [API, PEM].
- **None of the built-ins are flipbook sheets.**
- An EditableImage (max 1024×1024) drawn as a grid might work as a flipbook. UNVERIFIED.

### 5.2 ParticleEmitter (key properties) [API, RM, PEM]
- `Brightness` (UI 0–10; scales emitted light when LightInfluence = 0).
- `LightEmission` (0 = normal blend, 1 = additive).
- `LightInfluence` (0–1). **The default is 0 via `Instance.new` and 1 when inserted in Studio.** Code-built emitters are unlit by default.
- `ZOffset` (studs toward the camera).
- `Squash` (NumberSequence, −3..3).
- `Drag` (half-life in seconds; negative values accelerate).
- `WindAffectsDrag` (follows GlobalWind; needs Drag > 0).
- `LockedToPart`, `VelocityInheritance` (0–1), `TimeScale` (0–1).
- `Orientation` (FacingCamera, FacingCameraWorldUp, VelocityParallel, VelocityPerpendicular).
- `Shape` (Box/Sphere/Cylinder/Disc), `ShapeStyle` (Volume/Surface), `ShapeInOut` (Outward/Inward/InAndOut), `ShapePartial` (0–1: cone, annulus, hemisphere).
- `FlipbookLayout` (None, Grid2x2, Grid4x4, Grid8x8, Custom + `FlipbookSizeX/Y`), `FlipbookMode` (Loop, OneShot, PingPong, Random), `FlipbookFramerate` (≤ 30), `FlipbookStartRandom`, `FlipbookBlendFrames`.
- `TextureContent` (Content; accepts URIs, and an EditableImage via `Content.fromObject` [EI]).
- `:Emit(n)` for bursts.
- Property changes on emitters are expensive. Decals, textures and particles batch poorly [IMP].
- Particle caps scale with quality level [QL].

### 5.3 Beam and Trail [API, RM, BM, TR]
- **Beam with an empty `Texture` renders as a solid colour strip.** No asset is needed.
- Beam properties:
  - `Width0/1`, `CurveSize0/1` (UI −10..10, Bezier), `Segments` (default 10; curves need enough of them).
  - `FaceCamera`, `TextureMode` (Stretch/Wrap/Static), `TextureLength` (0–5), `TextureSpeed` (−1..1).
  - `LightEmission` / `LightInfluence` (0–1), `Brightness` (0–10), `ZOffset` (−1..1).
  - `Transparency` and `Color` sequences run **along the length**. Use `gradient.png` for a soft fade **across the width**.
- Trail properties: `Lifetime` (0–20), `WidthScale` (NumberSequence), `MinLength`/`MaxLength`, `FaceCamera`, `Brightness` (0–10), `LightEmission`.
- Trail fidelity drops at low quality [QL].

### 5.4 Highlight [API, HL, DF HL255]
- Properties: `FillColor`, `FillTransparency`, `OutlineColor`, `OutlineTransparency`, `DepthMode` (AlwaysOnTop/Occluded), `Adornee`, `Enabled`.
- Outline thickness is **not** adjustable (`LineThickness` is hidden, RobloxScriptSecurity).
- Up to **255** active on a client (raised from 31 in Nov 2025). Disabled ones still take a slot; extras are silently ignored.
- Performance:
  - The first Highlight costs up to ~1 ms GPU on mobile; more on mobile when it covers more of the screen.
  - Add/remove triggers a geometry rebuild, so prefer toggling properties.
  - Don't nest highlighted objects inside other highlighted objects.
  - Low-end devices render them more pixelated.

### 5.5 How glow is made without textures (techniques)
1. **Neon part plus Bloom.** BloomEffect Threshold sits near 0.8–1.0 for a strong glow, Intensity 0.5–1, Size 24–56 [PP, RM]. Neon colours should be bright; dark Neon barely glows [DF NEON].
2. **HDR additive sprites.** On particles, beams and trails, combine `LightEmission = 1`, `LightInfluence = 0` and `Brightness` 2–10, so they exceed the bloom threshold. The ≥1 → bloom interaction is observed behaviour, UNVERIFIED in the docs [PEM, BM].
3. **Layered shells.** Stack a solid Neon core, a slightly larger transparent (0.6–0.8) Neon shell, and a larger additive implosion-ball particle (`explosion01_implosion_main.dds`, LockedToPart, Rate 0 with `:Emit`).
4. **Highlight as glow or rim.** Use FillTransparency 0.7–0.9 with a bright FillColor and OutlineColor. Use AlwaysOnTop for "visible through walls" auras.
5. **Real light spill.** Put a PointLight (Shadows off for cheap fills) under any glowing object. Neon and particles do not emit light.
6. **Emissive UI in the world.** SurfaceGui or BillboardGui with `LightInfluence = 0` and `Brightness` 1–1000 (SurfaceGui documented range 0–1000) [CDR `classes/SurfaceGui.yaml`].
7. Hack to avoid: `SpecialMesh.VertexColor` above 1 reportedly glows, but it is called "very broken" and patchable [DF NEON].

---

## 6. Quality levels: mobile looks good, PC looks maximal

**What scales or disappears as quality drops** [QL, MPT, IMP, PP, MATE, HL]
- Render distance, shading quality, geometry and texture resolution, particle limits, trail fidelity and post-effect quality all scale down. Some post effects are fully disabled at low levels.
- Shadows (sun and lights) are off below level 4. The voxel light grid replaces them.
- SunRays may not render on low-end devices. DepthOfField and Blur may differ.
- Glass refraction is off on mobile.
- Highlights get more pixelated.
- Specific per-level effects "are platform- and device-specific and can not be relied upon" [QL].
- Community observations [DF QLOBS] (UNVERIFIED): ambient occlusion only at high levels (~8–10 of 10), and water and glass degrade below ~8.

**What a script can read** [UGS, DM, QL]
- Readable: `UserSettings():GetService("UserGameSettings").SavedQualityLevel` (enum `SavedQualitySetting`: `Automatic`, `QualityLevel1`..`QualityLevel10`).
  - Read it on the **client**. It has a change signal through `GetPropertyChangedSignal`.
  - When the player uses Automatic you learn nothing: "There is currently no way for developers to reliably get the current graphics quality level".
- Not readable: `UserGameSettings.GraphicsQualityLevel`, `MaxQualityEnabled` and `GraphicsOptimizationMode` are RobloxScriptSecurity.
- `GraphicsOptimizationMode` (new) only applies to manual quality: Performance = levels 1–3, Balanced = 4–7 (default), Quality = 8–10.
- `DataModel.GraphicsQualityChangeRequest(betterQuality)` fires only for F10 / Shift+F10.
- The internal `Enum.QualityLevel` scale is 1–21. `RenderSettings.QualityLevel` is Studio/plugin-only.

**Recommended strategy**
1. Keep Realistic with PrioritizeLightingQuality = true. The engine degrades gracefully, favouring near-field quality.
2. **Never make gameplay readability depend on shadows, DOF, SunRays or Glass.** Attacks such as bones and blasters should read through silhouette, Neon, Highlight and colour.
3. A client-side "VFX budget" module:
   - Take SavedQualityLevel as a hint, plus your own frame-time measurement through RunService.
   - When the hint or frame time says "low": scale particle `Rate` and `:Emit` counts, disable DOF and SunRays, drop Bloom Size, turn off `Light.Shadows` on non-key lights, and cap simultaneous Highlights.
   - Optionally add an in-game "Effects: Low / High" toggle.
4. Per-player effects go under `Workspace.CurrentCamera` [PP].

**Workspace and streaming props** [API; CDR enums]
- `StreamingEnabled` is set at edit time. `StreamingTargetRadius` and `StreamingMinRadius` are NotScriptable.
- For a small arena game, consider `StreamingEnabled = false` to avoid VFX models streaming out. That is a judgement call, not documented guidance.
- `Model.ModelStreamingMode`: Default / Atomic / Persistent / PersistentPerPlayer / Nonatomic.
- `Model.LevelOfDetail`: Automatic / StreamingMesh / Disabled / SLIM. It needs streaming, and its write capability is PluginOrOpenCloud, so set it in Studio or Rojo [API, CDR `enums/ModelLevelOfDetail.yaml`].
- `Workspace.MeshPartHeadsAndAccessories` (NotScriptable; Default means Enabled).
- New in the dump: `Player.FrustumStreaming`, plus `Workspace.PredictiveStreamingMode` and `Workspace.MeshStreamingAndImprovedLods` (both NotScriptable).
- `Workspace.GlobalWind` (Vector3, scriptable) drives clouds, grass and wind-affected particles.

**Terrain** [TER, CTM]
- `Decoration` (animated grass on Grass only) and `GrassLength` (0.1–1) are **NotScriptable**; set them in Studio or the project file.
- Water props are scriptable: `WaterColor`, `WaterReflectance` (0–1), `WaterTransparency` (0–1), `WaterWaveSize` (0–1), `WaterWaveSpeed` (0–100).
- `Terrain:SetMaterialColor()` works at runtime.
- `Workspace.ExpandedTerrain = Enabled` (Studio, place restart) enables up to 62 custom terrain materials.

---

## 7. Other showcase-level techniques (all upload-free)

**Runtime-generated textures and meshes** [EI]
- APIs:
  - `AssetService:CreateEditableImage({Size=Vector2})`: default 512², **max 1024×1024**.
  - `AssetService:CreateEditableMesh()`, then `AssetService:CreateMeshPartAsync(Content.fromObject(em))`.
  - `AssetService:CreateSurfaceAppearanceAsync({ColorMap, NormalMap, RoughnessMap, MetalnessMap, EmissiveMask})`, which takes EditableImage content only.
  - `AssetService:CreateDecalAsync({TextureContent, NormalMapContent, MetalnessMapContent, RoughnessMapContent})`.
- These give **procedural PBR without any upload**. EditableImage can also feed ImageLabel, MeshPart.TextureContent and particle textures.
- Requirements:
  - Toggle **"Allow Mesh / Image APIs"**. In Studio this is Experience Settings > Security. In the Creator Dashboard it is Configure > Settings > "Enable Mesh / Image APIs".
  - **Create them on the client.** Content.Object values do not replicate; a server-side editable on a replicated instance shows a magenta/cyan checkerboard.
- Limits: strict client memory budgets (creation returns nil when the budget is exhausted), and only one displayed EditableImage updates per frame.
- Use case: a smooth Sans skull or jacket built as an EditableMesh instead of an oval Part.

**Runtime CSG and sweeps** [GEO]
- `GeometryService:UnionAsync` / `SubtractAsync` / `IntersectAsync`.
- `SweepPartAsync`: a part swept through CFrames, which gives curved bones, scythe swooshes and blaster jaws.
- `FragmentAsync`: Voronoi shattering.
- Capability is CSG. Results are unparented, like `Clone()`.

**SurfaceAppearance** [SA, API]
- MeshPart only. The maps are PluginSecurity, so in Studio they need asset IDs (owner-uploaded or Open Use).
- At runtime, use `CreateSurfaceAppearanceAsync` with EditableImages.
- `Color`, `EmissiveStrength` (UI 0–40) and `EmissiveTint` are script-writable.

**Decal and Texture**
- `Texture` can be any `rbxasset://` path or Open Use ID.
- Script-writable: `Color3`, `Transparency`, `UVOffset`/`UVScale`, `ZIndex`, `EmissiveStrength`/`EmissiveTint`. The PBR map properties are PluginSecurity [API].
- Use case: `gradient.png` decals for fake gradients or ambient occlusion on walls.

**SpecialMesh**: `MeshType` Sphere/Cylinder/Head/Wedge/Brick/FileMesh; `MeshId`, `TextureId`, `Scale`, `Offset` and `VertexColor` are all script-writable [API].

**Camera** [CAM, GS, API]
- `FieldOfView` is clamped 1–120, default 70. `FieldOfViewMode`: Vertical / Diagonal / MaxAxis.
- Typical uses: punch-in (lower FOV) on big hits, FOV +5–10 on dashes.
- Screen shake best practice (not an official spec):
  - Use `RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, fn)` (Camera = 200).
  - Multiply `camera.CFrame` by a small rotational offset driven by `math.noise`, using a decaying "trauma" value.
  - It is non-cumulative because the camera script resets the CFrame each frame.
  - Scale it down or disable it when **`GuiService.ReducedMotionEnabled`** is true; this is readable and maps to the player's "Reduce Motion" setting.

**UI polish**
- Available: UIGradient, UIStroke, UICorner, CanvasGroup (its memory budget scales with quality level [CDR `classes/CanvasGroup.yaml`]), ViewportFrame (a Sky inside acts as a reflection cubemap [SKY]), and `rbxasset://textures/glow.png` / `gradient.png` for menu glows.
- `UIShadow` (BlurRadius, Spread, Inset, Mode = Shape/Text) is documented; whether it is live is UNVERIFIED [DF UISH].

---

## 8. What the owner can do in Studio to raise quality further

1. **Lighting style.** Explorer > Lighting > Properties: set `LightingStyle = Realistic` and `PrioritizeLightingQuality = true`. Scripts cannot do this, and Rojo serve doesn't apply it [RDOM].
2. **Preview at max quality.** Studio Settings (Alt+S) > Rendering > **Editor Quality Level** = highest. Also toggle **Show Light Guides** [PP, LS].
3. **Allow editables.** Experience Settings > Security > **Allow Mesh / Image APIs**, or Creator Dashboard > Configure > Settings > Enable Mesh / Image APIs [EI].
4. **4K textures.** File > Beta Features, while it is in beta; it is reportedly live now [DF 4K].
5. **Import real meshes.** **File > Import** (.fbx, .gltf/.glb, .obj; PBR textures, rigs and animations), or bulk import through the **Asset Manager** (Window menu or Home tab) [IMPT, CD `projects/assets/manager.md`]. This enables proper Sans and Gaster Blaster models with SurfaceAppearance, skyboxes (6 images), and 1024² particle flipbooks.
6. **AI materials, no upload needed.**
   - Window > 3D > **Material Generator** (or Generate in the Material widget), then Save & Apply Variant [MG].
   - Window > 3D > **Material** (Material Manager): variants, overrides, terrain details [MAT].
   - Select a mesh, then Model tab > **Texture** (AI Texture Generator) [TG].
7. **Terrain.** Workspace > Properties > **Expanded Terrain = Enabled** (restart), then Window > 3D > Terrain Materials Manager. Also enable Terrain `Decoration` [CTM, TER].
8. **Music and SFX.** Toolbox > **Creator Store** tab > category **Audio**; right-click > **Copy Asset ID**. The store has more than 100k free professional tracks and effects, Roblox-licensed partner audio included.
   - Own uploads must be under 20 MB and 7 min, ≤ 48 kHz.
   - Upload cap: 100 per 30 days unverified, 2,000 per 30 days ID-verified [AUD].
9. **Let Claude drive Studio directly** (this is where the PC matters).
   - Studio > **Assistant > … > Manage MCP Servers > "Enable Studio as MCP server"**. Quick connect supports Claude Code and Claude Desktop [MCP].
   - Tools include `execute_luau`, `screen_capture` (visual QA of lighting and VFX), `generate_mesh`, `generate_material`, `generate_procedural_model`, `upload_image`, `insert_asset` and `start_stop_play`.
   - Without it, the workflow is Rojo build → the owner opens the .rbxl, and no screenshots come back.
10. **Testing.** Device Simulator (beta) for screen layouts; real phone tests for Future/shadow fallback, since mobile behaviour is device-specific [CD `studio/device-simulator.md`, QL].

---

## 9. Explicitly UNVERIFIED or low-confidence items
- Whether the `PlatformContent/pc` sky files (`indoor512_*`) and the non-particle `content/textures/*.png` files exist on mobile clients.
- Using `blackBkg_square.png` as a solid black sky.
- Neon above-threshold and HDR sprite bloom specifics; neon glow at Transparency ≥ 0.62; default bloom without a BloomEffect (all DevForum observations).
- Per-quality-level feature thresholds beyond "shadows off below 4" [MPT]; the Android Future cutoff of QL ≥ 4.
- Whether `UIShadow` is live.
- Whether EditableImage works as a flipbook texture.
- Rojo `.model.json` enum and content serialization for MaterialVariant maps (expected to work, untested here).
- The `rojo serve` status of LightingStyle and PrioritizeLightingQuality after rbx-dom #665 (open as of 2026-09-23).
- The new-place default LightingStyle (the API says Realistic; the tutorial says Soft).

Local working copies used (scratch): docs clone at `/tmp/claude-0/-home-user-game/f493f3e8-eb29-53b3-b677-a9d1a3d2561e/scratchpad/dl/creator-docs`, API dump and ReflectionMetadata at `/tmp/claude-0/-home-user-game/f493f3e8-eb29-53b3-b677-a9d1a3d2561e/scratchpad/dl2/`, client tracker (textures, manifest) at `/tmp/claude-0/-home-user-game/f493f3e8-eb29-53b3-b677-a9d1a3d2561e/scratchpad/dl3/tracker`, and a contact sheet of the built-in particle textures at `/tmp/claude-0/-home-user-game/f493f3e8-eb29-53b3-b677-a9d1a3d2561e/scratchpad/sheet.png`.