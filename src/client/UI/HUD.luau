--!strict
-- Основной интерфейс: монеты, кнопки, кнопка СТАРТ, панель шторма, уведомления, виньетка урона.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local HUD = {}

HUD.Gui = nil :: ScreenGui?

local gui: ScreenGui
local effectsGui: ScreenGui

local coinsLabel: TextLabel
local levelLabel: TextLabel
local startButton: TextButton
local startHolder: Frame
local statusLabel: TextLabel
local stormPanel: Frame
local phaseLabel: TextLabel
local timerLabel: TextLabel
local bunkerBar: Frame
local bunkerText: TextLabel
local healthBar: Frame
local healthText: TextLabel
local acidText: TextLabel
local warningLabel: TextLabel
local warningHolder: Frame
local toastHolder: Frame
local vignette: { Frame } = {}
local shopButton: TextButton
local buildButton: TextButton
local sideColumn: Frame
local sideList: UIListLayout

local displayedCoins = 0
local targetCoins = 0

local PHASE_ICONS: { [string]: string } = {
	Prep = "⚠",
	Hail = "🌨",
	Wind = "🌪",
	Meteor = "☄",
	Calm = "☁",
	Acid = "☣",
	Quake = "🌍",
	Clear = "🌤",
}

local TOAST_COLORS: { [string]: Color3 } = {
	info = Theme.Blue,
	success = Theme.Green,
	purchase = Theme.Yellow,
	error = Theme.Red,
	warning = Theme.Orange,
}

-- Присваиваем текст только при изменении (меньше перерисовки текста на телефонах).
local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

----------------------------------------------------------------------
-- Построение
----------------------------------------------------------------------
local function makeBar(parent: Instance, order: number, color: Color3, icon: string): (Frame, TextLabel)
	local holder = UIKit.new("Frame", {
		Name = "Bar",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = Color3.fromRGB(18, 20, 28),
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.corner(holder, 8)
	UIKit.stroke(holder, 2, Theme.PanelStroke)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = holder,
	}) :: Frame
	UIKit.corner(fill, 8)
	UIKit.gradient(fill, color, color:Lerp(Color3.new(0, 0, 0), 0.3))
	local text = UIKit.label({
		Name = "Text",
		Text = icon,
		Size = UDim2.new(1, -16, 1, -4),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 18,
		ZIndex = 3,
		Parent = holder,
	})
	return fill, text
end

local function sideButton(parent: Instance, order: number, icon: string, caption: string, color: Color3, onClick: () -> ()): TextButton
	local button = UIKit.button({
		Name = caption,
		Text = "",
		Color = color,
		Size = UDim2.fromOffset(92, 92),
		LayoutOrder = order,
		Parent = parent,
	}, onClick)
	local label = button:FindFirstChild("Label")
	if label then
		label:Destroy()
	end
	UIKit.label({
		Name = "Icon",
		Text = icon,
		Size = UDim2.new(1, 0, 0.62, 0),
		Position = UDim2.fromScale(0.5, 0.06),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 44,
		ZIndex = 2,
		NoStroke = true,
		Parent = button,
	})
	UIKit.label({
		Name = "Caption",
		Text = caption,
		Size = UDim2.new(1, -6, 0.3, 0),
		Position = UDim2.fromScale(0.5, 0.95),
		AnchorPoint = Vector2.new(0.5, 1),
		MaxTextSize = 17,
		ZIndex = 2,
		Parent = button,
	})
	return button
end

local function buildStats()
	local panel = UIKit.panel({
		Name = "Stats",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.fromOffset(250, 92),
		BackgroundTransparency = 0.15,
		Parent = gui,
	})
	UIKit.autoScale(panel, "hud")
	UIKit.padding(panel, 8)
	UIKit.list(panel, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)
	coinsLabel = UIKit.label({
		Name = "Coins",
		Text = "💰 0",
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Yellow,
		MaxTextSize = 34,
		LayoutOrder = 1,
		Parent = panel,
	})
	levelLabel = UIKit.label({
		Name = "Level",
		Text = "🌩 Уровень шторма: 1",
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		LayoutOrder = 2,
		Parent = panel,
	})
	ClientState.Elements.Coins = panel
end

local function buildSideButtons()
	local column = UIKit.new("Frame", {
		Name = "SideButtons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.45, 0),
		Size = UDim2.fromOffset(92, 300),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(column, "hud")
	sideColumn = column
	sideList = UIKit.list(column, Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	shopButton = sideButton(column, 1, "🛒", "Магазин", Theme.Yellow, function()
		ClientState.setShopOpen(not ClientState.ShopOpen)
	end)
	buildButton = sideButton(column, 2, "🔨", "Строить", Theme.Blue, function()
		if ClientState.inStorm() then
			ClientState.notify("Во время шторма строить нельзя!", "error")
			return
		end
		ClientState.setBuildMode(not ClientState.BuildMode)
	end)
	local bunkerButton = sideButton(column, 3, "📍", "Бункер", Theme.Purple, function()
		ClientState.WaypointRequested:Fire()
	end)
	ClientState.Elements.ShopButton = shopButton
	ClientState.Elements.BuildButton = buildButton
	ClientState.Elements.BunkerButton = bunkerButton
end

local function buildStart()
	startHolder = UIKit.new("Frame", {
		Name = "StartHolder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(380, 140),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(startHolder, "hud")
	statusLabel = UIKit.label({
		Name = "Status",
		Text = "",
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 24,
		Parent = startHolder,
	})
	startButton = UIKit.button({
		Name = "Start",
		Text = "▶ НАЧАТЬ ШТОРМ",
		Color = Theme.Green,
		Size = UDim2.fromOffset(340, 88),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 38,
		Parent = startHolder,
	}, function()
		if startButton:GetAttribute("Cooldown") then
			return
		end
		startButton:SetAttribute("Cooldown", true)
		Remotes.StartStorm:FireServer()
		task.delay(2, function()
			startButton:SetAttribute("Cooldown", nil)
		end)
	end)
	ClientState.Elements.StartButton = startButton

	-- пульсация кнопки
	task.spawn(function()
		local scale = startButton:FindFirstChildOfClass("UIScale")
		while true do
			if startHolder.Visible and scale then
				UIKit.tween(scale, 0.6, { Scale = 1.06 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(0.6)
				UIKit.tween(scale, 0.6, { Scale = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(0.6)
			else
				task.wait(0.3)
			end
		end
	end)
end

local function buildStormPanel()
	stormPanel = UIKit.panel({
		Name = "Storm",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(470, 172),
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = gui,
	})
	UIKit.autoScale(stormPanel, "hud")
	UIKit.padding(stormPanel, 10)
	UIKit.list(stormPanel, Enum.FillDirection.Vertical, 6)
	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = stormPanel,
	})
	phaseLabel = UIKit.label({
		Name = "Phase",
		Text = "",
		Size = UDim2.new(0.72, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 30,
		Parent = header,
	})
	timerLabel = UIKit.label({
		Name = "Timer",
		Text = "0:00",
		Size = UDim2.new(0.28, 0, 1, 0),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Yellow,
		MaxTextSize = 30,
		Parent = header,
	})
	bunkerBar, bunkerText = makeBar(stormPanel, 2, Theme.Blue, "🧱 Бункер")
	healthBar, healthText = makeBar(stormPanel, 3, Theme.Green, "❤ Здоровье")
	acidText = UIKit.label({
		Name = "Acid",
		Text = "",
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = Theme.Acid,
		MaxTextSize = 20,
		LayoutOrder = 4,
		Parent = stormPanel,
	})
	-- предупреждение — отдельно под панелью (в панели работает UIListLayout)
	warningHolder = UIKit.new("Frame", {
		Name = "WarningHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 190),
		Size = UDim2.fromOffset(560, 40),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(warningHolder, "hud")
	warningLabel = UIKit.label({
		Name = "Warning",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Theme.Red,
		MaxTextSize = 30,
		Visible = false,
		Parent = warningHolder,
	})
	-- мигание предупреждения
	task.spawn(function()
		local on = true
		while true do
			task.wait(0.4)
			if warningLabel.Visible then
				on = not on
				warningLabel.TextTransparency = if on then 0 else 0.5
			end
		end
	end)
end

local function buildToasts()
	toastHolder = UIKit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(560, 260),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(toastHolder, "hud")
	UIKit.list(toastHolder, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
end

local toastOrder = 0
local function showToast(text: string, kind: string)
	toastOrder += 1
	local color = TOAST_COLORS[kind] or Theme.Blue
	local toast = UIKit.new("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(540, 46),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = toastOrder,
		Parent = toastHolder,
	}) :: Frame
	UIKit.corner(toast, 10)
	local stroke = UIKit.stroke(toast, 3, color)
	local label = UIKit.label({
		Text = text,
		Size = UDim2.new(1, -20, 1, -8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 22,
		Parent = toast,
	})
	-- не больше 4 одновременно
	local toasts: { Frame } = {}
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 4 then
		table.sort(toasts, function(a: Frame, b: Frame)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #toasts - 4 do
			toasts[i]:Destroy()
		end
	end
	task.delay(3.6, function()
		if toast.Parent then
			UIKit.tween(toast, 0.4, { BackgroundTransparency = 1 })
			UIKit.tween(label, 0.4, { TextTransparency = 1 })
			UIKit.tween(stroke, 0.4, { Transparency = 1 })
			local labelStroke = label:FindFirstChildOfClass("UIStroke")
			if labelStroke then
				UIKit.tween(labelStroke, 0.4, { Transparency = 1 })
			end
			task.wait(0.45)
			toast:Destroy()
		end
	end)
end

local function buildVignette()
	effectsGui = UIKit.new("ScreenGui", {
		Name = "BunkerEffects",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		ClipToDeviceSafeArea = false,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		DisplayOrder = -1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	local edges = {
		{ UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0), 90 },
		{ UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0.78), 270 },
		{ UDim2.new(0.18, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
		{ UDim2.new(0.18, 0, 1, 0), UDim2.fromScale(0.82, 0), 180 },
	}
	for _, e in edges do
		local f = UIKit.new("Frame", {
			Size = e[1],
			Position = e[2],
			BackgroundColor3 = Theme.Red,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = effectsGui,
		}) :: Frame
		UIKit.new("UIGradient", {
			Rotation = e[3],
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = f,
		})
		table.insert(vignette, f)
	end
end

-- Вспышка виньетки (урон / кислота).
function HUD.flash(color: Color3, strength: number?)
	local s = strength or 0.45
	for _, f in vignette do
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1 - s
		UIKit.tween(f, 0.6, { BackgroundTransparency = 1 })
	end
end

----------------------------------------------------------------------
-- Обновление
----------------------------------------------------------------------
local function refreshData(data: Remotes.DataSnapshot)
	targetCoins = data.Coins
	levelLabel.Text = "🌩 Уровень шторма: " .. data.StormLevel
end

local function myPlot(): Model?
	return ClientState.getPlotModel()
end

local function refreshStart()
	local inZone = player:GetAttribute("InPlotZone") == true
	local inBunker = player:GetAttribute("InBunker") == true
	local plot = myPlot()
	local hasBunker = plot ~= nil and plot:GetAttribute("HasBunker") == true
	local canShow = inZone
		and not ClientState.inStorm()
		and not ClientState.BuildMode
		and not ClientState.ModalOpen
		and ClientState.Data ~= nil
	startHolder.Visible = canShow
	-- Кнопка видна на всём участке (сервер сам проверяет условия), а статус подсказывает,
	-- что лучше сначала зайти в бункер. Так игрок никогда не "застрянет" без кнопки.
	if inBunker then
		setText(statusLabel, "✅ Ты в бункере. Готов?")
		statusLabel.TextColor3 = Theme.Green
	elseif hasBunker then
		setText(statusLabel, "🚪 Сначала зайди в бункер!")
		statusLabel.TextColor3 = Theme.Yellow
	else
		setText(statusLabel, "⚠ У тебя нет закрытого бункера!")
		statusLabel.TextColor3 = Theme.Orange
	end
end

local function setBar(fill: Frame, frac: number)
	local size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	if fill.Size ~= size then
		fill.Size = size
	end
	fill.Visible = frac > 0.001
end

local lastHealth = 100

-- Раскладка под тип ввода: на телефоне кнопки рядом с монетами (вне зоны джойстика),
-- кнопка СТАРТ смещена вправо от зоны джойстика.
local function applyInputLayout()
	local touch = ClientState.isTouch()
	if touch then
		local y = 8 + math.floor(92 * UIKit.currentHudScale()) + 8
		sideColumn.AnchorPoint = Vector2.new(0, 0)
		sideColumn.Position = UDim2.new(0, 12, 0, y)
		sideColumn.Size = UDim2.fromOffset(300, 92)
		sideList.FillDirection = Enum.FillDirection.Horizontal
		startHolder.Position = UDim2.new(0.6, 0, 1, -18)
	else
		sideColumn.AnchorPoint = Vector2.new(0, 0.5)
		sideColumn.Position = UDim2.new(0, 12, 0.45, 0)
		sideColumn.Size = UDim2.fromOffset(92, 300)
		sideList.FillDirection = Enum.FillDirection.Vertical
		startHolder.Position = UDim2.new(0.5, 0, 1, -18)
	end
end

local function refreshStorm()
	local plot = myPlot()
	local active = ClientState.inStorm() and plot ~= nil
	stormPanel.Visible = active
	local hudScale = UIKit.currentHudScale()
	toastHolder.Position = UDim2.new(0.5, 0, 0, if active then 8 + math.floor(232 * hudScale) else 8)
	warningHolder.Position = UDim2.new(0.5, 0, 0, 8 + math.floor(182 * hudScale))
	if not active or not plot then
		warningLabel.Visible = false
		return
	end
	local phase = plot:GetAttribute("Phase")
	local phaseName = if typeof(phase) == "string" then Config.PhaseNames[phase] else nil
	setText(phaseLabel, (PHASE_ICONS[phase :: any] or "") .. " " .. (phaseName or ""))
	local endsAt = plot:GetAttribute("PhaseEndsAt")
	if typeof(endsAt) == "number" then
		setText(timerLabel, formatTime(endsAt - workspace:GetServerTimeNow()))
	end
	local hp = plot:GetAttribute("BunkerHP")
	local maxHp = plot:GetAttribute("BunkerMaxHP")
	if typeof(hp) == "number" and typeof(maxHp) == "number" and maxHp > 0 then
		setBar(bunkerBar, hp / maxHp)
		setText(bunkerText, string.format("🧱 Бункер: %d%%", math.floor(hp / maxHp * 100 + 0.5)))
	else
		setBar(bunkerBar, 0)
		setText(bunkerText, "🧱 Бункера нет!")
	end
	local outside = plot:GetAttribute("OutsideAcid")
	local inside = plot:GetAttribute("InsideDepth")
	local o = if typeof(outside) == "number" then outside else 0
	local i = if typeof(inside) == "number" then inside else 0
	if o > 0 or i > 0 then
		setText(acidText, string.format("☣ Кислота снаружи: %.1f  •  внутри: %.1f", o, i))
	else
		local level = plot:GetAttribute("StormLevel")
		setText(acidText, "🌩 Уровень шторма " .. tostring(level or ""))
	end
	local leak = plot:GetAttribute("Leak")
	if i > Config.Storm.InsideDamageDepth then
		setText(warningLabel, "⚠ БУНКЕР ЗАТАПЛИВАЕТ КИСЛОТОЙ!")
		warningLabel.Visible = true
	elseif typeof(leak) == "number" and leak > 0 then
		setText(warningLabel, "⚠ Кислота просачивается через дверь!")
		warningLabel.Visible = true
	else
		warningLabel.Visible = false
	end
end

local function refreshHealth()
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum then
		local frac = hum.Health / math.max(hum.MaxHealth, 1)
		setBar(healthBar, frac)
		healthText.Text = string.format("❤ Здоровье: %d", math.floor(hum.Health + 0.5))
		if hum.Health < lastHealth - 0.5 then
			HUD.flash(Theme.Red, math.clamp((lastHealth - hum.Health) / 25, 0.2, 0.6))
		end
		lastHealth = hum.Health
	end
end

function HUD.init()
	gui = UIKit.new("ScreenGui", {
		Name = "BunkerHUD",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	HUD.Gui = gui

	buildVignette()
	buildStats()
	buildSideButtons()
	buildStart()
	buildStormPanel()
	buildToasts()

	ClientState.Notified:Connect(showToast)
	ClientState.DataChanged:Connect(refreshData)
	if ClientState.Data then
		refreshData(ClientState.Data)
	end

	for _, attr in { "InPlotZone", "InBunker", "InStorm" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			refreshStart()
			refreshStorm()
		end)
	end
	ClientState.BuildModeChanged:Connect(function(on)
		refreshStart()
		UIKit.setButtonColor(buildButton, if on then Theme.Orange else Theme.Blue)
		local caption = buildButton:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			caption.Text = if on then "Готово" else "Строить"
		end
	end)
	ClientState.ShopToggled:Connect(refreshStart)
	ClientState.DataChanged:Connect(refreshStart)
	ClientState.InputChanged:Connect(applyInputLayout)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyInputLayout)
	end
	applyInputLayout()

	-- здоровье
	local function bindCharacter(character: Model)
		local hum = character:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			lastHealth = hum.Health
			hum.HealthChanged:Connect(refreshHealth)
			refreshHealth()
		end
	end
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	-- плавный счётчик монет и обновление панели шторма
	local accumulator = 0
	RunService.PreRender:Connect(function(dt)
		if displayedCoins ~= targetCoins then
			local diff = targetCoins - displayedCoins
			local stepValue = diff * math.min(dt * 8, 1)
			if math.abs(diff) < 1 or math.abs(stepValue) < 0.5 then
				displayedCoins = targetCoins
			else
				displayedCoins += stepValue
			end
			coinsLabel.Text = "💰 " .. UIKit.formatNumber(displayedCoins)
		end
		accumulator += dt
		if accumulator >= 0.15 then
			accumulator = 0
			refreshStorm()
			refreshStart()
		end
	end)
	refreshStart()
	refreshStorm()
end

return HUD
