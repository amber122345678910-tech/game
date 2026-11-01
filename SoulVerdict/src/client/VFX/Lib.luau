--!strict
-- VFX/Lib: reusable client effect builders (SPEC §9). Everything is code-built (Neon parts, built-in particle
-- textures, HandleAdornments, PointLights); every frequent instance comes from a pool and has a lifetime.
--
-- Core
--   Lib.Folder() -> Folder                    Workspace.SV_ClientFX (all client VFX live here; CanQuery=false)
--   Lib.Now() -> number                        server time (Workspace:GetServerTimeNow(); os.clock offline)
--   Lib.Colors / Lib.Color(rule|Color3?, fallback?) -> Color3     colour rule: White, Blue #14A9FF,
--                                              Orange #FFA040, Red, Purple, Yellow, Green, Cyan (+ Grey, Gold, Black)
--   Lib.KitColor(model?) -> Color3?            signature colour of a character's kit (SOUL colour for humans)
--   Lib.ParticleScale() -> number              GraphicsController.ParticleScale() (cached ~1 s; 1 offline)
--   Lib.ReducedMotion() -> boolean
--   Lib.Animate(duration, step(alpha, dt, elapsed) -> boolean?, done?) -> handle {Cancel()}
--                                              one shared PreRender runner; step returning true stops early
--   Lib.Tween(inst, time, props, style?, dir?) -> Tween?
--   Lib.Debris(inst, seconds)                  pooled objects are released, others destroyed
--   Lib.RaycastParams() -> RaycastParams       excludes characters + FX (refreshed every 0.5 s)
--   Lib.Ground(pos, maxDrop?) -> Vector3?      ground point under pos
--   Lib.Characters() -> {Model}                player characters + workspace.Bots models (cached 0.5 s)
-- Parts & lights
--   Lib.Part(shape, size, cf, color, material?, transparency?) -> BasePart   pooled, anchored, no collision
--        shape: "Block" | "Ball" | "Cylinder" | "Wedge"
--   Lib.Release(part)                          back to its pool (or Destroy)
--   Lib.Light(parent, color, brightness, range, shadows?) -> PointLight?   budgeted (<= 24 VFX lights)
-- Particles (built-in textures only)
--   Lib.Emit(kind, pos, count, opts?)          shared emitters, opts {Color, Dir, Speed: {min,max}?, Life:
--        {min,max}?, Spread}; kinds: Spark, Glow, GlowBig, Dust, Ember, Star, SoulDust, Sweat, Heal, Debris,
--        Mote, Smoke
--   Lib.EmitRing(pos, radius, color, duration, opts?)   flat glowing ring particle growing to `radius`
--   Lib.EmitBurst(pos, size, color, duration, opts?)    camera-facing soft glow that grows to `size`
--   Lib.Emitter(kind, parent, props?) -> ParticleEmitter   a dedicated (attached) emitter, Rate 0 unless props
-- Builders (fire-and-forget unless noted)
--   Lib.Sparks(pos, dir?, color?, count?, speed?)        Lib.Dust(pos, radius?, color?, count?)
--   Lib.Flash(pos, color?, size?, duration?)              Lib.Shockwave(pos, radius, color?, duration?, opts?)
--   Lib.Ring(cf, radius, color?, duration?, thickness?)   expanding ring in cf's XZ plane (axis = UpVector)
--   Lib.Slash(cf, opts) -> nil                            curved neon blade swept along an arc (see below)
--   Lib.Line(p0, p1, color?, thickness?, duration?)       Lib.Beam(p0, p1, width, color?, duration?)
--   Lib.Afterimage(model, color?, duration?, opts?)       translucent ghost of a character's visible parts
--   Lib.Shatter(cf, size, color?, count?, opts?)          neon shards bursting out with gravity (opts.Parts:
--                                                         prebuilt shards in cf-local space, e.g. Lib.SoulShards)
--   Lib.Text(pos, text, color?, opts?)                    world text popup (VFX/DamageNumbers.Popup)
--   Lib.Telegraph(desc, opts?) -> handle                  see HazardVisuals (generic TelegraphDesc renderer)
-- Drawing primitives (handles; call :Destroy() when done)
--   Lib.GroundCircle(center, radius, color, opts?) -> GroundCircle
--        :SetCenter(v3) :SetRadius(r) :SetInner(r) :SetFill(alpha01, transparency?) :SetColor(c)
--        :SetTransparency(rim, fill?) :SetVisible(on) :Destroy()      (rim + fill + dark contrast ring)
--   Lib.Lane(cf, length, width, color, opts?) -> Lane     :SetCFrame(cf) :SetFill(alpha01) :SetColor(c)
--        :SetTransparency(edge, fill?) :Destroy()                     (ground strip along cf.LookVector)
--   Lib.Bone(thickness, length, color, opts?) -> BoneVisual   pooled 5-part cartoon bone (3 with {Bottom=false})
--        bone:Place(cf)  (cf.UpVector = bone axis, Position = centre)   bone:Write(cf, parts, cframes, n) -> n
--        bone:SetColor(c) bone:SetTransparency(t) bone:Release()     Lib.BoneDims(thickness) -> dims (pure)
--   Lib.Soul(color, size?) -> Model           Props.Soul.Build when present, else a 3-part neon heart
--   Lib.SoulBroken(color, size?) -> Model      halves "LeftHalf"/"RightHalf" (Props.Soul.BuildBroken fallback)
--   Lib.EyeFlame(attachment, opts?) -> handle {SetEnabled(on), SetIntensity(x), Destroy()}   Sans attack eye
--        (cyan #84FFF2 <-> yellow #FFFF40 flicker, PointLight, fire particles; tints a "<Side>Pupil" part)
-- Slash opts: { Radius: number [4], From: number (deg) [-70], To: number [70], Width: number [0.9],
--   Color: Color3, Core: Color3? [white], Duration: number [0.22], Segments: number?, Thickness: number [0.08] }
--   The arc lies in cf's XZ plane (0 deg = cf.LookVector, +deg toward cf.RightVector); tilt cf to angle it.
-- Lune: requiring this module is safe (no service member access at load time); builders need the engine.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HazardDefs = require(Shared:WaitForChild("Combat"):WaitForChild("HazardDefs")) :: any
local Pool = require(script.Parent.Pool) :: any

local Lib = {}

local LookAlong: (Vector3, Vector3, Vector3?) -> CFrame = HazardDefs.LookAlong
local AxisFrame: (Vector3, Vector3) -> CFrame = HazardDefs.AxisFrame
Lib.LookAlong = LookAlong
Lib.AxisFrame = AxisFrame

---------------------------------------------------------------------------------------------------
-- Colours

Lib.Colors = {
	White = Color3.fromRGB(255, 255, 255),
	Blue = Color3.fromRGB(20, 169, 255), -- #14A9FF (moving hurts)
	Orange = Color3.fromRGB(255, 160, 64), -- #FFA040 (standing still hurts)
	Red = Color3.fromRGB(255, 38, 38),
	Purple = Color3.fromRGB(213, 53, 217), -- KR / Perseverance
	Yellow = Color3.fromRGB(255, 236, 64),
	Green = Color3.fromRGB(64, 255, 110),
	Cyan = Color3.fromRGB(66, 252, 255),
	Grey = Color3.fromRGB(191, 191, 191), -- Undertale MISS #BFBFBF
	Gold = Color3.fromRGB(255, 213, 74),
	Black = Color3.fromRGB(0, 0, 0),
	EyeCyan = Color3.fromRGB(132, 255, 242), -- #84FFF2
	EyeYellow = Color3.fromRGB(255, 255, 64), -- #FFFF40
	KR = Color3.fromRGB(205, 70, 255),
}

function Lib.Color(rule: any, fallback: Color3?): Color3
	if typeof(rule) == "Color3" then
		return rule
	end
	if type(rule) == "string" then
		local c = (Lib.Colors :: any)[rule]
		if c then
			return c
		end
	end
	return fallback or Lib.Colors.White
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end
Lib.LerpColor = lerpColor

local kitsModule: any = nil
function Lib.KitColor(model: Model?): Color3?
	if model == nil then
		return nil
	end
	local id = model:GetAttribute("KitId")
	if type(id) ~= "string" then
		return nil
	end
	if kitsModule == nil then
		local ok, k = pcall(require, Shared:WaitForChild("Kits") :: any)
		kitsModule = if ok then k else false
	end
	if kitsModule then
		local kit = kitsModule.Get(id)
		if kit and typeof(kit.Color) == "Color3" then
			return kit.Color
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Services / time / settings

local fxFolder: Folder? = nil

function Lib.Folder(): Folder
	local f = fxFolder
	if f and f.Parent then
		return f
	end
	local W = game:GetService("Workspace")
	local existing = W:FindFirstChild("SV_ClientFX")
	if existing and existing:IsA("Folder") then
		fxFolder = existing
		return existing
	end
	local nf = Instance.new("Folder")
	nf.Name = "SV_ClientFX"
	nf.Parent = W
	fxFolder = nf
	return nf
end

function Lib.Now(): number
	local ok, t = pcall(function()
		return game:GetService("Workspace"):GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.clock()
end

local graphics: any = nil
local scaleCache, scaleAt = 1, -math.huge
local reducedCache = false

local function graphicsController(): any
	if graphics == nil then
		graphics = false
		local client = script.Parent.Parent
		local controllers = client:FindFirstChild("Controllers")
		local m = controllers and controllers:FindFirstChild("GraphicsController")
		if m and m:IsA("ModuleScript") then
			local ok, g = pcall(require, m)
			if ok and type(g) == "table" then
				graphics = g
			end
		end
	end
	return graphics or nil
end

function Lib.ParticleScale(): number
	local t = os.clock()
	if t - scaleAt > 1 then
		scaleAt = t
		local g = graphicsController()
		if g and type(g.ParticleScale) == "function" then
			local ok, s = pcall(g.ParticleScale)
			if ok and type(s) == "number" then
				scaleCache = math.clamp(s, 0, 2)
			end
		end
		if g and type(g.ReducedMotion) == "function" then
			local ok, r = pcall(g.ReducedMotion)
			reducedCache = ok and r == true
		end
	end
	return scaleCache
end

function Lib.ReducedMotion(): boolean
	Lib.ParticleScale()
	return reducedCache
end

local function scaled(count: number): number
	if count <= 0 then
		return 0
	end
	local n = count * Lib.ParticleScale()
	if n < 1 then
		return if n > 0.25 then 1 else 0
	end
	return math.floor(n + 0.5)
end
Lib.ScaledCount = scaled

local rng = Random.new()
function Lib.Rand(a: number, b: number): number
	return a + (b - a) * rng:NextNumber()
end

---------------------------------------------------------------------------------------------------
-- Animation runner (single PreRender connection)

type Anim = {
	Start: number,
	Duration: number,
	Step: (alpha: number, dt: number, elapsed: number) -> boolean?,
	Done: (() -> ())?,
	Dead: boolean,
}

local anims: { Anim } = {}
local runnerConn: any = nil

local function runAnims(dt: number)
	local now = os.clock()
	local i = 1
	while i <= #anims do
		local a = anims[i]
		local stop = a.Dead
		if not stop then
			local elapsed = now - a.Start
			local alpha = if a.Duration > 0 then math.clamp(elapsed / a.Duration, 0, 1) else 1
			local ok, res = pcall(a.Step, alpha, dt, elapsed)
			if not ok then
				warn("[VFX.Lib] animation error: " .. tostring(res))
				stop = true
			elseif res == true or alpha >= 1 then
				stop = true
			end
		end
		if stop then
			a.Dead = true
			local n = #anims
			anims[i] = anims[n]
			anims[n] = nil
			if a.Done then
				local ok, err = pcall(a.Done)
				if not ok then
					warn("[VFX.Lib] animation done error: " .. tostring(err))
				end
			end
		else
			i += 1
		end
	end
	if #anims == 0 and runnerConn then
		runnerConn:Disconnect()
		runnerConn = nil
	end
end

function Lib.Animate(duration: number, step: (number, number, number) -> boolean?, done: (() -> ())?): any
	local a: Anim = { Start = os.clock(), Duration = math.max(0, duration), Step = step, Done = done, Dead = false }
	table.insert(anims, a)
	if runnerConn == nil then
		runnerConn = RunService.PreRender:Connect(runAnims)
	end
	return {
		Cancel = function()
			a.Dead = true
		end,
	}
end

function Lib.Tween(
	inst: Instance,
	time: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
): Tween?
	local ok, tw = pcall(function()
		local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
		local t = TweenService:Create(inst, info, props)
		t:Play()
		return t
	end)
	return if ok then tw else nil
end

local function ease(name: string, x: number): number
	x = math.clamp(x, 0, 1)
	if name == "OutQuad" then
		return 1 - (1 - x) * (1 - x)
	elseif name == "InQuad" then
		return x * x
	elseif name == "OutCubic" then
		local y = 1 - x
		return 1 - y * y * y
	elseif name == "OutBack" then
		local c1, c3 = 1.70158, 2.70158
		local y = x - 1
		return 1 + c3 * y * y * y + c1 * y * y
	elseif name == "OutExpo" then
		return if x >= 1 then 1 else 1 - 2 ^ (-10 * x)
	elseif name == "InOutSine" then
		return -(math.cos(math.pi * x) - 1) / 2
	end
	return x
end
Lib.Ease = ease

---------------------------------------------------------------------------------------------------
-- Part pools

local PART_SHAPES = { Block = Enum.PartType.Block, Ball = Enum.PartType.Ball, Cylinder = Enum.PartType.Cylinder }
local partPools: { [string]: any } = {}

local function resetPart(p: BasePart)
	if #p:GetChildren() > 0 then
		p:ClearAllChildren()
	end
	p.Transparency = 1
	p.LocalTransparencyModifier = 0
end

local function partPool(shape: string): any
	local pool = partPools[shape]
	if pool then
		return pool
	end
	pool = Pool.new(function(): BasePart
		local p: BasePart
		if shape == "Wedge" then
			p = Instance.new("WedgePart")
		else
			local part = Instance.new("Part")
			part.Shape = PART_SHAPES[shape] or Enum.PartType.Block
			p = part
		end
		p.Name = "FX" .. shape
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.Neon
		p.Transparency = 1
		p.CFrame = Pool.PARK
		p.Parent = Lib.Folder()
		return p
	end, { Max = 220, Reset = resetPart, Name = "Part." .. shape })
	partPools[shape] = pool
	return pool
end

function Lib.Part(
	shape: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?
): BasePart
	local p: BasePart = partPool(shape):Get()
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Transparency = transparency or 0
	if p.Parent == nil then
		p.Parent = Lib.Folder()
	end
	return p
end

function Lib.Release(obj: any)
	if obj == nil then
		return
	end
	Pool.ReleaseAny(obj)
end

function Lib.Debris(inst: any, seconds: number)
	task.delay(math.max(0, seconds), function()
		if Pool.Owner(inst) then
			Pool.ReleaseAny(inst)
		elseif typeof(inst) == "Instance" or (type(inst) == "table" and type(inst.Destroy) == "function") then
			inst:Destroy()
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Lights (budgeted)

local MAX_LIGHTS = 24
local lights: { [PointLight]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function liveLights(): number
	local n = 0
	for l in lights do
		if l.Parent ~= nil then
			n += 1
		else
			lights[l] = nil
		end
	end
	return n
end

function Lib.Light(parent: Instance, color: Color3, brightness: number, range: number, shadows: boolean?): PointLight?
	if liveLights() >= MAX_LIGHTS then
		return nil
	end
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = math.clamp(range, 0, 60)
	l.Shadows = shadows == true
	l.Parent = parent
	lights[l] = true
	return l
end

---------------------------------------------------------------------------------------------------
-- Particles

local TEX = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Glow = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	DarkSmoke = "rbxasset://textures/particles/explosion01_smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Specks = "rbxasset://textures/particles/fire_sparks_main.dds",
	Vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
}
Lib.Textures = TEX

local function ns(...: number): NumberSequence
	local args = { ... }
	if #args == 1 then
		return NumberSequence.new(args[1])
	end
	local keys = {}
	for i = 1, #args, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(args[i], args[i + 1]))
	end
	return NumberSequence.new(keys)
end
Lib.NS = ns

type EmitDef = {
	Texture: string,
	Size: NumberSequence,
	Transparency: NumberSequence,
	Life: { number },
	Speed: { number },
	Spread: Vector2,
	Drag: number?,
	Accel: Vector3?,
	LightEmission: number,
	LightInfluence: number?,
	Brightness: number?,
	Orientation: Enum.ParticleOrientation?,
	Squash: NumberSequence?,
	RotSpeed: { number }?,
	Rotation: { number }?,
	ZOffset: number?,
	ColorEnd: Color3?, -- optional fade-to colour
}

local DEFS: { [string]: EmitDef } = {
	Spark = {
		Texture = TEX.Spark,
		Size = ns(0, 0.42, 1, 0),
		Transparency = ns(0, 0, 0.6, 0.15, 1, 1),
		Life = { 0.14, 0.32 },
		Speed = { 16, 34 },
		Spread = Vector2.new(40, 40),
		Drag = 7,
		LightEmission = 1,
		Brightness = 6,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = ns(1.6),
	},
	Glow = {
		Texture = TEX.Glow,
		Size = ns(0, 0.6, 0.25, 2.8, 1, 3.4),
		Transparency = ns(0, 0.1, 1, 1),
		Life = { 0.18, 0.24 },
		Speed = { 0, 0 },
		Spread = Vector2.new(0, 0),
		LightEmission = 1,
		Brightness = 4,
		ZOffset = 0.5,
	},
	GlowBig = {
		Texture = TEX.Glow,
		Size = ns(0, 1.5, 0.2, 7, 1, 9),
		Transparency = ns(0, 0.05, 1, 1),
		Life = { 0.28, 0.34 },
		Speed = { 0, 0 },
		Spread = Vector2.new(0, 0),
		LightEmission = 1,
		Brightness = 5,
		ZOffset = 1,
	},
	Dust = {
		Texture = TEX.Smoke,
		Size = ns(0, 1.1, 1, 3.6),
		Transparency = ns(0, 0.5, 0.6, 0.75, 1, 1),
		Life = { 0.6, 1.1 },
		Speed = { 4, 10 },
		Spread = Vector2.new(75, 75),
		Drag = 3.5,
		Accel = Vector3.new(0, 1.5, 0),
		LightEmission = 0,
		LightInfluence = 1,
		RotSpeed = { -40, 40 },
		Rotation = { 0, 360 },
	},
	Smoke = {
		Texture = TEX.DarkSmoke,
		Size = ns(0, 1.5, 1, 4),
		Transparency = ns(0, 0.35, 1, 1),
		Life = { 0.7, 1.2 },
		Speed = { 2, 6 },
		Spread = Vector2.new(180, 180),
		Drag = 2,
		Accel = Vector3.new(0, 2, 0),
		LightEmission = 0,
		LightInfluence = 1,
		RotSpeed = { -30, 30 },
		Rotation = { 0, 360 },
	},
	Ember = {
		Texture = TEX.Spark,
		Size = ns(0, 0.22, 1, 0),
		Transparency = ns(0, 0.1, 1, 1),
		Life = { 0.7, 1.3 },
		Speed = { 1, 3.5 },
		Spread = Vector2.new(30, 30),
		Accel = Vector3.new(0, 4, 0),
		Drag = 1,
		LightEmission = 1,
		Brightness = 3,
	},
	Star = {
		Texture = TEX.Spark,
		Size = ns(0, 0.75, 1, 0),
		Transparency = ns(0, 0, 0.7, 0.2, 1, 1),
		Life = { 0.4, 0.8 },
		Speed = { 3, 9 },
		Spread = Vector2.new(180, 180),
		Drag = 3,
		LightEmission = 1,
		Brightness = 4,
		RotSpeed = { 90, 180 },
		Rotation = { 0, 360 },
	},
	SoulDust = {
		Texture = TEX.Smoke,
		Size = ns(0, 0.35, 0.3, 0.7, 1, 1.1),
		Transparency = ns(0, 0.15, 0.7, 0.55, 1, 1),
		Life = { 1.1, 1.9 },
		Speed = { 1.5, 4.5 },
		Spread = Vector2.new(70, 70),
		Drag = 1.2,
		Accel = Vector3.new(2.2, 2.6, 0.8),
		LightEmission = 0.35,
		LightInfluence = 0.4,
		RotSpeed = { -60, 60 },
		Rotation = { 0, 360 },
	},
	Sweat = {
		Texture = TEX.Glow,
		Size = ns(0, 0.3, 1, 0.18),
		Transparency = ns(0, 0.1, 1, 0.6),
		Life = { 0.45, 0.6 },
		Speed = { 4, 6.5 },
		Spread = Vector2.new(35, 35),
		Accel = Vector3.new(0, -32, 0),
		LightEmission = 0.5,
		Brightness = 2,
	},
	Heal = {
		Texture = TEX.Spark,
		Size = ns(0, 0.5, 1, 0),
		Transparency = ns(0, 0.05, 1, 1),
		Life = { 0.8, 1.2 },
		Speed = { 2, 4.5 },
		Spread = Vector2.new(25, 25),
		Accel = Vector3.new(0, 3, 0),
		Drag = 1,
		LightEmission = 1,
		Brightness = 4,
		RotSpeed = { -90, 90 },
	},
	Debris = {
		Texture = TEX.DarkSmoke,
		Size = ns(0, 0.45, 1, 0.2),
		Transparency = ns(0, 0, 0.8, 0.1, 1, 1),
		Life = { 0.4, 0.75 },
		Speed = { 12, 24 },
		Spread = Vector2.new(50, 50),
		Accel = Vector3.new(0, -45, 0),
		LightEmission = 0,
		LightInfluence = 1,
		RotSpeed = { -300, 300 },
		Rotation = { 0, 360 },
	},
	Mote = {
		Texture = TEX.Glow,
		Size = ns(0, 0.18, 0.5, 0.32, 1, 0),
		Transparency = ns(0, 0.2, 1, 1),
		Life = { 0.35, 0.6 },
		Speed = { 3, 8 },
		Spread = Vector2.new(180, 180),
		Drag = 4,
		LightEmission = 1,
		Brightness = 5,
	},
}
Lib.EmitDefs = DEFS

local hostPart: BasePart? = nil
local function host(): BasePart
	local h = hostPart
	if h and h.Parent then
		return h
	end
	local p = Instance.new("Part")
	p.Name = "FXEmitHost"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.identity
	p.Parent = Lib.Folder()
	hostPart = p
	return p
end

local function applyDef(e: ParticleEmitter, def: EmitDef, color: Color3)
	e.Texture = def.Texture
	e.Size = def.Size
	e.Transparency = def.Transparency
	e.Lifetime = NumberRange.new(def.Life[1], def.Life[2])
	e.Speed = NumberRange.new(def.Speed[1], def.Speed[2])
	e.SpreadAngle = def.Spread
	e.Drag = def.Drag or 0
	e.Acceleration = def.Accel or Vector3.zero
	e.LightEmission = def.LightEmission
	e.LightInfluence = def.LightInfluence or 0
	e.Brightness = def.Brightness or 1
	e.Orientation = def.Orientation or Enum.ParticleOrientation.FacingCamera
	if def.Squash then
		e.Squash = def.Squash
	end
	if def.RotSpeed then
		e.RotSpeed = NumberRange.new(def.RotSpeed[1], def.RotSpeed[2])
	end
	if def.Rotation then
		e.Rotation = NumberRange.new(def.Rotation[1], def.Rotation[2])
	end
	e.ZOffset = def.ZOffset or 0
	if def.ColorEnd then
		e.Color = ColorSequence.new(color, def.ColorEnd)
	else
		e.Color = ColorSequence.new(color)
	end
	e.Rate = 0
end

type Shared = { Att: Attachment, E: ParticleEmitter }
local sharedEmitters: { [string]: Shared } = {}
local sharedCount = 0
local MAX_SHARED = 96

local function colorKey(c: Color3): string
	-- quantised so similar colours share an emitter
	return string.format("%x%x%x", math.floor(c.R * 15 + 0.5), math.floor(c.G * 15 + 0.5), math.floor(c.B * 15 + 0.5))
end

local function sharedEmitter(kind: string, color: Color3): Shared?
	local key = kind .. "|" .. colorKey(color)
	local s = sharedEmitters[key]
	if s and s.Att.Parent then
		return s
	end
	local def = DEFS[kind]
	if def == nil then
		return nil
	end
	if sharedCount >= MAX_SHARED then
		-- evict everything of the oldest generation (rare: many distinct colours)
		for k, v in sharedEmitters do
			v.Att:Destroy()
			sharedEmitters[k] = nil
		end
		sharedCount = 0
	end
	local att = Instance.new("Attachment")
	att.Name = "FX_" .. key
	local e = Instance.new("ParticleEmitter")
	applyDef(e, def, color)
	e.Enabled = false
	e.Parent = att
	att.Parent = host()
	local created = { Att = att, E = e }
	sharedEmitters[key] = created
	sharedCount += 1
	return created
end

export type EmitOpts = {
	Color: Color3?,
	Dir: Vector3?,
	Speed: { number }?,
	Life: { number }?,
	Spread: Vector2?,
}

function Lib.Emit(kind: string, pos: Vector3, count: number, opts: EmitOpts?)
	local n = scaled(count)
	if n <= 0 then
		return
	end
	local o: EmitOpts = opts or {}
	local s = sharedEmitter(kind, o.Color or Lib.Colors.White)
	if s == nil then
		return
	end
	local def = DEFS[kind]
	local h = host()
	local dir = o.Dir
	local world = if dir and dir.Magnitude > 1e-4 then AxisFrame(pos, dir) else CFrame.new(pos)
	s.Att.CFrame = h.CFrame:ToObjectSpace(world)
	local e = s.E
	local sp = o.Speed or def.Speed
	e.Speed = NumberRange.new(sp[1], sp[2] or sp[1])
	local life = o.Life or def.Life
	e.Lifetime = NumberRange.new(life[1], life[2] or life[1])
	e.SpreadAngle = o.Spread or def.Spread
	e:Emit(n)
end

-- Exclusive (leased) emitters for effects whose size/colour curve is unique per use.
type Lease = { Att: Attachment, E: ParticleEmitter }
local leasePool: { Lease } = {}

local function lease(): Lease
	local n = #leasePool
	if n > 0 then
		local l = leasePool[n]
		leasePool[n] = nil
		if l.Att.Parent then
			return l
		end
	end
	local att = Instance.new("Attachment")
	att.Name = "FXLease"
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Enabled = false
	e.Parent = att
	att.Parent = host()
	return { Att = att, E = e }
end

local function unlease(l: Lease, after: number)
	task.delay(after, function()
		if l.Att.Parent and #leasePool < 48 then
			table.insert(leasePool, l)
		else
			l.Att:Destroy()
		end
	end)
end

-- Flat ring (lies in the plane perpendicular to `axis`, default up) growing from 0 to `radius`.
function Lib.EmitRing(
	pos: Vector3,
	radius: number,
	color: Color3?,
	duration: number?,
	opts: { Axis: Vector3?, Brightness: number?, Start: number?, Transparency: number? }?
)
	if Lib.ParticleScale() <= 0.05 then
		return
	end
	local o = opts or {}
	local l = lease()
	local d = duration or 0.45
	local e = l.E
	e.Texture = TEX.Ring
	-- the ring of the built-in texture sits at ~42 % of the sprite width
	local size = math.max(0.1, radius / 0.42)
	e.Size = ns(0, size * (o.Start or 0.08), 0.35, size * 0.8, 1, size)
	e.Transparency = ns(0, o.Transparency or 0.05, 0.6, 0.45, 1, 1)
	e.Lifetime = NumberRange.new(d)
	e.Speed = NumberRange.new(0.02)
	e.SpreadAngle = Vector2.zero
	e.Drag = 0
	e.Acceleration = Vector3.zero
	e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = o.Brightness or 3
	e.Color = ColorSequence.new(color or Lib.Colors.White)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(0)
	e.ZOffset = 0
	l.Att.CFrame = host().CFrame:ToObjectSpace(AxisFrame(pos, o.Axis or Vector3.yAxis))
	e.EmissionDirection = Enum.NormalId.Top
	e:Emit(1)
	unlease(l, d + 0.1)
end

-- Camera-facing soft glow growing to `size` studs.
function Lib.EmitBurst(
	pos: Vector3,
	size: number,
	color: Color3?,
	duration: number?,
	opts: { Brightness: number?, Texture: string? }?
)
	if Lib.ParticleScale() <= 0.05 then
		return
	end
	local o = opts or {}
	local l = lease()
	local d = duration or 0.3
	local e = l.E
	e.Texture = o.Texture or TEX.Glow
	e.Size = ns(0, size * 0.25, 0.25, size * 0.9, 1, size)
	e.Transparency = ns(0, 0.05, 0.5, 0.35, 1, 1)
	e.Lifetime = NumberRange.new(d)
	e.Speed = NumberRange.new(0)
	e.SpreadAngle = Vector2.zero
	e.Drag = 0
	e.Acceleration = Vector3.zero
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = o.Brightness or 4
	e.Color = ColorSequence.new(color or Lib.Colors.White)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(0)
	e.ZOffset = 1
	l.Att.CFrame = host().CFrame:ToObjectSpace(CFrame.new(pos))
	e:Emit(1)
	unlease(l, d + 0.1)
end

-- Dedicated emitter attached to `parent` (an Attachment or BasePart). Rate defaults to 0 (use :Emit or set Rate).
function Lib.Emitter(kind: string, parent: Instance, props: { [string]: any }?): ParticleEmitter
	local def = DEFS[kind] or DEFS.Spark
	local e = Instance.new("ParticleEmitter")
	local color = if props and typeof(props.Color) == "Color3" then props.Color else Lib.Colors.White
	applyDef(e, def, color)
	if props then
		for k, v in props do
			if k ~= "Color" or typeof(v) ~= "Color3" then
				(e :: any)[k] = v
			end
		end
	end
	e.Parent = parent
	return e
end

---------------------------------------------------------------------------------------------------
-- Raycasting helpers

local charCache: { Model } = {}
local charCacheAt = -math.huge

function Lib.Characters(): { Model }
	local t = os.clock()
	if t - charCacheAt < 0.5 then
		return charCache
	end
	charCacheAt = t
	local out: { Model } = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c then
			table.insert(out, c)
		end
	end
	local W = game:GetService("Workspace")
	local bots = W:FindFirstChild("Bots")
	if bots then
		for _, m in bots:GetChildren() do
			if m:IsA("Model") then
				table.insert(out, m)
			end
		end
	end
	charCache = out
	return out
end

local rayParams: RaycastParams? = nil
local rayParamsAt = -math.huge

function Lib.RaycastParams(): RaycastParams
	local t = os.clock()
	local rp = rayParams
	if rp and t - rayParamsAt < 0.5 then
		return rp
	end
	rayParamsAt = t
	local params = rp or RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { Lib.Folder() }
	for _, c in Lib.Characters() do
		table.insert(list, c)
	end
	params.FilterDescendantsInstances = list
	params.IgnoreWater = true
	rayParams = params
	return params
end

function Lib.Ground(pos: Vector3, maxDrop: number?): Vector3?
	local drop = maxDrop or 40
	local W = game:GetService("Workspace")
	local hit = W:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -(drop + 2), 0), Lib.RaycastParams())
	if hit then
		return hit.Position
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Simple builders

function Lib.Sparks(pos: Vector3, dir: Vector3?, color: Color3?, count: number?, speed: number?)
	local c = color or Lib.Colors.White
	local s = speed or 24
	Lib.Emit("Spark", pos, count or 10, {
		Color = c,
		Dir = dir,
		Speed = { s * 0.6, s * 1.25 },
		Spread = if dir then Vector2.new(55, 55) else Vector2.new(180, 180),
	})
	Lib.Emit("Mote", pos, math.ceil((count or 10) * 0.4), { Color = c })
end

function Lib.Dust(pos: Vector3, radius: number?, color: Color3?, count: number?)
	local r = radius or 2
	local c = color or Color3.fromRGB(205, 200, 190)
	local n = count or 10
	local points = math.clamp(math.floor(r * 1.2), 3, 10)
	local per = math.max(1, math.floor(n / points + 0.5))
	for i = 1, points do
		local a = (i / points) * math.pi * 2 + Lib.Rand(-0.2, 0.2)
		local off = Vector3.new(math.cos(a) * r * 0.8, 0.3, math.sin(a) * r * 0.8)
		local dir = Vector3.new(math.cos(a), 0.55, math.sin(a))
		Lib.Emit("Dust", pos + off, per, { Color = c, Dir = dir, Spread = Vector2.new(30, 30) })
	end
end

function Lib.Flash(pos: Vector3, color: Color3?, size: number?, duration: number?)
	local c = color or Lib.Colors.White
	local s = size or 3
	local d = duration or 0.25
	local ball = Lib.Part("Ball", Vector3.one * (s * 0.3), CFrame.new(pos), c, Enum.Material.Neon, 0)
	local light = Lib.Light(ball, c, 6, math.min(40, s * 4))
	Lib.EmitBurst(pos, s * 2.2, c, d * 1.3)
	Lib.Animate(d, function(a)
		local grow = ease("OutCubic", math.min(1, a * 2.5))
		ball.Size = Vector3.one * (s * (0.3 + 0.7 * grow))
		ball.CFrame = CFrame.new(pos)
		ball.Transparency = ease("InQuad", a)
		if light then
			light.Brightness = 6 * (1 - a)
		end
		return nil
	end, function()
		Lib.Release(ball)
	end)
end

-- Expanding ring in the XZ plane of `cf` (axis = cf.UpVector).
function Lib.Ring(cf: CFrame, radius: number, color: Color3?, duration: number?, thickness: number?)
	local c = color or Lib.Colors.White
	local d = duration or 0.35
	Lib.EmitRing(cf.Position, radius, c, d, { Axis = cf.UpVector })
	local segs = math.clamp(math.floor(radius * 2.5), 12, 32)
	local parts: { BasePart } = table.create(segs)
	local th = thickness or 0.18
	local chord = 2 * radius * math.sin(math.pi / segs) * 1.08
	for i = 1, segs do
		parts[i] = Lib.Part("Block", Vector3.new(chord, th, th), cf, c, Enum.Material.Neon, 0.1)
	end
	local cframes: { CFrame } = table.create(segs)
	local W = game:GetService("Workspace")
	Lib.Animate(d, function(a)
		local r = radius * ease("OutCubic", a)
		local scale = math.max(0.05, r / radius)
		for i = 1, segs do
			local ang = (i / segs) * math.pi * 2
			cframes[i] = cf * CFrame.Angles(0, -ang, 0) * CFrame.new(0, 0, -r)
			local p = parts[i]
			p.Size = Vector3.new(chord * scale, th, th)
			p.Transparency = 0.1 + 0.9 * ease("InQuad", a)
		end
		W:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		return nil
	end, function()
		for _, p in parts do
			Lib.Release(p)
		end
	end)
end

function Lib.Shockwave(
	pos: Vector3,
	radius: number,
	color: Color3?,
	duration: number?,
	opts: { Dust: boolean?, Height: number? }?
)
	local c = color or Lib.Colors.White
	local d = duration or 0.45
	local o = opts or {}
	Lib.EmitRing(pos + Vector3.new(0, 0.15, 0), radius, c, d)
	local circle = Lib.GroundCircle(pos, 0.1, c, { Rim = 0.5, Fill = 1, Height = o.Height or 0.35 })
	Lib.Animate(d, function(a)
		local r = math.max(0.1, radius * ease("OutCubic", a))
		circle:SetRadius(r)
		circle:SetTransparency(0.15 + 0.85 * ease("InQuad", a), 1)
		return nil
	end, function()
		circle:Destroy()
	end)
	if o.Dust ~= false then
		Lib.Dust(pos, radius * 0.6, nil, math.floor(radius * 1.5))
	end
end

function Lib.Line(p0: Vector3, p1: Vector3, color: Color3?, thickness: number?, duration: number?)
	local c = color or Lib.Colors.White
	local th = thickness or 0.15
	local d = duration or 0.3
	local delta = p1 - p0
	local len = delta.Magnitude
	if len < 0.01 then
		return
	end
	local cf = LookAlong(p0 + delta * 0.5, delta) * CFrame.Angles(0, math.pi / 2, 0)
	local part = Lib.Part("Cylinder", Vector3.new(len, th, th), cf, c, Enum.Material.Neon, 0)
	Lib.Animate(d, function(a)
		local w = th * (1 - a * 0.7)
		part.Size = Vector3.new(len, w, w)
		part.Transparency = ease("InQuad", a)
		return nil
	end, function()
		Lib.Release(part)
	end)
end

function Lib.Beam(p0: Vector3, p1: Vector3, width: number, color: Color3?, duration: number?)
	local c = color or Lib.Colors.White
	local d = duration or 0.35
	local delta = p1 - p0
	local len = delta.Magnitude
	if len < 0.01 then
		return
	end
	local cf = LookAlong(p0 + delta * 0.5, delta) * CFrame.Angles(0, math.pi / 2, 0)
	local core =
		Lib.Part("Cylinder", Vector3.new(len, width * 0.5, width * 0.5), cf, Lib.Colors.White, Enum.Material.Neon, 0)
	local shell = Lib.Part("Cylinder", Vector3.new(len, width, width), cf, c, Enum.Material.Neon, 0.45)
	Lib.Animate(d, function(a)
		local k = 0.8 ^ (a * d * 30)
		core.Size = Vector3.new(len, width * 0.5 * k, width * 0.5 * k)
		shell.Size = Vector3.new(len, width * k, width * k)
		core.Transparency = a
		shell.Transparency = 0.45 + 0.55 * a
		return nil
	end, function()
		Lib.Release(core)
		Lib.Release(shell)
	end)
end

-- Curved neon blade swept along an arc in cf's XZ plane.
function Lib.Slash(cf: CFrame, opts: { [string]: any }?)
	local o = opts or {}
	local radius: number = o.Radius or 4
	local from: number = math.rad(o.From or -70)
	local to: number = math.rad(o.To or 70)
	local width: number = o.Width or 0.9
	local color: Color3 = o.Color or Lib.Colors.White
	local core: Color3 = o.Core or Lib.Colors.White
	local d: number = o.Duration or 0.22
	local thick: number = o.Thickness or 0.08
	local span = math.abs(to - from)
	local n: number = o.Segments or math.clamp(math.floor(math.deg(span) / 9), 6, 18)
	local step = (to - from) / n
	local segLen = radius * math.abs(step) * 1.18
	local parts: { BasePart } = table.create(n)
	local cframes: { CFrame } = table.create(n)
	local widths: { number } = table.create(n)
	for i = 1, n do
		local mid = from + step * (i - 0.5)
		-- angle 0 = LookVector (-Z), positive toward RightVector (+X)
		local local_ = CFrame.Angles(0, -mid, 0) * CFrame.new(0, 0, -radius)
		local seg = cf * local_
		local frac = (i - 0.5) / n
		local w = width * (0.25 + 0.75 * math.sin(math.pi * frac) ^ 0.6)
		widths[i] = w
		cframes[i] = seg
		local col = lerpColor(color, core, frac * 0.8)
		parts[i] = Lib.Part("Block", Vector3.new(segLen, thick, w), seg, col, Enum.Material.Neon, 1)
	end
	local W = game:GetService("Workspace")
	W:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	local sweep = 0.45
	Lib.Animate(d, function(a)
		local head = math.min(1, a / sweep) * n
		for i = 1, n do
			local p = parts[i]
			if i > head + 0.5 then
				p.Transparency = 1
			else
				local age = (a - (i / n) * sweep) / (1 - sweep * 0.5)
				local t = math.clamp(age, 0, 1)
				p.Transparency = 0.05 + 0.95 * ease("InQuad", t)
				local w = widths[i] * (1 - 0.6 * t)
				p.Size = Vector3.new(segLen, thick, w)
			end
		end
		return nil
	end, function()
		for _, p in parts do
			Lib.Release(p)
		end
	end)
	if o.Sparks ~= false then
		local tip = cf * (CFrame.Angles(0, -to, 0) * CFrame.new(0, 0, -radius))
		Lib.Emit("Mote", tip.Position, 4, { Color = color })
	end
end

-- Ghost of a character's visible parts (largest MaxParts), fading out.
function Lib.Afterimage(model: Model, color: Color3?, duration: number?, opts: { [string]: any }?)
	local o = opts or {}
	local c = color or Lib.Colors.White
	local d = duration or 0.45
	local maxParts: number = o.MaxParts or 26
	local startT: number = o.Transparency or 0.35
	local offset: CFrame? = o.Offset
	local material: Enum.Material = o.Material or Enum.Material.Neon
	local list: { BasePart } = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") and inst.Transparency < 0.95 and inst.Name ~= "HumanoidRootPart" then
			if inst.LocalTransparencyModifier < 0.95 then
				table.insert(list, inst)
			end
		end
	end
	if #list == 0 then
		return
	end
	table.sort(list, function(a, b)
		local sa, sb = a.Size, b.Size
		return sa.X * sa.Y * sa.Z > sb.X * sb.Y * sb.Z
	end)
	local ghosts: { BasePart } = {}
	local folder = Lib.Folder()
	for i = 1, math.min(maxParts, #list) do
		local src = list[i]
		local ok, g = pcall(function()
			return src:Clone()
		end)
		if ok and g then
			local ghost = g :: BasePart
			for _, ch in ghost:GetChildren() do
				if not (ch:IsA("SpecialMesh") or ch:IsA("DataModelMesh")) then
					ch:Destroy()
				end
			end
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.CanTouch = false
			ghost.CastShadow = false
			ghost.Massless = true
			ghost.Material = material
			ghost.Color = c
			ghost.Transparency = startT
			ghost.LocalTransparencyModifier = 0
			if offset then
				ghost.CFrame = offset * src.CFrame
			end
			ghost.Parent = folder
			table.insert(ghosts, ghost)
		end
	end
	Lib.Animate(d, function(a)
		local t = startT + (1 - startT) * ease("InQuad", a)
		for _, g in ghosts do
			g.Transparency = t
		end
		return nil
	end, function()
		for _, g in ghosts do
			g:Destroy()
		end
	end)
end

-- Shards bursting from cf with gravity (glass / SOUL / guard pieces).
function Lib.Shatter(cf: CFrame, size: number, color: Color3?, count: number?, opts: { [string]: any }?)
	local o = opts or {}
	local c = color or Lib.Colors.White
	local n = math.max(1, scaled(count or 8))
	local d: number = o.Duration or 1.1
	local speed: number = o.Speed or 14
	local gravity: number = o.Gravity or 55
	local shards: { BasePart } = {}
	local vel: { Vector3 } = {}
	local spin: { Vector3 } = {}
	local rot: { CFrame } = {}
	local pos: { Vector3 } = {}
	local given: { BasePart }? = o.Parts -- prebuilt shards positioned in cf-local space (e.g. Soul.Shards)
	if given then
		n = #given
	end
	for i = 1, n do
		local part: BasePart
		local dir: Vector3
		if given then
			part = given[i]
			local localCF = part.CFrame
			local world = cf * localCF
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CFrame = world
			part.Parent = Lib.Folder()
			local out = cf:VectorToWorldSpace(Vector3.new(localCF.Position.X, localCF.Position.Y, 0))
			dir = (if out.Magnitude > 1e-3 then out.Unit else cf.UpVector) + Vector3.new(0, Lib.Rand(0.3, 0.9), 0)
			dir = dir.Unit
			rot[i] = world - world.Position
			pos[i] = world.Position
		else
			local s = size * Lib.Rand(0.12, 0.26)
			part = Lib.Part("Wedge", Vector3.new(s * 0.35, s, s * 0.8), cf, c, o.Material or Enum.Material.Neon, 0)
			local a = Lib.Rand(0, math.pi * 2)
			local up = Lib.Rand(0.2, 1)
			dir = cf:VectorToWorldSpace(Vector3.new(math.cos(a), up, math.sin(a) * 0.6)).Unit
			rot[i] = CFrame.Angles(Lib.Rand(0, 6), Lib.Rand(0, 6), Lib.Rand(0, 6))
			pos[i] = cf.Position + dir * size * 0.15
		end
		shards[i] = part
		vel[i] = dir * (speed * Lib.Rand(0.6, 1.2))
		spin[i] = Vector3.new(Lib.Rand(-12, 12), Lib.Rand(-12, 12), Lib.Rand(-12, 12))
	end
	local cframes: { CFrame } = table.create(n)
	local W = game:GetService("Workspace")
	Lib.Animate(d, function(a, dt, elapsed)
		for i = 1, n do
			local v = vel[i] - Vector3.new(0, gravity * dt, 0)
			vel[i] = v
			pos[i] += v * dt
			local w = spin[i]
			cframes[i] = CFrame.new(pos[i]) * rot[i] * CFrame.Angles(w.X * elapsed, w.Y * elapsed, w.Z * elapsed)
			shards[i].Transparency = ease("InQuad", math.max(0, (a - 0.45) / 0.55))
		end
		W:BulkMoveTo(shards, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		return nil
	end, function()
		for _, p in shards do
			if given then
				p:Destroy()
			else
				Lib.Release(p)
			end
		end
	end)
end

-- SOUL shards (Rigs/Props/Soul.Shards when present) positioned in heart-local space, for Lib.Shatter {Parts}.
function Lib.SoulShards(color: Color3, size: number, n: number?): { BasePart }?
	local SoulProp = Lib.Prop("Soul")
	if SoulProp and type(SoulProp.Shards) == "function" then
		local ok, list = pcall(SoulProp.Shards, color, size, n or 6, math.random(1, 100000))
		if ok and type(list) == "table" and #list > 0 then
			return list
		end
	end
	return nil
end

local damageNumbers: any = nil
function Lib.Text(pos: Vector3, text: string, color: Color3?, opts: { [string]: any }?)
	if damageNumbers == nil then
		local m = script.Parent:FindFirstChild("DamageNumbers")
		local ok, dn = false, nil
		if m then
			ok, dn = pcall(require, m)
		end
		damageNumbers = if ok then dn else false
	end
	if damageNumbers and type(damageNumbers.Popup) == "function" then
		damageNumbers.Popup(pos, text, color or Lib.Colors.White, opts)
	end
end

---------------------------------------------------------------------------------------------------
-- Ground drawing primitives (HandleAdornments on a pooled invisible adornee)

local FLAT = CFrame.Angles(math.rad(90), 0, 0) -- CylinderHandleAdornment axis is its Z: turn it vertical

local function newAdornee(name: string): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = Pool.PARK
	p.Parent = Lib.Folder()
	return p
end

local function newCyl(parent: BasePart, name: string, z: number): CylinderHandleAdornment
	local a = Instance.new("CylinderHandleAdornment")
	a.Name = name
	a.Adornee = parent
	a.AlwaysOnTop = false
	a.ZIndex = z
	a.Visible = false
	a.Parent = parent
	return a
end

type CircleObj = {
	Part: BasePart,
	Shadow: CylinderHandleAdornment,
	Rim: CylinderHandleAdornment,
	Rim2: CylinderHandleAdornment,
	Fill: CylinderHandleAdornment,
}

local circlePool = Pool.new(function(): CircleObj
	local p = newAdornee("FXCircle")
	return {
		Part = p,
		Shadow = newCyl(p, "Shadow", 0),
		Rim = newCyl(p, "Rim", 2),
		Rim2 = newCyl(p, "Rim2", 2),
		Fill = newCyl(p, "Fill", 1),
	}
end, {
	Max = 48,
	Name = "GroundCircle",
	Reset = function(o: CircleObj)
		o.Shadow.Visible = false
		o.Rim.Visible = false
		o.Rim2.Visible = false
		o.Fill.Visible = false
		o.Part.CFrame = Pool.PARK
	end,
})

export type GroundCircle = {
	SetCenter: (self: any, center: Vector3) -> (),
	SetRadius: (self: any, r: number) -> (),
	SetInner: (self: any, r: number?) -> (),
	SetFill: (self: any, alpha: number, transparency: number?) -> (),
	SetColor: (self: any, c: Color3) -> (),
	SetTransparency: (self: any, rim: number, fill: number?) -> (),
	SetVisible: (self: any, on: boolean) -> (),
	Destroy: (self: any) -> (),
}

-- opts: { Inner: number? (annulus inner radius; nil = full disc), Rim: number? [0.35] (rim band width),
--   Fill: number? [0.65] (fill transparency, 1 = none), Height: number? [0.3] (rim height),
--   Shadow: boolean? [true] (dark contrast outline), Lift: number? [0] (raise the rim: Lift = Height/2 makes a
--   wall standing on the ground) }
-- The fill grows from the centre (disc) or from the inner edge (annulus) with SetFill(alpha).
function Lib.GroundCircle(center: Vector3, radius: number, color: Color3, opts: { [string]: any }?): GroundCircle
	local o = opts or {}
	local obj: CircleObj = circlePool:Get()
	local state = {
		R = radius,
		Inner = o.Inner :: number?,
		RimW = o.Rim or 0.35,
		H = o.Height or 0.3,
		FillT = if o.Fill ~= nil then o.Fill else 0.65,
		RimT = 0.12,
		Alpha = 1,
		Shadow = o.Shadow ~= false,
		Visible = true,
		Dead = false,
	}
	obj.Part.CFrame = CFrame.new(center + Vector3.new(0, 0.06, 0))
	local rim, rim2, fill, shadow = obj.Rim, obj.Rim2, obj.Fill, obj.Shadow
	rim.Color3 = color
	rim2.Color3 = color
	fill.Color3 = color
	shadow.Color3 = Color3.new(0, 0, 0)
	local lift: number = o.Lift or 0
	rim.CFrame = CFrame.new(0, lift, 0) * FLAT
	rim2.CFrame = CFrame.new(0, lift, 0) * FLAT
	shadow.CFrame = CFrame.new(0, -0.03, 0) * FLAT
	fill.CFrame = CFrame.new(0, -0.08, 0) * FLAT
	fill.Height = 0.05
	local function layout()
		local r = math.max(0.05, state.R)
		local w = math.min(state.RimW, r)
		local inner = state.Inner
		local vis = state.Visible
		rim.Height = state.H
		rim.Radius = r
		rim.InnerRadius = math.max(0, r - w)
		rim.Transparency = state.RimT
		rim.Visible = vis
		shadow.Height = state.H * 0.7
		shadow.Radius = r + 0.2
		shadow.Transparency = 0.55 + 0.45 * state.RimT
		shadow.Visible = vis and state.Shadow
		local fr: number
		local fi: number
		if inner and inner > 0.05 and inner < r then
			rim2.Height = state.H
			rim2.InnerRadius = inner
			rim2.Radius = math.min(r, inner + w)
			rim2.Transparency = state.RimT
			rim2.Visible = vis
			shadow.InnerRadius = math.max(0, inner - 0.2)
			fi = inner
			fr = inner + (r - inner) * state.Alpha
		else
			rim2.Visible = false
			shadow.InnerRadius = math.max(0, r - w - 0.2)
			fi = 0
			fr = r * state.Alpha
		end
		fill.Radius = math.max(0.02, fr)
		fill.InnerRadius = math.max(0, math.min(fi, fr - 0.02))
		fill.Transparency = state.FillT
		fill.Visible = vis and state.FillT < 0.99 and state.Alpha > 0.001
	end
	layout()
	local handle = {}
	function handle.SetCenter(_self: any, c: Vector3)
		obj.Part.CFrame = CFrame.new(c + Vector3.new(0, 0.06, 0))
	end
	function handle.SetRadius(_self: any, r: number)
		state.R = r
		layout()
	end
	function handle.SetInner(_self: any, r: number?)
		state.Inner = r
		layout()
	end
	function handle.SetFill(_self: any, alpha: number, transparency: number?)
		state.Alpha = math.clamp(alpha, 0, 1)
		if transparency then
			state.FillT = math.clamp(transparency, 0, 1)
		end
		layout()
	end
	function handle.SetColor(_self: any, c: Color3)
		rim.Color3 = c
		rim2.Color3 = c
		fill.Color3 = c
	end
	function handle.SetTransparency(_self: any, rimT: number, fillT: number?)
		state.RimT = math.clamp(rimT, 0, 1)
		if fillT then
			state.FillT = math.clamp(fillT, 0, 1)
		end
		layout()
	end
	function handle.SetVisible(_self: any, on: boolean)
		state.Visible = on
		layout()
	end
	function handle.Destroy(_self: any)
		if state.Dead then
			return
		end
		state.Dead = true
		circlePool:Release(obj)
	end
	return handle :: any
end

type LaneObj = {
	Part: BasePart,
	Fill: BoxHandleAdornment,
	Left: BoxHandleAdornment,
	Right: BoxHandleAdornment,
	Front: BoxHandleAdornment,
	Back: BoxHandleAdornment,
	Shadow: BoxHandleAdornment,
}

local function newBox(parent: BasePart, name: string, z: number): BoxHandleAdornment
	local a = Instance.new("BoxHandleAdornment")
	a.Name = name
	a.Adornee = parent
	a.AlwaysOnTop = false
	a.ZIndex = z
	a.Visible = false
	a.Parent = parent
	return a
end

local lanePool = Pool.new(function(): LaneObj
	local p = newAdornee("FXLane")
	return {
		Part = p,
		Shadow = newBox(p, "Shadow", 0),
		Fill = newBox(p, "Fill", 1),
		Left = newBox(p, "Left", 2),
		Right = newBox(p, "Right", 2),
		Front = newBox(p, "Front", 2),
		Back = newBox(p, "Back", 2),
	}
end, {
	Max = 16,
	Name = "Lane",
	Reset = function(o: LaneObj)
		for _, a in { o.Shadow, o.Fill, o.Left, o.Right, o.Front, o.Back } do
			a.Visible = false
		end
		o.Part.CFrame = Pool.PARK
	end,
})

-- Ground strip from cf.Position along cf.LookVector (length) with the given width (along cf.RightVector).
function Lib.Lane(cf: CFrame, length: number, width: number, color: Color3, opts: { [string]: any }?): any
	local o = opts or {}
	local obj: LaneObj = lanePool:Get()
	local edge: number = o.Edge or 0.3
	local h: number = o.Height or 0.3
	local state = { Alpha = 0, EdgeT = 0.12, FillT = if o.Fill ~= nil then o.Fill else 0.7, Dead = false }
	obj.Part.CFrame = cf + cf.UpVector * 0.06
	local function layout()
		local L = math.max(0.1, length)
		local W = math.max(0.1, width)
		obj.Left.Size = Vector3.new(edge, h, L)
		obj.Left.CFrame = CFrame.new(-W / 2, 0, -L / 2)
		obj.Right.Size = Vector3.new(edge, h, L)
		obj.Right.CFrame = CFrame.new(W / 2, 0, -L / 2)
		obj.Back.Size = Vector3.new(W + edge, h, edge)
		obj.Back.CFrame = CFrame.new(0, 0, 0)
		obj.Front.Size = Vector3.new(W + edge, h, edge)
		obj.Front.CFrame = CFrame.new(0, 0, -L)
		obj.Shadow.Size = Vector3.new(W + edge + 0.4, h * 0.6, L + edge + 0.4)
		obj.Shadow.CFrame = CFrame.new(0, -0.05, -L / 2)
		local fl = L * state.Alpha
		obj.Fill.Size = Vector3.new(W, 0.05, math.max(0.02, fl))
		obj.Fill.CFrame = CFrame.new(0, -0.08, -fl / 2)
		for _, a in { obj.Left, obj.Right, obj.Front, obj.Back } do
			a.Transparency = state.EdgeT
			a.Visible = true
		end
		obj.Shadow.Color3 = Color3.new(0, 0, 0)
		obj.Shadow.Transparency = 0.7 + 0.3 * state.EdgeT
		obj.Shadow.Visible = true
		obj.Fill.Transparency = state.FillT
		obj.Fill.Visible = state.Alpha > 0.001 and state.FillT < 0.99
	end
	for _, a in { obj.Left, obj.Right, obj.Front, obj.Back, obj.Fill } do
		a.Color3 = color
	end
	layout()
	local handle = {}
	function handle.SetCFrame(_self: any, c: CFrame)
		obj.Part.CFrame = c + c.UpVector * 0.06
	end
	function handle.SetFill(_self: any, alpha: number, transparency: number?)
		state.Alpha = math.clamp(alpha, 0, 1)
		if transparency then
			state.FillT = transparency
		end
		layout()
	end
	function handle.SetColor(_self: any, c: Color3)
		for _, a in { obj.Left, obj.Right, obj.Front, obj.Back, obj.Fill } do
			a.Color3 = c
		end
	end
	function handle.SetTransparency(_self: any, edgeT: number, fillT: number?)
		state.EdgeT = math.clamp(edgeT, 0, 1)
		if fillT then
			state.FillT = math.clamp(fillT, 0, 1)
		end
		layout()
	end
	function handle.Destroy(_self: any)
		if state.Dead then
			return
		end
		state.Dead = true
		lanePool:Release(obj)
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Telegraphs: renders a HazardDefs.TelegraphDesc (Circle / Ring / Lane / Beam / Multi). Shared by
-- HazardVisuals and kit indicators. Visuals are created lazily when an item's warning window opens.

Lib.TELEGRAPH_IMPACT = 0.16

-- Pure: phase of a telegraph item at time t (seconds since the hazard's t0).
--   "Hidden" (t < Start) | "Warn" (Start <= t < End, progress 0..1) | "Impact" (End <= t < End + IMPACT,
--   progress 0..1 through the flash) | "Done"
function Lib.TelegraphPhase(startT: number, endT: number, t: number): (string, number)
	if t < startT then
		return "Hidden", 0
	end
	if t < endT then
		local span = endT - startT
		return "Warn", if span > 1e-3 then (t - startT) / span else 1
	end
	local k = (t - endT) / Lib.TELEGRAPH_IMPACT
	if k < 1 then
		return "Impact", k
	end
	return "Done", 1
end

-- Pure: rim on/off. Steady for the first 70 % of the warning, then blinks at 7 Hz ("now!").
function Lib.TelegraphBlink(progress: number, t: number): boolean
	if progress < 0.7 then
		return true
	end
	return math.floor(t * 14) % 2 == 0
end

type TeleItem = {
	Desc: any,
	Circle: any?,
	Lane: any?,
	Line: BasePart?,
	Shell: BasePart?,
	Done: boolean,
}

-- opts: { Color: Color3? (overrides desc.Color), Fill: boolean? [true], Thin: boolean? (indicator style) }
-- handle: { Update(t) -> boolean (false once every item is done), Destroy(), Kind: string }
function Lib.Telegraph(desc: any, opts: { [string]: any }?): any
	local o = opts or {}
	local items: { TeleItem } = {}
	if desc.Kind == "Multi" and type(desc.Items) == "table" then
		for _, d in desc.Items do
			table.insert(items, { Desc = d, Done = false })
		end
	elseif desc.Kind ~= "None" then
		table.insert(items, { Desc = desc, Done = false })
	end
	local withFill = o.Fill ~= false
	local function colorOf(d: any): Color3
		return o.Color or Lib.Color(d.Color)
	end
	local function show(it: TeleItem)
		local d = it.Desc
		local c = colorOf(d)
		if d.Kind == "Circle" or d.Kind == "Ring" then
			local r = math.max(0.2, d.Radius or 1)
			it.Circle = Lib.GroundCircle(d.Center or Vector3.zero, r, c, {
				Inner = if d.Kind == "Ring" then d.InnerRadius else nil,
				Rim = math.clamp(r * 0.05, 0.22, 0.55),
				Fill = if withFill then 0.82 else 1,
				Height = if o.Thin then 0.18 else 0.32,
			})
			it.Circle:SetFill(0)
		elseif d.Kind == "Lane" and d.CFrame then
			it.Lane = Lib.Lane(d.CFrame, d.Length or 10, d.Width or 2, c, { Fill = if withFill then 0.8 else 1 })
		elseif d.Kind == "Beam" and d.CFrame then
			local cf: CFrame = d.CFrame
			local len = math.max(0.5, d.Length or 10)
			local axis = cf * CFrame.new(0, 0, -len / 2) * CFrame.Angles(0, math.pi / 2, 0)
			it.Line = Lib.Part("Cylinder", Vector3.new(len, 0.14, 0.14), axis, c, Enum.Material.Neon, 0.2)
			local w = math.max(0.2, d.Width or 1)
			it.Shell = Lib.Part("Cylinder", Vector3.new(len, w, w), axis, c, Enum.Material.Neon, 0.93)
		end
	end
	local function hide(it: TeleItem)
		if it.Circle then
			it.Circle:Destroy()
			it.Circle = nil
		end
		if it.Lane then
			it.Lane:Destroy()
			it.Lane = nil
		end
		if it.Line then
			Lib.Release(it.Line)
			it.Line = nil
		end
		if it.Shell then
			Lib.Release(it.Shell)
			it.Shell = nil
		end
	end
	local handle = { Kind = desc.Kind }
	function handle.Update(_self: any, t: number): boolean
		local alive = false
		for _, it in items do
			if not it.Done then
				local d = it.Desc
				local phase, k = Lib.TelegraphPhase(d.Start or 0, d.End or 0, t)
				if phase == "Done" then
					hide(it)
					it.Done = true
				else
					alive = true
					if phase ~= "Hidden" then
						if it.Circle == nil and it.Lane == nil and it.Line == nil then
							show(it)
						end
						local on = phase == "Impact" or Lib.TelegraphBlink(k, t)
						local rimT, fillT, fillA
						if phase == "Warn" then
							rimT = if on then 0.3 * (1 - k) else 0.65
							fillT = 0.84 - 0.26 * k
							fillA = ease("OutQuad", k)
						else
							rimT = 0.9 * k
							fillT = 0.5 + 0.5 * k
							fillA = 1
						end
						if it.Circle then
							it.Circle:SetFill(fillA, if withFill then fillT else 1)
							it.Circle:SetTransparency(rimT)
						elseif it.Lane then
							it.Lane:SetFill(fillA, if withFill then fillT else 1)
							it.Lane:SetTransparency(rimT)
						elseif it.Line then
							local line = it.Line :: BasePart
							line.Transparency = if phase == "Warn" then (if on then 0.15 else 0.7) else k
							local shell = it.Shell
							if shell then
								shell.Transparency = if phase == "Warn" then 0.93 - 0.13 * k else 0.8 + 0.2 * k
							end
						end
					end
				end
			end
		end
		return alive
	end
	function handle.Destroy(_self: any)
		for _, it in items do
			hide(it)
			it.Done = true
		end
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Bones (pooled 5-part cartoon bones; axis = CFrame.UpVector)

-- Pure: visual dimensions for a bone whose hit thickness is `thickness` (visual >= hitbox * forgiveness).
function Lib.BoneDims(thickness: number): { Shaft: number, Knob: number, KnobOffset: number, Span: number }
	-- shaft ~= hit thickness (server volumes shrink by HazardForgiveness 0.85, so the shaft is never thinner
	-- than what hurts); the knob pair spans ~2.1x the shaft like Rigs/Props/Bone
	local t = math.max(0.05, thickness)
	local shaft = t * 0.86
	local knob = t * 0.92
	local off = t * 0.44
	return { Shaft = shaft, Knob = knob, KnobOffset = off, Span = off * 2 + knob }
end

export type BoneVisual = {
	Parts: { BasePart },
	Length: number,
	Thickness: number,
	Place: (self: any, cf: CFrame) -> (),
	Write: (self: any, cf: CFrame, parts: { BasePart }, cframes: { CFrame }, n: number) -> number,
	SetColor: (self: any, c: Color3) -> (),
	SetTransparency: (self: any, t: number) -> (),
	SetLength: (self: any, length: number) -> (),
	Release: (self: any) -> (),
}

local ROT_SHAFT = CFrame.Angles(0, 0, math.pi / 2) -- Cylinder X axis -> bone axis (UpVector)

function Lib.Bone(
	thickness: number,
	length: number,
	color: Color3,
	opts: { Bottom: boolean?, Material: Enum.Material? }?
): BoneVisual
	local o = opts or {}
	local bottom = o.Bottom ~= false
	local mat = o.Material or Enum.Material.Neon
	local dims = Lib.BoneDims(thickness)
	local parts: { BasePart } = {}
	local shaft = Lib.Part("Cylinder", Vector3.new(length, dims.Shaft, dims.Shaft), Pool.PARK, color, mat, 0)
	table.insert(parts, shaft)
	local knobSize = Vector3.one * dims.Knob
	for _ = 1, (if bottom then 4 else 2) do
		table.insert(parts, Lib.Part("Ball", knobSize, Pool.PARK, color, mat, 0))
	end
	local offsets: { CFrame } = {}
	local self: any = { Parts = parts, Length = length, Thickness = thickness, Dead = false }
	local function rebuild(len: number)
		local half = math.max(0, len / 2 - dims.Knob * 0.42)
		shaft.Size = Vector3.new(math.max(0.05, len - dims.Knob * 0.6), dims.Shaft, dims.Shaft)
		offsets[1] = ROT_SHAFT
		offsets[2] = CFrame.new(dims.KnobOffset, half, 0)
		offsets[3] = CFrame.new(-dims.KnobOffset, half, 0)
		if bottom then
			offsets[4] = CFrame.new(dims.KnobOffset, -half, 0)
			offsets[5] = CFrame.new(-dims.KnobOffset, -half, 0)
		end
	end
	rebuild(length)
	function self.SetLength(_s: any, len: number)
		self.Length = len
		rebuild(len)
	end
	function self.Write(_s: any, cf: CFrame, outParts: { BasePart }, outCFrames: { CFrame }, n: number): number
		for i, p in parts do
			n += 1
			outParts[n] = p
			outCFrames[n] = cf * offsets[i]
		end
		return n
	end
	function self.Place(_s: any, cf: CFrame)
		for i, p in parts do
			p.CFrame = cf * offsets[i]
		end
	end
	function self.SetColor(_s: any, c: Color3)
		for _, p in parts do
			p.Color = c
		end
	end
	function self.SetTransparency(_s: any, t: number)
		for _, p in parts do
			p.Transparency = t
		end
	end
	function self.Release(_s: any)
		if self.Dead then
			return
		end
		self.Dead = true
		for _, p in parts do
			Lib.Release(p)
		end
	end
	return self
end

---------------------------------------------------------------------------------------------------
-- Props (lazy, optional) and the SOUL heart

local propCache: { [string]: any } = {}
function Lib.Prop(name: string): any?
	local cached = propCache[name]
	if cached ~= nil then
		return cached or nil
	end
	local result: any = false
	local rigs = Shared:FindFirstChild("Rigs")
	local props = rigs and rigs:FindFirstChild("Props")
	local m = props and props:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" then
			result = mod
		end
	end
	propCache[name] = result
	return result or nil
end

local function prepModel(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
end
Lib.PrepModel = prepModel

local function heartParts(parent: Instance, color: Color3, s: number, side: number?)
	-- side nil = both halves; -1 = left half only; 1 = right half only
	local function ellipsoid(name: string, size: Vector3, cf: CFrame)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		p.Parent = parent
		return p
	end
	local function wedge(name: string, sgn: number)
		-- right-angle corner at the heart's centre-top (0, 0.1s); legs run outward (sgn * X) and down (-Y):
		-- wedge local -Z -> world sgn*X, local +Y -> world -Y, hence local X -> world -sgn*Z
		local w = Instance.new("WedgePart")
		w.Name = name
		local h, l = 0.65 * s, 0.5 * s
		w.Size = Vector3.new(0.26 * s, h, l)
		local right = Vector3.new(0, 0, -sgn)
		local up = Vector3.new(0, -1, 0)
		local centre = Vector3.new(sgn * l / 2, 0.1 * s - h / 2, 0)
		w.CFrame = CFrame.fromMatrix(centre, right, up)
		w.Color = color
		w.Material = Enum.Material.Neon
		w.Anchored = true
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.CastShadow = false
		w.Parent = parent
		return w
	end
	local first: BasePart? = nil
	for _, sgn in { -1, 1 } do
		if side == nil or side == sgn then
			local lobe = ellipsoid(
				if sgn < 0 then "LobeL" else "LobeR",
				Vector3.new(0.56 * s, 0.56 * s, 0.3 * s),
				CFrame.new(sgn * 0.22 * s, 0.14 * s, 0)
			)
			wedge(if sgn < 0 then "TipL" else "TipR", sgn)
			first = first or lobe
		end
	end
	return first
end

function Lib.Soul(color: Color3, size: number?): Model
	local s = size or 1.2
	local SoulProp = Lib.Prop("Soul")
	if SoulProp and type(SoulProp.Build) == "function" then
		local ok, m = pcall(SoulProp.Build, color, s)
		if ok and typeof(m) == "Instance" and m:IsA("Model") then
			prepModel(m)
			return m
		end
	end
	local model = Instance.new("Model")
	model.Name = "SoulFX"
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Parent = model
	heartParts(model, color, s)
	model.PrimaryPart = core
	return model
end

function Lib.SoulBroken(color: Color3, size: number?): Model
	local s = size or 1.2
	local SoulProp = Lib.Prop("Soul")
	if SoulProp and type(SoulProp.BuildBroken) == "function" then
		local ok, m = pcall(SoulProp.BuildBroken, color, s)
		if ok and typeof(m) == "Instance" and m:IsA("Model") then
			prepModel(m)
			return m
		end
	end
	local model = Instance.new("Model")
	model.Name = "SoulBrokenFX"
	for _, side in { -1, 1 } do
		local half = Instance.new("Model")
		half.Name = if side < 0 then "LeftHalf" else "RightHalf"
		local first = heartParts(half, color, s, side)
		half.PrimaryPart = first
		half.Parent = model
	end
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Parent = model
	model.PrimaryPart = core
	return model
end

---------------------------------------------------------------------------------------------------
-- Sans attack eye (flame + light + pupil tint), flickering cyan <-> yellow

type EyeState = {
	Att: Attachment,
	Light: PointLight?,
	Fire: ParticleEmitter,
	Glow: ParticleEmitter,
	Pupil: BasePart?,
	PupilColor: Color3?,
	PupilSize: Vector3?,
	Colors: { Color3 },
	Intensity: number,
	On: boolean,
	Dead: boolean,
}

local eyes: { EyeState } = {}
local eyeConn: any = nil

local function eyeTick()
	local t = os.clock()
	local phase = math.floor(t * 12) % 2
	local i = 1
	while i <= #eyes do
		local e = eyes[i]
		if e.Dead or e.Att.Parent == nil then
			table.remove(eyes, i)
		else
			if e.On then
				local c = e.Colors[phase + 1]
				local flick = 0.85 + 0.15 * math.sin(t * 31)
				if e.Light then
					e.Light.Color = c
					e.Light.Brightness = 3.2 * e.Intensity * flick
				end
				if e.Pupil then
					e.Pupil.Color = c
				end
			end
			i += 1
		end
	end
	if #eyes == 0 and eyeConn then
		eyeConn:Disconnect()
		eyeConn = nil
	end
end

-- opts: { Pupil: BasePart?, Colors: {Color3}? [{EyeCyan, EyeYellow}], Intensity: number? [1], Size: number? [1] }
function Lib.EyeFlame(att: Attachment, opts: { [string]: any }?): any
	local o = opts or {}
	local colors: { Color3 } = o.Colors or { Lib.Colors.EyeCyan, Lib.Colors.EyeYellow }
	local size: number = o.Size or 1
	local fire = Lib.Emitter("Ember", att, {
		Texture = TEX.Fire,
		Size = ns(0, 0.55 * size, 0.5, 0.42 * size, 1, 0),
		Transparency = ns(0, 0.15, 0.6, 0.4, 1, 1),
		Lifetime = NumberRange.new(0.22, 0.36),
		Speed = NumberRange.new(1.2 * size, 2.4 * size),
		Acceleration = Vector3.new(0, 7 * size, 0),
		SpreadAngle = Vector2.new(12, 12),
		Rate = 0,
		LightEmission = 1,
		Brightness = 5,
		Color = ColorSequence.new(colors[1], colors[2] or colors[1]),
		LockedToPart = false,
		ZOffset = 0.2,
	})
	fire.Color = ColorSequence.new(colors[1], colors[2] or colors[1])
	local glow = Lib.Emitter("Glow", att, {
		Size = ns(0, 0.9 * size, 1, 0.6 * size),
		Transparency = ns(0, 0.35, 1, 1),
		Lifetime = NumberRange.new(0.12),
		Rate = 0,
		LockedToPart = true,
		Brightness = 3,
		ZOffset = 0.3,
	})
	glow.Color = ColorSequence.new(colors[1], colors[2] or colors[1])
	local light = Lib.Light(att, colors[1], 0, 9 * size)
	local pupil: BasePart? = o.Pupil
	local state: EyeState = {
		Att = att,
		Light = light,
		Fire = fire,
		Glow = glow,
		Pupil = pupil,
		PupilColor = if pupil then pupil.Color else nil,
		PupilSize = if pupil then pupil.Size else nil,
		Colors = colors,
		Intensity = o.Intensity or 1,
		On = false,
		Dead = false,
	}
	table.insert(eyes, state)
	if eyeConn == nil then
		eyeConn = RunService.PreRender:Connect(eyeTick)
	end
	local handle = {}
	function handle.SetEnabled(_self: any, on: boolean)
		if state.Dead or state.On == on then
			return
		end
		state.On = on
		local scale = Lib.ParticleScale()
		fire.Rate = if on then 42 * scale * state.Intensity else 0
		glow.Rate = if on then 22 * scale else 0
		if light then
			light.Brightness = if on then 3 * state.Intensity else 0
		end
		local p = state.Pupil
		if p and p.Parent then
			if on then
				p.Size = (state.PupilSize or p.Size) * 1.35
			else
				p.Color = state.PupilColor or p.Color
				p.Size = state.PupilSize or p.Size
			end
		end
	end
	function handle.SetIntensity(_self: any, x: number)
		state.Intensity = math.max(0, x)
		if state.On then
			fire.Rate = 42 * Lib.ParticleScale() * state.Intensity
		end
	end
	function handle.Destroy(_self: any)
		if state.Dead then
			return
		end
		handle.SetEnabled(handle, false)
		state.Dead = true
		fire.Rate = 0
		glow.Rate = 0
		task.delay(0.5, function()
			fire:Destroy()
			glow:Destroy()
			if light then
				light:Destroy()
			end
		end)
	end
	return handle
end

return Lib
