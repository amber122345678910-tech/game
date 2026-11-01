--!strict
-- StatusService (P10): timed statuses + derived stats + the 10 Hz resource tick (SPEC §7.4, §17).
--
-- Statuses live server-side as { EndsAt, Data } per model and are mirrored to the attribute
-- "Status_<Name>" = EndsAt (server time; removed when the status ends) so clients can show icons.
-- Re-applying an active status keeps the LATER end time and replaces Data when new data is given.
--
-- Built-in names and semantics (any other name is allowed and only tracked/mirrored):
--   Stunned      no move/act; cancels blocking          Rooted      no move/jump
--   Slowed       walk x data.mult [0.6]                  Hasted      walk x data.mult [1.3]
--   Silenced     no abilities (M1 still allowed)         Blue        JumpPower x0.35, SoulMode "Blue"
--   Invulnerable immune to everything but Kind "Box"    IFrames     immune (dash i-frames)
--   Invisible    attribute Invisible = true              Marked      marker; incoming x data.mult [1] if given
--   Rage         outgoing x data.damage [1.3], walk x data.speed [1.2], monster cannot lazy-dodge
--   DamageUp     outgoing x data.mult [1.2]              DamageDown  incoming x data.mult [0.6]
--   Shielded     absorbs data.amount (attribute "Shield" mirrors the remaining amount)
--   Exhausted    monster: Dodges = 0, attribute Exhausted = EndsAt, incoming x Config.Monster.ExhaustDamageMult;
--                when it ends Dodges refill to MaxDodges
--   Boxed        in the Verdict Box: no move/act, SoulMode "Boxed", only Kind "Box" damage applies
--   SecondWind   walk x data.speed [Config.Human.SecondWindSpeedMult], outgoing x data.damage [SecondWindDamageMult]
--   Surge        outgoing x data.mult [Config.Objectives.SurgeDamageMult], walk x data.speed [1.1]
--   Undodgeable  the bearer's hits ignore lazy dodges   StealthStrike  next hit: x data.mult [1.6], undodgeable
--                                                                     (consumed by DamageService)
--   Determined   HP cannot drop below 1                  KRBoost     the bearer's KR applications x data.mult [2]
--
-- Movement: StatusService is the ONLY writer of Humanoid.WalkSpeed / JumpPower: kit Stats x modifiers,
-- Blocking x Config.Human.BlockWalkSpeedMult, Downed -> Config.Human.DownedWalkSpeed (no jump),
-- Stunned/Rooted/Boxed/Dead -> 0. (AutoRotate is left to the client MovementController.)
--
-- 10 Hz tick: status expiry (safety net; exact expiry uses task.delay), KR drain (DamageService.TickKR),
-- monster dodge regen (x Config.Monster.FinalPhaseDodgeRegenMult while FinalForm), human Guard regen
-- (after Config.Human.GuardRegenDelay without a blocked hit; x attribute GuardRegenMult), dash charge
-- regen, passive Ult gain (during Round/Collapse, or for Lobby players), then OnTick hooks.
--
-- API
--   StatusService.Apply(model, name, duration, data?) -> boolean
--   StatusService.Remove(model, name)
--   StatusService.Has(model, name) -> boolean
--   StatusService.Get(model, name) -> (endsAt: number?, data: {[string]: any}?)
--   StatusService.SetData(model, name, data)          update data without touching the duration
--   StatusService.ClearAll(model)
--   StatusService.Cleanse(model, names?)              removes debuffs (default list) -> number removed
--   StatusService.List(model) -> {[name]: {EndsAt, Data}}
--   StatusService.DamageMult(model) -> number          outgoing multiplier from statuses
--   StatusService.IncomingMult(model) -> number        incoming multiplier from statuses
--   StatusService.SpeedMult(model) -> number
--   StatusService.RecomputeMovement(model)
--   StatusService.CanAct(model) -> boolean             alive, up, not Stunned/Boxed
--   StatusService.OnTick(fn(dt, now)) -> disconnect()  kit passives (Calm, Nurturing, Hope...)
--   StatusService.NoteDodge(model) / NoteGuardHit(model)   bookkeeping used by DamageService
--   StatusService.Track(model) / Untrack(model)
--   StatusService.Applied: Signal(model, name, endsAt, data)   StatusService.Removed: Signal(model, name)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Config = require(Shared.Config) :: any
local Signal = require(Shared.Util.Signal) :: any
local Trove = require(Shared.Util.Trove) :: any
local DamageMath = require(Shared.Combat.DamageMath) :: any

local Validation = require(script.Parent.Parent.Combat.Validation) :: any

local StatusService = {}
StatusService.Priority = 10
StatusService.Applied = Signal.new()
StatusService.Removed = Signal.new()

local TICK = 0.1
local MAX_DURATION = 3600

type Entry = { EndsAt: number, Data: { [string]: any }?, Started: number }
type ModelState = {
	Statuses: { [string]: Entry },
	LastDodge: number,
	DodgeAcc: number,
	LastGuardHit: number,
	DashAcc: number,
	BaseWalk: number,
	BaseJump: number,
	Trove: any?,
	Walk: number?,
	Jump: number?,
	Mult: number?,
	UltAcc: number,
}

local states: { [Model]: ModelState } = setmetatable({}, { __mode = "k" }) :: any
local tickHooks: { (number, number) -> () } = {}

local DamageService: any = nil

local DEBUFFS = { "Stunned", "Rooted", "Slowed", "Silenced", "Blue", "DamageDown", "Marked" }

---------------------------------------------------------------------------------------------------
-- State

local function now(): number
	return Validation.Now()
end

local function stateOf(model: Model): ModelState
	local st = states[model]
	if st then
		return st
	end
	local hum = Validation.Humanoid(model)
	local created: ModelState = {
		Statuses = {},
		LastDodge = -math.huge,
		DodgeAcc = 0,
		LastGuardHit = -math.huge,
		DashAcc = 0,
		BaseWalk = if hum then hum.WalkSpeed else 16,
		BaseJump = if hum then hum.JumpPower else 50,
		Trove = nil,
		Walk = nil,
		Jump = nil,
		Mult = nil,
		UltAcc = 0,
	}
	states[model] = created
	return created
end

local function dataNum(data: { [string]: any }?, key: string, default: number): number
	if data then
		local v = data[key]
		if type(v) == "number" and v == v then
			return v
		end
	end
	return default
end

local function activeEntry(model: Model, name: string): Entry?
	local st = states[model]
	if st == nil then
		return nil
	end
	local e = st.Statuses[name]
	if e and e.EndsAt > now() then
		return e
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Queries

function StatusService.Has(model: Model?, name: string): boolean
	if model == nil then
		return false
	end
	return activeEntry(model, name) ~= nil
end

function StatusService.Get(model: Model?, name: string): (number?, { [string]: any }?)
	if model == nil then
		return nil, nil
	end
	local e = activeEntry(model, name)
	if e then
		return e.EndsAt, e.Data
	end
	return nil, nil
end

function StatusService.List(model: Model): { [string]: { EndsAt: number, Data: { [string]: any }? } }
	local out = {}
	local st = states[model]
	if st then
		local t = now()
		for name, e in st.Statuses do
			if e.EndsAt > t then
				out[name] = { EndsAt = e.EndsAt, Data = e.Data }
			end
		end
	end
	return out
end

function StatusService.DamageMult(model: Model?): number
	if model == nil then
		return 1
	end
	local mults = {}
	local e = activeEntry(model, "DamageUp")
	if e then
		table.insert(mults, dataNum(e.Data, "mult", 1.2))
	end
	e = activeEntry(model, "Rage")
	if e then
		table.insert(mults, dataNum(e.Data, "damage", 1.3))
	end
	e = activeEntry(model, "Surge")
	if e then
		table.insert(mults, dataNum(e.Data, "mult", Config.Objectives.SurgeDamageMult))
	end
	e = activeEntry(model, "SecondWind")
	if e then
		table.insert(mults, dataNum(e.Data, "damage", Config.Human.SecondWindDamageMult))
	end
	return DamageMath.OutgoingMult(mults)
end

function StatusService.IncomingMult(model: Model?): number
	if model == nil then
		return 1
	end
	local mults = {}
	local e = activeEntry(model, "DamageDown")
	if e then
		table.insert(mults, dataNum(e.Data, "mult", 0.6))
	end
	if activeEntry(model, "Exhausted") then
		table.insert(mults, Config.Monster.ExhaustDamageMult)
	end
	e = activeEntry(model, "Marked")
	if e then
		table.insert(mults, dataNum(e.Data, "mult", 1))
	end
	return DamageMath.IncomingMult(mults)
end

function StatusService.SpeedMult(model: Model): number
	local m = 1
	local e = activeEntry(model, "Slowed")
	if e then
		m *= math.max(0, dataNum(e.Data, "mult", 0.6))
	end
	e = activeEntry(model, "Hasted")
	if e then
		m *= math.max(0, dataNum(e.Data, "mult", 1.3))
	end
	e = activeEntry(model, "Rage")
	if e then
		m *= math.max(0, dataNum(e.Data, "speed", 1.2))
	end
	e = activeEntry(model, "SecondWind")
	if e then
		m *= math.max(0, dataNum(e.Data, "speed", Config.Human.SecondWindSpeedMult))
	end
	e = activeEntry(model, "Surge")
	if e then
		m *= math.max(0, dataNum(e.Data, "speed", 1.1))
	end
	return m
end

function StatusService.CanAct(model: Model?): boolean
	if not Validation.IsUp(model) then
		return false
	end
	local m = model :: Model
	return not StatusService.Has(m, "Stunned") and not StatusService.Has(m, "Boxed")
end

---------------------------------------------------------------------------------------------------
-- Derived stats

function StatusService.RecomputeMovement(model: Model)
	local hum = Validation.Humanoid(model)
	if hum == nil then
		return
	end
	local st = stateOf(model)
	local kit = Validation.Kit(model)
	local baseWalk = if kit and type(kit.Stats.WalkSpeed) == "number" then kit.Stats.WalkSpeed else st.BaseWalk
	local baseJump = if kit and type(kit.Stats.JumpPower) == "number" then kit.Stats.JumpPower else st.BaseJump
	local walk = baseWalk * StatusService.SpeedMult(model)
	local jump = baseJump
	if model:GetAttribute("Blocking") == true then
		walk *= Config.Human.BlockWalkSpeedMult
	end
	if StatusService.Has(model, "Blue") then
		jump *= 0.35
	end
	if model:GetAttribute("Downed") == true then
		walk = Config.Human.DownedWalkSpeed
		jump = 0
	end
	if StatusService.Has(model, "Stunned") or StatusService.Has(model, "Boxed") then
		walk = Config.Combat.StunWalkSpeed
		jump = 0
	end
	if StatusService.Has(model, "Rooted") then
		walk = 0
		jump = 0
	end
	if model:GetAttribute("Dead") == true then
		walk = 0
		jump = 0
	end
	walk = math.max(0, walk)
	jump = math.max(0, jump)
	if st.Walk == nil or math.abs(st.Walk - walk) > 1e-3 or math.abs(hum.WalkSpeed - walk) > 1e-3 then
		st.Walk = walk
		hum.WalkSpeed = walk
	end
	if st.Jump == nil or math.abs(st.Jump - jump) > 1e-3 or math.abs(hum.JumpPower - jump) > 1e-3 then
		st.Jump = jump
		hum.JumpPower = jump
	end
end

local function refreshDerived(model: Model)
	local st = stateOf(model)
	local mult = math.floor(StatusService.DamageMult(model) * 1000 + 0.5) / 1000
	if st.Mult ~= mult then
		st.Mult = mult
		model:SetAttribute("Buff_DamageMult", mult)
	end
	StatusService.RecomputeMovement(model)
end

---------------------------------------------------------------------------------------------------
-- Side effects of specific statuses

local function soulModeAfter(model: Model): string
	if StatusService.Has(model, "Boxed") then
		return "Boxed"
	elseif StatusService.Has(model, "Blue") then
		return "Blue"
	end
	return "Red"
end

local function onStart(model: Model, name: string, entry: Entry)
	if name == "Stunned" or name == "Boxed" then
		if model:GetAttribute("Blocking") == true then
			model:SetAttribute("Blocking", false)
			model:SetAttribute("BlockStart", 0)
		end
	end
	if name == "Boxed" or name == "Blue" then
		model:SetAttribute("SoulMode", soulModeAfter(model))
	elseif name == "Invisible" then
		model:SetAttribute("Invisible", true)
	elseif name == "Exhausted" then
		model:SetAttribute("Dodges", 0)
		model:SetAttribute("Exhausted", entry.EndsAt)
	elseif name == "Shielded" then
		model:SetAttribute("Shield", dataNum(entry.Data, "amount", 0))
	end
end

local function onEnd(model: Model, name: string)
	if name == "Boxed" or name == "Blue" then
		model:SetAttribute("SoulMode", soulModeAfter(model))
	elseif name == "Invisible" then
		model:SetAttribute("Invisible", false)
	elseif name == "Exhausted" then
		local max = model:GetAttribute("MaxDodges")
		if type(max) == "number" then
			model:SetAttribute("Dodges", max)
		end
		model:SetAttribute("Exhausted", 0)
		local st = stateOf(model)
		st.LastDodge = now()
		st.DodgeAcc = 0
	elseif name == "Shielded" then
		model:SetAttribute("Shield", nil)
	end
end

---------------------------------------------------------------------------------------------------
-- Apply / remove

local function scheduleExpiry(model: Model, name: string, endsAt: number)
	local delay = math.max(0, endsAt - now()) + 0.01
	task.delay(delay, function()
		local st = states[model]
		if st == nil then
			return
		end
		local e = st.Statuses[name]
		if e and e.EndsAt <= now() then
			StatusService.Remove(model, name)
		end
	end)
end

function StatusService.Apply(model: Model?, name: string, duration: number, data: { [string]: any }?): boolean
	if typeof(model) ~= "Instance" or not (model :: Instance):IsA("Model") then
		return false
	end
	local m = model :: Model
	if type(name) ~= "string" or name == "" or #name > 40 then
		return false
	end
	if type(duration) ~= "number" or duration ~= duration then
		return false
	end
	if duration <= 0 then
		StatusService.Remove(m, name)
		return false
	end
	if m:GetAttribute("Dead") == true then
		return false
	end
	duration = math.min(duration, MAX_DURATION)
	local t = now()
	local st = stateOf(m)
	local entry = st.Statuses[name]
	local endsAt = t + duration
	local isNew = entry == nil or entry.EndsAt <= t
	local e: Entry
	if entry ~= nil and not isNew then
		e = entry
		e.EndsAt = math.max(e.EndsAt, endsAt)
		if data ~= nil then
			e.Data = data
		end
	else
		e = { EndsAt = endsAt, Data = data, Started = t }
		st.Statuses[name] = e
	end
	m:SetAttribute("Status_" .. name, e.EndsAt)
	if isNew then
		onStart(m, name, e)
	else
		if name == "Exhausted" then
			m:SetAttribute("Exhausted", e.EndsAt)
		elseif name == "Shielded" then
			m:SetAttribute("Shield", dataNum(e.Data, "amount", 0))
		end
	end
	scheduleExpiry(m, name, e.EndsAt)
	refreshDerived(m)
	StatusService.Applied:Fire(m, name, e.EndsAt, e.Data)
	return true
end

function StatusService.SetData(model: Model, name: string, data: { [string]: any }?)
	local e = activeEntry(model, name)
	if e == nil then
		return
	end
	e.Data = data
	if name == "Shielded" then
		model:SetAttribute("Shield", dataNum(data, "amount", 0))
	end
	refreshDerived(model)
end

function StatusService.Remove(model: Model?, name: string)
	if model == nil then
		return
	end
	local st = states[model]
	if st == nil then
		return
	end
	local e = st.Statuses[name]
	if e == nil then
		return
	end
	st.Statuses[name] = nil
	model:SetAttribute("Status_" .. name, nil)
	onEnd(model, name)
	refreshDerived(model)
	StatusService.Removed:Fire(model, name)
end

function StatusService.ClearAll(model: Model)
	local st = states[model]
	if st == nil then
		return
	end
	local names = {}
	for name in st.Statuses do
		table.insert(names, name)
	end
	for _, name in names do
		StatusService.Remove(model, name)
	end
end

function StatusService.Cleanse(model: Model, names: { string }?): number
	local removed = 0
	for _, name in names or DEBUFFS do
		if StatusService.Has(model, name) then
			StatusService.Remove(model, name)
			removed += 1
		end
	end
	return removed
end

---------------------------------------------------------------------------------------------------
-- Bookkeeping used by DamageService

function StatusService.NoteDodge(model: Model)
	local st = stateOf(model)
	st.LastDodge = now()
	st.DodgeAcc = 0
end

function StatusService.NoteGuardHit(model: Model)
	stateOf(model).LastGuardHit = now()
end

---------------------------------------------------------------------------------------------------
-- Tracking

function StatusService.Track(model: Model)
	local st = stateOf(model)
	if st.Trove then
		return
	end
	local trove = Trove.new()
	st.Trove = trove
	local function recompute()
		if states[model] then
			StatusService.RecomputeMovement(model)
		end
	end
	for _, attr in { "Downed", "Blocking", "Dead" } do
		pcall(function()
			trove:Connect(model:GetAttributeChangedSignal(attr), recompute)
		end)
	end
	pcall(function()
		trove:Connect(model.Destroying, function()
			StatusService.Untrack(model)
		end)
	end)
	refreshDerived(model)
end

function StatusService.Untrack(model: Model)
	local st = states[model]
	if st == nil then
		return
	end
	states[model] = nil
	if st.Trove then
		st.Trove:Destroy()
	end
end

---------------------------------------------------------------------------------------------------
-- Tick

function StatusService.OnTick(fn: (number, number) -> ()): () -> ()
	table.insert(tickHooks, fn)
	return function()
		local i = table.find(tickHooks, fn)
		if i then
			table.remove(tickHooks, i)
		end
	end
end

local function numAttr(model: Model, name: string): number?
	local v = model:GetAttribute(name)
	if type(v) == "number" and v == v then
		return v
	end
	return nil
end

local function tickDodges(model: Model, st: ModelState, t: number, dt: number)
	local dodges = numAttr(model, "Dodges")
	local max = numAttr(model, "MaxDodges")
	if dodges == nil or max == nil then
		return
	end
	if StatusService.Has(model, "Exhausted") then
		st.DodgeAcc = 0
		return
	end
	if dodges <= 0 and max > 0 then
		-- drained to zero by something other than a dodge (kit drains, SAVE points): exhaust now
		StatusService.Apply(model, "Exhausted", Config.Monster.ExhaustTime)
		return
	end
	local state = { Dodges = dodges, Max = max, LastDodge = st.LastDodge, Acc = st.DodgeAcc, ExhaustedUntil = 0 }
	local mult = if model:GetAttribute("FinalForm") == true then Config.Monster.FinalPhaseDodgeRegenMult else 1
	DamageMath.DodgeRegen(state, t, dt, mult)
	st.DodgeAcc = state.Acc
	if state.Dodges ~= dodges then
		model:SetAttribute("Dodges", state.Dodges)
	end
end

local function tickGuard(model: Model, st: ModelState, t: number, dt: number)
	local guard = numAttr(model, "Guard")
	local max = numAttr(model, "MaxGuard")
	if guard == nil or max == nil or guard >= max then
		return
	end
	local mult = numAttr(model, "GuardRegenMult") or 1
	local g = DamageMath.GuardRegen(guard, max, t, st.LastGuardHit, dt, mult)
	if math.abs(g - guard) > 1e-3 then
		model:SetAttribute("Guard", math.floor(g * 10 + 0.5) / 10)
	end
end

local function tickDash(model: Model, st: ModelState, dt: number)
	local charges = numAttr(model, "DashCharges")
	if charges == nil then
		return
	end
	local kit = Validation.Kit(model)
	local max = if kit and type(kit.Stats.DashCharges) == "number" then kit.Stats.DashCharges else Config.Human.DashCharges
	if charges >= max then
		st.DashAcc = 0
		return
	end
	local c, acc = DamageMath.ChargeTick(charges, max, st.DashAcc, dt, Config.Human.DashRecharge)
	st.DashAcc = acc
	if c ~= charges then
		model:SetAttribute("DashCharges", c)
	end
end

local function tickUlt(model: Model, st: ModelState, dt: number, inRound: boolean)
	local ult = numAttr(model, "Ult")
	if ult == nil or ult >= DamageMath.UltMax then
		return
	end
	if not inRound and Validation.Team(model) ~= "Lobby" then
		return
	end
	if model:GetAttribute("Downed") == true or StatusService.Has(model, "Boxed") then
		return
	end
	-- accumulate and write in 0.1 steps (keeps attribute replication light)
	st.UltAcc += DamageMath.UltPerSecond(Validation.Role(model)) * dt
	if st.UltAcc >= 0.1 then
		local add = math.floor(st.UltAcc * 10) / 10
		st.UltAcc -= add
		model:SetAttribute("Ult", DamageMath.AddUlt(ult, add))
	end
end

-- Removes every status of `model` whose end time has passed (names collected first: Removed handlers
-- may apply new statuses while we iterate).
local function expireDue(model: Model, st: ModelState, t: number)
	local due: { string }? = nil
	for name, e in st.Statuses do
		if e.EndsAt <= t then
			local list = due or {}
			due = list
			table.insert(list, name)
		end
	end
	if due then
		for _, name in due do
			StatusService.Remove(model, name)
		end
	end
end

local function step(dt: number)
	local t = now()
	local inRound = Validation.InCombatPhase()
	local seen: { [Model]: boolean } = {}
	for _, model in Validation.Combatants() do
		seen[model] = true
		local st = stateOf(model)
		expireDue(model, st, t)
		if Validation.IsAlive(model) then
			local kr = numAttr(model, "KR")
			if kr and kr > 0 and model:GetAttribute("Downed") ~= true and DamageService then
				local ok, err = pcall(DamageService.TickKR, model, dt)
				if not ok then
					warn("[StatusService] KR tick failed: " .. tostring(err))
				end
			end
			tickDodges(model, st, t, dt)
			tickGuard(model, st, t, dt)
			tickDash(model, st, dt)
			tickUlt(model, st, dt, inRound)
			StatusService.RecomputeMovement(model)
		end
	end
	-- models we track that are no longer combatants: just expire their statuses
	local others: { Model } = {}
	for model in states do
		if not seen[model] then
			table.insert(others, model)
		end
	end
	for _, model in others do
		local st = states[model]
		if st then
			if model.Parent == nil then
				StatusService.Untrack(model)
			else
				expireDue(model, st, t)
			end
		end
	end
	for _, fn in table.clone(tickHooks) do
		local ok, err = pcall(fn, dt, t)
		if not ok then
			warn("[StatusService] OnTick hook failed: " .. tostring(err))
		end
	end
end

-- Exposed for tests / tools: run one tick synchronously.
StatusService._Step = step

---------------------------------------------------------------------------------------------------
-- Lifecycle

function StatusService.Init()
	DamageService = require(script.Parent.DamageService) :: any
end

function StatusService.Start()
	local cs = Validation.Service("CharacterService")
	if cs then
		if cs.Spawned then
			cs.Spawned:Connect(function(model: Model)
				StatusService.ClearAll(model)
				StatusService.Track(model)
			end)
		end
		if cs.Died then
			cs.Died:Connect(function(model: Model)
				StatusService.ClearAll(model)
				StatusService.RecomputeMovement(model)
			end)
		end
		if cs.Revived then
			cs.Revived:Connect(function(model: Model)
				StatusService.RecomputeMovement(model)
			end)
		end
	end
	task.spawn(function()
		while true do
			local dt = task.wait(TICK)
			local ok, err = pcall(step, math.min(dt, 0.5))
			if not ok then
				warn("[StatusService] tick failed: " .. tostring(err))
			end
		end
	end)
end

return StatusService
