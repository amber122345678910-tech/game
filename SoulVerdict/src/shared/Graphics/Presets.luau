--!strict
-- Graphics presets: Lighting + Atmosphere + Sky + post effects + Clouds + GlobalWind + ambient weather.
-- Lune-safe DATA module (no services). Applied by Graphics/Apply.luau, driven by Controllers/GraphicsController.
--
-- Rules for preset data (enforced by tools/lune/tests/graphics.spec.luau):
--   * Only script-writable properties. Lighting.LightingStyle / PrioritizeLightingQuality / Technology are
--     Studio/plugin-only (capability PluginOrOpenCloud) and are set once in the place file by the owner.
--   * Sky uses the built-in default skybox only (no asset ids): CelestialBodiesShown, StarCount (0..5000),
--     SunAngularSize / MoonAngularSize (0..60; 0 hides that body).
--   * Clouds are applied under Workspace.Terrain; GlobalWind goes to Workspace.GlobalWind.
--   * An absent effect section means "that effect is off" (see Apply.Normalize).
--   * Ambient.Particles is a weather id from client VFX/Ambient.luau (Snow, Blizzard, Embers, Ash, Dust,
--     Fireflies, Spores, VoidMotes, RiftMotes, Glimmer, Rain); Ambient.Density multiplies its base rate.
--   * A map preset "<Id>" may have a final-phase variant "<Id>Final" (used automatically in FinalPhase).
--
-- API:
--   Presets.Get(id) -> GraphicsPreset?            Presets.All() -> {GraphicsPreset} (display order)
--   Presets.Ids() -> {string}                      Presets.Has(id) -> boolean
--   Presets.FinalOf(id) -> string?                 "<id>Final" if it exists (a final preset maps to itself)
--   Presets.ForMap(mapId) -> (string?, string?)    default + final preset for a map id (fallback only;
--                                                  the authoritative ids come from Maps/Registry MapDef)
--   Presets.Kind(id) -> "Map"|"Style"|"Special"|"Final"
--   Presets.Resolve(state) -> (presetId, source)   which preset is active (see ResolveState below)
--   Presets.MAP_DEFAULT = "MapDefault"             settings value meaning "follow the map"
--   Presets.Default = "Lobby", Presets.Fallback = "Performance"

local Types = require(script.Parent.Parent.Types)

type GraphicsPreset = Types.GraphicsPreset

export type OverrideEntry = {
	Key: string,
	PresetId: string,
	Priority: number,
	Order: number, -- push order; the newest wins a priority tie
}

export type ResolveState = {
	MapPreset: string?, -- ReplicatedStorage.RoundState "GraphicsPreset"
	FinalPreset: string?, -- optional explicit final id (RoundState "FinalPreset" if the server sets it)
	MapId: string?, -- ReplicatedStorage.RoundState "MapId" (fallback when GraphicsPreset is missing)
	FinalPhase: boolean?,
	UserOverride: string?, -- player setting; nil / "MapDefault" = follow the map
	Overrides: { OverrideEntry }?, -- pushed overrides (Eclipse ult, Style Lab, cinematics)
}

local rgb = Color3.fromRGB
local v3 = Vector3.new

local Presets = {}

Presets.MAP_DEFAULT = "MapDefault"
Presets.Default = "Lobby"
Presets.Fallback = "Performance"

local LIST: { GraphicsPreset } = {
	----------------------------------------------------------------------------------------------- Lobby
	{
		Id = "Lobby",
		Name = { en = "Save Room", ru = "Комната сохранения" },
		Desc = {
			en = "Cozy save-room warmth: soft afternoon light, gentle haze and a few drifting motes.",
			ru = "Уютное тепло комнаты сохранения: мягкий дневной свет, лёгкая дымка и редкие пылинки.",
		},
		Lighting = {
			ClockTime = 15.6,
			GeographicLatitude = 38,
			Brightness = 2.4,
			ExposureCompensation = 0.2,
			Ambient = rgb(96, 80, 64),
			OutdoorAmbient = rgb(150, 132, 112),
			ColorShift_Top = rgb(255, 222, 180),
			ColorShift_Bottom = rgb(40, 30, 20),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.6,
			ShadowSoftness = 0.3,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.26,
			Offset = 0.3,
			Color = rgb(255, 222, 180),
			Decay = rgb(130, 100, 70),
			Glare = 0.5,
			Haze = 1.0,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 0, SunAngularSize = 16, MoonAngularSize = 11 },
		Clouds = { Cover = 0.4, Density = 0.35, Color = rgb(255, 240, 225) },
		Bloom = { Intensity = 0.45, Size = 28, Threshold = 1.1 },
		ColorCorrection = { Brightness = 0.02, Contrast = 0.06, Saturation = 0.1, TintColor = rgb(255, 246, 234) },
		SunRays = { Intensity = 0.06, Spread = 0.4 },
		DepthOfField = { FarIntensity = 0.15, NearIntensity = 0, FocusDistance = 40, InFocusRadius = 50 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(1.5, 0, 0.5),
		Ambient = { Particles = "Dust", Density = 0.6 },
	},
	------------------------------------------------------------------------------------------ GoldenHall
	{
		Id = "GoldenHall",
		Name = { en = "Golden Hall", ru = "Золотой зал" },
		Desc = {
			en = "Judgement-hall golden hour: amber light shafts through tall windows, deep warm shadows, floating dust.",
			ru = "Золотой час в Зале суда: янтарные лучи сквозь высокие окна, глубокие тёплые тени, парящая пыль.",
		},
		Lighting = {
			ClockTime = 17.35, -- sun ~9.5° above the west (-X) horizon: long beams through windows
			GeographicLatitude = 30,
			Brightness = 3.2,
			ExposureCompensation = 0.15,
			Ambient = rgb(62, 44, 30),
			OutdoorAmbient = rgb(138, 108, 82),
			ColorShift_Top = rgb(255, 196, 120),
			ColorShift_Bottom = rgb(40, 26, 14),
			EnvironmentDiffuseScale = 0.45,
			EnvironmentSpecularScale = 0.85,
			ShadowSoftness = 0.12,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.3,
			Offset = 0.25,
			Color = rgb(255, 200, 140),
			Decay = rgb(150, 85, 40),
			Glare = 1.4,
			Haze = 1.9,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 0, SunAngularSize = 12, MoonAngularSize = 11 },
		Clouds = { Cover = 0.35, Density = 0.4, Color = rgb(255, 214, 170) },
		Bloom = { Intensity = 0.6, Size = 30, Threshold = 1.05 },
		ColorCorrection = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.14, TintColor = rgb(255, 240, 220) },
		SunRays = { Intensity = 0.14, Spread = 0.6 },
		DepthOfField = { FarIntensity = 0.18, NearIntensity = 0, FocusDistance = 32, InFocusRadius = 40 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(2, 0, 1),
		Ambient = { Particles = "Dust", Density = 1.0 },
	},
	{
		Id = "GoldenHallFinal",
		Name = { en = "Golden Hall: Last Light", ru = "Золотой зал: последний свет" },
		Desc = {
			en = "The sun touches the horizon: darker, desaturated gold with cold cyan shadows and blazing highlights.",
			ru = "Солнце касается горизонта: темнее, приглушённое золото, холодные бирюзовые тени и яркие блики.",
		},
		Lighting = {
			ClockTime = 17.85, -- sun ~2° up: razor-long shadows
			GeographicLatitude = 30,
			Brightness = 2.2,
			ExposureCompensation = -0.1,
			Ambient = rgb(20, 30, 42), -- cyan-teal shadows (accent 1)
			OutdoorAmbient = rgb(70, 80, 92),
			ColorShift_Top = rgb(255, 214, 96), -- yellow light (accent 2)
			ColorShift_Bottom = rgb(10, 40, 55),
			EnvironmentDiffuseScale = 0.3,
			EnvironmentSpecularScale = 0.9,
			ShadowSoftness = 0.08,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.38,
			Offset = 0.15,
			Color = rgb(200, 190, 160),
			Decay = rgb(40, 90, 110),
			Glare = 2.2,
			Haze = 2.6,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 600, SunAngularSize = 16, MoonAngularSize = 11 },
		Clouds = { Cover = 0.45, Density = 0.5, Color = rgb(150, 160, 175) },
		Bloom = { Intensity = 0.7, Size = 30, Threshold = 0.95 },
		ColorCorrection = { Brightness = -0.02, Contrast = 0.24, Saturation = -0.28, TintColor = rgb(232, 244, 255) },
		SunRays = { Intensity = 0.2, Spread = 0.7 },
		DepthOfField = { FarIntensity = 0.22, NearIntensity = 0, FocusDistance = 28, InFocusRadius = 34 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(4, 0, 2),
		Ambient = { Particles = "Dust", Density = 1.4 },
	},
	------------------------------------------------------------------------------------------- SnowNight
	{
		Id = "SnowNight",
		Name = { en = "Snow Night", ru = "Снежная ночь" },
		Desc = {
			en = "Snowdin-like night: cold blue moonlight, starry sky, soft snowfall; warm windows glow in contrast.",
			ru = "Ночь как в Сноудине: холодный голубой лунный свет, звёзды, мягкий снегопад; тёплые окна светятся контрастом.",
		},
		Lighting = {
			ClockTime = 21.2, -- moon fairly low: long blue moon shadows
			GeographicLatitude = 52,
			Brightness = 1.8,
			ExposureCompensation = 0.45,
			Ambient = rgb(24, 30, 48),
			OutdoorAmbient = rgb(78, 96, 140),
			ColorShift_Top = rgb(150, 182, 255),
			ColorShift_Bottom = rgb(12, 18, 34),
			EnvironmentDiffuseScale = 0.7,
			EnvironmentSpecularScale = 0.8,
			ShadowSoftness = 0.4,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.4,
			Offset = 0.1,
			Color = rgb(150, 172, 215),
			Decay = rgb(52, 70, 115),
			Glare = 0.15,
			Haze = 1.7,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 4500, SunAngularSize = 21, MoonAngularSize = 16 },
		Clouds = { Cover = 0.5, Density = 0.3, Color = rgb(190, 205, 240) },
		Bloom = { Intensity = 0.55, Size = 28, Threshold = 1.05 },
		ColorCorrection = { Brightness = 0, Contrast = 0.1, Saturation = -0.05, TintColor = rgb(236, 242, 255) },
		DepthOfField = { FarIntensity = 0.25, NearIntensity = 0, FocusDistance = 36, InFocusRadius = 46 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(7, 0, 2.5),
		Ambient = { Particles = "Snow", Density = 1.0 },
	},
	{
		Id = "SnowNightFinal",
		Name = { en = "Snow Night: Whiteout", ru = "Снежная ночь: белая мгла" },
		Desc = {
			en = "Whiteout: the blizzard closes in, the wind howls, the world turns colder and darker.",
			ru = "Белая мгла: метель сгущается, ветер воет, мир становится холоднее и темнее.",
		},
		Lighting = {
			ClockTime = 23,
			GeographicLatitude = 58,
			Brightness = 1.2,
			ExposureCompensation = 0.3,
			Ambient = rgb(14, 22, 40),
			OutdoorAmbient = rgb(56, 74, 118),
			ColorShift_Top = rgb(120, 170, 255),
			ColorShift_Bottom = rgb(6, 14, 32),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.8,
			ShadowSoftness = 0.55,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.55,
			Offset = 0.04,
			Color = rgb(135, 160, 205),
			Decay = rgb(35, 55, 105),
			Glare = 0,
			Haze = 3.2,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 1500, SunAngularSize = 21, MoonAngularSize = 13 },
		Clouds = { Cover = 0.85, Density = 0.65, Color = rgb(150, 165, 200) },
		Bloom = { Intensity = 0.6, Size = 28, Threshold = 1 },
		ColorCorrection = { Brightness = -0.02, Contrast = 0.18, Saturation = -0.25, TintColor = rgb(218, 232, 255) },
		DepthOfField = { FarIntensity = 0.32, NearIntensity = 0, FocusDistance = 30, InFocusRadius = 34 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(18, 0, 7),
		Ambient = { Particles = "Blizzard", Density = 1.0 },
	},
	--------------------------------------------------------------------------------------- WaterfallGlow
	{
		Id = "WaterfallGlow",
		Name = { en = "Waterfall Glow", ru = "Сияние водопадов" },
		Desc = {
			en = "Dark cavern lit by bioluminescence: cyan glow, teal mist over water, a sparkling crystal ceiling.",
			ru = "Тёмная пещера в биолюминесценции: бирюзовое свечение, туман над водой, мерцающий кристальный свод.",
		},
		Lighting = {
			ClockTime = 23.5, -- dim moonlight through cave openings only
			GeographicLatitude = 41.73,
			Brightness = 0.6,
			ExposureCompensation = 0.55,
			Ambient = rgb(16, 44, 58), -- most of a cavern is "indoor": this colour carries the mood
			OutdoorAmbient = rgb(34, 74, 96),
			ColorShift_Top = rgb(90, 200, 255),
			ColorShift_Bottom = rgb(6, 30, 40),
			EnvironmentDiffuseScale = 0.25,
			EnvironmentSpecularScale = 0.9, -- wet rock and water sheen
			ShadowSoftness = 0.5,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.46,
			Offset = 0,
			Color = rgb(40, 110, 140),
			Decay = rgb(10, 40, 70),
			Glare = 0,
			Haze = 2.4,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 5000, SunAngularSize = 0, MoonAngularSize = 0 },
		Bloom = { Intensity = 0.65, Size = 34, Threshold = 0.92 },
		ColorCorrection = { Brightness = 0.01, Contrast = 0.14, Saturation = 0.18, TintColor = rgb(225, 248, 255) },
		DepthOfField = { FarIntensity = 0.3, NearIntensity = 0, FocusDistance = 30, InFocusRadius = 36 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(1, 0, 0.5),
		Ambient = { Particles = "Fireflies", Density = 1.0 },
	},
	{
		Id = "WaterfallGlowFinal",
		Name = { en = "Waterfall Glow: Echo Bloom", ru = "Сияние водопадов: цветение эха" },
		Desc = {
			en = "The echoes bloom violet: deeper dark, magenta-cyan glow and rising spores.",
			ru = "Эхо расцветает фиолетовым: глубже тьма, пурпурно-бирюзовое свечение и поднимающиеся споры.",
		},
		Lighting = {
			ClockTime = 0,
			GeographicLatitude = 41.73,
			Brightness = 0.4,
			ExposureCompensation = 0.35,
			Ambient = rgb(30, 16, 52),
			OutdoorAmbient = rgb(46, 30, 80),
			ColorShift_Top = rgb(190, 120, 255),
			ColorShift_Bottom = rgb(10, 40, 50),
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 1,
			ShadowSoftness = 0.4,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.52,
			Offset = 0,
			Color = rgb(70, 40, 120),
			Decay = rgb(10, 60, 80),
			Glare = 0,
			Haze = 3,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 5000, SunAngularSize = 0, MoonAngularSize = 0 },
		Bloom = { Intensity = 0.72, Size = 36, Threshold = 0.9 },
		ColorCorrection = { Brightness = 0, Contrast = 0.22, Saturation = 0.25, TintColor = rgb(240, 225, 255) },
		DepthOfField = { FarIntensity = 0.34, NearIntensity = 0, FocusDistance = 26, InFocusRadius = 32 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(2, 0, 1),
		Ambient = { Particles = "Spores", Density = 1.2 },
	},
	------------------------------------------------------------------------------------------- VoidAbyss
	{
		Id = "VoidAbyss",
		Name = { en = "Void Abyss", ru = "Бездна пустоты" },
		Desc = {
			en = "A dream rift in an endless deep-blue void: drifting stars, cold rim light, blazing neon cracks.",
			ru = "Разлом сна в бесконечной синей пустоте: дрейфующие звёзды, холодный контровой свет, сияющие неоновые трещины.",
		},
		Lighting = {
			ClockTime = 20.5, -- moon ~37° above the east (+X): cold side/rim light
			GeographicLatitude = 10,
			Brightness = 1,
			ExposureCompensation = 0.4,
			Ambient = rgb(10, 14, 32),
			OutdoorAmbient = rgb(24, 32, 70),
			ColorShift_Top = rgb(100, 150, 255),
			ColorShift_Bottom = rgb(20, 0, 40),
			EnvironmentDiffuseScale = 0.15,
			EnvironmentSpecularScale = 0.6,
			ShadowSoftness = 0.3,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.5,
			Offset = 0.05,
			Color = rgb(18, 26, 64),
			Decay = rgb(40, 10, 80),
			Glare = 0,
			Haze = 4,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 5000, SunAngularSize = 0, MoonAngularSize = 0 },
		Bloom = { Intensity = 0.7, Size = 36, Threshold = 0.9 },
		ColorCorrection = { Brightness = 0, Contrast = 0.2, Saturation = 0.1, TintColor = rgb(220, 228, 255) },
		DepthOfField = { FarIntensity = 0.3, NearIntensity = 0, FocusDistance = 34, InFocusRadius = 40 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(1.5, 0, -1),
		Ambient = { Particles = "VoidMotes", Density = 1.0 },
	},
	{
		Id = "VoidAbyssFinal",
		Name = { en = "Void Abyss: Red Shift", ru = "Бездна пустоты: красное смещение" },
		Desc = {
			en = "The rift red-shifts: crimson void, hot magenta glow, red stars.",
			ru = "Разлом краснеет: багровая пустота, жгучее пурпурное свечение, красные звёзды.",
		},
		Lighting = {
			ClockTime = 3.5, -- the moon swings to the west: the light flips during the transition
			GeographicLatitude = 10,
			Brightness = 0.9,
			ExposureCompensation = 0.3,
			Ambient = rgb(34, 8, 18),
			OutdoorAmbient = rgb(70, 18, 38),
			ColorShift_Top = rgb(255, 90, 120),
			ColorShift_Bottom = rgb(50, 0, 30),
			EnvironmentDiffuseScale = 0.15,
			EnvironmentSpecularScale = 0.6,
			ShadowSoftness = 0.25,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.52,
			Offset = 0.04,
			Color = rgb(70, 10, 26),
			Decay = rgb(90, 0, 60),
			Glare = 0,
			Haze = 4.5,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 5000, SunAngularSize = 0, MoonAngularSize = 0 },
		Bloom = { Intensity = 0.75, Size = 38, Threshold = 0.88 },
		ColorCorrection = { Brightness = -0.01, Contrast = 0.26, Saturation = 0.2, TintColor = rgb(255, 220, 228) },
		DepthOfField = { FarIntensity = 0.3, NearIntensity = 0, FocusDistance = 30, InFocusRadius = 36 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(3, 0, -2),
		Ambient = { Particles = "RiftMotes", Density = 1.2 },
	},
	----------------------------------------------------------------------------------------- CoreInferno
	{
		Id = "CoreInferno",
		Name = { en = "Core Inferno", ru = "Пекло Ядра" },
		Desc = {
			en = "Industrial heat: orange-red glare through hazy air, silhouetted machinery, rising embers.",
			ru = "Промышленный жар: оранжево-красный блеск в дымном воздухе, силуэты машин, летящие искры.",
		},
		Lighting = {
			ClockTime = 16.9,
			GeographicLatitude = 25,
			Brightness = 2.4,
			ExposureCompensation = 0.1,
			Ambient = rgb(60, 24, 12),
			OutdoorAmbient = rgb(120, 60, 34),
			ColorShift_Top = rgb(255, 140, 60),
			ColorShift_Bottom = rgb(90, 30, 0), -- lava under-glow on surfaces facing away from the sun
			EnvironmentDiffuseScale = 0.35,
			EnvironmentSpecularScale = 1,
			ShadowSoftness = 0.2,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.36,
			Offset = 0.12,
			Color = rgb(255, 130, 60),
			Decay = rgb(120, 30, 10),
			Glare = 3.2,
			Haze = 4.2,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 0, SunAngularSize = 24, MoonAngularSize = 11 },
		Clouds = { Cover = 0.6, Density = 0.45, Color = rgb(120, 60, 40) },
		Bloom = { Intensity = 0.65, Size = 32, Threshold = 0.95 },
		ColorCorrection = { Brightness = 0, Contrast = 0.18, Saturation = 0.22, TintColor = rgb(255, 228, 205) },
		SunRays = { Intensity = 0.16, Spread = 0.85 },
		DepthOfField = { FarIntensity = 0.22, NearIntensity = 0, FocusDistance = 30, InFocusRadius = 38 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(3, 0, 4),
		Ambient = { Particles = "Embers", Density = 1.0 },
	},
	{
		Id = "CoreInfernoFinal",
		Name = { en = "Core Inferno: Meltdown", ru = "Пекло Ядра: расплав" },
		Desc = {
			en = "Meltdown: red alert light, choking haze, a storm of embers.",
			ru = "Расплав: красный аварийный свет, удушливая дымка, буря искр.",
		},
		Lighting = {
			ClockTime = 17.95,
			GeographicLatitude = 25,
			Brightness = 2,
			ExposureCompensation = 0.1,
			Ambient = rgb(80, 14, 8),
			OutdoorAmbient = rgb(140, 36, 20),
			ColorShift_Top = rgb(255, 96, 40),
			ColorShift_Bottom = rgb(120, 10, 0),
			EnvironmentDiffuseScale = 0.3,
			EnvironmentSpecularScale = 1,
			ShadowSoftness = 0.25,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.46,
			Offset = 0.08,
			Color = rgb(255, 104, 52),
			Decay = rgb(110, 10, 0),
			Glare = 4.5,
			Haze = 6,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 0, SunAngularSize = 30, MoonAngularSize = 11 },
		Clouds = { Cover = 0.8, Density = 0.6, Color = rgb(90, 30, 20) },
		Bloom = { Intensity = 0.75, Size = 34, Threshold = 0.92 },
		ColorCorrection = { Brightness = -0.01, Contrast = 0.25, Saturation = 0.3, TintColor = rgb(255, 212, 196) },
		SunRays = { Intensity = 0.22, Spread = 1 },
		DepthOfField = { FarIntensity = 0.25, NearIntensity = 0, FocusDistance = 28, InFocusRadius = 34 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(6, 0, 7),
		Ambient = { Particles = "Embers", Density = 1.6 },
	},
	------------------------------------------------------------------------------------------- BloodFell
	{
		Id = "BloodFell",
		Name = { en = "Blood Fell", ru = "Кровавый Фелл" },
		Desc = {
			en = "Crimson dusk of a crueler underground: blood-red sky, black silhouettes, falling ash.",
			ru = "Багровые сумерки жестокого подземелья: кроваво-красное небо, чёрные силуэты, падающий пепел.",
		},
		Lighting = {
			ClockTime = 17.8,
			GeographicLatitude = 20,
			Brightness = 2.4,
			ExposureCompensation = 0,
			Ambient = rgb(40, 6, 8),
			OutdoorAmbient = rgb(96, 22, 22),
			ColorShift_Top = rgb(255, 72, 40),
			ColorShift_Bottom = rgb(60, 0, 6),
			EnvironmentDiffuseScale = 0.4,
			EnvironmentSpecularScale = 0.8,
			ShadowSoftness = 0.18,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.44,
			Offset = 0.1,
			Color = rgb(190, 46, 34),
			Decay = rgb(72, 0, 6),
			Glare = 2.8,
			Haze = 3.6,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 0, SunAngularSize = 26, MoonAngularSize = 11 },
		Clouds = { Cover = 0.72, Density = 0.55, Color = rgb(110, 24, 22) },
		Bloom = { Intensity = 0.62, Size = 30, Threshold = 0.98 },
		ColorCorrection = { Brightness = -0.03, Contrast = 0.3, Saturation = 0.18, TintColor = rgb(255, 208, 204) },
		SunRays = { Intensity = 0.18, Spread = 0.8 },
		DepthOfField = { FarIntensity = 0.2, NearIntensity = 0, FocusDistance = 32, InFocusRadius = 40 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(5, 0, 3),
		Ambient = { Particles = "Ash", Density = 1.0 },
	},
	{
		Id = "BloodFellFinal",
		Name = { en = "Blood Fell: Red Sun", ru = "Кровавый Фелл: красное солнце" },
		Desc = {
			en = "The red sun drowns: near-black crimson, heavy ash, searing highlights.",
			ru = "Красное солнце тонет: почти чёрный багрянец, густой пепел, обжигающие блики.",
		},
		Lighting = {
			ClockTime = 17.97,
			GeographicLatitude = 20,
			Brightness = 1.4,
			ExposureCompensation = -0.25,
			Ambient = rgb(28, 2, 4),
			OutdoorAmbient = rgb(62, 8, 10),
			ColorShift_Top = rgb(255, 40, 30),
			ColorShift_Bottom = rgb(40, 0, 0),
			EnvironmentDiffuseScale = 0.3,
			EnvironmentSpecularScale = 0.9,
			ShadowSoftness = 0.12,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.55,
			Offset = 0.05,
			Color = rgb(140, 18, 16),
			Decay = rgb(30, 0, 0),
			Glare = 4,
			Haze = 5,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 200, SunAngularSize = 34, MoonAngularSize = 11 },
		Clouds = { Cover = 0.9, Density = 0.7, Color = rgb(60, 10, 10) },
		Bloom = { Intensity = 0.72, Size = 30, Threshold = 0.92 },
		ColorCorrection = { Brightness = -0.04, Contrast = 0.38, Saturation = 0.12, TintColor = rgb(255, 196, 190) },
		SunRays = { Intensity = 0.24, Spread = 0.9 },
		DepthOfField = { FarIntensity = 0.26, NearIntensity = 0, FocusDistance = 28, InFocusRadius = 32 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(9, 0, 5),
		Ambient = { Particles = "Ash", Density = 1.7 },
	},
	------------------------------------------------------------------------------------------ Dreamscape
	{
		Id = "Dreamscape",
		Name = { en = "Dreamscape", ru = "Мир грёз" },
		Desc = {
			en = "Soft pastel dawn: pink and lavender sky, wide gentle bloom, floating glimmers. A lighter, hopeful mood.",
			ru = "Мягкий пастельный рассвет: розово-лавандовое небо, широкое нежное свечение, парящие искорки. Светлое, обнадёживающее настроение.",
		},
		Lighting = {
			ClockTime = 6.55, -- sun ~8° above the east (+X) horizon
			GeographicLatitude = 15,
			Brightness = 2.2,
			ExposureCompensation = 0.25,
			Ambient = rgb(96, 82, 110),
			OutdoorAmbient = rgb(168, 150, 182),
			ColorShift_Top = rgb(255, 196, 210),
			ColorShift_Bottom = rgb(60, 50, 90),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.6,
			ShadowSoftness = 0.45,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.32,
			Offset = 0.3,
			Color = rgb(255, 205, 228),
			Decay = rgb(160, 130, 210),
			Glare = 0.8,
			Haze = 2,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 0, SunAngularSize = 18, MoonAngularSize = 14 },
		Clouds = { Cover = 0.5, Density = 0.35, Color = rgb(255, 225, 240) },
		Bloom = { Intensity = 0.5, Size = 46, Threshold = 1 },
		ColorCorrection = { Brightness = 0.03, Contrast = -0.04, Saturation = 0, TintColor = rgb(255, 244, 252) },
		SunRays = { Intensity = 0.1, Spread = 0.9 },
		DepthOfField = { FarIntensity = 0.3, NearIntensity = 0, FocusDistance = 34, InFocusRadius = 40 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(2, 0, -1),
		Ambient = { Particles = "Glimmer", Density = 1.0 },
	},
	{
		Id = "DreamscapeFinal",
		Name = { en = "Dreamscape: Lucid Dusk", ru = "Мир грёз: осознанные сумерки" },
		Desc = {
			en = "The dream turns lucid: violet dusk, cooler pastels, sharper contrast.",
			ru = "Сон становится осознанным: фиолетовые сумерки, холодная пастель, резче контраст.",
		},
		Lighting = {
			ClockTime = 17.85,
			GeographicLatitude = 15,
			Brightness = 1.8,
			ExposureCompensation = 0.25,
			Ambient = rgb(70, 56, 110),
			OutdoorAmbient = rgb(120, 100, 160),
			ColorShift_Top = rgb(220, 150, 255),
			ColorShift_Bottom = rgb(40, 30, 80),
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.6,
			ShadowSoftness = 0.35,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.4,
			Offset = 0.18,
			Color = rgb(190, 150, 230),
			Decay = rgb(90, 60, 160),
			Glare = 1.4,
			Haze = 2.6,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 1200, SunAngularSize = 20, MoonAngularSize = 16 },
		Clouds = { Cover = 0.62, Density = 0.45, Color = rgb(200, 170, 230) },
		Bloom = { Intensity = 0.6, Size = 42, Threshold = 0.95 },
		ColorCorrection = { Brightness = 0.01, Contrast = 0.1, Saturation = 0.05, TintColor = rgb(245, 235, 255) },
		SunRays = { Intensity = 0.14, Spread = 0.9 },
		DepthOfField = { FarIntensity = 0.32, NearIntensity = 0, FocusDistance = 30, InFocusRadius = 36 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(4, 0, -2),
		Ambient = { Particles = "Glimmer", Density = 1.4 },
	},
	------------------------------------------------------------------------------------------ Monochrome
	{
		Id = "Monochrome",
		Name = { en = "Monochrome", ru = "Монохром" },
		Desc = {
			en = "High-contrast 'old film' black and white: hard light, deep blacks, film dust. A ghost of colour keeps attack colours readable.",
			ru = "Контрастное чёрно-белое «старое кино»: жёсткий свет, глубокий чёрный, пылинки на плёнке. Едва заметный цвет сохраняет читаемость цветов атак.",
		},
		Lighting = {
			ClockTime = 14.5,
			GeographicLatitude = 41.73,
			Brightness = 2.4,
			ExposureCompensation = 0,
			Ambient = rgb(18, 18, 18),
			OutdoorAmbient = rgb(70, 70, 70),
			ColorShift_Top = rgb(0, 0, 0),
			ColorShift_Bottom = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 0.5,
			ShadowSoftness = 0.05, -- noir-hard shadows
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.3,
			Offset = 0.15,
			Color = rgb(170, 170, 170),
			Decay = rgb(40, 40, 40),
			Glare = 0.4,
			Haze = 1.6,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 0, SunAngularSize = 14, MoonAngularSize = 11 },
		Clouds = { Cover = 0.45, Density = 0.5, Color = rgb(255, 255, 255) },
		Bloom = { Intensity = 0.5, Size = 22, Threshold = 1 },
		ColorCorrection = { Brightness = 0, Contrast = 0.35, Saturation = -0.85, TintColor = rgb(255, 248, 236) }, -- faint sepia paper
		SunRays = { Intensity = 0.1, Spread = 0.5 },
		DepthOfField = { FarIntensity = 0.25, NearIntensity = 0, FocusDistance = 30, InFocusRadius = 38 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Retro }, -- pre-2019 tonemapper: harsher, vintage
		GlobalWind = v3(2, 0, 1),
		Ambient = { Particles = "Dust", Density = 0.8 },
	},
	{
		Id = "MonochromeFinal",
		Name = { en = "Monochrome: Burnt Film", ru = "Монохром: горящая плёнка" },
		Desc = {
			en = "The film burns: crushed blacks, blown highlights and a faint blood-red cast.",
			ru = "Плёнка горит: провалы в чёрное, пересвеченные блики и слабый кроваво-красный оттенок.",
		},
		Lighting = {
			ClockTime = 14.5,
			GeographicLatitude = 41.73,
			Brightness = 2.4,
			ExposureCompensation = -0.15,
			Ambient = rgb(8, 8, 8),
			OutdoorAmbient = rgb(50, 50, 50),
			ColorShift_Top = rgb(0, 0, 0),
			ColorShift_Bottom = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 0.5,
			ShadowSoftness = 0.03,
			GlobalShadows = true,
		},
		Atmosphere = {
			Density = 0.38,
			Offset = 0.1,
			Color = rgb(170, 170, 170),
			Decay = rgb(20, 20, 20),
			Glare = 0.4,
			Haze = 2,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 0, SunAngularSize = 14, MoonAngularSize = 11 },
		Clouds = { Cover = 0.6, Density = 0.6, Color = rgb(220, 220, 220) },
		Bloom = { Intensity = 0.6, Size = 24, Threshold = 0.95 },
		ColorCorrection = { Brightness = 0, Contrast = 0.5, Saturation = -0.8, TintColor = rgb(255, 225, 220) },
		SunRays = { Intensity = 0.14, Spread = 0.5 },
		DepthOfField = { FarIntensity = 0.3, NearIntensity = 0, FocusDistance = 28, InFocusRadius = 34 },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Retro },
		GlobalWind = v3(3, 0, 1.5),
		Ambient = { Particles = "Ash", Density = 1.0 },
	},
	----------------------------------------------------------------------------------------- EclipseDark
	{
		Id = "EclipseDark",
		Name = { en = "Total Eclipse", ru = "Полное затмение" },
		Desc = {
			en = "Total eclipse: the world goes almost black; only glowing attacks and nearby silhouettes remain.",
			ru = "Полное затмение: мир почти чёрный; видны лишь светящиеся атаки и силуэты рядом.",
		},
		Lighting = {
			ClockTime = 0,
			GeographicLatitude = 41.73,
			Brightness = 0.15, -- a faint cold rim so nearby silhouettes still read
			ExposureCompensation = 0.3,
			Ambient = rgb(24, 24, 38),
			OutdoorAmbient = rgb(30, 30, 48),
			ColorShift_Top = rgb(60, 70, 140),
			ColorShift_Bottom = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0,
			EnvironmentSpecularScale = 0.2,
			ShadowSoftness = 0.6,
			GlobalShadows = true,
		},
		-- Very dense black fog: geometry vanishes after a few dozen studs, Neon telegraphs still glow through.
		Atmosphere = { Density = 0.9, Offset = 0, Color = rgb(2, 2, 6), Decay = rgb(0, 0, 0), Glare = 0, Haze = 10 },
		Sky = { CelestialBodiesShown = false, StarCount = 0, SunAngularSize = 0, MoonAngularSize = 0 },
		Bloom = { Intensity = 0.6, Size = 30, Threshold = 0.92 },
		ColorCorrection = { Brightness = -0.03, Contrast = 0.3, Saturation = -0.45, TintColor = rgb(205, 210, 255) },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(0, 0, 0),
		Ambient = { Particles = "VoidMotes", Density = 0.7 },
	},
	----------------------------------------------------------------------------------------- Performance
	{
		Id = "Performance",
		Name = { en = "Performance", ru = "Производительность" },
		Desc = {
			en = "Clean, flat and fast: neutral daylight, no shadows, minimal post-processing, maximum readability.",
			ru = "Чисто, плоско и быстро: нейтральный дневной свет, без теней, минимум постобработки, максимальная читаемость.",
		},
		Lighting = {
			ClockTime = 13,
			GeographicLatitude = 41.73,
			Brightness = 2,
			ExposureCompensation = 0.15,
			Ambient = rgb(128, 128, 132), -- GlobalShadows off: Ambient lights everything evenly
			OutdoorAmbient = rgb(140, 140, 145),
			ColorShift_Top = rgb(0, 0, 0),
			ColorShift_Bottom = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0,
			EnvironmentSpecularScale = 0,
			ShadowSoftness = 0.5,
			GlobalShadows = false,
		},
		Atmosphere = {
			Density = 0.2,
			Offset = 0.3,
			Color = rgb(200, 210, 225),
			Decay = rgb(110, 120, 140),
			Glare = 0,
			Haze = 0,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 1000, SunAngularSize = 21, MoonAngularSize = 11 },
		Bloom = { Intensity = 0.25, Size = 16, Threshold = 1.3 },
		ColorCorrection = { Brightness = 0, Contrast = 0.05, Saturation = 0.08, TintColor = rgb(255, 255, 255) },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(0, 0, 0),
	},
	{
		Id = "PerformanceFinal",
		Name = { en = "Performance: Final", ru = "Производительность: финал" },
		Desc = {
			en = "The Performance look with a warm red final-phase tint (still cheap).",
			ru = "Режим производительности с тёплым красным оттенком финальной фазы (всё так же дёшево).",
		},
		Lighting = {
			ClockTime = 13,
			GeographicLatitude = 41.73,
			Brightness = 2,
			ExposureCompensation = 0.1,
			Ambient = rgb(132, 118, 118),
			OutdoorAmbient = rgb(145, 128, 128),
			ColorShift_Top = rgb(0, 0, 0),
			ColorShift_Bottom = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0,
			EnvironmentSpecularScale = 0,
			ShadowSoftness = 0.5,
			GlobalShadows = false,
		},
		Atmosphere = {
			Density = 0.24,
			Offset = 0.3,
			Color = rgb(225, 190, 185),
			Decay = rgb(130, 90, 90),
			Glare = 0,
			Haze = 0,
		},
		Sky = { CelestialBodiesShown = true, StarCount = 1000, SunAngularSize = 21, MoonAngularSize = 11 },
		Bloom = { Intensity = 0.3, Size = 16, Threshold = 1.25 },
		ColorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = 0.12, TintColor = rgb(255, 226, 222) },
		ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
		GlobalWind = v3(0, 0, 0),
	},
}

-- Map id (Maps/Registry) -> default preset. Only a fallback: MapDef.Preset / RoundState.GraphicsPreset win.
local MAP_PRESETS: { [string]: string } = {
	HallOfVerdicts = "GoldenHall",
	SnowdinCrossroads = "SnowNight",
	WaterfallGrotto = "WaterfallGlow",
	VoidRift = "VoidAbyss",
	CoreReactor = "CoreInferno",
	Lobby = "Lobby",
}

local STYLE_PRESETS: { [string]: boolean } = {
	BloodFell = true,
	Dreamscape = true,
	Monochrome = true,
	Performance = true,
}

local SPECIAL_PRESETS: { [string]: boolean } = {
	EclipseDark = true,
}

local byId: { [string]: GraphicsPreset } = {}
local ids: { string } = {}
for _, preset in LIST do
	assert(byId[preset.Id] == nil, "duplicate graphics preset " .. preset.Id)
	byId[preset.Id] = preset
	table.insert(ids, preset.Id)
end

function Presets.Get(id: string?): GraphicsPreset?
	if id == nil then
		return nil
	end
	return byId[id]
end

function Presets.Has(id: string?): boolean
	return id ~= nil and byId[id] ~= nil
end

function Presets.All(): { GraphicsPreset }
	return table.clone(LIST)
end

function Presets.Ids(): { string }
	return table.clone(ids)
end

local function isFinalId(id: string): boolean
	return #id > 5 and string.sub(id, -5) == "Final"
end

-- "<id>Final" when it exists. A final preset maps to itself; ids without a variant return nil.
function Presets.FinalOf(id: string?): string?
	if id == nil or byId[id] == nil then
		return nil
	end
	if isFinalId(id) then
		return id
	end
	local finalId = id .. "Final"
	if byId[finalId] then
		return finalId
	end
	return nil
end

function Presets.ForMap(mapId: string?): (string?, string?)
	if mapId == nil then
		return nil, nil
	end
	local base = MAP_PRESETS[mapId]
	if base == nil then
		return nil, nil
	end
	return base, Presets.FinalOf(base)
end

function Presets.Kind(id: string): "Map" | "Style" | "Special" | "Final"
	if isFinalId(id) then
		return "Final"
	elseif SPECIAL_PRESETS[id] then
		return "Special"
	elseif STYLE_PRESETS[id] then
		return "Style"
	end
	return "Map"
end

-- Decides which preset should be on screen. Returns (presetId, source) where source is
-- "Override:<key>" | "User" | "Map" | "Fallback".
--   1. the highest-priority pushed override (newest wins a tie) — applied exactly as pushed;
--   2. else the player's own choice (not "MapDefault");
--   3. else the map preset (RoundState.GraphicsPreset, or Presets.ForMap(MapId));
--   4. else Presets.Default.
-- In FinalPhase, 2–4 switch to their final variant: explicit FinalPreset (map only) or "<id>Final".
function Presets.Resolve(state: ResolveState): (string, string)
	local best: OverrideEntry? = nil
	for _, entry in state.Overrides or {} do
		if byId[entry.PresetId] then
			if
				best == nil
				or entry.Priority > best.Priority
				or (entry.Priority == best.Priority and entry.Order > best.Order)
			then
				best = entry
			end
		end
	end
	if best then
		return best.PresetId, "Override:" .. best.Key
	end

	local base: string? = nil
	local source = "Fallback"
	local explicitFinal: string? = nil
	local user = state.UserOverride
	if user ~= nil and user ~= Presets.MAP_DEFAULT and byId[user] then
		base = user
		source = "User"
	elseif state.MapPreset and byId[state.MapPreset] then
		base = state.MapPreset
		source = "Map"
		explicitFinal = state.FinalPreset
	else
		local fromMap, finalFromMap = Presets.ForMap(state.MapId)
		if fromMap then
			base = fromMap
			source = "Map"
			explicitFinal = finalFromMap
		end
	end
	local chosen: string = base or Presets.Default

	if state.FinalPhase then
		if explicitFinal ~= nil and byId[explicitFinal] then
			return explicitFinal, source
		end
		local finalId = Presets.FinalOf(chosen)
		if finalId then
			return finalId, source
		end
	end
	return chosen, source
end

return Presets
