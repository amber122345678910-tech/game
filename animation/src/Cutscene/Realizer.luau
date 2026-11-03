--!strict
-- Roblox side: turns the scene description into Instances and applies
-- evaluated frames (camera, bone transforms, channels, overlay, effects).
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Builder = require(script.Parent.Builder)
local Scene = require(script.Parent.Scene)
local Shots = require(script.Parent.Shots)
local Paint = require(script.Parent.Paint)

local Realizer = {}

export type Live = {
	scene: Builder.Scene,
	root: Folder,
	parts: { BasePart },
	dynamic: { { spec: Builder.PartSpec, part: BasePart } },
	effects: Folder,
	dof: DepthOfFieldEffect?,
	overlayFrames: { [string]: { GuiObject } },
	moveParts: { BasePart },
	moveCFs: { CFrame },
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

local function makeSurfaceGui(gui: Builder.GuiSpec, adornee: BasePart): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Face = (Enum.NormalId :: any)[gui.face]
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = gui.canvas
	sg.LightInfluence = gui.lightInfluence
	sg.Brightness = 1
	sg.AlwaysOnTop = false
	sg.ClipsDescendants = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.MaxDistance = 0
	sg.ResetOnSpawn = false
	for i, e in gui.elems do
		Realizer.makeFrame(e, i, nil).Parent = sg
	end
	sg.Adornee = adornee
	sg.Parent = adornee
	return sg
end

local function makePart(spec: Builder.PartSpec): BasePart
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
	p.CFrame = spec.cf
	if spec.gui then
		makeSurfaceGui(spec.gui, p)
	end
	return p
end

local function applyLighting(scene: Builder.Scene, effects: Folder): DepthOfFieldEffect?
	local st = scene.style
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

	-- remove effects of the previous style (only ours, tagged by attribute)
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
	end
	if post.cc then
		local c = Instance.new("ColorCorrectionEffect")
		c.Brightness = post.cc.Brightness
		c.Contrast = post.cc.Contrast
		c.Saturation = post.cc.Saturation
		c.TintColor = post.cc.TintColor
		tag(c, Lighting)
	end
	if post.sunrays then
		local s = Instance.new("SunRaysEffect")
		s.Intensity = post.sunrays.Intensity
		s.Spread = post.sunrays.Spread
		tag(s, Lighting)
	end
	local dof: DepthOfFieldEffect? = nil
	if post.dof then
		local d = Instance.new("DepthOfFieldEffect")
		d.FarIntensity = post.dof.FarIntensity
		d.NearIntensity = post.dof.NearIntensity
		d.InFocusRadius = post.dof.InFocusRadius
		d.FocusDistance = 100
		tag(d, Lighting)
		dof = d
	end
	return dof
end

local function makeSnow(spec: Builder.EmitterSpec, parent: Instance)
	local box = Instance.new("Part")
	box.Name = spec.name
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.Transparency = 1
	box.Size = spec.size
	box.CFrame = spec.cf
	local pe = Instance.new("ParticleEmitter")
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.Rate = spec.rate
	pe.Color = ColorSequence.new(spec.color)
	pe.Size = NumberSequence.new(spec.sizeRange[1], spec.sizeRange[2])
	pe.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
	pe.Lifetime = NumberRange.new(spec.lifetime[1], spec.lifetime[2])
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, spec.transparency),
		NumberSequenceKeypoint.new(0.85, spec.transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.SpreadAngle = Vector2.new(18, 18)
	pe.Acceleration = Vector3.new(1.2, -0.6, 0)
	pe.RotSpeed = NumberRange.new(-40, 40)
	pe.LightInfluence = 0.6
	pe.LightEmission = 0.15
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Parent = box
	box.Parent = parent
	-- fill the volume right away so the first frame already has snow
	-- (pcall: Emit is an engine method the offline checker does not have)
	local count = math.floor(spec.rate * spec.lifetime[2] * 0.6)
	pcall(function()
		pe:Emit(count)
	end)
end

function Realizer.build(styleId: string, parent: Instance): Live
	local scene = Scene.build(styleId)
	local root = Instance.new("Folder")
	root.Name = "Cutscene_" .. styleId
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
	local parts: { BasePart } = {}
	local dynamic: { { spec: Builder.PartSpec, part: BasePart } } = {}
	for _, spec in scene.parts do
		local p = makePart(spec)
		p.Parent = models[spec.model] or root
		parts[spec.id] = p
		if spec.rig or spec.channel then
			table.insert(dynamic, { spec = spec, part = p })
		end
	end
	local effects = Instance.new("Folder")
	effects.Name = "Effects"
	effects.Parent = root
	for _, em in scene.emitters do
		makeSnow(em, effects)
	end
	local dof = applyLighting(scene, effects)
	root.Parent = parent
	local moveParts: { BasePart } = {}
	for i, d in dynamic do
		moveParts[i] = d.part
	end
	return {
		scene = scene,
		root = root,
		parts = parts,
		dynamic = dynamic,
		effects = effects,
		dof = dof,
		overlayFrames = {},
		moveParts = moveParts,
		moveCFs = {},
	}
end

-- Overlay elements (split-screen divider) inside a 16:9 container frame
function Realizer.buildOverlay(live: Live, container: GuiObject)
	for _, ch in container:GetChildren() do
		if ch:GetAttribute("CutsceneOverlay") then
			ch:Destroy()
		end
	end
	live.overlayFrames = {}
	local design = Vector2.new(1113, 626)
	for i, e in live.scene.overlay do
		local f = Realizer.makeFrame(e, 10 + i, design)
		f:SetAttribute("CutsceneOverlay", true)
		f.Visible = false
		f.Parent = container
		local g = e.group or "misc"
		live.overlayFrames[g] = live.overlayFrames[g] or {}
		table.insert(live.overlayFrames[g], f)
	end
end

function Realizer.apply(live: Live, frame: Shots.FrameState, camera: Camera, fovScale: number)
	camera.CFrame = frame.camera
	-- keep the 16:9 picture's vertical FOV when the window is taller than 16:9
	local fov = frame.fov
	if fovScale ~= 1 then
		fov = math.deg(2 * math.atan(math.tan(math.rad(fov) / 2) * fovScale))
	end
	camera.FieldOfView = fov
	for i, d in live.dynamic do
		live.moveCFs[i] = Scene.partCFrame(d.spec, frame)
	end
	Workspace:BulkMoveTo(live.moveParts, live.moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
	local dof = live.dof
	local dofStyle = live.scene.style.post.dof
	if dof and dofStyle then
		dof.FocusDistance = frame.focus
		dof.FarIntensity = dofStyle.FarIntensity * frame.dof
		dof.NearIntensity = dofStyle.NearIntensity * frame.dof
	end
	for g, frames in live.overlayFrames do
		local vis = frame.overlay[g] == true
		for _, f in frames do
			f.Visible = vis
		end
	end
end

function Realizer.destroy(live: Live)
	live.root:Destroy()
end

return Realizer
