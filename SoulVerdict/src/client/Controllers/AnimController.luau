--!strict
-- AnimController (client, SPEC §8 / §20, Priority 20): procedural animation for EVERY character model in
-- the workspace on this client (any Model with a Humanoid and a RigFamily attribute). One
-- RunService.PreSimulation loop writes Motor6D.Transform (AnimationConstraint.Transform is accepted too).
--
-- LAYERS (blended in this order into one 15-joint pose buffer, then smoothed by per-joint springs)
--   1 locomotion   Idle (Tired when Exhausted, IdleMenace in FinalForm) + Walk/Run/WalkBack/StrafeL/StrafeR
--                  4-way directional blend from the move direction relative to facing, all cycles share one
--                  phase (cadence = speed / blended Stride) so feet stay in sync; procedural hip yaw toward the
--                  move direction (backwards for backpedalling); "Step" footsteps on phase crossings.
--   2 air          Jump on take-off (and double jumps), Fall loop, Land impact scaled by the fall speed.
--   3 status       Block (Blocking, upper body), BlueHeavy (Status_Blue / SoulMode Blue), Downed (crawl, phase
--                  advances with crawl speed), Stunned (Status_Stunned), Death once (Dead) - by priority.
--   4 one-shots    Play() tracks with fade in/out, masks (Full clips shrink to the upper body while moving and
--                  hand their root twist to the waist), Mirror, markers; higher Priority blends last.
--   5 procedural   lean into acceleration & turns, breathing (faster after running), head/torso look-at
--                  toward the aim (local: CameraController.AimPoint, others: AimService relay, idle: nearby
--                  characters), aiming arms for clips with Aim, Blue-soul tremble, hit flinch impulses.
--   6 springs      critically/under-damped per-joint springs (Util/Spring coefficients) - follow-through and
--                  overshoot; skipped at LOD distance (> 120 studs: 15 Hz updates).
-- Hit reactions: Net "DamageFx" -> Hit flinch away from the attacker (+ spring impulses, melee hit-stop),
-- Parry, block recoil, Skeleton family lazy Dodge on "MISS". Dummies only wobble on their stand.
-- Kit casts: Net "AbilityFx" phase "Start" -> PlayAbility(caster, kit, ability, data) unless the caster's own
-- client already predicted that castId (MarkPredicted). M1 combos pick Slash/Punch/Kick N from data.combo.
-- Emotes: character attribute "Emote" (clip name, "" = stop) or AbilityFx ability "Emote" { data.clip }.
-- Victory: RoundEvent "RoundEnd" plays Victory on the winners until they move.
--
-- API (SPEC §8 + extras)
--   AnimController.Play(character, clip, opts?) -> TrackHandle?
--       opts = { Speed?, FadeIn?, FadeOut?, Weight?, Loop?, Mirror?, Priority?, Mask? }
--       TrackHandle = { Stop(fade?), Ended: Signal(), Marker: Signal(name), IsPlaying() -> boolean, Name, Length }
--   AnimController.Stop(character, clip, fade?)        AnimController.StopAll(character, fade?)
--   AnimController.SetAim(character, point: Vector3?)  explicit aim override (nil = automatic)
--   AnimController.HitStop(character, duration, shake?) freeze the pose (max with any running hit-stop)
--   AnimController.MarkPredicted(character, castId)    skip the server echo of a locally predicted cast
--   AnimController.PlayAbility(character, kitId, abilityId, data?) -> TrackHandle?   clip by kit data
--   AnimController.ResolveAbilityClip(character, kitId, abilityId, data?) -> (clipName?, speed?)
--   AnimController.HasClip(character, clip) -> boolean ; GetClip(character, clip) -> Clip?
--   AnimController.IsPlaying(character, clip) -> boolean
--   AnimController.Track(model, opts?) / Untrack(model) / IsTracked(model)   opts.Viewport = true animates a
--       model outside the workspace (ViewportFrame previews: FK writes part CFrames at 30 Hz)
--   Signals: Marker(character, clipName, markerName), Footstep(character, side "Left"|"Right"|"Both", intensity)
--   AnimController.Tuning   (numbers below)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = Shared:WaitForChild("Util")
local AnimFolder = Shared:WaitForChild("Anim")
local Signal = require(Util:WaitForChild("Signal"))
local Spring = require(Util:WaitForChild("Spring"))
local MathUtil = require(Util:WaitForChild("MathUtil"))
local Config = require(Shared:WaitForChild("Config"))
local Kits = require(Shared:WaitForChild("Kits"))
local Net = require(Shared:WaitForChild("Net"))
local Joints = require(AnimFolder:WaitForChild("Joints"))
local AnimMath = require(AnimFolder:WaitForChild("AnimMath"))
local Skeletons = require(Shared:WaitForChild("Rigs"):WaitForChild("Skeletons"))
local RigBuilder = require(Shared:WaitForChild("Rigs"):WaitForChild("RigBuilder"))
local ClipsFolder = AnimFolder:WaitForChild("Clips")

type Compiled = AnimMath.Compiled
type Buffer = AnimMath.Buffer
type Clip = AnimMath.Clip
type ClipLib = { [string]: Clip }

export type PlayOptions = {
	Speed: number?,
	FadeIn: number?,
	FadeOut: number?,
	Weight: number?,
	Loop: boolean?,
	Mirror: boolean?,
	Priority: number?,
	Mask: string?,
}

export type TrackHandle = {
	Stop: (...any) -> (),
	Ended: any,
	Marker: any,
	IsPlaying: () -> boolean,
	Name: string,
	Length: number,
}

type Track = {
	Name: string,
	Clip: Compiled,
	Time: number,
	Speed: number,
	Weight: number,
	FadeIn: number,
	FadeOut: number,
	Loop: boolean,
	Hold: boolean,
	Mirror: boolean,
	Priority: number,
	Order: number,
	Elapsed: number,
	Stopping: boolean,
	StopElapsed: number,
	StopFade: number,
	Env: number,
	Kind: string,
	MaskName: string,
	Done: boolean,
	Ended: any,
	Marker: any,
	Handle: TrackHandle?,
}

type Layer = { Weight: number, Time: number }

type CharState = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Family: string,
	KitId: string,
	IsDummy: boolean,
	IsLocal: boolean,
	Viewport: boolean,
	ViewportAccum: number,
	Scale: number,
	NeckHeight: number,
	Lib: ClipLib,
	KitLib: ClipLib?,
	Compiled: { [string]: Compiled | false },
	Motors: { any },
	MotorsDirty: boolean,
	Pose: Buffer,
	Tmp: Buffer,
	Tmp2: Buffer,
	Out: Buffer,
	Vel: Buffer,
	Initialized: boolean,
	Tracks: { Track },
	TrackOrder: number,
	Attr: { [string]: any },
	Conns: { RBXScriptConnection },
	-- locomotion
	Phase: number,
	IdleTime: number,
	IdleName: string,
	Speed: number,
	VelLocal: Vector3,
	AccLocal: Vector3,
	DirX: number,
	DirZ: number,
	HipYaw: number,
	LastPos: Vector3?,
	LastYaw: number?,
	YawRate: number,
	Exertion: number,
	BreathT: number,
	DownPhase: number,
	-- air
	Grounded: boolean,
	AirTime: number,
	JumpTime: number,
	AirW: number,
	VyPrev: number,
	LandTime: number,
	LandW: number,
	LandActive: boolean,
	-- status layers
	Layers: { [string]: Layer },
	DeathTrack: Track?,
	-- look / aim
	AimExplicit: Vector3?,
	AimRelay: Vector3?,
	AimRelayAt: number,
	LookYaw: number,
	LookPitch: number,
	Social: Model?,
	SocialAt: number,
	-- timing
	HitStopUntil: number,
	HitShake: number,
	Accum: number,
	LastActive: number,
	NextFidget: number,
	Predicted: { [number]: number },
	Seed: number,
}

local AnimController = {}
AnimController.Priority = 20
AnimController.Marker = Signal.new()
AnimController.Footstep = Signal.new()

local TUNING = {
	LodDistance = 120, -- studs from the camera: beyond = LodRate updates, no springs
	LodRate = 15,
	OffscreenRate = 12, -- behind the camera and > 30 studs away
	FarDistance = 400, -- beyond: 5 Hz
	MaxTracks = 6,
	DefaultFadeIn = 0.1,
	DefaultFadeOut = 0.18,
	AirGrace = 0.08, -- seconds airborne before the Fall pose takes over (steps, small drops)
	LandMinAir = 0.3,
	LookYaw = 75,
	LookPitch = 45,
	LookBehind = 115, -- aim further behind than this: look forward instead
	AimSendRate = 10, -- Hz (SPEC: <= 10)
	AimStale = 1.5,
	SocialRange = 24,
	FidgetMin = 8,
	FidgetMax = 16,
	ViewportRate = 30,
	MoveMaskStart = 1.5, -- planar speed where one-shots start shrinking to the upper body
	MoveMaskFull = 4,
}
AnimController.Tuning = TUNING

-- spring tuning per joint group: { angular frequency (rad/s), damping ratio }
local SPRING: { [string]: { number } } = {
	Spine = { 22, 0.9 },
	Head = { 15, 0.7 },
	Shoulder = { 26, 0.72 },
	Elbow = { 24, 0.64 },
	Wrist = { 20, 0.55 },
	Hip = { 44, 1 },
	Knee = { 44, 1 },
	Ankle = { 44, 1 },
}
local TRANSLATION_SPRING = { 32, 1 }
local DUMMY_ROOT_SPRING = { 9, 0.22 } -- training dummies wobble on their stand
local BOOST = { 1, 1.4, 1.85 } -- upper-body spring speed multipliers while actions play
local UPPER_GROUPS: { [string]: boolean } = { Spine = true, Head = true, Shoulder = true, Elbow = true, Wrist = true }

local NJ = Joints.COUNT
local JI = Joints.Index
local J_ROOT, J_WAIST, J_NECK = JI.Root, JI.Waist, JI.Neck
local J_LSH, J_RSH = JI.LeftShoulder, JI.RightShoulder
local function ch(j: number, c: number): number
	return (j - 1) * 6 + c
end
local GROUP_OF: { string } = {}
for i, name in Joints.ALL do
	GROUP_OF[i] = Joints.Group[name]
end

local FULL_MASK = Joints.MaskArray("Full")
local UPPERMOVE_MASK = Joints.MaskArray("UpperMove")
local LOWER_MASK = Joints.MaskArray("Lower")

local FIDGETS: { [string]: { string } } = {
	Skeleton = { "Idle_Look", "Idle_Stretch", "Wink", "Idle_Look" },
	Human = { "Idle_Look", "Idle_Fidget", "Idle_Look" },
}

local states: { [Model]: CharState } = {}
local pending: { [Model]: boolean } = {}
local familyLibs: { [string]: ClipLib } = {}
local kitLibs: { [string]: ClipLib | false } = {}
local neckHeights: { [string]: number } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local rayDirty = true
local started = false
local cameraController: any = nil
local cameraTriedAt = -math.huge
local lastAimSend = -math.huge
local lastAimSent: Vector3? = nil
local rng = Random.new()

---------------------------------------------------------------------------------------------------
-- Clip libraries
---------------------------------------------------------------------------------------------------

local function familyLib(family: string): ClipLib?
	local lib = familyLibs[family]
	if lib then
		return lib
	end
	local mod = ClipsFolder:FindFirstChild(family)
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			familyLibs[family] = res :: any
			return res :: any
		end
		warn("[AnimController] failed to load clips for " .. family .. ": " .. tostring(res))
	end
	return nil
end

local function kitLib(kitId: string): ClipLib?
	local cached = kitLibs[kitId]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local folder = ClipsFolder:FindFirstChild("Kits")
	local mod = folder and folder:FindFirstChild(kitId)
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			kitLibs[kitId] = res :: any
			return res :: any
		end
		warn("[AnimController] failed to load kit clips " .. kitId .. ": " .. tostring(res))
	end
	kitLibs[kitId] = false
	return nil
end

local function neckHeight(family: string): number
	local h = neckHeights[family]
	if h then
		return h
	end
	local ok, r = pcall(Skeletons.Resolve, family)
	h = if ok then (r.Joints.Neck.Pivot.Y - r.Joints.Root.Pivot.Y) else 1.6
	neckHeights[family] = h
	return h
end

local function rawClip(st: CharState, name: string): Clip?
	if st.KitLib and st.KitLib[name] then
		return st.KitLib[name]
	end
	return st.Lib[name]
end

local function compiled(st: CharState, name: string): Compiled?
	local c = st.Compiled[name]
	if c == nil then
		local raw = rawClip(st, name)
		c = if raw then AnimMath.Compile(raw, name) else false
		st.Compiled[name] = c
	end
	return if c == false then nil else c :: Compiled
end

---------------------------------------------------------------------------------------------------
-- Motors
---------------------------------------------------------------------------------------------------

local function isJoint(inst: Instance): boolean
	return (inst:IsA("Motor6D") or inst:IsA("AnimationConstraint")) and JI[inst.Name] ~= nil
end

local function refreshMotors(st: CharState)
	local motors = table.create(NJ, false) :: { any }
	for _, inst in st.Model:GetDescendants() do
		if isJoint(inst) then
			local j = JI[inst.Name]
			-- prefer Motor6D when both exist
			if motors[j] == false or inst:IsA("Motor6D") then
				motors[j] = inst
			end
		end
	end
	st.Motors = motors
	st.MotorsDirty = false
end

local function resetMotors(st: CharState)
	for _, m in st.Motors do
		if m then
			pcall(function()
				(m :: any).Transform = CFrame.identity
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Tracks
---------------------------------------------------------------------------------------------------

local function finishTrack(t: Track)
	if t.Done then
		return
	end
	t.Done = true
	t.Ended:Fire()
	task.defer(function()
		t.Ended:DisconnectAll()
		t.Marker:DisconnectAll()
	end)
end

local function stopTrack(t: Track, fade: number?)
	if t.Done or t.Stopping then
		return
	end
	t.Stopping = true
	t.StopElapsed = 0
	t.StopFade = math.max(0, fade or t.FadeOut)
	if t.StopFade <= 0 then
		finishTrack(t)
	end
end

local function kindOf(name: string): string
	if string.sub(name, 1, 6) == "Emote_" or name == "Victory" then
		return "Emote"
	elseif string.sub(name, 1, 5) == "Idle_" or name == "Wink" then
		return "Fidget"
	end
	return "Action"
end

local function startTrack(st: CharState, name: string, opts: PlayOptions?): Track?
	local c = compiled(st, name)
	if c == nil then
		return nil
	end
	local o: PlayOptions = opts or {}
	-- restarting the same clip: the old instance fades out quickly
	for _, t in st.Tracks do
		if t.Name == name and not t.Done then
			stopTrack(t, 0.06)
		end
	end
	local kind = kindOf(name)
	if kind ~= "Fidget" then
		for _, t in st.Tracks do
			if t.Kind == "Fidget" or (t.Kind == "Emote" and kind == "Action") then
				stopTrack(t, 0.12)
			end
		end
		if kind == "Action" then
			st.LastActive = os.clock()
		end
	end
	st.TrackOrder += 1
	local loop = if o.Loop ~= nil then o.Loop else c.Loop
	local t: Track = {
		Name = name,
		Clip = c,
		Time = 0,
		Speed = math.max(0.01, (o.Speed or 1) * c.Speed),
		Weight = math.clamp(o.Weight or 1, 0, 1),
		FadeIn = o.FadeIn or c.FadeIn or TUNING.DefaultFadeIn,
		FadeOut = o.FadeOut or c.FadeOut or TUNING.DefaultFadeOut,
		Loop = loop,
		Hold = c.Hold and not loop,
		Mirror = o.Mirror == true,
		Priority = o.Priority or c.Priority,
		Order = st.TrackOrder,
		Elapsed = 0,
		Stopping = false,
		StopElapsed = 0,
		StopFade = 0,
		Env = 0,
		Kind = kind,
		MaskName = o.Mask or c.Mask,
		Done = false,
		Ended = Signal.new(),
		Marker = Signal.new(),
		Handle = nil,
	}
	table.insert(st.Tracks, t)
	table.sort(st.Tracks, function(a, b)
		if a.Priority ~= b.Priority then
			return a.Priority < b.Priority
		end
		return a.Order < b.Order
	end)
	-- cap: drop the oldest finished-looking tracks
	while #st.Tracks > TUNING.MaxTracks do
		local oldest, idx = nil :: Track?, 0
		for i, tr in st.Tracks do
			if tr ~= t and (oldest == nil or tr.Order < (oldest :: Track).Order) then
				oldest, idx = tr, i
			end
		end
		if oldest == nil then
			break
		end
		finishTrack(oldest)
		table.remove(st.Tracks, idx)
	end
	-- t = 0 markers fire on the first update (EventsBetween uses a half-open (a, b] window)
	t.Time = -1e-6
	return t
end

local function handleFor(t: Track): TrackHandle
	if t.Handle then
		return t.Handle :: TrackHandle
	end
	local handle: TrackHandle
	handle = {
		Stop = function(a: any?, b: any?)
			local fade = if type(a) == "table" then b else a
			stopTrack(t, if type(fade) == "number" then fade else nil)
		end,
		Ended = t.Ended,
		Marker = t.Marker,
		IsPlaying = function()
			return not t.Done
		end,
		Name = t.Name,
		Length = t.Clip.Length,
	}
	t.Handle = handle
	return handle
end

---------------------------------------------------------------------------------------------------
-- Tracking characters
---------------------------------------------------------------------------------------------------

local function rebuildRayFilter()
	local list: { Instance } = {}
	for model in states do
		table.insert(list, model)
	end
	rayParams.FilterDescendantsInstances = list
	rayDirty = false
end

local function scaleOf(model: Model): number
	local s = model:GetAttribute("RigScale")
	return if type(s) == "number" and s > 0 then s else 1
end

local untrack: (Model) -> ()

local function trackModel(model: Model, viewport: boolean?): CharState?
	if states[model] then
		return states[model]
	end
	local family = model:GetAttribute("RigFamily")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if type(family) ~= "string" or humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end
	local lib = familyLib(family)
	if lib == nil then
		return nil
	end
	local kitId = model:GetAttribute("KitId")
	local kit = if type(kitId) == "string" then kitId else ""
	local player = Players.LocalPlayer
	local attrs = model:GetAttributes()
	local now = os.clock()
	local st: CharState = {
		Model = model,
		Humanoid = humanoid,
		Root = root :: BasePart,
		Family = family,
		KitId = kit,
		IsDummy = kit == "Dummy" or attrs.Team == "Dummy" or attrs.BlueprintId == "Dummy",
		IsLocal = player ~= nil and player.Character == model,
		Viewport = viewport == true,
		ViewportAccum = 0,
		Scale = scaleOf(model),
		NeckHeight = neckHeight(family),
		Lib = lib,
		KitLib = if kit ~= "" then kitLib(kit) else nil,
		Compiled = {},
		Motors = {},
		MotorsDirty = true,
		Pose = AnimMath.NewBuffer(),
		Tmp = AnimMath.NewBuffer(),
		Tmp2 = AnimMath.NewBuffer(),
		Out = AnimMath.NewBuffer(),
		Vel = AnimMath.NewBuffer(),
		Initialized = false,
		Tracks = {},
		TrackOrder = 0,
		Attr = attrs,
		Conns = {},
		Phase = 0,
		IdleTime = rng:NextNumber() * 3,
		IdleName = "Idle",
		Speed = 0,
		VelLocal = Vector3.zero,
		AccLocal = Vector3.zero,
		DirX = 0,
		DirZ = 1,
		HipYaw = 0,
		LastPos = nil,
		LastYaw = nil,
		YawRate = 0,
		Exertion = 0,
		BreathT = rng:NextNumber() * 6,
		DownPhase = 0,
		Grounded = true,
		AirTime = 0,
		JumpTime = math.huge,
		AirW = 0,
		VyPrev = 0,
		LandTime = 0,
		LandW = 0,
		LandActive = false,
		Layers = {
			Block = { Weight = 0, Time = 0 },
			Blue = { Weight = 0, Time = 0 },
			Downed = { Weight = 0, Time = 0 },
			Stunned = { Weight = 0, Time = 0 },
		},
		DeathTrack = nil,
		AimExplicit = nil,
		AimRelay = nil,
		AimRelayAt = -math.huge,
		LookYaw = 0,
		LookPitch = 0,
		Social = nil,
		SocialAt = 0,
		HitStopUntil = 0,
		HitShake = 0,
		Accum = 0,
		LastActive = now,
		NextFidget = now + TUNING.FidgetMin + rng:NextNumber() * (TUNING.FidgetMax - TUNING.FidgetMin),
		Predicted = {},
		Seed = rng:NextNumber() * 100,
	}
	states[model] = st
	pending[model] = nil
	rayDirty = true

	table.insert(
		st.Conns,
		model.AttributeChanged:Connect(function(name: string)
			local v = model:GetAttribute(name)
			st.Attr[name] = v
			if name == "RigScale" then
				st.Scale = scaleOf(model)
			elseif name == "KitId" then
				st.KitId = if type(v) == "string" then v else ""
				st.KitLib = if st.KitId ~= "" then kitLib(st.KitId) else nil
				table.clear(st.Compiled)
			elseif name == "RigFamily" then
				untrack(model)
			elseif name == "Emote" then
				if type(v) == "string" and v ~= "" then
					AnimController.Play(model, v)
				else
					for _, t in st.Tracks do
						if t.Kind == "Emote" then
							stopTrack(t, 0.25)
						end
					end
				end
			end
		end)
	)
	table.insert(
		st.Conns,
		model.DescendantAdded:Connect(function(inst: Instance)
			if isJoint(inst) then
				st.MotorsDirty = true
			end
		end)
	)
	table.insert(
		st.Conns,
		model.DescendantRemoving:Connect(function(inst: Instance)
			if isJoint(inst) then
				st.MotorsDirty = true
			end
		end)
	)
	if not st.Viewport then
		table.insert(
			st.Conns,
			model.AncestryChanged:Connect(function()
				if not model:IsDescendantOf(workspace) then
					untrack(model)
				end
			end)
		)
	end
	table.insert(
		st.Conns,
		humanoid.AncestryChanged:Connect(function()
			if humanoid.Parent ~= model then
				untrack(model)
			end
		end)
	)
	return st
end

untrack = function(model: Model)
	local st = states[model]
	if st == nil then
		return
	end
	states[model] = nil
	rayDirty = true
	for _, c in st.Conns do
		c:Disconnect()
	end
	for _, t in st.Tracks do
		finishTrack(t)
	end
	table.clear(st.Tracks)
	if model.Parent ~= nil then
		resetMotors(st)
	end
end

local function consider(model: Instance?)
	if model == nil or not model:IsA("Model") then
		return
	end
	local m = model :: Model
	if states[m] or m:FindFirstChildOfClass("Humanoid") == nil then
		return
	end
	if trackModel(m) == nil and not pending[m] then
		-- attribute or root not there yet: retry when they appear
		pending[m] = true
		local conns: { RBXScriptConnection } = {}
		local function retry()
			if states[m] or trackModel(m) then
				for _, c in conns do
					c:Disconnect()
				end
				pending[m] = nil
			end
		end
		table.insert(conns, m:GetAttributeChangedSignal("RigFamily"):Connect(retry))
		table.insert(conns, m.ChildAdded:Connect(retry))
		table.insert(
			conns,
			m.AncestryChanged:Connect(function()
				if not m:IsDescendantOf(workspace) then
					for _, c in conns do
						c:Disconnect()
					end
					pending[m] = nil
				end
			end)
		)
	end
end

---------------------------------------------------------------------------------------------------
-- Aim helpers
---------------------------------------------------------------------------------------------------

local function camera(): any
	if cameraController ~= nil then
		return cameraController
	end
	local now = os.clock()
	if now - cameraTriedAt < 3 then
		return nil
	end
	cameraTriedAt = now
	local mod = script.Parent and script.Parent:FindFirstChild("CameraController")
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			cameraController = res
		end
	end
	return cameraController
end

local function localAimPoint(): Vector3?
	local cc = camera()
	if cc and type(cc.AimPoint) == "function" then
		local ok, p = pcall(cc.AimPoint, 160)
		if ok and typeof(p) == "Vector3" then
			return p
		end
	end
	local cam = workspace.CurrentCamera
	if cam then
		return cam.CFrame.Position + cam.CFrame.LookVector * 120
	end
	return nil
end

local function socialTarget(st: CharState, now: number): Vector3?
	if now - st.SocialAt > 0.6 then
		st.SocialAt = now
		local best, bestD = nil :: Model?, TUNING.SocialRange
		local pos = st.Root.Position
		local look = st.Root.CFrame.LookVector
		for model, other in states do
			if model ~= st.Model and not other.Viewport and other.Attr.Dead ~= true then
				local d = other.Root.Position - pos
				local dist = d.Magnitude
				if dist < bestD and dist > 0.5 and d.Unit:Dot(look) > -0.1 then
					best, bestD = model, dist
				end
			end
		end
		st.Social = best
	end
	local m = st.Social
	if m then
		local other = states[m]
		if other then
			return other.Root.Position + Vector3.new(0, other.NeckHeight * other.Scale + 0.6, 0)
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------------------------------

local coeffCache: { [string]: { number } } = {}
local coeffDt = -1

local function coeffs(speed: number, damping: number, dt: number): (number, number, number, number)
	if dt ~= coeffDt then
		table.clear(coeffCache)
		coeffDt = dt
	end
	local key = speed .. ":" .. damping
	local c = coeffCache[key]
	if c == nil then
		local a, b, cc, d = Spring.Coefficients(speed, damping, dt)
		c = { a, b, cc, d }
		coeffCache[key] = c
	end
	return c[1], c[2], c[3], c[4]
end

local function statusActive(v: any, serverNow: number): boolean
	return type(v) == "number" and v > serverNow
end

local function approach(w: number, target: number, rateIn: number, rateOut: number, dt: number): number
	if target > w then
		return math.min(target, w + dt * rateIn)
	end
	return math.max(target, w - dt * rateOut)
end

local function wrapFast(d: number): number
	if d > 180 or d < -180 then
		return AnimMath.Wrap180(d)
	end
	return d
end

local function sampleLayer(st: CharState, name: string, time: number, w: number, mask: { number }?)
	if w <= 0.001 then
		return
	end
	local c = compiled(st, name)
	if c then
		AnimMath.Sample(c, time, st.Tmp)
		AnimMath.BlendInto(st.Pose, st.Tmp, w, mask, c.Driven)
	end
end

local function fireMarkers(st: CharState, t: Track, a: number, b: number)
	AnimMath.EventsBetween(t.Clip, a, b, function(name: string)
		t.Marker:Fire(name)
		AnimController.Marker:Fire(st.Model, t.Name, name)
	end)
end

local function sense(st: CharState, dt: number, now: number)
	local root = st.Root
	local cf = root.CFrame
	local pos = cf.Position
	local vel = root.AssemblyLinearVelocity
	if root.Anchored or st.Viewport then
		vel = Vector3.zero
		if st.LastPos and not st.Viewport then
			local delta = pos - (st.LastPos :: Vector3)
			if delta.Magnitude < 25 then
				vel = delta / math.max(dt, 1e-3)
			end
		end
	end
	st.LastPos = pos
	local look = cf.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 1e-3 then
		flatLook = Vector3.new(0, 0, -1)
	end
	flatLook = flatLook.Unit
	local flatRight = Vector3.new(-flatLook.Z, 0, flatLook.X)
	local planar = Vector3.new(vel.X, 0, vel.Z)
	local speed = planar.Magnitude
	if speed > 80 then
		speed = 80
	end
	st.Speed = MathUtil.damp(st.Speed, speed, 12, dt)
	local f, r = planar:Dot(flatLook), planar:Dot(flatRight)
	if speed > 0.6 then
		st.DirX = MathUtil.damp(st.DirX, r / speed, 10, dt)
		st.DirZ = MathUtil.damp(st.DirZ, f / speed, 10, dt)
	else
		st.DirX = MathUtil.damp(st.DirX, 0, 4, dt)
		st.DirZ = MathUtil.damp(st.DirZ, 1, 4, dt)
	end
	local velLocal = Vector3.new(r, vel.Y, f)
	local acc = (velLocal - st.VelLocal) / math.max(dt, 1e-3)
	if acc.Magnitude > 400 then
		acc = acc.Unit * 400
	end
	st.AccLocal = MathUtil.dampVector(st.AccLocal, acc, 8, dt)
	st.VelLocal = velLocal
	local yaw = math.atan2(-flatLook.X, -flatLook.Z)
	if st.LastYaw then
		local rate = MathUtil.angleDiff(st.LastYaw :: number, yaw) / math.max(dt, 1e-3)
		st.YawRate = MathUtil.damp(st.YawRate, math.clamp(rate, -12, 12), 10, dt)
	end
	st.LastYaw = yaw
	-- exertion: rises while running, decays slowly (breathing rate and depth follow it)
	if speed > 12 then
		st.Exertion = math.min(1, st.Exertion + dt * 0.12)
	else
		st.Exertion = math.max(0, st.Exertion - dt * 0.05)
	end

	-- ground
	local vy = vel.Y
	local grounded: boolean
	if st.Viewport then
		grounded = true
	elseif st.IsLocal then
		grounded = st.Humanoid.FloorMaterial ~= Enum.Material.Air
	else
		if rayDirty then
			rebuildRayFilter()
		end
		local len = root.Size.Y * 0.5 + st.Humanoid.HipHeight + 0.7 * st.Scale
		grounded = workspace:Raycast(pos, Vector3.new(0, -len, 0), rayParams) ~= nil and vy < 7
	end
	if grounded then
		if not st.Grounded and (st.AirTime > TUNING.LandMinAir or st.VyPrev < -24) then
			st.LandActive = true
			st.LandTime = 0
			st.LandW = math.clamp(-st.VyPrev / 55 + st.AirTime * 0.15, 0.3, 1)
			AnimController.Footstep:Fire(st.Model, "Both", st.LandW)
			-- squash: push the root spring down
			st.Vel[ch(J_ROOT, 5)] -= 2.2 * st.LandW
		end
		st.AirTime = 0
	else
		if st.Grounded then
			st.AirTime = 0
			st.JumpTime = if vy > 5 then 0 else math.huge
		elseif vy - st.VyPrev > 14 and vy > 8 then
			st.JumpTime = 0 -- double jump
		end
		st.AirTime += dt
		st.JumpTime += dt
	end
	st.Grounded = grounded
	st.VyPrev = vy
end

local function chooseIdle(st: CharState, serverNow: number): string
	local a = st.Attr
	if st.Family == "Skeleton" then
		if (type(a.Exhausted) == "number" and a.Exhausted > serverNow) or statusActive(a.Status_Exhausted, serverNow) then
			if compiled(st, "Tired") then
				return "Tired"
			end
		end
		if a.FinalForm == true and compiled(st, "IdleMenace") then
			return "IdleMenace"
		end
	end
	return "Idle"
end

local function buildPose(st: CharState, dt: number, now: number, serverNow: number)
	local P = st.Pose
	local attr = st.Attr
	local dead = attr.Dead == true or (st.Humanoid.Health <= 0 and st.Humanoid.MaxHealth > 0 and not st.IsDummy)
	local downed = attr.Downed == true and not dead
	local stunned = statusActive(attr.Status_Stunned, serverNow) and not dead and not downed
	local blue = (statusActive(attr.Status_Blue, serverNow) or attr.SoulMode == "Blue") and not dead and not downed
	local blocking = attr.Blocking == true and not dead and not downed and not stunned
	local speed = st.Speed
	local airborne = not st.Grounded

	-- death (once, held)
	if dead and st.DeathTrack == nil then
		for _, t in st.Tracks do
			stopTrack(t, 0.1)
		end
		st.DeathTrack = startTrack(st, "Death", { Priority = 4 })
	elseif not dead and st.DeathTrack then
		stopTrack(st.DeathTrack :: Track, 0.3)
		st.DeathTrack = nil
	end

	-- 1 locomotion ------------------------------------------------------------------------------
	local idleName = chooseIdle(st, serverNow)
	if idleName ~= st.IdleName then
		st.IdleName = idleName
	end
	st.IdleTime += dt
	local idleC = compiled(st, idleName) or compiled(st, "Idle")
	AnimMath.ZeroBuffer(P)
	if idleC then
		AnimMath.Sample(idleC, st.IdleTime, P)
	end
	local idleW, walkW, runW = AnimMath.LocomotionWeights(speed)
	if st.IsDummy then
		idleW, walkW, runW = 1, 0, 0
	end
	local moveW = walkW + runW
	local theta = math.atan2(-st.DirX, st.DirZ) -- > 0: moving left of facing
	local fw, bw, lw, rw = AnimMath.DirectionWeights(theta)
	if moveW > 0.001 then
		local walkC, runC = compiled(st, "Walk"), compiled(st, "Run")
		local backC = compiled(st, "WalkBack") or walkC
		local leftC, rightC = compiled(st, "StrafeL") or walkC, compiled(st, "StrafeR") or walkC
		local function stride(c: Compiled?, fallback: number): number
			return if c and c.Stride then c.Stride :: number else fallback
		end
		local fwdStride = (stride(walkC, 7) * walkW + stride(runC, 11) * runW) / moveW
		local blended = fw * fwdStride + bw * stride(backC, 6) + (lw + rw) * stride(leftC, 6)
		local cadence = AnimMath.Cadence(speed, blended, 0.6, 2.6)
		if blue then
			cadence *= 0.7
		end
		local prev = st.Phase
		st.Phase = (st.Phase + dt * cadence) % 1
		if st.Grounded and moveW > 0.35 and not downed and not dead then
			local crossedHalf = prev < 0.5 and st.Phase >= 0.5
			local crossedZero = st.Phase < prev
			if crossedZero or crossedHalf then
				AnimController.Footstep:Fire(st.Model, if crossedZero then "Left" else "Right", math.clamp(speed / 20, 0.2, 1))
			end
		end
		local acc = idleW
		local function add(c: Compiled?, w: number)
			if c == nil or w <= 0.001 then
				return
			end
			AnimMath.Sample(c, st.Phase * c.Length, st.Tmp)
			acc += w
			AnimMath.BlendInto(P, st.Tmp, w / acc, nil, c.Driven)
		end
		add(walkC, fw * walkW)
		add(runC, fw * runW)
		add(backC, bw * moveW)
		add(leftC, lw * moveW)
		add(rightC, rw * moveW)
	end
	-- hip yaw toward the movement direction (backwards: toward the reverse direction)
	local diag = if fw >= bw then theta else MathUtil.wrapAngle(theta - math.pi)
	local hipTarget = math.deg(math.clamp(diag, -1.2, 1.2)) * 0.32 * moveW
	st.HipYaw = MathUtil.damp(st.HipYaw, hipTarget, 8, dt)

	-- 2 air -------------------------------------------------------------------------------------
	local airTarget = if (airborne and (st.AirTime > TUNING.AirGrace or st.JumpTime < 0.4)) and not downed and not dead then 1 else 0
	st.AirW = approach(st.AirW, airTarget, 12, 18, dt)
	if st.AirW > 0.001 then
		local jumpC, fallC = compiled(st, "Jump"), compiled(st, "Fall")
		local A2 = st.Tmp2
		AnimMath.CopyBuffer(A2, P)
		local fallW = 1
		if jumpC and st.JumpTime < jumpC.Length then
			fallW = MathUtil.smoothstep(jumpC.Length * 0.45, jumpC.Length, st.JumpTime)
			if st.VyPrev < -6 then
				fallW = math.max(fallW, 0.6)
			end
		end
		if jumpC and fallW < 1 then
			AnimMath.Sample(jumpC, st.JumpTime, st.Tmp)
			AnimMath.BlendInto(A2, st.Tmp, 1, nil, jumpC.Driven)
		end
		if fallC and fallW > 0 then
			AnimMath.Sample(fallC, st.AirTime, st.Tmp)
			AnimMath.BlendInto(A2, st.Tmp, fallW, nil, fallC.Driven)
		end
		AnimMath.BlendInto(P, A2, st.AirW)
	end
	if st.LandActive then
		local landC = compiled(st, "Land")
		if landC == nil then
			st.LandActive = false
		else
			st.LandTime += dt
			local remaining = landC.Length - st.LandTime
			if remaining <= 0 then
				st.LandActive = false
			else
				local env = AnimMath.Envelope(st.LandTime, 0.02, remaining, 0.12) * st.LandW
				local mask = if speed > TUNING.MoveMaskStart then LOWER_MASK else FULL_MASK
				AnimMath.Sample(landC, st.LandTime, st.Tmp)
				AnimMath.BlendInto(P, st.Tmp, env, mask, landC.Driven)
			end
		end
	end

	-- 3+4 status layers interleaved with tracks by priority ---------------------------------------
	local L = st.Layers
	L.Block.Weight = approach(L.Block.Weight, if blocking then 1 else 0, 14, 9, dt)
	L.Blue.Weight = approach(L.Blue.Weight, if blue then (if speed > 3 then 0.55 else 0.9) else 0, 6, 4, dt)
	L.Downed.Weight = approach(L.Downed.Weight, if downed then 1 else 0, 4, 3, dt)
	L.Stunned.Weight = approach(L.Stunned.Weight, if stunned then 1 else 0, 9, 4, dt)
	for _, layer in L do
		layer.Time += dt
	end
	if downed and speed > 0.4 then
		local downC = compiled(st, "Downed")
		local stride = if downC and downC.Stride then downC.Stride :: number else 2.5
		st.DownPhase = (st.DownPhase + dt * math.clamp(speed / stride, 0.2, 1.4)) % 1
	end
	if (downed or stunned or dead) and #st.Tracks > 0 then
		for _, t in st.Tracks do
			if t.Priority < 3 and not t.Stopping then
				stopTrack(t, 0.12)
			end
		end
	end

	-- moving one-shots shrink toward the upper body
	local moveF = if airborne
		then 1
		else MathUtil.smoothstep(TUNING.MoveMaskStart, TUNING.MoveMaskFull, speed)
	local moveMask = st.Tmp2 -- reuse as a 15-entry mask array (first NJ entries)
	for j = 1, NJ do
		moveMask[j] = FULL_MASK[j] + (UPPERMOVE_MASK[j] - FULL_MASK[j]) * moveF
	end
	local actionW, aimR, aimL, aimT = 0, 0, 0, 0
	local fullBodyW = 0

	local function applyLayer(name: string, layer: Layer, prio: number)
		if layer.Weight <= 0.001 then
			return
		end
		if name == "Block" then
			sampleLayer(st, "Block", layer.Time, layer.Weight, Joints.MaskArray("Upper"))
		elseif name == "Blue" then
			sampleLayer(st, "BlueHeavy", layer.Time, layer.Weight, if speed > 3 then Joints.MaskArray("Upper") else nil)
		elseif name == "Downed" then
			local c = compiled(st, "Downed")
			if c then
				AnimMath.Sample(c, st.DownPhase * c.Length, st.Tmp)
				AnimMath.BlendInto(P, st.Tmp, layer.Weight, nil, c.Driven)
			end
			fullBodyW = math.max(fullBodyW, layer.Weight)
		elseif name == "Stunned" then
			sampleLayer(st, "Stunned", layer.Time, layer.Weight)
			fullBodyW = math.max(fullBodyW, layer.Weight)
		end
		local _ = prio
	end

	local trackIdx = 1
	local tracks = st.Tracks
	local function runTracksUpTo(prio: number)
		while trackIdx <= #tracks and tracks[trackIdx].Priority <= prio do
			local t = tracks[trackIdx]
			trackIdx += 1
			if not t.Done then
				local c = t.Clip
				local prevTime = t.Time
				t.Time += dt * t.Speed
				t.Elapsed += dt
				fireMarkers(st, t, prevTime, t.Time)
				-- envelope
				local remaining = math.huge
				if not t.Loop and not t.Hold then
					remaining = (c.Length - t.Time) / t.Speed
				end
				local env = AnimMath.Envelope(t.Elapsed, t.FadeIn, remaining, t.FadeOut)
				if t.Stopping then
					t.StopElapsed += dt
					env *= if t.StopFade > 0 then math.clamp(1 - t.StopElapsed / t.StopFade, 0, 1) else 0
					if t.StopElapsed >= t.StopFade then
						finishTrack(t)
					end
				end
				if not t.Loop and not t.Hold and t.Time >= c.Length then
					finishTrack(t)
				end
				-- emotes / fidgets end when the character moves
				if (t.Kind == "Emote" or t.Kind == "Fidget") and (speed > 3 or airborne) then
					stopTrack(t, 0.2)
				end
				t.Env = env
				local w = env * t.Weight
				if w > 0.001 and not t.Done then
					AnimMath.Sample(c, t.Time, st.Tmp, t.Mirror)
					local cc = if t.Mirror and c.Mirrored then c.Mirrored :: Compiled else c
					local mask: { number }
					local rootW = 1
					if t.MaskName == "Full" and not c.FullBody then
						mask = moveMask
						rootW = moveMask[J_ROOT]
					else
						mask = Joints.MaskArray(t.MaskName)
						rootW = mask[J_ROOT]
					end
					-- root twist the mask drops goes to the waist (keeps the upper-body intent while walking)
					local wRootLost = w * (1 - rootW)
					local rootRy, rootRx = st.Tmp[ch(J_ROOT, 2)], st.Tmp[ch(J_ROOT, 1)]
					AnimMath.BlendInto(P, st.Tmp, w, mask, cc.Driven)
					if wRootLost > 0.001 and cc.Driven[J_ROOT] then
						P[ch(J_WAIST, 2)] += wrapFast(rootRy) * wRootLost * 0.8
						P[ch(J_WAIST, 1)] += rootRx * wRootLost * 0.5
					end
					if t.Kind == "Action" or t.Priority >= 3 then
						actionW = math.max(actionW, w)
					end
					if c.FullBody or (t.MaskName == "Full" and moveF < 0.5) then
						fullBodyW = math.max(fullBodyW, w * (if t.Priority >= 3 then 1 else 0.7))
					end
					local aim = c.Aim
					if aim == "Right" or aim == "Both" then
						aimR = math.max(aimR, w)
					end
					if aim == "Left" or aim == "Both" then
						aimL = math.max(aimL, w)
					end
					if aim then
						aimT = math.max(aimT, w)
					end
				end
			end
		end
	end

	runTracksUpTo(1)
	applyLayer("Block", L.Block, 2)
	runTracksUpTo(2)
	applyLayer("Blue", L.Blue, 3)
	applyLayer("Downed", L.Downed, 3)
	applyLayer("Stunned", L.Stunned, 3)
	runTracksUpTo(4)
	-- drop finished tracks
	for i = #tracks, 1, -1 do
		if tracks[i].Done then
			table.remove(tracks, i)
		end
	end
	if st.DeathTrack and (st.DeathTrack :: Track).Done then
		st.DeathTrack = nil
	end
	local deathW = if dead then 1 else 0
	fullBodyW = math.max(fullBodyW, deathW)

	-- 5 procedural additive layers --------------------------------------------------------------
	local free = 1 - fullBodyW
	local function add(j: number, c: number, v: number)
		local i = ch(j, c)
		P[i] += v
	end
	if not st.IsDummy then
		-- hip yaw (feet toward the move direction, torso keeps facing)
		local hy = st.HipYaw * free
		add(J_ROOT, 2, hy)
		add(J_WAIST, 2, -hy * 0.8)
		add(J_NECK, 2, -hy * 0.2)
		-- lean into acceleration and turns
		local ground = (1 - st.AirW) * free
		local accF, accR = st.AccLocal.Z, st.AccLocal.X
		local leanPitch = -math.clamp(accF * 0.32, -7, 9) * ground
		local turnRoll = math.clamp(st.YawRate * math.min(speed, 24) * 0.9, -12, 12)
		local leanRoll = math.clamp(turnRoll - accR * 0.25, -12, 12) * ground
		add(J_ROOT, 1, leanPitch * 0.4)
		add(J_WAIST, 1, leanPitch * 0.6)
		add(J_ROOT, 3, leanRoll * 0.35)
		add(J_WAIST, 3, leanRoll * 0.65)
		add(J_NECK, 1, -leanPitch * 0.4)
		add(J_NECK, 3, -leanRoll * 0.45)
		-- breathing: deeper and faster after running, shallow while acting
		local period = MathUtil.lerp(3.6, 1.3, st.Exertion)
		st.BreathT += dt * (2 * math.pi / period)
		local b = math.sin(st.BreathT)
		local amp = (0.7 + 2.2 * st.Exertion) * (1 - actionW * 0.7) * (1 - L.Downed.Weight * 0.5)
		add(J_WAIST, 1, b * amp * 0.9)
		add(J_NECK, 1, -b * amp * 0.5)
		add(J_LSH, 3, -b * amp * 0.35)
		add(J_RSH, 3, b * amp * 0.35)
		add(J_ROOT, 5, b * amp * 0.004)
		-- blue soul: struggling tremble
		if L.Blue.Weight > 0.01 then
			local tt = now * 13 + st.Seed
			local k = L.Blue.Weight
			add(J_WAIST, 3, math.noise(tt, 1.3) * 3 * k)
			add(J_WAIST, 1, math.noise(tt, 4.7) * 2 * k)
			add(J_NECK, 3, math.noise(tt, 8.1) * 3 * k)
			add(J_LSH, 3, math.noise(tt, 2.2) * 4 * k)
			add(J_RSH, 3, math.noise(tt, 6.6) * 4 * k)
		end
		-- look-at / aim
		local point = st.AimExplicit
		if point == nil and st.IsLocal then
			point = localAimPoint()
		end
		if point == nil and st.AimRelay and now - st.AimRelayAt < TUNING.AimStale then
			point = st.AimRelay
		end
		if point == nil and speed < 4 and actionW < 0.1 then
			point = socialTarget(st, now)
		end
		local targetYaw, targetPitch = 0, 0
		if point then
			local cf = st.Root.CFrame
			local head = cf.Position + cf.UpVector * (st.NeckHeight * st.Scale)
			local yaw, pitch = AnimMath.AimAngles(cf, head, point :: Vector3)
			if math.abs(yaw) <= TUNING.LookBehind then
				targetYaw = math.clamp(yaw, -TUNING.LookYaw, TUNING.LookYaw)
				targetPitch = math.clamp(pitch, -TUNING.LookPitch, TUNING.LookPitch)
			end
		end
		local lookW = (1 - math.max(L.Downed.Weight, L.Stunned.Weight, deathW))
		st.LookYaw = MathUtil.damp(st.LookYaw, targetYaw * lookW, 9, dt)
		st.LookPitch = MathUtil.damp(st.LookPitch, targetPitch * lookW, 9, dt)
		local yaw, pitch = st.LookYaw, st.LookPitch
		local aimArm = math.max(aimR, aimL)
		local torsoShare = 0.28 + 0.42 * math.max(aimArm, aimT)
		add(J_WAIST, 2, yaw * torsoShare)
		add(J_NECK, 2, yaw * (1 - torsoShare))
		add(J_WAIST, 1, pitch * torsoShare * 0.55)
		add(J_NECK, 1, pitch * (1 - torsoShare * 0.55))
		-- arms of aiming clips follow the rest of the aim (an extended arm: +rx raises, -rz turns left)
		local restPitch = pitch * (1 - torsoShare * 0.55)
		local restYaw = yaw * (1 - torsoShare)
		if aimR > 0.001 then
			add(J_RSH, 1, restPitch * aimR)
			add(J_RSH, 3, -restYaw * aimR)
		end
		if aimL > 0.001 then
			add(J_LSH, 1, restPitch * aimL)
			add(J_LSH, 3, -restYaw * aimL)
		end
	end
end

local function smooth(st: CharState, dt: number, boostLevel: number)
	local P, O, V = st.Pose, st.Out, st.Vel
	local boost = BOOST[boostLevel]
	for j = 1, NJ do
		local group = GROUP_OF[j]
		local cfg = SPRING[group]
		local speed, damping = cfg[1], cfg[2]
		if UPPER_GROUPS[group] then
			speed *= boost
		end
		if st.IsDummy and j == J_ROOT then
			speed, damping = DUMMY_ROOT_SPRING[1], DUMMY_ROOT_SPRING[2]
		end
		local a, b, c, d = coeffs(speed, damping, dt)
		local o = (j - 1) * 6
		for k = 1, 3 do
			local i = o + k
			local target = P[i]
			local x = O[i] - target
			if x > 180 or x < -180 then
				x = AnimMath.Wrap180(x)
			end
			local v = V[i]
			O[i] = target + x * a + v * b
			V[i] = x * c + v * d
		end
		if j == J_ROOT then
			local ta, tb, tc, td = coeffs(TRANSLATION_SPRING[1], TRANSLATION_SPRING[2], dt)
			for k = 4, 6 do
				local i = o + k
				local target = P[i]
				local x = O[i] - target
				local v = V[i]
				O[i] = target + x * ta + v * tb
				V[i] = x * tc + v * td
			end
		else
			for k = 4, 6 do
				local i = o + k
				O[i] = P[i]
			end
		end
	end
end

local function writeMotors(st: CharState, buf: Buffer)
	local scale = st.Scale
	for j = 1, NJ do
		local m = st.Motors[j]
		if m then
			(m :: any).Transform = AnimMath.ChannelCFrame(buf, j, scale)
		end
	end
end

local function writeViewport(st: CharState)
	local pose = AnimMath.BufferToPose(st.Out)
	pcall(RigBuilder.ApplyPose, st.Model, pose)
end

local function updateCharacter(st: CharState, dt: number, now: number, serverNow: number, camPos: Vector3, camLook: Vector3)
	local root = st.Root
	if root.Parent == nil then
		return
	end
	-- level of detail
	local springs = true
	if st.Viewport then
		st.ViewportAccum += dt
		if st.ViewportAccum < 1 / TUNING.ViewportRate then
			return
		end
		dt = st.ViewportAccum
		st.ViewportAccum = 0
	else
		local offset = root.Position - camPos
		local dist = offset.Magnitude
		local rate = 0
		if dist > TUNING.FarDistance then
			rate = 5
		elseif dist > TUNING.LodDistance then
			rate = TUNING.LodRate
		elseif dist > 30 and offset:Dot(camLook) < 0 then
			rate = TUNING.OffscreenRate
		end
		if dist > TUNING.LodDistance then
			springs = false
		end
		if rate > 0 then
			st.Accum += dt
			if st.Accum < 1 / rate then
				return
			end
			dt = st.Accum
			st.Accum = 0
		else
			st.Accum = 0
		end
	end
	dt = math.min(dt, 0.25)
	if st.MotorsDirty then
		refreshMotors(st)
	end
	-- hit-stop: frozen pose (optionally shaking), clocks paused
	if now < st.HitStopUntil then
		if st.HitShake > 0 and springs and st.Initialized then
			AnimMath.CopyBuffer(st.Tmp, st.Out)
			local s = st.HitShake
			st.Tmp[ch(J_ROOT, 4)] += (rng:NextNumber() - 0.5) * 0.12 * s
			st.Tmp[ch(J_WAIST, 3)] += (rng:NextNumber() - 0.5) * 3 * s
			writeMotors(st, st.Tmp)
		end
		return
	end
	sense(st, dt, now)
	buildPose(st, dt, now, serverNow)
	-- idle fidgets
	if not st.IsDummy and not st.Viewport then
		if st.Speed > 1 or not st.Grounded or #st.Tracks > 0 or st.AirW > 0.01 then
			st.NextFidget = math.max(st.NextFidget, now + TUNING.FidgetMin * 0.5)
		elseif now >= st.NextFidget and now - st.LastActive > 6 then
			local list = FIDGETS[st.Family]
			if list and st.Layers.Block.Weight < 0.01 and st.Attr.Dead ~= true then
				local name = list[rng:NextInteger(1, #list)]
				startTrack(st, name, nil)
			end
			st.NextFidget = now + TUNING.FidgetMin + rng:NextNumber() * (TUNING.FidgetMax - TUNING.FidgetMin)
		end
	end
	if springs and st.Initialized then
		local actionW = 0
		for _, t in st.Tracks do
			if t.Kind == "Action" then
				actionW = math.max(actionW, t.Env)
			end
		end
		smooth(st, dt, if actionW > 0.6 then 3 elseif actionW > 0.2 then 2 else 1)
	else
		AnimMath.CopyBuffer(st.Out, st.Pose)
		AnimMath.ZeroBuffer(st.Vel)
		st.Initialized = true
	end
	if st.Viewport then
		writeViewport(st)
	else
		writeMotors(st, st.Out)
	end
end

local function sendLocalAim(now: number)
	if now - lastAimSend < 1 / TUNING.AimSendRate then
		return
	end
	local player = Players.LocalPlayer
	local char = player and player.Character
	if char == nil or states[char] == nil then
		return
	end
	local point = localAimPoint()
	if point == nil then
		return
	end
	if lastAimSent and ((point - (lastAimSent :: Vector3)).Magnitude < 0.5 and now - lastAimSend < 1) then
		return
	end
	lastAimSend = now
	lastAimSent = point
	pcall(Net.Client.Fire, "Aim", point)
end

local function onStep(dt: number)
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local cam = workspace.CurrentCamera
	local camCF = if cam then cam.CFrame else CFrame.new()
	local camPos, camLook = camCF.Position, camCF.LookVector
	for _, st in states do
		local ok, err = pcall(updateCharacter, st, dt, now, serverNow, camPos, camLook)
		if not ok then
			warn("[AnimController] update failed for " .. st.Model:GetFullName() .. ": " .. tostring(err))
			untrack(st.Model)
		end
	end
	sendLocalAim(now)
end

---------------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------------

function AnimController.Play(character: Model, clip: string, opts: PlayOptions?): TrackHandle?
	local st = states[character]
	if st == nil then
		st = trackModel(character)
		if st == nil then
			return nil
		end
	end
	local s = st :: CharState
	if s.DeathTrack and clip ~= "Death" then
		return nil
	end
	local t = startTrack(s, clip, opts)
	if t == nil then
		return nil
	end
	return handleFor(t)
end

function AnimController.Stop(character: Model, clip: string, fade: number?)
	local st = states[character]
	if st == nil then
		return
	end
	for _, t in st.Tracks do
		if t.Name == clip then
			stopTrack(t, fade)
		end
	end
end

function AnimController.StopAll(character: Model, fade: number?)
	local st = states[character]
	if st == nil then
		return
	end
	for _, t in st.Tracks do
		if t ~= st.DeathTrack then
			stopTrack(t, fade)
		end
	end
end

function AnimController.IsPlaying(character: Model, clip: string): boolean
	local st = states[character]
	if st then
		for _, t in st.Tracks do
			if t.Name == clip and not t.Done and not t.Stopping then
				return true
			end
		end
	end
	return false
end

function AnimController.HasClip(character: Model, clip: string): boolean
	return AnimController.GetClip(character, clip) ~= nil
end

function AnimController.GetClip(character: Model, clip: string): Clip?
	local st = states[character]
	if st then
		return rawClip(st, clip)
	end
	local family = character:GetAttribute("RigFamily")
	local lib = if type(family) == "string" then familyLib(family) else nil
	local kitId = character:GetAttribute("KitId")
	local kl = if type(kitId) == "string" and kitId ~= "" then kitLib(kitId) else nil
	if kl and kl[clip] then
		return kl[clip]
	end
	return if lib then lib[clip] else nil
end

function AnimController.SetAim(character: Model, point: Vector3?)
	local st = states[character]
	if st then
		st.AimExplicit = point
	end
end

function AnimController.HitStop(character: Model, duration: number, shake: number?)
	local st = states[character]
	if st == nil or type(duration) ~= "number" or duration <= 0 then
		return
	end
	local untilT = os.clock() + math.min(duration, 0.5)
	if untilT > st.HitStopUntil then
		st.HitStopUntil = untilT
	end
	st.HitShake = shake or 0
end

function AnimController.MarkPredicted(character: Model, castId: number)
	local st = states[character]
	if st == nil or type(castId) ~= "number" then
		return
	end
	local now = os.clock()
	for id, expires in st.Predicted do
		if expires < now then
			st.Predicted[id] = nil
		end
	end
	st.Predicted[castId] = now + 4
end

-- Which clip (and speed) an ability plays on this character. Kit clip files may key clips by ability id.
function AnimController.ResolveAbilityClip(character: Model, kitId: string?, abilityId: string, data: { [string]: any }?): (string?, number?)
	local st = states[character]
	if st == nil then
		return nil, nil
	end
	local d = data or {}
	if abilityId == "Emote" then
		local clip = d.clip or d.emote
		return if type(clip) == "string" and rawClip(st, clip) then clip else nil, nil
	end
	if rawClip(st, abilityId) and st.KitLib and st.KitLib[abilityId] then
		return abilityId, nil
	end
	if abilityId == "Dash" then
		return "Dash", nil
	elseif abilityId == "VerdictBox" then
		return if rawClip(st, "Verdict") then "Verdict" else "Point", nil
	end
	local kit = kitId or st.KitId
	local def = if kit ~= "" then Kits.Ability(kit, abilityId) else nil
	if def == nil or def.Clip == nil then
		return nil, nil
	end
	local clipName = def.Clip :: string
	if type(def.Combo) == "number" and def.Combo > 1 then
		local combo = d.combo
		if type(combo) == "number" then
			clipName = AnimMath.ComboClipName(clipName, combo, def.Combo, function(n: string): boolean
				return rawClip(st, n) ~= nil
			end)
		end
	end
	local raw = rawClip(st, clipName)
	if raw == nil then
		return nil, nil
	end
	return clipName, AnimMath.WindupSpeed(raw, def.Windup)
end

function AnimController.PlayAbility(character: Model, kitId: string?, abilityId: string, data: { [string]: any }?, dir: Vector3?): TrackHandle?
	local st = states[character]
	if st == nil then
		return nil
	end
	local clipName, speed = AnimController.ResolveAbilityClip(character, kitId, abilityId, data)
	if clipName == nil then
		return nil
	end
	local opts: PlayOptions = { Speed = speed }
	-- dashes that are not forward read better as a side-step
	if clipName == "Dash" and dir and dir.Magnitude > 0.1 then
		local look = st.Root.CFrame.LookVector
		local flatDir = Vector3.new(dir.X, 0, dir.Z)
		if flatDir.Magnitude > 0.1 and Vector3.new(look.X, 0, look.Z).Unit:Dot(flatDir.Unit) < 0.35 and rawClip(st, "Dodge") then
			clipName = "Dodge"
			opts.Mirror = flatDir:Dot(st.Root.CFrame.RightVector) > 0
		end
	end
	return AnimController.Play(character, clipName :: string, opts)
end

function AnimController.Track(model: Model, opts: { Viewport: boolean? }?): boolean
	local o = opts or {}
	return trackModel(model, o.Viewport) ~= nil
end

function AnimController.Untrack(model: Model)
	untrack(model)
end

function AnimController.IsTracked(model: Model): boolean
	return states[model] ~= nil
end

---------------------------------------------------------------------------------------------------
-- Network reactions
---------------------------------------------------------------------------------------------------

local function sourceLocal(st: CharState, attacker: Model?, pos: Vector3?): Vector3?
	local src: Vector3? = nil
	if attacker then
		local root = attacker:FindFirstChild("HumanoidRootPart") or attacker.PrimaryPart
		if root and root:IsA("BasePart") then
			src = root.Position
		end
	end
	if src == nil and pos then
		local d = (st.Root.Position - pos)
		if d.Magnitude > 0.3 then
			src = pos
		end
	end
	if src == nil then
		return nil
	end
	return st.Root.CFrame:PointToObjectSpace(src :: Vector3)
end

local function onDamageFx(packet: any)
	if type(packet) ~= "table" then
		return
	end
	local target = packet.target
	if typeof(target) ~= "Instance" or not (target :: Instance):IsA("Model") then
		return
	end
	local st = states[target :: Model]
	if st == nil or packet.kind == "Heal" then
		return
	end
	local attacker = if typeof(packet.attacker) == "Instance" and (packet.attacker :: Instance):IsA("Model") then packet.attacker :: Model else nil
	local pos = if typeof(packet.pos) == "Vector3" then packet.pos :: Vector3 else nil
	local src = sourceLocal(st, attacker, pos)
	local fromLeft = src ~= nil and (src :: Vector3).X < -0.3
	local fromFront = src == nil or (src :: Vector3).Z < 0
	if packet.dodged then
		if st.Family == "Skeleton" and not st.IsDummy then
			local mirror = fromLeft or (src ~= nil and math.abs((src :: Vector3).X) <= 0.3 and rng:NextNumber() < 0.5)
			AnimController.Play(st.Model, "Dodge", { Mirror = mirror })
		end
		return
	end
	if packet.parried then
		AnimController.Play(st.Model, "Parry")
		return
	end
	local springsOn = st.Initialized
	if packet.blocked then
		if springsOn then
			st.Vel[ch(J_WAIST, 1)] += if fromFront then 120 else -120
			st.Vel[ch(J_RSH, 1)] -= 90
		end
		return
	end
	local amount = if type(packet.amount) == "number" then packet.amount else 0
	if amount <= 0 then
		return
	end
	local maxHp = math.max(1, st.Humanoid.MaxHealth)
	local severity = math.clamp(amount / maxHp * 7, 0.3, 1)
	if packet.killed or packet.downed or packet.guardBreak then
		severity = 1
	end
	local now = os.clock()
	st.LastActive = now
	if not st.IsDummy and st.Attr.Dead ~= true then
		AnimController.Play(st.Model, "Hit", {
			Mirror = fromLeft,
			Weight = if fromFront then 0.5 + 0.5 * severity else 0.35,
		})
	end
	if springsOn then
		-- flinch away from the source: front hit bends the torso back, side hit tilts it away
		local side = if src then math.clamp(-(src :: Vector3).X, -1, 1) else 0
		local back = if fromFront then 1 else -1
		local k = severity * (if st.IsDummy then 1.6 else 1)
		st.Vel[ch(J_WAIST, 1)] += 260 * k * back
		st.Vel[ch(J_NECK, 1)] += 200 * k * back
		st.Vel[ch(J_WAIST, 3)] += 140 * k * side
		st.Vel[ch(J_ROOT, 1)] += (if st.IsDummy then 260 else 60) * k * back
		st.Vel[ch(J_ROOT, 3)] += (if st.IsDummy then 160 else 0) * k * side
	end
	if packet.kind == "Melee" then
		local combat = (Config :: any).Combat or {}
		local stop = if severity >= 0.8 then combat.HitStopHeavy or 0.12 else combat.HitStopMelee or 0.06
		AnimController.HitStop(st.Model, stop, 1)
		if attacker and states[attacker] then
			AnimController.HitStop(attacker, stop * 0.9, 0)
		end
	end
end

local function onAbilityFx(packet: any)
	if type(packet) ~= "table" or packet.phase ~= "Start" then
		return
	end
	local caster = packet.caster
	if typeof(caster) ~= "Instance" or not (caster :: Instance):IsA("Model") then
		return
	end
	local st = states[caster :: Model]
	if st == nil then
		return
	end
	local castId = packet.castId
	if type(castId) == "number" and castId ~= 0 and st.Predicted[castId] then
		st.Predicted[castId] = nil
		return
	end
	local ability = packet.ability
	if type(ability) ~= "string" then
		return
	end
	local data = if type(packet.data) == "table" then packet.data else nil
	local dir = if typeof(packet.dir) == "Vector3" then packet.dir :: Vector3 else nil
	AnimController.PlayAbility(caster :: Model, if type(packet.kit) == "string" then packet.kit else nil, ability, data, dir)
end

local function onAim(character: any, point: any)
	if typeof(character) ~= "Instance" or typeof(point) ~= "Vector3" then
		return
	end
	local st = states[character :: Model]
	if st and not st.IsLocal then
		st.AimRelay = point
		st.AimRelayAt = os.clock()
	end
end

local function onRoundEvent(name: any, data: any)
	if name == "RoundEnd" and type(data) == "table" then
		local winner = data.winner
		local team = if winner == "Monster" then "Monster" elseif winner == "Humans" then "Humans" else nil
		if team == nil then
			return
		end
		for model, st in states do
			if st.Attr.Team == team and st.Attr.Dead ~= true and st.Attr.Downed ~= true and not st.Viewport then
				AnimController.Play(model, "Victory", { Loop = true })
			end
		end
	elseif name == "PhaseChanged" then
		for model, st in states do
			if AnimController.IsPlaying(model, "Victory") then
				AnimController.Stop(model, "Victory", 0.3)
			end
			local _ = st
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------------

function AnimController.Init()
	-- warm the family libraries (validates them once at startup)
	for _, family in Joints.FAMILIES do
		familyLib(family)
	end
end

function AnimController.Start()
	if started then
		return
	end
	started = true
	for _, inst in workspace:GetDescendants() do
		if inst:IsA("Humanoid") then
			consider(inst.Parent)
		end
	end
	workspace.DescendantAdded:Connect(function(inst: Instance)
		if inst:IsA("Humanoid") then
			consider(inst.Parent)
		end
	end)
	local player = Players.LocalPlayer
	if player then
		player.CharacterAdded:Connect(function(char: Model)
			local st = states[char]
			if st then
				st.IsLocal = true
			else
				consider(char)
			end
		end)
	end
	RunService.PreSimulation:Connect(onStep)
	local function listen(name: string, fn: (...any) -> ())
		task.spawn(function()
			local ok, err = pcall(Net.Client.On, name, fn)
			if not ok then
				warn("[AnimController] cannot listen to " .. name .. ": " .. tostring(err))
			end
		end)
	end
	listen("DamageFx", onDamageFx)
	listen("AbilityFx", onAbilityFx)
	listen("Aim", onAim)
	listen("RoundEvent", onRoundEvent)
end

return AnimController
