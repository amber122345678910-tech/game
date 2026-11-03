--!strict
-- Roblox side: turns the scene description into Instances and applies
-- evaluated frames (camera, bones, effect parts, lights, particles, GUI
-- groups, overlay, colour grade).
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Builder = require(script.Parent.Builder)
local Scene = require(script.Parent.Scene)
local Timeline = require(script.Parent.Timeline)
local Paint = require(script.Parent.Paint)
local Particles = require(script.Parent.Particles)

local Realizer = {}

type Applied = { t: number?, s: Vector3?, c: Color3? }

export type Live = {
	scene: Builder.Scene,
	root: Folder,
	parts: { [number]: BasePart },
	moveSpecs: { Builder.PartSpec },
	moveParts: { BasePart },
	moveCFs: { CFrame },
	applied: { [number]: Applied },
	propIds: { [number]: boolean }, -- parts whose properties the last frame changed
	groups: { [string]: { GuiObject } },
	groupState: { [string]: boolean },
	overlay: { [string]: { { f: GuiObject, base: number } } },
	overlayAlpha: { [string]: number },
	lights: { [string]: Light },
	emitters: { [string]: ParticleEmitter },
	dof: DepthOfFieldEffect?,
	cc: ColorCorrectionEffect?,
	bloom: BloomEffect?,
	atmo: Atmosphere?,
	fog: number,
}

local SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Wedge = Enum.PartType.Wedge,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
	Ellipsoid = Enum.PartType.Block,
}

-- UI element -> Frame
function Realizer.makeFrame(e: Paint.Elem, z: number, scaleMode: Vector2?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	if scaleMode then
		f.Position = UDim2.fromScale(e.x / scaleMode.X, e.y / scaleMode.Y)
		f.Size = UDim2.fromScale(e.w / scaleMode.X, e.h / scaleMode.Y)
	else
		f.Position = UDim2.fromOffset(e.x, e.y)
		f.Size = UDim2.fromOffset(e.w, e.h)
	end
	f.Rotation = e.rot
	f.BackgroundColor3 = e.color
	f.BackgroundTransparency = e.alpha
	f.ZIndex = z
	if e.radius ~= 0 then
		local c = Instance.new("UICorner")
		c.CornerRadius = if e.radius < 0 then UDim.new(0.5, 0) else UDim.new(0, e.radius)
		c.Parent = f
	end
	local g = e.grad
	if g then
		local ug = Instance.new("UIGradient")
		if g.color then
			ug.Color = g.color
		end
		if g.transparency then
			ug.Transparency = g.transparency
		end
		ug.Rotation = g.rotation or 0
		ug.Parent = f
	end
	return f
end

local function makeSurfaceGui(live: Live, gui: Builder.GuiSpec, adornee: BasePart): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Face = (Enum.NormalId :: any)[gui.face]
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = gui.canvas
	sg.LightInfluence = gui.lightInfluence
	sg.Brightness = 1
	sg.AlwaysOnTop = gui.alwaysOnTop == true
	sg.ClipsDescendants = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.MaxDistance = 0
	sg.ResetOnSpawn = false
	for i, e in gui.elems do
		local f = Realizer.makeFrame(e, i, nil)
		if e.group then
			f.Visible = false
			local list = live.groups[e.group]
			if not list then
				list = {}
				live.groups[e.group] = list
			end
			table.insert(list, f)
		end
		f.Parent = sg
	end
	sg.Adornee = adornee
	sg.Parent = adornee
	return sg
end

local PARK = CFrame.new(0, 9000, 40000) -- same as Scene.PARK

local function makePart(live: Live, spec: Builder.PartSpec): BasePart
	local p = Instance.new("Part")
	p.Name = spec.name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.AudioCanCollide = false
	p.Shape = SHAPES[spec.shape] or Enum.PartType.Block
	p.Size = spec.size
	p.Color = spec.color
	p.Material = (Enum.Material :: any)[spec.material] or Enum.Material.SmoothPlastic
	p.Transparency = spec.transparency
	p.CastShadow = spec.castShadow
	if spec.studs then
		p.TopSurface = Enum.SurfaceType.Studs
		p.BottomSurface = Enum.SurfaceType.Inlet
	else
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
	end
	if spec.shape == "Ellipsoid" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Scale = Vector3.one
		m.Parent = p
	end
	p.CFrame = if spec.fx or spec.rig then PARK else spec.cf
	if spec.gui then
		makeSurfaceGui(live, spec.gui, p)
	end
	return p
end

local function applyLighting(live: Live)
	local st = live.scene.style
	local L = st.lighting
	pcall(function()
		(Lighting :: any).LightingStyle = (Enum :: any).LightingStyle[L.LightingStyle]
	end)
	Lighting.Brightness = L.Brightness
	Lighting.Ambient = L.Ambient
	Lighting.OutdoorAmbient = L.OutdoorAmbient
	Lighting.ClockTime = L.ClockTime
	Lighting.GeographicLatitude = L.GeographicLatitude
	Lighting.EnvironmentDiffuseScale = L.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = L.EnvironmentSpecularScale
	Lighting.ExposureCompensation = L.ExposureCompensation
	Lighting.GlobalShadows = L.GlobalShadows
	Lighting.ShadowSoftness = L.ShadowSoftness

	for _, ch in Lighting:GetChildren() do
		if ch:GetAttribute("CutsceneFX") then
			ch:Destroy()
		end
	end
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		for _, ch in terrain:GetChildren() do
			if ch:GetAttribute("CutsceneFX") then
				ch:Destroy()
			end
		end
	end
	local function tag(i: Instance, parent: Instance)
		i:SetAttribute("CutsceneFX", true)
		i.Parent = parent
	end
	if st.atmosphere then
		local a = Instance.new("Atmosphere")
		a.Density = st.atmosphere.Density
		a.Offset = st.atmosphere.Offset
		a.Color = st.atmosphere.Color
		a.Decay = st.atmosphere.Decay
		a.Glare = st.atmosphere.Glare
		a.Haze = st.atmosphere.Haze
		tag(a, Lighting)
		live.atmo = a
	end
	if st.defaultSky then
		local s = Instance.new("Sky")
		s.CelestialBodiesShown = st.clouds == nil
		tag(s, Lighting)
	end
	if st.clouds and terrain then
		local c = Instance.new("Clouds")
		c.Cover = st.clouds.Cover
		c.Density = st.clouds.Density
		c.Color = st.clouds.Color
		tag(c, terrain)
	end
	local post = st.post
	if post.bloom then
		local b = Instance.new("BloomEffect")
		b.Intensity = post.bloom.Intensity
		b.Size = post.bloom.Size
		b.Threshold = post.bloom.Threshold
		tag(b, Lighting)
		live.bloom = b
	end
	if post.cc then
		local c = Instance.new("ColorCorrectionEffect")
		c.Brightness = post.cc.Brightness
		c.Contrast = post.cc.Contrast
		c.Saturation = post.cc.Saturation
		c.TintColor = post.cc.TintColor
		tag(c, Lighting)
		live.cc = c
	end
	if post.sunrays then
		local s = Instance.new("SunRaysEffect")
		s.Intensity = post.sunrays.Intensity
		s.Spread = post.sunrays.Spread
		tag(s, Lighting)
	end
	if post.dof then
		local d = Instance.new("DepthOfFieldEffect")
		d.FarIntensity = post.dof.FarIntensity
		d.NearIntensity = post.dof.NearIntensity
		d.InFocusRadius = post.dof.InFocusRadius
		d.FocusDistance = 100
		tag(d, Lighting)
		live.dof = d
	end
end

local function makeLight(spec: Builder.LightSpec, parent: BasePart): Light
	local l: Light
	if spec.kind == "Spot" then
		local s = Instance.new("SpotLight")
		s.Angle = spec.angle or 60
		s.Face = (Enum.NormalId :: any)[spec.face or "Front"]
		s.Range = spec.range
		l = s
	else
		local p = Instance.new("PointLight")
		p.Range = spec.range
		l = p
	end
	l.Name = spec.name
	l.Color = spec.color
	l.Brightness = 0
	l.Shadows = spec.shadows
	l.Enabled = false
	l.Parent = parent
	return l
end

local function makeEmitter(spec: Builder.EmitterSpec, parent: BasePart): ParticleEmitter
	local p = Particles.get(spec.kind)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = spec.name
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.Rate = 0
	pe.Enabled = false
	pe.Color = ColorSequence.new(spec.color)
	pe.Size = NumberSequence.new(p.size[1] * spec.scale, p.size[2] * spec.scale)
	pe.Speed = NumberRange.new(p.speed[1] * spec.speed, p.speed[2] * spec.speed)
	pe.Lifetime = NumberRange.new(p.lifetime[1], p.lifetime[2])
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, p.transparency),
		NumberSequenceKeypoint.new(0.8, p.transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.EmissionDirection = (Enum.NormalId :: any)[p.direction]
	pe.SpreadAngle = Vector2.new(p.spread, p.spread)
	pe.Acceleration = p.accel
	pe.Drag = p.drag
	pe.RotSpeed = NumberRange.new(-p.rotSpeed, p.rotSpeed)
	pe.Rotation = NumberRange.new(0, 360)
	pe.LightInfluence = p.lightInfluence
	pe.LightEmission = p.lightEmission
	pe.ZOffset = p.zOffset
	if p.squash > 0 then
		pe.Orientation = Enum.ParticleOrientation.VelocityParallel
		pe.Squash = NumberSequence.new(p.squash)
	end
	pe.Texture = Particles.SPARKLE
	pe.Parent = parent
	return pe
end

function Realizer.build(styleId: string, parent: Instance, part: number?): Live
	local scene = Scene.build(styleId, part)
	local root = Instance.new("Folder")
	root.Name = "Cutscene"
	local live: Live = {
		scene = scene,
		root = root,
		parts = {},
		moveSpecs = {},
		moveParts = {},
		moveCFs = {},
		applied = {},
		propIds = {},
		groups = {},
		groupState = {},
		overlay = {},
		overlayAlpha = {},
		lights = {},
		emitters = {},
		dof = nil,
		cc = nil,
		bloom = nil,
		atmo = nil,
		fog = 1,
	}
	local models: { [string]: Model } = {}
	for _, m in scene.models do
		local model = Instance.new("Model")
		model.Name = m.name
		model.Parent = root
		models[m.name] = model
		local o = scene.style.outline
		if m.outline and o then
			local h = Instance.new("Highlight")
			h.FillTransparency = 1
			h.OutlineColor = o.color
			h.OutlineTransparency = o.transparency
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Adornee = model
			h.Parent = model
		end
	end
	for _, spec in scene.parts do
		local p = makePart(live, spec)
		p.Parent = models[spec.model] or root
		live.parts[spec.id] = p
		if spec.rig or spec.channel or spec.fx then
			table.insert(live.moveSpecs, spec)
			table.insert(live.moveParts, p)
		end
	end
	for _, l in scene.lights do
		live.lights[l.name] = makeLight(l, live.parts[l.part])
	end
	for _, e in scene.emitters do
		live.emitters[e.name] = makeEmitter(e, live.parts[e.part])
	end
	applyLighting(live)
	root.Parent = parent
	return live
end

-- 2D overlay elements inside the 16:9 picture frame
function Realizer.buildOverlay(live: Live, container: GuiObject)
	for _, ch in container:GetChildren() do
		if ch:GetAttribute("CutsceneOverlay") then
			ch:Destroy()
		end
	end
	live.overlay = {}
	live.overlayAlpha = {}
	local design = Vector2.new(1113, 626)
	for i, e in live.scene.overlay do
		local f = Realizer.makeFrame(e, 10 + i, design)
		f:SetAttribute("CutsceneOverlay", true)
		f.Visible = false
		f.Parent = container
		local g = e.group or "misc"
		local list = live.overlay[g]
		if not list then
			list = {}
			live.overlay[g] = list
		end
		table.insert(list, { f = f, base = e.alpha })
	end
end

local function sameColor(a: Color3?, b: Color3?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a == b
end

function Realizer.apply(live: Live, frame: Timeline.FrameState, camera: Camera, fovScale: number)
	camera.CFrame = frame.camera
	-- keep the 16:9 picture's vertical FOV when the window is taller than 16:9
	local fov = frame.fov
	if fovScale ~= 1 then
		fov = math.deg(2 * math.atan(math.tan(math.rad(fov) / 2) * fovScale))
	end
	camera.FieldOfView = fov

	-- transforms
	for i, spec in live.moveSpecs do
		live.moveCFs[i] = Scene.partCFrame(spec, frame)
	end
	Workspace:BulkMoveTo(live.moveParts, live.moveCFs, Enum.BulkMoveMode.FireCFrameChanged)

	-- a property set by a frame holds only for that frame: parts the last frame
	-- changed but this one does not go back to how they were built
	for id in live.propIds do
		if frame.props[id] == nil then
			local spec = live.scene.parts[id]
			local part = live.parts[id]
			part.Size = spec.size
			part.Transparency = spec.transparency
			part.Color = spec.color
			live.applied[id] = nil
		end
	end
	table.clear(live.propIds)
	for id in frame.props do
		live.propIds[id] = true
	end

	-- animated part properties (only written when they change)
	for id, p in frame.props do
		local part = live.parts[id]
		local last: Applied = live.applied[id] or ({} :: Applied)
		live.applied[id] = last
		if p.t ~= nil and p.t ~= last.t then
			part.Transparency = p.t
			last.t = p.t
		end
		if p.s ~= nil and p.s ~= last.s then
			part.Size = p.s
			last.s = p.s
		end
		if p.c ~= nil and not sameColor(p.c, last.c) then
			part.Color = p.c
			last.c = p.c
		end
	end

	-- GUI groups (face expressions etc.)
	for g, list in live.groups do
		local on = frame.vis[g] == true
		if live.groupState[g] ~= on then
			live.groupState[g] = on
			for _, f in list do
				f.Visible = on
			end
		end
	end
	-- overlay groups with alpha
	for g, list in live.overlay do
		local a = frame.alpha[g] or (if frame.vis[g] then 1 else 0)
		if live.overlayAlpha[g] ~= a then
			live.overlayAlpha[g] = a
			for _, it in list do
				it.f.Visible = a > 0.001
				it.f.BackgroundTransparency = 1 - (1 - it.base) * a
			end
		end
	end

	-- lights and particles
	for name, l in live.lights do
		local s = frame.lights[name]
		if s and s.b > 0 then
			l.Enabled = true
			l.Brightness = s.b
			if s.c then
				l.Color = s.c
			end
			if s.r then
				(l :: any).Range = s.r
			end
		elseif l.Enabled then
			l.Enabled = false
		end
	end
	for name, pe in live.emitters do
		local r = frame.emit[name] or 0
		if r > 0 then
			pe.Rate = r
			pe.Enabled = true
		elseif pe.Enabled then
			pe.Enabled = false
		end
	end

	-- post
	local st = live.scene.style
	local dof = live.dof
	local dofStyle = st.post.dof
	if dof and dofStyle then
		dof.FocusDistance = frame.focus
		dof.FarIntensity = dofStyle.FarIntensity * frame.dof
		dof.NearIntensity = dofStyle.NearIntensity * frame.dof
	end
	local cc = live.cc
	local ccStyle = st.post.cc
	if cc and ccStyle then
		local g = frame.grade
		if g then
			cc.Brightness = g.brightness
			cc.Contrast = g.contrast
			cc.Saturation = g.saturation
			cc.TintColor = g.tint
		else
			cc.Brightness = ccStyle.Brightness
			cc.Contrast = ccStyle.Contrast
			cc.Saturation = ccStyle.Saturation
			cc.TintColor = ccStyle.TintColor
		end
	end
	local bloom = live.bloom
	local bloomStyle = st.post.bloom
	if bloom and bloomStyle then
		bloom.Intensity = bloomStyle.Intensity * frame.bloom
	end
	local atmo = live.atmo
	local atmoStyle = st.atmosphere
	if atmo and atmoStyle and live.fog ~= frame.fog then
		live.fog = frame.fog
		atmo.Density = math.clamp(atmoStyle.Density * frame.fog, 0, 1)
	end
end

function Realizer.destroy(live: Live)
	live.root:Destroy()
end

return Realizer
