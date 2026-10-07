--!strict
-- Цвета и шрифты интерфейса. BuilderSans поддерживает кириллицу.

local Theme = {
	Font = Font.fromEnum(Enum.Font.BuilderSansExtraBold),
	FontBold = Font.fromEnum(Enum.Font.BuilderSansBold),
	FontBody = Font.fromEnum(Enum.Font.BuilderSansMedium),

	Panel = Color3.fromRGB(28, 32, 44),
	PanelLight = Color3.fromRGB(44, 50, 68),
	PanelStroke = Color3.fromRGB(10, 12, 18),
	Card = Color3.fromRGB(52, 59, 80),
	CardHover = Color3.fromRGB(64, 72, 98),

	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(190, 198, 215),
	TextStroke = Color3.fromRGB(12, 14, 22),

	Green = Color3.fromRGB(64, 200, 92),
	GreenDark = Color3.fromRGB(34, 140, 60),
	Red = Color3.fromRGB(235, 70, 70),
	RedDark = Color3.fromRGB(160, 36, 40),
	Blue = Color3.fromRGB(60, 150, 255),
	BlueDark = Color3.fromRGB(30, 96, 200),
	Yellow = Color3.fromRGB(255, 200, 40),
	YellowDark = Color3.fromRGB(205, 140, 10),
	Orange = Color3.fromRGB(255, 140, 40),
	Purple = Color3.fromRGB(150, 90, 255),
	Acid = Color3.fromRGB(140, 255, 60),
	AcidDark = Color3.fromRGB(70, 160, 30),
	Gray = Color3.fromRGB(120, 126, 140),
	GrayDark = Color3.fromRGB(80, 84, 96),

	Corner = 14,
	CornerSmall = 10,
}

return Theme
