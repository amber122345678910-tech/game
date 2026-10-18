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

return UIKit
