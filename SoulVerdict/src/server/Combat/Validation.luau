--!strict
-- Validation: server-side combat helpers shared by the combat services, CastContext and server kits.
-- Character queries, payload sanitising, rate limiting, raycasts, optional-service lookup.
-- Never requires services at load time: optional services are resolved lazily with Validation.Service().
--
-- API
--   Validation.Now() -> number                         workspace:GetServerTimeNow()
--   Validation.Service(name) -> any?                   lazily required ServerScriptService.Server.Services[name]
--                                                      (nil if missing / failed); SetService(name, impl?) overrides
--   Validation.Root(model) -> BasePart?   .Humanoid(model) -> Humanoid?   .RootPosition(model) -> Vector3?
--   Validation.IsAlive(model) -> boolean               in the world, not Dead, Health > 0 (Downed counts as alive)
--   Validation.IsUp(model) -> boolean                  alive and not Downed
--   Validation.Team(model) -> string                   Teams.TeamOf
--   Validation.Kit(model) -> KitDef?                   from the KitId attribute
--   Validation.Role(model) -> "Monster" | "Human" | ""  kit role (Lobby players with a human kit are "Human")
--   Validation.GetPlayer(model) -> Player?
--   Validation.ModelOf(player) -> Model?
--   Validation.Combatants() -> {Model}                 CharacterService.GetAll() + RegisterCombatant() extras
--                                                      (+ player characters if CharacterService is missing)
--   Validation.RegisterCombatant(model) / UnregisterCombatant(model)
--   Validation.Capsule(model) -> Capsule?              vertical hit capsule (RigScale, HipHeight aware)
--   Validation.Velocity(model) -> Vector3   .HorizontalSpeed(model) -> number
--   Validation.Look(model) -> Vector3                  flat facing of the root
--   Validation.Flat(v) -> Vector3   .FlatUnit(v, fallback) -> Vector3   .Unit(v, fallback) -> Vector3
--   Validation.IsVector(v, maxMagnitude?) -> boolean   finite Vector3 check
--   Validation.WorldRaycastParams(extraIgnore?) -> RaycastParams   excludes every combatant (+ extras)
--   Validation.Raycast(origin, direction, extraIgnore?) -> RaycastResult?
--   Validation.GroundBelow(pos, maxDrop) -> Vector3?   ground hit point straight below pos
--   Validation.LineOfSight(a, b, extraIgnore?) -> boolean
--   Validation.RoundState() -> Instance?   .RoundAttr(name) -> any   .InCombatPhase() -> boolean
--   Validation.RateLimiter(interval) -> (key: any, now: number) -> boolean

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Kits = require(Shared.Kits) :: any
local Teams = require(Shared.Combat.Teams) :: any
local HitTest = require(Shared.Combat.HitTest) :: any

local Validation = {}

---------------------------------------------------------------------------------------------------
-- Time

function Validation.Now(): number
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------------------------------------------
-- Optional services (CharacterService, RoundService, StatsService, VerdictBoxService, ...)

local serviceCache: { [string]: any } = {}
local serviceOverrides: { [string]: any } = {}

function Validation.Service(name: string): any?
	local override = serviceOverrides[name]
	if override ~= nil then
		return override or nil
	end
	local cached = serviceCache[name]
	if cached ~= nil then
		return cached or nil
	end
	local result: any = false
	local servicesFolder = script.Parent.Parent:FindFirstChild("Services")
	local module = servicesFolder and servicesFolder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, value = pcall(require, module)
		if ok and type(value) == "table" then
			result = value
		end
	end
	serviceCache[name] = result
	return result or nil
end

-- Test / tooling hook: replace (impl) or hide (false) a service; nil restores the lazy lookup.
function Validation.SetService(name: string, impl: any)
	serviceOverrides[name] = impl
	serviceCache[name] = nil
end

---------------------------------------------------------------------------------------------------
-- Character queries

function Validation.Root(model: Model?): BasePart?
	if model == nil then
		return nil
	end
	local primary = model.PrimaryPart
	if primary then
		return primary
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function Validation.Humanoid(model: Model?): Humanoid?
	if model == nil then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

function Validation.RootPosition(model: Model?): Vector3?
	local root = Validation.Root(model)
	if root then
		return root.CFrame.Position
	end
	return nil
end

function Validation.IsAlive(model: Model?): boolean
	if model == nil or model.Parent == nil then
		return false
	end
	if model:GetAttribute("Dead") == true then
		return false
	end
	local hum = Validation.Humanoid(model)
	if hum == nil or hum.Health <= 0 then
		return false
	end
	return Validation.Root(model) ~= nil
end

function Validation.IsUp(model: Model?): boolean
	return Validation.IsAlive(model) and (model :: Model):GetAttribute("Downed") ~= true
end

function Validation.Team(model: Model?): string
	return Teams.TeamOf(model)
end

function Validation.Kit(model: Model?): any?
	if model == nil then
		return nil
	end
	local kitId = model:GetAttribute("KitId")
	if type(kitId) ~= "string" then
		return nil
	end
	return Kits.Get(kitId)
end

function Validation.Role(model: Model?): string
	local kit = Validation.Kit(model)
	if kit then
		return if kit.Role == "Monster" then "Monster" else "Human"
	end
	local team = Validation.Team(model)
	if team == "Monster" then
		return "Monster"
	elseif team == "Humans" or team == "Lobby" then
		return "Human"
	end
	return ""
end

function Validation.GetPlayer(model: Model?): Player?
	if model == nil then
		return nil
	end
	local cs = Validation.Service("CharacterService")
	if cs and type(cs.GetPlayer) == "function" then
		local ok, player = pcall(cs.GetPlayer, model)
		if ok and typeof(player) == "Instance" and player:IsA("Player") then
			return player
		end
		if ok then
			-- CharacterService answered "no player" (bot / dummy); still honour engine characters
			local ok2, p2 = pcall(function()
				return Players:GetPlayerFromCharacter(model)
			end)
			return if ok2 then p2 else nil
		end
	end
	local ok, player = pcall(function()
		return Players:GetPlayerFromCharacter(model)
	end)
	if ok then
		return player
	end
	return nil
end

function Validation.ModelOf(player: Player): Model?
	local cs = Validation.Service("CharacterService")
	if cs and type(cs.GetModel) == "function" then
		local ok, model = pcall(cs.GetModel, player)
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			return model
		end
	end
	local character = player.Character
	if character and character:IsA("Model") then
		return character
	end
	return nil
end

local extras: { [Model]: boolean } = {}

function Validation.RegisterCombatant(model: Model)
	extras[model] = true
end

function Validation.UnregisterCombatant(model: Model)
	extras[model] = nil
end

function Validation.Combatants(): { Model }
	local out: { Model } = {}
	local seen: { [Model]: boolean } = {}
	local cs = Validation.Service("CharacterService")
	local got = false
	if cs and type(cs.GetAll) == "function" then
		local ok, list = pcall(cs.GetAll)
		if ok and type(list) == "table" then
			got = true
			for _, m in list do
				if typeof(m) == "Instance" and m:IsA("Model") and not seen[m] then
					seen[m] = true
					table.insert(out, m)
				end
			end
		end
	end
	if not got then
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character and not seen[character] then
				seen[character] = true
				table.insert(out, character)
			end
		end
	end
	for m in extras do
		if m.Parent == nil then
			extras[m] = nil
		elseif not seen[m] then
			seen[m] = true
			table.insert(out, m)
		end
	end
	return out
end

function Validation.Capsule(model: Model): any?
	local root = Validation.Root(model)
	if root == nil then
		return nil
	end
	local scale = model:GetAttribute("RigScale")
	local s = if type(scale) == "number" and scale > 0 then scale else 1
	local hum = Validation.Humanoid(model)
	local groundOffset: number? = nil
	if hum then
		groundOffset = hum.HipHeight + root.Size.Y * 0.5
	end
	return HitTest.CharacterCapsule(root.CFrame.Position, s, groundOffset)
end

function Validation.Velocity(model: Model): Vector3
	local root = Validation.Root(model)
	if root == nil then
		return Vector3.zero
	end
	local ok, v = pcall(function()
		return root.AssemblyLinearVelocity
	end)
	if ok and typeof(v) == "Vector3" then
		return v
	end
	return Vector3.zero
end

function Validation.HorizontalSpeed(model: Model): number
	local v = Validation.Velocity(model)
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

function Validation.Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Validation.FlatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return fallback
	end
	return f.Unit
end

function Validation.Unit(v: Vector3, fallback: Vector3): Vector3
	if v.Magnitude < 1e-6 then
		return fallback
	end
	return v.Unit
end

function Validation.Look(model: Model): Vector3
	local root = Validation.Root(model)
	if root == nil then
		return Vector3.new(0, 0, -1)
	end
	return Validation.FlatUnit(root.CFrame.LookVector, Vector3.new(0, 0, -1))
end

function Validation.IsVector(v: any, maxMagnitude: number?): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local x, y, z = v.X, v.Y, v.Z
	if x ~= x or y ~= y or z ~= z then
		return false
	end
	local limit = maxMagnitude or 1e6
	return math.abs(x) <= limit and math.abs(y) <= limit and math.abs(z) <= limit
end

---------------------------------------------------------------------------------------------------
-- World queries

local IGNORE_FOLDERS = { "Effects", "VFX", "Debris", "Hazards", "Boxes", "SV_VFX" }

function Validation.WorldRaycastParams(extraIgnore: { Instance }?): RaycastParams
	local ignore: { Instance } = {}
	for _, m in Validation.Combatants() do
		table.insert(ignore, m)
	end
	for _, name in IGNORE_FOLDERS do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	if extraIgnore then
		for _, inst in extraIgnore do
			table.insert(ignore, inst)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

function Validation.Raycast(origin: Vector3, direction: Vector3, extraIgnore: { Instance }?): RaycastResult?
	if direction.Magnitude < 1e-4 then
		return nil
	end
	return workspace:Raycast(origin, direction, Validation.WorldRaycastParams(extraIgnore))
end

function Validation.GroundBelow(pos: Vector3, maxDrop: number): Vector3?
	local hit = Validation.Raycast(pos, Vector3.new(0, -math.max(0.1, maxDrop), 0))
	if hit then
		return hit.Position
	end
	return nil
end

function Validation.LineOfSight(a: Vector3, b: Vector3, extraIgnore: { Instance }?): boolean
	return Validation.Raycast(a, b - a, extraIgnore) == nil
end

---------------------------------------------------------------------------------------------------
-- Round state

function Validation.RoundState(): Instance?
	return ReplicatedStorage:FindFirstChild("RoundState")
end

function Validation.RoundAttr(name: string): any
	local rs = Validation.RoundState()
	if rs then
		return rs:GetAttribute(name)
	end
	return nil
end

function Validation.InCombatPhase(): boolean
	local phase = Validation.RoundAttr("Phase")
	return phase == "Round" or phase == "Collapse"
end

---------------------------------------------------------------------------------------------------
-- Rate limiting

function Validation.RateLimiter(interval: number): (key: any, now: number) -> boolean
	local last: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
	return function(key: any, now: number): boolean
		local prev = last[key]
		if prev ~= nil and now - prev < interval then
			return false
		end
		last[key] = now
		return true
	end
end

return Validation
