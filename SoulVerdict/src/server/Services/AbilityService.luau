--!strict
-- AbilityService (P30): ability casting, cooldowns, blocking and dashing (SPEC §7.2, §7.3, §17).
--
-- Net "Cast" (abilityId, payload): validated per player (rate limit Config.Combat.CastRateLimit, caster up
--   and not Stunned/Boxed, Silenced blocks everything but M1, ability in the caster's kit, cooldown ready
--   (0.08 s latency tolerance), Ult >= 100 for ultimates (set to 0), Hold charge clamped to the time the
--   ability has been ready (ClampCharge vs Hold.MaxTime), aim clamped to Range + Config.Combat.AimSlack
--   (MaxAimRange for range-less abilities), Aim "Target"/"Ally" target checks (living enemy/ally within
--   range + slack, roughly in front, enemies not Invisible; "Target" falls back to the nearest visible enemy in a
--   cone, "Ally" to self),
--   M1 combos (ComboIndex 1..Combo while casts follow within Numbers.ComboWindow)). Then: the monster's first
--   ultimate of a round starts its Phase 2 (startPhaseTwo -> RoundService.TriggerFinalPhase("Ult", model), before
--   the bar is spent; the Start packet then carries data.phase2 = true and the ult runs normally), cooldown set
--   (Net "Cooldown" to the caster + model attribute "Cooldown_<abilityId>" = endsAt for spectator/Studious
--   UI), AbilityFx {phase = "Start"} to everyone, Casted signal, and the kit handler
--   ServerKits[kitId].Abilities[abilityId](ctx) in its own thread (xpcall). A rejected cast answers the
--   caster with "Cooldown"(abilityId, realEndsAt) so a predicted client cooldown can roll back.
-- Missing handler: M1 abilities with Numbers.Damage1 fall back to Kits/Common.ComboStrike; others warn once.
-- Pseudo-ability "VerdictBox" (monsters, slot F): Config.VerdictBox cooldown/range/cone + line of sight, never an
--   Invisible human -> VerdictBoxService.Start(monster, target) (if that service exists).
-- Net "Block" (isBlocking): humans only; sets attributes Blocking and BlockStart (server time; 0 = this
--   block cannot parry because the previous block ended < PARRY_RETRY s ago — anti parry-spam).
-- Net "Dash" (direction, castId?): humans only; needs DashCharges >= 1; grants IFrames Config.Human.DashIFrames and
--   MovementService.Dash(..., echo = true) (the owner client may already be dashing: echo packets confirm). The
--   AbilityFx "Dash" echo carries the client's castId so the owner's AnimController skips its predicted clip.
-- Kit lifecycle: on CharacterService.Spawned the kit's OnSpawn(model, ctxFactory) runs (ctxFactory(abilityId?)
--   -> CastContext for passives); OnDespawn(model) runs once on death/despawn; active casts are cancelled.
--
-- API
--   AbilityService.CastAs(model, abilityId, payload?) -> (boolean, string?)   bots (same validation, no player)
--   AbilityService.BlockAs(model, on) / AbilityService.DashAs(model, direction, echo?, castId?) -> boolean
--   AbilityService.SetCooldown(model, abilityId, seconds)
--   AbilityService.GetCooldowns(model) -> {[string]: number}     abilityId -> endsAt (server time)
--   AbilityService.ResetCooldowns(model)
--   AbilityService.ScaleCooldowns(model, mult, duration)          cooldowns progress at `mult` speed for duration
--   AbilityService.GetServerKit(kitId) -> table?
--   AbilityService.ContextFor(model, abilityId?) -> CastContext?  passive / scripted contexts
--   AbilityService.Casted: Signal(model, abilityId)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Config = require(Shared.Config) :: any
local Net = require(Shared.Net) :: any
local Kits = require(Shared.Kits) :: any
local Signal = require(Shared.Util.Signal) :: any
local Trove = require(Shared.Util.Trove) :: any
local Teams = require(Shared.Combat.Teams) :: any
local DamageMath = require(Shared.Combat.DamageMath) :: any

local Validation = require(script.Parent.Parent.Combat.Validation) :: any
local CastContext = require(script.Parent.Parent.Combat.CastContext) :: any

local AbilityService = {}
AbilityService.Priority = 30
AbilityService.Casted = Signal.new()

local COOLDOWN_TOLERANCE = 0.08
local HOLD_TOLERANCE = 0.15
local PARRY_RETRY = 0.45
local TARGET_MIN_DOT = -0.2 -- "roughly in front" of the caster's aim
local MAX_ID_LENGTH = 48
local VERDICT_ID = "VerdictBox"

local StatusService: any = nil
local DamageService: any = nil
local HazardService: any = nil
local MovementService: any = nil

type ComboState = { Index: number, Last: number }
type ModelState = {
	Cooldowns: { [string]: number },
	Combo: { [string]: ComboState },
	Scale: { Mult: number, Until: number }?,
	Casts: { [any]: boolean },
	LastBlockEnd: number,
	LastDash: number,
	SpawnTime: number,
	Trove: any,
	Despawned: boolean,
}

local states: { [Model]: ModelState } = setmetatable({}, { __mode = "k" }) :: any
local lastCast: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastBlockToggle: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local serverKits: { [string]: any } = {}
local warned: { [string]: boolean } = {}
local Common: any = nil

local function now(): number
	return Validation.Now()
end

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(message)
	end
end

local function stateOf(model: Model): ModelState
	local st = states[model]
	if st then
		return st
	end
	local created: ModelState = {
		Cooldowns = {},
		Combo = {},
		Scale = nil,
		Casts = {},
		LastBlockEnd = -math.huge,
		LastDash = -math.huge,
		SpawnTime = now(),
		Trove = Trove.new(),
		Despawned = false,
	}
	states[model] = created
	return created
end

---------------------------------------------------------------------------------------------------
-- Server kit modules

local function getCommon(): any
	if Common == nil then
		local folder = script.Parent.Parent:FindFirstChild("Kits")
		local module = folder and folder:FindFirstChild("Common")
		if module then
			local ok, result = pcall(require, module)
			Common = if ok then result else false
			if not ok then
				warn("[AbilityService] Kits/Common failed to load: " .. tostring(result))
			end
		else
			Common = false
		end
	end
	return Common or nil
end

function AbilityService.GetServerKit(kitId: string): any?
	local cached = serverKits[kitId]
	if cached ~= nil then
		return cached or nil
	end
	local result: any = false
	local folder = script.Parent.Parent:FindFirstChild("Kits")
	local module = folder and folder:FindFirstChild(kitId)
	if module and module:IsA("ModuleScript") then
		local ok, value = xpcall(require, debug.traceback, module)
		if ok and type(value) == "table" then
			result = value
		else
			warn(("[AbilityService] server kit %s failed to load:\n%s"):format(kitId, tostring(value)))
		end
	end
	serverKits[kitId] = result
	return result or nil
end

local function handlerFor(kit: any, ability: any): ((any) -> ())?
	local serverKit = AbilityService.GetServerKit(kit.Id)
	if serverKit and type(serverKit.Abilities) == "table" then
		local fn = serverKit.Abilities[ability.Id]
		if type(fn) == "function" then
			return fn
		end
	end
	local common = getCommon()
	if
		common
		and ability.Slot == "M1"
		and type(ability.Numbers.Damage1) == "number"
		and type(common.ComboStrike) == "function"
	then
		return common.ComboStrike
	end
	warnOnce(kit.Id .. "." .. ability.Id, ("[AbilityService] no server handler for %s.%s"):format(kit.Id, ability.Id))
	return nil
end

---------------------------------------------------------------------------------------------------
-- Cooldowns

local function fireCooldown(model: Model, player: Player?, abilityId: string, endsAt: number)
	if model.Parent ~= nil then
		model:SetAttribute("Cooldown_" .. abilityId, if endsAt > now() then endsAt else nil)
	end
	local p = player or Validation.GetPlayer(model)
	if p and p.Parent then
		Net.Server.Fire("Cooldown", p, abilityId, endsAt)
	end
end

local function setCooldownInternal(model: Model, player: Player?, abilityId: string, seconds: number)
	local st = stateOf(model)
	local t = now()
	local endsAt = t + math.max(0, seconds)
	local scale = st.Scale
	if scale and scale.Until > t and seconds > 0 then
		endsAt = DamageMath.ScaledCooldownEnd(t, seconds, scale.Until - t, scale.Mult)
	end
	st.Cooldowns[abilityId] = endsAt
	fireCooldown(model, player, abilityId, endsAt)
end

function AbilityService.SetCooldown(model: Model, abilityId: string, seconds: number)
	if typeof(model) ~= "Instance" or type(abilityId) ~= "string" or type(seconds) ~= "number" then
		return
	end
	setCooldownInternal(model, nil, abilityId, seconds)
end

function AbilityService.GetCooldowns(model: Model): { [string]: number }
	local st = states[model]
	if st == nil then
		return {}
	end
	return table.clone(st.Cooldowns)
end

function AbilityService.ResetCooldowns(model: Model)
	local st = states[model]
	if st == nil then
		return
	end
	local ids = {}
	for id in st.Cooldowns do
		table.insert(ids, id)
	end
	table.clear(st.Cooldowns)
	for _, id in ids do
		fireCooldown(model, nil, id, 0)
	end
end

function AbilityService.ScaleCooldowns(model: Model, mult: number, duration: number)
	if type(mult) ~= "number" or mult ~= mult or type(duration) ~= "number" or duration <= 0 then
		return
	end
	local st = stateOf(model)
	local t = now()
	local m = math.clamp(mult, 0.05, 10)
	local newUntil = t + duration
	local from = t
	local scale = st.Scale
	if scale and scale.Until > t and math.abs(scale.Mult - m) < 1e-6 then
		from = scale.Until -- [t, scale.Until] is already accounted for
	end
	if newUntil <= from then
		return
	end
	for id, endsAt in st.Cooldowns do
		if endsAt > from then
			local newEnd = DamageMath.ScaledCooldownEnd(from, endsAt - from, newUntil - from, m)
			if math.abs(newEnd - endsAt) > 1e-3 then
				st.Cooldowns[id] = newEnd
				fireCooldown(model, nil, id, newEnd)
			end
		end
	end
	st.Scale = { Mult = m, Until = newUntil }
end

---------------------------------------------------------------------------------------------------
-- Payload sanitising

type Payload = { aim: Vector3?, dir: Vector3?, charge: number?, target: Model?, castId: number }

local function sanitizePayload(raw: any): Payload
	local p: Payload = { aim = nil, dir = nil, charge = nil, target = nil, castId = 0 }
	if type(raw) ~= "table" then
		return p
	end
	if Net.Check.Vector3(raw.aim) then
		p.aim = raw.aim
	end
	if Net.Check.Vector3(raw.dir) and (raw.dir :: Vector3).Magnitude > 1e-4 then
		p.dir = (raw.dir :: Vector3).Unit
	end
	if Net.Check.Number(raw.charge, -1, 2) then
		p.charge = raw.charge
	end
	if typeof(raw.target) == "Instance" and (raw.target :: Instance):IsA("Model") then
		p.target = raw.target
	end
	if Net.Check.Number(raw.castId, 0, 2 ^ 31) then
		p.castId = math.floor(raw.castId)
	end
	return p
end

---------------------------------------------------------------------------------------------------
-- Targets

local function inFront(origin: Vector3, dir: Vector3, pos: Vector3, minDot: number): boolean
	local to = Validation.FlatUnit(pos - origin, Vector3.zero)
	if to.Magnitude < 1e-4 then
		return true
	end
	return to:Dot(Validation.FlatUnit(dir, to)) >= minDot
end

-- Invisible (Patience stealth, Eclipse VoidStep): the attribute, or a Status_Invisible the server still holds.
local function isInvisible(model: Model): boolean
	return model:GetAttribute("Invisible") == true or StatusService.Has(model, "Invisible")
end

local function validTarget(
	caster: Model,
	target: Model?,
	wantEnemy: boolean,
	origin: Vector3,
	dir: Vector3,
	maxDist: number
): boolean
	if target == nil or target == caster or not Validation.IsUp(target) then
		return false
	end
	if wantEnemy then
		if not Teams.AreEnemies(caster, target) or isInvisible(target) then
			return false
		end
	elseif not Teams.AreAllies(caster, target) then
		return false
	end
	local pos = Validation.RootPosition(target)
	if pos == nil or (pos - origin).Magnitude > maxDist then
		return false
	end
	return inFront(origin, dir, pos, TARGET_MIN_DOT)
end

local function autoTarget(caster: Model, origin: Vector3, dir: Vector3, aim: Vector3, maxDist: number): Model?
	-- nearest-to-the-aim enemy in a forward cone
	local best: Model? = nil
	local bestScore = math.huge
	for _, m in Validation.Combatants() do
		if m ~= caster and Validation.IsUp(m) and Teams.AreEnemies(caster, m) and not isInvisible(m) then
			local pos = Validation.RootPosition(m)
			if pos and (pos - origin).Magnitude <= maxDist and inFront(origin, dir, pos, 0.5) then
				local score = (pos - aim).Magnitude
				if score < bestScore then
					bestScore = score
					best = m
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------------------------------------------
-- Blocking

local function setBlocking(model: Model, on: boolean)
	local st = stateOf(model)
	local t = now()
	if on then
		if model:GetAttribute("Blocking") == true then
			return
		end
		local start = if t - st.LastBlockEnd >= PARRY_RETRY then t else 0
		model:SetAttribute("BlockStart", start)
		model:SetAttribute("Blocking", true)
	else
		if model:GetAttribute("Blocking") ~= true then
			return
		end
		model:SetAttribute("Blocking", false)
		model:SetAttribute("BlockStart", 0)
		st.LastBlockEnd = t
	end
	StatusService.RecomputeMovement(model)
end

function AbilityService.BlockAs(model: Model, on: boolean): boolean
	if Validation.Role(model) ~= "Human" then
		return false
	end
	if on then
		if not StatusService.CanAct(model) then
			return false
		end
		local guard = model:GetAttribute("Guard")
		if type(guard) == "number" and guard <= 0 then
			return false
		end
	end
	setBlocking(model, on)
	return true
end

---------------------------------------------------------------------------------------------------
-- Dashing

function AbilityService.DashAs(model: Model, direction: Vector3, echo: boolean?, castId: number?): boolean
	if Validation.Role(model) ~= "Human" or not StatusService.CanAct(model) then
		return false
	end
	if StatusService.Has(model, "Rooted") then
		return false
	end
	local st = stateOf(model)
	local t = now()
	if t - st.LastDash < Config.Human.DashTime then
		return false
	end
	local charges = model:GetAttribute("DashCharges")
	if type(charges) ~= "number" or charges < 1 then
		return false
	end
	st.LastDash = t
	model:SetAttribute("DashCharges", charges - 1)
	if model:GetAttribute("Blocking") == true then
		setBlocking(model, false)
	end
	local dir = Validation.FlatUnit(direction, Validation.Look(model))
	StatusService.Apply(model, "IFrames", Config.Human.DashIFrames)
	MovementService.Dash(model, dir, Config.Human.DashDistance, Config.Human.DashTime, echo)
	Net.Server.FireAll("AbilityFx", {
		caster = model,
		kit = model:GetAttribute("KitId") or "",
		ability = "Dash",
		phase = "Start",
		castId = castId or 0,
		t0 = t,
		dir = dir,
	})
	return true
end

---------------------------------------------------------------------------------------------------
-- Casting

local function runHandler(handler: (any) -> (), ctx: any, st: ModelState)
	st.Casts[ctx] = true
	local ok, err = xpcall(handler, debug.traceback, ctx)
	st.Casts[ctx] = nil
	if not ok then
		warn(
			("[AbilityService] %s.%s failed:\n%s"):format(ctx.Kit and ctx.Kit.Id or "?", ctx.Ability.Id, tostring(err))
		)
	end
end

-- The monster's FIRST ultimate of a round starts its Phase 2: RoundService.TriggerFinalPhase("Ult", model), called
-- while the cast commits (after every check passed, before the ult bar is set to 0). Cheap pre-checks here (monster
-- team, Round/Collapse, RoundState.FinalPhase still false); RoundService checks that `model` is the round's monster.
-- Phase 2 started this way refills nothing (ult bar, dodges and Exhausted stay as they are: it is no reset button) and
-- never stops the caster (its short Invulnerable window, skipped while Exhausted, only blocks incoming hits), so the
-- ultimate below runs unchanged as the transformation's opening move. Human ultimates, casts outside fight phases
-- and every ultimate after Phase 2 began are untouched; the HP threshold (DamageService) stays the safety net.
local function startPhaseTwo(model: Model): boolean
	if Teams.TeamOf(model) ~= "Monster" or not Validation.InCombatPhase() then
		return false
	end
	if Validation.RoundAttr("FinalPhase") ~= false then
		return false
	end
	local rs = Validation.Service("RoundService")
	if rs == nil or type(rs.TriggerFinalPhase) ~= "function" then
		return false
	end
	local ok, started = pcall(rs.TriggerFinalPhase, "Ult", model)
	if not ok then
		warn("[AbilityService] TriggerFinalPhase failed: " .. tostring(started))
		return false
	end
	return started == true
end

local function castVerdictBox(model: Model, player: Player?, payload: Payload): (boolean, string?)
	if Teams.TeamOf(model) ~= "Monster" then
		return false, "role"
	end
	if StatusService.Has(model, "Silenced") then
		return false, "silenced"
	end
	local st = stateOf(model)
	local t = now()
	if t < (st.Cooldowns[VERDICT_ID] or 0) - COOLDOWN_TOLERANCE then
		return false, "cooldown"
	end
	local vbs = Validation.Service("VerdictBoxService")
	if vbs == nil or type(vbs.Start) ~= "function" then
		warnOnce("VerdictBoxService", "[AbilityService] VerdictBoxService missing: Verdict Box unavailable")
		return false, "unavailable"
	end
	local root = Validation.Root(model) :: BasePart
	local origin = root.CFrame.Position
	local dir = Validation.FlatUnit(payload.dir or Validation.Look(model), Validation.Look(model))
	local cfg = Config.VerdictBox
	local maxDist = cfg.Range + 2
	local function eligible(m: Model?): boolean
		if m == nil or not Validation.IsUp(m) or Teams.TeamOf(m) ~= "Humans" then
			return false
		end
		if StatusService.Has(m, "Boxed") or StatusService.Has(m, "Invulnerable") or isInvisible(m) then
			return false
		end
		local pos = Validation.RootPosition(m)
		if pos == nil or (pos - origin).Magnitude > maxDist then
			return false
		end
		if not inFront(origin, dir, pos, cfg.ConeDot) then
			return false
		end
		return Validation.LineOfSight(origin, pos)
	end
	local target: Model? = if eligible(payload.target) then payload.target else nil
	if target == nil then
		local bestDot = -math.huge
		for _, m in Validation.Combatants() do
			if eligible(m) then
				local pos = Validation.RootPosition(m) :: Vector3
				local d = Validation.FlatUnit(pos - origin, dir):Dot(dir)
				if d > bestDot then
					bestDot = d
					target = m
				end
			end
		end
	end
	if target == nil then
		return false, "notarget"
	end
	local ok, started = pcall(vbs.Start, model, target)
	if not ok or started ~= true then
		if not ok then
			warn("[AbilityService] VerdictBoxService.Start failed: " .. tostring(started))
		end
		return false, "failed"
	end
	setCooldownInternal(model, player, VERDICT_ID, cfg.Cooldown)
	Net.Server.FireAll("AbilityFx", {
		caster = model,
		kit = model:GetAttribute("KitId") or "",
		ability = VERDICT_ID,
		phase = "Start",
		castId = payload.castId,
		t0 = t,
		dir = dir,
		data = { target = target },
	})
	AbilityService.Casted:Fire(model, VERDICT_ID)
	return true, nil
end

local function tryCast(model: Model, player: Player?, abilityId: string, payload: Payload): (boolean, string?)
	if not Validation.IsUp(model) then
		return false, "dead"
	end
	if StatusService.Has(model, "Stunned") or StatusService.Has(model, "Boxed") then
		return false, "stunned"
	end
	if abilityId == VERDICT_ID then
		return castVerdictBox(model, player, payload)
	end
	local kit = Validation.Kit(model)
	if kit == nil then
		return false, "nokit"
	end
	local ability = Kits.Ability(kit.Id, abilityId)
	if ability == nil then
		return false, "noability"
	end
	if ability.Slot ~= "M1" and StatusService.Has(model, "Silenced") then
		return false, "silenced"
	end
	local st = stateOf(model)
	local t = now()
	local cdEnd = st.Cooldowns[abilityId] or 0
	if t < cdEnd - COOLDOWN_TOLERANCE then
		return false, "cooldown"
	end
	if ability.Ult then
		local ult = model:GetAttribute("Ult")
		if type(ult) ~= "number" or ult < DamageMath.UltMax - 1e-6 then
			return false, "ult"
		end
	end

	-- aim
	local root = Validation.Root(model) :: BasePart
	local origin = root.CFrame.Position
	local look = Validation.Look(model)
	local range = if type(ability.Range) == "number" then ability.Range else Config.Combat.MaxAimRange
	local maxAim = math.min(range, Config.Combat.MaxAimRange) + Config.Combat.AimSlack
	local aim = payload.aim or (origin + (payload.dir or look) * math.min(range, 40))
	aim = DamageMath.ClampAim(origin, aim, maxAim)
	local dir = payload.dir or Validation.Unit(aim - origin, look)

	-- hold charge
	local charge = 0
	if type(ability.Hold) == "table" and type(ability.Hold.MaxTime) == "number" then
		local readySince = math.max(cdEnd, st.SpawnTime)
		charge = DamageMath.ClampCharge(payload.charge, readySince, t, ability.Hold.MaxTime, HOLD_TOLERANCE)
	end

	-- target
	local target: Model? = nil
	if ability.Aim == "Target" then
		if validTarget(model, payload.target, true, origin, dir, maxAim) then
			target = payload.target
		else
			target = autoTarget(model, origin, dir, aim, maxAim)
		end
		if target == nil then
			return false, "notarget"
		end
	elseif ability.Aim == "Ally" then
		if validTarget(model, payload.target, false, origin, dir, maxAim) then
			target = payload.target
		else
			target = model
		end
	end
	if target and ability.Aim == "Target" then
		aim = Validation.RootPosition(target) or aim
	end

	-- combo
	local comboIndex = 1
	if type(ability.Combo) == "number" and ability.Combo > 1 then
		local c = st.Combo[abilityId] or { Index = 0, Last = -math.huge }
		local window = if type(ability.Numbers.ComboWindow) == "number"
			then ability.Numbers.ComboWindow
			else Config.Combat.ComboResetTime
		comboIndex = DamageMath.NextComboIndex(c.Index, c.Last, t, window, ability.Combo)
		c.Index = comboIndex
		c.Last = t
		st.Combo[abilityId] = c
	end

	-- commit
	setCooldownInternal(model, player, abilityId, ability.Cooldown)
	local phaseTwo = false
	if ability.Ult then
		phaseTwo = startPhaseTwo(model) -- before the bar is spent; the cast still runs below as Phase 2's opener
		model:SetAttribute("Ult", 0)
	end
	if model:GetAttribute("Blocking") == true then
		setBlocking(model, false)
	end
	local ctx = CastContext.new({
		Caster = model,
		Player = player,
		Kit = kit,
		Ability = ability,
		CastId = payload.castId,
		Aim = aim,
		AimDir = dir,
		Charge = charge,
		Target = target,
		ComboIndex = comboIndex,
	})
	Net.Server.FireAll("AbilityFx", {
		caster = model,
		kit = kit.Id,
		ability = abilityId,
		phase = "Start",
		castId = payload.castId,
		t0 = ctx.StartTime,
		aim = aim,
		dir = ctx.AimDir,
		charge = charge,
		data = { combo = comboIndex, target = target, phase2 = if phaseTwo then true else nil },
	})
	AbilityService.Casted:Fire(model, abilityId)
	local handler = handlerFor(kit, ability)
	if handler then
		task.spawn(runHandler, handler, ctx, st)
	end
	return true, nil
end

function AbilityService.CastAs(model: Model, abilityId: string, payload: any?): (boolean, string?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or type(abilityId) ~= "string" then
		return false, "invalid"
	end
	local p = sanitizePayload(payload or {})
	local ok, result, reason = pcall(tryCast, model, Validation.GetPlayer(model), abilityId, p)
	if not ok then
		warn("[AbilityService] CastAs failed: " .. tostring(result))
		return false, "error"
	end
	return result, reason
end

function AbilityService.ContextFor(model: Model, abilityId: string?): any?
	local kit = Validation.Kit(model)
	if kit == nil or Validation.Root(model) == nil then
		return nil
	end
	local ability = if abilityId then Kits.Ability(kit.Id, abilityId) else nil
	if ability == nil then
		ability = { Id = abilityId or "Passive", Numbers = {} }
	end
	return CastContext.new({
		Caster = model,
		Player = Validation.GetPlayer(model),
		Kit = kit,
		Ability = ability,
	})
end

---------------------------------------------------------------------------------------------------
-- Character lifecycle

local function despawned(model: Model)
	local st = states[model]
	if st == nil or st.Despawned then
		return
	end
	st.Despawned = true
	for ctx in st.Casts do
		ctx:Cancel()
	end
	local kitId = model:GetAttribute("KitId")
	local serverKit = if type(kitId) == "string" then AbilityService.GetServerKit(kitId) else nil
	if serverKit and type(serverKit.OnDespawn) == "function" then
		local ok, err = xpcall(serverKit.OnDespawn, debug.traceback, model)
		if not ok then
			warn(("[AbilityService] %s.OnDespawn failed:\n%s"):format(tostring(kitId), tostring(err)))
		end
	end
	st.Trove:Destroy()
end

local function spawned(model: Model, _player: Player?)
	local old = states[model]
	if old then
		despawned(model)
		states[model] = nil
	end
	local st = stateOf(model)
	st.Trove:Add(function()
		states[model] = nil
	end)
	local kitId = model:GetAttribute("KitId")
	local serverKit = if type(kitId) == "string" then AbilityService.GetServerKit(kitId) else nil
	if serverKit and type(serverKit.OnSpawn) == "function" then
		local factory = function(abilityId: string?)
			return AbilityService.ContextFor(model, abilityId)
		end
		task.spawn(function()
			local ok, err = xpcall(serverKit.OnSpawn, debug.traceback, model, factory)
			if not ok then
				warn(("[AbilityService] %s.OnSpawn failed:\n%s"):format(tostring(kitId), tostring(err)))
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Net handlers

local function onCast(player: Player, abilityId: any, rawPayload: any)
	if type(abilityId) ~= "string" or #abilityId == 0 or #abilityId > MAX_ID_LENGTH then
		return
	end
	local clock = os.clock()
	local last = lastCast[player]
	if last and clock - last < Config.Combat.CastRateLimit then
		return
	end
	lastCast[player] = clock
	local model = Validation.ModelOf(player)
	if model == nil then
		return
	end
	local payload = sanitizePayload(rawPayload)
	local ok, result, reason = pcall(tryCast, model, player, abilityId, payload)
	if not ok then
		warn("[AbilityService] cast failed: " .. tostring(result))
		return
	end
	if not result and reason ~= "dead" then
		-- let a predicting client roll its cooldown back to the truth
		local st = states[model]
		local endsAt = if st then st.Cooldowns[abilityId] or 0 else 0
		Net.Server.Fire("Cooldown", player, abilityId, endsAt)
	end
end

local function onBlock(player: Player, isBlocking: any)
	if type(isBlocking) ~= "boolean" then
		return
	end
	local clock = os.clock()
	local last = lastBlockToggle[player]
	if isBlocking and last and clock - last < 0.05 then
		return
	end
	lastBlockToggle[player] = clock
	local model = Validation.ModelOf(player)
	if model then
		AbilityService.BlockAs(model, isBlocking)
	end
end

local function onDash(player: Player, direction: any, castId: any)
	if not Net.Check.Vector3(direction) then
		return
	end
	local id = if Net.Check.Number(castId, 0, 2 ^ 31) then math.floor(castId) else 0
	local model = Validation.ModelOf(player)
	if model then
		AbilityService.DashAs(model, direction, true, id)
	end
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

function AbilityService.Init()
	StatusService = require(script.Parent.StatusService) :: any
	DamageService = require(script.Parent.DamageService) :: any
	HazardService = require(script.Parent.HazardService) :: any
	MovementService = require(script.Parent.MovementService) :: any
	CastContext.Bind({
		StatusService = StatusService,
		DamageService = DamageService,
		HazardService = HazardService,
		MovementService = MovementService,
		AbilityService = AbilityService,
	})
end

function AbilityService.Start()
	Net.Server.On("Cast", onCast)
	Net.Server.On("Block", onBlock)
	Net.Server.On("Dash", onDash)
	local cs = Validation.Service("CharacterService")
	if cs then
		if cs.Spawned then
			cs.Spawned:Connect(spawned)
		end
		if cs.Died then
			cs.Died:Connect(function(model: Model)
				despawned(model)
			end)
		end
		if cs.Despawning then
			cs.Despawning:Connect(function(model: Model)
				despawned(model)
			end)
		end
		-- characters spawned before Start (unlikely) still get their kit hooks
		if type(cs.GetAll) == "function" then
			local ok, list = pcall(cs.GetAll)
			if ok and type(list) == "table" then
				for _, m in list do
					if states[m] == nil then
						spawned(m, nil)
					end
				end
			end
		end
	else
		warn("[AbilityService] CharacterService missing: kit OnSpawn hooks disabled")
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCast[player] = nil
		lastBlockToggle[player] = nil
	end)
end

return AbilityService
