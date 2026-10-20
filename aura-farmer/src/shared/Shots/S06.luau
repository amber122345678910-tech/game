--!strict
-- S06 (5.900–6.600 с): Сверхкрупно: улыбка с огромными зубами на фоне солнца.
-- Камера на штативе (не двигается): низкий ракурс снизу вверх (~18°), FOV 38, ~1 студ до передних зубов.
-- Солнце в кадре слева вверху (x≈35%, y≈18%) — контровой свет за головой коня; горизонт у нижнего края.
-- Смаз движения при «щелчке» челюсти и рывке головы — каналом blur камеры (5.93–6.17).
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local CAM = Config.at("Beach", 0.157, 5.382, 2.387)
local LOOK = Config.at("Beach", -0.438, 5.842, 1.090)
local FOCUS = 1.03 -- передние резцы/губы

local function k(t: number, blur: number, ease: string?): any
	return { t = t, pos = CAM, look = LOOK, fov = 38, blur = blur, focus = FOCUS, ease = ease or "linear" }
end

return {
	id = "S06",
	start = 5.9,
	finish = 6.6,
	set = "Beach",
	preset = "Beach",
	lighting = {
		-- направление НА солнце: в кадре слева вверху, за головой (контровой свет на мех)
		sunDir = Vector3.new(-0.514, 0.497, -0.699),
		lighting = {
			-- экспозиция «по зубам»: мех почти чёрный, небо насыщенно-голубое
			ExposureCompensation = -0.8,
			Ambient = Color3.fromRGB(100, 88, 80),
			-- тёплый «отражённый от песка» заполняющий свет на лице
			OutdoorAmbient = Color3.fromRGB(205, 194, 184),
			ColorShift_Top = Color3.fromRGB(255, 240, 214),
		},
		atmosphere = { Density = 0.3, Offset = 0.1, Color = Color3.fromRGB(205, 211, 211), Decay = Color3.fromRGB(92, 120, 150), Glare = 0.9, Haze = 1.0 },
		bloom = { Intensity = 1.0, Size = 48, Threshold = 1.0 },
		sunRays = { Intensity = 0.1, Spread = 0.7 },
		cc = { Brightness = 0.02, Contrast = 0.22, Saturation = 0.1, TintColor = Color3.fromRGB(255, 250, 242) },
		dof = { Enabled = true, FarIntensity = 0.7, NearIntensity = 0, InFocusRadius = 0.7, FocusDistance = FOCUS },
		clouds = { Enabled = false },
	},
	actors = {
		Horse = { char = "Horse", place = Config.place("Beach", 0, 0, 180) },
	},
	camera = {
		-- позиция/взгляд постоянны; ключи — только для смаза (blur) на быстрых кадрах
		keys = {
			k(5.9, 0),
			k(5.933, 3), -- челюсть «щёлкает» вниз
			k(5.967, 2),
			k(6.0, 1.2),
			k(6.033, 3.5), -- рывок головы к объективу (пик смеха, доля 12)
			k(6.067, 4.5),
			k(6.1, 4.5), -- челюсть быстро закрывается — самый сильный смаз
			k(6.133, 1.5),
			k(6.167, 0.6),
			k(6.2, 0),
			k(6.6, 0),
		},
		focus = FOCUS,
	},
	effects = {},
}
