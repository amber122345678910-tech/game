--!strict
-- Эффекты на персонажах всех игроков:
--  * банка на спине: неоновое ядро наполняется снизу по атрибуту JarFill (пружинкой), голубое -> белое,
--    выше 100% краснеет, пульсирует и трещит (треск — только у своего игрока);
--  * кончик громоотвода светится ярче с комбо;
--  * «Шарахнуло» (атрибут ZappedUntil): сажа (Highlight) и искры над головой;
--  * цепная молния — дуга между громоотводами, сдача банки — сгустки энергии летят на подстанцию,
--    лопнувшая банка — стеклянные осколки;
--  * Тесла-дрон: взлетает с банки со сгустком заряда, летит к подстанции, сдаёт его и возвращается.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Loc = require(Shared:WaitForChild("Loc"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)
local Juice = require(script.Parent.Juice)
local Theme = require(script.Parent.Parent.UI.Theme)

local CharacterFX = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Визуальные константы
----------------------------------------------------------------------
local JAR_BLUE = Color3.fromRGB(80, 165, 255)
local JAR_HOT = Color3.fromRGB(235, 245, 255)
local JAR_OVER = Color3.fromRGB(255, 200, 175)
local JAR_RED = Color3.fromRGB(255, 60, 55)
local WHITE = Color3.new(1, 1, 1)
local SOOT = Color3.fromRGB(26, 22, 30)
local ZAP_OUTLINE = Color3.fromRGB(255, 230, 90)
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPRING = 9 -- жёсткость пружины заполнения банки
local SEARCH_EVERY = 0.5 -- как часто искать банку и громоотвод
local FAR_UPDATE = 120 -- дальше этого чужие персонажи обновляются редко
local FAR_UPDATE_EVERY = 0.25
local JAR_LIGHT_DISTANCE = 70 -- дальше этого свет чужой банки выключаем
local JAR_LIGHTS_OTHERS = 2 -- свет чужих банок — только у стольких ближайших (лимит источников света)
local JAR_LIGHT_MIN_FILL = 0.05 -- почти пустая чужая банка не светит
local JAR_LIGHT_EVERY = 0.1 -- яркость и цвет света банки обновляем не чаще
local TIP_FX_DISTANCE = 90
local HIGHLIGHT_DISTANCE = 150
local COMBO_FULL = Config.Catch.ComboCap -- при таком комбо громоотвод сияет на максимум
local CHAIN_TIME = 0.4
local CHAIN_POOL = 4
local ORB_COUNT = 7
local ORB_TIME = 0.45
local DEBRIS_POOL = 28
local DEBRIS_COUNT = 12
local DEBRIS_TIME = 0.9
local BURST_DEDUPE = 0.6
local DRONE_RISE = 0.5 -- взлёт с банки (с)
local DRONE_OUT = 0.45 -- доля полёта: прилетел к подстанции
local DRONE_DROP = 0.52 -- сдал заряд
local DRONE_BACK = 0.62 -- полетел обратно
local DRONE_WAIT = 1.5 -- ждёт "sold" над игроком не дольше
local DRONE_LAND = 0.3 -- садится в банку
local DRONE_BODY = Color3.fromRGB(70, 76, 104)
local DRONE_ROTOR = Color3.fromRGB(200, 210, 235)
local HIDDEN = CFrame.new(0, 1e4, 0)

----------------------------------------------------------------------
-- Типы
----------------------------------------------------------------------
type Track = {
	player: Player,
	char: Model?,
	core: BasePart?,
	jarLight: PointLight?,
	fill: Part?,
	weld: Weld?,
	axis: Vector3, -- ось высоты ядра в его локальных координатах (вверх)
	axisIndex: number, -- 1 = X, 2 = Y, 3 = Z
	size0: Vector3,
	h0: number,
	ball: boolean,
	fillPos: number,
	fillVel: number,
	written: number,
	tip: BasePart?,
	tipEmitter: ParticleEmitter?,
	tipK: number,
	highlight: Highlight?,
	zapAtt: Attachment?,
	zapEmitter: ParticleEmitter?,
	zapping: boolean,
	nextSearch: number,
	nextUpdate: number,
	nextCrackle: number,
	nextLight: number,
	lastClock: number,
	conns: { RBXScriptConnection },
}

type ChainArc = {
	p0: Part,
	p1: Part,
	core: Beam,
	glow: Beam,
	u0: number,
	u1: number,
	t0: number,
	busy: boolean,
}

type Debris = { part: Part, pos: Vector3, vel: Vector3, spin: Vector3, rot: CFrame, t0: number, dur: number, base: number }
type Orb = { part: Part, from: Vector3, ctrl: Vector3, to: Vector3, t0: number, dur: number }

----------------------------------------------------------------------
-- Помощники
----------------------------------------------------------------------
local fxFolder = Instance.new("Folder")
fxFolder.Name = "CharacterFX"
fxFolder.Parent = Workspace

local function newPart(shape: Enum.PartType, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = 1
	p.Size = Vector3.one * 0.3
	p.CFrame = HIDDEN
	p.Parent = fxFolder
	return p
end

local function sparkEmitter(color: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK_TEXTURE
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 0
	e.Enabled = false
	e.Lifetime = NumberRange.new(0.25, 0.5)
	e.Speed = NumberRange.new(3, 8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Color = ColorSequence.new(WHITE, color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0.8),
	})
	return e
end

local function shakeOn(): boolean
	local d = ClientState.data
	return d ~= nil and d.Settings.Shake
end

local function softFlash(): boolean
	local d = ClientState.data
	return d == nil or d.Settings.SoftFlash
end

local function cameraPos(): Vector3
	local cam = Workspace.CurrentCamera
	return if cam then cam.CFrame.Position else Vector3.zero
end

local function rootOf(char: Model?): BasePart?
	if not char then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Кончик громоотвода, голова или корень — куда цепляется дуга
local function tipPosOf(p: Player): Vector3?
	local char = p.Character
	if not char then
		return nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	local tip = if tool then tool:FindFirstChild("Tip", true) else nil
	if tip and tip:IsA("BasePart") then
		return tip.Position
	end
	local head = char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, 1, 0)
	end
	local root = rootOf(char)
	return if root then root.Position + Vector3.new(0, 2.5, 0) else nil
end

-- Исходные цвета чужих деталей (кончик громоотвода), чтобы не перепутать с уже подкрашенными
local baseColors: { [BasePart]: Color3 } = setmetatable({}, { __mode = "k" }) :: any

local function axisComponent(v: Vector3, index: number): number
	return if index == 1 then v.X elseif index == 2 then v.Y else v.Z
end

local function withAxis(v: Vector3, index: number, value: number): Vector3
	if index == 1 then
		return Vector3.new(value, v.Y, v.Z)
	elseif index == 2 then
		return Vector3.new(v.X, value, v.Z)
	end
	return Vector3.new(v.X, v.Y, value)
end

----------------------------------------------------------------------
-- Персонажи
----------------------------------------------------------------------
local tracks: { [Player]: Track } = {}

local function clearJar(t: Track)
	local fill = t.fill
	if fill then
		fill:Destroy()
	end
	local core = t.core
	if core and core.Parent then
		core.LocalTransparencyModifier = 0
	end
	t.fill = nil
	t.weld = nil
	t.core = nil
	t.jarLight = nil
	t.written = -1
end

local function clearTip(t: Track)
	local tip = t.tip
	if tip and tip.Parent then
		local base = baseColors[tip]
		if base then
			tip.Color = base
		end
	end
	local e = t.tipEmitter
	if e then
		e:Destroy()
	end
	t.tip = nil
	t.tipEmitter = nil
	t.tipK = -1
end

local function clearZap(t: Track)
	local h = t.highlight
	if h then
		h:Destroy()
	end
	local a = t.zapAtt
	if a then
		a:Destroy()
	end
	t.highlight = nil
	t.zapAtt = nil
	t.zapEmitter = nil
	t.zapping = false
end

local function clearCharacter(t: Track)
	clearJar(t)
	clearTip(t)
	clearZap(t)
	t.char = nil
end

-- Найти ядро банки и подготовить своё «наполнение», приваренное к нему
local function setupJar(t: Track, char: Model)
	local jar = char:FindFirstChild("Jar") or char:FindFirstChild("Jar", true)
	if not jar or not jar:IsA("Model") then
		return
	end
	local core = jar:FindFirstChild("Core")
	if not core or not core:IsA("BasePart") then
		return
	end
	local root = rootOf(char)
	local up = if root then root.CFrame.UpVector else Vector3.yAxis
	local cf = core.CFrame
	local dots = { cf.XVector:Dot(up), cf.YVector:Dot(up), cf.ZVector:Dot(up) }
	local best = 1
	for i = 2, 3 do
		if math.abs(dots[i]) > math.abs(dots[best]) then
			best = i
		end
	end
	local sign = if dots[best] >= 0 then 1 else -1
	local unit = if best == 1 then Vector3.xAxis elseif best == 2 then Vector3.yAxis else Vector3.zAxis
	local isBall = core:IsA("Part") and core.Shape == Enum.PartType.Ball

	local fill = Instance.new("Part")
	fill.Name = "JarFillFX"
	fill.Material = Enum.Material.Neon
	if core:IsA("Part") then
		local shape = core.Shape
		-- цилиндр масштабируется по длине только вдоль своей оси X
		if shape == Enum.PartType.Cylinder and best ~= 1 then
			shape = Enum.PartType.Block
		end
		fill.Shape = shape
	end
	fill.Size = core.Size
	fill.Color = JAR_BLUE
	fill.Transparency = 1
	fill.Anchored = false
	fill.Massless = true
	fill.CanCollide = false
	fill.CanQuery = false
	fill.CanTouch = false
	fill.CastShadow = false
	fill.CFrame = cf
	local weld = Instance.new("Weld")
	weld.Name = "FillWeld"
	weld.Part0 = core
	weld.Part1 = fill
	weld.C0 = CFrame.identity
	weld.Parent = fill
	fill.Parent = jar
	-- настоящее ядро прячем только у себя (сервер его не трогает)
	core.LocalTransparencyModifier = 1

	t.core = core
	t.jarLight = core:FindFirstChildOfClass("PointLight")
	t.fill = fill
	t.weld = weld
	t.axis = unit * sign
	t.axisIndex = best
	t.size0 = core.Size
	t.h0 = axisComponent(core.Size, best)
	t.ball = isBall
	t.written = -1
end

local function setupTip(t: Track, char: Model)
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		return
	end
	local tip = tool:FindFirstChild("Tip", true)
	if not tip or not tip:IsA("BasePart") then
		return
	end
	if not baseColors[tip] then
		baseColors[tip] = tip.Color
	end
	local e = sparkEmitter(baseColors[tip] or Theme.Electric)
	e.Name = "ComboSparks"
	e.Parent = tip
	t.tip = tip
	t.tipEmitter = e
	t.tipK = -1
end

local function attrNumber(p: Player, name: string): number
	local v = p:GetAttribute(name)
	return if typeof(v) == "number" and v == v then v else 0
end

local function startZap(t: Track)
	local char = t.char
	if not char then
		return
	end
	t.zapping = true
	local root = rootOf(char)
	local near = root ~= nil and (root.Position - cameraPos()).Magnitude <= HIGHLIGHT_DISTANCE
	if near and not t.highlight then
		local h = Instance.new("Highlight")
		h.Name = "ZapSoot"
		h.FillColor = SOOT
		h.FillTransparency = 0.35
		h.OutlineColor = ZAP_OUTLINE
		h.OutlineTransparency = 0.25
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = char
		h.Parent = fxFolder
		t.highlight = h
	end
	local h = t.highlight
	if h then
		h.Enabled = near
	end
	if not t.zapEmitter then
		local head = char:FindFirstChild("Head")
		local parent: BasePart? = if head and head:IsA("BasePart") then head else root
		if parent then
			local att = Instance.new("Attachment")
			att.Name = "ZapSparks"
			att.Position = Vector3.new(0, 0.9, 0)
			att.Parent = parent
			local e = sparkEmitter(ZAP_OUTLINE)
			e.Rate = 45
			e.Speed = NumberRange.new(6, 14)
			e.Lifetime = NumberRange.new(0.2, 0.45)
			e.Parent = att
			t.zapAtt = att
			t.zapEmitter = e
		end
	end
	local e = t.zapEmitter
	if e then
		e.Enabled = true
	end
	if t.player == player then
		Sounds.play("Zap")
		if shakeOn() then
			Juice.shake(0.35)
		end
	end
end

local function stopZap(t: Track)
	t.zapping = false
	local h = t.highlight
	if h then
		h.Enabled = false
	end
	local e = t.zapEmitter
	if e then
		e.Enabled = false
	end
end

-- Прогноз «Шарахнуло» у своего игрока (CatchController): показываем сразу, атрибут сервера потом только продлевает
local predictedZapUntil = 0

local function checkZap(t: Track)
	local untilT = attrNumber(t.player, Net.PlayerAttrs.ZappedUntil)
	if t.player == player then
		untilT = math.max(untilT, predictedZapUntil)
	end
	local on = t.char ~= nil and untilT > ClientState.now()
	if on and not t.zapping then
		startZap(t)
	elseif not on and t.zapping then
		stopZap(t)
	end
end

local function updateJar(t: Track, dt: number, clock: number, lightOn: boolean)
	local core = t.core
	local fill = t.fill
	local weld = t.weld
	if not core or not fill or not weld then
		return
	end
	local target = math.clamp(attrNumber(t.player, Net.PlayerAttrs.JarFill), 0, Config.Overcharge.MaxFill)
	-- критически затухающая пружина
	local x, v = t.fillPos, t.fillVel
	local a = SPRING * SPRING * (target - x) - 2 * SPRING * v
	v += a * dt
	x += v * dt
	if math.abs(target - x) < 0.0005 and math.abs(v) < 0.001 then
		x, v = target, 0
	end
	t.fillPos, t.fillVel = x, v
	local f = math.clamp(x, 0, Config.Overcharge.MaxFill)

	if math.abs(f - t.written) > 0.003 then
		t.written = f
		if t.ball then
			fill.Size = t.size0 * (0.3 + 0.7 * math.min(f, 1.5))
		else
			local h = math.max(0.02, t.h0 * f)
			fill.Size = withAxis(t.size0, t.axisIndex, h)
			weld.C0 = CFrame.new(t.axis * ((h - t.h0) / 2))
		end
		fill.Transparency = if f < 0.01 then 1 else 0.05
	end
	if core.LocalTransparencyModifier < 1 then
		core.LocalTransparencyModifier = 1
	end

	local color: Color3
	local pulse = 0
	if f <= 1 then
		color = JAR_BLUE:Lerp(JAR_HOT, f ^ 1.6)
	else
		local k = math.clamp((f - 1) / (Config.Overcharge.MaxFill - 1), 0, 1)
		pulse = 0.5 + 0.5 * math.sin(clock * (7 + 9 * k))
		color = JAR_OVER:Lerp(JAR_RED, 0.35 + 0.65 * pulse * (0.4 + 0.6 * k))
		-- треск перегрузки: только у своего игрока
		if t.player == player and clock >= t.nextCrackle then
			Sounds.play("Crackle", 1 + 0.25 * k)
			t.nextCrackle = clock + (1.1 - 0.65 * k) * (0.8 + 0.4 * math.random())
		end
	end
	fill.Color = color
	local light = t.jarLight
	if light and light.Parent then
		if light.Enabled ~= lightOn then
			light.Enabled = lightOn
			t.nextLight = 0
		end
		-- свет меняем ~10 раз в секунду, а не каждый кадр (дорого на телефонах)
		if lightOn and clock >= t.nextLight then
			t.nextLight = clock + JAR_LIGHT_EVERY
			light.Color = color
			light.Brightness = 0.3 + 1.8 * math.min(f, 1) + 1.4 * pulse
			light.Range = 5 + 5 * math.min(f, 1.5)
		end
	end
end

-- Чьи чужие банки светят: только JAR_LIGHTS_OTHERS ближайших к камере и не пустых (пересчёт раз в SEARCH_EVERY)
local jarLightAllowed: { [Player]: boolean } = {}
local nextJarLightPick = 0

local function pickJarLights(clock: number)
	if clock < nextJarLightPick then
		return
	end
	nextJarLightPick = clock + SEARCH_EVERY
	table.clear(jarLightAllowed)
	local cam = cameraPos()
	local picked: { Player } = {}
	local dists: { [Player]: number } = {}
	for p, t in tracks do
		if p ~= player and t.jarLight and attrNumber(p, Net.PlayerAttrs.JarFill) >= JAR_LIGHT_MIN_FILL then
			local root = rootOf(t.char)
			if root then
				local d = (root.Position - cam).Magnitude
				if d <= JAR_LIGHT_DISTANCE then
					dists[p] = d
					table.insert(picked, p)
				end
			end
		end
	end
	table.sort(picked, function(a: Player, b: Player): boolean
		return dists[a] < dists[b]
	end)
	for i = 1, math.min(JAR_LIGHTS_OTHERS, #picked) do
		jarLightAllowed[picked[i]] = true
	end
end

local function updateTip(t: Track, near: boolean)
	local tip = t.tip
	if not tip then
		return
	end
	local combo = attrNumber(t.player, Net.PlayerAttrs.Combo)
	local k = math.clamp(combo / COMBO_FULL, 0, 1)
	if math.abs(k - t.tipK) < 0.01 then
		return
	end
	t.tipK = k
	local base = baseColors[tip] or tip.Color
	tip.Color = base:Lerp(WHITE, 0.7 * k)
	local e = t.tipEmitter
	if e then
		local on = near and k >= 0.15
		e.Enabled = on
		e.Rate = if on then 3 + 30 * k else 0
	end
end

local function updateTrack(t: Track, clock: number)
	local char = t.char
	if not char or not char.Parent then
		return
	end
	local root = rootOf(char)
	local dist = if root then (root.Position - cameraPos()).Magnitude else math.huge
	local isLocal = t.player == player
	-- дальние персонажи обновляются реже
	if not isLocal and dist > FAR_UPDATE and clock < t.nextUpdate then
		return
	end
	t.nextUpdate = clock + FAR_UPDATE_EVERY
	local dt = math.clamp(clock - t.lastClock, 0, 0.1)
	t.lastClock = clock

	-- поиск и проверка банки и громоотвода
	if clock >= t.nextSearch then
		t.nextSearch = clock + SEARCH_EVERY
		local core = t.core
		if core and not core:IsDescendantOf(char) then
			clearJar(t)
		end
		if not t.core then
			setupJar(t, char)
		end
		local tip = t.tip
		if tip and not tip:IsDescendantOf(char) then
			clearTip(t)
		end
		if not t.tip then
			setupTip(t, char)
		end
	end

	updateJar(t, dt, clock, isLocal or (dist <= JAR_LIGHT_DISTANCE and jarLightAllowed[t.player] == true))
	updateTip(t, isLocal or dist <= TIP_FX_DISTANCE)
	checkZap(t)
	if t.zapping then
		local h = t.highlight
		if h and h.Enabled then
			-- контур искрит; с «мягкими вспышками» — плавно дрожит (~3 раза в секунду), без стробоскопа
			h.OutlineTransparency = if softFlash() then 0.3 + 0.25 * math.sin(clock * 18) else math.random() * 0.6
		end
	end
end

local function onCharacter(t: Track, char: Model)
	clearCharacter(t)
	t.char = char
	t.fillPos = 0
	t.fillVel = 0
	t.nextSearch = 0
	t.nextUpdate = 0
	t.lastClock = os.clock()
end

local function addPlayer(p: Player)
	if tracks[p] then
		return
	end
	local t: Track = {
		player = p,
		char = nil,
		core = nil,
		jarLight = nil,
		fill = nil,
		weld = nil,
		axis = Vector3.yAxis,
		axisIndex = 2,
		size0 = Vector3.one,
		h0 = 1,
		ball = false,
		fillPos = 0,
		fillVel = 0,
		written = -1,
		tip = nil,
		tipEmitter = nil,
		tipK = -1,
		highlight = nil,
		zapAtt = nil,
		zapEmitter = nil,
		zapping = false,
		nextSearch = 0,
		nextUpdate = 0,
		nextCrackle = 0,
		nextLight = 0,
		lastClock = os.clock(),
		conns = {},
	}
	tracks[p] = t
	table.insert(t.conns, p.CharacterAdded:Connect(function(char: Model)
		onCharacter(t, char)
	end))
	table.insert(t.conns, p.CharacterRemoving:Connect(function()
		clearCharacter(t)
	end))
	table.insert(t.conns, p:GetAttributeChangedSignal(Net.PlayerAttrs.ZappedUntil):Connect(function()
		checkZap(t)
	end))
	if p.Character then
		onCharacter(t, p.Character)
	end
end

local function removePlayer(p: Player)
	local t = tracks[p]
	if not t then
		return
	end
	tracks[p] = nil
	for _, c in t.conns do
		c:Disconnect()
	end
	clearCharacter(t)
end

----------------------------------------------------------------------
-- Цепная молния: дуга между громоотводами
----------------------------------------------------------------------
local arcs: { ChainArc } = {}
for i = 1, CHAIN_POOL do
	local p0 = newPart(Enum.PartType.Block, Enum.Material.SmoothPlastic)
	p0.Name = "ChainA" .. i
	local p1 = newPart(Enum.PartType.Block, Enum.Material.SmoothPlastic)
	p1.Name = "ChainB" .. i
	local a0 = Instance.new("Attachment")
	a0.Parent = p0
	local a1 = Instance.new("Attachment")
	a1.Parent = p1
	local function beam(width: number, color: ColorSequence, transp: number): Beam
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 14
		b.Width0 = width
		b.Width1 = width
		b.Color = color
		b.Transparency = NumberSequence.new(transp)
		b.Enabled = false
		b.Parent = p0
		return b
	end
	arcs[i] = {
		p0 = p0,
		p1 = p1,
		core = beam(0.22, ColorSequence.new(WHITE), 0),
		glow = beam(0.8, ColorSequence.new(Theme.Electric), 0.35),
		u0 = 0,
		u1 = 0,
		t0 = 0,
		busy = false,
	}
end

local function startArc(u0: number, u1: number)
	for _, a in arcs do
		if not a.busy then
			a.busy = true
			a.u0 = u0
			a.u1 = u1
			a.t0 = os.clock()
			a.core.Enabled = true
			a.glow.Enabled = true
			return
		end
	end
end

local function updateArcs(clock: number)
	for _, a in arcs do
		if a.busy then
			local k = (clock - a.t0) / CHAIN_TIME
			local p0 = Players:GetPlayerByUserId(a.u0)
			local p1 = Players:GetPlayerByUserId(a.u1)
			local from = if p0 then tipPosOf(p0) else nil
			local to = if p1 then tipPosOf(p1) else nil
			if k >= 1 or not from or not to then
				a.busy = false
				a.core.Enabled = false
				a.glow.Enabled = false
				a.p0.CFrame = HIDDEN
				a.p1.CFrame = HIDDEN
			else
				a.p0.CFrame = CFrame.new(from)
				a.p1.CFrame = CFrame.new(to)
				local c0 = (math.random() - 0.5) * 8
				local c1 = (math.random() - 0.5) * 8
				a.core.CurveSize0, a.core.CurveSize1 = c0, c1
				a.glow.CurveSize0, a.glow.CurveSize1 = c0, c1
				local fade = math.max(0, (k - 0.6) / 0.4)
				a.core.Transparency = NumberSequence.new(fade)
				a.glow.Transparency = NumberSequence.new(0.35 + 0.65 * fade)
			end
		end
	end
end

----------------------------------------------------------------------
-- Сгустки энергии (сдача банки) и осколки стекла (банка лопнула)
----------------------------------------------------------------------
local orbFree: { Part } = {}
local orbs: { Orb } = {}
local debrisFree: { Part } = {}
local debris: { Debris } = {}

for i = 1, ORB_COUNT * 2 do
	local p = newPart(Enum.PartType.Ball, Enum.Material.Neon)
	p.Name = "Orb" .. i
	table.insert(orbFree, p)
end
for i = 1, DEBRIS_POOL do
	local p = newPart(Enum.PartType.Block, Enum.Material.Glass)
	p.Name = "Glass" .. i
	p.Reflectance = 0.2
	table.insert(debrisFree, p)
end

local moveParts: { BasePart } = {}
local moveCFs: { CFrame } = {}

local function jarPosOf(p: Player): Vector3?
	local t = tracks[p]
	local fill = t and t.fill
	if fill and fill.Parent then
		return fill.Position
	end
	local core = t and t.core
	if core and core.Parent then
		return core.Position
	end
	local root = rootOf(p.Character)
	if root then
		return root.Position - root.CFrame.LookVector * 1.2 + Vector3.new(0, 0.5, 0)
	end
	return nil
end

-- Ближайшая подстанция (метки SellPad_N на карте)
local function nearestStation(pos: Vector3): Vector3?
	local map = Workspace:FindFirstChild("Map")
	local markers = map and map:FindFirstChild("Markers")
	if not markers then
		return nil
	end
	local best: Vector3? = nil
	local bestD = math.huge
	for _, m in markers:GetChildren() do
		if m:IsA("BasePart") and string.sub(m.Name, 1, 8) == "SellPad_" then
			local d = (m.Position - pos).Magnitude
			if d < bestD then
				bestD = d
				best = m.Position
			end
		end
	end
	return best
end

local function launchOrbs(from: Vector3, to: Vector3)
	local clock = os.clock()
	for i = 1, ORB_COUNT do
		local p = table.remove(orbFree)
		if not p then
			break
		end
		local mid = from:Lerp(to, 0.5)
		local side = Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
		p.Color = Theme.Volt:Lerp(Theme.Electric, (i - 1) / ORB_COUNT)
		p.Size = Vector3.one * (0.5 + 0.35 * math.random())
		p.Transparency = 0.05
		p.CFrame = CFrame.new(from)
		table.insert(orbs, {
			part = p,
			from = from,
			ctrl = mid + side + Vector3.new(0, 5 + 3 * math.random(), 0),
			to = to,
			t0 = clock + (i - 1) * 0.05,
			dur = ORB_TIME + 0.1 * math.random(),
		})
	end
end

local function burstGlass(at: Vector3)
	local clock = os.clock()
	for _ = 1, DEBRIS_COUNT do
		local p = table.remove(debrisFree)
		if not p then
			break
		end
		local s = 0.2 + 0.35 * math.random()
		p.Size = Vector3.new(s, s * (0.6 + math.random()), s * 0.4)
		p.Color = JAR_HOT:Lerp(Theme.Shard, math.random())
		p.Transparency = 0.3
		local dir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
		dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.xAxis
		table.insert(debris, {
			part = p,
			pos = at,
			vel = dir * (10 + 12 * math.random()) + Vector3.new(0, 8 + 10 * math.random(), 0),
			spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 18,
			rot = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			t0 = clock,
			dur = DEBRIS_TIME * (0.8 + 0.4 * math.random()),
			base = 0.3,
		})
	end
end

local function updateParticles(clock: number, dt: number)
	local n = 0
	for i = #orbs, 1, -1 do
		local o = orbs[i]
		local k = (clock - o.t0) / o.dur
		if k >= 1 then
			o.part.Transparency = 1
			n += 1
			moveParts[n] = o.part
			moveCFs[n] = HIDDEN
			table.insert(orbFree, o.part)
			orbs[i] = orbs[#orbs]
			orbs[#orbs] = nil
		elseif k >= 0 then
			local e = k * k * (3 - 2 * k)
			local a = o.from:Lerp(o.ctrl, e)
			local b = o.ctrl:Lerp(o.to, e)
			n += 1
			moveParts[n] = o.part
			moveCFs[n] = CFrame.new(a:Lerp(b, e))
		end
	end
	for i = #debris, 1, -1 do
		local d = debris[i]
		local k = (clock - d.t0) / d.dur
		if k >= 1 then
			d.part.Transparency = 1
			n += 1
			moveParts[n] = d.part
			moveCFs[n] = HIDDEN
			table.insert(debrisFree, d.part)
			debris[i] = debris[#debris]
			debris[#debris] = nil
		else
			d.vel += Vector3.new(0, -70 * dt, 0)
			d.pos += d.vel * dt
			d.rot = d.rot * CFrame.Angles(d.spin.X * dt, d.spin.Y * dt, d.spin.Z * dt)
			if k > 0.65 then
				d.part.Transparency = d.base + (1 - d.base) * ((k - 0.65) / 0.35)
			end
			n += 1
			moveParts[n] = d.part
			moveCFs[n] = CFrame.new(d.pos) * d.rot
		end
	end
	for i = #moveParts, n + 1, -1 do
		moveParts[i] = nil
		moveCFs[i] = nil
	end
	if n > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------
-- Тесла-дрон своего игрока (Effect drone: "depart" — улетел с зарядом, "sold" — сдал)
----------------------------------------------------------------------
type DronePart = { part: Part, offset: CFrame, spin: boolean }
local droneParts: { DronePart } = {}
local droneOrb: Part
do
	local function add(shape: Enum.PartType, material: Enum.Material, size: Vector3, color: Color3, offset: CFrame, spin: boolean): Part
		local p = newPart(shape, material)
		p.Name = "Drone"
		p.Size = size
		p.Color = color
		table.insert(droneParts, { part = p, offset = offset, spin = spin })
		return p
	end
	add(Enum.PartType.Ball, Enum.Material.Metal, Vector3.one * 1.1, DRONE_BODY, CFrame.identity, false)
	add(Enum.PartType.Cylinder, Enum.Material.Neon, Vector3.new(0.2, 1.6, 1.6), Theme.Electric, CFrame.Angles(0, 0, math.pi / 2), false)
	add(Enum.PartType.Block, Enum.Material.SmoothPlastic, Vector3.new(2.8, 0.06, 0.26), DRONE_ROTOR, CFrame.new(0, 0.72, 0), true)
	add(Enum.PartType.Block, Enum.Material.SmoothPlastic, Vector3.new(0.26, 0.06, 2.8), DRONE_ROTOR, CFrame.new(0, 0.72, 0), true)
	droneOrb = add(Enum.PartType.Ball, Enum.Material.Neon, Vector3.one * 0.9, Theme.Volt, CFrame.new(0, -0.95, 0), false)
end

type DroneFlight = {
	t0: number,
	trip: number,
	from: Vector3, -- где взлетел (над банкой)
	station: Vector3, -- куда везёт заряд
	out: Vector3?, -- откуда полетел к подстанции (после взлёта)
	dropped: boolean,
	landT: number?, -- начал садиться в банку
	landFrom: Vector3?,
	pos: Vector3,
}
local flight: DroneFlight? = nil
local droneShown = false
local droneMoveParts: { BasePart } = {}
local droneMoveCFs: { CFrame } = {}

local function bezier(a: Vector3, ctrl: Vector3, b: Vector3, t: number): Vector3
	local e = t * t * (3 - 2 * t)
	return a:Lerp(ctrl, e):Lerp(ctrl:Lerp(b, e), e)
end

local function hideDrone()
	if not droneShown then
		return
	end
	droneShown = false
	for _, dp in droneParts do
		dp.part.Transparency = 1
		dp.part.CFrame = HIDDEN
	end
end

local function droneDepart(trip: number)
	local from = jarPosOf(player)
	if not from then
		return
	end
	local station = nearestStation(from)
	flight = {
		t0 = os.clock(),
		trip = math.max(1, trip),
		from = from,
		-- нет подстанции рядом — просто кружит над игроком
		station = if station then station + Vector3.new(0, 7, 0) else from + Vector3.new(0, 14, 0),
		out = nil,
		dropped = false,
		landT = nil,
		landFrom = nil,
		pos = from,
	}
	droneShown = true
	for _, dp in droneParts do
		dp.part.Transparency = if dp.spin then 0.35 else 0
	end
	droneOrb.Transparency = 0.05
	Sounds.play("Sell", 1.25, 0.6)
	Juice.popup(from + Vector3.new(0, 2.5, 0), Loc.t("🤖 Дрон везёт заряд"), Theme.Electric, false)
end

local function droneLand(clock: number)
	local f = flight
	if f and not f.landT then
		f.landT = clock
		f.landFrom = f.pos
	end
end

local function updateDrone(clock: number)
	local f = flight
	if not f then
		hideDrone()
		return
	end
	local home = (jarPosOf(player) or f.from) + Vector3.new(0, 4, 0)
	local t = clock - f.t0
	local pos: Vector3
	local landT = f.landT
	local scale = 1
	if landT then
		local k = math.clamp((clock - landT) / DRONE_LAND, 0, 1)
		pos = (f.landFrom or home):Lerp(home - Vector3.new(0, 4, 0), k)
		scale = 1 - 0.8 * k
		if k >= 1 then
			flight = nil
			hideDrone()
			return
		end
	elseif t < DRONE_RISE then
		pos = f.from:Lerp(home, t / DRONE_RISE)
	elseif t < f.trip * DRONE_OUT then
		local out = f.out or home
		f.out = out
		local k = (t - DRONE_RISE) / math.max(0.05, f.trip * DRONE_OUT - DRONE_RISE)
		pos = bezier(out, out:Lerp(f.station, 0.5) + Vector3.new(0, 10, 0), f.station, k)
	elseif t < f.trip * DRONE_BACK then
		pos = f.station + Vector3.new(0, math.sin(clock * 5) * 0.4, 0)
		if not f.dropped and t >= f.trip * DRONE_DROP then
			f.dropped = true
			droneOrb.Transparency = 1
			launchOrbs(pos, f.station - Vector3.new(0, 4, 0))
		end
	elseif t < f.trip then
		local k = (t - f.trip * DRONE_BACK) / math.max(0.05, f.trip * (1 - DRONE_BACK))
		pos = bezier(f.station, f.station:Lerp(home, 0.5) + Vector3.new(0, 8, 0), home, k)
	else
		pos = home + Vector3.new(0, math.sin(clock * 5) * 0.3, 0)
		if t >= f.trip + DRONE_WAIT then
			droneLand(clock) -- "sold" так и не пришёл
		end
	end
	if not f.dropped and t >= f.trip * DRONE_DROP then
		f.dropped = true
		droneOrb.Transparency = 1
	end
	f.pos = pos
	-- лёгкое покачивание корпуса и вращение винтов
	local base = CFrame.new(pos) * CFrame.Angles(0, clock * 0.8, math.sin(clock * 2.2) * 0.08)
	local n = 0
	for _, dp in droneParts do
		n += 1
		local off = dp.offset
		if dp.spin then
			off = off * CFrame.Angles(0, clock * 28, 0)
		end
		if scale ~= 1 then
			off = CFrame.new(off.Position * scale) * off.Rotation
		end
		droneMoveParts[n] = dp.part
		droneMoveCFs[n] = base * off
	end
	Workspace:BulkMoveTo(droneMoveParts, droneMoveCFs, Enum.BulkMoveMode.FireCFrameChanged)
end

----------------------------------------------------------------------
-- Разовые эффекты
----------------------------------------------------------------------
local lastBurst = -math.huge

local function onBurst(p: Player, lost: number?)
	local isLocal = p == player
	if isLocal then
		local clock = os.clock()
		if clock - lastBurst < BURST_DEDUPE then
			return
		end
		lastBurst = clock
	end
	local at = jarPosOf(p)
	if at and (isLocal or (at - cameraPos()).Magnitude < 150) then
		burstGlass(at)
	end
	if isLocal then
		Sounds.play("Burst")
		if shakeOn() then
			Juice.shake(0.3)
		end
		local text = if lost and lost > 0 then Loc.t("Банка лопнула! −%s", Format.short(lost)) else Loc.t("Банка лопнула!")
		ClientState.Toast:Fire(text, "bad")
	end
end

local function onSell(msg: Net.EffectMsg, p: Player)
	local isLocal = p == player
	local from = jarPosOf(p)
	if from and (isLocal or (from - cameraPos()).Magnitude < 120) then
		local station: Vector3? = if typeof(msg.Pos) == "Vector3" then msg.Pos else nearestStation(from)
		if station then
			launchOrbs(from, station + Vector3.new(0, 3, 0))
		end
	end
	if isLocal then
		Sounds.play("Sell")
		task.delay(ORB_TIME, function()
			Sounds.play("Coins")
		end)
		local value = if typeof(msg.Value) == "number" then msg.Value else 0
		local root = rootOf(player.Character)
		if root and value > 0 then
			Juice.popup(root.Position + Vector3.new(0, 4, 0), "+" .. Format.short(value) .. " ⚡", Theme.Volt, true)
		end
	end
end

local function onEffect(msg: Net.EffectMsg)
	local m = msg :: any
	if typeof(m) ~= "table" or typeof(m.Kind) ~= "string" then
		return
	end
	local subject: Player = player
	if typeof(m.UserId) == "number" then
		subject = Players:GetPlayerByUserId(m.UserId) or player
		if m.UserId ~= player.UserId and subject == player then
			return -- игрок уже вышел
		end
	end
	if msg.Kind == "chain" then
		local ids: { number } = {}
		if typeof(m.UserId) == "number" then
			table.insert(ids, m.UserId)
		end
		if typeof(m.Targets) == "table" then
			for _, id in m.Targets do
				if typeof(id) == "number" and not table.find(ids, id) then
					table.insert(ids, id)
				end
			end
		end
		-- дуги от поймавшего (первый в списке) к каждому напарнику, а не между напарниками
		for i = 2, #ids do
			startArc(ids[1], ids[i])
		end
		if table.find(ids, player.UserId) then
			Sounds.play("PerfectZap", 1.25, 0.8)
			local root = rootOf(player.Character)
			if root then
				Juice.popup(root.Position + Vector3.new(0, 5, 0), Loc.t("Цепная молния!"), Theme.Electric, true)
			end
		end
	elseif msg.Kind == "sell" then
		onSell(msg, subject)
	elseif msg.Kind == "drone" and m.Text == "depart" and subject == player then
		droneDepart(if typeof(m.Value) == "number" then math.clamp(m.Value, 0, 60) else Config.Drone.TripTime)
	elseif msg.Kind == "drone" and m.Text == "sold" and subject == player then
		droneLand(os.clock())
		local value = if typeof(m.Value) == "number" then m.Value else 0
		local root = rootOf(player.Character)
		if root and value > 0 then
			Sounds.play("Coins")
			Juice.popup(root.Position + Vector3.new(0, 4, 0), "+" .. Format.short(value) .. " ⚡", Theme.Volt, true)
		end
	elseif msg.Kind == "burst" then
		onBurst(subject, if typeof(m.Value) == "number" then m.Value else nil)
	end
end

local function onResolved(msg: Net.StrikeResultMsg)
	local m = msg :: any
	if typeof(m) ~= "table" then
		return
	end
	if m.Grade == "burst" then
		onBurst(player, if typeof(m.Lost) == "number" then m.Lost else nil)
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Точка кончика громоотвода игрока (для дуг и молний)
function CharacterFX.rodTip(p: Player): Vector3?
	return tipPosOf(p)
end

-- Точка банки игрока
function CharacterFX.jarPosition(p: Player): Vector3?
	return jarPosOf(p)
end

-- Прогноз «Шарахнуло» у своего игрока: сажа, искры, звук и тряска сразу, на duration секунд.
-- Когда придёт ZappedUntil от сервера, эффект просто продолжится (без второго звука).
function CharacterFX.predictZap(duration: number)
	predictedZapUntil = ClientState.now() + math.max(0, duration)
	local t = tracks[player]
	if t then
		checkZap(t)
	end
end

-- Прогноз не подтвердился (сервер не шарахнул): убрать эффект, если сервер сам его не включил
function CharacterFX.cancelPredictedZap()
	predictedZapUntil = 0
	local t = tracks[player]
	if t then
		checkZap(t)
	end
end

----------------------------------------------------------------------
-- Запуск
----------------------------------------------------------------------
local started = false
function CharacterFX.start()
	if started then
		return
	end
	started = true
	for _, p in Players:GetPlayers() do
		addPlayer(p)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)
	ClientState.Effect:Connect(onEffect)
	ClientState.StrikeResolved:Connect(onResolved)

	local last = os.clock()
	RunService.PreRender:Connect(function()
		local clock = os.clock()
		local dt = math.clamp(clock - last, 0, 0.1)
		last = clock
		pickJarLights(clock)
		for _, t in tracks do
			updateTrack(t, clock)
		end
		updateArcs(clock)
		updateParticles(clock, dt)
		updateDrone(clock)
	end)
end

return CharacterFX
