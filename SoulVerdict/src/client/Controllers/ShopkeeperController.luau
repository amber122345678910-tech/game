--!strict
-- ShopkeeperController (client, Priority 62): brings "sleepy Sans" at the lobby ShopBooth to life
-- (Shared/Maps/Shopkeeper builds him into the lobby, frozen and anchored). Every client animates its own copy
-- locally; nothing is replicated and the server keeps no state.
--   * Asleep: slow breathing, "Z z z" letters rising and fading above his skull (BillboardGui, pixel font).
--   * The LOCAL player comes within Tuning.WAKE_RADIUS (16 studs: a little beyond the reach of the booth's Shop
--     prompt) IN FRONT of him (not behind the booth's back shelf): he wakes up (eyes open, the skull lifts off
--     his arms and turns towards the player, eased with a small overshoot) and a speech bubble (BillboardGui,
--     black box with a white pixel border and the pixel menu font, like the Classic theme) types
--     shop.keeper.greet with Sans's text blips (SoundController "SansTextBlip"; only while the bubble is on
--     screen: a 2D blip with nothing to see would come out of nowhere).
--   * Awake: his head follows the player (yaw/pitch clamped; a player behind him -> he looks ahead) and he
--     blinks now and then.
--   * The player stays beyond Tuning.LEAVE_RADIUS (22 studs) for Tuning.LEAVE_TIME (2 s): he says
--     shop.keeper.bye (only if the bubble is on screen; otherwise he dozes off without a word), then dozes off
--     again (the skull sinks back onto his arms, eyes shut, Zzz again). Coming back while he says bye keeps him
--     awake (no second greeting); coming back while he dozes off wakes him up with the greeting again.
--   * Cheap: one Heartbeat callback that returns at once while both the camera and the player are farther than
--     Tuning.ACTIVE_RADIUS (the guis are disabled, no part moves). Nothing moves either while he is off screen
--     (InView: outside the camera's view, e.g. behind the title-screen camera or the walking player) or behind
--     the opaque Shop screen; his current pose is applied the moment he shows again. Breathing updates at
--     ~15 Hz, ~30 Hz awake once the skull has settled on the player, waking / dozing / turning every frame.
--     Poses come from Maps/Shopkeeper.Solve (pure forward kinematics, no Motor6Ds) and only the upper body
--     (~130 anchored parts, no shadows) is moved, with one workspace:BulkMoveTo call.
--   * Reduced Motion (GraphicsController): shallower breathing, no overshoot, calmer Zzz.
--   * The speech bubble goes away while the Shop screen is open (the screen has its own pixel shopkeeper) and
--     does not come back when it closes.
--
-- API
--   ShopkeeperController.Priority = 62
--   ShopkeeperController.State() -> string?       state of the local shopkeeper ("Asleep", "Waking", "Awake",
--                                                 "Bye", "Dozing"), nil while there is none
--   ShopkeeperController.Attach(model) -> boolean / Detach() / Step(dt)   attach to a shopkeeper model (Start finds
--                                                 the lobby's by itself), let go (parts back to the sleep pose),
--                                                 advance one frame (Start drives it from RunService.Heartbeat)
--   ShopkeeperController.Tuning                   radii (studs) and times (s), see below
--   ShopkeeperController.Machine                  the pure state machine (no engine access; tests):
--     Machine.new() -> Machine                    { State = "Asleep", Time = 0, Far = 0, From = 0 }
--     Machine.Step(m, dt, distance?) -> {string}  advances it; distance = local player -> shopkeeper (nil = no
--                                                 character = far). Events: "Wake" (Asleep/Dozing -> Waking),
--                                                 "Awake" (Waking -> Awake), "Bye" (Awake -> Bye), "Return"
--                                                 (Bye -> Awake), "Doze" (Bye -> Dozing), "Asleep" (Dozing -> Asleep)
--     Machine.Alpha(m, reduced?) -> number        0 = sleep pose .. 1 = awake pose (Waking overshoots a little
--                                                 above 1 unless reduced); continuous across interruptions
--   ShopkeeperController.LookAngles(neck: CFrame, target: Vector3) -> (yaw, pitch)   radians in the neck frame
--       (+yaw = his left, +pitch = up), clamped to Tuning.MAX_YAW / MAX_PITCH_UP / MAX_PITCH_DOWN; (0, 0) for a
--       target behind him (farther round than Tuning.LOOK_BEHIND)
--   ShopkeeperController.InView(cameraCF, fov, aspect, centre: Vector3, radius) -> boolean   a sphere at least
--       partly inside a camera's view (fov = Camera.FieldOfView, vertical degrees; aspect = width / height)
--   ShopkeeperController.Search(lobby, fresh?)   look for the shopkeeper in a lobby map and attach (Start does it;
--       retried for late replication). A lobby searched to the end in vain, or carrying ShopkeeperError (the
--       server could not build him), is skipped from then on unless `fresh` (a new LobbyController.Ready)
--   ShopkeeperController._Harness(deps)           tests: stand-ins for Init's controllers { Sound, UI, Graphics }
--   ShopkeeperController.Typing(text, elapsed, interval?, pause?) -> number   graphemes shown after `elapsed`
--       seconds of typing (punctuation pauses longer)
--   ShopkeeperController.PoseRig(model) -> PoseRig?   reads the frozen NPC (joint attributes, root) for Pose
--   ShopkeeperController.Pose(poseRig, alpha, breath?, yaw?, pitch?, into?) -> { [limbName]: CFrame }   every limb
--       for a sleep (0) .. awake (1) blend + breathing (rad on the Waist) + look-at; alpha 0 = the built model
--       exactly; `into` = a table to fill instead of a new one
--   ShopkeeperController.BuildBubble(anchor: Attachment, text?) -> BillboardGui   the speech bubble (text shown in
--       full when given); ShopkeeperController.BuildZzz(anchor, clock?) -> BillboardGui   the Zzz at a moment
--       (offline tests / previews; the runtime builds the same guis)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Shopkeeper = require(Shared:WaitForChild("Maps"):WaitForChild("Shopkeeper")) :: any

local ShopkeeperController = {}
ShopkeeperController.Priority = 62

local Tuning = {
	-- the local player this close wakes him: the booth's Shop prompt shows 11 studs from its marker, which is ~4 studs
	-- in front of him (~15 studs at most), so he is up before the player can open the Shop from it
	WAKE_RADIUS = 16,
	LEAVE_RADIUS = 22, -- ... and this far away, for LEAVE_TIME seconds, makes him say bye
	LEAVE_TIME = 2,
	FRONT_MARGIN = 0.5, -- studs in front of him a player must be to count at all (not behind the booth's shelf)
	WAKE_TIME = 0.85, -- skull lift (s)
	BYE_TIME = 2.6, -- bye line on screen before he dozes off
	DOZE_TIME = 1.9, -- skull sinking back onto his arms
	ACTIVE_RADIUS = 80, -- camera or player closer than this: animate; otherwise idle (nothing moves)
	MAX_YAW = math.rad(65),
	MAX_PITCH_UP = math.rad(28),
	MAX_PITCH_DOWN = math.rad(22),
	-- a target farther round than this is behind him: he looks ahead (clamping would swing the skull from one
	-- shoulder limit to the other as the player crosses behind his back)
	LOOK_BEHIND = math.rad(90),
	LOOK_RATE = 7, -- 1/s, smoothing of the head following the player
	LOOK_SETTLED = math.rad(1), -- the skull this close to its target counts as settled (AWAKE_HZ)
	SLEEP_BREATH = { Period = 4.6, Amp = math.rad(1.7) },
	AWAKE_BREATH = { Period = 3.4, Amp = math.rad(0.7) },
	SLEEP_HZ = 15, -- pose updates per second while only breathing
	AWAKE_HZ = 30, -- ... while awake with the skull settled on the player (only breathing moves)
	VIEW_MARGIN = 1, -- studs added around the upper body / Zzz for the on-screen test (awake lift, look-at)
	ZZZ_REACH = 3.2, -- studs the Zzz letters reach from their anchor
	BUBBLE_VIEW_RADIUS = 1.5, -- studs around the bubble's anchor for "the bubble is on screen"
	SEARCH_TRIES = 20, -- looking for him in a new lobby: tries, one every SEARCH_INTERVAL seconds
	SEARCH_INTERVAL = 1,
	GREET_HOLD = 6, -- the greeting stays up this long after it is typed
	TYPE_INTERVAL = 0.045,
	TYPE_PAUSE = 0.22, -- after . , ? ! and the like
	BLIP_EVERY = 2, -- one blip every N letters
	ZZZ_CYCLE = 2.7, -- seconds for one "Z" to rise and fade
	BUBBLE_WIDTH = 252, -- px
	BUBBLE_MAX_DISTANCE = 70,
	ZZZ_MAX_DISTANCE = 90,
}
ShopkeeperController.Tuning = Tuning

------------------------------------------------------------------------------------------------ pure state machine

export type Machine = { State: string, Time: number, Far: number, From: number }

local Machine = {}
ShopkeeperController.Machine = Machine

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smoothstep(t: number): number
	t = clamp01(t)
	return t * t * (3 - 2 * t)
end

local function easeOutBack(t: number): number
	t = clamp01(t)
	local c1 = 1.4
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function Machine.new(): Machine
	return { State = "Asleep", Time = 0, Far = 0, From = 0 }
end

function Machine.Alpha(m: Machine, reduced: boolean?): number
	local state = m.State
	if state == "Asleep" then
		return 0
	elseif state == "Waking" then
		local t = m.Time / Tuning.WAKE_TIME
		local e = if reduced then smoothstep(t) else easeOutBack(t)
		return m.From + (1 - m.From) * e
	elseif state == "Dozing" then
		return m.From * (1 - smoothstep(m.Time / Tuning.DOZE_TIME))
	end
	return 1 -- Awake, Bye
end

local function enter(m: Machine, state: string)
	m.From = clamp01(Machine.Alpha(m, true))
	m.State = state
	m.Time = 0
	m.Far = 0
end

function Machine.Step(m: Machine, dt: number, distance: number?): { string }
	local events: { string } = {}
	local d = if type(distance) == "number" and distance == distance then distance else math.huge
	m.Time += math.max(dt, 0)
	local state = m.State
	if state == "Asleep" then
		if d <= Tuning.WAKE_RADIUS then
			enter(m, "Waking")
			table.insert(events, "Wake")
		end
	elseif state == "Waking" or state == "Awake" then
		m.Far = if d > Tuning.LEAVE_RADIUS then m.Far + math.max(dt, 0) else 0
		if state == "Waking" then
			if m.Time >= Tuning.WAKE_TIME then
				local far = m.Far -- a player who ran straight past still gets a timely bye
				enter(m, "Awake")
				m.Far = far
				table.insert(events, "Awake")
			end
		elseif m.Far >= Tuning.LEAVE_TIME then
			enter(m, "Bye")
			table.insert(events, "Bye")
		end
	elseif state == "Bye" then
		if d <= Tuning.WAKE_RADIUS then
			enter(m, "Awake")
			table.insert(events, "Return")
		elseif m.Time >= Tuning.BYE_TIME then
			enter(m, "Dozing")
			table.insert(events, "Doze")
		end
	elseif state == "Dozing" then
		if d <= Tuning.WAKE_RADIUS then
			enter(m, "Waking")
			table.insert(events, "Wake")
		elseif m.Time >= Tuning.DOZE_TIME then
			enter(m, "Asleep")
			table.insert(events, "Asleep")
		end
	else
		enter(m, "Asleep")
	end
	return events
end

function ShopkeeperController.LookAngles(neck: CFrame, target: Vector3): (number, number)
	local rel = neck:Inverse() * target
	local flat = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
	if flat < 1e-4 and math.abs(rel.Y) < 1e-4 then
		return 0, 0
	end
	local yaw = if flat < 1e-4 then 0 else math.atan2(-rel.X, -rel.Z)
	if math.abs(yaw) > Tuning.LOOK_BEHIND then
		-- behind him: look ahead. Clamping would park the skull at one shoulder limit and swing it to the other
		-- (130 deg in a blink) as the target crosses behind his back, where atan2 jumps from +180 to -180.
		return 0, 0
	end
	local pitch = math.atan2(rel.Y, flat)
	return math.clamp(yaw, -Tuning.MAX_YAW, Tuning.MAX_YAW),
		math.clamp(pitch, -Tuning.MAX_PITCH_DOWN, Tuning.MAX_PITCH_UP)
end

-- True while a sphere (centre, radius: studs) is at least partly inside a camera's view: not behind it and not
-- beyond any of its four side planes. fov = Camera.FieldOfView (the vertical field of view, degrees), aspect =
-- viewport width / height.
function ShopkeeperController.InView(
	cameraCF: CFrame,
	fov: number,
	aspect: number,
	centre: Vector3,
	radius: number
): boolean
	local rel = cameraCF:PointToObjectSpace(centre)
	local depth = -rel.Z
	if depth < -radius then
		return false -- behind the camera
	end
	local tanV = math.tan(math.rad(math.clamp(fov, 1, 179)) / 2)
	local tanH = tanV * math.max(aspect, 0.05)
	-- how far the centre lies outside each pair of side planes (|x| = depth * tan at the edge), along their normals
	if (math.abs(rel.X) - depth * tanH) / math.sqrt(1 + tanH * tanH) > radius then
		return false
	end
	return (math.abs(rel.Y) - depth * tanV) / math.sqrt(1 + tanV * tanV) <= radius
end

local TYPE_BEAT = 0.12 -- a beat between the bubble popping up and the first letter
local PUNCTUATION: { [string]: boolean } =
	{ ["."] = true, [","] = true, ["?"] = true, ["!"] = true, [":"] = true, [";"] = true }

local function graphemes(text: string): { string }
	local out: { string } = {}
	for _, code in utf8.codes(text) do
		table.insert(out, utf8.char(code))
	end
	return out
end

-- Graphemes shown `elapsed` seconds into typing `chars` (the first one at 0; a punctuation mark holds longer).
local function typedCount(chars: { string }, elapsed: number, interval: number?, pause: number?): number
	local step = interval or Tuning.TYPE_INTERVAL
	local stop = pause or Tuning.TYPE_PAUSE
	local t = 0
	local shown = 0
	for _, char in chars do
		if t > elapsed then
			break
		end
		shown += 1
		t += if PUNCTUATION[char] then stop else step
	end
	return shown
end

function ShopkeeperController.Typing(text: string, elapsed: number, interval: number?, pause: number?): number
	return typedCount(graphemes(text), elapsed, interval, pause)
end

------------------------------------------------------------------------------------------------ pure pose maths

export type PoseRig = {
	RootCF: CFrame,
	Scale: number,
	Joints: { any },
	Neck: any,
	Sleep: { [string]: CFrame },
	Awake: { [string]: CFrame },
	HeadSleep: CFrame, -- world rotation of the skull asleep
	HeadAwake: CFrame, -- world rotation of the skull awake (facing the customers)
	LookFrame: CFrame, -- the awake skull (centre + rotation): look-at angles are measured from it
	UpperBody: { string }, -- the limbs that move: UpperTorso and everything hanging off it
	Transforms: { [string]: CFrame }, -- scratch table reused every frame
}

local IDENTITY = CFrame.new()

local function isUpperBody(name: string, parentOf: { [string]: string }): boolean
	local node: string? = name
	while node do
		if node == "UpperTorso" then
			return true
		end
		node = parentOf[node]
	end
	return false
end

-- Reads the frozen shopkeeper (joint attributes + root) into the data Pose() needs; nil while incomplete.
function ShopkeeperController.PoseRig(model: Model): PoseRig?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local joints = Shopkeeper.Joints(model)
	local neck: any = nil
	local parentOf: { [string]: string } = {}
	for _, joint in joints do
		parentOf[joint.Limb] = joint.Parent
		if joint.Name == "Neck" then
			neck = joint
		end
	end
	if #joints < 15 or neck == nil then
		return nil -- still replicating (or an old map without joint data)
	end
	local scaleAttr = model:GetAttribute("RigScale")
	local scale = if type(scaleAttr) == "number" and scaleAttr > 0 then scaleAttr else 1
	local rootCF = root.CFrame
	local sleep = Shopkeeper.Transforms(Shopkeeper.SleepPose, scale)
	local awake = Shopkeeper.Transforms(Shopkeeper.AwakePose, scale)
	local sleepLimbs = Shopkeeper.Solve(rootCF, joints, sleep)
	local awakeLimbs = Shopkeeper.Solve(rootCF, joints, awake)
	if sleepLimbs.Head == nil or awakeLimbs.Head == nil or sleepLimbs.UpperTorso == nil then
		return nil
	end
	local upper: { string } = {}
	for _, joint in joints do
		if isUpperBody(joint.Limb, parentOf) then
			table.insert(upper, joint.Limb)
		end
	end
	return {
		RootCF = rootCF,
		Scale = scale,
		Joints = joints,
		Neck = neck,
		Sleep = sleep,
		Awake = awake,
		HeadSleep = sleepLimbs.Head.Rotation,
		HeadAwake = awakeLimbs.Head.Rotation,
		LookFrame = awakeLimbs.Head,
		UpperBody = upper,
		Transforms = {},
	}
end

-- Every limb's CFrame for a blend between the sleep pose (alpha 0) and the awake pose (alpha 1; clamped), plus
-- breathing (radians on the Waist) and the look-at (yaw / pitch, radians, relative to the awake skull). The skull
-- blends its WORLD rotation (so asleep it stays put on the arms while the torso breathes) about the neck pivot.
function ShopkeeperController.Pose(
	pr: PoseRig,
	alpha: number,
	breath: number?,
	yaw: number?,
	pitch: number?,
	into: { [string]: CFrame }?
): { [string]: CFrame }
	local a = clamp01(alpha)
	local transforms = pr.Transforms
	for _, joint in pr.Joints do
		local name = joint.Name
		local from = pr.Sleep[name] or IDENTITY
		local to = pr.Awake[name] or IDENTITY
		transforms[name] = if a <= 0 then from elseif a >= 1 then to else from:Lerp(to, a)
	end
	if breath and breath ~= 0 then
		transforms.Waist = (transforms.Waist or IDENTITY) * CFrame.Angles(breath, 0, 0)
	end
	local limbs = Shopkeeper.Solve(pr.RootCF, pr.Joints, transforms, into)
	local torso = limbs.UpperTorso
	if torso then
		local look = pr.HeadAwake * CFrame.Angles(0, yaw or 0, 0) * CFrame.Angles(pitch or 0, 0, 0)
		local rotation = if a <= 0 then pr.HeadSleep else pr.HeadSleep:Lerp(look, a)
		limbs.Head = CFrame.new((torso * pr.Neck.C0).Position) * rotation * pr.Neck.C1Inv
	end
	return limbs
end

------------------------------------------------------------------------------------------------ runtime

type Bubble = {
	Gui: BillboardGui,
	Group: Frame,
	Scale: UIScale,
	Box: Frame,
	Stroke: UIStroke,
	Label: TextLabel,
	Tail: { Frame },
	Chars: { string },
	Shown: number,
	Clock: number, -- seconds since the line started typing
	Hold: number, -- seconds left on screen after typing (math.huge = until replaced)
	Alpha: number, -- current opacity 0..1
	Visible: boolean, -- wanted on screen
	Pop: number, -- 0..1 pop-in progress
}

type Limb = { Name: string, Parts: { BasePart }, Offsets: { CFrame } }

type Rig = {
	Model: Model,
	Root: BasePart,
	Pose: PoseRig,
	RootInv: CFrame, -- world -> his root space (customers at -Z)
	ViewCentre: Vector3, -- the sphere the camera must see for posing to matter (upper body in any pose + Zzz)
	ViewRadius: number,
	BubblePos: Vector3, -- the speech bubble's anchor (world)
	Limbs: { Limb },
	LimbCFrames: { [string]: CFrame }, -- scratch: solved limbs, reused every frame
	MoveParts: { BasePart },
	MoveCFrames: { CFrame },
	Pupils: { BasePart },
	Lids: { BasePart },
	Anchors: { Attachment },
	Zzz: BillboardGui,
	Letters: { TextLabel },
	LetterStrokes: { UIStroke },
	ZzzAlpha: number,
	Bubble: Bubble,
	Machine: Machine,
	Yaw: number,
	Pitch: number,
	EyesOpen: boolean,
	BlinkAt: number,
	BlinkUntil: number,
	Clock: number,
	Breath: number, -- breathing phase (radians)
	PoseAccum: number, -- seconds since the last pose update (SLEEP_HZ / AWAKE_HZ)
	PoseDirty: boolean, -- a pose update was skipped while he could not be seen: apply one as soon as he can
	Idle: boolean,
	Connections: { RBXScriptConnection },
}

local PIXEL_FONT = Font.new("rbxasset://fonts/families/PressStart2P.json")
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local ZZZ_STROKE = Color3.fromRGB(20, 24, 48)

local Lobby: any = nil
local Graphics: any = nil
local Sound: any = nil
local UI: any = nil

local rig: Rig? = nil
local random = Random.new()
local searching = false
local fruitless: Instance? = nil -- the last lobby searched to the end without a usable shopkeeper

local function controller(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			return result
		end
	end
	return nil
end

local function L(key: string): string
	local ok, text = pcall(Strings.L, key)
	return if ok and type(text) == "string" then text else key
end

local function reducedMotion(): boolean
	if Graphics and type(Graphics.ReducedMotion) == "function" then
		local ok, value = pcall(Graphics.ReducedMotion)
		return ok and value == true
	end
	return false
end

local function shopOpen(): boolean
	if UI and type(UI.IsOpen) == "function" then
		local ok, value = pcall(UI.IsOpen, "Shop")
		return ok and value == true
	end
	return false
end

local function playBlip()
	if Sound and type(Sound.Play) == "function" then
		pcall(Sound.Play, "SansTextBlip")
	end
end

local function localTarget(): (Vector3?, Vector3?)
	-- (body position for distances, head position for the look-at)
	local player = Players.LocalPlayer
	local character = player and player.Character
	if character == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	local head = character:FindFirstChild("Head")
	local headPos = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.6, 0)
	return root.Position, headPos
end

-- The camera's vertical field of view (degrees) and aspect; nil while it has no usable viewport yet.
local function viewOf(camera: Camera?): (number?, number?)
	if camera == nil then
		return nil, nil
	end
	local cam = camera :: any
	local fov, size = cam.FieldOfView, cam.ViewportSize
	if type(fov) ~= "number" or typeof(size) ~= "Vector2" or size.X < 2 or size.Y < 2 then
		return nil, nil
	end
	return fov, size.X / size.Y
end

-- InView for this frame's camera; without a usable camera / viewport everything counts as seen.
local function cameraSees(cameraCF: CFrame?, fov: number?, aspect: number?, centre: Vector3, radius: number): boolean
	if cameraCF == nil or fov == nil or aspect == nil then
		return true
	end
	return ShopkeeperController.InView(cameraCF, fov, aspect, centre, radius)
end

-- Guis -------------------------------------------------------------------------------------------------------

local function newAnchor(root: BasePart, name: string, offset: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = offset
	attachment.Parent = root
	return attachment
end

local function buildZzz(anchor: Attachment): (BillboardGui, { TextLabel }, { UIStroke })
	local gui = Instance.new("BillboardGui")
	gui.Name = "ShopkeeperZzz"
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(3.4, 3.4) -- studs: shrinks with distance like a world effect
	gui.SizeOffset = Vector2.new(0.3, 0.38) -- rise up and to the right of the skull, under the booth's awning
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true -- the booth's low awning would hide most of the rise from the plaza
	gui.MaxDistance = Tuning.ZZZ_MAX_DISTANCE
	gui.ClipsDescendants = false
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local letters: { TextLabel } = {}
	local strokes: { UIStroke } = {}
	for i = 1, 3 do
		local label = Instance.new("TextLabel")
		label.Name = "Z" .. i
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.fromScale(0.2, 0.2)
		label.Position = UDim2.fromScale(0.2, 0.85)
		label.FontFace = PIXEL_FONT
		label.Text = "Z"
		label.TextScaled = true
		label.TextColor3 = WHITE
		label.TextTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = ZZZ_STROKE
		stroke.Thickness = 2
		stroke.LineJoinMode = Enum.LineJoinMode.Miter
		stroke.Transparency = 1
		stroke.Parent = label
		label.Parent = gui
		letters[i] = label
		strokes[i] = stroke
	end
	gui.Parent = anchor
	return gui, letters, strokes
end

local TAIL_PIXEL = 3 -- = the border thickness, so the tail's steps match the box outline
-- the tail, top (the box's bottom border band) to tip: { core width, outline width } per 3 px row
local TAIL_ROWS = { { 22, 0 }, { 22, 28 }, { 16, 22 }, { 10, 16 }, { 4, 10 }, { 0, 4 } }

local function pixelRow(parent: Instance, name: string, width: number, y: number, color: Color3, z: number): Frame
	local row = Instance.new("Frame")
	row.Name = name
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 1, y)
	row.Size = UDim2.fromOffset(width, TAIL_PIXEL)
	row.BackgroundColor3 = color
	row.BorderSizePixel = 0
	row.ZIndex = z
	row.Parent = parent
	return row
end

local function buildBubble(anchor: Attachment): Bubble
	local tailHeight = #TAIL_ROWS * TAIL_PIXEL -- the box's border band + the stepped triangle under it
	local gui = Instance.new("BillboardGui")
	gui.Name = "ShopkeeperBubble"
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(Tuning.BUBBLE_WIDTH + 8, 150)
	gui.SizeOffset = Vector2.new(0, 0.5) -- the tail tip (bottom edge) sits on the anchor above his skull
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true -- the local player's conversation: never hidden behind the awning posts
	gui.MaxDistance = Tuning.BUBBLE_MAX_DISTANCE
	gui.ClipsDescendants = false
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local group = Instance.new("Frame")
	group.Name = "Group"
	group.AnchorPoint = Vector2.new(0.5, 1)
	group.Position = UDim2.fromScale(0.5, 1)
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = group

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -tailHeight)
	box.Size = UDim2.new(0, Tuning.BUBBLE_WIDTH, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = BLACK
	box.BorderSizePixel = 0
	box.ZIndex = 2
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 11)
	padding.PaddingBottom = UDim.new(0, 11)
	padding.Parent = box
	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.FontFace = PIXEL_FONT
	label.TextSize = 13
	label.LineHeight = 1.25
	label.TextColor3 = WHITE
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	label.MaxVisibleGraphemes = 0
	label.ZIndex = 3
	label.Parent = box
	box.Parent = group

	-- pixel tail pointing down at him: a stepped black triangle with a white outline; its first row opens the
	-- box's bottom border (the UIStroke is drawn outside the box, in the band right under it)
	local tail: { Frame } = {}
	for i, row in TAIL_ROWS do
		local y = -tailHeight + (i - 1) * TAIL_PIXEL
		if row[2] > 0 then
			table.insert(tail, pixelRow(group, "TailEdge" .. i, row[2], y, WHITE, 3))
		end
		if row[1] > 0 then
			table.insert(tail, pixelRow(group, "TailCore" .. i, row[1], y, BLACK, 4))
		end
	end
	group.Parent = gui
	gui.Parent = anchor
	return {
		Gui = gui,
		Group = group,
		Scale = scale,
		Box = box,
		Stroke = stroke,
		Label = label,
		Tail = tail,
		Chars = {},
		Shown = 0,
		Clock = 0,
		Hold = 0,
		Alpha = 0,
		Visible = false,
		Pop = 1,
	}
end

local function setBubbleAlpha(bubble: Bubble, alpha: number)
	bubble.Alpha = alpha
	local t = 1 - alpha
	bubble.Box.BackgroundTransparency = t
	bubble.Stroke.Transparency = t
	bubble.Label.TextTransparency = t
	for _, row in bubble.Tail do
		row.BackgroundTransparency = t
	end
end

-- Puts a line in the bubble with `shown` graphemes visible (0 = about to be typed; nil = all of it).
local function setLine(bubble: Bubble, text: string, shown: number?)
	bubble.Label.Text = text
	bubble.Chars = graphemes(text)
	bubble.Shown = math.clamp(shown or #bubble.Chars, 0, #bubble.Chars)
	bubble.Label.MaxVisibleGraphemes = if bubble.Shown >= #bubble.Chars then -1 else bubble.Shown
end

local function say(r: Rig, key: string, hold: number)
	local bubble = r.Bubble
	setLine(bubble, "* " .. L(key), 0)
	bubble.Clock = 0
	bubble.Hold = hold
	bubble.Visible = true
	bubble.Pop = 0
end

-- Takes the line down for good: the rest of it is shown silently while the bubble fades out, and it does not come
-- back later (no hold left).
local function hideBubble(bubble: Bubble)
	if bubble.Shown < #bubble.Chars then
		bubble.Shown = #bubble.Chars
		bubble.Label.MaxVisibleGraphemes = -1
	end
	bubble.Visible = false
	bubble.Hold = 0
end

-- shop: the Shop screen is open; audible: the bubble is on screen (its blips play only then)
local function stepBubble(r: Rig, dt: number, reduced: boolean, shop: boolean, audible: boolean)
	local bubble = r.Bubble
	if shop and bubble.Visible then
		-- the Shop screen's own pixel shopkeeper talks now: drop the line, whether it is still typing or already
		-- up, so that it does not fade back in when the Shop closes
		hideBubble(bubble)
	end
	-- typing
	if bubble.Visible and bubble.Shown < #bubble.Chars then
		bubble.Clock += dt
		local target = if bubble.Clock < TYPE_BEAT then 0 else typedCount(bubble.Chars, bubble.Clock - TYPE_BEAT)
		local blipped = false
		while bubble.Shown < target do
			bubble.Shown += 1
			local char = bubble.Chars[bubble.Shown]
			-- one blip every BLIP_EVERY letters (not for the "* " prefix, spaces or punctuation), one per frame
			if
				not blipped
				and char ~= " "
				and not PUNCTUATION[char]
				and bubble.Shown > 2
				and bubble.Shown % Tuning.BLIP_EVERY == 1
			then
				blipped = true
				if audible then
					playBlip()
				end
			end
		end
		bubble.Label.MaxVisibleGraphemes = if bubble.Shown >= #bubble.Chars then -1 else bubble.Shown
	elseif bubble.Visible and bubble.Hold < math.huge then
		bubble.Hold -= dt
		if bubble.Hold <= 0 then
			bubble.Visible = false
		end
	end
	-- fade / pop
	local target = if bubble.Visible and not shop then 1 else 0
	local alpha = bubble.Alpha
	if alpha ~= target then
		local rate = if target > alpha then 8 else 4
		alpha = if target > alpha then math.min(target, alpha + dt * rate) else math.max(target, alpha - dt * rate)
		setBubbleAlpha(bubble, alpha)
	end
	if bubble.Pop < 1 then
		bubble.Pop = math.min(1, bubble.Pop + dt / 0.22)
		bubble.Scale.Scale = if reduced then 1 else 0.7 + 0.3 * easeOutBack(bubble.Pop)
	end
	bubble.Gui.Enabled = alpha > 0.01
end

-- Three "Z"s, a third of a cycle apart, each rising up and to the right, growing, swaying and fading.
local function layoutZzz(letters: { TextLabel }, strokes: { UIStroke }, clock: number, alpha: number, reduced: boolean)
	local cycle = Tuning.ZZZ_CYCLE * (if reduced then 1.4 else 1)
	for i, label in letters do
		local phase = ((clock / cycle) + (i - 1) / #letters) % 1
		local fadeIn = clamp01(phase / 0.18)
		local fadeOut = clamp01((1 - phase) / 0.4)
		local vis = math.min(fadeIn, fadeOut) * alpha
		local sway = if reduced then 0 else math.sin(phase * math.pi * 3 + i) * 0.05
		label.Position = UDim2.fromScale(0.18 + 0.5 * phase + sway, 0.86 - 0.72 * phase)
		local size = 0.13 + 0.17 * phase
		label.Size = UDim2.fromScale(size, size)
		label.Rotation = if reduced then 0 else -14 + 22 * math.sin(phase * math.pi)
		label.TextTransparency = 1 - vis
		strokes[i].Transparency = 1 - vis
	end
end

-- seen: the camera can see him (otherwise the letters wait where they are)
local function stepZzz(r: Rig, dt: number, reduced: boolean, seen: boolean)
	local asleep = r.Machine.State == "Asleep"
		or (r.Machine.State == "Dozing" and r.Machine.Time > Tuning.DOZE_TIME * 0.6)
	local target = if asleep then 1 else 0
	if r.ZzzAlpha ~= target then
		local rate = if target > r.ZzzAlpha then 1.2 else 6
		r.ZzzAlpha = if target > r.ZzzAlpha
			then math.min(1, r.ZzzAlpha + dt * rate)
			else math.max(0, r.ZzzAlpha - dt * rate)
	end
	local visible = r.ZzzAlpha > 0.01
	r.Zzz.Enabled = visible
	if not visible or not seen then
		return
	end
	layoutZzz(r.Letters, r.LetterStrokes, r.Clock, r.ZzzAlpha, reduced)
end

-- Eyes -------------------------------------------------------------------------------------------------------

local function setEyes(r: Rig, open: boolean)
	if r.EyesOpen == open then
		return
	end
	r.EyesOpen = open
	for _, part in r.Pupils do
		part.Transparency = if open then 0 else 1
	end
	for _, part in r.Lids do
		part.Transparency = if open then 1 else 0
	end
end

local function stepEyes(r: Rig)
	local m = r.Machine
	local state = m.State
	local open: boolean
	if state == "Asleep" then
		open = false
	elseif state == "Waking" then
		open = m.Time >= 0.08
	elseif state == "Dozing" then
		-- heavy-lidded: shut, a last sleepy peek, shut for good
		open = m.Time < 0.3 or (m.Time >= 0.55 and m.Time < 0.85)
	else
		if r.Clock >= r.BlinkAt then
			r.BlinkUntil = r.Clock + 0.13
			r.BlinkAt = r.Clock + random:NextNumber(2.4, 5.2)
		end
		open = r.Clock >= r.BlinkUntil
	end
	setEyes(r, open)
end

-- Pose -------------------------------------------------------------------------------------------------------

local function applyPose(r: Rig, alpha: number, breath: number, extraPitch: number)
	local limbs = ShopkeeperController.Pose(r.Pose, alpha, breath, r.Yaw, r.Pitch + extraPitch, r.LimbCFrames)
	local n = 0
	for _, limb in r.Limbs do
		local cf = limbs[limb.Name]
		if cf then
			for i, part in limb.Parts do
				n += 1
				r.MoveParts[n] = part
				r.MoveCFrames[n] = cf * limb.Offsets[i]
			end
		end
	end
	for i = #r.MoveParts, n + 1, -1 do
		r.MoveParts[i] = nil
		r.MoveCFrames[i] = nil
	end
	if n > 0 then
		workspace:BulkMoveTo(r.MoveParts, r.MoveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Setup / teardown --------------------------------------------------------------------------------------------

local function teardown()
	local r = rig
	if r == nil then
		return
	end
	rig = nil
	for _, c in r.Connections do
		c:Disconnect()
	end
	if r.Model.Parent then
		-- leave the replicated model exactly as the server built it (asleep)
		pcall(function()
			r.Yaw, r.Pitch = 0, 0
			applyPose(r, 0, 0, 0)
			setEyes(r, false)
		end)
	end
	for _, attachment in r.Anchors do
		attachment:Destroy()
	end
end

local function setup(model: Model): boolean
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	local pose = ShopkeeperController.PoseRig(model)
	if root == nil or not root:IsA("BasePart") or head == nil or pose == nil then
		return false
	end
	local sleepLimbs = ShopkeeperController.Pose(pose, 0)

	-- every visible part of the upper body, as an offset from its limb in the (built) sleep pose
	local limbs: { Limb } = {}
	for _, name in pose.UpperBody do
		local limbPart = model:FindFirstChild(name)
		local limbCF = sleepLimbs[name]
		if limbPart and limbCF then
			local entry: Limb = { Name = name, Parts = {}, Offsets = {} }
			local inverse = limbCF:Inverse()
			for _, part in limbPart:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(entry.Parts, part)
					table.insert(entry.Offsets, inverse * part.CFrame)
				end
			end
			if #entry.Parts > 0 then
				table.insert(limbs, entry)
			end
		end
	end

	local pupils: { BasePart } = {}
	local lids: { BasePart } = {}
	for _, part in head:GetDescendants() do
		if part:IsA("BasePart") then
			if table.find(Shopkeeper.EYES, part.Name) then
				table.insert(pupils, part)
			elseif table.find(Shopkeeper.LIDS, part.Name) then
				table.insert(lids, part)
			end
		end
	end

	local zzzOffset = model:GetAttribute("ZzzOffset")
	local bubbleOffset = model:GetAttribute("BubbleOffset")
	local zzzAnchor = newAnchor(
		root,
		"ShopkeeperZzzAnchor",
		if typeof(zzzOffset) == "Vector3" then zzzOffset else Vector3.new(0, 3.2, -1.5)
	)
	local bubbleAnchor = newAnchor(
		root,
		"ShopkeeperBubbleAnchor",
		if typeof(bubbleOffset) == "Vector3" then bubbleOffset else Vector3.new(0, 4, -1.3)
	)
	local zzz, letters, strokes = buildZzz(zzzAnchor)
	local bubble = buildBubble(bubbleAnchor)
	setBubbleAlpha(bubble, 0)

	-- what the camera has to see for posing to matter: every moving part (+ a margin for the awake lift and the
	-- look-at) and the rising Zzz; the root never moves, so this is fixed
	local rootCF = pose.RootCF
	local lo, hi = rootCF.Position, rootCF.Position
	local function extend(p: Vector3, pad: number)
		lo = Vector3.new(math.min(lo.X, p.X - pad), math.min(lo.Y, p.Y - pad), math.min(lo.Z, p.Z - pad))
		hi = Vector3.new(math.max(hi.X, p.X + pad), math.max(hi.Y, p.Y + pad), math.max(hi.Z, p.Z + pad))
	end
	for _, entry in limbs do
		for _, part in entry.Parts do
			extend(part.CFrame.Position, part.Size.Magnitude * 0.5)
		end
	end
	extend(rootCF * zzzAnchor.Position, Tuning.ZZZ_REACH)

	local r: Rig = {
		Model = model,
		Root = root,
		Pose = pose,
		RootInv = rootCF:Inverse(),
		ViewCentre = (lo + hi) * 0.5,
		ViewRadius = (hi - lo).Magnitude * 0.5 + Tuning.VIEW_MARGIN,
		BubblePos = rootCF * bubbleAnchor.Position,
		Limbs = limbs,
		LimbCFrames = {},
		MoveParts = {},
		MoveCFrames = {},
		Pupils = pupils,
		Lids = lids,
		Anchors = { zzzAnchor, bubbleAnchor },
		Zzz = zzz,
		Letters = letters,
		LetterStrokes = strokes,
		ZzzAlpha = 0,
		Bubble = bubble,
		Machine = Machine.new(),
		Yaw = 0,
		Pitch = 0,
		EyesOpen = false,
		BlinkAt = 0,
		BlinkUntil = 0,
		Clock = random:NextNumber(0, 10),
		Breath = random:NextNumber(0, 2 * math.pi),
		PoseAccum = 0,
		PoseDirty = false,
		Idle = true,
		Connections = {},
	}
	pcall(function()
		table.insert(
			r.Connections,
			model.AncestryChanged:Connect(function(_, parent)
				if parent == nil and rig == r then
					teardown()
				end
			end)
		)
	end)
	rig = r
	return true
end

local function findShopkeeper(container: Instance): Model?
	for _, inst in container:GetDescendants() do
		if inst:IsA("Model") and inst:GetAttribute("Shopkeeper") == true then
			return inst
		end
	end
	return nil
end

local function consider(lobby: Instance?, fresh: boolean?)
	if lobby == nil or searching then
		return
	end
	local current = rig
	if current and current.Model.Parent and current.Model:IsDescendantOf(lobby) then
		return
	end
	if lobby:GetAttribute("ShopkeeperError") ~= nil then
		return -- the server could not build him into this lobby: nothing to find
	end
	if lobby == fruitless then
		if not fresh then
			return -- searched to the end already (a TestArena fallback, a rig PoseRig rejects): no rescans
		end
		fruitless = nil
	end
	searching = true
	task.spawn(function()
		-- the map replicates as a whole, but give late descendants (joint attributes, head parts) a moment
		local found = false
		for _ = 1, Tuning.SEARCH_TRIES do
			if lobby.Parent == nil then
				break
			end
			local model = findShopkeeper(lobby)
			if model and ShopkeeperController.Attach(model) then
				found = true
				break
			end
			task.wait(Tuning.SEARCH_INTERVAL)
		end
		if not found and lobby.Parent ~= nil then
			fruitless = lobby
		end
		searching = false
	end)
end

-- Frame step -------------------------------------------------------------------------------------------------

local function step(dt: number)
	local r = rig
	if r == nil then
		return
	end
	if r.Model.Parent == nil then
		teardown()
		return
	end
	local rootPos = r.Pose.RootCF.Position
	local body, headPos = localTarget()
	local bodyDistance: number? = if body then (body - rootPos).Magnitude else nil
	local camera = workspace.CurrentCamera
	local cameraCF: CFrame? = if camera then camera.CFrame else nil
	local cameraPos: Vector3? = if cameraCF then cameraCF.Position else nil
	local cameraDistance = if cameraPos then (cameraPos - rootPos).Magnitude else math.huge
	if (bodyDistance == nil or bodyDistance > Tuning.ACTIVE_RADIUS) and cameraDistance > Tuning.ACTIVE_RADIUS then
		-- far away (in a round, on the other side of the island): snap back to sleep once, then do nothing
		if not r.Idle then
			r.Idle = true
			r.Machine = Machine.new()
			r.Bubble.Visible = false
			setBubbleAlpha(r.Bubble, 0)
			r.Bubble.Gui.Enabled = false
			r.Zzz.Enabled = false
			r.ZzzAlpha = 0
			r.Yaw, r.Pitch = 0, 0
			applyPose(r, 0, 0, 0)
			setEyes(r, false)
			r.PoseDirty = false
		end
		return
	end
	r.Idle = false
	r.Clock += dt
	local reduced = reducedMotion()
	local shop = shopOpen()
	-- only a customer counts: a player in front of him (one behind the booth's back shelf does not wake him up)
	local distance: number? = nil
	if body and bodyDistance and (r.RootInv * body).Z < -Tuning.FRONT_MARGIN then
		distance = bodyDistance
	end
	-- what the camera can see: him (pose, Zzz; nothing of the world shows behind the opaque Shop screen) and the
	-- speech bubble (on screen and within its MaxDistance: its 2D blips and the bye line need it)
	local fov, aspect = viewOf(camera)
	local bodySeen = not shop and cameraSees(cameraCF, fov, aspect, r.ViewCentre, r.ViewRadius)
	local bubbleSeen = not shop
		and (cameraPos == nil or (cameraPos - r.BubblePos).Magnitude <= Tuning.BUBBLE_MAX_DISTANCE)
		and cameraSees(cameraCF, fov, aspect, r.BubblePos, Tuning.BUBBLE_VIEW_RADIUS)
	local m = r.Machine
	for _, event in Machine.Step(m, dt, distance) do
		if event == "Wake" then
			say(r, "shop.keeper.greet", Tuning.GREET_HOLD)
			r.BlinkAt = r.Clock + random:NextNumber(1.6, 3)
		elseif event == "Bye" then
			if bubbleSeen then
				say(r, "shop.keeper.bye", math.huge)
			else
				-- the player walked off with the booth out of sight: no line typed (and blipped) where nobody can see
				-- it, and no old line left up either; he dozes off without a word
				hideBubble(r.Bubble)
			end
		elseif event == "Doze" or event == "Return" then
			-- the bye line (if still up) fades shortly after it is fully typed
			r.Bubble.Hold = math.min(r.Bubble.Hold, if event == "Doze" then 0.4 else 0.8)
		end
	end

	-- the skull follows the player's head (smoothed) while he is up; it relaxes back as he dozes off
	local alpha = Machine.Alpha(m, reduced)
	local awake = m.State == "Waking" or m.State == "Awake" or m.State == "Bye"
	local yawTarget, pitchTarget = 0, 0
	if awake and headPos then
		yawTarget, pitchTarget = ShopkeeperController.LookAngles(r.Pose.LookFrame, headPos)
	end
	local k = 1 - math.exp(-(if awake then Tuning.LOOK_RATE else 3) * dt)
	r.Yaw += (yawTarget - r.Yaw) * k
	r.Pitch += (pitchTarget - r.Pitch) * k

	stepEyes(r)
	stepZzz(r, dt, reduced, bodySeen)
	stepBubble(r, dt, reduced, shop, bubbleSeen)

	-- breathing: slow and deep asleep, light awake; the phase is integrated so changing pace never jumps
	local up = clamp01(alpha)
	local sleepBreath, awakeBreath = Tuning.SLEEP_BREATH, Tuning.AWAKE_BREATH
	local period = sleepBreath.Period + (awakeBreath.Period - sleepBreath.Period) * up
	local amp = (sleepBreath.Amp + (awakeBreath.Amp - sleepBreath.Amp) * up) * (if reduced then 0.5 else 1)
	r.Breath = (r.Breath + dt * 2 * math.pi / period) % (2 * math.pi)
	local breath = math.sin(r.Breath) * amp

	-- pose: never while he cannot be seen (off screen, behind the Shop screen: the current pose is applied the moment
	-- he shows again); every frame while he wakes, dozes off or turns; ~30 Hz awake with the skull settled on the
	-- player; ~15 Hz while he only breathes in his sleep
	if not bodySeen then
		r.PoseDirty = true
		return
	end
	local settled = (m.State == "Awake" or m.State == "Bye")
		and math.abs(yawTarget - r.Yaw) < Tuning.LOOK_SETTLED
		and math.abs(pitchTarget - r.Pitch) < Tuning.LOOK_SETTLED
	local hz = if m.State == "Asleep" then Tuning.SLEEP_HZ elseif settled then Tuning.AWAKE_HZ else 0
	r.PoseAccum += dt
	if hz > 0 and not r.PoseDirty and r.PoseAccum < 1 / hz then
		return
	end
	r.PoseAccum = 0
	r.PoseDirty = false
	local overshoot = if alpha > 1 then (alpha - 1) * math.rad(40) else 0
	applyPose(r, alpha, breath, overshoot)
end

-- GUI builders (no services; offline tests and previews build them on any Attachment) -------------------------

function ShopkeeperController.BuildBubble(anchor: Attachment, text: string?): BillboardGui
	local bubble = buildBubble(anchor)
	if text then
		setLine(bubble, text)
		setBubbleAlpha(bubble, 1)
		bubble.Gui.Enabled = true
	else
		setBubbleAlpha(bubble, 0)
	end
	return bubble.Gui
end

function ShopkeeperController.BuildZzz(anchor: Attachment, clock: number?): BillboardGui
	local gui, letters, strokes = buildZzz(anchor)
	layoutZzz(letters, strokes, clock or 0, 1, false)
	gui.Enabled = true
	return gui
end

-- Attaches the controller to a shopkeeper model (Start finds the lobby's one by itself); false while the model is
-- incomplete. Detach() lets go of it (the parts return to the sleep pose); Step(dt) advances one frame (Heartbeat).
function ShopkeeperController.Attach(model: Model): boolean
	teardown()
	return setup(model)
end

function ShopkeeperController.Detach()
	teardown()
end

function ShopkeeperController.Step(dt: number)
	step(dt)
end

function ShopkeeperController.State(): string?
	local r = rig
	return if r then r.Machine.State else nil
end

-- Looks for the shopkeeper in a lobby map (in the background, retried for late replication) and attaches to it.
function ShopkeeperController.Search(lobby: Instance?, fresh: boolean?)
	consider(lobby, fresh)
end

-- Tests: stand-ins for the controllers Init() looks up.
function ShopkeeperController._Harness(deps: { [string]: any })
	Sound = deps.Sound
	UI = deps.UI
	Graphics = deps.Graphics
end

function ShopkeeperController.Init()
	Lobby = controller("LobbyController")
	Graphics = controller("GraphicsController")
	Sound = controller("SoundController")
	UI = controller("UIController")
end

function ShopkeeperController.Start()
	if Lobby and Lobby.Ready then
		Lobby.Ready:Connect(function(model: Model)
			consider(model, true)
		end)
	end
	if Lobby and type(Lobby.Lobby) == "function" then
		consider(Lobby.Lobby())
	end
	-- fallback (no LobbyController, or the Ready signal fired before Start): look for the lobby map now and then
	task.spawn(function()
		while true do
			if rig == nil and not searching then
				consider(workspace:FindFirstChild("Lobby"))
			end
			task.wait(3)
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return ShopkeeperController
