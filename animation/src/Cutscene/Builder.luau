--!strict
-- Scene description as plain data. Stages, characters and effects add parts,
-- lights and particle emitters here; the Realizer creates Roblox instances
-- from it and the exporter writes it to JSON for the offline preview.
local Paint = require(script.Parent.Paint)
local Rig = require(script.Parent.Rig)
local Styles = require(script.Parent.Styles)

export type GuiSpec = {
	face: string, -- NormalId name
	canvas: Vector2, -- SurfaceGui.CanvasSize
	lightInfluence: number,
	elems: { Paint.Elem },
	alwaysOnTop: boolean?,
}

export type PartSpec = {
	id: number,
	name: string,
	model: string,
	shape: string, -- "Block" | "Wedge" | "Ball" | "Cylinder" | "Ellipsoid"
	size: Vector3,
	color: Color3,
	material: string,
	transparency: number,
	castShadow: boolean,
	studs: boolean,
	rig: string?, -- animated by a rig bone (parked while the rig is not in the shot)
	bone: string?,
	channel: string?, -- or by a named transform channel
	fx: boolean, -- or placed directly by the timeline (parked when not placed)
	flex: number?, -- sways in the wind / with the body (degrees), rig parts only
	pivot: Vector3?, -- where a flexing part is attached (part-local offset)
	cf: CFrame, -- local to bone / channel, or world CFrame for static parts
	gui: GuiSpec?,
}

export type ModelSpec = { name: string, outline: boolean }

export type RigInst = { name: string, def: Rig.RigDef, model: string }

-- Light attached to a part (PointLight / SpotLight). Brightness etc. are
-- animated by the timeline; a light is off unless the frame turns it on.
export type LightSpec = {
	name: string,
	kind: string, -- "Point" | "Spot"
	part: number,
	color: Color3,
	range: number,
	angle: number?,
	face: string?,
	shadows: boolean,
}

-- Particle emitter attached to a part (its size is the emission volume).
-- "kind" selects a preset (see FX.EMITTERS); off unless the frame sets a rate.
export type EmitterSpec = {
	name: string,
	kind: string,
	part: number,
	color: Color3,
	scale: number, -- particle size multiplier
	speed: number, -- speed multiplier
}

export type Scene = {
	style: Styles.Style,
	parts: { PartSpec },
	models: { ModelSpec },
	rigs: { [string]: RigInst },
	lights: { LightSpec },
	emitters: { EmitterSpec },
	overlay: { Paint.Elem }, -- 2D overlay (design px 1113 x 626), grouped
	data: { [string]: any }, -- free-form data for the timeline (part ids, poses)
}

local Builder = {}

function Builder.new(style: Styles.Style): Scene
	return {
		style = style,
		parts = {},
		models = {},
		rigs = {},
		lights = {},
		emitters = {},
		overlay = {},
		data = {},
	}
end

function Builder.model(scene: Scene, name: string, outline: boolean?)
	for _, m in scene.models do
		if m.name == name then
			return
		end
	end
	table.insert(scene.models, { name = name, outline = outline == true })
end

export type PartOpts = {
	shape: string?,
	material: string?,
	transparency: number?,
	castShadow: boolean?,
	studs: boolean?,
	rig: string?,
	bone: string?,
	channel: string?,
	fx: boolean?,
	gui: GuiSpec?,
	name: string?,
}

function Builder.part(scene: Scene, model: string, size: Vector3, cf: CFrame, color: Color3, o: PartOpts?): PartSpec
	local opts: PartOpts = o or {}
	local p: PartSpec = {
		id = #scene.parts + 1,
		name = opts.name or "Part",
		model = model,
		shape = opts.shape or "Block",
		size = size,
		color = color,
		material = opts.material or "SmoothPlastic",
		transparency = opts.transparency or 0,
		castShadow = if opts.castShadow == nil then true else opts.castShadow :: boolean,
		studs = opts.studs == true,
		rig = opts.rig,
		bone = opts.bone,
		channel = opts.channel,
		fx = opts.fx == true,
		cf = cf,
		gui = opts.gui,
	}
	table.insert(scene.parts, p)
	return p
end

-- Effect part: parked out of sight unless the timeline places it.
-- Let a rig part (hair strand, fur tuft, hem) sway: `amp` degrees at full
-- wind, rotating about `pivot` (the point where it is attached, part-local)
function Builder.flex(p: PartSpec, amp: number, pivot: Vector3?): PartSpec
	p.flex = amp
	p.pivot = pivot
	return p
end

function Builder.fx(scene: Scene, model: string, shape: string, size: Vector3, color: Color3, material: string?, transparency: number?, name: string?): PartSpec
	Builder.model(scene, model, false)
	return Builder.part(scene, model, size, CFrame.new(), color, {
		shape = shape,
		material = material or "Neon",
		transparency = transparency or 0,
		castShadow = false,
		fx = true,
		name = name or "FX",
	})
end

function Builder.light(scene: Scene, name: string, kind: string, part: PartSpec, color: Color3, range: number, shadows: boolean?, angle: number?, face: string?): LightSpec
	local l: LightSpec = {
		name = name,
		kind = kind,
		part = part.id,
		color = color,
		range = range,
		angle = angle,
		face = face,
		shadows = shadows == true,
	}
	table.insert(scene.lights, l)
	return l
end

function Builder.emitter(scene: Scene, name: string, kind: string, part: PartSpec, color: Color3, scale: number?, speed: number?): EmitterSpec
	local e: EmitterSpec = {
		name = name,
		kind = kind,
		part = part.id,
		color = color,
		scale = scale or 1,
		speed = speed or 1,
	}
	table.insert(scene.emitters, e)
	return e
end

function Builder.rig(scene: Scene, name: string, def: Rig.RigDef, model: string)
	scene.rigs[name] = { name = name, def = def, model = model }
end

-- Character part helper bound to one rig: colors/materials by palette keys.
export type Kit = {
	add: (bone: string, shape: string, size: Vector3, cf: CFrame, colorKey: string, matKey: string, name: string?) -> PartSpec,
	addColor: (bone: string, shape: string, size: Vector3, cf: CFrame, color: Color3, matKey: string, name: string?) -> PartSpec,
}

function Builder.kit(scene: Scene, model: string, rigName: string): Kit
	local st = scene.style
	local function addColor(bone: string, shape: string, size: Vector3, cf: CFrame, color: Color3, matKey: string, name: string?): PartSpec
		return Builder.part(scene, model, size, cf, color, {
			shape = shape,
			material = st.material[matKey] or "SmoothPlastic",
			rig = rigName,
			bone = bone,
			name = name or bone,
		})
	end
	local function add(bone: string, shape: string, size: Vector3, cf: CFrame, colorKey: string, matKey: string, name: string?): PartSpec
		local c = st.color[colorKey]
		assert(c, "missing palette color " .. colorKey)
		return addColor(bone, shape, size, cf, c, matKey, name)
	end
	return { add = add, addColor = addColor }
end

return Builder
