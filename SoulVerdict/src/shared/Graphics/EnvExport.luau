--!strict
-- Converts a GraphicsPreset into the environment JSON of the offline 3D preview renderer (tools/preview,
-- three.js). Lune-safe. The renderer owns the format; this module only fills it:
--   {"sky":{"top":[r,g,b],"horizon":[r,g,b],"bottom":[r,g,b]},
--    "sun":{"dir":[x,y,z],"color":[r,g,b],"intensity":n},
--    "ambient":{"sky":[r,g,b],"ground":[r,g,b],"intensity":n},
--    "fog":{"color":[r,g,b],"near":n,"far":n},
--    "bloom":{"strength":n,"radius":n,"threshold":n},
--    "exposure":n,"saturation":n,"contrast":n,"tint":[r,g,b]}
-- Value semantics produced here (all colours 0..1, linear-ish sRGB values as in Roblox Color3):
--   sun.dir      unit vector from the scene TOWARD the key light, Roblox world axes (Y up, east = +X) —
--                the same convention as Lighting:GetSunDirection(). By night the key light is the moon.
--   sun.color    normalised (max channel 1); sun.intensity = 0.45 × Lighting.Brightness × horizon fade
--                (renderer: 1 = full albedo on a sun-facing white surface, Brightness 2-3 -> ~0.9-1.35;
--                0 when the key light is below the horizon); moonlight = 0.3 × that.
--   ambient      hemisphere fill: sky = up-facing (OutdoorAmbient + sky diffuse), ground = down-facing
--                (Ambient + ColorShift_Bottom); intensity ≥ 1 only when the colours had to be normalised.
--   fog          linear fog (studs) approximating Atmosphere Density/Offset/Haze; colour = sky horizon.
--   bloom        the renderer blooms Neon/ForceField only: strength = Intensity × 1.5 (0 when off),
--                radius = Size / 56, threshold = (Threshold − 0.8) × 0.5 clamped 0..1 (0 = all neon blooms).
--   exposure     linear multiplier: 2^ExposureCompensation × (1 + ColorCorrection.Brightness); 1 = neutral.
--   saturation / contrast   ColorCorrection offsets, 0 = neutral, -1..1.   tint = TintColor (white = neutral).
--
-- Sun model (documented approximation of Roblox, which inherits G3D's LightingParameters — note the
-- default GeographicLatitude 41.7333 = G3D's Brown University constant): with a = 2π·ClockTime/24 and
-- θ = rad(23.5 − GeographicLatitude) (fixed earth tilt, fixed day of year):
--   sun  = ( sin a·cos θ, −cos a·cos θ, −sin θ )      sunrise 6:00 at +X (east), sunset 18:00 at −X,
--                                                      noon overhead when latitude = 23.5, else tilted ±Z
--   moon = ( −sin a·cos φ, cos a·cos φ, −sin φ ), φ = rad(−GeographicLatitude)   (opposite the sun)
-- In Studio the ground truth is Lighting:GetSunDirection(); the shape (east/west, noon high, night via
-- the moon) is what matters for previews.
--
-- API:
--   EnvExport.SunDirection(clockTime, latitude) -> Vector3
--   EnvExport.MoonDirection(clockTime, latitude) -> Vector3
--   EnvExport.FromPreset(preset) -> Env              (plain tables/numbers, ready to encode)
--   EnvExport.Validate(env) -> {string}               problems (empty = every value in range)
--   EnvExport.ToJson(env, pretty?) -> string          stable key order, 4 decimals

local Types = require(script.Parent.Parent.Types)
local Apply = require(script.Parent.Apply)

type GraphicsPreset = Types.GraphicsPreset

export type RGB = { number }
export type Env = {
	sky: { top: RGB, horizon: RGB, bottom: RGB },
	sun: { dir: { number }, color: RGB, intensity: number },
	ambient: { sky: RGB, ground: RGB, intensity: number },
	fog: { color: RGB, near: number, far: number },
	bloom: { strength: number, radius: number, threshold: number },
	exposure: number,
	saturation: number,
	contrast: number,
	tint: RGB,
}

local EnvExport = {}

local EARTH_TILT = 23.5
local MAX_FOG = 10000
local SUN_SCALE = 0.45 -- Roblox Brightness -> renderer sun intensity
local MOON_SCALE = 0.3 -- moonlight relative to sunlight at the same Brightness

--------------------------------------------------------------------------------------------- helpers

type V = { number } -- {r, g, b} working colour

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smoothstep(e0: number, e1: number, x: number): number
	local t = clamp01((x - e0) / (e1 - e0))
	return t * t * (3 - 2 * t)
end

local function vec(c: Color3): V
	return { c.R, c.G, c.B }
end

local function mix(a: V, b: V, t: number): V
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function scale(a: V, s: number): V
	return { a[1] * s, a[2] * s, a[3] * s }
end

local function add(a: V, b: V): V
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

local function mul(a: V, b: V): V
	return { a[1] * b[1], a[2] * b[2], a[3] * b[3] }
end

local function maxc(a: V): number
	return math.max(a[1], a[2], a[3])
end

local function clampColor(a: V): V
	return { clamp01(a[1]), clamp01(a[2]), clamp01(a[3]) }
end

-- hue of a colour with its brightest channel at 1 (white for black input)
local function hue(a: V): V
	local m = maxc(a)
	if m < 1e-4 then
		return { 1, 1, 1 }
	end
	return scale(a, 1 / m)
end

local function round(x: number, digits: number?): number
	local m = 10 ^ (digits or 4)
	local r = math.floor(x * m + 0.5) / m
	if r == 0 then
		return 0 -- no "-0"
	end
	return r
end

local function roundV(a: V): RGB
	return { round(a[1]), round(a[2]), round(a[3]) }
end

-------------------------------------------------------------------------------------------- sun/moon

function EnvExport.SunDirection(clockTime: number, latitude: number): Vector3
	local a = 2 * math.pi * clockTime / 24
	local theta = math.rad(EARTH_TILT - latitude)
	return Vector3.new(math.sin(a) * math.cos(theta), -math.cos(a) * math.cos(theta), -math.sin(theta)).Unit
end

function EnvExport.MoonDirection(clockTime: number, latitude: number): Vector3
	local a = 2 * math.pi * clockTime / 24
	local phi = math.rad(-latitude)
	return Vector3.new(-math.sin(a) * math.cos(phi), math.cos(a) * math.cos(phi), -math.sin(phi)).Unit
end

-- 0 below the horizon, ~0.7 at the horizon, 1 high in the sky
local function horizonFade(y: number): number
	return clamp01((y + 0.035) / 0.08) * (0.7 + 0.3 * clamp01(y / 0.5))
end

--------------------------------------------------------------------------------------------- convert

local DAY_TOP: V = { 0.29, 0.5, 0.86 }
local DAY_HORIZON: V = { 0.68, 0.79, 0.93 }
local NIGHT_TOP: V = { 0.008, 0.012, 0.035 }
local NIGHT_HORIZON: V = { 0.025, 0.035, 0.07 }
local TWILIGHT_TOP: V = { 0.2, 0.22, 0.42 }
local TWILIGHT_HORIZON: V = { 1, 0.56, 0.3 }
local SUN_HIGH: V = { 1, 0.96, 0.9 }
local SUN_LOW: V = { 1, 0.6, 0.34 }
local MOON: V = { 0.6, 0.7, 1 }

function EnvExport.FromPreset(preset: GraphicsPreset): Env
	local p = Apply.Normalize(preset) :: any
	local L = p.Lighting
	local atm = p.Atmosphere
	local cc = p.ColorCorrection
	local bloom = p.Bloom
	local atmOn = atm.Enabled ~= false
	local ccOn = cc.Enabled ~= false

	local clock: number = L.ClockTime
	local latitude: number = L.GeographicLatitude
	local brightness: number = math.max(L.Brightness, 0)
	local sunDir = EnvExport.SunDirection(clock, latitude)
	local moonDir = EnvExport.MoonDirection(clock, latitude)
	local sunY = sunDir.Y

	local day = smoothstep(-0.12, 0.1, sunY) -- 0 night .. 1 day
	local twilight = clamp01(1 - math.abs(sunY - 0.02) / 0.22) -- peaks with the sun on the horizon

	-- key light --------------------------------------------------------------------------------------
	local useMoon = sunY < -0.03
	local keyDir = if useMoon then moonDir else sunDir
	local keyColor: V
	local intensity: number
	if useMoon then
		keyColor = table.clone(MOON)
		intensity = brightness * SUN_SCALE * MOON_SCALE * horizonFade(moonDir.Y)
	else
		local warm = 1 - smoothstep(0.02, 0.5, sunY)
		keyColor = mix(SUN_HIGH, SUN_LOW, warm ^ 1.5)
		intensity = brightness * SUN_SCALE * horizonFade(sunY)
	end
	local shiftTop = vec(L.ColorShift_Top)
	local shiftStrength = math.min(maxc(shiftTop), 1) * 0.6
	keyColor = mul(keyColor, mix({ 1, 1, 1 }, hue(shiftTop), shiftStrength))
	if atmOn then
		local haze = clamp01(atm.Haze / 4)
		local s = math.min(atm.Density * (0.25 + 0.5 * haze), 0.5) * (0.4 + 0.6 * twilight)
		keyColor = mul(keyColor, mix({ 1, 1, 1 }, hue(vec(atm.Color)), s))
	end
	keyColor = hue(keyColor)

	-- sky ----------------------------------------------------------------------------------------------
	-- how brightly the atmosphere itself is lit (moonlit haze still shows a little colour at night)
	local lightLevel = (0.14 + 0.86 * day) * math.clamp(0.45 + brightness * 0.22, 0.45, 1.25)
	local top = mix(mix(NIGHT_TOP, DAY_TOP, day), TWILIGHT_TOP, twilight * 0.45)
	local horizon = mix(mix(NIGHT_HORIZON, DAY_HORIZON, day), TWILIGHT_HORIZON, twilight * 0.7 * day)
	if atmOn then
		local haze = clamp01(atm.Haze / 4)
		local lit = clampColor(scale(vec(atm.Color), lightLevel))
		horizon = mix(horizon, lit, math.clamp(0.25 + 0.55 * haze + 0.3 * atm.Density, 0, 0.92))
		top = mix(top, scale(lit, 0.8), math.clamp(0.35 * haze + 0.15 * atm.Density, 0, 0.8))
		if atm.Glare > 0 and atm.Haze > 0 then
			local decay = clampColor(scale(vec(atm.Decay), lightLevel))
			top = mix(top, decay, math.clamp(0.12 * atm.Glare * haze, 0, 0.45))
			if not useMoon then
				horizon =
					mix(horizon, scale(keyColor, lightLevel), math.clamp(0.08 * atm.Glare * twilight * haze, 0, 0.35))
			end
		end
	end
	top = clampColor(top)
	horizon = clampColor(horizon)
	local bottom = clampColor(scale(horizon, 0.55))

	-- ambient (hemisphere) ---------------------------------------------------------------------------
	local diffuse = math.max(L.EnvironmentDiffuseScale, 0)
	local ambientSky: V
	local ambientGround: V
	if L.GlobalShadows then
		ambientSky = add(vec(L.OutdoorAmbient), scale(top, diffuse * 0.35))
		ambientGround = add(add(vec(L.Ambient), scale(vec(L.ColorShift_Bottom), 0.25)), scale(horizon, diffuse * 0.12))
	else
		-- without GlobalShadows Roblox ignores OutdoorAmbient: Ambient lights everything
		ambientSky = add(vec(L.Ambient), scale(top, diffuse * 0.35))
		ambientGround = add(vec(L.Ambient), scale(vec(L.ColorShift_Bottom), 0.25))
	end
	local ambientIntensity = 1
	local peak = math.max(maxc(ambientSky), maxc(ambientGround))
	if peak > 1 then
		ambientIntensity = peak
		ambientSky = scale(ambientSky, 1 / peak)
		ambientGround = scale(ambientGround, 1 / peak)
	end

	-- fog ----------------------------------------------------------------------------------------------
	local near, far = 0, MAX_FOG
	if atmOn then
		far = (60 + 2400 * (1 - clamp01(atm.Density)) ^ 2.5) * (1 - 0.3 * clamp01(atm.Haze / 10))
		near = far * (0.02 + 0.3 * clamp01(atm.Offset))
	end

	-- post ----------------------------------------------------------------------------------------------
	local bloomOn = bloom.Enabled ~= false
	local exposure = 2 ^ L.ExposureCompensation
	if ccOn then
		exposure *= math.max(1 + cc.Brightness, 0.05)
	end

	local env: Env = {
		sky = { top = roundV(top), horizon = roundV(horizon), bottom = roundV(bottom) },
		sun = {
			dir = { round(keyDir.X), round(keyDir.Y), round(keyDir.Z) },
			color = roundV(clampColor(keyColor)),
			intensity = round(math.max(intensity, 0)),
		},
		ambient = {
			sky = roundV(clampColor(ambientSky)),
			ground = roundV(clampColor(ambientGround)),
			intensity = round(ambientIntensity),
		},
		fog = { color = roundV(horizon), near = round(near, 2), far = round(math.min(far, MAX_FOG), 2) },
		bloom = {
			strength = if bloomOn then round(math.clamp(bloom.Intensity * 1.5, 0, 3)) else 0,
			radius = round(clamp01(bloom.Size / 56)),
			threshold = round(clamp01((bloom.Threshold - 0.8) * 0.5)),
		},
		exposure = round(exposure),
		saturation = if ccOn then round(math.clamp(cc.Saturation, -1, 1)) else 0,
		contrast = if ccOn then round(math.clamp(cc.Contrast, -1, 1)) else 0,
		tint = if ccOn then roundV(clampColor(vec(cc.TintColor))) else { 1, 1, 1 },
	}
	return env
end

-------------------------------------------------------------------------------------------- validate

local function checkColor(problems: { string }, label: string, c: any)
	if type(c) ~= "table" or #c ~= 3 then
		table.insert(problems, label .. ": expected [r,g,b]")
		return
	end
	for i = 1, 3 do
		local x = c[i]
		if type(x) ~= "number" or x ~= x or x < 0 or x > 1 then
			table.insert(problems, ("%s[%d] = %s out of 0..1"):format(label, i, tostring(x)))
		end
	end
end

local function checkNumber(problems: { string }, label: string, x: any, lo: number, hi: number)
	if type(x) ~= "number" or x ~= x or x < lo or x > hi then
		table.insert(problems, ("%s = %s out of %s..%s"):format(label, tostring(x), tostring(lo), tostring(hi)))
	end
end

function EnvExport.Validate(env: Env): { string }
	local problems: { string } = {}
	checkColor(problems, "sky.top", env.sky.top)
	checkColor(problems, "sky.horizon", env.sky.horizon)
	checkColor(problems, "sky.bottom", env.sky.bottom)
	local d = env.sun.dir
	if type(d) ~= "table" or #d ~= 3 then
		table.insert(problems, "sun.dir: expected [x,y,z]")
	else
		local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
		if math.abs(len - 1) > 1e-3 then
			table.insert(problems, ("sun.dir length %.4f ~= 1"):format(len))
		end
	end
	checkColor(problems, "sun.color", env.sun.color)
	checkNumber(problems, "sun.intensity", env.sun.intensity, 0, 10)
	checkColor(problems, "ambient.sky", env.ambient.sky)
	checkColor(problems, "ambient.ground", env.ambient.ground)
	checkNumber(problems, "ambient.intensity", env.ambient.intensity, 0, 10)
	checkColor(problems, "fog.color", env.fog.color)
	checkNumber(problems, "fog.near", env.fog.near, 0, MAX_FOG)
	checkNumber(problems, "fog.far", env.fog.far, 1, MAX_FOG)
	if type(env.fog.near) == "number" and type(env.fog.far) == "number" and env.fog.near >= env.fog.far then
		table.insert(problems, "fog.near must be < fog.far")
	end
	checkNumber(problems, "bloom.strength", env.bloom.strength, 0, 3)
	checkNumber(problems, "bloom.radius", env.bloom.radius, 0, 1)
	checkNumber(problems, "bloom.threshold", env.bloom.threshold, 0, 1)
	checkNumber(problems, "exposure", env.exposure, 0.05, 8)
	checkNumber(problems, "saturation", env.saturation, -1, 1)
	checkNumber(problems, "contrast", env.contrast, -1, 1)
	checkColor(problems, "tint", env.tint)
	return problems
end

------------------------------------------------------------------------------------------------ json

local function num(x: number): string
	local s = string.format("%.4f", x)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	if s == "-0" then
		s = "0"
	end
	return s
end

local function arr(a: { number }): string
	local parts = table.create(#a)
	for i, x in a do
		parts[i] = num(x)
	end
	return "[" .. table.concat(parts, ", ") .. "]"
end

-- Stable key order (matches the renderer's documented format). pretty = one top-level key per line.
function EnvExport.ToJson(env: Env, pretty: boolean?): string
	local entries = {
		('"sky": {"top": %s, "horizon": %s, "bottom": %s}'):format(
			arr(env.sky.top),
			arr(env.sky.horizon),
			arr(env.sky.bottom)
		),
		('"sun": {"dir": %s, "color": %s, "intensity": %s}'):format(
			arr(env.sun.dir),
			arr(env.sun.color),
			num(env.sun.intensity)
		),
		('"ambient": {"sky": %s, "ground": %s, "intensity": %s}'):format(
			arr(env.ambient.sky),
			arr(env.ambient.ground),
			num(env.ambient.intensity)
		),
		('"fog": {"color": %s, "near": %s, "far": %s}'):format(arr(env.fog.color), num(env.fog.near), num(env.fog.far)),
		('"bloom": {"strength": %s, "radius": %s, "threshold": %s}'):format(
			num(env.bloom.strength),
			num(env.bloom.radius),
			num(env.bloom.threshold)
		),
		('"exposure": %s'):format(num(env.exposure)),
		('"saturation": %s'):format(num(env.saturation)),
		('"contrast": %s'):format(num(env.contrast)),
		('"tint": %s'):format(arr(env.tint)),
	}
	if pretty then
		return "{\n  " .. table.concat(entries, ",\n  ") .. "\n}\n"
	end
	return "{" .. table.concat(entries, ", ") .. "}"
end

return EnvExport
