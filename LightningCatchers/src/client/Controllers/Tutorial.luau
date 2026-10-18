--!strict
-- Обучение без стен текста: одна короткая подсказка за раз (не больше 6 слов), луч-стрелка в мире к цели
-- и пульсирующая кнопка интерфейса. Ничего не блокирует: все элементы не перехватывают касания.
-- Шаги (флаги data.Tutorial): catch -> sell -> shop -> zone2, а overcharge — когда впервые можно перегрузить банку.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Zones = require(Shared:WaitForChild("Zones"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local StrikeController = require(script.Parent.StrikeController)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = require(script.Parent.Parent.UI.Theme)

local Tutorial = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Константы
----------------------------------------------------------------------
local EVAL_EVERY = 0.2
local HINT_W, HINT_H = 600, 66
local TOP_OFFSET = 168 -- под верхней панелью HUD (точки макета 1280×720)
local GRADE_PAUSE = 1.1 -- пока видна надпись оценки, подсказку прячем
local OVERCHARGE_SHOW = 6
local GATE_REACHED = 14 -- подошёл к барьеру — шаг «новый остров» выполнен
local BEAM_MIN = 4 -- ближе луч не нужен
local PULSE_COLOR = Theme.Volt

local TEXT = {
	ring = "Встань в светящийся круг",
	tapTouch = "Жми ⚡, когда кольцо сомкнётся",
	tapKeys = "Жми E, когда кольцо сомкнётся",
	sell = "Сдай заряд на подстанции",
	shop = "Купи улучшение",
	zone2 = "Открой новый остров!",
	overcharge = "Можно рискнуть: перегрузи банку!",
}

type Hint = { text: string, target: Vector3?, button: string? }

----------------------------------------------------------------------
-- Состояние
----------------------------------------------------------------------
local localDone: { [string]: boolean } = {}
local openWindows: { [string]: boolean } = {}
local gradeHideUntil = 0
local overchargeUntil = 0
local current: Hint? = nil

local gui: ScreenGui? = nil
local panel: Frame? = nil
local panelScale: UIScale? = nil
local panelStroke: UIStroke? = nil
local hintLabel: TextLabel? = nil
local hintArrow: TextLabel? = nil

local folder = Instance.new("Folder")
folder.Name = "TutorialFX"
folder.Parent = Workspace

local targetPart: Part? = nil
local targetGui: BillboardGui? = nil
local targetArrow: TextLabel? = nil
local beam: Beam? = nil
local rootAtt: Attachment? = nil

local pulseButton: GuiObject? = nil
local pulseFrame: Frame? = nil
local pulseStroke: UIStroke? = nil
local pulseArrow: TextLabel? = nil

----------------------------------------------------------------------
-- Помощники
----------------------------------------------------------------------
local function localRoot(): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function jarFill(): number
	local v = player:GetAttribute(Net.PlayerAttrs.JarFill)
	return if typeof(v) == "number" then v else 0
end

local function anyWindowOpen(): boolean
	return next(openWindows) ~= nil
end

local function marker(name: string): BasePart?
	local map = Workspace:FindFirstChild("Map")
	local mk = map and map:FindFirstChild("Markers")
	local p = mk and mk:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

-- Ближайшая подстанция: метки SellPad_N, иначе геометрия Zones
local function nearestStation(pos: Vector3): Vector3?
	local best: Vector3? = nil
	local bestD = math.huge
	local map = Workspace:FindFirstChild("Map")
	local mk = map and map:FindFirstChild("Markers")
	if mk then
		for _, m in mk:GetChildren() do
			if m:IsA("BasePart") and string.sub(m.Name, 1, 8) == "SellPad_" then
				local d = (m.Position - pos).Magnitude
				if d < bestD then
					bestD = d
					best = m.Position
				end
			end
		end
	end
	if best then
		return best
	end
	local zone = ClientState.zone()
	if zone >= 1 and zone <= #Zones.Geo then
		return Zones.Geo[zone].SellPad
	end
	return Zones.HubCenter
end

local function gatePos(zone: number): Vector3?
	local m = marker("Gate_" .. zone)
	if m then
		return m.Position
	end
	local g = Zones.Geo[zone]
	return if g then g.Gate else nil
end

-- Кнопка интерфейса по имени (HUD создаёт их сам; ищем один раз и проверяем)
local buttonCache: { [string]: GuiObject } = {}
local function findButton(name: string): GuiObject?
	local cached = buttonCache[name]
	if cached and cached.Parent and cached:IsDescendantOf(player) then
		return cached
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local found = pg:FindFirstChild(name, true)
	if found and found:IsA("GuiObject") then
		buttonCache[name] = found
		return found
	end
	return nil
end

----------------------------------------------------------------------
-- Выполнение шагов
----------------------------------------------------------------------
local function upgradesBought(d: any): boolean
	for _, lvl in d.Upgrades do
		if typeof(lvl) == "number" and lvl > 0 then
			return true
		end
	end
	return false
end

local function isDone(step: string): boolean
	if localDone[step] then
		return true
	end
	local d = ClientState.data
	if not d then
		return true -- без данных ничего не подсказываем
	end
	if d.Tutorial[step] then
		return true
	end
	-- опытные игроки (данные без флагов) — по статистике
	if step == "catch" then
		return d.Stats.Catches > 0
	elseif step == "sell" then
		return d.Stats.Sells > 0
	elseif step == "shop" then
		return upgradesBought(d)
	elseif step == "zone2" then
		return d.Zone >= 2
	end
	return false
end

local requestFn: RemoteFunction? = nil

local function complete(step: string)
	if localDone[step] then
		return
	end
	localDone[step] = true
	task.spawn(function()
		local fn = requestFn
		if not fn then
			return
		end
		-- тихо: подсказки не должны показывать ошибки
		pcall(function()
			fn:InvokeServer(Net.Actions.TutorialStep, step)
		end)
	end)
end

----------------------------------------------------------------------
-- Выбор подсказки
----------------------------------------------------------------------
local function cheapestUpgrade(d: any): number
	local best = math.huge
	for _, id in Config.UpgradeOrder do
		local cost = Economy.upgradeCost(id, d.Upgrades[id] or 0)
		if cost and cost < best then
			best = cost
		end
	end
	return best
end

local function evaluate(clock: number): Hint?
	local d = ClientState.data
	local root = localRoot()
	if not d or not root then
		return nil
	end
	local zone = ClientState.zone()
	local rootPos = root.Position

	-- 1. поймать молнию
	if not isDone("catch") then
		if zone < 1 then
			return nil
		end
		local best = nil
		local bestD = math.huge
		for _, s in StrikeController.activeStrikes() do
			local dist = Zones.flatDist(rootPos, s.Center)
			if dist < bestD then
				bestD = dist
				best = s
			end
		end
		if not best then
			return nil
		end
		if bestD <= best.Radius then
			return { text = if UIKit.isTouch() then TEXT.tapTouch else TEXT.tapKeys, target = nil, button = "CatchButton" }
		end
		return { text = TEXT.ring, target = best.Center, button = nil }
	end

	-- 2. сдать банку
	if not isDone("sell") then
		if jarFill() >= 0.999 then
			return { text = TEXT.sell, target = nearestStation(rootPos), button = nil }
		end
		return nil
	end

	-- 5. перегрузка (впервые банка полна там, где можно рисковать)
	if not isDone("overcharge") and zone >= 1 and zone <= #Config.Zones and Config.Zones[zone].Overcharge and jarFill() >= 1 then
		overchargeUntil = clock + OVERCHARGE_SHOW
		complete("overcharge")
	end
	if clock < overchargeUntil then
		return { text = TEXT.overcharge, target = nil, button = nil }
	end

	-- 3. купить улучшение
	if not isDone("shop") then
		if d.Volts >= cheapestUpgrade(d) then
			return { text = TEXT.shop, target = nil, button = "ShopButton" }
		end
	end

	-- 4. открыть второй остров
	if not isDone("zone2") and d.Zone == 1 and d.Volts >= Config.Zones[2].Cost then
		local gate = gatePos(2)
		if gate and (gate - rootPos).Magnitude <= GATE_REACHED then
			complete("zone2")
			return nil
		end
		return { text = TEXT.zone2, target = gate, button = nil }
	end
	return nil
end

----------------------------------------------------------------------
-- Отрисовка: панель подсказки
----------------------------------------------------------------------
local function ensureGui(): boolean
	local g = gui
	if g and g.Parent then
		return true
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return false
	end
	local ng = UIKit.new("ScreenGui", {
		Name = "TutorialHint",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = pg,
	}) :: ScreenGui
	local p = UIKit.panel({
		Name = "Hint",
		Size = UDim2.fromOffset(HINT_W, HINT_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP_OFFSET),
		BackgroundTransparency = 0.12,
		Active = false, -- не перехватывает касания
		Visible = false,
		Parent = ng,
	})
	local s = UIKit.autoScale(p, "hud", 1280, 720)
	-- место под верхней панелью HUD зависит от масштаба экрана (не от анимации появления)
	local function place()
		local base = s:GetAttribute("BaseScale")
		local k = if typeof(base) == "number" then base else s.Scale
		p.Position = UDim2.new(0.5, 0, 0, math.floor(TOP_OFFSET * k))
	end
	s:GetAttributeChangedSignal("BaseScale"):Connect(place)
	place()
	local arrow = UIKit.label({
		Name = "Arrow",
		Text = "👉",
		Size = UDim2.fromOffset(52, 52),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		MaxTextSize = 44,
		NoStroke = true,
		Parent = p,
	})
	local label = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -84, 1, -14),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 70, 0.5, 0),
		MaxTextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = p,
	})
	gui = ng
	panel = p
	panelScale = s
	panelStroke = p:FindFirstChildOfClass("UIStroke")
	hintLabel = label
	hintArrow = arrow
	return true
end

----------------------------------------------------------------------
-- Отрисовка: луч в мире и стрелка над целью
----------------------------------------------------------------------
local function ensureWorldArrow(): boolean
	local tp = targetPart
	if tp and tp.Parent then
		return true
	end
	local p = Instance.new("Part")
	p.Name = "TutorialTarget"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.new(0, 1e4, 0)
	p.Parent = folder
	local att = Instance.new("Attachment")
	att.Name = "Target"
	att.Parent = p
	local b = Instance.new("Beam")
	b.Name = "Guide"
	b.Attachment1 = att
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Segments = 1
	b.Width0 = 1.1
	b.Width1 = 0.5
	b.Color = ColorSequence.new(PULSE_COLOR, Color3.new(1, 1, 1))
	b.Transparency = NumberSequence.new(0.3)
	b.Enabled = false
	b.Parent = p
	local bg = Instance.new("BillboardGui")
	bg.Name = "Arrow"
	bg.Size = UDim2.fromScale(3, 3)
	bg.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	bg.AlwaysOnTop = true
	bg.LightInfluence = 0
	bg.MaxDistance = 600
	bg.ResetOnSpawn = false
	bg.Enabled = false
	bg.Parent = p
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Text = "▼"
	glyph.TextScaled = true
	glyph.FontFace = Theme.Font
	glyph.TextColor3 = PULSE_COLOR
	glyph.Parent = bg
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Theme.TextStroke
	stroke.Parent = glyph
	targetPart = p
	targetGui = bg
	targetArrow = glyph
	beam = b
	return true
end

local function ensureRootAttachment(): Attachment?
	local root = localRoot()
	if not root then
		return nil
	end
	local a = rootAtt
	if a and a.Parent == root then
		return a
	end
	if a then
		a:Destroy()
	end
	local na = Instance.new("Attachment")
	na.Name = "TutorialFrom"
	na.Position = Vector3.new(0, -1.6, 0)
	na.Parent = root
	rootAtt = na
	return na
end

local function hideWorldArrow()
	local b = beam
	if b then
		b.Enabled = false
	end
	local g = targetGui
	if g then
		g.Enabled = false
	end
end

----------------------------------------------------------------------
-- Отрисовка: пульс кнопки интерфейса
----------------------------------------------------------------------
local function clearPulse()
	local f = pulseFrame
	if f then
		f:Destroy()
	end
	pulseFrame = nil
	pulseStroke = nil
	pulseArrow = nil
	pulseButton = nil
end

local function setPulse(button: GuiObject?)
	if button == pulseButton and (button == nil or (pulseFrame and pulseFrame.Parent)) then
		return
	end
	clearPulse()
	if not button then
		return
	end
	local f = UIKit.new("Frame", {
		Name = "TutorialPulse",
		Size = UDim2.new(1, 18, 1, 18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = 40,
		Parent = button,
	}) :: Frame
	local corner = button:FindFirstChildOfClass("UICorner")
	UIKit.new("UICorner", { CornerRadius = if corner then corner.CornerRadius else UDim.new(0, Theme.Corner), Parent = f })
	local stroke = UIKit.new("UIStroke", {
		Thickness = 4,
		Color = PULSE_COLOR,
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = f,
	}) :: UIStroke
	-- стрелка над кнопкой
	local arrow = UIKit.label({
		Name = "Arrow",
		Text = "▼",
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		TextColor3 = PULSE_COLOR,
		MaxTextSize = 40,
		ZIndex = 41,
		Parent = f,
	})
	pulseButton = button
	pulseFrame = f
	pulseStroke = stroke
	pulseArrow = arrow
end

----------------------------------------------------------------------
-- Показ подсказки
----------------------------------------------------------------------
local function show(h: Hint?, clock: number)
	local hidden = h == nil or anyWindowOpen()
	local p = panel
	local label = hintLabel
	-- панель с текстом
	if not hidden and h and ensureGui() then
		p = panel
		label = hintLabel
		if p and label then
			local textChanged = current == nil or current.text ~= h.text
			label.Text = h.text
			local showPanel = clock >= gradeHideUntil
			if showPanel and (textChanged or not p.Visible) then
				local s = panelScale
				if s then
					UIKit.popIn(p, s)
				else
					p.Visible = true
				end
			elseif not showPanel then
				p.Visible = false
			end
		end
	elseif p then
		p.Visible = false
	end

	-- луч к цели
	local target = if hidden or not h then nil else h.target
	local root = localRoot()
	if target and root and (target - root.Position).Magnitude > BEAM_MIN and ensureWorldArrow() then
		local tp = targetPart
		local b = beam
		local g = targetGui
		local from = ensureRootAttachment()
		if tp and b and g and from then
			tp.CFrame = CFrame.new(target + Vector3.new(0, 1.2, 0))
			b.Attachment0 = from
			b.Enabled = true
			g.Enabled = true
		end
	else
		hideWorldArrow()
	end

	-- пульс кнопки
	local buttonName = if hidden or not h then nil else h.button
	setPulse(if buttonName then findButton(buttonName) else nil)
	current = if hidden then nil else h
end

local function animate(clock: number)
	local wave = 0.5 + 0.5 * math.sin(clock * 6)
	local p = panel
	if p and p.Visible then
		local stroke = panelStroke
		if stroke then
			stroke.Color = Theme.Stroke:Lerp(PULSE_COLOR, wave)
		end
		local arrow = hintArrow
		if arrow then
			arrow.Position = UDim2.new(0, 10 + 6 * wave, 0.5, 0)
		end
	end
	local b = beam
	if b and b.Enabled then
		b.Transparency = NumberSequence.new(0.15 + 0.35 * wave)
		local g = targetGui
		if g then
			g.StudsOffsetWorldSpace = Vector3.new(0, 3.5 + 1.2 * wave, 0)
		end
		local glyph = targetArrow
		if glyph then
			glyph.TextTransparency = 0.25 * (1 - wave)
		end
	end
	local ps = pulseStroke
	if ps then
		ps.Thickness = 3 + 4 * wave
		ps.Transparency = 0.45 * (1 - wave)
		local pa = pulseArrow
		if pa then
			pa.Position = UDim2.new(0.5, 0, 0, -4 - 8 * wave)
		end
	end
end

----------------------------------------------------------------------
-- Запуск
----------------------------------------------------------------------
local started = false
function Tutorial.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		requestFn = Net.func("Request")
	end)

	ClientState.StrikeResolved:Connect(function(msg: Net.StrikeResultMsg)
		local g = (msg :: any).Grade
		if g == "perfect" or g == "good" or g == "burst" then
			complete("catch")
		end
		if g == "zap" or g == "burst" then
			gradeHideUntil = os.clock() + GRADE_PAUSE
		end
	end)
	ClientState.LocalGrade:Connect(function()
		gradeHideUntil = os.clock() + GRADE_PAUSE
	end)
	ClientState.Effect:Connect(function(msg: Net.EffectMsg)
		local m = msg :: any
		if (m.Kind == "sell" or m.Kind == "drone") and (m.UserId == nil or m.UserId == player.UserId) then
			if m.Kind == "sell" or m.Text == "sold" then
				complete("sell")
			end
		end
	end)
	ClientState.WindowOpened:Connect(function(name: string)
		openWindows[name] = true
		if name == "Shop" then
			complete("shop")
		end
	end)
	ClientState.WindowClosed:Connect(function(name: string)
		openWindows[name] = nil
	end)
	ClientState.Changed:Connect(function(d)
		if d.Zone >= 2 then
			localDone.zone2 = true
		end
	end)

	local acc = EVAL_EVERY
	RunService.Heartbeat:Connect(function(dt: number)
		local clock = os.clock()
		acc += dt
		if acc >= EVAL_EVERY then
			acc = 0
			local ok, err = pcall(function()
				show(evaluate(clock), clock)
			end)
			if not ok then
				warn("[Tutorial] " .. tostring(err))
			end
		end
		animate(clock)
	end)
end

return Tutorial
