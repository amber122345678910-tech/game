--!strict
-- Server kit: Justice (yellow SOUL) — "The Gunslinger". Ranged DPS. Numbers come from
-- Shared/Kits/Humans/Justice (ctx.N; the Revolver's Ammo / Reload / LongRange* are shared by every shot).
--
-- Ammo (server-authoritative, per character): Ammo rounds of Revolver.Numbers.Ammo; firing the last one starts a
--   Reload s reload that is ALSO set as the Revolver cooldown (AbilityService.SetCooldown), so no cast is accepted
--   mid-reload. Mirrored for the client (CombatController ammo mirror) as model attributes, always written in this
--   order: "ReloadEndsAt" (server time, 0 = not reloading) THEN "Ammo" (the client re-reads both on Ammo changes).
-- Shots are server hitscans: origin = the gun muzzle computed from the caster's root (MUZZLE offset; the root is
--   used when a wall is between them), direction from the muzzle to the validated aim point (+ spread), clamped by
--   world geometry (Validation.Raycast ignores characters), hits = character capsules swept by a BULLET_RADIUS
--   capsule (Combat/Melee.Sweep; first one only unless the shot pierces).
-- Passive "SharpEye": a target more than LongRange studs from the caster takes x LongRangeMult (every Justice shot
--   and the ultimate beam). Shot Fx carry long = true for the gold hit marker.
--
-- Abilities (AbilityFx phases after the automatic "Start"):
--   Revolver (M1)          1 round; Spread deg cone (none when the gun was steady for STEADY_TIME s); Damage.
--                          Fx "Shot" {from, to, hit?, long, primed, ammo}
--   FanTheHammer (Q)       after Windup fans a full cylinder (Ammo shots, Interval apart) sweeping ConeDegrees
--                          left -> right, DamagePerShot each, then the cylinder is empty -> reload.
--                          Fx "Fan" {count, interval, cone}, then "Shot" {..., fan = true} per round
--   QuickRoll (E)          dodge roll (Distance; along the movement direction when moving, else the aim; ROLL_IFRAMES
--                          i-frames), instant reload, status "Primed" {mult = NextShotMult} for PRIMED_TIME: the next
--                          shot (any Justice shot) deals x mult. Fx "Roll" {from, to, time}
--   FinalVerdict (R, ult)  AimTime of aiming (caster Slowed x AIM_SLOW, status "Verdict"): the laser sight tracks
--                          the caster's live aim (AimService.GetAim) at most TURN_RATE rad/s, locks LOCK_TIME s
--                          before firing, then a piercing golden beam (Length, Width; stops at walls): Damage
--                          (Kind Beam, Undodgeable, unblockable) to every enemy on it + DamageService.DrainDodges of
--                          ALL their dodges. Dying / being stunned while aiming cancels it.
--                          Fx "Aim" {dir, time, lock, length, width}, "Track" {dir}, "Lock" {dir},
--                          "Fire" {from, to, width, hits}, "Cancel"
--
-- Extra API (tests / bots): Kit.Ammo(model) -> (ammo, max, reloadEndsAt)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Kits = require(Shared.Kits) :: any

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Melee = require(Combat.Melee) :: any
local Common = require(script.Parent.Common) :: any

local Kit = {}
local Abilities: { [string]: (any) -> () } = {}
Kit.Abilities = Abilities

local KIT_ID = "Justice"
local BULLET_RADIUS = 0.6
local MUZZLE_RIGHT, MUZZLE_UP, MUZZLE_FORWARD = 0.85, 0.65, 1.4
local STEADY_TIME = 0.75
local FAN_JITTER = 1.2 -- degrees of random yaw per fanned round
local ROLL_TIME = 0.28
local ROLL_IFRAMES = 0.22
local ROLL_MOVE_SPEED = 4 -- horizontal speed above which the roll follows the movement
local PRIMED_TIME = 6
local AIM_SLOW = 0.4
local TURN_RATE = math.rad(110)
local LOCK_TIME = 0.25
local TRACK_STEP = 0.1
local TRACK_FX_ANGLE = math.rad(1.5)
local RECOIL = 22

local rng = Random.new()

---------------------------------------------------------------------------------------------------
-- Helpers

local function revolver(): { [string]: number }
	local def = Kits.Ability(KIT_ID, "Revolver")
	return if def and def.Numbers then def.Numbers else {}
end

local function windupOf(ctx: any, default: number): number
	local w = ctx.Ability.Windup
	return if type(w) == "number" then w else default
end

local function landed(result: any): boolean
	return result ~= nil
		and result.Reason == nil
		and not result.Dodged
		and not result.Parried
		and ((result.Applied or 0) > 0 or (result.Absorbed or 0) > 0)
end

local function rotateYaw(dir: Vector3, angle: number): Vector3
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(dir.X * c - dir.Z * s, dir.Y, dir.X * s + dir.Z * c)
end

-- Rodrigues rotation of unit `a` toward unit `b` by at most maxAngle radians.
local function turnToward(a: Vector3, b: Vector3, maxAngle: number): Vector3
	local dot = math.clamp(a:Dot(b), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle or angle < 1e-5 then
		return b
	end
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-5 then
		axis = Vector3.yAxis
	end
	axis = axis.Unit
	local c, s = math.cos(maxAngle), math.sin(maxAngle)
	local v = a * c + axis:Cross(a) * s + axis * (axis:Dot(a) * (1 - c))
	return v.Unit
end

local function spreadDir(dir: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return dir
	end
	local right = dir:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(dir).Unit
	local a = rng:NextNumber() * math.pi * 2
	local r = math.sqrt(rng:NextNumber()) * math.tan(math.rad(degrees))
	return (dir + right * (math.cos(a) * r) + up * (math.sin(a) * r)).Unit
end

-- Gun muzzle for a caster facing `flat` (wall-safe: falls back to the root when the muzzle is behind a wall).
local function muzzleAt(ctx: any, flat: Vector3): Vector3
	local root = ctx:RootPosition()
	local muzzle = root + Common.Right(flat) * MUZZLE_RIGHT + Vector3.new(0, MUZZLE_UP, 0) + flat * MUZZLE_FORWARD
	if Validation.Raycast(root, muzzle - root) then
		return root + Vector3.new(0, MUZZLE_UP, 0)
	end
	return muzzle
end

-- Direction from the muzzle to the validated aim point (falls back to the cast direction for degenerate aims).
local function aimFrom(ctx: any, origin: Vector3): Vector3
	local delta = ctx.Aim - origin
	if delta.Magnitude < 3 then
		return ctx.AimDir
	end
	local dir = delta.Unit
	if Validation.FlatUnit(dir, ctx.FlatDir):Dot(ctx.FlatDir) < 0.2 then
		return ctx.AimDir
	end
	return dir
end

-- SharpEye multiplier for a target (and whether it applied).
local function sharpEye(ctx: any, target: Model): (number, boolean)
	local N = revolver()
	local a = ctx:RootPosition()
	local b = Validation.RootPosition(target)
	if b and (b - a).Magnitude > (N.LongRange or 30) then
		return N.LongRangeMult or 1.15, true
	end
	return 1, false
end

-- Consumes the QuickRoll "Primed" bonus (1 when none).
local function takePrimed(ctx: any): number
	local StatusService = Common.Services().StatusService
	if not StatusService.Has(ctx.Caster, "Primed") then
		return 1
	end
	local _, data = StatusService.Get(ctx.Caster, "Primed")
	StatusService.Remove(ctx.Caster, "Primed")
	return if data and type(data.mult) == "number" then data.mult else 1.5
end

---------------------------------------------------------------------------------------------------
-- Ammo state

type Gun = { Ammo: number, Max: number, ReloadEndsAt: number, Token: number, LastShot: number }

local guns: { [Model]: Gun } = setmetatable({}, { __mode = "k" }) :: any

local function gunOf(model: Model): Gun
	local g = guns[model]
	if g == nil then
		local max = math.max(1, math.floor(revolver().Ammo or 6))
		g = { Ammo = max, Max = max, ReloadEndsAt = 0, Token = 0, LastShot = -math.huge }
		guns[model] = g
	end
	return g
end

local function publish(model: Model, g: Gun)
	if model.Parent == nil then
		return
	end
	model:SetAttribute("ReloadEndsAt", if g.ReloadEndsAt > 0 then g.ReloadEndsAt else 0)
	model:SetAttribute("Ammo", g.Ammo)
end

local function finishReload(model: Model, g: Gun)
	g.Token += 1
	g.Ammo = g.Max
	g.ReloadEndsAt = 0
	publish(model, g)
end

local function startReload(model: Model, g: Gun)
	local reload = revolver().Reload or 1.6
	g.Token += 1
	local token = g.Token
	g.Ammo = 0
	g.ReloadEndsAt = Validation.Now() + reload
	publish(model, g)
	Common.Services().AbilityService.SetCooldown(model, "Revolver", reload)
	Validation.Delay(reload, function()
		if guns[model] == g and g.Token == token then
			finishReload(model, g)
		end
	end)
end

function Kit.Ammo(model: Model): (number, number, number)
	local g = gunOf(model)
	return g.Ammo, g.Max, g.ReloadEndsAt
end

function Kit.OnSpawn(model: Model, _ctxFactory: any)
	guns[model] = nil
	publish(model, gunOf(model))
end

function Kit.OnDespawn(model: Model)
	guns[model] = nil
end

---------------------------------------------------------------------------------------------------
-- Hitscan

type ShotOpts = { Pierce: boolean?, Fan: boolean? }

-- Fires one round from `origin` along unit `dir`; returns the models hit.
local function fire(ctx: any, origin: Vector3, dir: Vector3, range: number, damage: number, opts: ShotOpts?): { Model }
	local o: ShotOpts = opts or {}
	local wall = Validation.Raycast(origin, dir * range)
	local length = if wall then (wall.Position - origin).Magnitude else range
	local stop = origin + dir * length
	local hits = Melee.Sweep(origin, stop, BULLET_RADIUS, ctx:Enemies(true))
	if not o.Pierce and #hits > 1 then
		hits = { hits[1] }
	end
	if not o.Pierce and hits[1] then
		local p = Validation.RootPosition(hits[1])
		if p then
			stop = origin + dir * math.clamp((p - origin):Dot(dir), 0, length)
		end
	end
	local primed = takePrimed(ctx)
	local long = false
	local victim: Model? = nil
	for _, m in hits do
		local mult, isLong = sharpEye(ctx, m)
		long = long or isLong
		local r = ctx:Damage(m, { Amount = damage * primed * mult, Kind = "Projectile", Position = origin })
		if landed(r) and victim == nil then
			victim = m
		end
	end
	ctx:Fx("Shot", {
		from = origin,
		to = stop,
		hit = victim,
		long = long,
		primed = primed > 1,
		fan = o.Fan == true,
		ammo = gunOf(ctx.Caster).Ammo,
	})
	return hits
end

---------------------------------------------------------------------------------------------------
-- Revolver (M1)

Abilities.Revolver = function(ctx: any)
	local N = ctx.N
	local caster = ctx.Caster
	local g = gunOf(caster)
	if g.Ammo <= 0 then
		if g.ReloadEndsAt <= 0 then
			startReload(caster, g)
		end
		return
	end
	local now = ctx:Now()
	local steady = now - g.LastShot >= STEADY_TIME
	g.LastShot = now
	g.Ammo -= 1
	if g.Ammo <= 0 then
		startReload(caster, g)
	else
		publish(caster, g)
	end
	local origin = muzzleAt(ctx, ctx.FlatDir)
	local dir = aimFrom(ctx, origin)
	if not steady then
		dir = spreadDir(dir, N.Spread or 0.6)
	end
	fire(ctx, origin, dir, if type(ctx.Ability.Range) == "number" then ctx.Ability.Range else 120, N.Damage or 8)
end

---------------------------------------------------------------------------------------------------
-- FanTheHammer (Q)

Abilities.FanTheHammer = function(ctx: any)
	local N = ctx.N
	local caster = ctx.Caster
	if not ctx:Wait(windupOf(ctx, 0.05)) then
		return
	end
	local g = gunOf(caster)
	local shots = g.Max
	local interval = math.max(0.02, N.Interval or 0.07)
	local cone = N.ConeDegrees or 12
	local range = if type(ctx.Ability.Range) == "number" then ctx.Ability.Range else 60
	g.Token += 1 -- a pending reload is superseded: the hammer fans a full cylinder
	g.ReloadEndsAt = 0
	ctx:Fx("Fan", { count = shots, interval = interval, cone = cone })
	for i = 1, shots do
		if i > 1 and not ctx:Wait(interval) then
			break
		end
		g.Ammo = shots - i
		g.LastShot = ctx:Now()
		publish(caster, g)
		local frac = if shots == 1 then 0.5 else (i - 1) / (shots - 1)
		local yaw = math.rad((frac - 0.5) * cone + (rng:NextNumber() - 0.5) * FAN_JITTER)
		local origin = muzzleAt(ctx, ctx.FlatDir)
		fire(ctx, origin, rotateYaw(aimFrom(ctx, origin), yaw), range, N.DamagePerShot or 8, { Fan = true })
	end
	if Validation.IsAlive(caster) then
		startReload(caster, g)
	end
end

---------------------------------------------------------------------------------------------------
-- QuickRoll (E)

Abilities.QuickRoll = function(ctx: any)
	local N = ctx.N
	local caster = ctx.Caster
	local from = ctx:RootPosition()
	local dir = ctx.FlatDir
	local vel = Validation.Velocity(caster)
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	if flatVel.Magnitude > ROLL_MOVE_SPEED then
		dir = flatVel.Unit
	end
	local distance = Common.ClampPath(from, dir, N.Distance or 12)
	ctx:Status(caster, "IFrames", ROLL_IFRAMES)
	if distance > 0.5 then
		ctx:ForceMove(caster, { kind = "Dash", velocity = dir * (distance / ROLL_TIME), duration = ROLL_TIME })
	end
	ctx:Fx("Roll", { from = from, to = from + dir * distance, time = ROLL_TIME })
	finishReload(caster, gunOf(caster))
	Common.Services().AbilityService.SetCooldown(caster, "Revolver", 0)
	ctx:Status(caster, "Primed", PRIMED_TIME, { mult = N.NextShotMult or 1.5 })
end

---------------------------------------------------------------------------------------------------
-- FinalVerdict (R, ultimate)

Abilities.FinalVerdict = function(ctx: any)
	local N = ctx.N
	local caster = ctx.Caster
	local aimTime = math.max(0.3, N.AimTime or 1.2)
	local lock = math.min(LOCK_TIME, aimTime * 0.5)
	local length = N.Length or 120
	local width = N.Width or 3
	local dir: Vector3 = ctx.AimDir
	ctx:Status(caster, "Verdict", aimTime + 0.8)
	ctx:Status(caster, "Slowed", aimTime, { mult = AIM_SLOW })
	ctx:Fx("Aim", { dir = dir, time = aimTime, lock = lock, length = length, width = width })

	-- tracking: follow the live aim at a readable turn rate
	local AimService = Validation.Service("AimService")
	local trackTime = aimTime - lock
	local tracked = 0
	local lastSent = dir
	while tracked < trackTime - 1e-6 do
		local step = math.min(TRACK_STEP, trackTime - tracked)
		if not ctx:Wait(step) then
			ctx:Fx("Cancel")
			return
		end
		tracked += step
		local point = if AimService and type(AimService.GetAim) == "function" then AimService.GetAim(caster) else nil
		if typeof(point) == "Vector3" then
			local origin = muzzleAt(ctx, Validation.FlatUnit(dir, ctx.FlatDir))
			local want = Validation.Unit(point - origin, dir)
			dir = turnToward(dir, want, TURN_RATE * step)
			if math.acos(math.clamp(dir:Dot(lastSent), -1, 1)) > TRACK_FX_ANGLE then
				lastSent = dir
				ctx:Fx("Track", { dir = dir })
			end
		end
	end
	ctx:Fx("Lock", { dir = dir })
	if not ctx:Wait(lock) then
		ctx:Fx("Cancel")
		return
	end

	-- fire
	local flat = Validation.FlatUnit(dir, ctx.FlatDir)
	local origin = muzzleAt(ctx, flat)
	local wall = Validation.Raycast(origin, dir * length)
	local stop = if wall then wall.Position else origin + dir * length
	local DamageService = Common.Services().DamageService
	local hitList: { Model } = {}
	for _, m in Melee.Sweep(origin, stop, width * 0.5, ctx:Enemies(true)) do
		local mult = sharpEye(ctx, m) -- (Primed is for gun shots; the ultimate stays predictable)
		local r = ctx:Damage(m, {
			Amount = (N.Damage or 45) * mult,
			Kind = "Beam",
			Undodgeable = true,
			Blockable = false,
			Position = origin,
		})
		if landed(r) then
			table.insert(hitList, m)
			local dodges = m:GetAttribute("Dodges")
			if type(dodges) == "number" and dodges > 0 then
				DamageService.DrainDodges(m, dodges, caster)
			end
		end
	end
	ctx:Fx("Fire", { from = origin, to = stop, width = width, hits = hitList })
	ctx:ForceMove(caster, { kind = "Impulse", velocity = -flat * RECOIL, duration = 0.15 })
end

return Kit
