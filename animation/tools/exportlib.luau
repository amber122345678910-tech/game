--!nocheck
-- Serialises a built scene and a list of evaluated frames into the JSON the
-- preview renderer reads. Shared by export.luau and the character lab.
local S = require("./serialize")

local E = {}

local function colorTable(t)
	local o = {}
	for k, v in t do
		if typeof(v) == "Color3" then
			o[k] = S.color(v)
		else
			o[k] = v
		end
	end
	return o
end

function E.sceneJson(scene, Particles)
	local st = scene.style
	local parts, dynamicIds = {}, {}
	for _, p in scene.parts do
		local o = {
			id = p.id,
			name = p.name,
			model = p.model,
			shape = p.shape,
			size = S.v3(p.size),
			color = S.color(p.color),
			material = p.material,
			transparency = p.transparency,
			castShadow = p.castShadow,
			studs = p.studs,
			cf = S.cf(p.cf),
		}
		if p.gui then
			o.gui = {
				face = p.gui.face,
				canvas = { p.gui.canvas.X, p.gui.canvas.Y },
				lightInfluence = p.gui.lightInfluence,
				elems = S.elems(p.gui.elems),
			}
		end
		if p.rig or p.channel or p.fx then
			table.insert(dynamicIds, p.id)
			o.dynamic = true
		end
		table.insert(parts, o)
	end
	local lights = {}
	for _, l in scene.lights do
		table.insert(lights, { name = l.name, kind = l.kind, part = l.part, color = S.color(l.color), range = l.range, angle = l.angle, face = l.face, shadows = l.shadows })
	end
	local emitters = {}
	for _, e in scene.emitters do
		local p = Particles.get(e.kind)
		table.insert(emitters, {
			name = e.name,
			kind = e.kind,
			part = e.part,
			color = S.color(e.color),
			scale = e.scale,
			speed = e.speed,
			preset = {
				lifetime = p.lifetime,
				speed = p.speed,
				spread = p.spread,
				accel = S.v3(p.accel),
				drag = p.drag,
				size = p.size,
				transparency = p.transparency,
				lightEmission = p.lightEmission,
				direction = p.direction,
				squash = p.squash,
			},
		})
	end
	local models = {}
	for _, m in scene.models do
		table.insert(models, { name = m.name, outline = m.outline })
	end
	return {
		style = {
			id = st.id,
			title = st.title,
			lighting = colorTable(st.lighting),
			atmosphere = st.atmosphere and colorTable(st.atmosphere) or nil,
			clouds = st.clouds and colorTable(st.clouds) or nil,
			defaultSky = st.defaultSky,
			post = {
				bloom = st.post.bloom,
				cc = st.post.cc and colorTable(st.post.cc) or nil,
				dof = st.post.dof,
				sunrays = st.post.sunrays,
			},
			outline = st.outline and { color = S.color(st.outline.color), transparency = st.outline.transparency } or nil,
			vignette = st.vignette,
		},
		parts = parts,
		models = models,
		lights = lights,
		emitters = emitters,
		overlay = S.elems(scene.overlay),
		dynamicIds = dynamicIds,
	}
end

function E.frameJson(scene, fr, partCFrame, dynamicIds)
	local cfs = table.create(#dynamicIds)
	for i, id in dynamicIds do
		cfs[i] = S.cf(partCFrame(scene.parts[id], fr))
	end
	local props = {}
	for id, p in fr.props do
		props[tostring(id)] = {
			t = p.t,
			s = p.s and S.v3(p.s) or nil,
			c = p.c and S.color(p.c) or nil,
		}
	end
	local lights = {}
	for name, l in fr.lights do
		lights[name] = { b = l.b, c = l.c and S.color(l.c) or nil, r = l.r }
	end
	local vis = {}
	for k, v in fr.vis do
		if v then
			table.insert(vis, k)
		end
	end
	local alpha = {}
	for k, v in fr.alpha do
		alpha[k] = v
	end
	local emit = {}
	for k, v in fr.emit do
		emit[k] = v
	end
	return {
		t = fr.t,
		shot = fr.shot,
		camera = S.cf(fr.camera),
		fov = fr.fov,
		focus = fr.focus,
		dof = fr.dof,
		cfs = cfs,
		props = props,
		lights = lights,
		vis = vis,
		alpha = alpha,
		emit = emit,
		flash = fr.flash and { c = S.color(fr.flash.color), a = fr.flash.alpha } or nil,
		sub = fr.sub,
		grade = fr.grade and {
			brightness = fr.grade.brightness,
			contrast = fr.grade.contrast,
			saturation = fr.grade.saturation,
			tint = S.color(fr.grade.tint),
		} or nil,
		bloom = fr.bloom,
		fog = fr.fog,
	}
end

return E
