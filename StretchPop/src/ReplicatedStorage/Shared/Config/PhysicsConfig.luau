--!strict
-- STRETCH-POP · Физические константы. Единицы: studs, секунды, «игровые» массы (база = 1).
-- Клиент и сервер читают один и тот же файл → валидация на сервере совпадает с симуляцией клиента.

export type StatCurve = {
	Base: number,
	PerLevel: number,
	Max: number,
}

local PhysicsConfig = {
	-- Фиксированный шаг клиентской симуляции (интерполяция рендера — на RenderStepped)
	FixedTimestep = 1 / 120,
	MaxSubstepsPerFrame = 8,

	-- Полёт
	FlightGravityScale = 0.82, -- доля workspace.Gravity в полёте (мультяшная «лёгкость»)
	AirDrag = 0.00042, -- квадратичное сопротивление: a = −c·|v|·v
	AirControlAcceleration = 48, -- подруливание WASD в воздухе
	MaxFlightSpeed = 640,
	FlightMass = 1, -- инерция тела при запуске (v = √(2E/m))

	-- Тело персонажа в кастомной физике = сфера
	BodyRadius = 2.3,
	BallVisualRadius = 2.75,
	SkinWidth = 0.05,
	GroundNormalMinY = 0.62,
	GroundProbeExtra = 0.35,
	LandSpeed = 38, -- ниже этой касательной скорости персонаж «приземляется» в обычную ходьбу
	SkidFriction = 1.9, -- 1/с, экспоненциальное затухание скорости при скольжении по земле
	WallSlideKeep = 0.55, -- доля касательной скорости после «шлепка» о стену без шара
	LaunchGroundGrace = 0.16, -- после выстрела земля не тормозит (иначе вертикальный старт гасится)

	-- Руки
	HandSpeed = 760,
	HandRetractSpeed = 980,
	HandArriveEpsilon = 0.75,
	MissReachFraction = 0.65,
	ArmRestLength = 3.4, -- естественная длина руки: от неё считается сохранение объёма (утончение)
	ArmBaseWidth = 1.05,
	ArmMinWidth = 0.24,
	ArmOutlineWidth = 0.3,
	AimAssistCos = math.cos(math.rad(5.5)),

	GrabRange = { Base = 140, PerLevel = 6, Max = 320 } :: StatCurve, -- Elasticity
	MaxStretch = { Base = 26, PerLevel = 1.25, Max = 90 } :: StatCurve, -- Elasticity
	Stiffness = { Base = 24, PerLevel = 1.15, Max = 140 } :: StatCurve, -- Spring Power (k одной резинки)
	Restitution = { Base = 0.84, PerLevel = 0.0045, Max = 0.985 } :: StatCurve, -- Spring Power
	ImpactMass = { Base = 1, PerLevel = 0.07, Max = 8 } :: StatCurve, -- Smash Mass

	-- Рогатка (натяжение на земле)
	DrawSpeed = 40, -- скорость оттягивания назад при зажатой кнопке
	DrawResistance = 0.65, -- чем сильнее натяжение, тем медленнее тянется (F = −kx ощущается руками)
	MinLaunchSpeed = 28,
	LaunchUpBias = 0.08,
	LaunchSpeedCap = 560,
	ChargeLeanDegrees = 24,

	-- Захват в воздухе (банджи): резинка укорачивается, пока кнопка зажата
	AirStiffnessScale = 0.55,
	AirRadialDamping = 1.6,
	AirRetractSpeed = 58,
	AirMinRestLength = 6,

	-- Пружинный шар и отскоки
	BallTangentKeep = 0.985,
	BounceMinNormalSpeed = 9,
	BouncySurfaceRestitution = 1.08, -- бамперы/бортики добавляют скорость (пинбол)
	BouncySurfaceMaxSpeed = 520,
	GongRestitution = 0.55,
	ComboRestTime = 0.4, -- сколько секунд стоять на земле, чтобы комбо сбросилось

	-- Предпросмотр траектории
	PreviewDuration = 2.4,
	PreviewStep = 1 / 25,
	PreviewKnotEvery = 3,
	PreviewMaxBounces = 3,
	PreviewRefreshInterval = 1 / 20,

	-- Мир
	KillY = -90,
	SupersonicSpeed = 260,

	CollisionGroups = {
		Characters = "StretchCharacters",
		Debris = "StretchDebris",
	},

	Tags = {
		Smashable = "StretchSmashable",
		Bouncy = "StretchBouncy",
		GrabPoint = "StretchGrabPoint",
		Gong = "StretchGong",
		BoostRing = "StretchBoostRing",
		Pinata = "StretchPinata",
		CapsuleMachine = "StretchCapsuleMachine",
	},

	-- Прокачка статов (меню — следующий шаг, цены нужны серверу уже сейчас)
	StatUpgrade = {
		MaxLevel = 60,
		BaseCost = 30,
		CostGrowth = 1.28,
	},

	-- Серверная валидация (допуски на пинг и дискретность сэмплов)
	Validation = {
		SpeedSlack = 1.35, -- заявленная скорость ≤ наблюдаемая·1.35 + SpeedFlat
		SpeedFlat = 25,
		ObservedWindow = 0.9, -- окно поиска максимальной скорости, с
		DistanceBase = 18,
		DistanceLatency = 0.45, -- + наблюдаемая скорость · 0.45 с
		PendingTimeout = 0.6, -- ожидание догоняющих сэмплов позиции
		HardSpeedCap = 1100,
		TeleportMinJump = 70,
		StrikesBeforePullback = 3,
		StrikeWindow = 8,
		ComboSlack = 2,
		SmashTokensPerSecond = 10,
		SmashTokenBurst = 16,
		TrackerCapacity = 128,
		MinSampleDt = 1 / 30,
		TurnMinSpeed = 45,
		TurnCos = math.cos(math.rad(38)),
		TurnCooldown = 0.07,
		RestSpeed = 12,
		RestTime = 0.5,
		ArmEventsPerSecond = 20,
	},
}

return PhysicsConfig
