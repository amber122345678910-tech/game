--!strict
-- Цвета и шрифты интерфейса «электро-наклейка» (docs/STYLE.md §8). Шрифты — из общего Shared/Fonts (§8.3):
-- BuilderSans и FredokaOne без кириллицы, в UI их нет. Три семейства, у каждого своя роль:
-- Montserrat — слова-события и заголовки, Oswald — числа, Nunito — читаемый текст.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fonts = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Fonts"))

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Theme = {
	-- Шрифты по ролям (§8.3.3)
	FontDisplay = Fonts.Display, -- D1 оценки, D2 заголовки окон, D4 кнопки-глаголы
	FontDisplayFlat = Fonts.DisplayFlat, -- D5 названия предметов, глифы ◆ ▲ ▼
	FontNumber = Fonts.Number, -- D3 валюта, цены, множители
	FontBody = Fonts.Body, -- B1/B2 описания, тосты, строки
	FontBodyHeavy = Fonts.BodyHeavy, -- L теги, S вкладки, T таймеры (цифры Nunito одной ширины)
	-- Алиасы старых имён: по умолчанию «безопасный» BodyHeavy, а не Display
	Font = Fonts.BodyHeavy,
	FontBold = Fonts.Body,

	-- Токены цвета (§8.2)
	Ink = rgb(18, 14, 40), -- внешние обводки, жёсткие тени, тёмный текст на жёлтом
	Night900 = rgb(20, 18, 46), -- низ градиента окна
	Night800 = rgb(30, 28, 66), -- фон окна, плитки меню
	Night700 = rgb(42, 42, 92), -- верх градиента окна, карточки
	Night600 = rgb(56, 58, 120), -- наведение, активная карточка
	Well = rgb(12, 10, 30), -- «колодцы»: трек полос, поле ввода, счётчики
	LineLight = rgb(124, 132, 214), -- внутренняя светлая рамка (прозрачность LineLightT)
	LineLightT = 0.55,
	Cream = rgb(255, 248, 232), -- основной текст
	TextDim = rgb(170, 174, 220), -- второстепенный текст

	Volt = rgb(255, 210, 60), -- ⚡, главная кнопка, ИДЕАЛЬНО
	VoltHi = rgb(255, 240, 150),
	VoltLo = rgb(224, 138, 24),
	Spark = rgb(80, 206, 255), -- энергия, навигация, ХОРОШО
	SparkHi = rgb(186, 242, 255),
	SparkLo = rgb(28, 118, 214),
	Go = rgb(78, 212, 112), -- «Купить», «Забрать»
	GoHi = rgb(168, 244, 160),
	GoLo = rgb(24, 136, 72),
	Danger = rgb(244, 72, 92), -- закрыть, ошибка, перегрузка
	DangerHi = rgb(255, 152, 150),
	DangerLo = rgb(158, 26, 58),
	Shard = rgb(120, 230, 255), -- 💎
	ShardHi = rgb(214, 250, 255),
	ShardLo = rgb(40, 150, 214),
	Violet = rgb(160, 104, 255), -- события, Молниедекс
	VioletHi = rgb(214, 186, 255),
	VioletLo = rgb(96, 54, 196),
	Pink = rgb(255, 112, 190), -- питомцы
	PinkHi = rgb(255, 196, 228),
	PinkLo = rgb(186, 48, 132),
	Orange = rgb(255, 150, 52), -- перезапуск
	OrangeHi = rgb(255, 214, 150),
	OrangeLo = rgb(196, 82, 20),
	Slate = rgb(78, 82, 128), -- нейтральные и неактивные кнопки
	SlateHi = rgb(122, 128, 182),
	SlateLo = rgb(48, 50, 84),
	DisabledFace = rgb(70, 72, 100),

	-- Слова оценок (градиенты текста, §8.4)
	Perfect = rgb(255, 226, 80),
	Good = rgb(120, 230, 255),
	Miss = rgb(255, 110, 120),
	Zap = rgb(255, 120, 60),

	-- События и особые цвета
	Gold = rgb(255, 196, 40),
	GoldDark = rgb(190, 120, 20),
	Supercell = rgb(90, 230, 120),
	Ball = rgb(255, 150, 70),
	Rainbow = rgb(255, 120, 210),

	-- Старые имена (их читают контроллеры мира и ещё не переведённый код)
	Panel = rgb(30, 28, 66),
	PanelLight = rgb(42, 42, 92),
	PanelDark = rgb(20, 18, 46),
	Card = rgb(42, 42, 92),
	CardHover = rgb(56, 58, 120),
	Stroke = rgb(18, 14, 40),
	Text = rgb(255, 248, 232),
	TextStroke = rgb(18, 14, 40),
	Electric = rgb(80, 206, 255),
	ElectricDark = rgb(28, 118, 214),
	Green = rgb(78, 212, 112),
	GreenDark = rgb(24, 136, 72),
	Red = rgb(244, 72, 92),
	RedDark = rgb(158, 26, 58),
	Purple = rgb(160, 104, 255),
	PurpleDark = rgb(96, 54, 196),
	Gray = rgb(78, 82, 128),
	GrayDark = rgb(48, 50, 84),

	-- Скругления (§8.4): тег 6, кнопка и карточка 10, окно 14
	CornerTag = 6,
	CornerSmall = 10,
	Corner = 14,
}

return Theme
