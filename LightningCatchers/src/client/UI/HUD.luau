--!strict
-- HUD «электро-наклейка» (docs/STYLE.md §8.4): чипы Вольт и осколков, банка-батарейка с зоной опасности
-- и тегом риска, кнопка ЛОВИ с нарисованной молнией и комбо «×12», слова-оценки с градиентом, наклоном
-- и взрывом-звездой, плитки меню слева (на сенсорных экранах — только в верхней трети, выше зоны джойстика;
-- что не влезло — в «Ещё»), таймер события, шкала Электрограда и множитель справа сверху.
-- Сначала телефон: на телефоне всё компактнее, кнопка ЛОВИ левее кнопки прыжка.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

-- Размеры макета (пиксели до масштабирования UIScale)
local TOP_W = 440
local CHIP_H = 52
local JAR_W = TOP_W - 34
local JAR_H = 34
local JAR_Y = CHIP_H + 14
local STATUS_H = 30
local TOP_H = JAR_Y + JAR_H + 6 + STATUS_H
local RIGHT_W = 300
local CATCH_PX_PHONE = 100 -- реальный размер кнопки ЛОВИ на экране
local CATCH_PX_PC = 120
local MENU_GAP = 10
local MENU_MIN_TILE = 56 -- сенсорный экран: плитка меню не мельче (реальные точки, кнопки ≥ 56), иначе часть уходит в «Ещё»
local CAPTION_PC = 22 -- высота тега-подписи под плиткой на ПК (точки макета)
local CAPTION_TOUCH = 18 -- на сенсорном экране (реальные точки: шрифт ≈ 11.5 px)
local MORE_AUTO_CLOSE = 6 -- раскрытое «Ещё» само закрывается через столько секунд
local CATCH_EST_N = 5 -- риск перегрузки: заряд следующей поимки = медиана стольких последних своих поимок
local HAZARD_STEP = 16 -- шаг диагональных полос опасности

-- Порядок = важность: на маленьком экране последние кнопки уходят в «Ещё»
-- (награды дня нужны с первой минуты, перезапуск — только через час-полтора, настройки — редко).
-- Акценты разделов — §8.2; Short — подпись под плиткой (короче 9 букв: «Перезапуск» не помещается)
local MENU = {
	{ Name = "ShopButton", Window = "Shop", Icon = "🛒", Short = "Магазин", Color = Theme.Volt },
	{ Name = "PetsButton", Window = "Pets", Icon = "🐾", Short = "Питомцы", Color = Theme.Pink },
	{ Name = "DailyButton", Window = "Daily", Icon = "🎁", Short = "Награды", Color = Theme.Go },
	{ Name = "TeleportButton", Window = "Teleport", Icon = "🌀", Short = "Острова", Color = Theme.Violet },
	{ Name = "CollectionButton", Window = "Collection", Icon = "🔮", Short = "Коллекция", Color = Theme.Spark },
	{ Name = "RebirthButton", Window = "Rebirth", Icon = "♻", Short = "Рестарт", Color = Theme.Orange },
	{ Name = "SettingsButton", Window = "Settings", Icon = "⚙", Short = "Настройки", Color = Theme.Slate },
}

local EVENT_INFO = {
	supercell = { Now = "Суперячейка", Icon = "⚡", Color = Theme.Supercell },
	ball = { Now = "Шаровая молния", Icon = "🔮", Color = Theme.Ball },
	rainbow = { Now = "Радужная молния", Icon = "🌈", Color = Theme.Rainbow },
} :: { [string]: { Now: string, Icon: string, Color: Color3 } }

local NEXT_EVENTS = {
	{ Attr = "NextSupercell", Text = "Суперячейка через ", Icon = "⚡", Color = Theme.Supercell },
	{ Attr = "NextBall", Text = "Шаровая через ", Icon = "🔮", Color = Theme.Ball },
	{ Attr = "NextRainbow", Text = "Радужная через ", Icon = "🌈", Color = Theme.Rainbow },
}

-- Слова-оценки (§8.4): размер, градиент букв, наклон
type GradeStyle = { Text: string, Size: number, Colors: { Color3 }, Tilt: number, Motion: string }
local GRADES: { [string]: GradeStyle } = {
	perfect = {
		Text = "ИДЕАЛЬНО!",
		Size = 96,
		Colors = { Color3.fromRGB(255, 255, 240), Color3.fromRGB(255, 226, 80), Color3.fromRGB(255, 160, 30) },
		Tilt = -6,
		Motion = "burst",
	},
	good = {
		Text = "ХОРОШО",
		Size = 72,
		Colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 230, 255) },
		Tilt = 3,
		Motion = "spark",
	},
	miss = {
		Text = "МИМО",
		Size = 64,
		Colors = { Color3.fromRGB(230, 220, 240), Color3.fromRGB(255, 110, 120) },
		Tilt = 0,
		Motion = "droop",
	},
	zap = {
		Text = "ШАРАХНУЛО!",
		Size = 80,
		Colors = { Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 120, 60) },
		Tilt = 0,
		Motion = "shake",
	},
	burst = {
		Text = "БАНКА ЛОПНУЛА!",
		Size = 72,
		Colors = { Color3.fromRGB(255, 236, 230), Color3.fromRGB(244, 72, 92) },
		Tilt = 0,
		Motion = "shake",
	},
}

----------------------------------------------------------------------
-- Состояние
----------------------------------------------------------------------
local gui: ScreenGui
local topRoot: Frame
local topScale: UIScale
local topInner: Frame
local topInnerScale: UIScale
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

local catchButton: TextButton
local catchButtonScale: UIScale
local catchRingFrame: Frame
local catchRing: Frame
local comboRoot: Frame
local comboLabel: TextLabel
local comboScale: UIScale
local comboGrad: UIGradient
local lastCombo = 0

-- надпись оценки
local gradeRoot: Frame
local gradeWord: Frame
local gradeWordScale: UIScale
local gradeLabel: TextLabel
local gradeShadow: TextLabel
local gradeStroke: UIStroke
local gradeShadowStroke: UIStroke
local gradeGrad: UIGradient
local gradeSizeLimit: UITextSizeConstraint
local gradeShadowLimit: UITextSizeConstraint
local burstSquares: { Frame } = {}
local sparks: { Frame } = {}
local gradeToken = 0

local jarFill: Frame
local jarOver: Frame
local jarOverZone: Frame
local jarTick: Frame
local jarTicks: { Frame } = {}
local jarLabel: TextLabel
local jarFillGrad: UIGradient
local riskTag: Frame
local riskLabel: TextLabel
local statusLabel: TextLabel
local statusScale: UIScale
local statusPulse: Tween? = nil
-- заряд последних своих поимок на острове recentZone (для оценки следующей)
local recentCatches: { number } = {}
local recentZone = -1

local eventPill: Frame
local eventLabel: TextLabel
local eventGrad: UIGradient
local eventBadge: Frame
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

type Tile = {
	button: TextButton,
	badge: Frame,
	glow: Frame,
	glowTween: Tween?,
	scale: UIScale,
	caption: Frame,
	captionText: string,
}
local tiles: { [string]: Tile } = {}
local moreTile: Tile
local morePlus: Frame
local moreMinus: Frame

----------------------------------------------------------------------
-- Помощники
----------------------------------------------------------------------
local function loopTween(obj: Instance, time: number, props: { [string]: any }): Tween
	return UIKit.loop(obj, time, props)
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

-- Плашка Ink поверх мира (чипы и таймеры): полупрозрачная, со скруглением и обводкой
local function plate(parent: Instance, name: string, size: UDim2, order: number?): Frame
	local f = UIKit.new("Frame", {
		Name = name,
		Size = size,
		BackgroundColor3 = WHITE,
		LayoutOrder = order or 0,
		Parent = parent,
	}) :: Frame
	UIKit.corner(f, Theme.CornerSmall)
	UIKit.stroke(f, 2.5, Theme.Ink)
	return f
end

-- Примерная ширина надписи Nunito 800 ЗАГЛАВНЫМИ (для ширины тега: TextBounds до отрисовки нет)
local function tagWidth(text: string, size: number): number
	return math.ceil((utf8.len(text) or #text) * size * 0.7 + size * 0.9)
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
-- Сверху по центру: чипы Вольт и осколков, банка-батарейка, строка состояния
----------------------------------------------------------------------
local function buildJar()
	local jar = UIKit.new("Frame", {
		Name = "Jar",
		Size = UDim2.fromOffset(JAR_W, JAR_H),
		Position = UDim2.fromOffset(14, JAR_Y),
		BackgroundColor3 = Theme.Well,
		BackgroundTransparency = 0.05,
		Parent = topInner,
	}) :: Frame
	UIKit.corner(jar, 6)
	UIKit.stroke(jar, 2.5, Theme.Ink)
	-- жёсткая тень и «клемма» батарейки справа
	local jarShadow = UIKit.new("Frame", {
		Name = "JarShadow",
		Size = jar.Size,
		Position = jar.Position + UDim2.fromOffset(0, 4),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.35,
		ZIndex = 0,
		Parent = topInner,
	})
	UIKit.corner(jarShadow, 6)
	local term = UIKit.new("Frame", {
		Name = "Terminal",
		Size = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 2, 0.5, 0),
		BackgroundColor3 = Theme.Ink,
		Parent = jar,
	})
	UIKit.corner(term, 2)

	-- зона перегрузки (100–150%): диагональные полосы опасности (повёрнутые бруски в обрезающей рамке)
	jarOverZone = UIKit.new("Frame", {
		Name = "OverZone",
		Size = UDim2.fromScale(1 / 3, 1),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		BackgroundColor3 = Theme.DangerLo,
		BackgroundTransparency = 0.35,
		ClipsDescendants = true,
		Visible = false,
		Parent = jar,
	}) :: Frame
	UIKit.corner(jarOverZone, 6)
	local zoneW = math.ceil(JAR_W / 3)
	local n = math.ceil((zoneW + JAR_H) / HAZARD_STEP) + 1
	for i = 0, n - 1 do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			Size = UDim2.fromOffset(math.floor(HAZARD_STEP * 0.5), math.floor(JAR_H * 1.8)),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, i * HAZARD_STEP - math.floor(JAR_H / 2), 0.5, 0),
			Rotation = 40,
			BackgroundColor3 = Theme.Danger,
			BackgroundTransparency = 0.45,
			Parent = jarOverZone,
		})
	end

	jarFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = jar,
	}) :: Frame
	UIKit.corner(jarFill, 6)
	jarFillGrad = UIKit.gradient(jarFill, Theme.SparkHi, Theme.Spark)
	UIKit.new("Frame", {
		Name = "Gleam",
		Size = UDim2.new(1, -8, 0, 3),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		ZIndex = 2,
		Parent = jarFill,
	})
	jarOver = UIKit.new("Frame", {
		Name = "Over",
		Size = UDim2.fromScale(0, 1),
		Position = UDim2.fromScale(2 / 3, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Visible = false,
		Parent = jar,
	}) :: Frame
	UIKit.corner(jarOver, 6)
	UIKit.gradient(jarOver, Theme.DangerHi, Theme.Danger)
	-- деления каждые 25% обычной части
	for i = 1, 3 do
		local t = UIKit.new("Frame", {
			Name = "Tick" .. i,
			Size = UDim2.new(0, 2, 1, -8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(i / 4, 0.5),
			BackgroundColor3 = Theme.Ink,
			BackgroundTransparency = 0.5,
			ZIndex = 3,
			Parent = jar,
		}) :: Frame
		table.insert(jarTicks, t)
	end
	jarTick = UIKit.new("Frame", {
		Name = "Full",
		Size = UDim2.new(0, 4, 1, 6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(2 / 3, 0.5),
		BackgroundColor3 = Theme.Cream,
		ZIndex = 4,
		Visible = false,
		Parent = jar,
	}) :: Frame
	UIKit.stroke(jarTick, 1.5, Theme.Ink)
	jarLabel = UIKit.label({
		Name = "Label",
		Text = "БАНКА 0/25",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -20, 1, -6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 21,
		NoStroke = false,
		ZIndex = 5,
		Parent = jar,
	})
	-- тег риска над правым краем банки
	riskTag, riskLabel = UIKit.tag({
		Name = "Risk",
		Size = UDim2.fromOffset(118, 24),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 6, 0, -2),
		Rotation = -4,
		ZIndex = 6,
		Visible = false,
		Parent = jar,
	}, "Риск 0%", 15, Theme.Danger)
	riskLabel.TextColor3 = Theme.Cream
end

local function buildTop()
	topRoot = UIKit.new("Frame", {
		Name = "Top",
		Size = UDim2.fromOffset(TOP_W, TOP_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	topScale = UIKit.autoScale(topRoot, "hud", 1280, 720)
	-- внутренний масштаб: на телефоне чипы и банка крупнее, если между меню и правым блоком есть место
	topInner = UIKit.new("Frame", {
		Name = "Inner",
		Size = UDim2.fromOffset(TOP_W, TOP_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundTransparency = 1,
		Parent = topRoot,
	}) :: Frame
	topInnerScale = UIKit.new("UIScale", { Scale = 1, Parent = topInner }) :: UIScale

	local row = UIKit.new("Frame", {
		Name = "Currency",
		Size = UDim2.fromOffset(TOP_W, CHIP_H + 4),
		BackgroundTransparency = 1,
		Parent = topInner,
	}) :: Frame
	UIKit.list(row, Enum.FillDirection.Horizontal, 22)
	local vChip = UIKit.chip(row, "Volts", 238, CHIP_H, "⚡", Theme.Volt, 1)
	voltsPill = vChip.Frame
	volts = newCounter(vChip.Value, vChip.Scale)
	local sChip = UIKit.chip(row, "Shards", 160, CHIP_H, "💎", Theme.Shard, 2)
	shards = newCounter(sChip.Value, sChip.Scale)

	buildJar()

	statusLabel = UIKit.label({
		Name = "Status",
		Text = "",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.fromOffset(TOP_W, STATUS_H),
		Position = UDim2.fromOffset(0, JAR_Y + JAR_H + 6),
		TextColor3 = Theme.Miss,
		MaxTextSize = 24,
		NoStroke = false,
		Visible = false,
		Parent = topInner,
	})
	local st = statusLabel:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 2.5
	end
	statusScale = UIKit.new("UIScale", { Scale = 1, Parent = statusLabel }) :: UIScale
end

local function setPulse(on: boolean)
	if on and not statusPulse then
		statusScale.Scale = 1
		statusPulse = loopTween(statusScale, 0.45, { Scale = 1.1 })
	elseif not on and statusPulse then
		statusPulse:Cancel()
		statusPulse = nil
		statusScale.Scale = 1
	end
end

-- Сколько заряда, скорее всего, даст следующая поимка: медиана своих последних поимок на этом острове
-- (редкая золотая не раздувает оценку), а пока их нет — голубая «ХОРОШО» при текущем комбо
local function nextCatchCharge(zone: number, d: PlayerData.Data?): number
	if zone == recentZone and #recentCatches > 0 then
		local sorted = table.clone(recentCatches)
		table.sort(sorted)
		return sorted[(#sorted + 1) // 2]
	end
	if not Config.Zones[zone] then
		return 0
	end
	return Economy.catchCharge(zone, "blue", "good", playerNumber(Net.PlayerAttrs.Combo), if d then d.Upgrades.Rod else 0)
end

-- Своя поимка: уточнить оценку следующей
local function noteCatch(msg: Net.StrikeResultMsg)
	local charge, cap, jar = msg.Charge, msg.Capacity, msg.Jar
	if msg.Grade ~= "perfect" and msg.Grade ~= "good" then
		return
	end
	if typeof(charge) ~= "number" or typeof(cap) ~= "number" or typeof(jar) ~= "number" or charge <= 0 or cap <= 0 then
		return
	end
	-- банка упёрлась в предел — заряд обрезан и не показывает, сколько дала бы поимка
	if jar >= cap * Config.Overcharge.MaxFill * (1 - 1e-6) or math.abs(jar - cap) <= cap * 1e-6 then
		return
	end
	local zone = ClientState.zone()
	if zone ~= recentZone then
		recentZone = zone
		table.clear(recentCatches)
	end
	table.insert(recentCatches, charge)
	if #recentCatches > CATCH_EST_N then
		table.remove(recentCatches, 1)
	end
end

local function setStatus(text: string, color: Color3, pulse: boolean)
	statusLabel.Visible = true
	statusLabel.Text = text
	statusLabel.TextColor3 = color
	setPulse(pulse)
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
	for i, t in jarTicks do
		t.Position = UDim2.fromScale(normalFrac * i / 4, 0.5)
	end
	local nf = math.min(fill, 1) * normalFrac
	UIKit.tween(jarFill, 0.18, { Size = UDim2.fromScale(nf, 1) })
	jarFill.Visible = nf > 0.004
	local over = math.clamp(fill - 1, 0, Config.Overcharge.MaxFill - 1) / (Config.Overcharge.MaxFill - 1)
	jarOver.Visible = overMode and over > 0.002
	UIKit.tween(jarOver, 0.18, { Size = UDim2.fromScale(over * (1 - normalFrac), 1) })

	jarLabel.Text = string.format("БАНКА  %s / %s", Format.short(math.floor(charge + 0.5)), Format.short(cap))

	-- цвет заливки: голубая → золотая (почти полна)
	local key = if fill >= 0.999 then "full" elseif fill >= 0.8 then "high" else "low"
	if key ~= lastJarKey then
		lastJarKey = key
		if key == "low" then
			jarFillGrad.Color = ColorSequence.new(Theme.SparkHi, Theme.Spark)
		else
			jarFillGrad.Color = ColorSequence.new(Theme.VoltHi, Theme.Volt)
		end
	end

	-- строка состояния: риск перегрузки или "сдай заряд" (или Тесла-дрон везёт заряд)
	local full = (fill >= 0.999 and not overAllowed) or fill >= Config.Overcharge.MaxFill - 0.001
	local droneAway = droneOn and ClientState.droneAway()
	-- риск следующей поимки: сервер бросает его по заполнению ПОСЛЕ неё (как только банка переливается за 100%)
	local risk = 0
	if overAllowed and not full then
		local ins = if d then d.Upgrades.Insulation else 0
		local nextFill = math.min(fill + nextCatchCharge(zone, d) / math.max(1, cap), Config.Overcharge.MaxFill)
		risk = Strikes.overchargeRisk(math.max(nextFill, if fill >= 0.999 then 1.0001 else 0), ins)
	end
	local riskPct = math.max(1, math.floor(risk * 100 + 0.5))
	riskTag.Visible = risk > 0 or (fill > 1.001 and not full)
	riskLabel.Text = string.format("РИСК ~%d%%", riskPct)
	if full and zone ~= 0 then
		setStatus(if droneAway then "Банка полна — дрон скоро вернётся" else "Банка полна — сдай заряд!", Theme.Volt, not droneAway)
	elseif full then
		setStatus("Сдай заряд у Тесла-башни!", Theme.Volt, true)
	elseif fill > 1.001 then
		setStatus(string.format("Перегрузка! Банка может лопнуть: ~%d%%", riskPct), Theme.DangerHi, false)
	elseif overAllowed and fill >= 0.999 then
		-- ровно полна: можно сдать или рискнуть
		setStatus(string.format("Банка полна! Дальше риск ~%d%%", riskPct), Theme.Volt, true)
	elseif risk > 0 then
		-- следующая поимка, скорее всего, перельётся за 100%
		setStatus(string.format("Почти полна: риск лопнуть ~%d%%", riskPct), Theme.Orange, false)
	elseif droneAway then
		setStatus("Дрон везёт заряд", Theme.Spark, false)
	else
		statusLabel.Visible = false
		setPulse(false)
	end
end

----------------------------------------------------------------------
-- Справа сверху: событие, Электроград, множитель, буст ×2
----------------------------------------------------------------------
local function smallChip(parent: Instance, name: string, w: number, h: number, order: number, font: Font): (Frame, TextLabel)
	local frame = plate(parent, name, UDim2.fromOffset(w, h), order)
	local label = UIKit.label({
		Name = "Label",
		Text = "",
		FontFace = font,
		Size = UDim2.new(1, -14, 1, -8),
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
		Size = UDim2.fromOffset(RIGHT_W, 46 + 8 + 74 + 8 + 40),
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

	-- событие: значок-иконка слева, таймер Nunito (цифры одной ширины — не дрожат)
	eventPill = plate(rightInner, "Event", UDim2.fromOffset(RIGHT_W - 8, 46), 1)
	eventGrad = UIKit.gradient(eventPill, Theme.Night800, Theme.Ink)
	eventBadge = UIKit.iconBadge(eventPill, "⚡", Theme.Supercell, 42, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -12, 0.5, 0),
		ZIndex = 2,
	})
	eventLabel = UIKit.label({
		Name = "Label",
		Text = "",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -50, 1, -12),
		Position = UDim2.new(0, 38, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 21,
		Parent = eventPill,
	})

	-- Электроград: тег-подпись и батарейка
	local city = plate(rightInner, "City", UDim2.fromOffset(RIGHT_W, 74), 2)
	UIKit.gradient(city, Theme.Night800, Theme.Ink)
	UIKit.label({
		Name = "Title",
		Text = "ЭЛЕКТРОГРАД",
		FontFace = Theme.FontBodyHeavy,
		TextColor3 = Theme.TextDim,
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 7),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 17,
		Parent = city,
	})
	cityBar = UIKit.bar({
		Name = "CityBar",
		Size = UDim2.new(1, -32, 0, 26),
		Position = UDim2.fromOffset(12, 36),
		Color = Theme.Volt,
		TextSize = 18,
		Parent = city,
	})
	cityBoost, cityBoostLabel = UIKit.tag({
		Name = "Boost",
		Size = UDim2.fromOffset(150, 26),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 4),
		Rotation = -3,
		Visible = false,
		ZIndex = 3,
		Parent = city,
	}, "×2 вольт", 16, Theme.Volt)
	cityBoostLabel.TextColor3 = Theme.Ink

	-- множитель и личный буст
	local row = UIKit.new("Frame", {
		Name = "Pills",
		Size = UDim2.fromOffset(RIGHT_W, 40),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = rightInner,
	}) :: Frame
	UIKit.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right)
	boostPill, boostLabel = smallChip(row, "Boost2x", 150, 40, 1, Theme.FontBodyHeavy)
	UIKit.gradient(boostPill, Theme.OrangeHi:Lerp(Theme.Orange, 0.4), Theme.OrangeLo)
	local bs = boostLabel:FindFirstChildOfClass("UIStroke") or UIKit.textStroke(boostLabel, 2)
	bs.Thickness = 2
	multPill, multLabel = smallChip(row, "Multiplier", 118, 40, 2, Theme.FontNumber)
	UIKit.gradient(multPill, Theme.Night800, Theme.Ink)
	UIKit.gradientText(multLabel, Theme.VoltHi, Theme.Volt)
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
			eventLabel.Text = UIKit.upper(info.Now) .. "  " .. Format.time(ends - now)
		else
			eventLabel.Text = UIKit.upper(info.Now) .. "!"
		end
		key = "now:" .. tostring(ev)
		if key ~= lastEventKey then
			local t = UIKit.tones(info.Color)
			eventGrad.Color = ColorSequence.new(t.Base:Lerp(Theme.Ink, 0.15), t.Lo:Lerp(Theme.Ink, 0.45))
			UIKit.setIconBadge(eventBadge, info.Icon, info.Color)
		end
		eventPill.Visible = true
	else
		local best: number? = nil
		local bestDef = NEXT_EVENTS[1]
		for _, e in NEXT_EVENTS do
			local t = attrNumber(gs, e.Attr)
			if t and t > now and (best == nil or t < best) then
				best = t
				bestDef = e
			end
		end
		key = "next:" .. bestDef.Attr
		if key ~= lastEventKey then
			eventGrad.Color = ColorSequence.new(Theme.Night800, Theme.Ink)
			UIKit.setIconBadge(eventBadge, bestDef.Icon, bestDef.Color)
		end
		if best then
			eventLabel.Text = bestDef.Text .. Format.time(best - now)
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
		cityBar.setColor(Theme.Volt)
		cityBar.set(1, "Город сияет!")
	else
		cityBoost.Visible = false
		cityBar.setColor(Theme.Volt)
		cityBar.set(points / target, string.format("%d / %d", math.floor(points), math.floor(target)))
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
-- Меню: плитки (§8.4) — тёмная плитка с колодцем-значком цвета раздела и подписью-тегом под плиткой.
-- На ПК — два столбца по центру слева; на сенсорном экране — только верхняя треть
-- (левые 40% нижних 2/3 — зона джойстика): что не поместилось крупно, прячется в «Ещё»
----------------------------------------------------------------------
local function setGlow(tile: Tile, on: boolean)
	if on and not tile.glowTween then
		tile.glow.Visible = true
		tile.glow.BackgroundTransparency = 0.7
		tile.glowTween = loopTween(tile.glow, 0.6, { BackgroundTransparency = 0.2 })
	elseif not on and tile.glowTween then
		tile.glowTween:Cancel()
		tile.glowTween = nil
		tile.glow.Visible = false
	end
end

local function makeTile(name: string, icon: string, caption: string, color: Color3, order: number, onClick: () -> ()): Tile
	local t = UIKit.tones(color)
	local button = UIKit.new("TextButton", {
		Name = name,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Active = true,
		Parent = menuRoot,
	}) :: TextButton
	UIKit.corner(button, 16)
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = button }) :: UIScale
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		Size = UDim2.new(1, 14, 1, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Theme.Volt,
		BackgroundTransparency = 0.5,
		Visible = false,
		ZIndex = 0,
		Parent = button,
	}) :: Frame
	UIKit.corner(glow, 22)
	local shadow = UIKit.new("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 4),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.25,
		ZIndex = 1,
		Parent = button,
	})
	UIKit.corner(shadow, 16)
	local tilePlate = UIKit.new("Frame", {
		Name = "Plate",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = button,
	}) :: Frame
	UIKit.corner(tilePlate, 16)
	UIKit.stroke(tilePlate, 2.5, Theme.Ink)
	UIKit.gradient(tilePlate, Theme.Night700, Theme.Night800)
	-- колодец-значок цвета раздела
	local well = UIKit.new("Frame", {
		Name = "Well",
		Size = UDim2.fromScale(0.72, 0.72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = tilePlate,
	}) :: Frame
	UIKit.corner(well, 12)
	UIKit.stroke(well, 2, Theme.Ink)
	UIKit.gradient(well, t.Hi:Lerp(t.Base, 0.3), t.Lo)
	UIKit.new("Frame", {
		Name = "TopLine",
		Size = UDim2.new(0.7, 0, 0, 2),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.45,
		ZIndex = 1,
		Parent = well,
	})
	if string.sub(icon, 1, 1) ~= "#" then
		UIKit.label({
			Name = "Icon",
			Text = icon,
			Size = UDim2.fromScale(0.7, 0.7),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			MaxTextSize = 44,
			ZIndex = 2,
			Parent = well,
		})
	end
	-- подпись под плиткой на теге Ink (наполовину выступает за нижний край)
	local cap, capLabel = UIKit.tag({
		Name = "Caption",
		Size = UDim2.fromOffset(tagWidth(caption, 14), CAPTION_PC),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		ZIndex = 3,
		Parent = button,
	}, caption, 14)
	capLabel.ZIndex = 3
	local badge = UIKit.badge(button, "!", 28)
	badge.Size = UDim2.fromScale(0.36, 0.36)
	badge.Position = UDim2.fromScale(0.92, 0.08)

	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, 0.07, { Scale = 0.92 })
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
	return {
		button = button,
		badge = badge,
		glow = glow,
		glowTween = nil,
		scale = scale,
		caption = cap,
		captionText = UIKit.upper(caption),
	}
end

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
	morePlus.Visible = not moreOpen
	moreMinus.Visible = moreOpen
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
		tiles[m.Name] = makeTile(m.Name, m.Icon, m.Short, m.Color, i, function()
			if moreOpen then
				setMoreOpen(false)
			end
			ClientState.OpenWindow:Fire(m.Window)
		end)
	end

	-- «Ещё» — последняя плитка ряда; раскрывает блок со спрятанными кнопками прямо под собой
	local more = makeTile("MoreButton", "#plus", "Ещё", Theme.Spark, #MENU + 1, function()
		setMoreOpen(not moreOpen)
	end)
	more.button.Visible = false
	moreTile = more
	local well = more.button:FindFirstChild("Plate")
	local wellInner = well and well:FindFirstChild("Well")
	if wellInner then
		morePlus = UIKit.glyph(wellInner, "plus", { Name = "Plus", Size = UDim2.fromScale(0.55, 0.55), Stroke = 2, ZIndex = 2 })
		moreMinus = UIKit.glyph(wellInner, "minus", { Name = "Minus", Size = UDim2.fromScale(0.55, 0.55), Stroke = 2, ZIndex = 2, Visible = false })
	else
		morePlus = UIKit.glyph(more.button, "plus", { Name = "Plus", Size = UDim2.fromScale(0.4, 0.4), ZIndex = 4 })
		moreMinus = UIKit.glyph(more.button, "minus", { Name = "Minus", Size = UDim2.fromScale(0.4, 0.4), ZIndex = 4, Visible = false })
	end
	moreRoot = UIKit.new("Frame", {
		Name = "MenuMore",
		Size = UDim2.fromOffset(100, 100),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.2,
		Visible = false,
		ZIndex = 4,
		Parent = gui,
	}) :: Frame
	UIKit.corner(moreRoot, 14)
	UIKit.stroke(moreRoot, 2.5, Theme.Ink)
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
-- Кнопка ЛОВИ (§8.4): круг под большой палец с кольцом Ink, лицо VoltHi → Volt → VoltLo,
-- нарисованная молния и тег «ЛОВИ!» снизу; комбо «×12» с тегом «КОМБО» над кнопкой
----------------------------------------------------------------------
local function pressCatch()
	ClientState.CatchPressed:Fire()
	catchButtonScale.Scale = 0.88
	UIKit.tween(catchButtonScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	-- кольцо вспыхивает Spark и расходится
	catchRingFrame.BackgroundColor3 = Theme.Spark
	UIKit.tween(catchRingFrame, 0.3, { BackgroundColor3 = Theme.Ink })
	local ringScale = catchRing:FindFirstChildOfClass("UIScale")
	local stroke = catchRing:FindFirstChildOfClass("UIStroke")
	if ringScale and stroke then
		catchRing.Visible = true
		ringScale.Scale = 1
		stroke.Transparency = 0.05
		UIKit.tween(ringScale, 0.35, { Scale = 1.4 })
		UIKit.tween(stroke, 0.35, { Transparency = 1 })
	end
end

local function circle(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, z: number): Frame
	local f = UIKit.new("Frame", {
		Name = name,
		Size = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		BackgroundColor3 = color,
		ZIndex = z,
		Parent = parent,
	}) :: Frame
	UIKit.round(f)
	return f
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
		Position = UDim2.new(1, 0, 1, -10),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Active = true,
		Selectable = false,
		Parent = catchRoot,
	}) :: TextButton
	UIKit.round(catchButton)
	catchButtonScale = UIKit.new("UIScale", { Scale = 1, Parent = catchButton }) :: UIScale

	-- мягкий ореол-пульс за кнопкой
	local halo = circle(catchButton, "Halo", UDim2.fromScale(1.2, 1.2), UDim2.fromScale(0.5, 0.5), Theme.Volt, 0)
	halo.BackgroundTransparency = 0.82
	loopTween(halo, 0.9, { BackgroundTransparency = 0.6 })
	-- жёсткая тень, кольцо Ink, кромка и лицо
	local shadow = circle(catchButton, "Shadow", UDim2.fromScale(1, 1), UDim2.new(0.5, 0, 0.5, 5), Theme.Ink, 1)
	shadow.BackgroundTransparency = 0.35
	catchRingFrame = circle(catchButton, "Ring", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Theme.Ink, 1)
	local lip = circle(catchRingFrame, "Lip", UDim2.new(1, -10, 1, -10), UDim2.fromScale(0.5, 0.5), Theme.VoltLo:Lerp(Theme.Ink, 0.25), 1)
	local face = circle(lip, "Face", UDim2.new(1, 0, 1, -6), UDim2.new(0.5, 0, 0.5, -3), WHITE, 1)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Color = UIKit.seq({ { 0, Theme.VoltHi }, { 0.5, Theme.Volt }, { 1, Theme.VoltLo } }),
		Parent = face,
	})
	-- блик: тонкий светлый полумесяц сверху
	local gleam = circle(face, "Gleam", UDim2.fromScale(0.62, 0.18), UDim2.fromScale(0.5, 0.17), WHITE, 1)
	gleam.BackgroundTransparency = 0.6
	UIKit.glyph(face, "bolt", {
		Name = "Bolt",
		Size = UDim2.fromScale(0.56, 0.56),
		Position = UDim2.fromScale(0.5, 0.45),
		Color = Theme.Cream,
		Stroke = 3,
		ZIndex = 2,
	})
	-- тег «ЛОВИ!» — наполовину за нижним краем круга
	local _catchTag, tagLabel = UIKit.tag({
		Name = "Label",
		Size = UDim2.fromScale(0.74, 0.27),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.94),
		Rotation = -4,
		ZIndex = 5,
		Parent = catchButton,
	}, "ЛОВИ!", 40)
	tagLabel.FontFace = Theme.FontDisplay
	tagLabel.Size = UDim2.new(1, -8, 1, -4)
	tagLabel.ZIndex = 5
	UIKit.italicPad(tagLabel, 2)

	catchRing = UIKit.new("Frame", {
		Name = "PressRing",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 6,
		Parent = catchButton,
	}) :: Frame
	UIKit.round(catchRing)
	UIKit.stroke(catchRing, 5, Theme.Spark, 1)
	UIKit.new("UIScale", { Scale = 1, Parent = catchRing })

	-- мгновенный отклик: InputBegan, а не Activated
	catchButton.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) and input.UserInputState == Enum.UserInputState.Begin then
			pressCatch()
		end
	end)

	-- комбо: «×12» Oswald с градиентом и тег «КОМБО» под ним, наклон −4°
	comboRoot = UIKit.new("Frame", {
		Name = "Combo",
		Size = UDim2.fromOffset(170, 70),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(1, -60, 1, -132),
		BackgroundTransparency = 1,
		Rotation = -4,
		Visible = false,
		Parent = catchRoot,
	}) :: Frame
	comboScale = UIKit.new("UIScale", { Scale = 1, Parent = comboRoot }) :: UIScale
	comboLabel = UIKit.label({
		Name = "Value",
		Text = "",
		FontFace = Theme.FontNumber,
		Size = UDim2.fromScale(1, 0.74),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 72,
		NoStroke = false,
		ZIndex = 2,
		Parent = comboRoot,
	})
	local cs = comboLabel:FindFirstChildOfClass("UIStroke")
	if cs then
		cs.Thickness = 3
	end
	comboGrad = UIKit.gradientText(comboLabel, Theme.VoltHi, Theme.Volt)
	UIKit.textShadow(comboLabel, 4)
	local tag, tl = UIKit.tag({
		Name = "Tag",
		Size = UDim2.fromScale(0.56, 0.3),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1.04),
		ZIndex = 3,
		Parent = comboRoot,
	}, "Комбо", 18)
	tl.ZIndex = 3
	tag.ZIndex = 3
end

local function comboColor(c: number): Color3
	if c >= Config.Catch.ComboCap then
		return Theme.Volt
	elseif c >= 20 then
		return Theme.Orange
	elseif c >= 10 then
		return Theme.Violet
	elseif c >= 5 then
		return Theme.Spark
	end
	return Theme.Good
end

local function comboBase(c: number): number
	return 0.85 + 0.3 * math.min(c, Config.Catch.ComboCap) / Config.Catch.ComboCap
end

local function updateCombo()
	local c = math.floor(playerNumber(Net.PlayerAttrs.Combo))
	if c <= 0 then
		if comboRoot.Visible and lastCombo > 0 then
			local tw = UIKit.tween(comboScale, 0.15, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tw.Completed:Once(function()
				if math.floor(playerNumber(Net.PlayerAttrs.Combo)) <= 0 then
					comboRoot.Visible = false
				end
			end)
		end
		lastCombo = 0
		return
	end
	comboRoot.Visible = true
	comboLabel.Text = "×" .. tostring(c)
	local t = UIKit.tones(comboColor(c))
	comboGrad.Color = ColorSequence.new(t.Hi, t.Base)
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
-- Слово-оценка по центру (§8.4): градиент букв, обводка 6 Ink, жёсткая тень, наклон,
-- у ИДЕАЛЬНО — взрыв-звезда сзади и разлёт ромбов-искр. Все детали созданы заранее (без churn)
----------------------------------------------------------------------
local SPARK_DIRS = { { 1, -0.35 }, { 0.75, 0.7 }, { -0.2, 1 }, { -1, 0.35 }, { -0.75, -0.75 }, { 0.25, -1 } }

local function buildGrade()
	gradeRoot = UIKit.new("Frame", {
		Name = "Grade",
		Size = UDim2.fromOffset(780, 170),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(gradeRoot, "hud", 1280, 720)
	-- взрыв-звезда: два квадрата Volt (0° и 45°)
	for i, rot in { 0, 45 } do
		local sq = UIKit.new("Frame", {
			Name = "Burst" .. i,
			Size = UDim2.fromOffset(150, 150),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = rot,
			BackgroundColor3 = Theme.Volt,
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 1,
			Parent = gradeRoot,
		}) :: Frame
		UIKit.corner(sq, 10)
		UIKit.new("UIScale", { Scale = 1, Parent = sq })
		table.insert(burstSquares, sq)
	end
	-- искры-ромбы
	for i = 1, #SPARK_DIRS do
		local sp = UIKit.new("Frame", {
			Name = "Spark" .. i,
			Size = UDim2.fromOffset(18, 18),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = 45,
			BackgroundColor3 = Theme.VoltHi,
			Visible = false,
			ZIndex = 4,
			Parent = gradeRoot,
		}) :: Frame
		UIKit.corner(sp, 3)
		UIKit.stroke(sp, 2, Theme.Ink)
		table.insert(sparks, sp)
	end
	-- слово: тень и лицо внутри одной наклоняемой рамки
	gradeWord = UIKit.new("Frame", {
		Name = "Word",
		Size = UDim2.fromScale(1, 0.8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = gradeRoot,
	}) :: Frame
	gradeWordScale = UIKit.new("UIScale", { Scale = 1, Parent = gradeWord }) :: UIScale
	local function wordLabel(name: string, z: number, dy: number): TextLabel
		local l = UIKit.label({
			Name = name,
			Text = "",
			FontFace = Theme.FontDisplay,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.new(0, 0, 0, dy),
			TextColor3 = WHITE,
			MaxTextSize = 96,
			NoStroke = false,
			TextTransparency = 1,
			ZIndex = z,
			Parent = gradeWord,
		})
		UIKit.italicPad(l, 24)
		return l
	end
	gradeShadow = wordLabel("Shadow", 2, 8)
	gradeShadow.TextColor3 = Theme.Ink
	gradeLabel = wordLabel("Text", 3, 0)
	gradeStroke = gradeLabel:FindFirstChildOfClass("UIStroke") :: UIStroke
	gradeShadowStroke = gradeShadow:FindFirstChildOfClass("UIStroke") :: UIStroke
	for _, s in { gradeStroke, gradeShadowStroke } do
		s.Thickness = 6
		s.Transparency = 1
	end
	gradeSizeLimit = gradeLabel:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
	gradeShadowLimit = gradeShadow:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
	gradeGrad = UIKit.gradientText(gradeLabel, Theme.Cream, Theme.Volt)
end

local function fadeGrade(time: number)
	for _, l in { gradeLabel, gradeShadow } do
		UIKit.tween(l, time, { TextTransparency = 1 })
	end
	for _, s in { gradeStroke, gradeShadowStroke } do
		UIKit.tween(s, time, { Transparency = 1 })
	end
end

local function playBurst(color: Color3)
	for i, sq in burstSquares do
		local s = sq:FindFirstChildOfClass("UIScale")
		sq.Visible = true
		sq.BackgroundColor3 = color
		sq.BackgroundTransparency = 0.3
		sq.Rotation = (i - 1) * 45
		if s then
			s.Scale = 0
			UIKit.tween(s, 0.35, { Scale = 1.4 }, Enum.EasingStyle.Quad)
		end
		local tw = UIKit.tween(sq, 0.35, { BackgroundTransparency = 1, Rotation = (i - 1) * 45 + 20 })
		tw.Completed:Once(function()
			sq.Visible = false
		end)
	end
end

local function playSparks(count: number, color: Color3)
	for i, sp in sparks do
		if i > count then
			sp.Visible = false
			continue
		end
		local dir = SPARK_DIRS[i]
		local dist = 150 + (i % 3) * 40
		sp.Visible = true
		sp.BackgroundColor3 = color
		sp.BackgroundTransparency = 0
		sp.Position = UDim2.fromScale(0.5, 0.5)
		local stroke = sp:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
			UIKit.tween(stroke, 0.45, { Transparency = 1 })
		end
		local tw = UIKit.tween(sp, 0.45, {
			Position = UDim2.new(0.5, math.floor(dir[1] * dist), 0.5, math.floor(dir[2] * dist * 0.6)),
			BackgroundTransparency = 1,
			Rotation = 45 + 90,
		})
		tw.Completed:Once(function()
			sp.Visible = false
		end)
	end
end

local function showGrade(kind: string)
	local style = GRADES[kind]
	if not style then
		return
	end
	gradeToken += 1
	local token = gradeToken
	gradeLabel.Text = style.Text
	gradeShadow.Text = style.Text
	gradeSizeLimit.MaxTextSize = style.Size
	gradeShadowLimit.MaxTextSize = style.Size
	local c = style.Colors
	if #c >= 3 then
		gradeGrad.Color = UIKit.seq({ { 0, c[1] }, { 0.5, c[2] }, { 1, c[3] } })
	else
		gradeGrad.Color = ColorSequence.new(c[1], c[2])
	end
	for _, l in { gradeLabel, gradeShadow } do
		l.TextTransparency = 0
	end
	gradeShadow.Position = UDim2.new(0, 0, 0, math.floor(style.Size * 0.08))
	for _, s in { gradeStroke, gradeShadowStroke } do
		s.Transparency = 0
	end
	gradeWord.Position = UDim2.fromScale(0.5, 0.5)
	gradeWord.Rotation = style.Tilt
	-- пружина 0.4 → 1.15 → 1.0
	gradeWordScale.Scale = 0.4
	local up = UIKit.tween(gradeWordScale, 0.16, { Scale = 1.15 }, Enum.EasingStyle.Quad)
	up.Completed:Once(function()
		if token == gradeToken then
			UIKit.tween(gradeWordScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)
	if style.Motion == "burst" then
		playBurst(Theme.Volt)
		playSparks(#SPARK_DIRS, Theme.VoltHi)
	elseif style.Motion == "spark" then
		playSparks(1, Theme.Spark)
	elseif style.Motion == "droop" then
		-- «сникает»: опускается, уменьшается, клонится
		task.delay(0.2, function()
			if token == gradeToken then
				UIKit.tween(gradeWord, 0.5, { Position = UDim2.new(0.5, 0, 0.5, 20), Rotation = 8 }, Enum.EasingStyle.Quad)
				UIKit.tween(gradeWordScale, 0.5, { Scale = 0.9 })
			end
		end)
	elseif style.Motion == "shake" then
		-- тряска ±4° за 0.3 с: короткая цепочка твинов
		local steps = { 4, -4, 3, -2, 0 }
		local function step(i: number)
			if token ~= gradeToken or i > #steps then
				return
			end
			local tw = UIKit.tween(gradeWord, 0.06, { Rotation = steps[i] }, Enum.EasingStyle.Sine)
			tw.Completed:Once(function()
				step(i + 1)
			end)
		end
		step(1)
	end
	task.delay(0.7, function()
		if token ~= gradeToken then
			return
		end
		fadeGrade(0.3)
		UIKit.tween(gradeWordScale, 0.3, { Scale = 1.06 })
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

-- Подписи-теги под плитками: высота capH (точки макета), шрифт ≈ 0.64 высоты, ширина — по тексту
local function sizeCaptions(capH: number, maxW: number)
	local font = math.floor(capH * 0.64)
	for _, t in tiles do
		t.caption.Size = UDim2.fromOffset(math.min(maxW, tagWidth(t.captionText, font)), capH)
		local l = t.caption:FindFirstChild("Text")
		local c = l and l:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			c.MaxTextSize = font
		end
	end
	if moreTile then
		moreTile.caption.Size = UDim2.fromOffset(math.min(maxW, tagWidth(moreTile.captionText, font)), capH)
		local l = moreTile.caption:FindFirstChild("Text")
		local c = l and l:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			c.MaxTextSize = font
		end
	end
end

-- Внутренний масштаб верхнего блока: корень растёт вместе с ним (под ним тосты и подсказки обучения)
local function setTopScale(k: number)
	topInnerScale.Scale = k
	topRoot.Size = UDim2.fromOffset(math.floor(TOP_W * k), math.floor(TOP_H * k))
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
	local comboH = math.floor((if phone then 50 else 64) / sCatch)
	local tagBelow = math.floor(btn * 0.1)
	local rootW = math.floor(btn * 1.8)
	catchButton.Size = UDim2.fromOffset(btn, btn)
	catchButton.Position = UDim2.new(1, 0, 1, -tagBelow)
	catchRoot.Size = UDim2.fromOffset(rootW, btn + comboH + tagBelow + math.floor(10 / sCatch))
	local rightMargin = if phone then 110 elseif touch then 190 else 24
	if phone then
		catchRoot.Position = UDim2.new(1, -110, 1, -24)
	elseif touch then
		catchRoot.Position = UDim2.new(1, -190, 1, -34)
	else
		catchRoot.Position = UDim2.new(1, -24, 1, -18)
	end
	-- комбо по центру над кнопкой (кнопка прижата к правому краю корня), не шире, чем до края экрана
	local spare = math.min(math.floor(btn * 0.4), math.floor((rightMargin - 6) / sCatch))
	comboRoot.Size = UDim2.fromOffset(btn + 2 * spare, comboH)
	comboRoot.Position = UDim2.new(1, -math.floor(btn / 2), 1, -(btn + tagBelow + math.floor(8 / sCatch)))

	-- правый блок: на телефоне крупнее; на портретном экране уходит под верхний блок
	local portrait = vp.X < vp.Y
	rightInnerScale.Scale = if phone then 1.22 else 1
	if portrait then
		rightRoot.Position = UDim2.new(1, -8, 0, math.floor((TOP_H + 30) * baseScale(topScale)))
	else
		rightRoot.Position = UDim2.new(1, -8, 0, 6)
	end

	-- меню: на сенсорных экранах — ряд(ы) сразу под верхней панелью и только в верхней трети экрана
	-- (левые 40% нижних 2/3 — зона джойстика); что не помещается крупно — в «Ещё». На ПК — два столбца слева
	if touch then
		local guiW = if gui.AbsoluteSize.X > 0 then gui.AbsoluteSize.X else vp.X
		local top = 6
		local gapReal = if phone then 8 else 10
		local maxTile = if phone then 64 else 80
		local topW = TOP_W * baseScale(topScale)
		local rightW = if portrait then 0 else RIGHT_W * baseScale(topScale) * rightInnerScale.Scale + 8
		-- ширина: левее верхнего блока (по центру или, если тесно, сдвинутого вплотную к правому блоку)
		local availW = math.max((guiW - topW) / 2 - 20, guiW - rightW - topW - 30)
		-- подписи под плитками — только если с ними плитки не мельче MENU_MIN_TILE (на низком экране без подписей)
		local capReal = if phone then CAPTION_TOUCH else CAPTION_TOUCH + 4
		local stripH = vp.Y / 3 - inset - top
		local captions = stripH - math.ceil(capReal / 2) >= MENU_MIN_TILE
		local overhang = if captions then math.ceil(capReal / 2) else 0
		local availH = stripH - overhang
		local gapY = gapReal + overhang
		local shown = #MENU
		local cols, rows, tile = fitMenu(#MENU, availW, availH + overhang, gapY, maxTile)
		tile = math.min(tile, availH)
		if tile < MENU_MIN_TILE then
			-- все не помещаются: последние кнопки уходят в «Ещё» (оно само — ещё одна плитка)
			for n = #MENU - 1, 1, -1 do
				shown = n
				cols, rows, tile = fitMenu(n + 1, availW, availH + overhang, gapY, maxTile)
				tile = math.min(tile, availH)
				if tile >= MENU_MIN_TILE then
					break
				end
			end
		end
		tile = math.max(1, math.floor(tile))
		applyMenuSplit(shown)
		local gap = math.floor(gapReal / sMenu)
		local gapYl = math.floor(gapY / sMenu)
		local t = math.floor(tile / sMenu)
		local capH = if captions then math.floor(capReal / sMenu) else 0
		for _, tl in tiles do
			tl.caption.Visible = captions
		end
		moreTile.caption.Visible = captions
		if captions then
			sizeCaptions(capH, t + gap - 2)
		end
		menuGrid.CellSize = UDim2.fromOffset(t, t)
		menuGrid.CellPadding = UDim2.fromOffset(gap, gapYl)
		menuRoot.Size = UDim2.fromOffset(cols * t + (cols - 1) * gap, rows * t + (rows - 1) * gapYl + math.ceil(capH / 2))
		menuRoot.AnchorPoint = Vector2.new(0, 0)
		menuRoot.Position = UDim2.new(0, 10, 0, top)
		-- блок «Ещё» — строкой справа от своей плитки, в её ряду (не столбцом вниз: левые 40% ниже
		-- верхней трети — зона джойстика); не влезает по ширине — в несколько рядов, но, пока блок
		-- левее 40% ширины, не ниже верхней трети
		local hidden = #MENU - shown
		if hidden > 0 then
			local pad = morePad * sMenu
			local x = 10 + (shown % cols + 1) * (tile + gapReal)
			local y = top + (shown // cols) * (tile + gapY) - pad
			local fitCols = math.max(1, math.floor((guiW - 6 - x - 2 * pad + gapReal) / (tile + gapReal)))
			local mCols = math.min(hidden, fitCols)
			local mRows = math.ceil(hidden / mCols)
			local w = mCols * t + (mCols - 1) * gap + 2 * morePad
			local h = mRows * t + (mRows - 1) * gapYl + 2 * morePad + math.ceil(capH / 2)
			local mx = math.max(4, math.min(x, guiW - w * sMenu - 6))
			if mx < guiW * 0.4 then
				y = math.min(y, vp.Y / 3 - inset - h * sMenu)
			end
			moreGrid.CellSize = UDim2.fromOffset(t, t)
			moreGrid.CellPadding = UDim2.fromOffset(gap, gapYl)
			moreRoot.Size = UDim2.fromOffset(w, h)
			moreRoot.Position = UDim2.fromOffset(math.floor(mx), math.floor(math.max(0, y)))
		end
		-- верхний блок: на телефоне крупнее, сколько позволяет место между меню и правым блоком;
		-- узкий экран — сдвигается правее меню, чтобы не наезжать на кнопки
		local menuRight = 10 + cols * tile + (cols - 1) * gapReal + 10
		local room = guiW - rightW - 8 - menuRight
		local k = if phone and not portrait then math.clamp(room / topW, 1, 1.18) else 1
		setTopScale(k)
		local w = topW * k
		if guiW / 2 - w / 2 < menuRight then
			topRoot.AnchorPoint = Vector2.new(0, 0)
			topRoot.Position = UDim2.new(0, menuRight, 0, 6)
		else
			topRoot.AnchorPoint = Vector2.new(0.5, 0)
			topRoot.Position = UDim2.new(0.5, 0, 0, 6)
		end
	else
		applyMenuSplit(#MENU)
		setTopScale(1)
		for _, tl in tiles do
			tl.caption.Visible = true
		end
		moreTile.caption.Visible = true
		topRoot.AnchorPoint = Vector2.new(0.5, 0)
		topRoot.Position = UDim2.new(0.5, 0, 0, 6)
		local t = 84
		local gapY = MENU_GAP + math.ceil(CAPTION_PC / 2)
		sizeCaptions(CAPTION_PC, t + 12)
		menuGrid.CellSize = UDim2.fromOffset(t, t)
		menuGrid.CellPadding = UDim2.fromOffset(MENU_GAP + 6, gapY)
		menuRoot.Size = UDim2.fromOffset(2 * t + MENU_GAP + 6, 4 * t + 3 * gapY + math.ceil(CAPTION_PC / 2))
		menuRoot.AnchorPoint = Vector2.new(0, 0.5)
		menuRoot.Position = UDim2.new(0, 16, 0.5, 0)
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
		-- прогноз CatchController: zap — стоял в кольце и не нажал
		if grade == "perfect" or grade == "good" or grade == "miss" or grade == "zap" then
			showGrade(grade)
		end
	end)
	ClientState.StrikeResolved:Connect(function(msg: Net.StrikeResultMsg)
		noteCatch(msg)
		updateJar()
		if msg.Grade == "zap" then
			-- уже показано прогнозом клиента — ответ сервера только подтверждает
			if ClientState.predictedGrade(msg.Id, msg.Hit) ~= "zap" then
				showGrade("zap")
			end
		elseif msg.Grade == "burst" then
			showGrade("burst")
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
