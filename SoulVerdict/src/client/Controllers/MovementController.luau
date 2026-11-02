--!strict
-- MovementController (client, SPEC §7.7 / §20, Priority 22): everything that moves the LOCAL character beyond
-- normal walking (the client owns its character's physics, so forced movement must be applied here).
--   * Net "ForceMove" packets (Impulse / Pull / Lift / Slam / Dash / Teleport / Root) -> one LinearVelocity on a
--     HumanoidRootPart attachment (created on demand, disabled when the move ends; a new packet replaces the old):
--       Impulse  vertical part applied at once (ballistic arc), horizontal part held by a Plane mover decaying to 0
--       Pull     homing velocity toward `target` (stops 2 studs short), Lift: Line mover with a decelerating profile
--                covering exactly `height`, Slam: downward until the feet touch ground (Landed fires, camera shake),
--       Dash     front-loaded speed curve covering exactly the packet distance (Plane on ground, level in the air),
--                echo packets answering our own predicted dash are skipped
--       Teleport PivotTo locally (+ camera cut),  Root: horizontal velocity held at 0
--   * PredictDash(dir, castId?): instant local dash (Config.Human.DashDistance / DashTime) - does NOT fire Net
--     "Dash"; CombatController fires it (the server stays authoritative for charges and i-frames). Also plays the
--     local Dash clip right away (AnimController.PlayAbility "Dash": a side-step Dodge when not forward) and marks
--     castId predicted so the server's AbilityFx echo does not restart it.
--   * Character facing: Humanoid.AutoRotate = false + AlignOrientation toward the camera yaw while
--     CameraController.ShouldFaceCamera() (lock on) or Facing(true) / FaceFor(s) is requested; normal auto-rotate
--     otherwise. Never while Dead / Downed / Stunned / Boxed.
--   * Double jump for kits with Stats.DoubleJump (Integrity): second jump in the air (JumpPower, small push along
--     the move direction), neon ring VFX + "DoubleJump" sound + DoubleJumped signal (kit FX can add more).
--   * Blue SOUL (Status_Blue active or SoulMode "Blue"): extra downward VectorForce while airborne (total gravity
--     x Tuning.BlueGravityMult) and sluggish air steering. No double jump while blue.
--   * FallingDown / Ragdoll humanoid states are disabled on the local character (SPEC §19).
--
-- API (SPEC §20)
--   MovementController.Facing(on: boolean, key: string?)    request facing the camera (ref-counted by key)
--   MovementController.ApplyForceMove(packet: ForceMovePacket)
--   MovementController.IsDashing() -> boolean
-- Extras
--   MovementController.PredictDash(dir: Vector3, castId: number?) -> boolean
--   MovementController.FaceFor(seconds)                     face the camera briefly (casts while unlocked)
--   MovementController.SetFacingYaw(yaw?)                   explicit facing yaw (nil = camera yaw)
--   MovementController.Stop()                               cancel the active forced move
--   MovementController.ActiveMove() -> string?              kind of the active forced move
--   Signals: Dashed(direction, predicted), DoubleJumped(model), ForceMoved(packet), Landed(model, fallSpeed),
--            MoveEnded(kind)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Kits = require(Shared:WaitForChild("Kits"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local MovementController = {}
MovementController.Priority = 22

MovementController.Dashed = Signal.new()
MovementController.DoubleJumped = Signal.new()
MovementController.ForceMoved = Signal.new()
MovementController.Landed = Signal.new()
MovementController.MoveEnded = Signal.new()

local TUNING = {
	MoverForce = 1e7,
	FacingResponsiveness = 45,
	FacingMaxTorque = 1e7,
	FacingMaxAngularVelocity = 40,
	DashEchoWindow = 0.6, -- seconds after a predicted dash in which the server echo is ignored
	DashFrontLoad = 0.6, -- speed curve 1 - k x^2 (normalised to cover the exact distance)
	ImpulseDecay = Config.Human.LeapArcFactor, -- shared with the server leaps (Bravery / Integrity)
	PullDefaultSpeed = 20,
	PullStopDistance = 2,
	SlamDefault = Vector3.new(0, -140, 0),
	DoubleJumpBoost = 4,
	DoubleJumpMinAirTime = 0.08,
	BlueGravityMult = 1.9,
	BlueAirControl = 3.5,
	RingColor = Color3.fromRGB(120, 170, 255),
}
MovementController.Tuning = TUNING

export type ForceMovePacket = {
	kind: string,
	velocity: Vector3?,
	target: Vector3?,
	duration: number?,
	cframe: CFrame?,
	height: number?,
	echo: boolean?,
}

type Move = {
	Kind: string,
	Start: number,
	Duration: number,
	Velocity: Vector3,
	Target: Vector3?,
	Speed: number,
	Height: number,
	Air: boolean,
}

type Rig = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Trove: any,
	Attachment: Attachment?,
	Mover: LinearVelocity?,
	Align: AlignOrientation?,
	Gravity: VectorForce?,
	DoubleJump: boolean,
	DoubleJumpUsed: boolean,
	AirborneSince: number,
	FallSpeed: number,
	BlueH: Vector3?,
	LastYaw: number,
	-- cached attributes
	Dead: boolean,
	Downed: boolean,
	SoulMode: string,
	Statuses: { [string]: number },
}

local rig: Rig? = nil
local move: Move? = nil
local lastPredictedDash = -math.huge
local facingKeys: { [string]: boolean } = {}
local faceUntil = 0
local facingYawOverride: number? = nil
local ringPool: { BasePart } = {}
local ringIndex = 0
local started = false

local WATCHED_STATUSES = { "Status_Stunned", "Status_Boxed", "Status_Rooted", "Status_Blue" }

-------------------------------------------------------------------------------------------- lazy deps

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

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function statusActive(r: Rig, attr: string, nowServer: number): boolean
	local endsAt = r.Statuses[attr]
	return endsAt ~= nil and endsAt > nowServer
end

------------------------------------------------------------------------------------------- constraints

local function ensureConstraints(r: Rig): (Attachment, LinearVelocity, AlignOrientation, VectorForce)
	local attachment = r.Attachment
	if attachment == nil or attachment.Parent == nil then
		local a = Instance.new("Attachment")
		a.Name = "SV_MoveAtt"
		a.Parent = r.Root
		r.Attachment = a
		attachment = a
	end
	assert(attachment)
	local mover = r.Mover
	if mover == nil or mover.Parent == nil then
		local lv = Instance.new("LinearVelocity")
		lv.Name = "SV_ClientMover"
		lv.Attachment0 = attachment
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.ForceLimitMode = Enum.ForceLimitMode.Magnitude
		lv.MaxForce = TUNING.MoverForce
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.VectorVelocity = Vector3.zero
		lv.Enabled = false
		lv.Parent = r.Root
		r.Mover = lv
		mover = lv
	end
	assert(mover)
	local align = r.Align
	if align == nil or align.Parent == nil then
		local ao = Instance.new("AlignOrientation")
		ao.Name = "SV_FaceAlign"
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Attachment0 = attachment
		ao.Responsiveness = TUNING.FacingResponsiveness
		ao.MaxTorque = TUNING.FacingMaxTorque
		ao.MaxAngularVelocity = TUNING.FacingMaxAngularVelocity
		ao.RigidityEnabled = false
		ao.CFrame = CFrame.Angles(0, r.LastYaw, 0)
		ao.Enabled = false
		ao.Parent = r.Root
		r.Align = ao
		align = ao
	end
	assert(align)
	local gravity = r.Gravity
	if gravity == nil or gravity.Parent == nil then
		local vf = Instance.new("VectorForce")
		vf.Name = "SV_BlueGravity"
		vf.Attachment0 = attachment
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = true
		vf.Force = Vector3.zero
		vf.Enabled = false
		vf.Parent = r.Root
		r.Gravity = vf
		gravity = vf
	end
	assert(gravity)
	return attachment, mover, align, gravity
end

------------------------------------------------------------------------------------------- forced moves

local function stopMove(reason: string?)
	local m = move
	if m == nil then
		return
	end
	move = nil
	local r = rig
	if r and r.Mover then
		r.Mover.Enabled = false
	end
	MovementController.MoveEnded:Fire(m.Kind, reason)
end

local function grounded(r: Rig): boolean
	return r.Humanoid.FloorMaterial ~= Enum.Material.Air
end

local function startMove(m: Move)
	local r = rig
	if r == nil then
		return
	end
	stopMove("Replaced")
	local _, mover = ensureConstraints(r)
	local kind = m.Kind
	if kind == "Root" or kind == "Impulse" or (kind == "Dash" and not m.Air) then
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		mover.PrimaryTangentAxis = Vector3.xAxis
		mover.SecondaryTangentAxis = Vector3.zAxis
		mover.PlaneVelocity = if kind == "Root" then Vector2.zero else Vector2.new(m.Velocity.X, m.Velocity.Z)
	elseif kind == "Lift" then
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		mover.LineDirection = Vector3.yAxis
		mover.LineVelocity = 2 * m.Height / m.Duration
	else
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		mover.VectorVelocity = if kind == "Dash" then Vector3.new(m.Velocity.X, 0, m.Velocity.Z) else m.Velocity
	end
	mover.MaxForce = TUNING.MoverForce
	mover.Enabled = true
	move = m
end

local function updateMove(r: Rig)
	local m = move
	if m == nil then
		return
	end
	local mover = r.Mover
	if mover == nil or mover.Parent == nil then
		move = nil
		return
	end
	local t = os.clock() - m.Start
	if t >= m.Duration then
		stopMove("Done")
		return
	end
	local x = t / m.Duration
	local kind = m.Kind
	if kind == "Impulse" then
		local decay = (1 - x) ^ TUNING.ImpulseDecay
		mover.PlaneVelocity = Vector2.new(m.Velocity.X * decay, m.Velocity.Z * decay)
	elseif kind == "Dash" then
		local k = TUNING.DashFrontLoad
		local f = (1 - k * x * x) / (1 - k / 3)
		if m.Air then
			mover.VectorVelocity = Vector3.new(m.Velocity.X * f, 0, m.Velocity.Z * f)
		else
			mover.PlaneVelocity = Vector2.new(m.Velocity.X * f, m.Velocity.Z * f)
		end
	elseif kind == "Pull" then
		local target = m.Target
		if target == nil then
			return
		end
		local delta = target - r.Root.Position
		local distance = delta.Magnitude
		if distance < TUNING.PullStopDistance then
			stopMove("Arrived")
			return
		end
		mover.VectorVelocity = delta * (m.Speed / distance)
	elseif kind == "Lift" then
		mover.LineVelocity = 2 * m.Height / m.Duration * (1 - x)
	elseif kind == "Slam" then
		if t > 0.05 and grounded(r) then
			stopMove("Landed")
			MovementController.Landed:Fire(r.Model, math.abs(m.Velocity.Y))
			local Camera = controller("CameraController")
			if Camera then
				pcall(Camera.Shake, 0.5, 0.35)
			end
			local Sound = controller("SoundController")
			if Sound then
				pcall(Sound.Play, "SlamLand", r.Root)
			end
		end
	end
end

function MovementController.ApplyForceMove(packet: ForceMovePacket)
	if type(packet) ~= "table" then
		return
	end
	local r = rig
	if r == nil or r.Dead then
		return
	end
	local kind = packet.kind
	local clock = os.clock()
	if kind == "Teleport" then
		local cf = packet.cframe
		if typeof(cf) == "CFrame" then
			stopMove("Teleport")
			r.Model:PivotTo(cf)
			r.Root.AssemblyLinearVelocity = Vector3.zero
			local Camera = controller("CameraController")
			if Camera then
				pcall(Camera.Cut)
			end
		end
		MovementController.ForceMoved:Fire(packet)
		return
	end
	if kind == "Dash" and packet.echo == true and clock - lastPredictedDash < TUNING.DashEchoWindow then
		return -- our predicted dash already moved us
	end
	local velocity = if typeof(packet.velocity) == "Vector3" then packet.velocity :: Vector3 else Vector3.zero
	local duration = if type(packet.duration) == "number" then math.clamp(packet.duration, 0.02, 5) else nil
	local m: Move = {
		Kind = kind,
		Start = clock,
		Duration = 0.25,
		Velocity = velocity,
		Target = if typeof(packet.target) == "Vector3" then packet.target :: Vector3 else nil,
		Speed = TUNING.PullDefaultSpeed,
		Height = 0,
		Air = false,
	}
	if kind == "Impulse" then
		m.Duration = duration or 0.2
		-- vertical pop at once, the Plane mover carries the horizontal part
		if velocity.Y ~= 0 then
			local v = r.Root.AssemblyLinearVelocity
			r.Root.AssemblyLinearVelocity = Vector3.new(v.X, velocity.Y, v.Z)
		end
	elseif kind == "Pull" then
		m.Duration = duration or 0.25
		if velocity.Magnitude > 0.1 then
			m.Speed = velocity.Magnitude
		end
		if m.Target == nil then
			-- no target: treat as a plain velocity push
			m.Kind = "Impulse"
		end
	elseif kind == "Lift" then
		m.Duration = duration or 0.45
		m.Height = if type(packet.height) == "number" then math.clamp(packet.height, 0, 60) else 8
	elseif kind == "Slam" then
		m.Duration = duration or 0.3
		if velocity.Magnitude < 0.1 then
			m.Velocity = TUNING.SlamDefault
		end
	elseif kind == "Dash" then
		m.Duration = duration or Config.Human.DashTime
		m.Air = not grounded(r)
	elseif kind == "Root" then
		m.Duration = duration or 0.5
	else
		return
	end
	startMove(m)
	MovementController.ForceMoved:Fire(packet)
end

function MovementController.PredictDash(direction: Vector3, castId: number?): boolean
	local r = rig
	if r == nil or r.Dead or r.Downed then
		return false
	end
	local nowServer = serverNow()
	if
		statusActive(r, "Status_Stunned", nowServer)
		or statusActive(r, "Status_Boxed", nowServer)
		or statusActive(r, "Status_Rooted", nowServer)
	then
		return false
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		local look = r.Root.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	if flat.Magnitude < 1e-3 then
		return false
	end
	local dir = flat.Unit
	local time = math.max(Config.Human.DashTime, 0.05)
	local m: Move = {
		Kind = "Dash",
		Start = os.clock(),
		Duration = time,
		Velocity = dir * (Config.Human.DashDistance / time),
		Target = nil,
		Speed = 0,
		Height = 0,
		Air = not grounded(r),
	}
	lastPredictedDash = os.clock()
	startMove(m)
	-- own dash clip now (not ~ping later on the server echo); the echo of this castId is skipped
	local Anim = controller("AnimController")
	if Anim and type(Anim.PlayAbility) == "function" then
		if type(castId) == "number" and castId ~= 0 and type(Anim.MarkPredicted) == "function" then
			pcall(Anim.MarkPredicted, r.Model, castId)
		end
		pcall(Anim.PlayAbility, r.Model, r.Model:GetAttribute("KitId"), "Dash", nil, dir)
	end
	MovementController.Dashed:Fire(dir, true)
	local Camera = controller("CameraController")
	if Camera then
		pcall(Camera.Kick, 4, 0.28)
	end
	return true
end

function MovementController.IsDashing(): boolean
	return move ~= nil and (move :: Move).Kind == "Dash"
end

function MovementController.ActiveMove(): string?
	return if move then (move :: Move).Kind else nil
end

function MovementController.Stop()
	stopMove("Stopped")
end

------------------------------------------------------------------------------------------------ facing

function MovementController.Facing(on: boolean, key: string?)
	local k = key or "default"
	facingKeys[k] = if on then true else nil
end

function MovementController.FaceFor(seconds: number)
	if type(seconds) == "number" and seconds > 0 then
		faceUntil = math.max(faceUntil, os.clock() + seconds)
	end
end

function MovementController.SetFacingYaw(yaw: number?)
	facingYawOverride = yaw
end

local function updateFacing(r: Rig, nowServer: number)
	local Camera = controller("CameraController")
	local blocked = r.Dead
		or r.Downed
		or statusActive(r, "Status_Stunned", nowServer)
		or statusActive(r, "Status_Boxed", nowServer)
	local want = false
	if not blocked then
		if next(facingKeys) ~= nil or os.clock() < faceUntil then
			want = true
		elseif Camera and type(Camera.ShouldFaceCamera) == "function" then
			want = Camera.ShouldFaceCamera()
		end
	end
	local humanoid = r.Humanoid
	if want then
		local _, _, align = ensureConstraints(r)
		local yaw = facingYawOverride
		if yaw == nil and Camera then
			yaw = Camera.FacingYaw()
		end
		if yaw ~= nil and math.abs(yaw - r.LastYaw) > 1e-3 then
			r.LastYaw = yaw
			align.CFrame = CFrame.Angles(0, yaw, 0)
		end
		if not align.Enabled then
			align.Enabled = true
		end
		if humanoid.AutoRotate then
			humanoid.AutoRotate = false
		end
	else
		local align = r.Align
		if align and align.Enabled then
			align.Enabled = false
		end
		if not humanoid.AutoRotate then
			humanoid.AutoRotate = true
		end
	end
end

------------------------------------------------------------------------------------------- blue gravity

local function updateBlue(r: Rig, dt: number, nowServer: number)
	local blue = r.SoulMode == "Blue" or statusActive(r, "Status_Blue", nowServer)
	local airborne = not grounded(r)
	local gravity = r.Gravity
	if blue and airborne and move == nil and not r.Dead then
		if gravity == nil then
			local _, _, _, g = ensureConstraints(r)
			gravity = g
		end
		assert(gravity)
		local mass = r.Root.AssemblyMass
		gravity.Force = Vector3.new(0, -(TUNING.BlueGravityMult - 1) * workspace.Gravity * mass, 0)
		if not gravity.Enabled then
			gravity.Enabled = true
		end
		-- sluggish air steering: the humanoid only gets part of its usual air control
		local v = r.Root.AssemblyLinearVelocity
		local h = Vector3.new(v.X, 0, v.Z)
		local previous = r.BlueH or h
		local alpha = 1 - math.exp(-TUNING.BlueAirControl * dt)
		local blended = previous + (h - previous) * alpha
		r.BlueH = blended
		if (blended - h).Magnitude > 0.05 then
			r.Root.AssemblyLinearVelocity = Vector3.new(blended.X, v.Y, blended.Z)
		end
	else
		if gravity and gravity.Enabled then
			gravity.Enabled = false
		end
		r.BlueH = nil
	end
end

------------------------------------------------------------------------------------------- double jump

local function ringPart(): BasePart?
	local folder = workspace:FindFirstChild("SV_VFX")
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = "SV_VFX"
		f.Parent = workspace
		folder = f
	end
	ringIndex = ringIndex % 4 + 1
	local part = ringPool[ringIndex]
	if part == nil or part.Parent == nil then
		local p = Instance.new("Part")
		p.Name = "SV_JumpRing"
		p.Shape = Enum.PartType.Cylinder
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = Vector3.new(0.12, 1, 1)
		p.Parent = folder
		ringPool[ringIndex] = p
		part = p
	end
	return part
end

local function doubleJumpVfx(r: Rig)
	local part = ringPart()
	if part == nil then
		return
	end
	local kit = Kits.Get(r.Model:GetAttribute("KitId") or "")
	local color = if kit then kit.Color else TUNING.RingColor
	local feet = r.Root.Position - Vector3.new(0, r.Humanoid.HipHeight + r.Root.Size.Y * 0.5 - 0.2, 0)
	part.Color = color
	part.Size = Vector3.new(0.14, 2.2, 2.2)
	part.Transparency = 0.15
	part.CFrame = CFrame.new(feet) * CFrame.Angles(0, 0, math.rad(90))
	local tween = TweenService:Create(
		part,
		TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.04, 8.5, 8.5), Transparency = 1 }
	)
	tween:Play()
end

local function tryDoubleJump()
	local r = rig
	if r == nil or not r.DoubleJump or r.DoubleJumpUsed or r.Dead or r.Downed then
		return
	end
	local nowServer = serverNow()
	if
		statusActive(r, "Status_Stunned", nowServer)
		or statusActive(r, "Status_Boxed", nowServer)
		or statusActive(r, "Status_Rooted", nowServer)
		or statusActive(r, "Status_Blue", nowServer)
		or r.SoulMode == "Blue"
	then
		return
	end
	local humanoid = r.Humanoid
	local state = humanoid:GetState()
	if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
		return
	end
	if os.clock() - r.AirborneSince < TUNING.DoubleJumpMinAirTime then
		return
	end
	local jump = humanoid.JumpPower
	if jump <= 1 then
		return
	end
	r.DoubleJumpUsed = true
	local v = r.Root.AssemblyLinearVelocity
	local h = Vector3.new(v.X, 0, v.Z)
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude > 0.1 then
		local d = moveDir.Unit
		h = d * (math.max(h.Magnitude, humanoid.WalkSpeed) + TUNING.DoubleJumpBoost)
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	r.Root.AssemblyLinearVelocity = Vector3.new(h.X, jump, h.Z)
	doubleJumpVfx(r)
	local Sound = controller("SoundController")
	if Sound then
		pcall(Sound.Play, "DoubleJump", r.Root)
	end
	local Anim = controller("AnimController")
	if Anim and type(Anim.Play) == "function" then
		pcall(Anim.Play, r.Model, "Jump", { FadeIn = 0.05, Speed = 1.25 })
	end
	MovementController.DoubleJumped:Fire(r.Model)
end

------------------------------------------------------------------------------------------- character rig

local function releaseRig()
	local r = rig
	if r == nil then
		return
	end
	rig = nil
	move = nil
	r.Trove:Destroy()
end

local function setupRig(model: Model)
	releaseRig()
	local trove = Trove.new()
	local humanoid = model:WaitForChild("Humanoid", 10)
	local root = model:WaitForChild("HumanoidRootPart", 10)
	if humanoid == nil or root == nil or not humanoid:IsA("Humanoid") or not root:IsA("BasePart") then
		trove:Destroy()
		return
	end
	local player = Players.LocalPlayer
	if model.Parent == nil or (player ~= nil and player.Character ~= model) then
		trove:Destroy() -- the character changed while we waited for its parts
		return
	end
	local kit = Kits.Get(model:GetAttribute("KitId") or "")
	local look = root.CFrame.LookVector
	local r: Rig = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Trove = trove,
		Attachment = nil,
		Mover = nil,
		Align = nil,
		Gravity = nil,
		DoubleJump = kit ~= nil and kit.Stats.DoubleJump == true,
		DoubleJumpUsed = false,
		AirborneSince = os.clock(),
		FallSpeed = 0,
		BlueH = nil,
		LastYaw = math.atan2(-look.X, -look.Z),
		Dead = model:GetAttribute("Dead") == true,
		Downed = model:GetAttribute("Downed") == true,
		SoulMode = tostring(model:GetAttribute("SoulMode") or "Red"),
		Statuses = {},
	}
	for _, attr in WATCHED_STATUSES do
		local value = model:GetAttribute(attr)
		r.Statuses[attr] = if type(value) == "number" then value else nil
	end
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end)
	trove:Connect(model.AttributeChanged, function(attr: string)
		local value = model:GetAttribute(attr)
		if attr == "Dead" then
			r.Dead = value == true
			if r.Dead then
				stopMove("Dead")
			end
		elseif attr == "Downed" then
			r.Downed = value == true
		elseif attr == "SoulMode" then
			r.SoulMode = tostring(value or "Red")
		elseif attr == "KitId" then
			local k = Kits.Get(tostring(value or ""))
			r.DoubleJump = k ~= nil and k.Stats.DoubleJump == true
		elseif string.sub(attr, 1, 7) == "Status_" and table.find(WATCHED_STATUSES, attr) then
			r.Statuses[attr] = if type(value) == "number" then value else nil
		end
	end)
	trove:Connect(humanoid.StateChanged, function(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		if new == Enum.HumanoidStateType.Freefall or new == Enum.HumanoidStateType.Jumping then
			if old ~= Enum.HumanoidStateType.Freefall and old ~= Enum.HumanoidStateType.Jumping then
				r.AirborneSince = os.clock()
			end
		elseif
			new == Enum.HumanoidStateType.Landed
			or new == Enum.HumanoidStateType.Running
			or new == Enum.HumanoidStateType.RunningNoPhysics
			or new == Enum.HumanoidStateType.Climbing
			or new == Enum.HumanoidStateType.Swimming
		then
			if new == Enum.HumanoidStateType.Landed then
				MovementController.Landed:Fire(model, r.FallSpeed)
			end
			r.DoubleJumpUsed = false
			r.FallSpeed = 0
		end
	end)
	trove:Add(function()
		local function destroy(inst: Instance?)
			if inst then
				pcall(function()
					inst:Destroy()
				end)
			end
		end
		destroy(r.Mover)
		destroy(r.Align)
		destroy(r.Gravity)
		destroy(r.Attachment)
		pcall(function()
			humanoid.AutoRotate = true
		end)
	end)
	trove:Connect(model.AncestryChanged, function()
		if model.Parent == nil and rig == r then
			releaseRig()
		end
	end)
	rig = r
end

local function onStep(dt: number)
	local r = rig
	if r == nil then
		return
	end
	if r.Root.Parent == nil then
		releaseRig()
		return
	end
	local nowServer = serverNow()
	local vy = r.Root.AssemblyLinearVelocity.Y
	if vy < 0 then
		r.FallSpeed = math.max(r.FallSpeed, -vy)
	end
	updateMove(r)
	updateFacing(r, nowServer)
	updateBlue(r, dt, nowServer)
end

------------------------------------------------------------------------------------------------ lifecycle

function MovementController.Init() end

function MovementController.Start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	local function onCharacter(model: Model?)
		if model then
			task.spawn(setupRig, model)
		else
			releaseRig()
		end
	end
	local State = controller("StateController")
	if State and State.CharacterChanged then
		State.CharacterChanged:Connect(onCharacter)
		local ok, current = pcall(State.LocalCharacter)
		if ok and current then
			onCharacter(current)
		elseif player and player.Character then
			onCharacter(player.Character)
		end
	elseif player then
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			onCharacter(player.Character)
		end
	end
	local Input = controller("InputController")
	if Input and Input.Action then
		Input.Action:Connect(function(action: string, state: string)
			if action == "Jump" and state == "Begin" then
				tryDoubleJump()
			end
		end)
	end
	RunService.PreSimulation:Connect(onStep)
	task.spawn(function()
		Net.Client.On("ForceMove", function(packet: any)
			local ok, err = pcall(MovementController.ApplyForceMove, packet)
			if not ok then
				warn("[MovementController] ForceMove failed: " .. tostring(err))
			end
		end)
	end)
end

return MovementController
