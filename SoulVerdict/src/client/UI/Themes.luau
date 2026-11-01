--!strict
-- Themes: pure design-token data for the four menu themes and the two HUD styles. Lune-safe
-- (no services, no requires). Every UIKit builder reads its look from these tokens.
--
--   Themes.Get(id) -> Theme                 unknown id -> default theme (Config.Defaults.MenuTheme = "Classic")
--   Themes.List() -> { Theme }              display order: Classic, Royal, Void, Fell
--   Themes.Ids : { string }
--   Themes.Font(theme, role, lang?) -> Font  role = "Display"|"Title"|"Heading"|"Subtitle"|"Body"|"Button"|
--                                            "Caption"|"Number"|"Mono"; lang "ru" uses theme.FontsRu overrides
--                                            (display fonts without Cyrillic glyphs fall back to a Cyrillic face)
--   Themes.HudStyles[id], Themes.GetHud(id) -> HudStyle, Themes.HudIds : { string }  ("Battle", "Modern")
--   Themes.Rarity(theme, rarity) -> Color3
--
-- Font families are verified against the client content manifest (content/fonts/families/*.json) and
-- Enum.Font in .tools/API-Dump.json: PressStart2P (= Enum.Font.Arcade), Merriweather, SourceSansPro,
-- Michroma, Sarpanch, TitilliumWeb, Jura, Oswald, RobotoCondensed, GrenzeGotisch, RobotoMono, BuilderSans.
-- Cyrillic coverage: PressStart2P, Merriweather, SourceSansPro, Jura, Oswald, RobotoCondensed, RobotoMono,
-- BuilderSans have it; Michroma, Sarpanch, TitilliumWeb, GrenzeGotisch do not (hence FontsRu).

export type Localized = { en: string, ru: string }

export type FontRole = "Display" | "Title" | "Heading" | "Subtitle" | "Body" | "Button" | "Caption" | "Number" | "Mono"

export type ThemeFonts = {
	Display: Font, -- hero/logo text
	Title: Font,
	Heading: Font,
	Subtitle: Font,
	Body: Font,
	Button: Font,
	Caption: Font,
	Number: Font,
	Mono: Font,
}

export type TextSizes = {
	Hero: number,
	Title: number,
	Heading: number,
	Subtitle: number,
	Body: number,
	Small: number,
	Button: number,
	Caption: number,
	Number: number,
}

export type ThemeColors = {
	Background: Color3, -- full-screen backdrop base
	Backdrop2: Color3, -- second backdrop tone (gradient end / vignette)
	Panel: Color3,
	PanelAlt: Color3,
	PanelInset: Color3,
	Stroke: Color3,
	StrokeAlt: Color3,
	StrokeDim: Color3,
	Text: Color3,
	TextDim: Color3,
	TextMuted: Color3,
	TextInverse: Color3, -- text drawn on Accent fills
	Accent: Color3,
	Accent2: Color3,
	Accent3: Color3,
	Hover: Color3,
	Selected: Color3,
	Disabled: Color3,
	Danger: Color3,
	Success: Color3,
	Warning: Color3,
	Info: Color3,
	HP: Color3,
	HPBack: Color3,
	KR: Color3,
	Guard: Color3,
	Dodge: Color3,
	Ult: Color3,
	Gold: Color3,
	Exp: Color3,
	SoulRed: Color3,
	Shadow: Color3,
	Glow: Color3,
	Overlay: Color3, -- modal dim colour
	Cursor: Color3,
}

export type ThemeGradients = {
	Backdrop: ColorSequence,
	PanelFill: ColorSequence?, -- multiplied with Colors.Panel (white = no change); rotation 90 = top->bottom
	PanelTransparency: NumberSequence?,
	Stroke: ColorSequence?, -- applied to panel/button strokes (e.g. gold sheen); multiplied with stroke colour
	StrokeTransparency: NumberSequence?,
	StrokeRotation: number,
	Title: ColorSequence?, -- title text fill
	Accent: ColorSequence, -- primary button / highlighted fills
	Bar: ColorSequence?, -- sheen applied over value bars (multiplied)
	Glass: NumberSequence?, -- top highlight line transparency (Void)
	Stained: { Color3 }?, -- Royal stained-glass accent palette
}

export type ButtonStyle = "Outline" | "Plate" | "Glass" | "Blade"
export type CursorStyle = "Heart" | "Diamond" | "Chevron" | "Fang"
export type MotionStyle = "Snappy" | "Elegant" | "Smooth" | "Bouncy"

export type TweenSpec = {
	Time: number,
	Style: Enum.EasingStyle,
	Direction: Enum.EasingDirection,
}

export type Theme = {
	Id: string,
	Name: Localized,
	Desc: Localized,
	Fonts: ThemeFonts,
	FontsRu: { [string]: Font }, -- per-role overrides for Russian text
	TextSize: TextSizes,
	Colors: ThemeColors,
	Gradients: ThemeGradients,
	Rarity: { Common: Color3, Rare: Color3, Epic: Color3, Legendary: Color3 },
	-- shape
	CornerRadius: UDim, -- panels
	ButtonCorner: UDim,
	SmallCorner: UDim, -- badges, key caps, chips
	StrokeThickness: number, -- panels / primary outlines (design px)
	StrokeThin: number, -- secondary lines
	LineJoin: Enum.LineJoinMode,
	PanelTransparency: number, -- body fill transparency (Void glass)
	Slant: number, -- degrees: blade buttons / slanted plates (Fell); 0 = none
	Pixel: number, -- pixel unit for pixel-art details (Classic)
	Blur: number, -- BlurEffect.Size under the camera while menus are open (0 = none)
	Shadow: { Enabled: boolean, Color: Color3, Transparency: number, Offset: Vector2, Layers: number, Spread: number, Hard: boolean },
	Glow: { Enabled: boolean, Color: Color3, Transparency: number, Size: number },
	Ornament: "None" | "Corners" | "Brackets" | "Fangs",
	-- text
	Uppercase: boolean, -- button / heading text forced uppercase
	DialoguePrefix: string, -- "* " in Classic
	LineHeight: number,
	-- controls
	Button: {
		Style: ButtonStyle,
		Height: number,
		PaddingX: number,
		IconSize: number, -- fraction of button height
		Align: "Left" | "Center",
		PressScale: number,
	},
	Cursor: { Style: CursorStyle, Color: Color3, Size: number },
	-- feedback
	Sounds: {
		Hover: string,
		Select: string,
		Back: string,
		Open: string,
		Close: string,
		Error: string,
		Toggle: string,
		Type: string, -- typewriter blip
		Reward: string,
	},
	Motion: {
		Style: MotionStyle,
		Hover: TweenSpec,
		Press: TweenSpec,
		Pop: TweenSpec,
		Slide: TweenSpec,
		Fade: TweenSpec,
		TypeInterval: number, -- seconds per character (typewriter)
		PunctuationPause: number,
		PulsePeriod: number,
	},
}

export type HudStyle = {
	Id: string,
	Name: Localized,
	Desc: Localized,
	Fonts: { Label: Font, Number: Font, Title: Font, Body: Font },
	FontsRu: { [string]: Font },
	TextSize: { Label: number, Number: number, Title: number, Small: number, Big: number },
	Colors: {
		Text: Color3,
		TextDim: Color3,
		Box: Color3, -- box / frame stroke
		BoxFill: Color3,
		HP: Color3,
		HPBack: Color3,
		KR: Color3,
		KRText: Color3,
		Guard: Color3,
		GuardBack: Color3,
		Dodge: Color3,
		DodgeEmpty: Color3,
		Ult: Color3,
		UltFull: Color3,
		Monster: Color3,
		Danger: Color3,
		Ghost: Color3,
		Shadow: Color3,
	},
	Gradients: { HP: ColorSequence?, KR: ColorSequence?, Guard: ColorSequence?, Ult: ColorSequence?, Monster: ColorSequence? },
	Bar: {
		Height: number,
		Corner: UDim,
		StrokeThickness: number,
		StrokeColor: Color3,
		StrokeTransparency: number,
		BackTransparency: number,
		Shine: boolean,
		Ghost: boolean,
		SegmentGap: number,
		LabelInside: boolean,
	},
	Box: { StrokeThickness: number, Corner: UDim, FillTransparency: number },
	Uppercase: boolean,
}

local Themes = {}

-- helpers -----------------------------------------------------------------------------------------
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function F(family: string, weight: Enum.FontWeight?, style: Enum.FontStyle?): Font
	return Font.new(
		"rbxasset://fonts/families/" .. family .. ".json",
		weight or Enum.FontWeight.Regular,
		style or Enum.FontStyle.Normal
	)
end

local function cs(points: { { any } }): ColorSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, ColorSequenceKeypoint.new(p[1] :: number, p[2] :: Color3))
	end
	return ColorSequence.new(keys)
end

local function ns(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function tw(time: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): TweenSpec
	return { Time = time, Style = style, Direction = direction }
end

local W = Enum.FontWeight
local Ease = Enum.EasingStyle
local Dir = Enum.EasingDirection
local WHITE = rgb(255, 255, 255)
local BLACK = rgb(0, 0, 0)

-- CLASSIC ----------------------------------------------------------------------------------------
-- Authentic battle-menu look: pure black boxes, crisp white pixel borders, PressStart2P everywhere,
-- orange FIGHT/ACT outlines that turn yellow when selected, red pixel SOUL cursor, "* " dialogue lines.
local PIXEL = F("PressStart2P")
local classic: Theme = {
	Id = "Classic",
	Name = { en = "Classic", ru = "Классика" },
	Desc = {
		en = "Black boxes, white pixel borders and a red SOUL cursor.",
		ru = "Чёрные рамки, белые пиксельные границы и красная ДУША-курсор.",
	},
	Fonts = {
		Display = PIXEL,
		Title = PIXEL,
		Heading = PIXEL,
		Subtitle = PIXEL,
		Body = PIXEL,
		Button = PIXEL,
		Caption = PIXEL,
		Number = PIXEL,
		Mono = PIXEL,
	},
	FontsRu = {},
	TextSize = { Hero = 44, Title = 28, Heading = 18, Subtitle = 13, Body = 13, Small = 11, Button = 17, Caption = 10, Number = 16 },
	Colors = {
		Background = BLACK,
		Backdrop2 = rgb(6, 6, 10),
		Panel = BLACK,
		PanelAlt = rgb(16, 16, 16),
		PanelInset = rgb(10, 10, 10),
		Stroke = WHITE,
		StrokeAlt = rgb(150, 150, 150),
		StrokeDim = rgb(70, 70, 70),
		Text = WHITE,
		TextDim = rgb(170, 170, 170),
		TextMuted = rgb(110, 110, 110),
		TextInverse = BLACK,
		Accent = rgb(255, 127, 39), -- FIGHT/ACT orange
		Accent2 = rgb(255, 255, 0), -- selected yellow
		Accent3 = rgb(66, 252, 255),
		Hover = rgb(255, 255, 0),
		Selected = rgb(255, 255, 0),
		Disabled = rgb(90, 90, 90),
		Danger = rgb(255, 0, 0),
		Success = rgb(0, 230, 64),
		Warning = rgb(255, 160, 0),
		Info = rgb(66, 252, 255),
		HP = rgb(255, 255, 0),
		HPBack = rgb(255, 0, 0),
		KR = rgb(255, 0, 255),
		Guard = rgb(66, 160, 255),
		Dodge = WHITE,
		Ult = rgb(255, 201, 14),
		Gold = rgb(255, 201, 14),
		Exp = rgb(0, 230, 64),
		SoulRed = rgb(255, 0, 0),
		Shadow = BLACK,
		Glow = WHITE,
		Overlay = BLACK,
		Cursor = rgb(255, 0, 0),
	},
	Gradients = {
		Backdrop = cs({ { 0, BLACK }, { 1, BLACK } }),
		PanelFill = nil,
		PanelTransparency = nil,
		Stroke = nil,
		StrokeTransparency = nil,
		StrokeRotation = 0,
		Title = nil,
		Accent = cs({ { 0, rgb(255, 127, 39) }, { 1, rgb(255, 127, 39) } }),
		Bar = nil,
		Glass = nil,
		Stained = nil,
	},
	Rarity = { Common = WHITE, Rare = rgb(66, 160, 255), Epic = rgb(220, 90, 255), Legendary = rgb(255, 255, 0) },
	CornerRadius = UDim.new(0, 0),
	ButtonCorner = UDim.new(0, 0),
	SmallCorner = UDim.new(0, 0),
	StrokeThickness = 4,
	StrokeThin = 2,
	LineJoin = Enum.LineJoinMode.Miter,
	PanelTransparency = 0,
	Slant = 0,
	Pixel = 3,
	Blur = 0,
	Shadow = { Enabled = false, Color = BLACK, Transparency = 1, Offset = Vector2.new(0, 0), Layers = 0, Spread = 0, Hard = true },
	Glow = { Enabled = false, Color = WHITE, Transparency = 1, Size = 0 },
	Ornament = "None",
	Uppercase = true,
	DialoguePrefix = "* ",
	LineHeight = 1.35,
	Button = { Style = "Outline", Height = 56, PaddingX = 14, IconSize = 0.5, Align = "Left", PressScale = 1 },
	Cursor = { Style = "Heart", Color = rgb(255, 0, 0), Size = 22 },
	Sounds = {
		Hover = "UI.Classic.Move",
		Select = "UI.Classic.Select",
		Back = "UI.Classic.Back",
		Open = "UI.Classic.Open",
		Close = "UI.Classic.Back",
		Error = "UI.Classic.Error",
		Toggle = "UI.Classic.Select",
		Type = "UI.Classic.Text",
		Reward = "UI.Classic.Save",
	},
	Motion = {
		Style = "Snappy",
		Hover = tw(0.05, Ease.Linear, Dir.Out),
		Press = tw(0.04, Ease.Linear, Dir.Out),
		Pop = tw(0.12, Ease.Linear, Dir.Out),
		Slide = tw(0.14, Ease.Quad, Dir.Out),
		Fade = tw(0.1, Ease.Linear, Dir.Out),
		TypeInterval = 0.033,
		PunctuationPause = 0.18,
		PulsePeriod = 1.0,
	},
}

-- ROYAL ------------------------------------------------------------------------------------------
-- Judgement Hall: deep navy and ivory, gold-sheen strokes, serif capitals, stained-glass accents,
-- soft layered drop shadows, gold diamond ornaments.
local GOLD_HI = rgb(255, 240, 180)
local GOLD = rgb(226, 182, 84)
local GOLD_LO = rgb(150, 104, 36)
local royal: Theme = {
	Id = "Royal",
	Name = { en = "Royal", ru = "Королевская" },
	Desc = {
		en = "Judgement Hall gold and navy, serif capitals, stained-glass light.",
		ru = "Золото и синь Зала Суда, строгие засечки и свет витражей.",
	},
	Fonts = {
		Display = F("Merriweather", W.Heavy),
		Title = F("Merriweather", W.Heavy),
		Heading = F("Merriweather", W.Bold),
		Subtitle = F("Merriweather", W.Regular, Enum.FontStyle.Italic),
		Body = F("SourceSansPro", W.Regular),
		Button = F("Merriweather", W.Bold),
		Caption = F("SourceSansPro", W.SemiBold),
		Number = F("Merriweather", W.Bold),
		Mono = F("RobotoMono", W.Medium),
	},
	FontsRu = {},
	TextSize = { Hero = 60, Title = 38, Heading = 23, Subtitle = 18, Body = 18, Small = 15, Button = 18, Caption = 13, Number = 22 },
	Colors = {
		Background = rgb(10, 14, 32),
		Backdrop2 = rgb(34, 24, 48),
		Panel = rgb(16, 23, 52),
		PanelAlt = rgb(26, 36, 74),
		PanelInset = rgb(9, 13, 31),
		Stroke = GOLD,
		StrokeAlt = rgb(240, 228, 200),
		StrokeDim = rgb(112, 92, 52),
		Text = rgb(246, 239, 222),
		TextDim = rgb(196, 186, 164),
		TextMuted = rgb(134, 128, 116),
		TextInverse = rgb(20, 18, 32),
		Accent = GOLD,
		Accent2 = rgb(96, 140, 255), -- sapphire
		Accent3 = rgb(214, 64, 96), -- ruby
		Hover = rgb(255, 222, 140),
		Selected = rgb(255, 214, 110),
		Disabled = rgb(92, 92, 104),
		Danger = rgb(224, 72, 88),
		Success = rgb(96, 204, 146),
		Warning = rgb(240, 182, 72),
		Info = rgb(120, 168, 255),
		HP = rgb(255, 214, 90),
		HPBack = rgb(112, 30, 44),
		KR = rgb(232, 96, 220),
		Guard = rgb(124, 200, 255),
		Dodge = rgb(246, 239, 222),
		Ult = rgb(255, 196, 84),
		Gold = rgb(255, 205, 84),
		Exp = rgb(150, 210, 255),
		SoulRed = rgb(232, 40, 64),
		Shadow = rgb(0, 0, 6),
		Glow = rgb(255, 214, 120),
		Overlay = rgb(4, 6, 16),
		Cursor = GOLD,
	},
	Gradients = {
		Backdrop = cs({ { 0, rgb(30, 22, 46) }, { 0.45, rgb(12, 17, 40) }, { 1, rgb(6, 9, 22) } }),
		PanelFill = cs({ { 0, rgb(255, 255, 255) }, { 1, rgb(150, 150, 170) } }),
		PanelTransparency = nil,
		Stroke = cs({ { 0, GOLD_HI }, { 0.3, GOLD }, { 0.55, GOLD_LO }, { 0.8, GOLD }, { 1, GOLD_HI } }),
		StrokeTransparency = nil,
		StrokeRotation = 35,
		Title = cs({ { 0, rgb(255, 246, 214) }, { 0.5, rgb(250, 214, 120) }, { 1, rgb(196, 140, 52) } }),
		Accent = cs({ { 0, rgb(255, 228, 150) }, { 0.5, GOLD }, { 1, rgb(176, 124, 44) } }),
		Bar = cs({ { 0, rgb(255, 255, 255) }, { 1, rgb(200, 190, 170) } }),
		Glass = nil,
		Stained = { rgb(214, 64, 96), rgb(96, 140, 255), rgb(240, 190, 80), rgb(70, 184, 130), rgb(156, 96, 220) },
	},
	Rarity = { Common = rgb(214, 206, 188), Rare = rgb(110, 160, 255), Epic = rgb(190, 110, 255), Legendary = rgb(255, 200, 80) },
	CornerRadius = UDim.new(0, 6),
	ButtonCorner = UDim.new(0, 4),
	SmallCorner = UDim.new(0, 4),
	StrokeThickness = 2,
	StrokeThin = 1,
	LineJoin = Enum.LineJoinMode.Round,
	PanelTransparency = 0,
	Slant = 0,
	Pixel = 2,
	Blur = 10,
	Shadow = { Enabled = true, Color = rgb(0, 0, 6), Transparency = 0.55, Offset = Vector2.new(0, 8), Layers = 3, Spread = 6, Hard = false },
	Glow = { Enabled = false, Color = GOLD, Transparency = 0.8, Size = 6 },
	Ornament = "Corners",
	Uppercase = true,
	DialoguePrefix = "",
	LineHeight = 1.2,
	Button = { Style = "Plate", Height = 54, PaddingX = 18, IconSize = 0.46, Align = "Center", PressScale = 0.97 },
	Cursor = { Style = "Diamond", Color = GOLD, Size = 14 },
	Sounds = {
		Hover = "UI.Royal.Hover",
		Select = "UI.Royal.Select",
		Back = "UI.Royal.Back",
		Open = "UI.Royal.Open",
		Close = "UI.Royal.Close",
		Error = "UI.Royal.Error",
		Toggle = "UI.Royal.Toggle",
		Type = "UI.Royal.Text",
		Reward = "UI.Royal.Reward",
	},
	Motion = {
		Style = "Elegant",
		Hover = tw(0.22, Ease.Sine, Dir.Out),
		Press = tw(0.12, Ease.Quad, Dir.Out),
		Pop = tw(0.38, Ease.Quart, Dir.Out),
		Slide = tw(0.45, Ease.Quart, Dir.Out),
		Fade = tw(0.3, Ease.Sine, Dir.InOut),
		TypeInterval = 0.028,
		PunctuationPause = 0.2,
		PulsePeriod = 2.4,
	},
}

-- VOID -------------------------------------------------------------------------------------------
-- Dark glass over a blurred world: translucent panels, cyan/blue neon strokes with a sweeping
-- gradient, tech corner brackets, glowing hover states.
local CYAN = rgb(0, 229, 255)
local voidTheme: Theme = {
	Id = "Void",
	Name = { en = "Void", ru = "Пустота" },
	Desc = {
		en = "Dark glass, neon cyan edges and a blurred world behind.",
		ru = "Тёмное стекло, неоновые грани и размытый мир за ним.",
	},
	Fonts = {
		Display = F("Michroma"),
		Title = F("Michroma"),
		Heading = F("Michroma"),
		Subtitle = F("TitilliumWeb", W.SemiBold),
		Body = F("TitilliumWeb", W.Regular),
		Button = F("Sarpanch", W.SemiBold),
		Caption = F("TitilliumWeb", W.SemiBold),
		Number = F("Sarpanch", W.Bold),
		Mono = F("RobotoMono", W.Medium),
	},
	FontsRu = {
		Display = F("Jura", W.Bold),
		Title = F("Jura", W.Bold),
		Heading = F("Jura", W.Bold),
		Subtitle = F("Jura", W.SemiBold),
		Body = F("Jura", W.Medium),
		Button = F("Jura", W.Bold),
		Caption = F("Jura", W.SemiBold),
	},
	TextSize = { Hero = 54, Title = 32, Heading = 19, Subtitle = 18, Body = 18, Small = 15, Button = 20, Caption = 13, Number = 24 },
	Colors = {
		Background = rgb(3, 6, 14),
		Backdrop2 = rgb(10, 22, 46),
		Panel = rgb(10, 18, 36),
		PanelAlt = rgb(18, 32, 62),
		PanelInset = rgb(5, 10, 22),
		Stroke = rgb(80, 220, 255),
		StrokeAlt = rgb(90, 124, 255),
		StrokeDim = rgb(52, 84, 130),
		Text = rgb(232, 246, 255),
		TextDim = rgb(150, 180, 210),
		TextMuted = rgb(92, 116, 148),
		TextInverse = rgb(2, 14, 24),
		Accent = CYAN,
		Accent2 = rgb(70, 120, 255),
		Accent3 = rgb(168, 104, 255),
		Hover = rgb(150, 242, 255),
		Selected = CYAN,
		Disabled = rgb(70, 84, 104),
		Danger = rgb(255, 72, 112),
		Success = rgb(64, 255, 186),
		Warning = rgb(255, 204, 84),
		Info = rgb(96, 184, 255),
		HP = rgb(120, 255, 214),
		HPBack = rgb(60, 16, 40),
		KR = rgb(255, 64, 214),
		Guard = rgb(96, 170, 255),
		Dodge = rgb(220, 248, 255),
		Ult = rgb(184, 120, 255),
		Gold = rgb(255, 212, 92),
		Exp = rgb(96, 200, 255),
		SoulRed = rgb(255, 54, 96),
		Shadow = rgb(0, 4, 12),
		Glow = CYAN,
		Overlay = rgb(0, 4, 12),
		Cursor = CYAN,
	},
	Gradients = {
		Backdrop = cs({ { 0, rgb(12, 26, 56) }, { 0.5, rgb(5, 10, 24) }, { 1, rgb(2, 3, 9) } }),
		PanelFill = cs({ { 0, rgb(255, 255, 255) }, { 1, rgb(170, 190, 230) } }),
		PanelTransparency = ns({ { 0, 0 }, { 1, 0.25 } }),
		Stroke = cs({ { 0, rgb(70, 120, 255) }, { 0.5, rgb(140, 250, 255) }, { 1, rgb(70, 120, 255) } }),
		StrokeTransparency = ns({ { 0, 0.55 }, { 0.5, 0 }, { 1, 0.55 } }),
		StrokeRotation = 20,
		Title = cs({ { 0, rgb(255, 255, 255) }, { 0.6, rgb(170, 246, 255) }, { 1, rgb(64, 190, 255) } }),
		Accent = cs({ { 0, rgb(0, 236, 255) }, { 1, rgb(64, 110, 255) } }),
		Bar = cs({ { 0, rgb(255, 255, 255) }, { 1, rgb(190, 210, 255) } }),
		Glass = ns({ { 0, 1 }, { 0.2, 0.55 }, { 0.5, 0.35 }, { 0.8, 0.55 }, { 1, 1 } }),
		Stained = nil,
	},
	Rarity = { Common = rgb(180, 204, 228), Rare = rgb(64, 170, 255), Epic = rgb(176, 104, 255), Legendary = rgb(255, 210, 90) },
	CornerRadius = UDim.new(0, 14),
	ButtonCorner = UDim.new(0, 10),
	SmallCorner = UDim.new(0, 6),
	StrokeThickness = 1.5,
	StrokeThin = 1,
	LineJoin = Enum.LineJoinMode.Round,
	PanelTransparency = 0.28,
	Slant = 0,
	Pixel = 2,
	Blur = 20,
	Shadow = { Enabled = true, Color = rgb(0, 6, 18), Transparency = 0.6, Offset = Vector2.new(0, 10), Layers = 2, Spread = 8, Hard = false },
	Glow = { Enabled = true, Color = CYAN, Transparency = 0.86, Size = 6 },
	Ornament = "Brackets",
	Uppercase = true,
	DialoguePrefix = "",
	LineHeight = 1.15,
	Button = { Style = "Glass", Height = 52, PaddingX = 18, IconSize = 0.44, Align = "Center", PressScale = 0.96 },
	Cursor = { Style = "Chevron", Color = CYAN, Size = 16 },
	Sounds = {
		Hover = "UI.Void.Hover",
		Select = "UI.Void.Select",
		Back = "UI.Void.Back",
		Open = "UI.Void.Open",
		Close = "UI.Void.Close",
		Error = "UI.Void.Error",
		Toggle = "UI.Void.Toggle",
		Type = "UI.Void.Text",
		Reward = "UI.Void.Reward",
	},
	Motion = {
		Style = "Smooth",
		Hover = tw(0.16, Ease.Exponential, Dir.Out),
		Press = tw(0.1, Ease.Quad, Dir.Out),
		Pop = tw(0.3, Ease.Exponential, Dir.Out),
		Slide = tw(0.35, Ease.Exponential, Dir.Out),
		Fade = tw(0.25, Ease.Quad, Dir.Out),
		TypeInterval = 0.022,
		PunctuationPause = 0.14,
		PulsePeriod = 1.8,
	},
}

-- FELL -------------------------------------------------------------------------------------------
-- Black and crimson, slanted blades and hard offset shadows, heavy condensed capitals, aggressive
-- red glow, gold-tooth accents.
local CRIMSON = rgb(228, 18, 50)
local TOOTH = rgb(255, 196, 40)
local fell: Theme = {
	Id = "Fell",
	Name = { en = "Fell", ru = "Падший" },
	Desc = {
		en = "Black and crimson blades, hard shadows, a gold tooth grin.",
		ru = "Чёрно-багровые клинки, жёсткие тени и золотой клык.",
	},
	Fonts = {
		Display = F("GrenzeGotisch", W.Bold),
		Title = F("Oswald", W.Bold),
		Heading = F("Oswald", W.SemiBold),
		Subtitle = F("Oswald", W.Medium),
		Body = F("RobotoCondensed", W.Regular),
		Button = F("Oswald", W.SemiBold),
		Caption = F("RobotoCondensed", W.Bold),
		Number = F("Oswald", W.Bold),
		Mono = F("RobotoMono", W.Bold),
	},
	FontsRu = {
		Display = F("Oswald", W.Bold),
	},
	TextSize = { Hero = 66, Title = 40, Heading = 24, Subtitle = 20, Body = 18, Small = 15, Button = 22, Caption = 14, Number = 26 },
	Colors = {
		Background = rgb(7, 2, 4),
		Backdrop2 = rgb(52, 4, 12),
		Panel = rgb(20, 6, 10),
		PanelAlt = rgb(36, 9, 15),
		PanelInset = rgb(11, 3, 6),
		Stroke = CRIMSON,
		StrokeAlt = rgb(255, 84, 92),
		StrokeDim = rgb(104, 18, 30),
		Text = rgb(255, 242, 242),
		TextDim = rgb(214, 162, 166),
		TextMuted = rgb(140, 96, 102),
		TextInverse = rgb(255, 250, 250),
		Accent = CRIMSON,
		Accent2 = TOOTH,
		Accent3 = rgb(255, 92, 40),
		Hover = rgb(255, 54, 78),
		Selected = rgb(255, 40, 66),
		Disabled = rgb(84, 56, 60),
		Danger = rgb(255, 36, 60),
		Success = rgb(132, 232, 96),
		Warning = TOOTH,
		Info = rgb(255, 128, 140),
		HP = TOOTH,
		HPBack = rgb(84, 0, 12),
		KR = rgb(255, 0, 164),
		Guard = rgb(255, 128, 120),
		Dodge = rgb(255, 242, 242),
		Ult = rgb(255, 48, 72),
		Gold = TOOTH,
		Exp = rgb(255, 128, 96),
		SoulRed = rgb(255, 24, 44),
		Shadow = rgb(0, 0, 0),
		Glow = rgb(255, 24, 56),
		Overlay = rgb(10, 0, 2),
		Cursor = TOOTH,
	},
	Gradients = {
		Backdrop = cs({ { 0, rgb(70, 6, 16) }, { 0.55, rgb(16, 3, 6) }, { 1, rgb(4, 1, 2) } }),
		PanelFill = cs({ { 0, rgb(255, 255, 255) }, { 1, rgb(150, 120, 125) } }),
		PanelTransparency = nil,
		Stroke = nil,
		StrokeTransparency = nil,
		StrokeRotation = 0,
		Title = cs({ { 0, rgb(255, 255, 255) }, { 0.55, rgb(255, 196, 200) }, { 1, rgb(255, 64, 84) } }),
		Accent = cs({ { 0, rgb(255, 46, 76) }, { 1, rgb(150, 0, 24) } }),
		Bar = cs({ { 0, rgb(255, 255, 255) }, { 1, rgb(210, 170, 170) } }),
		Glass = nil,
		Stained = nil,
	},
	Rarity = { Common = rgb(214, 190, 192), Rare = rgb(255, 110, 120), Epic = rgb(255, 54, 160), Legendary = TOOTH },
	CornerRadius = UDim.new(0, 0),
	ButtonCorner = UDim.new(0, 0),
	SmallCorner = UDim.new(0, 2),
	StrokeThickness = 2,
	StrokeThin = 1,
	LineJoin = Enum.LineJoinMode.Miter,
	PanelTransparency = 0,
	Slant = 14,
	Pixel = 2,
	Blur = 6,
	Shadow = { Enabled = true, Color = rgb(120, 0, 18), Transparency = 0.35, Offset = Vector2.new(7, 7), Layers = 1, Spread = 0, Hard = true },
	Glow = { Enabled = true, Color = rgb(255, 24, 56), Transparency = 0.82, Size = 8 },
	Ornament = "Fangs",
	Uppercase = true,
	DialoguePrefix = "",
	LineHeight = 1.15,
	Button = { Style = "Blade", Height = 54, PaddingX = 26, IconSize = 0.46, Align = "Center", PressScale = 0.94 },
	Cursor = { Style = "Fang", Color = TOOTH, Size = 16 },
	Sounds = {
		Hover = "UI.Fell.Hover",
		Select = "UI.Fell.Select",
		Back = "UI.Fell.Back",
		Open = "UI.Fell.Open",
		Close = "UI.Fell.Close",
		Error = "UI.Fell.Error",
		Toggle = "UI.Fell.Toggle",
		Type = "UI.Fell.Text",
		Reward = "UI.Fell.Reward",
	},
	Motion = {
		Style = "Bouncy",
		Hover = tw(0.12, Ease.Back, Dir.Out),
		Press = tw(0.07, Ease.Quad, Dir.Out),
		Pop = tw(0.26, Ease.Back, Dir.Out),
		Slide = tw(0.24, Ease.Back, Dir.Out),
		Fade = tw(0.16, Ease.Quad, Dir.Out),
		TypeInterval = 0.026,
		PunctuationPause = 0.12,
		PulsePeriod = 0.9,
	},
}

-- HUD STYLES -------------------------------------------------------------------------------------
local battleHud: HudStyle = {
	Id = "Battle",
	Name = { en = "Battle Box", ru = "Боевая рамка" },
	Desc = {
		en = "Yellow HP on red, magenta KR, white boxes — straight from the battle screen.",
		ru = "Жёлтое HP на красном, пурпурная KR, белые рамки — как в бою.",
	},
	Fonts = { Label = PIXEL, Number = PIXEL, Title = PIXEL, Body = PIXEL },
	FontsRu = {},
	TextSize = { Label = 13, Number = 13, Title = 16, Small = 10, Big = 26 },
	Colors = {
		Text = WHITE,
		TextDim = rgb(180, 180, 180),
		Box = WHITE,
		BoxFill = BLACK,
		HP = rgb(255, 255, 0),
		HPBack = rgb(255, 0, 0),
		KR = rgb(255, 0, 255),
		KRText = rgb(255, 0, 255),
		Guard = rgb(0, 160, 255),
		GuardBack = rgb(0, 40, 80),
		Dodge = WHITE,
		DodgeEmpty = rgb(64, 64, 64),
		Ult = rgb(255, 160, 0),
		UltFull = rgb(255, 255, 0),
		Monster = WHITE,
		Danger = rgb(255, 0, 0),
		Ghost = rgb(255, 255, 255),
		Shadow = BLACK,
	},
	Gradients = { HP = nil, KR = nil, Guard = nil, Ult = nil, Monster = nil },
	Bar = {
		Height = 20,
		Corner = UDim.new(0, 0),
		StrokeThickness = 0,
		StrokeColor = WHITE,
		StrokeTransparency = 1,
		BackTransparency = 0,
		Shine = false,
		Ghost = false,
		SegmentGap = 4,
		LabelInside = false,
	},
	Box = { StrokeThickness = 4, Corner = UDim.new(0, 0), FillTransparency = 0 },
	Uppercase = true,
}

local BUILDER_B = F("BuilderSans", W.Bold)
local modernHud: HudStyle = {
	Id = "Modern",
	Name = { en = "Modern", ru = "Современный" },
	Desc = {
		en = "Sleek rounded bars with gradients, glass backing and damage trails.",
		ru = "Скруглённые полосы с градиентом, стеклянная подложка и шлейф урона.",
	},
	Fonts = { Label = BUILDER_B, Number = F("BuilderSans", W.ExtraBold), Title = F("BuilderSans", W.ExtraBold), Body = F("BuilderSans", W.Medium) },
	FontsRu = {},
	TextSize = { Label = 14, Number = 16, Title = 20, Small = 12, Big = 30 },
	Colors = {
		Text = rgb(255, 255, 255),
		TextDim = rgb(196, 204, 220),
		Box = rgb(255, 255, 255),
		BoxFill = rgb(10, 12, 20),
		HP = rgb(255, 214, 64),
		HPBack = rgb(46, 12, 20),
		KR = rgb(255, 64, 200),
		KRText = rgb(255, 120, 220),
		Guard = rgb(96, 200, 255),
		GuardBack = rgb(14, 30, 48),
		Dodge = rgb(255, 255, 255),
		DodgeEmpty = rgb(70, 76, 96),
		Ult = rgb(176, 112, 255),
		UltFull = rgb(255, 214, 64),
		Monster = rgb(96, 170, 255),
		Danger = rgb(255, 64, 88),
		Ghost = rgb(255, 255, 255),
		Shadow = rgb(0, 0, 0),
	},
	Gradients = {
		HP = cs({ { 0, rgb(255, 160, 40) }, { 1, rgb(255, 236, 110) } }),
		KR = cs({ { 0, rgb(200, 40, 255) }, { 1, rgb(255, 80, 190) } }),
		Guard = cs({ { 0, rgb(64, 140, 255) }, { 1, rgb(120, 230, 255) } }),
		Ult = cs({ { 0, rgb(130, 80, 255) }, { 1, rgb(255, 110, 220) } }),
		Monster = cs({ { 0, rgb(40, 110, 255) }, { 1, rgb(120, 220, 255) } }),
	},
	Bar = {
		Height = 16,
		Corner = UDim.new(0.5, 0),
		StrokeThickness = 1.5,
		StrokeColor = rgb(255, 255, 255),
		StrokeTransparency = 0.82,
		BackTransparency = 0.2,
		Shine = true,
		Ghost = true,
		SegmentGap = 5,
		LabelInside = false,
	},
	Box = { StrokeThickness = 1.5, Corner = UDim.new(0, 12), FillTransparency = 0.35 },
	Uppercase = true,
}

-- registry ---------------------------------------------------------------------------------------
local ORDER = { classic, royal, voidTheme, fell }
local byId: { [string]: Theme } = {}
Themes.Ids = {} :: { string }
for _, theme in ORDER do
	byId[theme.Id] = theme
	table.insert(Themes.Ids, theme.Id)
end

Themes.Default = "Classic"
Themes.HudStyles = { Battle = battleHud, Modern = modernHud } :: { [string]: HudStyle }
Themes.HudIds = { "Battle", "Modern" }
Themes.DefaultHud = "Battle"

function Themes.Get(id: string?): Theme
	return (id and byId[id]) or byId[Themes.Default]
end

function Themes.Has(id: string): boolean
	return byId[id] ~= nil
end

function Themes.List(): { Theme }
	return table.clone(ORDER)
end

function Themes.GetHud(id: string?): HudStyle
	return (id and Themes.HudStyles[id]) or Themes.HudStyles[Themes.DefaultHud]
end

function Themes.Font(theme: Theme, role: FontRole, lang: string?): Font
	if lang == "ru" then
		local override = theme.FontsRu[role]
		if override then
			return override
		end
	end
	return (theme.Fonts :: any)[role] or theme.Fonts.Body
end

function Themes.HudFont(style: HudStyle, role: "Label" | "Number" | "Title" | "Body", lang: string?): Font
	if lang == "ru" then
		local override = style.FontsRu[role]
		if override then
			return override
		end
	end
	return (style.Fonts :: any)[role] or style.Fonts.Label
end

function Themes.Rarity(theme: Theme, rarity: string): Color3
	return (theme.Rarity :: any)[rarity] or theme.Rarity.Common
end

return Themes
