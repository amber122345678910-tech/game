--!nocheck
-- UI core: every theme builds every UIKit component (all variants / states / kinds), every icon (Kits.IconNames +
-- Icons.Names()), the HUD-style bars, and the Gallery screen (every page, desktop + phone, en + ru).
-- Lune validates property names / enum items, so a wrong property in a builder fails here.

local UI = "src/client/UI/"

local function setup(Loader)
	Loader.isServer = false
	Loader.quietWarnings = true
	local Themes = Loader.requirePath(UI .. "Themes")
	local UIKit = Loader.requirePath(UI .. "UIKit")
	local Icons = Loader.requirePath(UI .. "Icons")
	local UIRoot = Loader.requirePath(UI .. "UIRoot")
	local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
	local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
	return Themes, UIKit, Icons, UIRoot, Strings, Kits
end

local function destroyHandle(h)
	if type(h) == "table" and type(h.Destroy) == "function" then
		h.Destroy()
	elseif typeof(h) == "Instance" then
		h:Destroy()
	end
end

-- builds every component once in `theme`; returns the number of builders exercised
local function buildAll(T, UIKit, Themes, theme, Kits)
	local n = 0
	local function try(name, fn)
		n += 1
		local ok, result = pcall(fn)
		T.ok(ok, theme.Id .. " " .. name .. ": " .. tostring(result))
		if ok then
			pcall(destroyHandle, result)
		end
	end
	local c = theme.Colors
	try("Label", function()
		local l = UIKit.Label(theme, { Text = "Hello", Role = "Body", Dialogue = true, Wrap = true, Upper = true, Stroke = { Thickness = 1 }, Scaled = true, Truncate = true })
		for _, role in { "Title", "Heading", "Subtitle", "Caption", "Small", "Number", "Mono", "Display", "Button" } do
			UIKit.Label(theme, { Text = role, Role = role, Tone = "Dim", AutoSize = "X", Parent = l })
		end
		return l
	end)
	try("Title", function()
		return UIKit.Title(theme, { Text = "Soul Verdict", Role = "Display", Subtitle = "sub", XAlign = "Center" })
	end)
	try("Divider", function()
		local f = UIKit.Divider(theme, { Ornament = true })
		UIKit.Divider(theme, { Vertical = true, Parent = f })
		return f
	end)
	try("Backdrop", function()
		return UIKit.Backdrop(theme, {})
	end)
	for _, variant in { "Default", "Alt", "Inset", "Glass", "Accent", "Dialogue" } do
		try("Panel " .. variant, function()
			return UIKit.Panel(theme, { Variant = variant, Title = variant, TitleIcon = "Star", Layout = "Vertical", Gap = 6, AutoSize = "Y", Clip = true })
		end)
	end
	try("List", function()
		local l = UIKit.List(theme, { Gap = 4, Horizontal = true })
		l.Add(UIKit.Label(theme, { Text = "row" }))
		l.Clear()
		return l
	end)
	try("Grid", function()
		local g = UIKit.Grid(theme, { CellSize = UDim2.fromOffset(40, 40), Scroll = true })
		g.Add(UIKit.Icon("Heart", c.SoulRed, 20))
		return g
	end)
	try("Modal", function()
		return UIKit.Modal(theme, { Title = "Modal", Buttons = { { Text = "A", Variant = "Ghost" }, { Text = "B", Variant = "Primary", Icon = "Gold" } } })
	end)
	try("Tooltip", function()
		return UIKit.Tooltip(theme, { Title = "Tip", Text = "Body", Tags = { "KR", "Beam" }, Stats = { { Label = "Cooldown", Value = "9s", Icon = "Clock" } } })
	end)
	for _, kind in { "Info", "Success", "Warning", "Danger", "Reward" } do
		try("Toast " .. kind, function()
			return UIKit.Toast(theme, { Text = kind, Kind = kind })
		end)
	end
	for _, variant in { "Primary", "Secondary", "Ghost", "Danger", "Icon" } do
		for _, state in { "Normal", "Hover", "Pressed", "Disabled", "Selected" } do
			try("Button " .. variant .. "/" .. state, function()
				local b = UIKit.Button(theme, { Text = "Play", Icon = "Play", Variant = variant, State = state, Hint = "Enter", Disabled = state == "Disabled" })
				b.SetText("Again")
				b.SetSelected(true)
				b.SetDisabled(false)
				b.SetState("Hover")
				return b
			end)
		end
	end
	try("Toggle", function()
		local t = UIKit.Toggle(theme, { Label = "Toggle", Value = true, State = "Hover" })
		t.Set(false)
		T.eq(t.Get(), false, "toggle value")
		return t
	end)
	try("Slider", function()
		local s = UIKit.Slider(theme, { Label = "Slider", Value = 0.4, Min = 0, Max = 1, Step = 0.1 })
		s.Set(0.75)
		return s
	end)
	try("Cycle", function()
		local cy = UIKit.Cycle(theme, { Label = "Cycle", Options = { "A", "B", "C" }, Index = 2, Dots = true })
		cy.Set(3)
		T.eq(cy.Get(), 3, "cycle index")
		return cy
	end)
	try("Dropdown", function()
		local dd = UIKit.Dropdown(theme, { Label = "Dropdown", Options = { { Id = "a", Text = "A" }, { Id = "b", Text = "B" } }, Index = 1 })
		dd.Open()
		dd.Close()
		return dd
	end)
	try("Tabs", function()
		local tb = UIKit.Tabs(theme, { Items = { { Id = "x", Text = "X", Icon = "Star" }, { Id = "y", Text = "Y" } }, Selected = "x" })
		tb.Select("y")
		T.eq(tb.Selected(), "y", "tabs selection")
		return tb
	end)
	try("Heart+Cursor", function()
		local h = UIKit.Heart(c.SoulRed, 24, true)
		UIKit.Cursor(theme).Parent = h
		return h
	end)
	for _, kind in { "HP", "Guard", "Ult", "Exp", "Dodge", "Monster", "Custom" } do
		try("Bar " .. kind, function()
			local b = UIKit.Bar(theme, { Kind = kind, Value = 40, Max = 100, Secondary = 10, Label = kind, ShowValue = true, Segments = if kind == "Dodge" then 6 else nil, Ghost = true })
			b.Set(60, 100, 5)
			b.SetColor(c.Accent)
			return b
		end)
		for _, hudId in Themes.HudIds do
			try("Bar " .. kind .. " hud " .. hudId, function()
				return UIKit.Bar(theme, { Kind = kind, Value = 3, Max = 6, Hud = Themes.GetHud(hudId), Label = kind })
			end)
		end
	end
	try("Card", function()
		local kit = Kits.Get("ClassicSans")
		local card = UIKit.Card(theme, { Name = "Sans", Title = "The Judge", Color = kit.Color, Icon = "Blaster", Role = "Monster", RoleMonster = true, Difficulty = 2, Tags = { "KR", "Beam" }, Price = 1200, Locked = true, Selected = true, State = "Hover" })
		card.SetSelected(false)
		card.SetLocked(false)
		return card
	end)
	for _, style in { "Solid", "Outline", "Soft" } do
		try("Badge " .. style, function()
			return UIKit.Badge(theme, { Text = "KR", Icon = "Skull", Color = c.KR, Style = style })
		end)
	end
	for _, key in { "E", "Shift", "M1", "Enter", "ButtonA", "ButtonB", "ButtonL1", "DPadUp", "Backspace" } do
		try("KeyHint " .. key, function()
			return UIKit.KeyHint(theme, { Key = key, Label = "Do" })
		end)
	end
	try("StatRow", function()
		return UIKit.StatRow(theme, { Label = "Wins", Value = 12, Icon = "Trophy", Fill = 0.4 })
	end)
	try("Countdown", function()
		local cd = UIKit.Countdown(theme, { Seconds = 75, Format = "Clock", Label = "Round" })
		cd.Set(5)
		return cd
	end)
	try("Viewport", function()
		local v = UIKit.Viewport(theme, { Color = c.Accent })
		v.SetModel(nil)
		return v
	end)
	try("LinkSelection", function()
		local a = UIKit.Button(theme, { Text = "A" })
		local b = UIKit.Button(theme, { Text = "B" })
		UIKit.LinkSelection({ a.Root, b.Root }, "Vertical", true)
		UIKit.LinkSelection({ a.Root, b.Root }, "Horizontal")
		b.Root.Parent = a.Root
		return a
	end)
	return n
end

return {
	everyComponentInEveryTheme = function(T, Loader)
		local Themes, UIKit, _, _, Strings, Kits = setup(Loader)
		for _, lang in { "en", "ru" } do
			Strings.SetLanguage(lang)
			for _, theme in Themes.List() do
				local n = buildAll(T, UIKit, Themes, theme, Kits)
				T.ok(n > 60, "exercised builders: " .. n)
			end
		end
		Strings.SetLanguage("en")
		T.eq(#Themes.List(), 4, "four menu themes")
	end,

	everyKitIconExistsAndBuilds = function(T, Loader)
		local Themes, _, Icons, _, _, Kits = setup(Loader)
		for _, name in Kits.IconNames do
			T.ok(Icons.Has(name), "Icons implements kit icon " .. name)
		end
		-- every icon referenced by kit data (abilities + passives) too
		for _, kit in Kits.All() do
			for _, a in kit.Abilities do
				T.ok(Icons.Has(a.Icon), kit.Id .. "." .. a.Id .. " icon " .. tostring(a.Icon))
			end
			for _, p in kit.Passives do
				T.ok(Icons.Has(p.Icon), kit.Id .. " passive icon " .. tostring(p.Icon))
			end
		end
		for _, theme in Themes.List() do
			for _, name in Icons.Names() do
				local ok, icon = pcall(Icons.Create, name, theme.Colors.Accent, 32, theme.Colors.Accent2)
				T.ok(ok and icon ~= nil and #icon:GetChildren() > 1, theme.Id .. " icon " .. name .. ": " .. tostring(icon))
				if ok then
					icon:Destroy()
				end
			end
		end
	end,

	galleryEveryPageEveryTheme = function(T, Loader)
		local Themes, _, _, UIRoot, Strings = setup(Loader)
		local Gallery = Loader.requirePath(UI .. "Gallery")
		local roblox = Loader.roblox
		local layouts = {
			desktop = UIRoot.ComputeLayout(roblox.Vector2.new(1920, 1080)),
			phone = UIRoot.ComputeLayout(roblox.Vector2.new(844, 390)),
		}
		for _, lang in { "en", "ru" } do
			Strings.SetLanguage(lang)
			for _, theme in Themes.List() do
				for lname, layout in layouts do
					for _, page in { "All", "Controls", "Data", "Icons", "Overlay" } do
						if not (layout.Compact and page == "All") then
							local ok, handle = pcall(Gallery.Create, theme, { Layout = layout, Page = page })
							T.ok(ok and handle and handle.Root, ("Gallery %s %s %s %s: %s"):format(theme.Id, lname, page, lang, tostring(handle)))
							if ok and handle then
								T.noerror(function()
									handle.SetPage("Controls")
									handle.Destroy()
								end, "gallery destroy")
							end
						end
					end
				end
			end
		end
		Strings.SetLanguage("en")
	end,

	themesAndLayoutContracts = function(T, Loader)
		local Themes, _, _, UIRoot = setup(Loader)
		local roblox = Loader.roblox
		for _, theme in Themes.List() do
			for _, role in { "Display", "Title", "Heading", "Subtitle", "Body", "Button", "Caption", "Number", "Mono" } do
				T.ok(Themes.Font(theme, role, "en") ~= nil and Themes.Font(theme, role, "ru") ~= nil, theme.Id .. " font " .. role)
			end
			for _, rarity in { "Common", "Rare", "Epic", "Legendary" } do
				T.ok(typeof(Themes.Rarity(theme, rarity)) == "Color3", theme.Id .. " rarity " .. rarity)
			end
		end
		local desk = UIRoot.ComputeLayout(roblox.Vector2.new(1920, 1080))
		T.near(desk.Scale, 1.2, 1e-3, "1080p scale")
		T.ok(not desk.Phone and not desk.Compact, "1080p is desktop")
		local phone = UIRoot.ComputeLayout(roblox.Vector2.new(844, 390))
		T.ok(phone.Phone and phone.Compact, "844x390 is a compact phone layout")
	end,
}
