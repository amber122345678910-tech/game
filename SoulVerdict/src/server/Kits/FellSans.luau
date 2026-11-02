--!strict
-- Server kit: Fell Sans — "The Executioner" (aggressive brawler, Underfell AU). Every tunable comes from
-- Shared/Kits/Monsters/FellSans (ctx.N); the constants in C are feel / geometry values the data does not carry.
--
-- Abilities (AbilityFx phases sent with ctx:Fx, after the automatic "Start" {combo, target}):
--   BoneCleaver (M1)     4-hit red bone-blade combo: Damage1..4 + KR in a Range-deep box. Hits 1-3 land at Windup,
--                        the overhead 4th at Windup + C.FinisherExtraWindup (Slash4's hit frame) in a wider box and
--                        launches: Knockback x C.LaunchForward along the aim + KnockbackUp [Knockback x C.LaunchUp] up.
--                        Fx "Strike" {combo, last, hits (landed)}
--   CrimsonBlaster (Q)   one Fell-style BlasterBeam ("Red") over Fell's right shoulder aimed at the aim point (chest
--                        height above ground): Delay charge, BeamTime, Width, Length, Damage, KR. An interrupted Fell
--                        loses the shot (hazard removed).          Fx "Summon" {hazard, origin}, "Fizzle" {hazard, origin}
--   ChainGrab (E)        after Windup a Projectile hazard (visual "FellChain", Speed, Range, radius C.ChainRadius; from
--                        the hand toward the aim at chest height, within C.ChainMaxSlope of level). The
--                        first human it reaches takes Damage, is Stunned for PullTime + Stun and pulled (ForceMove Pull)
--                        to C.GrabStop studs in front of Fell. Blocked / parried / absorbed-to-death hits, or a Fell who
--                        was interrupted meanwhile, do not pull ("Snap"). I-framed humans let the chain fly on; downed
--                        humans get the default hit.     Fx "Throw" {hazard}, "Grab" {target, time, to}, "Snap" {target, pos}
--   BoneRush (R)         dash Distance along the aim in C.RushTime; as Fell passes each of Spikes points (RushPoints) a
--                        red BoneSpikes cluster is spawned that erupts SpikeDelay later (Damage + KR, upward pop). One hit
--                        per human per rush; an interrupted rush spawns nothing further.
--                        Fx "Rush" {from, to, time, spikeDelay, count}
--   Bloodlust (T)        after Windup: Rage {damage = DamageMult, speed = SpeedMult, lifesteal = Lifesteal} for Duration
--                        (Rage also disables the lazy dodge, see DamageService). Lifesteal = the After hook below.
--                        Fx "Rage" {duration}; every lifesteal heal: "Siphon" {target, amount}
--   Lunge (Shift)        dash Distance in the move direction (Humanoid.MoveDirection, else the aim) in C.LungeTime.
--                        Fx "Dash" {from, to, time}
--   Execution (G, ult)   marks every up human within Radius (status Marked). At Delay - C.ExecLock each mark locks on
--                        the ground under its human and a Fell blaster drops from above, firing straight DOWN at Delay
--                        (vertical BlasterBeam, Width [C.ExecWidth], BeamTime [C.ExecBeamTime], unblockable). Hits on
--                        humans below LowHpFraction HP deal x LowHpMult (Before hook). Interrupted before the lock ->
--                        nothing drops.  Fx "Mark" {targets, delay, lock, radius}, "Drop" {targets, points, hazards, delay,
--                        width}, "Cancel" {targets}; every low-HP hit: "Executed" {target, pos}
-- Passives (DamageService hooks, installed once per server on the first spawn / cast):
--   LazyDodge   framework (DamageService lazy dodge; Rage switches it off during Bloodlust).
--   GoldTooth   Before: Fell's hits on Stunned / Rooted targets deal +C.GoldToothBonus (state.Bonus) and every Fell
--               hit on a human carries +C.GoldToothKR KR. A boosted hit that lands broadcasts AbilityFx ability
--               "GoldTooth" phase "Glint" {target, pos} (passive context via AbilityService.ContextFor).
--
-- API: Kit.Abilities[abilityId](ctx), Kit.OnSpawn(model, ctxFactory?), Kit.OnDespawn(model)
-- Pure helpers (shared with tests / the client kit): Kit.RushPoints(start, dir, distance, count) -> {Vector3},
--   Kit.BlasterSlot(origin, flatDir) -> Vector3, Kit.Constants (= C)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Kits = require(Shared.Kits) :: any
local HazardDefs = require(Shared.Combat.HazardDefs) :: any

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Melee = require(Combat.Melee) :: any
local Common = require(script.Parent.Common) :: any

local Kit = {}
local Abilities: { [string]: (any) -> () } = {}
Kit.Abilities = Abilities

local KIT_ID = "FellSans"
local LookAlong = HazardDefs.LookAlong
local DOWN = Vector3.new(0, -1, 0)

-- Feel / geometry constants (the client kit mirrors the ones it draws: keep in sync).
local C = {
	GoldToothBonus = 0.25, -- kit text: "+25% damage" against Stunned / Rooted humans
	GoldToothKR = 1, -- kit text: "Hits add a little KR"
	FinisherExtraWindup = 0.07, -- the 4th hit lands on Slash4's "Hit" frame (0.21 s)
	LaunchForward = 0.6, -- 4th hit: horizontal knockback = Knockback x this
	LaunchUp = 0.8, -- 4th hit: KnockbackUp default = Knockback x this
	ComboWidth = 5.6,
	ComboHeight = 5.5,
	FinisherWidth = 7,
	BlasterSlot = { 2.4, 4.4, 1.8 }, -- CrimsonBlaster muzzle in caster space: right, up, back (studs)
	ChainRadius = 1.1, -- ChainGrab hook radius (the visual hook glow is >= this)
	ChainMaxSlope = 0.47, -- the throw stays within ~25 degrees of level
	GrabStop = 3.4, -- the grabbed human ends this far in front of Fell (inside the M1 box)
	PullSlack = 0.1,
	RushTime = 0.24,
	SpikeRadius = 2.6,
	SpikeBones = 5,
	SpikeHeight = 4.6,
	SpikePop = 16, -- BoneRush spikes knock the victim up (studs/s)
	LungeTime = 0.16,
	ExecLock = 0.5, -- Execution: the mark locks on the ground this long before the beam
	ExecHeight = 20, -- the execution blaster hovers this high above the locked ground point
	ExecWidth = 6,
	ExecBeamTime = 0.4,
	ExecDropFrom = 16, -- the skull flies in from this much higher still
}
Kit.Constants = C

---------------------------------------------------------------------------------------------------
-- Helpers

local function isFell(model: any): boolean
	return typeof(model) == "Instance" and model:GetAttribute("KitId") == KIT_ID
end

local function hpFraction(model: Model): number
	local hum = Validation.Humanoid(model)
	if hum == nil or hum.MaxHealth <= 0 then
		return 1
	end
	return hum.Health / hum.MaxHealth
end

local function windupOf(ctx: any, default: number): number
	local w = ctx.Ability.Windup
	return if type(w) == "number" then w else default
end

local function immune(StatusService: any, target: Model): boolean
	return StatusService.Has(target, "IFrames")
		or StatusService.Has(target, "Invulnerable")
		or StatusService.Has(target, "Boxed")
end

-- Passive / out-of-cast broadcasts use one context per (Fell model, ability id).
local passiveCtx: { [Model]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

local function passiveFx(model: Model, abilityId: string, phase: string, data: { [string]: any })
	local per = passiveCtx[model]
	if per == nil then
		per = {}
		passiveCtx[model] = per
	end
	local ctx = per[abilityId]
	if ctx == nil then
		local AS = Common.Services().AbilityService
		ctx = if AS and type(AS.ContextFor) == "function" then AS.ContextFor(model, abilityId) else nil
		if ctx == nil then
			return
		end
		per[abilityId] = ctx
	end
	ctx:Fx(phase, data)
end

function Kit.RushPoints(start: Vector3, dir: Vector3, distance: number, count: number): { Vector3 }
	local out: { Vector3 } = {}
	local n = math.max(1, math.floor(count))
	for i = 1, n do
		table.insert(out, start + dir * (distance * (i - 0.5) / n))
	end
	return out
end

function Kit.BlasterSlot(origin: Vector3, flatDir: Vector3): Vector3
	local fwd = Validation.FlatUnit(flatDir, Vector3.new(0, 0, -1))
	local right = Common.Right(fwd)
	local s = C.BlasterSlot
	return origin + right * s[1] + Vector3.yAxis * s[2] - fwd * s[3]
end

-- Beams aim at chest height when the aim point is on (or just above) the ground.
local function chestAim(ctx: any): Vector3
	local aim: Vector3 = ctx.Aim
	local ground = Validation.GroundBelow(aim + Vector3.new(0, 0.5, 0), 3.5)
	if ground then
		return ground + Vector3.new(0, 2.5, 0)
	end
	return aim
end

local function moveDir(ctx: any): Vector3
	local hum = ctx.Humanoid
	if hum then
		local ok, md = pcall(function()
			return hum.MoveDirection
		end)
		if ok and typeof(md) == "Vector3" then
			local flat = Vector3.new(md.X, 0, md.Z)
			if flat.Magnitude > 0.2 then
				return flat.Unit
			end
		end
	end
	return ctx.FlatDir
end

---------------------------------------------------------------------------------------------------
-- Passive hooks (Gold Tooth, Bloodlust lifesteal, Execution vs the weakened)

local hooksInstalled = false

local function installHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true
	local services = Common.Services()
	local StatusService = services.StatusService
	local DamageService = services.DamageService

	Common.InstallHook("FellSans.Before", "Before", function(info: any, _result: any, state: any)
		local attacker = info.Attacker
		if not isFell(attacker) or info.Target == attacker then
			return nil
		end
		local kind = state.Kind
		if kind == "True" or kind == "Box" then
			return nil
		end
		local target: Model = info.Target
		-- Gold Tooth: brutal on the helpless
		if StatusService.Has(target, "Stunned") or StatusService.Has(target, "Rooted") then
			state.Bonus = (if type(state.Bonus) == "number" then state.Bonus else 0) + C.GoldToothBonus
			state.FellGoldTooth = true
		end
		-- Gold Tooth: every hit on a human carries a little KR (DamageService reads info.KR after the hooks)
		if state.TargetTeam == "Humans" then
			info.KR = (if type(info.KR) == "number" then info.KR else 0) + C.GoldToothKR
		end
		-- Execution: the weakened take LowHpMult
		if info.Ability == "Execution" then
			local ability = Kits.Ability(KIT_ID, "Execution")
			local N = if ability and ability.Numbers then ability.Numbers else {}
			if hpFraction(target) < (N.LowHpFraction or 0.35) then
				state.Mult = (if type(state.Mult) == "number" then state.Mult else 1) * (N.LowHpMult or 2)
				state.FellExecute = true
			end
		end
		return nil
	end)

	Common.InstallHook("FellSans.After", "After", function(info: any, result: any, state: any)
		local attacker = info.Attacker
		if not isFell(attacker) or type(result) ~= "table" then
			return nil
		end
		local applied = if type(result.Applied) == "number" then result.Applied else 0
		local target: Model = info.Target
		if applied <= 0 or target == attacker then
			return nil
		end
		local pos = Validation.RootPosition(target)
		if state.FellGoldTooth then
			passiveFx(attacker, "GoldTooth", "Glint", { target = target, pos = pos })
		end
		if state.FellExecute then
			passiveFx(attacker, "Execution", "Executed", { target = target, pos = pos })
		end
		-- Bloodlust: heal a share of the damage dealt while Rage (from Bloodlust: data.lifesteal) is active
		if StatusService.Has(attacker, "Rage") then
			local _, data = StatusService.Get(attacker, "Rage")
			local steal = if data and type(data.lifesteal) == "number" then data.lifesteal else 0
			if steal > 0 then
				local healed = DamageService.Heal(attacker, applied * steal, attacker)
				if healed > 0 then
					passiveFx(attacker, "Bloodlust", "Siphon", { target = target, amount = healed })
				end
			end
		end
		return nil
	end)
end

function Kit.OnSpawn(model: Model, _ctxFactory: any)
	installHooks()
	passiveCtx[model] = nil
end

function Kit.OnDespawn(model: Model)
	passiveCtx[model] = nil
end

---------------------------------------------------------------------------------------------------
-- Bone Cleaver (M1)

Abilities.BoneCleaver = function(ctx: any)
	installHooks()
	local N = ctx.N
	local index = if type(ctx.ComboIndex) == "number" then ctx.ComboIndex else 1
	local comboLength = if type(ctx.Ability.Combo) == "number" then ctx.Ability.Combo else 4
	local last = index >= comboLength
	local windup = windupOf(ctx, 0.14) + (if last then C.FinisherExtraWindup else 0)
	if not ctx:Wait(windup) then
		return
	end
	local root = ctx.Root
	if root == nil or root.Parent == nil then
		return
	end
	local range = N.Range or 7
	local origin = ctx:RootPosition()
	local frame = Melee.Frame(origin, ctx.FlatDir, CFrame.new(0, 0, -range * 0.5))
	local size = Vector3.new(if last then C.FinisherWidth else C.ComboWidth, C.ComboHeight, range)
	local targets = Melee.Query(frame, size, ctx:Enemies(true), { Origin = origin })
	local damage = N["Damage" .. index] or N.Damage1 or N.Damage or 8
	local knockback: Vector3? = nil
	if last then
		local kb = N.Knockback or 45
		knockback = ctx.FlatDir * (kb * C.LaunchForward) + Vector3.new(0, N.KnockbackUp or kb * C.LaunchUp, 0)
	end
	local landed = 0
	for _, target in targets do
		local result = ctx:Damage(target, {
			Amount = damage,
			Kind = "Melee",
			KR = N.KR,
			Knockback = knockback,
			Position = origin,
		})
		if (result.Applied or 0) > 0 or (result.Absorbed or 0) > 0 then
			landed += 1
		end
	end
	ctx:Fx("Strike", { combo = index, last = last, hits = landed })
end

---------------------------------------------------------------------------------------------------
-- Crimson Blaster (Q)

Abilities.CrimsonBlaster = function(ctx: any)
	installHooks()
	local N = ctx.N
	local origin = ctx:RootPosition()
	local fwd = ctx.FlatDir
	local pos = Kit.BlasterSlot(origin, fwd)
	local dir = chestAim(ctx) - pos
	if dir.Magnitude < 4 or Validation.FlatUnit(dir, fwd):Dot(fwd) < 0.1 then
		dir = fwd + Vector3.new(0, -0.05, 0) -- aim too close / behind: fire straight ahead
	end
	local cf = LookAlong(pos, dir)
	local delay = N.Delay or 0.45
	local id = ctx:Hazard("BlasterBeam", {
		origin = cf,
		length = N.Length or 80,
		width = N.Width or 3.5,
		delay = delay,
		duration = N.BeamTime or 0.35,
		damage = N.Damage or 26,
		kr = N.KR or 0,
		color = "Red",
		style = "Fell",
		spawnFrom = origin + Vector3.new(0, 1.5, 0),
	})
	ctx:Fx("Summon", { hazard = id, origin = cf })
	-- counterplay: interrupting Fell during the short charge cancels the shot
	if not ctx:Wait(math.max(0, delay - 0.05)) then
		if id ~= 0 then
			Common.Services().HazardService.Remove(id)
		end
		ctx:Fx("Fizzle", { hazard = id, origin = cf })
	end
end

---------------------------------------------------------------------------------------------------
-- Chain Grab (E)

Abilities.ChainGrab = function(ctx: any)
	installHooks()
	local N = ctx.N
	if not ctx:Wait(windupOf(ctx, 0.25)) then
		return
	end
	local StatusService = Common.Services().StatusService
	local pullTime = math.max(0.05, N.PullTime or 0.35)
	local stun = N.Stun or 0.7
	local damage = N.Damage or 10
	local grabbed = false
	local function onHit(target: Model, _hazardId: number): boolean?
		if grabbed then
			return true
		end
		if target:GetAttribute("Downed") == true or immune(StatusService, target) then
			return nil -- default effect: i-framed humans let the chain fly on, downed humans are finished
		end
		grabbed = true
		local tpos = Validation.RootPosition(target)
		local result = ctx:Damage(target, { Amount = damage, Kind = "Projectile", Color = "Red", Position = tpos })
		local landed = (result.Applied or 0) > 0 or (result.Absorbed or 0) > 0
		if
			not landed
			or result.Blocked
			or result.Parried
			or result.Killed
			or result.Downed
			or tpos == nil
			or not ctx:Alive()
		then
			ctx:Fx("Snap", { target = target, pos = tpos })
			return true
		end
		local from = ctx:RootPosition()
		local to: Vector3 = tpos
		local toward = Validation.FlatUnit(to - from, ctx.FlatDir)
		local dest = from + toward * C.GrabStop
		local delta = dest - to
		ctx:Status(target, "Stunned", pullTime + stun)
		if delta.Magnitude > 0.5 then
			ctx:ForceMove(target, {
				kind = "Pull",
				target = dest,
				velocity = delta.Unit * (delta.Magnitude / pullTime),
				duration = pullTime + C.PullSlack,
			})
		end
		ctx:Fx("Grab", { target = target, time = pullTime, to = dest })
		return true
	end
	-- thrown from the hand toward the aim at chest height, kept roughly level (<= ~25 degrees up / down)
	local start = ctx:RootPosition() + Vector3.new(0, 1, 0) + ctx.FlatDir * 1.5
	local dir = chestAim(ctx) - start
	local flatLen = Vector3.new(dir.X, 0, dir.Z).Magnitude
	if flatLen < 1 then
		dir = ctx.FlatDir
	else
		local maxRise = flatLen * C.ChainMaxSlope
		dir = Vector3.new(dir.X, math.clamp(dir.Y, -maxRise, maxRise), dir.Z)
	end
	local id = ctx:Projectile({
		Origin = LookAlong(start, dir),
		Speed = N.Speed or 90,
		Radius = C.ChainRadius,
		MaxDist = ctx.Ability.Range or 40,
		Visual = "FellChain",
		Damage = damage,
		Color = "Red",
		Hooks = { OnHit = onHit },
	})
	ctx:Fx("Throw", { hazard = id })
end

---------------------------------------------------------------------------------------------------
-- Bone Rush (R)

Abilities.BoneRush = function(ctx: any)
	installHooks()
	local N = ctx.N
	if not ctx:Wait(windupOf(ctx, 0.1)) then
		return
	end
	local StatusService = Common.Services().StatusService
	local start = ctx:RootPosition()
	local dir = ctx.FlatDir
	local distance = Common.ClampPath(start, dir, math.max(0, N.Distance or 26))
	local time = C.RushTime
	local spikeDelay = N.SpikeDelay or 0.35
	local count = math.max(1, math.floor(N.Spikes or 7))
	if distance > 0.5 then
		ctx:ForceMove(ctx.Caster, { kind = "Dash", velocity = dir * (distance / time), duration = time })
	end
	ctx:Fx("Rush", { from = start, to = start + dir * distance, time = time, spikeDelay = spikeDelay, count = count })
	local feetY = Common.Feet(ctx).Y
	local drop = ctx:RootHeight() + 6
	local hitSet: { [Model]: boolean } = {}
	local function onHit(target: Model, _hazardId: number): boolean?
		if hitSet[target] then
			return true -- one hit per human per rush (overlapping clusters)
		end
		if immune(StatusService, target) then
			return nil -- not consumed: the next cluster can still catch them
		end
		hitSet[target] = true
		return nil
	end
	local elapsed = 0
	for i, p in Kit.RushPoints(start, dir, distance, count) do
		-- each cluster is spawned as Fell passes its point (an interrupted rush leaves nothing ahead)
		local passAt = time * (i - 0.5) / count
		if passAt > elapsed then
			if not ctx:Wait(passAt - elapsed) then
				return
			end
			elapsed = passAt
		end
		local ground = Validation.GroundBelow(p, drop) or Vector3.new(p.X, feetY, p.Z)
		ctx:Hazard("BoneSpikes", {
			center = ground,
			radius = C.SpikeRadius,
			count = C.SpikeBones,
			height = C.SpikeHeight,
			delay = spikeDelay,
			rise = 0.08,
			hold = 0.35,
			damage = N.Damage or 14,
			kr = N.KR or 0,
			color = "Red",
			knockbackUp = C.SpikePop,
			seed = (ctx.CastId * 13 + i) % 100000,
		}, { OnHit = onHit })
	end
end

---------------------------------------------------------------------------------------------------
-- Bloodlust (T)

Abilities.Bloodlust = function(ctx: any)
	installHooks()
	local N = ctx.N
	if not ctx:Wait(windupOf(ctx, 0.3)) then
		return
	end
	local duration = N.Duration or 6
	ctx:Status(ctx.Caster, "Rage", duration, {
		damage = N.DamageMult or 1.3,
		speed = N.SpeedMult or 1.2,
		lifesteal = N.Lifesteal or 0.2,
	})
	ctx:Fx("Rage", { duration = duration })
end

---------------------------------------------------------------------------------------------------
-- Lunge (Shift)

Abilities.Lunge = function(ctx: any)
	installHooks()
	local N = ctx.N
	if not ctx:Wait(windupOf(ctx, 0.02)) then
		return
	end
	local start = ctx:RootPosition()
	local dir = moveDir(ctx)
	local distance = Common.ClampPath(start, dir, math.max(0, N.Distance or 18))
	local time = C.LungeTime
	if distance > 0.5 then
		ctx:ForceMove(ctx.Caster, { kind = "Dash", velocity = dir * (distance / time), duration = time })
	end
	ctx:Fx("Dash", { from = start, to = start + dir * distance, time = time })
end

---------------------------------------------------------------------------------------------------
-- Execution (G, ultimate)

Abilities.Execution = function(ctx: any)
	installHooks()
	local N = ctx.N
	local radius = N.Radius or 40
	local delay = math.max(0.2, N.Delay or 1.2)
	local lockLead = math.min(C.ExecLock, delay)
	local beamTime = N.BeamTime or C.ExecBeamTime
	local width = N.Width or C.ExecWidth
	local marked = ctx:EnemiesInRadius(ctx:RootPosition(), radius)
	for _, m in marked do
		ctx:Status(m, "Marked", delay + beamTime)
	end
	ctx:Fx("Mark", { targets = marked, delay = delay, lock = delay - lockLead, radius = radius })
	if not ctx:Wait(delay - lockLead) then
		ctx:Fx("Cancel", { targets = marked })
		return
	end
	local casterPos = ctx:RootPosition()
	local targets: { Model } = {}
	local points: { Vector3 } = {}
	local ids: { number } = {}
	for _, m in marked do
		local p = Validation.RootPosition(m)
		if p and Validation.IsUp(m) then
			local ground = Validation.GroundBelow(p, 16) or (p - Vector3.new(0, 3, 0))
			local top = ground + Vector3.new(0, C.ExecHeight, 0)
			local crown = Validation.FlatUnit(p - casterPos, ctx.FlatDir) -- skull crown faces away from Fell
			table.insert(
				ids,
				ctx:Hazard("BlasterBeam", {
					origin = LookAlong(top, DOWN, crown),
					length = C.ExecHeight + 2,
					width = width,
					delay = lockLead,
					duration = beamTime,
					damage = N.Damage or 32,
					kr = N.KR or 0,
					color = "Red",
					style = "Fell",
					blockable = false,
					spawnFrom = top + Vector3.new(0, C.ExecDropFrom, 0),
				})
			)
			table.insert(targets, m)
			table.insert(points, ground)
		end
	end
	ctx:Fx("Drop", { targets = targets, points = points, hazards = ids, delay = lockLead, width = width })
end

return Kit
