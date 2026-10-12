--!strict
-- Палитра и шрифты интерфейса. Тёмный "аналоговый" хоррор: почти чёрные панели, тёплый янтарный акцент,
-- красный только для опасности. BuilderSans поддерживает кириллицу, RobotoMono — для текста оповещений.

local Theme = {
	Font = Font.fromEnum(Enum.Font.BuilderSansExtraBold),
	FontBold = Font.fromEnum(Enum.Font.BuilderSansBold),
	FontBody = Font.fromEnum(Enum.Font.BuilderSansMedium),
	FontMono = Font.fromEnum(Enum.Font.RobotoMono),

	Panel = Color3.fromRGB(12, 13, 17),
	PanelLight = Color3.fromRGB(24, 26, 34),
	PanelStroke = Color3.fromRGB(3, 3, 5),
	Card = Color3.fromRGB(30, 32, 42),
	CardHover = Color3.fromRGB(42, 45, 58),

	Text = Color3.fromRGB(232, 229, 220),
	TextDim = Color3.fromRGB(150, 152, 164),
	TextStroke = Color3.fromRGB(0, 0, 0),

	Amber = Color3.fromRGB(255, 170, 40),
	AmberDark = Color3.fromRGB(170, 100, 10),
	Red = Color3.fromRGB(205, 42, 42),
	RedDark = Color3.fromRGB(120, 18, 18),
	Green = Color3.fromRGB(90, 180, 100),
	GreenDark = Color3.fromRGB(40, 110, 55),
	Blue = Color3.fromRGB(80, 140, 230),
	BlueDark = Color3.fromRGB(35, 80, 160),
	Gray = Color3.fromRGB(110, 114, 128),
	GrayDark = Color3.fromRGB(60, 62, 72),
	Cash = Color3.fromRGB(120, 220, 130),

	Corner = 8,
	CornerSmall = 6,
}

return Theme
