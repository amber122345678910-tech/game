--!strict
-- HazardService (P15): spawns hazards, samples Shared/Combat/HazardDefs every Heartbeat against character
-- capsules, applies hits, broadcasts packets (SPEC §7.6, §17).
--
-- Spawn(owner, team, hazardType, params, hooks?) -> id (0 on failure)
--   * params are validated (HazardDefs.Validate), normalized (every documented default filled in) and
--     must be plain data; they are broadcast to all clients in Net "Hazard" {id, type, t0, owner, team, params}
--     with t0 = workspace:GetServerTimeNow(). Clients compute the same geometry from (params, now - t0).
--   * hooks (server only, never sent): { OnHit = fn(target, hazardId) -> boolean? (true = skip the default
--     effect), OnTick = fn(t), OnEnd = fn() }
--   * at most MAX_HAZARDS (40, SPEC §14) live at once: the oldest hazard whose damage window is over is
--     evicted first, else the oldest overall.
-- Sampling: each frame the hazard is sampled at sub-steps of <= 1/60 s (max 4) so fast projectiles cannot
-- tunnel through a character on a slow server frame. Hit volumes are shrunk by Config.Combat.HazardForgiveness
-- (HitTest.Hits). HitPolicy (Once / Interval / PerKey) is tracked per target (and per Volume.Key).
-- A hit that the colour rule or i-frames ignored is NOT consumed (a still player inside a blue wall who starts
-- moving gets hit; a dash through a beam is safe only while the i-frames last).
-- Default effect: DamageService.Apply { Attacker = owner (if still present), AttackerTeam = team,
--   Kind = HazardDefs.DamageKind (Beam / Projectile / Area or params.kind), Amount = params.damage
--   (Orb: implodeDamage), KR = kr, Color = color, Dodgeable = dodgeable, Undodgeable = undodgeable,
--   Blockable = blockable, Stun = stun, Knockback = HazardDefs.KnockbackDir * knockback + Y * knockbackUp }
-- Zone effects: "Damage" (Apply amount per tick), "Heal" (DamageService.Heal amount, CleanseKR cleanseKR),
--   "Slow" (Slowed {mult = amount}), "Mark" (Marked for amount s); `affects` picks Enemies/Allies/All.
-- Orb pull: ForceMove "Pull" toward the centre at pullStrength studs/s, 5 Hz, enemies inside radius.
-- Projectiles (Projectile / BoneProjectile) with pierce = false end on their first consumed hit.
-- Early ends (Remove / Clear / projectile hit / eviction) broadcast Net "HazardEnd" (id); natural expiry
-- does not (clients end at t0 + HazardDefs[type].Duration(params)).
--
-- API
--   HazardService.Spawn(owner: Model?, team: string?, hazardType: string, params, hooks?) -> number
--   HazardService.Remove(id: number)        HazardService.Clear()
--   HazardService.Get(id) -> record?         HazardService.Count() -> number
--   HazardService.HazardHit: Signal(id, target, result?)   HazardService.Ended: Signal(id)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Config = require(Shared.Config) :: any
local Net = require(Shared.Net) :: any
local Signal = require(Shared.Util.Signal) :: any
local Teams = require(Shared.Combat.Teams) :: any
local HitTest = require(Shared.Combat.HitTest) :: any
local HazardDefs = require(Shared.Combat.HazardDefs) :: any

local Validation = require(script.Parent.Parent.Combat.Validation) :: any

local HazardService = {}
HazardService.Priority = 15
HazardService.HazardHit = Signal.new()
HazardService.Ended = Signal.new()

local MAX_HAZARDS = 40
local SUBSTEP = 1 / 60
local MAX_SUBSTEPS = 4
local PULL_RATE = 0.2

local DamageService: any = nil
local StatusService: any = nil
local MovementService: any = nil

export type Hooks = {
	OnHit: ((Model, number) -> boolean?)?,
	OnTick: ((number) -> ())?,
	OnEnd: (() -> ())?,
}

type Record = {
	Id: number,
	Type: string,
	Def: any,
	Params: { [string]: any },
	T0: number,
	Owner: Model?,
	Team: string,
	Duration: number,
	ActiveEnd: number,
	Policy: { Once: boolean, Interval: number?, PerKey: boolean? },
	Hooks: Hooks,
	Hits: { [Model]: { [number]: number } },
	LastT: number,
	NextEffect: number,
	Ended: boolean,
}

type Target = { Model: Model, Capsule: any, Team: string, Position: Vector3 }

local active: { [number]: Record } = {}
local order: { number } = {}
local nextId = 0

---------------------------------------------------------------------------------------------------
-- Lifecycle of a record

local function endRecord(rec: Record, broadcast: boolean)
	if rec.Ended then
		return
	end
	rec.Ended = true
	active[rec.Id] = nil
	local i = table.find(order, rec.Id)
	if i then
		table.remove(order, i)
	end
	if broadcast then
		Net.Server.FireAll("HazardEnd", rec.Id)
	end
	local onEnd = rec.Hooks.OnEnd
	if onEnd then
		local ok, err = pcall(onEnd)
		if not ok then
			warn(("[HazardService] OnEnd of %s #%d failed: %s"):format(rec.Type, rec.Id, tostring(err)))
		end
	end
	HazardService.Ended:Fire(rec.Id)
end

local function evictOne(now: number)
	-- prefer a hazard whose damage window is over (only visuals left)
	for _, id in order do
		local rec = active[id]
		if rec and now - rec.T0 > rec.ActiveEnd then
			endRecord(rec, true)
			return
		end
	end
	local oldest = order[1]
	if oldest and active[oldest] then
		warn("[HazardService] hazard cap reached; ending the oldest hazard early")
		endRecord(active[oldest], true)
	end
end

local function stripNonPlain(params: { [string]: any })
	for _ = 1, 64 do
		local ok, bad = HazardDefs.IsPlainData(params)
		if ok or bad == nil then
			return
		end
		warn(("[HazardService] param %s is not plain data and was removed"):format(tostring(bad)))
		params[bad] = nil
	end
end

function HazardService.Spawn(owner: Model?, team: string?, hazardType: string, params: { [string]: any }, hooks: Hooks?): number
	local def = HazardDefs.Get(hazardType)
	if def == nil then
		warn("[HazardService] unknown hazard type " .. tostring(hazardType))
		return 0
	end
	if type(params) ~= "table" then
		warn("[HazardService] params must be a table")
		return 0
	end
	local ok, err = HazardDefs.Validate(hazardType, params)
	if not ok then
		warn(("[HazardService] invalid %s params: %s"):format(hazardType, tostring(err)))
		return 0
	end
	local p = HazardDefs.Normalize(hazardType, params)
	stripNonPlain(p)

	local ownerModel: Model? = nil
	if typeof(owner) == "Instance" and (owner :: Instance):IsA("Model") then
		ownerModel = owner
	end
	local teamName = if type(team) == "string" and team ~= "" then team else Teams.TeamOf(ownerModel)

	local now = Validation.Now()
	while #order >= MAX_HAZARDS do
		local before = #order
		evictOne(now)
		if #order >= before then
			break
		end
	end

	nextId += 1
	local id = nextId
	local _, activeEnd = HazardDefs.ActiveWindow(hazardType, p)
	local rec: Record = {
		Id = id,
		Type = hazardType,
		Def = def,
		Params = p,
		T0 = now,
		Owner = ownerModel,
		Team = teamName,
		Duration = def.Duration(p),
		ActiveEnd = activeEnd,
		Policy = def.HitPolicy(p),
		Hooks = hooks or {},
		Hits = {},
		LastT = 0,
		NextEffect = 0,
		Ended = false,
	}
	active[id] = rec
	table.insert(order, id)
	Net.Server.FireAll("Hazard", {
		id = id,
		type = hazardType,
		t0 = now,
		owner = ownerModel,
		team = teamName,
		params = p,
	})
	return id
end

function HazardService.Remove(id: number)
	local rec = active[id]
	if rec then
		endRecord(rec, true)
	end
end

function HazardService.Clear()
	for _, id in table.clone(order) do
		local rec = active[id]
		if rec then
			endRecord(rec, true)
		end
	end
end

function HazardService.Get(id: number): Record?
	return active[id]
end

function HazardService.Count(): number
	return #order
end

---------------------------------------------------------------------------------------------------
-- Hits

local function affects(rec: Record, target: Target): boolean
	if rec.Type == "Zone" then
		local who = rec.Params.affects
		if who == "Allies" then
			return Teams.AreAllyTeams(rec.Team, target.Team)
		elseif who == "All" then
			return target.Team ~= ""
		end
	end
	return Teams.AreEnemyTeams(rec.Team, target.Team)
end

local function ownerIfPresent(rec: Record): Model?
	local o = rec.Owner
	if o and o.Parent ~= nil then
		return o
	end
	return nil
end

local function knockbackFor(rec: Record, target: Target, t: number): Vector3?
	local p = rec.Params
	local kb = if type(p.knockback) == "number" then p.knockback else 0
	local up = if type(p.knockbackUp) == "number" then p.knockbackUp else 0
	if kb == 0 and up == 0 then
		return nil
	end
	local dir = HazardDefs.KnockbackDir(rec.Type, p, t, target.Position)
	return dir * kb + Vector3.new(0, up, 0)
end

local function damageInfo(rec: Record, target: Target, t: number, amount: number, volume: any): { [string]: any }
	local p = rec.Params
	return {
		Attacker = ownerIfPresent(rec),
		AttackerTeam = rec.Team,
		Target = target.Model,
		Amount = amount,
		Kind = HazardDefs.DamageKind(rec.Type, p),
		Ability = if type(p.ability) == "string" and p.ability ~= "" then p.ability else nil,
		Color = p.color,
		KR = if type(p.kr) == "number" then p.kr else 0,
		Dodgeable = p.dodgeable ~= false,
		Undodgeable = p.undodgeable == true,
		Blockable = if type(p.blockable) == "boolean" then p.blockable else nil,
		Stun = if type(p.stun) == "number" and p.stun > 0 then p.stun else nil,
		Knockback = knockbackFor(rec, target, t),
		Position = volume.CFrame.Position,
	}
end

-- Returns (result?, consumed)
local function defaultEffect(rec: Record, target: Target, t: number, volume: any): (any?, boolean)
	local p = rec.Params
	if rec.Type == "Zone" then
		local effect = p.effect
		local amount = if type(p.amount) == "number" then p.amount else 0
		if effect == "Heal" then
			local healed = DamageService.Heal(target.Model, amount, ownerIfPresent(rec), { Silent = false })
			local cleanse = if type(p.cleanseKR) == "number" then p.cleanseKR else 0
			if cleanse > 0 then
				DamageService.CleanseKR(target.Model, cleanse)
			end
			return { Healed = healed }, true
		elseif effect == "Slow" then
			local interval = rec.Policy.Interval or 0.5
			StatusService.Apply(target.Model, "Slowed", interval + 0.2, { mult = amount })
			return nil, true
		elseif effect == "Mark" then
			StatusService.Apply(target.Model, "Marked", math.max(0.1, amount))
			return nil, true
		end
		local result = DamageService.Apply(damageInfo(rec, target, t, amount, volume))
		return result, result.Reason ~= "Color" and result.Reason ~= "Immune"
	end
	local amount = if type(p.damage) == "number" then p.damage else 0
	if rec.Type == "Orb" and type(p.implodeDamage) == "number" then
		amount = p.implodeDamage
	end
	local result = DamageService.Apply(damageInfo(rec, target, t, amount, volume))
	local consumed = result.Reason ~= "Color" and result.Reason ~= "Immune"
	return result, consumed
end

local function tryHit(rec: Record, target: Target, volume: any, t: number, now: number)
	local key = if rec.Policy.PerKey then (volume.Key or 0) else 0
	local log = rec.Hits[target.Model]
	local last = if log then log[key] else nil
	if last ~= nil then
		if rec.Policy.Once then
			return
		end
		local interval = rec.Policy.Interval or math.huge
		if now - last < interval then
			return
		end
	end
	local skipDefault = false
	local onHit = rec.Hooks.OnHit
	if onHit then
		local ok, ret = pcall(onHit, target.Model, rec.Id)
		if not ok then
			warn(("[HazardService] OnHit of %s #%d failed: %s"):format(rec.Type, rec.Id, tostring(ret)))
		elseif ret == true then
			skipDefault = true
		end
	end
	local result: any = nil
	local consumed = true
	if not skipDefault then
		result, consumed = defaultEffect(rec, target, t, volume)
	end
	if consumed then
		local l = log or {}
		rec.Hits[target.Model] = l
		l[key] = now
	end
	HazardService.HazardHit:Fire(rec.Id, target.Model, result)
	if consumed and HazardDefs.IsProjectile(rec.Type) and rec.Params.pierce ~= true then
		endRecord(rec, true)
	end
end

local function applyEffects(rec: Record, t: number, now: number, targets: { Target })
	if rec.Type ~= "Orb" or now < rec.NextEffect then
		return
	end
	rec.NextEffect = now + PULL_RATE
	local eff = HazardDefs.Effect(rec.Type, rec.Params, t)
	if eff == nil or eff.Kind ~= "Pull" or eff.Strength <= 0 then
		return
	end
	for _, target in targets do
		if Teams.AreEnemyTeams(rec.Team, target.Team) then
			local delta = Vector3.new(eff.Center.X - target.Position.X, 0, eff.Center.Z - target.Position.Z)
			local dist = delta.Magnitude
			if dist <= eff.Radius and dist > 1.5 then
				MovementService.Send(target.Model, {
					kind = "Pull",
					target = eff.Center,
					velocity = delta.Unit * eff.Strength,
					duration = PULL_RATE + 0.05,
				})
			end
		end
	end
end

local function gatherTargets(): { Target }
	local out: { Target } = {}
	for _, model in Validation.Combatants() do
		if Validation.IsAlive(model) then
			local cap = Validation.Capsule(model)
			local pos = Validation.RootPosition(model)
			if cap and pos then
				table.insert(out, { Model = model, Capsule = cap, Team = Teams.TeamOf(model), Position = pos })
			end
		end
	end
	return out
end

local function sample(rec: Record, ts: number, now: number, targets: { Target }, forgiveness: number)
	local vols = rec.Def.Volumes(rec.Params, ts)
	if #vols == 0 then
		return
	end
	for _, target in targets do
		if rec.Ended then
			return
		end
		if affects(rec, target) then
			for _, vol in vols do
				if HitTest.MayOverlap(target.Capsule, vol) and HitTest.Hits(target.Capsule, vol, forgiveness) then
					tryHit(rec, target, vol, ts, now)
					if not rec.Policy.PerKey or rec.Ended then
						break
					end
				end
			end
		end
	end
end

local function step(_dt: number)
	if #order == 0 then
		return
	end
	local now = Validation.Now()
	local targets: { Target }? = nil
	local forgiveness = Config.Combat.HazardForgiveness
	for _, id in table.clone(order) do
		local rec = active[id]
		if rec and not rec.Ended then
			local t = now - rec.T0
			if t >= rec.Duration then
				endRecord(rec, false)
			else
				local onTick = rec.Hooks.OnTick
				if onTick then
					local ok, err = pcall(onTick, t)
					if not ok then
						warn(("[HazardService] OnTick of %s #%d failed: %s"):format(rec.Type, rec.Id, tostring(err)))
					end
				end
				if not rec.Ended then
					local list = targets or gatherTargets()
					targets = list
					applyEffects(rec, t, now, list)
					local prev = math.min(rec.LastT, t)
					local span = t - prev
					local steps = if span > SUBSTEP then math.min(MAX_SUBSTEPS, math.ceil(span / SUBSTEP)) else 1
					for s = 1, steps do
						if rec.Ended then
							break
						end
						local ts = if steps == 1 then t else prev + span * s / steps
						sample(rec, ts, now, list, forgiveness)
					end
					rec.LastT = t
				end
			end
		end
	end
end

-- Exposed for tests / tools: run one sampling step synchronously.
HazardService._Step = step

function HazardService.Init()
	DamageService = require(script.Parent.DamageService) :: any
	StatusService = require(script.Parent.StatusService) :: any
	MovementService = require(script.Parent.MovementService) :: any
end

function HazardService.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[HazardService] step failed: " .. tostring(err))
		end
	end)
end

return HazardService
