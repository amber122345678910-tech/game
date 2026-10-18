--!strict
-- Мир вокруг игрока: небо и освещение по зоне (плавно), дождь у камеры, далёкие вспышки в тучах,
-- дуги Тесла-башни в хабе, барьеры открытых островов, окна Электрограда (волной от центра),
-- настроение событий (Суперячейка, Шаровая, Радужная, Перун), музыка и фоновые звуки.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Zones = require(Shared:WaitForChild("Zones"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)
local Juice = require(script.Parent.Juice)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local WorldFX = {}

----------------------------------------------------------------------
-- Визуальные константы
----------------------------------------------------------------------
local SKY_TWEEN = 2
local RAIN_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local RAIN_COLOR = Color3.fromRGB(185, 205, 235)
local RAIN_SUPERCELL = 1.8 -- во время Суперячейки дождь сильнее
local RAIN_MAX = 420
local FLASH_RANGE = 60
local FLASH_PEAK = 5
local FLASH_TIME = 0.32
local TESLA_RANGE = 350 -- дуги башни видно, когда камера ближе
local CITY_WAVE = 1.6 -- окна квартала зажигаются за столько секунд волной от центра
local CITY_STAGGER = 0.4 -- следующий квартал — с задержкой
local WHITE = Color3.new(1, 1, 1)
local TESLA_CORE = Color3.fromRGB(235, 245, 255)
local TESLA_GLOW = Color3.fromRGB(110, 200, 255)
-- Суперячейка: зеленовато-чёрное небо
local SUPERCELL_SKY = {
	Ambient = Color3.fromRGB(50, 80, 62),
	OutdoorAmbient = Color3.fromRGB(85, 125, 95),
	AtmosphereColor = Color3.fromRGB(90, 140, 100),
	AtmosphereDecay = Color3.fromRGB(30, 60, 40),
	Tint = Color3.fromRGB(205, 255, 215),
	CloudColor = Color3.fromRGB(38, 58, 46),
}
local SUPERCELL_MIX = 0.6

type Sky = typeof(Config.Hub.Sky)

type FlashState = { part: Part, light: PointLight, t0: number, peak: number, active: boolean }

type TeslaArc = { core: Beam, glow: Beam }

type WindowRec = {
	part: BasePart,
	onColor: Color3,
	offColor: Color3,
	offMaterial: Enum.Material,
	lit: boolean,
	want: boolean,
	at: number,
	norm: number, -- 0 — ближе всех к центру, 1 — дальше всех (в своём квартале)
}

----------------------------------------------------------------------
-- Освещение
----------------------------------------------------------------------
local fxFolder = Instance.new("Folder")
fxFolder.Name = "WorldFX"
fxFolder.Parent = Workspace

local function findAtmosphere(): Atmosphere
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	if a then
		return a
	end
	local na = Instance.new("Atmosphere")
	na.Parent = Lighting
	return na
end

local function findColorCorrection(): ColorCorrectionEffect
	local c = Lighting:FindFirstChild("ColorCorrection")
	if c and c:IsA("ColorCorrectionEffect") then
		return c
	end
	local nc = Instance.new("ColorCorrectionEffect")
	nc.Name = "ColorCorrection"
	nc.Parent = Lighting
	return nc
end

local function findClouds(): Clouds
	local terrain = Workspace.Terrain
	local c = terrain:FindFirstChildOfClass("Clouds")
	if c then
		return c
	end
	local nc = Instance.new("Clouds")
	nc.Cover = 0.7
	nc.Density = 0.75
	nc.Parent = terrain
	return nc
end

local atmosphere: Atmosphere? = nil
local colorCorrection: ColorCorrectionEffect? = nil
local clouds: Clouds? = nil
local pulseCC: ColorCorrectionEffect? = nil -- свой эффект для вспышек (не мешает твину зоны)

local currentZone = 0
local currentEvent = ""

local function skyFor(zone: number): Sky
	if zone >= 1 and zone <= #Config.Zones then
		return Config.Zones[zone].Sky
	end
	return Config.Hub.Sky
end

local function tween(obj: Instance, time: number, props: { [string]: any })
	TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props):Play()
end

local function applySky(time: number)
	local sky = skyFor(currentZone)
	local ambient, outdoor = sky.Ambient, sky.OutdoorAmbient
	local atmoColor, atmoDecay = sky.AtmosphereColor, sky.AtmosphereDecay
	local density, haze = sky.Density, sky.Haze
	local tint, saturation, cloudColor = sky.Tint, sky.Saturation, sky.CloudColor
	if currentEvent == "supercell" then
		local k = SUPERCELL_MIX
		ambient = ambient:Lerp(SUPERCELL_SKY.Ambient, k)
		outdoor = outdoor:Lerp(SUPERCELL_SKY.OutdoorAmbient, k)
		atmoColor = atmoColor:Lerp(SUPERCELL_SKY.AtmosphereColor, k)
		atmoDecay = atmoDecay:Lerp(SUPERCELL_SKY.AtmosphereDecay, k)
		tint = tint:Lerp(SUPERCELL_SKY.Tint, k)
		cloudColor = cloudColor:Lerp(SUPERCELL_SKY.CloudColor, k)
		density += 0.06
		haze += 0.6
		saturation += 0.05
	end
	tween(Lighting, time, { Ambient = ambient, OutdoorAmbient = outdoor })
	local atmo = atmosphere
	if atmo then
		tween(atmo, time, { Color = atmoColor, Decay = atmoDecay, Density = density, Haze = haze })
	end
	local cc = colorCorrection
	if cc then
		tween(cc, time, { TintColor = tint, Saturation = saturation })
	end
	local cl = clouds
	if cl then
		tween(cl, time, { Color = cloudColor, Cover = if currentEvent == "supercell" then 0.82 else 0.7 })
	end
end

----------------------------------------------------------------------
-- Музыка и фоновые звуки
----------------------------------------------------------------------
local function applyAudio()
	local music: string
	if currentEvent == "supercell" or currentEvent == "ball" or currentEvent == "rainbow" then
		music = "Event"
	elseif currentZone == 0 then
		music = "Hub"
	elseif currentZone == #Config.Zones then
		music = "Storm"
	else
		music = "Zone"
	end
	Sounds.playMusic(music)
	local island = currentZone >= 1
	Sounds.setAmbient("Rain", island)
	Sounds.setAmbient("Rumble", island)
	Sounds.setAmbient("Wind", not island)
end

----------------------------------------------------------------------
-- Дождь у камеры
----------------------------------------------------------------------
local rainPart: Part? = nil
local rainEmitter: ParticleEmitter? = nil

local function qualityLevel(): number
	local ok, q = pcall(function(): any
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and typeof(q) == "EnumItem" then
		local v = (q :: any).Value
		if typeof(v) == "number" and v >= 1 and v <= 10 then
			return v
		end
	end
	return 6 -- «автоматически»
end

local function makeRain()
	local p = Instance.new("Part")
	p.Name = "Rain"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(90, 1, 90)
	p.Parent = fxFolder
	local e = Instance.new("ParticleEmitter")
	e.Name = "RainStreaks"
	e.Texture = RAIN_TEXTURE
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Speed = NumberRange.new(80, 100)
	e.Lifetime = NumberRange.new(0.6, 0.85)
	e.SpreadAngle = Vector2.new(4, 4)
	e.Acceleration = Vector3.new(4, -20, 2)
	e.Size = NumberSequence.new(0.14)
	e.Squash = NumberSequence.new(2.6)
	e.Color = ColorSequence.new(RAIN_COLOR)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.45),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	e.LightEmission = 0.25
	e.LightInfluence = 0.6
	e.Rate = 0
	e.Enabled = false
	e.Parent = p
	rainPart = p
	rainEmitter = e
end

local function applyRain()
	local e = rainEmitter
	if not e then
		return
	end
	if currentZone < 1 then
		e.Enabled = false
		return
	end
	local rate = 40 + 24 * qualityLevel()
	if UIKit.isPhone() then
		rate *= 0.6
	end
	if currentEvent == "supercell" then
		rate *= RAIN_SUPERCELL
	end
	e.Rate = math.min(RAIN_MAX, rate)
	e.Speed = if currentEvent == "supercell" then NumberRange.new(95, 120) else NumberRange.new(80, 100)
	e.Enabled = true
end

local function updateRain()
	local p = rainPart
	local cam = Workspace.CurrentCamera
	if not p or not cam or currentZone < 1 then
		return
	end
	local cf = cam.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local ahead = if look.Magnitude > 1e-3 then look.Unit * 18 else Vector3.zero
	p.CFrame = CFrame.new(cf.Position + Vector3.new(0, 30, 0) + ahead)
end

----------------------------------------------------------------------
-- Далёкие вспышки в тучах
----------------------------------------------------------------------
local flash: FlashState? = nil
local nextFlash = 0

local function makeFlash()
	local p = Instance.new("Part")
	p.Name = "SkyFlash"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.Parent = fxFolder
	local l = Instance.new("PointLight")
	l.Range = FLASH_RANGE
	l.Brightness = 0
	l.Shadows = false
	l.Enabled = false
	l.Parent = p
	flash = { part = p, light = l, t0 = 0, peak = 0, active = false }
end

local function scheduleFlash(clock: number)
	local lo, hi
	if currentEvent == "supercell" then
		lo, hi = 1.2, 3
	elseif currentZone >= 1 then
		lo, hi = 3, 7
	else
		lo, hi = 5, 10
	end
	nextFlash = clock + lo + (hi - lo) * math.random()
end

local function skyFlash(clock: number)
	local f = flash
	local cam = Workspace.CurrentCamera
	if not f or not cam then
		return
	end
	local a = math.random() * math.pi * 2
	local d = 70 + 100 * math.random()
	local y = Zones.groundY(math.max(0, currentZone)) + Config.CloudHeight - 6
	local camPos = cam.CFrame.Position
	f.part.CFrame = CFrame.new(camPos.X + math.cos(a) * d, y, camPos.Z + math.sin(a) * d)
	local d0 = ClientState.data
	local soft = d0 == nil or d0.Settings.SoftFlash
	f.peak = FLASH_PEAK * (if soft then 0.5 else 1)
	f.t0 = clock
	f.active = true
	f.light.Color = WHITE:Lerp(TESLA_GLOW, math.random() * 0.5)
	f.light.Enabled = true
	-- очень тихий далёкий гром — с задержкой, как в жизни
	task.delay(0.4 + d / 170, function()
		Sounds.play("ThunderFar", 0.9 + 0.2 * math.random(), 0.25)
	end)
end

local function updateFlash(clock: number)
	local f = flash
	if not f then
		return
	end
	if f.active then
		local t = clock - f.t0
		if t >= FLASH_TIME then
			f.active = false
			f.light.Enabled = false
			f.light.Brightness = 0
		else
			-- двойное мигание
			local b
			if t < 0.06 then
				b = 1
			elseif t < 0.11 then
				b = 0.1
			else
				b = 0.75 * (1 - (t - 0.11) / (FLASH_TIME - 0.11))
			end
			f.light.Brightness = f.peak * b
		end
	elseif clock >= nextFlash then
		scheduleFlash(clock)
		skyFlash(clock)
	end
end

----------------------------------------------------------------------
-- Карта: метки, барьеры, город
----------------------------------------------------------------------
local map: Instance? = nil

local function markers(): Instance?
	local m = map
	return if m then m:FindFirstChild("Markers") else nil
end

local function markerPart(name: string): BasePart?
	local mk = markers()
	local p = mk and mk:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

-- Тесла-башня: дуги от катушек к верху
local teslaArcs: { TeslaArc } = {}
local teslaOn = false
local nextTesla = 0
local teslaCenter: Vector3 = Zones.HubCenter

local function setupTesla()
	local top = markerPart("Tower_Top")
	if not top then
		return
	end
	teslaCenter = top.Position
	local topAtt = Instance.new("Attachment")
	topAtt.Name = "TeslaTop"
	topAtt.Parent = top
	for i = 1, 8 do
		local coil = markerPart("Tower_Coil_" .. i)
		if not coil then
			continue
		end
		local att = Instance.new("Attachment")
		att.Name = "TeslaCoil"
		att.Parent = coil
		local function beam(width: number, color: Color3, transp: number): Beam
			local b = Instance.new("Beam")
			b.Attachment0 = att
			b.Attachment1 = topAtt
			b.FaceCamera = true
			b.LightEmission = 1
			b.LightInfluence = 0
			b.Brightness = 3
			b.Segments = 12
			b.Width0 = width
			b.Width1 = width * 0.6
			b.Color = ColorSequence.new(color)
			b.Transparency = NumberSequence.new(transp)
			b.Enabled = false
			b.Parent = fxFolder
			return b
		end
		table.insert(teslaArcs, { core = beam(0.18, TESLA_CORE, 0), glow = beam(0.7, TESLA_GLOW, 0.4) })
	end
end

local function updateTesla(clock: number)
	if #teslaArcs == 0 then
		return
	end
	local cam = Workspace.CurrentCamera
	local near = cam ~= nil and (cam.CFrame.Position - teslaCenter).Magnitude < TESLA_RANGE
	if not near then
		if teslaOn then
			teslaOn = false
			for _, a in teslaArcs do
				a.core.Enabled = false
				a.glow.Enabled = false
			end
		end
		return
	end
	teslaOn = true
	if clock < nextTesla then
		return
	end
	nextTesla = clock + 0.06 + 0.07 * math.random()
	for _, a in teslaArcs do
		local on = math.random() < 0.82
		a.core.Enabled = on
		a.glow.Enabled = on
		if on then
			local c0 = (math.random() - 0.5) * 12
			local c1 = (math.random() - 0.5) * 12
			a.core.CurveSize0, a.core.CurveSize1 = c0, c1
			a.glow.CurveSize0, a.glow.CurveSize1 = c0, c1
			local w = 0.12 + 0.12 * math.random()
			a.core.Width0 = w
			a.glow.Width0 = w * 4
		end
	end
end

-- Барьеры: открытые острова — барьер прозрачный и проходимый (только у себя)
local gateOriginal: { [Instance]: { [string]: any } } = {}
local gatesAppliedFor = -1

local function setGateOpen(gate: Instance, open: boolean)
	local list = gate:GetDescendants()
	table.insert(list, gate)
	for _, d in list do
		local orig = gateOriginal[d]
		if d:IsA("BasePart") then
			if open then
				if not orig then
					gateOriginal[d] = { Transparency = d.Transparency, CanCollide = d.CanCollide }
				end
				d.Transparency = 1
				d.CanCollide = false
			elseif orig then
				d.Transparency = orig.Transparency
				d.CanCollide = orig.CanCollide
			end
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			if open then
				if not orig then
					gateOriginal[d] = { Enabled = d.Enabled }
				end
				d.Enabled = false
			elseif orig then
				d.Enabled = orig.Enabled
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Light") then
			if open then
				if not orig then
					gateOriginal[d] = { Enabled = d.Enabled }
				end
				d.Enabled = false
			elseif orig then
				d.Enabled = orig.Enabled
			end
		elseif d:IsA("Decal") then
			if open then
				if not orig then
					gateOriginal[d] = { Transparency = d.Transparency }
				end
				d.Transparency = 1
			elseif orig then
				d.Transparency = orig.Transparency
			end
		end
	end
end

local function applyGates(force: boolean)
	local d = ClientState.data
	local m = map
	if not d or not m then
		return
	end
	if not force and d.Zone == gatesAppliedFor then
		return
	end
	local gates = m:FindFirstChild("Gates")
	if not gates then
		return
	end
	gatesAppliedFor = d.Zone
	for n = 2, #Config.Zones do
		local g = gates:FindFirstChild("Gate_" .. n)
		if g then
			setGateOpen(g, n <= d.Zone)
		end
	end
end

-- Электроград: окна кварталов
local districts: { { WindowRec } } = {}
local pendingWindows: { [WindowRec]: boolean } = {}
local cityLit = -1

local function setupCity()
	local m = map
	local city = m and m:FindFirstChild("City")
	if not city then
		return
	end
	for k = 1, Config.City.Districts do
		local list: { WindowRec } = {}
		local folder = city:FindFirstChild("District_" .. k)
		if folder then
			local minD, maxD = math.huge, 0
			local dists: { number } = {}
			for _, d in folder:GetDescendants() do
				if d:IsA("BasePart") then
					local on = d:GetAttribute("OnColor")
					if typeof(on) == "Color3" then
						local dist = Zones.flatDist(d.Position, Zones.HubCenter)
						minD = math.min(minD, dist)
						maxD = math.max(maxD, dist)
						table.insert(list, {
							part = d,
							onColor = on,
							offColor = d.Color,
							offMaterial = d.Material,
							lit = false,
							want = false,
							at = 0,
							norm = 0,
						})
						table.insert(dists, dist)
					end
				end
			end
			local span = math.max(1, maxD - minD)
			for i, rec in list do
				rec.norm = (dists[i] - minD) / span
			end
		end
		districts[k] = list
	end
end

local function setWindow(rec: WindowRec, on: boolean)
	rec.lit = on
	if on then
		rec.part.Material = Enum.Material.Neon
		rec.part.Color = rec.onColor
	else
		rec.part.Material = rec.offMaterial
		rec.part.Color = rec.offColor
	end
end

local function applyCity(lit: number, instant: boolean)
	lit = math.clamp(math.floor(lit), 0, Config.City.Districts)
	local old = if cityLit < 0 then 0 else cityLit
	if lit == cityLit and not instant then
		return
	end
	cityLit = lit
	local clock = os.clock()
	for k, list in districts do
		local want = k <= lit
		local order = 0
		if want and k > old then
			order = k - old - 1 -- новые кварталы зажигаются по очереди
		elseif not want and k <= old then
			order = old - k -- гаснут с последнего
		end
		for _, rec in list do
			if instant then
				pendingWindows[rec] = nil
				rec.want = want
				if rec.lit ~= want then
					setWindow(rec, want)
				end
			elseif rec.want ~= want or rec.lit ~= want then
				rec.want = want
				-- зажигаются от центра наружу, гаснут снаружи внутрь
				local wave = if want then rec.norm else (1 - rec.norm)
				rec.at = clock + order * CITY_STAGGER + CITY_WAVE * wave
				pendingWindows[rec] = true
			end
		end
	end
end

local function updateCity(clock: number)
	local done: { WindowRec }? = nil
	for rec in pendingWindows do
		if clock >= rec.at then
			if rec.lit ~= rec.want then
				setWindow(rec, rec.want)
			end
			done = done or {}
			table.insert(done :: { WindowRec }, rec)
		end
	end
	if done then
		for _, rec in done do
			pendingWindows[rec] = nil
		end
	end
end

----------------------------------------------------------------------
-- Вспышки неба: Перун и Радужная
----------------------------------------------------------------------
local pulseGen = 0
local rainbowUntil = 0
local rainbowStart = 0

local function neutralPulse(time: number)
	local cc = pulseCC
	if cc then
		tween(cc, time, { TintColor = WHITE, Brightness = 0, Contrast = 0, Saturation = 0 })
	end
end

local function perun()
	local cc = pulseCC
	if not cc then
		return
	end
	pulseGen += 1
	local gen = pulseGen
	rainbowUntil = 0
	local d = ClientState.data
	local soft = d == nil or d.Settings.SoftFlash
	-- белая вспышка, потом тёмно-фиолетовое небо на 2 секунды
	cc.TintColor = WHITE
	cc.Brightness = if soft then 0.25 else 0.55
	cc.Contrast = 0
	TweenService:Create(cc, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		TintColor = Color3.fromRGB(150, 110, 220),
		Brightness = -0.2,
		Contrast = 0.15,
		Saturation = -0.1,
	}):Play()
	task.delay(2, function()
		if pulseGen == gen then
			neutralPulse(1.2)
		end
	end)
	Juice.flash(WHITE, if soft then 0.3 else 0.6)
	Sounds.play("Perun")
	if d and d.Settings.Shake then
		Juice.shake(0.85)
	end
end

local function rainbowWarn()
	pulseGen += 1
	rainbowStart = os.clock()
	rainbowUntil = rainbowStart + 3
	Sounds.play("Rainbow")
end

local function updateRainbow(clock: number)
	local cc = pulseCC
	if not cc or rainbowUntil <= 0 then
		return
	end
	if clock >= rainbowUntil then
		rainbowUntil = 0
		neutralPulse(0.6)
		return
	end
	local t = clock - rainbowStart
	local env = math.sin(math.pi * math.clamp(t / 3, 0, 1))
	cc.TintColor = WHITE:Lerp(Color3.fromHSV((t * 0.6) % 1, 1, 1), 0.28 * env)
	cc.Saturation = 0.25 * env
end

----------------------------------------------------------------------
-- Смена зоны и события
----------------------------------------------------------------------
local function refresh(time: number)
	applySky(time)
	applyAudio()
	applyRain()
end

local function readEvent(gs: Instance): string
	local e = gs:GetAttribute("Event")
	return if typeof(e) == "string" then e else ""
end

----------------------------------------------------------------------
-- Запуск
----------------------------------------------------------------------
local started = false
function WorldFX.start()
	if started then
		return
	end
	started = true
	atmosphere = findAtmosphere()
	colorCorrection = findColorCorrection()
	clouds = findClouds()
	local pcc = Instance.new("ColorCorrectionEffect")
	pcc.Name = "WorldPulse"
	pcc.TintColor = WHITE
	pcc.Parent = Lighting
	pulseCC = pcc
	makeRain()
	makeFlash()

	currentZone = ClientState.zone()
	refresh(0.5)
	scheduleFlash(os.clock())

	ClientState.ZoneChanged:Connect(function(zone: number)
		currentZone = zone
		refresh(SKY_TWEEN)
	end)
	ClientState.Changed:Connect(function()
		applyGates(false)
	end)
	ClientState.Effect:Connect(function(msg: Net.EffectMsg)
		local kind = (msg :: any).Kind
		if kind == "perun" then
			perun()
		elseif kind == "rainbowWarn" then
			rainbowWarn()
		elseif kind == "cityLit" then
			Sounds.play("CityLit")
		end
	end)

	-- общее состояние сервера: событие и огни города
	task.spawn(function()
		local gs = Net.gameState()
		currentEvent = readEvent(gs)
		refresh(SKY_TWEEN)
		gs:GetAttributeChangedSignal("Event"):Connect(function()
			local e = readEvent(gs)
			if e ~= currentEvent then
				currentEvent = e
				refresh(SKY_TWEEN)
				scheduleFlash(os.clock())
			end
		end)
		local function readLit(): number
			local v = gs:GetAttribute("CityLit")
			return if typeof(v) == "number" then v else 0
		end
		-- город настраивается, когда загрузится карта
		while #districts == 0 and not map do
			task.wait(0.5)
		end
		applyCity(readLit(), true)
		gs:GetAttributeChangedSignal("CityLit"):Connect(function()
			applyCity(readLit(), false)
		end)
	end)

	-- карта (метки, барьеры, город)
	task.spawn(function()
		local m = Workspace:WaitForChild("Map", 60)
		if not m then
			warn("[WorldFX] карта не найдена")
			return
		end
		m:WaitForChild("Markers", 10)
		setupCity()
		setupTesla()
		map = m
		applyGates(true)
	end)

	-- качество графики могло измениться в меню Roblox
	task.spawn(function()
		while true do
			task.wait(5)
			applyRain()
		end
	end)

	RunService.PreRender:Connect(function()
		local clock = os.clock()
		updateRain()
		updateFlash(clock)
		updateTesla(clock)
		updateCity(clock)
		updateRainbow(clock)
	end)
end

-- Текущее событие сервера ("" | "supercell" | "ball" | "rainbow")
function WorldFX.event(): string
	return currentEvent
end

return WorldFX
