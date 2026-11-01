--!strict
-- MovementService (P12): forced movement routing (SPEC §7.7, §17).
--   * Player characters are simulated by their owner client: packets go to that client via Net "ForceMove"
--     (the client MovementController applies them with LinearVelocity/AlignPosition).
--   * Bots / dummies (server-owned): applied here with a LinearVelocity on the HumanoidRootPart that is
--     destroyed after the packet's duration (one mover per model; a new packet replaces the old one).
--   * Teleports are also performed on the server (PivotTo) for everyone, plus the packet to the owner.
--
-- ForceMovePacket = { kind: "Impulse"|"Pull"|"Lift"|"Slam"|"Dash"|"Teleport"|"Root", velocity: Vector3?,
--                     target: Vector3?, duration: number?, cframe: CFrame?, height: number?, echo: boolean? }
--   Impulse  velocity (studs/s, world) for duration [0.2]           (knockback)
--   Pull     velocity toward `target` for duration [0.25]; if velocity is nil: 20 studs/s toward target
--   Lift     rise `height` [8] studs over duration [0.45] (then gravity resumes)
--   Slam     velocity [(0,-140,0)] for duration [0.3] (stops on landing, client side)
--   Dash     velocity for duration [Config.Human.DashTime]; echo = true when this answers the client's own
--            Dash request (a client that already predicted the dash should ignore it)
--   Teleport cframe (root CFrame); server PivotTo + packet
--   Root     hold position (horizontal velocity 0) for duration [0.5]
--
-- API
--   MovementService.Send(target: Model, packet: ForceMovePacket)
--   MovementService.Teleport(model: Model, cframe: CFrame)
--   MovementService.Dash(model: Model, dir: Vector3, distance: number, time: number, echo: boolean?)
--   MovementService.Stop(model: Model)          removes a server-applied mover (bots)
--   MovementService.Sent: Signal(model, packet)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Config = require(Shared.Config) :: any
local Net = require(Shared.Net) :: any
local Signal = require(Shared.Util.Signal) :: any

local Validation = require(script.Parent.Parent.Combat.Validation) :: any

local MovementService = {}
MovementService.Priority = 12
MovementService.Sent = Signal.new()

local KINDS = { Impulse = true, Pull = true, Lift = true, Slam = true, Dash = true, Teleport = true, Root = true }
local MAX_SPEED = 400
local MAX_DURATION = 5
local MOVER_FORCE = 1e7

type Mover = { Token: number, Velocity: LinearVelocity, Attachment: Attachment }
local movers: { [Model]: Mover } = setmetatable({}, { __mode = "k" }) :: any
local nextToken = 0

local function clampVector(v: any, limit: number): Vector3?
	if not Validation.IsVector(v) then
		return nil
	end
	local vec = v :: Vector3
	local m = vec.Magnitude
	if m > limit then
		return vec * (limit / m)
	end
	return vec
end

local function clampDuration(d: any, default: number): number
	if type(d) ~= "number" or d ~= d then
		return default
	end
	return math.clamp(d, 0.02, MAX_DURATION)
end

-- Returns a clean copy of the packet with only known, valid fields.
local function sanitize(packet: any): { [string]: any }?
	if type(packet) ~= "table" or not KINDS[packet.kind] then
		return nil
	end
	local out: { [string]: any } = { kind = packet.kind }
	local v = clampVector(packet.velocity, MAX_SPEED)
	if v then
		out.velocity = v
	end
	if Validation.IsVector(packet.target) then
		out.target = packet.target
	end
	if packet.duration ~= nil then
		out.duration = clampDuration(packet.duration, 0.25)
	end
	if typeof(packet.cframe) == "CFrame" then
		out.cframe = packet.cframe
	end
	if type(packet.height) == "number" and packet.height == packet.height then
		out.height = math.clamp(packet.height, 0, 60)
	end
	if packet.echo == true then
		out.echo = true
	end
	return out
end

function MovementService.Stop(model: Model)
	local m = movers[model]
	if m then
		movers[model] = nil
		m.Velocity:Destroy()
		m.Attachment:Destroy()
	end
end

-- Server-side application for server-owned characters (bots / dummies).
local function applyServer(model: Model, packet: { [string]: any })
	local root = Validation.Root(model)
	if root == nil then
		return
	end
	local kind = packet.kind
	if kind == "Teleport" then
		return -- PivotTo already done by Send/Teleport
	end
	local pos = root.CFrame.Position
	local velocity: Vector3 = Vector3.zero
	local duration = 0.25
	local planar = false
	if kind == "Impulse" then
		velocity = packet.velocity or Vector3.zero
		duration = packet.duration or 0.2
	elseif kind == "Dash" then
		velocity = packet.velocity or Vector3.zero
		duration = packet.duration or Config.Human.DashTime
	elseif kind == "Pull" then
		local target: Vector3? = packet.target
		if packet.velocity then
			velocity = packet.velocity
		elseif target then
			velocity = Validation.Unit(target - pos, Vector3.zero) * 20
		end
		duration = packet.duration or 0.25
	elseif kind == "Lift" then
		local height = packet.height or 8
		duration = packet.duration or 0.45
		velocity = Vector3.new(0, height / math.max(duration, 0.05), 0)
	elseif kind == "Slam" then
		velocity = packet.velocity or Vector3.new(0, -140, 0)
		duration = packet.duration or 0.3
	elseif kind == "Root" then
		planar = true
		duration = packet.duration or 0.5
	end
	MovementService.Stop(model)
	nextToken += 1
	local token = nextToken

	local att = Instance.new("Attachment")
	att.Name = "SV_MoveAttachment"
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "SV_Mover"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = MOVER_FORCE
	if planar then
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		lv.PrimaryTangentAxis = Vector3.xAxis
		lv.SecondaryTangentAxis = Vector3.zAxis
		lv.PlaneVelocity = Vector2.zero
	else
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.VectorVelocity = velocity
	end
	lv.Parent = root

	movers[model] = { Token = token, Velocity = lv, Attachment = att }
	Validation.Delay(duration, function()
		local m = movers[model]
		if m and m.Token == token then
			MovementService.Stop(model)
		end
	end)
end

function MovementService.Send(target: Model, packet: any)
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return
	end
	local clean = sanitize(packet)
	if clean == nil then
		warn("[MovementService] invalid ForceMove packet")
		return
	end
	if clean.kind == "Teleport" and clean.cframe then
		target:PivotTo(clean.cframe)
	end
	local player = Validation.GetPlayer(target)
	if player then
		Net.Server.Fire("ForceMove", player, clean)
	else
		applyServer(target, clean)
	end
	MovementService.Sent:Fire(target, clean)
end

function MovementService.Teleport(model: Model, cframe: CFrame)
	if typeof(cframe) ~= "CFrame" then
		return
	end
	MovementService.Stop(model)
	model:PivotTo(cframe)
	local root = Validation.Root(model)
	if root then
		pcall(function()
			root.AssemblyLinearVelocity = Vector3.zero
		end)
	end
	local player = Validation.GetPlayer(model)
	if player then
		Net.Server.Fire("ForceMove", player, { kind = "Teleport", cframe = cframe })
	end
	MovementService.Sent:Fire(model, { kind = "Teleport", cframe = cframe })
end

function MovementService.Dash(model: Model, dir: Vector3, distance: number, time: number, echo: boolean?)
	local t = math.max(0.05, time)
	local d = Validation.FlatUnit(dir, Validation.Look(model))
	MovementService.Send(model, {
		kind = "Dash",
		velocity = d * (math.max(0, distance) / t),
		duration = t,
		echo = if echo then true else nil,
	})
end

function MovementService.Init() end

function MovementService.Start() end

return MovementService
