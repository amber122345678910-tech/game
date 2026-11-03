--!strict
-- Small math/color helpers shared by every module. No Roblox services here:
-- the same code runs inside Roblox and in Lune (offline preview).
local Util = {}

function Util.clamp(x: number, a: number, b: number): number
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.invLerp(a: number, b: number, x: number): number
	if b == a then
		return 0
	end
	return (x - a) / (b - a)
end

function Util.smoothstep(a: number, b: number, x: number): number
	local t = Util.clamp(Util.invLerp(a, b, x), 0, 1)
	return t * t * (3 - 2 * t)
end

-- "#RRGGBB" -> Color3
function Util.hex(s: string): Color3
	local h = string.gsub(s, "#", "")
	local r = tonumber(string.sub(h, 1, 2), 16) or 0
	local g = tonumber(string.sub(h, 3, 4), 16) or 0
	local b = tonumber(string.sub(h, 5, 6), 16) or 0
	return Color3.fromRGB(r, g, b)
end

function Util.mix(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

-- Multiply a color by a factor (clamped).
function Util.shade(c: Color3, k: number): Color3
	return Color3.new(math.min(1, c.R * k), math.min(1, c.G * k), math.min(1, c.B * k))
end

-- CFrame at `at` whose LookVector points at `target` (same as Roblox's
-- CFrame.lookAt, built explicitly so the offline Lune preview, whose lookAt
-- is flipped, gives identical results).
function Util.lookAt(at: Vector3, target: Vector3, up: Vector3?): CFrame
	local look = (target - at).Unit
	local u = up or Vector3.new(0, 1, 0)
	local right = look:Cross(u).Unit
	local up2 = right:Cross(look).Unit
	return CFrame.new(at.X, at.Y, at.Z, right.X, up2.X, -look.X, right.Y, up2.Y, -look.Y, right.Z, up2.Z, -look.Z)
end

-- Deterministic pseudo-random numbers (same sequence in Roblox and Lune).
export type Rng = { seed: number }

function Util.rng(seed: number): Rng
	return { seed = seed % 2147483647 }
end

function Util.rand(r: Rng): number
	-- Park-Miller minimal standard generator.
	r.seed = (r.seed * 48271) % 2147483647
	return r.seed / 2147483647
end

function Util.randRange(r: Rng, a: number, b: number): number
	return a + (b - a) * Util.rand(r)
end

-- Smooth 1D value noise in [-1, 1].
function Util.noise1(x: number, seed: number): number
	local i = math.floor(x)
	local f = x - i
	local function h(n: number): number
		local v = math.sin(n * 127.1 + seed * 311.7) * 43758.5453
		return (v - math.floor(v)) * 2 - 1
	end
	local u = f * f * (3 - 2 * f)
	return h(i) * (1 - u) + h(i + 1) * u
end

return Util
