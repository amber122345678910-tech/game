--!strict
-- Frame state + the context object shots use to fill it.
-- A frame is a pure function of time: Timeline.evaluate(scene, t) finds the
-- shot that covers t and lets it describe the camera, characters, effects
-- and overlay for that instant.
local Builder = require(script.Parent.Builder)
local Rig = require(script.Parent.Rig)

export type PropState = { t: number?, s: Vector3?, c: Color3? }
export type LightState = { b: number, c: Color3?, r: number? }
export type Grade = { brightness: number, contrast: number, saturation: number, tint: Color3 }

export type FrameState = {
	t: number,
	shot: string,
	camera: CFrame,
	fov: number,
	focus: number,
	dof: number,
	rigs: { [string]: { [string]: CFrame } },
	channels: { [string]: CFrame },
	parts: { [number]: CFrame },
	props: { [number]: PropState },
	vis: { [string]: boolean },
	alpha: { [string]: number },
	lights: { [string]: LightState },
	emit: { [string]: number },
	flash: { color: Color3, alpha: number }?,
	sub: string?,
	grade: Grade?,
	bloom: number,
	fog: number, -- atmosphere density multiplier
	wind: number, -- wind on hair, fur and cloth (1 = normal breeze)
	gust: number, -- extra sway on top of the wind (a jolt, an impact)
}

export type Ctx = {
	scene: Builder.Scene,
	frame: FrameState,
	t: number, -- global time
	lt: number, -- time since the shot started
	dur: number, -- shot length
	u: number, -- 0..1 progress through the shot
	camera: (self: Ctx, cf: CFrame, fov: number?) -> (),
	focus: (self: Ctx, dist: number, amount: number?) -> (),
	rig: (self: Ctx, name: string, root: CFrame, pose: Rig.Pose?) -> { [string]: CFrame },
	place: (self: Ctx, part: Builder.PartSpec, cf: CFrame) -> (),
	prop: (self: Ctx, part: Builder.PartSpec, p: PropState) -> (),
	show: (self: Ctx, group: string, on: boolean?) -> (),
	alpha: (self: Ctx, group: string, a: number) -> (),
	light: (self: Ctx, name: string, brightness: number, color: Color3?, range: number?) -> (),
	emit: (self: Ctx, name: string, rate: number) -> (),
	flash: (self: Ctx, color: Color3, alpha: number) -> (),
	sub: (self: Ctx, text: string?) -> (),
	grade: (self: Ctx, g: Grade) -> (),
	bloom: (self: Ctx, k: number) -> (),
	fog: (self: Ctx, k: number) -> (),
	wind: (self: Ctx, k: number) -> (),
	gust: (self: Ctx, k: number) -> (),
	channel: (self: Ctx, name: string, cf: CFrame) -> (),
}

export type Shot = {
	id: string,
	t0: number,
	t1: number,
	run: (ctx: Ctx) -> (),
}

local Ctx = {}
Ctx.__index = Ctx

function Ctx.camera(self: Ctx, cf: CFrame, fov: number?)
	self.frame.camera = cf
	if fov then
		self.frame.fov = fov
	end
end

function Ctx.focus(self: Ctx, dist: number, amount: number?)
	self.frame.focus = dist
	self.frame.dof = amount or 1
end

function Ctx.rig(self: Ctx, name: string, root: CFrame, pose: Rig.Pose?): { [string]: CFrame }
	local r = self.scene.rigs[name]
	assert(r, "unknown rig " .. name)
	local bones = Rig.solve(r.def, root, pose)
	self.frame.rigs[name] = bones
	return bones
end

function Ctx.place(self: Ctx, part: Builder.PartSpec, cf: CFrame)
	self.frame.parts[part.id] = cf
end

function Ctx.prop(self: Ctx, part: Builder.PartSpec, p: PropState)
	self.frame.props[part.id] = p
end

function Ctx.show(self: Ctx, group: string, on: boolean?)
	self.frame.vis[group] = on ~= false
end

function Ctx.alpha(self: Ctx, group: string, a: number)
	self.frame.alpha[group] = a
end

function Ctx.light(self: Ctx, name: string, brightness: number, color: Color3?, range: number?)
	self.frame.lights[name] = { b = brightness, c = color, r = range }
end

function Ctx.emit(self: Ctx, name: string, rate: number)
	self.frame.emit[name] = rate
end

function Ctx.flash(self: Ctx, color: Color3, alpha: number)
	self.frame.flash = { color = color, alpha = alpha }
end

function Ctx.sub(self: Ctx, text: string?)
	self.frame.sub = text
end

function Ctx.grade(self: Ctx, g: Grade)
	self.frame.grade = g
end

function Ctx.bloom(self: Ctx, k: number)
	self.frame.bloom = k
end

function Ctx.wind(self: Ctx, k: number)
	self.frame.wind = k
end

function Ctx.gust(self: Ctx, k: number)
	self.frame.gust = k
end

function Ctx.fog(self: Ctx, k: number)
	self.frame.fog = k
end

function Ctx.channel(self: Ctx, name: string, cf: CFrame)
	self.frame.channels[name] = cf
end

local Timeline = {}

function Timeline.newFrame(t: number): FrameState
	return {
		t = t,
		shot = "",
		camera = CFrame.new(),
		fov = 70,
		focus = 100,
		dof = 0,
		rigs = {},
		channels = {},
		parts = {},
		props = {},
		vis = {},
		alpha = {},
		lights = {},
		emit = {},
		flash = nil,
		sub = nil,
		grade = nil,
		bloom = 1,
		fog = 1,
		wind = 1,
		gust = 0,
	}
end

function Timeline.context(scene: Builder.Scene, t: number, shot: Shot): Ctx
	local frame = Timeline.newFrame(t)
	frame.shot = shot.id
	local dur = shot.t1 - shot.t0
	local lt = t - shot.t0
	local c = setmetatable({
		scene = scene,
		frame = frame,
		t = t,
		lt = lt,
		dur = dur,
		u = if dur > 0 then math.clamp(lt / dur, 0, 1) else 0,
	}, Ctx)
	return (c :: any) :: Ctx
end

-- Picks the shot covering t (shots are sorted, contiguous)
function Timeline.find(shots: { Shot }, t: number): Shot
	local pick = shots[1]
	for _, s in shots do
		if t >= s.t0 then
			pick = s
		else
			break
		end
	end
	return pick
end

return Timeline
