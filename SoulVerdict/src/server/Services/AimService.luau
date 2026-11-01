--!strict
-- AimService (server, Priority 70): relays aim points for the client head/torso look-at layer
-- (SPEC §4 "Aim", §8 AnimController.SetAim).
--   C->S  Net "Aim" (aimPoint: Vector3)              UnreliableRemoteEvent, clients send <= 10 Hz
--   S->C  Net "Aim" (character: Model, aimPoint)     to every OTHER player (the sender animates itself)
-- Validation (every packet): a finite Vector3 with |coords| < 1e6; the sender has a character with a
-- HumanoidRootPart that is not Dead; the point is clamped to Config.Combat.MaxAimRange + AimSlack from the
-- root; per-sender token bucket (10 packets/s, burst 3); near-duplicates (< 0.25 studs within 1 s) are
-- dropped instead of relayed. Payload = Instance ref + Vector3 (well under the 900-byte limit).
--
-- API
--   AimService.Init() / AimService.Start()
--   AimService.GetAim(model: Model) -> Vector3?          latest validated aim point of a character
--   AimService.SetAim(model: Model, point: Vector3)      server-side aim (bots): stored + relayed to everyone
--   AimService.Sanitize(rootPos, point, maxRange) -> Vector3?   pure: nil if invalid, else clamped point
--   AimService.Allow(state, now) -> boolean              pure token bucket (RATE per second, BURST)
--   AimService.RATE, AimService.BURST

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local AnimMath = require(Shared:WaitForChild("Anim"):WaitForChild("AnimMath"))

type SenderState = { Bucket: AnimMath.RateState, LastPoint: Vector3?, LastSentAt: number }

local AimService = {}
AimService.Priority = 70
AimService.RATE = 10
AimService.BURST = 3

local DUPLICATE_DISTANCE = 0.25
local DUPLICATE_KEEPALIVE = 1

local senders: { [Player]: SenderState } = {}
local botSenders: { [Model]: SenderState } = setmetatable({} :: any, { __mode = "k" })
local latest: { [Model]: Vector3 } = setmetatable({} :: any, { __mode = "k" })
local CharacterService: any = nil

local function maxRange(): number
	local combat = Config.Combat or {}
	return (combat.MaxAimRange or 160) + (combat.AimSlack or 10)
end

function AimService.Sanitize(rootPos: Vector3, point: any, range: number): Vector3?
	return AnimMath.SanitizeAim(rootPos, point, range)
end

function AimService.Allow(state: AnimMath.RateState, now: number): boolean
	return AnimMath.RateGate(state, now, AimService.RATE, AimService.BURST)
end

local function newState(): SenderState
	return { Bucket = {}, LastPoint = nil, LastSentAt = -math.huge }
end

local function modelOf(player: Player): Model?
	if CharacterService and type(CharacterService.GetModel) == "function" then
		local ok, model = pcall(CharacterService.GetModel, player)
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			return model
		end
	end
	return player.Character
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- shared validation + dedupe; returns the point to relay (nil = drop)
local function accept(state: SenderState, model: Model, point: any, now: number): Vector3?
	if not AimService.Allow(state.Bucket, now) then
		return nil
	end
	if model:GetAttribute("Dead") == true then
		return nil
	end
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	local clean = AimService.Sanitize(root.Position, point, maxRange())
	if clean == nil then
		return nil
	end
	local last = state.LastPoint
	if last and (clean - last).Magnitude < DUPLICATE_DISTANCE and now - state.LastSentAt < DUPLICATE_KEEPALIVE then
		return nil
	end
	state.LastPoint = clean
	state.LastSentAt = now
	latest[model] = clean
	return clean
end

function AimService.GetAim(model: Model): Vector3?
	return latest[model]
end

function AimService.SetAim(model: Model, point: Vector3)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local state = botSenders[model]
	if state == nil then
		state = newState()
		botSenders[model] = state
	end
	local clean = accept(state, model, point, os.clock())
	if clean then
		Net.Server.FireAll("Aim", model, clean)
	end
end

function AimService.Init()
	local services = script.Parent
	local mod = services and services:FindFirstChild("CharacterService")
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			CharacterService = res
		end
	end
end

function AimService.Start()
	Net.Server.On("Aim", function(player: Player, point: any)
		if typeof(point) ~= "Vector3" then
			return
		end
		local model = modelOf(player)
		if model == nil then
			return
		end
		local state = senders[player]
		if state == nil then
			state = newState()
			senders[player] = state
		end
		local clean = accept(state, model, point, os.clock())
		if clean then
			Net.Server.FireExcept("Aim", player, model, clean)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		senders[player] = nil
	end)
end

return AimService
