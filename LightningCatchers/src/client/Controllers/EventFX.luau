--!strict
-- Клиентские эффекты событий сервера (только вид, на игру не влияют):
--  * киоски хаба: ProximityPrompt с атрибутом Window открывает окно (ClientState.OpenWindow) без запроса к серверу;
--  * Шаровая молния — яркое ядро-шар в двух колючих полупрозрачных оболочках с иглами и искрами-ромбами
--    на орбите (Models.ballLightning, «колючая гроза» вместо шаров на шаре): пульсирующий свет, трескучие дуги (Beam),
--    искры; плывёт по BallFrom → BallTo между BallStart и BallEnd (атрибуты GameState), над ним полоска
--    «Шаровая молния ♥ HP/макс»; его кольца связаны с ним дрожащими нитями; Effect ballBurst — взрыв искр,
--    тряска, гром и победный звук; улетел сам — тает и поднимается в тучи;
--  * Радужная молния — вертикальный радужный луч над огромным общим кольцом (само кольцо рисует StrikeController);
--  * подарок питомца (Effect hatch) и «Я видел Чёрную молнию!» (Effect witness) — надписи над игроком и звук;
--  * начало события — звук EventStart (небо, дождь и музыку меняет WorldFX).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Pets = require(Shared:WaitForChild("Pets"))
local Models = require(Shared:WaitForChild("Models"))
local Loc = require(Shared:WaitForChild("Loc"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)
local Juice = require(script.Parent.Juice)
local Theme = require(script.Parent.Parent.UI.Theme)

local EventFX = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Визуальные константы
----------------------------------------------------------------------
local BALL_HEIGHT = 16 -- шар висит над землёй
local BALL_BOB = 1.2
local CORE_D = 5 -- размер вспышки взрыва
local SHELL_D = 8.5 -- и её волны
local GLOW_D = 12.5 -- габарит шара с иглами: над ним полоска HP
local ORBIT_R = 6.4
local ARCS = 6
local ARC_REACH = 8
local ARC_HOLD_MIN = 0.05
local ARC_HOLD_MAX = 0.16
-- «Мягкие вспышки»: дуги перескакивают не чаще ~3 раз в секунду и не мигают
local ARC_SOFT_HOLD_MIN = 0.35
local ARC_SOFT_HOLD_MAX = 0.6
-- всплески света шара — по таймеру (не зависят от частоты кадров), не чаще ~2.5 раз в секунду
local SPIKE_MIN = 0.4
local SPIKE_MAX = 0.9
local SPIKE_TIME = 0.12
local SPIKE_AMOUNT = 0.4
local LIGHT_RANGE = 40
local LIGHT_BRIGHTNESS = 3
local HP_SIZE = UDim2.fromOffset(260, 56)
local HP_DISTANCE = 420
local FADE_TIME = 1.5
local FADE_RISE = 24
local TETHER_MAX = 4
local BURST_SIZE = 46
local BURST_TIME = 0.7
local BURST_SPARKS = 140
local BURST_WAIT = 1 -- сколько ждать Effect ballBurst после того, как HP стали 0
local RAINBOW_BEAM_H = 160
local RAINBOW_BEAM_W = 4
local RAINBOW_FADE = 0.7
local POPUP_UP = 3.5

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local WHITE = Color3.new(1, 1, 1)
local BALL_GOLD = Models.BallColors.Gold
local BALL_CORE = Models.BallColors.Core
local BALL_ARC = Models.BallColors.Arc
local HP_BG = Color3.fromRGB(14, 16, 32)

----------------------------------------------------------------------
-- Состояние
----------------------------------------------------------------------
type Arc = { beam: Beam, tip: Attachment, nextAt: number }

type Ball = {
	model: Model,
	core: BasePart,
	shells: { BasePart }, -- две колючие оболочки (крутятся навстречу друг другу)
	shellOffsets: { CFrame },
	shellBase: { number }, -- их исходная прозрачность
	spikes: { BasePart }, -- иглы крутятся вместе с первой оболочкой
	spikeOffsets: { CFrame },
	orbiters: { BasePart },
	orbiterRot: CFrame, -- поворот искры-ромба (куб на вершине)
	light: PointLight,
	sparks: ParticleEmitter,
	center: Attachment,
	arcs: { Arc },
	hpFill: Frame,
	hpText: TextLabel,
	hpScale: UIScale,
	lastHp: number,
	hitFlash: number, -- os.clock удара по шару (вспышка оболочки)
	spikeAt: number, -- os.clock последнего всплеска света
	nextSpike: number,
	dyingSince: number?, -- HP кончились: ждём Effect ballBurst
}

type Tether = { part: Part, beam: Beam, untilT: number }
type RainbowBeam = { outer: Part, inner: Part, light: PointLight, hitAt: number, born: number }

local folder: Folder? = nil
local ball: Ball? = nil
local tethers: { Tether } = {}
local rainbows: { RainbowBeam } = {}

-- атрибуты GameState (кэш)
local event = ""
local ballZone = 0
local ballHp = 0
local ballMax = 0
local ballFrom = Vector3.zero
local ballTo = Vector3.zero
local ballStart = 0
local ballEnd = 0

----------------------------------------------------------------------
-- Вспомогательное
----------------------------------------------------------------------
local function settings(): (boolean, boolean)
	local d = ClientState.data
	if not d then
		return true, true
	end
	return d.Settings.SoftFlash ~= false, d.Settings.Shake ~= false
end

local function newPart(name: string, shape: Enum.PartType, material: Enum.Material, size: Vector3, color: Color3, transparency: number, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Material = material
	p.Size = size
	p.Color = color
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sparkEmitter(parent: Instance, color: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparks"
	e.Texture = SPARK_TEXTURE
	e.Color = ColorSequence.new(WHITE, color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = NumberRange.new(6, 14)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Rate = 26
	e.Parent = parent
	return e
end

local function tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function randomUnit(): Vector3
	local v = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
	if v.Magnitude < 1e-3 then
		return Vector3.yAxis
	end
	return v.Unit
end

local function localRoot(): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function attrNumber(gs: Instance, name: string): number
	local v = gs:GetAttribute(name)
	return if typeof(v) == "number" then v else 0
end

local function attrVector(gs: Instance, name: string): Vector3
	local v = gs:GetAttribute(name)
	return if typeof(v) == "Vector3" then v else Vector3.zero
end

----------------------------------------------------------------------
-- Шаровая молния
----------------------------------------------------------------------
local function ballPosition(t: number): Vector3
	local k = math.clamp((t - ballStart) / math.max(1e-3, ballEnd - ballStart), 0, 1)
	local ground = ballFrom:Lerp(ballTo, k)
	return ground + Vector3.new(0, BALL_HEIGHT + math.sin(t * 1.7) * BALL_BOB, 0)
end

local function ballActive(): boolean
	return event == "ball" and ballZone >= 1 and ballHp > 0 and ClientState.now() < ballEnd
end

local function updateHpBar(b: Ball)
	local max = math.max(1, ballMax)
	local hp = math.clamp(ballHp, 0, max)
	b.hpFill.Size = UDim2.fromScale(hp / max, 1)
	b.hpText.Text = Loc.t("ШАРОВАЯ МОЛНИЯ  %d/%d", hp, max)
end

local function buildBall(parent: Instance): Ball
	local model = Models.ballLightning()
	model.Name = "BallLightning"
	local core = model.PrimaryPart :: BasePart
	-- детали модели собраны вокруг (0, 0, 0): запоминаем смещения групп до переноса
	local shells: { BasePart } = {}
	local shellOffsets: { CFrame } = {}
	local shellBase: { number } = {}
	local spikes: { BasePart } = {}
	local spikeOffsets: { CFrame } = {}
	local orbiters: { BasePart } = {}
	local orbiterRot = CFrame.identity
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d ~= core then
			local name = d.Name
			if string.sub(name, 1, 5) == "Shell" then
				table.insert(shells, d)
				table.insert(shellOffsets, d.CFrame)
				table.insert(shellBase, d.Transparency)
			elseif string.sub(name, 1, 5) == "Spike" then
				table.insert(spikes, d)
				table.insert(spikeOffsets, d.CFrame)
			elseif string.sub(name, 1, 7) == "Orbiter" then
				table.insert(orbiters, d)
				orbiterRot = d.CFrame.Rotation
			end
		end
	end
	model:PivotTo(CFrame.new(ballPosition(ClientState.now())))

	local light = Instance.new("PointLight")
	light.Color = BALL_GOLD
	light.Range = LIGHT_RANGE
	light.Brightness = LIGHT_BRIGHTNESS
	light.Shadows = false
	light.Parent = core
	local sparks = sparkEmitter(core, BALL_GOLD)

	-- трескучие дуги: от центра к случайным точкам вокруг шара
	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = core
	local arcs: { Arc } = {}
	for i = 1, ARCS do
		local tip = Instance.new("Attachment")
		tip.Name = "ArcTip" .. i
		tip.Position = randomUnit() * ARC_REACH
		tip.Parent = core
		local beam = Instance.new("Beam")
		beam.Name = "Arc" .. i
		beam.Attachment0 = center
		beam.Attachment1 = tip
		beam.Color = ColorSequence.new(WHITE, BALL_ARC)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.8, 0.2),
			NumberSequenceKeypoint.new(1, 0.8),
		})
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 12
		beam.Width0 = 0.55
		beam.Width1 = 0.12
		beam.Parent = core
		table.insert(arcs, { beam = beam, tip = tip, nextAt = 0 })
	end

	-- полоска HP над шаром
	local gui = Instance.new("BillboardGui")
	gui.Name = "Hp"
	gui.Size = HP_SIZE
	gui.StudsOffsetWorldSpace = Vector3.new(0, GLOW_D / 2 + 3, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = HP_DISTANCE
	gui.ResetOnSpawn = false
	gui.Parent = core
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = HP_BG
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local hpScale = Instance.new("UIScale")
	hpScale.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = BALL_GOLD
	stroke.Thickness = 2
	stroke.Parent = panel
	local text = Instance.new("TextLabel")
	text.Name = "Title"
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, -16, 0.58, 0)
	text.Position = UDim2.fromOffset(8, 2)
	text.FontFace = Theme.FontDisplay -- заголовок плашки события: Montserrat Black Italic (§8.3.8)
	text.TextColor3 = Theme.Cream
	text.TextScaled = true
	text.Text = ""
	text.Parent = panel
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Theme.Ink
	textStroke.Thickness = 2
	textStroke.LineJoinMode = Enum.LineJoinMode.Round
	textStroke.Parent = text
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(1, -20, 0.26, 0)
	bar.Position = UDim2.new(0, 10, 0.64, 0)
	bar.BackgroundColor3 = Color3.fromRGB(50, 40, 30)
	bar.BorderSizePixel = 0
	bar.Parent = panel
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.5, 0)
	barCorner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 150, 40))
	grad.Parent = fill

	model.PrimaryPart = core
	model.Parent = parent
	local b: Ball = {
		model = model,
		core = core,
		shells = shells,
		shellOffsets = shellOffsets,
		shellBase = shellBase,
		spikes = spikes,
		spikeOffsets = spikeOffsets,
		orbiters = orbiters,
		orbiterRot = orbiterRot,
		light = light,
		sparks = sparks,
		center = center,
		arcs = arcs,
		hpFill = fill,
		hpText = text,
		hpScale = hpScale,
		lastHp = ballHp,
		hitFlash = 0,
		spikeAt = -math.huge,
		nextSpike = os.clock() + SPIKE_MIN,
		dyingSince = nil,
	}
	updateHpBar(b)
	return b
end

local function clearTethers()
	for _, t in tethers do
		t.part:Destroy()
	end
	table.clear(tethers)
end

-- Шар улетел сам: тает и поднимается в тучи
local function fadeBall(b: Ball)
	clearTethers()
	b.sparks.Enabled = false
	for _, a in b.arcs do
		a.beam.Enabled = false
	end
	local gui = b.core:FindFirstChild("Hp")
	if gui and gui:IsA("BillboardGui") then
		gui.Enabled = false
	end
	local rise = Vector3.new(0, FADE_RISE, 0)
	for _, p in b.model:GetChildren() do
		if p:IsA("BasePart") then
			tween(p, FADE_TIME, { Transparency = 1, CFrame = p.CFrame + rise }, Enum.EasingStyle.Sine)
		end
	end
	tween(b.light, FADE_TIME, { Brightness = 0 })
	Sounds.play("ThunderFar")
	task.delay(FADE_TIME + 0.1, function()
		b.model:Destroy()
	end)
end

local function updateBall(b: Ball, clock: number, t: number)
	local pos = ballPosition(t)
	local spin = clock * 1.3
	local base = CFrame.new(pos)
	b.core.CFrame = base * CFrame.Angles(spin * 0.6, spin, 0)
	-- оболочки крутятся навстречу друг другу: колючий силуэт всё время меняется
	local rotA = base * CFrame.Angles(0, -spin * 0.8, spin * 0.4)
	local rotB = base * CFrame.Angles(spin * 0.5, spin * 0.9, 0)
	for i, sh in b.shells do
		sh.CFrame = (if i == 1 then rotA else rotB) * b.shellOffsets[i]
	end
	for i, sp in b.spikes do
		sp.CFrame = rotA * b.spikeOffsets[i]
	end
	for i, o in b.orbiters do
		local a = spin * 1.6 + i * (math.pi * 2 / #b.orbiters)
		local tilt = math.sin(clock * 0.9 + i) * 0.6
		o.CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * ORBIT_R, math.sin(a * 0.5 + i) * ORBIT_R * tilt, math.sin(a) * ORBIT_R)) * CFrame.Angles(0, a * 2, 0) * b.orbiterRot
	end
	-- пульс: свет и свечение, вспышка оболочки после удара по шару
	local soft = settings()
	if clock >= b.nextSpike then
		b.nextSpike = clock + SPIKE_MIN + math.random() * (SPIKE_MAX - SPIKE_MIN)
		b.spikeAt = clock
	end
	local spike = math.max(0, 1 - (clock - b.spikeAt) / SPIKE_TIME) * SPIKE_AMOUNT * (if soft then 0.5 else 1)
	local pulse = 0.7 + 0.3 * math.sin(clock * 9) + spike
	local hit = math.clamp(1 - (clock - b.hitFlash) / 0.25, 0, 1)
	b.light.Brightness = LIGHT_BRIGHTNESS * pulse * (if soft then 0.7 else 1) + hit * 3
	-- оболочки «дышат», а после удара по шару вспыхивают
	for i, sh in b.shells do
		sh.Transparency = math.clamp(b.shellBase[i] + 0.05 * math.sin(clock * 5 + i) - 0.4 * hit, 0, 1)
	end
	-- дуги перескакивают на новые точки
	local holdMin = if soft then ARC_SOFT_HOLD_MIN else ARC_HOLD_MIN
	local holdMax = if soft then ARC_SOFT_HOLD_MAX else ARC_HOLD_MAX
	for _, a in b.arcs do
		if clock >= a.nextAt then
			a.nextAt = clock + holdMin + math.random() * (holdMax - holdMin)
			a.tip.Position = randomUnit() * ARC_REACH * (0.6 + 0.4 * math.random())
			a.beam.CurveSize0 = (math.random() * 2 - 1) * 4
			a.beam.CurveSize1 = (math.random() * 2 - 1) * 4
			a.beam.Enabled = soft or math.random() > 0.15
		end
	end
end

-- Привести шар в соответствие с атрибутами GameState
local function syncBall()
	local active = ballActive()
	local b = ball
	if active and not b then
		local f = folder
		if f then
			ball = buildBall(f)
		end
	elseif not active and b then
		if ballHp <= 0 then
			-- HP кончились: шар висит до прихода Effect ballBurst (взрыв), а если он не придёт
			-- (мы на другом острове) — тихо тает через BURST_WAIT
			if not b.dyingSince then
				b.dyingSince = os.clock()
				b.lastHp = 0
				updateHpBar(b)
			elseif os.clock() - (b.dyingSince :: number) >= BURST_WAIT then
				ball = nil
				fadeBall(b)
			end
		else
			-- время вышло (улетел)
			ball = nil
			fadeBall(b)
		end
	elseif b then
		if ballHp < b.lastHp then
			b.hitFlash = os.clock()
			b.hpScale.Scale = 1.12
			tween(b.hpScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		b.lastHp = ballHp
		updateHpBar(b)
	end
end

local function readGameState(gs: Instance)
	local e = gs:GetAttribute("Event")
	event = if typeof(e) == "string" then e else ""
	ballZone = attrNumber(gs, "BallZone")
	ballHp = attrNumber(gs, "BallHp")
	ballMax = attrNumber(gs, "BallMaxHp")
	ballFrom = attrVector(gs, "BallFrom")
	ballTo = attrVector(gs, "BallTo")
	ballStart = attrNumber(gs, "BallStart")
	ballEnd = attrNumber(gs, "BallEnd")
end

-- Нить от шара к его кольцу (пока кольцо не ударит)
local function addTether(msg: Net.StrikeMsg)
	local b = ball
	local f = folder
	if not b or not f or #msg.Hits == 0 then
		return
	end
	if #tethers >= TETHER_MAX then
		local old = table.remove(tethers, 1)
		if old then
			old.part:Destroy()
		end
	end
	local anchor = newPart("TetherEnd", Enum.PartType.Block, Enum.Material.SmoothPlastic, Vector3.one * 0.2, WHITE, 1, f)
	anchor.CFrame = CFrame.new(msg.Pos + Vector3.new(0, 0.3, 0))
	local att = Instance.new("Attachment")
	att.Parent = anchor
	local beam = Instance.new("Beam")
	beam.Attachment0 = b.center
	beam.Attachment1 = att
	beam.Color = ColorSequence.new(BALL_ARC, WHITE)
	beam.Transparency = NumberSequence.new(0.25, 0.6)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 16
	beam.Width0 = 0.7
	beam.Width1 = 0.25
	beam.Parent = anchor
	table.insert(tethers, { part = anchor, beam = beam, untilT = msg.Hits[1] + 0.2 })
end

local function updateTethers(t: number)
	for i = #tethers, 1, -1 do
		local th = tethers[i]
		if t >= th.untilT or not ball then
			th.part:Destroy()
			table.remove(tethers, i)
		else
			th.beam.CurveSize0 = (math.random() * 2 - 1) * 3
			th.beam.CurveSize1 = (math.random() * 2 - 1) * 3
		end
	end
end

-- Шар повержен: взрыв искр, свет, тряска, гром и победа
local function ballBurst(msg: Net.EffectMsg)
	local f = folder
	if not f then
		return
	end
	local b = ball
	local pos: Vector3
	if b then
		pos = b.core.Position
		ball = nil
		clearTethers()
		b.model:Destroy()
	elseif msg.Pos then
		pos = msg.Pos + Vector3.new(0, BALL_HEIGHT, 0)
	else
		return
	end
	local soft, shake = settings()
	local flash = newPart("Burst", Enum.PartType.Ball, Enum.Material.Neon, Vector3.one * CORE_D, BALL_CORE, 0.1, f)
	flash.CFrame = CFrame.new(pos)
	local wave = newPart("BurstWave", Enum.PartType.Ball, Enum.Material.ForceField, Vector3.one * SHELL_D, BALL_GOLD, 0.2, f)
	wave.CFrame = CFrame.new(pos)
	tween(flash, BURST_TIME, { Size = Vector3.one * BURST_SIZE * 0.6, Transparency = 1 })
	tween(wave, BURST_TIME * 1.4, { Size = Vector3.one * BURST_SIZE, Transparency = 1 })
	local light = Instance.new("PointLight")
	light.Color = BALL_GOLD
	light.Range = 60
	light.Brightness = if soft then 5 else 9
	light.Shadows = false
	light.Parent = flash
	tween(light, BURST_TIME * 1.2, { Brightness = 0 })
	local sparks = sparkEmitter(flash, BALL_GOLD)
	sparks.Enabled = false
	sparks.Speed = NumberRange.new(28, 60)
	sparks.Lifetime = NumberRange.new(0.8, 1.6)
	sparks.Drag = 2
	sparks:Emit(BURST_SPARKS)
	task.delay(2, function()
		flash:Destroy()
		wave:Destroy()
	end)
	if shake then
		Juice.shake(0.55)
		Juice.fovPunch(6)
	end
	Juice.flash(Theme.Gold, if soft then 0.25 else 0.45)
	Sounds.play("ThunderNear")
	Sounds.play("Victory")
end

----------------------------------------------------------------------
-- Радужная молния: вертикальный луч над кольцом
----------------------------------------------------------------------
local function addRainbowBeam(msg: Net.StrikeMsg)
	local f = folder
	if not f or #msg.Hits == 0 then
		return
	end
	local base = msg.Pos
	local cf = CFrame.new(base + Vector3.new(0, RAINBOW_BEAM_H / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local outer = newPart("RainbowBeam", Enum.PartType.Cylinder, Enum.Material.Neon, Vector3.new(RAINBOW_BEAM_H, RAINBOW_BEAM_W, RAINBOW_BEAM_W), WHITE, 0.45, f)
	outer.CFrame = cf
	local inner = newPart("RainbowCore", Enum.PartType.Cylinder, Enum.Material.Neon, Vector3.new(RAINBOW_BEAM_H, RAINBOW_BEAM_W * 0.35, RAINBOW_BEAM_W * 0.35), WHITE, 0.15, f)
	inner.CFrame = cf
	-- деталь со светом у основания луча (удаляется вместе с лучом)
	local glowAnchor = newPart("RainbowGlow", Enum.PartType.Block, Enum.Material.SmoothPlastic, Vector3.one * 0.2, WHITE, 1, outer)
	glowAnchor.CFrame = CFrame.new(base + Vector3.new(0, 3, 0))
	local light = Instance.new("PointLight")
	light.Range = 34
	light.Brightness = 0
	light.Shadows = false
	light.Parent = glowAnchor
	table.insert(rainbows, { outer = outer, inner = inner, light = light, hitAt = msg.Hits[1], born = os.clock() })
end

local function updateRainbows(clock: number, t: number)
	for i = #rainbows, 1, -1 do
		local r = rainbows[i]
		local hue = (clock * 0.35) % 1
		local color = Color3.fromHSV(hue, 0.6, 1)
		r.outer.Color = color
		r.light.Color = color
		local since = t - r.hitAt
		if since >= RAINBOW_FADE then
			r.outer:Destroy()
			r.inner:Destroy()
			table.remove(rainbows, i)
		else
			-- появляется за полсекунды, после удара тает
			local appear = math.clamp((clock - r.born) / 0.5, 0, 1)
			local fade = if since > 0 then since / RAINBOW_FADE else 0
			local pulse = 0.08 * math.sin(clock * 7)
			r.outer.Transparency = math.clamp(1 - appear * (0.55 + pulse) * (1 - fade), 0, 1)
			r.inner.Transparency = math.clamp(1 - appear * 0.85 * (1 - fade), 0, 1)
			r.light.Brightness = 2 * appear * (1 - fade)
		end
	end
end

----------------------------------------------------------------------
-- Подарки и «Я видел!»
----------------------------------------------------------------------
local function onHatchGift(msg: Net.EffectMsg)
	if msg.UserId ~= nil and msg.UserId ~= player.UserId then
		return
	end
	local kind = msg.Text
	local def = if kind then Pets.Kinds[kind] else nil
	if not def then
		return
	end
	local color = Pets.Rarities[def.Rarity].Color
	local root = localRoot()
	if root then
		Juice.popup(root.Position + Vector3.new(0, POPUP_UP, 0), Loc.t("🎁 %s!", def.Name), color, true)
	end
	Sounds.play("RareReveal")
	local soft = settings()
	Juice.flash(color, if soft then 0.15 else 0.3)
end

local function onWitness(msg: Net.EffectMsg)
	local root = localRoot()
	if root then
		local value = msg.Value
		local text = if value and value > 0 then Loc.t("☠ Я видел! +%s ⚡", Format.short(value)) else Loc.t("☠ Я видел!")
		Juice.popup(root.Position + Vector3.new(0, POPUP_UP, 0), text, Theme.Volt, true)
	end
	Sounds.play("Coins")
end

-- Молния оставила фульгурит (подробности — в тосте от сервера)
local function onFulgurite(msg: Net.StrikeResultMsg)
	Sounds.play("Fulgurite")
	-- 🔮 и сиреневый — не путать с 💎 осколком
	Juice.popup(msg.Pos + Vector3.new(0, 2, 0), Loc.t("🔮 Фульгурит!"), Theme.Purple:Lerp(Color3.new(1, 1, 1), 0.35), true)
end

----------------------------------------------------------------------
-- Запуск
----------------------------------------------------------------------

-- Киоски: подсказка с атрибутом Window открывает окно
local function setupPrompts()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player then
			return
		end
		local window = prompt:GetAttribute("Window")
		if typeof(window) == "string" and window ~= "" then
			ClientState.OpenWindow:Fire(window)
		end
	end)
end

local started = false
function EventFX.start()
	if started then
		return
	end
	started = true
	-- окна киосков — первыми и отдельно: если что-то ниже сломается, киоски всё равно работают
	local okPrompts, errPrompts = pcall(setupPrompts)
	if not okPrompts then
		warn("[EventFX] киоски: " .. tostring(errPrompts))
	end

	local f = Instance.new("Folder")
	f.Name = "EventFX"
	f.Parent = Workspace
	folder = f

	ClientState.Effect:Connect(function(msg: Net.EffectMsg)
		local kind = msg.Kind
		if kind == "ballBurst" then
			ballBurst(msg)
		elseif kind == "hatch" then
			onHatchGift(msg)
		elseif kind == "witness" then
			onWitness(msg)
		end
	end)
	ClientState.StrikeResolved:Connect(function(msg: Net.StrikeResultMsg)
		if msg.Fulg then
			onFulgurite(msg)
		end
	end)
	ClientState.StrikeSpawned:Connect(function(msg: Net.StrikeMsg)
		if msg.Tag == "rainbow" then
			addRainbowBeam(msg)
		elseif msg.Tag == "ball" then
			addTether(msg)
		end
	end)

	task.spawn(function()
		local gs = Net.gameState()
		readGameState(gs)
		syncBall()
		gs.AttributeChanged:Connect(function(name: string)
			local wasEvent = event
			readGameState(gs)
			-- у Радужной свой волшебный звук (WorldFX, Effect rainbowWarn)
			if name == "Event" and event ~= "" and event ~= "rainbow" and event ~= wasEvent then
				Sounds.play("EventStart")
			end
			syncBall()
		end)
	end)

	RunService.PreRender:Connect(function()
		local clock = os.clock()
		local t = ClientState.now()
		local b = ball
		if b then
			updateBall(b, clock, t)
			if not ballActive() then
				syncBall() -- время шара вышло или HP кончились
			end
		end
		if #tethers > 0 then
			updateTethers(t)
		end
		if #rainbows > 0 then
			updateRainbows(clock, t)
		end
	end)
end

return EventFX
