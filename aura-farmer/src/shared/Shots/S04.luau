--!strict
-- S04 (3.867–4.967 с): нижний ракурс, солнце за головой: конь хлёстко разворачивается из профиля к камере,
-- показывает левым кулаком большой палец «через плечо», хохочет (пик на доле 4.066), кивает и застывает в оскале.
-- Постановка: конь стоит на песке, камера снизу (≈4 студа, наклон вверх 16°) смотрит в сторону моря; пирс справа
-- за плечом, колесо обозрения — за правым краем кадра. Камера неподвижна (кроме толчка на хлысте и дрейфа 0.2°).
-- Камера и солнце заданы в пространстве персонажа: x вправо, y вверх, f вперёд; финальный торс смотрит в −Z,
-- камера спереди-справа (≈43° от фронта торса). Камера подобрана по ориентирам кадров 4.067/4.3/4.633.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local YAW = -150
local PLACE = Config.place("Beach", 20, -100, YAW)

-- точка в пространстве персонажа -> мир
local function at(x: number, y: number, f: number): Vector3
	return (PLACE * CFrame.new(x, y, -f)).Position
end

local FOV = 38.5
local CAM = at(3.52, 3.89, 3.76)
local LOOK = at(-0.1, 5.35, 0.2)
-- базис камеры (вручную: CFrame.lookAt в Lune-превью транспонирован)
local FWD = (LOOK - CAM).Unit
local RIGHT = FWD:Cross(Vector3.new(0, 1, 0)).Unit
local UP = RIGHT:Cross(FWD)

-- направление из камеры в точку кадра (x, y — доли кадра 16:9, 0..1 слева/сверху)
local function screenDir(x: number, y: number): Vector3
	local th = math.tan(math.rad(FOV / 2))
	local nx = (x - 0.5) * 2 * th * 16 / 9
	local ny = (0.5 - y) * 2 * th
	return (FWD + RIGHT * nx + UP * ny).Unit
end

-- микро-толчок камеры на кадре хлыста: сдвиг ≈0.02 студа и поворот ≈0.35° (фон смещается ≈0.6% ширины кадра)
local JOLT = CAM + RIGHT * 0.02
local JOLT_LOOK = LOOK + RIGHT * 0.035
-- «живой» дрейф: за 4.07–4.97 камера едва заметно поворачивает влево (фон ползёт вправо ≈0.2°)
local LOOK_DRIFT = LOOK - RIGHT * 0.016

return {
	id = "S04",
	start = 3.8667,
	finish = 4.9667,
	set = "Beach",
	preset = "Beach",
	lighting = {
		-- контровое солнце прямо за головой: ≈34% x, 15% y кадра, высота ≈30°; лицо в открытой тени
		sunDir = screenDir(0.34, 0.15),
		lighting = {
			Brightness = 3,
			ExposureCompensation = 0.15,
			Ambient = Color3.fromRGB(48, 53, 64),
			OutdoorAmbient = Color3.fromRGB(118, 128, 152),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 1,
			ShadowSoftness = 0.2,
		},
		-- чистое синее небо (без облаков), белое гало вокруг солнца, дымка у горизонта
		atmosphere = {
			Density = 0.3,
			Offset = 0.1,
			Color = Color3.fromRGB(201, 214, 227),
			Decay = Color3.fromRGB(95, 134, 166),
			Glare = 0.7,
			Haze = 1.2,
		},
		bloom = { Intensity = 1.2, Size = 56, Threshold = 0.9 },
		sunRays = { Intensity = 0.06, Spread = 0.9 },
		cc = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.15, TintColor = Color3.fromRGB(244, 247, 255) },
		-- малая ГРИП: резко лицо/очки и кулак (≈3.5 студа), пирс и пляж размыты
		dof = { Enabled = true, FarIntensity = 0.75, NearIntensity = 0, InFocusRadius = 2.2, FocusDistance = 3.6 },
		clouds = { Enabled = false },
	},
	actors = {
		Horse = { char = "Horse", place = PLACE },
	},
	camera = {
		path = "linear",
		keys = {
			{ t = 3.8667, pos = CAM, look = LOOK, fov = FOV, blur = 0, ease = "linear" },
			-- хлыст: смаз (BlurEffect) и микро-толчок на один кадр
			{ t = 3.8833, pos = CAM, look = LOOK, fov = FOV, blur = 3, ease = "linear" },
			{ t = 3.9, pos = JOLT, look = JOLT_LOOK, fov = FOV, blur = 6, ease = "linear" },
			{ t = 3.9333, pos = CAM, look = LOOK, fov = FOV, blur = 5, ease = "linear" },
			{ t = 3.9667, pos = CAM, look = LOOK, fov = FOV, blur = 2.5, ease = "linear" },
			{ t = 4.0, pos = CAM, look = LOOK, fov = FOV, blur = 1, ease = "linear" },
			{ t = 4.0333, pos = CAM, look = LOOK, fov = FOV, blur = 0, ease = "linear" },
			-- «живой» дрейф: едва заметная панорама влево до склейки
			{ t = 4.0667, pos = CAM, look = LOOK, fov = FOV, blur = 0, ease = "Sine_InOut" },
			{ t = 4.9667, pos = CAM, look = LOOK_DRIFT, fov = FOV, blur = 0 },
		},
		focus = { actor = "Horse", part = "Glasses" },
	},
	effects = {
		-- очки ловят солнце на хлысте: короткий тёплый «блик» (лёгкая вспышка кадра)
		{ t = 3.8833, dur = 0.1, kind = "flash", color = Color3.fromRGB(255, 244, 222), from = 0.9, to = 1, ease = "out" },
	},
}
