--!strict
-- Applies a GraphicsPreset to a Lighting instance (+ named children), Terrain clouds and Workspace wind,
-- and provides the pure helpers used for smooth transitions. Lune-safe: no services are touched — every
-- instance is passed in by the caller (GraphicsController on the client, tests/tools under Lune).
--
-- API:
--   Apply.ToLighting(lighting, preset, opts?) -> {string}
--       Idempotently creates/updates SV_Atmosphere, SV_Sky, SV_Bloom, SV_ColorCorrection, SV_SunRays,
--       SV_DOF, SV_ColorGrading under `lighting` and sets the Lighting properties. A missing (or
--       Enabled=false) effect section disables that effect; a missing Atmosphere removes SV_Atmosphere.
--       opts = { Terrain: Instance?  -> also Apply.ToTerrain,
--                Workspace: Instance? -> also Apply.ToWorkspace,
--                Exclusive: boolean?  -> move foreign Sky/Atmosphere/ColorGrading into Lighting.SV_Stash
--                                        (and disable foreign Clouds) so ours are the ones the engine uses }
--       Returns a list of problems (unknown/forbidden keys, failed sets); empty when everything applied.
--   Apply.ToTerrain(terrain, preset, exclusive?) -> {string}   SV_Clouds (Clouds only render under Terrain)
--   Apply.ToWorkspace(workspace, preset) -> {string}            Workspace.GlobalWind
--   Apply.Snapshot(lighting, opts?) -> GraphicsPreset            what is applied now (normalized)
--   Apply.Normalize(preset) -> GraphicsPreset   every section present with every key; effect sections and
--                                              Atmosphere carry `Enabled`; missing values = engine defaults
--   Apply.Lerp(a, b, alpha, out?) -> GraphicsPreset
--       numbers / Color3 / Vector3 lerp; booleans, enums and strings switch at 0.5; ClockTime and
--       GeographicLatitude take the shortest way around the clock / globe; StarCount is rounded; an
--       effect enabled on either side stays enabled mid-way and fades through its neutral value
--       (Bloom.Intensity 0 ...), so effects never pop. `out` (a previous Lerp result) is reused to avoid
--       per-frame allocations. alpha <= 0 / >= 1 return exact copies of a / b.
--   Apply.ForQuality(preset, "Low"|"Medium"|"High"|"Ultra") -> GraphicsPreset   (normalized copy)
--       Low: no DOF, no SunRays, no Clouds, smaller/weaker Bloom, half the stars.
--       Medium: no DOF, SunRays ×0.8, Bloom size ×0.8.  High/Ultra: as authored.
--   Apply.Copy(preset) -> GraphicsPreset        deep copy (normalized)
--   Apply.ALLOWED[section] -> {string}          writable property names per section (the whitelist)
--   Apply.CHILD_NAMES[section] -> string        instance names used under Lighting / Terrain
--   Apply.CLASS_NAMES[section] -> string        engine class per section

local Types = require(script.Parent.Parent.Types)

type GraphicsPreset = Types.GraphicsPreset
type Dict = { [string]: any }

export type Quality = "Low" | "Medium" | "High" | "Ultra"

export type ApplyOptions = {
	Terrain: Instance?,
	Workspace: Instance?,
	Exclusive: boolean?,
}

local Apply = {}

local WHITE = Color3.new(1, 1, 1)

-- Script-writable properties only (checked against the API dump by graphics.spec.luau).
-- Deliberately absent: Lighting.LightingStyle / PrioritizeLightingQuality / Technology (plugin-only),
-- FogColor/FogStart/FogEnd (ignored while an Atmosphere exists), TimeOfDay (string twin of ClockTime),
-- Sky textures (built-in default skybox only — never asset ids).
local ALLOWED: { [string]: { string } } = {
	Lighting = {
		"Ambient",
		"OutdoorAmbient",
		"Brightness",
		"ExposureCompensation",
		"EnvironmentDiffuseScale",
		"EnvironmentSpecularScale",
		"GlobalShadows",
		"ShadowSoftness",
		"ClockTime",
		"GeographicLatitude",
		"ColorShift_Top",
		"ColorShift_Bottom",
	},
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	Sky = { "CelestialBodiesShown", "StarCount", "SunAngularSize", "MoonAngularSize", "SkyboxOrientation" },
	Bloom = { "Intensity", "Size", "Threshold" },
	ColorCorrection = { "Brightness", "Contrast", "Saturation", "TintColor" },
	SunRays = { "Intensity", "Spread" },
	DepthOfField = { "FarIntensity", "NearIntensity", "FocusDistance", "InFocusRadius" },
	ColorGrading = { "TonemapperPreset" },
	Clouds = { "Cover", "Density", "Color" },
}
Apply.ALLOWED = ALLOWED

local ALLOWED_SET: { [string]: { [string]: boolean } } = {}
for section, keys in ALLOWED do
	local set = {}
	for _, key in keys do
		set[key] = true
	end
	ALLOWED_SET[section] = set
end

-- Sections applied as children of Lighting, in application order.
type ChildSpec = { Section: string, Class: string, Name: string, Toggle: boolean }
local LIGHTING_CHILDREN: { ChildSpec } = {
	{ Section = "Atmosphere", Class = "Atmosphere", Name = "SV_Atmosphere", Toggle = false },
	{ Section = "Sky", Class = "Sky", Name = "SV_Sky", Toggle = false },
	{ Section = "Bloom", Class = "BloomEffect", Name = "SV_Bloom", Toggle = true },
	{ Section = "ColorCorrection", Class = "ColorCorrectionEffect", Name = "SV_ColorCorrection", Toggle = true },
	{ Section = "SunRays", Class = "SunRaysEffect", Name = "SV_SunRays", Toggle = true },
	{ Section = "DepthOfField", Class = "DepthOfFieldEffect", Name = "SV_DOF", Toggle = true },
	{ Section = "ColorGrading", Class = "ColorGradingEffect", Name = "SV_ColorGrading", Toggle = true },
}
local CLOUDS_SPEC: ChildSpec = { Section = "Clouds", Class = "Clouds", Name = "SV_Clouds", Toggle = true }

local EFFECT_SECTIONS =
	{ "Atmosphere", "Sky", "Bloom", "ColorCorrection", "SunRays", "DepthOfField", "ColorGrading", "Clouds" }
-- Sections whose absence means "off" (Sky is always drawn: absent = default sky values).
local TOGGLED: { [string]: boolean } = {
	Atmosphere = true,
	Bloom = true,
	ColorCorrection = true,
	SunRays = true,
	DepthOfField = true,
	ColorGrading = true,
	Clouds = true,
}

Apply.CHILD_NAMES = {} :: { [string]: string }
Apply.CLASS_NAMES = { Lighting = "Lighting" } :: { [string]: string }
for _, spec in LIGHTING_CHILDREN do
	Apply.CHILD_NAMES[spec.Section] = spec.Name
	Apply.CLASS_NAMES[spec.Section] = spec.Class
end
Apply.CHILD_NAMES.Clouds = CLOUDS_SPEC.Name
Apply.CLASS_NAMES.Clouds = CLOUDS_SPEC.Class

local OUR_NAMES: { [string]: boolean } = { SV_Clouds = true }
for _, spec in LIGHTING_CHILDREN do
	OUR_NAMES[spec.Name] = true
end

local STASH_NAME = "SV_Stash"

-- Engine defaults (API dump 0.745), used to fill values a preset leaves out. Lighting uses the
-- place-file baseline instead of the bare-instance defaults (GlobalShadows on, softer ambient).
local DEFAULTS: { [string]: Dict } = {
	Lighting = {
		Ambient = Color3.fromRGB(70, 70, 70),
		OutdoorAmbient = Color3.fromRGB(128, 128, 128),
		Brightness = 2,
		ExposureCompensation = 0,
		EnvironmentDiffuseScale = 0.5,
		EnvironmentSpecularScale = 0.5,
		GlobalShadows = true,
		ShadowSoftness = 0.2,
		ClockTime = 14,
		GeographicLatitude = 41.7333,
		ColorShift_Top = Color3.new(0, 0, 0),
		ColorShift_Bottom = Color3.new(0, 0, 0),
	},
	Atmosphere = {
		Density = 0.395,
		Offset = 0,
		Color = Color3.fromRGB(199, 170, 107),
		Decay = Color3.fromRGB(92, 60, 14),
		Glare = 0,
		Haze = 0,
	},
	Sky = {
		CelestialBodiesShown = true,
		StarCount = 3000,
		SunAngularSize = 21,
		MoonAngularSize = 11,
		SkyboxOrientation = Vector3.new(0, 0, 0),
	},
	Bloom = { Intensity = 0.4, Size = 24, Threshold = 0.95 },
	ColorCorrection = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE },
	SunRays = { Intensity = 0.25, Spread = 1 },
	DepthOfField = { FarIntensity = 0.75, NearIntensity = 0.75, FocusDistance = 0.05, InFocusRadius = 10 },
	ColorGrading = { TonemapperPreset = Enum.TonemapperPreset.Default },
	Clouds = { Cover = 0.5, Density = 0.7, Color = WHITE },
}
Apply.DEFAULTS = DEFAULTS

-- What a disabled effect "looks like" while fading in/out (keys not listed keep the other side's value).
local NEUTRAL: { [string]: Dict } = {
	Atmosphere = { Density = 0, Offset = 0, Glare = 0, Haze = 0 },
	Bloom = { Intensity = 0 },
	ColorCorrection = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE },
	SunRays = { Intensity = 0 },
	DepthOfField = { FarIntensity = 0, NearIntensity = 0 },
	ColorGrading = {},
	Clouds = { Cover = 0 },
	Sky = {},
}

-- Tables produced by Normalize/Copy/Lerp/Snapshot/ForQuality (weak keys: no leaks).
local NORMALIZED: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function isNormalized(preset: any): boolean
	return NORMALIZED[preset] == true
end

local function problem(list: { string }, message: string)
	table.insert(list, message)
end

local function setProperty(instance: Instance, key: string, value: any, label: string, problems: { string })
	local ok, err = pcall(function()
		(instance :: any)[key] = value
	end)
	if not ok then
		problem(problems, ("%s.%s: %s"):format(label, key, tostring(err)))
	end
end

-- Creates (fully configured, parented last) or returns the named child of the right class.
local function ensureChild(parent: Instance, spec: ChildSpec, section: Dict, problems: { string }): Instance?
	local existing = parent:FindFirstChild(spec.Name)
	if existing and existing.ClassName == spec.Class then
		return existing
	end
	if existing then
		existing:Destroy() -- same name, wrong class: replace
	end
	local ok, created = pcall(Instance.new, spec.Class)
	if not ok then
		problem(problems, ("%s: cannot create %s (%s)"):format(spec.Section, spec.Class, tostring(created)))
		return nil
	end
	local instance = created :: Instance
	instance.Name = spec.Name
	for key, value in section do
		if ALLOWED_SET[spec.Section][key] then
			setProperty(instance, key, value, spec.Section, problems)
		end
	end
	instance.Parent = parent
	return instance
end

local function applySection(parent: Instance, spec: ChildSpec, section: Dict?, problems: { string })
	local enabled = section ~= nil and section.Enabled ~= false
	if spec.Section == "Sky" then
		enabled = true -- the sky is always drawn; an absent section means default sky values
	end
	if not enabled then
		local existing = parent:FindFirstChild(spec.Name)
		if existing then
			if spec.Toggle and existing.ClassName == spec.Class then
				(existing :: any).Enabled = false
			else
				existing:Destroy() -- Atmosphere has no Enabled: remove it
			end
		end
		return
	end
	local data: Dict = section or DEFAULTS[spec.Section]
	local instance = ensureChild(parent, spec, data, problems)
	if not instance then
		return
	end
	local allowed = ALLOWED_SET[spec.Section]
	for key, value in data do
		if key == "Enabled" then
			continue
		elseif allowed[key] then
			setProperty(instance, key, value, spec.Section, problems)
		else
			problem(problems, ("%s.%s: not an allowed property"):format(spec.Section, tostring(key)))
		end
	end
	if spec.Toggle then
		(instance :: any).Enabled = true
	end
end

local function stashForeign(lighting: Instance)
	local stash: Instance? = nil
	for _, child in lighting:GetChildren() do
		if OUR_NAMES[child.Name] then
			continue
		end
		if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("ColorGradingEffect") then
			if stash == nil then
				stash = lighting:FindFirstChild(STASH_NAME)
				if stash == nil then
					local folder = Instance.new("Folder")
					folder.Name = STASH_NAME
					folder.Parent = lighting
					stash = folder
				end
			end
			child.Parent = stash
		end
	end
end

function Apply.ToTerrain(terrain: Instance, preset: GraphicsPreset, exclusive: boolean?): { string }
	local problems: { string } = {}
	if exclusive then
		for _, child in terrain:GetChildren() do
			if child:IsA("Clouds") and child.Name ~= CLOUDS_SPEC.Name then
				(child :: any).Enabled = false
			end
		end
	end
	applySection(terrain, CLOUDS_SPEC, preset.Clouds, problems)
	return problems
end

function Apply.ToWorkspace(workspaceInstance: Instance, preset: GraphicsPreset): { string }
	local problems: { string } = {}
	setProperty(workspaceInstance, "GlobalWind", preset.GlobalWind or Vector3.new(0, 0, 0), "Workspace", problems)
	return problems
end

function Apply.ToLighting(lighting: Instance, preset: GraphicsPreset, opts: ApplyOptions?): { string }
	local problems: { string } = {}
	local options: ApplyOptions = opts or {}
	if options.Exclusive then
		stashForeign(lighting)
	end
	local allowedLighting = ALLOWED_SET.Lighting
	for key, value in preset.Lighting do
		if allowedLighting[key] then
			setProperty(lighting, key, value, "Lighting", problems)
		else
			problem(problems, ("Lighting.%s: not an allowed property"):format(tostring(key)))
		end
	end
	local p = preset :: any
	for _, spec in LIGHTING_CHILDREN do
		applySection(lighting, spec, p[spec.Section], problems)
	end
	if options.Terrain then
		for _, message in Apply.ToTerrain(options.Terrain, preset, options.Exclusive) do
			table.insert(problems, message)
		end
	end
	if options.Workspace then
		for _, message in Apply.ToWorkspace(options.Workspace, preset) do
			table.insert(problems, message)
		end
	end
	return problems
end

-------------------------------------------------------------------------------------------- normalize

local function normalizeSection(name: string, section: Dict?): Dict
	local out: Dict = {}
	local defaults = DEFAULTS[name]
	local enabled = section ~= nil and section.Enabled ~= false
	if name == "Sky" then
		enabled = true
	end
	for _, key in ALLOWED[name] do
		local value = if section then section[key] else nil
		if value == nil then
			value = defaults[key]
		end
		out[key] = value
	end
	if TOGGLED[name] then
		out.Enabled = enabled
	end
	return out
end

function Apply.Normalize(preset: GraphicsPreset): GraphicsPreset
	if isNormalized(preset) then
		return preset
	end
	local p = preset :: any
	local lighting: Dict = {}
	for _, key in ALLOWED.Lighting do
		local value = preset.Lighting[key]
		if value == nil then
			value = DEFAULTS.Lighting[key]
		end
		lighting[key] = value
	end
	local out: GraphicsPreset = {
		Id = preset.Id,
		Name = preset.Name,
		Desc = preset.Desc,
		Lighting = lighting,
		Atmosphere = normalizeSection("Atmosphere", p.Atmosphere),
		Sky = normalizeSection("Sky", p.Sky),
		Bloom = normalizeSection("Bloom", p.Bloom),
		ColorCorrection = normalizeSection("ColorCorrection", p.ColorCorrection),
		SunRays = normalizeSection("SunRays", p.SunRays),
		DepthOfField = normalizeSection("DepthOfField", p.DepthOfField),
		ColorGrading = normalizeSection("ColorGrading", p.ColorGrading),
		Clouds = normalizeSection("Clouds", p.Clouds),
		GlobalWind = preset.GlobalWind or Vector3.new(0, 0, 0),
		Ambient = if preset.Ambient then table.clone(preset.Ambient) else nil,
	}
	NORMALIZED[out] = true
	return out
end

function Apply.Copy(preset: GraphicsPreset): GraphicsPreset
	local source = Apply.Normalize(preset) :: any
	local out: Dict = {
		Id = source.Id,
		Name = source.Name,
		Desc = source.Desc,
		Lighting = table.clone(source.Lighting),
		GlobalWind = source.GlobalWind,
		Ambient = if source.Ambient then table.clone(source.Ambient) else nil,
	}
	for _, name in EFFECT_SECTIONS do
		out[name] = table.clone(source[name])
	end
	NORMALIZED[out] = true
	return out :: any
end

------------------------------------------------------------------------------------------------- lerp

local function wrapLerp(a: number, b: number, t: number, period: number): number
	local delta = (b - a) % period
	if delta > period / 2 then
		delta -= period
	end
	return (a + delta * t) % period
end

local function lerpValue(key: string, a: any, b: any, t: number): any
	if a == nil then
		return b
	elseif b == nil then
		return a
	end
	local ta, tb = typeof(a), typeof(b)
	if ta ~= tb then
		return if t < 0.5 then a else b
	end
	if ta == "number" then
		if key == "ClockTime" then
			return wrapLerp(a, b, t, 24)
		elseif key == "GeographicLatitude" then
			return wrapLerp(a, b, t, 360)
		elseif key == "StarCount" then
			return math.round(a + (b - a) * t)
		end
		return a + (b - a) * t
	elseif ta == "Color3" then
		return (a :: Color3):Lerp(b :: Color3, t)
	elseif ta == "Vector3" then
		return (a :: Vector3):Lerp(b :: Vector3, t)
	end
	return if t < 0.5 then a else b
end

local function newShell(): Dict
	local shell: Dict = { Lighting = {} }
	for _, name in EFFECT_SECTIONS do
		shell[name] = {}
	end
	return shell
end

local function copyInto(out: Dict, source: Dict)
	out.Id = source.Id
	out.Name = source.Name
	out.Desc = source.Desc
	out.GlobalWind = source.GlobalWind
	out.Ambient = source.Ambient
	local lighting = out.Lighting
	for key, value in source.Lighting do
		lighting[key] = value
	end
	for _, name in EFFECT_SECTIONS do
		local target = out[name]
		for key, value in source[name] do
			target[key] = value
		end
	end
end

function Apply.Lerp(a: GraphicsPreset, b: GraphicsPreset, alpha: number, out: GraphicsPreset?): GraphicsPreset
	local na = Apply.Normalize(a) :: any
	local nb = Apply.Normalize(b) :: any
	local t = math.clamp(alpha, 0, 1)
	local o: Dict = if out ~= nil then out :: any else newShell()
	o.Lighting = o.Lighting or {}
	for _, name in EFFECT_SECTIONS do
		o[name] = o[name] or {}
	end
	NORMALIZED[o] = true

	if t <= 0 then
		copyInto(o, na)
		return o :: any
	elseif t >= 1 then
		copyInto(o, nb)
		return o :: any
	end

	local pick = if t < 0.5 then na else nb
	o.Id = pick.Id
	o.Name = pick.Name
	o.Desc = pick.Desc
	o.Ambient = pick.Ambient
	o.GlobalWind = lerpValue("GlobalWind", na.GlobalWind, nb.GlobalWind, t)

	local lighting = o.Lighting
	for _, key in ALLOWED.Lighting do
		lighting[key] = lerpValue(key, na.Lighting[key], nb.Lighting[key], t)
	end

	for _, name in EFFECT_SECTIONS do
		local sa, sb, so = na[name], nb[name], o[name]
		local neutral = NEUTRAL[name]
		local enabledA = sa.Enabled ~= false
		local enabledB = sb.Enabled ~= false
		for _, key in ALLOWED[name] do
			local va, vb = sa[key], sb[key]
			if not enabledA then
				if neutral[key] ~= nil then
					va = neutral[key]
				else
					va = vb
				end
			end
			if not enabledB then
				if neutral[key] ~= nil then
					vb = neutral[key]
				else
					vb = va
				end
			end
			so[key] = lerpValue(key, va, vb, t)
		end
		if TOGGLED[name] then
			so.Enabled = enabledA or enabledB
		end
	end
	return o :: any
end

---------------------------------------------------------------------------------------------- quality

function Apply.ForQuality(preset: GraphicsPreset, quality: Quality | string): GraphicsPreset
	local p = Apply.Copy(preset) :: any
	if quality == "Low" then
		p.DepthOfField.Enabled = false
		p.SunRays.Enabled = false
		p.Clouds.Enabled = false
		p.Bloom.Size *= 0.55
		p.Bloom.Intensity *= 0.75
		p.Sky.StarCount = math.floor(p.Sky.StarCount * 0.5)
	elseif quality == "Medium" then
		p.DepthOfField.Enabled = false
		p.SunRays.Intensity *= 0.8
		p.Bloom.Size *= 0.8
	end
	return p
end

--------------------------------------------------------------------------------------------- snapshot

local function readSection(instance: Instance?, name: string): Dict
	if instance == nil then
		-- nothing in the scene: a toggled effect is off, the sky shows its defaults
		local section = normalizeSection(name, nil)
		return section
	end
	local out: Dict = {}
	for _, key in ALLOWED[name] do
		local ok, value = pcall(function()
			return (instance :: any)[key]
		end)
		out[key] = if ok then value else DEFAULTS[name][key]
	end
	if TOGGLED[name] then
		if name == "Atmosphere" then
			out.Enabled = true
		else
			out.Enabled = (instance :: any).Enabled
		end
	end
	return out
end

local function findForSnapshot(parent: Instance, spec: ChildSpec): Instance?
	local named = parent:FindFirstChild(spec.Name)
	if named and named.ClassName == spec.Class then
		return named
	end
	return parent:FindFirstChildOfClass(spec.Class)
end

function Apply.Snapshot(lighting: Instance, opts: ApplyOptions?): GraphicsPreset
	local options: ApplyOptions = opts or {}
	local lightingValues: Dict = {}
	for _, key in ALLOWED.Lighting do
		lightingValues[key] = (lighting :: any)[key]
	end
	local out: Dict = {
		Id = "Snapshot",
		Name = { en = "Snapshot", ru = "Снимок" },
		Lighting = lightingValues,
		GlobalWind = Vector3.new(0, 0, 0),
	}
	for _, spec in LIGHTING_CHILDREN do
		out[spec.Section] = readSection(findForSnapshot(lighting, spec), spec.Section)
	end
	if options.Terrain then
		out.Clouds = readSection(findForSnapshot(options.Terrain, CLOUDS_SPEC), "Clouds")
	else
		out.Clouds = normalizeSection("Clouds", nil)
	end
	if options.Workspace then
		local ok, wind = pcall(function()
			return (options.Workspace :: any).GlobalWind
		end)
		if ok and typeof(wind) == "Vector3" then
			out.GlobalWind = wind
		end
	end
	NORMALIZED[out] = true
	return out :: any
end

return Apply
