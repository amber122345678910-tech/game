--!strict
-- CastContext: the object server kit handlers receive (SPEC §7.3). Created by AbilityService for every cast
-- (and by the ctxFactory passed to kit OnSpawn hooks for passives).
--
-- Fields
--   ctx.Caster: Model   ctx.Player: Player?   ctx.Root: BasePart   ctx.Humanoid: Humanoid
--   ctx.Kit: KitDef     ctx.Ability: AbilityDef   ctx.N: {[string]: number} (= Ability.Numbers)
--   ctx.CastId: number  ctx.Aim: Vector3 (clamped to Range + Config.Combat.AimSlack)
--   ctx.AimDir: Vector3 (unit, from the caster's root toward the aim; the client's dir when given)
--   ctx.FlatDir: Vector3 (unit, y = 0)   ctx.Charge: number (0..1)   ctx.Target: Model? (validated)
--   ctx.StartTime: number (server time)   ctx.ComboIndex: number (1..Combo)   ctx.Team: string
-- Methods (SPEC §7.3)
--   ctx:Wait(seconds) -> boolean         yields; false if the caster died / was downed / stunned / boxed /
--                                        despawned or the cast was cancelled meanwhile (then return!)
--   ctx:Alive() -> boolean
--   ctx:Fx(phase, data?)                 AbilityFx broadcast {caster, kit, ability, phase, castId, t0, aim, dir, charge, data}
--   ctx:Melee(spec) -> ({Model}, {[Model]: DamageResult})   box in front of the caster (Combat/Melee)
--   ctx:Hazard(type, params, hooks?) -> number   HazardService.Spawn(caster, team, ...) (params.ability defaults
--                                        to the ability id)
--   ctx:Damage(target, info) -> DamageResult      Attacker/Target/Ability filled in; Kind defaults to "Melee";
--                                        info.Amount (or info.Damage)
--   ctx:Heal(target, amount) -> number   ctx:Status(target, name, duration, data?) -> boolean
--   ctx:ForceMove(target, packet)        ctx:Teleport(cframe) -> CFrame?   (validated: no walls between, ground
--                                        within 20 studs below, else the last valid point on the path; nil = no move;
--                                        broadcasts Fx phase "Teleport" {from, to}; cframe.Position may be a ground
--                                        point or a root position — the result always stands on the ground)
--   ctx:Enemies(includeDowned?) -> {Model}   ctx:Allies(includeSelf?) -> {Model}
--   ctx:EnemiesInRadius(pos, radius, includeDowned?) -> {Model}
--   ctx:NearestEnemy(pos, maxDist, cone?: Vector3, coneDot?: number) -> Model?   (up enemies only)
--   ctx:AddUlt(model, amount)            ctx:Projectile(spec) -> number   (hazard "Projectile" convenience)
-- Extras
--   ctx:Now() -> number   ctx:IsEnemy(model) -> boolean   ctx:Cancel()   ctx:Cancelled() -> boolean
--   ctx:RootPosition() -> Vector3   ctx:GroundAt(pos, maxDrop?) -> Vector3?   ctx:LookFrame(pos?, dir?) -> CFrame
--   ctx:RootHeight() -> number (root above the feet)
--
-- CastContext.Bind(deps)   called once by AbilityService.Init with
--   { StatusService, DamageService, HazardService, MovementService, AbilityService }
-- CastContext.new(opts) -> ctx   opts: { Caster, Player?, Kit, Ability, CastId?, Aim?, AimDir?, Charge?,
--                                        Target?, ComboIndex? }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Net = require(Shared.Net) :: any
local Teams = require(Shared.Combat.Teams) :: any
local HazardDefs = require(Shared.Combat.HazardDefs) :: any
local DamageMath = require(Shared.Combat.DamageMath) :: any

local Validation = require(script.Parent.Validation) :: any
local Melee = require(script.Parent.Melee) :: any

local CastContext = {}
CastContext.__index = CastContext

local deps: any = {}

function CastContext.Bind(services: any)
	deps = services
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	return Validation.FlatUnit(v, fallback)
end

function CastContext.new(opts: any): any
	local caster: Model = opts.Caster
	local root = Validation.Root(caster)
	local hum = Validation.Humanoid(caster)
	local origin = if root then root.CFrame.Position else Vector3.zero
	local look = Validation.Look(caster)
	local aim: Vector3 = if typeof(opts.Aim) == "Vector3" then opts.Aim else origin + look * 10
	local aimDir: Vector3
	if typeof(opts.AimDir) == "Vector3" and opts.AimDir.Magnitude > 1e-4 then
		aimDir = opts.AimDir.Unit
	else
		aimDir = Validation.Unit(aim - origin, look)
	end
	local ability = opts.Ability or { Id = "Passive", Numbers = {} }
	local self = {
		Caster = caster,
		Player = opts.Player,
		Root = root,
		Humanoid = hum,
		Kit = opts.Kit,
		Ability = ability,
		N = ability.Numbers or {},
		CastId = if type(opts.CastId) == "number" then opts.CastId else 0,
		Aim = aim,
		AimDir = aimDir,
		FlatDir = flatUnit(aimDir, look),
		Charge = if type(opts.Charge) == "number" then math.clamp(opts.Charge, 0, 1) else 0,
		Target = opts.Target,
		StartTime = Validation.Now(),
		ComboIndex = if type(opts.ComboIndex) == "number" then opts.ComboIndex else 1,
		Team = Teams.TeamOf(caster),
		_cancelled = false,
	}
	return setmetatable(self, CastContext)
end

---------------------------------------------------------------------------------------------------
-- Lifetime

function CastContext.Now(_self: any): number
	return Validation.Now()
end

function CastContext.Cancel(self: any)
	self._cancelled = true
end

function CastContext.Cancelled(self: any): boolean
	return self._cancelled == true
end

function CastContext.Alive(self: any): boolean
	if self._cancelled then
		return false
	end
	local caster = self.Caster
	if not Validation.IsUp(caster) then
		return false
	end
	local status = deps.StatusService
	if status and (status.Has(caster, "Stunned") or status.Has(caster, "Boxed")) then
		return false
	end
	return true
end

function CastContext.Wait(self: any, seconds: number?): boolean
	local s = if type(seconds) == "number" and seconds == seconds then seconds else 0
	if s > 0 then
		Validation.Wait(math.min(s, 30))
	end
	return self:Alive()
end

---------------------------------------------------------------------------------------------------
-- Broadcast

function CastContext.Fx(self: any, phase: string, data: { [string]: any }?)
	Net.Server.FireAll("AbilityFx", {
		caster = self.Caster,
		kit = if self.Kit then self.Kit.Id else "",
		ability = self.Ability.Id,
		phase = phase,
		castId = self.CastId,
		t0 = Validation.Now(),
		aim = self.Aim,
		dir = self.AimDir,
		charge = self.Charge,
		data = data,
	})
end

---------------------------------------------------------------------------------------------------
-- Combat helpers

function CastContext.Melee(self: any, spec: any): ({ Model }, { [Model]: any })
	return Melee.Swing(self, spec)
end

function CastContext.Hazard(self: any, hazardType: string, params: { [string]: any }, hooks: any?): number
	local p = params
	if p.ability == nil then
		p = table.clone(params)
		p.ability = self.Ability.Id
	end
	return deps.HazardService.Spawn(self.Caster, self.Team, hazardType, p, hooks)
end

function CastContext.Damage(self: any, target: Model, info: { [string]: any }?): any
	local i: { [string]: any } = if info then table.clone(info) else {}
	i.Attacker = self.Caster
	i.Target = target
	if i.Ability == nil then
		i.Ability = self.Ability.Id
	end
	if i.Amount == nil then
		i.Amount = i.Damage
	end
	if i.Kind == nil then
		i.Kind = "Melee"
	end
	return deps.DamageService.Apply(i)
end

function CastContext.Heal(self: any, target: Model, amount: number): number
	return deps.DamageService.Heal(target, amount, self.Caster)
end

function CastContext.Status(
	_self: any,
	target: Model,
	name: string,
	duration: number,
	data: { [string]: any }?
): boolean
	return deps.StatusService.Apply(target, name, duration, data)
end

function CastContext.ForceMove(_self: any, target: Model, packet: any)
	deps.MovementService.Send(target, packet)
end

function CastContext.AddUlt(_self: any, model: Model, amount: number)
	local cur = model:GetAttribute("Ult")
	if type(cur) == "number" then
		model:SetAttribute("Ult", DamageMath.AddUlt(cur, amount))
	end
end

function CastContext.Projectile(self: any, spec: { [string]: any }): number
	local root = self.Root
	local origin: CFrame
	if typeof(spec.Origin) == "CFrame" then
		origin = spec.Origin
	else
		local start = (if root then root.CFrame.Position else self.Aim) + Vector3.new(0, 1, 0) + self.FlatDir * 1.5
		local dir = Validation.Unit(self.Aim - start, self.AimDir)
		origin = HazardDefs.LookAlong(start, dir)
	end
	local params: { [string]: any } = {
		origin = origin,
		speed = spec.Speed or 80,
		radius = spec.Radius or 0.6,
		maxDist = spec.MaxDist or spec.Range or (if self.Ability.Range then self.Ability.Range else 60),
		delay = spec.Delay or 0,
		gravity = spec.Gravity or 0,
		visual = spec.Visual or "Orb",
		damage = spec.Damage or 0,
		kr = spec.KR or 0,
		color = spec.Color or "White",
		stun = spec.Stun or 0,
		knockback = spec.Knockback or 0,
		pierce = spec.Pierce == true,
		undodgeable = spec.Undodgeable == true,
		style = spec.Style,
	}
	return self:Hazard("Projectile", params, spec.Hooks)
end

---------------------------------------------------------------------------------------------------
-- Targeting

function CastContext.IsEnemy(self: any, model: Model): boolean
	return Teams.AreEnemies(self.Caster, model)
end

function CastContext.Enemies(self: any, includeDowned: boolean?): { Model }
	local out: { Model } = {}
	for _, m in Validation.Combatants() do
		if m ~= self.Caster and Teams.AreEnemies(self.Caster, m) then
			if (includeDowned and Validation.IsAlive(m)) or Validation.IsUp(m) then
				table.insert(out, m)
			end
		end
	end
	return out
end

function CastContext.Allies(self: any, includeSelf: boolean?): { Model }
	local out: { Model } = {}
	for _, m in Validation.Combatants() do
		if Validation.IsUp(m) and Teams.AreAllies(self.Caster, m) then
			if m ~= self.Caster or includeSelf then
				table.insert(out, m)
			end
		end
	end
	return out
end

function CastContext.EnemiesInRadius(self: any, pos: Vector3, radius: number, includeDowned: boolean?): { Model }
	local out: { Model } = {}
	for _, m in self:Enemies(includeDowned) do
		local p = Validation.RootPosition(m)
		if p and (p - pos).Magnitude <= radius then
			table.insert(out, m)
		end
	end
	return out
end

function CastContext.NearestEnemy(self: any, pos: Vector3, maxDist: number, cone: Vector3?, coneDot: number?): Model?
	local best: Model? = nil
	local bestDist = maxDist
	local coneFlat = if cone then flatUnit(cone, Vector3.zero) else nil
	for _, m in self:Enemies(false) do
		local p = Validation.RootPosition(m)
		if p then
			local d = (p - pos).Magnitude
			if d <= bestDist then
				local ok = true
				if coneFlat and coneFlat.Magnitude > 0 then
					local to = flatUnit(p - pos, coneFlat)
					ok = to:Dot(coneFlat) >= (coneDot or 0.5)
				end
				if ok then
					best = m
					bestDist = d
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------------------------------------------
-- Movement

function CastContext.RootPosition(self: any): Vector3
	local root = self.Root
	if root and root.Parent then
		return root.CFrame.Position
	end
	return self.Aim
end

function CastContext.RootHeight(self: any): number
	local hum = self.Humanoid
	local root = self.Root
	local hip = if hum then hum.HipHeight else 2
	local half = if root then root.Size.Y * 0.5 else 1
	return hip + half
end

function CastContext.GroundAt(_self: any, pos: Vector3, maxDrop: number?): Vector3?
	return Validation.GroundBelow(pos + Vector3.new(0, 3, 0), (maxDrop or 40) + 3)
end

function CastContext.LookFrame(self: any, pos: Vector3?, dir: Vector3?): CFrame
	return HazardDefs.LookAlong(pos or self:RootPosition(), flatUnit(dir or self.FlatDir, self.FlatDir))
end

local MAX_GROUND_DROP = 20

function CastContext.Teleport(self: any, cframe: CFrame): CFrame?
	local root = self.Root
	if root == nil or root.Parent == nil or typeof(cframe) ~= "CFrame" then
		return nil
	end
	local from = root.CFrame.Position
	local rootHeight = self:RootHeight()
	local dest = cframe.Position
	-- 1) no walls between: ray at body height from the current root to the destination's body height
	local destBody = Vector3.new(dest.X, math.max(dest.Y, from.Y - rootHeight) + rootHeight * 0.5, dest.Z)
	local delta = destBody - from
	if delta.Magnitude > 0.05 then
		local hit = Validation.Raycast(from, delta)
		if hit then
			local back = delta.Unit * 1.5
			local clamped = hit.Position - back
			if (clamped - from):Dot(delta) <= 0 then
				clamped = from
			end
			destBody = clamped
		end
	end
	-- 2) ground below within MAX_GROUND_DROP; else walk back along the path to the last valid point
	local function groundAt(p: Vector3): Vector3?
		return Validation.GroundBelow(p + Vector3.new(0, 1, 0), MAX_GROUND_DROP + rootHeight + 1)
	end
	local ground = groundAt(destBody)
	if ground == nil then
		for i = 1, 10 do
			local p = destBody:Lerp(from, i / 10)
			ground = groundAt(p)
			if ground then
				break
			end
		end
	end
	if ground == nil then
		return nil
	end
	local finalPos = ground + Vector3.new(0, rootHeight + 0.05, 0)
	local look = flatUnit(cframe.LookVector, self.FlatDir)
	local final = HazardDefs.LookAlong(finalPos, look)
	deps.MovementService.Teleport(self.Caster, final)
	self:Fx("Teleport", { from = from, to = finalPos })
	return final
end

return CastContext
