--!strict
-- Помощники для интерфейса, созданного кодом. Язык «электро-наклейки» (docs/STYLE.md §8):
-- плотные тёмно-синие плашки, двойная рамка, жёсткие смещённые тени вместо «обводки у всего»,
-- наклонённые ленты-заголовки, ромбы и шевроны как знаки энергии, жёлтый «вольт» — цвет главного действия.
-- Все окна рисуются в пикселях макета и масштабируются своим UIScale под экран,
-- поэтому одинаково выглядят на телефоне, планшете и ПК.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Theme = require(script.Parent.Theme)

local UIKit = {}

type Props = { [string]: any }

local WHITE = Color3.new(1, 1, 1)

----------------------------------------------------------------------
-- Тип ввода. PreferredInput — новое API, читаем его в pcall.
----------------------------------------------------------------------
local hasPreferredInput = pcall(function()
	return UserInputService.PreferredInput
end)

function UIKit.isTouch(): boolean
	if hasPreferredInput then
		return UserInputService.PreferredInput == Enum.PreferredInput.Touch
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function UIKit.isMouse(): boolean
	if hasPreferredInput then
		return UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse
	end
	return UserInputService.KeyboardEnabled and UserInputService.MouseEnabled
end

function UIKit.onInputTypeChanged(callback: () -> ())
	if hasPreferredInput then
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(callback)
	else
		local last = UIKit.isTouch()
		UserInputService.LastInputTypeChanged:Connect(function()
			local now = UIKit.isTouch()
			if now ~= last then
				last = now
				callback()
			end
		end)
	end
end

----------------------------------------------------------------------
-- Создание инстансов
----------------------------------------------------------------------

-- Свойства задаются до Parent (быстрее), дети подключаются в конце.
function UIKit.new(className: string, props: Props?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent: Instance? = nil
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UIKit.corner(parent: Instance, radius: number?): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Corner), Parent = parent })
end

-- Полный круг: только у точек-индикаторов и кнопки ЛОВИ
function UIKit.round(parent: Instance): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent })
end

function UIKit.stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Theme.Ink,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function UIKit.textStroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or 2,
		Color = color or Theme.Ink,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function UIKit.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

-- Последовательность цветов из пар {время, цвет}: резкие переходы — два ключа почти в одной точке
function UIKit.seq(stops: { { any } }): ColorSequence
	local kps = {}
	for _, s in stops do
		table.insert(kps, ColorSequenceKeypoint.new(s[1] :: number, s[2] :: Color3))
	end
	return ColorSequence.new(kps)
end

function UIKit.padding(parent: Instance, px: number, py: number?): UIPadding
	local y = py or px
	return UIKit.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, y),
		PaddingBottom = UDim.new(0, y),
		Parent = parent,
	})
end

function UIKit.list(
	parent: Instance,
	direction: Enum.FillDirection,
	gap: number,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	return UIKit.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Center,
		Parent = parent,
	})
end

function UIKit.grid(parent: Instance, cell: Vector2, gap: number): UIGridLayout
	return UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(gap, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = parent,
	})
end

----------------------------------------------------------------------
-- Текст. Роли и шрифты — §8.3.3: внутри панелей текст без обводки (по умолчанию),
-- обводка и D-шрифт включаются явно (NoStroke = false, FontFace = Theme.FontDisplay)
----------------------------------------------------------------------

-- Заглавные буквы с кириллицей (string.upper знает только латиницу)
function UIKit.upper(s: string): string
	local out = table.create(#s)
	for _, c in utf8.codes(s) do
		local code = c
		if code >= 0x430 and code <= 0x44F then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401
		elseif code >= 0x61 and code <= 0x7A then
			code -= 0x20
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

-- Текст: TextScaled с ограничением размера. Служебные ключи: MaxTextSize, NoStroke (по умолчанию true)
function UIKit.label(props: Props): TextLabel
	local maxSize = props.MaxTextSize or 32
	local noStroke = props.NoStroke ~= false
	props.MaxTextSize = nil
	props.NoStroke = nil
	local base: Props = {
		BackgroundTransparency = 1,
		FontFace = Theme.FontBody,
		TextColor3 = Theme.Cream,
		TextScaled = true,
		TextWrapped = true,
		Size = UDim2.fromOffset(200, 30),
	}
	for k, v in props do
		base[k] = v
	end
	local label = UIKit.new("TextLabel", base) :: TextLabel
	UIKit.new("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8, Parent = label })
	if not noStroke then
		UIKit.textStroke(label, 2)
	end
	return label
end

-- Градиент букв (UIGradient на лейбле с прозрачным фоном красит сами буквы): Hi сверху → основа (→ Lo)
function UIKit.gradientText(label: TextLabel, hi: Color3, base: Color3, lo: Color3?): UIGradient
	local grad = label:FindFirstChild("TextGrad")
	local g: UIGradient
	if grad and grad:IsA("UIGradient") then
		g = grad
	else
		g = UIKit.new("UIGradient", { Name = "TextGrad", Rotation = 90, Parent = label })
	end
	if lo then
		g.Color = UIKit.seq({ { 0, hi }, { 0.55, base }, { 1, lo } })
	else
		g.Color = ColorSequence.new(hi, base)
	end
	label.TextColor3 = WHITE
	return g
end

-- Жёсткая тень текста (D1–D3): копия Ink за лейблом (сосед с ZIndex − 1), повторяет текст и видимость
function UIKit.textShadow(label: TextLabel, dy: number, transparency: number?): TextLabel
	local shadow = label:Clone()
	shadow.Name = label.Name .. "Shadow"
	for _, c in shadow:GetChildren() do
		if c:IsA("UIGradient") then
			c:Destroy()
		end
	end
	shadow.TextColor3 = Theme.Ink
	shadow.ZIndex = label.ZIndex - 1
	local alpha = transparency or 0
	local function sync()
		shadow.Text = label.Text
		shadow.Visible = label.Visible
		shadow.Size = label.Size
		shadow.AnchorPoint = label.AnchorPoint
		shadow.Rotation = label.Rotation
		shadow.Position = label.Position + UDim2.fromOffset(0, dy)
		shadow.TextTransparency = 1 - (1 - label.TextTransparency) * (1 - alpha)
	end
	sync()
	for _, prop in { "Text", "Visible", "Position", "Size", "Rotation", "TextTransparency" } do
		label:GetPropertyChangedSignal(prop):Connect(sync)
	end
	shadow.Parent = label.Parent
	return shadow
end

-- Курсив и обводка выступают за рамку: у D-лейблов отступ слева и справа (§8.3.3)
function UIKit.italicPad(label: TextLabel, px: number?)
	local p = px or 8
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), Parent = label })
end

function UIKit.tween(
	obj: Instance,
	time: number,
	props: Props,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

-- Бесконечный «маятник» (Sine, туда-обратно)
function UIKit.loop(obj: Instance, time: number, props: Props): Tween
	local tw = TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), props)
	tw:Play()
	return tw
end

----------------------------------------------------------------------
-- Звук нажатия (подставляется контроллером звуков)
----------------------------------------------------------------------
local clickHandler: (() -> ())? = nil
function UIKit.setClickHandler(fn: () -> ())
	clickHandler = fn
end
function UIKit.playClick()
	if clickHandler then
		clickHandler()
	end
end

----------------------------------------------------------------------
-- Тона цвета: (Hi, основа, Lo). Для токенов Theme — их пары из §8.2, для прочих — расчёт
----------------------------------------------------------------------
export type Tones = { Hi: Color3, Base: Color3, Lo: Color3 }

local TONES: { Tones } = {
	{ Hi = Theme.VoltHi, Base = Theme.Volt, Lo = Theme.VoltLo },
	{ Hi = Theme.SparkHi, Base = Theme.Spark, Lo = Theme.SparkLo },
	{ Hi = Theme.GoHi, Base = Theme.Go, Lo = Theme.GoLo },
	{ Hi = Theme.DangerHi, Base = Theme.Danger, Lo = Theme.DangerLo },
	{ Hi = Theme.ShardHi, Base = Theme.Shard, Lo = Theme.ShardLo },
	{ Hi = Theme.VioletHi, Base = Theme.Violet, Lo = Theme.VioletLo },
	{ Hi = Theme.PinkHi, Base = Theme.Pink, Lo = Theme.PinkLo },
	{ Hi = Theme.OrangeHi, Base = Theme.Orange, Lo = Theme.OrangeLo },
	{ Hi = Theme.SlateHi, Base = Theme.Slate, Lo = Theme.SlateLo },
}

local function sameColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.02
end

function UIKit.tones(color: Color3): Tones
	for _, t in TONES do
		if sameColor(color, t.Base) or sameColor(color, t.Lo) then
			return t
		end
	end
	return { Hi = color:Lerp(WHITE, 0.45), Base = color, Lo = color:Lerp(Theme.Ink, 0.4) }
end

----------------------------------------------------------------------
-- Глифы, нарисованные примитивами (§8.5): в шрифтах игры нет ● ★ ✦ ✺ ☯ ✓ ✕ и ⚡.
-- Многодетальные глифы — два слоя: снизу детали с обводкой Ink, сверху заливка (единый контур).
----------------------------------------------------------------------
-- деталь: центр (cx, cy), размер (w, h) в долях квадрата, поворот, круглая?
type Piece = { number }

local GLYPHS: { [string]: { Piece } } = {
	-- молния «Z»: верхний брусок, перемычка, нижний брусок и острие-ромб
	bolt = {
		{ 0.53, 0.27, 0.27, 0.58, 31 },
		{ 0.5, 0.5, 0.54, 0.19, -12 },
		{ 0.53, 0.68, 0.23, 0.42, 31 },
		{ 0.39, 0.885, 0.13, 0.2, 33 },
	},
	diamond = { { 0.5, 0.5, 0.66, 0.66, 45 } },
	dot = { { 0.5, 0.5, 0.72, 0.72, 0, 1 } },
	cross = { { 0.5, 0.5, 0.2, 0.92, 45 }, { 0.5, 0.5, 0.2, 0.92, -45 } },
	plus = { { 0.5, 0.5, 0.2, 0.86, 0 }, { 0.5, 0.5, 0.86, 0.2, 0 } },
	minus = { { 0.5, 0.5, 0.86, 0.2, 0 } },
	check = { { 0.3, 0.62, 0.2, 0.46, -45 }, { 0.6, 0.5, 0.2, 0.8, 38 } },
	chevronDown = { { 0.33, 0.42, 0.2, 0.62, -42 }, { 0.67, 0.42, 0.2, 0.62, 42 } },
	chevronRight = { { 0.48, 0.3, 0.62, 0.2, 42 }, { 0.48, 0.7, 0.62, 0.2, -42 } },
	star = { { 0.5, 0.5, 0.64, 0.64, 0, 3 }, { 0.5, 0.5, 0.64, 0.64, 45, 3 } },
	sparkle = { { 0.5, 0.5, 0.13, 1, 0 }, { 0.5, 0.5, 1, 0.13, 0 }, { 0.5, 0.5, 0.46, 0.46, 45, 3 } },
	burst = {
		{ 0.5, 0.5, 0.16, 0.96, 0 },
		{ 0.5, 0.5, 0.16, 0.96, 45 },
		{ 0.5, 0.5, 0.16, 0.96, 90 },
		{ 0.5, 0.5, 0.16, 0.96, 135 },
		{ 0.5, 0.5, 0.36, 0.36, 22.5, 1 },
	},
	-- замок: дужка (рамка) и корпус
	lock = { { 0.5, 0.34, 0.44, 0.5, 0, 2 }, { 0.5, 0.66, 0.7, 0.5, 0 } },
	pin = { { 0.5, 0.42, 0.56, 0.56, 45 }, { 0.5, 0.42, 0.22, 0.22, 0, 1 } },
}

export type GlyphOptions = {
	Color: Color3?, -- заливка (по умолчанию Cream)
	Stroke: number?, -- толщина обводки Ink (0 — без обводки)
	StrokeColor: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Rotation: number?,
	ZIndex: number?,
	Name: string?,
	LayoutOrder: number?,
	Visible: boolean?,
}

local function buildPieces(holder: Frame, pieces: { Piece }, color: Color3, stroke: number, strokeColor: Color3, z: number)
	local layers = if stroke > 0 then 2 else 1
	for layer = 1, layers do
		local isStroke = layers == 2 and layer == 1
		for i, p in pieces do
			local ring = p[6] == 2 -- рамка без заливки (дужка замка)
			local f = UIKit.new("Frame", {
				Name = (if isStroke then "S" else "F") .. i,
				Size = UDim2.fromScale(p[3], p[4]),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(p[1], p[2]),
				Rotation = p[5],
				BackgroundColor3 = if isStroke then strokeColor else color,
				BackgroundTransparency = if ring then 1 else 0,
				ZIndex = z,
				Parent = holder,
			}) :: Frame
			if p[6] == 1 then
				UIKit.round(f)
			elseif p[6] == 3 then
				-- острые углы (звезда-взрыв)
			elseif ring then
				UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = f })
			else
				UIKit.new("UICorner", { CornerRadius = UDim.new(0.12, 0), Parent = f })
			end
			if ring then
				UIKit.new("UIStroke", {
					Thickness = if isStroke then 4 + stroke * 2 else 4,
					Color = if isStroke then strokeColor else color,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					BorderStrokePosition = Enum.BorderStrokePosition.Center,
					Parent = f,
				})
			elseif isStroke then
				UIKit.new("UIStroke", {
					Thickness = stroke,
					Color = strokeColor,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					LineJoinMode = Enum.LineJoinMode.Round,
					Parent = f,
				})
			end
		end
	end
end

-- Нарисованный глиф в квадратной рамке: bolt, diamond, dot, cross, plus, minus, check, chevronDown,
-- chevronRight, star, sparkle, burst, lock, pin, perun (молния в тёмном круге), triangle (▲ из Montserrat)
function UIKit.glyph(parent: Instance?, kind: string, opts: GlyphOptions?): Frame
	local o: GlyphOptions = opts or {}
	local color = o.Color or Theme.Cream
	local stroke = o.Stroke or 2
	local strokeColor = o.StrokeColor or Theme.Ink
	local z = o.ZIndex or 1
	local holder = UIKit.new("Frame", {
		Name = o.Name or ("Glyph_" .. kind),
		Size = o.Size or UDim2.fromOffset(32, 32),
		Position = o.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = o.AnchorPoint or Vector2.new(0.5, 0.5),
		Rotation = o.Rotation or 0,
		BackgroundTransparency = 1,
		LayoutOrder = o.LayoutOrder or 0,
		Visible = if o.Visible == nil then true else o.Visible,
		ZIndex = z,
	}) :: Frame
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = holder })
	if kind == "perun" then
		-- «Чёрная Перуна»: тёмный круг и светлая молния внутри
		local disc = UIKit.new("Frame", {
			Name = "Disc",
			Size = UDim2.fromScale(0.9, 0.9),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = color,
			ZIndex = z,
			Parent = holder,
		}) :: Frame
		UIKit.round(disc)
		if stroke > 0 then
			UIKit.stroke(disc, stroke, strokeColor)
		end
		local inner = UIKit.new("Frame", {
			Name = "Inner",
			Size = UDim2.fromScale(0.62, 0.62),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = z,
			Parent = holder,
		}) :: Frame
		buildPieces(inner, GLYPHS.bolt, Theme.Cream, 0, strokeColor, z)
	elseif kind == "triangle" then
		local l = UIKit.label({
			Name = "Tri",
			Text = "▲",
			FontFace = Theme.FontDisplayFlat,
			TextColor3 = color,
			Size = UDim2.fromScale(1.5, 1.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			MaxTextSize = 100,
			NoStroke = stroke <= 0,
			ZIndex = z,
			Parent = holder,
		})
		local s = l:FindFirstChildOfClass("UIStroke")
		if s then
			s.Thickness = stroke
			s.Color = strokeColor
		end
	else
		buildPieces(holder, GLYPHS[kind] or GLYPHS.diamond, color, stroke, strokeColor, z)
	end
	if parent then
		holder.Parent = parent
	end
	return holder
end

-- Перекрасить заливку глифа (слой F*)
function UIKit.setGlyphColor(glyph: Instance, color: Color3)
	for _, c in glyph:GetDescendants() do
		if c:IsA("Frame") and string.sub(c.Name, 1, 1) == "F" then
			c.BackgroundColor3 = color
		elseif c:IsA("TextLabel") and c.Name == "Tri" then
			c.TextColor3 = color
		end
	end
end

-- Знак цвета молнии (Config.Colors[*].Icon: ● ◆ ▲ ★ ✦ ✺ ☯) — нарисованный
local COLOR_GLYPH = {
	blue = "dot",
	purple = "diamond",
	green = "triangle",
	red = "star",
	gold = "sparkle",
	rainbow = "burst",
	black = "perun",
} :: { [string]: string }

function UIKit.colorGlyphKind(colorId: string): string
	return COLOR_GLYPH[colorId] or "diamond"
end

----------------------------------------------------------------------
-- Иконка-значок (§8.4): квадрат со скруглением, градиент акцента, обводка Ink, наклон −6°.
-- icon — эмодзи или имя нарисованного глифа с «#» впереди («#bolt»)
----------------------------------------------------------------------
function UIKit.iconBadge(parent: Instance?, icon: string, accent: Color3, size: number, props: Props?): Frame
	local t = UIKit.tones(accent)
	local base: Props = {
		Name = "IconBadge",
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Rotation = -6,
		BackgroundColor3 = WHITE,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local badge = UIKit.new("Frame", base) :: Frame
	local z = badge.ZIndex
	UIKit.corner(badge, math.max(6, math.floor(size * 0.25)))
	UIKit.stroke(badge, if size >= 40 then 2.5 else 2, Theme.Ink)
	local grad = UIKit.gradient(badge, t.Hi, t.Lo)
	grad.Name = "Grad"
	UIKit.new("Frame", {
		Name = "TopLine",
		Size = UDim2.new(1, -math.floor(size * 0.3), 0, 2),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, math.max(2, math.floor(size * 0.07))),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.45,
		ZIndex = z,
		Parent = badge,
	})
	if string.sub(icon, 1, 1) == "#" then
		UIKit.glyph(badge, string.sub(icon, 2), {
			Name = "Glyph",
			Size = UDim2.fromScale(0.62, 0.62),
			Stroke = 2,
			ZIndex = z,
		})
	else
		UIKit.label({
			Name = "Glyph",
			Text = icon,
			Size = UDim2.fromScale(0.68, 0.68),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			MaxTextSize = math.floor(size * 0.62),
			ZIndex = z,
			Parent = badge,
		})
	end
	if parent then
		badge.Parent = parent
	end
	return badge
end

function UIKit.setIconBadge(badge: Instance, icon: string?, accent: Color3?)
	if accent then
		local t = UIKit.tones(accent)
		local grad = badge:FindFirstChild("Grad")
		if grad and grad:IsA("UIGradient") then
			grad.Color = ColorSequence.new(t.Hi, t.Lo)
		end
	end
	if icon then
		local g = badge:FindFirstChild("Glyph")
		if g and g:IsA("TextLabel") then
			g.Text = icon
		end
	end
end

----------------------------------------------------------------------
-- Кнопка (§8.4): прозрачный TextButton → Lip (кромка цвета Lo, одна обводка Ink на всю кнопку) →
-- Face (градиент Hi → основа) → TopLine → Label. Нажатие: лицо въезжает в кромку.
-- Варианты: Volt (главное), Go (купить, забрать), Spark (навигация), Danger, Slate (второстепенное),
-- Violet, Orange, Pink и Disabled. Вариант выбирается по Color (токен Theme) или setButtonVariant.
----------------------------------------------------------------------
export type ButtonOptions = {
	Text: string?,
	Icon: string?, -- нарисованный глиф («#bolt») или эмодзи слева от текста
	Color: Color3?,
	ColorDark: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextSize: number?,
	Parent: Instance?,
	LayoutOrder: number?,
	Name: string?,
	ZIndex: number?,
	Silent: boolean?,
}

type Variant = { Base: Color3, Hi: Color3, Lo: Color3, Text: Color3, Stroke: boolean, TextT: number }

local VARIANTS: { [string]: Variant } = {
	Volt = { Base = Theme.Volt, Hi = Theme.VoltHi, Lo = Theme.VoltLo, Text = Theme.Ink, Stroke = false, TextT = 0 },
	Go = { Base = Theme.Go, Hi = Theme.GoHi, Lo = Theme.GoLo, Text = Theme.Cream, Stroke = true, TextT = 0 },
	Spark = { Base = Theme.Spark, Hi = Theme.SparkHi, Lo = Theme.SparkLo, Text = Theme.Cream, Stroke = true, TextT = 0 },
	Danger = { Base = Theme.Danger, Hi = Theme.DangerHi, Lo = Theme.DangerLo, Text = Theme.Cream, Stroke = true, TextT = 0 },
	Slate = { Base = Theme.Slate, Hi = Theme.SlateHi, Lo = Theme.SlateLo, Text = Theme.Cream, Stroke = true, TextT = 0 },
	Violet = { Base = Theme.Violet, Hi = Theme.VioletHi, Lo = Theme.VioletLo, Text = Theme.Cream, Stroke = true, TextT = 0 },
	Orange = { Base = Theme.Orange, Hi = Theme.OrangeHi, Lo = Theme.OrangeLo, Text = Theme.Cream, Stroke = true, TextT = 0 },
	Pink = { Base = Theme.Pink, Hi = Theme.PinkHi, Lo = Theme.PinkLo, Text = Theme.Cream, Stroke = true, TextT = 0 },
	Disabled = {
		Base = Theme.DisabledFace,
		Hi = Theme.DisabledFace:Lerp(WHITE, 0.08),
		Lo = Color3.fromRGB(42, 42, 66),
		Text = Theme.TextDim,
		Stroke = false,
		TextT = 0.3,
	},
}

-- Старые цвета кнопок → варианты
local function variantForColor(color: Color3): string?
	local map: { { any } } = {
		{ Theme.Volt, "Volt" },
		{ Theme.Gold, "Volt" },
		{ Theme.Go, "Go" },
		{ Theme.Spark, "Spark" },
		{ Theme.SparkLo, "Spark" },
		{ Theme.Danger, "Danger" },
		{ Theme.Slate, "Slate" },
		{ Theme.SlateLo, "Disabled" },
		{ Theme.Violet, "Violet" },
		{ Theme.Orange, "Orange" },
		{ Theme.Pink, "Pink" },
	}
	for _, m in map do
		if sameColor(color, m[1] :: Color3) then
			return m[2] :: string
		end
	end
	return nil
end

local function variantOf(name: string?, color: Color3?, dark: Color3?): Variant
	if name and VARIANTS[name] then
		return VARIANTS[name]
	end
	if color then
		local v = variantForColor(color)
		if v then
			return VARIANTS[v]
		end
		return {
			Base = color,
			Hi = color:Lerp(WHITE, 0.4),
			Lo = dark or color:Lerp(Theme.Ink, 0.45),
			Text = Theme.Cream,
			Stroke = true,
			TextT = 0,
		}
	end
	return VARIANTS.Go
end

local function applyVariant(button: GuiObject, v: Variant)
	local lip = button:FindFirstChild("Lip")
	local face = button:FindFirstChild("Face")
	if lip and lip:IsA("Frame") then
		lip.BackgroundColor3 = v.Lo
	end
	if not face then
		return
	end
	local grad = face:FindFirstChild("Grad")
	if grad and grad:IsA("UIGradient") then
		-- Hi → основа, но верх не выбеливается: Hi наполовину смешан с основой
		grad.Color = ColorSequence.new(v.Base:Lerp(v.Hi, 0.5), v.Base)
	end
	local top = face:FindFirstChild("TopLine")
	if top and top:IsA("Frame") then
		top.Visible = v.TextT == 0
	end
	for _, name in { "Label", "Price" } do
		local l = face:FindFirstChild(name)
		if l and l:IsA("TextLabel") then
			l.TextColor3 = v.Text
			l.TextTransparency = v.TextT
			local s = l:FindFirstChildOfClass("UIStroke")
			if s then
				s.Enabled = v.Stroke
			end
		end
	end
	local glyph = face:FindFirstChild("IconGlyph")
	if glyph then
		UIKit.setGlyphColor(glyph, if v.Stroke then Theme.Cream else v.Text)
	end
	button:SetAttribute("Disabled", v.TextT > 0)
end

-- Подпись кнопки: стиль "verb" (D4: Montserrat Black Italic, ЗАГЛАВНЫЕ), "plain" (S: Nunito 800 как есть),
-- "number" (Oswald, цены)
local function styleText(button: Instance, text: string): string
	local style = button:GetAttribute("TextStyle")
	if style == "plain" or style == "number" then
		return text
	end
	return UIKit.upper(text)
end

local function fontForStyle(style: any): Font
	if style == "plain" then
		return Theme.FontBodyHeavy
	elseif style == "number" then
		return Theme.FontNumber
	end
	return Theme.FontDisplay
end

function UIKit.button(opts: ButtonOptions, onClick: (() -> ())?): TextButton
	local z = opts.ZIndex or 1
	local button = UIKit.new("TextButton", {
		Name = opts.Name or "Button",
		Size = opts.Size or UDim2.fromOffset(180, 56),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = z,
		Active = true,
	}) :: TextButton
	UIKit.corner(button, Theme.CornerSmall)
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = button }) :: UIScale

	-- кромка снизу (объём) и единственная обводка кнопки
	local lip = UIKit.new("Frame", {
		Name = "Lip",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		ZIndex = z,
		Parent = button,
	}) :: Frame
	UIKit.corner(lip, Theme.CornerSmall)
	UIKit.stroke(lip, 2.5, Theme.Ink)
	local face = UIKit.new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -6),
		BackgroundColor3 = WHITE,
		ZIndex = z,
		Parent = button,
	}) :: Frame
	UIKit.corner(face, Theme.CornerSmall)
	local grad = UIKit.gradient(face, WHITE, WHITE)
	grad.Name = "Grad"
	UIKit.new("Frame", {
		Name = "TopLine",
		Size = UDim2.new(1, -16, 0, 2),
		Position = UDim2.fromOffset(8, 3),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		ZIndex = z,
		Parent = face,
	})

	local hasIcon = opts.Icon ~= nil and string.sub(opts.Icon :: string, 1, 1) == "#"
	local text = opts.Text or ""
	if opts.Icon and not hasIcon then
		text = (opts.Icon :: string) .. "  " .. text
	end
	local label = UIKit.label({
		Name = "Label",
		Text = UIKit.upper(text),
		FontFace = Theme.FontDisplay,
		Size = if hasIcon then UDim2.new(1, -60, 1, -12) else UDim2.new(1, -20, 1, -12),
		Position = if hasIcon then UDim2.new(0.5, 20, 0.5, 0) else UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = opts.TextSize or 26,
		NoStroke = false,
		ZIndex = z + 1,
		Parent = face,
	})
	label:SetAttribute("Role", "ButtonLabel")
	if hasIcon then
		UIKit.glyph(face, string.sub(opts.Icon :: string, 2), {
			Name = "IconGlyph",
			Size = UDim2.fromScale(0.5, 0.5),
			Position = UDim2.new(0, 30, 0.5, 0),
			Stroke = 2,
			ZIndex = z + 1,
		})
	end
	-- цена отдельным лейблом (D3, Oswald); показывается через setButtonPrice
	UIKit.label({
		Name = "Price",
		Text = "",
		FontFace = Theme.FontNumber,
		Size = UDim2.new(1, -16, 0.52, -4),
		Position = UDim2.new(0.5, 0, 1, -4),
		AnchorPoint = Vector2.new(0.5, 1),
		MaxTextSize = 28,
		NoStroke = false,
		Visible = false,
		ZIndex = z + 1,
		Parent = face,
	})
	applyVariant(button, variantOf(nil, opts.Color, opts.ColorDark))

	local pressed = false
	local function release()
		face.Position = UDim2.fromOffset(0, 0)
	end
	button.MouseEnter:Connect(function()
		if UIKit.isMouse() and not pressed and button:GetAttribute("Disabled") ~= true then
			UIKit.tween(scale, 0.12, { Scale = 1.04 })
		end
	end)
	button.MouseLeave:Connect(function()
		pressed = false
		UIKit.tween(scale, 0.12, { Scale = 1 })
		release()
	end)
	button.MouseButton1Down:Connect(function()
		if button:GetAttribute("Disabled") == true then
			return
		end
		pressed = true
		UIKit.tween(scale, 0.07, { Scale = 0.96 })
		face.Position = UDim2.fromOffset(0, 4)
	end)
	button.MouseButton1Up:Connect(function()
		pressed = false
		UIKit.tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		release()
	end)
	if onClick then
		button.Activated:Connect(function()
			if not opts.Silent then
				UIKit.playClick()
			end
			onClick()
		end)
	end
	if opts.Parent then
		button.Parent = opts.Parent
	end
	return button
end

local function faceLabel(button: GuiObject, name: string): TextLabel?
	local face = button:FindFirstChild("Face")
	local label = face and face:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

-- Стиль подписи: "verb" (по умолчанию), "plain", "number"
function UIKit.setButtonStyle(button: GuiObject, style: string)
	button:SetAttribute("TextStyle", style)
	local label = faceLabel(button, "Label")
	if label then
		label.FontFace = fontForStyle(style)
	end
end

function UIKit.setButtonText(button: GuiObject, text: string)
	local label = faceLabel(button, "Label")
	local price = faceLabel(button, "Price")
	if label then
		label.Text = styleText(button, text)
		label.Visible = true
		label.Size = UDim2.new(label.Size.X.Scale, label.Size.X.Offset, 1, -12)
		label.Position = UDim2.new(label.Position.X.Scale, label.Position.X.Offset, 0.5, 0)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	if price then
		price.Visible = false
	end
end

-- Глагол сверху и цена снизу (или только цена — крупно): «ОТКРЫТЬ / ⚡ 1.2K»
function UIKit.setButtonPrice(button: GuiObject, verb: string?, price: string)
	local label = faceLabel(button, "Label")
	local p = faceLabel(button, "Price")
	if not label or not p then
		return
	end
	p.Text = price
	p.Visible = true
	if verb and verb ~= "" then
		label.Visible = true
		label.Text = styleText(button, verb)
		label.Size = UDim2.new(label.Size.X.Scale, label.Size.X.Offset, 0.44, -4)
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(label.Position.X.Scale, label.Position.X.Offset, 0, 5)
		p.Size = UDim2.new(1, -16, 0.56, -6)
	else
		label.Visible = false
		p.Size = UDim2.new(1, -16, 1, -12)
		p.Position = UDim2.new(0.5, 0, 1, -6)
	end
	if verb and verb ~= "" then
		p.Position = UDim2.new(0.5, 0, 1, -3)
	end
end

function UIKit.setButtonVariant(button: GuiObject, name: string)
	applyVariant(button, variantOf(name, nil, nil))
end

-- Совместимость: цвет-токен → вариант
function UIKit.setButtonColor(button: GuiObject, color: Color3, dark: Color3?)
	applyVariant(button, variantOf(nil, color, dark))
end

-- Лейбл кнопки по имени ("Label" или "Price") — например, подкрасить цену, если не хватает
function UIKit.buttonPart(button: GuiObject, name: string): TextLabel?
	return faceLabel(button, name)
end

-- Плашка (простой фон окна-подсказки и т.п.): Night800, скругление, обводка Ink
function UIKit.panel(props: Props): Frame
	local base: Props = {
		BackgroundColor3 = Theme.Night800,
		Active = true, -- поглощает касания, чтобы они не "проваливались" в мир
	}
	for k, v in props do
		base[k] = v
	end
	local frame = UIKit.new("Frame", base) :: Frame
	UIKit.corner(frame, Theme.Corner)
	UIKit.stroke(frame, 3, Theme.Ink)
	return frame
end

----------------------------------------------------------------------
-- Масштабирование под экран
----------------------------------------------------------------------
export type ScaleMode = "hud" | "modal"

type ScaledEntry = {
	scale: UIScale,
	mode: ScaleMode,
	designW: number,
	designH: number,
}

local scaled: { ScaledEntry } = {}

local function viewportSize(): Vector2
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

-- Телефон: сенсорный экран и низкая сторона меньше 500 точек (планшеты больше).
function UIKit.isPhone(): boolean
	local vp = viewportSize()
	return UIKit.isTouch() and math.min(vp.X, vp.Y) < 500
end

local function computeScale(entry: ScaledEntry): number
	local vp = viewportSize()
	local touch = UIKit.isTouch()
	local phone = touch and math.min(vp.X, vp.Y) < 500
	if entry.mode == "hud" then
		local s = math.min(vp.Y / 720, vp.X / 1100)
		if phone then
			return math.clamp(s * 0.95, 0.5, 0.85)
		end
		return math.clamp(s, 0.62, 1.3)
	end
	local fw, fh = if phone then 0.9 else 0.92, if phone then 0.86 else 0.88
	local s = math.min(vp.X * fw / entry.designW, vp.Y * fh / entry.designH)
	return math.clamp(s, 0.3, 1.25)
end

function UIKit.autoScale(object: GuiObject, mode: ScaleMode, designW: number?, designH: number?): UIScale
	local scale = UIKit.new("UIScale", { Parent = object }) :: UIScale
	local entry: ScaledEntry = {
		scale = scale,
		mode = mode,
		designW = designW or 1280,
		designH = designH or 720,
	}
	table.insert(scaled, entry)
	scale.Scale = computeScale(entry)
	scale:SetAttribute("BaseScale", scale.Scale)
	scale.Destroying:Connect(function()
		local i = table.find(scaled, entry)
		if i then
			table.remove(scaled, i)
		end
	end)
	return scale
end

local function refreshAll()
	for _, entry in scaled do
		local s = computeScale(entry)
		entry.scale.Scale = s
		entry.scale:SetAttribute("BaseScale", s)
	end
end

local cameraConn: RBXScriptConnection? = nil
local function bindCamera()
	if cameraConn then
		cameraConn:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshAll)
	end
	refreshAll()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
UIKit.onInputTypeChanged(refreshAll)
bindCamera()

----------------------------------------------------------------------
-- Окна: появление с пружинкой и размытие фона
----------------------------------------------------------------------
local blur = Lighting:FindFirstChild("UIBlur") :: BlurEffect?
if not blur then
	local b = Instance.new("BlurEffect")
	b.Name = "UIBlur"
	b.Size = 0
	b.Enabled = true
	b.Parent = Lighting
	blur = b
end
local openModals = 0

function UIKit.popIn(frame: GuiObject, scale: UIScale)
	local target = (scale:GetAttribute("BaseScale") :: number?) or scale.Scale
	scale.Scale = target * 0.85
	frame.Visible = true
	UIKit.tween(scale, 0.25, { Scale = target }, Enum.EasingStyle.Back)
end

function UIKit.popOut(frame: GuiObject, scale: UIScale, onDone: (() -> ())?)
	local target = (scale:GetAttribute("BaseScale") :: number?) or scale.Scale
	local t = UIKit.tween(scale, 0.12, { Scale = target * 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	t.Completed:Once(function()
		frame.Visible = false
		scale.Scale = target
		if onDone then
			onDone()
		end
	end)
end

function UIKit.modalOpened()
	openModals += 1
	local b = blur
	if b then
		UIKit.tween(b, 0.2, { Size = 10 })
	end
end

function UIKit.modalClosed()
	openModals = math.max(0, openModals - 1)
	local b = blur
	if b and openModals == 0 then
		UIKit.tween(b, 0.2, { Size = 0 })
	end
end

-- Короткий "пульс" элемента (счётчик монет при начислении и т.п.)
function UIKit.bump(scale: UIScale, amount: number?)
	local base = (scale:GetAttribute("BaseScale") :: number?) or 1
	scale.Scale = base * (1 + (amount or 0.12))
	UIKit.tween(scale, 0.25, { Scale = base }, Enum.EasingStyle.Back)
end

----------------------------------------------------------------------
-- Звуки интерфейса (как и клик, подставляются контроллером звуков)
----------------------------------------------------------------------
local soundHandler: ((name: string) -> ())? = nil
function UIKit.setSoundHandler(fn: (name: string) -> ())
	soundHandler = fn
end
function UIKit.playSound(name: string)
	local fn = soundHandler
	if fn then
		fn(name)
	end
end

----------------------------------------------------------------------
-- Прокрутка, полоса-«батарейка», значок-ромб
----------------------------------------------------------------------
function UIKit.scroll(props: Props): ScrollingFrame
	local base: Props = {
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.LineLight,
		ScrollBarImageTransparency = 0.2,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Selectable = false,
		Active = true,
	}
	for k, v in props do
		base[k] = v
	end
	return UIKit.new("ScrollingFrame", base) :: ScrollingFrame
end

export type BarOptions = {
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	Back: Color3?,
	TextSize: number?,
	LayoutOrder: number?,
	Name: string?,
	Parent: Instance?,
	Ticks: boolean?, -- деления каждые 25% (по умолчанию да)
	Terminal: boolean?, -- «клемма» справа (по умолчанию да)
}

export type Bar = {
	Frame: Frame,
	Fill: Frame,
	Label: TextLabel,
	set: (fraction: number, text: string?, instant: boolean?) -> (),
	setColor: (color: Color3) -> (),
}

-- Полоса-«батарейка» (§8.4): трек-колодец, заливка Hi → основа, деления, клемма справа, подпись с обводкой
function UIKit.bar(opts: BarOptions): Bar
	local frame = UIKit.new("Frame", {
		Name = opts.Name or "Bar",
		Size = opts.Size,
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		BackgroundColor3 = opts.Back or Theme.Well,
		LayoutOrder = opts.LayoutOrder or 0,
	}) :: Frame
	UIKit.corner(frame, 6)
	UIKit.stroke(frame, 2.5, Theme.Ink)
	if opts.Terminal ~= false then
		local term = UIKit.new("Frame", {
			Name = "Terminal",
			Size = UDim2.new(0, 6, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, 2, 0.5, 0),
			BackgroundColor3 = Theme.Ink,
			Parent = frame,
		})
		UIKit.corner(term, 2)
	end
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 1,
		Parent = frame,
	}) :: Frame
	UIKit.corner(fill, 6)
	local grad = UIKit.gradient(fill, WHITE, WHITE)
	local function setColor(color: Color3)
		local t = UIKit.tones(color)
		grad.Color = ColorSequence.new(t.Hi, t.Base)
	end
	setColor(opts.Color or Theme.Go)
	if opts.Ticks ~= false then
		for i = 1, 3 do
			UIKit.new("Frame", {
				Name = "Tick" .. i,
				Size = UDim2.new(0, 2, 1, -4),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(i / 4, 0.5),
				BackgroundColor3 = Theme.Ink,
				BackgroundTransparency = 0.5,
				ZIndex = 2,
				Parent = frame,
			})
		end
	end
	local label = UIKit.label({
		Name = "Label",
		Text = "",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -12, 1, -2),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = opts.TextSize or 18,
		NoStroke = false,
		ZIndex = 3,
		Parent = frame,
	})
	local current = -1
	local function set(fraction: number, text: string?, instant: boolean?)
		local f = math.clamp(if fraction == fraction then fraction else 0, 0, 1)
		if text then
			label.Text = text
		end
		if math.abs(f - current) < 0.0005 then
			return
		end
		current = f
		fill.Visible = f > 0.002
		if instant then
			fill.Size = UDim2.fromScale(f, 1)
		else
			UIKit.tween(fill, 0.25, { Size = UDim2.fromScale(f, 1) })
		end
	end
	if opts.Parent then
		frame.Parent = opts.Parent
	end
	return { Frame = frame, Fill = fill, Label = label, set = set, setColor = setColor }
end

-- Значок уведомления (§8.4): ромб Danger с обводкой и неповёрнутый «!» поверх, пульсирует, пока виден
function UIKit.badge(parent: GuiObject, text: string?, size: number?): Frame
	local s = size or 26
	local badge = UIKit.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(s, s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -math.floor(s * 0.25), 0, math.floor(s * 0.25)),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Visible = false,
		Parent = parent,
	}) :: Frame
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = badge }) :: UIScale
	local diamond = UIKit.new("Frame", {
		Name = "Diamond",
		Size = UDim2.fromScale(0.74, 0.74),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = Theme.Danger,
		ZIndex = 8,
		Parent = badge,
	}) :: Frame
	UIKit.corner(diamond, 3)
	UIKit.stroke(diamond, 2, Theme.Ink)
	UIKit.gradient(diamond, Theme.DangerHi:Lerp(Theme.Danger, 0.5), Theme.Danger, 45)
	UIKit.label({
		Name = "Label",
		Text = text or "!",
		FontFace = Theme.FontDisplayFlat,
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = math.floor(s * 0.62),
		ZIndex = 9,
		Parent = badge,
	})
	local pulse: Tween? = nil
	local function refresh()
		if badge.Visible and not pulse then
			scale.Scale = 1
			pulse = TweenService:Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.15 })
			local tw = pulse
			if tw then
				tw:Play()
			end
		elseif not badge.Visible and pulse then
			pulse:Cancel()
			pulse = nil
			scale.Scale = 1
		end
	end
	badge:GetPropertyChangedSignal("Visible"):Connect(refresh)
	return badge
end

-- Тег (§8.4, роль L): плашка Ink со скруглением 6 и подписью Nunito 800 ЗАГЛАВНЫМИ
function UIKit.tag(props: Props, text: string, textSize: number?, color: Color3?): (Frame, TextLabel)
	local base: Props = {
		Name = "Tag",
		Size = UDim2.fromOffset(120, 24),
		BackgroundColor3 = color or Theme.Ink,
	}
	for k, v in props do
		base[k] = v
	end
	local frame = UIKit.new("Frame", base) :: Frame
	UIKit.corner(frame, Theme.CornerTag)
	UIKit.stroke(frame, 2, Theme.Ink)
	local label = UIKit.label({
		Name = "Text",
		Text = UIKit.upper(text),
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -10, 1, -4),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = textSize or 16,
		ZIndex = frame.ZIndex,
		Parent = frame,
	})
	return frame, label
end

----------------------------------------------------------------------
-- Строка состояния с нарисованным знаком слева (вместо ✔ 🔒 📍 ❌ в тексте): set(глиф, текст, цвет).
-- Глифы создаются один раз на вид и переиспользуются
----------------------------------------------------------------------
export type Status = { Frame: Frame, Label: TextLabel, set: (glyph: string?, text: string, color: Color3) -> () }

function UIKit.status(parent: Instance, size: UDim2, position: UDim2, textSize: number, font: Font?): Status
	local frame = UIKit.new("Frame", {
		Name = "Status",
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	local g = math.floor(textSize * 1.05)
	local label = UIKit.label({
		Name = "Text",
		Text = "",
		FontFace = font or Theme.FontBodyHeavy,
		Size = UDim2.new(1, -(g + 6), 1, 0),
		Position = UDim2.fromOffset(g + 6, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = textSize,
		Parent = frame,
	})
	local glyphs: { [string]: Frame } = {}
	local function set(glyph: string?, text: string, color: Color3)
		label.Text = text
		label.TextColor3 = color
		for k, f in glyphs do
			f.Visible = k == glyph
		end
		if glyph then
			local f = glyphs[glyph]
			if not f then
				f = UIKit.glyph(frame, glyph, {
					Name = "Glyph_" .. glyph,
					Size = UDim2.fromOffset(g, g),
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 0, 0.5, 0),
					Stroke = 2,
				})
				glyphs[glyph] = f
			end
			UIKit.setGlyphColor(f, color)
			label.Position = UDim2.fromOffset(g + 6, 0)
			label.Size = UDim2.new(1, -(g + 6), 1, 0)
		else
			label.Position = UDim2.fromOffset(0, 0)
			label.Size = UDim2.fromScale(1, 1)
		end
	end
	return { Frame = frame, Label = label, set = set }
end

-- Квадратик Go с галочкой (надет, забрано)
function UIKit.checkBadge(parent: Instance, size: number, props: Props?): Frame
	local base: Props = {
		Name = "Check",
		Size = UDim2.fromOffset(size, size),
		Rotation = -6,
		BackgroundColor3 = WHITE,
		ZIndex = 5,
		Visible = false,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local f = UIKit.new("Frame", base) :: Frame
	UIKit.corner(f, math.max(4, math.floor(size * 0.25)))
	UIKit.stroke(f, 2, Theme.Ink)
	UIKit.gradient(f, Theme.GoHi:Lerp(Theme.Go, 0.4), Theme.GoLo)
	UIKit.glyph(f, "check", { Name = "Glyph", Size = UDim2.fromScale(0.7, 0.7), Stroke = 2, ZIndex = f.ZIndex })
	f.Parent = parent
	return f
end

-- Значок-иконка с цифрой (номер острова): Montserrat Black Italic с обводкой
function UIKit.numberBadge(parent: Instance?, text: string, accent: Color3, size: number, props: Props?): Frame
	local badge = UIKit.iconBadge(parent, text, accent, size, props)
	local l = badge:FindFirstChild("Glyph")
	if l and l:IsA("TextLabel") then
		l.FontFace = Theme.FontDisplay
		l.TextColor3 = Theme.Cream
		l.Size = UDim2.fromScale(0.8, 0.8)
		UIKit.textStroke(l, 2.5)
	end
	return badge
end

----------------------------------------------------------------------
-- Карточка (§8.4): градиент Night700 → Night800, тонкая светлая обводка, внутренняя тень снизу.
-- Карточка редкости: полоса цвета редкости сверху и подложка этого цвета (rarityCard)
----------------------------------------------------------------------
local CARD_STROKE_T = 0.7

local function cardSeq(top: Color3, bottom: Color3, stripe: Color3?): ColorSequence
	local shade = bottom:Lerp(Theme.Ink, 0.55)
	if stripe then
		return UIKit.seq({
			{ 0, stripe },
			{ 0.045, stripe },
			{ 0.05, top },
			{ 0.93, bottom },
			{ 0.95, shade },
			{ 1, shade },
		})
	end
	return UIKit.seq({ { 0, top }, { 0.93, bottom }, { 0.95, shade }, { 1, shade } })
end

function UIKit.card(props: Props): Frame
	local base: Props = {
		BackgroundColor3 = WHITE,
		Active = false,
	}
	for k, v in props do
		base[k] = v
	end
	local frame = UIKit.new("Frame", base) :: Frame
	UIKit.corner(frame, Theme.CornerSmall)
	UIKit.stroke(frame, 1.5, Theme.LineLight, CARD_STROKE_T)
	UIKit.new("UIGradient", { Name = "CardGrad", Rotation = 90, Color = cardSeq(Theme.Night700, Theme.Night800, nil), Parent = frame })
	return frame
end

-- Перекрасить карточку (верх/низ; полоса сверху — по желанию)
function UIKit.tintCard(card: GuiObject, top: Color3, bottom: Color3, stripe: Color3?)
	local grad = card:FindFirstChild("CardGrad")
	if grad and grad:IsA("UIGradient") then
		grad.Color = cardSeq(top, bottom, stripe)
	end
end

-- Карточка редкости: полоса 6 px цвета редкости сверху, подложка цвета редкости (15%)
function UIKit.rarityCard(card: GuiObject, color: Color3)
	UIKit.tintCard(card, Theme.Night700:Lerp(color, 0.16), Theme.Night800:Lerp(color, 0.1), color)
end

-- Выбранная карточка: обводка Volt 3, масштаб 1.04, наклон −1.5°
function UIKit.selectCard(card: GuiObject, on: boolean)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if on then Theme.Volt else Theme.LineLight
		stroke.Thickness = if on then 3 else 1.5
		stroke.Transparency = if on then 0 else CARD_STROKE_T
	end
	local found = card:FindFirstChild("SelectScale")
	local scale: UIScale = if found and found:IsA("UIScale")
		then found
		else UIKit.new("UIScale", { Name = "SelectScale", Scale = 1, Parent = card }) :: UIScale
	scale.Scale = if on then 1.04 else 1
	card.Rotation = if on then -1.5 else 0
	card.ZIndex = if on then 2 else 1
end

-- Вспышка обводки карточки (покупка)
function UIKit.flashCard(card: GuiObject)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.Volt
		stroke.Thickness = 5
		stroke.Transparency = 0
		UIKit.tween(stroke, 0.5, { Thickness = 1.5, Color = Theme.LineLight, Transparency = CARD_STROKE_T })
	end
end

----------------------------------------------------------------------
-- 3D-превью (ViewportFrame) и камера вокруг модели
----------------------------------------------------------------------
function UIKit.viewport(props: Props): (ViewportFrame, Camera)
	local base: Props = {
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 160, 200),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
	}
	for k, v in props do
		base[k] = v
	end
	local vp = UIKit.new("ViewportFrame", base) :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.Parent = vp
	vp.CurrentCamera = camera
	return vp, camera
end

-- 3D-превью на тёмной плашке-колодце со светлым «полом» (§8.4): плашка по props, превью внутри
function UIKit.previewWell(props: Props): (Frame, ViewportFrame, Camera)
	local base: Props = {
		Name = "PreviewWell",
		BackgroundColor3 = Theme.Well,
		BackgroundTransparency = 0.15,
	}
	for k, v in props do
		base[k] = v
	end
	local well = UIKit.new("Frame", base) :: Frame
	UIKit.corner(well, Theme.CornerSmall)
	local floor = UIKit.new("Frame", {
		Name = "Floor",
		Size = UDim2.fromScale(1, 0.5),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Night600,
		ZIndex = well.ZIndex,
		Parent = well,
	}) :: Frame
	UIKit.corner(floor, Theme.CornerSmall)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.15),
		}),
		Parent = floor,
	})
	local vp, cam = UIKit.viewport({
		Name = "Preview",
		Size = UDim2.fromScale(1, 1),
		ZIndex = well.ZIndex,
		Parent = well,
	})
	return well, vp, cam
end

-- Центр модели и расстояние камеры, чтобы модель целиком помещалась в кадр
function UIKit.frameModel(model: Model, fov: number, zoom: number?): (Vector3, number)
	local cf, size = model:GetBoundingBox()
	local radius = math.max(0.5, size.Magnitude / 2)
	local dist = radius / math.sin(math.rad(fov / 2)) * (zoom or 1)
	return cf.Position, dist
end

-- Камера на орбите вокруг точки: yaw — поворот вокруг вертикали (0 — смотрим модели в лицо,
-- перёд моделей смотрит в −Z), pitch — насколько сверху
function UIKit.orbit(camera: Camera, center: Vector3, dist: number, yaw: number, pitch: number?)
	camera.CFrame = CFrame.new(center)
		* CFrame.Angles(0, yaw + math.pi, 0)
		* CFrame.Angles(-(pitch or 0.3), 0, 0)
		* CFrame.new(0, 0, dist)
end

----------------------------------------------------------------------
-- Чип валюты (§8.4): плашка Ink, жёсткая тень, значок-иконка выступает за левый край, число D3
----------------------------------------------------------------------
export type Chip = { Frame: Frame, Value: TextLabel, Badge: Frame, Scale: UIScale }

function UIKit.chip(parent: Instance, name: string, w: number, h: number, icon: string, color: Color3, order: number?): Chip
	local t = UIKit.tones(color)
	local holder = UIKit.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(w, h + 4),
		BackgroundTransparency = 1,
		LayoutOrder = order or 0,
		Parent = parent,
	}) :: Frame
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = holder }) :: UIScale
	local shadow = UIKit.new("Frame", {
		Name = "Shadow",
		Size = UDim2.new(1, 0, 0, h),
		Position = UDim2.fromOffset(0, 4),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.25,
		Parent = holder,
	})
	UIKit.corner(shadow, Theme.CornerSmall)
	local plate = UIKit.new("Frame", {
		Name = "Plate",
		Size = UDim2.new(1, 0, 0, h),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.15,
		Parent = holder,
	}) :: Frame
	UIKit.corner(plate, Theme.CornerSmall)
	UIKit.stroke(plate, 2.5, Theme.Ink)
	UIKit.new("Frame", {
		Name = "Line",
		Size = UDim2.new(1, -math.floor(h * 0.9), 0, 2),
		Position = UDim2.fromOffset(math.floor(h * 0.75), 4),
		BackgroundColor3 = Theme.LineLight,
		BackgroundTransparency = 0.6,
		Parent = plate,
	})
	local bs = h + 4
	local badge = UIKit.iconBadge(holder, icon, color, bs, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -10, 0, math.floor(h / 2)),
		ZIndex = 3,
	})
	local value = UIKit.label({
		Name = "Value",
		Text = "0",
		FontFace = Theme.FontNumber,
		Size = UDim2.new(1, -(bs + 2), 0, math.floor(h * 0.86)),
		Position = UDim2.new(0, bs - 2, 0, math.floor(h / 2)),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = math.floor(h * 0.74),
		NoStroke = false,
		ZIndex = 2,
		Parent = holder,
	})
	local s = value:FindFirstChildOfClass("UIStroke")
	if s then
		s.Thickness = 2.5
	end
	UIKit.gradientText(value, t.Hi, t.Base)
	return { Frame = holder, Value = value, Badge = badge, Scale = scale }
end

----------------------------------------------------------------------
-- Окна (§8.4): тень, тело с двойной рамкой, лента-заголовок с наклоном −2° (выступает влево, как наклейка),
-- значок слева на ленте, полоска акцента по низу ленты, крестик из двух брусков. Вкладки — колодец.
-- Одновременно открыто только одно окно — открытие нового закрывает текущее.
----------------------------------------------------------------------
export type TabDef = { Id: string, Text: string }

export type WindowOptions = {
	Name: string,
	Title: string,
	Icon: string?,
	Width: number?, -- размер макета (масштабируется под экран)
	Height: number?,
	Accent: Color3?,
	Tabs: { TabDef }?,
	DisplayOrder: number?,
	Parent: Instance?,
	OnOpen: ((tab: string?) -> ())?,
	OnClose: (() -> ())?,
	OnTab: ((id: string) -> ())?,
}

export type Window = {
	Name: string,
	Gui: ScreenGui,
	Root: Frame, -- масштабируемая рамка окна
	Scale: UIScale,
	Header: Frame, -- лента заголовка (сюда можно добавить счётчик валюты)
	Body: Frame, -- область содержимого под заголовком и вкладками
	Pages: { [string]: Frame }, -- по странице на вкладку
	open: (tab: string?) -> (),
	close: (instant: boolean?) -> (),
	isOpen: () -> boolean,
	tab: () -> string?,
	setTab: (id: string) -> (),
	setTabBadge: (id: string, on: boolean) -> (),
	setTitle: (text: string) -> (),
	confirm: (text: string, yesText: string, onYes: () -> (), yesColor: Color3?) -> (),
}

UIKit.HeaderHeight = 80
UIKit.TabHeight = 70
local RIBBON_H = 64
local RIBBON_X = -12
local RIBBON_Y = 4

local currentWindow: Window? = nil

-- "Pets:cocoons" -> ("Pets", "cocoons")
function UIKit.parseWindowName(name: string): (string, string?)
	local base, tab = string.match(name, "^([^:]+):(.+)$")
	if base and tab then
		return base, tab
	end
	return name, nil
end

function UIKit.currentWindow(): string?
	local w = currentWindow
	return if w then w.Name else nil
end

function UIKit.closeWindows()
	local w = currentWindow
	if w then
		w.close()
	end
end

-- Счётчик валюты на ленте окна (левее края ленты): возвращает подпись для числа
function UIKit.headerCounter(win: Window, icon: string, color: Color3, width: number?): TextLabel
	local w = width or 196
	local t = UIKit.tones(color)
	local title = win.Header:FindFirstChild("Title")
	if title and title:IsA("GuiObject") then
		title.Size = UDim2.new(1, -(86 + w + 22), 1, -14)
	end
	local well = UIKit.new("Frame", {
		Name = "Counter",
		Size = UDim2.fromOffset(w, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, -2),
		BackgroundColor3 = Theme.Well,
		ZIndex = 3,
		Parent = win.Header,
	}) :: Frame
	UIKit.corner(well, 8)
	UIKit.stroke(well, 2, Theme.LineLight, 0.6)
	UIKit.label({
		Name = "Icon",
		Text = icon,
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		MaxTextSize = 28,
		ZIndex = 4,
		Parent = well,
	})
	local value = UIKit.label({
		Name = "Value",
		Text = "0",
		FontFace = Theme.FontNumber,
		Size = UDim2.new(1, -56, 1, -8),
		Position = UDim2.new(0, 46, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 30,
		NoStroke = false,
		ZIndex = 4,
		Parent = well,
	})
	UIKit.gradientText(value, t.Hi, t.Base)
	return value
end

-- Вкладка-сегмент: активная — поднятая Spark-кнопка, неактивные — прозрачные с текстом TextDim
type TabButton = { button: TextButton, raised: Frame, label: TextLabel, badge: Frame }

local function makeTab(parent: Instance, t: TabDef, order: number, w: number, onClick: () -> ()): TabButton
	local button = UIKit.new("TextButton", {
		Name = "Tab_" .. t.Id,
		Size = UDim2.new(0, w, 1, 0),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}) :: TextButton
	local raised = UIKit.new("Frame", {
		Name = "Raised",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.SparkLo,
		Visible = false,
		Parent = button,
	}) :: Frame
	UIKit.corner(raised, 9)
	UIKit.stroke(raised, 2.5, Theme.Ink)
	local face = UIKit.new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -5),
		BackgroundColor3 = WHITE,
		Parent = raised,
	}) :: Frame
	UIKit.corner(face, 9)
	UIKit.gradient(face, Theme.SparkHi:Lerp(Theme.Spark, 0.35), Theme.Spark)
	UIKit.new("Frame", {
		Name = "TopLine",
		Size = UDim2.new(1, -16, 0, 2),
		Position = UDim2.fromOffset(8, 3),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.5,
		Parent = face,
	})
	local label = UIKit.label({
		Name = "Label",
		Text = t.Text,
		FontFace = Theme.FontBodyHeavy,
		TextColor3 = Theme.TextDim,
		Size = UDim2.new(1, -24, 1, -16),
		Position = UDim2.new(0.5, 0, 0.5, -2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 24,
		ZIndex = 2,
		Parent = button,
	})
	local badge = UIKit.badge(button, "!", 24)
	badge.Position = UDim2.new(1, -10, 0, 4)
	button.Activated:Connect(function()
		UIKit.playClick()
		onClick()
	end)
	return { button = button, raised = raised, label = label, badge = badge }
end

-- Роль S (§8.3.3): вкладки без обводки; на поднятой Spark-вкладке тёмный текст Ink, как на Volt-кнопке
local function setTabActive(tb: TabButton, on: boolean)
	tb.raised.Visible = on
	tb.label.TextColor3 = if on then Theme.Ink else Theme.TextDim
end

function UIKit.window(opts: WindowOptions): Window
	local w = opts.Width or 880
	local h = opts.Height or 560
	local accent = opts.Accent or Theme.Spark
	local at = UIKit.tones(accent)
	local parent: Instance = opts.Parent
		or (game:GetService("Players").LocalPlayer :: Player):WaitForChild("PlayerGui")

	local gui = UIKit.new("ScreenGui", {
		Name = "Window_" .. opts.Name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = opts.DisplayOrder or 20,
		Enabled = false,
		Parent = parent,
	}) :: ScreenGui
	local backdrop = UIKit.new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 6, 22),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Parent = gui,
	}) :: TextButton
	local root = UIKit.new("Frame", {
		Name = "Window",
		Size = UDim2.fromOffset(w, h),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Active = true,
		Visible = false,
		Parent = gui,
	}) :: Frame
	local scale = UIKit.autoScale(root, "modal", w, h + 16)
	-- на низких экранах (телефон) окно сдвигается вниз из-под верхней панели Roblox,
	-- насколько позволяет свободное место снизу
	local function placeRoot()
		local inset = game:GetService("GuiService"):GetGuiInset().Y
		local s = (scale:GetAttribute("BaseScale") :: number?) or scale.Scale
		local margin = math.max(0, (viewportSize().Y - h * s) / 2)
		local shift = math.clamp(inset - margin + 10 * s, 0, margin)
		root.Position = UDim2.new(0.5, 0, 0.5, math.floor(shift))
	end
	placeRoot()
	scale:GetAttributeChangedSignal("BaseScale"):Connect(placeRoot)

	-- 1. жёсткая тень
	local shadow = UIKit.new("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 8),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.4,
		ZIndex = 0,
		Parent = root,
	})
	UIKit.corner(shadow, Theme.Corner)
	-- 2. тело: градиент Night700 → Night900, обводка Ink
	local panel = UIKit.new("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		Active = true,
		Parent = root,
	}) :: Frame
	UIKit.corner(panel, Theme.Corner)
	UIKit.stroke(panel, 3, Theme.Ink)
	UIKit.gradient(panel, Theme.Night700, Theme.Night900)
	-- 3. внутренняя светлая рамка
	local inner = UIKit.new("Frame", {
		Name = "Inner",
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
		Parent = panel,
	}) :: Frame
	UIKit.corner(inner, 10)
	UIKit.stroke(inner, 2, Theme.LineLight, Theme.LineLightT)
	-- 4. тонкая линия-блик
	UIKit.new("Frame", {
		Name = "Gleam",
		Size = UDim2.new(1, -28, 0, 2),
		Position = UDim2.fromOffset(14, 6),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.85,
		Parent = panel,
	})

	-- 5. лента-заголовок: выступает за левый край, наклон −2°, полоска акцента по низу (градиентом —
	-- повторяет скругление), значок слева, заголовок D2
	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, -40, 0, RIBBON_H),
		Position = UDim2.fromOffset(RIBBON_X, RIBBON_Y),
		Rotation = -2,
		BackgroundColor3 = WHITE,
		ZIndex = 3,
		Parent = root,
	}) :: Frame
	UIKit.corner(header, 10)
	UIKit.stroke(header, 3, Theme.Ink)
	UIKit.new("UIGradient", {
		Name = "Grad",
		Rotation = 90,
		Color = UIKit.seq({
			{ 0, Theme.Night800 },
			{ 0.86, Theme.Ink },
			{ 0.875, at.Base },
			{ 1, at.Lo:Lerp(at.Base, 0.4) },
		}),
		Parent = header,
	})
	local ribbonShadow = UIKit.new("Frame", {
		Name = "HeaderShadow",
		Size = header.Size,
		Position = header.Position + UDim2.fromOffset(0, 6),
		Rotation = -2,
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.45,
		ZIndex = 2,
		Parent = root,
	}) :: Frame
	UIKit.corner(ribbonShadow, 10)
	local titleX = 22
	if opts.Icon then
		UIKit.iconBadge(header, opts.Icon, accent, 60, {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -6, 0.5, -4),
			ZIndex = 5,
		})
		titleX = 68
	end
	local title = UIKit.label({
		Name = "Title",
		Text = UIKit.upper(opts.Title),
		FontFace = Theme.FontDisplay,
		Size = UDim2.new(1, -(titleX + 16), 1, -14),
		Position = UDim2.new(0, titleX, 0.5, -3),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 40,
		NoStroke = false,
		ZIndex = 5,
		Parent = header,
	})
	local ts = title:FindFirstChildOfClass("UIStroke")
	if ts then
		ts.Thickness = 3
	end
	UIKit.italicPad(title, 6)
	UIKit.textShadow(title, 4)

	local win: Window
	local opened = false
	local selectedTab: string? = nil
	local tabButtons: { [string]: TabButton } = {}
	local pages: { [string]: Frame } = {}

	-- 6. «закрыть»: квадрат Danger, крестик из двух брусков, наклон +4°, выступает за угол
	local closeButton = UIKit.button({
		Name = "Close",
		Text = "",
		Color = Theme.Danger,
		Size = UDim2.fromOffset(56, 56),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 12, 0, -12),
		ZIndex = 6,
		Parent = root,
	}, function()
		win.close()
	end)
	closeButton.Rotation = 4
	local closeFace = closeButton:FindFirstChild("Face")
	if closeFace then
		UIKit.glyph(closeFace, "cross", {
			Name = "Cross",
			Size = UDim2.fromOffset(30, 30),
			Color = Theme.Cream,
			Stroke = 2,
			ZIndex = 7,
		})
	end

	local top = UIKit.HeaderHeight + 4
	local tabs = opts.Tabs
	if tabs and #tabs > 0 then
		local well = UIKit.new("Frame", {
			Name = "Tabs",
			Size = UDim2.new(1, -32, 0, UIKit.TabHeight - 12),
			Position = UDim2.fromOffset(16, top),
			BackgroundColor3 = Theme.Well,
			Parent = panel,
		}) :: Frame
		UIKit.corner(well, 12)
		UIKit.stroke(well, 1.5, Theme.LineLight, 0.75)
		UIKit.padding(well, 4, 4)
		UIKit.list(well, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left)
		local tabW = math.floor((w - 32 - 8 - 4 * (#tabs - 1)) / #tabs)
		for i, t in tabs do
			tabButtons[t.Id] = makeTab(well, t, i, tabW, function()
				win.setTab(t.Id)
			end)
		end
		top += UIKit.TabHeight - 4
	end

	local body = UIKit.new("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -32, 1, -(top + 14)),
		Position = UDim2.fromOffset(16, top + 2),
		BackgroundTransparency = 1,
		Parent = panel,
	}) :: Frame
	if tabs then
		for _, t in tabs do
			pages[t.Id] = UIKit.new("Frame", {
				Name = "Page_" .. t.Id,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = false,
				Parent = body,
			}) :: Frame
		end
	end

	-- подтверждение ("Точно удалить?")
	local overlay = UIKit.new("TextButton", {
		Name = "Confirm",
		Size = UDim2.new(1, 24, 1, 24),
		Position = UDim2.fromOffset(-12, -12),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.3,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		ZIndex = 20,
		Visible = false,
		Parent = root,
	}) :: TextButton
	UIKit.corner(overlay, Theme.Corner + 6)
	local boxShadow = UIKit.new("Frame", {
		Name = "BoxShadow",
		Size = UDim2.fromOffset(540, 280),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 8),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.2,
		Rotation = -1,
		ZIndex = 21,
		Parent = overlay,
	}) :: Frame
	UIKit.corner(boxShadow, Theme.Corner)
	local box = UIKit.panel({
		Name = "Box",
		Size = UDim2.fromOffset(540, 280),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = WHITE,
		Rotation = -1,
		ZIndex = 22,
		Parent = overlay,
	})
	UIKit.gradient(box, Theme.Night700, Theme.Night900)
	local boxInner = UIKit.new("Frame", {
		Name = "Inner",
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = box,
	})
	UIKit.corner(boxInner, 10)
	UIKit.stroke(boxInner, 2, Theme.LineLight, Theme.LineLightT)
	local boxScale = UIKit.new("UIScale", { Scale = 1, Parent = box }) :: UIScale
	local confirmLabel = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -48, 0, 150),
		Position = UDim2.fromOffset(24, 18),
		MaxTextSize = 24,
		ZIndex = 23,
		Parent = box,
	})
	local confirmYes: (() -> ())? = nil
	local yesButton = UIKit.button({
		Name = "Yes",
		Text = "Да",
		Color = Theme.Danger,
		Size = UDim2.fromOffset(220, 68),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -10, 1, -20),
		ZIndex = 23,
		Parent = box,
	}, function()
		overlay.Visible = false
		local fn = confirmYes
		confirmYes = nil
		if fn then
			fn()
		end
	end)
	UIKit.button({
		Name = "No",
		Text = "Нет",
		Color = Theme.Slate,
		Size = UDim2.fromOffset(220, 68),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 10, 1, -20),
		ZIndex = 23,
		Parent = box,
	}, function()
		overlay.Visible = false
		confirmYes = nil
	end)
	overlay.Activated:Connect(function()
		overlay.Visible = false
		confirmYes = nil
	end)

	local function setTab(id: string)
		if not pages[id] then
			return
		end
		local changed = selectedTab ~= id
		selectedTab = id
		for tid, b in tabButtons do
			setTabActive(b, tid == id)
		end
		for pid, page in pages do
			page.Visible = pid == id
		end
		if changed and opts.OnTab then
			opts.OnTab(id)
		end
	end

	local function close(instant: boolean?)
		if not opened then
			return
		end
		opened = false
		if currentWindow == win then
			currentWindow = nil
		end
		overlay.Visible = false
		confirmYes = nil
		UIKit.modalClosed()
		if instant then
			root.Visible = false
			gui.Enabled = false
		else
			UIKit.tween(backdrop, 0.15, { BackgroundTransparency = 1 })
			UIKit.popOut(root, scale, function()
				-- окно могли снова открыть, пока шла анимация закрытия
				if opened then
					root.Visible = true
				else
					gui.Enabled = false
				end
			end)
		end
		if opts.OnClose then
			opts.OnClose()
		end
	end

	local headerPos = header.Position
	local function open(tab: string?)
		local cur = currentWindow
		if cur and cur ~= win then
			cur.close(true)
		end
		if tab and pages[tab] then
			setTab(tab)
		elseif not selectedTab and tabs and tabs[1] then
			setTab(tabs[1].Id)
		end
		if opened then
			return
		end
		opened = true
		currentWindow = win
		gui.Enabled = true
		backdrop.BackgroundTransparency = 1
		UIKit.tween(backdrop, 0.2, { BackgroundTransparency = 0.45 })
		UIKit.popIn(root, scale)
		-- лента выезжает слева
		header.Position = headerPos - UDim2.fromOffset(60, 0)
		task.delay(0.05, function()
			UIKit.tween(header, 0.2, { Position = headerPos }, Enum.EasingStyle.Back)
		end)
		UIKit.modalOpened()
		UIKit.playSound("Whoosh")
		if opts.OnOpen then
			opts.OnOpen(selectedTab)
		end
	end
	header:GetPropertyChangedSignal("Position"):Connect(function()
		ribbonShadow.Position = header.Position + UDim2.fromOffset(0, 6)
	end)

	local function confirm(text: string, yesText: string, onYes: () -> (), yesColor: Color3?)
		confirmLabel.Text = text
		UIKit.setButtonText(yesButton, yesText)
		UIKit.setButtonColor(yesButton, yesColor or Theme.Danger)
		confirmYes = onYes
		overlay.Visible = true
		boxScale.Scale = 0.85
		UIKit.tween(boxScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	backdrop.Activated:Connect(function()
		if overlay.Visible then
			overlay.Visible = false
			confirmYes = nil
			return
		end
		close()
	end)

	win = {
		Name = opts.Name,
		Gui = gui,
		Root = root,
		Scale = scale,
		Header = header,
		Body = body,
		Pages = pages,
		open = open,
		close = close,
		isOpen = function(): boolean
			return opened
		end,
		tab = function(): string?
			return selectedTab
		end,
		setTab = setTab,
		setTabBadge = function(id: string, on: boolean)
			local b = tabButtons[id]
			if b then
				b.badge.Visible = on
			end
		end,
		setTitle = function(text: string)
			title.Text = UIKit.upper(text)
		end,
		confirm = confirm,
	}
	return win
end

return UIKit
