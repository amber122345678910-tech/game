--!strict
-- STRETCH-POP · Ретрансляция визуального состояния рук/шара другим игрокам.
-- Физика и визуал считаются у каждого клиента локально; остальным нужен только факт
-- «рука прицеплена к точке X» / «игрок в режиме шара». Сервер проверяет типы, лимит частоты
-- и разумную дистанцию точки до персонажа, затем рассылает всем, кроме отправителя.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local StretchPhysics = require(Shared.Physics.StretchPhysics)
local Net = require(Shared.Net)

local MAX_POINT_DISTANCE = PhysicsConfig.GrabRange.Max + 120
local VALID_SIDES = { Left = true, Right = true, Ball = true }

type Budget = {
	Tokens: number,
	At: number,
}

local StretchReplicationService = {}

local budgets: { [Player]: Budget } = {}
local initialized = false

local function allow(player: Player): boolean
	local now = os.clock()
	local budget = budgets[player]
	if budget == nil then
		budget = { Tokens = PhysicsConfig.Validation.ArmEventsPerSecond, At = now }
		budgets[player] = budget
	end
	local rate = PhysicsConfig.Validation.ArmEventsPerSecond
	budget.Tokens = math.min(rate, budget.Tokens + (now - budget.At) * rate)
	budget.At = now
	if budget.Tokens < 1 then
		return false
	end
	budget.Tokens -= 1
	return true
end

local function onArmVisual(player: Player, side: unknown, active: unknown, point: unknown)
	if typeof(side) ~= "string" or VALID_SIDES[side] == nil then
		return
	end
	if typeof(active) ~= "boolean" then
		return
	end
	local relayPoint: Vector3? = nil
	if point ~= nil then
		if typeof(point) ~= "Vector3" or not StretchPhysics.IsFiniteVector(point, 1e6) then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - point).Magnitude > MAX_POINT_DISTANCE then
			return
		end
		relayPoint = point
	end
	if not allow(player) then
		return
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.PeerArmVisual:FireClient(other, player, side, active, relayPoint)
		end
	end
end

function StretchReplicationService.Init()
	if initialized then
		return
	end
	initialized = true
	Net.ArmVisual.OnServerEvent:Connect(onArmVisual)
	Players.PlayerRemoving:Connect(function(player)
		budgets[player] = nil
	end)
end

return StretchReplicationService
