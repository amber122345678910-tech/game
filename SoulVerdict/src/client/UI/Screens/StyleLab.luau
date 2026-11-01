--!strict
-- Screens/StyleLab: the owner's live comparison bench (SPEC §10). A compact side panel on the right that leaves
-- the 3D view visible. Everything here is a PREVIEW (not saved to the profile) except server actions.
--   LOOK   graphics preset (GraphicsController.PushOverride("StyleLab", id, 50, 0.8); "Off" pops it),
--          menu theme (ThemeService.Set), HUD style (ThemeService.SetHudStyle), rig style + particle density
--          (UIController.ApplySetting, live only), skin of your current kit (EquipSkin, or StyleLab SetSkin)
--   WORLD  map (Request StyleLab {action="SetMap", mapId, now}), ambient weather (GraphicsController
--          .SetAmbientOverride when present, else VFX/Ambient.Set)
--   A / B  pin two complete looks and flip between them (pins survive theme rebuilds: module state)
--   MATCH  StartRound, StartPractice {side}, GiveUlt, SetPhase {FinalPhase|Collapse}, EndRound, SpawnDummy,
--          Heal, ResetCooldowns  (all Request "StyleLab" {action=...}, validated by StyleLabService)
--   PHOTO  CameraController.SetMode("Photo") + UIController.SetVisible(false); Back returns.
-- A status line shows the active preset, quality tier and FPS (GraphicsController).
--
--   StyleLab.Create(theme, deps) -> { Root, Destroy, DefaultSelection }
--   deps: Graphics, Theme (ThemeService), Camera, UI, State, Layout (+ offline mocks: Round, Kit)

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Motion = require(script.Parent.Parent.Motion)
local Common = require(script.Parent.Common)

type Theme = Themes.Theme

local StyleLab = {}

local L = Common.L
local pick = Common.Pick
local frame = Common.Frame

local WEATHER = { "Preset", "None", "Snow", "Blizzard", "Embers", "Ash", "Dust", "Fireflies", "Spores", "VoidMotes", "RiftMotes", "Glimmer", "Rain" }

-- lab state survives screen rebuilds (theme switches rebuild every screen)
type Look = { Graphics: string, Theme: string, Hud: string, Rig: string, Weather: string }
local lab = {
	Graphics = nil :: string?,
	Weather = "Preset",
	Rig = nil :: string?,
	Particles = nil :: number?,
	PinA = nil :: Look?,
	PinB = nil :: Look?,
	Showing = "A",
}

local function call(target: any, method: string, ...: any): (boolean, any)
	if type(target) ~= "table" or type(target[method]) ~= "function" then
		return false, nil
	end
	return pcall(target[method], ...)
end

function StyleLab.Create(theme: Theme, deps: any): any
	local d = deps or {}
	local c = theme.Colors
	local layout = Common.Layout(d)
	local phone = layout.Phone == true
	local bag = Common.Bag()
	local graphics = d.Graphics
	local themeService = d.Theme
	local presets = Common.Module({ "Graphics", "Presets" })
	local registry = Common.Module({ "Maps", "Registry" })
	local kits = Common.Kits()

	local root = frame({ Name = "StyleLab", Size = UDim2.fromScale(1, 1) })
	-- legibility gradient behind the panel only (the world stays visible)
	local shade = frame({ Name = "Shade", BackgroundTransparency = 0, BackgroundColor3 = c.Background, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, if phone then 520 else 640, 1, 0), Parent = root })
	Common.Gradient(shade, nil, Common.NSeq({ { 0, 1 }, { 0.5, 0.55 }, { 1, 0.3 } }), 0)
	if Common.IsPreview(d) then
		-- offline stand-in for the live world on the left
		local world = UIKit.Backdrop(theme, { Name = "PreviewWorld" })
		world.ZIndex = 0
		world.Parent = root
		shade.ZIndex = 1
	end

	local panelW = if phone then 420 else 460
	local margin = if phone then 10 else 22
	local panel = UIKit.Panel(theme, {
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -margin, 0, margin),
		Size = UDim2.new(0, panelW, 1, -margin * 2),
		Padding = if phone then 10 else 16,
	})
	panel.Root.ZIndex = 2
	panel.Root.Parent = root
	local content = panel.Content

	-- header ------------------------------------------------------------------------------------------
	local headH = if phone then 40 else 64
	local head = frame({ Name = "Head", Size = UDim2.new(1, 0, 0, headH), Parent = content })
	local title = UIKit.Title(theme, {
		Text = L("lab.title"),
		Role = "Title",
		TextSize = if phone then math.floor(theme.TextSize.Title * 0.6) else math.floor(theme.TextSize.Title * 0.78),
		Subtitle = if phone then nil else L("lab.subtitle"),
		Size = UDim2.new(1, -60, 0, if phone then 30 else 36),
		Glow = false,
	})
	title.Root.Parent = head
	local close = UIKit.Button(theme, {
		Name = "Close",
		Variant = "Icon",
		Icon = "Close",
		Height = if phone then 34 else 42,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		OnActivated = function()
			if d.UI and type(d.UI.Back) == "function" then
				d.UI.Back()
			elseif d.UIRoot then
				d.UIRoot.Pop()
			end
		end,
	})
	close.Root.Parent = head

	-- status line (preset · quality · fps)
	local status = UIKit.Label(theme, {
		Name = "Status",
		Text = "",
		Role = "Mono",
		TextSize = if theme.Id == "Classic" then 8 else 12,
		Tone = "Accent",
		Position = UDim2.fromOffset(0, headH + 2),
		Size = UDim2.new(1, 0, 0, 18),
		Truncate = true,
		Parent = content,
	})
	local function statusText(): string
		local preset = lab.Graphics or "?"
		local okP, cur = call(graphics, "Current")
		if okP and type(cur) == "string" then
			preset = cur
		end
		local quality = "Auto"
		local okQ, q = call(graphics, "Quality")
		if okQ and type(q) == "string" then
			quality = q
		end
		local fps = 60
		local okF, ft = call(graphics, "FrameTime")
		if okF and type(ft) == "number" and ft > 0 then
			fps = math.floor(1 / ft + 0.5)
		end
		return L("lab.status", preset, quality, fps)
	end
	status.Text = statusText()
	local acc = 0
	bag.Add(Motion.Loop(status, function(dt: number)
		acc += dt
		if acc > 0.5 then
			acc = 0
			status.Text = statusText()
		end
	end))

	-- scrolling body ----------------------------------------------------------------------------------
	local listTop = headH + 26
	local scroll = UIKit.List(theme, { Gap = if phone then 6 else 8 })
	scroll.Root.Position = UDim2.fromOffset(0, listTop)
	scroll.Root.Size = UDim2.new(1, 0, 1, -listTop)
	scroll.Root.Parent = content
	local order = 0
	local rowH = if phone then 34 else 40
	local first: GuiObject? = nil

	local function nextOrder(): number
		order += 1
		return order
	end

	local function section(key: string, icon: string)
		local row = frame({ Name = "Section_" .. key, Size = UDim2.new(1, -8, 0, if phone then 24 else 30), LayoutOrder = nextOrder() })
		local ic = UIKit.Icon(icon, c.Accent, if phone then 16 else 18)
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 0, 0.5, 0)
		ic.Parent = row
		UIKit.Label(theme, { Text = UIKit.Upper(L(key)), Role = "Caption", Tone = "Accent", Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 1, 0), Parent = row })
		UIKit.Divider(theme, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 4), Parent = row })
		scroll.Add(row)
	end

	local function cycle(labelKey: string, options: { { Id: string, Text: string } }, current: string?, onChanged: (string) -> ())
		local index = 1
		for i, o in options do
			if o.Id == current then
				index = i
			end
		end
		local h = UIKit.Cycle(theme, {
			Label = L(labelKey),
			Options = options,
			Index = index,
			Dots = false,
			Height = rowH,
			LayoutOrder = nextOrder(),
			OnChanged = function(i: number)
				local o = options[i]
				if o then
					onChanged(o.Id)
				end
			end,
		})
		h.Root.Size = UDim2.new(1, -8, 0, rowH)
		scroll.Add(h.Root)
		first = first or h.Root
	end

	local function buttonRow(specs: { { [string]: any } })
		local row = frame({ Name = "Buttons", Size = UDim2.new(1, -8, 0, rowH), LayoutOrder = nextOrder() })
		local rl = UIKit.ListLayout(row, { Horizontal = true, Gap = 8 })
		rl.HorizontalFlex = Enum.UIFlexAlignment.Fill
		for i, sp in specs do
			local b = UIKit.Button(theme, {
				Text = sp.Text,
				Icon = sp.Icon,
				Variant = sp.Variant or "Secondary",
				Height = rowH,
				Width = 100,
				Selected = sp.Selected,
				LayoutOrder = i,
				OnActivated = sp.OnActivated,
			})
			b.Root.Parent = row
		end
		scroll.Add(row)
	end

	local function labRequest(data: { [string]: any })
		Common.Request(d, "StyleLab", data)
	end

	local function applySetting(key: string, value: any)
		local ui = d.UI
		if ui and type(ui.ApplySetting) == "function" then
			ui.ApplySetting(key, value)
		end
	end

	local function setGraphics(id: string)
		if id == "Off" then
			lab.Graphics = nil
			call(graphics, "PopOverride", "StyleLab", 0.8)
		else
			lab.Graphics = id
			call(graphics, "PushOverride", "StyleLab", id, 50, 0.8)
		end
		status.Text = statusText()
	end

	local function setWeather(id: string)
		lab.Weather = id
		if id == "Preset" then
			if not call(graphics, "SetAmbientOverride", nil) then
				call(graphics, "Refresh", 0.5)
			end
			return
		end
		local ok = call(graphics, "SetAmbientOverride", if id == "None" then "" else id)
		if not ok and not Common.IsPreview(d) then
			pcall(function()
				local player = game:GetService("Players").LocalPlayer
				local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
				local ambient = require(client:WaitForChild("VFX"):WaitForChild("Ambient")) :: any
				if id == "None" then
					ambient.Stop()
				else
					local okS, scale = call(graphics, "ParticleScale")
					ambient.Set(id, if okS and type(scale) == "number" then scale else 1)
				end
			end)
		end
	end

	local function currentTheme(): string
		local ok, t = call(themeService, "Current")
		return if ok and t then t.Id else theme.Id
	end
	local function currentHud(): string
		local ok, h = call(themeService, "HudStyle")
		return if ok and h then h.Id else "Battle"
	end
	local function currentRig(): string
		return lab.Rig or tostring(Common.Setting(d, "RigStyle") or "Toon")
	end

	local function snapshot(): Look
		return {
			Graphics = lab.Graphics or "Off",
			Theme = currentTheme(),
			Hud = currentHud(),
			Rig = currentRig(),
			Weather = lab.Weather,
		}
	end

	local function applyLook(look: Look)
		setGraphics(look.Graphics)
		setWeather(look.Weather)
		lab.Rig = look.Rig
		applySetting("RigStyle", look.Rig)
		call(themeService, "SetHudStyle", look.Hud)
		if look.Theme ~= currentTheme() then
			-- rebuilds every screen (this one included) -> do it last
			task.defer(function()
				call(themeService, "Set", look.Theme)
			end)
		end
	end

	-- LOOK ------------------------------------------------------------------------------------------------
	section("lab.section.look", "Palette")
	local presetOptions = { { Id = "Off", Text = L("lab.weather.Preset") } }
	if presets then
		for _, p in presets.All() do
			local kind = "Map"
			pcall(function()
				kind = presets.Kind(p.Id)
			end)
			table.insert(presetOptions, { Id = p.Id, Text = pick(p.Name) .. (if kind == "Final" then "  (" .. L("lab.kind.Final") .. ")" else "") })
		end
	end
	cycle("lab.graphics", presetOptions, lab.Graphics or "Off", setGraphics)
	local themeOptions = {}
	for _, t in Themes.List() do
		table.insert(themeOptions, { Id = t.Id, Text = pick(t.Name) })
	end
	cycle("lab.theme", themeOptions, currentTheme(), function(id: string)
		task.defer(function()
			call(themeService, "Set", id)
		end)
	end)
	local hudOptions = {}
	for _, id in Themes.HudIds do
		table.insert(hudOptions, { Id = id, Text = pick(Themes.GetHud(id).Name) })
	end
	cycle("lab.hud", hudOptions, currentHud(), function(id: string)
		call(themeService, "SetHudStyle", id)
	end)
	local rigStyles = Common.Module({ "Rigs", "RigStyles" })
	local rigOptions = {}
	if rigStyles then
		for _, id in rigStyles.List() do
			local info = rigStyles.Get(id)
			table.insert(rigOptions, { Id = id, Text = if info then pick(info.Name) else id })
		end
	end
	cycle("lab.rig", rigOptions, currentRig(), function(id: string)
		lab.Rig = id
		applySetting("RigStyle", id)
	end)
	-- skin of the kit you are wearing right now
	local character: any = nil
	local okChar, model = call(d.State, "LocalCharacter")
	if okChar then
		character = model
	end
	local kitId = d.Kit or (character and character:GetAttribute("KitId")) or Common.EquippedKit(Common.Profile(d), "Human")
	local kit = kits and kitId and kits.Get(kitId)
	if kit then
		local skinOptions = {}
		for _, skin in kit.Skins do
			table.insert(skinOptions, { Id = skin.Id, Text = pick(skin.Name) })
		end
		local currentSkin = (character and character:GetAttribute("SkinId")) or Common.EquippedSkin(Common.Profile(d), kit)
		cycle("lab.skin", skinOptions, currentSkin, function(id: string)
			local skin = kits.Skin(kit.Id, id)
			if skin and Common.SkinOwned(Common.Profile(d), kit, skin) then
				Common.Request(d, "EquipSkin", { kitId = kit.Id, skinId = id })
			else
				labRequest({ action = "SetSkin", kitId = kit.Id, skinId = id })
			end
		end)
	end

	-- WORLD -----------------------------------------------------------------------------------------------
	section("lab.section.world", "Map")
	local mapOptions = {}
	local mapId = tostring(Common.Round(d).MapId or "")
	if registry then
		for _, meta in registry.List() do
			if meta.Kind == "Arena" or meta.Kind == "Test" then
				table.insert(mapOptions, { Id = meta.Id, Text = pick(meta.Name) })
			end
		end
	end
	local pendingMap = mapId
	if #mapOptions > 0 then
		cycle("lab.map", mapOptions, mapId, function(id: string)
			pendingMap = id
		end)
		buttonRow({
			{
				Text = L("lab.mapNext"),
				Icon = "Flag",
				OnActivated = function()
					labRequest({ action = "SetMap", mapId = pendingMap })
				end,
			},
			{
				Text = L("lab.mapNow"),
				Icon = "Play",
				Variant = "Primary",
				OnActivated = function()
					labRequest({ action = "SetMap", mapId = pendingMap, now = true })
				end,
			},
		})
	end
	local weatherOptions = {}
	for _, id in WEATHER do
		table.insert(weatherOptions, { Id = id, Text = L("lab.weather." .. id) })
	end
	cycle("lab.weather", weatherOptions, lab.Weather, setWeather)
	local density = lab.Particles or tonumber(Common.Setting(d, "ParticleDensity")) or 1
	local slider = UIKit.Slider(theme, {
		Label = L("lab.particles"),
		Value = density,
		Min = 0,
		Max = 2,
		Step = 0.1,
		Height = rowH,
		LayoutOrder = nextOrder(),
		Format = function(v: number): string
			return string.format("x%.1f", v)
		end,
		OnChanged = function(v: number)
			lab.Particles = v
			applySetting("ParticleDensity", v)
		end,
	})
	slider.Root.Size = UDim2.new(1, -8, 0, rowH)
	scroll.Add(slider.Root)

	-- A / B -----------------------------------------------------------------------------------------------
	section("lab.section.compare", "Eye")
	local function pinText(slot: string, look: Look?): string
		if look == nil then
			return slot .. ": " .. L("lab.slotEmpty")
		end
		return slot .. ": " .. look.Graphics .. " / " .. look.Theme .. " / " .. look.Rig
	end
	local pins = frame({ Name = "Pins", Size = UDim2.new(1, -8, 0, if phone then 30 else 36), LayoutOrder = nextOrder() })
	UIKit.ListLayout(pins, { Gap = 2 })
	for i, slot in { "A", "B" } do
		local look = if slot == "A" then lab.PinA else lab.PinB
		UIKit.Label(theme, {
			Text = pinText(slot, look),
			Role = "Mono",
			TextSize = if theme.Id == "Classic" then 7 else 11,
			Color = if lab.Showing == slot and look then c.Accent else c.TextDim,
			Size = UDim2.new(1, 0, 0, if phone then 14 else 17),
			Truncate = true,
			LayoutOrder = i,
			Parent = pins,
		})
	end
	scroll.Add(pins)
	local rebuild: () -> ()
	buttonRow({
		{
			Text = L("lab.pinA"),
			Icon = "Plus",
			OnActivated = function()
				lab.PinA = snapshot()
				lab.Showing = "A"
				rebuild()
			end,
		},
		{
			Text = L("lab.pinB"),
			Icon = "Plus",
			OnActivated = function()
				lab.PinB = snapshot()
				lab.Showing = "B"
				rebuild()
			end,
		},
		{
			Text = L("lab.swap", if lab.Showing == "A" then "B" else "A"),
			Icon = "Refresh",
			Variant = "Primary",
			OnActivated = function()
				local target = if lab.Showing == "A" then lab.PinB else lab.PinA
				if target then
					lab.Showing = if lab.Showing == "A" then "B" else "A"
					applyLook(target)
					rebuild()
				end
			end,
		},
	})
	UIKit.Label(theme, {
		Text = L("lab.compareHint"),
		Role = "Caption",
		Tone = "Muted",
		Wrap = true,
		Size = UDim2.new(1, -8, 0, if phone then 24 else 30),
		LayoutOrder = nextOrder(),
		Parent = scroll.Content,
	})

	-- MATCH -----------------------------------------------------------------------------------------------
	section("lab.section.match", "Swords")
	local actions = {
		{ "lab.startRound", "Play", { action = "StartRound" } },
		{ "lab.practiceH", "Heart", { action = "StartPractice", side = "Human" } },
		{ "lab.practiceM", "Skull", { action = "StartPractice", side = "Monster" } },
		{ "lab.giveUlt", "Bolt", { action = "GiveUlt" } },
		{ "lab.finalPhase", "Eye", { action = "SetPhase", phase = "FinalPhase" } },
		{ "lab.collapse", "Target", { action = "SetPhase", phase = "Collapse" } },
		{ "lab.endRound", "Flag", { action = "EndRound" } },
		{ "lab.dummy", "Users", { action = "SpawnDummy", count = 1 } },
		{ "lab.heal", "Heart", { action = "Heal" } },
		{ "lab.cooldowns", "Clock", { action = "ResetCooldowns" } },
	}
	local gridH = math.ceil(#actions / 2) * (rowH + 8)
	local grid = frame({ Name = "Actions", Size = UDim2.new(1, -8, 0, gridH), LayoutOrder = nextOrder() })
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -4, 0, rowH)
	gl.CellPadding = UDim2.fromOffset(8, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	for i, a in actions do
		local data = a[3]
		local b = UIKit.Button(theme, {
			Text = L(a[1]),
			Icon = a[2],
			Variant = "Secondary",
			Height = rowH,
			LayoutOrder = i,
			OnActivated = function()
				labRequest(data)
			end,
		})
		b.Root.Parent = grid
	end
	scroll.Add(grid)

	-- PHOTO -----------------------------------------------------------------------------------------------
	local photo = UIKit.Button(theme, {
		Name = "Photo",
		Text = L("lab.photo"),
		Icon = "Camera",
		Variant = "Primary",
		Height = rowH + 8,
		LayoutOrder = nextOrder(),
		OnActivated = function()
			local ui = d.UI
			if ui and type(ui.PhotoMode) == "function" then
				ui.PhotoMode(true)
			else
				call(d.Camera, "SetMode", "Photo")
				if ui and type(ui.SetVisible) == "function" then
					ui.SetVisible(false)
				end
			end
		end,
	})
	photo.Root.Size = UDim2.new(1, -8, 0, rowH + 8)
	scroll.Add(photo.Root)

	rebuild = function()
		local ui = d.UI
		if ui and type(ui.Open) == "function" then
			ui.Open("StyleLab", { Replace = true })
		end
	end

	return {
		Root = root,
		DefaultSelection = first or close.Root,
		Destroy = function()
			bag.Clean()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- exposed for tests / UIController (current lab overrides)
function StyleLab.State(): any
	return lab
end

return StyleLab
