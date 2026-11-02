--!strict
-- Screens/Settings: every player setting, saved to the profile (Request SetSetting {key, value}) and applied
-- live. Applying is centralised in UIController.SetSetting(key, value) (GraphicsController.SetOverride /
-- SetQualityOverride / SetParticleDensity, ThemeService.Set / SetHudStyle, RigStyleController, SoundController
-- .SetVolumes, CameraController, Strings.SetLanguage + UI rebuild); without a UIController the screen only
-- sends the request. Ranges/enums come from Shared/Progression/ProfileSchema.Settings() when present.
--
--   Settings.Create(theme, deps) -> { Root, Destroy, DefaultSelection }
--   deps: UI (UIController: Setting(key), SetSetting(key, value), ResetSettings()), State, Layout
--         (+ offline: Profile, Section = "Graphics"|"Interface"|"Audio" on phones)

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Motion = require(script.Parent.Parent.Motion)
local Common = require(script.Parent.Common)

type Theme = Themes.Theme

local Settings = {}

local L = Common.L
local pick = Common.Pick
local frame = Common.Frame

local QUALITY = { "Auto", "Low", "Medium", "High", "Ultra" }
local LANGS = { "auto", "en", "ru" }

local function spec(key: string): any
	local schema = Common.Progression("ProfileSchema")
	local ok, specs = Common.Call(schema, { "Settings" })
	if ok and type(specs) == "table" then
		return specs[key]
	end
	return nil
end

local function range(key: string, min: number, max: number): (number, number)
	local s = spec(key)
	if s and type(s.Min) == "number" and type(s.Max) == "number" then
		return s.Min, s.Max
	end
	return min, max
end

local function presetOptions(): { { Id: string, Text: string } }
	local out = { { Id = "MapDefault", Text = L("set.preset.MapDefault") } }
	local presets = Common.Module({ "Graphics", "Presets" })
	if presets then
		for _, p in presets.All() do
			local kind = "Map"
			pcall(function()
				kind = presets.Kind(p.Id)
			end)
			if kind ~= "Final" then
				table.insert(out, { Id = p.Id, Text = pick(p.Name) })
			end
		end
	end
	return out
end

local function rigOptions(): { { Id: string, Text: string } }
	local out = {}
	local rigStyles = Common.Module({ "Rigs", "RigStyles" })
	if rigStyles then
		for _, id in rigStyles.List() do
			local info = rigStyles.Get(id)
			table.insert(out, { Id = id, Text = if info then pick(info.Name) else id })
		end
	end
	if #out == 0 then
		for _, id in { "Classic", "Toon", "Soft", "Glow" } do
			table.insert(out, { Id = id, Text = id })
		end
	end
	return out
end

local function indexOf(options: { { Id: string, Text: string } }, id: any): number
	for i, o in options do
		if o.Id == id then
			return i
		end
	end
	return 1
end

function Settings.Create(theme: Theme, deps: any): any
	local d = deps or {}
	local screen = Common.Screen(theme, d, {
		Name = "Settings",
		Title = L("set.title"),
		Subtitle = L("set.subtitle"),
		Icon = "Settings",
	})
	local root, body = screen.Root, screen.Body
	local phone = screen.Phone
	local canvas = screen.Canvas
	local bodyW = canvas.X - screen.Margin * 2
	local bodyH = body.Size.Y.Offset + canvas.Y * body.Size.Y.Scale
	local gap = screen.Gap
	local section: string = d.Section or "Graphics"
	local desc: TextLabel? = nil
	local first: GuiObject? = nil

	local function get(key: string): any
		local v = Common.Setting(d, key)
		if v == nil then
			local s = spec(key)
			v = s and s.Default
		end
		return v
	end

	local function set(key: string, value: any)
		local ui = d.UI
		if ui and type(ui.SetSetting) == "function" then
			ui.SetSetting(key, value)
		else
			Common.Request(d, "SetSetting", { key = key, value = value })
		end
	end

	local function describe(key: string)
		if desc then
			local k = "set.desc." .. key
			desc.Text = (if theme.Id == "Classic" then theme.DialoguePrefix else "") .. (if Common.Has(k) then L(k) else L("set." .. key))
		end
	end

	local rowH = if phone then 34 else 40
	local function hook(control: GuiObject, key: string)
		Motion.Hover(control, function()
			describe(key)
		end, function() end)
		first = first or control
	end

	-- control builders ------------------------------------------------------------------------------
	local function cycle(parent: Instance, key: string, options: { { Id: string, Text: string } }, order: number)
		local h = UIKit.Cycle(theme, {
			Label = L("set." .. key),
			Options = options,
			Index = indexOf(options, get(key)),
			Height = rowH,
			Dots = #options <= 6,
			LayoutOrder = order,
			Parent = parent,
			OnChanged = function(i: number)
				local o = options[i]
				if o then
					set(key, o.Id)
				end
			end,
		})
		hook(h.Root, key)
	end

	local function dropdown(parent: Instance, key: string, options: { { Id: string, Text: string } }, order: number)
		local h = UIKit.Dropdown(theme, {
			Label = L("set." .. key),
			Options = options,
			Index = indexOf(options, get(key)),
			Height = rowH,
			LayoutOrder = order,
			Parent = parent,
			OnChanged = function(i: number)
				local o = options[i]
				if o then
					set(key, o.Id)
				end
			end,
		})
		hook(h.Root, key)
	end

	local function slider(parent: Instance, key: string, min: number, max: number, step: number, format: (number) -> string, order: number)
		local lo, hi = range(key, min, max)
		local h = UIKit.Slider(theme, {
			Label = L("set." .. key),
			Value = math.clamp(tonumber(get(key)) or lo, lo, hi),
			Min = lo,
			Max = hi,
			Step = step,
			Format = format,
			Height = rowH,
			LayoutOrder = order,
			Parent = parent,
			OnChanged = function(v: number)
				set(key, v)
			end,
		})
		hook(h.Root, key)
	end

	local function toggle(parent: Instance, key: string, order: number)
		local h = UIKit.Toggle(theme, {
			Label = L("set." .. key),
			Value = get(key) == true,
			Height = rowH,
			LayoutOrder = order,
			Parent = parent,
			OnChanged = function(v: boolean)
				set(key, v)
			end,
		})
		hook(h.Root, key)
	end

	local function pct(v: number): string
		return L("set.percent", math.floor(v * 100 + 0.5))
	end

	local function panel(name: string, titleKey: string, icon: string, x: number, y: number, w: number, h: number): Frame
		local p = UIKit.Panel(theme, {
			Name = name,
			Title = L(titleKey),
			TitleIcon = icon,
			Size = UDim2.fromOffset(w, h),
			Position = UDim2.fromOffset(x, y),
			Padding = if phone then 10 else 16,
			Layout = "Vertical",
			Gap = if phone then 4 else 8,
		})
		p.Root.Parent = body
		return p.Content
	end

	-- sections ----------------------------------------------------------------------------------------
	local themeOptions = {}
	for _, t in Themes.List() do
		table.insert(themeOptions, { Id = t.Id, Text = pick(t.Name) })
	end
	local hudOptions = {}
	for _, id in Themes.HudIds do
		table.insert(hudOptions, { Id = id, Text = pick(Themes.GetHud(id).Name) })
	end
	local qualityOptions = {}
	for _, q in QUALITY do
		table.insert(qualityOptions, { Id = q, Text = L("set.quality." .. q) })
	end
	local langOptions = {}
	for _, lang in LANGS do
		table.insert(langOptions, { Id = lang, Text = if lang == "auto" then L("set.lang.auto") else L("ui.lang." .. lang) })
	end

	-- "now showing" info card at the bottom of a panel: title, description and a colour strip
	local function infoCard(content: Frame, title: string, text: string, colors: { Color3 }, _order: number)
		-- sits at the bottom of the panel, outside the content's list flow
		local panelRoot = (content.Parent :: Instance) :: Frame
		local pad = if phone then 10 else 16
		local card = Common.Well(theme, { Name = "InfoCard", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, pad, 1, -pad), Size = UDim2.new(1, -pad * 2, 0, if phone then 56 else 132), ZIndex = 9 })
		card.Parent = panelRoot
		local strip = frame({ Name = "Strip", Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 0, if phone then 8 else 12), Parent = card })
		local sl = UIKit.ListLayout(strip, { Horizontal = true, Gap = 0 })
		sl.HorizontalFlex = Enum.UIFlexAlignment.Fill
		for i, col in colors do
			local seg = frame({ Name = "Seg", BackgroundTransparency = 0, BackgroundColor3 = col, Size = UDim2.new(0, 10, 1, 0), LayoutOrder = i, Parent = strip })
			seg.BorderSizePixel = 0
		end
		UIKit.Label(theme, { Name = "Caption", Text = UIKit.Upper(L("set.previewTitle")) .. "  ·  " .. title, Role = "Caption", Tone = "Accent", Position = UDim2.fromOffset(12, if phone then 24 else 32), Size = UDim2.new(1, -24, 0, 18), Truncate = true, Parent = card })
		if not phone then
			UIKit.Label(theme, { Name = "Text", Text = text, Role = "Small", Tone = "Dim", Wrap = true, YAlign = "Top", Scaled = true, MaxTextSize = if theme.Id == "Classic" then 9 else theme.TextSize.Small, MinTextSize = 7, Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -24, 1, -64), Parent = card })
		end
	end

	local function presetCard(content: Frame, order: number)
		local presets = Common.Module({ "Graphics", "Presets" })
		local id = tostring(get("GraphicsPreset") or "MapDefault")
		local p = if presets and id ~= "MapDefault" then presets.Get(id) else nil
		if p == nil then
			infoCard(content, L("set.preset.MapDefault"), L("set.desc.GraphicsPreset"), { Color3.fromRGB(226, 182, 84), Color3.fromRGB(110, 150, 230), Color3.fromRGB(120, 90, 255), Color3.fromRGB(220, 30, 45), Color3.fromRGB(66, 252, 255) }, order)
			return
		end
		local colors: { Color3 } = {}
		local function add(v: any)
			if typeof(v) == "Color3" and #colors < 6 then
				table.insert(colors, v)
			end
		end
		local lighting = p.Lighting or {}
		add(lighting.Ambient)
		add(lighting.OutdoorAmbient)
		add(lighting.ColorShift_Top)
		add(p.Atmosphere and p.Atmosphere.Color)
		add(p.Atmosphere and p.Atmosphere.Decay)
		add(p.ColorCorrection and p.ColorCorrection.TintColor)
		if #colors == 0 then
			colors = { theme.Colors.Accent }
		end
		infoCard(content, pick(p.Name), if p.Desc then pick(p.Desc) else "", colors, order)
	end

	local function themeCard(content: Frame, order: number)
		local t = Themes.Get(tostring(get("MenuTheme") or theme.Id))
		local tc = t.Colors
		infoCard(content, pick(t.Name), pick(t.Desc), { tc.Background, tc.Panel, tc.Stroke, tc.Accent, tc.Accent2, tc.SoulRed }, order)
	end

	local function graphics(content: Frame)
		dropdown(content, "GraphicsPreset", presetOptions(), 1)
		cycle(content, "GraphicsQuality", qualityOptions, 2)
		slider(content, "ParticleDensity", 0, 2, 0.1, function(v: number): string
			return L("set.mult", string.format("%.1f", v))
		end, 3)
		cycle(content, "RigStyle", rigOptions(), 4)
		presetCard(content, 10)
	end
	local function interface(content: Frame)
		cycle(content, "MenuTheme", themeOptions, 1)
		cycle(content, "HudStyle", hudOptions, 2)
		cycle(content, "Language", langOptions, 3)
		toggle(content, "DamageNumbers", 4)
		if spec("ColorblindPatterns") then
			toggle(content, "ColorblindPatterns", 5)
		end
		if spec("ReducedFlashes") then
			toggle(content, "ReducedFlashes", 6)
		end
		themeCard(content, 10)
	end
	local function audio(content: Frame)
		slider(content, "MusicVolume", 0, 1, 0.05, pct, 1)
		slider(content, "SfxVolume", 0, 1, 0.05, pct, 2)
	end
	local function camera(content: Frame)
		slider(content, "CameraShake", 0, 2, 0.1, pct, 1)
		slider(content, "FieldOfView", 50, 100, 1, function(v: number): string
			return L("set.degrees", math.floor(v + 0.5))
		end, 2)
		slider(content, "Sensitivity", 0.1, 5, 0.05, function(v: number): string
			return L("set.mult", string.format("%.2f", v))
		end, 3)
		toggle(content, "CameraLock", 4)
		toggle(content, "InvertY", 5)
		toggle(content, "QuickCast", 6)
	end

	local descH = if phone then 0 else 86
	local panelsH = bodyH - descH - (if phone then 0 else gap)
	if phone then
		-- phones: one section at a time
		local tabs = UIKit.Tabs(theme, {
			Items = {
				{ Id = "Graphics", Text = L("set.section.graphics") },
				{ Id = "Interface", Text = L("set.section.interface") },
				{ Id = "Audio", Text = L("set.section.audio") },
			},
			Selected = section,
			Height = 34,
			Size = UDim2.fromOffset(640, 34),
			OnChanged = function(id: string)
				if d.UI and type(d.UI.Open) == "function" and id ~= section then
					d.UI.Open("Settings", { Section = id, Replace = true })
				end
			end,
		})
		tabs.Root.Parent = body
		local y = 42
		local h = bodyH - y
		if section == "Graphics" then
			graphics(panel("Graphics", "set.section.graphics", "Sparkle", 0, y, bodyW, h))
		elseif section == "Interface" then
			interface(panel("Interface", "set.section.interface", "Palette", 0, y, bodyW, h))
		else
			local half = math.floor((bodyW - gap) / 2)
			audio(panel("Audio", "set.section.audio", "Music", 0, y, half, h))
			camera(panel("Camera", "set.section.camera", "Camera", half + gap, y, bodyW - half - gap, h))
		end
	else
		local colW = math.floor((bodyW - gap * 2) / 3)
		local audioH = math.floor(panelsH * 0.36)
		graphics(panel("Graphics", "set.section.graphics", "Sparkle", 0, 0, colW, panelsH))
		interface(panel("Interface", "set.section.interface", "Palette", colW + gap, 0, colW, panelsH))
		audio(panel("Audio", "set.section.audio", "Music", (colW + gap) * 2, 0, bodyW - (colW + gap) * 2, audioH))
		camera(panel("Camera", "set.section.camera", "Camera", (colW + gap) * 2, audioH + gap, bodyW - (colW + gap) * 2, panelsH - audioH - gap))
		-- description + reset
		local box = UIKit.Panel(theme, { Name = "Describe", Variant = "Dialogue", Padding = 16, Shadow = false, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, -310, 0, descH) })
		box.Root.Parent = body
		local label = UIKit.Label(theme, { Name = "Text", Text = "", Role = "Body", Wrap = true, YAlign = "Top", Size = UDim2.fromScale(1, 1), LineHeight = theme.LineHeight, Parent = box.Content })
		desc = label
		describe("GraphicsPreset")
		UIKit.Button(theme, {
			Name = "Reset",
			Text = L("set.reset"),
			Icon = "Refresh",
			Variant = "Secondary",
			Height = 50,
			Width = 280,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 0, 1, -math.floor((descH - 50) / 2)),
			Parent = body,
			OnActivated = function()
				local ui = d.UI
				if ui and type(ui.ResetSettings) == "function" then
					ui.ResetSettings()
				end
			end,
		})
	end

	return {
		Root = root,
		DefaultSelection = first or screen.Back,
		OnAction = function(action: string): boolean
			if phone and (action == "PrevTab" or action == "NextTab") then
				local order = { "Graphics", "Interface", "Audio" }
				local idx = table.find(order, section) or 1
				idx = ((idx - 1 + (if action == "NextTab" then 1 else -1)) % #order) + 1
				if d.UI and type(d.UI.Open) == "function" then
					d.UI.Open("Settings", { Section = order[idx], Replace = true })
				end
				return true
			end
			return false
		end,
		Destroy = function()
			screen.Destroy()
		end,
	}
end

return Settings
