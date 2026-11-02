--!strict
-- Server kit: Perseverance (purple SOUL) — "The Scholar". Control / utility. Numbers come from
-- Shared/Kits/Humans/Perseverance (ctx.N); the constants below only shape hitboxes and timing.
--
-- Abilities (AbilityFx phases after the automatic "Start"):
--   NotebookSwat (M1)     3-hit combo of WIDE notebook swats (box Range deep, Range x SWAT_WIDTH wide); the 3rd is
--                         an overhead slam (wider, knocks back SLAM_KNOCKBACK).   Fx "Strike" {combo, last, hits}
--   SpellboundPages (Q)   after Windup a stream of Pages page projectiles (Interval apart, Speed, Damage each,
--                         hazard visual "SpellPage", alternating +-PAGE_WOBBLE deg). A target hit by RootHits
--                         pages of the SAME stream is Rooted for Root s (dodged pages do not count).
--                         Fx "Stream" {count, interval}, "Bind" {target, duration}
--   Rewrite (E)           rewinds the caster to where they stood Seconds ago: a server ring buffer (StatusService
--                         10 Hz tick) keeps the root CFrame + HP; the sample closest to `now - Seconds` with a clear
--                         line from here is used (else the next newer one). ctx:Teleport validates the move, HP is
--                         restored to max(now, then) (a rewind never hurts), KR is cleared.
--                         Fx "Rewind" {from, path: {Vector3} (oldest first), heal, seconds}, then ctx:Teleport's
--                         "Teleport" {from, to}
--   FinalChapter (R, ult) a giant book opens over the target, follows it for TRACK_FRACTION of Delay, locks
--                         ("Lock"), then slams shut at Delay: every enemy under it (BOOK_RADIUS, cylinder) takes
--                         Damage (Undodgeable, unblockable, Kind Area) and is Silenced for Silence s. The caster
--                         carries status "Chapter" while the book is out (client SOUL glow). Dying / being stunned
--                         mid-cast cancels the slam. Fx "Summon" {target, pos, delay, lockAt, radius},
--                         "Lock" {pos}, "Slam" {pos, hits, silence}, "Cancel"
-- Passive "Studious": nothing to run here — AbilityService already mirrors every cooldown as the model attribute
--   Cooldown_<abilityId> = endsAt, and Hud/BossBar shows the monster's ones to players whose kit has Studious.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Kits = require(Shared.Kits) :: any
local HazardDefs = require(Shared.Combat.HazardDefs) :: any

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Common = require(script.Parent.Common) :: any

local Kit = {}
local Abilities: { [string]: (any) -> () } = {}
Kit.Abilities = Abilities

local KIT_ID = "Perseverance"
local SWAT_WIDTH = 1.3 -- swats are wider than deep (crowd control, forgiving)
local SLAM_WIDTH = 1.5
local SLAM_KNOCKBACK = 16
local PAGE_RADIUS = 0.7
local PAGE_WOBBLE = 3 -- degrees: the stream flutters left / right of the aim line
local PAGE_VISUAL = "SpellPage" -- registered by src/client/Kits/Perseverance.luau
local SAMPLE_INTERVAL = 0.1
local HISTORY_SLACK = 1.5 -- seconds of history kept beyond Rewrite.Seconds
local BOOK_RADIUS = 7.5
local BOOK_REACH_UP = 9 -- the slam reaches targets this high above the ground (jumping does not save you)
local TRACK_FRACTION = 0.6 -- the book follows its target for this part of Delay, then locks (dash to escape)

-- Hand / notebook position in front of the caster (matches the client's page spawn point).
local function handOrigin(ctx: any): Vector3
	local root = ctx:RootPosition()
	return root + ctx.FlatDir * 1.3 + Common.Right(ctx.FlatDir) * 0.6 + Vector3.new(0, 0.6, 0)
end

local function windupOf(ctx: any, default: number): number
	local w = ctx.Ability.Windup
	return if type(w) == "number" then w else default
end

local function rotateYaw(dir: Vector3, angle: number): Vector3
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(dir.X * c - dir.Z * s, dir.Y, dir.X * s + dir.Z * c)
end

local function landed(result: any): boolean
	return result ~= nil
		and result.Reason == nil
		and not result.Dodged
		and not result.Parried
		and ((result.Applied or 0) > 0 or (result.Absorbed or 0) > 0)
end

---------------------------------------------------------------------------------------------------
-- Rewrite history (ring buffer per Perseverance model, recorded by the StatusService 10 Hz tick)

type Sample = { T: number, CFrame: CFrame, Health: number }

local histories: { [Model]: { Sample } } = setmetatable({}, { __mode = "k" }) :: any
local tickInstalled = false

local function historySeconds(): number
	local def = Kits.Ability(KIT_ID, "Rewrite")
	local seconds = if def and def.Numbers and type(def.Numbers.Seconds) == "number" then def.Numbers.Seconds else 3
	return seconds + HISTORY_SLACK
end

local function record(model: Model, now: number)
	local hist = histories[model]
	if hist == nil or not Validation.IsUp(model) then
		return
	end
	local root = Validation.Root(model)
	local hum = Validation.Humanoid(model)
	if root == nil or hum == nil then
		return
	end
	local last = hist[#hist]
	if last and now - last.T < SAMPLE_INTERVAL * 0.5 then
		return
	end
	table.insert(hist, { T = now, CFrame = root.CFrame, Health = hum.Health })
	local cutoff = now - historySeconds()
	while #hist > 2 and hist[1].T < cutoff do
		table.remove(hist, 1)
	end
end

local function installTick()
	if tickInstalled then
		return
	end
	tickInstalled = true
	Common.Services().StatusService.OnTick(function(_dt: number, now: number)
		for model in histories do
			if model.Parent == nil then
				histories[model] = nil
			else
				record(model, now)
			end
		end
	end)
end

-- Test / tooling access to the buffer (read-only use).
function Kit.History(model: Model): { Sample }?
	return histories[model]
end

function Kit.OnSpawn(model: Model, _ctxFactory: any)
	installTick()
	histories[model] = {}
	record(model, Validation.Now())
end

function Kit.OnDespawn(model: Model)
	histories[model] = nil
end

---------------------------------------------------------------------------------------------------
-- NotebookSwat (M1)

Abilities.NotebookSwat = function(ctx: any)
	local N = ctx.N
	local index = ctx.ComboIndex or 1
	local comboLength = if type(ctx.Ability.Combo) == "number" then ctx.Ability.Combo else 3
	local isLast = index >= comboLength
	if not ctx:Wait(windupOf(ctx, 0.12)) then
		return
	end
	local range = N.Range or 6.5
	local hits = ctx:Melee({
		Offset = CFrame.new(0, 0, -range * 0.5),
		Size = Vector3.new(range * (if isLast then SLAM_WIDTH else SWAT_WIDTH), 5.5, range),
		Damage = N["Damage" .. index] or N.Damage1 or 6,
		Kind = "Melee",
		Knockback = if isLast then SLAM_KNOCKBACK else nil,
	})
	ctx:Fx("Strike", { combo = index, last = isLast, hits = #hits })
end

---------------------------------------------------------------------------------------------------
-- SpellboundPages (Q)

Abilities.SpellboundPages = function(ctx: any)
	local N = ctx.N
	if not ctx:Wait(windupOf(ctx, 0.15)) then
		return
	end
	local count = math.max(1, math.floor(N.Pages or 5))
	local interval = math.max(0.02, N.Interval or 0.08)
	local need = math.max(1, math.floor(N.RootHits or 3))
	local rootTime = N.Root or 1
	local damage = N.Damage or 4
	local range = if type(ctx.Ability.Range) == "number" then ctx.Ability.Range else 50
	local hitsBy: { [Model]: number } = {}
	local bound: { [Model]: boolean } = {}

	local function onHit(target: Model): boolean?
		local result = ctx:Damage(target, { Amount = damage, Kind = "Projectile", Position = ctx:RootPosition() })
		if landed(result) then
			local n = (hitsBy[target] or 0) + 1
			hitsBy[target] = n
			if n >= need and not bound[target] and Validation.IsAlive(target) then
				bound[target] = true
				ctx:Status(target, "Rooted", rootTime)
				ctx:Fx("Bind", { target = target, duration = rootTime })
			end
		end
		return true -- damage handled here (counted per stream); the page ends on its target
	end

	ctx:Fx("Stream", { count = count, interval = interval })
	for i = 1, count do
		if i > 1 and not ctx:Wait(interval) then
			return
		end
		local origin = handOrigin(ctx)
		local aimDir = Validation.Unit(ctx.Aim - origin, ctx.AimDir)
		local side = if i == 1 then 0 elseif i % 2 == 0 then 1 else -1
		local dir = rotateYaw(aimDir, math.rad(PAGE_WOBBLE) * side)
		ctx:Projectile({
			Origin = HazardDefs.LookAlong(origin, dir),
			Speed = N.Speed or 70,
			Radius = PAGE_RADIUS,
			MaxDist = range,
			Damage = damage,
			Color = "Purple",
			Visual = PAGE_VISUAL,
			Hooks = { OnHit = onHit },
		})
	end
end

---------------------------------------------------------------------------------------------------
-- Rewrite (E)

Abilities.Rewrite = function(ctx: any)
	local N = ctx.N
	local seconds = N.Seconds or 3
	if not ctx:Wait(windupOf(ctx, 0.1)) then
		return
	end
	local caster = ctx.Caster
	local hist = histories[caster]
	local from = ctx:RootPosition()
	local want = ctx:Now() - seconds
	local chosenIndex: number? = nil
	if hist and #hist > 0 then
		local first = #hist
		for i, s in hist do
			if s.T >= want - SAMPLE_INTERVAL * 0.5 then
				first = i
				break
			end
		end
		for i = first, #hist do
			local p = hist[i].CFrame.Position
			if (p - from).Magnitude < 0.5 or Validation.LineOfSight(from, p) then
				chosenIndex = i
				break
			end
		end
	end

	local heal = 0
	local path: { Vector3 } = {}
	if hist and chosenIndex then
		local chosen = hist[chosenIndex]
		local hum = ctx.Humanoid
		if hum then
			heal = math.max(0, chosen.Health - hum.Health)
		end
		local n = #hist - chosenIndex + 1
		local step = math.max(1, math.ceil(n / 8))
		for i = chosenIndex, #hist, step do
			table.insert(path, hist[i].CFrame.Position)
		end
	end
	ctx:Fx("Rewind", { from = from, path = path, heal = heal, seconds = seconds })
	if hist and chosenIndex then
		ctx:Teleport(hist[chosenIndex].CFrame)
		table.clear(hist) -- the rewound moment is the new present
	end
	if heal > 0 then
		ctx:Heal(caster, heal)
	end
	Common.Services().DamageService.CleanseKR(caster)
	if hist then
		record(caster, ctx:Now())
	end
end

---------------------------------------------------------------------------------------------------
-- FinalChapter (R, ultimate)

local function underBook(ctx: any, pos: Vector3): { Model }
	local out: { Model } = {}
	local ground = Common.GroundAim(ctx, pos)
	for _, m in ctx:Enemies(true) do
		local p = Validation.RootPosition(m)
		if p then
			local flat = Vector3.new(p.X - pos.X, 0, p.Z - pos.Z).Magnitude
			local up = p.Y - ground.Y
			if flat <= BOOK_RADIUS and up >= -2 and up <= BOOK_REACH_UP + 3 then
				table.insert(out, m)
			end
		end
	end
	return out
end

Abilities.FinalChapter = function(ctx: any)
	local N = ctx.N
	local delay = math.max(0.2, N.Delay or 0.8)
	local target: Model? = ctx.Target
	if target == nil or not Validation.IsAlive(target) or not ctx:IsEnemy(target) then
		target = ctx:NearestEnemy(ctx.Aim, 24)
	end
	if target == nil then
		ctx:Fx("Cancel")
		return
	end
	local pos: Vector3 = Validation.RootPosition(target) or ctx.Aim
	local lockAt = delay * TRACK_FRACTION
	ctx:Status(ctx.Caster, "Chapter", delay + 0.7)
	ctx:Fx("Summon", { target = target, pos = pos, delay = delay, lockAt = lockAt, radius = BOOK_RADIUS })
	if not ctx:Wait(lockAt) then
		ctx:Fx("Cancel")
		return
	end
	if Validation.IsAlive(target :: Model) then
		pos = Validation.RootPosition(target) or pos
	end
	ctx:Fx("Lock", { pos = pos })
	if not ctx:Wait(delay - lockAt) then
		ctx:Fx("Cancel")
		return
	end
	local hits: { Model } = {}
	for _, m in underBook(ctx, pos) do
		local result = ctx:Damage(m, {
			Amount = N.Damage or 35,
			Kind = "Area",
			Undodgeable = true,
			Blockable = false,
			Position = pos + Vector3.new(0, BOOK_REACH_UP, 0),
		})
		if landed(result) then
			table.insert(hits, m)
			if Validation.IsAlive(m) then
				ctx:Status(m, "Silenced", N.Silence or 3)
			end
		end
	end
	ctx:Fx("Slam", { pos = Common.GroundAim(ctx, pos), hits = hits, silence = N.Silence or 3 })
end

return Kit
