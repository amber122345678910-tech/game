--!strict
-- Particle presets shared by the Roblox emitters and the offline preview.
-- Only built-in engine textures are used (no uploads).
local Particles = {}

Particles.SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

export type Preset = {
	lifetime: { number }, -- min, max seconds
	speed: { number }, -- min, max studs/s
	spread: number, -- degrees (SpreadAngle)
	accel: Vector3,
	drag: number,
	size: { number }, -- size at birth, at death (studs)
	transparency: number, -- body transparency (fades in/out at the ends)
	lightEmission: number,
	lightInfluence: number,
	direction: string, -- NormalId of the emitter part
	rotSpeed: number,
	squash: number, -- >0 stretches particles along their motion (sparks)
	zOffset: number,
}

Particles.presets = {
	snow = {
		lifetime = { 7, 9 },
		speed = { 3, 5 },
		spread = 18,
		accel = Vector3.new(1.2, -0.6, 0),
		drag = 0,
		size = { 0.24, 0.2 },
		transparency = 0.15,
		lightEmission = 0.15,
		lightInfluence = 0.6,
		direction = "Bottom",
		rotSpeed = 40,
		squash = 0,
		zOffset = 0,
	},
	sparks = {
		lifetime = { 0.25, 0.55 },
		speed = { 18, 36 },
		spread = 180,
		accel = Vector3.new(0, -24, 0),
		drag = 2.5,
		size = { 0.32, 0.06 },
		transparency = 0,
		lightEmission = 1,
		lightInfluence = 0,
		direction = "Top",
		rotSpeed = 0,
		squash = 1.5,
		zOffset = 1,
	},
	shards = {
		lifetime = { 0.45, 0.9 },
		speed = { 10, 24 },
		spread = 180,
		accel = Vector3.new(0, -8, 0),
		drag = 1.2,
		size = { 0.9, 0.15 },
		transparency = 0,
		lightEmission = 1,
		lightInfluence = 0,
		direction = "Top",
		rotSpeed = 360,
		squash = 0,
		zOffset = 1,
	},
	embers = {
		lifetime = { 0.7, 1.4 },
		speed = { 1, 4 },
		spread = 180,
		accel = Vector3.new(0, 3, 0),
		drag = 0.5,
		size = { 0.35, 0 },
		transparency = 0,
		lightEmission = 1,
		lightInfluence = 0,
		direction = "Top",
		rotSpeed = 90,
		squash = 0,
		zOffset = 1,
	},
	streaks = {
		lifetime = { 0.25, 0.45 },
		speed = { 40, 70 },
		spread = 8,
		accel = Vector3.zero,
		drag = 0,
		size = { 0.25, 0.1 },
		transparency = 0,
		lightEmission = 1,
		lightInfluence = 0,
		direction = "Front",
		rotSpeed = 0,
		squash = 4,
		zOffset = 1,
	},
} :: { [string]: Preset }

function Particles.get(kind: string): Preset
	local p = Particles.presets[kind]
	assert(p, "unknown particle preset " .. kind)
	return p
end

return Particles
