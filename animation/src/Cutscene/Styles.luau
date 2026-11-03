--!strict
-- Look preset: palette, materials, lighting, atmosphere, post-processing.
local Util = require(script.Parent.Util)
local hex = Util.hex

export type Lighting = {
	LightingStyle: string, -- "Soft" | "Realistic"
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ClockTime: number,
	GeographicLatitude: number,
	EnvironmentDiffuseScale: number,
	EnvironmentSpecularScale: number,
	ExposureCompensation: number,
	GlobalShadows: boolean,
	ShadowSoftness: number,
}

export type Atmosphere = { Density: number, Offset: number, Color: Color3, Decay: Color3, Glare: number, Haze: number }
export type Clouds = { Cover: number, Density: number, Color: Color3 }
export type Post = {
	bloom: { Intensity: number, Size: number, Threshold: number }?,
	cc: { Brightness: number, Contrast: number, Saturation: number, TintColor: Color3 }?,
	dof: { FarIntensity: number, NearIntensity: number, InFocusRadius: number }?,
	sunrays: { Intensity: number, Spread: number }?,
}

export type Style = {
	id: string,
	title: string,
	subtitle: string,
	color: { [string]: Color3 },
	material: { [string]: string },
	lighting: Lighting,
	atmosphere: Atmosphere?,
	clouds: Clouds?,
	defaultSky: boolean, -- add a Roblox Sky object with the stock skybox
	post: Post,
	outline: { color: Color3, transparency: number }?,
	face: { lightInfluence: number, line: number, soft: boolean },
	snow: boolean, -- falling snow particles
	vignette: number, -- 0..1 overlay strength
	sky: string, -- which painted sky to use: "storm" | "cinema" | "clear"
	studs: boolean, -- studded ground (classic look)
}

local Styles = {}

-- Part 1 is made in the "Кино" (cinema) look chosen after the style test.
-- Palette keys: skin*/rSkin* (faces), y* (Yuta), r* (Ryu), k* (Rika),
-- e* (energy colours), environment colours (snow, ice, crack, rubble...).

Styles.cinema = {
	id = "cinema",
	title = "2 · КИНО",
	subtitle = "объёмный свет, туман, глубина резкости, снег",
	color = {
		skin = hex("#E4CDBF"),
		skinShade = hex("#A88290"),
		skinDeep = hex("#6F5767"),
		rSkin = hex("#D5BCAD"),
		rSkinShade = hex("#9A7683"),
		rSkinDeep = hex("#5F4757"),
		line = hex("#2A2229"),
		sclera = hex("#E6E8EE"),
		scleraShade = hex("#A9A8BE"),
		yHair = hex("#1E262E"),
		yHairHi = hex("#3D4C58"),
		yIris = hex("#3A6F86"),
		yIrisDark = hex("#14252F"),
		yIrisLight = hex("#86BDCF"),
		yUniform = hex("#D9DDE5"),
		yUniformShade = hex("#8F98AD"),
		yPants = hex("#161B29"), -- dark navy trousers
		yShoe = hex("#D8DCE4"), -- white sneakers
		yShoeSole = hex("#9AA1B0"),
		ySheath = hex("#18181D"),
		rHair = hex("#17171C"),
		rIris = hex("#45466C"),
		rIrisDark = hex("#1E1E31"),
		rIrisLight = hex("#8F90C4"),
		rCoat = hex("#17181E"),
		rCoatHi = hex("#2C2F3B"),
		rFur = hex("#DEDFE4"),
		rFurShade = hex("#9EA3B3"),
		rPants = hex("#1E1F26"),
		rShoe = hex("#0F0F12"),
		rBelt = hex("#5A1E26"), -- burgundy belt
		rTag = hex("#B5B9C2"),
		kBody = hex("#E3E7EF"),
		kBodyShade = hex("#A7B0C4"),
		kDark = hex("#1F222C"),
		kStripe = hex("#15161C"),
		kMouth = hex("#2A1A22"),
		kTeeth = hex("#EEEAE2"),
		kEye = hex("#0E0F14"),
		kHair = hex("#ECEFF5"),
		kRing = hex("#C9A44A"),
		yBlood = hex("#7C1D25"),
		yBloodDark = hex("#4E1117"),
		eCyan = hex("#62E6FF"),
		eBlue = hex("#2F86FF"),
		eIce = hex("#BFF3FF"),
		ePink = hex("#FF5AD9"),
		eMagenta = hex("#E02FC0"),
		ePurple = hex("#A84BFF"),
		eYellow = hex("#FFE166"),
		eOrange = hex("#FF9A3C"),
		eRed = hex("#FF3B48"),
		eWhite = hex("#FFFFFF"),
		ice = hex("#A9C6E2"),
		iceDark = hex("#46607F"),
		crack = hex("#1C2738"),
		rubble = hex("#2B3346"),
		rubbleLight = hex("#5C6C88"),
		concrete = hex("#6C7687"),
		concreteDark = hex("#3A4252"),
		city = hex("#141A2A"),
		cityLight = hex("#26324A"),
		snow = hex("#E6ECF5"),
		ground = hex("#B8C2D4"), -- pale concrete in cold blue light
		snowFar = hex("#C8D3E6"),
		fogLight = hex("#D3DBEA"),
		fogDark = hex("#6E7EA4"),
	},
	material = {
		cloth = "Fabric",
		fur = "Fabric",
		skin = "SmoothPlastic",
		hair = "SmoothPlastic",
		metal = "Metal",
		body = "SmoothPlastic",
		ground = "Concrete",
	},
	lighting = {
		LightingStyle = "Realistic",
		Brightness = 1.6,
		Ambient = hex("#4A5266"),
		OutdoorAmbient = hex("#8A97B6"),
		ClockTime = 15.3,
		GeographicLatitude = 40,
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 0.5,
		ExposureCompensation = 0.1,
		GlobalShadows = true,
		ShadowSoftness = 0.6,
	},
	atmosphere = {
		Density = 0.52, -- a thick freezing fog over the battlefield
		Offset = 0.12,
		Color = hex("#B9C5DC"),
		Decay = hex("#66779E"),
		Glare = 0.05,
		Haze = 2.6,
	},
	clouds = { Cover = 0.86, Density = 0.72, Color = hex("#A3AFC7") },
	defaultSky = true,
	post = {
		bloom = { Intensity = 0.45, Size = 26, Threshold = 1.15 },
		cc = { Brightness = -0.01, Contrast = 0.14, Saturation = -0.28, TintColor = hex("#E7EEFF") },
		dof = { FarIntensity = 0.32, NearIntensity = 0.0, InFocusRadius = 28 },
		sunrays = { Intensity = 0.015, Spread = 0.5 },
	},
	outline = nil,
	face = { lightInfluence = 0.3, line = 0.85, soft = true },
	snow = true,
	vignette = 0.3,
	sky = "cinema",
	studs = false,
} :: Style

Styles.order = { "cinema" }

function Styles.get(id: string): Style
	local s = (Styles :: any)[id]
	assert(type(s) == "table" and s.id == id, "unknown style " .. id)
	return s :: Style
end

return Styles
