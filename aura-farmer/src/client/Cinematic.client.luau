--!strict
-- Проигрыватель ролика «Aura Farmer» (клиент). Нажми Play (F5) в Studio — ролик пойдёт сам.
--
-- Управление: Пробел — пауза, R — заново, ←/→ — перемотка на 1 с, 1..9, 0, - — к планам S01..S11,
--             T — субтитры вкл/выкл, B — рамка 16:9, L — повтор по кругу, H — подсказка/таймкод.
-- Музыка: вставь SoundId в SoundService > AuraFarmerMusic. Тогда ролик идёт строго по времени трека.
--         Атрибут StartOffset у звука — с какой секунды трека начинается ролик (по умолчанию 0).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")

local AF = ReplicatedStorage:WaitForChild("AuraFarmer")
local Anim = AF:WaitForChild("Anim")
local Config = require(AF:WaitForChild("Config"))
local Timeline = require(AF:WaitForChild("Timeline"))
local Presets = require(AF:WaitForChild("Presets"))
local Lyrics = require(AF:WaitForChild("Lyrics"))
local CameraTrack = require(AF:WaitForChild("CameraTrack"))
local KFS = require(Anim:WaitForChild("KFS"))
local FK = require(Anim:WaitForChild("FK"))
local Effects = require(script.Parent:WaitForChild("Effects"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ===== Интерфейс =====
local gui = Instance.new("ScreenGui")
gui.Name = "AuraFarmerUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.ScreenInsets = Enum.ScreenInsets.None
gui.Parent = player:WaitForChild("PlayerGui")

local function frame(name: string, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	f.Parent = gui
	return f
end

local flash = frame("Flash", Color3.new(1, 1, 1), 5)
flash.Visible = false
local black = frame("Black", Color3.new(0, 0, 0), 20)
local loading = Instance.new("TextLabel")
loading.BackgroundTransparency = 1
loading.Size = UDim2.fromScale(1, 1)
loading.Text = "AURA FARMER — загрузка…"
loading.TextColor3 = Color3.fromRGB(255, 214, 64)
loading.FontFace = Font.fromEnum(Enum.Font.Bangers)
loading.TextSize = 36
loading.ZIndex = 21
loading.Parent = black

local barTop = frame("LetterboxTop", Color3.new(0, 0, 0), 15)
local barBottom = frame("LetterboxBottom", Color3.new(0, 0, 0), 15)
barTop.Visible = false
barBottom.Visible = false

-- Субтитры как в клипе: жирный узкий курсив, градиент жёлтый -> оранжевый -> красный,
-- сплошная тёмно-малиновая «выдавленная» тень вниз-вправо, без обводки, лёгкое медленное покачивание.
local SUB_FONT = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
local SUB_EXTRUDE_STEPS = 6
local subRoot = Instance.new("Frame")
subRoot.Name = "Subtitle"
subRoot.BackgroundTransparency = 1
subRoot.AnchorPoint = Vector2.new(0.5, 0.5)
subRoot.Position = UDim2.fromScale(0.5, 0.923)
subRoot.Size = UDim2.fromScale(1, 0.1)
subRoot.ZIndex = 10
subRoot.Parent = gui
local function subLabel(name: string, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.5)
	l.Size = UDim2.fromScale(1, 1)
	l.FontFace = SUB_FONT
	l.TextScaled = false
	l.Text = ""
	l.ZIndex = z
	l.Parent = subRoot
	return l
end
local subExtrude: { TextLabel } = {}
for i = 1, SUB_EXTRUDE_STEPS do
	local l = subLabel("Extrude" .. i, 10)
	l.TextColor3 = Color3.fromRGB(122, 0, 18):Lerp(Color3.fromRGB(96, 0, 22), i / SUB_EXTRUDE_STEPS)
	table.insert(subExtrude, l)
end
local subtitle = subLabel("Fill", 11)
subtitle.TextColor3 = Color3.new(1, 1, 1)
local subGradient = Instance.new("UIGradient")
subGradient.Rotation = 90
subGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 216, 58)),
	ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 174, 44)),
	ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 122, 46)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 68, 60)),
})
subGradient.Parent = subtitle

local hud = Instance.new("TextLabel")
hud.Name = "HUD"
hud.BackgroundColor3 = Color3.new(0, 0, 0)
hud.BackgroundTransparency = 0.4
hud.TextColor3 = Color3.new(1, 1, 1)
hud.TextXAlignment = Enum.TextXAlignment.Left
hud.FontFace = Font.fromEnum(Enum.Font.RobotoMono)
hud.TextSize = 14
hud.Position = UDim2.fromOffset(8, 8)
hud.Size = UDim2.fromOffset(560, 44)
hud.ZIndex = 30
hud.Visible = false
hud.Parent = gui

task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
		if ok then
			break
		end
		task.wait(0.25)
	end
end)

-- ===== Ожидание мира =====
local worldRoot = workspace:WaitForChild("AuraFarmer")
local shotsRoot = worldRoot:WaitForChild("Shots")
local setsRoot = worldRoot:WaitForChild("Sets")
local animsRoot = ReplicatedStorage:WaitForChild("AuraFarmerAnims")
while not animsRoot:GetAttribute("Ready") do
	animsRoot:GetAttributeChangedSignal("Ready"):Wait()
end
while not workspace:GetAttribute("AuraTerrainReady") do
	task.wait(0.1)
end

-- ===== Постобработка =====
local function ensure(parent: Instance, className: string, name: string): any
	local inst = parent:FindFirstChild(name)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
	end
	return inst
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or ensure(Lighting, "Atmosphere", "Atmosphere")
local bloom = ensure(Lighting, "BloomEffect", "AF_Bloom")
local sunRays = ensure(Lighting, "SunRaysEffect", "AF_SunRays")
local cc = ensure(Lighting, "ColorCorrectionEffect", "AF_Color")
local dof = ensure(Lighting, "DepthOfFieldEffect", "AF_DOF")
local blur = ensure(Lighting, "BlurEffect", "AF_Blur")
local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or ensure(workspace.Terrain, "Clouds", "Clouds")
for _, e in Lighting:GetChildren() do
	-- чужие эффекты из места не должны мешать пресетам
	if e:IsA("PostEffect") and string.sub(e.Name, 1, 3) ~= "AF_" then
		e.Enabled = false
	end
end

-- Подбор ClockTime/GeographicLatitude под нужное направление солнца.
local sunCache: { [string]: { number } } = {}
local function solveSun(p: any): (number, number)
	local dir = (p.sunDir :: Vector3).Unit
	local key = string.format("%.3f,%.3f,%.3f", dir.X, dir.Y, dir.Z)
	local hit = sunCache[key]
	if hit then
		return hit[1], hit[2]
	end
	local bestDot, bestCt, bestLat = -2, p.clockTime or 14, p.latitude or 40
	local function try(ct: number, lat: number)
		Lighting.GeographicLatitude = lat
		Lighting.ClockTime = ct % 24
		local d = Lighting:GetSunDirection()
		local s = d:Dot(dir)
		if s > bestDot then
			bestDot, bestCt, bestLat = s, ct % 24, lat
		end
	end
	for lat = -88, 88, 4 do
		for ct = 0, 23.75, 0.25 do
			try(ct, lat)
		end
	end
	local stepCt, stepLat = 0.25, 4
	for _ = 1, 4 do
		stepCt /= 2
		stepLat /= 2
		local c0, l0 = bestCt, bestLat
		for i = -2, 2 do
			for j = -2, 2 do
				try(c0 + i * stepCt, math.clamp(l0 + j * stepLat, -89.9, 89.9))
			end
		end
	end
	if bestDot < 0.9 then
		bestCt, bestLat = p.clockTime or 14, p.latitude or 40
	end
	sunCache[key] = { bestCt, bestLat }
	return bestCt, bestLat
end

local function setProps(inst: Instance, props: { [string]: any }?)
	if not props then
		return
	end
	for k, v in props do
		pcall(function()
			(inst :: any)[k] = v
		end)
	end
end

local currentPreset: any = nil
local function applyPreset(p: any)
	currentPreset = p
	setProps(Lighting, p.lighting)
	local ct, lat = solveSun(p)
	Lighting.ClockTime = ct
	Lighting.GeographicLatitude = lat
	setProps(atmosphere, p.atmosphere)
	setProps(bloom, p.bloom)
	setProps(sunRays, p.sunRays)
	setProps(cc, p.cc)
	setProps(dof, p.dof)
	if p.clouds then
		setProps(clouds, p.clouds)
	end
	blur.Size = 0
end

-- заранее подобрать солнце для всех пресетов
for _, shot in Timeline.shots do
	solveSun(Presets.resolve(shot))
end

-- ===== Актёры =====
type Actor = {
	model: Model,
	rig: FK.Rig,
	clip: KFS.Clip?,
	rootCf: CFrame,
	tr: { [string]: CFrame },
	cfs: { CFrame },
}

local shotFolders: { [string]: Instance } = {}
local shotActors: { [string]: { [string]: Actor } } = {}

for _, shot in Timeline.shots do
	local folder = shotsRoot:WaitForChild(shot.id)
	shotFolders[shot.id] = folder
	local actors = {}
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:FindFirstChild("HumanoidRootPart") then
			local rig = FK.build(model)
			for _, p in rig.parts do
				p.Anchored = true
			end
			local clip = nil
			local holder = animsRoot:FindFirstChild(model.Name)
			local clipName = model:GetAttribute("Clip") or shot.id
			local kfs = holder and holder:FindFirstChild(clipName)
			if kfs and kfs:IsA("KeyframeSequence") then
				clip = KFS.compile(kfs)
			end
			local actorName = (model:GetAttribute("Actor") :: string?) or model.Name
			actors[actorName] = {
				model = model,
				rig = rig,
				clip = clip,
				rootCf = rig.root.CFrame,
				tr = {},
				cfs = {} :: { CFrame },
			}
		end
	end
	shotActors[shot.id] = actors
	folder.Parent = nil
end

-- ===== Часы ролика =====
local music = SoundService:FindFirstChild("AuraFarmerMusic") :: Sound?
local musicOffset = 0
local useMusic = false
if music and music:IsA("Sound") and music.SoundId ~= "" then
	musicOffset = (music:GetAttribute("StartOffset") :: number?) or 0
	if not music.IsLoaded then
		local t0 = os.clock()
		while not music.IsLoaded and os.clock() - t0 < 10 do
			task.wait(0.1)
		end
	end
	useMusic = music.IsLoaded
end

local state = {
	t = 0,
	playing = false,
	loop = false,
	subtitles = true,
	letterbox = false,
	started = false,
}

local function clockTime(): number
	if useMusic and music then
		return music.TimePosition - musicOffset
	end
	return state.t
end

local function seek(t: number)
	t = math.clamp(t, 0, Config.Duration)
	state.t = t
	if useMusic and music then
		music.TimePosition = musicOffset + t
	end
end

local function play()
	state.playing = true
	if useMusic and music then
		music.TimePosition = musicOffset + state.t
		music:Play()
	end
end

local function pause()
	state.playing = false
	if useMusic and music then
		state.t = clockTime()
		music:Pause()
	end
end

-- ===== Кадр =====
local activeShot: any = nil
local prevT = -1
local ctx = { shotFolder = nil :: Instance?, setModel = nil :: Instance?, flash = flash }

local function activate(shot: any)
	if activeShot and activeShot.id ~= shot.id then
		shotFolders[activeShot.id].Parent = nil
	end
	activeShot = shot
	shotFolders[shot.id].Parent = shotsRoot
	ctx.shotFolder = shotFolders[shot.id]
	ctx.setModel = setsRoot:FindFirstChild(shot.set)
	applyPreset(Presets.resolve(shot))
	Effects.enter(shot, ctx)
end

local function updateActors(shot: any, t: number)
	local lt = t - shot.start
	for _, a in shotActors[shot.id] do
		if a.clip then
			KFS.sample(a.clip, lt, a.tr)
		end
		FK.solve(a.rig, a.rootCf, a.tr, a.cfs)
		workspace:BulkMoveTo(a.rig.parts, a.cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function focusDistance(shot: any, camCf: CFrame, track: CameraTrack.Result): number?
	if track.focusDistance then
		return track.focusDistance
	end
	local f = shot.camera.focus
	if type(f) == "number" then
		return f
	elseif type(f) == "table" then
		local a = shotActors[shot.id][f.actor]
		if a then
			for i, p in a.rig.parts do
				if p.Name == (f.part or "Head") then
					return (a.cfs[i].Position - camCf.Position).Magnitude
				end
			end
		end
	end
	return nil
end

local function lyricAt(t: number): string
	for _, l in Lyrics do
		if t >= l.start and t < l.finish then
			return l.text
		end
	end
	return ""
end

local function updateUI(t: number)
	local vp = camera.ViewportSize
	-- субтитры (жёсткая смена строк, медленное покачивание всего слоя)
	local text = lyricAt(t)
	subRoot.Visible = state.subtitles and text ~= ""
	local size = math.floor(vp.Y * 0.064 + 0.5)
	local wx = (math.noise(t * 0.4, 1.7, 0.3) * 0.004 + math.noise(t * 7, 3.1, 0.9) * 0.0012) * vp.X
	local wy = (math.noise(t * 0.4, 5.3, 0.6) * 0.006 + math.noise(t * 7, 8.2, 0.4) * 0.0012) * vp.Y
	subRoot.Position = UDim2.new(0.5, wx, 0.923, wy)
	subtitle.Text = text
	subtitle.TextSize = size
	for i, l in subExtrude do
		l.Text = text
		l.TextSize = size
		local k = i / SUB_EXTRUDE_STEPS
		l.Position = UDim2.new(0.5, vp.Y * 0.0083 * k, 0.5, vp.Y * 0.0073 * k)
	end
	-- 16:9
	local want = vp.X / math.max(vp.Y, 1)
	if state.letterbox and want > 16 / 9 + 0.01 then
		local w = vp.Y * 16 / 9
		local side = (vp.X - w) / 2
		barTop.Visible, barBottom.Visible = true, true
		barTop.Position, barTop.Size = UDim2.fromOffset(0, 0), UDim2.new(0, side, 1, 0)
		barBottom.Position, barBottom.Size = UDim2.new(1, -side, 0, 0), UDim2.new(0, side, 1, 0)
	elseif state.letterbox and want < 16 / 9 - 0.01 then
		local h = vp.X * 9 / 16
		local bar = (vp.Y - h) / 2
		barTop.Visible, barBottom.Visible = true, true
		barTop.Position, barTop.Size = UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, bar)
		barBottom.Position, barBottom.Size = UDim2.new(0, 0, 1, -bar), UDim2.new(1, 0, 0, bar)
	else
		barTop.Visible, barBottom.Visible = false, false
	end
	-- чёрный кадр в конце
	black.Visible = (not state.started) or t >= Config.BlackFrom
	loading.Visible = not state.started
	if hud.Visible then
		hud.Text = string.format(
			" t=%6.3f  %s  %s%s\n [Пробел] пауза [R] заново [←/→] ±1с [1-9,0,-] план [T] текст [B] 16:9 [L] круг [H] скрыть",
			t :: number,
			(activeShot and activeShot.id or "-") :: string,
			if state.playing then "▶" else "❚❚",
			if useMusic then "  ♪" else ""
		)
	end
end

local function step(dt: number)
	if state.playing and not useMusic then
		state.t += dt
	end
	local t = clockTime()
	if t >= Config.Duration then
		if state.loop then
			seek(0)
			t = 0
			if useMusic then
				play()
			end
		else
			t = Config.Duration
			if state.playing then
				pause()
				state.t = Config.Duration
			end
		end
	end
	local shot = Timeline.shotAt(math.min(t, Config.BlackFrom - 1e-3))
	if shot ~= activeShot then
		activate(shot)
		prevT = t
	end
	updateActors(shot, t)
	local track = CameraTrack.evaluate(shot, t)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = track.cframe
	camera.FieldOfView = track.fov
	local fd = focusDistance(shot, track.cframe, track)
	if fd and currentPreset and currentPreset.dof and currentPreset.dof.Enabled ~= false then
		dof.FocusDistance = fd
	end
	blur.Size = track.blur
	blur.Enabled = track.blur > 0.05
	Effects.update(shot, t, prevT, ctx)
	prevT = t
	updateUI(t)
end

RunService:BindToRenderStep("AuraFarmerCinematic", Enum.RenderPriority.Camera.Value + 1, step)

-- ===== Клавиши =====
local SHOT_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
	[Enum.KeyCode.Minus] = 11,
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.Space then
		if state.playing then
			pause()
		else
			if clockTime() >= Config.Duration - 1e-3 then
				seek(0)
			end
			play()
		end
	elseif k == Enum.KeyCode.R then
		seek(0)
		play()
	elseif k == Enum.KeyCode.Left then
		seek(clockTime() - 1)
	elseif k == Enum.KeyCode.Right then
		seek(clockTime() + 1)
	elseif SHOT_KEYS[k] then
		local s = Timeline.shots[SHOT_KEYS[k]]
		if s then
			seek(s.start)
		end
	elseif k == Enum.KeyCode.T then
		state.subtitles = not state.subtitles
	elseif k == Enum.KeyCode.B then
		state.letterbox = not state.letterbox
	elseif k == Enum.KeyCode.L then
		state.loop = not state.loop
	elseif k == Enum.KeyCode.H then
		hud.Visible = not hud.Visible
		UserInputService.MouseIconEnabled = hud.Visible
	end
end)

UserInputService.MouseIconEnabled = false

-- Старт: секунда чёрного кадра (чтобы запись не пропустила начало), затем ролик.
loading.Text = ""
task.delay(1, function()
	state.started = true
	seek(0)
	play()
end)
