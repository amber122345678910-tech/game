--!strict
-- Набор помощников для создания интерфейса кодом.
-- Каждая "панель" рисуется в пикселях макета (1280x720) и масштабируется своим UIScale
-- под размер экрана: так одинаково выглядит на телефоне, планшете и ПК.

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local UIKit = {}

type Props = { [string]: any }

-- Создать инстанс: свойства задаются до Parent (быстрее), дети подключаются в конце.
function UIKit.new(className: string, props: Props?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent: Instance? = nil
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0 -- по умолчанию у Instance.new рамка 1px
	end
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
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

function UIKit.stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Theme.PanelStroke,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UIKit.textStroke(parent: Instance, thickness: number?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or 2,
		Color = Theme.TextStroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
end

function UIKit.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
		Parent = parent,
	})
end

function UIKit.padding(parent: Instance, px: number): UIPadding
	return UIKit.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		Parent = parent,
	})
end

function UIKit.list(parent: Instance, direction: Enum.FillDirection, gap: number, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return UIKit.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Center,
		Parent = parent,
	})
end

-- Текст: TextScaled с ограничением максимального размера.
function UIKit.label(props: Props): TextLabel
	local maxSize = props.MaxTextSize or 32
	props.MaxTextSize = nil
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
	if props.NoStroke ~= true then
		UIKit.textStroke(label, 2)
	end
	return label
end

local clickSound: Sound? = nil

function UIKit.setClickSound(sound: Sound?)
	clickSound = sound
end

function UIKit.playClick()
	local s = clickSound
	if s then
		SoundService:PlayLocalSound(s)
	end
end

function UIKit.tween(obj: Instance, time: number, props: Props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

export type ButtonOptions = {
	Text: string?,
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
}

-- Кнопка в стиле симуляторов: градиент, обводка, "пружинка" при нажатии.
function UIKit.button(opts: ButtonOptions, onClick: (() -> ())?): TextButton
	local color = opts.Color or Theme.Green
	local dark = opts.ColorDark or color:Lerp(Color3.new(0, 0, 0), 0.35)
	local button = UIKit.new("TextButton", {
		Name = opts.Name or "Button",
		Size = opts.Size or UDim2.fromOffset(180, 56),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = opts.ZIndex or 1,
		Active = true,
	}) :: TextButton
	UIKit.corner(button, Theme.CornerSmall)
	UIKit.stroke(button, 3, Theme.PanelStroke)
	local gradient = UIKit.gradient(button, color, dark)
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = button }) :: UIScale
	local label = UIKit.label({
		Name = "Label",
		Text = opts.Text or "",
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = opts.TextSize or 28,
		ZIndex = (opts.ZIndex or 1) + 1,
		Parent = button,
	})
	label:SetAttribute("Role", "ButtonLabel")

	button.MouseEnter:Connect(function()
		-- на тач-экранах MouseEnter может "залипнуть" без MouseLeave
		if UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
			UIKit.tween(scale, 0.12, { Scale = 1.05 })
		end
	end)
	button.MouseLeave:Connect(function()
		UIKit.tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, 0.06, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(function()
		UIKit.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	if onClick then
		button.Activated:Connect(function()
			UIKit.playClick()
			onClick()
		end)
	end
	button:SetAttribute("BaseColor", color)
	button:SetAttribute("DarkColor", dark)
	local _ = gradient
	if opts.Parent then
		button.Parent = opts.Parent
	end
	return button
end

function UIKit.setButtonText(button: TextButton, text: string)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function UIKit.setButtonColor(button: TextButton, color: Color3, dark: Color3?)
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(color, dark or color:Lerp(Color3.new(0, 0, 0), 0.35))
	end
end

-- Панель с фоном, скруглением и обводкой.
function UIKit.panel(props: Props): Frame
	local base: Props = {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Active = true, -- поглощает касания, чтобы они не "проваливались" в мир
	}
	for k, v in props do
		base[k] = v
	end
	local frame = UIKit.new("Frame", base) :: Frame
	UIKit.corner(frame, Theme.Corner)
	UIKit.stroke(frame, 3, Theme.PanelStroke)
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

local function computeScale(entry: ScaledEntry): number
	local vp = viewportSize()
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	if entry.mode == "hud" then
		local s = math.min(vp.Y / 720, vp.X / 1100)
		-- на телефоне не даём кнопкам стать меньше удобного для пальца размера
		return math.clamp(s, if touch then 0.72 else 0.62, 1.35)
	end
	-- модальное окно целиком помещается на экран
	local s = math.min(vp.X * 0.94 / entry.designW, vp.Y * 0.9 / entry.designH)
	return math.clamp(s, 0.4, 1.3)
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
	scale.Destroying:Connect(function()
		local i = table.find(scaled, entry)
		if i then
			table.remove(scaled, i)
		end
	end)
	return scale
end

function UIKit.currentHudScale(): number
	return computeScale({ scale = nil :: any, mode = "hud", designW = 1280, designH = 720 })
end

local function refreshAll()
	for _, entry in scaled do
		entry.scale.Scale = computeScale(entry)
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
UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refreshAll)
bindCamera()

-- Плавное появление окна.
function UIKit.popIn(frame: GuiObject, scale: UIScale)
	local target = scale.Scale
	scale.Scale = target * 0.85
	frame.Visible = true
	UIKit.tween(scale, 0.22, { Scale = target }, Enum.EasingStyle.Back)
end

-- Форматирование чисел: 1234 -> 1.2K
function UIKit.formatNumber(n: number): string
	local abs = math.abs(n)
	if abs >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif abs >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif abs >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

return UIKit
