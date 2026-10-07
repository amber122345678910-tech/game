--!strict
-- Визуальные эффекты шторма (только клиент): град, кислотный дождь, тучи, молнии,
-- уровень кислоты (снаружи и внутри бункера), протечка у двери, обломки блоков.
-- Плотность эффектов подстраивается под качество графики и FPS.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer

local StormFX = {}

local FX_RANGE = 450 -- дальше этого расстояния эффекты чужих штормов не рисуем
local ACID_SLAB = Config.Plot.PitDepth + 2 -- высота плиты кислоты
local HAIL_POOL_SIZE = 140
local DEBRIS_POOL_SIZE = 60
local PARK = CFrame.new(0, -1000, 0)

local fxFolder: Folder
local qualityScale = 1

----------------------------------------------------------------------
-- Качество эффектов
----------------------------------------------------------------------
local fpsAverage = 60
local function updateQuality(dt: number)
	if dt > 0 then
		fpsAverage = fpsAverage * 0.97 + (1 / dt) * 0.03
	end
	local saved = 0
	local ok, value = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	if ok and typeof(value) == "number" then
		saved = value
	end
	local base = 1
	if saved >= 1 and saved <= 3 then
		base = 0.35
	elseif saved >= 4 and saved <= 6 then
		base = 0.7
	end
	if fpsAverage < 30 then
		base = math.min(base, 0.35)
	elseif fpsAverage < 45 then
		base = math.min(base, 0.6)
	end
	qualityScale = base
end

local function fxPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = PARK
	return p
end

----------------------------------------------------------------------
-- Град: пул шариков, двигаем все разом через BulkMoveTo
----------------------------------------------------------------------
type Hailstone = {
	part: Part,
	from: Vector3,
	to: Vector3,
	t0: number,
	duration: number,
	big: boolean,
	plotId: number,
}

local hailFree: { Part } = {}
local hailActive: { Hailstone } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local impactAttachment: Attachment
local impactEmitter: ParticleEmitter
local lastHailSound = 0

local function acquireHail(): Part?
	local p = table.remove(hailFree)
	return p
end

local function onHailBatch(plotId: number, impacts: { { number } })
	if typeof(plotId) ~= "number" or typeof(impacts) ~= "table" then
		return
	end
	local plot = ClientState.getPlotById(plotId)
	local origin = plot and ClientState.getOrigin(plot)
	local camera = workspace.CurrentCamera
	if not plot or not origin or not camera then
		return
	end
	if (camera.CFrame.Position - origin.Position).Magnitude > FX_RANGE then
		return
	end
	local now = os.clock()
	for i, impact in impacts do
		-- при низком качестве рисуем часть градин (урон считает сервер всё равно)
		if qualityScale < 1 and (i % 3 == 0) and qualityScale < 0.5 then
			continue
		end
		local lx, lz, ly, big = impact[1], impact[2], impact[3], impact[4]
		if typeof(lx) == "number" and typeof(lz) == "number" and typeof(ly) == "number" then
			local part = acquireHail()
			if part then
				local isBig = big == 1
				local size = if isBig then 1.6 else 0.7
				part.Size = Vector3.new(size, size, size)
				local to = origin:PointToWorldSpace(Vector3.new(lx, ly + size / 2, lz))
				local from = to + Vector3.new(4, Config.Storm.HailSpawnHeight, 2)
				table.insert(hailActive, {
					part = part,
					from = from,
					to = to,
					t0 = now,
					duration = Config.Storm.FallTime,
					big = isBig,
					plotId = plotId,
				})
			end
		end
	end
end

local function updateHail()
	local now = os.clock()
	table.clear(moveParts)
	table.clear(moveCFrames)
	local i = 1
	local soundBudget = 0
	while i <= #hailActive do
		local h = hailActive[i]
		local alpha = (now - h.t0) / h.duration
		if alpha >= 1 then
			-- удар
			impactAttachment.WorldPosition = h.to
			impactEmitter:Emit(if h.big then 8 else 3)
			if now - lastHailSound > 0.07 and soundBudget < 2 then
				lastHailSound = now
				soundBudget += 1
				Sounds.playAt("HailHit", h.to, if h.big then 1 else 0.5)
			end
			table.insert(moveParts, h.part)
			table.insert(moveCFrames, PARK)
			hailActive[i] = hailActive[#hailActive]
			hailActive[#hailActive] = nil
			table.insert(hailFree, h.part)
		else
			-- лёгкое ускорение при падении
			local eased = alpha * alpha * 0.4 + alpha * 0.6
			table.insert(moveParts, h.part)
			table.insert(moveCFrames, CFrame.new(h.from:Lerp(h.to, eased)))
			i += 1
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------
-- Обломки разрушенных блоков
----------------------------------------------------------------------
type Debris = {
	part: Part,
	pos: Vector3,
	vel: Vector3,
	t0: number,
	life: number,
	spin: CFrame,
}

local debrisFree: { Part } = {}
local debrisActive: { Debris } = {}
local rng = Random.new()

local function onBlockBroken(plotId: number, position: Vector3, color: Color3)
	if typeof(position) ~= "Vector3" then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - position).Magnitude > FX_RANGE then
		return
	end
	local count = math.max(2, math.floor(7 * qualityScale))
	for _ = 1, count do
		local part = table.remove(debrisFree)
		if not part then
			break
		end
		part.Color = if typeof(color) == "Color3" then color else Color3.new(0.5, 0.5, 0.5)
		local s = rng:NextNumber(0.6, 1.4)
		part.Size = Vector3.new(s, s, s)
		table.insert(debrisActive, {
			part = part,
			pos = position + Vector3.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(-1.5, 1.5), rng:NextNumber(-1.5, 1.5)),
			vel = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(10, 24), rng:NextNumber(-12, 12)),
			t0 = os.clock(),
			life = rng:NextNumber(0.7, 1.1),
			spin = CFrame.Angles(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3), rng:NextNumber(-3, 3)),
		})
	end
	Sounds.playAt("BlockBreak", position, 0.8)
	local _ = plotId
end

local function updateDebris(dt: number)
	if #debrisActive == 0 then
		return
	end
	table.clear(moveParts)
	table.clear(moveCFrames)
	local now = os.clock()
	local i = 1
	while i <= #debrisActive do
		local d = debrisActive[i]
		local age = now - d.t0
		if age >= d.life then
			table.insert(moveParts, d.part)
			table.insert(moveCFrames, PARK)
			table.insert(debrisFree, d.part)
			debrisActive[i] = debrisActive[#debrisActive]
			debrisActive[#debrisActive] = nil
		else
			d.vel += Vector3.new(0, -workspace.Gravity * 0.5 * dt, 0)
			d.pos += d.vel * dt
			local spinAngle = age * 6
			table.insert(moveParts, d.part)
			table.insert(moveCFrames, CFrame.new(d.pos) * CFrame.fromAxisAngle(Vector3.new(1, 1, 0).Unit, spinAngle))
			i += 1
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------
-- Эффекты одного участка (дождь, тучи, кислота, протечка)
----------------------------------------------------------------------
type AcidRect = {
	part: Part,
	lx0: number,
	lx1: number,
	lz0: number,
	lz1: number,
	shown: number,
}

type PlotFX = {
	model: Model,
	origin: CFrame,
	folder: Folder,
	rainPart: Part,
	rain: ParticleEmitter,
	sleet: ParticleEmitter,
	clouds: { Part },
	outside: { AcidRect },
	inside: { AcidRect },
	outsideLevel: number,
	insideLevel: number,
	layout: string,
	leakAttachments: { Attachment },
	leakEmitters: { ParticleEmitter },
	leakSound: Sound?,
	rainSound: Sound?,
	phase: string,
	rainWanted: boolean,
	sleetWanted: boolean,
	indoor: boolean,
}

local plotFx: { [Model]: PlotFX } = {}
local cameraIndoorPlot: Model? = nil
local roofParams = RaycastParams.new()
roofParams.FilterType = Enum.RaycastFilterType.Include

-- Под чьей крышей сейчас камера (луч вверх по блокам всех участков).
local function updateIndoor()
	cameraIndoorPlot = nil
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local result = workspace:Raycast(camera.CFrame.Position, Vector3.new(0, 80, 0), roofParams)
	if result then
		local plot = result.Instance:FindFirstAncestorWhichIsA("Model")
		if plot and plot:GetAttribute("PlotId") ~= nil then
			cameraIndoorPlot = plot
		end
	end
end

local function makeRain(parent: Part, color: Color3, rate: number, speed: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Speed = NumberRange.new(speed, speed * 1.15)
	e.Lifetime = NumberRange.new(0.8, 1.0)
	e.Size = NumberSequence.new(0.2)
	e.Squash = NumberSequence.new(2.5) -- > 0: капля узкая и вытянутая
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.35
	e.LightInfluence = 0.6
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.85, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rate = rate
	e.Enabled = false
	e.Parent = parent
	return e
end

local function parseRects(s: string): { { number } }
	local out = {}
	for chunk in string.gmatch(s, "[^;]+") do
		local a, b, c, d = string.match(chunk, "^(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)$")
		local n1, n2, n3, n4 = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
		if n1 and n2 and n3 and n4 then
			table.insert(out, { n1, n2, n3, n4 })
		end
	end
	return out
end

local function clearAcid(fx: PlotFX)
	for _, r in fx.outside do
		r.part:Destroy()
	end
	for _, r in fx.inside do
		r.part:Destroy()
	end
	table.clear(fx.outside)
	table.clear(fx.inside)
	fx.outsideLevel = 0
	fx.insideLevel = 0
end

local function buildAcid(fx: PlotFX, layout: string)
	clearAcid(fx)
	fx.layout = layout
	if layout == "" then
		return
	end
	local outsideStr, insideStr = string.match(layout, "^O:(.-)|I:(.*)$")
	local function make(rects: { { number } }, list: { AcidRect }, name: string)
		for _, r in rects do
			-- постоянный размер: двигаем только CFrame (дешевле, чем менять Size каждый кадр)
			local p = fxPart(name, Vector3.new(r[2] - r[1], ACID_SLAB, r[4] - r[3]), Config.AcidColor, Enum.Material.SmoothPlastic)
			p.Reflectance = 0.08
			p.Transparency = 1
			p.Parent = fx.folder
			table.insert(list, { part = p, lx0 = r[1], lx1 = r[2], lz0 = r[3], lz1 = r[4], shown = -1 })
		end
	end
	make(parseRects(outsideStr or ""), fx.outside, "AcidOutside")
	make(parseRects(insideStr or ""), fx.inside, "AcidInside")
end

local function setAcid(fx: PlotFX, list: { AcidRect }, level: number)
	for _, r in list do
		if math.abs(r.shown - level) > 0.01 then
			local visible = level >= 0.05
			local wasVisible = r.shown >= 0.05
			r.shown = level
			-- верх плиты = уровень кислоты, низ спрятан под полом котлована
			r.part.CFrame = fx.origin * CFrame.new((r.lx0 + r.lx1) / 2, level - ACID_SLAB / 2, (r.lz0 + r.lz1) / 2)
			if visible ~= wasVisible then
				r.part.Transparency = if visible then Config.AcidTransparency else 1
			end
		end
	end
end

local function refreshLeaks(fx: PlotFX)
	for _, a in fx.leakAttachments do
		a:Destroy()
	end
	table.clear(fx.leakAttachments)
	table.clear(fx.leakEmitters)
	local count = fx.model:GetAttribute("LeakCount")
	if typeof(count) ~= "number" then
		return
	end
	for i = 1, count do
		local cf = fx.model:GetAttribute("LeakCF" .. i)
		if typeof(cf) == "CFrame" then
			local att = Instance.new("Attachment")
			att.WorldCFrame = cf
			att.Parent = fx.rainPart
			local e = Instance.new("ParticleEmitter")
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.EmissionDirection = Enum.NormalId.Front
			e.SpreadAngle = Vector2.new(25, 10)
			e.Speed = NumberRange.new(6, 10)
			e.Acceleration = Vector3.new(0, -40, 0)
			e.Lifetime = NumberRange.new(0.5, 0.8)
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 0.15),
			})
			e.Color = ColorSequence.new(Config.AcidColor)
			e.LightEmission = 0.6
			e.LightInfluence = 0.4
			e.Rate = 30
			e.Parent = att
			table.insert(fx.leakAttachments, att)
			table.insert(fx.leakEmitters, e)
		end
	end
end

local function ensureFx(model: Model): PlotFX?
	local existing = plotFx[model]
	if existing then
		return existing
	end
	local origin = ClientState.getOrigin(model)
	if not origin then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "StormFX_" .. model.Name
	folder.Parent = fxFolder
	local half = Config.Plot.PitHalfSize
	local rainPart = fxPart("RainEmitter", Vector3.new(half * 2, 1, half * 2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	rainPart.Transparency = 1
	rainPart.CFrame = origin * CFrame.new(0, 62, 0)
	rainPart.Parent = folder
	local fx: PlotFX = {
		model = model,
		origin = origin,
		folder = folder,
		rainPart = rainPart,
		rain = makeRain(rainPart, Color3.fromRGB(150, 255, 90), 260, 75),
		sleet = makeRain(rainPart, Color3.fromRGB(220, 235, 255), 140, 90),
		clouds = {},
		outside = {},
		inside = {},
		outsideLevel = 0,
		insideLevel = 0,
		layout = "",
		leakAttachments = {},
		leakEmitters = {},
		leakSound = nil,
		rainSound = nil,
		phase = "",
		rainWanted = false,
		sleetWanted = false,
		indoor = false,
	}
	-- тучи над участком
	local cloudRng = Random.new(model:GetAttribute("PlotId") :: number? or 1)
	for _ = 1, 9 do
		local s = cloudRng:NextNumber(22, 36)
		local cloud = fxPart(
			"Cloud",
			Vector3.new(s * 1.6, s * 0.55, s),
			Color3.fromRGB(58, 62, 72),
			Enum.Material.SmoothPlastic
		)
		cloud.Shape = Enum.PartType.Ball
		cloud.CFrame = origin * CFrame.new(cloudRng:NextNumber(-34, 34), cloudRng:NextNumber(70, 80), cloudRng:NextNumber(-34, 34))
		cloud:SetAttribute("Home", cloud.CFrame)
		cloud.Transparency = 1
		cloud.Parent = folder
		table.insert(fx.clouds, cloud)
	end
	plotFx[model] = fx
	return fx
end

local function setPhaseFx(fx: PlotFX, phase: string)
	fx.phase = phase
	local stormOn = phase ~= ""
	for _, cloud in fx.clouds do
		cloud.Transparency = if stormOn then 0 else 1
	end
	local isAcid = phase == Config.Phases.Acid
	local isHail = phase == Config.Phases.Hail
	local cap = if ClientState.isTouch() then 90 else 300
	fx.rain.Rate = math.min(math.floor(300 * qualityScale), cap)
	fx.sleet.Rate = math.min(math.floor(120 * qualityScale), cap)
	fx.rainWanted = isAcid
	fx.sleetWanted = isHail
	fx.rain.Enabled = isAcid and not fx.indoor
	fx.sleet.Enabled = isHail and not fx.indoor
	if isAcid and not fx.rainSound then
		fx.rainSound = Sounds.loopAt("Rain", fx.rainPart, 0.6)
	elseif not isAcid and fx.rainSound then
		fx.rainSound:Destroy()
		fx.rainSound = nil
	end
	if not stormOn then
		clearAcid(fx)
		refreshLeaks(fx)
		if fx.leakSound then
			fx.leakSound:Destroy()
			fx.leakSound = nil
		end
	end
end

local function updatePlotFx(fx: PlotFX, dt: number)
	local model = fx.model
	local phase = model:GetAttribute("Phase")
	local p = if typeof(phase) == "string" then phase else ""
	if p ~= fx.phase then
		setPhaseFx(fx, p)
	end
	if p == "" then
		return
	end
	-- частицы не сталкиваются с крышей: если камера под крышей на этом участке — дождь выключаем
	local indoor = cameraIndoorPlot == model
	if indoor ~= fx.indoor then
		fx.indoor = indoor
		fx.rain.Enabled = fx.rainWanted and not indoor
		fx.sleet.Enabled = fx.sleetWanted and not indoor
		if indoor then
			fx.rain:Clear()
			fx.sleet:Clear()
		end
	end
	local layout = model:GetAttribute("AcidLayout")
	local l = if typeof(layout) == "string" then layout else ""
	if l ~= fx.layout then
		buildAcid(fx, l)
	end
	-- плавное приближение к серверному уровню кислоты
	local out = model:GetAttribute("OutsideAcid")
	local inn = model:GetAttribute("InsideAcid")
	local targetOut = if typeof(out) == "number" then out else 0
	local targetIn = if typeof(inn) == "number" then inn else 0
	local k = math.min(dt * 2.5, 1)
	fx.outsideLevel += (targetOut - fx.outsideLevel) * k
	fx.insideLevel += (targetIn - fx.insideLevel) * k
	setAcid(fx, fx.outside, fx.outsideLevel)
	setAcid(fx, fx.inside, fx.insideLevel)
	-- протечка
	local count = model:GetAttribute("LeakCount")
	local n = if typeof(count) == "number" then count else 0
	if n ~= #fx.leakEmitters then
		refreshLeaks(fx)
		if n > 0 and not fx.leakSound and #fx.leakAttachments > 0 then
			fx.leakSound = Sounds.loopAt("Leak", fx.leakAttachments[1], 0.8)
		elseif n == 0 and fx.leakSound then
			fx.leakSound:Destroy()
			fx.leakSound = nil
		end
	end
	local leak = model:GetAttribute("Leak")
	local intensity = if typeof(leak) == "number" then leak else 0
	for _, e in fx.leakEmitters do
		e.Rate = math.floor((15 + 60 * intensity) * math.max(qualityScale, 0.4))
	end
	-- медленный дрейф туч
	local t = os.clock()
	for i, cloud in fx.clouds do
		local home = cloud:GetAttribute("Home")
		if typeof(home) == "CFrame" then
			cloud.CFrame = home * CFrame.new(math.sin(t * 0.1 + i) * 6, 0, math.cos(t * 0.08 + i) * 6)
		end
	end
end

----------------------------------------------------------------------
-- Освещение (только у игрока, чей шторм идёт, или кто стоит на участке со штормом)
----------------------------------------------------------------------
local stormCC: ColorCorrectionEffect
local atmosphere: Atmosphere? = nil
local baseAtmosphereDensity = 0.28
local baseBrightness = 2.2
local lightingPhase = ""
local nextLightning = 0

local stormClouds: Clouds? = nil

local function applyLighting(phase: string)
	if phase == lightingPhase then
		return
	end
	lightingPhase = phase
	local clouds = stormClouds
	if clouds then
		local on = phase ~= ""
		clouds.Enabled = on
		clouds.Color = if phase == Config.Phases.Acid then Color3.fromRGB(120, 160, 90) else Color3.fromRGB(110, 115, 125)
	end
	local tint, brightness, saturation, density, sunBrightness
	if phase == Config.Phases.Hail or phase == Config.Phases.Prep then
		tint, brightness, saturation, density, sunBrightness = Color3.fromRGB(200, 212, 235), -0.08, -0.35, 0.45, 1.2
	elseif phase == Config.Phases.Calm then
		tint, brightness, saturation, density, sunBrightness = Color3.fromRGB(215, 222, 235), -0.04, -0.2, 0.38, 1.5
	elseif phase == Config.Phases.Acid then
		tint, brightness, saturation, density, sunBrightness = Color3.fromRGB(196, 255, 170), -0.1, -0.15, 0.5, 1.0
	elseif phase == Config.Phases.Clear then
		tint, brightness, saturation, density, sunBrightness = Color3.fromRGB(235, 240, 245), -0.02, -0.08, 0.34, 1.8
	else
		tint, brightness, saturation, density, sunBrightness = Color3.new(1, 1, 1), 0, 0, baseAtmosphereDensity, baseBrightness
	end
	UIKit.tween(stormCC, 2, { TintColor = tint, Brightness = brightness, Saturation = saturation })
	local atm = atmosphere
	if atm then
		UIKit.tween(atm, 2, { Density = density })
	end
	UIKit.tween(Lighting, 2, { Brightness = sunBrightness })
end

local function lightningFlash(fx: PlotFX)
	if GuiService.ReducedMotionEnabled then
		Sounds.playAt("Thunder", fx.rainPart.Position, 0.9)
		return
	end
	stormCC.Brightness = 0.55
	UIKit.tween(stormCC, 0.35, { Brightness = -0.08 })
	Sounds.playAt("Thunder", fx.rainPart.Position, 0.9)
end

local function currentLightingPlot(): PlotFX?
	-- мой шторм важнее всего
	local mine = ClientState.getPlotModel()
	if mine and plotFx[mine] and plotFx[mine].phase ~= "" then
		return plotFx[mine]
	end
	-- иначе — шторм участка, на котором я стою
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		for _, fx in plotFx do
			if fx.phase ~= "" then
				local lp = fx.origin:PointToObjectSpace(root.Position)
				local half = Config.Plot.PitHalfSize + 6
				if math.abs(lp.X) < half and math.abs(lp.Z) < half then
					return fx
				end
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
function StormFX.init()
	local existing = workspace:FindFirstChild("ClientFX")
	if existing and existing:IsA("Folder") then
		fxFolder = existing
	else
		fxFolder = Instance.new("Folder")
		fxFolder.Name = "ClientFX"
		fxFolder.Parent = workspace
	end

	stormCC = Instance.new("ColorCorrectionEffect")
	stormCC.Name = "StormColorCorrection"
	stormCC.Parent = Lighting
	-- облака Roblox работают только внутри Terrain; создаём локально и включаем на время шторма
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain and not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.85
		clouds.Density = 0.75
		clouds.Enabled = false
		clouds.Parent = terrain
		stormClouds = clouds
	end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		atmosphere = atm
		baseAtmosphereDensity = atm.Density
	end
	baseBrightness = Lighting.Brightness

	-- пулы
	for i = 1, HAIL_POOL_SIZE do
		local p = fxPart("Hail" .. i, Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(225, 240, 255), Enum.Material.Ice)
		p.Shape = Enum.PartType.Ball
		p.Parent = fxFolder
		table.insert(hailFree, p)
	end
	for i = 1, DEBRIS_POOL_SIZE do
		local p = fxPart("Debris" .. i, Vector3.new(1, 1, 1), Color3.new(0.5, 0.5, 0.5), Enum.Material.SmoothPlastic)
		p.Parent = fxFolder
		table.insert(debrisFree, p)
	end
	local impactPart = fxPart("ImpactFX", Vector3.new(1, 1, 1), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	impactPart.Transparency = 1
	impactPart.CFrame = CFrame.new()
	impactPart.Parent = fxFolder
	impactAttachment = Instance.new("Attachment")
	impactAttachment.Parent = impactPart
	impactEmitter = Instance.new("ParticleEmitter")
	impactEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	impactEmitter.Color = ColorSequence.new(Color3.fromRGB(230, 245, 255))
	impactEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	impactEmitter.Speed = NumberRange.new(6, 14)
	impactEmitter.SpreadAngle = Vector2.new(70, 70)
	impactEmitter.EmissionDirection = Enum.NormalId.Top
	impactEmitter.Acceleration = Vector3.new(0, -60, 0)
	impactEmitter.Lifetime = NumberRange.new(0.25, 0.45)
	impactEmitter.Rate = 0
	impactEmitter.LightEmission = 0.3
	impactEmitter.LightInfluence = 0.5
	impactEmitter.Parent = impactAttachment

	Remotes.HailBatch.OnClientEvent:Connect(onHailBatch)
	Remotes.BlockBroken.OnClientEvent:Connect(onBlockBroken)

	local plotsFolder = workspace:WaitForChild("Plots")
	local roofFolders: { Instance } = {}
	for _, child in plotsFolder:GetChildren() do
		local blocks = child:FindFirstChild("Blocks")
		if blocks then
			table.insert(roofFolders, blocks)
		end
	end
	roofParams.FilterDescendantsInstances = roofFolders
	local accumulator = 0
	RunService.PreRender:Connect(function(dt)
		updateQuality(dt)
		updateHail()
		updateDebris(dt)
		accumulator += dt
		if accumulator >= 0.2 then
			accumulator = 0
			updateIndoor()
		end
		local camera = workspace.CurrentCamera
		for _, child in plotsFolder:GetChildren() do
			if child:IsA("Model") then
				local phase = child:GetAttribute("Phase")
				local hasStorm = typeof(phase) == "string" and phase ~= ""
				local fx = plotFx[child]
				if hasStorm or (fx and fx.phase ~= "") then
					fx = ensureFx(child)
					if fx then
						local near = camera == nil or (camera.CFrame.Position - fx.origin.Position).Magnitude < FX_RANGE
						if near or fx.phase ~= "" then
							updatePlotFx(fx, dt)
						end
					end
				end
			end
		end
		-- освещение и молнии
		local lit = currentLightingPlot()
		applyLighting(if lit then lit.phase else "")
		if lit and lit.phase == Config.Phases.Hail and os.clock() >= nextLightning then
			nextLightning = os.clock() + rng:NextNumber(3, 7)
			lightningFlash(lit)
		end
		local _ = accumulator
	end)
end

return StormFX
