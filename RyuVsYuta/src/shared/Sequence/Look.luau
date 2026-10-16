--!strict
-- Базовый "вид" сцены: свет, атмосфера, небо, пост-эффекты. Используется при сборке места (чтобы сцена
-- выглядела правильно уже в редакторе) и как значения по умолчанию для кадров.

local Look = {}

-- Палитра (сэмплирована с кадров ролика)
Look.palette = {
	fog = Color3.fromRGB(196, 202, 232), -- светлый лавандово-голубой туман
	fogDeep = Color3.fromRGB(150, 160, 205),
	skyTop = Color3.fromRGB(88, 112, 178),
	skyLow = Color3.fromRGB(186, 196, 228),
	cloudLit = Color3.fromRGB(240, 242, 252),
	cloudShade = Color3.fromRGB(150, 164, 206),
	energy = Color3.fromRGB(96, 226, 255),
	rikaEye = Color3.fromRGB(226, 36, 48),
}

-- Technology = Future задаётся в default.project.json (из скриптов это свойство больше недоступно).
-- Солнце: ClockTime/широта подобраны так, чтобы направление на солнце было Layout.sunDirection
-- (формула: dir = (cos p·cos l, cos p·sin l, sin p), p = широта − 23.5°, l = (ClockTime − 6)·15°).
Look.lighting = {
	ClockTime = 10.39,
	GeographicLatitude = 54.8,
	Brightness = 2.4,
	Ambient = Color3.fromRGB(96, 100, 128),
	OutdoorAmbient = Color3.fromRGB(150, 156, 190),
	EnvironmentDiffuseScale = 0.6,
	EnvironmentSpecularScale = 0.25,
	GlobalShadows = true,
	ShadowSoftness = 0.35,
	ExposureCompensation = 0.1,
	ColorShift_Top = Color3.fromRGB(255, 250, 240),
	ColorShift_Bottom = Color3.fromRGB(120, 130, 170),
}

Look.atmosphere = {
	Density = 0.42,
	Offset = 0.15,
	Color = Look.palette.fog,
	Decay = Color3.fromRGB(120, 132, 186),
	Glare = 0.1,
	Haze = 2.2,
}

Look.sky = {
	CelestialBodiesShown = true,
	StarCount = 0,
	SunAngularSize = 12,
	MoonAngularSize = 8,
}

Look.colorCorrection = {
	Name = "CutsceneColor",
	Brightness = 0.02,
	Contrast = 0.08,
	Saturation = -0.05,
	TintColor = Color3.fromRGB(236, 238, 255),
}

Look.bloom = {
	Name = "CutsceneBloom",
	Intensity = 0.55,
	Size = 30,
	Threshold = 1.2,
}

Look.depthOfField = {
	Name = "CutsceneDepthOfField",
	FarIntensity = 0,
	FocusDistance = 40,
	InFocusRadius = 30,
	NearIntensity = 0,
	Enabled = false,
}

Look.sunRays = {
	Name = "CutsceneSunRays",
	Intensity = 0.04,
	Spread = 0.6,
}

Look.blur = {
	Name = "CutsceneBlur",
	Size = 0,
	Enabled = false,
}

-- вид камеры в редакторе Studio при открытии файла
Look.editorCamera = CFrame.new(-40, 22, -40) * CFrame.Angles(0, math.rad(-140), 0) * CFrame.Angles(math.rad(-8), 0, 0)

return Look
