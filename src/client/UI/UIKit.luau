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

----------------------------------------------------------------------
-- Тип ввода. PreferredInput — новое API (2025), поэтому читаем его в pcall
-- и при ошибке определяем по старым флагам.
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

-- Сигнал смены типа ввода (с запасным вариантом через LastInputTypeChanged).
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
	-- служебные ключи (не свойства TextLabel) вынимаем до создания инстанса
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
		if UIKit.isMouse() then
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
	local touch = UIKit.isTouch()
	-- телефон: сенсор и низкий экран (в точках); планшеты выше 500
	local phone = touch and math.min(vp.X, vp.Y) < 500
	if entry.mode == "hud" then
		local s = math.min(vp.Y / 720, vp.X / 1100)
		if phone then
			-- на телефоне панели компактнее, чтобы не закрывать полэкрана
			return math.clamp(s * 0.9, 0.45, 0.8)
		end
		return math.clamp(s, if touch then 0.6 else 0.62, 1.35)
	end
	-- модальное окно целиком помещается на экран
	local fw, fh = if phone then 0.86 else 0.94, if phone then 0.84 else 0.9
	local s = math.min(vp.X * fw / entry.designW, vp.Y * fh / entry.designH)
	return math.clamp(s, 0.3, 1.3)
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
UIKit.onInputTypeChanged(refreshAll)
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

----------------------------------------------------------------------
-- Дополнения для «Amber Alert» (функции выше не менялись).
-- Ленивый доступ к контроллерам, «тёмные» кнопки, полоски, модальные окна, пересчёт раскладки.
----------------------------------------------------------------------

-- Текст меняем только при отличии (меньше перерисовок текста на телефонах).
function UIKit.setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

-- Ленивый доступ к контроллерам (их пишет другой модуль): нет модуля — вернём nil и ничего не ломаем.
local controllerCache: { [string]: any } = {}

function UIKit.controller(name: string): any?
	local cached = controllerCache[name]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local folder = script.Parent.Parent:FindFirstChild("Controllers")
	local module = if folder then folder:FindFirstChild(name) else nil
	if not module or not module:IsA("ModuleScript") then
		return nil -- не кэшируем: модуль может появиться позже
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		controllerCache[name] = result
		return result
	end
	controllerCache[name] = false
	return nil
end

-- Звук интерфейса через Controllers.Sounds.playUI (если контроллер есть).
function UIKit.playUI(name: string)
	local sounds = UIKit.controller("Sounds")
	if sounds and type(sounds.playUI) == "function" then
		task.spawn(function()
			pcall(sounds.playUI, name)
		end)
	end
end

-- Размер под тип ввода: на сенсорном экране цели нажатия крупнее (HUD на телефоне сильно уменьшен).
function UIKit.touchPx(mouse: number, touch: number): number
	return if UIKit.isTouch() then touch else mouse
end

-- Пиксели HUD с учётом текущего масштаба (для отступов между соседними HUD-панелями).
function UIKit.hudPx(px: number): number
	return math.floor(px * UIKit.currentHudScale() + 0.5)
end

-- Тонкая обводка вместо толстой чёрной рамки панели/кнопки.
function UIKit.thinStroke(object: Instance, color: Color3?, transparency: number?, thickness: number?): UIStroke?
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = thickness or 1
		stroke.Color = color or Theme.GrayDark
		stroke.Transparency = transparency or 0.3
	end
	return stroke
end

-- «Тёмная» кнопка: почти чёрная заливка, тонкая обводка акцентом, подпись акцентом, без обводки текста.
function UIKit.styleDark(button: TextButton, accent: Color3?, fill: Color3?)
	local color = accent or Theme.Amber
	local base = fill or Theme.PanelLight
	UIKit.setButtonColor(button, base, base:Lerp(Color3.new(0, 0, 0), 0.45))
	UIKit.thinStroke(button, color, 0.25, 1.5)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextColor3 = color
		local textStroke = label:FindFirstChildOfClass("UIStroke")
		if textStroke then
			textStroke.Enabled = false
		end
	end
	button:SetAttribute("Accent", color)
end

-- Включить/выключить кнопку: выключенная не реагирует и тускнеет.
function UIKit.setButtonEnabled(button: TextButton, enabled: boolean)
	button.Interactable = enabled
	button:SetAttribute("Disabled", not enabled)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextTransparency = if enabled then 0 else 0.55
	end
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = if enabled then 0.25 else 0.7
	end
end

-- Тонкая полоска-индикатор: props идут контейнеру (Size, Position, AnchorPoint, Parent, LayoutOrder...).
-- Возвращает (контейнер, заливку).
function UIKit.bar(props: Props, color: Color3): (Frame, Frame)
	local base: Props = {
		Name = "Bar",
		BackgroundColor3 = Color3.fromRGB(6, 6, 8),
		BackgroundTransparency = 0.15,
	}
	for k, v in props do
		base[k] = v
	end
	local holder = UIKit.new("Frame", base) :: Frame
	UIKit.corner(holder, 3)
	UIKit.new("UIStroke", { Thickness = 1, Color = Theme.GrayDark, Transparency = 0.35, Parent = holder })
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		Parent = holder,
	}) :: Frame
	UIKit.corner(fill, 3)
	return holder, fill
end

function UIKit.setBar(fill: Frame, frac: number)
	local size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	if fill.Size ~= size then
		fill.Size = size
	end
	fill.Visible = frac > 0.001
end

-- Колбэк на смену размера экрана / типа ввода: пересчёт отступов между HUD-панелями и размеров под палец.
local layoutCallbacks: { () -> () } = {}
local layoutCameraConn: RBXScriptConnection? = nil
local layoutBound = false

local function fireLayout()
	for _, fn in layoutCallbacks do
		task.spawn(fn)
	end
end

local function bindLayoutCamera()
	if layoutCameraConn then
		layoutCameraConn:Disconnect()
		layoutCameraConn = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		layoutCameraConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fireLayout)
	end
end

function UIKit.onLayoutChanged(fn: () -> ())
	table.insert(layoutCallbacks, fn)
	if not layoutBound then
		layoutBound = true
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			bindLayoutCamera()
			fireLayout()
		end)
		UIKit.onInputTypeChanged(fireLayout)
		bindLayoutCamera()
	end
end

-- Модальное окно: затемнение (тап закрывает) + центрированная панель с заголовком и крестиком.
export type Modal = {
	Overlay: TextButton,
	Window: Frame,
	Scale: UIScale,
	Title: TextLabel,
	Close: TextButton,
	Body: Frame,
	IsOpen: boolean,
	OpenedAt: number,
	OnClose: (() -> ())?,
	Open: (self: Modal) -> (),
	Hide: (self: Modal) -> (),
}

export type ModalOptions = {
	Name: string,
	Width: number,
	Height: number,
	Title: string?,
	Parent: Instance,
	OnClose: (() -> ())?,
	NoClose: boolean?, -- без крестика и без закрытия по затемнению
	Accent: Color3?,
}

-- Сообщить ClientState об открытии/закрытии модального окна (курсор освобождается, пока открыто хоть одно).
function UIKit.notifyModal(open: boolean)
	local stateModule = script.Parent.Parent:FindFirstChild("ClientState")
	if not stateModule then
		return
	end
	local ok, state = pcall(require :: any, stateModule)
	if ok and type(state) == "table" then
		local fn: (() -> ())? = if open then (state :: any).pushModal else (state :: any).popModal
		if fn then
			fn()
		end
	end
end

function UIKit.modal(opts: ModalOptions): Modal
	local accent = opts.Accent or Theme.Amber
	local overlay = UIKit.new("TextButton", {
		Name = opts.Name .. "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Parent = opts.Parent,
	}) :: TextButton
	local window = UIKit.panel({
		Name = opts.Name,
		Size = UDim2.fromOffset(opts.Width, opts.Height),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = opts.Parent,
	})
	UIKit.thinStroke(window, accent, 0.45, 1)
	local scale = UIKit.autoScale(window, "modal", opts.Width, opts.Height)
	local title = UIKit.label({
		Name = "Title",
		Text = opts.Title or "",
		Size = UDim2.new(1, -140, 0, 40),
		Position = UDim2.fromOffset(20, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = accent,
		MaxTextSize = 28,
		NoStroke = true,
		Parent = window,
	})
	UIKit.new("Frame", {
		Name = "Rule",
		Size = UDim2.new(1, -40, 0, 1),
		Position = UDim2.new(0.5, 0, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.6,
		Parent = window,
	})
	local body = UIKit.new("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -32, 1, -84),
		Position = UDim2.fromOffset(16, 70),
		BackgroundTransparency = 1,
		Parent = window,
	}) :: Frame
	local closeSize = UIKit.touchPx(48, 64)
	local close = UIKit.button({
		Name = "Close",
		Text = "✕",
		Size = UDim2.fromOffset(closeSize, closeSize),
		Position = UDim2.new(1, -10, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 26,
		Parent = window,
	})
	UIKit.styleDark(close, Theme.Red)
	close.Visible = opts.NoClose ~= true

	local modal: Modal
	modal = {
		Overlay = overlay,
		Window = window,
		Scale = scale,
		Title = title,
		Close = close,
		Body = body,
		IsOpen = false,
		OpenedAt = 0,
		OnClose = opts.OnClose,
		Open = function(self: Modal)
			if self.IsOpen then
				return
			end
			self.IsOpen = true
			UIKit.notifyModal(true)
			self.Overlay.Visible = true
			-- если прошлая анимация появления ещё идёт, не запускаем новую (иначе окно «усохнет»)
			if os.clock() - self.OpenedAt < 0.3 then
				self.Window.Visible = true
			else
				UIKit.popIn(self.Window, self.Scale)
			end
			self.OpenedAt = os.clock()
		end,
		Hide = function(self: Modal)
			if not self.IsOpen then
				return
			end
			self.IsOpen = false
			UIKit.notifyModal(false)
			self.Window.Visible = false
			self.Overlay.Visible = false
			if self.OnClose then
				self.OnClose()
			end
		end,
	}
	local function requestClose()
		if opts.NoClose then
			return
		end
		modal:Hide()
	end
	close.Activated:Connect(function()
		UIKit.playClick()
		requestClose()
	end)
	overlay.Activated:Connect(requestClose)
	return modal
end

return UIKit
