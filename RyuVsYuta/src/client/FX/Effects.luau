--!strict
-- Эффекты катсцены, которые нельзя выразить позой:
--   туман: эмиттеры карты (слои), карточки-"занавесы" (FogCards), клочья у самого объектива;
--   глаз Рики: свечение поверх тумана (BillboardGui) + блик-вспышка, PointLight;
--   синяя проклятая энергия на помпадуре Рю: молнии (белое ядро + голубое свечение), искры, свет,
--   голубая подсветка волос (отдельный Highlight), всплеск на "дзынь";
--   пыль и кольцо пыли от тяжёлых толчков Рики.
--
-- Договорённости с моделями/картой (их создают строители в src/shared/Builders):
--   Workspace.Cutscene.Environment.FogEmitters — детали с ParticleEmitter; атрибуты BaseRate, Layer
--   Rika: деталь "Eye" (Neon), PointLight "EyeLight", детали "SoleL"/"SoleR"
--   Ryu:  деталь "EnergyAnchor" (у кончика помпадура, -Z вперёд), папка кости "Pompadour"

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Cutscene")
local Types = require(Shared:WaitForChild("Sequence"):WaitForChild("Types"))
local Timing = require(Shared:WaitForChild("Sequence"):WaitForChild("Timing"))
local MathX = require(Shared:WaitForChild("Math"))
local Textures = require(Shared:WaitForChild("Textures"))
local TextureLoader = require(script.Parent:WaitForChild("TextureLoader"))
local FogCards = require(script.Parent:WaitForChild("FogCards"))

local Effects = {}

type FogEmitter = { emitter: ParticleEmitter, base: number, layer: string }
type Arc = { core: Beam, glow: Beam, a0: Attachment, a1: Attachment, seed: number }

local fogEmitters: { FogEmitter } = {}
local fxFolder: Folder
local camRig: Part
local camWisps: ParticleEmitter
local camWispsNear: ParticleEmitter
local dustPart: Part
local dustBurst: ParticleEmitter
local dustRing: ParticleEmitter
local energy = {
	anchor = nil :: BasePart?,
	arcs = {} :: { Arc },
	sparks = nil :: ParticleEmitter?,
	glow = nil :: ParticleEmitter?,
	burst = nil :: ParticleEmitter?,
	light = nil :: PointLight?,
	hairGlow = nil :: Highlight?,
}
local eye = {
	part = nil :: BasePart?,
	light = nil :: PointLight?,
	baseColor = Color3.fromRGB(226, 36, 48),
	gui = nil :: BillboardGui?,
	glow = nil :: ImageLabel?,
	flare = nil :: ImageLabel?,
}
local speed = 1
local paused = false
local lastArcTick = -1

local function findDeep(root: Instance, name: string): Instance?
	return root:FindFirstChild(name, true)
end

local function makeEmitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e: any = Instance.new("ParticleEmitter")
	for k, v in props do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function invisiblePart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = fxFolder
	return p
end

-- Безопасно выставить свойство (на случай, если в какой-то версии клиента его нет)
local function trySet(inst: Instance, prop: string, value: any)
	pcall(function()
		(inst :: any)[prop] = value
	end)
end

local function setTexture(e: ParticleEmitter, key: string)
	e.Texture = TextureLoader.get(key)
	local tex = Textures.hq[key]
	if tex and tex.flipbook and TextureLoader.isHQ(key) then
		trySet(e, "FlipbookLayout", (Enum.ParticleFlipbookLayout :: any)[tex.flipbook])
		trySet(e, "FlipbookMode", Enum.ParticleFlipbookMode.OneShot)
		trySet(e, "FlipbookStartRandom", true)
	end
end

-- Когда качественные текстуры загрузились — подставить их вместо встроенных
local function upgradeTextures()
	for _, f in fogEmitters do
		local key = Textures.fogLayer[f.layer]
		if key and TextureLoader.isHQ(key) then
			setTexture(f.emitter, key)
			trySet(f.emitter, "Brightness", 1.25)
		end
	end
	setTexture(camWisps, "softFog")
	setTexture(camWispsNear, "wisps")
	setTexture(dustBurst, "dustBurst")
	setTexture(dustRing, "dustRing")
	if energy.sparks then
		setTexture(energy.sparks, "sparkStreak")
	end
	if energy.glow then
		setTexture(energy.glow, "radialGlow")
	end
	if energy.burst then
		setTexture(energy.burst, "electricBurst")
	end
	if eye.glow then
		eye.glow.Image = TextureLoader.get("radialGlow")
	end
	if eye.flare then
		eye.flare.Image = TextureLoader.get("flare")
	end
end

local function initFog(stage: Instance)
	local env = stage:FindFirstChild("Environment")
	local fogFolder = env and env:FindFirstChild("FogEmitters")
	if fogFolder then
		for _, d in fogFolder:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				local base = d:GetAttribute("BaseRate")
				local layer = d:GetAttribute("Layer")
				table.insert(fogEmitters, {
					emitter = d,
					base = if type(base) == "number" then base else d.Rate,
					layer = if type(layer) == "string" then layer else "bank",
				})
			end
		end
	end

	-- клочья тумана у объектива: эмиттер в ~30 стадах перед камерой выпускает их к камере
	camRig = invisiblePart("CameraWisps", Vector3.new(60, 26, 6))
	camWisps = makeEmitter(camRig, {
		Name = "Wisps",
		Texture = Textures.smoke,
		Rate = 0,
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(25, 10),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 22) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(0.7, 0.65),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(214, 220, 240), Color3.fromRGB(184, 192, 224)),
		LightEmission = 0.05,
		LightInfluence = 0.5,
		Brightness = 1.2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-12, 12),
		Drag = 0.4,
		EmissionDirection = Enum.NormalId.Front,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	camWispsNear = makeEmitter(camRig, {
		Name = "NearWisps",
		Texture = Textures.smoke,
		Rate = 0,
		Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(40, 15),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 11) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(226, 230, 246)),
		LightInfluence = 0.4,
		Brightness = 1.2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		EmissionDirection = Enum.NormalId.Front,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})

	-- пыль от толчков Рики: облако + плоское кольцо по земле
	dustPart = invisiblePart("StepDust", Vector3.new(3, 0.2, 3))
	dustBurst = makeEmitter(dustPart, {
		Name = "Dust",
		Texture = Textures.smoke,
		Rate = 0,
		Lifetime = NumberRange.new(2.2, 3.6),
		Speed = NumberRange.new(9, 16),
		SpreadAngle = Vector2.new(85, 5),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 9) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.6, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(200, 204, 222), Color3.fromRGB(170, 172, 196)),
		LightInfluence = 0.7,
		Drag = 3.2,
		Acceleration = Vector3.new(0, 1.2, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
	})
	dustRing = makeEmitter(dustPart, {
		Name = "DustRing",
		Texture = Textures.ring,
		Rate = 0,
		Lifetime = NumberRange.new(0.9, 1.1),
		Speed = NumberRange.new(0.01, 0.01),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 16) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(196, 202, 226)),
		LightInfluence = 0.6,
		EmissionDirection = Enum.NormalId.Top,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		ZOffset = 0.3,
	})
end

local function initEye(rika: Instance)
	local e = findDeep(rika, "Eye")
	if e and e:IsA("BasePart") then
		eye.part = e
		eye.baseColor = e.Color
		-- свечение рисуется поверх тумана (в аниме глаз горит сквозь дым)
		local gui = Instance.new("BillboardGui")
		gui.Name = "EyeGlow"
		gui.Size = UDim2.fromScale(3.2, 3.2)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Adornee = e
		gui.Parent = fxFolder
		local glow = Instance.new("ImageLabel")
		glow.Name = "Glow"
		glow.BackgroundTransparency = 1
		glow.Size = UDim2.fromScale(1, 1)
		glow.Image = TextureLoader.get("radialGlow")
		glow.ImageColor3 = Color3.fromRGB(255, 52, 64)
		glow.ImageTransparency = 1
		glow.Parent = gui
		local flare = Instance.new("ImageLabel")
		flare.Name = "Flare"
		flare.BackgroundTransparency = 1
		flare.AnchorPoint = Vector2.new(0.5, 0.5)
		flare.Position = UDim2.fromScale(0.5, 0.5)
		flare.Size = UDim2.fromScale(4, 1.2)
		flare.Image = TextureLoader.get("flare")
		flare.ImageColor3 = Color3.fromRGB(255, 120, 120)
		flare.ImageTransparency = 1
		flare.Parent = gui
		eye.gui = gui
		eye.glow = glow
		eye.flare = flare
	end
	local l = findDeep(rika, "EyeLight")
	if l and l:IsA("PointLight") then
		eye.light = l
	end
end

local function newArcBeam(name: string, a0: Attachment, a1: Attachment, parent: Instance, core: boolean): Beam
	local b = Instance.new("Beam")
	b.Name = name
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.Segments = 1
	b.LightInfluence = 0
	b.LightEmission = 1
	b.Brightness = if core then 6 else 3
	b.Color = if core
		then ColorSequence.new(Color3.fromRGB(230, 255, 255), Color3.fromRGB(200, 250, 255))
		else ColorSequence.new(Color3.fromRGB(110, 225, 245), Color3.fromRGB(70, 180, 220))
	b.Transparency = NumberSequence.new(1)
	b.Width0 = if core then 0.045 else 0.2
	b.Width1 = if core then 0.02 else 0.1
	b.ZOffset = if core then 0.02 else 0
	b.Parent = parent
	return b
end

local function initEnergy(ryu: Instance)
	local anchor = findDeep(ryu, "EnergyAnchor")
	if not (anchor and anchor:IsA("BasePart")) then
		warn("[Cutscene] Ryu EnergyAnchor not found")
		return
	end
	energy.anchor = anchor
	local holder = invisiblePart("EnergyHolder", Vector3.new(0.2, 0.2, 0.2))
	holder.CFrame = CFrame.new()
	-- молнии: ломаные из 3 отрезков (4 точки), у каждого отрезка ядро и свечение
	for i = 1, 8 do
		local prev: Attachment? = nil
		for j = 1, 4 do
			local a = Instance.new("Attachment")
			a.Name = string.format("Arc%d_%d", i, j)
			a.Parent = holder
			if prev then
				local seg: Arc = {
					core = newArcBeam(string.format("Arc%d_%d_Core", i, j), prev, a, holder, true),
					glow = newArcBeam(string.format("Arc%d_%d_Glow", i, j), prev, a, holder, false),
					a0 = prev,
					a1 = a,
					seed = i * 3.71 + j * 0.53,
				}
				table.insert(energy.arcs, seg)
			end
			prev = a
		end
	end
	local att = Instance.new("Attachment")
	att.Name = "EnergyCore"
	att.Parent = anchor
	energy.sparks = makeEmitter(att, {
		Name = "Sparks",
		Texture = Textures.spark,
		Rate = 0,
		Lifetime = NumberRange.new(0.15, 0.4),
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(Color3.fromRGB(200, 250, 255), Color3.fromRGB(80, 210, 255)),
		LightEmission = 1,
		Brightness = 6,
		Drag = 6,
		Squash = NumberSequence.new(1.5),
	})
	energy.glow = makeEmitter(att, {
		Name = "Glow",
		Texture = Textures.glow,
		Rate = 0,
		Lifetime = NumberRange.new(0.12, 0.25),
		Speed = NumberRange.new(0, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 2.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(110, 230, 255)),
		LightEmission = 1,
		Brightness = 3,
		LockedToPart = true,
	})
	energy.burst = makeEmitter(att, {
		Name = "Burst",
		Texture = Textures.spark,
		Rate = 0,
		Lifetime = NumberRange.new(0.25, 0.35),
		Speed = NumberRange.new(0, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(207, 251, 255), Color3.fromRGB(80, 200, 235)),
		LightEmission = 1,
		Brightness = 5,
		Rotation = NumberRange.new(0, 360),
		LockedToPart = true,
	})
	local light = Instance.new("PointLight")
	light.Name = "EnergyLight"
	light.Color = Color3.fromRGB(96, 226, 255)
	light.Brightness = 0
	light.Range = 10
	light.Shadows = false
	light.Parent = att
	energy.light = light

	-- голубая подсветка волос: детали кости Pompadour — в отдельную модель со своим Highlight
	local pompFolder: Instance? = nil
	for _, d in ryu:GetDescendants() do
		if d:IsA("Folder") and d.Name == "Pompadour" then
			pompFolder = d
			break
		end
	end
	if pompFolder then
		local m = Instance.new("Model")
		m.Name = "PompadourGlow"
		m.Parent = pompFolder.Parent
		for _, d in pompFolder:GetChildren() do
			if d:IsA("BasePart") then
				d.Parent = m
			end
		end
		local h = Instance.new("Highlight")
		h.Name = "EnergyHairGlow"
		h.FillColor = Color3.fromRGB(79, 211, 230)
		h.OutlineColor = Color3.fromRGB(20, 18, 26)
		h.FillTransparency = 1
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = m
		energy.hairGlow = h
	end
end

function Effects.init()
	local stage = Workspace:WaitForChild("Cutscene")
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "RuntimeFX"
	fxFolder.Parent = stage
	initFog(stage)
	FogCards.init(fxFolder)
	local chars = stage:FindFirstChild("Characters")
	local rika = chars and chars:FindFirstChild("Rika")
	if rika then
		initEye(rika)
	end
	local ryu = chars and chars:FindFirstChild("Ryu")
	if ryu then
		initEnergy(ryu)
	end
	TextureLoader.onReady(upgradeTextures)
	TextureLoader.start()
end

-- Зигзаг молнии: ломаная по передней части помпадура, перерисовывается ~15 раз в секунду
local function updateArcs(level: number, flash: number, t: number)
	local anchor = energy.anchor
	if not anchor then
		return
	end
	local cf = anchor.CFrame
	local tick = math.floor(t * 15)
	local reroll = tick ~= lastArcTick
	lastArcTick = tick
	local perArc = 3
	local arcCount = #energy.arcs // perArc
	local active = math.floor(level * arcCount + 0.5)
	-- до вспышки разряды только у кончика, на вспышке — по всей передней части и макушке
	local spreadMul = 0.35 + 0.65 * math.clamp(flash * 2 + (level - 0.4), 0, 1)
	for i = 1, arcCount do
		local on = i <= active
		local first = energy.arcs[(i - 1) * perArc + 1]
		if on and reroll then
			local function h(k: number): number
				return MathX.hash01(tick * 13.1 + first.seed * 7.7 + k) * 2 - 1
			end
			-- точки ломаной: старт у переднего края, дальше вверх-назад по волосам со случайным изломом
			local p = Vector3.new(h(1) * 0.7, h(2) * 0.25, h(3) * 0.25) * spreadMul
			local dir = Vector3.new(h(4) * 0.9, 0.35 + math.abs(h(5)) * 0.5, 0.2 + math.abs(h(6)) * 0.6).Unit
			local pts = { p }
			for j = 1, perArc do
				local stepLen = (0.22 + 0.2 * math.abs(h(10 + j))) * (0.6 + spreadMul)
				p = p + dir * stepLen + Vector3.new(h(20 + j), h(30 + j), h(40 + j)) * 0.14
				table.insert(pts, p)
			end
			for j = 1, perArc do
				local seg = energy.arcs[(i - 1) * perArc + j]
				seg.a0.WorldPosition = cf:PointToWorldSpace(pts[j])
				seg.a1.WorldPosition = cf:PointToWorldSpace(pts[j + 1])
			end
		end
		local flick = if on then (0.1 + 0.45 * MathX.hash01(tick * 5.3 + i)) else 1
		local tr = if on then math.clamp(flick - flash * 0.3, 0, 1) else 1
		for j = 1, perArc do
			local seg = energy.arcs[(i - 1) * perArc + j]
			seg.core.Transparency = NumberSequence.new(tr)
			seg.glow.Transparency = NumberSequence.new(math.min(1, tr + 0.25))
			local wide = 1 + flash * 1.2
			seg.glow.Width0 = 0.2 * wide
			seg.glow.Width1 = 0.1 * wide
		end
	end
	if energy.sparks then
		energy.sparks.Rate = level * 70 + flash * 260
	end
	if energy.glow then
		energy.glow.Rate = if level > 0.05 then 30 + flash * 60 else 0
	end
	if energy.light then
		local flick = 0.75 + 0.25 * math.noise(t * 23, 1.7, 0.31)
		energy.light.Brightness = (level * 3.2 + flash * 9) * flick
		energy.light.Range = 8 + flash * 8
	end
	if energy.hairGlow then
		-- голубая заливка волос мерцает на вспышке
		local g = math.clamp(level * 0.45 + flash * 0.6, 0, 0.6)
		local flicker = 0.75 + 0.25 * MathX.hash01(tick * 2.7)
		energy.hairGlow.FillTransparency = 1 - g * flicker
	end
end

function Effects.update(frame: Types.Frame, t: number)
	local fx = frame.fx
	local ts = if paused then 0 else speed
	-- туман карты: множитель густоты по слоям
	local fogMul = fx.fog or 1
	for _, f in fogEmitters do
		local layerMul = fx["fog_" .. f.layer] or 1
		f.emitter.Rate = f.base * fogMul * layerMul
		f.emitter.TimeScale = ts
	end
	FogCards.update(frame, t)
	-- клочья у камеры
	camRig.CFrame = frame.camera.cf * CFrame.new(0, -2, -34) * CFrame.Angles(0, math.pi, 0)
	camWisps.Rate = (fx.wisps or 0) * 14
	camWispsNear.Rate = (fx.wispsNear or 0) * 10
	camWisps.TimeScale = ts
	camWispsNear.TimeScale = ts
	dustBurst.TimeScale = ts
	dustRing.TimeScale = ts

	-- глаз Рики
	local glow = fx.eyeGlow or 0
	if eye.part then
		eye.part.Color = Color3.new(0.25, 0.03, 0.05):Lerp(eye.baseColor, math.clamp(0.3 + glow * 0.7, 0, 1))
	end
	if eye.light then
		eye.light.Brightness = glow * 4
		eye.light.Range = 6 + glow * 10
	end
	local eyeGui, eyeGlow, eyeFlare = eye.gui, eye.glow, eye.flare
	if eyeGui and eyeGlow and eyeFlare then
		local inShot = frame.shotName == "A" or frame.shotName == "Menu"
		eyeGui.Enabled = inShot and glow > 0.01
		eyeGlow.ImageTransparency = 1 - math.clamp(glow * 0.75, 0, 0.85)
		local flash = if frame.shotName == "Menu" then 0 else MathX.window(frame.t, Timing.eyeOn - 0.05, Timing.eyeOn + 0.9, 0.06, 0.8)
		eyeFlare.ImageTransparency = 1 - flash * 0.9
		eyeFlare.Size = UDim2.fromScale(2 + 4 * flash, 0.8 + 0.5 * flash)
	end

	updateArcs(math.clamp(fx.energy or 0, 0, 1), math.clamp(fx.energyFlash or 0, 0, 1), t)
	if energy.sparks then
		energy.sparks.TimeScale = ts
	end
	if energy.burst then
		energy.burst.TimeScale = ts
	end
end

function Effects.trigger(name: string, args: { [string]: any }?)
	local a: { [string]: any } = args or {}
	if name == "stepDust" then
		local stage = Workspace:FindFirstChild("Cutscene")
		local chars = stage and stage:FindFirstChild("Characters")
		local who = chars and chars:FindFirstChild(tostring(a.char or "Rika"))
		local sole = who and findDeep(who, if a.foot == "R" then "SoleR" else "SoleL")
		if sole and sole:IsA("BasePart") then
			local scale = if type(a.scale) == "number" then a.scale else 1
			dustPart.Size = Vector3.new(3 * scale, 0.2, 3 * scale)
			dustPart.CFrame = CFrame.new(sole.Position.X, 0.25, sole.Position.Z)
			dustBurst:Emit(math.floor(22 * scale))
			dustRing:Emit(1)
		end
	elseif name == "zingBurst" then
		if energy.burst then
			energy.burst:Emit(2)
		end
		if energy.sparks then
			energy.sparks:Emit(40)
		end
	elseif name == "fogBurst" then
		camWispsNear:Emit(if type(a.count) == "number" then a.count else 10)
	end
end

function Effects.reset(_t: number)
	camWisps:Clear()
	camWispsNear:Clear()
	dustBurst:Clear()
	dustRing:Clear()
	if energy.sparks then
		energy.sparks:Clear()
	end
	if energy.burst then
		energy.burst:Clear()
	end
	lastArcTick = -1
end

function Effects.setPaused(p: boolean)
	paused = p
end

function Effects.setSpeed(s: number)
	speed = s
end

return Effects
