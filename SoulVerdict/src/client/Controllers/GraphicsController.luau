--!strict
-- GraphicsController (client, SPEC §9 / §20, Priority 12): owns Lighting, its post effects, Terrain clouds,
-- Workspace.GlobalWind and the ambient weather on this client.
--
-- Which preset is on screen (Presets.Resolve):
--   1. the highest-priority pushed override (PushOverride; newest wins a tie) — e.g. Eclipse Sans' ultimate
--      pushes "EclipseDark" for humans, the Style Lab pushes whatever the owner picks;
--   2. else the player's own choice from Settings (SetOverride; nil / "MapDefault" = follow the map);
--   3. else the map preset: ReplicatedStorage.RoundState attribute "GraphicsPreset" (fallback: "MapId");
--   4. else "Lobby".
--   While RoundState.FinalPhase is true, 2–4 use the "<Id>Final" variant when it exists (or an explicit
--   RoundState "FinalPreset" attribute, if the server ever sets one).
-- Changes cross-fade with Apply.Lerp, driven by RunService.PreRender, only while a transition runs
-- (default 1.5 s, smoothstep). The result is then adjusted to the quality tier (Apply.ForQuality).
--
-- Quality: a hint from UserGameSettings.SavedQualityLevel (pcall; Automatic tells us nothing) plus a
-- measured frame time: sustained < 28 FPS steps down a tier, sustained > 55 FPS steps back up (never above
-- the player's own setting). Low = no DOF/SunRays/Clouds and a smaller bloom; Medium = no DOF.
-- Reduced Motion (GuiService.ReducedMotionEnabled): fewer, slower ambient particles; VFX should check it too.
--
-- API:
--   GraphicsController.Init() / Start()
--   GraphicsController.SetOverride(presetId: string?)               player setting (nil/"MapDefault" = map)
--   GraphicsController.GetOverride() -> string?
--   GraphicsController.PushOverride(key, presetId, priority?, transitionTime?) -> boolean
--   GraphicsController.PopOverride(key, transitionTime?)
--   GraphicsController.PushTimed(key, presetId, duration, priority?, inTime?, outTime?) -> boolean
--   GraphicsController.Current() -> string            active preset id;  ActiveSource() -> string
--   GraphicsController.CurrentPreset() -> GraphicsPreset   the target (normalized, quality-adjusted)
--   GraphicsController.Quality() -> "Low"|"Medium"|"High"|"Ultra"
--   GraphicsController.SetQualityOverride(tier: string?)  nil/"Auto" = automatic
--   GraphicsController.ParticleScale() -> number      quality × player density × reduced-motion factor
--   GraphicsController.SetParticleDensity(multiplier) 0..2 (Settings "ParticleDensity")
--   GraphicsController.ReducedMotion() -> boolean
--   GraphicsController.FrameTime() -> number          smoothed seconds per frame
--   GraphicsController.Refresh(transitionTime?)       re-apply the current target (e.g. after a map rebuild)
--   Signals: Changed(quality) — Quality() or ParticleScale() changed; PresetChanged(presetId, source);
--            ReducedMotionChanged(enabled)
--   GraphicsController.PRIORITY = { User = 0, StyleLab = 50, Gameplay = 100, Cinematic = 200 }
-- Saved settings are also read from StateController.Profile().Settings (keys GraphicsPreset,
-- ParticleDensity, GraphicsQuality) when StateController exists.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))
local Presets = require(Shared:WaitForChild("Graphics"):WaitForChild("Presets"))
local Apply = require(Shared:WaitForChild("Graphics"):WaitForChild("Apply"))

type GraphicsPreset = Types.GraphicsPreset
type Quality = "Low" | "Medium" | "High" | "Ultra"

type OverrideEntry = { Key: string, PresetId: string, Priority: number, Order: number }

type Connection = { Disconnect: (self: any) -> () }
type SignalLike = {
	Connect: (self: any, fn: (...any) -> ()) -> any,
	Fire: (self: any, ...any) -> (),
}

-------------------------------------------------------------------------------------------------- signal

-- Uses Shared/Util/Signal when present (SPEC §16), otherwise a tiny compatible fallback.
local function fallbackSignal(): SignalLike
	local handlers: { [any]: (...any) -> () } = {}
	local signal = {}
	function signal.Connect(_self: any, fn: (...any) -> ()): any
		local key = {}
		handlers[key] = fn
		local connection = { Connected = true }
		function connection.Disconnect(conn: any)
			conn.Connected = false
			handlers[key] = nil
		end
		return connection
	end
	function signal.Once(self: any, fn: (...any) -> ()): any
		local connection: any
		connection = self:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end
	function signal.Fire(_self: any, ...: any)
		for _, fn in table.clone(handlers) do
			task.spawn(fn, ...)
		end
	end
	return signal :: any
end

local function newSignal(): SignalLike
	local util = Shared:FindFirstChild("Util")
	local module = util and util:FindFirstChild("Signal")
	if module and module:IsA("ModuleScript") then
		local ok, Signal = pcall(require, module)
		if ok and type(Signal) == "table" and type((Signal :: any).new) == "function" then
			local created = (Signal :: any).new()
			if created ~= nil then
				return created
			end
		end
	end
	return fallbackSignal()
end

----------------------------------------------------------------------------------------------- module

local GraphicsController = {}

GraphicsController.Priority = 12
GraphicsController.DEFAULT_TRANSITION = 1.5
GraphicsController.PRIORITY = { User = 0, StyleLab = 50, Gameplay = 100, Cinematic = 200 }

GraphicsController.Changed = newSignal() -- (quality: Quality)
GraphicsController.PresetChanged = newSignal() -- (presetId: string, source: string)
GraphicsController.ReducedMotionChanged = newSignal() -- (enabled: boolean)

local TIERS: { Quality } = { "Low", "Medium", "High", "Ultra" }
local TIER_INDEX: { [string]: number } = { Low = 1, Medium = 2, High = 3, Ultra = 4 }
local PARTICLE_SCALE: { [string]: number } = { Low = 0.35, Medium = 0.65, High = 1, Ultra = 1.25 }

local LOW_FPS = 28
local HIGH_FPS = 55
local DOWNGRADE_AFTER = 4 -- seconds of sustained low FPS
local UPGRADE_AFTER = 25 -- seconds of sustained high FPS
local AUTO_COOLDOWN = 8
local QUALITY_TRANSITION = 0.6
local FIRST_TRANSITION = 0.6
local REDUCED_MOTION_PARTICLES = 0.7
local REDUCED_MOTION_TIMESCALE = 0.6

-- state ---------------------------------------------------------------------------------------------
local started = false
local Ambient: any = nil

local roundState: Instance? = nil
local mapPreset: string? = nil
local finalPreset: string? = nil
local mapId: string? = nil
local finalPhase = false

local userOverride: string? = nil
local overrides: { [string]: OverrideEntry } = {}
local overrideOrder = 0
local timedTokens: { [string]: number } = {}

local activeId: string = Presets.Default
local activeSource = "Fallback"
local targetPreset: GraphicsPreset? = nil -- normalized + quality-adjusted
local displayed: GraphicsPreset? = nil -- what is on screen (normalized; Lerp writes into it)
local fromPreset: GraphicsPreset? = nil
local transitionElapsed = 0
local transitionTime = 0
local transitionConnection: RBXScriptConnection? = nil
local warnedProblems = false

local quality: Quality = "High"
local qualityOverride: Quality? = nil
local maxAutoTier: Quality = "High"
local particleDensity: number = (Config.Defaults :: any).ParticleDensity or 1
local reducedMotion = false

local frameTime = 1 / 60
local evalTimer = 0
local lowTime = 0
local highTime = 0
local sinceAutoChange = math.huge
local windowFocused = true

------------------------------------------------------------------------------------------------ helpers

local function isTier(value: any): boolean
	return type(value) == "string" and TIER_INDEX[value] ~= nil
end

local function readHintTier(): Quality?
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel
	end)
	if not ok or typeof(level) ~= "EnumItem" then
		return nil
	end
	local value = (level :: EnumItem).Value
	if value <= 0 then
		return nil -- Automatic: the real level is not readable
	elseif value <= 3 then
		return "Low"
	elseif value <= 6 then
		return "Medium"
	elseif value <= 8 then
		return "High"
	end
	return "Ultra"
end

local function readReducedMotion(): boolean
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

local function isTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function applyNow(preset: GraphicsPreset, exclusive: boolean)
	local problems = Apply.ToLighting(Lighting, preset, {
		Terrain = workspace.Terrain,
		Workspace = workspace,
		Exclusive = exclusive,
	})
	if #problems > 0 and not warnedProblems then
		warnedProblems = true
		warn("[GraphicsController] preset problems: " .. table.concat(problems, "; "))
	end
end

local function updateAmbient()
	if Ambient == nil then
		return
	end
	local preset = targetPreset
	local weather = if preset then preset.Ambient else nil
	local ok, err = pcall(function()
		if weather == nil or weather.Particles == nil then
			Ambient.Set(nil)
		else
			Ambient.Set(weather.Particles, (weather.Density or 1) * GraphicsController.ParticleScale(), {
				TimeScale = if reducedMotion then REDUCED_MOTION_TIMESCALE else 1,
			})
		end
	end)
	if not ok then
		warn("[GraphicsController] ambient weather failed: " .. tostring(err))
	end
end

---------------------------------------------------------------------------------------------- transitions

local function stopTransition()
	if transitionConnection then
		transitionConnection:Disconnect()
		transitionConnection = nil
	end
	fromPreset = nil
end

local function stepTransition(dt: number)
	local target = targetPreset
	local from = fromPreset
	local current = displayed
	if target == nil or from == nil or current == nil then
		stopTransition()
		return
	end
	transitionElapsed += dt
	local t = if transitionTime > 0 then transitionElapsed / transitionTime else 1
	if t >= 1 then
		displayed = Apply.Copy(target)
		applyNow(displayed :: GraphicsPreset, true)
		stopTransition()
		return
	end
	local eased = t * t * (3 - 2 * t)
	Apply.Lerp(from, target, eased, current)
	applyNow(current, false)
end

local function startTransition(duration: number)
	local target = targetPreset
	if target == nil then
		return
	end
	if displayed == nil or duration <= 0 then
		stopTransition()
		displayed = Apply.Copy(target)
		applyNow(displayed :: GraphicsPreset, true)
		return
	end
	fromPreset = Apply.Copy(displayed :: GraphicsPreset)
	transitionElapsed = 0
	transitionTime = duration
	applyNow(displayed :: GraphicsPreset, true) -- stash foreign Sky/Atmosphere before the fade starts
	if transitionConnection == nil then
		transitionConnection = RunService.PreRender:Connect(stepTransition)
	end
end

local function resolveState(): any
	local list: { OverrideEntry } = {}
	for _, entry in overrides do
		table.insert(list, entry)
	end
	return {
		MapPreset = mapPreset,
		FinalPreset = finalPreset,
		MapId = mapId,
		FinalPhase = finalPhase,
		UserOverride = userOverride,
		Overrides = list,
	}
end

-- Re-resolves the active preset; transitions when it changed (or always when `force`).
local function retarget(force: boolean, duration: number?)
	if not started then
		return
	end
	local id, source = Presets.Resolve(resolveState())
	local changed = id ~= activeId or targetPreset == nil
	activeSource = source
	if not changed and not force then
		return
	end
	local preset = Presets.Get(id) or Presets.Get(Presets.Fallback)
	if preset == nil then
		return
	end
	activeId = id
	targetPreset = Apply.ForQuality(preset, quality)
	startTransition(duration or GraphicsController.DEFAULT_TRANSITION)
	updateAmbient()
	if changed then
		GraphicsController.PresetChanged:Fire(id, source)
	end
end

------------------------------------------------------------------------------------------------ quality

local function setQuality(tier: Quality)
	if tier == quality then
		return
	end
	quality = tier
	retarget(true, QUALITY_TRANSITION)
	GraphicsController.Changed:Fire(quality)
end

local function onHeartbeat(dt: number)
	if not windowFocused then
		return
	end
	local d = math.min(dt, 0.25)
	frameTime += (d - frameTime) * (1 - math.exp(-d / 1.5))
	evalTimer += dt
	sinceAutoChange += dt
	if evalTimer < 1 then
		return
	end
	local elapsed = evalTimer
	evalTimer = 0
	if qualityOverride ~= nil then
		return
	end
	local fps = 1 / math.max(frameTime, 1e-3)
	if fps < LOW_FPS then
		lowTime += elapsed
		highTime = 0
	elseif fps > HIGH_FPS then
		highTime += elapsed
		lowTime = 0
	else
		lowTime = 0
		highTime = 0
	end
	local index = TIER_INDEX[quality]
	if lowTime >= DOWNGRADE_AFTER and index > 1 and sinceAutoChange > AUTO_COOLDOWN then
		lowTime = 0
		sinceAutoChange = 0
		setQuality(TIERS[index - 1])
	elseif highTime >= UPGRADE_AFTER and index < TIER_INDEX[maxAutoTier] and sinceAutoChange > AUTO_COOLDOWN then
		highTime = 0
		sinceAutoChange = 0
		setQuality(TIERS[index + 1])
	end
end

local function refreshHint()
	local hint = readHintTier()
	maxAutoTier = hint or "High"
	if qualityOverride == nil then
		if hint then
			setQuality(hint)
		elseif TIER_INDEX[quality] > TIER_INDEX[maxAutoTier] then
			setQuality(maxAutoTier)
		end
	end
end

------------------------------------------------------------------------------------------- round state

local function stringAttribute(instance: Instance, name: string): string?
	local value = instance:GetAttribute(name)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function readRoundState()
	local rs = roundState
	if rs == nil then
		return
	end
	mapPreset = stringAttribute(rs, "GraphicsPreset")
	finalPreset = stringAttribute(rs, "FinalPreset")
	mapId = stringAttribute(rs, "MapId")
	finalPhase = rs:GetAttribute("FinalPhase") == true
end

local function bindRoundState(rs: Instance)
	if roundState == rs then
		return
	end
	roundState = rs
	for _, name in { "GraphicsPreset", "FinalPreset", "MapId", "FinalPhase" } do
		rs:GetAttributeChangedSignal(name):Connect(function()
			readRoundState()
			retarget(false)
		end)
	end
	readRoundState()
	retarget(false)
end

local function watchRoundState()
	local existing = ReplicatedStorage:FindFirstChild("RoundState")
	if existing then
		bindRoundState(existing)
		return
	end
	local connection: RBXScriptConnection? = nil
	connection = ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "RoundState" then
			if connection then
				connection:Disconnect()
			end
			bindRoundState(child)
		end
	end)
end

--------------------------------------------------------------------------------------- saved settings

local lastSettings: { [string]: any } = {}

local function applySettings(profile: any)
	if type(profile) ~= "table" or type(profile.Settings) ~= "table" then
		return
	end
	local settings = profile.Settings
	if settings.GraphicsPreset ~= lastSettings.GraphicsPreset then
		lastSettings.GraphicsPreset = settings.GraphicsPreset
		if type(settings.GraphicsPreset) == "string" then
			GraphicsController.SetOverride(settings.GraphicsPreset)
		end
	end
	if settings.ParticleDensity ~= lastSettings.ParticleDensity then
		lastSettings.ParticleDensity = settings.ParticleDensity
		if type(settings.ParticleDensity) == "number" then
			GraphicsController.SetParticleDensity(settings.ParticleDensity)
		end
	end
	if settings.GraphicsQuality ~= lastSettings.GraphicsQuality then
		lastSettings.GraphicsQuality = settings.GraphicsQuality
		if type(settings.GraphicsQuality) == "string" then
			GraphicsController.SetQualityOverride(settings.GraphicsQuality)
		end
	end
end

local function hookSavedSettings()
	local module = (script.Parent :: Instance):FindFirstChild("StateController")
	if module == nil or not module:IsA("ModuleScript") then
		return
	end
	local ok, State = pcall(require, module)
	if not ok or type(State) ~= "table" then
		return
	end
	local state = State :: any
	if type(state.Profile) == "function" then
		local okProfile, profile = pcall(state.Profile)
		if okProfile then
			applySettings(profile)
		end
	end
	if type(state.ProfileChanged) == "table" then
		pcall(function()
			state.ProfileChanged:Connect(applySettings)
		end)
	end
end

------------------------------------------------------------------------------------------------- public

function GraphicsController.Init()
	reducedMotion = readReducedMotion()
	local hint = readHintTier()
	maxAutoTier = hint or "High"
	quality = hint or (if isTouchOnly() then "Medium" else "High")
	local clientRoot = (script.Parent :: Instance).Parent :: Instance
	local vfx = clientRoot:FindFirstChild("VFX")
	local ambientModule = if vfx then vfx:FindFirstChild("Ambient") else nil
	if ambientModule and ambientModule:IsA("ModuleScript") then
		local ok, module = pcall(require, ambientModule)
		if ok then
			Ambient = module
		else
			warn("[GraphicsController] VFX/Ambient failed to load: " .. tostring(module))
		end
	end
end

function GraphicsController.Start()
	if started then
		return
	end
	started = true

	-- start from what the place shows so the first change is a fade, not a pop
	local okSnapshot, snapshot = pcall(Apply.Snapshot, Lighting, { Terrain = workspace.Terrain, Workspace = workspace })
	if okSnapshot then
		displayed = Apply.Copy(snapshot)
	end
	retarget(true, FIRST_TRANSITION)

	watchRoundState()
	task.spawn(hookSavedSettings)

	RunService.Heartbeat:Connect(onHeartbeat)
	UserInputService.WindowFocused:Connect(function()
		windowFocused = true
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		windowFocused = false
	end)
	pcall(function()
		local userGameSettings = UserSettings():GetService("UserGameSettings")
		userGameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(refreshHint)
	end)
	pcall(function()
		GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
			local value = readReducedMotion()
			if value ~= reducedMotion then
				reducedMotion = value
				updateAmbient()
				GraphicsController.ReducedMotionChanged:Fire(value)
				GraphicsController.Changed:Fire(quality)
			end
		end)
	end)
end

function GraphicsController.SetOverride(presetId: string?)
	local id = presetId
	if id == Presets.MAP_DEFAULT or id == "" then
		id = nil
	end
	if id ~= nil and not Presets.Has(id) then
		warn("[GraphicsController] unknown preset " .. tostring(id))
		id = nil
	end
	userOverride = id
	retarget(false)
end

function GraphicsController.GetOverride(): string?
	return userOverride
end

function GraphicsController.PushOverride(
	key: string,
	presetId: string,
	priority: number?,
	transitionTime: number?
): boolean
	if not Presets.Has(presetId) then
		warn("[GraphicsController] PushOverride: unknown preset " .. tostring(presetId))
		return false
	end
	overrideOrder += 1
	overrides[key] = {
		Key = key,
		PresetId = presetId,
		Priority = priority or GraphicsController.PRIORITY.Gameplay,
		Order = overrideOrder,
	}
	timedTokens[key] = (timedTokens[key] or 0) + 1 -- cancels a pending PushTimed pop for this key
	retarget(false, transitionTime)
	return true
end

function GraphicsController.PopOverride(key: string, transitionTime: number?)
	if overrides[key] == nil then
		return
	end
	overrides[key] = nil
	timedTokens[key] = (timedTokens[key] or 0) + 1
	retarget(false, transitionTime)
end

function GraphicsController.PushTimed(
	key: string,
	presetId: string,
	duration: number,
	priority: number?,
	inTime: number?,
	outTime: number?
): boolean
	if not GraphicsController.PushOverride(key, presetId, priority, inTime) then
		return false
	end
	local token = timedTokens[key]
	task.delay(duration, function()
		if timedTokens[key] == token then
			GraphicsController.PopOverride(key, outTime)
		end
	end)
	return true
end

function GraphicsController.Current(): string
	return activeId
end

function GraphicsController.ActiveSource(): string
	return activeSource
end

function GraphicsController.CurrentPreset(): GraphicsPreset?
	return targetPreset
end

function GraphicsController.Quality(): Quality
	return quality
end

function GraphicsController.SetQualityOverride(tier: string?)
	if tier == nil or tier == "Auto" or not isTier(tier) then
		qualityOverride = nil
		refreshHint()
		return
	end
	qualityOverride = tier :: Quality
	setQuality(tier :: Quality)
end

function GraphicsController.ParticleScale(): number
	local scale = PARTICLE_SCALE[quality] * particleDensity
	if reducedMotion then
		scale *= REDUCED_MOTION_PARTICLES
	end
	return scale
end

function GraphicsController.SetParticleDensity(multiplier: number)
	local value = math.clamp(if multiplier == multiplier then multiplier else 1, 0, 2)
	if math.abs(value - particleDensity) < 1e-3 then
		return
	end
	particleDensity = value
	updateAmbient()
	GraphicsController.Changed:Fire(quality)
end

function GraphicsController.ReducedMotion(): boolean
	return reducedMotion
end

function GraphicsController.FrameTime(): number
	return frameTime
end

function GraphicsController.Refresh(transitionTime: number?)
	retarget(true, transitionTime or 0)
end

return GraphicsController
