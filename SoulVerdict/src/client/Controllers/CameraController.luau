--!strict
-- CameraController (client, SPEC §20, Priority 15): custom Scriptable third-person camera.
--
-- Feel (all numbers in CameraController.Tuning):
--   * over-the-shoulder pivot (Config.Camera.ShoulderOffset: X = shoulder, Y = pivot height above the root) that
--     blends to a centred orbit when the lock is off; critically damped follow (Util/Spring, fast horizontally,
--     softer vertically so jumps don't jerk the view); snaps on teleports;
--   * mouse-lock aiming (MouseBehavior.LockCenter + lock cursor) while locked in Follow mode and no UI context is
--     open; RMB-drag look when unlocked; touch drag + pinch zoom; gamepad right stick with radial dead zone,
--     response curve and a turn boost at full deflection; sensitivity / invert-Y from settings; pitch limits;
--   * wall collision with sphere casts (pivot -> shoulder, shoulder -> camera) that see only what blocks characters
--     (collision group Config.CollisionGroups.Characters + RespectCanCollide; characters, VFX folders, invisible
--     (Transparency >= 0.95) and CameraIgnore-attributed parts are ignored): smooth but never-clipping pull-in,
--     slow ease-out; the local character fades out when the camera is pushed into it;
--   * FOV: player setting + speed widening + Kick()s; trauma shake from VFX/CameraShake (scaled by the CameraShake
--     setting and GraphicsController.ReducedMotion);
--   * modes: Follow, Intro (centripetal Catmull-Rom flight through RoundEvent "Intro" data.introPath at constant
--     speed, look direction splined too; fallback: arena orbit), Spectate(model), KillCam(position, duration) (slow
--     orbit + slight zoom; also played for everyone on RoundEnd.lastHit), Menu (slow cinematic lobby orbit; Follow
--     without a character shows it too), Photo (free fly, UI + character controls hidden). Mode changes blend.
--
-- API (SPEC §20)
--   CameraController.SetMode(mode, opts?)  mode: "Follow"|"Intro"|"Spectate"|"KillCam"|"Menu"|"Photo"; opts {Blend: number?}
--   CameraController.PlayIntro(path: {CFrame}, duration, opts?)   opts {Center: Vector3?, Radius: number?}
--   CameraController.Spectate(model?)        nil -> back to Follow
--   CameraController.KillCam(position, duration?)
--   CameraController.Shake(intensity, duration?) ; ShakeAt(position, intensity, duration?, radius?) ; AddTrauma(amount)
--   CameraController.Kick(fovDelta, duration?)
--   CameraController.AimRay() -> (origin, unitDirection)   screen centre (KBM with a free cursor: the mouse)
--   CameraController.AimPoint(maxDist?) -> Vector3          ray hit (own character, allies, VFX excluded) or far point
--   CameraController.AimCast(maxDist?) -> (Vector3, RaycastResult?)
--   CameraController.SetLock(on) ; LockEnabled() -> boolean ; LockChanged: Signal(on)
--   CameraController.Focus(model?)           follow another model in Follow mode (nil = local character)
-- Extras
--   CameraController.Mode() -> string ; ModeChanged: Signal(mode)
--   CameraController.FacingYaw() -> number   camera yaw (radians, CFrame.Angles(0, yaw, 0) convention)
--   CameraController.ShouldFaceCamera() -> boolean   MovementController aligns the character when true
--   CameraController.Cut()                   snap follow/collision this frame (teleports, respawns)
--   CameraController.SetMenuShot(focus: Vector3?, radius?, height?)
--   CameraController.SetCrosshair(icon: string?)   mouse icon while locked (default: built-in lock cursor; "" = none)
--   CameraController.SetShoulder(side: number)     1 = right shoulder, -1 = left
--   CameraController.Yaw()/Pitch()/SetYawPitch(yaw, pitch)
--   CameraController.Shaker -> VFX/CameraShake instance ; CameraController.Math -> pure helpers (Lune-tested)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Spring = require(Shared:WaitForChild("Util"):WaitForChild("Spring"))
local MathUtil = require(Shared:WaitForChild("Util"):WaitForChild("MathUtil"))
local Registry = require(Shared:WaitForChild("Maps"):WaitForChild("Registry"))
local Teams = require(Shared:WaitForChild("Combat"):WaitForChild("Teams"))
local Strings = require(Shared:WaitForChild("Strings"))
local CameraShake = require((script.Parent :: Instance).Parent:WaitForChild("VFX"):WaitForChild("CameraShake"))

local CameraController = {}
CameraController.Priority = 15

export type Mode = "Follow" | "Intro" | "Spectate" | "KillCam" | "Menu" | "Photo"

CameraController.ModeChanged = Signal.new()
CameraController.LockChanged = Signal.new()

local CAM = Config.Camera
local TUNING = {
	-- follow rig
	ShoulderLocked = CAM.ShoulderOffset.X, -- studs to the right while locked
	ShoulderFree = 0.35, -- nearly centred orbit while unlocked
	ShoulderSpectate = 0.6,
	PivotHeight = CAM.ShoulderOffset.Y, -- above HumanoidRootPart (x RigScale)
	Distance = CAM.Distance,
	SpectateDistance = 13,
	MinDistance = CAM.MinDistance,
	MaxDistance = CAM.MaxDistance,
	ZoomStep = 1.75,
	ZoomRate = 14, -- exp rate of the zoom distance
	FollowSpeedH = CAM.FollowStiffness, -- spring angular frequency (critically damped)
	FollowSpeedV = CAM.FollowStiffness * 0.5,
	ShoulderSpeed = 9,
	SnapDistance = 40, -- pivot jumps farther than this (teleports) cut instead of glide
	-- collision
	CollisionRadius = 0.45,
	CollisionPadding = 0.12,
	MinCollisionDistance = 0.5,
	PullInRate = 32, -- exp rate while pulling in (bounded: never more than MaxPullLag behind the hit)
	MaxPullLag = 0.35,
	EaseOutRate = 2.2, -- slow release after an obstruction (~95 % back in 1.4 s)
	FadeStart = 2.6, -- camera-to-pivot distance where the local character starts to fade
	FadeEnd = 1.1, -- fully faded
	-- look
	MouseSensitivity = CAM.Sensitivity, -- radians per pixel (x setting CameraSensitivity)
	TouchSensitivity = CAM.TouchSensitivity,
	GamepadYawSpeed = CAM.GamepadSensitivity, -- radians/s at full deflection
	GamepadPitchFactor = 0.62,
	StickDeadzone = 0.14,
	StickExponent = 1.7,
	TurnBoost = 1.55,
	TurnBoostDelay = 0.28,
	TurnBoostRamp = 0.4,
	PitchMin = math.rad(CAM.PitchMin),
	PitchMax = math.rad(CAM.PitchMax),
	DefaultPitch = math.rad(-12),
	AutoYawDelay = 1.4, -- gamepad/touch, lock off: drift behind the movement after this long without look input
	AutoYawRate = 1.1,
	-- field of view
	BaseFov = Config.Defaults.FieldOfView,
	FovRate = 7,
	SpeedFovMax = 7, -- extra degrees at high speed (dash, knockback)
	SpeedFovStart = 20, -- studs/s
	SpeedFovRange = 34,
	MaxKick = 25,
	KickAttack = 0.07,
	-- blends (seconds)
	ModeBlend = 0.6,
	IntroOutBlend = 1.0,
	KillCamBlend = 0.45,
	-- intro
	IntroLookDistance = 40,
	IntroFov = 64,
	-- kill cam
	KillCamRadiusStart = 12,
	KillCamRadiusEnd = 8,
	KillCamHeight = 3.2,
	KillCamSpin = 0.32,
	KillCamFovStart = 60,
	KillCamFovEnd = 52,
	-- menu
	MenuRadius = 34,
	MenuHeight = 11,
	MenuSpin = 0.045,
	MenuFov = 55,
	-- photo
	PhotoSpeed = 16,
	PhotoFastMult = 3,
	PhotoSlowMult = 0.3,
	-- shake / kicks under reduced motion
	ReducedShakeScale = 0.35,
	ReducedKickScale = 0.5,
}
CameraController.Tuning = TUNING

local DEFAULT_CROSSHAIR = "rbxasset://textures/MouseLockedCursor.png"
local IGNORE_FOLDERS = { "Effects", "VFX", "Debris", "Hazards", "Boxes", "SV_VFX" }
local RENDER_NAME = "SV_Camera"

----------------------------------------------------------------------------------------------- pure math

local CameraMath = {}
CameraController.Math = CameraMath

function CameraMath.ClampPitch(pitch: number, minPitch: number, maxPitch: number): number
	if pitch ~= pitch then
		return 0
	end
	return math.clamp(pitch, minPitch, maxPitch)
end

-- Rotation looking along (yaw, pitch); yaw 0 = -Z, positive yaw turns left, positive pitch looks up.
function CameraMath.Rotation(yaw: number, pitch: number): CFrame
	return CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

function CameraMath.YawPitch(direction: Vector3): (number, number)
	local m = direction.Magnitude
	if m < 1e-6 then
		return 0, 0
	end
	local u = direction * (1 / m)
	return math.atan2(-u.X, -u.Z), math.asin(math.clamp(u.Y, -1, 1))
end

-- Lune-safe look-at (CFrame.lookAt is mirrored under Lune): position `from`, looking at `to`, no roll.
function CameraMath.LookAt(from: Vector3, to: Vector3): CFrame
	local yaw, pitch = CameraMath.YawPitch(to - from)
	return CFrame.new(from) * CameraMath.Rotation(yaw, pitch)
end

-- Distance the camera may sit at, given the desired distance and an optional obstruction distance.
function CameraMath.CollisionTarget(desired: number, hitDistance: number?, padding: number, minDistance: number): number
	if hitDistance == nil then
		return desired
	end
	return math.clamp(hitDistance - padding, math.min(minDistance, desired), desired)
end

-- Smooth pull-in that never lags more than maxLag behind an obstruction, slow ease-out when it clears.
function CameraMath.SmoothCollision(
	current: number,
	target: number,
	dt: number,
	pullRate: number,
	easeOutRate: number,
	maxLag: number
): number
	if target < current then
		local alpha = 1 - math.exp(-pullRate * dt)
		local smoothed = current + (target - current) * alpha
		return math.min(smoothed, target + maxLag)
	end
	local alpha = 1 - math.exp(-easeOutRate * dt)
	return current + (target - current) * alpha
end

-- Radial dead zone + response curve for one stick axis pair; returns the shaped vector.
function CameraMath.StickCurve(x: number, y: number, deadzone: number, exponent: number): (number, number)
	local m = math.sqrt(x * x + y * y)
	if m <= deadzone then
		return 0, 0
	end
	local scaled = math.min((m - deadzone) / (1 - deadzone), 1)
	local shaped = scaled ^ exponent
	return x / m * shaped, y / m * shaped
end

-- Character fade alpha from the camera-to-pivot distance (0 = visible, 1 = hidden).
function CameraMath.FadeAlpha(distance: number, fadeStart: number, fadeEnd: number): number
	if fadeStart <= fadeEnd then
		return if distance <= fadeEnd then 1 else 0
	end
	return math.clamp((fadeStart - distance) / (fadeStart - fadeEnd), 0, 1)
end

-- Centripetal Catmull-Rom (alpha 0.5 default): segment p1 -> p2 at u in [0, 1]. No cusps / self-intersections.
function CameraMath.CatmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: number, alpha: number?): Vector3
	local a = alpha or 0.5
	local function knot(t: number, from: Vector3, to: Vector3): number
		return t + math.max((to - from).Magnitude ^ a, 1e-4)
	end
	local t0 = 0
	local t1 = knot(t0, p0, p1)
	local t2 = knot(t1, p1, p2)
	local t3 = knot(t2, p2, p3)
	local t = t1 + (t2 - t1) * math.clamp(u, 0, 1)
	local a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	local a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	local a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	local b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	local b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
end

export type PathCache = {
	Points: { Vector3 },
	Looks: { Vector3 }, -- look-at targets (splined like the positions -> smooth rotation)
	Lengths: { number }, -- cumulative arc length per sample
	Samples: number, -- samples per segment
	Total: number,
}

local function controlPoint(points: { Vector3 }, i: number): Vector3
	local n = #points
	if i < 1 then
		return points[1] + (points[1] - points[2])
	elseif i > n then
		return points[n] + (points[n] - points[n - 1])
	end
	return points[i]
end

local function segmentPoint(points: { Vector3 }, segment: number, u: number): Vector3
	return CameraMath.CatmullRom(
		controlPoint(points, segment - 1),
		points[segment],
		points[segment + 1],
		controlPoint(points, segment + 2),
		u
	)
end

function CameraMath.BuildPath(path: { CFrame }, samplesPerSegment: number?, lookDistance: number?): PathCache?
	local n = #path
	if n < 2 then
		return nil
	end
	local samples = samplesPerSegment or 16
	local points: { Vector3 } = table.create(n)
	local looks: { Vector3 } = table.create(n)
	local reach = lookDistance or TUNING.IntroLookDistance
	for i, cf in path do
		points[i] = cf.Position
		looks[i] = cf.Position + cf.LookVector * reach
	end
	local lengths: { number } = table.create((n - 1) * samples + 1)
	lengths[1] = 0
	local previous = points[1]
	local total = 0
	for segment = 1, n - 1 do
		for k = 1, samples do
			local p = segmentPoint(points, segment, k / samples)
			total += (p - previous).Magnitude
			lengths[(segment - 1) * samples + k + 1] = total
			previous = p
		end
	end
	return { Points = points, Looks = looks, Lengths = lengths, Samples = samples, Total = total }
end

-- Constant-speed sample: s in [0, 1] is the fraction of the arc length. Returns (position, lookTarget).
function CameraMath.SamplePathPoints(cache: PathCache, s: number): (Vector3, Vector3)
	local lengths = cache.Lengths
	local count = #lengths
	local target = math.clamp(s, 0, 1) * cache.Total
	-- binary search: last index with lengths[i] <= target
	local lo, hi = 1, count
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if lengths[mid] <= target then
			lo = mid
		else
			hi = mid
		end
	end
	local span = lengths[hi] - lengths[lo]
	local frac = if span > 1e-9 then (target - lengths[lo]) / span else 0
	local index = lo - 1 + frac -- 0-based sample position
	local samples = cache.Samples
	local segment = math.min(math.floor(index / samples) + 1, #cache.Points - 1)
	local u = math.clamp((index - (segment - 1) * samples) / samples, 0, 1)
	return segmentPoint(cache.Points, segment, u), segmentPoint(cache.Looks, segment, u)
end

function CameraMath.SamplePath(cache: PathCache, s: number): CFrame
	local position, look = CameraMath.SamplePathPoints(cache, s)
	return CameraMath.LookAt(position, look)
end

-- Orbit camera around `center` (yaw convention as Rotation), looking at center + lookOffset.
function CameraMath.Orbit(center: Vector3, yaw: number, radius: number, height: number, lookHeight: number): CFrame
	local offset = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)) * -radius
	local position = center + offset + Vector3.new(0, height, 0)
	return CameraMath.LookAt(position, center + Vector3.new(0, lookHeight, 0))
end

---------------------------------------------------------------------------------------------- state

local mode: Mode = "Follow"
local resumeMode: Mode = "Follow"
local yaw, pitch = 0, TUNING.DefaultPitch
local zoomTarget = TUNING.Distance
local zoomDistance = TUNING.Distance
local collisionDistance = TUNING.Distance
local easingOut = false
local lockEnabled = Config.Defaults.CameraLock == true
local shoulderSide = 1
local crosshairIcon = DEFAULT_CROSSHAIR
local appliedIcon: string? = nil
local focusOverride: Model? = nil
local spectateTarget: Model? = nil
local needsCut = true
local lastCFrame = CFrame.new(0, 20, 30)
local lastFov = TUNING.BaseFov
local currentFov = TUNING.BaseFov
local speedFov = 0
local started = false

local pivotH = Spring.new(Vector3.zero, TUNING.FollowSpeedH, 1)
local pivotV = Spring.new(0, TUNING.FollowSpeedV, 1)
local shoulder = Spring.new(TUNING.ShoulderLocked, TUNING.ShoulderSpeed, 1)

-- settings
local sensitivityMult = 1
local invertY = false
local shakeSetting = Config.Defaults.CameraShake
local fovSetting = TUNING.BaseFov
local reducedMotion = false

-- input
local rmbDown = false
local stick2 = Vector2.zero
local stick1 = Vector2.zero
local stickFullTime = 0
local pendingTouch = Vector2.zero
local touchLook: InputObject? = nil
local touchPinch: InputObject? = nil
local pinchDistance = 0
local lastLookInput = 0
local lastPivot = Vector3.zero

-- blend between modes
local blendFrom: CFrame? = nil
local blendFromFov = TUNING.BaseFov
local blendTime = 0
local blendDuration = 0

-- fov kicks (fixed arrays, no per-kick allocation)
local MAX_KICKS = 8
local kickAmp = table.create(MAX_KICKS, 0)
local kickDur = table.create(MAX_KICKS, 0)
local kickAge = table.create(MAX_KICKS, 0)
local kickCount = 0

-- intro / kill cam / menu / photo
local intro: {
	Cache: PathCache?,
	Duration: number,
	Start: number,
	Center: Vector3,
	Radius: number,
	Yaw0: number,
}? =
	nil
local killCam: { Center: Vector3, Duration: number, Start: number, Yaw0: number }? = nil
local menuFocus: Vector3? = nil
local menuRadius = TUNING.MenuRadius
local menuHeight = TUNING.MenuHeight
local photoPosition = Vector3.zero
local photoFov = TUNING.BaseFov
local hiddenGuis: { ScreenGui } = {}
local controlsModule: any = nil
local cinematicPushed = false

-- raycast params (created in Init: RaycastParams does not exist under Lune)
local collisionParams: RaycastParams = nil :: any
local aimParams: RaycastParams = nil :: any
local cameraIgnore: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local cameraIgnoreCount = 0
local collisionGroupSet = false
local lastFilterRefresh = -math.huge

-- character fade
local fadeParts: { BasePart } = {}
local fadedByUs: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local fadeModel: Model? = nil
local currentFade = 0
local hadSubject = false

----------------------------------------------------------------------------------------------- lazy deps

local controllerCache: { [string]: any } = {}
local function controller(name: string): any?
	local cached = controllerCache[name]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local folder = script.Parent
	local module = folder and folder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			controllerCache[name] = result
			return result
		end
	end
	controllerCache[name] = false
	return nil
end

local function localCharacter(): Model?
	local State = controller("StateController")
	if State then
		local ok, model = pcall(State.LocalCharacter)
		if ok and model ~= nil then
			return model
		end
	end
	local player = Players.LocalPlayer
	return if player then player.Character else nil
end

local function rootOf(model: Model?): BasePart?
	if model == nil or model.Parent == nil then
		return nil
	end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function rigScale(model: Model?): number
	if model then
		local s = model:GetAttribute("RigScale")
		if type(s) == "number" and s > 0 then
			return s
		end
	end
	return 1
end

local function combatEnabled(): boolean
	local Input = controller("InputController")
	if Input and type(Input.CombatEnabled) == "function" then
		return Input.CombatEnabled()
	end
	return true
end

local function inputDevice(): string
	local Input = controller("InputController")
	if Input and type(Input.Device) == "function" then
		return Input.Device()
	end
	return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "KeyboardMouse"
end

local function now(): number
	return os.clock()
end

------------------------------------------------------------------------------------------- raycasting

local function refreshFilters()
	lastFilterRefresh = now()
	local me = localCharacter()
	local ignore: { Instance } = {}
	local aimIgnore: { Instance } = {}
	for _, name in IGNORE_FOLDERS do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
			table.insert(aimIgnore, folder)
		end
	end
	if me then
		table.insert(ignore, me)
		table.insert(aimIgnore, me)
	end
	-- other characters never block the camera; allies are transparent to the aim ray
	local function consider(model: Instance)
		if model:IsA("Model") and model ~= me and model:FindFirstChildOfClass("Humanoid") then
			table.insert(ignore, model)
			if me and Teams.AreAllies(me, model) then
				table.insert(aimIgnore, model)
			end
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			consider(player.Character)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, child in bots:GetChildren() do
			consider(child)
		end
	end
	for part in cameraIgnore do
		table.insert(ignore, part)
	end
	collisionParams.FilterDescendantsInstances = ignore
	aimParams.FilterDescendantsInstances = aimIgnore
	if not collisionGroupSet then
		local group = Config.CollisionGroups.Characters
		local ok, registered = pcall(function()
			return PhysicsService:IsCollisionGroupRegistered(group)
		end)
		if ok and registered then
			collisionParams.CollisionGroup = group
			collisionGroupSet = true
		end
	end
end

local function addCameraIgnore(part: BasePart)
	if cameraIgnore[part] or cameraIgnoreCount > 128 then
		return
	end
	cameraIgnore[part] = true
	cameraIgnoreCount += 1
	local ok = pcall(function()
		collisionParams:AddToFilter(part)
	end)
	if not ok then
		refreshFilters()
	end
end

-- Distance along `direction` to the first camera-blocking surface (sphere cast), or nil.
local function sphereCast(origin: Vector3, direction: Vector3): number?
	if direction.Magnitude < 1e-3 then
		return nil
	end
	for _ = 1, 3 do
		local result = workspace:Spherecast(origin, TUNING.CollisionRadius, direction, collisionParams)
		if result == nil then
			return nil
		end
		local hit = result.Instance
		if hit:IsA("BasePart") and (hit.Transparency >= 0.95 or hit:GetAttribute("CameraIgnore") == true) then
			addCameraIgnore(hit)
		else
			return result.Distance
		end
	end
	return nil
end

-------------------------------------------------------------------------------------------- settings

local function readSettings()
	local State = controller("StateController")
	if State == nil or type(State.Setting) ~= "function" then
		return
	end
	local function setting(key: string, default: any): any
		local ok, value = pcall(State.Setting, key, default)
		if ok and value ~= nil then
			return value
		end
		return default
	end
	local fov = setting("FieldOfView", TUNING.BaseFov)
	fovSetting = if type(fov) == "number" then math.clamp(fov, 50, 100) else TUNING.BaseFov
	local shake = setting("CameraShake", Config.Defaults.CameraShake)
	shakeSetting = if type(shake) == "number" then math.clamp(shake, 0, 2) elseif shake == false then 0 else 1
	local sens = setting("CameraSensitivity", 1)
	sensitivityMult = if type(sens) == "number" then math.clamp(sens, 0.1, 4) else 1
	invertY = setting("InvertY", false) == true
end

local function applyShakeScale()
	local scale = shakeSetting * (if reducedMotion then TUNING.ReducedShakeScale else 1)
	CameraShake.Default:SetScale(scale)
end

------------------------------------------------------------------------------------------------ modes

local function startBlend(duration: number)
	if duration <= 0 then
		blendFrom = nil
		return
	end
	blendFrom = lastCFrame
	blendFromFov = lastFov
	blendTime = 0
	blendDuration = duration
end

local function setCinematic(on: boolean)
	if on == cinematicPushed then
		return
	end
	local Input = controller("InputController")
	if Input == nil then
		return
	end
	cinematicPushed = on
	if on then
		Input.PushContext("Cinematic")
	else
		Input.PopContext("Cinematic")
	end
end

local function setUiHidden(hidden: boolean)
	local UI = controller("UIController")
	if UI and type(UI.SetHidden) == "function" then
		pcall(UI.SetHidden, hidden)
		return
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if hidden then
		table.clear(hiddenGuis)
		if playerGui then
			for _, gui in playerGui:GetChildren() do
				if gui:IsA("ScreenGui") and gui.Enabled then
					gui.Enabled = false
					table.insert(hiddenGuis, gui)
				end
			end
		end
	else
		for _, gui in hiddenGuis do
			if gui.Parent ~= nil then
				gui.Enabled = true
			end
		end
		table.clear(hiddenGuis)
	end
end

local function setControlsEnabled(enabled: boolean)
	local controls = controlsModule
	if controls == nil then
		return
	end
	pcall(function()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function leaveMode(old: Mode)
	if old == "Photo" then
		setUiHidden(false)
		setControlsEnabled(true)
		local Input = controller("InputController")
		if Input then
			Input.PopContext("Photo")
		end
	elseif old == "Intro" then
		intro = nil
	elseif old == "KillCam" then
		killCam = nil
	end
	if old == "Intro" or old == "KillCam" then
		setCinematic(false)
	end
end

local function setMode(newMode: Mode, blend: number?)
	local old = mode
	if old == newMode and newMode ~= "Spectate" then
		return
	end
	startBlend(if blend ~= nil then blend else TUNING.ModeBlend)
	leaveMode(old)
	mode = newMode
	if newMode == "Photo" then
		photoPosition = lastCFrame.Position
		yaw, pitch = CameraMath.YawPitch(lastCFrame.LookVector)
		photoFov = lastFov
		blendFrom = nil
		setUiHidden(true)
		setControlsEnabled(false)
		local Input = controller("InputController")
		if Input then
			Input.PushContext("Photo")
		end
	elseif newMode == "Intro" or newMode == "KillCam" then
		setCinematic(true)
	elseif newMode == "Follow" or newMode == "Spectate" then
		needsCut = true
	end
	CameraController.ModeChanged:Fire(newMode)
end

------------------------------------------------------------------------------------------------ input

local function isGamepadType(inputType: Enum.UserInputType): boolean
	return string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and not gameProcessed then
		rmbDown = true
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton2 then
		rmbDown = false
	elseif isGamepadType(inputType) then
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick2 = Vector2.zero
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick1 = Vector2.zero
		end
	end
end

local function onInputChanged(input: InputObject, gameProcessed: boolean)
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseWheel then
		if gameProcessed then
			return
		end
		local z = input.Position.Z
		if mode == "Photo" then
			photoFov = math.clamp(photoFov - z * 4, 10, 110)
		elseif mode == "Follow" or mode == "Spectate" then
			zoomTarget = math.clamp(zoomTarget - z * TUNING.ZoomStep, TUNING.MinDistance, TUNING.MaxDistance)
		end
	elseif isGamepadType(inputType) then
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick2 = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick1 = Vector2.new(input.Position.X, input.Position.Y)
		end
	end
end

local function onTouchStarted(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if touchLook == nil then
		touchLook = input
	elseif touchPinch == nil and input ~= touchLook then
		touchPinch = input
		local a = touchLook.Position
		local b = input.Position
		pinchDistance = Vector2.new(a.X - b.X, a.Y - b.Y).Magnitude
	end
end

local function onTouchMoved(input: InputObject, _gameProcessed: boolean)
	local lookTouch = touchLook
	if lookTouch == nil then
		return
	end
	local pinch = touchPinch
	if pinch ~= nil and (input == lookTouch or input == pinch) then
		local a = lookTouch.Position
		local b = pinch.Position
		local d = Vector2.new(a.X - b.X, a.Y - b.Y).Magnitude
		zoomTarget = math.clamp(zoomTarget - (d - pinchDistance) * 0.04, TUNING.MinDistance, TUNING.MaxDistance)
		pinchDistance = d
	elseif input == lookTouch then
		pendingTouch += Vector2.new(input.Delta.X, input.Delta.Y)
	end
end

local function onTouchEnded(input: InputObject, _gameProcessed: boolean)
	if input == touchLook then
		touchLook = touchPinch
		touchPinch = nil
	elseif input == touchPinch then
		touchPinch = nil
	end
end

local function mouseLookWanted(): (boolean, boolean)
	-- returns (lockCenter, lockCurrentPosition)
	if GuiService.MenuIsOpen then
		return false, false
	end
	local device = inputDevice()
	if device ~= "KeyboardMouse" then
		return false, false
	end
	local free = combatEnabled()
	if mode == "Follow" and lockEnabled and free and rootOf(focusOverride or localCharacter()) ~= nil then
		return true, false
	end
	if rmbDown and (mode == "Follow" or mode == "Spectate" or mode == "Photo") then
		if mode == "Follow" and not free then
			return false, false
		end
		return false, true
	end
	return false, false
end

local function applyLookInput(dt: number, allowLook: boolean)
	local lockCenter, dragLook = mouseLookWanted()
	local behavior = if lockCenter
		then Enum.MouseBehavior.LockCenter
		elseif dragLook then Enum.MouseBehavior.LockCurrentPosition
		else Enum.MouseBehavior.Default
	if UserInputService.MouseBehavior ~= behavior then
		UserInputService.MouseBehavior = behavior
	end
	local wantIcon = if lockCenter then crosshairIcon else ""
	if appliedIcon ~= wantIcon then
		appliedIcon = wantIcon
		UserInputService.MouseIcon = wantIcon
	end
	if not allowLook then
		pendingTouch = Vector2.zero
		return
	end
	local invert = if invertY then -1 else 1
	local looked = false
	-- mouse
	if lockCenter or dragLook then
		local delta = UserInputService:GetMouseDelta()
		if delta.X ~= 0 or delta.Y ~= 0 then
			local sens = TUNING.MouseSensitivity * sensitivityMult
			yaw -= delta.X * sens
			pitch -= delta.Y * sens * invert
			looked = true
		end
	end
	-- touch drag
	if pendingTouch.X ~= 0 or pendingTouch.Y ~= 0 then
		local sens = TUNING.TouchSensitivity * sensitivityMult
		yaw -= pendingTouch.X * sens
		pitch -= pendingTouch.Y * sens * invert
		pendingTouch = Vector2.zero
		looked = true
	end
	-- gamepad right stick
	local sx, sy = CameraMath.StickCurve(stick2.X, stick2.Y, TUNING.StickDeadzone, TUNING.StickExponent)
	if sx ~= 0 or sy ~= 0 then
		if math.abs(stick2.X) > 0.92 then
			stickFullTime += dt
		else
			stickFullTime = 0
		end
		local boost = 1
		if stickFullTime > TUNING.TurnBoostDelay then
			local ramp = math.clamp((stickFullTime - TUNING.TurnBoostDelay) / TUNING.TurnBoostRamp, 0, 1)
			boost = 1 + (TUNING.TurnBoost - 1) * ramp
		end
		local speed = TUNING.GamepadYawSpeed * sensitivityMult
		yaw -= sx * speed * boost * dt
		pitch += sy * speed * TUNING.GamepadPitchFactor * dt * invert
		looked = true
	else
		stickFullTime = 0
	end
	if looked then
		lastLookInput = now()
		yaw = MathUtil.wrapAngle(yaw)
	end
	pitch = CameraMath.ClampPitch(pitch, TUNING.PitchMin, TUNING.PitchMax)
end

------------------------------------------------------------------------------------------ fov kicks

local function kickOffset(dt: number): number
	local total = 0
	local i = 1
	while i <= kickCount do
		kickAge[i] += dt
		local age, dur = kickAge[i], kickDur[i]
		if age >= dur then
			kickAmp[i] = kickAmp[kickCount]
			kickDur[i] = kickDur[kickCount]
			kickAge[i] = kickAge[kickCount]
			kickCount -= 1
		else
			local attack = math.min(TUNING.KickAttack, dur * 0.4)
			local env
			if age < attack then
				env = MathUtil.smoothstep(0, attack, age)
			else
				local r = (age - attack) / math.max(dur - attack, 1e-3)
				env = (1 - r) * (1 - r)
			end
			total += kickAmp[i] * env
			i += 1
		end
	end
	return math.clamp(total, -TUNING.MaxKick, TUNING.MaxKick)
end

------------------------------------------------------------------------------------------- character fade

local function collectFadeParts(model: Model)
	table.clear(fadeParts)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(fadeParts, d)
		end
	end
end

local function refreshFadeParts(model: Model?)
	-- restore whatever we faded on the previous model
	for _, part in fadeParts do
		if fadedByUs[part] then
			fadedByUs[part] = nil
			part.LocalTransparencyModifier = 0
		end
	end
	table.clear(fadeParts)
	currentFade = 0
	fadeModel = model
	if model ~= nil then
		collectFadeParts(model)
	end
end

local function updateFade(target: number)
	if math.abs(target - currentFade) < 0.03 and not (target == 0 and currentFade > 0) then
		return
	end
	if currentFade <= 0 and target > 0 and fadeModel then
		-- parts added since the character spawned (weapons, HD meshes) fade too
		collectFadeParts(fadeModel)
	end
	currentFade = target
	for _, part in fadeParts do
		if part.Parent == nil then
			continue
		end
		-- parts hidden by someone else (HD mesh groups use 1) are left alone
		if not fadedByUs[part] and part.LocalTransparencyModifier >= 0.999 then
			continue
		end
		if target <= 0 then
			if fadedByUs[part] then
				fadedByUs[part] = nil
				part.LocalTransparencyModifier = 0
			end
		else
			fadedByUs[part] = true
			part.LocalTransparencyModifier = target
		end
	end
end

------------------------------------------------------------------------------------------- mode frames

local function faceBehindRoot(root: BasePart)
	local look = root.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = TUNING.DefaultPitch
end

local function snapFollow(root: BasePart, model: Model?)
	local target = root.Position + Vector3.new(0, TUNING.PivotHeight * rigScale(model), 0)
	pivotH:Reset(Vector3.new(target.X, 0, target.Z))
	pivotV:Reset(target.Y)
	collisionDistance = zoomDistance
	easingOut = false
	needsCut = false
end

-- Third-person frame around `model` (Follow / Spectate). Returns (cframe, pivot, fov).
local function followFrame(dt: number, model: Model, root: BasePart, spectating: boolean): (CFrame, Vector3, number)
	local scale = rigScale(model)
	local target = root.Position + Vector3.new(0, TUNING.PivotHeight * scale, 0)
	if needsCut or (Vector3.new(target.X, 0, target.Z) - pivotH.Position).Magnitude > TUNING.SnapDistance then
		snapFollow(root, model)
	end
	pivotH.Target = Vector3.new(target.X, 0, target.Z)
	pivotV.Target = target.Y
	local ph = pivotH:Update(dt)
	local pv = pivotV:Update(dt)
	local pivot = Vector3.new(ph.X, pv, ph.Z)
	lastPivot = pivot

	-- zoom
	local desired = zoomTarget
	if spectating then
		desired = math.max(desired, TUNING.SpectateDistance)
	end
	zoomDistance += (desired - zoomDistance) * (1 - math.exp(-TUNING.ZoomRate * dt))

	-- auto-yaw behind the movement (gamepad / touch, lock off, Follow only)
	local velocity = root.AssemblyLinearVelocity
	local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if
		not spectating
		and not lockEnabled
		and inputDevice() ~= "KeyboardMouse"
		and flatSpeed > 4
		and now() - lastLookInput > TUNING.AutoYawDelay
	then
		local moveYaw = math.atan2(-velocity.X, -velocity.Z)
		local diff = MathUtil.angleDiff(yaw, moveYaw)
		-- only follow when not running toward the camera
		if math.abs(diff) < math.rad(120) then
			yaw = MathUtil.wrapAngle(yaw + diff * (1 - math.exp(-TUNING.AutoYawRate * dt)))
		end
	end

	-- shoulder blend
	shoulder.Target = shoulderSide
		* (
			if spectating
				then TUNING.ShoulderSpectate
				elseif lockEnabled then TUNING.ShoulderLocked
				else TUNING.ShoulderFree
		)
	local shoulderX = shoulder:Update(dt) * scale

	local rotation = CameraMath.Rotation(yaw, pitch)
	local look = rotation.LookVector
	local right = CFrame.Angles(0, yaw, 0).RightVector

	-- collision: pivot -> shoulder, then shoulder -> camera
	local shoulderOffset = right * shoulderX
	local shoulderPoint = pivot + shoulderOffset
	if math.abs(shoulderX) > 0.05 then
		local hitSide = sphereCast(pivot, shoulderOffset)
		if hitSide then
			local allowed = math.max(0, hitSide - TUNING.CollisionPadding)
			shoulderPoint = pivot + right * (math.sign(shoulderX) * allowed)
		end
	end
	local hitBack = sphereCast(shoulderPoint, look * -zoomDistance)
	local targetDistance =
		CameraMath.CollisionTarget(zoomDistance, hitBack, TUNING.CollisionPadding, TUNING.MinCollisionDistance)
	if hitBack ~= nil and targetDistance < zoomDistance - 0.05 then
		easingOut = true
	end
	if targetDistance < collisionDistance then
		collisionDistance = CameraMath.SmoothCollision(
			collisionDistance,
			targetDistance,
			dt,
			TUNING.PullInRate,
			TUNING.EaseOutRate,
			TUNING.MaxPullLag
		)
	else
		local rate = if easingOut then TUNING.EaseOutRate else TUNING.ZoomRate
		collisionDistance += (targetDistance - collisionDistance) * (1 - math.exp(-rate * dt))
		if collisionDistance >= targetDistance - 0.05 then
			easingOut = false
		end
	end
	local position = shoulderPoint - look * collisionDistance

	-- speed FOV
	local speedT = math.clamp((flatSpeed - TUNING.SpeedFovStart) / TUNING.SpeedFovRange, 0, 1)
	speedFov += (speedT * TUNING.SpeedFovMax - speedFov) * (1 - math.exp(-TUNING.FovRate * dt))
	return CFrame.new(position) * rotation, pivot, fovSetting + speedFov
end

local function menuFrame(): (CFrame, Vector3, number)
	local focus = menuFocus
	if focus == nil then
		local root = rootOf(localCharacter())
		focus = if root then root.Position else (Registry.LobbyOrigin + Vector3.new(0, 5, 0))
	end
	assert(focus)
	local t = now()
	local angle = t * TUNING.MenuSpin
	local cf = CameraMath.Orbit(focus, angle, menuRadius, menuHeight + math.sin(t * 0.31) * 0.8, 3)
	return cf, focus, TUNING.MenuFov
end

local function introFrame(): (CFrame, Vector3, number)
	local state = intro
	if state == nil then
		return lastCFrame, lastPivot, lastFov
	end
	local elapsed = now() - state.Start
	local alpha = math.clamp(elapsed / math.max(state.Duration, 0.1), 0, 1)
	local eased = MathUtil.Ease(alpha, "Sine", "InOut")
	local cache = state.Cache
	if cache then
		local position, lookTarget = CameraMath.SamplePathPoints(cache, eased)
		return CameraMath.LookAt(position, lookTarget), lookTarget, TUNING.IntroFov
	end
	-- fallback: sweeping arena orbit that pushes in
	local r = state.Radius
	local angle = state.Yaw0 + eased * 2.2
	local radius = r * (0.95 - 0.4 * eased)
	local height = r * (0.45 - 0.2 * eased)
	return CameraMath.Orbit(state.Center, angle, radius, height, 4), state.Center, TUNING.IntroFov
end

local function killCamFrame(): (CFrame, Vector3, number)
	local state = killCam
	if state == nil then
		return lastCFrame, lastPivot, lastFov
	end
	local elapsed = now() - state.Start
	local alpha = math.clamp(elapsed / math.max(state.Duration, 0.1), 0, 1)
	local eased = MathUtil.Ease(alpha, "Quad", "Out")
	local radius = MathUtil.lerp(TUNING.KillCamRadiusStart, TUNING.KillCamRadiusEnd, eased)
	local angle = state.Yaw0 + elapsed * TUNING.KillCamSpin
	local center = state.Center
	local cf = CameraMath.Orbit(center, angle, radius, TUNING.KillCamHeight, 1.5)
	-- keep the orbit out of walls
	local fromCenter = cf.Position - (center + Vector3.new(0, 1.5, 0))
	local hit = sphereCast(center + Vector3.new(0, 1.5, 0), fromCenter)
	if hit then
		local d = math.max(TUNING.MinCollisionDistance, hit - TUNING.CollisionPadding)
		local position = center + Vector3.new(0, 1.5, 0) + fromCenter.Unit * d
		cf = CameraMath.LookAt(position, center + Vector3.new(0, 1.5, 0))
	end
	return cf, center, MathUtil.lerp(TUNING.KillCamFovStart, TUNING.KillCamFovEnd, eased)
end

local function photoFrame(dt: number): (CFrame, Vector3, number)
	local move = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		move += Vector3.new(0, 0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		move += Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		move += Vector3.new(-1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		move += Vector3.new(1, 0, 0)
	end
	local vertical = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.E) then
		vertical += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		vertical -= 1
	end
	local sx, sy = CameraMath.StickCurve(stick1.X, stick1.Y, TUNING.StickDeadzone, 1.4)
	move += Vector3.new(sx, 0, -sy)
	local okL2, l2 = pcall(function()
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL2)
	end)
	local okR2, r2 = pcall(function()
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR2)
	end)
	if okR2 and r2 then
		vertical += 1
	end
	if okL2 and l2 then
		vertical -= 1
	end
	local speed = TUNING.PhotoSpeed
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		speed *= TUNING.PhotoFastMult
	elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		speed *= TUNING.PhotoSlowMult
	end
	local rotation = CameraMath.Rotation(yaw, pitch)
	local worldMove = rotation:VectorToWorldSpace(move) + Vector3.new(0, vertical, 0)
	if worldMove.Magnitude > 1 then
		worldMove = worldMove.Unit
	end
	photoPosition += worldMove * (speed * dt)
	return CFrame.new(photoPosition) * rotation, photoPosition, photoFov
end

------------------------------------------------------------------------------------------- render step

local function onRender(rawDt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local dt = math.clamp(rawDt, 0, 0.1)
	if now() - lastFilterRefresh > 0.5 then
		refreshFilters()
	end

	-- timed modes
	if mode == "Intro" and intro and now() - intro.Start >= intro.Duration then
		setMode(resumeMode, TUNING.IntroOutBlend)
	elseif mode == "KillCam" and killCam and now() - killCam.Start >= killCam.Duration then
		setMode(resumeMode, TUNING.KillCamBlend)
	end

	local allowLook = mode == "Follow" or mode == "Spectate" or mode == "Photo"
	if mode == "Follow" and not combatEnabled() then
		-- a menu / the Verdict Box is open: keep the view still (touch drags belong to the UI)
		allowLook = rmbDown
	end
	applyLookInput(dt, allowLook)

	local me = localCharacter()
	local cf: CFrame, pivot: Vector3, fov: number
	local fadeTarget = 0
	if mode == "Follow" then
		local model = if focusOverride and focusOverride.Parent then focusOverride else me
		local root = rootOf(model)
		if model and root then
			if not hadSubject then
				-- the character just appeared: glide from the lobby/menu framing instead of cutting
				hadSubject = true
				startBlend(TUNING.ModeBlend)
				faceBehindRoot(root)
			end
			cf, pivot, fov = followFrame(dt, model, root, false)
			if model == me then
				fadeTarget = CameraMath.FadeAlpha((cf.Position - pivot).Magnitude, TUNING.FadeStart, TUNING.FadeEnd)
			end
		else
			cf, pivot, fov = menuFrame()
			needsCut = true
			hadSubject = false
		end
	elseif mode == "Spectate" then
		local model = spectateTarget
		local root = rootOf(model)
		if model and root then
			cf, pivot, fov = followFrame(dt, model, root, true)
		else
			cf, pivot, fov = lastCFrame, lastPivot, lastFov
		end
	elseif mode == "Intro" then
		cf, pivot, fov = introFrame()
	elseif mode == "KillCam" then
		cf, pivot, fov = killCamFrame()
	elseif mode == "Menu" then
		cf, pivot, fov = menuFrame()
	else
		cf, pivot, fov = photoFrame(dt)
	end

	-- smooth fov toward the mode's target (fast enough to feel instant on kicks: kicks are added after)
	currentFov += (fov - currentFov) * (1 - math.exp(-TUNING.FovRate * dt))

	-- blend from the previous mode
	local outFov = currentFov
	local from = blendFrom
	if from ~= nil then
		blendTime += dt
		local alpha = MathUtil.smootherstep(0, 1, blendTime / math.max(blendDuration, 1e-3))
		cf = from:Lerp(cf, alpha)
		outFov = MathUtil.lerp(blendFromFov, currentFov, alpha)
		if alpha >= 1 then
			blendFrom = nil
		end
	end

	-- unshaken frame (blends start from here, never from a shaken frame)
	lastCFrame = cf
	lastFov = outFov

	-- shake + kicks
	local shakePos, shakeRot = CameraShake.Default:Update(dt)
	if shakeRot.Magnitude > 0 or shakePos.Magnitude > 0 then
		cf = cf * CFrame.new(shakePos) * CFrame.Angles(shakeRot.X, shakeRot.Y, shakeRot.Z)
	end
	local kick = kickOffset(dt) * (if reducedMotion then TUNING.ReducedKickScale else 1)

	camera.CFrame = cf
	camera.Focus = CFrame.new(pivot)
	camera.FieldOfView = math.clamp(outFov + kick, 1, 120)

	if fadeModel ~= me then
		refreshFadeParts(me)
	end
	updateFade(fadeTarget)
end

---------------------------------------------------------------------------------------------------- API

function CameraController.Mode(): Mode
	return mode
end

function CameraController.SetMode(newMode: string, opts: { Blend: number? }?)
	local valid = newMode == "Follow"
		or newMode == "Intro"
		or newMode == "Spectate"
		or newMode == "KillCam"
		or newMode == "Menu"
		or newMode == "Photo"
	if not valid then
		warn("[CameraController] unknown mode " .. tostring(newMode))
		return
	end
	local m = newMode :: Mode
	if m == "Follow" or m == "Spectate" or m == "Menu" then
		resumeMode = m
	end
	setMode(m, opts and opts.Blend)
end

function CameraController.PlayIntro(path: { CFrame }?, duration: number?, opts: { Center: Vector3?, Radius: number? }?)
	local cframes: { CFrame } = {}
	if type(path) == "table" then
		for _, cf in path do
			if typeof(cf) == "CFrame" then
				table.insert(cframes, cf)
			end
		end
	end
	local o = opts or {}
	local center = if typeof(o.Center) == "Vector3" then o.Center :: Vector3 else lastPivot
	local radius = if type(o.Radius) == "number" and o.Radius > 0 then o.Radius :: number else 60
	intro = {
		Cache = CameraMath.BuildPath(cframes),
		Duration = if type(duration) == "number" and duration > 0.5 then duration else Config.Round.IntroTime,
		Start = now(),
		Center = center,
		Radius = radius,
		Yaw0 = yaw,
	}
	if mode ~= "Intro" and mode ~= "KillCam" and mode ~= "Photo" then
		resumeMode = if mode == "Menu" then "Follow" else mode
	end
	resumeMode = if resumeMode == "Menu" then "Follow" else resumeMode
	setMode("Intro", 0) -- cut in: the VS splash covers the jump
end

function CameraController.Spectate(model: Model?)
	if model == nil then
		spectateTarget = nil
		resumeMode = "Follow"
		if mode == "Spectate" then
			setMode("Follow", TUNING.ModeBlend)
		end
		return
	end
	local changed = spectateTarget ~= model
	spectateTarget = model
	resumeMode = "Spectate"
	if mode == "Intro" or mode == "KillCam" or mode == "Photo" then
		return -- picked up when that mode ends
	end
	if mode ~= "Spectate" then
		setMode("Spectate", TUNING.ModeBlend)
	elseif changed then
		startBlend(TUNING.ModeBlend)
		needsCut = true
	end
end

function CameraController.KillCam(position: Vector3, duration: number?)
	if typeof(position) ~= "Vector3" or mode == "Photo" then
		return
	end
	local look = lastCFrame.LookVector
	local yaw0 = math.atan2(-look.X, -look.Z) -- start from the current view direction (short blend)
	killCam = {
		Center = position,
		Duration = if type(duration) == "number" and duration > 0.3 then duration else 3,
		Start = now(),
		Yaw0 = yaw0,
	}
	if mode ~= "KillCam" and mode ~= "Intro" then
		resumeMode = if mode == "Menu" then "Follow" else mode
	end
	setMode("KillCam", TUNING.KillCamBlend)
end

function CameraController.Shake(intensity: number, duration: number?)
	CameraShake.Default:Shake(intensity, duration)
end

function CameraController.AddTrauma(amount: number)
	CameraShake.Default:AddTrauma(amount)
end

-- Shake attenuated by the distance from the camera pivot (quadratic falloff to 0 at `radius`).
function CameraController.ShakeAt(position: Vector3, intensity: number, duration: number?, radius: number?)
	if typeof(position) ~= "Vector3" then
		return
	end
	local r = radius or 60
	local d = (position - lastPivot).Magnitude
	local falloff = math.clamp(1 - d / r, 0, 1)
	if falloff > 0 then
		CameraShake.Default:Shake(intensity * falloff * falloff, duration)
	end
end

function CameraController.Kick(fovDelta: number, duration: number?)
	if type(fovDelta) ~= "number" or fovDelta ~= fovDelta then
		return
	end
	local d = if type(duration) == "number" and duration > 0.05 then duration else 0.3
	local index = kickCount + 1
	if index > MAX_KICKS then
		index = MAX_KICKS -- overwrite the newest slot when saturated
	else
		kickCount = index
	end
	kickAmp[index] = fovDelta
	kickDur[index] = d
	kickAge[index] = 0
end

function CameraController.AimRay(): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return lastCFrame.Position, lastCFrame.LookVector
	end
	local viewport = camera.ViewportSize
	local x, y = viewport.X * 0.5, viewport.Y * 0.5
	if
		mode == "Follow"
		and inputDevice() == "KeyboardMouse"
		and UserInputService.MouseBehavior == Enum.MouseBehavior.Default
	then
		local mouse = UserInputService:GetMouseLocation()
		x, y = mouse.X, mouse.Y
	end
	local ray = camera:ViewportPointToRay(x, y, 0)
	local direction = ray.Direction.Unit
	local origin = ray.Origin
	-- start next to the character: geometry between the camera and the player cannot eat the aim
	local skip = (lastPivot - origin):Dot(direction) - 1.5
	if skip > 0 and mode == "Follow" then
		origin += direction * skip
	end
	return origin, direction
end

function CameraController.AimCast(maxDist: number?): (Vector3, RaycastResult?)
	local origin, direction = CameraController.AimRay()
	local distance = if type(maxDist) == "number" and maxDist > 0 then maxDist else Config.Combat.MaxAimRange
	local result = workspace:Raycast(origin, direction * distance, aimParams)
	if result then
		return result.Position, result
	end
	return origin + direction * distance, nil
end

function CameraController.AimPoint(maxDist: number?): Vector3
	local point = CameraController.AimCast(maxDist)
	return point
end

function CameraController.SetLock(on: boolean)
	local value = on == true
	if value == lockEnabled then
		return
	end
	lockEnabled = value
	CameraController.LockChanged:Fire(value)
end

function CameraController.LockEnabled(): boolean
	return lockEnabled
end

function CameraController.Focus(model: Model?)
	if focusOverride ~= model then
		focusOverride = model
		needsCut = true
		startBlend(TUNING.ModeBlend)
	end
end

function CameraController.FacingYaw(): number
	return yaw
end

function CameraController.ShouldFaceCamera(): boolean
	return mode == "Follow" and lockEnabled and focusOverride == nil and combatEnabled()
end

function CameraController.Cut()
	needsCut = true
	blendFrom = nil
end

function CameraController.SetMenuShot(focus: Vector3?, radius: number?, height: number?)
	menuFocus = focus
	menuRadius = radius or TUNING.MenuRadius
	menuHeight = height or TUNING.MenuHeight
end

function CameraController.SetCrosshair(icon: string?)
	crosshairIcon = if icon == nil then DEFAULT_CROSSHAIR else icon
end

function CameraController.SetShoulder(side: number)
	shoulderSide = if side < 0 then -1 else 1
end

function CameraController.Yaw(): number
	return yaw
end

function CameraController.Pitch(): number
	return pitch
end

function CameraController.SetYawPitch(newYaw: number, newPitch: number?)
	yaw = MathUtil.wrapAngle(newYaw)
	if newPitch then
		pitch = CameraMath.ClampPitch(newPitch, TUNING.PitchMin, TUNING.PitchMax)
	end
end

CameraController.Shaker = CameraShake.Default

------------------------------------------------------------------------------------------------ lifecycle

local function faceBehind(model: Model?)
	local root = rootOf(model)
	if root then
		faceBehindRoot(root)
	end
end

local function hookState()
	local State = controller("StateController")
	if State == nil then
		return
	end
	readSettings()
	applyShakeScale()
	local okLock, lockSetting = pcall(State.Setting, "CameraLock")
	if okLock and type(lockSetting) == "boolean" then
		CameraController.SetLock(lockSetting)
	end
	if State.SettingChanged then
		State.SettingChanged:Connect(function(key: string, value: any)
			if key == "CameraLock" and type(value) == "boolean" then
				CameraController.SetLock(value)
			else
				readSettings()
				applyShakeScale()
			end
		end)
	end
	if State.CharacterChanged then
		State.CharacterChanged:Connect(function(model: Model?)
			needsCut = true
			if model then
				task.defer(faceBehind, model)
			end
		end)
	end
	if type(State.OnRoundEvent) == "function" then
		State.OnRoundEvent("Intro", function(data: any)
			if type(data) ~= "table" then
				return
			end
			local okLeft, left = pcall(State.TimeLeft)
			local duration = if okLeft
					and type(left) == "number"
					and left > 1
				then left - 0.1
				else Config.Round.IntroTime
			CameraController.PlayIntro(data.introPath, duration, { Center = data.center, Radius = data.radius })
		end)
		State.OnRoundEvent("RoundEnd", function(data: any)
			if type(data) ~= "table" or type(data.lastHit) ~= "table" then
				return
			end
			local position: Vector3? = nil
			if typeof(data.lastHit.position) == "Vector3" then
				position = data.lastHit.position
			else
				local victim = data.lastHit.victim
				local root = if typeof(victim) == "Instance" and victim:IsA("Model") then rootOf(victim) else nil
				position = if root then root.Position else nil
			end
			if position then
				local okLeft, left = pcall(State.TimeLeft)
				local duration = if okLeft and type(left) == "number" then math.clamp(left - 1, 2, 4.5) else 4
				CameraController.KillCam(position, duration)
			end
		end)
	end
	if State.RoundChanged then
		State.RoundChanged:Connect(function(attr: string, value: any)
			if attr == "Phase" and value == "Round" and mode == "Intro" then
				setMode(resumeMode, TUNING.IntroOutBlend)
			end
		end)
	end
end

local function hookInput()
	local Input = controller("InputController")
	if Input == nil or Input.Action == nil then
		return
	end
	Input.Action:Connect(function(action: string, state: string)
		if state ~= "Begin" then
			return
		end
		if action == "CameraLock" then
			if mode == "Follow" and combatEnabled() then
				CameraController.SetLock(not lockEnabled)
				local UI = controller("UIController")
				if UI and type(UI.Toast) == "function" then
					pcall(UI.Toast, Strings.L(if lockEnabled then "controls.lock.on" else "controls.lock.off"))
				end
			end
		elseif (action == "Back" or action == "Menu") and mode == "Photo" then
			CameraController.SetMode(resumeMode)
		end
	end)
end

local function hookGraphics()
	local Graphics = controller("GraphicsController")
	if Graphics == nil then
		return
	end
	if type(Graphics.ReducedMotion) == "function" then
		local ok, value = pcall(Graphics.ReducedMotion)
		reducedMotion = ok and value == true
	end
	if Graphics.ReducedMotionChanged then
		Graphics.ReducedMotionChanged:Connect(function(value: boolean)
			reducedMotion = value == true
			applyShakeScale()
		end)
	end
	applyShakeScale()
end

local function loadControls()
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	local ok, controls = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 10)
		local playerModule = scripts and scripts:WaitForChild("PlayerModule", 10)
		if playerModule and playerModule:IsA("ModuleScript") then
			return (require(playerModule) :: any):GetControls()
		end
		return nil
	end)
	if ok then
		controlsModule = controls
	end
end

function CameraController.Init()
	collisionParams = RaycastParams.new()
	aimParams = RaycastParams.new()
	collisionParams.FilterType = Enum.RaycastFilterType.Exclude
	collisionParams.IgnoreWater = true
	collisionParams.RespectCanCollide = true
	aimParams.FilterType = Enum.RaycastFilterType.Exclude
	aimParams.IgnoreWater = true
end

function CameraController.Start()
	if started then
		return
	end
	started = true
	local camera = workspace.CurrentCamera
	if camera then
		lastCFrame = camera.CFrame
		lastFov = camera.FieldOfView
		currentFov = lastFov
		camera.CameraType = Enum.CameraType.Scriptable
	end
	refreshFilters()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.TouchStarted:Connect(onTouchStarted)
	UserInputService.TouchMoved:Connect(onTouchMoved)
	UserInputService.TouchEnded:Connect(onTouchEnded)
	UserInputService.WindowFocusReleased:Connect(function()
		rmbDown = false
		stick1, stick2 = Vector2.zero, Vector2.zero
	end)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, onRender)
	hookState()
	hookInput()
	hookGraphics()
	faceBehind(localCharacter())
	task.spawn(loadControls)
end

return CameraController
