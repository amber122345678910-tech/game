--!strict
-- Цвета и шрифты интерфейса: ночная гроза — тёмно-синие панели, электрические акценты.
-- BuilderSans поддерживает кириллицу (FredokaOne/LuckiestGuy — нет, поэтому только для цифр).

local Theme = {
	Font = Font.fromEnum(Enum.Font.BuilderSansExtraBold),
	FontBold = Font.fromEnum(Enum.Font.BuilderSansBold),
	FontBody = Font.fromEnum(Enum.Font.BuilderSansMedium),
	FontNumber = Font.fromEnum(Enum.Font.FredokaOne), -- только цифры и латиница

	Panel = Color3.fromRGB(22, 26, 48),
	PanelLight = Color3.fromRGB(36, 42, 74),
	PanelDark = Color3.fromRGB(14, 16, 32),
	Card = Color3.fromRGB(44, 52, 90),
	CardHover = Color3.fromRGB(58, 68, 116),
	Stroke = Color3.fromRGB(8, 10, 22),

	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(176, 186, 220),
	TextStroke = Color3.fromRGB(10, 12, 26),

	Volt = Color3.fromRGB(255, 220, 70), -- ⚡ Вольты
	Shard = Color3.fromRGB(120, 230, 255), -- 💎 Осколки
	Electric = Color3.fromRGB(110, 200, 255),
	ElectricDark = Color3.fromRGB(40, 110, 210),
	Green = Color3.fromRGB(70, 210, 110),
	GreenDark = Color3.fromRGB(30, 140, 70),
	Red = Color3.fromRGB(240, 70, 80),
	RedDark = Color3.fromRGB(160, 30, 45),
	Orange = Color3.fromRGB(255, 150, 50),
	Purple = Color3.fromRGB(170, 100, 255),
	PurpleDark = Color3.fromRGB(100, 50, 190),
	Pink = Color3.fromRGB(255, 110, 190),
	Gray = Color3.fromRGB(110, 118, 150),
	GrayDark = Color3.fromRGB(70, 76, 104),

	Perfect = Color3.fromRGB(255, 235, 90),
	Good = Color3.fromRGB(120, 230, 255),
	Miss = Color3.fromRGB(255, 120, 120),

	Gold = Color3.fromRGB(255, 196, 40),
	GoldDark = Color3.fromRGB(190, 120, 20),
	Zap = Color3.fromRGB(255, 240, 120),
	Supercell = Color3.fromRGB(90, 230, 120),
	Ball = Color3.fromRGB(255, 150, 70),
	Rainbow = Color3.fromRGB(255, 120, 210),

	Corner = 16,
	CornerSmall = 12,
}

return Theme
