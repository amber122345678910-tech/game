--!strict
-- Помощники для интерфейса, созданного кодом.
-- Все окна рисуются в пикселях макета и масштабируются своим UIScale под экран,
-- поэтому одинаково выглядят на телефоне, планшете и ПК.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Theme = require(script.Parent.Theme)

local UIKit = {}

type Props = { [string]: any }

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

-- Круглое скругление (для иконок-кружков)
function UIKit.round(parent: Instance): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent })
end

function UIKit.stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Theme.Stroke,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function UIKit.textStroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or 2,
		Color = color or Theme.TextStroke,
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

-- Текст: TextScaled с ограничением размера и обводкой.
-- Служебные ключи: MaxTextSize, NoStroke.
function UIKit.label(props: Props): TextLabel
	local maxSize = props.MaxTextSize or 32
	local noStroke = props.NoStroke == true
	props.MaxTextSize = nil
	props.NoStroke = nil
	local base: Props = {
		BackgroundTransparency = 1,
		FontFace = Theme.Font,
		TextColor3 = Theme.Text,
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
-- Кнопка в стиле симуляторов: объёмная "таблетка" с нижней кромкой,
-- градиентом, обводкой и пружинкой при нажатии.
----------------------------------------------------------------------
export type ButtonOptions = {
	Text: string?,
	Icon: string?, -- эмодзи или короткий символ слева от текста
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

function UIKit.button(opts: ButtonOptions, onClick: (() -> ())?): TextButton
	local color = opts.Color or Theme.Green
	local dark = opts.ColorDark or color:Lerp(Color3.new(0, 0, 0), 0.4)
	local z = opts.ZIndex or 1
	local button = UIKit.new("TextButton", {
		Name = opts.Name or "Button",
		Size = opts.Size or UDim2.fromOffset(180, 56),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		BackgroundColor3 = dark,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = z,
		Active = true,
	}) :: TextButton
	UIKit.corner(button, Theme.CornerSmall)
	UIKit.stroke(button, 2.5, Theme.Stroke)
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = button }) :: UIScale

	-- лицевая часть чуть выше кромки — объём
	local face = UIKit.new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = z,
		Parent = button,
	}) :: Frame
	UIKit.corner(face, Theme.CornerSmall)
	local grad = UIKit.gradient(face, color:Lerp(Color3.new(1, 1, 1), 0.18), color)
	grad.Name = "Grad"
	-- блик сверху
	local shine = UIKit.new("Frame", {
		Name = "Shine",
		Size = UDim2.new(1, -10, 0.38, 0),
		Position = UDim2.fromOffset(5, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		ZIndex = z,
		Parent = face,
	})
	UIKit.corner(shine, Theme.CornerSmall - 2)

	local text = opts.Text or ""
	if opts.Icon then
		text = opts.Icon .. "  " .. text
	end
	local label = UIKit.label({
		Name = "Label",
		Text = text,
		Size = UDim2.new(1, -14, 1, -8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = opts.TextSize or 26,
		ZIndex = z + 1,
		Parent = face,
	})
	label:SetAttribute("Role", "ButtonLabel")

	local pressed = false
	button.MouseEnter:Connect(function()
		if UIKit.isMouse() and not pressed then
			UIKit.tween(scale, 0.12, { Scale = 1.05 })
		end
	end)
	button.MouseLeave:Connect(function()
		pressed = false
		UIKit.tween(scale, 0.12, { Scale = 1 })
		face.Position = UDim2.fromOffset(0, 0)
	end)
	button.MouseButton1Down:Connect(function()
		pressed = true
		UIKit.tween(scale, 0.07, { Scale = 0.93 })
		face.Position = UDim2.fromOffset(0, 3)
	end)
	button.MouseButton1Up:Connect(function()
		pressed = false
		UIKit.tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		face.Position = UDim2.fromOffset(0, 0)
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

function UIKit.setButtonText(button: GuiObject, text: string)
	local face = button:FindFirstChild("Face")
	local label = face and face:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function UIKit.setButtonColor(button: GuiObject, color: Color3, dark: Color3?)
	local face = button:FindFirstChild("Face")
	local grad = face and face:FindFirstChild("Grad")
	if grad and grad:IsA("UIGradient") then
		grad.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.18), color)
	end
	button.BackgroundColor3 = dark or color:Lerp(Color3.new(0, 0, 0), 0.4)
end

-- Панель с фоном, скруглением и обводкой.
function UIKit.panel(props: Props): Frame
	local base: Props = {
		BackgroundColor3 = Theme.Panel,
		Active = true, -- поглощает касания, чтобы они не "проваливались" в мир
	}
	for k, v in props do
		base[k] = v
	end
	local frame = UIKit.new("Frame", base) :: Frame
	UIKit.corner(frame, Theme.Corner)
	UIKit.stroke(frame, 3, Theme.Stroke)
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
	scale.Scale = target * 0.8
	frame.Visible = true
	UIKit.tween(scale, 0.28, { Scale = target }, Enum.EasingStyle.Back)
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
-- Прокрутка, полоска прогресса, значок-уведомление
----------------------------------------------------------------------
function UIKit.scroll(props: Props): ScrollingFrame
	local base: Props = {
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Electric,
		ScrollBarImageTransparency = 0.25,
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
}

export type Bar = {
	Frame: Frame,
	Fill: Frame,
	Label: TextLabel,
	set: (fraction: number, text: string?, instant: boolean?) -> (),
	setColor: (color: Color3) -> (),
}

-- Полоска прогресса: тёмная "таблетка" с цветной заливкой и подписью по центру
function UIKit.bar(opts: BarOptions): Bar
	local frame = UIKit.new("Frame", {
		Name = opts.Name or "Bar",
		Size = opts.Size,
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		BackgroundColor3 = opts.Back or Theme.PanelDark,
		LayoutOrder = opts.LayoutOrder or 0,
	}) :: Frame
	UIKit.round(frame)
	UIKit.stroke(frame, 2.5, Theme.Stroke)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 1,
		Parent = frame,
	}) :: Frame
	UIKit.round(fill)
	local grad = UIKit.gradient(fill, Color3.new(1, 1, 1), Color3.new(1, 1, 1))
	local function setColor(color: Color3)
		grad.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.3), color)
	end
	setColor(opts.Color or Theme.Green)
	local label = UIKit.label({
		Name = "Label",
		Text = "",
		Size = UDim2.new(1, -12, 1, -2),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = opts.TextSize or 20,
		ZIndex = 2,
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

-- Красный кружок с "!" в правом верхнем углу (что-то можно забрать или купить)
function UIKit.badge(parent: GuiObject, text: string?, size: number?): Frame
	local s = size or 26
	local badge = UIKit.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(s, s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -math.floor(s * 0.25), 0, math.floor(s * 0.25)),
		BackgroundColor3 = Theme.Red,
		ZIndex = 8,
		Visible = false,
		Parent = parent,
	}) :: Frame
	UIKit.round(badge)
	UIKit.stroke(badge, 2, Theme.Stroke)
	UIKit.label({
		Name = "Label",
		Text = text or "!",
		Size = UDim2.fromScale(0.78, 0.78),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = math.floor(s * 0.8),
		ZIndex = 9,
		Parent = badge,
	})
	return badge
end

-- Карточка внутри окна: светлее панели, с градиентом и обводкой
function UIKit.card(props: Props): Frame
	local base: Props = {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Active = false,
	}
	for k, v in props do
		base[k] = v
	end
	local frame = UIKit.new("Frame", base) :: Frame
	UIKit.corner(frame, Theme.CornerSmall)
	UIKit.stroke(frame, 2.5, Theme.Stroke)
	local grad = UIKit.gradient(frame, Theme.CardHover, Theme.Card)
	grad.Name = "CardGrad"
	return frame
end

-- Перекрасить карточку (например, в цвет редкости)
function UIKit.tintCard(card: GuiObject, top: Color3, bottom: Color3)
	local grad = card:FindFirstChild("CardGrad")
	if grad and grad:IsA("UIGradient") then
		grad.Color = ColorSequence.new(top, bottom)
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
-- Окна: затемнённый фон, рамка с заголовком, крестик, вкладки, подтверждение.
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
	Header: Frame, -- полоса заголовка (сюда можно добавить счётчик валюты)
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

-- Счётчик валюты в заголовке окна (левее крестика): возвращает подпись для числа
function UIKit.headerCounter(win: Window, icon: string, color: Color3, width: number?): TextLabel
	local w = width or 190
	-- заголовок уступает место счётчику (текст ужмётся сам)
	local title = win.Header:FindFirstChild("Title")
	if title and title:IsA("GuiObject") then
		title.Size = UDim2.new(1, -(110 + w + 12), 0.78, 0)
	end
	local pill = UIKit.new("Frame", {
		Name = "Counter",
		Size = UDim2.fromOffset(w, 48),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -80, 0.5, 0),
		BackgroundColor3 = Theme.PanelDark,
		ZIndex = 2,
		Parent = win.Header,
	}) :: Frame
	UIKit.round(pill)
	UIKit.stroke(pill, 2.5, Theme.Stroke)
	UIKit.label({
		Name = "Icon",
		Text = icon,
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		MaxTextSize = 30,
		NoStroke = true,
		ZIndex = 3,
		Parent = pill,
	})
	return UIKit.label({
		Name = "Value",
		Text = "0",
		FontFace = Theme.FontNumber,
		TextColor3 = color,
		Size = UDim2.new(1, -56, 1, -10),
		Position = UDim2.new(0, 46, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		MaxTextSize = 30,
		ZIndex = 3,
		Parent = pill,
	})
end

function UIKit.window(opts: WindowOptions): Window
	local w = opts.Width or 880
	local h = opts.Height or 560
	local accent = opts.Accent or Theme.ElectricDark
	local parent: Instance = opts.Parent
		or (game:GetService("Players").LocalPlayer :: Player):WaitForChild("PlayerGui")
	local white = Color3.new(1, 1, 1)
	local black = Color3.new(0, 0, 0)

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
		BackgroundColor3 = Color3.fromRGB(4, 6, 18),
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
	local scale = UIKit.autoScale(root, "modal", w, h)
	-- на низких экранах (телефон) окно сдвигается вниз из-под верхней панели Roblox,
	-- насколько позволяет свободное место снизу
	local function placeRoot()
		local inset = game:GetService("GuiService"):GetGuiInset().Y
		local s = (scale:GetAttribute("BaseScale") :: number?) or scale.Scale
		local margin = math.max(0, (viewportSize().Y - h * s) / 2)
		local shift = math.clamp(inset - margin, 0, margin)
		root.Position = UDim2.new(0.5, 0, 0.5, math.floor(shift))
	end
	placeRoot()
	scale:GetAttributeChangedSignal("BaseScale"):Connect(placeRoot)

	local panel = UIKit.panel({
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = white,
		Parent = root,
	})
	UIKit.gradient(panel, Theme.PanelLight, Theme.PanelDark)
	-- внутренняя светящаяся рамка — "двойной" бортик, как в симуляторах
	local inner = UIKit.new("Frame", {
		Name = "Inner",
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromOffset(5, 5),
		BackgroundTransparency = 1,
		Parent = panel,
	}) :: Frame
	UIKit.corner(inner, Theme.Corner - 4)
	UIKit.stroke(inner, 2, accent:Lerp(white, 0.35), 0.55)

	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, -16, 0, UIKit.HeaderHeight - 10),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = white,
		Parent = panel,
	}) :: Frame
	UIKit.corner(header, Theme.CornerSmall)
	UIKit.stroke(header, 2.5, Theme.Stroke)
	UIKit.gradient(header, accent:Lerp(white, 0.2), accent:Lerp(black, 0.35))
	local headerShine = UIKit.new("Frame", {
		Name = "Shine",
		Size = UDim2.new(1, -12, 0.4, 0),
		Position = UDim2.fromOffset(6, 3),
		BackgroundColor3 = white,
		BackgroundTransparency = 0.82,
		Parent = header,
	})
	UIKit.corner(headerShine, Theme.CornerSmall - 4)
	local title = UIKit.label({
		Name = "Title",
		Text = if opts.Icon then opts.Icon .. "  " .. opts.Title else opts.Title,
		Size = UDim2.new(1, -110, 0.78, 0),
		Position = UDim2.new(0, 18, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 40,
		ZIndex = 2,
		Parent = header,
	})

	local win: Window
	local opened = false
	local selectedTab: string? = nil
	local tabButtons: { [string]: TextButton } = {}
	local tabBadges: { [string]: Frame } = {}
	local pages: { [string]: Frame } = {}

	local closeButton = UIKit.button({
		Name = "Close",
		Text = "✕",
		Color = Theme.Red,
		Size = UDim2.fromOffset(66, 66),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 2),
		TextSize = 36,
		ZIndex = 3,
		Parent = header,
	}, function()
		win.close()
	end)
	closeButton.Name = "Close"

	local top = UIKit.HeaderHeight + 4
	local tabs = opts.Tabs
	if tabs and #tabs > 0 then
		local row = UIKit.new("Frame", {
			Name = "Tabs",
			Size = UDim2.new(1, -32, 0, UIKit.TabHeight - 6),
			Position = UDim2.fromOffset(16, top),
			BackgroundTransparency = 1,
			Parent = panel,
		}) :: Frame
		UIKit.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left)
		local tabW = math.min(230, math.floor((w - 32 - 10 * (#tabs - 1)) / #tabs))
		for i, t in tabs do
			local b = UIKit.button({
				Name = "Tab_" .. t.Id,
				Text = t.Text,
				Color = Theme.GrayDark,
				Size = UDim2.new(0, tabW, 1, 0),
				LayoutOrder = i,
				TextSize = 26,
				Parent = row,
			}, function()
				win.setTab(t.Id)
			end)
			tabButtons[t.Id] = b
			tabBadges[t.Id] = UIKit.badge(b, "!", 24)
		end
		top += UIKit.TabHeight
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
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = black,
		BackgroundTransparency = 0.35,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		ZIndex = 20,
		Visible = false,
		Parent = root,
	}) :: TextButton
	UIKit.corner(overlay, Theme.Corner)
	local box = UIKit.panel({
		Name = "Box",
		Size = UDim2.fromOffset(500, 250),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Theme.PanelLight,
		ZIndex = 21,
		Parent = overlay,
	})
	local boxScale = UIKit.new("UIScale", { Scale = 1, Parent = box }) :: UIScale
	local confirmLabel = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -40, 0, 120),
		Position = UDim2.fromOffset(20, 18),
		MaxTextSize = 30,
		ZIndex = 22,
		Parent = box,
	})
	local confirmYes: (() -> ())? = nil
	local yesButton = UIKit.button({
		Name = "Yes",
		Text = "Да",
		Color = Theme.Red,
		Size = UDim2.fromOffset(200, 68),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -10, 1, -18),
		ZIndex = 22,
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
		Color = Theme.Gray,
		Size = UDim2.fromOffset(200, 68),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 10, 1, -18),
		ZIndex = 22,
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
			if tid == id then
				UIKit.setButtonColor(b, Theme.Electric, Theme.ElectricDark)
			else
				UIKit.setButtonColor(b, Theme.GrayDark)
			end
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
		UIKit.modalOpened()
		UIKit.playSound("Whoosh")
		if opts.OnOpen then
			opts.OnOpen(selectedTab)
		end
	end

	local function confirm(text: string, yesText: string, onYes: () -> (), yesColor: Color3?)
		confirmLabel.Text = text
		UIKit.setButtonText(yesButton, yesText)
		UIKit.setButtonColor(yesButton, yesColor or Theme.Red)
		confirmYes = onYes
		overlay.Visible = true
		boxScale.Scale = 0.8
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
			local b = tabBadges[id]
			if b then
				b.Visible = on
			end
		end,
		setTitle = function(text: string)
			title.Text = text
		end,
		confirm = confirm,
	}
	return win
end

return UIKit
