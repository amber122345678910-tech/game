--!strict
-- HazardVisuals (client controller, Priority 31): renders every hazard from its HazardPacket (SPEC §7.6) using the
-- SAME params and Shared/Combat/HazardDefs geometry as the server, sampled every frame at
-- t = Workspace:GetServerTimeNow() - packet.t0. What you see is what hits you (visuals >= server volumes).
--
-- Telegraphs (VFX/Lib.Telegraph, from HazardDefs.Telegraph): ground rings / discs / lanes / warning rays in the
-- colour rule (White, Blue #14A9FF = moving hurts, Orange #FFA040 = standing still hurts, Red, Purple, ...),
-- shown during [delay - warn, delay] with a fill that reaches the rim at the moment damage starts, a blink
-- in the last 30 % and a short impact flash.
-- Types: BlasterBeam (Gaster Blaster: fly-in, exponential aim ease, jaw opens in frames, eyes + converging
-- charge particles, 3-layer wobbling beam with lights, recoil, fade), BoneLine, BoneSpikes, BoneProjectile,
-- Projectile (visual registry), Shockwave, Orb, Zone, Rain, plus a generic volume renderer for kit-registered
-- hazard types (or HazardVisuals.RegisterRenderer).
--
-- API
--   HazardVisuals.Spawn(packet)                 start rendering (FxController forwards Net "Hazard")
--   HazardVisuals.End(id)                       early end (Net "HazardEnd": projectile hit, removal)
--   HazardVisuals.Clear()                       HazardVisuals.Count() -> number      HazardVisuals.Get(id) -> rec?
--   HazardVisuals.RegisterVisual(name, builder) projectile / rain / zone / orb visuals by params.visual
--        builder(ctx) -> visual { Update: (self, cf: CFrame, t: number, dt: number) -> ()?,
--                                 Impact: (self, pos: Vector3) -> ()?, Destroy: (self) -> () }
--        ctx = { Packet, Params, Type, Kind ("Projectile"|"Rain"|"Zone"|"Orb"), Color: Color3, Rule: string,
--                Style: string, Size: number (radius / drop size / bone length), Lib }
--        Built-in visuals: Orb, Bone, Bullet, Ribbon, Page, Dish, StarBone, Chain, Star, Fireball, Knife, VoidOrb
--   HazardVisuals.HasVisual(name) -> boolean    HazardVisuals.Visuals() -> {string}
--   HazardVisuals.RegisterRenderer(type, renderer)   renderer = { Create(rec), Update(rec, t, dt) -> boolean,
--                                               Destroy(rec), EndEarly(rec, t)?, NoTelegraph: boolean? }
--   HazardVisuals.AcquireBlaster(style, width, opts?) -> Blaster   (opts.Ghost: translucent preview, never HD)
--        blaster:Pose(muzzleCFrame, jawAngle) :SetEyes(0..1, color?) :SetTransparency(t) :SetGhost(on)
--        :Release()
-- Pure helpers (Lune-tested): BeamLayers(params, t) -> (core, mid, outer, alpha, phase),
--   BlasterPose(params, t) -> pose {Pos, Look, Jaw, Eyes, Alpha, Recoil, Phase},
--   SpikeFrac(params, t) -> 0..1, RainFall(params, drop, t) -> (state, height), BlasterScale(width, nominal)
-- Perf: one PreRender loop; pooled parts/bones/blasters (VFX/Lib, VFX/Pool); BulkMoveTo for multi-part movers;
-- particle counts scaled by GraphicsController.ParticleScale(); lights budgeted by Lib.Light.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HazardDefs = require(Shared:WaitForChild("Combat"):WaitForChild("HazardDefs")) :: any
local Lib = require(script.Parent.Parent:WaitForChild("VFX"):WaitForChild("Lib")) :: any
local Pool = require(script.Parent.Parent:WaitForChild("VFX"):WaitForChild("Pool")) :: any

local HazardVisuals = {}
HazardVisuals.Priority = 31

local LookAlong = HazardDefs.LookAlong
local AxisFrame = HazardDefs.AxisFrame
local ROT_X_TO_LOOK = CFrame.Angles(0, math.pi / 2, 0) -- cylinder X axis along a LookAlong frame's look
local FLY_TIME = 0.25

type Params = { [string]: any }

---------------------------------------------------------------------------------------------------
-- Small helpers

local function num(p: Params, key: string, default: number): number
	local v = p[key]
	if type(v) == "number" and v == v then
		return v
	end
	return default
end

local function clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

local controllerCache: { [string]: any } = {}
local function controller(name: string): any?
	local c = controllerCache[name]
	if c ~= nil then
		return c or nil
	end
	local m = script.Parent:FindFirstChild(name)
	local result: any = false
	if m and m:IsA("ModuleScript") then
		local ok, r = pcall(require, m)
		if ok and type(r) == "table" then
			result = r
		end
	end
	controllerCache[name] = result
	if result == false then
		task.delay(5, function()
			if controllerCache[name] == false then
				controllerCache[name] = nil
			end
		end)
	end
	return result or nil
end

local function playSound(name: string, at: any?, opts: any?)
	local s = controller("SoundController")
	if s and type(s.Play) == "function" then
		pcall(s.Play, name, at, opts)
	end
end

local function shake(intensity: number, duration: number)
	if intensity <= 0.01 then
		return
	end
	local cam = controller("CameraController")
	if cam and type(cam.Shake) == "function" then
		pcall(cam.Shake, intensity, duration)
	end
end

-- Focus point of the local viewer (character root, else camera).
local function viewerPos(): Vector3?
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local cam = game:GetService("Workspace").CurrentCamera
	return if cam then cam.CFrame.Position else nil
end

local function distToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

-- Shake scaled by distance (full inside `near`, none beyond `far`).
local function shakeNear(pos: Vector3, near: number, far: number, intensity: number, duration: number)
	local v = viewerPos()
	if v == nil then
		return
	end
	local d = (v - pos).Magnitude
	if d >= far then
		return
	end
	local k = if d <= near then 1 else 1 - (d - near) / math.max(1e-3, far - near)
	shake(intensity * k, duration)
end

---------------------------------------------------------------------------------------------------
-- Pure helpers (also used by tests)

-- Beam layer diameters at time t: core = outer / 2, mid = outer / 1.25 (research: 3 stacked layers),
-- sine wobble sin(t*20) (period ~0.31 s), full size from `delay` (the visual appears 0.06 s early and is never
-- thinner than `width` while damage is possible), then x0.8 per 30 Hz frame and -10 % opacity per frame.
function HazardVisuals.BeamLayers(p: Params, t: number): (number, number, number, number, string)
	local delay = num(p, "delay", 0.6)
	local duration = num(p, "duration", 0.5)
	local linger = num(p, "linger", 0.35)
	local width = math.max(0.1, num(p, "width", 4))
	local start = delay - 0.06
	if t < start then
		return 0, 0, 0, 0, "Charge"
	end
	local outer: number
	local alpha: number
	local phase: string
	if t <= delay + duration then
		local ramp = clamp01((t - start) / 0.06)
		local wob = math.sin((t - delay) * 20)
		outer = width * ramp * (1.08 + 0.08 * wob)
		alpha = 1
		phase = "Fire"
	else
		local tau = t - (delay + duration)
		if tau > linger then
			return 0, 0, 0, 0, "Done"
		end
		local k = 0.8 ^ (tau * 30)
		outer = width * 1.08 * k
		alpha = math.max(0, 1 - tau * 3)
		phase = "Fade"
	end
	return outer / 2, outer / 1.25, outer, alpha, phase
end

-- Scale for a blaster model whose nominal skull width is `nominal` so it frames a beam of `width`.
function HazardVisuals.BlasterScale(width: number, nominal: number): number
	return math.clamp(width * 1.25 / math.max(0.1, nominal), 0.4, 6)
end

-- Gaster Blaster pose at time t (pure): fly-in from spawnFrom (or from above/behind) in FLY_TIME with an
-- overshoot, exponential aim ease (Ang += (End-Ang)*dt*10, research §3), jaw opening in frames before the
-- beam, hollow eyes while firing, recoil accelerating backwards, fade out after the beam.
-- Returns { Pos (muzzle), Look (unit), Jaw (radians), Eyes (0..1), Alpha (0..1 opacity), Recoil (studs), Phase }.
function HazardVisuals.BlasterPose(p: Params, t: number): { [string]: any }
	local origin: CFrame = if typeof(p.origin) == "CFrame" then p.origin else CFrame.identity
	local look = origin.LookVector
	local delay = num(p, "delay", 0.6)
	local duration = num(p, "duration", 0.5)
	local linger = num(p, "linger", 0.35)
	local final = origin.Position
	local from: Vector3
	if typeof(p.spawnFrom) == "Vector3" then
		from = (p.spawnFrom :: Vector3) + Vector3.new(0, 1.5, 0)
	else
		from = final + Vector3.new(0, 9, 0) - look * 5
	end
	local fly = math.min(FLY_TIME, math.max(0.08, delay * 0.45))
	local pos: Vector3
	if t < fly then
		local u = clamp01(t / fly)
		-- ease out back (small overshoot past the slot, then settle)
		local c1, c3 = 1.4, 2.4
		local y = u - 1
		local e = 1 + c3 * y * y * y + c1 * y * y
		pos = from:Lerp(final, e)
	else
		pos = final
	end
	-- aim
	local startDir = final - from
	local startLook = if startDir.Magnitude > 0.5 then startDir.Unit else look
	local a = 1 - math.exp(-10 * math.max(0, t))
	a = math.max(a, clamp01((t - (delay - 0.25)) / 0.12))
	local rot = LookAlong(Vector3.zero, startLook):Lerp(LookAlong(Vector3.zero, look), a)
	local lookNow = rot.LookVector
	-- jaw frames (research: closed -> slightly open -> split wide just before the beam)
	local jaw: number
	local fireAt = delay
	if t < fireAt - 0.32 then
		jaw = 0
	elseif t < fireAt - 0.12 then
		local frame = math.floor((t - (fireAt - 0.32)) / 0.0667) + 1
		jaw = math.min(3, frame) * 0.07
	elseif t < fireAt + duration then
		jaw = if t < fireAt then 0.5 else 0.58 + 0.04 * math.sin(t * 40)
	else
		jaw = math.max(0.2, 0.58 - (t - fireAt - duration) * 1.2)
	end
	-- eyes: charge glow, hollow while firing
	local eyes: number
	if t < fly then
		eyes = 0.15
	elseif t < fireAt then
		eyes = 0.15 + 0.85 * clamp01((t - fly) / math.max(0.05, fireAt - fly - 0.08))
	else
		eyes = 0
	end
	-- recoil (backwards along the beam): gentle while firing, then accelerating away
	local recoil = 0
	if t > fireAt then
		local tau = math.min(t - fireAt, duration)
		recoil = 0.5 * 9 * tau * tau
		if t > fireAt + duration then
			local tau2 = t - fireAt - duration
			recoil += 9 * duration * tau2 + 0.5 * 140 * tau2 * tau2
		end
	end
	pos -= look * recoil
	-- opacity
	local alpha = clamp01(t / 0.08)
	local phase = if t < fly
		then "FlyIn"
		elseif t < fireAt then "Charge"
		elseif t <= fireAt + duration then "Fire"
		else "Leave"
	if t > fireAt + duration then
		alpha = 1 - clamp01((t - fireAt - duration) / math.max(0.05, linger))
	end
	return { Pos = pos, Look = lookNow, Jaw = jaw, Eyes = eyes, Alpha = alpha, Recoil = recoil, Phase = phase }
end

-- Visual spike height fraction (pure): tips peek 0.12 s before damage, rise with overshoot, hold, retract.
function HazardVisuals.SpikeFrac(p: Params, t: number): number
	local delay = num(p, "delay", 0.6)
	local rise = math.max(0.01, num(p, "rise", 0.12))
	local hold = num(p, "hold", 0.45)
	local retract = math.max(0.01, num(p, "retract", 0.2))
	if t < delay - 0.12 then
		return 0
	elseif t < delay then
		return 0.08 * clamp01((t - (delay - 0.12)) / 0.12)
	elseif t < delay + rise then
		local u = clamp01((t - delay) / rise)
		local c1, c3 = 1.2, 2.2
		local y = u - 1
		return 0.08 + 0.92 * (1 + c3 * y * y * y + c1 * y * y)
	elseif t < delay + rise + hold then
		return 1
	elseif t < delay + rise + hold + retract then
		local u = clamp01((t - delay - rise - hold) / retract)
		return 1 - u * u
	end
	return 0
end

-- Rain drop state (pure): "Wait" | "Fall" (height above ground) | "Stuck" | "Gone".
function HazardVisuals.RainFall(p: Params, drop: { [string]: any }, t: number): (string, number)
	local fallTime = math.max(0.05, num(p, "fallTime", 0.35))
	local fallHeight = num(p, "fallHeight", 30)
	local impact: number = drop.ImpactTime
	local stay = num(p, "impactTime", 0.12) + 0.35
	if t < impact - fallTime then
		return "Wait", fallHeight
	elseif t < impact then
		local u = clamp01((t - (impact - fallTime)) / fallTime)
		return "Fall", fallHeight * (1 - u * u)
	elseif t < impact + stay then
		return "Stuck", 0
	end
	return "Gone", 0
end

---------------------------------------------------------------------------------------------------
-- Gaster Blasters: Rigs/Props/GasterBlaster (upgraded in the background with HDMesh.ApplyToModel when the HD tier
-- is available) or a built-in mini blaster; pooled per style + scale bucket

type Blaster = {
	Model: Model,
	Kind: string,
	Parts: { BasePart },
	Offsets: { CFrame },
	JawMask: { boolean },
	Hinge: CFrame,
	HingeInv: CFrame,
	Muzzle: Vector3,
	Eyes: { BasePart },
	EyeColors: { Color3 },
	BaseT: { number },
	BaseMat: { Enum.Material },
	BaseColor: { Color3 },
	CFrames: { CFrame },
	Key: string,
	Transparency: number,
	Ghost: boolean,
	Glow: number,
	Extra: { BasePart },
	ExtraT: { number },
	Pose: (self: any, muzzleCF: CFrame, jaw: number) -> (),
	SetEyes: (self: any, glow: number, color: Color3?) -> (),
	SetTransparency: (self: any, t: number) -> (),
	SetGhost: (self: any, on: boolean) -> (),
	Refresh: (self: any) -> (),
	Release: (self: any) -> (),
}

local STYLE_COLORS: { [string]: { Core: Color3, Mid: Color3, Outer: Color3, Eye: Color3, Charge: Color3 } } = {
	Classic = {
		Core = Color3.fromRGB(255, 255, 255),
		Mid = Color3.fromRGB(235, 250, 255),
		Outer = Color3.fromRGB(190, 240, 255),
		Eye = Color3.fromRGB(150, 245, 255),
		Charge = Color3.fromRGB(200, 250, 255),
	},
	Fell = {
		Core = Color3.fromRGB(255, 245, 240),
		Mid = Color3.fromRGB(255, 120, 110),
		Outer = Color3.fromRGB(255, 40, 40),
		Eye = Color3.fromRGB(255, 60, 50),
		Charge = Color3.fromRGB(255, 110, 90),
	},
	Eclipse = {
		Core = Color3.fromRGB(250, 235, 255),
		Mid = Color3.fromRGB(190, 120, 255),
		Outer = Color3.fromRGB(110, 50, 210),
		Eye = Color3.fromRGB(255, 200, 90),
		Charge = Color3.fromRGB(200, 150, 255),
	},
}
HazardVisuals.StyleColors = STYLE_COLORS

local function styleColors(style: string, rule: string?): { [string]: Color3 }
	local base = STYLE_COLORS[style] or STYLE_COLORS.Classic
	if rule and rule ~= "White" and rule ~= "" then
		-- the colour rule always wins for the outer layers: readability first
		local c = Lib.Color(rule)
		return { Core = base.Core, Mid = c:Lerp(Color3.new(1, 1, 1), 0.35), Outer = c, Eye = c, Charge = c }
	end
	return base :: any
end

local blasterPools: { [string]: { Blaster } } = {}
local nominalWidth: { [string]: number } = {}
local hdModule: any = nil

local function hd(): any?
	if hdModule == nil then
		hdModule = false
		local vfx = script.Parent.Parent:FindFirstChild("VFX")
		local m = vfx and vfx:FindFirstChild("HDMesh")
		if m and m:IsA("ModuleScript") then
			local ok, r = pcall(require, m)
			if ok and type(r) == "table" then
				hdModule = r
			end
		end
	end
	return hdModule or nil
end

local function hdAvailable(): boolean
	local h = hd()
	if h == nil or type(h.Available) ~= "function" then
		return false
	end
	local ok, on = pcall(h.Available)
	return ok and on == true
end

-- Built-in fallback blaster (~13 parts) used only when Rigs/Props/GasterBlaster is unavailable.
local function buildMiniBlaster(w: number): Model
	local model = Instance.new("Model")
	model.Name = "MiniBlaster"
	local white = Color3.fromRGB(245, 245, 245)
	local dark = Color3.fromRGB(15, 15, 22)
	local function part(
		name: string,
		shape: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		parent: Instance,
		mat: Enum.Material?
	): BasePart
		local p: BasePart
		if shape == "Wedge" then
			p = Instance.new("WedgePart")
		else
			local pp = Instance.new("Part")
			pp.Shape = if shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Block
			p = pp
		end
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape == "Ellipsoid" then
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = p
		end
		p.Parent = parent
		return p
	end
	local core =
		part("Core", "Ellipsoid", Vector3.new(w, 0.78 * w, 1.15 * w), CFrame.new(0, 0.12 * w, 0.15 * w), white, model)
	part(
		"Snout",
		"Ellipsoid",
		Vector3.new(0.62 * w, 0.42 * w, 0.85 * w),
		CFrame.new(0, -0.04 * w, -0.5 * w),
		white,
		model
	)
	part("Ridge", "Block", Vector3.new(0.1 * w, 0.12 * w, 0.9 * w), CFrame.new(0, 0.48 * w, 0.0), white, model)
	for _, s in { -1, 1 } do
		part(
			"Socket",
			"Ellipsoid",
			Vector3.new(0.3 * w, 0.24 * w, 0.2 * w),
			CFrame.new(s * 0.23 * w, 0.2 * w, -0.4 * w),
			dark,
			model
		)
		local eye = part(
			"Eye",
			"Ball",
			Vector3.one * (0.1 * w),
			CFrame.new(s * 0.23 * w, 0.2 * w, -0.47 * w),
			Color3.new(1, 1, 1),
			model,
			Enum.Material.Neon
		)
		eye:SetAttribute("Role", "Eye")
		part(
			"Horn",
			"Wedge",
			Vector3.new(0.12 * w, 0.55 * w, 0.4 * w),
			CFrame.new(s * 0.42 * w, 0.45 * w, 0.55 * w) * CFrame.Angles(math.rad(-25), 0, s * math.rad(-20)),
			white,
			model
		)
	end
	local jaw = Instance.new("Model")
	jaw.Name = "Jaw"
	part(
		"Mandible",
		"Ellipsoid",
		Vector3.new(0.58 * w, 0.18 * w, 0.85 * w),
		CFrame.new(0, -0.3 * w, -0.42 * w),
		white,
		jaw
	)
	part("Teeth", "Block", Vector3.new(0.46 * w, 0.06 * w, 0.06 * w), CFrame.new(0, -0.2 * w, -0.8 * w), dark, jaw)
	jaw.Parent = model
	local hinge = Instance.new("Attachment")
	hinge.Name = "JawHinge"
	hinge.CFrame = core.CFrame:Inverse() * CFrame.new(0, -0.22 * w, 0.05 * w)
	hinge.Parent = core
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = core.CFrame:Inverse() * CFrame.new(0, -0.22 * w, -0.95 * w)
	muzzle.Parent = core
	model.PrimaryPart = core
	return model
end

-- Measures a model's X extent (skull width) from its visible parts.
local function modelWidth(model: Model): number
	local minX, maxX = math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local cf, s = d.CFrame, d.Size
			for _, sx in { -0.5, 0.5 } do
				for _, sy in { -0.5, 0.5 } do
					for _, sz in { -0.5, 0.5 } do
						local x = (cf * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)).X
						minX = math.min(minX, x)
						maxX = math.max(maxX, x)
					end
				end
			end
		end
	end
	return if maxX > minX then maxX - minX else 1
end

-- Pure: world CFrames of a blaster's parts for a muzzle frame (Position = muzzle, LookVector = facing) and a jaw
-- angle (radians, Rx(-angle) about the Core's JawHinge opens it). `offsets` are rest CFrames relative to the Core's
-- position (model built at the origin facing -Z); results go into `out`.
local function blasterFrames(
	muzzleCF: CFrame,
	muzzle: Vector3,
	hinge: CFrame,
	hingeInv: CFrame,
	jaw: number,
	offsets: { CFrame },
	jawMask: { boolean },
	out: { CFrame }
)
	local frame = muzzleCF * CFrame.new(-muzzle)
	local jawCF = hinge * CFrame.Angles(-jaw, 0, 0) * hingeInv
	for i = 1, #offsets do
		if jawMask[i] then
			out[i] = frame * jawCF * offsets[i]
		else
			out[i] = frame * offsets[i]
		end
	end
end

-- Turns a built blaster model (Rigs/Props/GasterBlaster or the mini fallback) into an animatable Blaster:
-- every part is anchored and moved with one BulkMoveTo from cached offsets; jaw parts rotate about the
-- Core's JawHinge (Rx(-angle) opens, like GasterBlaster.SetJaw / HDMesh.PoseBlasterJaw).
local function rigBlaster(model: Model, kind: string, key: string): Blaster
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local jawMask: { boolean } = {}
	local eyes: { BasePart } = {}
	local baseT: { number } = {}
	local baseMat: { Enum.Material } = {}
	local baseColor: { Color3 } = {}
	local hingeCF = CFrame.identity
	local muzzle = Vector3.new(0, 0, -1)
	local root: BasePart? = model.PrimaryPart or model:FindFirstChild("Core") :: BasePart?
	if root == nil then
		root = model:FindFirstChildWhichIsA("BasePart", true)
	end
	-- reference frame: the model as built (at the origin, facing -Z), positioned at the core
	local ref = CFrame.new(if root then root.CFrame.Position else Vector3.zero)
	local refInv = ref:Inverse()
	if root then
		local h = root:FindFirstChild("JawHinge")
		if h and h:IsA("Attachment") then
			hingeCF = refInv * root.CFrame * h.CFrame
		end
		local m = root:FindFirstChild("Muzzle")
		if m and m:IsA("Attachment") then
			muzzle = (refInv * root.CFrame * m.CFrame).Position
		end
	end
	local jawModel = model:FindFirstChild("Jaw")
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			table.insert(parts, d)
			table.insert(offsets, refInv * d.CFrame)
			table.insert(jawMask, jawModel ~= nil and d:IsDescendantOf(jawModel))
			table.insert(baseT, d.Transparency)
			table.insert(baseMat, d.Material)
			table.insert(baseColor, d.Color)
			if d:GetAttribute("Role") == "Eye" then
				table.insert(eyes, d)
			end
		end
	end
	local eyeColors: { Color3 } = {}
	for i, e in eyes do
		eyeColors[i] = e.Color
	end
	local maxOpen = model:GetAttribute("JawMaxOpen")
	local Prop = if kind == "Prop" then Lib.Prop("GasterBlaster") else nil
	local self: any = {
		Model = model,
		Kind = kind,
		Parts = parts,
		Offsets = offsets,
		JawMask = jawMask,
		Hinge = hingeCF,
		HingeInv = hingeCF:Inverse(),
		Muzzle = muzzle,
		Eyes = eyes,
		EyeColors = eyeColors,
		BaseT = baseT,
		BaseMat = baseMat,
		BaseColor = baseColor,
		CFrames = table.create(#parts),
		Key = key,
		Transparency = 0,
		Ghost = false,
		Glow = -1,
		Extra = {} :: { BasePart },
		ExtraT = {} :: { number },
	}
	local W = game:GetService("Workspace")
	function self.Pose(_s: any, muzzleCF: CFrame, jaw: number)
		-- muzzleCF: Position = muzzle point, LookVector = facing
		local a = if type(maxOpen) == "number" then math.min(jaw, maxOpen * 1.1) else jaw
		local cfs = self.CFrames
		blasterFrames(muzzleCF, self.Muzzle, self.Hinge, self.HingeInv, a, self.Offsets, self.JawMask, cfs)
		W:BulkMoveTo(self.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- glow 0..1 (charge); 0 = hollow sockets (firing). Prop blasters use GasterBlaster.SetGlow (rate-limited).
	function self.SetEyes(_s: any, glow: number, color: Color3?)
		local c = color or Color3.new(1, 1, 1)
		if Prop and type(Prop.SetGlow) == "function" and not self.Ghost then
			local g = if glow <= 0.02 then 1 else glow -- mouth + halos stay lit while firing
			if math.abs(g - self.Glow) > 0.04 or (g == 1 and self.Glow ~= 1) then
				self.Glow = g
				pcall(Prop.SetGlow, model, c, g)
			end
		end
		for i, e in self.Eyes do
			if glow <= 0.02 then
				e.Transparency = 1 -- hollow sockets (research: frames 3-5)
			elseif not Prop then
				e.Transparency = math.max(self.Transparency, 1 - glow)
				e.Color = (self.EyeColors[i] or Color3.new(1, 1, 1)):Lerp(c, 0.6)
			elseif self.Transparency > 0 then
				e.Transparency = math.max(e.Transparency, self.Transparency)
			end
		end
	end
	function self.SetTransparency(_s: any, t: number)
		if t == self.Transparency or (math.abs(t - self.Transparency) < 0.04 and t > 0.01 and t < 0.99) then
			return
		end
		self.Transparency = t
		for i, p in self.Parts do
			local base = if self.Ghost then 0.55 else self.BaseT[i]
			if base < 0.999 then
				p.Transparency = base + (1 - base) * t
			end
		end
		for i, p in self.Extra do
			p.Transparency = self.ExtraT[i] + (1 - self.ExtraT[i]) * t
		end
	end
	function self.SetGhost(_s: any, on: boolean)
		if self.Ghost == on then
			return
		end
		self.Ghost = on
		for i, p in self.Parts do
			if self.BaseT[i] < 0.999 then
				if on then
					p.Material = Enum.Material.ForceField
					p.Color = Color3.fromRGB(170, 235, 255)
					p.Transparency = 0.55
				else
					p.Material = self.BaseMat[i]
					p.Color = self.BaseColor[i]
					p.Transparency = self.BaseT[i]
				end
			end
		end
		for _, p in self.Extra do
			p.LocalTransparencyModifier = if on then 1 else 0
		end
	end
	-- picks up MeshParts welded in later (HDMesh.ApplyToModel) so fades include them
	function self.Refresh(_s: any)
		local known: { [BasePart]: boolean } = {}
		for _, p in self.Parts do
			known[p] = true
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and not known[d] and not table.find(self.Extra, d) then
				d.CanQuery = false
				d.CanTouch = false
				d.CanCollide = false
				d.CastShadow = false
				table.insert(self.Extra, d)
				table.insert(self.ExtraT, d.Transparency)
			end
		end
	end
	function self.Release(_s: any)
		if self.Ghost then
			self.SetGhost(self, false)
		end
		self.SetTransparency(self, 0)
		self.Glow = -1
		if Prop and type(Prop.SetGlow) == "function" then
			pcall(Prop.SetGlow, model, Color3.new(1, 1, 1), 0)
		end
		for i, e in self.Eyes do
			e.Color = self.EyeColors[i]
			e.Transparency = 0
		end
		self.Pose(self, Pool.PARK, 0)
		local list = blasterPools[self.Key]
		if list == nil then
			list = {}
			blasterPools[self.Key] = list
		end
		if #list < 8 then
			table.insert(list, self)
		else
			self.Model:Destroy()
		end
	end
	return self
end

local function buildProp(style: string, scale: number): Model?
	local Prop = Lib.Prop("GasterBlaster")
	if Prop and type(Prop.Build) == "function" then
		local ok, m = pcall(Prop.Build, style, scale)
		if ok and typeof(m) == "Instance" and m:IsA("Model") then
			return m
		end
	end
	return nil
end

-- Skull width of the prop at scale 1 (the prop shares the HD meshes' design space).
local function propNominal(style: string): number?
	local n = nominalWidth[style]
	if n ~= nil then
		return if n > 0 then n else nil
	end
	local m = buildProp(style, 1)
	if m == nil then
		nominalWidth[style] = 0
		return nil
	end
	local w = modelWidth(m)
	m:Destroy()
	nominalWidth[style] = w
	return w
end

local function scaleBucket(s: number): number
	return math.floor(s * 4 + 0.5) / 4
end

-- Upgrades a pooled prop blaster to the HD meshes in the background (HDMesh.ApplyToModel yields).
local function upgradeHD(b: Blaster)
	if not hdAvailable() then
		return
	end
	task.spawn(function()
		local h = hd()
		if h == nil or type(h.ApplyToModel) ~= "function" then
			return
		end
		local ok, applied = pcall(h.ApplyToModel, b.Model)
		if ok and applied then
			(b :: any):Refresh()
		end
	end)
end

-- opts.Ghost: a translucent preview blaster (kit indicators). Ghosts come from their own pool and are never
-- upgraded to HD meshes (HDMesh hides the part-built skull that the ghost look relies on).
function HazardVisuals.AcquireBlaster(style: string, width: number, opts: { Ghost: boolean? }?): Blaster
	local ghost = opts ~= nil and opts.Ghost == true
	local nominal = propNominal(style) or propNominal("Classic")
	local kind = if nominal then "Prop" else "Mini"
	local scale = if nominal then scaleBucket(HazardVisuals.BlasterScale(width, nominal)) else scaleBucket(width * 1.25)
	local suffix = if ghost then "|Ghost" else ""
	local key = kind .. "|" .. style .. "|" .. scale .. suffix
	local pool = blasterPools[key]
	while pool and #pool > 0 do
		local b = table.remove(pool) :: Blaster
		if b.Model.Parent ~= nil then
			if ghost then
				b:SetGhost(true)
			end
			return b
		end
	end
	local model: Model? = nil
	if kind == "Prop" then
		model = buildProp(style, scale) or buildProp("Classic", scale)
	end
	if model == nil then
		kind = "Mini"
		scale = scaleBucket(width * 1.25)
		key = kind .. "|" .. style .. "|" .. scale .. suffix
		model = buildMiniBlaster(scale)
	end
	local m = model :: Model
	Lib.PrepModel(m)
	m.Parent = Lib.Folder()
	local b = rigBlaster(m, kind, key)
	if ghost then
		b:SetGhost(true)
	elseif kind == "Prop" then
		upgradeHD(b)
	end
	return b
end

---------------------------------------------------------------------------------------------------
-- Visual registry (projectiles, rain drops, zone / orb variants)

type Visual = {
	Update: ((self: any, cf: CFrame, t: number, dt: number) -> ())?,
	Impact: ((self: any, pos: Vector3) -> ())?,
	Destroy: (self: any) -> (),
}
type Builder = (ctx: { [string]: any }) -> Visual

local visuals: { [string]: Builder } = {}

function HazardVisuals.RegisterVisual(name: string, builder: Builder)
	assert(type(name) == "string" and name ~= "", "HazardVisuals.RegisterVisual: bad name")
	assert(type(builder) == "function", "HazardVisuals.RegisterVisual: builder must be a function")
	visuals[name] = builder
end

function HazardVisuals.HasVisual(name: string): boolean
	return visuals[name] ~= nil
end

function HazardVisuals.Visuals(): { string }
	local out = {}
	for k in visuals do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

-- Generic multi-part visual helper: parts placed relative to a frame every Update.
local function partsVisual(
	parts: { BasePart },
	offsets: { CFrame },
	spin: ((t: number) -> CFrame)?,
	light: PointLight?,
	trail: { [string]: any }?
): Visual
	local cfs: { CFrame } = table.create(#parts)
	local W = game:GetService("Workspace")
	local lastEmit = 0
	local v: any = {}
	function v.Update(_s: any, cf: CFrame, t: number, _dt: number)
		local frame = if spin then cf * spin(t) else cf
		for i = 1, #parts do
			cfs[i] = frame * offsets[i]
		end
		W:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if trail and t - lastEmit > (trail.Every or 0.05) then
			lastEmit = t
			Lib.Emit(trail.Kind or "Mote", cf.Position, trail.Count or 1, { Color = trail.Color })
		end
	end
	function v.Impact(_s: any, pos: Vector3)
		local c = if parts[1] then parts[1].Color else Lib.Colors.White
		Lib.Sparks(pos, nil, c, 8, 18)
		Lib.EmitBurst(pos, 3, c, 0.2)
	end
	function v.Destroy(_s: any)
		for _, p in parts do
			Lib.Release(p)
		end
		if light then
			light:Destroy()
		end
	end
	return v
end

local function orbVisual(ctx: { [string]: any }, coreColor: Color3?, glowScale: number?): Visual
	local r = math.max(0.2, ctx.Size or 0.6)
	local c: Color3 = ctx.Color
	local core = Lib.Part(
		"Ball",
		Vector3.one * (r * 2.1),
		Pool.PARK,
		coreColor or c:Lerp(Color3.new(1, 1, 1), 0.55),
		Enum.Material.Neon,
		0
	)
	local shell = Lib.Part("Ball", Vector3.one * (r * 2 * (glowScale or 1.7)), Pool.PARK, c, Enum.Material.Neon, 0.62)
	local light = Lib.Light(core, c, 2.5, math.min(24, r * 10))
	return partsVisual(
		{ core, shell },
		{ CFrame.identity, CFrame.identity },
		nil,
		light,
		{ Kind = "Mote", Color = c, Every = 0.04 }
	)
end

visuals.Orb = function(ctx)
	return orbVisual(ctx)
end

visuals.Fireball = function(ctx)
	return orbVisual(ctx, Color3.fromRGB(255, 230, 160), 1.9)
end

visuals.VoidOrb = function(ctx)
	local r = math.max(0.3, ctx.Size or 0.8)
	local core =
		Lib.Part("Ball", Vector3.one * (r * 1.9), Pool.PARK, Color3.fromRGB(8, 4, 16), Enum.Material.SmoothPlastic, 0)
	local rim =
		Lib.Part("Ball", Vector3.one * (r * 2.5), Pool.PARK, Color3.fromRGB(150, 70, 255), Enum.Material.Neon, 0.6)
	local light = Lib.Light(rim, Color3.fromRGB(150, 70, 255), 2, math.min(24, r * 10))
	return partsVisual(
		{ core, rim },
		{ CFrame.identity, CFrame.identity },
		nil,
		light,
		{ Kind = "Mote", Color = Color3.fromRGB(170, 110, 255), Every = 0.04 }
	)
end

local function boneVisual(ctx: { [string]: any }, color: Color3?, spinRate: number?): Visual
	local len = math.max(1, ctx.Size or 3)
	local bone = Lib.Bone(math.max(0.35, len * 0.2), len, color or ctx.Color)
	local rate = spinRate or 14
	local W = game:GetService("Workspace")
	local parts: { BasePart } = table.create(5)
	local cfs: { CFrame } = table.create(5)
	local v: any = {}
	function v.Update(_s: any, cf: CFrame, t: number, _dt: number)
		-- bone perpendicular to the flight, tumbling about the flight axis
		local frame = cf * CFrame.Angles(0, 0, t * rate)
		local n = bone:Write(frame, parts, cfs, 0)
		W:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		for i = n + 1, #parts do
			parts[i] = nil
		end
	end
	function v.Impact(_s: any, pos: Vector3)
		Lib.Sparks(pos, nil, Lib.Colors.White, 9, 18)
		Lib.Emit("Debris", pos, 4, { Color = Color3.fromRGB(235, 235, 235) })
	end
	function v.Destroy(_s: any)
		bone:Release()
	end
	return v
end

visuals.Bone = function(ctx)
	return boneVisual(ctx)
end

visuals.StarBone = function(ctx)
	local v = boneVisual(ctx, Color3.fromRGB(255, 214, 90), 10)
	local star = Lib.Part("Ball", Vector3.one * 0.9, Pool.PARK, Color3.fromRGB(255, 240, 170), Enum.Material.Neon, 0.15)
	local light = Lib.Light(star, Color3.fromRGB(255, 220, 120), 2, 12)
	local upd = v.Update
	local last = 0
	local wrapped: any = {}
	function wrapped.Update(s: any, cf: CFrame, t: number, dt: number)
		if upd then
			upd(s, cf, t, dt)
		end
		star.CFrame = cf
		if t - last > 0.05 then
			last = t
			Lib.Emit("Star", cf.Position, 1, { Color = Color3.fromRGB(255, 225, 120), Speed = { 0.5, 2 } })
		end
	end
	wrapped.Impact = v.Impact
	function wrapped.Destroy(s: any)
		v.Destroy(s)
		Lib.Release(star)
		if light then
			light:Destroy()
		end
	end
	return wrapped
end

visuals.Bullet = function(ctx)
	local c: Color3 = if ctx.Rule == "White" then Lib.Colors.Yellow else ctx.Color
	local r = math.max(0.15, ctx.Size or 0.3)
	local body = Lib.Part(
		"Cylinder",
		Vector3.new(r * 5, r * 1.3, r * 1.3),
		Pool.PARK,
		Color3.fromRGB(255, 250, 220),
		Enum.Material.Neon,
		0
	)
	local glow = Lib.Part("Cylinder", Vector3.new(r * 9, r * 2.6, r * 2.6), Pool.PARK, c, Enum.Material.Neon, 0.6)
	return partsVisual(
		{ body, glow },
		{ ROT_X_TO_LOOK, CFrame.new(0, 0, r * 2) * ROT_X_TO_LOOK },
		nil,
		nil,
		{ Kind = "Mote", Color = c, Every = 0.03 }
	)
end

visuals.Knife = function(ctx)
	local c: Color3 = ctx.Color
	local blade = Lib.Part(
		"Wedge",
		Vector3.new(0.12, 0.35, 1.6),
		Pool.PARK,
		Color3.fromRGB(235, 235, 245),
		Enum.Material.Metal,
		0
	)
	local edge = Lib.Part("Block", Vector3.new(0.05, 0.08, 1.7), Pool.PARK, c, Enum.Material.Neon, 0.2)
	return partsVisual(
		{ blade, edge },
		{ CFrame.identity, CFrame.new(0, -0.15, 0) },
		nil,
		nil,
		{ Kind = "Mote", Color = c, Every = 0.05 }
	)
end

visuals.Ribbon = function(ctx)
	local c: Color3 = if ctx.Rule == "White" then Lib.Colors.Cyan else ctx.Color
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for i = 0, 3 do
		table.insert(
			parts,
			Lib.Part("Block", Vector3.new(0.7, 0.06, 0.55), Pool.PARK, c, Enum.Material.Neon, 0.05 + i * 0.12)
		)
		table.insert(offsets, CFrame.new(0, 0, i * 0.5))
	end
	local function spin(t: number): CFrame
		return CFrame.Angles(0, 0, math.sin(t * 9) * 0.6)
	end
	local base = partsVisual(parts, offsets, spin, nil, { Kind = "Mote", Color = c, Every = 0.05 })
	local W = game:GetService("Workspace")
	local cfs: { CFrame } = table.create(#parts)
	local v: any = {}
	function v.Update(_s: any, cf: CFrame, t: number, _dt: number)
		for i = 1, #parts do
			local k = i - 1
			cfs[i] = cf
				* CFrame.new(math.sin(t * 12 - k * 0.9) * 0.35, 0, k * 0.5)
				* CFrame.Angles(0, 0, math.sin(t * 9 - k) * 0.7)
		end
		W:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	v.Impact = base.Impact
	v.Destroy = base.Destroy
	return v
end

visuals.Page = function(ctx)
	local c: Color3 = if ctx.Rule == "White" then Lib.Colors.Purple else ctx.Color
	local page = Lib.Part(
		"Block",
		Vector3.new(1.3, 1.7, 0.06),
		Pool.PARK,
		Color3.fromRGB(250, 246, 235),
		Enum.Material.SmoothPlastic,
		0
	)
	local glyph = Lib.Part("Block", Vector3.new(0.8, 0.12, 0.08), Pool.PARK, c, Enum.Material.Neon, 0)
	local glyph2 = Lib.Part("Block", Vector3.new(0.6, 0.12, 0.08), Pool.PARK, c, Enum.Material.Neon, 0)
	local function spin(t: number): CFrame
		return CFrame.Angles(math.sin(t * 7) * 0.5, t * 5, math.sin(t * 5) * 0.4)
	end
	return partsVisual(
		{ page, glyph, glyph2 },
		{ CFrame.identity, CFrame.new(0, 0.25, 0), CFrame.new(-0.1, -0.15, 0) },
		spin,
		nil,
		{ Kind = "Mote", Color = c, Every = 0.06 }
	)
end

visuals.Dish = function(ctx)
	local c: Color3 = if ctx.Rule == "White" then Lib.Colors.Green else ctx.Color
	local r = math.max(0.5, ctx.Size or 0.8)
	local plate = Lib.Part(
		"Cylinder",
		Vector3.new(0.18, r * 2.2, r * 2.2),
		Pool.PARK,
		Color3.fromRGB(245, 245, 240),
		Enum.Material.SmoothPlastic,
		0
	)
	local rim = Lib.Part("Cylinder", Vector3.new(0.12, r * 2.5, r * 2.5), Pool.PARK, c, Enum.Material.Neon, 0.35)
	local function spin(t: number): CFrame
		return CFrame.Angles(0, t * 14, 0) * CFrame.Angles(0, 0, math.pi / 2)
	end
	return partsVisual(
		{ plate, rim },
		{ CFrame.identity, CFrame.new(-0.05, 0, 0) },
		spin,
		nil,
		{ Kind = "Heal", Color = c, Every = 0.07 }
	)
end

visuals.Chain = function(ctx)
	-- hook head + links trailing back to the owner's hand
	local c: Color3 = if ctx.Rule == "White" then Color3.fromRGB(255, 70, 60) else ctx.Color
	local metal = Color3.fromRGB(70, 70, 78)
	local head = Lib.Part("Wedge", Vector3.new(0.35, 0.6, 1.1), Pool.PARK, metal, Enum.Material.Metal, 0)
	local glow = Lib.Part("Ball", Vector3.one * 0.8, Pool.PARK, c, Enum.Material.Neon, 0.4)
	local links: { BasePart } = {}
	for i = 1, 12 do
		links[i] = Lib.Part("Block", Vector3.new(0.18, 0.42, 0.62), Pool.PARK, metal, Enum.Material.Metal, 0)
	end
	local owner: Model? = ctx.Packet and ctx.Packet.owner
	local origin: CFrame = if typeof(ctx.Params.origin) == "CFrame" then ctx.Params.origin else CFrame.identity
	local W = game:GetService("Workspace")
	local all: { BasePart } = { head, glow }
	for _, l in links do
		table.insert(all, l)
	end
	local cfs: { CFrame } = table.create(#all)
	local v: any = {}
	function v.Update(_s: any, cf: CFrame, _t: number, _dt: number)
		local hand = origin.Position
		if owner and owner.Parent then
			local rh = owner:FindFirstChild("RightHand")
			if rh and rh:IsA("BasePart") then
				hand = rh.Position
			end
		end
		cfs[1] = cf
		cfs[2] = cf
		local tip = cf.Position
		local delta = tip - hand
		local dir = if delta.Magnitude > 1e-3 then delta.Unit else cf.LookVector
		for i = 1, #links do
			local f = (i - 0.5) / #links
			local p = hand:Lerp(tip, f)
			cfs[2 + i] = LookAlong(p, dir) * CFrame.Angles(0, 0, if i % 2 == 0 then math.pi / 2 else 0)
		end
		W:BulkMoveTo(all, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	function v.Impact(_s: any, pos: Vector3)
		Lib.Sparks(pos, nil, c, 10, 20)
	end
	function v.Destroy(_s: any)
		for _, p in all do
			Lib.Release(p)
		end
	end
	return v
end

visuals.Star = function(ctx)
	local c: Color3 = if ctx.Rule == "White" then Color3.fromRGB(255, 236, 150) else ctx.Color
	local s = math.max(0.6, (ctx.Size or 2) * 0.45)
	local core = Lib.Part("Ball", Vector3.one * s, Pool.PARK, Color3.fromRGB(255, 252, 235), Enum.Material.Neon, 0)
	local a = Lib.Part("Block", Vector3.new(s * 2.4, s * 0.25, s * 0.25), Pool.PARK, c, Enum.Material.Neon, 0.1)
	local b = Lib.Part("Block", Vector3.new(s * 0.25, s * 2.4, s * 0.25), Pool.PARK, c, Enum.Material.Neon, 0.1)
	local light = Lib.Light(core, c, 2.5, 14)
	local function spin(t: number): CFrame
		return CFrame.Angles(0, t * 6, t * 9)
	end
	return partsVisual(
		{ core, a, b },
		{ CFrame.identity, CFrame.identity, CFrame.identity },
		spin,
		light,
		{ Kind = "Star", Color = c, Every = 0.03 }
	)
end

---------------------------------------------------------------------------------------------------
-- Records & renderers

export type Record = {
	Id: number,
	Type: string,
	T0: number,
	Params: Params,
	Owner: Model?,
	Team: string,
	Packet: { [string]: any },
	Duration: number,
	Rule: string,
	Color: Color3,
	Style: string,
	Telegraph: any?,
	Renderer: any,
	S: { [string]: any },
	EndedAt: number?,
	Dead: boolean,
}

local records: { [number]: Record } = {}
local order: { Record } = {}
local renderers: { [string]: any } = {}
local loopConn: any = nil

local function releaseAll(list: { any }?)
	if list == nil then
		return
	end
	for _, x in list do
		if type(x) == "table" and type(x.Release) == "function" then
			x:Release()
		elseif type(x) == "table" and type(x.Destroy) == "function" then
			x:Destroy()
		else
			Lib.Release(x)
		end
	end
end

-- BlasterBeam ------------------------------------------------------------------------------------
renderers.BlasterBeam = {
	Create = function(rec: Record)
		local p = rec.Params
		local S = rec.S
		local width = num(p, "width", 4)
		S.Colors = styleColors(rec.Style, rec.Rule)
		S.Blaster = HazardVisuals.AcquireBlaster(rec.Style, width)
		S.Blaster:SetTransparency(1)
		S.Width = width
		S.Length = num(p, "length", 60)
		S.Start = HazardDefs.BeamStart(p)
		local origin: CFrame = p.origin
		S.Look = origin.LookVector
		S.Fired = false
		S.LastEmit = 0
		-- charge particles converging into the mouth
		local holder = Lib.Part("Ball", Vector3.one * (width * 2.2), Pool.PARK, S.Colors.Charge, Enum.Material.Neon, 1)
		local charge = Lib.Emitter("Mote", holder, {
			Color = S.Colors.Charge,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			Speed = NumberRange.new(width * 2.4, width * 3),
			Lifetime = NumberRange.new(0.32, 0.4),
			Size = Lib.NS(0, 0.15, 0.5, 0.42, 1, 0.1),
			Rate = 0,
			Drag = 0,
			LockedToPart = true,
		})
		S.ChargeHolder = holder
		S.Charge = charge
		S.EyeLight = Lib.Light(holder, S.Colors.Eye, 0, math.min(30, width * 4))
		if rec.T0 + 0.3 > Lib.Now() then
			playSound("BlasterCharge", origin.Position)
			local from = if typeof(p.spawnFrom) == "Vector3" then p.spawnFrom else origin.Position
			Lib.EmitBurst(from + Vector3.new(0, 1.5, 0), width * 1.6, S.Colors.Charge, 0.25)
		end
	end,
	Update = function(rec: Record, t: number, _dt: number): boolean
		local p = rec.Params
		local S = rec.S
		local blaster: Blaster = S.Blaster
		local pose = HazardVisuals.BlasterPose(p, t)
		local muzzleCF = LookAlong(pose.Pos, pose.Look)
		blaster:Pose(muzzleCF, pose.Jaw)
		blaster:SetTransparency(1 - pose.Alpha)
		blaster:SetEyes(pose.Eyes, S.Colors.Eye)
		local holder: BasePart = S.ChargeHolder
		holder.CFrame = muzzleCF
		local delay = num(p, "delay", 0.6)
		local charging = pose.Phase == "Charge" or pose.Phase == "FlyIn"
		S.Charge.Rate = if charging and t > 0.1 then 70 * Lib.ParticleScale() else 0
		if S.EyeLight then
			S.EyeLight.Brightness = if charging then 1 + 4 * pose.Eyes else 0
		end
		-- beam
		local core, mid, outer, alpha, phase = HazardVisuals.BeamLayers(p, t)
		if phase == "Done" then
			return pose.Alpha > 0.01 or t < delay
		end
		if outer > 0 then
			if not S.Fired then
				S.Fired = true
				local width: number = S.Width
				local C = S.Colors
				S.Core = Lib.Part("Cylinder", Vector3.one, Pool.PARK, C.Core, Enum.Material.Neon, 0)
				S.Mid = Lib.Part("Cylinder", Vector3.one, Pool.PARK, C.Mid, Enum.Material.Neon, 0.25)
				S.Outer = Lib.Part("Cylinder", Vector3.one, Pool.PARK, C.Outer, Enum.Material.Neon, 0.58)
				S.CapMid = Lib.Part("Ball", Vector3.one, Pool.PARK, C.Mid, Enum.Material.Neon, 0.25)
				S.CapOuter = Lib.Part("Ball", Vector3.one, Pool.PARK, C.Outer, Enum.Material.Neon, 0.58)
				S.Lights = {}
				local len: number = S.Length
				for i = -1, 1 do
					local att = Instance.new("Attachment")
					att.Position = Vector3.new(i * len / 3, 0, 0)
					att.Parent = S.Core
					local l = Lib.Light(att, C.Outer, 0, math.clamp(width * 4, 10, 40))
					if l then
						table.insert(S.Lights, l)
					end
				end
				S.Sparkle = Lib.Emitter("Spark", S.Outer, {
					Color = C.Mid,
					Shape = Enum.ParticleEmitterShape.Box,
					EmissionDirection = Enum.NormalId.Right,
					Speed = NumberRange.new(40, 70),
					Lifetime = NumberRange.new(0.15, 0.3),
					SpreadAngle = Vector2.new(4, 4),
					Rate = 70 * Lib.ParticleScale(),
				})
				-- impact point where the beam meets the world (visual only; the server never clips beams)
				local start: Vector3 = S.Start
				local W = game:GetService("Workspace")
				local hit = W:Raycast(start, S.Look * len, Lib.RaycastParams())
				S.ImpactPos = if hit then hit.Position else nil
				S.ImpactNormal = if hit then hit.Normal else nil
				playSound("BlasterFire", start)
				Lib.Flash(start, C.Core, width * 1.6, 0.18)
				local endPos = start + S.Look * len
				local v = viewerPos()
				if v then
					local d = distToSegment(v, start, endPos)
					if d < width + 26 then
						shake(0.5 * (1 - d / (width + 26)) + 0.08, num(p, "duration", 0.5) + 0.15)
					end
				end
			end
			-- place layers: from the recoiled muzzle to the far end
			local look: Vector3 = S.Look
			local start: Vector3 = S.Start
			local back = math.max(0, (start - pose.Pos):Dot(look))
			local s0 = start - look * back
			local len = (S.Length :: number) + back
			local cf = LookAlong(s0 + look * (len / 2), look) * ROT_X_TO_LOOK
			local coreP: BasePart, midP: BasePart, outerP: BasePart = S.Core, S.Mid, S.Outer
			coreP.Size = Vector3.new(len, core, core)
			midP.Size = Vector3.new(len, mid, mid)
			outerP.Size = Vector3.new(len, outer, outer)
			coreP.CFrame = cf
			midP.CFrame = cf
			outerP.CFrame = cf
			coreP.Transparency = 1 - alpha
			midP.Transparency = 0.25 + 0.75 * (1 - alpha)
			outerP.Transparency = 0.58 + 0.42 * (1 - alpha)
			local cm: BasePart, co: BasePart = S.CapMid, S.CapOuter
			cm.Size = Vector3.one * mid
			co.Size = Vector3.one * outer
			cm.CFrame = CFrame.new(s0)
			co.CFrame = CFrame.new(s0)
			cm.Transparency = midP.Transparency
			co.Transparency = outerP.Transparency
			for _, l in S.Lights do
				l.Brightness = 5 * alpha
			end
			S.Sparkle.Rate = if phase == "Fire" then 70 * Lib.ParticleScale() else 0
			-- burning impact point
			local ip: Vector3? = S.ImpactPos
			if ip and phase == "Fire" and t - S.LastEmit > 0.05 then
				S.LastEmit = t
				Lib.Emit("Spark", ip, 4, { Color = S.Colors.Mid, Dir = S.ImpactNormal })
				Lib.Emit("Dust", ip, 1, { Color = Color3.fromRGB(200, 200, 210) })
			end
		end
		return true
	end,
	Destroy = function(rec: Record)
		local S = rec.S
		if S.Blaster then
			S.Blaster:Release()
		end
		for _, k in { "Core", "Mid", "Outer", "CapMid", "CapOuter", "ChargeHolder" } do
			if S[k] then
				Lib.Release(S[k])
				S[k] = nil
			end
		end
	end,
}

-- BoneLine ----------------------------------------------------------------------------------------
renderers.BoneLine = {
	Create = function(rec: Record)
		local p = rec.Params
		local S = rec.S
		local count = math.clamp(math.floor(num(p, "count", 9)), 1, 200)
		local spacing = num(p, "spacing", 2.5)
		local height = num(p, "height", 5)
		local thick = num(p, "boneThickness", 0.8)
		local gaps: { [number]: boolean } = {}
		if type(p.gaps) == "table" then
			for _, g in p.gaps do
				if type(g) == "number" then
					gaps[math.floor(g)] = true
				end
			end
		end
		S.Bones = {}
		S.X = {}
		for i = 1, count do
			if not gaps[i] then
				table.insert(S.Bones, Lib.Bone(thick, height, rec.Color))
				table.insert(S.X, (i - (count + 1) * 0.5) * spacing)
			end
		end
		S.Parts = {}
		S.CFrames = {}
		S.Height = height
		S.LastDust = 0
		local lightPart = Lib.Part("Ball", Vector3.one * 0.2, Pool.PARK, rec.Color, Enum.Material.Neon, 1)
		S.LightPart = lightPart
		S.Light = Lib.Light(lightPart, rec.Color, 0, math.clamp(count * spacing * 0.6, 8, 36))
	end,
	Update = function(rec: Record, t: number, _dt: number): boolean
		local p = rec.Params
		local S = rec.S
		local delay = num(p, "delay", 0.5)
		local speed = math.max(0.01, num(p, "speed", 30))
		local distance = num(p, "distance", 60)
		local linger = num(p, "linger", 0.25)
		local travelTime = distance / speed
		local appear = math.min(0.3, math.max(0.12, delay * 0.6))
		if t < delay - appear then
			return true
		end
		local h: number = S.Height
		local rise: number
		if t < delay then
			local u = clamp01((t - (delay - appear)) / appear)
			local c1, c3 = 1.3, 2.3
			local y = u - 1
			rise = 1 + c3 * y * y * y + c1 * y * y
		elseif t > delay + travelTime then
			rise = 1 - clamp01((t - delay - travelTime) / math.max(0.05, linger))
		else
			rise = 1
		end
		local travel = math.clamp((t - delay) * speed, 0, distance)
		local o: CFrame = p.origin
		local yCenter = h * 0.5 - h * (1 - rise)
		local n = 0
		local parts, cfs = S.Parts, S.CFrames
		for i, bone in S.Bones do
			n = bone:Write(o * CFrame.new(S.X[i], yCenter, -travel), parts, cfs, n)
		end
		game:GetService("Workspace"):BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		local centre = o * CFrame.new(0, h * 0.6, -travel)
		S.LightPart.CFrame = centre
		if S.Light then
			S.Light.Brightness = 2.2 * rise
		end
		local xs = S.X
		if #xs > 0 and t >= delay and t <= delay + travelTime and t - S.LastDust > 0.07 then
			S.LastDust = t
			local x = xs[math.random(1, #xs)]
			Lib.Emit(
				"Dust",
				(o * CFrame.new(x, 0.3, -travel + 0.6)).Position,
				1,
				{ Dir = -o.LookVector + Vector3.new(0, 0.6, 0) }
			)
		end
		return t <= delay + travelTime + linger
	end,
	Destroy = function(rec: Record)
		local S = rec.S
		releaseAll(S.Bones)
		S.Bones = nil
		if S.LightPart then
			Lib.Release(S.LightPart)
		end
	end,
}

-- BoneSpikes --------------------------------------------------------------------------------------
renderers.BoneSpikes = {
	Create = function(rec: Record)
		local p = rec.Params
		local S = rec.S
		S.Layout = HazardDefs.SpikeLayout(p)
		S.Bones = {}
		local thick = num(p, "boneThickness", 0.9)
		for i, sp in S.Layout do
			S.Bones[i] = Lib.Bone(thick, sp.Height, rec.Color, { Bottom = false })
		end
		S.Parts = {}
		S.CFrames = {}
		S.Center = p.center
		S.Erupted = false
		S.Visible = false
	end,
	Update = function(rec: Record, t: number, _dt: number): boolean
		local p = rec.Params
		local S = rec.S
		local frac = HazardVisuals.SpikeFrac(p, t)
		local delay = num(p, "delay", 0.6)
		local radius = num(p, "radius", 8)
		if frac > 0 or S.Visible then
			S.Visible = frac > 0
			local centre: Vector3 = S.Center
			local n = 0
			local parts, cfs = S.Parts, S.CFrames
			for i, sp in S.Layout do
				local L = sp.Height
				local tilt: Vector3 = sp.Tilt
				local base = centre + sp.Offset
				local mid = base + tilt * (frac * L - L * 0.5)
				n = S.Bones[i]:Write(AxisFrame(mid, tilt), parts, cfs, n)
			end
			game:GetService("Workspace"):BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		if not S.Erupted and t >= delay then
			S.Erupted = true
			local centre: Vector3 = S.Center
			local ring = p.ring == true
			Lib.Dust(centre, if ring then radius else radius * 0.7, nil, math.floor(radius * 2.2))
			Lib.EmitRing(
				centre + Vector3.new(0, 0.2, 0),
				radius + (if ring then num(p, "ringWidth", 3) * 0.5 else 0),
				rec.Color,
				0.35
			)
			Lib.Emit("Debris", centre, math.floor(radius), { Color = Color3.fromRGB(150, 140, 130) })
			playSound("BoneRise", centre)
			shakeNear(centre, radius + 2, radius + 22, 0.32, 0.25)
		end
		return t <= HazardDefs.BoneSpikes.Duration(p) + 0.05
	end,
	Destroy = function(rec: Record)
		releaseAll(rec.S.Bones)
		rec.S.Bones = nil
	end,
}

-- BoneProjectile ----------------------------------------------------------------------------------
renderers.BoneProjectile = {
	Create = function(rec: Record)
		local p = rec.Params
		local S = rec.S
		S.Bone = Lib.Bone(num(p, "thickness", 0.7), num(p, "length", 3.5), rec.Color)
		S.Parts = {}
		S.CFrames = {}
		S.Last = nil
		S.Launched = false
		S.LastMote = 0
	end,
	Update = function(rec: Record, t: number, _dt: number): boolean
		local p = rec.Params
		local S = rec.S
		local frame, _ = HazardDefs.ProjectileFrame("BoneProjectile", p, t)
		if frame == nil then
			return false
		end
		S.Last = frame.Position
		local n = S.Bone:Write(frame, S.Parts, S.CFrames, 0)
		if n > 0 then
			game:GetService("Workspace"):BulkMoveTo(S.Parts, S.CFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
		local delay = num(p, "delay", 0.15)
		if not S.Launched and t >= delay then
			S.Launched = true
			Lib.EmitBurst(frame.Position, 2.2, rec.Color, 0.16)
		end
		if t >= delay and t - S.LastMote > 0.04 then
			S.LastMote = t
			Lib.Emit("Mote", frame.Position, 1, { Color = rec.Color })
		end
		return true
	end,
	EndEarly = function(rec: Record, _t: number)
		local pos: Vector3? = rec.S.Last
		if pos then
			Lib.Sparks(pos, nil, rec.Color, 10, 20)
			Lib.Emit("Debris", pos, 3, { Color = Color3.fromRGB(235, 235, 235) })
		end
	end,
	Destroy = function(rec: Record)
		if rec.S.Bone then
			rec.S.Bone:Release()
		end
	end,
}

-- Projectile (registered visuals) -----------------------------------------------------------------
local function visualCtx(rec: Record, kind: string, size: number): { [string]: any }
	return {
		Packet = rec.Packet,
		Params = rec.Params,
		Type = rec.Type,
		Kind = kind,
		Color = rec.Color,
		Rule = rec.Rule,
		Style = rec.Style,
		Size = size,
		Lib = Lib,
	}
end

local function buildVisual(name: string?, ctx: { [string]: any }): Visual?
	local builder = visuals[name or ""] or visuals.Orb
	local ok, v = pcall(builder, ctx)
	if ok and type(v) == "table" then
		return v
	end
	warn("[HazardVisuals] visual " .. tostring(name) .. " failed: " .. tostring(v))
	return nil
end

renderers.Projectile = {
	Create = function(rec: Record)
		local p = rec.Params
		rec.S.Visual = buildVisual(p.visual, visualCtx(rec, "Projectile", num(p, "radius", 0.6)))
		rec.S.Launched = false
	end,
	Update = function(rec: Record, t: number, dt: number): boolean
		local p = rec.Params
		local S = rec.S
		local frame, _ = HazardDefs.ProjectileFrame("Projectile", p, t)
		if frame == nil then
			return false
		end
		S.Last = frame.Position
		local v: Visual? = S.Visual
		if v and v.Update then
			v.Update(v, frame, t, dt)
		end
		if not S.Launched and t >= num(p, "delay", 0) then
			S.Launched = true
			Lib.EmitBurst(frame.Position, math.max(1.5, num(p, "radius", 0.6) * 4), rec.Color, 0.14)
		end
		return true
	end,
	EndEarly = function(rec: Record, _t: number)
		local v: Visual? = rec.S.Visual
		local pos: Vector3? = rec.S.Last
		if v and v.Impact and pos then
			pcall(v.Impact, v, pos)
		end
	end,
	Destroy = function(rec: Record)
		local v: Visual? = rec.S.Visual
		if v then
			pcall(v.Destroy, v)
		end
	end,
}

-- Shockwave ---------------------------------------------------------------------------------------
local WAVE_SEGS = 24
renderers.Shockwave = {
	Create = function(rec: Record)
		local p = rec.Params
		local S = rec.S
		S.Height = math.max(0.3, num(p, "height", 2.5))
		S.Max = num(p, "maxRadius", 14)
		S.Started = false
		S.LastDust = 0
		local chord = 2 * S.Max * math.sin(math.pi / WAVE_SEGS) * 1.05
		S.Segs = {}
		for i = 1, WAVE_SEGS do
			S.Segs[i] =
				Lib.Part("Block", Vector3.new(chord, 0.22, 0.22), Pool.PARK, rec.Color, Enum.Material.Neon, 0.05)
		end
		S.CFrames = table.create(WAVE_SEGS)
	end,
	Update = function(rec: Record, t: number, _dt: number): boolean
		local p = rec.Params
		local S = rec.S
		local center: Vector3 = p.center
		local r = HazardDefs.ShockwaveRadius(p, t)
		local delay = num(p, "delay", 0.3)
		if r == nil then
			if t > delay then
				-- linger: fade the wall at the max radius
				local wall = S.Wall
				if wall then
					local linger = math.max(0.05, num(p, "linger", 0.15))
					local k = clamp01((t - delay - S.Max / math.max(0.01, num(p, "speed", 28))) / linger)
					wall:SetTransparency(0.3 + 0.7 * k, 1)
					for _, seg in S.Segs do
						seg.Transparency = 0.05 + 0.95 * k
					end
					return k < 1
				end
				return false
			end
			return true
		end
		local h: number = S.Height
		local band = math.min(math.max(0.05, num(p, "thickness", 2)), math.max(r, 0.05))
		if not S.Started then
			S.Started = true
			S.Wall = Lib.GroundCircle(
				center,
				math.max(0.1, r),
				rec.Color,
				{ Rim = band, Height = h, Lift = h / 2, Fill = 1 }
			)
			S.Wall:SetTransparency(0.3, 1)
			S.LightPart = Lib.Part(
				"Ball",
				Vector3.one * 0.2,
				CFrame.new(center + Vector3.new(0, h, 0)),
				rec.Color,
				Enum.Material.Neon,
				1
			)
			S.Light = Lib.Light(S.LightPart, rec.Color, 3, math.clamp(S.Max * 1.2, 8, 40))
			playSound("Shockwave", center)
			shakeNear(center, S.Max * 0.5, S.Max + 20, 0.3, 0.3)
			Lib.EmitRing(
				center + Vector3.new(0, 0.15, 0),
				S.Max,
				rec.Color,
				S.Max / math.max(0.01, num(p, "speed", 28)) + 0.1,
				{ Start = 0.02 }
			)
		end
		local wall = S.Wall
		wall:SetRadius(math.max(0.1, r))
		local cfs = S.CFrames
		for i = 1, WAVE_SEGS do
			local a = (i / WAVE_SEGS) * math.pi * 2
			cfs[i] = CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(0, h, -r)
		end
		game:GetService("Workspace"):BulkMoveTo(S.Segs, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if t - S.LastDust > 0.05 then
			S.LastDust = t
			for _ = 1, 3 do
				local a = math.random() * math.pi * 2
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				Lib.Emit("Dust", center + dir * r + Vector3.new(0, 0.4, 0), 1, { Dir = dir + Vector3.new(0, 0.8, 0) })
			end
		end
		return true
	end,
	Destroy = function(rec: Record)
		local S = rec.S
		if S.Wall then
			S.Wall:Destroy()
		end
		releaseAll(S.Segs)
		S.Segs = nil
		if S.LightPart then
			Lib.Release(S.LightPart)
		end
	end,
}

-- Orb (black star + pull swirl + implosion) -------------------------------------------------------
renderers.Orb = {
	Create = function(rec: Record)
		local p = rec.Params
		local S = rec.S
		local center: Vector3 = p.center
		S.Center = center
		local radius = num(p, "radius", 12)
		local violet = if rec.Rule == "White" then Color3.fromRGB(160, 80, 255) else rec.Color
		S.Violet = violet
		local custom = p.visual
		if type(custom) == "string" and custom ~= "Orb" and visuals[custom] then
			S.Visual = buildVisual(custom, visualCtx(rec, "Orb", radius))
		end
		S.Core = Lib.Part(
			"Ball",
			Vector3.one * 0.1,
			CFrame.new(center),
			Color3.fromRGB(6, 2, 12),
			Enum.Material.SmoothPlastic,
			0
		)
		S.Rim = Lib.Part("Ball", Vector3.one * 0.1, CFrame.new(center), violet, Enum.Material.Neon, 0.55)
		S.Light = Lib.Light(S.Rim, violet, 3, math.clamp(radius * 1.5, 10, 40))
		local field = Lib.Part("Ball", Vector3.one * (radius * 2), CFrame.new(center), violet, Enum.Material.Neon, 1)
		S.Field = field
		S.Swirl = Lib.Emitter("Mote", field, {
			Color = violet,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			Speed = NumberRange.new(radius * 0.9, radius * 1.2),
			Lifetime = NumberRange.new(0.8, 1),
			Size = Lib.NS(0, 0.2, 0.5, 0.5, 1, 0.1),
			Rate = 0,
			Drag = 0,
			LockedToPart = true,
		})
		local ground = Lib.Ground(center, 30) or (center - Vector3.new(0, 2.5, 0))
		S.PullRing = Lib.GroundCircle(ground, radius, violet, { Rim = 0.25, Fill = 0.92, Height = 0.2 })
		S.PullRing:SetVisible(false)
		S.Imploded = false
	end,
	Update = function(rec: Record, t: number, dt: number): boolean
		local p = rec.Params
		local S = rec.S
		local center: Vector3 = S.Center
		local delay = num(p, "delay", 0.4)
		local duration = num(p, "duration", 2.5)
		local implodeTime = num(p, "implodeTime", 0.15)
		local linger = num(p, "linger", 0.4)
		local at = delay + duration
		local coreSize: number
		if t < delay then
			coreSize = 2.2 * clamp01(t / math.max(0.05, delay))
		elseif t < at then
			coreSize = 2.2 + 0.25 * math.sin(t * 9)
		elseif t < at + implodeTime then
			coreSize = 2.4 * (1 - clamp01((t - at) / implodeTime))
		else
			coreSize = 0
		end
		local spin = CFrame.new(center) * CFrame.Angles(t * 1.3, t * 2.1, 0)
		S.Core.Size = Vector3.one * math.max(0.05, coreSize)
		S.Core.CFrame = spin
		S.Rim.Size = Vector3.one * math.max(0.05, coreSize * 1.35)
		S.Rim.CFrame = spin
		S.Rim.Transparency = if coreSize > 0 then 0.5 + 0.1 * math.sin(t * 12) else 1
		local pulling = t >= delay and t < at
		S.Swirl.Rate = if pulling then 55 * Lib.ParticleScale() else 0
		S.PullRing:SetVisible(pulling)
		if pulling then
			S.PullRing:SetTransparency(0.35 + 0.2 * math.sin(t * 6), 0.9)
		end
		local v: Visual? = S.Visual
		if v and v.Update then
			v.Update(v, spin, t, dt)
		end
		if not S.Imploded and t >= at then
			S.Imploded = true
			local ir = num(p, "implodeRadius", num(p, "radius", 12))
			Lib.EmitBurst(center, ir * 1.6, S.Violet, 0.3)
			Lib.EmitBurst(center, ir * 0.8, Color3.new(1, 1, 1), 0.18)
			Lib.Ring(CFrame.new(center), ir, S.Violet, 0.3, 0.3)
			Lib.Emit("Star", center, 14, { Color = S.Violet, Speed = { 10, 22 } })
			playSound("Implode", center)
			shakeNear(center, ir, ir + 25, 0.5, 0.35)
		end
		if S.Light then
			S.Light.Brightness = if coreSize > 0 then 3 else 0
		end
		return t <= at + implodeTime + linger
	end,
	Destroy = function(rec: Record)
		local S = rec.S
		for _, k in { "Core", "Rim", "Field" } do
			if S[k] then
				Lib.Release(S[k])
			end
		end
		if S.PullRing then
			S.PullRing:Destroy()
		end
		local v: Visual? = S.Visual
		if v then
			pcall(v.Destroy, v)
		end
	end,
}

-- Zone --------------------------------------------------------------------------------------------
local ZONE_EFFECT = {
	Heal = { Color = "Green", Emit = "Heal" },
	Slow = { Color = "Cyan", Emit = "Mote" },
	Mark = { Color = "Yellow", Emit = "Star" },
	Damage = { Color = nil, Emit = "Ember" },
}

renderers.Zone = {
	Create = function(rec: Record)
		local p = rec.Params
		local S = rec.S
		local eff = ZONE_EFFECT[p.effect] or ZONE_EFFECT.Damage
		local color = if eff.Color and (rec.Rule == "White" or rec.Rule == "") then Lib.Color(eff.Color) else rec.Color
		S.ZColor = color
		S.Emit = eff.Emit
		S.Center = p.center
		S.Radius = num(p, "radius", 9)
		S.Height = num(p, "height", 6)
		S.Started = false
		S.LastTick = -1
		S.LastEmit = 0
		local custom = p.visual
		if type(custom) == "string" and custom ~= "Zone" and visuals[custom] then
			local ctx = visualCtx(rec, "Zone", S.Radius)
			ctx.Color = color
			S.Visual = buildVisual(custom, ctx)
		end
	end,
	Update = function(rec: Record, t: number, dt: number): boolean
		local p = rec.Params
		local S = rec.S
		local delay = num(p, "delay", 0.3)
		local duration = num(p, "duration", 5)
		local linger = math.max(0.05, num(p, "linger", 0.3))
		local center: Vector3 = S.Center
		local radius: number = S.Radius
		if t < delay then
			return true
		end
		if not S.Started then
			S.Started = true
			local c: Color3 = S.ZColor
			S.Disc = Lib.GroundCircle(
				center,
				radius,
				c,
				{ Rim = math.clamp(radius * 0.05, 0.25, 0.5), Fill = 0.8, Height = 0.3 }
			)
			S.Wall = Lib.GroundCircle(
				center,
				radius,
				c,
				{ Rim = 0.08, Height = S.Height * 0.55, Lift = S.Height * 0.275, Fill = 1, Shadow = false }
			)
			S.Wall:SetTransparency(0.85, 1)
			S.LightPart = Lib.Part(
				"Ball",
				Vector3.one * 0.2,
				CFrame.new(center + Vector3.new(0, 1.5, 0)),
				c,
				Enum.Material.Neon,
				1
			)
			S.Light = Lib.Light(S.LightPart, c, 1.6, math.clamp(radius * 1.6, 10, 40))
			Lib.EmitRing(center + Vector3.new(0, 0.2, 0), radius, c, 0.4)
		end
		local active = t <= delay + duration
		local fade = if active then 0 else clamp01((t - delay - duration) / linger)
		local tick = math.max(0.05, num(p, "tick", 0.5))
		local tickIndex = math.floor((t - delay) / tick)
		local sinceTick = (t - delay) - tickIndex * tick
		local pulse = if active then math.max(0, 1 - sinceTick / 0.18) else 0
		S.Disc:SetTransparency(0.15 + 0.85 * fade - 0.1 * pulse, 0.8 + 0.2 * fade - 0.12 * pulse)
		S.Wall:SetTransparency(0.86 + 0.14 * fade - 0.1 * pulse, 1)
		if S.Light then
			S.Light.Brightness = (1.4 + 1.2 * pulse) * (1 - fade)
		end
		if active and tickIndex ~= S.LastTick then
			S.LastTick = tickIndex
			if tickIndex > 0 then
				Lib.EmitRing(
					center + Vector3.new(0, 0.25, 0),
					radius * 0.95,
					S.ZColor,
					0.3,
					{ Start = 0.5, Brightness = 2 }
				)
			end
		end
		if active and t - S.LastEmit > 0.08 then
			S.LastEmit = t
			local a = math.random() * math.pi * 2
			local rr = radius * math.sqrt(math.random())
			Lib.Emit(
				S.Emit,
				center + Vector3.new(math.cos(a) * rr, 0.3, math.sin(a) * rr),
				2,
				{ Color = S.ZColor, Dir = Vector3.yAxis }
			)
		end
		local v: Visual? = S.Visual
		if v and v.Update then
			v.Update(v, CFrame.new(center), t, dt)
		end
		return t <= delay + duration + linger
	end,
	Destroy = function(rec: Record)
		local S = rec.S
		if S.Disc then
			S.Disc:Destroy()
		end
		if S.Wall then
			S.Wall:Destroy()
		end
		if S.LightPart then
			Lib.Release(S.LightPart)
		end
		local v: Visual? = S.Visual
		if v then
			pcall(v.Destroy, v)
		end
	end,
}

-- Rain --------------------------------------------------------------------------------------------
renderers.Rain = {
	Create = function(rec: Record)
		local p = rec.Params
		local S = rec.S
		S.Drops = HazardDefs.RainDrops(p)
		S.Objects = {}
		S.Impacted = {}
		S.Visual = if type(p.visual) == "string" then p.visual else "Bone"
		S.Size = num(p, "size", 3)
		S.LastSound = 0
	end,
	Update = function(rec: Record, t: number, dt: number): boolean
		local p = rec.Params
		local S = rec.S
		local alive = false
		local size: number = S.Size
		for i, drop in S.Drops do
			local state, height = HazardVisuals.RainFall(p, drop, t)
			local obj = S.Objects[i]
			if state == "Wait" then
				alive = true
			elseif state == "Gone" then
				if obj then
					pcall(obj.Destroy, obj)
					S.Objects[i] = nil
				end
			else
				alive = true
				if obj == nil then
					if S.Visual == "Bone" then
						local bone = Lib.Bone(0.75, math.max(2.4, size * 1.2), rec.Color)
						obj = {
							Bone = bone,
							Update = function(self2: any, cf: CFrame, _t: number, _dt: number)
								self2.Bone:Place(cf)
							end,
							Destroy = function(self2: any)
								self2.Bone:Release()
							end,
						}
					else
						obj = buildVisual(S.Visual, visualCtx(rec, "Rain", size))
					end
					S.Objects[i] = obj
				end
				local pos: Vector3 = drop.Position
				local len = math.max(2.4, size * 1.2)
				local cf: CFrame
				if state == "Fall" then
					cf = CFrame.new(pos + Vector3.new(0, height + len * 0.5, 0))
						* CFrame.Angles(0.25, i * 1.7 + t * 2, 0.15)
				else
					-- stuck in the ground, sinking slowly
					local sink = (t - drop.ImpactTime) * 2.2
					cf = CFrame.new(pos + Vector3.new(0, len * 0.3 - sink, 0)) * CFrame.Angles(0.25, i * 1.7, 0.15)
				end
				if obj and obj.Update then
					obj.Update(obj, cf, t, dt)
				end
				if state ~= "Fall" and not S.Impacted[i] then
					S.Impacted[i] = true
					Lib.Dust(pos, size * 0.8, nil, 6)
					Lib.EmitRing(pos + Vector3.new(0, 0.2, 0), size, rec.Color, 0.25, { Start = 0.3 })
					Lib.Emit("Debris", pos, 3, { Color = Color3.fromRGB(150, 140, 130) })
					if t - S.LastSound > 0.12 then
						S.LastSound = t
						playSound("BoneImpact", pos)
					end
					shakeNear(pos, size + 1, size + 10, 0.15, 0.12)
				end
			end
		end
		return alive
	end,
	Destroy = function(rec: Record)
		for _, obj in rec.S.Objects do
			pcall(obj.Destroy, obj)
		end
		table.clear(rec.S.Objects)
	end,
}

-- Generic: draws the server volumes themselves (kit-registered hazard types without a renderer) ----------
local function volumePart(v: { [string]: any }, color: Color3): (BasePart, CFrame, Vector3)
	local shape = v.Shape
	local s: Vector3 = v.Size
	if shape == "Ball" then
		return Lib.Part("Ball", Vector3.one * s.X, v.CFrame, color, Enum.Material.Neon, 0.6),
			v.CFrame,
			Vector3.one * s.X
	elseif shape == "Capsule" or shape == "Cylinder" or shape == "Ring" then
		local size = Vector3.new(s.Y, s.X, s.X)
		local cf = v.CFrame * CFrame.Angles(0, 0, math.pi / 2)
		return Lib.Part("Cylinder", size, cf, color, Enum.Material.Neon, 0.6), cf, size
	end
	return Lib.Part("Block", s, v.CFrame, color, Enum.Material.Neon, 0.6), v.CFrame, s
end

renderers.Generic = {
	Create = function(rec: Record)
		rec.S.Parts = {}
		rec.S.Def = HazardDefs.Get(rec.Type)
	end,
	Update = function(rec: Record, t: number, _dt: number): boolean
		local def = rec.S.Def
		if def == nil then
			return false
		end
		local parts: { BasePart } = rec.S.Parts
		local vols = def.Volumes(rec.Params, t)
		for i, v in vols do
			local part = parts[i]
			if part == nil then
				part = volumePart(v, rec.Color)
				parts[i] = part
			else
				local shape = v.Shape
				local s: Vector3 = v.Size
				if shape == "Capsule" or shape == "Cylinder" or shape == "Ring" then
					part.Size = Vector3.new(s.Y, s.X, s.X)
					part.CFrame = v.CFrame * CFrame.Angles(0, 0, math.pi / 2)
				elseif shape == "Ball" then
					part.Size = Vector3.one * s.X
					part.CFrame = v.CFrame
				else
					part.Size = s
					part.CFrame = v.CFrame
				end
				part.Transparency = 0.6
			end
		end
		for i = #vols + 1, #parts do
			parts[i].Transparency = 1
		end
		return t <= rec.Duration
	end,
	Destroy = function(rec: Record)
		releaseAll(rec.S.Parts)
	end,
}

function HazardVisuals.RegisterRenderer(hazardType: string, renderer: any)
	assert(type(hazardType) == "string" and hazardType ~= "", "HazardVisuals.RegisterRenderer: bad type")
	assert(
		type(renderer) == "table" and type(renderer.Update) == "function",
		"HazardVisuals.RegisterRenderer: bad renderer"
	)
	renderers[hazardType] = renderer
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

local function destroyRecord(rec: Record)
	if rec.Dead then
		return
	end
	rec.Dead = true
	records[rec.Id] = nil
	if rec.Telegraph then
		pcall(rec.Telegraph.Destroy, rec.Telegraph)
		rec.Telegraph = nil
	end
	local ok, err = pcall(rec.Renderer.Destroy, rec)
	if not ok then
		warn("[HazardVisuals] destroy " .. rec.Type .. " failed: " .. tostring(err))
	end
end

local lastFrame = os.clock()
local function step()
	local nowLocal = os.clock()
	local dt = math.min(0.1, nowLocal - lastFrame)
	lastFrame = nowLocal
	local now = Lib.Now()
	local i = 1
	while i <= #order do
		local rec = order[i]
		local alive = not rec.Dead
		if alive then
			local t = now - rec.T0
			if rec.Telegraph then
				local ok, still = pcall(rec.Telegraph.Update, rec.Telegraph, t)
				if not ok or not still then
					pcall(rec.Telegraph.Destroy, rec.Telegraph)
					rec.Telegraph = nil
				end
			end
			local ok, res = pcall(rec.Renderer.Update, rec, t, dt)
			if not ok then
				warn("[HazardVisuals] " .. rec.Type .. " update failed: " .. tostring(res))
				alive = false
			elseif res ~= true and rec.Telegraph == nil then
				alive = false
			end
			if rec.EndedAt and nowLocal - (rec.EndedAt :: number) > 0.05 then
				alive = false
			end
			if t > rec.Duration + 3 then
				alive = false -- safety net
			end
		end
		if not alive then
			destroyRecord(rec)
			local n = #order
			order[i] = order[n]
			order[n] = nil
		else
			i += 1
		end
	end
	if #order == 0 and loopConn then
		loopConn:Disconnect()
		loopConn = nil
	end
end

function HazardVisuals.Spawn(packet: { [string]: any })
	if type(packet) ~= "table" or type(packet.id) ~= "number" or type(packet.type) ~= "string" then
		return
	end
	if records[packet.id] then
		return
	end
	local params: Params = if type(packet.params) == "table" then packet.params else {}
	local hazardType: string = packet.type
	local def = HazardDefs.Get(hazardType)
	local renderer = renderers[hazardType]
	if renderer == nil then
		if def == nil then
			return
		end
		renderer = renderers.Generic
	end
	local t0 = if type(packet.t0) == "number" then packet.t0 else Lib.Now()
	local duration = 5
	if def then
		local ok, d = pcall(def.Duration, params)
		if ok and type(d) == "number" then
			duration = d
		end
	end
	if Lib.Now() - t0 > duration + 0.5 then
		return -- arrived too late to matter
	end
	local rule = if type(params.color) == "string" then params.color else "White"
	local rec: Record = {
		Id = packet.id,
		Type = hazardType,
		T0 = t0,
		Params = params,
		Owner = packet.owner,
		Team = packet.team or "",
		Packet = packet,
		Duration = duration,
		Rule = rule,
		Color = Lib.Color(rule),
		Style = if type(params.style) == "string" and params.style ~= "" then params.style else "Classic",
		Telegraph = nil,
		Renderer = renderer,
		S = {},
		EndedAt = nil,
		Dead = false,
	}
	if not renderer.NoTelegraph then
		local ok, desc = pcall(HazardDefs.Telegraph, hazardType, params)
		if ok and type(desc) == "table" and desc.Kind ~= "None" then
			rec.Telegraph = Lib.Telegraph(desc)
		end
	end
	local ok, err = pcall(renderer.Create, rec)
	if not ok then
		warn("[HazardVisuals] create " .. hazardType .. " failed: " .. tostring(err))
		pcall(renderer.Destroy, rec)
		if rec.Telegraph then
			rec.Telegraph:Destroy()
		end
		return
	end
	records[rec.Id] = rec
	table.insert(order, rec)
	if loopConn == nil then
		lastFrame = os.clock()
		loopConn = RunService.PreRender:Connect(step)
	end
end

function HazardVisuals.End(id: number)
	local rec = records[id]
	if rec == nil or rec.EndedAt then
		return
	end
	rec.EndedAt = os.clock()
	local early = rec.Renderer.EndEarly
	if early then
		pcall(early, rec, Lib.Now() - rec.T0)
	end
	if rec.Telegraph then
		pcall(rec.Telegraph.Destroy, rec.Telegraph)
		rec.Telegraph = nil
	end
end

function HazardVisuals.Clear()
	for _, rec in order do
		destroyRecord(rec)
	end
	table.clear(order)
end

function HazardVisuals.Count(): number
	return #order
end

function HazardVisuals.Get(id: number): Record?
	return records[id]
end

---------------------------------------------------------------------------------------------------
-- Offline snapshot (Lune-safe: plain Instances, no workspace): a static Model of a hazard at time t built with the
-- SAME pose / layer / layout maths as the live renderers, for tools/preview renders and visual review.
--   lune run tools/lune/dump_model.luau module src/client/Controllers/HazardVisuals Snapshot '["BoneSpikes", {...}, 0.8]'

function HazardVisuals.Snapshot(hazardType: string, params: Params, t: number): Model
	local p = HazardDefs.Normalize(hazardType, params)
	local model = Instance.new("Model")
	model.Name = "Snapshot_" .. hazardType
	local color = Lib.Color(p.color)
	local function part(
		shape: string,
		size: Vector3,
		cf: CFrame,
		c: Color3,
		mat: Enum.Material,
		transp: number
	): BasePart
		local q = Instance.new("Part")
		q.Shape = if shape == "Ball"
			then Enum.PartType.Ball
			elseif shape == "Cylinder" then Enum.PartType.Cylinder
			else Enum.PartType.Block
		q.Size = size
		q.CFrame = cf
		q.Color = c
		q.Material = mat
		q.Transparency = transp
		q.Anchored = true
		q.CastShadow = false
		q.Parent = model
		return q
	end
	-- telegraph discs / rings as thin cylinders (HandleAdornments do not exist offline)
	local desc = HazardDefs.Telegraph(hazardType, p)
	local items = if desc.Kind == "Multi" then desc.Items else { desc }
	for _, d in items or {} do
		local phase, k = Lib.TelegraphPhase(d.Start, d.End, t)
		if phase == "Warn" and (d.Kind == "Circle" or d.Kind == "Ring") then
			local c: Vector3 = d.Center
			local r: number = d.Radius
			local flat = CFrame.new(c + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			part(
				"Cylinder",
				Vector3.new(0.06, r * 2 + 0.4, r * 2 + 0.4),
				flat,
				Color3.new(0, 0, 0),
				Enum.Material.SmoothPlastic,
				0.5
			)
			part(
				"Cylinder",
				Vector3.new(0.1, r * 2, r * 2),
				flat * CFrame.new(0.03, 0, 0),
				color,
				Enum.Material.Neon,
				0.25
			)
			local fill = (if d.Kind == "Ring" then (d.InnerRadius or 0) + (r - (d.InnerRadius or 0)) * k else r * k)
			part(
				"Cylinder",
				Vector3.new(0.12, fill * 2, fill * 2),
				flat * CFrame.new(0.05, 0, 0),
				color,
				Enum.Material.Neon,
				0.6
			)
		elseif phase == "Warn" and d.Kind == "Beam" and d.CFrame then
			local len = d.Length or 10
			local axis = d.CFrame * CFrame.new(0, 0, -len / 2) * CFrame.Angles(0, math.pi / 2, 0)
			part("Cylinder", Vector3.new(len, 0.14, 0.14), axis, color, Enum.Material.Neon, 0.2)
			part("Cylinder", Vector3.new(len, d.Width or 1, d.Width or 1), axis, color, Enum.Material.Neon, 0.9)
		elseif phase == "Warn" and d.Kind == "Lane" and d.CFrame then
			local len, w = d.Length or 10, d.Width or 2
			part(
				"Block",
				Vector3.new(w, 0.1, len * k),
				d.CFrame * CFrame.new(0, 0.05, -len * k / 2),
				color,
				Enum.Material.Neon,
				0.6
			)
			part(
				"Block",
				Vector3.new(0.3, 0.2, len),
				d.CFrame * CFrame.new(-w / 2, 0.1, -len / 2),
				color,
				Enum.Material.Neon,
				0.1
			)
			part(
				"Block",
				Vector3.new(0.3, 0.2, len),
				d.CFrame * CFrame.new(w / 2, 0.1, -len / 2),
				color,
				Enum.Material.Neon,
				0.1
			)
		end
	end
	local BoneProp = Lib.Prop("Bone")
	local function bone(len: number, thick: number, cf: CFrame)
		if BoneProp and type(BoneProp.Build) == "function" then
			local b = BoneProp.Build(len, thick, color, Enum.Material.Neon)
			-- move part by part (Model:PivotTo does not exist offline); Bone.Frame = the bone's own frame
			local frame = if type(BoneProp.Frame) == "function" then BoneProp.Frame(b) else CFrame.identity
			local delta = cf * frame:Inverse()
			for _, q in b:GetDescendants() do
				if q:IsA("BasePart") then
					q.CFrame = delta * q.CFrame
				end
			end
			b.Parent = model
		else
			part(
				"Cylinder",
				Vector3.new(len, thick, thick),
				cf * CFrame.Angles(0, 0, math.pi / 2),
				color,
				Enum.Material.Neon,
				0
			)
		end
	end
	if hazardType == "BlasterBeam" then
		local width = num(p, "width", 4)
		local nominal = propNominal(p.style) or propNominal("Classic")
		local bm = if nominal then buildProp(p.style, scaleBucket(HazardVisuals.BlasterScale(width, nominal))) else nil
		bm = bm or buildMiniBlaster(scaleBucket(width * 1.25))
		local b = bm :: Model
		local root = b.PrimaryPart or b:FindFirstChildWhichIsA("BasePart", true) :: BasePart
		local refInv = CFrame.new(root.CFrame.Position):Inverse()
		local hinge, muzzle = CFrame.identity, Vector3.new(0, 0, -1)
		local h = root:FindFirstChild("JawHinge")
		if h and h:IsA("Attachment") then
			hinge = refInv * root.CFrame * h.CFrame
		end
		local m = root:FindFirstChild("Muzzle")
		if m and m:IsA("Attachment") then
			muzzle = (refInv * root.CFrame * m.CFrame).Position
		end
		local jawModel = b:FindFirstChild("Jaw")
		local list: { BasePart } = {}
		local offsets: { CFrame } = {}
		local mask: { boolean } = {}
		for _, d in b:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
				table.insert(offsets, refInv * d.CFrame)
				table.insert(mask, jawModel ~= nil and d:IsDescendantOf(jawModel))
			end
		end
		local pose = HazardVisuals.BlasterPose(p, t)
		local out: { CFrame } = {}
		blasterFrames(LookAlong(pose.Pos, pose.Look), muzzle, hinge, hinge:Inverse(), pose.Jaw, offsets, mask, out)
		for i, q in list do
			q.CFrame = out[i]
		end
		local Prop = Lib.Prop("GasterBlaster")
		if Prop and type(Prop.SetGlow) == "function" then
			Prop.SetGlow(b, styleColors(p.style, p.color).Eye, if pose.Eyes <= 0.02 then 1 else pose.Eyes)
		end
		b.Parent = model
		local core, mid, outer, alpha = HazardVisuals.BeamLayers(p, t)
		if outer > 0 then
			local C = styleColors(p.style, p.color)
			local look = (p.origin :: CFrame).LookVector
			local start = HazardDefs.BeamStart(p)
			local back = math.max(0, (start - pose.Pos):Dot(look))
			local s0 = start - look * back
			local len = num(p, "length", 60) + back
			local cf = LookAlong(s0 + look * (len / 2), look) * ROT_X_TO_LOOK
			part("Cylinder", Vector3.new(len, core, core), cf, C.Core, Enum.Material.Neon, 1 - alpha)
			part("Cylinder", Vector3.new(len, mid, mid), cf, C.Mid, Enum.Material.Neon, 0.25 + 0.75 * (1 - alpha))
			part("Cylinder", Vector3.new(len, outer, outer), cf, C.Outer, Enum.Material.Neon, 0.58 + 0.42 * (1 - alpha))
			part("Ball", Vector3.one * outer, CFrame.new(s0), C.Outer, Enum.Material.Neon, 0.58)
		end
	elseif hazardType == "BoneSpikes" then
		local frac = HazardVisuals.SpikeFrac(p, t)
		if frac > 0 then
			for _, sp in HazardDefs.SpikeLayout(p) do
				local L = sp.Height
				local mid = (p.center :: Vector3) + sp.Offset + sp.Tilt * (frac * L - L * 0.5)
				bone(L, num(p, "boneThickness", 0.9), AxisFrame(mid, sp.Tilt))
			end
		end
	elseif hazardType == "BoneLine" then
		for _, b in HazardDefs.BoneLineBones(p, t) do
			bone(num(p, "height", 5), num(p, "boneThickness", 0.8), b.CFrame)
		end
	end
	return model
end

function HazardVisuals.Init() end

function HazardVisuals.Start()
	-- warm the blaster pool (part-built, HD-upgraded in the background) so the first cast never hitches
	task.delay(4, function()
		local warm: { Blaster } = {}
		for _ = 1, 3 do
			local ok, b = pcall(HazardVisuals.AcquireBlaster, "Classic", 5)
			if ok and b then
				table.insert(warm, b)
			end
		end
		for _, b in warm do
			b:Release()
		end
	end)
end

return HazardVisuals
