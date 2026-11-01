--!strict
-- HazardDefs: deterministic hazard geometry shared by the server (hit tests) and clients (visuals).
-- Lune-safe. A hazard is fully described by (type, params, t) where t = now - t0 (server time).
-- Server: HazardService samples Volumes(params, t) every Heartbeat. Clients: HazardVisuals renders
-- from the SAME params (+ the layout helpers below) so what you see is what hits you.
--
-- Shapes (Types.Volume, see Combat/HitTest.luau): Box (Size = extents), Ball (Size.X = diameter),
-- Capsule (axis = CFrame.UpVector, Size.X = diameter, Size.Y = tip-to-tip length),
-- Cylinder (axis = UpVector, Size.X = diameter, Size.Y = height), Ring (annulus: Size.X = outer diameter,
-- Size.Y = height, Size.Z = band thickness).
--
-- COMMON PARAMS (every type; defaults in brackets)
--   delay: number [type default]   telegraph time: damage starts at t = delay
--   warn: number [= delay]         telegraph lead time: telegraph shown during [delay - warn, delay]
--   telegraph: boolean [true]      false = no telegraph (traps, stealth)
--   color: ColorRule ["White"]     "White"|"Blue"|"Orange"|"Red"|"Purple"|"Yellow"|"Green"|"Cyan" (Blue/Orange
--                                  apply the movement rule on the server; all colours tint visuals)
--   damage: number [10]  kr: number [0]  stun: number [0] (seconds)
--   knockback: number [0] (studs/s, horizontal: along travel for beams/lines/projectiles, away from the
--                          centre for area types)   knockbackUp: number [0] (studs/s upward)
--   undodgeable: boolean [false]   dodgeable: boolean [true]   blockable: boolean [Beam/Projectile true, else false]
--   style: string ["Classic"]      visual variant ("Classic"|"Fell"|"Eclipse"|kit-defined)
--   ability: string [""]           ability id for kill feed / stats
--   kind: string [by type]         damage kind override ("Beam"|"Projectile"|"Area"|"True")
--
-- TYPES (geometry is exact; "origin" CFrames: Position = anchor, LookVector = forward)
-- BlasterBeam  origin: CFrame (blaster skull at muzzle, LookVector = beam direction), offset [1] (beam
--              starts at origin.Position + LookVector*offset), length [60], width [4] (beam diameter),
--              delay [0.6] (charge), duration [0.5] (firing), tick [0] (>0 = re-hit every tick s, 0 = once),
--              linger [0.35] (visual fade, no damage), spawnFrom: Vector3? (visual only: skull flies in from
--              here during the first 0.25 s).
--              Damage volume during [delay, delay+duration]: Capsule from beam start to start+length*Look,
--              diameter = width.
-- BoneLine     origin: CFrame (row centre ON THE GROUND, LookVector = travel, RightVector = row axis),
--              count [9], spacing [2.5], height [5] (bone height above origin), boneThickness [0.8],
--              speed [30], distance [60], delay [0.5], linger [0.25], gaps: {number}? (1-based indices of
--              bones that are missing). Bone i (1..count) sits at local X = (i - (count+1)/2)*spacing;
--              the row starts moving at t = delay: travel(t) = (t - delay)*speed (<= distance).
--              Volumes: one Box per bone (thickness x height x thickness), Key = i.
-- BoneSpikes   center: Vector3 (ground point), radius [8], count [14], height [5], boneThickness [0.9],
--              delay [0.6], rise [0.12] (time to full height), hold [0.45], retract [0.2] (visual only),
--              ring: boolean [false], ringWidth [3], seed [0] (layout jitter).
--              Height(t) = height * clamp((t - delay)/rise, 0, 1) during [delay, delay+rise+hold].
--              Volume: ring=false -> Cylinder radius `radius`; ring=true -> Ring with outer radius
--              radius + ringWidth/2 and band ringWidth; both from the ground up to Height(t).
--              Visual layout: HazardDefs.SpikeLayout(params).
-- BoneProjectile origin: CFrame (start, LookVector = flight), speed [60], length [3.5] (bone length),
--              thickness [0.7], maxDist [60], delay [0.15] (held before launch), spin [0] (rad/s about the
--              flight axis), pierce [false] (false = ends on first hit).
--              Bone axis at time t: origin.RightVector rotated by spin*(t-delay) about LookVector.
--              Volume: Capsule (diameter thickness, length `length`) centred on the bone.
-- Projectile   origin: CFrame, speed [80], radius [0.6], maxDist [60], delay [0], gravity [0] (studs/s^2
--              down), visual ["Orb"] (registered client visual), pierce [false].
--              Position(tau) = origin.Position + Look*speed*tau - (0, gravity*tau^2/2, 0), tau = t - delay,
--              flight time = maxDist/speed. Volume: Ball, diameter 2*radius.
-- Shockwave    center: Vector3 (ground), maxRadius [14], speed [28], height [2.5] (jump over it!),
--              thickness [2] (band), delay [0.3], linger [0.15].
--              Front radius R(t) = (t - delay)*speed while R <= maxRadius. Volume: Ring outer R,
--              band min(thickness, R), from the ground up to height.
-- Orb          center: Vector3 (orb centre), radius [12] (pull radius), delay [0.4], duration [2.5] (pull),
--              pullStrength [14] (studs/s toward centre, applied by HazardService as ForceMove "Pull"),
--              implodeDamage [= damage], implodeRadius [= radius], implodeTime [0.15], linger [0.4],
--              visual ["Orb"]. Volume: Ball (diameter 2*implodeRadius) during
--              [delay+duration, delay+duration+implodeTime]. HazardDefs.Effect() describes the pull.
-- Zone         center: Vector3 (ground), radius [9], height [6], delay [0.3], duration [5], tick [0.5],
--              effect ["Damage"] ("Damage"|"Heal"|"Slow"|"Mark"), amount [Damage: damage, Heal: 5 HP/tick,
--              Slow: 0.6 speed mult, Mark: 3 s], affects ["Enemies"; "Allies" for Heal] ("Enemies"|"Allies"|
--              "All"), cleanseKR [0] (Heal: KR removed per tick), visual ["Zone"], linger [0.3].
--              Volume: Cylinder radius x height on the ground during [delay, delay+duration], re-hit every tick.
-- Rain         center: Vector3 (ground), radius [14], count [10], interval [0.15], delay [0.6] (first impact),
--              fallHeight [30], fallTime [0.35] (visual fall duration), size [3] (impact radius),
--              impactHeight [4], impactTime [0.12], visual ["Bone"], seed [1], linger [0.3].
--              Drop i: impact at t_i = delay + (i-1)*interval at a point uniform in the disc (Util/Rng from
--              seed). Volume: Cylinder (radius size, impactHeight) during [t_i, t_i + impactTime], Key = i;
--              each drop hits each target at most once. Layout: HazardDefs.RainDrops(params).
--
-- API
--   HazardDefs[type] / HazardDefs.Get(type) -> HazardDef { Duration(p), Volumes(p, t), HitPolicy(p) }
--   HazardDefs.Types -> {string}
--   HazardDefs.Normalize(type, params) -> params'     copy with every documented default filled in
--   HazardDefs.Validate(type, params) -> (ok, err?)   type-checks present keys against the defaults
--   HazardDefs.IsPlainData(params) -> (ok, badKey?)   only numbers/strings/booleans/Vector3/CFrame/Color3 and
--                                                     arrays of those (safe to send in a packet)
--   HazardDefs.ActiveWindow(type, params) -> (start, finish)    when damage can happen
--   HazardDefs.DamageKind(type, params) -> "Beam"|"Projectile"|"Area"|...
--   HazardDefs.IsProjectile(type) -> boolean
--   HazardDefs.Telegraph(type, params) -> TelegraphDesc (see type below; times relative to t0)
--   HazardDefs.Effect(type, params, t) -> EffectDesc?  non-damage effect active at t (Orb pull)
--   HazardDefs.KnockbackDir(type, params, t, targetPos) -> Vector3 (unit, horizontal)
--   HazardDefs.Defaults(type) -> params?               the type's default table (read-only)
--   HazardDefs.SpikeLayout(params) -> { {Offset: Vector3, Height: number, Tilt: Vector3} }  (cached;
--                                                     Offset from center on the ground, Height = full height,
--                                                     Tilt = unit axis of the spike)
--   HazardDefs.SpikeHeight(params, t) -> number        current spike height (0 outside the damage window)
--   HazardDefs.ShockwaveRadius(params, t) -> number?   current wave-front radius
--   HazardDefs.RainDrops(params) -> { {Position: Vector3, ImpactTime: number, Radius: number} } (cached)
--   HazardDefs.BoneLineBones(params, t) -> { {Index: number, CFrame: CFrame} }  bone centres (any t)
--   HazardDefs.ProjectileFrame(type, params, t) -> (CFrame?, traveled)  flying object pose; for
--                                                     BoneProjectile UpVector = bone axis
--   HazardDefs.BeamStart(params) -> Vector3
--   HazardDefs.LookAlong(pos, dir, up?) -> CFrame      robust look-at (LookVector = dir)
--   HazardDefs.AxisFrame(pos, axis) -> CFrame          frame whose UpVector = axis
--   HazardDefs.Register(name, def, defaults?)          add a custom type (call from a shared module)

local Types = require(script.Parent.Parent.Types)
local Rng = require(script.Parent.Parent.Util.Rng)

type Params = { [string]: any }
type Volume = Types.Volume
export type HazardDef = Types.HazardDef

export type TelegraphDesc = {
	-- "None"; "Circle" (filled disc on the ground); "Ring" (annulus); "Lane" (flat ground strip from
	-- CFrame.Position along LookVector, Length long, Width wide); "Beam" (3D warning ray from CFrame.Position
	-- along LookVector, Length, Width = diameter); "Multi" (Items, each with its own Start/End)
	Kind: string,
	Color: string,
	Start: number,
	End: number,
	Center: Vector3?,
	Radius: number?,
	InnerRadius: number?,
	CFrame: CFrame?,
	Length: number?,
	Width: number?,
	Items: { TelegraphDesc }?,
}

export type EffectDesc = {
	Kind: string, -- "Pull"
	Center: Vector3,
	Radius: number,
	Strength: number,
}

export type SpikeInfo = { Offset: Vector3, Height: number, Tilt: Vector3 }
export type RainDrop = { Position: Vector3, ImpactTime: number, Radius: number }

local HazardDefs: { [string]: any } = {}

local DEFS: { [string]: HazardDef } = {}
local DEFAULTS: { [string]: Params } = {}
local ORDER: { string } = {}

HazardDefs.Types = ORDER

local COMMON: Params = {
	color = "White",
	damage = 10,
	kr = 0,
	stun = 0,
	knockback = 0,
	knockbackUp = 0,
	undodgeable = false,
	dodgeable = true,
	telegraph = true,
	style = "Classic",
	ability = "",
}

---------------------------------------------------------------------------------------------------
-- Param readers: value from params, else the type's defaults `d`, else COMMON.

local function get(p: Params, d: Params, key: string): any
	local v = p[key]
	if v ~= nil then
		return v
	end
	v = d[key]
	if v ~= nil then
		return v
	end
	return COMMON[key]
end

local function num(p: Params, d: Params, key: string, fallback: number?): number
	local v = get(p, d, key)
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return fallback or 0
end

local function bool(p: Params, d: Params, key: string): boolean
	return get(p, d, key) == true
end

local function vec(p: Params, d: Params, key: string): Vector3
	local v = get(p, d, key)
	if typeof(v) == "Vector3" then
		return v
	end
	return Vector3.zero
end

local function cfr(p: Params, d: Params, key: string): CFrame
	local v = get(p, d, key)
	if typeof(v) == "CFrame" then
		return v
	end
	return CFrame.identity
end

local function str(p: Params, d: Params, key: string): string
	local v = get(p, d, key)
	if type(v) == "string" then
		return v
	end
	return ""
end

---------------------------------------------------------------------------------------------------
-- Frames

local function lookAlong(pos: Vector3, dir: Vector3, upHint: Vector3?): CFrame
	local look = if dir.Magnitude > 1e-6 then dir.Unit else Vector3.new(0, 0, -1)
	local up = upHint or Vector3.yAxis
	local right = look:Cross(up)
	if right.Magnitude < 1e-4 then
		right = look:Cross(Vector3.zAxis)
		if right.Magnitude < 1e-4 then
			right = look:Cross(Vector3.xAxis)
		end
	end
	right = right.Unit
	local up2 = right:Cross(look).Unit
	return CFrame.fromMatrix(pos, right, up2)
end

local function axisFrame(pos: Vector3, axis: Vector3): CFrame
	local up = if axis.Magnitude > 1e-6 then axis.Unit else Vector3.yAxis
	local ref = if math.abs(up.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local right = up:Cross(ref).Unit
	return CFrame.fromMatrix(pos, right, up)
end

HazardDefs.LookAlong = lookAlong
HazardDefs.AxisFrame = axisFrame

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return fallback
	end
	return f.Unit
end

local function clamp01(x: number): number
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

local EMPTY: { Volume } = table.freeze({}) :: any

local function register(name: string, def: HazardDef, defaults: Params)
	DEFS[name] = def
	DEFAULTS[name] = defaults
	HazardDefs[name] = def
	if not table.find(ORDER, name) then
		table.insert(ORDER, name)
	end
end

---------------------------------------------------------------------------------------------------
-- BlasterBeam

local D_BEAM: Params = {
	origin = CFrame.identity,
	offset = 1,
	length = 60,
	width = 4,
	delay = 0.6,
	duration = 0.5,
	tick = 0,
	linger = 0.35,
	blockable = true,
	kind = "Beam",
}

local function beamStart(p: Params): Vector3
	local o = cfr(p, D_BEAM, "origin")
	return o.Position + o.LookVector * num(p, D_BEAM, "offset")
end

register("BlasterBeam", {
	Duration = function(p: Params): number
		return num(p, D_BEAM, "delay") + num(p, D_BEAM, "duration") + num(p, D_BEAM, "linger")
	end,
	Volumes = function(p: Params, t: number): { Volume }
		local delay = num(p, D_BEAM, "delay")
		if t < delay or t > delay + num(p, D_BEAM, "duration") then
			return EMPTY
		end
		local o = cfr(p, D_BEAM, "origin")
		local look = o.LookVector
		local length = math.max(0.1, num(p, D_BEAM, "length"))
		local width = math.max(0.1, num(p, D_BEAM, "width"))
		local centre = o.Position + look * (num(p, D_BEAM, "offset") + length * 0.5)
		return { { Shape = "Capsule", CFrame = axisFrame(centre, look), Size = Vector3.new(width, length, width) } }
	end,
	HitPolicy = function(p: Params)
		local tick = num(p, D_BEAM, "tick")
		if tick > 0 then
			return { Once = false, Interval = math.max(0.05, tick) }
		end
		return { Once = true }
	end,
}, D_BEAM)

---------------------------------------------------------------------------------------------------
-- BoneLine

local D_LINE: Params = {
	origin = CFrame.identity,
	count = 9,
	spacing = 2.5,
	height = 5,
	boneThickness = 0.8,
	speed = 30,
	distance = 60,
	delay = 0.5,
	linger = 0.25,
	blockable = false,
	kind = "Area",
}

local function lineCount(p: Params): number
	return math.clamp(math.floor(num(p, D_LINE, "count")), 1, 200)
end

local function lineTravelTime(p: Params): number
	return num(p, D_LINE, "distance") / math.max(0.01, num(p, D_LINE, "speed"))
end

local function gapSet(p: Params): { [number]: boolean }
	local set = {}
	local g = p.gaps
	if type(g) == "table" then
		for _, i in g do
			if type(i) == "number" then
				set[math.floor(i)] = true
			end
		end
	end
	return set
end

function HazardDefs.BoneLineBones(p: Params, t: number): { { Index: number, CFrame: CFrame } }
	local out = {}
	local o = cfr(p, D_LINE, "origin")
	local count = lineCount(p)
	local spacing = num(p, D_LINE, "spacing")
	local height = num(p, D_LINE, "height")
	local speed = math.max(0.01, num(p, D_LINE, "speed"))
	local travel = math.clamp((t - num(p, D_LINE, "delay")) * speed, 0, num(p, D_LINE, "distance"))
	local gaps = gapSet(p)
	for i = 1, count do
		if not gaps[i] then
			local x = (i - (count + 1) * 0.5) * spacing
			table.insert(out, { Index = i, CFrame = o * CFrame.new(x, height * 0.5, -travel) })
		end
	end
	return out
end

register("BoneLine", {
	Duration = function(p: Params): number
		return num(p, D_LINE, "delay") + lineTravelTime(p) + num(p, D_LINE, "linger")
	end,
	Volumes = function(p: Params, t: number): { Volume }
		local delay = num(p, D_LINE, "delay")
		if t < delay or t > delay + lineTravelTime(p) then
			return EMPTY
		end
		local thick = math.max(0.05, num(p, D_LINE, "boneThickness"))
		local size = Vector3.new(thick, math.max(0.05, num(p, D_LINE, "height")), thick)
		local out: { Volume } = {}
		for _, bone in HazardDefs.BoneLineBones(p, t) do
			table.insert(out, { Shape = "Box", CFrame = bone.CFrame, Size = size, Key = bone.Index })
		end
		return out
	end,
	HitPolicy = function(_p: Params)
		return { Once = true }
	end,
}, D_LINE)

---------------------------------------------------------------------------------------------------
-- BoneSpikes

local D_SPIKES: Params = {
	center = Vector3.zero,
	radius = 8,
	count = 14,
	height = 5,
	boneThickness = 0.9,
	delay = 0.6,
	rise = 0.12,
	hold = 0.45,
	retract = 0.2,
	ring = false,
	ringWidth = 3,
	seed = 0,
	blockable = false,
	kind = "Area",
}

-- Current spike height (0 outside the damaging window).
function HazardDefs.SpikeHeight(p: Params, t: number): number
	local delay = num(p, D_SPIKES, "delay")
	local rise = num(p, D_SPIKES, "rise")
	if t < delay or t > delay + rise + num(p, D_SPIKES, "hold") then
		return 0
	end
	local frac = if rise > 0 then clamp01((t - delay) / rise) else 1
	return num(p, D_SPIKES, "height") * frac
end

local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
local spikeCache: { [Params]: { SpikeInfo } } = setmetatable({}, { __mode = "k" }) :: any

function HazardDefs.SpikeLayout(p: Params): { SpikeInfo }
	local cached = spikeCache[p]
	if cached then
		return cached
	end
	local list: { SpikeInfo } = {}
	local count = math.clamp(math.floor(num(p, D_SPIKES, "count")), 1, 200)
	local radius = num(p, D_SPIKES, "radius")
	local height = num(p, D_SPIKES, "height")
	local rng = Rng.new(Rng.Hash("BoneSpikes", num(p, D_SPIKES, "seed")))
	local rot = rng:Number(0, 2 * math.pi)
	if bool(p, D_SPIKES, "ring") then
		local width = num(p, D_SPIKES, "ringWidth")
		for i = 0, count - 1 do
			local a = rot + 2 * math.pi * i / count
			local r = radius + rng:Number(-0.25, 0.25) * width
			local lean = rng:Number(0, 0.18)
			table.insert(list, {
				Offset = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r),
				Height = height * rng:Number(0.85, 1.12),
				Tilt = Vector3.new(math.cos(a) * lean, 1, math.sin(a) * lean).Unit,
			})
		end
	else
		for i = 0, count - 1 do
			local r = radius * math.sqrt((i + 0.5) / count)
			local a = rot + i * GOLDEN_ANGLE
			table.insert(list, {
				Offset = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r),
				Height = height * rng:Number(0.8, 1.15),
				Tilt = Vector3.new(rng:Number(-0.15, 0.15), 1, rng:Number(-0.15, 0.15)).Unit,
			})
		end
	end
	spikeCache[p] = list
	return list
end

register("BoneSpikes", {
	Duration = function(p: Params): number
		return num(p, D_SPIKES, "delay") + num(p, D_SPIKES, "rise") + num(p, D_SPIKES, "hold") + num(p, D_SPIKES, "retract")
	end,
	Volumes = function(p: Params, t: number): { Volume }
		local h = HazardDefs.SpikeHeight(p, t)
		if h <= 0.05 then
			return EMPTY
		end
		local centre = vec(p, D_SPIKES, "center") + Vector3.new(0, h * 0.5, 0)
		local radius = math.max(0.1, num(p, D_SPIKES, "radius"))
		if bool(p, D_SPIKES, "ring") then
			local band = math.max(0.1, num(p, D_SPIKES, "ringWidth"))
			local outer = radius + band * 0.5
			return { { Shape = "Ring", CFrame = CFrame.new(centre), Size = Vector3.new(outer * 2, h, band) } }
		end
		return { { Shape = "Cylinder", CFrame = CFrame.new(centre), Size = Vector3.new(radius * 2, h, radius * 2) } }
	end,
	HitPolicy = function(_p: Params)
		return { Once = true }
	end,
}, D_SPIKES)

---------------------------------------------------------------------------------------------------
-- BoneProjectile

local D_BONEPROJ: Params = {
	origin = CFrame.identity,
	speed = 60,
	length = 3.5,
	thickness = 0.7,
	maxDist = 60,
	delay = 0.15,
	spin = 0,
	pierce = false,
	blockable = true,
	kind = "Projectile",
}

local function boneProjectileFrame(p: Params, t: number): (CFrame?, number)
	local speed = math.max(0.01, num(p, D_BONEPROJ, "speed"))
	local maxDist = num(p, D_BONEPROJ, "maxDist")
	local tau = t - num(p, D_BONEPROJ, "delay")
	if tau > maxDist / speed then
		return nil, maxDist
	end
	tau = math.max(0, tau)
	local o = cfr(p, D_BONEPROJ, "origin")
	local traveled = tau * speed
	local pos = o.Position + o.LookVector * traveled
	local phi = num(p, D_BONEPROJ, "spin") * tau
	local axis = o.RightVector * math.cos(phi) + o.UpVector * math.sin(phi)
	return axisFrame(pos, axis), traveled
end

register("BoneProjectile", {
	Duration = function(p: Params): number
		return num(p, D_BONEPROJ, "delay") + num(p, D_BONEPROJ, "maxDist") / math.max(0.01, num(p, D_BONEPROJ, "speed"))
	end,
	Volumes = function(p: Params, t: number): { Volume }
		if t < num(p, D_BONEPROJ, "delay") then
			return EMPTY
		end
		local frame = boneProjectileFrame(p, t)
		if not frame then
			return EMPTY
		end
		local thick = math.max(0.05, num(p, D_BONEPROJ, "thickness"))
		local length = math.max(thick, num(p, D_BONEPROJ, "length"))
		return { { Shape = "Capsule", CFrame = frame, Size = Vector3.new(thick, length, thick) } }
	end,
	HitPolicy = function(_p: Params)
		return { Once = true }
	end,
}, D_BONEPROJ)

---------------------------------------------------------------------------------------------------
-- Projectile

local D_PROJ: Params = {
	origin = CFrame.identity,
	speed = 80,
	radius = 0.6,
	maxDist = 60,
	delay = 0,
	gravity = 0,
	visual = "Orb",
	pierce = false,
	blockable = true,
	kind = "Projectile",
}

local function projectileFrame(p: Params, t: number): (CFrame?, number)
	local speed = math.max(0.01, num(p, D_PROJ, "speed"))
	local maxDist = num(p, D_PROJ, "maxDist")
	local tau = t - num(p, D_PROJ, "delay")
	if tau > maxDist / speed then
		return nil, maxDist
	end
	tau = math.max(0, tau)
	local o = cfr(p, D_PROJ, "origin")
	local g = num(p, D_PROJ, "gravity")
	local look = o.LookVector
	local pos = o.Position + look * (speed * tau) - Vector3.new(0, 0.5 * g * tau * tau, 0)
	local vel = look * speed - Vector3.new(0, g * tau, 0)
	return lookAlong(pos, vel), speed * tau
end

register("Projectile", {
	Duration = function(p: Params): number
		return num(p, D_PROJ, "delay") + num(p, D_PROJ, "maxDist") / math.max(0.01, num(p, D_PROJ, "speed"))
	end,
	Volumes = function(p: Params, t: number): { Volume }
		if t < num(p, D_PROJ, "delay") then
			return EMPTY
		end
		local frame = projectileFrame(p, t)
		if not frame then
			return EMPTY
		end
		local d = math.max(0.05, num(p, D_PROJ, "radius")) * 2
		return { { Shape = "Ball", CFrame = frame, Size = Vector3.new(d, d, d) } }
	end,
	HitPolicy = function(_p: Params)
		return { Once = true }
	end,
}, D_PROJ)

---------------------------------------------------------------------------------------------------
-- Shockwave

local D_WAVE: Params = {
	center = Vector3.zero,
	maxRadius = 14,
	speed = 28,
	height = 2.5,
	thickness = 2,
	delay = 0.3,
	linger = 0.15,
	blockable = false,
	kind = "Area",
}

-- Current wave-front radius (nil before the delay / after maxRadius).
function HazardDefs.ShockwaveRadius(p: Params, t: number): number?
	local tau = t - num(p, D_WAVE, "delay")
	if tau < 0 then
		return nil
	end
	local r = tau * num(p, D_WAVE, "speed")
	if r > num(p, D_WAVE, "maxRadius") then
		return nil
	end
	return r
end

register("Shockwave", {
	Duration = function(p: Params): number
		return num(p, D_WAVE, "delay") + num(p, D_WAVE, "maxRadius") / math.max(0.01, num(p, D_WAVE, "speed")) + num(p, D_WAVE, "linger")
	end,
	Volumes = function(p: Params, t: number): { Volume }
		local r = HazardDefs.ShockwaveRadius(p, t)
		if r == nil or r <= 0.01 then
			return EMPTY
		end
		local h = math.max(0.05, num(p, D_WAVE, "height"))
		local band = math.min(math.max(0.05, num(p, D_WAVE, "thickness")), r)
		local centre = vec(p, D_WAVE, "center") + Vector3.new(0, h * 0.5, 0)
		return { { Shape = "Ring", CFrame = CFrame.new(centre), Size = Vector3.new(r * 2, h, band) } }
	end,
	HitPolicy = function(_p: Params)
		return { Once = true }
	end,
}, D_WAVE)

---------------------------------------------------------------------------------------------------
-- Orb

local D_ORB: Params = {
	center = Vector3.zero,
	radius = 12,
	delay = 0.4,
	duration = 2.5,
	pullStrength = 14,
	implodeTime = 0.15,
	linger = 0.4,
	visual = "Orb",
	blockable = false,
	kind = "Area",
}

local function implodeRadius(p: Params): number
	local r = p.implodeRadius
	if type(r) == "number" and r == r then
		return r
	end
	return num(p, D_ORB, "radius")
end

register("Orb", {
	Duration = function(p: Params): number
		return num(p, D_ORB, "delay") + num(p, D_ORB, "duration") + num(p, D_ORB, "implodeTime") + num(p, D_ORB, "linger")
	end,
	Volumes = function(p: Params, t: number): { Volume }
		local at = num(p, D_ORB, "delay") + num(p, D_ORB, "duration")
		if t < at or t > at + num(p, D_ORB, "implodeTime") then
			return EMPTY
		end
		local d = math.max(0.1, implodeRadius(p)) * 2
		return { { Shape = "Ball", CFrame = CFrame.new(vec(p, D_ORB, "center")), Size = Vector3.new(d, d, d) } }
	end,
	HitPolicy = function(_p: Params)
		return { Once = true }
	end,
}, D_ORB)

---------------------------------------------------------------------------------------------------
-- Zone

local D_ZONE: Params = {
	center = Vector3.zero,
	radius = 9,
	height = 6,
	delay = 0.3,
	duration = 5,
	tick = 0.5,
	effect = "Damage",
	cleanseKR = 0,
	visual = "Zone",
	linger = 0.3,
	blockable = false,
	kind = "Area",
}

register("Zone", {
	Duration = function(p: Params): number
		return num(p, D_ZONE, "delay") + num(p, D_ZONE, "duration") + num(p, D_ZONE, "linger")
	end,
	Volumes = function(p: Params, t: number): { Volume }
		local delay = num(p, D_ZONE, "delay")
		if t < delay or t > delay + num(p, D_ZONE, "duration") then
			return EMPTY
		end
		local r = math.max(0.1, num(p, D_ZONE, "radius"))
		local h = math.max(0.1, num(p, D_ZONE, "height"))
		local centre = vec(p, D_ZONE, "center") + Vector3.new(0, h * 0.5, 0)
		return { { Shape = "Cylinder", CFrame = CFrame.new(centre), Size = Vector3.new(r * 2, h, r * 2) } }
	end,
	HitPolicy = function(p: Params)
		return { Once = false, Interval = math.max(0.05, num(p, D_ZONE, "tick")) }
	end,
}, D_ZONE)

---------------------------------------------------------------------------------------------------
-- Rain

local D_RAIN: Params = {
	center = Vector3.zero,
	radius = 14,
	count = 10,
	interval = 0.15,
	delay = 0.6,
	fallHeight = 30,
	fallTime = 0.35,
	size = 3,
	impactHeight = 4,
	impactTime = 0.12,
	visual = "Bone",
	seed = 1,
	linger = 0.3,
	blockable = false,
	kind = "Area",
}

local rainCache: { [Params]: { RainDrop } } = setmetatable({}, { __mode = "k" }) :: any

local function rainCount(p: Params): number
	return math.clamp(math.floor(num(p, D_RAIN, "count")), 1, 200)
end

function HazardDefs.RainDrops(p: Params): { RainDrop }
	local cached = rainCache[p]
	if cached then
		return cached
	end
	local list: { RainDrop } = {}
	local radius = num(p, D_RAIN, "radius")
	local center = vec(p, D_RAIN, "center")
	local delay = num(p, D_RAIN, "delay")
	local interval = num(p, D_RAIN, "interval")
	local size = num(p, D_RAIN, "size")
	local rng = Rng.new(Rng.Hash("Rain", num(p, D_RAIN, "seed")))
	for i = 1, rainCount(p) do
		local x, z = rng:InCircle(radius)
		table.insert(list, {
			Position = center + Vector3.new(x, 0, z),
			ImpactTime = delay + (i - 1) * interval,
			Radius = size,
		})
	end
	rainCache[p] = list
	return list
end

register("Rain", {
	Duration = function(p: Params): number
		return num(p, D_RAIN, "delay")
			+ (rainCount(p) - 1) * num(p, D_RAIN, "interval")
			+ num(p, D_RAIN, "impactTime")
			+ num(p, D_RAIN, "linger")
	end,
	Volumes = function(p: Params, t: number): { Volume }
		local impactTime = num(p, D_RAIN, "impactTime")
		local h = math.max(0.1, num(p, D_RAIN, "impactHeight"))
		local out: { Volume }? = nil
		for i, drop in HazardDefs.RainDrops(p) do
			if t >= drop.ImpactTime and t <= drop.ImpactTime + impactTime then
				local d = math.max(0.1, drop.Radius) * 2
				local list = out or {}
				out = list
				table.insert(list, {
					Shape = "Cylinder",
					CFrame = CFrame.new(drop.Position + Vector3.new(0, h * 0.5, 0)),
					Size = Vector3.new(d, h, d),
					Key = i,
				})
			end
		end
		return out or EMPTY
	end,
	HitPolicy = function(_p: Params)
		return { Once = true, PerKey = true }
	end,
}, D_RAIN)

---------------------------------------------------------------------------------------------------
-- Generic helpers

function HazardDefs.Get(hazardType: string): HazardDef?
	return DEFS[hazardType]
end

function HazardDefs.Defaults(hazardType: string): Params?
	return DEFAULTS[hazardType]
end

function HazardDefs.Register(name: string, def: HazardDef, defaults: Params?)
	assert(type(name) == "string" and name ~= "", "HazardDefs.Register: bad name")
	assert(DEFS[name] == nil, "HazardDefs.Register: duplicate type " .. name)
	assert(
		type(def.Duration) == "function" and type(def.Volumes) == "function" and type(def.HitPolicy) == "function",
		"HazardDefs.Register: incomplete def " .. name
	)
	register(name, def, defaults or {})
end

function HazardDefs.IsProjectile(hazardType: string): boolean
	return hazardType == "Projectile" or hazardType == "BoneProjectile"
end

function HazardDefs.DamageKind(hazardType: string, p: Params?): string
	local k = if p then p.kind else nil
	if type(k) == "string" and k ~= "" then
		return k
	end
	local d = DEFAULTS[hazardType]
	if d and type(d.kind) == "string" then
		return d.kind
	end
	return "Area"
end

local function copyValue(v: any): any
	if type(v) == "table" then
		return table.clone(v)
	end
	return v
end

function HazardDefs.Normalize(hazardType: string, params: Params): Params
	local out: Params = {}
	for k, v in params do
		out[k] = copyValue(v)
	end
	for k, v in COMMON do
		if out[k] == nil then
			out[k] = v
		end
	end
	local d = DEFAULTS[hazardType]
	if d then
		for k, v in d do
			if out[k] == nil then
				out[k] = copyValue(v)
			end
		end
	end
	if out.warn == nil and type(out.delay) == "number" then
		out.warn = out.delay
	end
	if hazardType == "Orb" then
		if out.implodeDamage == nil then
			out.implodeDamage = out.damage
		end
		if out.implodeRadius == nil then
			out.implodeRadius = out.radius
		end
	elseif hazardType == "Zone" then
		local effect = out.effect
		if out.amount == nil then
			if effect == "Heal" then
				out.amount = 5
			elseif effect == "Slow" then
				out.amount = 0.6
			elseif effect == "Mark" then
				out.amount = 3
			else
				out.amount = out.damage
			end
		end
		if out.affects == nil then
			out.affects = if effect == "Heal" then "Allies" else "Enemies"
		end
	end
	return out
end

local PLAIN = {
	number = true,
	string = true,
	boolean = true,
	Vector3 = true,
	Vector2 = true,
	CFrame = true,
	Color3 = true,
}

function HazardDefs.IsPlainData(params: Params): (boolean, string?)
	for k, v in params do
		if type(k) ~= "string" then
			return false, tostring(k)
		end
		local t = typeof(v)
		if t == "table" then
			for _, item in v do
				if not PLAIN[typeof(item)] then
					return false, k
				end
			end
		elseif not PLAIN[t] then
			return false, k
		end
	end
	return true, nil
end

local NEEDS_ORIGIN = { BlasterBeam = true, BoneLine = true, BoneProjectile = true, Projectile = true }
local NEEDS_CENTER = { BoneSpikes = true, Shockwave = true, Orb = true, Zone = true, Rain = true }

function HazardDefs.Validate(hazardType: string, params: Params): (boolean, string?)
	if DEFS[hazardType] == nil then
		return false, "unknown hazard type " .. tostring(hazardType)
	end
	local d = DEFAULTS[hazardType] or {}
	for k, v in params do
		local expected = d[k]
		if expected == nil then
			expected = COMMON[k]
		end
		if expected ~= nil and typeof(v) ~= typeof(expected) then
			return false, ("param %s: expected %s, got %s"):format(tostring(k), typeof(expected), typeof(v))
		end
		if type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then
			return false, ("param %s is not finite"):format(tostring(k))
		end
	end
	if NEEDS_ORIGIN[hazardType] and typeof(params.origin) ~= "CFrame" then
		return false, hazardType .. " needs params.origin (CFrame)"
	end
	if NEEDS_CENTER[hazardType] and typeof(params.center) ~= "Vector3" then
		return false, hazardType .. " needs params.center (Vector3)"
	end
	return true, nil
end

function HazardDefs.ActiveWindow(hazardType: string, p: Params): (number, number)
	if hazardType == "BlasterBeam" then
		local delay = num(p, D_BEAM, "delay")
		return delay, delay + num(p, D_BEAM, "duration")
	elseif hazardType == "Zone" then
		local delay = num(p, D_ZONE, "delay")
		return delay, delay + num(p, D_ZONE, "duration")
	elseif hazardType == "BoneLine" then
		local delay = num(p, D_LINE, "delay")
		return delay, delay + lineTravelTime(p)
	elseif hazardType == "BoneSpikes" then
		local delay = num(p, D_SPIKES, "delay")
		return delay, delay + num(p, D_SPIKES, "rise") + num(p, D_SPIKES, "hold")
	elseif hazardType == "BoneProjectile" then
		local delay = num(p, D_BONEPROJ, "delay")
		return delay, delay + num(p, D_BONEPROJ, "maxDist") / math.max(0.01, num(p, D_BONEPROJ, "speed"))
	elseif hazardType == "Projectile" then
		local delay = num(p, D_PROJ, "delay")
		return delay, delay + num(p, D_PROJ, "maxDist") / math.max(0.01, num(p, D_PROJ, "speed"))
	elseif hazardType == "Shockwave" then
		local delay = num(p, D_WAVE, "delay")
		return delay, delay + num(p, D_WAVE, "maxRadius") / math.max(0.01, num(p, D_WAVE, "speed"))
	elseif hazardType == "Orb" then
		local at = num(p, D_ORB, "delay") + num(p, D_ORB, "duration")
		return at, at + num(p, D_ORB, "implodeTime")
	elseif hazardType == "Rain" then
		local delay = num(p, D_RAIN, "delay")
		return delay, delay + (rainCount(p) - 1) * num(p, D_RAIN, "interval") + num(p, D_RAIN, "impactTime")
	end
	local def = DEFS[hazardType]
	local d = DEFAULTS[hazardType] or COMMON
	return num(p, d, "delay"), if def then def.Duration(p) else 0
end

function HazardDefs.BeamStart(p: Params): Vector3
	return beamStart(p)
end

function HazardDefs.ProjectileFrame(hazardType: string, p: Params, t: number): (CFrame?, number)
	if hazardType == "BoneProjectile" then
		return boneProjectileFrame(p, t)
	elseif hazardType == "Projectile" then
		return projectileFrame(p, t)
	end
	return nil, 0
end

function HazardDefs.Effect(hazardType: string, p: Params, t: number): EffectDesc?
	if hazardType ~= "Orb" then
		return nil
	end
	local delay = num(p, D_ORB, "delay")
	if t < delay or t >= delay + num(p, D_ORB, "duration") then
		return nil
	end
	return {
		Kind = "Pull",
		Center = vec(p, D_ORB, "center"),
		Radius = num(p, D_ORB, "radius"),
		Strength = num(p, D_ORB, "pullStrength"),
	}
end

local ALONG_TRAVEL = { Projectile = true, BoneProjectile = true, BlasterBeam = true, BoneLine = true }

function HazardDefs.KnockbackDir(hazardType: string, p: Params, _t: number, targetPos: Vector3): Vector3
	local fallback = Vector3.new(0, 0, -1)
	local o = p.origin
	if ALONG_TRAVEL[hazardType] and typeof(o) == "CFrame" then
		return flatUnit(o.LookVector, fallback)
	end
	local centre = p.center
	if typeof(centre) == "Vector3" then
		return flatUnit(targetPos - centre, fallback)
	end
	if typeof(o) == "CFrame" then
		return flatUnit(targetPos - o.Position, flatUnit(o.LookVector, fallback))
	end
	return fallback
end

local function telegraphTimes(p: Params, finish: number): (number, number)
	local w = p.warn
	local lead = if type(w) == "number" and w >= 0 then w else finish
	return math.max(0, finish - lead), finish
end

function HazardDefs.Telegraph(hazardType: string, p: Params): TelegraphDesc
	local d = DEFAULTS[hazardType] or COMMON
	local color = str(p, d, "color")
	if color == "" then
		color = "White"
	end
	local none: TelegraphDesc = { Kind = "None", Color = color, Start = 0, End = 0 }
	if p.telegraph == false or DEFS[hazardType] == nil then
		return none
	end
	local delay = num(p, d, "delay")
	if hazardType == "BlasterBeam" then
		local s, e = telegraphTimes(p, delay)
		local o = cfr(p, D_BEAM, "origin")
		return {
			Kind = "Beam",
			Color = color,
			Start = s,
			End = e,
			CFrame = lookAlong(beamStart(p), o.LookVector),
			Length = num(p, D_BEAM, "length"),
			Width = num(p, D_BEAM, "width"),
		}
	elseif hazardType == "BoneLine" then
		local s, e = telegraphTimes(p, delay)
		return {
			Kind = "Lane",
			Color = color,
			Start = s,
			End = e,
			CFrame = cfr(p, D_LINE, "origin"),
			Length = num(p, D_LINE, "distance"),
			Width = (lineCount(p) - 1) * num(p, D_LINE, "spacing") + num(p, D_LINE, "boneThickness"),
		}
	elseif hazardType == "BoneSpikes" then
		local s, e = telegraphTimes(p, delay)
		local radius = num(p, D_SPIKES, "radius")
		local centre = vec(p, D_SPIKES, "center")
		if bool(p, D_SPIKES, "ring") then
			local band = num(p, D_SPIKES, "ringWidth")
			return {
				Kind = "Ring",
				Color = color,
				Start = s,
				End = e,
				Center = centre,
				Radius = radius + band * 0.5,
				InnerRadius = math.max(0, radius - band * 0.5),
			}
		end
		return { Kind = "Circle", Color = color, Start = s, End = e, Center = centre, Radius = radius }
	elseif hazardType == "BoneProjectile" or hazardType == "Projectile" then
		if delay <= 0 then
			return none
		end
		local s, e = telegraphTimes(p, delay)
		local width = if hazardType == "BoneProjectile" then num(p, D_BONEPROJ, "length") else num(p, D_PROJ, "radius") * 2
		return {
			Kind = "Beam",
			Color = color,
			Start = s,
			End = e,
			CFrame = cfr(p, d, "origin"),
			Length = num(p, d, "maxDist"),
			Width = width,
		}
	elseif hazardType == "Shockwave" then
		local s, e = telegraphTimes(p, delay)
		return { Kind = "Circle", Color = color, Start = s, End = e, Center = vec(p, D_WAVE, "center"), Radius = num(p, D_WAVE, "maxRadius") }
	elseif hazardType == "Orb" then
		local at = delay + num(p, D_ORB, "duration")
		local w = p.warn
		local s = if type(w) == "number" and w >= 0 then math.max(0, at - w) else 0
		return { Kind = "Circle", Color = color, Start = s, End = at, Center = vec(p, D_ORB, "center"), Radius = num(p, D_ORB, "radius") }
	elseif hazardType == "Zone" then
		local s, e = telegraphTimes(p, delay)
		return { Kind = "Circle", Color = color, Start = s, End = e, Center = vec(p, D_ZONE, "center"), Radius = num(p, D_ZONE, "radius") }
	elseif hazardType == "Rain" then
		local items: { TelegraphDesc } = {}
		local w = p.warn
		local lead = if type(w) == "number" and w >= 0 then w else delay
		for _, drop in HazardDefs.RainDrops(p) do
			table.insert(items, {
				Kind = "Circle",
				Color = color,
				Start = math.max(0, drop.ImpactTime - lead),
				End = drop.ImpactTime,
				Center = drop.Position,
				Radius = drop.Radius,
			})
		end
		local last = items[#items]
		return { Kind = "Multi", Color = color, Start = 0, End = if last then last.End else 0, Items = items }
	end
	return none
end

return HazardDefs
