--!nocheck
-- Graphics: presets data, Apply (a Lune Lighting validates every property name, type and enum), Snapshot,
-- Lerp between all pairs, quality adjustments, preset resolution, EnvExport ranges + JSON, RigStyles
-- apply/revert, Ambient weather builder, strings, client modules require cleanly.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local task = require("@lune/task")

local PRESETS = "ReplicatedStorage.Shared.Graphics.Presets"
local APPLY = "ReplicatedStorage.Shared.Graphics.Apply"
local ENV = "ReplicatedStorage.Shared.Graphics.EnvExport"
local RIGSTYLES = "ReplicatedStorage.Shared.Rigs.RigStyles"
local AMBIENT = "StarterPlayer.StarterPlayerScripts.Client.VFX.Ambient"
local CONTROLLER = "StarterPlayer.StarterPlayerScripts.Client.Controllers.GraphicsController"

local REQUIRED = {
	"GoldenHall",
	"SnowNight",
	"WaterfallGlow",
	"VoidAbyss",
	"CoreInferno",
	"BloodFell",
	"Monochrome",
	"Dreamscape",
	"Lobby",
	"EclipseDark",
	"Performance",
}
local NEEDS_FINAL =
	{ "GoldenHall", "SnowNight", "WaterfallGlow", "VoidAbyss", "CoreInferno", "BloodFell", "Dreamscape", "Monochrome" }
local EFFECTS = { "Atmosphere", "Sky", "Bloom", "ColorCorrection", "SunRays", "DepthOfField", "ColorGrading", "Clouds" }
local FORBIDDEN = { LightingStyle = true, PrioritizeLightingQuality = true, Technology = true }
local BUILTIN_TEXTURES = {
	["rbxasset://textures/particles/sparkles_main.dds"] = true,
	["rbxasset://textures/particles/smoke_main.dds"] = true,
	["rbxasset://textures/particles/fire_main.dds"] = true,
	["rbxasset://textures/particles/fire_sparks_main.dds"] = true,
	["rbxasset://textures/particles/explosion01_core_main.dds"] = true,
	["rbxasset://textures/particles/explosion01_implosion_main.dds"] = true,
	["rbxasset://textures/particles/explosion01_shockwave_main.dds"] = true,
	["rbxasset://textures/particles/explosion01_smoke_main.dds"] = true,
	["rbxasset://textures/particles/forcefield_glow_main.dds"] = true,
	["rbxasset://textures/particles/forcefield_vortex_main.dds"] = true,
}
-- numeric sanity ranges (Studio slider ranges, slightly widened where scripts may exceed them)
local RANGES = {
	Lighting = {
		Brightness = { 0, 10 },
		ExposureCompensation = { -3, 3 },
		EnvironmentDiffuseScale = { 0, 1 },
		EnvironmentSpecularScale = { 0, 1 },
		ShadowSoftness = { 0, 1 },
		ClockTime = { 0, 24 },
		GeographicLatitude = { -360, 360 },
	},
	Atmosphere = { Density = { 0, 1 }, Offset = { 0, 1 }, Glare = { 0, 10 }, Haze = { 0, 10 } },
	Sky = { StarCount = { 0, 5000 }, SunAngularSize = { 0, 60 }, MoonAngularSize = { 0, 60 } },
	Bloom = { Intensity = { 0, 1.5 }, Size = { 0, 56 }, Threshold = { 0.5, 4 } },
	ColorCorrection = { Brightness = { -1, 1 }, Contrast = { -1, 1 }, Saturation = { -1, 1 } },
	SunRays = { Intensity = { 0, 1 }, Spread = { 0, 1 } },
	DepthOfField = {
		FarIntensity = { 0, 1 },
		NearIntensity = { 0, 1 },
		FocusDistance = { 0, 200 },
		InFocusRadius = { 0, 50 },
	},
	Clouds = { Cover = { 0, 1 }, Density = { 0, 1 } },
}

local function scene(Loader)
	local roblox = Loader.roblox
	return roblox.Instance.new("Lighting"), roblox.Instance.new("Terrain"), roblox.Instance.new("Workspace")
end

local function close(a, b, eps)
	eps = eps or 1e-3
	local ta, tb = typeof(a), typeof(b)
	if ta ~= tb then
		return false
	end
	if ta == "number" then
		return math.abs(a - b) <= eps
	elseif ta == "Color3" then
		return math.abs(a.R - b.R) <= eps and math.abs(a.G - b.G) <= eps and math.abs(a.B - b.B) <= eps
	elseif ta == "Vector3" then
		return (a - b).Magnitude <= eps
	end
	return a == b
end

-- API dump (gitignored .tools/): returns class table or nil
local apiClasses = nil
local function api()
	if apiClasses ~= nil then
		return apiClasses or nil
	end
	local path = ".tools/API-Dump.json"
	if not fs.isFile(path) then
		apiClasses = false
		return nil
	end
	local dump = serde.decode("json", fs.readFile(path))
	local classes = {}
	for _, c in dump.Classes do
		classes[c.Name] = c
	end
	apiClasses = classes
	return classes
end

local function findMember(classes, className, name)
	local c = classes[className]
	while c do
		for _, m in c.Members do
			if m.MemberType == "Property" and m.Name == name then
				return m
			end
		end
		c = classes[c.Superclass]
	end
	return nil
end

-- nil when a LocalScript/Script may write this property, else the reason
local function notWritable(member)
	if member == nil then
		return "not in the API dump"
	end
	for _, tag in member.Tags or {} do
		if tag == "NotScriptable" or tag == "ReadOnly" or tag == "Deprecated" or tag == "Hidden" then
			return "tag " .. tag
		end
	end
	local security = member.Security
	local write = if type(security) == "table" then security.Write else security
	if write ~= nil and write ~= "None" then
		return "write security " .. tostring(write)
	end
	local caps = member.Capabilities
	if type(caps) == "table" and type(caps.Write) == "table" then
		for _, cap in caps.Write do
			if string.find(cap, "Plugin") or string.find(cap, "Roblox") then
				return "write capability " .. cap
			end
		end
	end
	return nil
end

local function allPresets(Loader)
	return Loader.require(PRESETS).All()
end

-- Mock signal with a handler count (RBXScriptSignal-like: Connect/Fire).
local function makeSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local entry = { fn = fn }
		table.insert(handlers, entry)
		return {
			Connected = true,
			Disconnect = function()
				for i, e in handlers do
					if e == entry then
						table.remove(handlers, i)
						break
					end
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, e in table.clone(handlers) do
			e.fn(...)
		end
	end
	function signal:Count()
		return #handlers
	end
	return signal
end

-- Loads src/client/Controllers/GraphicsController.luau with mocked engine services so its runtime logic
-- (RoundState binding, transitions, overrides, quality, reduced motion, ambient) can run under Lune.
local function loadControllerWithMocks(Loader)
	local roblox = Loader.roblox
	local world = { warnings = {}, ambientCalls = {} }
	world.lighting = roblox.Instance.new("Lighting")
	world.terrain = roblox.Instance.new("Terrain")
	local wsInstance = roblox.Instance.new("Workspace")
	world.workspace = setmetatable({ Terrain = world.terrain }, {
		__index = function(_, k)
			return wsInstance[k]
		end,
		__newindex = function(_, k, v)
			wsInstance[k] = v
		end,
	})
	-- RoundState: attributes + per-attribute changed signals
	local attrs = { GraphicsPreset = "GoldenHall", MapId = "HallOfVerdicts", FinalPhase = false }
	local attrSignals = {}
	world.roundState = {
		Name = "RoundState",
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		GetAttributeChangedSignal = function(_, k)
			attrSignals[k] = attrSignals[k] or makeSignal()
			return attrSignals[k]
		end,
	}
	function world.setAttribute(k, v)
		attrs[k] = v
		if attrSignals[k] then
			attrSignals[k]:Fire()
		end
	end
	local function marker(path)
		return {
			__module = path,
			IsA = function(_, c)
				return c == "ModuleScript"
			end,
		}
	end
	local function folder(children)
		return {
			WaitForChild = function(_, n)
				return children[n] or error("mock: missing child " .. n)
			end,
			FindFirstChild = function(_, n)
				return children[n]
			end,
		}
	end
	local shared = folder({
		Types = marker("ReplicatedStorage.Shared.Types"),
		Config = marker("ReplicatedStorage.Shared.Config"),
		Graphics = folder({ Presets = marker(PRESETS), Apply = marker(APPLY) }),
	})
	local replicatedStorage = {
		WaitForChild = function(_, n)
			return if n == "Shared" then shared else error("mock: missing " .. n)
		end,
		FindFirstChild = function(_, n)
			return if n == "RoundState" then world.roundState else nil
		end,
		ChildAdded = makeSignal(),
	}
	world.runService = { PreRender = makeSignal(), Heartbeat = makeSignal() }
	local guiSignals = {}
	world.guiService = { ReducedMotionEnabled = false }
	function world.guiService:GetPropertyChangedSignal(name)
		guiSignals[name] = guiSignals[name] or makeSignal()
		return guiSignals[name]
	end
	world.guiSignals = guiSignals
	local uis = {
		TouchEnabled = false,
		KeyboardEnabled = true,
		WindowFocused = makeSignal(),
		WindowFocusReleased = makeSignal(),
	}
	local userGameSettings = { SavedQualityLevel = roblox.Enum.SavedQualitySetting.QualityLevel7 }
	function userGameSettings:GetPropertyChangedSignal()
		return makeSignal()
	end
	local services = {
		Lighting = world.lighting,
		ReplicatedStorage = replicatedStorage,
		RunService = world.runService,
		GuiService = world.guiService,
		UserInputService = uis,
	}
	local fakeAmbient = {}
	function fakeAmbient.Set(id, density, opts)
		table.insert(world.ambientCalls, { id = id, density = density, timeScale = opts and opts.TimeScale })
	end
	local ambientMarker = {
		__fake = fakeAmbient,
		IsA = function(_, c)
			return c == "ModuleScript"
		end,
	}
	local controllersFolder = folder({})
	controllersFolder.Parent = folder({ VFX = folder({ Ambient = ambientMarker }) })
	local env = setmetatable({
		game = {
			GetService = function(_, n)
				return services[n] or error("mock: no service " .. n)
			end,
		},
		workspace = world.workspace,
		script = { Name = "GraphicsController", Parent = controllersFolder },
		require = function(target)
			if type(target) == "table" and target.__module then
				return Loader.require(target.__module)
			elseif type(target) == "table" and target.__fake then
				return target.__fake
			end
			error("mock: unexpected require")
		end,
		UserSettings = function()
			return {
				GetService = function()
					return userGameSettings
				end,
			}
		end,
		warn = function(...)
			table.insert(world.warnings, table.concat({ ... }, " "))
		end,
		task = task,
		Instance = roblox.Instance,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		Enum = roblox.Enum,
	}, { __index = _G })
	local source = fs.readFile("src/client/Controllers/GraphicsController.luau")
	local chunk = luau.load(source, { debugName = "GraphicsController(mock)", environment = env, injectGlobals = true })
	world.controller = chunk()
	-- drive frames
	function world.frames(seconds, dt)
		dt = dt or 0.1
		local steps = math.floor(seconds / dt + 0.5)
		for _ = 1, steps do
			world.runService.PreRender:Fire(dt)
		end
	end
	return world
end

return {
	presets_registry_and_data = function(T, Loader)
		local Presets = Loader.require(PRESETS)
		local Apply = Loader.require(APPLY)
		local Ambient = Loader.require(AMBIENT)
		T.ok(#Presets.Ids() >= 20, "at least 20 presets")
		for _, id in REQUIRED do
			T.ok(Presets.Has(id), "missing preset " .. id)
		end
		for _, id in NEEDS_FINAL do
			T.eq(Presets.FinalOf(id), id .. "Final", "final variant of " .. id)
		end
		T.eq(Presets.FinalOf("GoldenHallFinal"), "GoldenHallFinal", "a final maps to itself")
		T.eq(Presets.FinalOf("EclipseDark"), nil, "no final for EclipseDark")
		T.eq(Presets.Kind("GoldenHall"), "Map")
		T.eq(Presets.Kind("VoidAbyssFinal"), "Final")
		T.eq(Presets.Kind("EclipseDark"), "Special")
		T.eq(Presets.Kind("Monochrome"), "Style")
		local base, final = Presets.ForMap("HallOfVerdicts")
		T.eq(base, "GoldenHall")
		T.eq(final, "GoldenHallFinal")
		for _, p in allPresets(Loader) do
			local label = p.Id
			T.ok(p.Name and p.Name.en ~= "" and p.Name.ru ~= "", label .. " name en/ru")
			T.ok(p.Desc and p.Desc.en ~= "" and p.Desc.ru ~= "", label .. " desc en/ru")
			for _, key in Apply.ALLOWED.Lighting do
				T.ok(p.Lighting[key] ~= nil, label .. " Lighting." .. key .. " must be set (complete presets)")
			end
			for section, values in p do
				if type(values) == "table" and section ~= "Name" and section ~= "Desc" and section ~= "Ambient" then
					for key in values do
						T.ok(not FORBIDDEN[key], label .. "." .. section .. "." .. tostring(key) .. " is plugin-only")
						T.ok(
							type(key) ~= "string" or string.sub(key, 1, 6) ~= "Skybox" or key == "SkyboxOrientation",
							label .. " uses sky textures"
						)
					end
				end
			end
			for section, ranges in RANGES do
				local values = p[section]
				if values then
					for key, range in ranges do
						local v = values[key]
						if v ~= nil then
							T.ok(
								v >= range[1] and v <= range[2],
								("%s.%s.%s = %s outside %s..%s"):format(
									label,
									section,
									key,
									tostring(v),
									range[1],
									range[2]
								)
							)
						end
					end
				end
			end
			if p.Ambient then
				T.ok(Ambient.Has(p.Ambient.Particles), label .. " unknown weather " .. tostring(p.Ambient.Particles))
				T.ok(
					type(p.Ambient.Density) == "number" and p.Ambient.Density > 0 and p.Ambient.Density <= 2,
					label .. " weather density"
				)
			end
			T.ok(p.GlobalWind == nil or typeof(p.GlobalWind) == "Vector3", label .. " GlobalWind")
			-- the blue/orange attack colour rules must stay readable in every look
			local cc = p.ColorCorrection
			T.ok(
				cc == nil or cc.Saturation == nil or cc.Saturation >= -0.85,
				label .. " keeps enough colour for attack rules"
			)
		end
		-- performance stays cheap
		local perf = Presets.Get("Performance")
		T.ok(
			perf.DepthOfField == nil and perf.SunRays == nil and perf.Clouds == nil,
			"Performance has no DOF/SunRays/Clouds"
		)
		T.eq(perf.Lighting.GlobalShadows, false, "Performance disables shadows")
	end,

	presets_only_script_writable_properties = function(T, Loader)
		local classes = api()
		if classes == nil then
			print("  (graphics.spec: .tools/API-Dump.json not found — API writability check skipped)")
			T.ok(true)
			return
		end
		local Apply = Loader.require(APPLY)
		-- the whitelist itself
		for section, keys in Apply.ALLOWED do
			local className = Apply.CLASS_NAMES[section]
			T.ok(className ~= nil, "class for " .. section)
			for _, key in keys do
				local reason = notWritable(findMember(classes, className, key))
				T.ok(reason == nil, ("%s.%s is not script-writable: %s"):format(className, key, tostring(reason)))
			end
			if section ~= "Lighting" and section ~= "Atmosphere" and section ~= "Sky" then
				local reason = notWritable(findMember(classes, className, "Enabled"))
				T.ok(reason == nil, className .. ".Enabled writable")
			end
		end
		T.ok(notWritable(findMember(classes, "Workspace", "GlobalWind")) == nil, "Workspace.GlobalWind writable")
		-- the plugin-only ones really are plugin-only (so the whitelist must never contain them)
		T.ok(notWritable(findMember(classes, "Lighting", "LightingStyle")) ~= nil, "LightingStyle is plugin-only")
		T.ok(notWritable(findMember(classes, "Lighting", "Technology")) ~= nil, "Technology is not scriptable")
		-- every key used by every preset is whitelisted
		for _, p in allPresets(Loader) do
			for _, section in { "Lighting", table.unpack(EFFECTS) } do
				local values = p[section]
				if values then
					local allowed = {}
					for _, key in Apply.ALLOWED[section] do
						allowed[key] = true
					end
					for key in values do
						T.ok(
							allowed[key] or key == "Enabled",
							("%s.%s.%s not whitelisted"):format(p.Id, section, tostring(key))
						)
					end
				end
			end
		end
	end,

	apply_every_preset_to_lune_lighting = function(T, Loader)
		local Apply = Loader.require(APPLY)
		for _, p in allPresets(Loader) do
			local lighting, terrain, ws = scene(Loader)
			local problems = Apply.ToLighting(lighting, p, { Terrain = terrain, Workspace = ws, Exclusive = true })
			T.eq(#problems, 0, p.Id .. " applies cleanly: " .. table.concat(problems, "; "))
			for key, value in p.Lighting do
				T.ok(close(lighting[key], value), ("%s Lighting.%s"):format(p.Id, key))
			end
			for _, section in EFFECTS do
				local name = Apply.CHILD_NAMES[section]
				local parent = if section == "Clouds" then terrain else lighting
				local inst = parent:FindFirstChild(name)
				local data = p[section]
				if data then
					T.ok(inst ~= nil and inst.ClassName == Apply.CLASS_NAMES[section], p.Id .. " creates " .. name)
					if inst then
						for key, value in data do
							T.ok(close(inst[key], value), ("%s %s.%s"):format(p.Id, name, key))
						end
						if section ~= "Atmosphere" and section ~= "Sky" then
							T.eq(inst.Enabled, true, p.Id .. " " .. name .. " enabled")
						end
					end
				elseif section == "Sky" then
					T.ok(inst ~= nil, p.Id .. " always has a sky")
				else
					T.ok(inst == nil or inst.Enabled == false, p.Id .. " " .. name .. " off when absent")
				end
			end
			T.ok(close(ws.GlobalWind, p.GlobalWind or Loader.roblox.Vector3.new(0, 0, 0)), p.Id .. " GlobalWind")
		end
	end,

	apply_is_idempotent_across_switches = function(T, Loader)
		local Apply = Loader.require(APPLY)
		local lighting, terrain, ws = scene(Loader)
		local opts = { Terrain = terrain, Workspace = ws, Exclusive = true }
		for _ = 1, 2 do
			for _, p in allPresets(Loader) do
				T.eq(#Apply.ToLighting(lighting, p, opts), 0, p.Id .. " re-apply")
			end
		end
		local p = Loader.require(PRESETS).Get("GoldenHall")
		Apply.ToLighting(lighting, p, opts)
		local first = Apply.Snapshot(lighting, opts)
		local childCount = #lighting:GetChildren()
		Apply.ToLighting(lighting, p, opts)
		local second = Apply.Snapshot(lighting, opts)
		T.eq(#lighting:GetChildren(), childCount, "no duplicate children")
		T.eq(childCount, 7, "seven SV_ children under Lighting")
		T.eq(#terrain:GetChildren(), 1, "one SV_Clouds under Terrain")
		for _, section in { "Lighting", table.unpack(EFFECTS) } do
			for key, value in first[section] do
				T.ok(close(second[section][key], value), "stable " .. section .. "." .. key)
			end
		end
	end,

	apply_exclusive_and_forbidden = function(T, Loader)
		local roblox = Loader.roblox
		local Apply = Loader.require(APPLY)
		local lighting, terrain, ws = scene(Loader)
		local foreignSky = roblox.Instance.new("Sky")
		foreignSky.Parent = lighting
		local foreignAtmosphere = roblox.Instance.new("Atmosphere")
		foreignAtmosphere.Parent = lighting
		local foreignBloom = roblox.Instance.new("BloomEffect")
		foreignBloom.Parent = lighting
		local foreignClouds = roblox.Instance.new("Clouds")
		foreignClouds.Parent = terrain
		local p = Loader.require(PRESETS).Get("SnowNight")
		T.eq(#Apply.ToLighting(lighting, p, { Terrain = terrain, Workspace = ws, Exclusive = true }), 0, "clean")
		T.eq(foreignSky.Parent and foreignSky.Parent.Name, "SV_Stash", "foreign Sky stashed")
		T.eq(foreignAtmosphere.Parent and foreignAtmosphere.Parent.Name, "SV_Stash", "foreign Atmosphere stashed")
		T.eq(foreignBloom.Parent, lighting, "foreign post effects are left alone (they compose)")
		T.eq(foreignClouds.Enabled, false, "foreign Clouds disabled")
		-- non-exclusive applies leave foreign objects alone
		local l2 = roblox.Instance.new("Lighting")
		local sky2 = roblox.Instance.new("Sky")
		sky2.Parent = l2
		Apply.ToLighting(l2, p)
		T.eq(sky2.Parent, l2, "non-exclusive keeps foreign Sky")
		-- plugin-only and texture keys are refused, not written
		local bad = {
			Id = "Bad",
			Name = { en = "Bad", ru = "Плохой" },
			Lighting = { LightingStyle = roblox.Enum.LightingStyle.Soft, Brightness = 1 },
			Sky = { SkyboxBk = "rbxassetid://1" },
		}
		local l3 = roblox.Instance.new("Lighting")
		local before = l3.LightingStyle
		local problems = Apply.ToLighting(l3, bad)
		T.eq(#problems, 2, "two refused keys: " .. table.concat(problems, "; "))
		T.eq(l3.LightingStyle, before, "LightingStyle untouched")
		T.eq(l3.Brightness, 1, "allowed key still applied")
		local sky3 = l3:FindFirstChild("SV_Sky")
		T.ok(sky3 and sky3.SkyboxBk == "rbxasset://textures/sky/sky512_bk.tex", "default sky texture kept")
	end,

	snapshot_matches_applied_preset = function(T, Loader)
		local Apply = Loader.require(APPLY)
		for _, p in allPresets(Loader) do
			local lighting, terrain, ws = scene(Loader)
			Apply.ToLighting(lighting, p, { Terrain = terrain, Workspace = ws })
			local snap = Apply.Snapshot(lighting, { Terrain = terrain, Workspace = ws })
			local norm = Apply.Normalize(p)
			for _, section in { "Lighting", table.unpack(EFFECTS) } do
				for key, value in norm[section] do
					local enabled = norm[section].Enabled ~= false
					if enabled or key == "Enabled" then
						T.ok(close(snap[section][key], value), ("%s snapshot %s.%s"):format(p.Id, section, key))
					end
				end
			end
			T.ok(close(snap.GlobalWind, norm.GlobalWind), p.Id .. " snapshot wind")
		end
	end,

	lerp_between_all_pairs = function(T, Loader)
		local Apply = Loader.require(APPLY)
		local list = allPresets(Loader)
		local lighting, terrain, ws = scene(Loader)
		local out = nil
		local failures = 0
		for _, a in list do
			local na = Apply.Normalize(a)
			for _, b in list do
				local nb = Apply.Normalize(b)
				local at0 = Apply.Lerp(a, b, 0)
				local at1 = Apply.Lerp(a, b, 1)
				out = Apply.Lerp(a, b, 0.5, out)
				for _, section in { "Lighting", table.unpack(EFFECTS) } do
					for key, va in na[section] do
						local vb = nb[section][key]
						if at0[section][key] ~= va or at1[section][key] ~= vb then
							failures += 1
						end
						local mid = out[section][key]
						if key == "Enabled" then
							if mid ~= (va or vb) then
								failures += 1
							end
						elseif type(va) == "number" and key ~= "ClockTime" and key ~= "GeographicLatitude" then
							local enabledA, enabledB = na[section].Enabled ~= false, nb[section].Enabled ~= false
							if
								enabledA
								and enabledB
								and (mid < math.min(va, vb) - 1e-6 or mid > math.max(va, vb) + 1e-6)
							then
								failures += 1
							end
						elseif type(va) == "boolean" and section == "Lighting" then
							if mid ~= vb then -- booleans switch at 0.5 (alpha 0.5 -> b)
								failures += 1
							end
						end
					end
				end
				T.ok(
					out.Lighting.ClockTime >= 0 and out.Lighting.ClockTime < 24,
					"clock wrapped " .. a.Id .. ">" .. b.Id
				)
				local problems = Apply.ToLighting(lighting, out, { Terrain = terrain, Workspace = ws })
				if #problems > 0 then
					failures += 1
					print("  lerp apply problems " .. a.Id .. ">" .. b.Id .. ": " .. table.concat(problems, "; "))
				end
			end
		end
		T.eq(failures, 0, "lerp endpoint/mid/apply failures over " .. (#list * #list) .. " pairs")
	end,

	lerp_details = function(T, Loader)
		local roblox = Loader.roblox
		local Apply = Loader.require(APPLY)
		local Presets = Loader.require(PRESETS)
		local function only(clock, lat)
			return {
				Id = "x",
				Name = { en = "x", ru = "x" },
				Lighting = { ClockTime = clock, GeographicLatitude = lat },
			}
		end
		local mid = Apply.Lerp(only(23, 350), only(1, 10), 0.5)
		T.ok(
			close(mid.Lighting.ClockTime, 0) or close(mid.Lighting.ClockTime, 24),
			"23 -> 1 goes through midnight, got " .. mid.Lighting.ClockTime
		)
		T.ok(
			close(mid.Lighting.GeographicLatitude, 0) or close(mid.Lighting.GeographicLatitude, 360),
			"350 -> 10 latitude wraps"
		)
		local evening = Apply.Lerp(Presets.Get("GoldenHall"), Presets.Get("EclipseDark"), 0.5)
		T.ok(
			evening.Lighting.ClockTime > 17.35 and evening.Lighting.ClockTime < 24,
			"GoldenHall -> EclipseDark sweeps through sunset, not noon"
		)
		-- effects fade through neutral instead of popping
		local snow, gold = Presets.Get("SnowNight"), Presets.Get("GoldenHall")
		local a = Apply.Lerp(snow, gold, 0.25)
		T.eq(a.SunRays.Enabled, true, "SunRays enabled while fading in")
		T.near(a.SunRays.Intensity, gold.SunRays.Intensity * 0.25, 1e-4, "SunRays intensity fades from 0")
		local b = Apply.Lerp(gold, snow, 1)
		T.eq(b.SunRays.Enabled, false, "SunRays off at the end")
		-- out table reuse
		local out = Apply.Lerp(snow, gold, 0.1)
		T.eq(Apply.Lerp(snow, gold, 0.9, out), out, "Lerp reuses out")
		T.ok(close(out.Lighting.Ambient, snow.Lighting.Ambient:Lerp(gold.Lighting.Ambient, 0.9)), "Color3 lerp")
		T.ok(close(out.GlobalWind, snow.GlobalWind:Lerp(gold.GlobalWind, 0.9)), "wind lerp")
		T.eq(Apply.Lerp(snow, gold, 0.4).Ambient.Particles, "Snow", "weather switches at 0.5 (before)")
		T.eq(Apply.Lerp(snow, gold, 0.6).Ambient.Particles, "Dust", "weather switches at 0.5 (after)")
		T.eq(Apply.Lerp(snow, gold, 0.6).Sky.StarCount % 1, 0, "StarCount stays an integer")
		-- enum switch
		local mono = Presets.Get("Monochrome")
		T.eq(Apply.Lerp(gold, mono, 0.49).ColorGrading.TonemapperPreset, roblox.Enum.TonemapperPreset.Default)
		T.eq(Apply.Lerp(gold, mono, 0.51).ColorGrading.TonemapperPreset, roblox.Enum.TonemapperPreset.Retro)
		-- presets themselves are never mutated
		T.eq(gold.SunRays.Intensity, 0.14, "source preset untouched")
	end,

	quality_adjustments = function(T, Loader)
		local Apply = Loader.require(APPLY)
		local gold = Loader.require(PRESETS).Get("GoldenHall")
		local low = Apply.ForQuality(gold, "Low")
		T.eq(low.DepthOfField.Enabled, false, "Low: no DOF")
		T.eq(low.SunRays.Enabled, false, "Low: no SunRays")
		T.eq(low.Clouds.Enabled, false, "Low: no Clouds")
		T.ok(low.Bloom.Size < gold.Bloom.Size and low.Bloom.Intensity < gold.Bloom.Intensity, "Low: smaller bloom")
		local medium = Apply.ForQuality(gold, "Medium")
		T.eq(medium.DepthOfField.Enabled, false, "Medium: no DOF")
		T.eq(medium.SunRays.Enabled, true, "Medium keeps SunRays")
		local high = Apply.ForQuality(gold, "High")
		T.eq(high.DepthOfField.Enabled, true, "High keeps DOF")
		T.eq(high.Bloom.Size, gold.Bloom.Size, "High as authored")
		-- the global dim (owner: too bright) applies to every tier
		T.near(high.Lighting.ExposureCompensation, gold.Lighting.ExposureCompensation + Apply.DIM.Exposure, 1e-9, "dimmer exposure")
		T.ok(high.Lighting.Brightness < gold.Lighting.Brightness, "dimmer brightness")
		T.ok(high.Bloom.Intensity < gold.Bloom.Intensity, "softer bloom")
		T.eq(gold.Bloom.Size, 30, "ForQuality does not mutate the preset")
		local lighting, terrain, ws = scene(Loader)
		T.eq(#Apply.ToLighting(lighting, low, { Terrain = terrain, Workspace = ws }), 0, "Low applies")
		T.eq(lighting:FindFirstChild("SV_DOF"), nil, "a disabled effect is not even created")
		T.eq(#Apply.ToLighting(lighting, high, { Terrain = terrain, Workspace = ws }), 0, "High applies")
		T.eq(lighting:FindFirstChild("SV_DOF").Enabled, true, "High: DOF on")
		Apply.ToLighting(lighting, low, { Terrain = terrain, Workspace = ws })
		T.eq(lighting:FindFirstChild("SV_DOF").Enabled, false, "back to Low: DOF instance kept but disabled")
		T.eq(terrain:FindFirstChild("SV_Clouds").Enabled, false, "Low: clouds off")
	end,

	resolve_rules = function(T, Loader)
		local Presets = Loader.require(PRESETS)
		local function resolve(state)
			return (Presets.Resolve(state))
		end
		T.eq(resolve({}), "Lobby", "nothing known -> Lobby")
		T.eq(resolve({ MapPreset = "GoldenHall" }), "GoldenHall")
		T.eq(resolve({ MapPreset = "GoldenHall", FinalPhase = true }), "GoldenHallFinal")
		T.eq(resolve({ MapPreset = "Lobby", FinalPhase = true }), "Lobby", "no final variant -> same preset")
		T.eq(resolve({ MapPreset = "Nope", MapId = "VoidRift" }), "VoidAbyss", "MapId fallback")
		T.eq(resolve({ MapId = "VoidRift", FinalPhase = true }), "VoidAbyssFinal")
		T.eq(
			resolve({ MapPreset = "GoldenHall", FinalPreset = "BloodFellFinal", FinalPhase = true }),
			"BloodFellFinal",
			"explicit final"
		)
		T.eq(resolve({ MapPreset = "GoldenHall", UserOverride = "MapDefault" }), "GoldenHall")
		T.eq(resolve({ MapPreset = "GoldenHall", UserOverride = "Monochrome" }), "Monochrome")
		T.eq(resolve({ MapPreset = "GoldenHall", UserOverride = "Monochrome", FinalPhase = true }), "MonochromeFinal")
		T.eq(resolve({ MapPreset = "GoldenHall", UserOverride = "Performance", FinalPhase = true }), "PerformanceFinal")
		T.eq(resolve({ MapPreset = "GoldenHall", UserOverride = "Bogus" }), "GoldenHall", "unknown user choice ignored")
		local overrides = {
			{ Key = "StyleLab", PresetId = "Dreamscape", Priority = 50, Order = 1 },
			{ Key = "EclipseUlt", PresetId = "EclipseDark", Priority = 100, Order = 2 },
		}
		local id, source = Presets.Resolve({
			MapPreset = "GoldenHall",
			UserOverride = "Monochrome",
			FinalPhase = true,
			Overrides = overrides,
		})
		T.eq(id, "EclipseDark", "highest priority override wins and is exact (no final)")
		T.eq(source, "Override:EclipseUlt")
		T.eq(
			resolve({
				MapPreset = "GoldenHall",
				Overrides = {
					{ Key = "A", PresetId = "Dreamscape", Priority = 50, Order = 1 },
					{ Key = "B", PresetId = "BloodFell", Priority = 50, Order = 2 },
				},
			}),
			"BloodFell",
			"newest wins a priority tie"
		)
		T.eq(
			resolve({
				MapPreset = "GoldenHall",
				Overrides = { { Key = "X", PresetId = "Nope", Priority = 999, Order = 1 } },
			}),
			"GoldenHall",
			"unknown override ignored"
		)
	end,

	envexport_ranges_and_json = function(T, Loader)
		local EnvExport = Loader.require(ENV)
		for _, p in allPresets(Loader) do
			local env = EnvExport.FromPreset(p)
			local problems = EnvExport.Validate(env)
			T.eq(#problems, 0, p.Id .. " env in range: " .. table.concat(problems, "; "))
			local decoded = serde.decode("json", EnvExport.ToJson(env, true))
			for _, key in { "sky", "sun", "ambient", "fog", "bloom", "exposure", "saturation", "contrast", "tint" } do
				T.ok(decoded[key] ~= nil, p.Id .. " json has " .. key)
			end
			T.near(decoded.sun.intensity, env.sun.intensity, 1e-4, p.Id .. " json roundtrip")
			T.eq(#decoded.sky.horizon, 3, p.Id .. " rgb arrays")
			T.ok(EnvExport.ToJson(env) == EnvExport.ToJson(EnvExport.FromPreset(p)), p.Id .. " deterministic")
		end
	end,

	envexport_sun_convention = function(T, Loader)
		local EnvExport = Loader.require(ENV)
		local Presets = Loader.require(PRESETS)
		local noon = EnvExport.SunDirection(12, 23.5)
		T.ok(math.abs(noon.Y - 1) < 1e-6, "noon at latitude 23.5 is overhead")
		local rise = EnvExport.SunDirection(6, 41.73)
		T.ok(rise.X > 0.9 and math.abs(rise.Y) < 1e-6, "sunrise on the +X (east) horizon")
		local set = EnvExport.SunDirection(18, 41.73)
		T.ok(set.X < -0.9 and math.abs(set.Y) < 1e-6, "sunset on the -X (west) horizon")
		T.ok(EnvExport.SunDirection(14, 41.73).Y > 0.7, "afternoon sun is high")
		T.ok(EnvExport.SunDirection(0, 41.73).Y < -0.5, "midnight sun is below the horizon")
		T.ok(EnvExport.MoonDirection(0, 41.73).Y > 0.5, "midnight moon is up")
		local gold = EnvExport.FromPreset(Presets.Get("GoldenHall"))
		T.ok(gold.sun.dir[2] > 0.05 and gold.sun.dir[1] < -0.9, "GoldenHall: low sun from the west")
		T.ok(gold.sun.color[3] < gold.sun.color[1] * 0.6, "GoldenHall: warm sun")
		local snow = EnvExport.FromPreset(Presets.Get("SnowNight"))
		T.ok(snow.sun.dir[2] > 0.2 and snow.sun.color[3] >= snow.sun.color[1], "SnowNight: bluish moonlight from above")
		local eclipse = EnvExport.FromPreset(Presets.Get("EclipseDark"))
		T.ok(eclipse.fog.far < 80, "EclipseDark: you only see nearby")
		T.ok(eclipse.sun.intensity < 0.1, "EclipseDark: almost no key light")
		local perf = EnvExport.FromPreset(Presets.Get("Performance"))
		T.ok(close(perf.ambient.sky[1], perf.ambient.ground[1]), "no GlobalShadows: flat ambient")
	end,

	rigstyles_apply_revert = function(T, Loader)
		local roblox = Loader.roblox
		local Instance, Color3, Enum = roblox.Instance, roblox.Color3, roblox.Enum
		local RigStyles = Loader.require(RIGSTYLES)

		local model = Instance.new("Model")
		model.Name = "TestRig"
		local function part(name, role, material, color, reflectance, parent)
			local p = Instance.new("Part")
			p.Name = name
			p.Material = material
			p.Color = color
			p.Reflectance = reflectance or 0
			if role then
				p:SetAttribute("Role", role)
			end
			p.Parent = parent or model
			return p
		end
		local root = part("HumanoidRootPart", nil, Enum.Material.Plastic, Color3.fromRGB(163, 162, 165))
		local head = part("Head", nil, Enum.Material.Plastic, Color3.fromRGB(163, 162, 165))
		local cloth = part("Jacket", "Cloth", Enum.Material.Plastic, Color3.fromRGB(40, 80, 160))
		local trim = part("Fur", "Trim", Enum.Material.SmoothPlastic, Color3.fromRGB(230, 230, 230))
		local skin = part("Skull", "Bone", Enum.Material.Plastic, Color3.fromRGB(240, 240, 235))
		local metal = part("Buckle", "Metal", Enum.Material.Metal, Color3.fromRGB(200, 180, 90), 0.05)
		local accent = part("Stripe", "Accent", Enum.Material.Plastic, Color3.fromRGB(150, 30, 30))
		local pupilL = part("LeftPupil", "Eye", Enum.Material.Neon, Color3.fromRGB(255, 255, 255), 0, head)
		local pupilR = part("RightPupil", "Eye", Enum.Material.Neon, Color3.fromRGB(255, 255, 255), 0, head)
		local eyeExtra = part("BrowGlow", "Eye", Enum.Material.Neon, Color3.fromRGB(120, 200, 255), 0, head)
		local glow = part("Aura", "Glow", Enum.Material.Neon, Color3.fromRGB(90, 160, 255))
		local glass = part("Visor", "Detail", Enum.Material.Glass, Color3.fromRGB(200, 220, 255))
		local all = { root, head, cloth, trim, skin, metal, accent, pupilL, pupilR, eyeExtra, glow, glass }
		local original = {}
		for _, p in all do
			original[p] = { p.Material, p.Color, p.Reflectance }
		end
		local function countClass(className)
			local n = 0
			for _, d in model:GetDescendants() do
				if d.ClassName == className then
					n += 1
				end
			end
			return n
		end
		local function snapshot()
			local s = {}
			for _, p in all do
				s[p] = { p.Material, p.Color, p.Reflectance }
			end
			return s
		end
		local function same(a, b)
			for p, v in a do
				if v[1] ~= b[p][1] or not close(v[2], b[p][2], 0.005) or not close(v[3], b[p][3], 1e-4) then
					return false, p.Name
				end
			end
			return true
		end

		T.eq(table.concat(RigStyles.List(), ","), "Classic,Toon,Soft,Glow", "style list")
		for _, id in RigStyles.List() do
			local info = RigStyles.Get(id)
			T.ok(info and info.Name.ru ~= "" and info.Desc.en ~= "", id .. " info")
		end

		-- Toon
		T.eq(RigStyles.Apply(model, "Toon"), true)
		T.eq(countClass("Highlight"), 1, "Toon: one outline")
		local outline = model:FindFirstChild(RigStyles.OUTLINE_NAME)
		T.ok(outline ~= nil, "outline named")
		if outline then
			T.eq(outline.FillTransparency, 1)
			T.eq(outline.OutlineTransparency, 0)
			T.eq(outline.DepthMode, Enum.HighlightDepthMode.Occluded)
			T.ok(close(outline.OutlineColor, Color3.new(0, 0, 0)), "black outline")
		end
		T.eq(cloth.Material, Enum.Material.SmoothPlastic, "Toon: cloth smooth")
		T.eq(pupilL.Material, Enum.Material.Neon, "Toon keeps neon")
		T.eq(glass.Material, Enum.Material.Glass, "Toon keeps glass")
		T.eq(root.Material, Enum.Material.Plastic, "physics parts untouched")
		T.eq(RigStyles.Current(model), "Toon")
		local toonState = snapshot()
		RigStyles.Apply(model, "Toon")
		T.eq(countClass("Highlight"), 1, "Toon twice: still one outline")
		T.ok(same(toonState, snapshot()), "Toon idempotent")
		RigStyles.SetOutlineVisible(model, false)
		T.eq(model:FindFirstChild(RigStyles.OUTLINE_NAME).Enabled, false, "outline can be hidden")

		-- Soft
		RigStyles.Apply(model, "Soft")
		T.eq(countClass("Highlight"), 0, "Soft: no outline")
		T.eq(cloth.Material, Enum.Material.Fabric, "Soft: cloth fabric")
		T.eq(trim.Material, Enum.Material.Fabric, "Soft: trim fabric")
		T.eq(skin.Material, Enum.Material.SmoothPlastic, "Soft: bone smooth")
		T.eq(metal.Material, Enum.Material.Metal, "Soft: metal stays metal")
		T.ok(metal.Reflectance > 0.1, "Soft: metal shine")
		T.eq(accent.Material, Enum.Material.Plastic, "Soft: accent untouched")

		-- Glow
		RigStyles.Apply(model, "Glow")
		T.eq(accent.Material, Enum.Material.Neon, "Glow: accent neon")
		local _, _, vBefore = original[accent][2]:ToHSV()
		local _, _, vAfter = accent.Color:ToHSV()
		T.ok(vAfter > vBefore + 0.1, "Glow: accent brighter")
		T.eq(countClass("PointLight"), RigStyles.MAX_EYE_LIGHTS, "Glow: eye lights capped")
		T.ok(
			pupilL:FindFirstChild(RigStyles.EYE_LIGHT_NAME) ~= nil
				and pupilR:FindFirstChild(RigStyles.EYE_LIGHT_NAME) ~= nil,
			"pupils get the lights first"
		)
		local light = pupilL:FindFirstChild(RigStyles.EYE_LIGHT_NAME)
		T.ok(light and light.Shadows == false and light.Range <= 10, "cheap small light")
		RigStyles.Apply(model, "Glow")
		T.eq(countClass("PointLight"), RigStyles.MAX_EYE_LIGHTS, "Glow twice: no duplicate lights")

		-- Revert restores everything exactly
		RigStyles.Revert(model)
		local ok, which = same(original, snapshot())
		T.ok(ok, "revert restores originals (" .. tostring(which) .. ")")
		T.eq(countClass("Highlight") + countClass("PointLight"), 0, "revert removes outline/lights")
		T.eq(RigStyles.Current(model), nil, "no style attribute")
		for _, d in model:GetDescendants() do
			for name in d:GetAttributes() do
				T.ok(string.sub(name, 1, 3) ~= "SV_", "leftover attribute " .. name .. " on " .. d.Name)
			end
		end

		-- a skin recolour after styling wins over the stale original
		RigStyles.Apply(model, "Glow")
		local skinColor = Color3.fromRGB(20, 200, 90)
		accent.Color = skinColor
		RigStyles.Apply(model, "Classic")
		T.ok(close(accent.Color, skinColor, 0.005), "foreign colour change is kept")
		T.eq(accent.Material, Enum.Material.SmoothPlastic, "Classic: accent smooth")
		RigStyles.Revert(model)
		T.eq(accent.Material, Enum.Material.Plastic, "material restored")

		-- unknown style
		RigStyles.Apply(model, "Toon")
		T.eq(RigStyles.Apply(model, "Nope"), false, "unknown style refused")
		T.eq(countClass("Highlight"), 0, "unknown style leaves the model reverted")
	end,

	ambient_weather_builder = function(T, Loader)
		local Ambient = Loader.require(AMBIENT)
		local ids = Ambient.Ids()
		T.ok(#ids >= 7, "weather ids")
		for _, needed in { "Snow", "Embers", "Dust", "Fireflies", "VoidMotes", "Ash", "Rain" } do
			T.ok(Ambient.Has(needed), "weather " .. needed)
		end
		T.eq(Ambient.Build("Nope", 1), nil, "unknown weather")
		for _, id in ids do
			local folder = Ambient.Build(id, 1)
			T.ok(folder ~= nil and folder.ClassName == "Folder", id .. " builds")
			if folder then
				local emitters = 0
				for _, part in folder:GetChildren() do
					T.ok(part:IsA("BasePart"), id .. " volume part")
					T.ok(
						part.Anchored
							and not part.CanCollide
							and not part.CanQuery
							and not part.CanTouch
							and not part.CastShadow,
						id .. " inert volume"
					)
					T.eq(part.Transparency, 1, id .. " invisible volume")
					for _, emitter in part:GetChildren() do
						if emitter.ClassName == "ParticleEmitter" then
							emitters += 1
							T.ok(BUILTIN_TEXTURES[emitter.Texture], id .. " built-in texture " .. emitter.Texture)
							T.ok(emitter.Rate > 0 and emitter.Rate <= 400, id .. " rate " .. emitter.Rate)
							T.ok(emitter.LightInfluence >= 0 and emitter.LightInfluence <= 1, id .. " light influence")
							T.eq(emitter.LockedToPart, false, id .. " world-space particles")
						end
					end
				end
				T.ok(emitters >= 1 and emitters <= 4, id .. " emitter count " .. emitters)
			end
			local dense = Ambient.Build(id, 50)
			for _, part in dense:GetChildren() do
				for _, emitter in part:GetChildren() do
					T.ok(emitter.Rate <= 400, id .. " rate capped")
				end
			end
			local slow = Ambient.Build(id, 1, 0.6)
			local firstPart = slow:GetChildren()[1]
			T.near(firstPart:GetChildren()[1].TimeScale, 0.6, 1e-4, id .. " time scale")
		end
	end,

	strings_complete = function(T, Loader)
		local tbl = Loader.require("ReplicatedStorage.Shared.Strings.Graphics")
		local count = 0
		for key, entry in tbl do
			count += 1
			T.ok(string.sub(key, 1, 9) == "graphics.", key .. " prefix")
			T.ok(
				type(entry.en) == "string" and entry.en ~= "" and type(entry.ru) == "string" and entry.ru ~= "",
				key .. " en/ru"
			)
		end
		T.ok(count >= 20, "graphics strings")
		local Ambient = Loader.require(AMBIENT)
		for _, id in Ambient.Ids() do
			T.ok(tbl["graphics.weather." .. id] ~= nil, "weather name " .. id)
		end
		for _, tier in { "Auto", "Low", "Medium", "High", "Ultra" } do
			T.ok(tbl["graphics.quality." .. tier] ~= nil, "quality name " .. tier)
		end
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		T.ok(Strings.Has("graphics.title"), "merged into Strings")
	end,

	client_modules_require = function(T, Loader)
		Loader.isServer = false
		local okController, controller = pcall(Loader.require, CONTROLLER)
		T.ok(okController, "GraphicsController requires under Lune: " .. tostring(controller))
		if okController then
			for _, name in
				{
					"Init",
					"Start",
					"SetOverride",
					"PushOverride",
					"PopOverride",
					"PushTimed",
					"Quality",
					"ReducedMotion",
					"ParticleScale",
					"SetParticleDensity",
					"SetQualityOverride",
					"Current",
					"Refresh",
				}
			do
				T.ok(type(controller[name]) == "function", "GraphicsController." .. name)
			end
			T.ok(
				type(controller.Changed) == "table" and type(controller.Changed.Connect) == "function",
				"Changed signal"
			)
			T.eq(controller.Priority, 12, "controller priority")
			T.eq(controller.Quality(), "High", "default tier before Init")
		end
		Loader.isServer = true
	end,
	controller_runtime_with_mocks = function(T, Loader)
		local world = loadControllerWithMocks(Loader)
		local G = world.controller
		local lighting = world.lighting
		local presetEvents, qualityEvents = {}, {}
		G.PresetChanged:Connect(function(id, source)
			table.insert(presetEvents, id .. "@" .. source)
		end)
		G.Changed:Connect(function(q)
			table.insert(qualityEvents, q)
		end)
		G.Init()
		T.eq(G.Quality(), "High", "hint QualityLevel7 -> High")
		G.Start()
		T.eq(G.Current(), "GoldenHall", "map preset from RoundState")
		T.eq(presetEvents[1], "GoldenHall@Map", "PresetChanged fired")
		T.eq(world.runService.PreRender:Count(), 1, "a transition is running")
		T.eq(world.ambientCalls[#world.ambientCalls].id, "Dust", "weather follows the preset")
		world.frames(0.3)
		local mid = lighting.ClockTime
		T.ok(mid > 14.05 and mid < 17.3, "fading from the place lighting (14) toward 17.35, got " .. mid)
		world.frames(0.4)
		T.eq(world.runService.PreRender:Count(), 0, "PreRender disconnected after the fade")
		T.near(lighting.ClockTime, 17.35, 1e-3, "GoldenHall applied")
		T.near(lighting:FindFirstChild("SV_Bloom").Intensity, 0.6 * Loader.require(APPLY).DIM.Bloom, 1e-4, "bloom applied (globally dimmed)")
		T.ok(world.terrain:FindFirstChild("SV_Clouds") ~= nil, "clouds under Terrain")
		T.ok(world.workspace.GlobalWind.X > 0, "wind applied")

		world.setAttribute("FinalPhase", true)
		T.eq(G.Current(), "GoldenHallFinal", "final phase variant")
		world.frames(1.6)
		T.near(lighting.ClockTime, 17.85, 1e-3, "final applied")

		T.eq(G.PushOverride("EclipseUlt", "EclipseDark", G.PRIORITY.Gameplay, 0.5), true)
		T.eq(G.Current(), "EclipseDark", "override wins")
		T.eq(G.ActiveSource(), "Override:EclipseUlt")
		world.frames(0.3)
		T.ok(
			lighting.ClockTime > 17.85 and lighting.ClockTime < 24,
			"eclipse fades through sunset, got " .. lighting.ClockTime
		)
		world.frames(0.3)
		T.ok(lighting.ClockTime < 1e-3 or lighting.ClockTime > 24 - 1e-3, "eclipse at midnight")
		T.eq(G.PushOverride("Nope", "NotAPreset"), false, "unknown preset refused")
		T.eq(#world.warnings, 1, "refusal is reported once")
		table.clear(world.warnings)
		G.SetOverride("Monochrome")
		T.eq(G.Current(), "EclipseDark", "user choice does not beat a gameplay override")
		G.PopOverride("EclipseUlt", 0.2)
		T.eq(G.Current(), "MonochromeFinal", "back to the user's choice, final variant")
		world.frames(0.3)
		T.near(lighting:FindFirstChild("SV_ColorCorrection").Saturation, -0.8, 1e-3, "monochrome final applied")
		G.SetOverride("MapDefault")
		T.eq(G.Current(), "GoldenHallFinal", "MapDefault follows the map again")
		world.frames(1.6)

		G.SetQualityOverride("Low")
		T.eq(G.Quality(), "Low")
		T.eq(qualityEvents[#qualityEvents], "Low", "Changed fired")
		world.frames(0.7)
		T.eq(lighting:FindFirstChild("SV_DOF").Enabled, false, "Low: DOF off")
		T.eq(lighting:FindFirstChild("SV_SunRays").Enabled, false, "Low: SunRays off")
		T.eq(world.terrain:FindFirstChild("SV_Clouds").Enabled, false, "Low: clouds off")
		T.near(world.ambientCalls[#world.ambientCalls].density, 1.4 * 0.35, 1e-6, "Low particle scale")
		T.near(G.ParticleScale(), 0.35, 1e-6)

		G.SetQualityOverride("Auto")
		T.eq(G.Quality(), "High", "Auto returns to the hint")
		world.frames(0.7)
		for _ = 1, 160 do
			world.runService.Heartbeat:Fire(0.05) -- 20 FPS for 8 s
		end
		T.eq(G.Quality(), "Medium", "sustained low FPS steps down one tier")
		world.frames(0.7)
		T.eq(lighting:FindFirstChild("SV_DOF").Enabled, false, "Medium: DOF off")

		G.SetParticleDensity(2)
		T.near(G.ParticleScale(), 0.65 * 2, 1e-6, "density multiplier")
		world.guiService.ReducedMotionEnabled = true
		world.guiSignals.ReducedMotionEnabled:Fire()
		T.eq(G.ReducedMotion(), true)
		local last = world.ambientCalls[#world.ambientCalls]
		T.eq(last.timeScale, 0.6, "reduced motion slows weather")
		T.near(last.density, 1.4 * 0.65 * 2 * 0.7, 1e-6, "reduced motion thins weather")

		G.Refresh()
		T.eq(world.runService.PreRender:Count(), 0, "Refresh() applies instantly")
		T.eq(#world.warnings, 0, "no warnings: " .. table.concat(world.warnings, " | "))
	end,
	ambient_runtime_with_mocks = function(T, Loader)
		local roblox = Loader.roblox
		local cam = roblox.Instance.new("Camera")
		cam.CFrame = roblox.CFrame.new(0, 10, 0)
		local delayed = {}
		local preRender = makeSignal()
		local env = setmetatable({
			game = {
				GetService = function(_, n)
					if n == "RunService" then
						return { PreRender = preRender }
					elseif n == "Players" then
						return { LocalPlayer = nil }
					end
					error("mock: no service " .. n)
				end,
			},
			workspace = {
				CurrentCamera = cam,
				Raycast = function(_, origin)
					return { Position = roblox.Vector3.new(origin.X, 2, origin.Z) } -- floor at y = 2
				end,
			},
			RaycastParams = {
				new = function()
					return {}
				end,
			},
			task = {
				delay = function(_, fn)
					table.insert(delayed, fn)
				end,
				spawn = task.spawn,
			},
			Instance = roblox.Instance,
			Color3 = roblox.Color3,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
			Enum = roblox.Enum,
			NumberRange = roblox.NumberRange,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		}, { __index = _G })
		local source = fs.readFile("src/client/VFX/Ambient.luau")
		local Ambient = luau.load(source, { debugName = "Ambient(mock)", environment = env, injectGlobals = true })()

		Ambient.Set("Snow", 1)
		local folder = cam:FindFirstChild("SV_Ambient_Snow")
		T.ok(folder ~= nil, "weather parented to the camera")
		T.eq(preRender:Count(), 1, "following the camera")
		local id, density = Ambient.Current()
		T.eq(id, "Snow")
		T.eq(density, 1)
		local mist = folder:FindFirstChild("Volume_Mist")
		local flakes = folder:FindFirstChild("Volume_Flakes")
		T.near(mist.CFrame.Position.Y, 3, 1e-3, "mist sits on the floor under the camera")
		T.near(flakes.CFrame.Position.Y, 24, 1e-3, "flake volume centred above the camera")

		cam.CFrame = roblox.CFrame.new(500, 40, 0) * roblox.CFrame.Angles(0, math.rad(90), 0) -- teleport, look -X
		preRender:Fire(1 / 60)
		local p = flakes.CFrame.Position
		T.ok((p - roblox.Vector3.new(500, 54, 0)).Magnitude < 30, "volumes follow the camera")
		T.ok(p.X < 499, "volumes are pushed along the view direction")

		local emitter = flakes:FindFirstChildOfClass("ParticleEmitter")
		Ambient.Set("Snow", 0.5, { TimeScale = 0.6 })
		T.eq(cam:FindFirstChild("SV_Ambient_Snow"), folder, "same weather updated in place")
		T.near(emitter.Rate, 80, 1e-3, "rate scaled by density")
		T.near(emitter.TimeScale, 0.6, 1e-4, "time scale for reduced motion")

		Ambient.Set("Embers", 1)
		T.eq(emitter.Enabled, false, "old emitters stop emitting")
		T.ok(cam:FindFirstChild("SV_Ambient_Embers") ~= nil, "new weather built")
		T.eq(#delayed, 1, "old weather cleanup scheduled after its particles die")
		delayed[1]()
		T.eq(folder.Parent, nil, "old weather destroyed")

		Ambient.Stop()
		T.eq(preRender:Count(), 0, "no per-frame work when idle")
		T.eq(Ambient.Current(), nil)
		Ambient.Set("Bogus", 1)
		T.eq(Ambient.Current(), nil, "unknown weather = none")
		Ambient.Set("Dust", 0)
		T.eq(Ambient.Current(), nil, "zero density = none")
	end,
	rigstyles_on_real_blueprints = function(T, Loader)
		local okBuilder, RigBuilder = pcall(Loader.require, "ReplicatedStorage.Shared.Rigs.RigBuilder")
		if not okBuilder or type(RigBuilder) ~= "table" or type(RigBuilder.Blueprints) ~= "function" then
			print("  (graphics.spec: RigBuilder not available yet — real-blueprint style check skipped)")
			T.ok(true)
			return
		end
		local RigStyles = Loader.require(RIGSTYLES)
		for _, id in RigBuilder.Blueprints() do
			local okBuild, model = pcall(RigBuilder.Build, id)
			if okBuild then
				local before = {}
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						before[d] = { d.Material, d.Color, d.Reflectance }
					end
				end
				for _, style in RigStyles.List() do
					T.ok(RigStyles.Apply(model, style), id .. " " .. style)
					local outlines, lights = 0, 0
					for _, d in model:GetDescendants() do
						if d.ClassName == "Highlight" then
							outlines += 1
						elseif d.Name == RigStyles.EYE_LIGHT_NAME then
							lights += 1
						end
					end
					T.eq(outlines, if style == "Toon" then 1 else 0, id .. " " .. style .. " outlines")
					T.ok(lights <= RigStyles.MAX_EYE_LIGHTS, id .. " " .. style .. " eye lights")
				end
				RigStyles.Revert(model)
				local changed = 0
				for part, v in before do
					if
						part.Material ~= v[1]
						or not close(part.Color, v[2], 0.006)
						or not close(part.Reflectance, v[3], 1e-4)
					then
						changed += 1
					end
				end
				T.eq(changed, 0, id .. " revert restores every part")
			else
				print("  (graphics.spec: RigBuilder.Build(" .. id .. ") failed — skipped: " .. tostring(model) .. ")")
			end
		end
	end,
}
