--!strict
-- Hud: the in-round HUD (everything on screen while playing). Owns per-phase / per-role visibility of every
-- piece, re-skins on ThemeService.Changed / HudChanged, adapts to device and viewport, and turns RoundEvents
-- into feed lines, announcements, the intro splash and the monster pick banner.
--
--   Hud.Mount(screenGui, deps?) -> HudHandle      runtime (UIController calls it once). screenGui: a ScreenGui
--       (the HUD creates its own UIScale'd design-px root) or an already-scaled Frame (UIRoot.Layer("Hud")).
--       deps (SPEC §20, all optional): Theme, State, Input, Camera, Sound, Combat, Graphics, UI, Kits, Strings,
--       + Spectate (SpectateController: Target() -> Model?), Layout (UIRoot layout when screenGui is a Frame).
--       Missing deps fall back to RoundState/character attributes and Net remotes.
--   HudHandle = { Root, Source, Pieces: {[name]: handle}, Destroy(), SetVisible(bool), Refresh(),
--                 Push(entry) (kill feed), Announce(kind, data?), Toast(text, kind?, icon?),
--                 SetSpectateTarget(model?), Rebuild() }
--   Hud.Create(theme, deps) -> { Root, Destroy }  offline composite preview of a mock scenario:
--       deps.Scenario = Hud/Mock.Names (default "HumanRound"), deps.Hud = "Battle"|"Modern", deps.Layout,
--       deps.Backdrop = false to skip the painted preview scene.
--   Hud.Visible(name, snapshot) -> boolean          the per-phase / per-role visibility rules (pure)
--   Hud.PIECES : { {Name, Z} }                       every piece module (children of this folder)
--   Hud.FeedFromEvent(name, data, unitOf?) -> FeedEntry?   RoundEvent -> kill-feed entry (pure)
-- Pieces (each: Create(theme, deps) -> { Root, Update(snapshot), Tick(now)?, Destroy } + extras):
--   LobbyHud, TopStrip, BossBar, RoundHud, AbilityBar, TeamPanel, Objectives, KillFeed, Notifications,
--   Announcements, IntroSplash, SpectateHud, DeathScreen, MobileControls, Nameplates, EmoteWheel (B / D-pad down
--   radial emote menu, whenever the local player has a body outside the intro). Snapshot contract: Hud/Mock.
local Style = require(script.Style)
local Mock = require(script.Mock)
local Data = require(script.Data)

local Hud = {}

Hud.PIECES = {
	{ Name = "Objectives", Z = 1 },
	{ Name = "TeamPanel", Z = 2 },
	{ Name = "TopStrip", Z = 3 },
	{ Name = "BossBar", Z = 3 },
	{ Name = "RoundHud", Z = 4 },
	{ Name = "AbilityBar", Z = 5 },
	{ Name = "KillFeed", Z = 5 },
	{ Name = "SpectateHud", Z = 5 },
	{ Name = "LobbyHud", Z = 6 },
	{ Name = "MobileControls", Z = 7 },
	{ Name = "Announcements", Z = 8 },
	{ Name = "Notifications", Z = 9 },
	{ Name = "DeathScreen", Z = 10 },
	{ Name = "EmoteWheel", Z = 11 },
	{ Name = "IntroSplash", Z = 12 },
	{ Name = "Nameplates", Z = 0 },
}

local DEATH_SCREEN_TIME = 3.6

local function isFight(phase: string?): boolean
	return phase == "Round" or phase == "Collapse"
end

-- Per-phase / per-role visibility (pure; unit-tested).
function Hud.Visible(name: string, s: { [string]: any }): boolean
	local phase = s.Phase or "Waiting"
	local role = s.Role or "Lobby"
	local me = s.Me
	local participant = role == "Human" or role == "Monster"
	local inMatch = participant or role == "Spectator"
	local fight = isFight(phase)
	local lobbyPhase = phase == "Waiting" or phase == "Intermission"
	local dead = s.Dead == true or (me ~= nil and me.Dead == true)
	local deathScreen = dead and fight and s.DeathAt ~= nil and (s.Now or 0) - s.DeathAt < DEATH_SCREEN_TIME
	local hasBody = me ~= nil and not dead
	local touch = s.Device == "Touch"
	if name == "LobbyHud" then
		return lobbyPhase or not inMatch
	elseif name == "IntroSplash" then
		return phase == "Intro" and inMatch
	elseif name == "TopStrip" then
		return inMatch and (fight or phase == "Ending")
	elseif name == "BossBar" then
		return inMatch and fight and s.Monster ~= nil
	elseif name == "TeamPanel" then
		return inMatch and fight and #(s.Humans or {}) > 0
	elseif name == "Objectives" then
		return inMatch and fight
	elseif name == "RoundHud" then
		return hasBody and ((participant and fight) or (lobbyPhase or not inMatch))
	elseif name == "AbilityBar" then
		return hasBody and not touch and ((participant and fight) or (lobbyPhase or not inMatch))
	elseif name == "MobileControls" then
		return hasBody and touch and ((participant and fight) or (lobbyPhase or not inMatch))
	elseif name == "KillFeed" then
		return inMatch and (fight or phase == "Ending")
	elseif name == "SpectateHud" then
		return fight and (role == "Spectator" or dead) and not deathScreen
	elseif name == "DeathScreen" then
		return deathScreen
	elseif name == "Nameplates" then
		return true
	elseif name == "EmoteWheel" then
		return hasBody and phase ~= "Intro" and not deathScreen
	end
	return true -- Announcements, Notifications
end

local function colorOf(unitOf: any, model: any): Color3?
	if typeof(model) == "Instance" and model:IsA("Model") then
		local kitId = model:GetAttribute("KitId")
		if type(kitId) == "string" then
			return Style.KitColor(kitId)
		end
	end
	if unitOf and model then
		local u = unitOf(model)
		if u then
			return Style.KitColor(u.KitId)
		end
	end
	return nil
end

local function nameOf(model: any, fallback: any): string
	if type(fallback) == "string" and fallback ~= "" then
		return fallback
	end
	if typeof(model) == "Instance" then
		local dn = model:GetAttribute("DisplayName")
		if type(dn) == "string" and dn ~= "" then
			return dn
		end
		return model.Name
	end
	return "?"
end

local SPECIAL_KILL = { Void = "round.feed.void", BleedOut = "round.feed.faded", Collapse = "round.feed.collapse" }

-- RoundEvent -> kill-feed entry (nil = not a feed event). `now` stamps the entry.
function Hud.FeedFromEvent(name: string, data: any, now: number?, unitOf: any?): { [string]: any }?
	if type(data) ~= "table" then
		data = {}
	end
	local t = now or 0
	if name == "Kill" then
		local killer = data.killer
		local victimName = nameOf(data.victim, data.victimName)
		local special = SPECIAL_KILL[data.ability or ""]
		if killer == nil or special then
			return {
				Kind = "Kill",
				Text = Style.L(special or "round.feed.faded", victimName),
				B = victimName,
				BColor = colorOf(unitOf, data.victim),
				Icon = if data.ability == "Void"
					then "ArrowDown"
					elseif data.ability == "Collapse" then "Eclipse"
					else "Skull",
				Time = t,
			}
		end
		local icon = "Skull"
		local kitId = if typeof(killer) == "Instance" then killer:GetAttribute("KitId") else nil
		if type(kitId) == "string" and type(data.ability) == "string" then
			local kits = Style.Kits()
			local ability = if kits then kits.Ability(kitId, data.ability) else nil
			if ability then
				icon = ability.Icon
			elseif data.ability == "VerdictBox" then
				icon = "Box"
			end
		end
		return {
			Kind = "Kill",
			A = nameOf(killer, data.killerName),
			AColor = colorOf(unitOf, killer),
			B = victimName,
			BColor = colorOf(unitOf, data.victim),
			Icon = icon,
			Time = t,
		}
	elseif name == "Downed" then
		local attacker = data.attacker
		return {
			Kind = "Downed",
			A = if attacker then nameOf(attacker, nil) else nil,
			AColor = colorOf(unitOf, attacker),
			B = nameOf(data.victim, data.name),
			BColor = colorOf(unitOf, data.victim),
			Text = Style.L("round.feed.downed", nameOf(data.victim, data.name)),
			Icon = "Skull",
			Time = t,
		}
	elseif name == "Revived" then
		return {
			Kind = "Revived",
			A = nameOf(data.by, data.byName),
			AColor = colorOf(unitOf, data.by),
			B = nameOf(data.victim, data.name),
			BColor = colorOf(unitOf, data.victim),
			Icon = "Heart",
			Time = t,
		}
	elseif name == "SaveLit" then
		local by = data.by
		local who = if type(by) == "table" and by[1]
			then nameOf(by[1], nil)
			elseif typeof(by) == "Instance" then nameOf(by, nil)
			else "?"
		return { Kind = "Save", A = who, B = tostring(data.index or "?"), Time = t }
	elseif name == "Surge" then
		return { Kind = "Surge", Time = t }
	elseif name == "SecondWind" then
		return { Kind = "SecondWind", A = nameOf(data.model, data.name), Time = t }
	elseif name == "PlayerLeft" then
		return { Kind = "Left", Text = Style.L("round.feed.left", data.name or "?"), Icon = "Back", Time = t }
	end
	return nil
end

-- builds every piece into `container`; returns name -> handle
local function buildPieces(
	theme: any,
	pdeps: { [string]: any },
	container: Instance,
	only: { [string]: boolean }?
): { [string]: any }
	local pieces: { [string]: any } = {}
	for _, entry in Hud.PIECES do
		if only == nil or only[entry.Name] then
			local module = script:FindFirstChild(entry.Name)
			if module then
				local okReq, mod = pcall(require, module :: any)
				if okReq and type(mod) == "table" and type((mod :: any).Create) == "function" then
					local okCreate, handle = pcall((mod :: any).Create, theme, pdeps)
					if okCreate and type(handle) == "table" and handle.Root then
						handle.Root.ZIndex = entry.Z
						handle.Root.Parent = container
						pieces[entry.Name] = handle
					else
						warn("[Hud] " .. entry.Name .. ".Create failed: " .. tostring(handle))
					end
				else
					warn("[Hud] cannot load " .. entry.Name .. ": " .. tostring(mod))
				end
			end
		end
	end
	return pieces
end

-- painted stand-in for the 3D world behind offline previews
local function previewScene(phase: string?): Frame
	local scene = Style.Frame({
		Name = "PreviewScene",
		BackgroundTransparency = 0,
		BackgroundColor3 = Style.WHITE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	})
	Style.Gradient(
		scene,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 30, 58)),
			ColorSequenceKeypoint.new(0.52, Color3.fromRGB(150, 108, 92)),
			ColorSequenceKeypoint.new(0.56, Color3.fromRGB(70, 52, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 14, 18)),
		}),
		nil,
		90
	)
	if phase == "Waiting" or phase == "Intermission" then
		scene.BackgroundColor3 = Color3.fromRGB(150, 170, 220)
	end
	for i, x in { 0.08, 0.24, 0.76, 0.92 } do
		local pillar = Style.Frame({
			Name = "Pillar" .. i,
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(34, 26, 30),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(x, 0.62 + (if i == 1 or i == 4 then 0.08 else 0)),
			Size = UDim2.fromScale(if i == 1 or i == 4 then 0.07 else 0.04, 0.62),
			Parent = scene,
		})
		Style.Gradient(pillar, ColorSequence.new(Color3.fromRGB(120, 96, 90), Color3.fromRGB(40, 30, 32)), nil, 0)
	end
	local floor = Style.Frame({
		Name = "Floor",
		BackgroundTransparency = 0.55,
		BackgroundColor3 = Color3.fromRGB(230, 190, 120),
		Position = UDim2.fromScale(0, 0.62),
		Size = UDim2.fromScale(1, 0.004),
		Parent = scene,
	})
	Style.Gradient(floor, nil, Style.Seq({ { 0, 1 }, { 0.5, 0 }, { 1, 1 } }), 0)
	return scene
end

function Hud.Create(theme: any, deps: any): any
	local d = if type(deps) == "table" then table.clone(deps) else {}
	local scenario = d.Scenario or "HumanRound"
	local snap = d.Snapshot or Mock.Scenario(scenario)
	d.Snapshot = snap
	d.Skin = Style.Resolve(theme, d.Hud)
	local root = Style.Frame({ Name = "Hud", Size = UDim2.fromScale(1, 1) })
	if d.Backdrop ~= false then
		previewScene(snap.Phase).Parent = root
	end
	local container = Style.Frame({ Name = "Pieces", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = root })
	local only: { [string]: boolean } = {}
	for _, entry in Hud.PIECES do
		only[entry.Name] = Hud.Visible(entry.Name, snap) and entry.Name ~= "Nameplates"
	end
	if d.Pieces then
		for _, entry in Hud.PIECES do
			only[entry.Name] = table.find(d.Pieces, entry.Name) ~= nil
		end
	end
	local pieces = buildPieces(theme, d, container, only)
	return {
		Root = root,
		Pieces = pieces,
		Destroy = function()
			for _, p in pieces do
				pcall(p.Destroy)
			end
			root:Destroy()
		end,
	}
end

-- runtime -----------------------------------------------------------------------------------------------
local function svc(name: string): any
	local ok, s = pcall(function()
		return game:GetService(name)
	end)
	return if ok then s else nil
end

local function connect(signal: any, fn: (...any) -> ()): any
	if type(signal) == "table" or typeof(signal) == "RBXScriptSignal" then
		local ok, conn = pcall(function()
			return signal:Connect(fn)
		end)
		if ok then
			return conn
		end
	end
	return nil
end

function Hud.Mount(screenGui: Instance, deps: any?): any
	local d: { [string]: any } = if type(deps) == "table" then deps else {}
	local RunService = svc("RunService")
	local Players = svc("Players")
	local okTS, ThemeService = pcall(function()
		return require(script.Parent.ThemeService) :: any
	end)
	local okRoot, UIRoot = pcall(function()
		return require(script.Parent.UIRoot) :: any
	end)
	local themeService: any = if type(d.Theme) == "table" and d.Theme.Current
		then d.Theme
		elseif okTS then ThemeService
		else nil

	local function camera(): Camera?
		local ok, cam = pcall(function()
			return workspace.CurrentCamera
		end)
		return if ok then cam else nil
	end
	local function viewport(): Vector2
		local cam = camera()
		return if cam then cam.ViewportSize else Vector2.new(1920, 1080)
	end
	local function computeLayout(): any
		if okRoot and UIRoot then
			return UIRoot.ComputeLayout(viewport())
		end
		return { Canvas = Vector2.new(1600, 900), Phone = false, Compact = false, Scale = 1, Viewport = viewport() }
	end

	local ownRoot = screenGui:IsA("LayerCollector")
	local layout = computeLayout()
	local base: Frame
	local uiScale: UIScale? = nil
	if ownRoot then
		base = Style.Frame({ Name = "SV_HudRoot", Size = UDim2.fromScale(1 / layout.Scale, 1 / layout.Scale) })
		uiScale = Instance.new("UIScale");
		(uiScale :: UIScale).Scale = layout.Scale;
		(uiScale :: UIScale).Parent = base
		base.Parent = screenGui
	else
		base = screenGui :: any
		if d.Layout then
			layout = d.Layout
		end
	end
	local container = Style.Frame({ Name = "SV_Hud", Size = UDim2.fromScale(1, 1), Parent = base })
	local source = Data.new(d)
	local playerGui: Instance? = nil
	if ownRoot and screenGui.Parent then
		playerGui = screenGui.Parent
	elseif Data.LocalPlayer(Players) then
		playerGui = (Data.LocalPlayer(Players) :: any):FindFirstChildOfClass("PlayerGui")
	end

	local handle: any = { Root = container, Source = source, Pieces = {} }
	local pieces: { [string]: any } = {}
	local feedHistory: { any } = {}
	local snap: { [string]: any } = source:Build()
	local visible = true
	local destroyed = false
	local conns: { any } = {}

	local function pdeps(): { [string]: any }
		local p: { [string]: any } = table.clone(d)
		p.Live = true
		p.Layout = layout
		p.Source = source
		p.BillboardParent = playerGui
		p.Snapshot = snap
		p.OnVote = function(mapId: string)
			source:SetMyVote(mapId)
		end
		return p
	end

	local function applyVisibility(s: { [string]: any })
		for name, piece in pieces do
			local show = visible and Hud.Visible(name, s)
			if piece.Root.Visible ~= show then
				piece.Root.Visible = show
				if show and piece.Update then
					pcall(piece.Update, s)
				end
				if piece.SetActive then
					pcall(piece.SetActive, show)
				end
			end
		end
	end

	local function rebuild()
		for _, piece in pieces do
			pcall(piece.Destroy)
		end
		local theme = if themeService then themeService.Current() else nil
		if theme == nil then
			local Themes = require(script.Parent.Themes) :: any
			theme = Themes.Get(nil)
		end
		local p = pdeps()
		p.Skin = Style.Resolve(theme, if themeService and themeService.HudStyle then themeService.HudStyle() else nil)
		pieces = buildPieces(theme, p, container, nil)
		handle.Pieces = pieces
		for _, piece in pieces do
			piece.Root.Visible = false
			if piece.SetActive then
				pcall(piece.SetActive, false) -- e.g. MobileControls drops its touch bindings until shown
			end
		end
		if pieces.KillFeed then
			for _, entry in feedHistory do
				pcall(pieces.KillFeed.Push, entry)
			end
		end
		applyVisibility(snap)
	end

	local function refresh()
		snap = source:Build()
		applyVisibility(snap)
		for name, piece in pieces do
			if piece.Root.Visible and piece.Update then
				local ok, err = pcall(piece.Update, snap)
				if not ok then
					warn("[Hud] " .. name .. ".Update: " .. tostring(err))
				end
			end
		end
	end

	local function pushFeed(entry: any)
		table.insert(feedHistory, entry)
		while #feedHistory > 6 do
			table.remove(feedHistory, 1)
		end
		if pieces.KillFeed then
			pcall(pieces.KillFeed.Push, entry)
		end
	end

	local function announce(kind: string, data: any?)
		if pieces.Announcements then
			pcall(pieces.Announcements.Show, kind, data)
		end
	end

	rebuild()
	refresh()
	local phaseSeen: string = snap.Phase or "Waiting"

	-- events --------------------------------------------------------------------------------------------
	local function isLocalModel(model: any): boolean
		return typeof(model) == "Instance" and model == source:LocalCharacter()
	end
	local function onRoundEvent(name: string, data: any)
		if destroyed then
			return
		end
		data = if type(data) == "table" then data else {}
		local now = source:Now()
		local monsterSide = snap.Role == "Monster"
		if name == "MapVote" then
			source:SetVotes(data.votes)
		elseif name == "MonsterChosen" then
			if pieces.LobbyHud and pieces.LobbyHud.ShowChosen then
				local localPlayer = Data.LocalPlayer(Players)
				pcall(pieces.LobbyHud.ShowChosen, {
					Name = data.name,
					KitId = data.kitId,
					IsLocal = localPlayer ~= nil and data.userId == localPlayer.UserId,
				})
			end
		elseif name == "Intro" then
			table.clear(feedHistory)
			if pieces.KillFeed then
				pieces.KillFeed.Clear()
			end
			if pieces.IntroSplash and pieces.IntroSplash.Play then
				pcall(pieces.IntroSplash.Play, data, source)
			end
		elseif name == "PhaseChanged" then
			if data.phase == "Round" and phaseSeen ~= "Round" and phaseSeen ~= "Collapse" and snap.Role ~= "Lobby" then
				announce("Fight", { Monster = monsterSide })
			elseif data.phase == "Intermission" or data.phase == "Waiting" then
				source:SetMyVote(nil)
				source:SetVotes({})
				source:SetKiller(nil)
			end
		elseif name == "FinalPhase" then
			announce("FinalPhase", { Monster = monsterSide })
		elseif name == "Surge" then
			announce("Surge", { Monster = monsterSide })
		elseif name == "SecondWind" then
			announce("SecondWind", { Self = isLocalModel(data.model), Name = data.name })
		elseif name == "Collapse" then
			announce("Collapse", {})
		elseif name == "SaveLit" then
			announce("SaveLit", { Lit = data.lit, Total = data.total })
		elseif name == "Kill" then
			if isLocalModel(data.victim) then
				source:SetKiller(nameOf(data.killer, data.killerName))
			end
		end
		if name == "PhaseChanged" and type(data.phase) == "string" then
			phaseSeen = data.phase
		end
		local entry = Hud.FeedFromEvent(name, data, now, function(model: any)
			return source:UnitOf(model, now)
		end)
		if entry then
			pushFeed(entry)
		end
		refresh()
	end

	local state = d.State
	if type(state) == "table" and state.RoundEvent then
		table.insert(conns, connect(state.RoundEvent, onRoundEvent))
	elseif type(state) == "table" and type(state.OnRoundEvent) == "function" then
		for _, name in
			{
				"PhaseChanged",
				"MapVote",
				"MonsterChosen",
				"Intro",
				"Kill",
				"Downed",
				"Revived",
				"SaveLit",
				"Surge",
				"FinalPhase",
				"SecondWind",
				"Collapse",
				"RoundEnd",
				"PlayerLeft",
			}
		do
			local ok, conn = pcall(state.OnRoundEvent, name, function(data: any)
				onRoundEvent(name, data)
			end)
			if ok then
				table.insert(conns, conn)
			end
		end
	else
		task.spawn(function()
			local ok, Net = pcall(function()
				return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Net")) :: any
			end)
			if ok and not destroyed then
				local okOn, conn = pcall(Net.Client.On, "RoundEvent", onRoundEvent)
				if okOn then
					table.insert(conns, conn)
				end
				local okN, connN = pcall(Net.Client.On, "Notify", function(key: string, args: any, style: any)
					if pieces.Notifications then
						pcall(pieces.Notifications.Notify, key, args, style)
					end
				end)
				if okN then
					table.insert(conns, connN)
				end
			end
		end)
	end
	if type(state) == "table" and state.Notify then
		table.insert(
			conns,
			connect(state.Notify, function(key: string, args: any, style: any)
				if pieces.Notifications then
					pcall(pieces.Notifications.Notify, key, args, style)
				end
			end)
		)
	end
	if type(state) == "table" and state.RoundChanged then
		table.insert(
			conns,
			connect(state.RoundChanged, function()
				refresh()
			end)
		)
	end
	if themeService then
		table.insert(conns, connect(themeService.Changed, rebuild))
		table.insert(conns, connect(themeService.HudChanged, rebuild))
	end
	if type(d.Input) == "table" and d.Input.DeviceChanged then
		table.insert(
			conns,
			connect(d.Input.DeviceChanged, function()
				rebuild()
				refresh()
			end)
		)
	end
	local cam = camera()
	if cam then
		table.insert(
			conns,
			connect((cam :: any):GetPropertyChangedSignal("ViewportSize"), function()
				local newLayout = computeLayout()
				if
					newLayout.Phone ~= layout.Phone
					or math.abs(newLayout.Scale - layout.Scale) > 0.01
					or newLayout.Canvas ~= layout.Canvas
				then
					if ownRoot or d.Layout == nil then
						layout = newLayout
					end
					if uiScale then
						uiScale.Scale = layout.Scale
						base.Size = UDim2.fromScale(1 / layout.Scale, 1 / layout.Scale)
					end
					rebuild()
					refresh()
				end
			end)
		)
	end

	-- frame loop: snapshot at 10 Hz, per-frame Tick for timers / cooldown wipes / markers
	local acc = 0
	local function step(dt: number)
		if destroyed or not visible then
			return
		end
		acc += dt
		if acc >= 0.1 then
			acc = 0
			refresh()
		end
		local now = source:Now()
		for name, piece in pieces do
			if piece.Tick and piece.Root.Visible then
				local ok, err = pcall(piece.Tick, now, dt)
				if not ok then
					warn("[Hud] " .. name .. ".Tick: " .. tostring(err))
				end
			end
		end
	end
	local bound = false
	if RunService then
		local ok = pcall(function()
			RunService:BindToRenderStep("SV_Hud", Enum.RenderPriority.Camera.Value + 10, step)
		end)
		bound = ok
		if not ok then
			table.insert(conns, connect(RunService.Heartbeat, step))
		end
	end

	handle.Destroy = function()
		if destroyed then
			return
		end
		destroyed = true
		if bound and RunService then
			pcall(function()
				RunService:UnbindFromRenderStep("SV_Hud")
			end)
		end
		for _, conn in conns do
			if conn then
				pcall(function()
					conn:Disconnect()
				end)
			end
		end
		for _, piece in pieces do
			pcall(piece.Destroy)
		end
		source:Destroy()
		container:Destroy()
		if ownRoot then
			base:Destroy()
		end
	end
	handle.SetVisible = function(on: boolean)
		visible = on
		container.Visible = on
		if on then
			refresh()
		else
			applyVisibility(snap) -- hides every piece (SetActive(false): touch bindings, nameplates)
		end
	end
	handle.Refresh = refresh
	handle.Rebuild = function()
		rebuild()
		refresh()
	end
	handle.Push = pushFeed
	handle.Announce = announce
	handle.Toast = function(text: string, kind: string?, icon: string?)
		if pieces.Notifications then
			pcall(pieces.Notifications.Push, text, kind, icon)
		end
	end
	handle.SetSpectateTarget = function(model: Model?)
		source:SetSpectate(model)
		refresh()
	end
	return handle
end

return Hud
