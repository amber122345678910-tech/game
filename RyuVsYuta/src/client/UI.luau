--!strict
-- Интерфейс катсцены: стартовый экран с кнопкой запуска, кинорамка, затемнения, субтитры, титры,
-- панель просмотра (пауза, заново, скорость, перемотка по таймлайну) и экран конца этапа.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Cutscene"):WaitForChild("Sequence"):WaitForChild("Types"))
local TextureLoader = require(script.Parent:WaitForChild("FX"):WaitForChild("TextureLoader"))

local UI = {}

export type Callbacks = {
	onStart: () -> (),
	onTogglePause: () -> (),
	onRestart: () -> (),
	onSpeed: (number) -> (),
	onSeek: (number) -> (),
	onStyle: (string) -> (), -- "models" | "dummies"
}

export type ShotMark = { name: string, title: string, start: number, finish: number }

local COLORS = {
	ink = Color3.fromRGB(8, 7, 12),
	panel = Color3.fromRGB(16, 14, 24),
	text = Color3.fromRGB(240, 238, 248),
	dim = Color3.fromRGB(160, 156, 180),
	energy = Color3.fromRGB(96, 226, 255),
	rika = Color3.fromRGB(232, 52, 64),
	white = Color3.new(1, 1, 1),
}

local gui: ScreenGui
local topBar: Frame
local bottomBar: Frame
local fadeFrame: Frame
local flashFrame: Frame
local vignette: ImageLabel
local grain: ImageLabel
local speedLines: ImageLabel
local subtitle: TextLabel
local caption: TextLabel
local startScreen: Frame
local startButton: TextButton
local loadingLabel: TextLabel
local loadingFill: Frame
local controls: Frame
local playButton: TextButton
local timeLabel: TextLabel
local timelineBar: Frame
local timelineFill: Frame
local speedButtons: { [number]: TextButton } = {}
local styleButtons: { TextButton } = {}
local currentStyle = "models"
local STYLE_TEXT: { [string]: string } = {
	models = "РЮ И ЮТА: МОДЕЛИ ПЕРСОНАЖЕЙ",
	dummies = "РЮ И ЮТА: ОБЫЧНЫЕ МАНЕКЕНЫ ROBLOX",
}
local endScreen: Frame
local callbacks: Callbacks
local duration = 1
local shotMarks: { ShotMark } = {}
local controlsVisible = true
local controlsPinnedHidden = false
local lastMouseMove = 0
local currentSpeed = 1
local isPlaying = false

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst: any = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Montserrat — штатный шрифт клиента (Gotham теперь рисуется им же); FontFace — актуальное свойство
local function font(weight: Enum.FontWeight): Font
	return Font.new("rbxasset://fonts/families/Montserrat.json", weight)
end

local function corner(parent: Instance, r: number)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function textStroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

local function fmtTime(t: number): string
	return string.format("%04.1f", t)
end

local function shotAt(t: number): ShotMark?
	for _, s in shotMarks do
		if t >= s.start and t < s.finish then
			return s
		end
	end
	return shotMarks[#shotMarks]
end

local function buildStart(parent: Instance)
	startScreen = make("Frame", {
		Name = "Start",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 20,
	}, parent)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, startScreen)

	local column = make("Frame", {
		Name = "Column",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromOffset(640, 420),
		BackgroundTransparency = 1,
		ZIndex = 21,
	}, startScreen)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, column)

	make("TextLabel", {
		Name = "Kicker",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(640, 22),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Medium),
		Text = "МАГИЧЕСКАЯ БИТВА  ·  ИГРА СМЕРТИ  ·  КОЛОНИЯ СЕНДАЙ",
		TextColor3 = COLORS.dim,
		TextSize = 15,
		ZIndex = 22,
	}, column)

	local title = make("TextLabel", {
		Name = "Title",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(640, 64),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Heavy),
		Text = "РЮ ИШИГОРИ  ✕  ЮТА ОККОЦУ",
		TextColor3 = COLORS.text,
		TextSize = 40,
		ZIndex = 22,
	}, column)
	textStroke(title, COLORS.ink, 2, 0.2)
	make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLORS.energy),
			ColorSequenceKeypoint.new(0.45, COLORS.white),
			ColorSequenceKeypoint.new(0.55, COLORS.white),
			ColorSequenceKeypoint.new(1, COLORS.rika),
		}),
	}, title)

	make("TextLabel", {
		Name = "Stage",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(640, 28),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Bold),
		Text = "ЭТАП 1  —  «ИЗ ТУМАНА»",
		TextColor3 = COLORS.text,
		TextSize = 20,
		ZIndex = 22,
	}, column)

	make("Frame", { Name = "Gap", LayoutOrder = 4, Size = UDim2.fromOffset(10, 14), BackgroundTransparency = 1 }, column)

	startButton = make("TextButton", {
		Name = "Play",
		LayoutOrder = 5,
		Size = UDim2.fromOffset(380, 66),
		BackgroundColor3 = COLORS.panel,
		AutoButtonColor = true,
		FontFace = font(Enum.FontWeight.Heavy),
		Text = "▶  ЗАПУСТИТЬ АНИМАЦИЮ",
		TextColor3 = COLORS.white,
		TextSize = 24,
		ZIndex = 22,
	}, column)
	corner(startButton, 12)
	stroke(startButton, COLORS.energy, 2)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(44, 40, 70), Color3.fromRGB(14, 12, 22)),
	}, startButton)

	-- кто играет Рю и Юту: модели или обычные персонажи Roblox (Рика — всегда модель)
	local styleBtn = make("TextButton", {
		Name = "Style",
		LayoutOrder = 6,
		Size = UDim2.fromOffset(380, 34),
		BackgroundColor3 = Color3.fromRGB(26, 24, 38),
		AutoButtonColor = true,
		FontFace = font(Enum.FontWeight.Bold),
		Text = "⇄  " .. STYLE_TEXT[currentStyle],
		TextColor3 = COLORS.text,
		TextSize = 14,
		ZIndex = 22,
	}, column)
	corner(styleBtn, 8)
	stroke(styleBtn, Color3.fromRGB(90, 86, 120), 1, 0.3)
	styleBtn.Activated:Connect(function()
		callbacks.onStyle(if currentStyle == "models" then "dummies" else "models")
	end)
	table.insert(styleButtons, styleBtn)

	local loadBack = make("Frame", {
		Name = "Loading",
		LayoutOrder = 7,
		Size = UDim2.fromOffset(380, 6),
		BackgroundColor3 = Color3.fromRGB(40, 38, 56),
		BorderSizePixel = 0,
		ZIndex = 22,
	}, column)
	corner(loadBack, 3)
	loadingFill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.energy,
		BorderSizePixel = 0,
		ZIndex = 23,
	}, loadBack)
	corner(loadingFill, 3)
	loadingLabel = make("TextLabel", {
		Name = "LoadingText",
		LayoutOrder = 8,
		Size = UDim2.fromOffset(640, 20),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Regular),
		Text = "Загрузка звуков…",
		TextColor3 = COLORS.dim,
		TextSize = 14,
		ZIndex = 22,
	}, column)

	make("TextLabel", {
		Name = "Hint",
		LayoutOrder = 9,
		Size = UDim2.fromOffset(640, 40),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Regular),
		Text = "Пробел — пауза   ·   ← → — перемотка на 2 с   ·   1 / 2 / 3 — скорость 0.25× / 0.5× / 1×\nR — сначала   ·   H — скрыть панель   ·   по таймлайну можно кликать",
		TextColor3 = COLORS.dim,
		TextSize = 13,
		TextWrapped = true,
		ZIndex = 22,
	}, column)

	startButton.Activated:Connect(function()
		callbacks.onStart()
	end)
end

local function smallButton(parent: Instance, name: string, text: string, width: number, order: number): TextButton
	local b = make("TextButton", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(width, 30),
		BackgroundColor3 = Color3.fromRGB(30, 28, 44),
		BackgroundTransparency = 0.15,
		AutoButtonColor = true,
		FontFace = font(Enum.FontWeight.Bold),
		Text = text,
		TextColor3 = COLORS.text,
		TextSize = 14,
		ZIndex = 31,
	}, parent)
	corner(b, 6)
	return b
end

local function buildControls(parent: Instance)
	controls = make("Frame", {
		Name = "Controls",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0.92, 0, 0, 74),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 30,
	}, parent)
	corner(controls, 10)
	stroke(controls, Color3.fromRGB(80, 76, 110), 1, 0.4)

	local row = make("Frame", {
		Name = "Buttons",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 30),
		BackgroundTransparency = 1,
		ZIndex = 31,
	}, controls)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	playButton = smallButton(row, "Pause", "⏸", 44, 1)
	playButton.Activated:Connect(function()
		callbacks.onTogglePause()
	end)
	local restart = smallButton(row, "Restart", "↺ Сначала", 96, 2)
	restart.Activated:Connect(function()
		callbacks.onRestart()
	end)
	for i, s in { 0.25, 0.5, 1 } do
		local b = smallButton(row, "Speed" .. i, (if s == 1 then "1" else tostring(s)) .. "×", 58, 2 + i)
		speedButtons[s] = b
		b.Activated:Connect(function()
			callbacks.onSpeed(s)
		end)
	end
	local styleSmall = smallButton(row, "Style", "⇄ Манекены", 104, 6)
	styleSmall.Activated:Connect(function()
		callbacks.onStyle(if currentStyle == "models" then "dummies" else "models")
	end)
	table.insert(styleButtons, styleSmall)
	timeLabel = make("TextLabel", {
		Name = "Time",
		LayoutOrder = 10,
		Size = UDim2.new(1, -540, 1, 0),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Medium),
		Text = "",
		TextColor3 = COLORS.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 31,
	}, row)

	timelineBar = make("Frame", {
		Name = "Timeline",
		Position = UDim2.new(0, 10, 0, 48),
		Size = UDim2.new(1, -20, 0, 12),
		BackgroundColor3 = Color3.fromRGB(46, 44, 64),
		BorderSizePixel = 0,
		ZIndex = 31,
	}, controls)
	corner(timelineBar, 4)
	timelineFill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.energy,
		BorderSizePixel = 0,
		ZIndex = 32,
	}, timelineBar)
	corner(timelineFill, 4)
	-- метки кадров
	for i, s in shotMarks do
		if i > 1 then
			make("Frame", {
				Name = "Mark" .. i,
				Position = UDim2.fromScale(s.start / duration, 0),
				Size = UDim2.new(0, 2, 1, 0),
				BackgroundColor3 = COLORS.white,
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
				ZIndex = 33,
			}, timelineBar)
		end
	end
	local hit = make("TextButton", {
		Name = "Hit",
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, -7),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 34,
	}, timelineBar)
	local dragging = false
	local function seekFromX(x: number)
		local absPos = timelineBar.AbsolutePosition.X
		local absSize = math.max(1, timelineBar.AbsoluteSize.X)
		local f = math.clamp((x - absPos) / absSize, 0, 1)
		callbacks.onSeek(f * duration)
	end
	hit.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			seekFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			seekFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local function buildEnd(parent: Instance)
	endScreen = make("Frame", {
		Name = "End",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
	}, parent)
	local col = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 220),
		BackgroundTransparency = 1,
		ZIndex = 41,
	}, endScreen)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, col)
	make("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.fromOffset(600, 44),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Heavy),
		Text = "ЭТАП 1 ЗАВЕРШЁН",
		TextColor3 = COLORS.text,
		TextSize = 34,
		ZIndex = 42,
	}, col)
	make("TextLabel", {
		LayoutOrder = 2,
		Size = UDim2.fromOffset(600, 40),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Regular),
		Text = "Напиши, что поправить, — и переходим к Этапу 2.",
		TextColor3 = COLORS.dim,
		TextSize = 16,
		TextWrapped = true,
		ZIndex = 42,
	}, col)
	local again = make("TextButton", {
		LayoutOrder = 3,
		Size = UDim2.fromOffset(300, 54),
		BackgroundColor3 = COLORS.panel,
		FontFace = font(Enum.FontWeight.Heavy),
		Text = "↻  СМОТРЕТЬ СНОВА",
		TextColor3 = COLORS.white,
		TextSize = 20,
		ZIndex = 42,
	}, col)
	corner(again, 10)
	stroke(again, COLORS.energy, 2)
	again.Activated:Connect(function()
		callbacks.onRestart()
	end)
end

function UI.init(cb: Callbacks, marks: { ShotMark }, totalDuration: number)
	callbacks = cb
	shotMarks = marks
	duration = totalDuration
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	gui = make("ScreenGui", {
		Name = "CutsceneUI",
		ScreenInsets = Enum.ScreenInsets.None,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	}, playerGui)

	fadeFrame = make("Frame", {
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, gui)
	-- лёгкая виньетка, как в кино (сначала встроенная текстура клиента, потом — из Магазина)
	vignette = make("ImageLabel", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = TextureLoader.get("vignette"),
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.55,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 4,
	}, gui)
	-- зерно плёнки (едва заметное) и аниме-линии скорости на вспышке
	grain = make("ImageLabel", {
		Name = "Grain",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "",
		ImageTransparency = 0.93,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(256, 256),
		ZIndex = 4,
	}, gui)
	speedLines = make("ImageLabel", {
		Name = "SpeedLines",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "",
		ImageColor3 = Color3.fromRGB(220, 250, 255),
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 4,
	}, gui)
	TextureLoader.onReady(function()
		vignette.Image = TextureLoader.get("vignette")
		grain.Image = TextureLoader.get("grain")
		speedLines.Image = TextureLoader.get("speedLines")
	end)
	flashFrame = make("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(225, 250, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, gui)
	topBar = make("Frame", {
		Name = "LetterboxTop",
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 8,
	}, gui)
	bottomBar = make("Frame", {
		Name = "LetterboxBottom",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 8,
	}, gui)
	subtitle = make("TextLabel", {
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.86, 0),
		Size = UDim2.new(0.8, 0, 0, 40),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Medium),
		Text = "",
		TextColor3 = COLORS.white,
		TextScaled = true,
		TextTransparency = 1,
		ZIndex = 9,
	}, gui)
	make("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 14 }, subtitle)
	textStroke(subtitle, Color3.new(0, 0, 0), 2, 0.25)
	caption = make("TextLabel", {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0, 90),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Heavy),
		Text = "",
		TextColor3 = COLORS.text,
		TextScaled = true,
		TextTransparency = 1,
		ZIndex = 9,
	}, gui)
	make("UITextSizeConstraint", { MaxTextSize = 44, MinTextSize = 16 }, caption)
	textStroke(caption, Color3.new(0, 0, 0), 2, 0.3)

	buildStart(gui)
	buildControls(gui)
	buildEnd(gui)

	-- подгонка размера под маленькие экраны
	local scale = make("UIScale", { Scale = 1 }, gui) :: UIScale
	local function rescale()
		local cam = Workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			scale.Scale = math.clamp(math.min(vp.X / 1100, vp.Y / 620), 0.55, 1.25)
		end
	end
	rescale()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			lastMouseMove = os.clock()
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		lastMouseMove = os.clock()
		local k = input.KeyCode
		if not isPlaying and k ~= Enum.KeyCode.R then
			return
		end
		if k == Enum.KeyCode.Space then
			callbacks.onTogglePause()
		elseif k == Enum.KeyCode.R then
			callbacks.onRestart()
		elseif k == Enum.KeyCode.One then
			callbacks.onSpeed(0.25)
		elseif k == Enum.KeyCode.Two then
			callbacks.onSpeed(0.5)
		elseif k == Enum.KeyCode.Three then
			callbacks.onSpeed(1)
		elseif k == Enum.KeyCode.H then
			controlsPinnedHidden = not controlsPinnedHidden
		end
	end)
end

function UI.seekKeys(getT: () -> number)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not isPlaying then
			return
		end
		if input.KeyCode == Enum.KeyCode.Left then
			callbacks.onSeek(getT() - 2)
		elseif input.KeyCode == Enum.KeyCode.Right then
			callbacks.onSeek(getT() + 2)
		end
	end)
end

function UI.setLoading(done: number, total: number)
	local f = if total > 0 then done / total else 1
	loadingFill.Size = UDim2.fromScale(f, 1)
	loadingLabel.Text = if done >= total
		then "Звуки загружены — можно смотреть"
		else string.format("Загрузка звуков: %d / %d", done, total)
end

function UI.setLoadingNote(text: string)
	loadingLabel.Text = text
end

function UI.hideStart()
	local tween = TweenService:Create(startScreen, TweenInfo.new(0.6), { BackgroundTransparency = 1 })
	tween:Play()
	for _, d in startScreen:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			TweenService:Create(d, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		elseif d:IsA("Frame") then
			TweenService:Create(d, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
	end
	task.delay(0.65, function()
		startScreen.Visible = false
	end)
	endScreen.Visible = false
	controls.Visible = true
	isPlaying = true
	lastMouseMove = os.clock()
end

function UI.showEnd()
	endScreen.Visible = true
end

function UI.hideEnd()
	endScreen.Visible = false
end

function UI.setStyle(style: string)
	currentStyle = style
	for i, b in styleButtons do
		if i == 1 then
			b.Text = "⇄  " .. (STYLE_TEXT[style] or style)
		else
			b.Text = if style == "models" then "⇄ Манекены" else "⇄ Модели"
		end
	end
end

function UI.setSpeed(s: number)
	currentSpeed = s
	for sp, b in speedButtons do
		b.BackgroundColor3 = if sp == s then Color3.fromRGB(46, 108, 140) else Color3.fromRGB(30, 28, 44)
	end
end

function UI.applyFrame(frame: Types.Frame, t: number, paused: boolean)
	local u = frame.ui
	fadeFrame.BackgroundTransparency = 1 - math.clamp(u.fade, 0, 1)
	speedLines.ImageTransparency = 1 - 0.75 * math.clamp(u.speedLines or 0, 0, 1)
	-- зерно "дрожит": сдвигаем плитку каждый кадр
	grain.Position = UDim2.fromOffset(-math.random(0, 128), -math.random(0, 128))
	grain.Size = UDim2.new(1, 128, 1, 128)
	flashFrame.BackgroundTransparency = 1 - math.clamp(u.flash, 0, 1)
	topBar.Size = UDim2.fromScale(1, u.letterbox)
	bottomBar.Size = UDim2.fromScale(1, u.letterbox)
	subtitle.Text = u.subtitle or ""
	subtitle.TextTransparency = 1 - u.subtitleAlpha
	caption.Text = u.caption or ""
	caption.TextTransparency = 1 - u.captionAlpha

	if isPlaying then
		local shot = shotAt(t)
		timeLabel.Text = string.format(
			"%s / %s с   ·   %s%s",
			fmtTime(t),
			fmtTime(duration),
			if shot then shot.title else "",
			if currentSpeed ~= 1 then string.format("   ·   %.2g×", currentSpeed) else ""
		)
		timelineFill.Size = UDim2.fromScale(math.clamp(t / duration, 0, 1), 1)
		playButton.Text = if paused then "▶" else "⏸"
		local idle = os.clock() - lastMouseMove > 2.5
		local show = not controlsPinnedHidden and (paused or not idle)
		if show ~= controlsVisible then
			controlsVisible = show
			controls.Visible = show
		end
	end
end

return UI
