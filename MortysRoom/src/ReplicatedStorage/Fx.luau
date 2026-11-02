-- Visual effects: screen overlays (flash, fade, glitch, speed lines, letterbox, titles)
-- and world effects (explosions, shockwaves, sonic rings, beams, dust). Client only.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local UI = require(script.Parent.UI)
local Audio = require(script.Parent.Audio)
local Lang = require(script.Parent.Lang)

local Fx = {}
local rgb = Color3.fromRGB

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local folder = Instance.new("Folder")
folder.Name = "ClientFx"
folder.Parent = workspace

----------------------------------------------------------------------------
-- overlay
----------------------------------------------------------------------------
local gui: ScreenGui
local canvas: Frame
local flashFrame, blackFrame, heatFrame, glitchFrame, linesFrame, barTop, barBottom, titleGroup, titleMain, titleSub
local glitchGrade: ColorCorrectionEffect

local function build()
	if gui then
		return
	end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = UI.new("ScreenGui", {
		Name = "FxOverlay",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = pg,
	})
	canvas = UI.canvas(gui)
	canvas.ZIndex = 12 -- titles draw above the black fade
	heatFrame = UI.full(gui, "Heat", 1)
	for i, rot in { 0, 90, 180, 270 } do
		UI.new("Frame", {
			BackgroundColor3 = rgb(255, 120, 40),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Parent = heatFrame,
		}, { UI.gradient(nil, { 0, 0.7, 1, 1 }, rot) })
		local _ = i
	end
	heatFrame.Visible = false
	linesFrame = UI.full(gui, "SpeedLines", 2)
	linesFrame.Visible = false
	for i = 1, 48 do
		UI.new("Frame", {
			Name = "Line" .. i,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(200, 2),
			Parent = linesFrame,
		})
	end
	glitchFrame = UI.full(gui, "Glitch", 3)
	glitchFrame.Visible = false
	for i = 1, 26 do
		UI.new("Frame", { Name = "Bar" .. i, BorderSizePixel = 0, Parent = glitchFrame })
	end
	UI.label({
		Name = "Lost",
		Font = Enum.Font.RobotoMono,
		TextSize = 40,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.1),
		TextScaled = false,
		Parent = glitchFrame,
	})
	barTop = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.fromScale(1, 0), ZIndex = 8, Parent = gui })
	barBottom = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), ZIndex = 8, Parent = gui })
	flashFrame = UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = gui })
	blackFrame = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = gui })
	titleGroup = UI.new("CanvasGroup", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), GroupTransparency = 1, ZIndex = 11, Parent = canvas })
	titleSub = UI.label({
		Font = Enum.Font.GothamMedium,
		TextSize = 22,
		TextColor3 = rgb(250, 222, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromOffset(1400, 30),
		Parent = titleGroup,
	})
	titleMain = UI.label({
		Font = Enum.Font.GothamBlack,
		TextSize = 60,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.51),
		Size = UDim2.fromOffset(1600, 80),
		Parent = titleGroup,
	})
	UI.stroke(2, Color3.new(0, 0, 0), 0.4).Parent = titleMain

	glitchGrade = Instance.new("ColorCorrectionEffect")
	glitchGrade.Name = "GlitchGrade"
	glitchGrade.Enabled = false
	glitchGrade.Parent = Lighting
end

function Fx.init()
	build()
end

function Fx.flash(color: Color3?, peak: number?, tin: number?, tout: number?)
	build()
	flashFrame.BackgroundColor3 = color or Color3.new(1, 1, 1)
	UI.tween(flashFrame, tin or 0.05, { BackgroundTransparency = 1 - (peak or 1) })
	task.delay((tin or 0.05) + 0.02, function()
		UI.tween(flashFrame, tout or 0.8, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
	end)
end

function Fx.fade(alpha: number, t: number, wait: boolean?)
	build()
	UI.tween(blackFrame, t, { BackgroundTransparency = 1 - alpha }, Enum.EasingStyle.Sine)
	if wait then
		task.wait(t)
	end
end

function Fx.black(alpha: number)
	build()
	blackFrame.BackgroundTransparency = 1 - alpha
end

function Fx.letterbox(on: boolean, t: number?)
	build()
	local h = if on then 0.09 else 0
	UI.tween(barTop, t or 1, { Size = UDim2.fromScale(1, h) }, Enum.EasingStyle.Quint)
	UI.tween(barBottom, t or 1, { Size = UDim2.fromScale(1, h) }, Enum.EasingStyle.Quint)
end

-- chapter title card (yields ~3.4 s)
function Fx.title(key: string)
	build()
	titleMain.Text = Lang.t(key)
	titleSub.Text = UI.spaced(Lang.t("ch.sub"))
	titleGroup.GroupTransparency = 1
	titleMain.Position = UDim2.fromScale(0.5, 0.53)
	UI.tween(titleGroup, 0.8, { GroupTransparency = 0 }, Enum.EasingStyle.Sine)
	UI.tween(titleMain, 1.2, { Position = UDim2.fromScale(0.5, 0.51) }, Enum.EasingStyle.Quint)
	task.wait(2.4)
	UI.tween(titleGroup, 0.9, { GroupTransparency = 1 }, Enum.EasingStyle.Sine)
	task.wait(0.9)
end

function Fx.heat(alpha: number, t: number?)
	build()
	heatFrame.Visible = alpha > 0
	for _, f in heatFrame:GetChildren() do
		if f:IsA("Frame") then
			UI.tween(f, t or 0.5, { BackgroundTransparency = 1 - alpha })
		end
	end
end

local linesConn: RBXScriptConnection? = nil
function Fx.speedLines(on: boolean, strength: number?)
	build()
	if linesConn then
		linesConn:Disconnect()
		linesConn = nil
	end
	linesFrame.Visible = on
	if not on then
		return
	end
	local s = strength or 1
	local data = {}
	for i, l in linesFrame:GetChildren() do
		data[l] = { a = math.random() * math.pi * 2, r = math.random(), speed = 0.9 + math.random() * 1.4, len = 80 + math.random() * 260 }
		local _ = i
	end
	linesConn = RunService.RenderStepped:Connect(function(dt)
		for l, d in data do
			d.r += dt * d.speed * s
			if d.r > 1 then
				d.r = 0.05 + math.random() * 0.1
				d.a = math.random() * math.pi * 2
			end
			local r = 0.08 + d.r * 0.7
			l.Position = UDim2.fromScale(0.5 + math.cos(d.a) * r, 0.5 + math.sin(d.a) * r * 1.6)
			l.Rotation = math.deg(math.atan2(math.sin(d.a) * 1.6, math.cos(d.a)))
			l.Size = UDim2.fromOffset(d.len * (0.3 + d.r), 2 + d.r * 2)
			l.BackgroundTransparency = 1 - math.clamp(d.r * 1.2, 0, 0.85)
		end
	end)
end

-- "Cameraman" style screen glitch (async)
local glitchToken = 0
function Fx.glitch(duration: number, intensity: number?)
	build()
	glitchToken += 1
	local my = glitchToken
	local k = intensity or 1
	glitchFrame.Visible = true
	glitchGrade.Enabled = true
	local lost = glitchFrame:FindFirstChild("Lost") :: TextLabel
	lost.Text = Lang.t("glitch.lost")
	task.spawn(function()
		local t0 = os.clock()
		local colors = { rgb(255, 30, 80), rgb(30, 255, 120), rgb(40, 120, 255), Color3.new(1, 1, 1), Color3.new(0, 0, 0), rgb(255, 0, 255) }
		while os.clock() - t0 < duration and my == glitchToken do
			local fade = 1 - (os.clock() - t0) / duration
			local amount = k * (0.4 + 0.6 * fade)
			for _, b in glitchFrame:GetChildren() do
				if b:IsA("Frame") then
					if math.random() < 0.55 * amount then
						b.Visible = true
						b.BackgroundColor3 = colors[math.random(1, #colors)]
						b.BackgroundTransparency = 0.15 + math.random() * 0.6
						local h = math.random(2, 46)
						b.Position = UDim2.new(math.random() * 0.4 - 0.2, 0, math.random(), 0)
						b.Size = UDim2.new(0.3 + math.random() * 1.0, 0, 0, h)
					else
						b.Visible = false
					end
				end
			end
			lost.Visible = math.random() < 0.3 * amount
			lost.Position = UDim2.new(0.5, math.random(-30, 30), 0.5, math.random(-12, 12))
			lost.TextColor3 = colors[math.random(1, 4)]
			glitchGrade.TintColor = Color3.new(1 - math.random() * 0.4 * amount, 1 - math.random() * 0.4 * amount, 1 - math.random() * 0.4 * amount)
			glitchGrade.Saturation = -math.random() * amount
			glitchGrade.Contrast = math.random() * 0.6 * amount
			glitchGrade.Brightness = (math.random() - 0.5) * 0.3 * amount
			task.wait(0.04 + math.random() * 0.05)
		end
		if my == glitchToken then
			glitchFrame.Visible = false
			glitchGrade.Enabled = false
		end
	end)
end

function Fx.stopGlitch()
	glitchToken += 1
	if glitchFrame then
		glitchFrame.Visible = false
		glitchGrade.Enabled = false
	end
end

-- muffled hearing (after an explosion)
local muffles: { Instance } = {}
function Fx.muffle(on: boolean)
	for _, m in muffles do
		m:Destroy()
	end
	table.clear(muffles)
	if on then
		for _, name in { "SFX", "Music", "Ambience" } do
			local g = SoundService:FindFirstChild(name)
			if g then
				local eq = Instance.new("EqualizerSoundEffect")
				eq.HighGain = -40
				eq.MidGain = -18
				eq.LowGain = 4
				eq.Parent = g
				table.insert(muffles, eq)
			end
		end
	end
end

----------------------------------------------------------------------------
-- world effects
----------------------------------------------------------------------------
local function fxPart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, val in props do
		(p :: any)[k] = val
	end
	p.Parent = folder
	return p
end
Fx.part = fxPart

local function emitterAt(pos: Vector3, props: { [string]: any }): (BasePart, ParticleEmitter)
	local holder = fxPart({ Transparency = 1, Size = Vector3.new(0.5, 0.5, 0.5), CFrame = CFrame.new(pos) })
	local pe = Instance.new("ParticleEmitter")
	pe.Enabled = false
	for k, val in props do
		(pe :: any)[k] = val
	end
	pe.Parent = holder
	return holder, pe
end

function Fx.sparks(pos: Vector3, count: number?, color: Color3?)
	local holder, pe = emitterAt(pos, {
		Texture = SPARK,
		Color = ColorSequence.new(color or rgb(255, 200, 120)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.4, 1.0),
		Speed = NumberRange.new(20, 50),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -60, 0),
		Drag = 2,
	})
	pe:Emit(count or 30)
	task.delay(2, function()
		holder:Destroy()
	end)
end

function Fx.smoke(pos: Vector3, size: number?, count: number?, color: Color3?, life: number?)
	local s = size or 4
	local holder, pe = emitterAt(pos, {
		Texture = SMOKE,
		Color = ColorSequence.new(color or rgb(50, 46, 44)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s * 0.6), NumberSequenceKeypoint.new(1, s * 2.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new((life or 3) * 0.7, life or 3),
		Speed = NumberRange.new(s * 0.6, s * 2.2),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		Drag = 1.5,
		Acceleration = Vector3.new(0, s * 0.4, 0),
		LightInfluence = 0.8,
	})
	pe:Emit(count or 20)
	task.delay((life or 3) + 1, function()
		holder:Destroy()
	end)
	return holder
end

function Fx.dust(pos: Vector3, radius: number?, count: number?)
	local r = radius or 10
	local holder, pe = emitterAt(pos, {
		Texture = SMOKE,
		Color = ColorSequence.new(rgb(220, 160, 104)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, r * 0.4), NumberSequenceKeypoint.new(1, r * 1.3) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(r * 1.5, r * 3.5),
		SpreadAngle = Vector2.new(80, 10),
		EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360),
		Drag = 3,
		Acceleration = Vector3.new(0, 2, 0),
		LightInfluence = 1,
	})
	pe.Shape = Enum.ParticleEmitterShape.Disc
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	holder.Size = Vector3.new(r * 2, 0.2, r * 2)
	pe:Emit(count or 40)
	task.delay(5, function()
		holder:Destroy()
	end)
end

-- expanding energy shell
function Fx.shockwave(pos: Vector3, radius: number, duration: number?, color: Color3?)
	local d = duration or 0.6
	local ball = fxPart({
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.ForceField,
		Color = color or rgb(255, 200, 140),
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(pos),
		Transparency = 0,
	})
	UI.tween(ball, d, { Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1 }, Enum.EasingStyle.Quad)
	local ring = fxPart({
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = color or rgb(255, 220, 170),
		Size = Vector3.new(0.4, 2, 2),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 0.3,
	})
	UI.tween(ring, d * 1.2, { Size = Vector3.new(0.2, radius * 2.4, radius * 2.4), Transparency = 1 }, Enum.EasingStyle.Quad)
	task.delay(d * 1.3, function()
		ball:Destroy()
		ring:Destroy()
	end)
end

function Fx.explosion(pos: Vector3, scale: number?, opts: { [string]: any }?)
	local s = scale or 1
	local o = opts or {}
	-- fireball
	local fire = fxPart({
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = rgb(255, 210, 120),
		Size = Vector3.new(0.5, 0.5, 0.5) * s,
		CFrame = CFrame.new(pos),
	})
	local light = Instance.new("PointLight")
	light.Range = 40 * math.sqrt(s)
	light.Brightness = 10
	light.Color = rgb(255, 170, 90)
	light.Parent = fire
	UI.tween(fire, 0.22, { Size = Vector3.new(9, 9, 9) * s, Color = rgb(255, 120, 40) }, Enum.EasingStyle.Quad)
	task.delay(0.22, function()
		UI.tween(fire, 0.7, { Size = Vector3.new(12, 12, 12) * s, Color = rgb(90, 20, 10), Transparency = 1 }, Enum.EasingStyle.Quad)
		UI.tween(light, 0.9, { Brightness = 0 })
	end)
	task.delay(1.1, function()
		fire:Destroy()
	end)
	-- smoke, sparks, shockwave
	Fx.smoke(pos, 4 * s, math.floor(24 * math.sqrt(s)), o.smokeColor, 4)
	Fx.sparks(pos, math.floor(50 * math.sqrt(s)))
	Fx.shockwave(pos, 14 * s, 0.5, o.waveColor)
	-- flying debris
	local debris = {}
	for i = 1, (o.debris or 14) do
		local p = fxPart({
			Size = Vector3.new(0.2 + math.random() * 0.6, 0.2 + math.random() * 0.4, 0.2 + math.random() * 0.6) * math.sqrt(s),
			Color = (o.debrisColors and o.debrisColors[math.random(1, #o.debrisColors)]) or rgb(40, 38, 36),
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(pos),
		})
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5).Unit
		table.insert(debris, { part = p, vel = dir * (20 + math.random() * 30) * math.sqrt(s), spin = Vector3.new(math.random(), math.random(), math.random()) * 10 })
		local _ = i
	end
	task.spawn(function()
		local t = 0
		while t < 1.6 do
			local dt = RunService.RenderStepped:Wait()
			t += dt
			for _, d in debris do
				d.vel += Vector3.new(0, -90, 0) * dt
				local p = d.part
				p.CFrame = (p.CFrame + d.vel * dt) * CFrame.Angles(d.spin.X * dt, d.spin.Y * dt, d.spin.Z * dt)
			end
		end
		for _, d in debris do
			d.part:Destroy()
		end
	end)
	-- sound
	if o.sound ~= false then
		local holder = fxPart({ Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos) })
		local snd = Audio.make(o.sound or "Explosion", holder)
		if snd then
			snd.RollOffMaxDistance = 600
			snd:Play()
		end
		task.delay(8, function()
			holder:Destroy()
		end)
	end
end

-- ring of sound travelling forward from `origin` (CFrame looking where it flies)
function Fx.sonicRing(origin: CFrame, distance: number, duration: number?, size: number?, color: Color3?)
	local d = duration or 0.6
	local sz = size or 6
	local ring = fxPart({
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.ForceField,
		Color = color or rgb(120, 220, 255),
		Size = Vector3.new(0.6, sz, sz),
		CFrame = origin * CFrame.Angles(0, math.rad(90), 0),
	})
	local core = fxPart({
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = color or rgb(150, 230, 255),
		Transparency = 0.6,
		Size = Vector3.new(0.2, sz * 0.9, sz * 0.9),
		CFrame = origin * CFrame.Angles(0, math.rad(90), 0),
	})
	local target = origin * CFrame.new(0, 0, -distance) * CFrame.Angles(0, math.rad(90), 0)
	UI.tween(ring, d, { CFrame = target, Size = Vector3.new(0.6, sz * 3, sz * 3), Transparency = 0.7 }, Enum.EasingStyle.Linear)
	UI.tween(core, d, { CFrame = target, Size = Vector3.new(0.2, sz * 2.6, sz * 2.6), Transparency = 1 }, Enum.EasingStyle.Linear)
	task.delay(d, function()
		ring:Destroy()
		core:Destroy()
	end)
end

-- energy beam between two points; returns a handle {Set(from, to), SetWidth(w), Destroy()}
function Fx.beam(from: Vector3, to: Vector3, width: number, color: Color3?)
	local col = color or rgb(150, 230, 255)
	local core = fxPart({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1) })
	local glow = fxPart({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = col, Transparency = 0.45 })
	local shell = fxPart({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.ForceField, Color = col })
	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 6
	light.Color = col
	light.Parent = glow
	local handle = {}
	local w = width
	function handle.Set(a: Vector3, b: Vector3)
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
		local jitter = 1 + (math.random() - 0.5) * 0.25
		core.Size = Vector3.new(len, w * 0.35 * jitter, w * 0.35 * jitter)
		glow.Size = Vector3.new(len, w * jitter, w * jitter)
		shell.Size = Vector3.new(len, w * 1.8, w * 1.8)
		core.CFrame = cf
		glow.CFrame = cf
		shell.CFrame = cf
	end
	function handle.SetWidth(nw: number)
		w = nw
	end
	function handle.Destroy()
		core:Destroy()
		glow:Destroy()
		shell:Destroy()
	end
	handle.Set(from, to)
	return handle
end

-- a big dark part flash (used for the curse hand blur)
function Fx.clear()
	folder:ClearAllChildren()
end

return Fx
