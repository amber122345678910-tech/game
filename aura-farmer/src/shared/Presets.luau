--!strict
-- Пресеты света и постобработки для планов. План указывает shot.preset = "Имя" и при желании
-- shot.lighting = { ...те же поля... } — они накладываются поверх пресета.
--
-- sunDir — направление НА солнце (мировое). Клиент подбирает ClockTime/GeographicLatitude,
-- чтобы Lighting:GetSunDirection() совпал с ним (clockTime/latitude — запасные значения).

local Presets = {}

Presets.Beach = {
	sunDir = Vector3.new(-0.35, 0.55, -0.76),
	clockTime = 15.5,
	latitude = 30,
	lighting = {
		Brightness = 3.2,
		ExposureCompensation = 0.1,
		Ambient = Color3.fromRGB(70, 74, 86),
		OutdoorAmbient = Color3.fromRGB(150, 160, 178),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		ShadowSoftness = 0.12,
		ColorShift_Top = Color3.fromRGB(255, 244, 226),
		ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	},
	atmosphere = {
		Density = 0.28,
		Offset = 0.25,
		Color = Color3.fromRGB(198, 214, 232),
		Decay = Color3.fromRGB(110, 130, 160),
		Glare = 0.35,
		Haze = 1.4,
	},
	bloom = { Intensity = 0.7, Size = 32, Threshold = 1.15 },
	sunRays = { Intensity = 0.06, Spread = 0.7 },
	cc = { Brightness = 0.02, Contrast = 0.14, Saturation = 0.18, TintColor = Color3.fromRGB(255, 250, 242) },
	dof = { Enabled = true, FarIntensity = 0.25, NearIntensity = 0, InFocusRadius = 14, FocusDistance = 12 },
	clouds = { Enabled = true, Cover = 0.45, Density = 0.55, Color = Color3.fromRGB(255, 255, 255) },
}

Presets.Park = {
	sunDir = Vector3.new(0.3, 0.7, -0.65),
	clockTime = 13.5,
	latitude = 40,
	lighting = {
		Brightness = 3,
		ExposureCompensation = 0.15,
		Ambient = Color3.fromRGB(70, 78, 70),
		OutdoorAmbient = Color3.fromRGB(150, 165, 155),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		ShadowSoftness = 0.15,
		ColorShift_Top = Color3.fromRGB(255, 248, 230),
		ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	},
	atmosphere = {
		Density = 0.3,
		Offset = 0.2,
		Color = Color3.fromRGB(215, 228, 236),
		Decay = Color3.fromRGB(120, 140, 150),
		Glare = 0.25,
		Haze = 1.2,
	},
	bloom = { Intensity = 0.6, Size = 30, Threshold = 1.2 },
	sunRays = { Intensity = 0.05, Spread = 0.6 },
	cc = { Brightness = 0.03, Contrast = 0.12, Saturation = 0.22, TintColor = Color3.fromRGB(255, 252, 240) },
	dof = { Enabled = true, FarIntensity = 0.35, NearIntensity = 0, InFocusRadius = 10, FocusDistance = 10 },
	clouds = { Enabled = true, Cover = 0.3, Density = 0.4, Color = Color3.fromRGB(255, 255, 255) },
}

Presets.Gym = {
	sunDir = Vector3.new(0.2, 0.9, 0.3),
	clockTime = 20,
	latitude = 40,
	lighting = {
		Brightness = 0,
		ExposureCompensation = 0.3,
		Ambient = Color3.fromRGB(32, 26, 42),
		OutdoorAmbient = Color3.fromRGB(32, 26, 42),
		EnvironmentDiffuseScale = 0.4,
		EnvironmentSpecularScale = 0.6,
		ShadowSoftness = 0.3,
		ColorShift_Top = Color3.fromRGB(0, 0, 0),
		ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	},
	atmosphere = { Density = 0, Offset = 0, Color = Color3.fromRGB(0, 0, 0), Decay = Color3.fromRGB(0, 0, 0), Glare = 0, Haze = 0 },
	bloom = { Intensity = 1.1, Size = 36, Threshold = 0.85 },
	sunRays = { Intensity = 0, Spread = 0 },
	cc = { Brightness = 0.02, Contrast = 0.16, Saturation = 0.12, TintColor = Color3.fromRGB(250, 240, 255) },
	dof = { Enabled = true, FarIntensity = 0.3, NearIntensity = 0, InFocusRadius = 9, FocusDistance = 10 },
	clouds = { Enabled = false },
}

Presets.Throne = {
	sunDir = Vector3.new(0, -1, 0.001),
	clockTime = 0,
	latitude = 40,
	lighting = {
		Brightness = 0,
		ExposureCompensation = 0.2,
		Ambient = Color3.fromRGB(4, 4, 6),
		OutdoorAmbient = Color3.fromRGB(0, 0, 0),
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0.35,
		ShadowSoftness = 0.25,
		ColorShift_Top = Color3.fromRGB(0, 0, 0),
		ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	},
	atmosphere = { Density = 0, Offset = 0, Color = Color3.fromRGB(0, 0, 0), Decay = Color3.fromRGB(0, 0, 0), Glare = 0, Haze = 0 },
	bloom = { Intensity = 1.3, Size = 40, Threshold = 0.9 },
	sunRays = { Intensity = 0, Spread = 0 },
	cc = { Brightness = 0, Contrast = 0.2, Saturation = 0.1, TintColor = Color3.fromRGB(255, 246, 232) },
	dof = { Enabled = true, FarIntensity = 0.2, NearIntensity = 0, InFocusRadius = 12, FocusDistance = 14 },
	clouds = { Enabled = false },
}

-- Слить пресет и переопределения плана (переопределения — поверх, по подтаблицам).
function Presets.resolve(shot: any): any
	local base = Presets[shot.preset or "Beach"] or Presets.Beach
	local over = shot.lighting
	if not over then
		return base
	end
	local out = {}
	for k, v in base do
		out[k] = v
	end
	for k, v in over do
		if type(v) == "table" and type(out[k]) == "table" then
			local merged = table.clone(out[k])
			for k2, v2 in v do
				merged[k2] = v2
			end
			out[k] = merged
		else
			out[k] = v
		end
	end
	return out
end

return Presets
