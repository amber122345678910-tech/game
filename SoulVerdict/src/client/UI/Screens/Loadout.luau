--!strict
-- Screens/Loadout ("Play/Loadout", SPEC §10): pick the kit you play as Monster and as Human.
--   * role tabs (Monsters / Humans), kit carousel (UIKit.Card per kit; locked kits show their price),
--   * hero ViewportFrame with the real 3D rig (RigBuilder.Build(kit.Rig, {Skin}), "Pockets" pose for
--     skeletons / "Ready" for humans, slow turntable, drag to spin),
--   * kit header (name, title, difficulty, playstyle, core stats) with EQUIP / UNLOCK, "Try in training room"
--     (Request TryKit) and PRACTICE (modal -> Request StartPractice {side}),
--   * ability list: icon, slot key, name, cooldown, HOLD/ULT/CORE markers, tag badges (KR, Blue, Orange...),
--     description and the key Numbers; built-in Verdict Box (monsters), Block/Parry + Dash (humans); passives,
--   * skin selector (swatches with rarity rings; preview on the rig; EQUIP / BUY / mastery lock),
--   * role preference (Request SetRolePref) and the player's live MonsterChance %.
--
--   Loadout.Create(theme, deps) -> { Root, Destroy, DefaultSelection, OnAction(action), Select(kitId) }
--   deps: State, UI, Input, Layout (+ offline: Profile, Attrs, Role "Monster"|"Human", Kit, Skin)
-- Requests: EquipKit {kitId, role}, EquipSkin {kitId, skinId}, Buy {kind="Kit"|"Skin", kitId, skinId?},
--           SetRolePref {pref}, TryKit {kitId}, StartPractice {side}.

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Icons = require(script.Parent.Parent.Icons)
local Motion = require(script.Parent.Parent.Motion)
local Common = require(script.Parent.Common)

type Theme = Themes.Theme

local Loadout = {}

local L = Common.L
local pick = Common.Pick
local frame = Common.Frame

local SLOT_ORDER: { [string]: number } = { M1 = 1, Q = 2, E = 3, R = 4, T = 5, Shift = 6, F = 7, G = 8 }
local BLUE_RULE = Color3.fromRGB(20, 169, 255)
local ORANGE_RULE = Color3.fromRGB(255, 160, 0)
local NUMBER_KEYS = { "Damage", "KR", "Heal", "HealPerSecond", "Radius", "Range", "Distance", "Duration", "Stun" }
local DISTANCE_KEYS: { [string]: boolean } = { Radius = true, Range = true, Distance = true }
local TIME_KEYS: { [string]: boolean } = { Duration = true, Stun = true }

type Entry = {
	Id: string,
	Slot: string?,
	Name: string,
	Desc: string,
	Icon: string,
	Cooldown: number?,
	Tags: { string },
	Numbers: { [string]: number }?,
	Range: number?,
	Ult: boolean,
	Hold: boolean,
	Builtin: boolean,
	Passive: boolean,
}

-- ability entries for a kit (data + the built-in slots every role has) ------------------------------------
local function entries(kit: any): { Entry }
	local out: { Entry } = {}
	for _, a in kit.Abilities do
		table.insert(out, {
			Id = a.Id,
			Slot = a.Slot,
			Name = pick(a.Name),
			Desc = pick(a.Desc),
			Icon = a.Icon,
			Cooldown = a.Cooldown,
			Tags = a.Tags or {},
			Numbers = a.Numbers,
			Range = a.Range,
			Ult = a.Ult == true,
			Hold = a.Hold ~= nil,
			Builtin = false,
			Passive = false,
		})
	end
	local config = Common.Config()
	if kit.Role == "Monster" then
		local cd = config and config.VerdictBox and config.VerdictBox.Cooldown or 40
		table.insert(out, { Id = "VerdictBox", Slot = "F", Name = L("scr.loadout.box.name"), Desc = L("scr.loadout.box.desc"), Icon = "Box", Cooldown = cd, Tags = { "Control" }, Ult = false, Hold = false, Builtin = true, Passive = false })
	else
		table.insert(out, { Id = "Block", Slot = "F", Name = L("scr.loadout.block.name"), Desc = L("scr.loadout.block.desc"), Icon = "Shield", Tags = { "Shield" }, Ult = false, Hold = true, Builtin = true, Passive = false })
		table.insert(out, { Id = "Dash", Slot = "Shift", Name = L("scr.loadout.dash.name"), Desc = L("scr.loadout.dash.desc"), Icon = "Dash", Tags = { "Mobility" }, Ult = false, Hold = false, Builtin = true, Passive = false })
	end
	table.sort(out, function(a, b)
		return (SLOT_ORDER[a.Slot or ""] or 99) < (SLOT_ORDER[b.Slot or ""] or 99)
	end)
	for _, p in kit.Passives or {} do
		table.insert(out, { Id = p.Id, Slot = nil, Name = pick(p.Name), Desc = pick(p.Desc), Icon = p.Icon, Tags = {}, Ult = false, Hold = false, Builtin = false, Passive = true })
	end
	return out
end

local function fmt(n: number): string
	if n == math.floor(n) then
		return tostring(n)
	end
	return string.format("%.1f", n)
end

local function hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- "DMG 7/7/12 · KR 3 · RANGE 6 st" (rich text, values tinted)
local function numbersText(theme: Theme, e: Entry, max: number): string
	local nums = e.Numbers
	if nums == nil then
		return ""
	end
	local parts: { string } = {}
	local valueColor = hex(theme.Colors.Text)
	local function add(key: string, value: string)
		if #parts < max then
			table.insert(parts, L("scr.num." .. key) .. ' <font color="' .. valueColor .. '">' .. value .. "</font>")
		end
	end
	if nums.Damage1 then
		local seq = {}
		for i = 1, 4 do
			local v = nums["Damage" .. i]
			if v then
				table.insert(seq, fmt(v))
			end
		end
		add("Damage", table.concat(seq, "/"))
	end
	local hadDistance = false
	for _, key in NUMBER_KEYS do
		local v = nums[key]
		if v and not (key == "Damage" and nums.Damage1) then
			if DISTANCE_KEYS[key] then
				if not hadDistance then
					hadDistance = true
					add(key, L("scr.unit.studs", fmt(v)))
				end
			elseif TIME_KEYS[key] then
				add(key, L("scr.unit.sec", fmt(v)))
			else
				add(key, fmt(v))
			end
		end
	end
	if not hadDistance and e.Range and #parts < max then
		add("Range", L("scr.unit.studs", fmt(e.Range)))
	end
	return table.concat(parts, "   ")
end

local function tagBadge(theme: Theme, tag: string, h: number, order: number): Frame
	local c = theme.Colors
	local color: Color3 = c.TextDim
	local style = "Outline"
	if tag == "KR" then
		color, style = c.KR, "Solid"
	elseif tag == "Blue" then
		color, style = BLUE_RULE, "Solid"
	elseif tag == "Orange" then
		color, style = ORANGE_RULE, "Solid"
	elseif tag == "Ultimate" then
		color, style = c.Ult, "Soft"
	end
	local key = "tag." .. tag
	return UIKit.Badge(theme, {
		Text = if Common.Has(key) then L(key) else tag,
		Color = color,
		Style = style,
		Height = h,
		TextSize = if theme.Id == "Classic" then 7 else math.floor(h * 0.6),
		LayoutOrder = order,
	})
end

-- one ability row/tile
local function abilityTile(theme: Theme, kit: any, e: Entry, size: Vector2, compact: boolean, order: number): Frame
	local c = theme.Colors
	local tile = Common.Well(theme, { Name = "Ability_" .. e.Id, Size = UDim2.fromOffset(size.X, size.Y), LayoutOrder = order })
	if e.Ult then
		Common.Stroke(tile, c.Ult, if theme.Id == "Classic" then 2 else 1.5, if theme.Id == "Classic" then 0 else 0.25, theme.LineJoin).Name = "UltRing"
		local ultStroke = tile:FindFirstChildOfClass("UIStroke")
		if ultStroke and ultStroke.Name ~= "UltRing" then
			ultStroke:Destroy()
		end
	end
	local pad = if compact then 8 else 10
	local iconSize = math.min(size.Y - pad * 2, if compact then 46 else 60)
	-- icon well
	local iconWell = frame({
		Name = "IconWell",
		BackgroundTransparency = 0,
		BackgroundColor3 = kit.Color:Lerp(c.PanelInset, if theme.Id == "Classic" then 0.85 else 0.62),
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(iconSize, iconSize),
		Parent = tile,
	})
	Common.Corner(iconWell, if theme.Id == "Void" then UDim.new(0, 10) elseif theme.Id == "Royal" then UDim.new(0, 6) else theme.SmallCorner)
	Common.Stroke(iconWell, if e.Ult then c.Ult else kit.Color, if theme.Id == "Classic" then 2 else 1, if theme.Id == "Classic" then 0 else 0.35, theme.LineJoin)
	local icon = Icons.Create(if Icons.Has(e.Icon) then e.Icon else "Info", kit.Color:Lerp(Color3.new(1, 1, 1), 0.2), UDim2.fromScale(0.64, 0.64), kit.Color:Lerp(Color3.new(1, 1, 1), 0.7))
	icon.Position = UDim2.fromScale(0.5, 0.46)
	icon.Parent = iconWell
	-- slot key (or passive marker) on the icon's lower edge
	if e.Slot then
		local key = UIKit.KeyHint(theme, { Key = e.Slot, Height = if compact then 18 else 20, AnchorPoint = Vector2.new(0.5, 0.5) })
		key.AnchorPoint = Vector2.new(0.5, 0.5)
		key.Position = UDim2.new(0.5, 0, 1, -1)
		key.ZIndex = 4
		key.Parent = iconWell
	else
		local mark = UIKit.Badge(theme, { Text = UIKit.Upper(L("scr.loadout.passives")), Color = c.Accent2, Style = "Soft", Height = 16, TextSize = if theme.Id == "Classic" then 6 else 9 })
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.new(0.5, 0, 1, -1)
		mark.Parent = iconWell
	end
	local textX = pad + iconSize + (if compact then 10 else 14)
	local textW = size.X - textX - pad
	-- line 1: name + markers + cooldown
	local line1 = frame({ Name = "Line1", Position = UDim2.fromOffset(textX, pad - 2), Size = UDim2.fromOffset(textW, if compact then 18 else 22), Parent = tile })
	local l1 = UIKit.ListLayout(line1, { Horizontal = true, Gap = 6, VAlign = Enum.VerticalAlignment.Center })
	l1.Wraps = false
	UIKit.Label(theme, {
		Name = "Name",
		Text = e.Name,
		Role = "Heading",
		TextSize = if theme.Id == "Classic" then (if compact then 10 else 12) else (if compact then 15 else 17),
		Color = if e.Ult then c.Ult elseif e.Passive then c.Accent2 else c.Text,
		AutoSize = "X",
		LayoutOrder = 1,
		Parent = line1,
	}).Size = UDim2.new(0, 0, 1, 0)
	local markerH = if compact then 15 else 17
	if e.Ult then
		UIKit.Badge(theme, { Text = L("scr.loadout.ult"), Color = c.Ult, Style = "Solid", Height = markerH, TextSize = if theme.Id == "Classic" then 7 else 10, LayoutOrder = 2, Parent = line1 })
	end
	if e.Hold then
		UIKit.Badge(theme, { Text = L("scr.loadout.hold"), Color = c.Info, Style = "Outline", Height = markerH, TextSize = if theme.Id == "Classic" then 7 else 10, LayoutOrder = 3, Parent = line1 })
	end
	if e.Builtin then
		UIKit.Badge(theme, { Text = L("scr.loadout.builtin"), Color = c.TextMuted, Style = "Outline", Height = markerH, TextSize = if theme.Id == "Classic" then 7 else 10, LayoutOrder = 4, Parent = line1 })
	end
	if e.Cooldown and not e.Passive then
		local cd = frame({ Name = "Cooldown", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, pad - 2), Size = UDim2.fromOffset(70, if compact then 18 else 22), Parent = tile })
		cd.Position = UDim2.new(1, -pad, 0, pad - 2)
		local clock = Icons.Create("Clock", c.TextDim, if compact then 12 else 14)
		clock.AnchorPoint = Vector2.new(1, 0.5)
		clock.Position = UDim2.new(1, -38, 0.5, 0)
		clock.Parent = cd
		UIKit.Label(theme, {
			Name = "Seconds",
			Text = L("scr.loadout.cd", fmt(e.Cooldown)),
			Role = "Number",
			TextSize = if theme.Id == "Classic" then 9 else (if compact then 12 else 14),
			Tone = "Dim",
			XAlign = "Right",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 34, 1, 0),
			Parent = cd,
		})
		line1.Size = UDim2.fromOffset(textW - 76, line1.Size.Y.Offset)
	end
	-- line 2: description (scaled to fit)
	local tagsH = if compact then 16 else 18
	local line1H = if compact then 18 else 22
	local descTop = pad - 2 + line1H + 2
	local descH = size.Y - descTop - pad - tagsH - 4
	UIKit.Label(theme, {
		Name = "Desc",
		Text = e.Desc,
		Role = "Small",
		Tone = "Dim",
		Wrap = true,
		YAlign = "Top",
		Scaled = true,
		MaxTextSize = if theme.Id == "Classic" then (if compact then 7 else 8) else (if compact then 12 else 14),
		MinTextSize = if theme.Id == "Classic" then 6 else 9,
		LineHeight = 1.12,
		Position = UDim2.fromOffset(textX, descTop),
		Size = UDim2.fromOffset(textW, math.max(descH, 14)),
		Parent = tile,
	})
	-- line 3: tag badges + numbers
	local line3 = frame({ Name = "Line3", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, textX, 1, -pad + 1), Size = UDim2.fromOffset(textW, tagsH), Parent = tile })
	UIKit.ListLayout(line3, { Horizontal = true, Gap = 5, VAlign = Enum.VerticalAlignment.Center })
	local shown = 0
	for i, tag in e.Tags do
		if tag ~= "Ultimate" and shown < (if compact then 2 else 3) then
			shown += 1
			tagBadge(theme, tag, tagsH, i).Parent = line3
		end
	end
	local nums = numbersText(theme, e, if compact then 2 else 3)
	if nums ~= "" then
		local numLabel = UIKit.Label(theme, {
			Name = "Numbers",
			Text = nums,
			RichText = true,
			Role = "Caption",
			TextSize = if theme.Id == "Classic" then 7 else (if compact then 11 else 12),
			Tone = "Muted",
			AutoSize = "X",
			LayoutOrder = 20,
			Parent = line3,
		})
		numLabel.Size = UDim2.new(0, 0, 1, 0)
		local spacer = frame({ Name = "Spacer", Size = UDim2.fromOffset(4, 1), LayoutOrder = 19, Parent = line3 })
		spacer.Visible = shown > 0
	end
	return tile
end

-- difficulty pips (hearts in Classic)
local function difficulty(theme: Theme, level: number, h: number): Frame
	local c = theme.Colors
	local row = frame({ Name = "Difficulty", Size = UDim2.fromOffset(h * 3 + 8, h) })
	UIKit.ListLayout(row, { Horizontal = true, Gap = 4, VAlign = Enum.VerticalAlignment.Center })
	for i = 1, 3 do
		local on = i <= level
		local pip: Frame
		if theme.Id == "Classic" then
			pip = UIKit.Heart(if on then c.SoulRed else c.StrokeDim, h)
			pip.AnchorPoint = Vector2.zero
			pip.Position = UDim2.new()
		else
			pip = frame({ Name = "Pip", BackgroundTransparency = if on then 0 else 0.5, BackgroundColor3 = if on then c.Accent2 else c.StrokeDim, Size = UDim2.fromOffset(h * 0.7, h * 0.7), Rotation = if theme.Id == "Void" then 0 else 45 })
			if theme.Id == "Void" then
				Common.Corner(pip, UDim.new(0.5, 0))
			end
		end
		pip.LayoutOrder = i
		pip.Parent = row
	end
	return row
end

function Loadout.Create(theme: Theme, deps: any): any
	local d = deps or {}
	local c = theme.Colors
	local kits = Common.Kits()
	local screen = Common.Screen(theme, d, {
		Name = "Loadout",
		Title = L("scr.loadout.title"),
		Subtitle = L("scr.loadout.subtitle"),
		Icon = "Swords",
		Hints = { { Action = "PrevTab" }, { Action = "NextTab", Label = L("scr.switchTab") } },
	})
	local root, body, bag = screen.Root, screen.Body, screen.Bag
	local phone = screen.Phone
	local compact = screen.Compact
	local canvas = screen.Canvas
	local bodyW = canvas.X - screen.Margin * 2
	local bodyH = body.Size.Y.Offset + canvas.Y * body.Size.Y.Scale

	-- state -------------------------------------------------------------------------------------------
	local profile = Common.Profile(d)
	local role: string = d.Role or (if Common.PlayerAttr(d, "Role", "Lobby") == "Monster" then "Monster" else "Human")
	if d.Role == nil and profile and profile.RolePreference == "Monster" then
		role = "Monster"
	end
	local pendingEquip: { [string]: string } = {}
	local pendingSkin: { [string]: string } = {}
	local selectedKit: string = d.Kit or Common.EquippedKit(profile, role) or ""
	local previewSkin: { [string]: string } = {}
	if d.Skin and d.Kit then
		previewSkin[d.Kit] = d.Skin
	end
	local modal: any = nil

	local function equippedKit(r: string): string?
		return pendingEquip[r] or Common.EquippedKit(profile, r)
	end
	local function equippedSkin(kit: any): string
		return pendingSkin[kit.Id] or Common.EquippedSkin(profile, kit)
	end
	local function shownSkin(kit: any): string
		return previewSkin[kit.Id] or equippedSkin(kit)
	end

	-- layout --------------------------------------------------------------------------------------------
	local topH = if phone then 34 else 46
	local gap = screen.Gap
	local carouselH = if phone then 64 else 164
	local mainY = topH + gap
	local mainH = bodyH - topH - carouselH - gap * 2
	local leftW = if phone then 250 else 420
	local rightW = bodyW - leftW - gap

	local topBar = frame({ Name = "TopBar", Size = UDim2.new(1, 0, 0, topH), Parent = body })
	local main = frame({ Name = "Main", Position = UDim2.fromOffset(0, mainY), Size = UDim2.new(1, 0, 0, mainH), Parent = body })
	local carousel = frame({ Name = "Carousel", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, carouselH), Parent = body })

	-- hero panel (left): 3D rig + skins
	local hero = UIKit.Panel(theme, { Name = "Hero", Size = UDim2.fromOffset(leftW, mainH), Padding = if phone then 8 else 14, Ornaments = not phone })
	hero.Root.Parent = main
	local skinsH = if phone then 44 else 128
	local rigView = Common.RigView(theme, {
		Kit = selectedKit,
		Skin = nil,
		Style = Common.Setting(d, "RigStyle"),
		Size = UDim2.new(1, 0, 1, -skinsH - (if phone then 4 else 10)),
	})
	rigView.Root.Parent = hero.Content
	local skinsArea = frame({ Name = "Skins", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, skinsH), Parent = hero.Content })

	-- details panel (right)
	local details = UIKit.Panel(theme, { Name = "Details", Size = UDim2.fromOffset(rightW, mainH), Position = UDim2.fromOffset(leftW + gap, 0), Padding = if phone then 10 else 18 })
	details.Root.Parent = main

	-- forward declarations
	local refresh: () -> ()
	local refreshCarousel: () -> ()
	local refreshDetails: () -> ()
	local refreshSkins: () -> ()

	local function closeModal()
		if modal then
			modal.Destroy()
			modal = nil
		end
	end

	local function confirm(titleText: string, bodyText: string, okText: string, okIcon: string?, onOk: () -> ())
		closeModal()
		modal = UIKit.Modal(theme, {
			Title = titleText,
			PanelSize = UDim2.fromOffset(if phone then 520 else 620, if phone then 230 else 280),
			Dim = 0.4,
			ZIndex = 60,
			OnClose = closeModal,
			Buttons = {
				{ Text = L("scr.back"), Variant = "Ghost", Width = if phone then 150 else 170, OnActivated = closeModal },
				{
					Text = okText,
					Variant = "Primary",
					Icon = okIcon,
					Width = if phone then 220 else 250,
					OnActivated = function()
						closeModal()
						onOk()
					end,
				},
			},
		})
		UIKit.Label(theme, { Text = bodyText, Role = "Body", Dialogue = true, Wrap = true, YAlign = "Top", Size = UDim2.fromScale(1, 1), Parent = modal.Content })
		modal.Root.Parent = root
	end

	local function practiceModal()
		closeModal()
		modal = UIKit.Modal(theme, {
			Title = L("scr.loadout.practiceTitle"),
			PanelSize = UDim2.fromOffset(if phone then 560 else 660, if phone then 240 else 290),
			Dim = 0.4,
			ZIndex = 60,
			OnClose = closeModal,
			Buttons = {
				{
					Text = L("scr.loadout.asHuman"),
					Variant = "Secondary",
					Icon = "Heart",
					Width = if phone then 220 else 260,
					OnActivated = function()
						closeModal()
						Common.Request(d, "StartPractice", { side = "Human" })
						if d.UI and type(d.UI.Close) == "function" then
							d.UI.Close()
						end
					end,
				},
				{
					Text = L("scr.loadout.asMonster"),
					Variant = "Primary",
					Icon = "Skull",
					Width = if phone then 220 else 260,
					OnActivated = function()
						closeModal()
						Common.Request(d, "StartPractice", { side = "Monster" })
						if d.UI and type(d.UI.Close) == "function" then
							d.UI.Close()
						end
					end,
				},
			},
		})
		UIKit.Label(theme, { Text = L("scr.loadout.practiceText"), Role = "Body", Dialogue = true, Wrap = true, YAlign = "Top", Size = UDim2.fromScale(1, 1), Parent = modal.Content })
		modal.Root.Parent = root
	end

	-- top bar: role tabs + role preference + monster chance ---------------------------------------------
	local tabs = UIKit.Tabs(theme, {
		Items = {
			{ Id = "Monster", Text = L("scr.loadout.tab.Monster"), Icon = "Skull" },
			{ Id = "Human", Text = L("scr.loadout.tab.Human"), Icon = "Heart" },
		},
		Selected = role,
		Height = topH,
		Size = UDim2.fromOffset(if phone then 300 else 420, topH),
		OnChanged = function(id: string)
			if id ~= role then
				role = id
				selectedKit = equippedKit(role) or ""
				refresh()
			end
		end,
	})
	tabs.Root.Parent = topBar
	local prefHolder = frame({ Name = "Preference", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, if phone then 640 else 1100, 1, 0), Parent = topBar })
	local pl = UIKit.ListLayout(prefHolder, { Horizontal = true, Gap = if phone then 10 else 18, HAlign = Enum.HorizontalAlignment.Right, VAlign = Enum.VerticalAlignment.Center })
	pl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local prefs = { "Either", "Monster", "Human" }
	local prefIndex = table.find(prefs, (profile and profile.RolePreference) or "Either") or 1
	local classic = theme.Id == "Classic"
	if phone then
		UIKit.Button(theme, {
			Name = "Practice",
			Variant = "Icon",
			Icon = "Flag",
			Disabled = Common.PlayerAttr(d, "Role", "Lobby") ~= "Lobby",
			Height = topH,
			LayoutOrder = 1,
			Parent = prefHolder,
			OnActivated = function()
				practiceModal()
			end,
		})
	else
		UIKit.Button(theme, {
			Name = "Practice",
			Text = L("scr.loadout.practice"),
			Icon = "Flag",
			Variant = "Secondary",
			Disabled = Common.PlayerAttr(d, "Role", "Lobby") ~= "Lobby",
			Height = topH,
			Width = if classic then 236 else 210,
			LayoutOrder = 1,
			Parent = prefHolder,
			OnActivated = function()
				practiceModal()
			end,
		})
	end
	UIKit.Cycle(theme, {
		Label = L("scr.loadout.rolePref"),
		Options = {
			{ Id = "Either", Text = L("role.either") },
			{ Id = "Monster", Text = L("role.monster") },
			{ Id = "Human", Text = L("role.human") },
		},
		Index = prefIndex,
		Dots = false,
		Height = topH,
		Size = UDim2.fromOffset(if phone then 330 elseif classic then 500 else 400, topH),
		LayoutOrder = 2,
		Parent = prefHolder,
		OnChanged = function(index: number)
			local pref = prefs[index] or "Either"
			Common.Request(d, "SetRolePref", { pref = pref })
			local ui = d.UI
			if ui and type(ui.Toast) == "function" then
				ui.Toast(L("scr.loadout.prefHint." .. pref), "Info", "Skull")
			end
		end,
	})
	local chance = tonumber(Common.PlayerAttr(d, "MonsterChance", 0)) or 0
	local chanceRow = UIKit.StatRow(theme, {
		Label = if phone then "" else L("scr.loadout.chance"),
		Value = tostring(math.floor(chance * 100 + 0.5)) .. "%",
		Icon = "Skull",
		Color = c.Danger,
		Fill = math.clamp(chance, 0.02, 1),
		Size = UDim2.fromOffset(if phone then 110 elseif classic then 330 else 250, if phone then 28 else 32),
		LayoutOrder = 3,
	})
	chanceRow.Parent = prefHolder
	local player = Common.LocalPlayer()
	if player then
		bag.Connect(player:GetAttributeChangedSignal("MonsterChance"), function()
			local v = tonumber(player:GetAttribute("MonsterChance")) or 0
			local old = chanceRow
			chanceRow = UIKit.StatRow(theme, {
				Label = if phone then "" else L("scr.loadout.chance"),
				Value = tostring(math.floor(v * 100 + 0.5)) .. "%",
				Icon = "Skull",
				Color = c.Danger,
				Fill = math.clamp(v, 0.02, 1),
				Size = old.Size,
				LayoutOrder = 3,
			})
			chanceRow.Parent = prefHolder
			old:Destroy()
		end)
	end

	-- carousel -----------------------------------------------------------------------------------------
	local cardButtons: { GuiObject } = {}
	refreshCarousel = function()
		carousel:ClearAllChildren()
		table.clear(cardButtons)
		local list = if kits then kits.ForRole(role) else {}
		local holder: GuiObject
		if phone then
			local scroll = UIKit.List(theme, { Horizontal = true, Gap = 8, ScrollBar = false })
			scroll.Root.Size = UDim2.fromScale(1, 1)
			scroll.Root.Parent = carousel
			holder = scroll.Content
		else
			local strip = frame({ Name = "Strip", Size = UDim2.fromScale(1, 1), Parent = carousel })
			local sl = UIKit.ListLayout(strip, { Horizontal = true, Gap = 14, HAlign = Enum.HorizontalAlignment.Center, VAlign = Enum.VerticalAlignment.Bottom })
			sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
			holder = strip
		end
		local n = #list
		local cardW = if phone then 150 else math.min(196, math.floor((bodyW - 14 * (n - 1)) / math.max(n, 1)))
		for i, kit in list do
			local owned = Common.KitOwned(profile, kit)
			local isSel = kit.Id == selectedKit
			local isEquipped = kit.Id == equippedKit(role)
			local kitId = kit.Id
			if phone then
				-- compact chip card: icon + name
				local chip = Instance.new("TextButton")
				chip.Name = "Kit_" .. kitId
				chip.Text = ""
				chip.AutoButtonColor = false
				chip.BackgroundTransparency = 1
				chip.Size = UDim2.fromOffset(cardW, carouselH - 6)
				chip.LayoutOrder = i
				local well = Common.Well(theme, { Size = UDim2.fromScale(1, 1), StrokeColor = if isSel then c.Accent else c.StrokeDim, StrokeTransparency = if isSel then 0 else 0.4 })
				well.Parent = chip
				local ic = Icons.Create(Common.KitIcon(kit), kit.Color, 34, kit.Color:Lerp(Color3.new(1, 1, 1), 0.7))
				ic.Position = UDim2.new(0, 26, 0.5, 0)
				ic.Parent = well
				UIKit.Label(theme, { Text = UIKit.Upper(pick(kit.Name)), Role = "Heading", TextSize = if theme.Id == "Classic" then 9 else 14, Position = UDim2.fromOffset(50, 8), Size = UDim2.new(1, -56, 0, 20), Scaled = true, MaxTextSize = if theme.Id == "Classic" then 9 else 14, Parent = well })
				UIKit.Label(theme, {
					Text = if not owned then L("common.gold", Common.Num(kit.Unlock.Gold)) elseif isEquipped then L("scr.loadout.equipped") else pick(kit.Title),
					Role = "Caption",
					TextSize = if theme.Id == "Classic" then 7 else 11,
					Color = if not owned then c.Gold elseif isEquipped then c.Success else c.TextDim,
					Position = UDim2.fromOffset(50, 30),
					Size = UDim2.new(1, -56, 0, 16),
					Truncate = true,
					Parent = well,
				})
				Motion.On(chip, "Activated", function()
					selectedKit = kitId
					refresh()
				end)
				chip.Parent = holder
				table.insert(cardButtons, chip)
			else
				local card = UIKit.Card(theme, {
					Name = pick(kit.Name),
					Title = if owned then pick(kit.Title) else L("common.gold", Common.Num(kit.Unlock.Gold)),
					Color = kit.Color,
					Icon = Common.KitIcon(kit),
					Role = L(if kit.Role == "Monster" then "role.monster" else "role.human"),
					RoleMonster = kit.Role == "Monster",
					Difficulty = kit.Difficulty,
					Locked = not owned,
					Selected = isSel,
					Size = UDim2.fromOffset(cardW, if isSel then carouselH else carouselH - 14),
					LayoutOrder = i,
					OnActivated = function()
						selectedKit = kitId
						refresh()
					end,
				})
				if isEquipped then
					local badge = UIKit.Badge(theme, { Text = L("scr.loadout.equipped"), Icon = "Check", Color = c.Success, Style = "Solid", Height = 18, TextSize = if theme.Id == "Classic" then 7 else 10 })
					badge.AnchorPoint = Vector2.new(0.5, 1)
					badge.Position = UDim2.new(0.5, 0, 1, -4)
					badge.ZIndex = 5
					badge.Parent = card.Portrait
				end
				card.Root.Parent = holder
				table.insert(cardButtons, card.Root)
			end
		end
		UIKit.LinkSelection(cardButtons, "Horizontal")
	end

	-- skins --------------------------------------------------------------------------------------------
	refreshSkins = function()
		skinsArea:ClearAllChildren()
		local kit = kits and kits.Get(selectedKit)
		if kit == nil then
			return
		end
		local shown = shownSkin(kit)
		local equipped = equippedSkin(kit)
		local kitOwned = Common.KitOwned(profile, kit)
		local sw = if phone then 34 else 46
		local row = frame({ Name = "Swatches", Size = UDim2.new(1, 0, 0, sw + 4), Position = UDim2.fromOffset(0, if phone then 0 else 30), Parent = skinsArea })
		local rl = UIKit.ListLayout(row, { Horizontal = true, Gap = if phone then 6 else 10, HAlign = Enum.HorizontalAlignment.Center, VAlign = Enum.VerticalAlignment.Center })
		rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local current: any = nil
		for i, skin in kit.Skins do
			local owned = Common.SkinOwned(profile, kit, skin)
			if skin.Id == shown then
				current = skin
			end
			local btn = Instance.new("TextButton")
			btn.Name = "Skin_" .. skin.Id
			btn.Text = ""
			btn.AutoButtonColor = false
			btn.BackgroundTransparency = 1
			btn.Size = UDim2.fromOffset(sw + 4, sw + 4)
			btn.LayoutOrder = i
			local swatch = Common.Swatch(theme, kit, skin, { Size = sw, Selected = skin.Id == shown, Locked = not owned })
			swatch.AnchorPoint = Vector2.new(0.5, 0.5)
			swatch.Position = UDim2.fromScale(0.5, 0.5)
			swatch.Parent = btn
			if skin.Id == equipped then
				local check = Icons.Create("Check", c.Success, if phone then 12 else 16)
				check.Position = UDim2.new(1, -3, 0, 3)
				check.ZIndex = 6
				check.Parent = btn
			end
			local skinId = skin.Id
			Motion.On(btn, "Activated", function()
				previewSkin[kit.Id] = skinId
				rigView.Set(kit.Id, skinId)
				refreshSkins()
			end)
			btn.Parent = row
		end
		if phone or current == nil then
			return
		end
		-- skin name + rarity
		local rarity = Themes.Rarity(theme, current.Rarity or "Common")
		UIKit.Label(theme, {
			Name = "SkinName",
			Text = UIKit.Upper(pick(current.Name)) .. "  ·  " .. L("scr.rarity." .. (current.Rarity or "Common")),
			Role = "Caption",
			Color = rarity,
			XAlign = "Center",
			Size = UDim2.new(1, 0, 0, 22),
			Parent = skinsArea,
		})
		-- action
		local owned = Common.SkinOwned(profile, kit, current)
		local text: string
		local variant = "Secondary"
		local disabled = false
		local icon: string? = nil
		local action: (() -> ())? = nil
		if current.Id == equipped then
			text, disabled, icon = L("scr.loadout.equipped"), true, "Check"
		elseif owned then
			text, variant, icon = L("scr.loadout.equip"), "Primary", "Check"
			action = function()
				pendingSkin[kit.Id] = current.Id
				Common.Request(d, "EquipSkin", { kitId = kit.Id, skinId = current.Id })
				refreshSkins()
			end
		elseif current.Mastery then
			text, disabled, icon = L("scr.mastery", current.Mastery), true, "Crown"
		elseif not kitOwned then
			text, disabled, icon = L("scr.loadout.skinLocked"), true, "Lock"
		else
			text, variant, icon = L("scr.loadout.buySkin", Common.Num(current.Price)), "Primary", "Gold"
			action = function()
				local gold = profile and profile.Gold or 0
				if gold < current.Price then
					confirm(L("scr.shop.confirmTitle", pick(current.Name)), L("scr.shop.notEnough", Common.Num(current.Price - gold)), L("common.ok"), nil, function() end)
					return
				end
				confirm(L("scr.shop.confirmTitle", pick(current.Name)), L("scr.shop.confirmText", Common.Num(current.Price), pick(current.Name), pick(kit.Name)), L("scr.shop.buy"), "Gold", function()
					Common.Request(d, "Buy", { kind = "Skin", kitId = kit.Id, skinId = current.Id })
				end)
			end
		end
		local btn = UIKit.Button(theme, {
			Name = "SkinAction",
			Text = text,
			Icon = icon,
			Variant = variant,
			Disabled = disabled,
			Height = 40,
			Width = math.min(leftW - 40, 300),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			OnActivated = action,
		})
		btn.Root.Parent = skinsArea
	end

	-- details ------------------------------------------------------------------------------------------
	refreshDetails = function()
		details.Content:ClearAllChildren()
		local kit = kits and kits.Get(selectedKit)
		if kit == nil then
			Common.Empty(theme, L("scr.loadingProfile"), { Parent = details.Content })
			return
		end
		local content = details.Content
		local owned = Common.KitOwned(profile, kit)
		local isEquipped = kit.Id == equippedKit(role)
		local headH = if phone then 52 else 112
		local head = frame({ Name = "Head", Size = UDim2.new(1, 0, 0, headH), Parent = content })
		-- name, title, difficulty
		local nameSize = if phone then math.floor(theme.TextSize.Title * 0.62) else math.floor(theme.TextSize.Title * 0.95)
		local name = UIKit.Title(theme, {
			Name = "KitName",
			Text = pick(kit.Name),
			Role = "Title",
			TextSize = nameSize,
			Size = UDim2.new(0.5, 0, 0, math.ceil(nameSize * 1.15)),
			Glow = false,
		})
		name.Root.Parent = head
		local sub = frame({ Name = "Sub", Position = UDim2.fromOffset(0, math.ceil(nameSize * 1.15) + 2), Size = UDim2.new(0.6, 0, 0, if phone then 18 else 24), Parent = head })
		UIKit.ListLayout(sub, { Horizontal = true, Gap = 10, VAlign = Enum.VerticalAlignment.Center })
		UIKit.Label(theme, { Name = "KitTitle", Text = pick(kit.Title), Role = "Subtitle", TextSize = if phone then theme.TextSize.Small else theme.TextSize.Subtitle, Color = kit.Color:Lerp(c.Text, 0.3), AutoSize = "X", LayoutOrder = 1, Parent = sub }).Size = UDim2.new(0, 0, 1, 0)
		local diff = difficulty(theme, kit.Difficulty or 1, if phone then 11 else 14)
		diff.LayoutOrder = 2
		diff.Parent = sub
		if not phone then
			UIKit.Label(theme, { Name = "DiffText", Text = L("difficulty." .. tostring(kit.Difficulty or 1)), Role = "Caption", Tone = "Muted", AutoSize = "X", LayoutOrder = 3, Parent = sub }).Size = UDim2.new(0, 0, 1, 0)
			-- playstyle line
			UIKit.Label(theme, {
				Name = "Playstyle",
				Text = pick(kit.Playstyle),
				Role = "Small",
				Tone = "Dim",
				Dialogue = theme.Id == "Classic",
				Wrap = true,
				YAlign = "Top",
				Scaled = true,
				MaxTextSize = if theme.Id == "Classic" then 9 else theme.TextSize.Small,
				MinTextSize = 7,
				Position = UDim2.fromOffset(0, math.ceil(nameSize * 1.15) + 30),
				Size = UDim2.new(0.55, 0, 0, 40),
				Parent = head,
			})
		end
		-- action buttons (right)
		local actions = frame({ Name = "Actions", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.46, 0, 0, if phone then 40 else 48), Parent = head })
		local al = UIKit.ListLayout(actions, { Horizontal = true, Gap = 10, HAlign = Enum.HorizontalAlignment.Right, VAlign = Enum.VerticalAlignment.Center })
		al.HorizontalAlignment = Enum.HorizontalAlignment.Right
		local bh = if phone then 36 else 46
		local primary: any
		if isEquipped then
			primary = UIKit.Button(theme, { Name = "Equip", Text = L("scr.loadout.equipped"), Icon = "Check", Variant = "Secondary", Selected = true, Disabled = true, Height = bh, Width = if phone then 150 else 190, LayoutOrder = 3 })
		elseif owned then
			primary = UIKit.Button(theme, {
				Name = "Equip",
				Text = L("scr.loadout.equip"),
				Icon = "Check",
				Variant = "Primary",
				Height = bh,
				Width = if phone then 150 else 190,
				LayoutOrder = 3,
				OnActivated = function()
					pendingEquip[kit.Role] = kit.Id
					Common.Request(d, "EquipKit", { kitId = kit.Id, role = kit.Role })
					refresh()
				end,
			})
		else
			local level = profile and profile.Level or 1
			local needLv = kit.Unlock.Level or 0
			if needLv > level then
				primary = UIKit.Button(theme, { Name = "Unlock", Text = L("common.requiresLevel", needLv), Icon = "Lock", Variant = "Secondary", Disabled = true, Height = bh, Width = if phone then 170 else 220, LayoutOrder = 3 })
			else
				primary = UIKit.Button(theme, {
					Name = "Unlock",
					Text = L("scr.loadout.unlock", Common.Num(kit.Unlock.Gold)),
					Icon = "Gold",
					Variant = "Primary",
					Height = bh,
					Width = if phone then 190 else 240,
					LayoutOrder = 3,
					OnActivated = function()
						local gold = profile and profile.Gold or 0
						if gold < kit.Unlock.Gold then
							confirm(L("scr.shop.confirmTitle", pick(kit.Name)), L("scr.shop.notEnough", Common.Num(kit.Unlock.Gold - gold)), L("common.ok"), nil, function() end)
							return
						end
						confirm(L("scr.shop.confirmTitle", pick(kit.Name)), L("scr.shop.confirmKit", Common.Num(kit.Unlock.Gold), pick(kit.Name)), L("common.unlock"), "Gold", function()
							Common.Request(d, "Buy", { kind = "Kit", kitId = kit.Id })
						end)
					end,
				})
			end
		end
		local inLobby = Common.PlayerAttr(d, "Role", "Lobby") == "Lobby"
		UIKit.Button(theme, {
			Name = "Try",
			Text = if phone or compact or theme.Id == "Classic" then L("scr.loadout.tryShort") else L("scr.loadout.try"),
			Icon = "Target",
			Variant = "Secondary",
			Disabled = not inLobby,
			Height = bh,
			Width = if phone then 130 elseif compact or theme.Id == "Classic" then 190 else 290,
			LayoutOrder = 2,
			Parent = actions,
			OnActivated = function()
				Common.Request(d, "TryKit", { kitId = kit.Id })
				if d.UI and type(d.UI.Close) == "function" then
					d.UI.Close()
				end
			end,
		})
		primary.Root.Parent = actions
		-- core stats row (under the actions)
		if not phone then
			local stats = frame({ Name = "Stats", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -4), Size = UDim2.new(0.44, 0, 0, 30), Parent = head })
			local stl = UIKit.ListLayout(stats, { Horizontal = true, Gap = 10, HAlign = Enum.HorizontalAlignment.Right, VAlign = Enum.VerticalAlignment.Center })
			stl.HorizontalAlignment = Enum.HorizontalAlignment.Right
			local hpText = Common.Num(kit.Stats.MaxHP)
			if kit.Stats.HPPerHuman then
				hpText ..= "  " .. L("scr.loadout.hpPerHuman", kit.Stats.HPPerHuman)
			end
			Common.Chip(theme, { Icon = "Heart", Text = L("stat.hp") .. " " .. hpText, Color = c.HP, Height = 30, Role = "Caption", TextSize = if theme.Id == "Classic" then 9 else 13, LayoutOrder = 1, Parent = stats })
			Common.Chip(theme, { Icon = "Shoe", Text = L("stat.speed") .. " " .. tostring(kit.Stats.WalkSpeed), Color = c.Info, Height = 30, Role = "Caption", TextSize = if theme.Id == "Classic" then 9 else 13, LayoutOrder = 2, Parent = stats })
			if kit.Stats.MaxDodges then
				Common.Chip(theme, { Icon = "Dash", Text = L("stat.dodges") .. " " .. tostring(kit.Stats.MaxDodges), Color = c.Dodge, Height = 30, Role = "Caption", TextSize = if theme.Id == "Classic" then 9 else 13, LayoutOrder = 3, Parent = stats })
			elseif kit.Stats.MaxGuard then
				Common.Chip(theme, { Icon = "Shield", Text = L("stat.guard") .. " " .. tostring(kit.Stats.MaxGuard), Color = c.Guard, Height = 30, Role = "Caption", TextSize = if theme.Id == "Classic" then 9 else 13, LayoutOrder = 3, Parent = stats })
			end
		end
		-- divider
		local divY = headH + (if phone then 4 else 8)
		UIKit.Divider(theme, { Position = UDim2.fromOffset(0, divY), Size = UDim2.new(1, 0, 0, if phone then 6 else 10), Parent = content })
		-- abilities grid
		local listTop = divY + (if phone then 10 else 18)
		local list = entries(kit)
		local cols = if phone then 1 else 2
		local contentW = rightW - (if phone then 20 else 36)
		local tileW = math.floor((contentW - (cols - 1) * 12 - (if phone then 0 else 10)) / cols)
		local tileH = if phone then 70 elseif theme.Id == "Classic" then 100 else 92
		local grid = UIKit.Grid(theme, {
			CellSize = UDim2.fromOffset(tileW, tileH),
			CellPadding = UDim2.fromOffset(12, if phone then 8 else 10),
			Scroll = true,
		})
		grid.Root.Name = "Abilities"
		grid.Root.Position = UDim2.fromOffset(0, listTop)
		grid.Root.Size = UDim2.new(1, 0, 1, -listTop)
		grid.Root.Parent = content
		for i, e in list do
			grid.Add(abilityTile(theme, kit, e, Vector2.new(tileW, tileH), phone, i))
		end
	end

	refresh = function()
		local kit = kits and kits.Get(selectedKit)
		if kit and kit.Role ~= role then
			role = kit.Role
			tabs.Select(role)
		end
		refreshCarousel()
		refreshSkins()
		refreshDetails()
		if kit then
			rigView.Set(kit.Id, shownSkin(kit))
		end
	end
	refresh()

	-- live profile updates
	local state = d.State
	if state and state.ProfileChanged then
		bag.Connect(state.ProfileChanged, function(newProfile: any)
			profile = newProfile or Common.Profile(d)
			table.clear(pendingEquip)
			table.clear(pendingSkin)
			refreshCarousel()
			refreshSkins()
			refreshDetails()
		end)
	end

	local function cycleKit(step: number)
		local list = if kits then kits.ForRole(role) else {}
		local idx = 1
		for i, k in list do
			if k.Id == selectedKit then
				idx = i
			end
		end
		local nextKit = list[((idx - 1 + step) % math.max(#list, 1)) + 1]
		if nextKit then
			selectedKit = nextKit.Id
			refresh()
		end
	end

	return {
		Root = root,
		DefaultSelection = cardButtons[1],
		Select = function(kitId: string)
			selectedKit = kitId
			refresh()
		end,
		OnAction = function(action: string): boolean
			if modal then
				if action == "Back" then
					closeModal()
					return true
				end
				return false
			end
			if action == "PrevTab" or action == "NextTab" then
				role = if role == "Monster" then "Human" else "Monster"
				tabs.Select(role)
				selectedKit = equippedKit(role) or ""
				refresh()
				return true
			elseif action == "Left" or action == "Right" then
				cycleKit(if action == "Left" then -1 else 1)
				return true
			end
			return false
		end,
		Destroy = function()
			closeModal()
			rigView.Destroy()
			screen.Destroy()
		end,
	}
end

return Loadout
