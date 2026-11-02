--!strict
-- UIController (client, SPEC §16 / §20, Priority 90): owns the whole menu layer.
--   * UIRoot.Init(PlayerGui) with the shared UI deps table (SPEC §20 + RigStyle, Spectate), UI sounds through
--     SoundController; mounts the HUD once (UI/Hud.Mount(UIRoot.Layer("Hud"), deps) when that module exists);
--   * shows the Title on join (camera "Menu" while in the lobby), keeps a named menu stack in sync with UIRoot,
--     pushes InputController context "Menu" while any menu is open (and "Photo" in photo mode);
--   * hotkeys: Menu toggles (lobby: Title, in a round: Settings), Back pops, Prev/Next switch tabs (screen OnAction);
--   * round flow: RoundEvent "RoundEnd" -> Results after the kill-cam, "Rewards" -> Results.SetRewards (kept in the
--     entry deps so theme/language rebuilds keep them); Intro for a local participant closes every menu;
--   * settings: cached + applied live (GraphicsController, ThemeService, Strings + rebuild, SoundController
--     volumes) and persisted through StateController.SetSetting (debounced for sliders; Camera/Sound/RigStyle
--     controllers react to StateController.SettingChanged); Style Lab previews use ApplySetting (not saved);
--   * toasts: Notify(key, args, kind) / Toast(text, kind, icon); server Notify events are toasted here only while
--     a menu hides the HUD (the HUD's Notifications piece handles them otherwise);
--   * menu exclusivity: every stack change reports the top menu to the HUD (HudHandle.SetMenu -> Hud.Visible: the
--     lobby/round HUD and the touch controls hide while a menu owns the screen) and hides Roblox's touch thumbstick /
--     jump button (GuiService.TouchControlsEnabled) while any menu or photo mode is up;
--   * Admin (owner test panel): "Admin" screen + Title button, only for the Player attribute "Admin" = true.
--   * PLAY / PRACTICE go through the loading screen (UI/Overlays/Loading: fade to black, spinning pixel Sans head,
--     "LOADING"); the menus close (and the practice request is sent) once the screen is black. If that module is
--     missing or fails, both fall back to the instant switch.
--
-- API
--   UIController.Open(name, opts?) -> ScreenHandle?   names: Title, Play (= Loadout), Loadout, Shop, Quests, Profile,
--       Settings, StyleLab, Admin, Results, Gallery. opts are merged into that screen's deps ({Replace = true} replaces
--       the top screen instead of pushing). StyleLab / Admin need the Player attribute of the same name.
--   UIController.Practice(side?)     loading screen, close the menus and ask for a practice round vs bots (Request
--                                    StartPractice); the screen stays black until the round leaves "Waiting", the
--                                    character is teleported or the server refuses (7 s cap)
--   UIController.Close(name?)        nil: close every menu (back to the game); name: remove that screen
--   UIController.Toggle(name)        UIController.Back() -> boolean
--   UIController.Play()              loading screen, then close the menus (enter the lobby)
--   UIController.IsOpen(name?) -> boolean       UIController.Top() -> string?
--   UIController.SetVisible(visible)            hide/show every UI layer (photo mode)
--   UIController.PhotoMode(on)                  Camera "Photo" + hidden UI; Back / tap returns
--   UIController.Notify(key, args?, kind?)      UIController.Toast(text, kind?, icon?)
--   UIController.Setting(key) -> any            UIController.Settings() -> {[key]: any}
--   UIController.SetSetting(key, value)         apply live + persist      UIController.ApplySetting(key, value) (live only)
--   UIController.ResetSettings()
--   Signals: MenuChanged(topName?), SettingChanged(key, value), LanguageChanged(lang), VisibleChanged(visible)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal")) :: any

local UIController = {}
UIController.Priority = 90

UIController.MenuChanged = Signal.new()
UIController.SettingChanged = Signal.new()
UIController.LanguageChanged = Signal.new()
UIController.VisibleChanged = Signal.new()

-- modules (required in Init: never at top level, SPEC §16)
local UIFolder: Instance = nil :: any
local UIRoot: any = nil
local ThemeService: any = nil
local ScreensFolder: Instance? = nil

-- controllers (lazy, optional)
local Input: any = nil
local State: any = nil
local Camera: any = nil
local Sound: any = nil
local Combat: any = nil
local Graphics: any = nil
local RigStyle: any = nil
local Spectate: any = nil

-- loading screen module (UI/Overlays/Loading), required on first use; false = unavailable (instant switch)
local LoadingOverlay: any = nil
-- server answers to StartPractice that mean "no practice round is coming" (the loading screen ends early)
local PRACTICE_REFUSED: { [string]: boolean } = {
	["round.practice.busy"] = true,
	["round.practice.disabled"] = true,
	["round.practice.unavailable"] = true,
	["prog.err.rateLimited"] = true,
	["prog.err.badRequest"] = true,
}
local TELEPORT_STEP = 25 -- studs the local character moves between two loading-screen checks = it was teleported

local SCREEN_MODULES: { [string]: string } = {
	Title = "Title",
	Play = "Loadout",
	Loadout = "Loadout",
	Shop = "Shop",
	Quests = "Quests",
	Profile = "Profile",
	Settings = "Settings",
	StyleLab = "StyleLab",
	Admin = "Admin",
	Results = "Results",
}
-- screens gated by a Player attribute of the same name (set by the server)
local GATED: { [string]: boolean } = { StyleLab = true, Admin = true }
-- fallback when the Hud module is missing: screens with a near-opaque backdrop (they hide the HUD's own toasts)
local FULLSCREEN: { [string]: boolean } = {
	Title = true,
	Loadout = true,
	Play = true,
	Shop = true,
	Quests = true,
	Profile = true,
	Settings = true,
	Results = true,
	Gallery = true,
	Admin = true,
}
local SLIDER_KEYS: { [string]: boolean } = {
	ParticleDensity = true,
	MusicVolume = true,
	SfxVolume = true,
	CameraShake = true,
	FieldOfView = true,
	Sensitivity = true,
}

type Entry = { name: string, deps: { [string]: any } }

local deps: { [string]: any } = {}
local stack: { Entry } = {}
local started = false
local visible = true
local photo = false
local menuContext = false
local menuCamera = false
local hudHandle: any = nil
local HudModule: any = nil
local touchHidden = false
local settingsCache: { [string]: any } = {}
local persistVersion: { [string]: number } = {}
local pendingResult: any = nil
local pendingRewards: any = nil
local resultsDeps: { [string]: any }? = nil

------------------------------------------------------------------------------------------------ helpers

local function controllerModule(name: string): any
	local folder = script.Parent
	local module = folder and folder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function call(target: any, method: string, ...: any): (boolean, any)
	if type(target) ~= "table" or type(target[method]) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(target[method], ...)
	if not ok then
		warn(("[UIController] %s failed: %s"):format(method, tostring(result)))
	end
	return ok, result
end

local function screenModule(name: string): any
	if name == "Gallery" then
		local g = UIFolder:FindFirstChild("Gallery")
		return if g then require(g) :: any else nil
	end
	local file = SCREEN_MODULES[name]
	local module = file and ScreensFolder and ScreensFolder:FindFirstChild(file)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
		warn("[UIController] screen " .. name .. " failed to load: " .. tostring(result))
	end
	return nil
end

local function phase(): string
	local ok, p = call(State, "Phase")
	if ok and type(p) == "string" then
		return p
	end
	local rs = ReplicatedStorage:FindFirstChild("RoundState")
	return if rs then tostring(rs:GetAttribute("Phase") or "Waiting") else "Waiting"
end

local function role(): string
	local ok, r = call(State, "Role")
	if ok and type(r) == "string" then
		return r
	end
	local player = Players.LocalPlayer
	return if player then tostring(player:GetAttribute("Role") or "Lobby") else "Lobby"
end

local function inLobby(): boolean
	local p = phase()
	local r = role()
	return r == "Lobby" or r == "" or p == "Waiting" or p == "Intermission" or p == "Ending"
end

local function topEntry(): Entry?
	return stack[#stack]
end

local function hasScreen(name: string): boolean
	for _, e in stack do
		if e.name == name then
			return true
		end
	end
	return false
end

-- does the open menu `name` hide the HUD? (Hud.MenuHidesHud is the source of truth)
local function menuHidesHud(name: string?): boolean
	if name == nil then
		return false
	end
	if HudModule and type(HudModule.MenuHidesHud) == "function" then
		local ok, hides = pcall(HudModule.MenuHidesHud, name)
		if ok then
			return hides == true
		end
	end
	return FULLSCREEN[name] == true
end

-- Roblox's thumbstick + jump button would sit on top of the menu buttons (and move the body behind the menu)
local function syncTouch()
	local hide = #stack > 0 or photo
	if hide == touchHidden then
		return
	end
	touchHidden = hide
	pcall(function()
		(game:GetService("GuiService") :: any).TouchControlsEnabled = not hide
	end)
end

-- keep InputController context, camera mode, the HUD and listeners in sync with the stack
local function sync()
	local open = #stack > 0
	if open ~= menuContext then
		menuContext = open
		if open then
			call(Input, "PushContext", "Menu")
		else
			call(Input, "PopContext", "Menu")
		end
	end
	if type(UIController._SyncMenuMusic) == "function" then
		pcall(UIController._SyncMenuMusic) -- the title's own track (defined further down)
	end
	local wantMenuCamera = hasScreen("Title") and inLobby()
	if wantMenuCamera ~= menuCamera then
		menuCamera = wantMenuCamera
		if wantMenuCamera then
			call(Camera, "SetMode", "Menu")
		elseif phase() ~= "Intro" then
			local okMode, mode = call(Camera, "Mode")
			if not okMode or mode == "Menu" then
				call(Camera, "SetMode", "Follow")
			end
		end
	end
	local top = topEntry()
	local topName = if top then top.name else nil
	if hudHandle and type(hudHandle.SetMenu) == "function" then
		local ok, err = pcall(hudHandle.SetMenu, topName)
		if not ok then
			warn("[UIController] Hud.SetMenu failed: " .. tostring(err))
		end
	end
	syncTouch()
	UIController.MenuChanged:Fire(topName)
end

------------------------------------------------------------------------------------------------ settings

local function specs(): { [string]: any }
	local ok, result = pcall(function()
		local schema = require(Shared:WaitForChild("Progression"):WaitForChild("ProfileSchema")) :: any
		return schema.Settings()
	end)
	return if ok and type(result) == "table" then result else {}
end

local function defaultOf(key: string): any
	local s = specs()[key]
	if s and s.Default ~= nil then
		return s.Default
	end
	return (Config.Defaults :: any)[key]
end

function UIController.Setting(key: string): any
	local v = settingsCache[key]
	if v ~= nil then
		return v
	end
	local ok, sv = call(State, "Setting", key)
	if ok and sv ~= nil then
		return sv
	end
	return defaultOf(key)
end

function UIController.Settings(): { [string]: any }
	local out: { [string]: any } = {}
	for key in specs() do
		out[key] = UIController.Setting(key)
	end
	for key in Config.Defaults :: any do
		out[key] = UIController.Setting(key)
	end
	return out
end

local function resolveLanguage(value: any): string
	if value == "en" or value == "ru" then
		return value
	end
	local player = Players.LocalPlayer
	local locale = if player then string.lower(player.LocaleId or "") else ""
	return if string.sub(locale, 1, 2) == "ru" then "ru" else "en"
end

-- immediate, local effect of a setting (no persistence)
local function applyDirect(key: string, value: any)
	if key == "GraphicsPreset" then
		call(Graphics, "SetOverride", if value == "MapDefault" or value == nil then nil else value)
	elseif key == "GraphicsQuality" then
		call(Graphics, "SetQualityOverride", if value == "Auto" or value == nil then nil else value)
	elseif key == "ParticleDensity" then
		call(Graphics, "SetParticleDensity", tonumber(value) or 1)
	elseif key == "MenuTheme" then
		if ThemeService and type(value) == "string" and ThemeService.Current().Id ~= value then
			-- rebuilds every screen (maybe the one calling us): defer
			task.defer(function()
				ThemeService.Set(value)
			end)
		end
	elseif key == "HudStyle" then
		if ThemeService and type(value) == "string" and ThemeService.HudStyle().Id ~= value then
			ThemeService.SetHudStyle(value)
		end
	elseif key == "Language" then
		local lang = resolveLanguage(value)
		if Strings.Language() ~= lang then
			Strings.SetLanguage(lang)
			task.defer(function()
				if UIRoot and UIRoot.IsInitialized() then
					UIRoot.Rebuild()
				end
				if hudHandle and type(hudHandle.Rebuild) == "function" then
					pcall(hudHandle.Rebuild)
				end
				UIController.LanguageChanged:Fire(lang)
			end)
		end
	elseif key == "MusicVolume" or key == "SfxVolume" then
		local music = tonumber(UIController.Setting("MusicVolume")) or 0.6
		local sfx = tonumber(UIController.Setting("SfxVolume")) or 0.8
		call(Sound, "SetVolumes", music, sfx)
	end
end

local function persist(key: string, value: any)
	if State and type(State.SetSetting) == "function" then
		call(State, "SetSetting", key, value)
	else
		pcall(function()
			local Net = require(Shared:WaitForChild("Net")) :: any
			Net.Client.Fire("Request", "SetSetting", { key = key, value = value })
		end)
	end
end

function UIController.SetSetting(key: string, value: any)
	settingsCache[key] = value
	applyDirect(key, value)
	UIController.SettingChanged:Fire(key, value)
	local version = (persistVersion[key] or 0) + 1
	persistVersion[key] = version
	if SLIDER_KEYS[key] then
		-- sliders fire continuously while dragging: persist once the value settles
		task.delay(0.45, function()
			if persistVersion[key] == version then
				persist(key, value)
			end
		end)
	else
		persist(key, value)
	end
end

-- Style Lab preview: live only, never saved
function UIController.ApplySetting(key: string, value: any)
	if key == "RigStyle" then
		if not call(RigStyle, "SetOverride", value) then
			settingsCache[key] = value
		end
	else
		applyDirect(key, value)
	end
	UIController.SettingChanged:Fire(key, value)
end

function UIController.ResetSettings()
	local i = 0
	for key, spec in specs() do
		local current = UIController.Setting(key)
		if spec.Default ~= nil and current ~= spec.Default then
			i += 1
			local default = spec.Default
			-- stagger the requests (RequestService is rate limited)
			task.delay(0.12 * i, function()
				UIController.SetSetting(key, default)
			end)
		end
	end
	task.delay(0.12 * i + 0.3, function()
		UIController.Notify("set.resetDone", nil, "Success")
		if UIRoot and UIRoot.IsInitialized() and hasScreen("Settings") then
			UIRoot.Rebuild()
		end
	end)
end

-- apply everything once (startup / first profile) and again when the server's values differ
local function applyAll(fromProfile: boolean)
	for _, key in
		{ "Language", "MenuTheme", "HudStyle", "GraphicsPreset", "GraphicsQuality", "ParticleDensity", "MusicVolume" }
	do
		local value = UIController.Setting(key)
		if fromProfile then
			local ok, sv = call(State, "Setting", key)
			if ok and sv ~= nil and settingsCache[key] == nil then
				value = sv
			end
		end
		if value ~= nil then
			applyDirect(key, value)
		end
	end
end

------------------------------------------------------------------------------------------------ screens

local function buildDeps(extra: { [string]: any }?): { [string]: any }
	local d: { [string]: any } = {}
	if extra then
		for k, v in extra do
			d[k] = v
		end
	end
	return d
end

function UIController.Open(name: string, opts: { [string]: any }?): any
	if not started or UIRoot == nil then
		return nil
	end
	local module = screenModule(name)
	if module == nil then
		return nil
	end
	local o = opts or {}
	if GATED[name] then
		local player = Players.LocalPlayer
		if player and player:GetAttribute(name) ~= true then
			return nil
		end
	end
	if photo then
		UIController.PhotoMode(false)
	end
	local top = topEntry()
	if o.Replace and top then
		local d = buildDeps(o)
		top.name = name
		top.deps = d
		local handle = UIRoot.Replace(module, d)
		sync()
		return handle
	end
	if top and top.name == name then
		return UIRoot.Top()
	end
	-- already deeper in the stack: pop back to it
	if hasScreen(name) then
		while #stack > 0 and stack[#stack].name ~= name do
			table.remove(stack)
			UIRoot.Pop()
		end
		sync()
		return UIRoot.Top()
	end
	if name == "Title" then
		-- the title is the root of the menu stack
		UIRoot.Clear()
		table.clear(stack)
	end
	local d = buildDeps(o)
	if name == "Results" then
		resultsDeps = d
	end
	table.insert(stack, { name = name, deps = d })
	local handle = UIRoot.Push(module, d)
	if handle == nil then
		table.remove(stack)
	end
	sync()
	return handle
end

function UIController.Close(name: string?)
	if UIRoot == nil then
		return
	end
	if name == nil then
		UIRoot.Clear()
		table.clear(stack)
		resultsDeps = nil
	else
		if not hasScreen(name) then
			return
		end
		while #stack > 0 do
			local e = table.remove(stack) :: Entry
			UIRoot.Pop()
			if e.name == name then
				break
			end
		end
		if name == "Results" then
			resultsDeps = nil
		end
	end
	sync()
end

function UIController.Toggle(name: string)
	local top = topEntry()
	if top and top.name == name then
		UIController.Close(name)
	else
		UIController.Open(name)
	end
end

function UIController.Back(): boolean
	if photo then
		UIController.PhotoMode(false)
		return true
	end
	local top = topEntry()
	if top == nil then
		return false
	end
	local handle = UIRoot.Top()
	if handle and type(handle.OnAction) == "function" then
		local ok, consumed = pcall(handle.OnAction, "Back")
		if ok and consumed then
			return true
		end
	end
	table.remove(stack)
	UIRoot.Pop()
	if top.name == "Results" then
		resultsDeps = nil
	end
	sync()
	return true
end

------------------------------------------------------------------------------------------------ loading screen

local function loadingOverlay(): any
	if LoadingOverlay == nil then
		LoadingOverlay = false
		local folder = UIFolder and UIFolder:FindFirstChild("Overlays")
		local module = folder and folder:FindFirstChild("Loading")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" and type((result :: any).Show) == "function" then
				LoadingOverlay = result
			else
				warn("[UIController] loading screen failed to load: " .. tostring(result))
			end
		end
	end
	return if LoadingOverlay then LoadingOverlay else nil
end

-- Shows the loading screen (opts.OnCovered runs once the screen is black). false = not shown: the caller does the
-- old instant switch itself. A second call while it runs joins the running screen (true, its opts are ignored).
local function showLoading(opts: { [string]: any }): boolean
	local overlay = if started then loadingOverlay() else nil
	if overlay == nil then
		return false
	end
	opts.Sound = Sound
	opts.Theme = if ThemeService then ThemeService.Current() else nil
	local ok, handle = pcall(overlay.Show, opts)
	if not ok then
		warn("[UIController] loading screen failed: " .. tostring(handle))
		return false
	end
	return handle ~= nil
end

local function characterRoot(): (Model?, Vector3?)
	local player = Players.LocalPlayer
	local character = player and player.Character
	if character == nil then
		return nil, nil
	end
	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	return character, if root and root:IsA("BasePart") then root.Position else nil
end

-- Music around the loading screen (owner's wish): the title plays its own "Menu" track (the Shop its "Shop" track);
-- on PLAY / PRACTICE the menu
-- track fades out into the black, and the next track (lobby, or the practice round's music) starts PLAY_MUSIC_LEAD s
-- before the screen lights up again.
local PLAY_MIN_VISIBLE = 4.0 -- s: long enough for the lead below to be heard under the black
local PLAY_MUSIC_LEAD = 2.0 -- s
local MENU_FADE_OUT = 1.2 -- s
local NEXT_FADE_IN = 1.5 -- s
local MENU_MUSIC = "Menu"
local SILENCE = "Silence"
local loadingMusic = false -- true while the loading screen owns the music

local function setMusic(key: string?, fade: number?)
	if Sound and type(Sound.SetMusicOverride) == "function" then
		pcall(Sound.SetMusicOverride, key, fade)
	end
end

local function musicUsable(key: string): boolean
	local ok, def = pcall(function()
		local Audio = require(Shared:WaitForChild("Audio")) :: any
		return Audio.Resolve(key)
	end)
	return ok and def ~= nil
end

-- screens with their own track while open: the Shop on top plays "Shop" (sleepy Sans's shop), else an open Title
-- plays "Menu"; nothing = automatic selection. Called on every menu change (sync).
local SHOP_MUSIC = "Shop"
local screenMusic: string? = nil
local function syncMenuMusic()
	if loadingMusic then
		return
	end
	local top = topEntry()
	local want: string? = nil
	if top and top.name == "Shop" and musicUsable(SHOP_MUSIC) then
		want = SHOP_MUSIC
	elseif hasScreen("Title") and musicUsable(MENU_MUSIC) then
		want = MENU_MUSIC
	end
	if want ~= screenMusic then
		screenMusic = want
		setMusic(want)
	end
end
UIController._SyncMenuMusic = syncMenuMusic

local function loadingMusicOpts(opts: { [string]: any }): { [string]: any }
	loadingMusic = true
	screenMusic = nil
	setMusic(SILENCE, MENU_FADE_OUT) -- the menu track fades out into the black
	opts.MusicLead = PLAY_MUSIC_LEAD
	opts.OnMusicCue = function()
		setMusic(nil, NEXT_FADE_IN) -- automatic selection again: the lobby track (or the round's) fades in
	end
	local onDone = opts.OnDone
	opts.OnDone = function()
		if loadingMusic then
			loadingMusic = false
			setMusic(nil, NEXT_FADE_IN)
		end
		syncMenuMusic()
		if type(onDone) == "function" then
			onDone()
		end
	end
	return opts
end

function UIController.Play()
	-- the menus close while the screen is black, so the reveal shows the lobby
	local shown = showLoading(loadingMusicOpts({
		MinVisible = PLAY_MIN_VISIBLE,
		OnCovered = function()
			UIController.Close()
		end,
	}))
	if not shown then
		loadingMusic = false
		UIController.Close()
		syncMenuMusic()
	end
end

function UIController.Practice(side: string?)
	local data = { side = if side == "Monster" then "Monster" else "Human" }
	local function request()
		if State and type(State.Request) == "function" then
			call(State, "Request", "StartPractice", data)
		else
			pcall(function()
				local Net = require(Shared:WaitForChild("Net")) :: any
				Net.Client.Fire("Request", "StartPractice", data)
			end)
		end
	end
	-- the screen stays black until the round leaves "Waiting" (map built, Intro), the local character is teleported
	-- or the server refuses; the loading screen caps it at MaxWait
	local refused = false
	local notifyConn: any = nil
	local lastCharacter: Model? = nil
	local lastPosition: Vector3? = nil
	local shown = showLoading(loadingMusicOpts({
		MaxWait = 7,
		MinVisible = PLAY_MIN_VISIBLE,
		OnCovered = function()
			UIController.Close()
			lastCharacter, lastPosition = characterRoot()
			if State and State.Notify then
				notifyConn = State.Notify:Connect(function(key: any)
					if PRACTICE_REFUSED[key] then
						refused = true
					end
				end)
			end
			request()
		end,
		Until = function(): boolean
			if refused or phase() ~= "Waiting" then
				return true
			end
			local character, position = characterRoot()
			local moved = character ~= lastCharacter
				or (position ~= nil and lastPosition ~= nil and (position - lastPosition).Magnitude > TELEPORT_STEP)
			lastCharacter, lastPosition = character, position
			return moved
		end,
		OnDone = function()
			if notifyConn then
				notifyConn:Disconnect()
				notifyConn = nil
			end
		end,
	}))
	if not shown then
		loadingMusic = false
		UIController.Close()
		syncMenuMusic()
		request()
	end
end

function UIController.IsOpen(name: string?): boolean
	if name == nil then
		return #stack > 0
	end
	return hasScreen(name)
end

function UIController.Top(): string?
	local top = topEntry()
	return if top then top.name else nil
end

------------------------------------------------------------------------------------------------ visibility / photo

function UIController.SetVisible(on: boolean)
	visible = on
	if UIRoot and UIRoot.IsInitialized() then
		for _, layer in UIRoot.LayerNames do
			local ok, root = pcall(UIRoot.Layer, layer)
			if ok and root and root.Parent and root.Parent:IsA("ScreenGui") then
				(root.Parent :: ScreenGui).Enabled = on
			end
		end
	end
	if hudHandle and type(hudHandle.SetVisible) == "function" then
		pcall(hudHandle.SetVisible, on)
	end
	UIController.VisibleChanged:Fire(on)
end

local photoPrevMode: string? = nil
function UIController.PhotoMode(on: boolean)
	if on == photo then
		return
	end
	photo = on
	if on then
		local ok, mode = call(Camera, "Mode")
		photoPrevMode = if ok and type(mode) == "string" then mode else "Follow"
		call(Camera, "SetMode", "Photo")
		call(Input, "PushContext", "Photo")
		UIController.SetVisible(false)
	else
		call(Camera, "SetMode", if photoPrevMode == "Photo" then "Follow" else (photoPrevMode or "Follow"))
		call(Input, "PopContext", "Photo")
		UIController.SetVisible(true)
		UIController.Toast(Strings.L("lab.photoHint"), "Info", "Camera", 2)
	end
	syncTouch()
end

------------------------------------------------------------------------------------------------ toasts

function UIController.Toast(text: string, kind: string?, icon: string?, duration: number?)
	if UIRoot and UIRoot.IsInitialized() then
		UIRoot.Toast(text, kind or "Info", icon, duration)
	end
end

local KIND_MAP: { [string]: string } = {
	Info = "Info",
	Success = "Success",
	Warning = "Warning",
	Danger = "Danger",
	Error = "Danger",
	Reward = "Reward",
}

function UIController.Notify(key: string, args: { any }?, kind: string?)
	local text = if args then Strings.L(key, table.unpack(args)) else Strings.L(key)
	UIController.Toast(text, KIND_MAP[kind or "Info"] or "Info")
end

------------------------------------------------------------------------------------------------ round flow

local function onRoundEnd(data: any)
	pendingResult = data
	pendingRewards = nil
	-- let the kill-cam breathe before the card slides in
	task.delay(2.6, function()
		if pendingResult ~= data then
			return
		end
		if hasScreen("Results") then
			UIController.Close("Results")
		end
		-- menus opened mid-round stay underneath; the card goes on top
		UIController.Open("Results", { Result = data, Rewards = pendingRewards })
	end)
end

local function onRewards(data: any)
	pendingRewards = data
	if resultsDeps then
		resultsDeps.Rewards = data
		local top = topEntry()
		if top and top.name == "Results" then
			local handle = UIRoot.Top()
			if handle and type(handle.SetRewards) == "function" then
				pcall(handle.SetRewards, data)
			end
		end
	end
end

local function onPhase(newPhase: string)
	if newPhase == "Intro" then
		local r = role()
		if r == "Human" or r == "Monster" then
			if photo then
				UIController.PhotoMode(false)
			end
			menuCamera = false -- the intro flyover owns the camera now
			UIController.Close()
		end
	end
	sync()
end

------------------------------------------------------------------------------------------------ input

local function routeToScreen(action: string): boolean
	local handle = UIRoot and UIRoot.Top()
	if handle and type(handle.OnAction) == "function" then
		local ok, consumed = pcall(handle.OnAction, action)
		return ok and consumed == true
	end
	return false
end

local function onMenuKey()
	if photo then
		UIController.PhotoMode(false)
		return
	end
	if #stack > 0 then
		UIController.Close()
	elseif inLobby() then
		UIController.Open("Title")
	else
		UIController.Open("Settings")
	end
end

local function bindInput()
	if Input and Input.Action then
		Input.Action:Connect(function(action: string, state: string)
			if state ~= "Begin" then
				return
			end
			if action == "Menu" then
				onMenuKey()
			elseif action == "Back" then
				if photo or #stack > 0 then
					UIController.Back()
				end
			elseif #stack > 0 and (action == "Prev" or action == "Next") then
				routeToScreen(if action == "Prev" then "PrevTab" else "NextTab")
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if photo and input.UserInputType == Enum.UserInputType.Touch then
			UIController.PhotoMode(false)
			return
		end
		if processed then
			return
		end
		local key = input.KeyCode
		if Input == nil then
			-- fallback hotkeys when InputController is missing
			if key == Enum.KeyCode.M or key == Enum.KeyCode.ButtonStart then
				onMenuKey()
				return
			elseif key == Enum.KeyCode.Backspace or key == Enum.KeyCode.ButtonB then
				UIController.Back()
				return
			elseif #stack > 0 and (key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonL1) then
				routeToScreen("PrevTab")
				return
			elseif #stack > 0 and (key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonR1) then
				routeToScreen("NextTab")
				return
			end
		end
		if #stack > 0 and (key == Enum.KeyCode.Left or key == Enum.KeyCode.Right) then
			routeToScreen(if key == Enum.KeyCode.Left then "Left" else "Right")
		end
	end)
end

------------------------------------------------------------------------------------------------ lifecycle

function UIController.Init()
	UIFolder = (script.Parent :: Instance).Parent:WaitForChild("UI")
	ScreensFolder = UIFolder:WaitForChild("Screens", 10)
	UIRoot = require(UIFolder:WaitForChild("UIRoot")) :: any
	ThemeService = require(UIFolder:WaitForChild("ThemeService")) :: any
	Input = controllerModule("InputController")
	State = controllerModule("StateController")
	Camera = controllerModule("CameraController")
	Sound = controllerModule("SoundController")
	Combat = controllerModule("CombatController")
	Graphics = controllerModule("GraphicsController")
	RigStyle = controllerModule("RigStyleController")
	Spectate = controllerModule("SpectateController")
end

function UIController.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	deps = {
		Theme = ThemeService,
		State = State,
		Input = Input,
		Camera = Camera,
		Sound = Sound,
		Combat = Combat,
		Graphics = Graphics,
		UI = UIController,
		Kits = Kits,
		Strings = Strings,
		RigStyle = RigStyle,
		Spectate = Spectate,
	}
	UIRoot.Init(playerGui, {
		PlaySound = function(key: string)
			if Sound and type(Sound.Play) == "function" then
				pcall(Sound.Play, key)
			end
		end,
		Deps = deps,
	})
	started = true

	-- saved look before the first screen is built
	applyAll(false)

	-- HUD (owned by the HUD area; mounted once)
	local hudModule = UIFolder:FindFirstChild("Hud")
	if hudModule and hudModule:IsA("ModuleScript") then
		local ok, Hud = pcall(require, hudModule)
		if ok and type(Hud) == "table" then
			HudModule = Hud
		end
		if ok and type(Hud) == "table" and type((Hud :: any).Mount) == "function" then
			local hudDeps = table.clone(deps)
			hudDeps.Layout = UIRoot.Layout()
			local okMount, handle = pcall((Hud :: any).Mount, UIRoot.Layer("Hud"), hudDeps)
			if okMount then
				hudHandle = handle
			else
				warn("[UIController] Hud.Mount failed: " .. tostring(handle))
			end
		elseif not ok then
			warn("[UIController] Hud failed to load: " .. tostring(Hud))
		end
	end

	-- state wiring
	if State then
		if State.ProfileChanged then
			local first = true
			State.ProfileChanged:Connect(function()
				if first then
					first = false
					applyAll(true)
				end
			end)
		end
		if State.SettingChanged then
			State.SettingChanged:Connect(function(key: string, value: any)
				-- the server's answer (validated / clamped) wins over our optimistic cache once it arrives
				if settingsCache[key] ~= nil and settingsCache[key] ~= value then
					settingsCache[key] = value
					applyDirect(key, value)
				end
			end)
		end
		if type(State.OnRoundEvent) == "function" then
			State.OnRoundEvent("RoundEnd", onRoundEnd)
			State.OnRoundEvent("Rewards", onRewards)
			State.OnRoundEvent("PhaseChanged", function(data: any)
				onPhase(if type(data) == "table" then tostring(data.phase) else tostring(data))
			end)
		end
		if State.Notify then
			State.Notify:Connect(function(key: string, args: any, style: any)
				local top = topEntry()
				if top and menuHidesHud(top.name) and visible then
					UIController.Notify(
						key,
						if type(args) == "table" then args else nil,
						if type(style) == "string" then style else nil
					)
				end
			end)
		end
	end
	bindInput()

	-- language "auto" resolves from LocaleId even before the profile arrives
	if Strings.Language() ~= resolveLanguage(UIController.Setting("Language")) then
		applyDirect("Language", UIController.Setting("Language"))
	end

	-- the title on join
	UIController.Open("Title")
end

return UIController
