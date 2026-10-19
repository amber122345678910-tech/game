--!strict
-- HUD: Вольты и осколки, банка с перегрузкой и риском, кнопка ⚡ ЛОВИ с комбо, надписи оценки,
-- меню слева (на сенсорных экранах — только в верхней трети, выше зоны джойстика; что не влезло — в «Ещё»),
-- таймер события, шкала Электрограда и множитель справа сверху.
-- Сначала телефон: на телефоне всё компактнее, кнопка ЛОВИ левее кнопки прыжка.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Strikes = require(Shared:WaitForChild("Strikes"))
local Quests = require(Shared:WaitForChild("Quests"))
local Pets = require(Shared:WaitForChild("Pets"))
local Fulgurite = require(Shared:WaitForChild("Fulgurite"))
local Format = require(Shared:WaitForChild("Format"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local HUD = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Размеры макета (пиксели до масштабирования UIScale)
local TOP_W = 440
local PILL_H = 64
local JAR_H = 40
local STATUS_H = 30
local RIGHT_W = 300
local CATCH_PX_PHONE = 100 -- реальный размер кнопки ЛОВИ на экране
local CATCH_PX_PC = 120
local MENU_GAP = 10
local MENU_MIN_TILE = 48 -- сенсорный экран: плитка меню не мельче (реальные точки), иначе часть уходит в «Ещё»
local MORE_AUTO_CLOSE = 6 -- раскрытое «Ещё» само закрывается через столько секунд

local MENU = {
	{ Name = "ShopButton", Window = "Shop", Icon = "🛒", Text = "Магазин", Color = Theme.Green },
	{ Name = "PetsButton", Window = "Pets", Icon = "🐾", Text = "Питомцы", Color = Theme.Pink },
	{ Name = "CollectionButton", Window = "Collection", Icon = "💎", Text = "Коллекция", Color = Theme.Electric },
	{ Name = "TeleportButton", Window = "Teleport", Icon = "🌀", Text = "Острова", Color = Theme.Purple },
	{ Name = "RebirthButton", Window = "Rebirth", Icon = "♻", Text = "Перезапуск", Color = Theme.Orange },
	{ Name = "DailyButton", Window = "Daily", Icon = "🎁", Text = "Награды", Color = Theme.Gold },
	{ Name = "SettingsButton", Window = "Settings", Icon = "⚙", Text = "Настройки", Color = Theme.Gray },
}

local EVENT_INFO = {
	supercell = { Now = "⚡ СУПЕРЯЧЕЙКА", Color = Theme.Supercell },
	ball = { Now = "🔮 ШАРОВАЯ МОЛНИЯ", Color = Theme.Ball },
	rainbow = { Now = "🌈 РАДУЖНАЯ МОЛНИЯ", Color = Theme.Rainbow },
} :: { [string]: { Now: string, Color: Color3 } }

local NEXT_EVENTS = {
	{ Attr = "NextSupercell", Text = "⚡ Суперячейка через " },
	{ Attr = "NextBall", Text = "🔮 Шаровая через " },
	{ Attr = "NextRainbow", Text = "🌈 Радужная через " },
}

----------------------------------------------------------------------
-- Состояние
----------------------------------------------------------------------
local gui: ScreenGui
local topRoot: Frame
local topScale: UIScale
local rightRoot: Frame
local rightInner: Frame
local rightInnerScale: UIScale
local menuRoot: Frame
local menuScale: UIScale
local menuGrid: UIGridLayout
-- «Ещё»: на маленьком сенсорном экране не все кнопки помещаются в верхнюю треть — лишние в выпадающем блоке
local moreRoot: Frame
local moreGrid: UIGridLayout
local morePad = 6
local moreOpen = false
local moreToken = 0
local hiddenTiles: { string } = {} -- имена плиток, которые сейчас в «Ещё»
local catchRoot: Frame
local catchScale: UIScale
local gradeRoot: Frame

local catchButton: TextButton
local catchButtonScale: UIScale
local catchRing: Frame
local comboLabel: TextLabel
local comboScale: UIScale
local comboGrad: UIGradient
local lastCombo = 0

local gradeLabel: TextLabel
local gradeStroke: UIStroke?
local gradeScale: UIScale
local gradeGrad: UIGradient
local gradeToken = 0

local jarFill: Frame
local jarOver: Frame
local jarOverZone: Frame
local jarTick: Frame
local jarLabel: TextLabel
local jarFillGrad: UIGradient
local statusLabel: TextLabel
local statusScale: UIScale
local statusPulse: Tween? = nil

local eventPill: Frame
local eventLabel: TextLabel
local eventGrad: UIGradient
local cityBar: UIKit.Bar
local cityBoost: Frame
local cityBoostLabel: TextLabel
local multPill: Frame
local multLabel: TextLabel
local boostPill: Frame
local boostLabel: TextLabel

type Counter = {
	label: TextLabel,
	scale: UIScale,
	shown: number,
	from: number,
	target: number,
	t0: number,
	conn: RBXScriptConnection?,
	ready: boolean,
}
local volts: Counter
local shards: Counter
local voltsPill: Frame

type Tile = { button: TextButton, badge: Frame, glow: Frame, glowTween: Tween?, scale: UIScale }
local tiles: { [string]: Tile } = {}
local moreTile: Tile

----------------------------------------------------------------------
-- Помощники
----------------------------------------------------------------------
local function loopTween(obj: Instance, time: number, props: { [string]: any }): Tween
	local tw = TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), props)
	tw:Play()
	return tw
end

local function multText(m: number): string
	local text = string.format(if m >= 100 then "%.0f" elseif m >= 10 then "%.1f" else "%.2f", m)
	text = string.gsub(text, "(%.%d-)0+$", "%1")
	text = string.gsub(text, "%.$", "")
	return "×" .. text
end

local function baseScale(s: UIScale): number
	return (s:GetAttribute("BaseScale") :: number?) or s.Scale
end

local function viewport(): Vector2
	local cam = Workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

local function gameState(): Instance?
	return ReplicatedStorage:FindFirstChild("GameState")
end

local function attrNumber(inst: Instance?, name: string): number?
	if not inst then
		return nil
	end
	local v = inst:GetAttribute(name)
	return if typeof(v) == "number" then v else nil
end

local function playerNumber(name: string): number
	local v = player:GetAttribute(name)
	return if typeof(v) == "number" then v else 0
end

----------------------------------------------------------------------
-- Счётчики (Вольты, осколки): плавный пересчёт + пружинка
----------------------------------------------------------------------
local function newCounter(label: TextLabel, scale: UIScale): Counter
	return { label = label, scale = scale, shown = 0, from = 0, target = 0, t0 = 0, conn = nil, ready = false }
end

local function setCounter(c: Counter, value: number)
	if not c.ready then
		c.ready = true
		c.shown, c.from, c.target = value, value, value
		c.label.Text = Format.short(value)
		return
	end
	if value == c.target then
		return
	end
	if value > c.target then
		UIKit.bump(c.scale, 0.12)
	end
	c.from = c.shown
	c.target = value
	c.t0 = os.clock()
	if c.conn then
		return
	end
	c.conn = RunService.Heartbeat:Connect(function()
		local k = math.clamp((os.clock() - c.t0) / 0.6, 0, 1)
		local e = 1 - (1 - k) ^ 3
		c.shown = c.from + (c.target - c.from) * e
		c.label.Text = Format.short(c.shown)
		if k >= 1 then
			c.shown = c.target
			c.label.Text = Format.short(c.target)
			local conn = c.conn
			c.conn = nil
			if conn then
				conn:Disconnect()
			end
		end
	end)
end

----------------------------------------------------------------------
-- Сверху по центру: Вольты, осколки, банка
----------------------------------------------------------------------
local function pill(parent: Instance, name: string, w: number, h: number, icon: string, color: Color3, order: number): (Frame, TextLabel, UIScale)
	local frame = UIKit.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = WHITE,
		LayoutOrder = order,
		Parent = parent,
	}) :: Frame
	UIKit.round(frame)
	UIKit.stroke(frame, 3, Theme.Stroke)
	UIKit.gradient(frame, Theme.PanelLight, Theme.PanelDark)
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = frame }) :: UIScale
	local circle = UIKit.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(h + 4, h + 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, math.floor(h * 0.42), 0.5, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = frame,
	}) :: Frame
	UIKit.round(circle)
	UIKit.stroke(circle, 3, Theme.Stroke)
	UIKit.gradient(circle, color:Lerp(WHITE, 0.35), color:Lerp(BLACK, 0.25))
	UIKit.label({
		Name = "Glyph",
		Text = icon,
		Size = UDim2.fromScale(0.68, 0.68),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = h,
		NoStroke = true,
		ZIndex = 3,
		Parent = circle,
	})
	local value = UIKit.label({
		Name = "Value",
		Text = "0",
		FontFace = Theme.FontNumber,
		TextColor3 = color,
		Size = UDim2.new(1, -(h + 16), 0.76, 0),
		Position = UDim2.new(0, h + 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		MaxTextSize = math.floor(h * 0.72),
		ZIndex = 2,
		Parent = frame,
	})
	return frame, value, scale
end

local function buildTop()
	topRoot = UIKit.new("Frame", {
		Name = "Top",
		Size = UDim2.fromOffset(TOP_W, PILL_H + 8 + JAR_H + 4 + STATUS_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	topScale = UIKit.autoScale(topRoot, "hud", 1280, 720)

	local row = UIKit.new("Frame", {
		Name = "Currency",
		Size = UDim2.fromOffset(TOP_W, PILL_H),
		BackgroundTransparency = 1,
		Parent = topRoot,
	}) :: Frame
	UIKit.list(row, Enum.FillDirection.Horizontal, 12)
	local vPill, vLabel, vScale = pill(row, "Volts", 258, PILL_H, "⚡", Theme.Volt, 1)
	voltsPill = vPill
	volts = newCounter(vLabel, vScale)
	local _, sLabel, sScale = pill(row, "Shards", 170, PILL_H, "💎", Theme.Shard, 2)
	shards = newCounter(sLabel, sScale)

	-- банка: обычная часть + красная зона перегрузки (100–150%)
	local jar = UIKit.new("Frame", {
		Name = "Jar",
		Size = UDim2.fromOffset(TOP_W - 20, JAR_H),
		Position = UDim2.fromOffset(10, PILL_H + 8),
		BackgroundColor3 = Theme.PanelDark,
		Parent = topRoot,
	}) :: Frame
	UIKit.round(jar)
	UIKit.stroke(jar, 3, Theme.Stroke)
	jarOverZone = UIKit.new("Frame", {
		Name = "OverZone",
		Size = UDim2.fromScale(1 / 3, 1),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		BackgroundColor3 = Theme.RedDark,
		BackgroundTransparency = 0.45,
		Visible = false,
		Parent = jar,
	}) :: Frame
	UIKit.round(jarOverZone)
	jarFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = jar,
	}) :: Frame
	UIKit.round(jarFill)
	jarFillGrad = UIKit.gradient(jarFill, Theme.Electric:Lerp(WHITE, 0.3), Theme.ElectricDark)
	jarOver = UIKit.new("Frame", {
		Name = "Over",
		Size = UDim2.fromScale(0, 1),
		Position = UDim2.fromScale(2 / 3, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Visible = false,
		Parent = jar,
	}) :: Frame
	UIKit.round(jarOver)
	UIKit.gradient(jarOver, Color3.fromRGB(255, 150, 140), Theme.Red)
	jarTick = UIKit.new("Frame", {
		Name = "Tick",
		Size = UDim2.new(0, 3, 1, -6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(2 / 3, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.25,
		ZIndex = 3,
		Visible = false,
		Parent = jar,
	}) :: Frame
	jarLabel = UIKit.label({
		Name = "Label",
		Text = "🫙 Банка 0/25",
		Size = UDim2.new(1, -20, 1, -6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 26,
		ZIndex = 4,
		Parent = jar,
	})

	statusLabel = UIKit.label({
		Name = "Status",
		Text = "",
		Size = UDim2.fromOffset(TOP_W, STATUS_H),
		Position = UDim2.fromOffset(0, PILL_H + 8 + JAR_H + 4),
		TextColor3 = Theme.Miss,
		MaxTextSize = 26,
		Visible = false,
		Parent = topRoot,
	})
	statusScale = UIKit.new("UIScale", { Scale = 1, Parent = statusLabel }) :: UIScale
end

local function setPulse(on: boolean)
	if on and not statusPulse then
		statusScale.Scale = 1
		statusPulse = loopTween(statusScale, 0.45, { Scale = 1.12 })
	elseif not on and statusPulse then
		statusPulse:Cancel()
		statusPulse = nil
		statusScale.Scale = 1
	end
end

local lastJarKey = ""
local function updateJar()
	local fill = playerNumber(Net.PlayerAttrs.JarFill)
	local cap = ClientState.capacity()
	local zone = ClientState.zone()
	local zdef = Config.Zones[zone]
	local d = ClientState.get()
	-- с включённым Тесла-дроном банка не перегружается: дрон забирает её на 100%
	local droneOn = d ~= nil and d.Drone and d.DroneOn
	local overAllowed = zdef ~= nil and zdef.Overcharge and not droneOn
	local overMode = overAllowed or fill > 1.001
	local normalFrac = if overMode then 1 / Config.Overcharge.MaxFill else 1
	-- атрибут JarFill приходит сразу после поимки; точное число берём из данных, если они свежие
	local charge = fill * cap
	if d and math.abs(d.Charge / math.max(1, cap) - fill) < 0.02 then
		charge = d.Charge
	end

	jarOverZone.Visible = overMode
	jarTick.Visible = overMode
	jarOverZone.Size = UDim2.fromScale(1 - normalFrac, 1)
	jarTick.Position = UDim2.fromScale(normalFrac, 0.5)
	jarOver.Position = UDim2.fromScale(normalFrac, 0)
	local nf = math.min(fill, 1) * normalFrac
	UIKit.tween(jarFill, 0.18, { Size = UDim2.fromScale(nf, 1) })
	jarFill.Visible = nf > 0.004
	local over = math.clamp(fill - 1, 0, Config.Overcharge.MaxFill - 1) / (Config.Overcharge.MaxFill - 1)
	jarOver.Visible = overMode and over > 0.002
	UIKit.tween(jarOver, 0.18, { Size = UDim2.fromScale(over * (1 - normalFrac), 1) })

	jarLabel.Text = string.format("🫙 Банка %s/%s", Format.short(math.floor(charge + 0.5)), Format.short(cap))

	-- цвет заливки: голубая → золотая (почти полна)
	local key = if fill >= 0.999 then "full" elseif fill >= 0.8 then "high" else "low"
	if key ~= lastJarKey then
		lastJarKey = key
		if key == "low" then
			jarFillGrad.Color = ColorSequence.new(Theme.Electric:Lerp(WHITE, 0.3), Theme.ElectricDark)
		else
			jarFillGrad.Color = ColorSequence.new(Theme.Volt:Lerp(WHITE, 0.3), Theme.GoldDark)
		end
	end

	-- строка состояния: риск перегрузки или "сдай заряд" (или Тесла-дрон везёт заряд)
	local full = (fill >= 0.999 and not overAllowed) or fill >= Config.Overcharge.MaxFill - 0.001
	local droneAway = droneOn and ClientState.droneAway()
	if full and zone ~= 0 then
		statusLabel.Visible = true
		statusLabel.Text = if droneAway then "Банка полна — дрон скоро вернётся" else "Банка полна — сдай заряд!"
		statusLabel.TextColor3 = Theme.Volt
		setPulse(not droneAway)
	elseif full then
		statusLabel.Visible = true
		statusLabel.Text = "Сдай заряд у Тесла-башни!"
		statusLabel.TextColor3 = Theme.Volt
		setPulse(true)
	elseif fill > 1.001 then
		local ins = if d then d.Upgrades.Insulation else 0
		local risk = Strikes.overchargeRisk(fill, ins)
		statusLabel.Visible = true
		statusLabel.Text = string.format("⚠ Перегрузка! Риск %d%%", math.floor(risk * 100 + 0.5))
		statusLabel.TextColor3 = Theme.Miss
		setPulse(false)
	elseif droneAway then
		statusLabel.Visible = true
		statusLabel.Text = "🤖 Дрон везёт заряд"
		statusLabel.TextColor3 = Theme.Electric
		setPulse(false)
	else
		statusLabel.Visible = false
		setPulse(false)
	end
end

----------------------------------------------------------------------
-- Справа сверху: событие, Электроград, множитель, буст ×2
----------------------------------------------------------------------
local function smallPill(parent: Instance, name: string, w: number, h: number, color: Color3, order: number): (Frame, TextLabel)
	local frame = UIKit.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = WHITE,
		LayoutOrder = order,
		Parent = parent,
	}) :: Frame
	UIKit.round(frame)
	UIKit.stroke(frame, 2.5, Theme.Stroke)
	UIKit.gradient(frame, color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.3))
	local label = UIKit.label({
		Name = "Label",
		Text = "",
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = math.floor(h * 0.62),
		Parent = frame,
	})
	return frame, label
end

local function buildRight()
	rightRoot = UIKit.new("Frame", {
		Name = "Right",
		Size = UDim2.fromOffset(RIGHT_W, 48 + 8 + 70 + 8 + 42),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(rightRoot, "hud", 1280, 720)
	-- внутренний масштаб: на телефоне блок крупнее, чтобы таймер читался
	rightInner = UIKit.new("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		Parent = rightRoot,
	}) :: Frame
	rightInnerScale = UIKit.new("UIScale", { Scale = 1, Parent = rightInner }) :: UIScale
	UIKit.list(rightInner, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top)

	-- событие
	eventPill = UIKit.new("Frame", {
		Name = "Event",
		Size = UDim2.fromOffset(RIGHT_W, 48),
		BackgroundColor3 = WHITE,
		LayoutOrder = 1,
		Parent = rightInner,
	}) :: Frame
	UIKit.round(eventPill)
	UIKit.stroke(eventPill, 2.5, Theme.Stroke)
	eventGrad = UIKit.gradient(eventPill, Theme.PanelLight, Theme.PanelDark)
	eventLabel = UIKit.label({
		Name = "Label",
		Text = "",
		Size = UDim2.new(1, -18, 1, -10),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 26,
		Parent = eventPill,
	})

	-- Электроград
	local city = UIKit.new("Frame", {
		Name = "City",
		Size = UDim2.fromOffset(RIGHT_W, 70),
		BackgroundColor3 = WHITE,
		LayoutOrder = 2,
		Parent = rightInner,
	}) :: Frame
	UIKit.corner(city, Theme.CornerSmall)
	UIKit.stroke(city, 2.5, Theme.Stroke)
	UIKit.gradient(city, Theme.PanelLight, Theme.PanelDark)
	UIKit.label({
		Name = "Title",
		Text = "🏙 Электроград",
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = city,
	})
	cityBar = UIKit.bar({
		Name = "CityBar",
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 36),
		Color = Theme.Volt,
		TextSize = 18,
		Parent = city,
	})
	cityBoost = UIKit.new("Frame", {
		Name = "Boost",
		Size = UDim2.fromOffset(150, 30),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 3),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 3,
		Parent = city,
	}) :: Frame
	UIKit.round(cityBoost)
	UIKit.stroke(cityBoost, 2, Theme.Stroke)
	UIKit.gradient(cityBoost, Theme.Volt, Theme.Orange)
	cityBoostLabel = UIKit.label({
		Name = "Label",
		Text = "",
		Size = UDim2.new(1, -10, 1, -4),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 20,
		ZIndex = 4,
		Parent = cityBoost,
	})

	-- множитель и личный буст
	local row = UIKit.new("Frame", {
		Name = "Pills",
		Size = UDim2.fromOffset(RIGHT_W, 42),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = rightInner,
	}) :: Frame
	UIKit.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right)
	boostPill, boostLabel = smallPill(row, "Boost2x", 150, 42, Theme.Orange, 1)
	multPill, multLabel = smallPill(row, "Multiplier", 120, 42, Theme.Purple, 2)
	boostPill.Visible = false
	multPill.Visible = false
end

local lastEventKey = ""
local function updateRight()
	local gs = gameState()
	local now = ClientState.now()
	-- событие
	local ev = if gs then gs:GetAttribute("Event") else nil
	local info = if typeof(ev) == "string" then EVENT_INFO[ev] else nil
	local key: string
	if info then
		local ends = attrNumber(gs, "EventEnds")
		if ends and ends > now then
			eventLabel.Text = info.Now .. " " .. Format.time(ends - now)
		else
			eventLabel.Text = info.Now .. "!"
		end
		key = "now:" .. tostring(ev)
		if key ~= lastEventKey then
			eventGrad.Color = ColorSequence.new(info.Color:Lerp(WHITE, 0.25), info.Color:Lerp(BLACK, 0.35))
		end
		eventPill.Visible = true
	else
		local best: number? = nil
		local bestText = ""
		for _, e in NEXT_EVENTS do
			local t = attrNumber(gs, e.Attr)
			if t and t > now and (best == nil or t < best) then
				best = t
				bestText = e.Text
			end
		end
		key = "next"
		if key ~= lastEventKey then
			eventGrad.Color = ColorSequence.new(Theme.PanelLight, Theme.PanelDark)
		end
		if best then
			eventLabel.Text = bestText .. Format.time(best - now)
			eventPill.Visible = true
		else
			eventPill.Visible = false
		end
	end
	lastEventKey = key

	-- Электроград
	local points = attrNumber(gs, "CityPoints") or 0
	local target = math.max(1, attrNumber(gs, "CityTarget") or 1)
	local boostUntil = attrNumber(gs, "CityBoostUntil") or 0
	if boostUntil > now then
		cityBoost.Visible = true
		cityBoostLabel.Text = "×2 ВОЛЬТ " .. Format.time(boostUntil - now)
		cityBar.setColor(Theme.Gold)
		cityBar.set(1, "Город сияет!")
	else
		cityBoost.Visible = false
		cityBar.setColor(Theme.Volt)
		cityBar.set(points / target, string.format("%d/%d", math.floor(points), math.floor(target)))
	end

	-- множитель и буст ×2
	local d = ClientState.get()
	local m = ClientState.multiplier()
	multPill.Visible = m > 1.001
	multLabel.Text = "⚡ " .. multText(m)
	local untilT = if d then d.Boosts.Volts2x else 0
	local left = untilT - now -- буст хранит серверный os.time()
	if left > 0 then
		boostPill.Visible = true
		boostLabel.Text = "×2 ⚡ " .. Format.time(left)
	else
		boostPill.Visible = false
	end
end

----------------------------------------------------------------------
-- Меню: на ПК — два столбца по центру слева; на сенсорном экране — только верхняя треть
-- (левые 40% нижних 2/3 — зона джойстика): что не поместилось крупно, прячется в «Ещё»
----------------------------------------------------------------------
local function setGlow(tile: Tile, on: boolean)
	if on and not tile.glowTween then
		tile.glow.Visible = true
		tile.glow.BackgroundTransparency = 0.75
		tile.glowTween = loopTween(tile.glow, 0.6, { BackgroundTransparency = 0.25 })
	elseif not on and tile.glowTween then
		tile.glowTween:Cancel()
		tile.glowTween = nil
		tile.glow.Visible = false
	end
end

local function makeTile(name: string, icon: string, text: string, color: Color3, order: number, onClick: () -> ()): (Tile, TextLabel)
	local button = UIKit.new("TextButton", {
		Name = name,
		BackgroundColor3 = color:Lerp(BLACK, 0.45),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Active = true,
		Parent = menuRoot,
	}) :: TextButton
	UIKit.round(button)
	UIKit.stroke(button, 3, Theme.Stroke)
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = button }) :: UIScale
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		Size = UDim2.fromScale(1.3, 1.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Theme.Volt,
		BackgroundTransparency = 0.5,
		Visible = false,
		ZIndex = 0,
		Parent = button,
	}) :: Frame
	UIKit.round(glow)
	local face = UIKit.new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 0.93),
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = button,
	}) :: Frame
	UIKit.round(face)
	UIKit.gradient(face, color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.12))
	local shine = UIKit.new("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(0.7, 0.32),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.06),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.78,
		ZIndex = 1,
		Parent = face,
	})
	UIKit.round(shine)
	local iconLabel = UIKit.label({
		Name = "Icon",
		Text = icon,
		Size = UDim2.fromScale(0.56, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		MaxTextSize = 60,
		NoStroke = true,
		ZIndex = 2,
		Parent = face,
	})
	UIKit.label({
		Name = "Label",
		Text = text,
		Size = UDim2.fromScale(1.12, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.82),
		MaxTextSize = 40,
		ZIndex = 3,
		Parent = face,
	})
	local badge = UIKit.badge(button, "!", 28)
	badge.Size = UDim2.fromScale(0.34, 0.34)
	badge.Position = UDim2.fromScale(0.88, 0.12)

	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, 0.07, { Scale = 0.9 })
	end)
	button.MouseLeave:Connect(function()
		UIKit.tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Up:Connect(function()
		UIKit.tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		UIKit.playClick()
		UIKit.tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		onClick()
	end)
	return { button = button, badge = badge, glow = glow, glowTween = nil, scale = scale }, iconLabel
end

local moreIcon: TextLabel

-- Значок и свечение «Ещё» повторяют спрятанные кнопки (например, «!» у наград)
local function refreshMore()
	if not moreTile then
		return
	end
	local badge, glow = false, false
	for _, name in hiddenTiles do
		local t = tiles[name]
		if t then
			badge = badge or t.badge.Visible
			glow = glow or t.glowTween ~= nil
		end
	end
	moreTile.badge.Visible = badge and not moreOpen
	setGlow(moreTile, glow and not moreOpen)
end

local function setMoreOpen(open: boolean)
	moreToken += 1
	moreOpen = open and #hiddenTiles > 0
	moreRoot.Visible = moreOpen
	moreIcon.Text = if moreOpen then "➖" else "➕"
	refreshMore()
	if moreOpen then
		local token = moreToken
		task.delay(MORE_AUTO_CLOSE, function()
			if token == moreToken and moreOpen then
				setMoreOpen(false)
			end
		end)
	end
end

local function buildMenu()
	menuRoot = UIKit.new("Frame", {
		Name = "Menu",
		Size = UDim2.fromOffset(200, 400),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	menuScale = UIKit.autoScale(menuRoot, "hud", 1280, 720)
	menuGrid = UIKit.grid(menuRoot, Vector2.new(84, 84), MENU_GAP)
	menuGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	menuGrid.FillDirection = Enum.FillDirection.Horizontal

	for i, m in MENU do
		tiles[m.Name] = makeTile(m.Name, m.Icon, m.Text, m.Color, i, function()
			if moreOpen then
				setMoreOpen(false)
			end
			ClientState.OpenWindow:Fire(m.Window)
		end)
	end

	-- «Ещё» — последняя плитка ряда; раскрывает блок со спрятанными кнопками прямо под собой
	local more, icon = makeTile("MoreButton", "➕", "Ещё", Theme.ElectricDark, #MENU + 1, function()
		setMoreOpen(not moreOpen)
	end)
	more.button.Visible = false
	moreTile, moreIcon = more, icon
	moreRoot = UIKit.new("Frame", {
		Name = "MenuMore",
		Size = UDim2.fromOffset(100, 100),
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.2,
		Visible = false,
		ZIndex = 4,
		Parent = gui,
	}) :: Frame
	UIKit.corner(moreRoot, Theme.CornerSmall)
	UIKit.stroke(moreRoot, 3, Theme.Stroke)
	UIKit.autoScale(moreRoot, "hud", 1280, 720)
	UIKit.padding(moreRoot, morePad)
	moreGrid = UIKit.grid(moreRoot, Vector2.new(84, 84), MENU_GAP)
	moreGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	moreGrid.FillDirection = Enum.FillDirection.Horizontal
end

-- Значки "!" на кнопках меню: можно забрать награду, купить улучшение, надеть питомца...
local function updateBadges(d: PlayerData.Data)
	-- день считаем по серверному времени (как DailyService), а не по часам устройства
	local today = Quests.dayNumber(math.floor(ClientState.now()))
	local dailyReady = today > d.Daily.LastDay
	if not dailyReady then
		for _, q in d.Quests.List do
			if q.Progress >= q.Target and not q.Claimed then
				dailyReady = true
				break
			end
		end
	end
	tiles.DailyButton.badge.Visible = dailyReady

	local canRebirth = Economy.canRebirth(d)
	tiles.RebirthButton.badge.Visible = canRebirth
	setGlow(tiles.RebirthButton, canRebirth)

	local nextZone = d.Zone + 1
	local zoneReady = Config.Zones[nextZone] ~= nil and d.Volts >= Economy.zoneCost(nextZone)
	tiles.TeleportButton.badge.Visible = zoneReady

	local shopReady = zoneReady
	if not shopReady then
		for _, id in Config.UpgradeOrder do
			local cost = Economy.upgradeCost(id, (d.Upgrades :: any)[id] :: number)
			if cost and d.Volts >= cost then
				shopReady = true
				break
			end
		end
	end
	if not shopReady and not d.Drone and d.Zone >= Config.Drone.FromZone and d.Volts >= Config.Drone.Cost then
		shopReady = true
	end
	tiles.ShopButton.badge.Visible = shopReady

	local slots = Economy.petSlots(d.Rebirths)
	local petsReady = #d.Equipped < math.min(slots, #d.Pets)
	if not petsReady and #d.Pets < Pets.MaxInventory then
		for _, id in Pets.CocoonOrder do
			local c = Pets.Cocoons[id]
			if d.Zone >= c.Zone and d.Shards >= c.Cost then
				petsReady = true
				break
			end
		end
	end
	tiles.PetsButton.badge.Visible = petsReady

	tiles.CollectionButton.badge.Visible = #d.EquippedFulgs < math.min(Fulgurite.MaxEquipped, #d.Fulgs)
	refreshMore()
end

----------------------------------------------------------------------
-- Кнопка ⚡ ЛОВИ и комбо (справа снизу, левее кнопки прыжка)
----------------------------------------------------------------------
local function pressCatch()
	ClientState.CatchPressed:Fire()
	catchButtonScale.Scale = 0.86
	UIKit.tween(catchButtonScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	-- расходящееся кольцо
	local ringScale = catchRing:FindFirstChildOfClass("UIScale")
	local stroke = catchRing:FindFirstChildOfClass("UIStroke")
	if ringScale and stroke then
		catchRing.Visible = true
		ringScale.Scale = 1
		stroke.Transparency = 0.1
		UIKit.tween(ringScale, 0.35, { Scale = 1.45 })
		UIKit.tween(stroke, 0.35, { Transparency = 1 })
	end
end

local function buildCatch()
	catchRoot = UIKit.new("Frame", {
		Name = "Catch",
		Size = UDim2.fromOffset(180, 240),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	catchScale = UIKit.autoScale(catchRoot, "hud", 1280, 720)

	catchButton = UIKit.new("TextButton", {
		Name = "CatchButton",
		Size = UDim2.fromOffset(120, 120),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.GoldDark,
		AutoButtonColor = false,
		Text = "",
		Active = true,
		Selectable = false,
		Parent = catchRoot,
	}) :: TextButton
	UIKit.round(catchButton)
	UIKit.stroke(catchButton, 4, Theme.Stroke)
	catchButtonScale = UIKit.new("UIScale", { Scale = 1, Parent = catchButton }) :: UIScale

	local halo = UIKit.new("Frame", {
		Name = "Halo",
		Size = UDim2.fromScale(1.18, 1.18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Theme.Volt,
		BackgroundTransparency = 0.8,
		ZIndex = 0,
		Parent = catchButton,
	}) :: Frame
	UIKit.round(halo)
	loopTween(halo, 0.9, { BackgroundTransparency = 0.55 })

	local face = UIKit.new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 0.94),
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = catchButton,
	}) :: Frame
	UIKit.round(face)
	UIKit.gradient(face, Color3.fromRGB(255, 240, 130), Color3.fromRGB(255, 160, 30))
	local ring = UIKit.new("Frame", {
		Name = "InnerRing",
		Size = UDim2.fromScale(0.84, 0.84),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = face,
	})
	UIKit.round(ring)
	UIKit.stroke(ring, 3, WHITE, 0.45)
	local shine = UIKit.new("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(0.6, 0.26),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.7,
		ZIndex = 2,
		Parent = face,
	})
	UIKit.round(shine)
	UIKit.label({
		Name = "Icon",
		Text = "⚡",
		Size = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		MaxTextSize = 100,
		NoStroke = true,
		ZIndex = 3,
		Parent = face,
	})
	UIKit.label({
		Name = "Label",
		Text = "ЛОВИ!",
		Size = UDim2.fromScale(0.78, 0.25),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72),
		MaxTextSize = 100,
		ZIndex = 3,
		Parent = face,
	})

	catchRing = UIKit.new("Frame", {
		Name = "PressRing",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
		Parent = catchButton,
	}) :: Frame
	UIKit.round(catchRing)
	UIKit.stroke(catchRing, 5, Theme.Volt, 1)
	UIKit.new("UIScale", { Scale = 1, Parent = catchRing })

	-- мгновенный отклик: InputBegan, а не Activated
	catchButton.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) and input.UserInputState == Enum.UserInputState.Begin then
			pressCatch()
		end
	end)

	comboLabel = UIKit.label({
		Name = "Combo",
		Text = "",
		Size = UDim2.new(1.6, 0, 0, 44),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -128),
		TextColor3 = WHITE,
		MaxTextSize = 44,
		Visible = false,
		Parent = catchRoot,
	})
	comboScale = UIKit.new("UIScale", { Scale = 1, Parent = comboLabel }) :: UIScale
	comboGrad = UIKit.new("UIGradient", {
		Color = ColorSequence.new(WHITE, Theme.Good),
		Rotation = 90,
		Parent = comboLabel,
	}) :: UIGradient
end

local function comboColor(c: number): Color3
	if c >= Config.Catch.ComboCap then
		return Theme.Perfect
	elseif c >= 20 then
		return Theme.Orange
	elseif c >= 10 then
		return Theme.Purple
	elseif c >= 5 then
		return Theme.Electric
	end
	return Theme.Good
end

local function comboBase(c: number): number
	return 0.85 + 0.3 * math.min(c, Config.Catch.ComboCap) / Config.Catch.ComboCap
end

local function updateCombo()
	local c = math.floor(playerNumber(Net.PlayerAttrs.Combo))
	if c <= 0 then
		if comboLabel.Visible and lastCombo > 0 then
			local tw = UIKit.tween(comboScale, 0.15, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tw.Completed:Once(function()
				if math.floor(playerNumber(Net.PlayerAttrs.Combo)) <= 0 then
					comboLabel.Visible = false
				end
			end)
		end
		lastCombo = 0
		return
	end
	comboLabel.Visible = true
	comboLabel.Text = string.format("x%d КОМБО", c)
	local col = comboColor(c)
	comboGrad.Color = ColorSequence.new(col:Lerp(WHITE, 0.55), col)
	local base = comboBase(c)
	comboScale:SetAttribute("BaseScale", base)
	if c > lastCombo then
		UIKit.bump(comboScale, if c % 5 == 0 then 0.35 else 0.18)
	else
		comboScale.Scale = base
	end
	lastCombo = c
end

----------------------------------------------------------------------
-- Надпись оценки по центру
----------------------------------------------------------------------
local function buildGrade()
	gradeRoot = UIKit.new("Frame", {
		Name = "Grade",
		Size = UDim2.fromOffset(640, 130),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(gradeRoot, "hud", 1280, 720)
	gradeLabel = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = WHITE,
		MaxTextSize = 84,
		TextTransparency = 1,
		Parent = gradeRoot,
	})
	gradeStroke = gradeLabel:FindFirstChildOfClass("UIStroke")
	local stroke = gradeStroke
	if stroke then
		stroke.Thickness = 4
		stroke.Transparency = 1
	end
	gradeScale = UIKit.new("UIScale", { Scale = 1, Parent = gradeLabel }) :: UIScale
	gradeGrad = UIKit.new("UIGradient", {
		Color = ColorSequence.new(WHITE, Theme.Perfect),
		Rotation = 90,
		Parent = gradeLabel,
	}) :: UIGradient
end

local function showGrade(text: string, color: Color3, size: number, wobble: boolean)
	gradeToken += 1
	local token = gradeToken
	gradeLabel.Text = text
	gradeGrad.Color = ColorSequence.new(color:Lerp(WHITE, 0.6), color)
	gradeLabel.TextTransparency = 0
	local stroke = gradeStroke
	if stroke then
		stroke.Transparency = 0
	end
	gradeScale.Scale = size * 0.35
	UIKit.tween(gradeScale, 0.32, { Scale = size }, Enum.EasingStyle.Back)
	if wobble then
		gradeLabel.Rotation = -9
		UIKit.tween(gradeLabel, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic)
	else
		gradeLabel.Rotation = 0
	end
	task.delay(0.6, function()
		if token ~= gradeToken then
			return
		end
		UIKit.tween(gradeLabel, 0.3, { TextTransparency = 1 })
		UIKit.tween(gradeScale, 0.3, { Scale = size * 1.08 })
		local s = gradeStroke
		if s then
			UIKit.tween(s, 0.3, { Transparency = 1 })
		end
	end)
end

----------------------------------------------------------------------
-- Раскладка под экран (телефон / планшет / ПК)
----------------------------------------------------------------------
-- Самая крупная квадратная плитка для count кнопок в полосе availW × availH (реальные точки): (столбцы, ряды, плитка)
local function fitMenu(count: number, availW: number, availH: number, gap: number, maxTile: number): (number, number, number)
	local bestCols, bestRows, bestTile = count, 1, -math.huge
	for r = 1, count do
		local cols = math.ceil(count / r)
		local rows = math.ceil(count / cols)
		local tile = math.min((availW - (cols - 1) * gap) / cols, (availH - (rows - 1) * gap) / rows, maxTile)
		if tile > bestTile + 0.5 then
			bestCols, bestRows, bestTile = cols, rows, tile
		end
	end
	return bestCols, bestRows, bestTile
end

-- Первые shown кнопок — в меню, остальные — в блок «Ещё»
local function applyMenuSplit(shown: number)
	table.clear(hiddenTiles)
	for i, m in MENU do
		local t = tiles[m.Name]
		if i <= shown then
			t.button.Parent = menuRoot
		else
			t.button.Parent = moreRoot
			table.insert(hiddenTiles, m.Name)
		end
	end
	moreTile.button.Visible = #hiddenTiles > 0
	if moreOpen and #hiddenTiles == 0 then
		setMoreOpen(false)
	end
	refreshMore()
end

local function layout()
	local phone = UIKit.isPhone()
	local touch = UIKit.isTouch()
	local vp = viewport()
	local inset = GuiService:GetGuiInset().Y
	local sCatch = baseScale(catchScale)
	local sMenu = baseScale(menuScale)

	-- кнопка ЛОВИ: постоянный реальный размер, левее кнопки прыжка на сенсорных экранах
	local px = if phone then CATCH_PX_PHONE else CATCH_PX_PC
	local btn = math.floor(px / sCatch)
	local comboH = math.floor((if phone then 30 else 38) / sCatch)
	local rootW = math.floor(btn * 1.8)
	catchButton.Size = UDim2.fromOffset(btn, btn)
	catchRoot.Size = UDim2.fromOffset(rootW, btn + comboH + math.floor(10 / sCatch))
	local rightMargin = if phone then 110 elseif touch then 190 else 24
	if phone then
		catchRoot.Position = UDim2.new(1, -110, 1, -30)
	elseif touch then
		catchRoot.Position = UDim2.new(1, -190, 1, -40)
	else
		catchRoot.Position = UDim2.new(1, -24, 1, -24)
	end
	-- комбо по центру над кнопкой (кнопка прижата к правому краю корня), не шире, чем до края экрана
	local spare = math.min(math.floor(btn * 0.4), math.floor((rightMargin - 6) / sCatch))
	comboLabel.AnchorPoint = Vector2.new(0.5, 1)
	comboLabel.Size = UDim2.fromOffset(btn + 2 * spare, comboH)
	comboLabel.Position = UDim2.new(1, -math.floor(btn / 2), 1, -(btn + math.floor(8 / sCatch)))

	-- правый блок: на телефоне крупнее; на портретном экране уходит под верхний блок
	local portrait = vp.X < vp.Y
	rightInnerScale.Scale = if phone then 1.22 else 1
	if portrait then
		rightRoot.Position = UDim2.new(1, -8, 0, math.floor((PILL_H + JAR_H + STATUS_H + 30) * baseScale(topScale)))
	else
		rightRoot.Position = UDim2.new(1, -8, 0, 6)
	end

	-- меню: на сенсорных экранах — ряд(ы) сразу под верхней панелью и только в верхней трети экрана
	-- (левые 40% нижних 2/3 — зона джойстика); что не помещается крупно — в «Ещё». На ПК — два столбца слева
	if touch then
		local guiW = if gui.AbsoluteSize.X > 0 then gui.AbsoluteSize.X else vp.X
		local guiH = if gui.AbsoluteSize.Y > 0 then gui.AbsoluteSize.Y else vp.Y - inset
		local top = 6
		local gapReal = if phone then 8 else 10
		local maxTile = if phone then 64 else 80
		local topW = TOP_W * baseScale(topScale)
		local rightW = if portrait then 0 else RIGHT_W * baseScale(topScale) * rightInnerScale.Scale + 8
		-- ширина: левее верхнего блока (по центру или, если тесно, сдвинутого вплотную к правому блоку)
		local availW = math.max((guiW - topW) / 2 - 20, guiW - rightW - topW - 30)
		-- высота: до верхней трети экрана
		local availH = vp.Y / 3 - inset - top
		local shown = #MENU
		local cols, rows, tile = fitMenu(#MENU, availW, availH, gapReal, maxTile)
		if tile < MENU_MIN_TILE then
			-- все не помещаются: последние кнопки уходят в «Ещё» (оно само — ещё одна плитка)
			for n = #MENU - 1, 1, -1 do
				shown = n
				cols, rows, tile = fitMenu(n + 1, availW, availH, gapReal, maxTile)
				if tile >= MENU_MIN_TILE then
					break
				end
			end
		end
		tile = math.max(1, math.floor(tile))
		applyMenuSplit(shown)
		local gap = math.floor(gapReal / sMenu)
		local t = math.floor(tile / sMenu)
		menuGrid.CellSize = UDim2.fromOffset(t, t)
		menuGrid.CellPadding = UDim2.fromOffset(gap, gap)
		menuRoot.Size = UDim2.fromOffset(cols * t + (cols - 1) * gap, rows * t + (rows - 1) * gap)
		menuRoot.AnchorPoint = Vector2.new(0, 0)
		menuRoot.Position = UDim2.new(0, 10, 0, top)
		-- блок «Ещё» — под своей плиткой: столбцом, а если не влезает по высоте — в несколько
		local hidden = #MENU - shown
		if hidden > 0 then
			local x = 10 + (shown % cols) * (tile + gapReal)
			local y = top + (shown // cols + 1) * (tile + gapReal)
			local pad = morePad * sMenu
			local fitRows = math.max(1, math.floor((guiH - y - 2 * pad - 6 + gapReal) / (tile + gapReal)))
			local mCols = math.ceil(hidden / fitRows)
			local mRows = math.ceil(hidden / mCols)
			local w = mCols * t + (mCols - 1) * gap + 2 * morePad
			local h = mRows * t + (mRows - 1) * gap + 2 * morePad
			moreGrid.CellSize = UDim2.fromOffset(t, t)
			moreGrid.CellPadding = UDim2.fromOffset(gap, gap)
			moreRoot.Size = UDim2.fromOffset(w, h)
			moreRoot.Position = UDim2.fromOffset(math.max(4, math.min(x - pad, guiW - w * sMenu - 6)), y)
		end
		-- узкий экран: верхний блок сдвигается правее меню, чтобы не наезжать на кнопки
		local menuRight = 10 + cols * tile + (cols - 1) * gapReal + 10
		if guiW / 2 - topW / 2 < menuRight then
			topRoot.AnchorPoint = Vector2.new(0, 0)
			topRoot.Position = UDim2.new(0, menuRight, 0, 6)
		else
			topRoot.AnchorPoint = Vector2.new(0.5, 0)
			topRoot.Position = UDim2.new(0.5, 0, 0, 6)
		end
	else
		applyMenuSplit(#MENU)
		topRoot.AnchorPoint = Vector2.new(0.5, 0)
		topRoot.Position = UDim2.new(0.5, 0, 0, 6)
		local t = 84
		menuGrid.CellSize = UDim2.fromOffset(t, t)
		menuGrid.CellPadding = UDim2.fromOffset(MENU_GAP, MENU_GAP)
		menuRoot.Size = UDim2.fromOffset(2 * t + MENU_GAP, 4 * t + 3 * MENU_GAP)
		menuRoot.AnchorPoint = Vector2.new(0, 0.5)
		menuRoot.Position = UDim2.new(0, 14, 0.5, 0)
	end

	-- оценка — над персонажем; на телефоне ниже, чтобы не спорить с тостами
	gradeRoot.Position = UDim2.fromScale(0.5, if phone then 0.47 else 0.31)
end

----------------------------------------------------------------------
-- Данные и события
----------------------------------------------------------------------
local function onData(d: PlayerData.Data)
	setCounter(volts, d.Volts)
	setCounter(shards, d.Shards)
	updateBadges(d)
	updateJar()
end

local function onZone(zone: number)
	catchRoot.Visible = zone ~= 0
	updateJar()
end

function HUD.start()
	if gui then
		return
	end
	-- звуки интерфейса (клик кнопок и звуки окон)
	UIKit.setClickHandler(function()
		Sounds.play("Click")
	end)
	UIKit.setSoundHandler(function(name: string)
		Sounds.play(name)
	end)

	gui = UIKit.new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	buildTop()
	buildRight()
	buildMenu()
	buildCatch()
	buildGrade()
	layout()

	-- пересчитать раскладку, когда меняется экран (размер, поворот, вырезы и верхняя панель) или тип ввода;
	-- в следующем кадре и один раз на пачку изменений — после того, как UIKit пересчитал масштабы
	local layoutQueued = false
	local function queueLayout()
		if layoutQueued then
			return
		end
		layoutQueued = true
		task.defer(function()
			layoutQueued = false
			layout()
		end)
	end
	catchScale:GetPropertyChangedSignal("Scale"):Connect(queueLayout)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(queueLayout)
	local cameraConn: RBXScriptConnection? = nil
	local function bindCamera()
		local old = cameraConn
		if old then
			old:Disconnect()
		end
		local camera = Workspace.CurrentCamera
		cameraConn = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(queueLayout) else nil
		queueLayout()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()
	UIKit.onInputTypeChanged(queueLayout)

	-- раскрытое «Ещё» закрывается касанием мимо интерфейса и при открытии любого окна
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if moreOpen and not processed then
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
				setMoreOpen(false)
			end
		end
	end)
	ClientState.OpenWindow:Connect(function(_name: string)
		if moreOpen then
			setMoreOpen(false)
		end
	end)

	onZone(ClientState.zone())
	ClientState.ZoneChanged:Connect(function(zone: number)
		onZone(zone)
	end)
	ClientState.Changed:Connect(onData)
	local d = ClientState.get()
	if d then
		onData(d)
	end

	player:GetAttributeChangedSignal(Net.PlayerAttrs.JarFill):Connect(updateJar)
	player:GetAttributeChangedSignal(Net.PlayerAttrs.Combo):Connect(updateCombo)
	updateCombo()

	ClientState.LocalGrade:Connect(function(grade: string, _color: string, _combo: number)
		if grade == "perfect" then
			showGrade("ИДЕАЛЬНО!", Theme.Perfect, 1.15, true)
		elseif grade == "good" then
			showGrade("ХОРОШО", Theme.Good, 0.9, false)
		elseif grade == "miss" then
			showGrade("МИМО", Theme.Miss, 0.8, false)
		elseif grade == "zap" then
			-- прогноз CatchController: стоял в кольце и не нажал
			showGrade("ШАРАХНУЛО!", Theme.Zap, 1.1, true)
		end
	end)
	ClientState.StrikeResolved:Connect(function(msg: Net.StrikeResultMsg)
		if msg.Grade == "zap" then
			-- уже показано прогнозом клиента — ответ сервера только подтверждает
			if ClientState.predictedGrade(msg.Id, msg.Hit) ~= "zap" then
				showGrade("ШАРАХНУЛО!", Theme.Zap, 1.1, true)
			end
		elseif msg.Grade == "burst" then
			showGrade("БАНКА ЛОПНУЛА!", Theme.Red, 1.0, true)
		end
		-- новая ячейка Молниедекса: тост с цветом и островом присылает сервер (Notify), свой не дублируем
	end)

	-- киоски в хабе (ProximityPrompt на сервере) открывают окна через Effect; дрон улетел / сдал — строка банки
	ClientState.Effect:Connect(function(msg: Net.EffectMsg)
		if msg.Kind == "openWindow" and typeof(msg.Text) == "string" then
			ClientState.OpenWindow:Fire(msg.Text)
		elseif msg.Kind == "drone" and (msg.UserId == nil or msg.UserId == player.UserId) then
			updateJar()
			if msg.Text == "depart" then
				-- если "sold" не придёт (перезапуск, выход), строка сама вернётся
				local trip = if typeof(msg.Value) == "number" then math.clamp(msg.Value, 0, 60) else 5
				task.delay(trip + 2, updateJar)
			end
		end
	end)

	-- таймеры справа сверху и значки, зависящие от времени
	task.spawn(function()
		while gui.Parent do
			updateRight()
			local data = ClientState.get()
			if data then
				updateBadges(data)
			end
			task.wait(0.25)
		end
	end)
end

-- Для анимации "монеты летят в счётчик"
function HUD.voltsTarget(): GuiObject?
	return voltsPill
end

function HUD.bumpVolts()
	if volts then
		UIKit.bump(volts.scale, 0.15)
	end
end

-- Нижний край верхнего блока (под ним тосты)
function HUD.toastAnchor(): GuiObject?
	return topRoot
end

-- Для обучения: кнопка ЛОВИ и кнопки меню
function HUD.catchButton(): GuiObject?
	return catchButton
end

function HUD.menuButton(name: string): GuiObject?
	local t = tiles[name]
	return if t then t.button else nil
end

return HUD
