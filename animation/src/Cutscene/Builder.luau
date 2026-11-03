--!strict
-- Scene description as plain data. Sets and characters add parts here; the
-- Realizer creates Roblox instances from it and the exporter writes it to
-- JSON for the offline preview.
local Paint = require(script.Parent.Paint)
local Rig = require(script.Parent.Rig)
local Styles = require(script.Parent.Styles)

export type GuiSpec = {
	face: string, -- NormalId name
	canvas: Vector2, -- SurfaceGui.CanvasSize
	lightInfluence: number,
	elems: { Paint.Elem },
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
	rig: string?, -- animated by a rig bone
	bone: string?,
	channel: string?, -- or by a named transform channel
	cf: CFrame, -- local to bone / channel, or world CFrame for static parts
	gui: GuiSpec?,
}

export type ModelSpec = { name: string, outline: boolean }

export type RigInst = { name: string, def: Rig.RigDef, model: string }

export type EmitterSpec = {
	name: string,
	kind: string, -- "snow"
	cf: CFrame, -- world CFrame of the emitter box
	size: Vector3, -- emission volume
	rate: number,
	color: Color3,
	sizeRange: { number },
	speed: { number },
	lifetime: { number },
	transparency: number,
}

export type Scene = {
	style: Styles.Style,
	parts: { PartSpec },
	models: { ModelSpec },
	rigs: { [string]: RigInst },
	emitters: { EmitterSpec },
	overlay: { Paint.Elem }, -- split-screen divider etc (design px 1113x626)
	data: { [string]: any }, -- free-form data for the timeline (poses, tracks)
}

local Builder = {}

function Builder.new(style: Styles.Style): Scene
	return {
		style = style,
		parts = {},
		models = {},
		rigs = {},
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
		cf = cf,
		gui = opts.gui,
	}
	table.insert(scene.parts, p)
	return p
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
