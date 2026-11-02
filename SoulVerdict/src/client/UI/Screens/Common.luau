--!strict
-- Screens/Common: shared plumbing for the menu screens (SPEC §10). Lune-safe at require time and inside
-- every builder: engine services are only touched lazily through deps (StateController & co.) or pcall.
--
-- Data (deps = the UI deps table, SPEC §20; every entry may be nil offline)
--   Common.Profile(deps) -> ProfileView?     deps.Profile (mock; false = "not loaded") > State.Profile() >
--                                            Common.SampleProfile() when previewing (no State)
--   Common.IsPreview(deps) -> boolean        true when there is no StateController (Lune previews/tests)
--   Common.Round(deps) -> {[string]: any}    RoundState snapshot (sample offline)
--   Common.Now(deps) -> number               server time (os.time offline)
--   Common.PlayerAttr(deps, name, default)   LocalPlayer attribute (deps.Attrs mock offline)
--   Common.PlayerName(deps) -> string
--   Common.Request(deps, action, data) -> boolean   StateController.Request or Net "Request"
--   Common.Setting(deps, key) -> any          deps.UI.Setting(key) > profile.Settings[key] > Config.Defaults[key]
--   Common.Progression(name) -> module?      Shared/Progression/<name> (pcall; nil while it does not exist)
--   Common.Call(module, {fnNames}, ...) -> (found, result)   first existing function wins (defensive APIs)
--   Common.ExpToNext(level), Common.Mastery(exp) -> (level, fraction, isMax), Common.KitOwned/SkinOwned/
--   Common.EquippedSkin(profile, kit), Common.SkinColors(kit, skin) -> {Color3}
-- Formatting: Common.L, Common.Pick, Common.Num(n) "12,345", Common.Clock(seconds) "7:42:10" / "4:05"
-- UI pieces
--   Common.Screen(theme, deps, opts) -> ScreenFrame   standard chrome: backdrop, header (icon, title, subtitle,
--       currency chips, close button), Body frame, footer key hints. opts: { Name, Title, Subtitle, Icon,
--       Backdrop ("Full"|"Dim"|"None"), Currency (true), OnBack, Hints {{Key?, Action?, Label}} }
--   Common.Chip(theme, props) -> Frame        icon + text pill (props: Icon, Text, Color, Height, Tone, Role)
--   Common.Currency(theme, profile, props) -> Frame    G balance + LV chip with a mini EXP bar
--   Common.Swatch(theme, kit, skin, props) -> Frame    palette swatch (2-3 colours) with a rarity ring
--   Common.RigView(theme, props) -> RigViewHandle      ViewportFrame with the kit's 3D rig (RigBuilder),
--       posed ("Pockets" skeletons / "Ready" humans), framed, slowly turning, drag to spin.
--       props: Kit, Skin, Size, Position, AnchorPoint, Style (rig style id), Styler (fn(model), e.g.
--       RigStyleController.ApplyTo), Spin (deg/s), Parent
--       handle: { Root, Set(kitId, skinId?), Destroy }
--   Common.Bleed(gui, layout) -> gui    stretches a full-screen background (direct child of the screen root, at 0,0
--       size 1,1) over the top bar / notch strips the CoreUISafeInsets layer leaves out (layout.Bleed, design px)
--   Common.Bag() -> { Add(x), Connect(signal, fn), Clean() }    connection/cleanup bag
--   Common.Empty(theme, text, props) -> Frame                   centred "nothing here" note
-- Samples (offline previews / tests): Common.SampleProfile(), Common.SampleRound(), Common.SampleResult(),
--   Common.SampleRewards(), Common.SampleLeaderboards(), Common.SampleAchievements()

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Icons = require(script.Parent.Parent.Icons)
local Motion = require(script.Parent.Parent.Motion)

type Theme = Themes.Theme

export type ScreenFrame = {
	Root: Frame,
	Body: Frame,
	Header: Frame,
	Footer: Frame,
	Layout: any,
	Canvas: Vector2,
	Compact: boolean,
	Phone: boolean,
	Margin: number,
	Gap: number,
	Bag: any,
	Back: GuiObject?,
	Destroy: () -> (),
}

export type RigViewHandle = { Root: Frame, Viewport: ViewportFrame, Set: (string?, string?) -> (), Destroy: () -> () }

local Common = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- lazy modules ---------------------------------------------------------------------------------------
local cache: { [string]: any } = {}

function Common.Shared(): any
	if cache.Shared == nil then
		cache.Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	end
	return cache.Shared
end

local function lazy(key: string, path: { string }): any
	if cache[key] == nil then
		local ok, result = pcall(function()
			local node: any = Common.Shared()
			for _, name in path do
				node = node:WaitForChild(name)
			end
			return require(node) :: any
		end)
		cache[key] = if ok then result else false
	end
	return if cache[key] then cache[key] else nil
end

function Common.Strings(): any
	return lazy("Strings", { "Strings" })
end

function Common.Kits(): any
	return lazy("Kits", { "Kits" })
end

function Common.Config(): any
	return lazy("Config", { "Config" })
end

function Common.Module(path: { string }): any
	return lazy(table.concat(path, "."), path)
end

-- Optional modules that may not exist yet (FindFirstChild: never waits).
function Common.Progression(name: string): any
	local key = "Progression." .. name
	if cache[key] == nil then
		local ok, result = pcall(function()
			local folder = Common.Shared():FindFirstChild("Progression")
			local module = folder and folder:FindFirstChild(name)
			if module == nil then
				return false
			end
			return require(module) :: any
		end)
		cache[key] = if ok and result then result else false
	end
	return if cache[key] then cache[key] else nil
end

function Common.Call(module: any, names: { string }, ...: any): (boolean, any)
	if type(module) ~= "table" then
		return false, nil
	end
	for _, name in names do
		local fn = module[name]
		if type(fn) == "function" then
			local ok, result = pcall(fn, ...)
			if ok then
				return true, result
			end
		end
	end
	return false, nil
end

function Common.L(key: string, ...: any): string
	local s = Common.Strings()
	return if s then s.L(key, ...) else key
end

function Common.Pick(tbl: any): string
	if type(tbl) == "string" then
		return tbl
	end
	local s = Common.Strings()
	if s then
		return s.Pick(tbl)
	end
	return if type(tbl) == "table" then (tbl.en or "") else ""
end

function Common.Has(key: string): boolean
	local s = Common.Strings()
	return s ~= nil and s.Has(key)
end

-- formatting -----------------------------------------------------------------------------------------
function Common.Num(n: number?): string
	local v = math.floor((n or 0) + 0.5)
	local s = tostring(math.abs(v))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if v < 0 then "-" else "") .. out
end

function Common.Clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

function Common.Short(n: number): string
	if n >= 1000000 then
		return string.format("%.1fM", n / 1000000)
	elseif n >= 10000 then
		return string.format("%.1fK", n / 1000)
	end
	return Common.Num(n)
end

-- deps & data ----------------------------------------------------------------------------------------
function Common.IsPreview(deps: any): boolean
	return deps == nil or deps.State == nil
end

function Common.Layout(deps: any): any
	return (deps and deps.Layout) or { Canvas = Vector2.new(1600, 900), Compact = false, Phone = false, Scale = 1 }
end

function Common.Bleed(gui: GuiObject, layout: any): GuiObject
	local b = if type(layout) == "table" then layout.Bleed else nil
	if type(b) == "table" then
		-- (UDim offsets are integers: round outwards so the strip is fully covered)
		local l, t = math.ceil(b.Left or 0), math.ceil(b.Top or 0)
		local r, bottom = math.ceil(b.Right or 0), math.ceil(b.Bottom or 0)
		local p, z = gui.Position, gui.Size
		gui.Position = UDim2.new(p.X.Scale, p.X.Offset - l, p.Y.Scale, p.Y.Offset - t)
		gui.Size = UDim2.new(z.X.Scale, z.X.Offset + l + r, z.Y.Scale, z.Y.Offset + t + bottom)
	end
	return gui
end

function Common.Profile(deps: any): any
	if deps and deps.Profile ~= nil then
		return if deps.Profile == false then nil else deps.Profile
	end
	local state = deps and deps.State
	if state then
		if type(state.Profile) == "function" then
			local ok, p = pcall(state.Profile)
			if ok then
				return p
			end
		end
		return nil
	end
	return Common.SampleProfile()
end

function Common.Round(deps: any): { [string]: any }
	if deps and type(deps.Round) == "table" then
		return deps.Round
	end
	local state = deps and deps.State
	if state and type(state.Round) == "function" then
		local ok, r = pcall(state.Round)
		if ok and type(r) == "table" then
			return r
		end
		return {}
	end
	return Common.SampleRound()
end

function Common.Now(deps: any): number
	local state = deps and deps.State
	if state and type(state.Now) == "function" then
		local ok, t = pcall(state.Now)
		if ok and type(t) == "number" then
			return t
		end
	end
	if deps and type(deps.Now) == "number" then
		return deps.Now
	end
	return os.time()
end

local function localPlayer(): any
	local ok, p = pcall(function()
		return game:GetService("Players").LocalPlayer
	end)
	return if ok then p else nil
end
Common.LocalPlayer = localPlayer

function Common.PlayerAttr(deps: any, name: string, default: any): any
	if deps and type(deps.Attrs) == "table" and deps.Attrs[name] ~= nil then
		return deps.Attrs[name]
	end
	local p = localPlayer()
	if p then
		local v = p:GetAttribute(name)
		if v ~= nil then
			return v
		end
		return default
	end
	if Common.IsPreview(deps) then
		local sample = { MonsterChance = 0.18, StyleLab = deps ~= nil and deps.StyleLab == true, Role = "Lobby" }
		local v = (sample :: any)[name]
		if v ~= nil then
			return v
		end
	end
	return default
end

function Common.PlayerName(deps: any): string
	if deps and type(deps.PlayerName) == "string" then
		return deps.PlayerName
	end
	local p = localPlayer()
	if p then
		return p.DisplayName
	end
	return "Frisk"
end

function Common.UserId(deps: any): number
	if deps and type(deps.UserId) == "number" then
		return deps.UserId
	end
	local p = localPlayer()
	return if p then p.UserId else 1
end

function Common.Request(deps: any, action: string, data: any): boolean
	local state = deps and deps.State
	if state and type(state.Request) == "function" then
		local ok = pcall(state.Request, action, data)
		return ok
	end
	if Common.IsPreview(deps) then
		return false
	end
	local ok = pcall(function()
		local Net = require(Common.Shared():WaitForChild("Net")) :: any
		Net.Client.Fire("Request", action, data)
	end)
	return ok
end

-- RigStyleController.ApplyTo as a RigView styler (nil offline)
function Common.Styler(deps: any): ((Model) -> ())?
	local rs = deps and deps.RigStyle
	if rs and type(rs.ApplyTo) == "function" then
		return function(model: Model)
			rs.ApplyTo(model)
		end
	end
	return nil
end

function Common.Setting(deps: any, key: string): any
	local ui = deps and deps.UI
	if ui and type(ui.Setting) == "function" then
		local ok, v = pcall(ui.Setting, key)
		if ok and v ~= nil then
			return v
		end
	end
	local profile = Common.Profile(deps)
	if profile and type(profile.Settings) == "table" and profile.Settings[key] ~= nil then
		return profile.Settings[key]
	end
	local config = Common.Config()
	return if config and config.Defaults then config.Defaults[key] else nil
end

-- progression math (defensive: Shared/Progression may not exist yet) -------------------------------------
function Common.ExpToNext(level: number): number
	local ok, v = Common.Call(Common.Progression("Levels"), { "ExpToNext" }, level)
	if ok and type(v) == "number" then
		return v
	end
	return 100 + 60 * (math.max(level, 1) - 1) -- SPEC §1.6
end

-- kit mastery exp -> (level 1..10, fraction to next, isMax)
function Common.Mastery(exp: number?): (number, number, boolean)
	local e = exp or 0
	local module = Common.Progression("Mastery")
	if module and type(module.Progress) == "function" then
		-- Mastery.Progress(exp) -> (level, into, need); need = 0 at max level
		local ok, lv, into, need = pcall(module.Progress, e)
		if ok and type(lv) == "number" then
			local isMax = (tonumber(need) or 0) <= 0
			return lv, if isMax then 1 else math.clamp((tonumber(into) or 0) / need, 0, 1), isMax
		end
	end
	if module and type(module.Level) == "function" then
		local ok, lv = pcall(module.Level, e)
		if ok and type(lv) == "number" then
			local max = (type(module.MaxLevel) == "number" and module.MaxLevel) or 10
			local per = (type(module.ExpPerLevel) == "number" and module.ExpPerLevel) or 400
			return lv, if lv >= max then 1 else (e % per) / per, lv >= max
		end
	end
	-- fallback (SPEC-level guess): 400 kit EXP per level, 10 levels
	local level = math.min(1 + math.floor(e / 400), 10)
	return level, if level >= 10 then 1 else (e % 400) / 400, level >= 10
end

function Common.KitOwned(profile: any, kit: any): boolean
	if kit == nil then
		return false
	end
	if kit.Unlock and (kit.Unlock.Gold or 0) <= 0 and (kit.Unlock.Level or 0) <= 0 then
		return true
	end
	return profile ~= nil and type(profile.Unlocked) == "table" and profile.Unlocked[kit.Id] == true
end

function Common.SkinOwned(profile: any, kit: any, skin: any): boolean
	if skin == nil then
		return false
	end
	if skin.Id == "Default" or ((skin.Price or 0) <= 0 and skin.Mastery == nil) then
		return true
	end
	if profile == nil or type(profile.Unlocked) ~= "table" then
		return false
	end
	if profile.Unlocked[kit.Id .. ":" .. skin.Id] == true then
		return true
	end
	if skin.Mastery then
		local lv = Common.Mastery(profile.Mastery and profile.Mastery[kit.Id] or 0)
		return lv >= skin.Mastery
	end
	return false
end

function Common.EquippedKit(profile: any, role: string): string?
	if profile and type(profile.Equipped) == "table" then
		local id = profile.Equipped[role]
		if type(id) == "string" then
			return id
		end
	end
	local kits = Common.Kits()
	return if kits then (if role == "Monster" then kits.DefaultMonster else kits.DefaultHuman) else nil
end

function Common.EquippedSkin(profile: any, kit: any): string
	if profile and type(profile.Equipped) == "table" and type(profile.Equipped.Skins) == "table" then
		local id = profile.Equipped.Skins[kit.Id]
		if type(id) == "string" then
			return id
		end
	end
	return "Default"
end

function Common.KitIcon(kit: any): string
	if kit == nil then
		return "Soul"
	end
	local portrait = Icons.PixelIcons and Icons.PixelIcons.KitIcon(kit.Id)
	if portrait then
		return portrait -- the owner's pixel portrait
	end
	for _, slot in { "Q", "E", "M1" } do
		for _, a in kit.Abilities do
			if a.Slot == slot and Icons.Has(a.Icon) then
				return a.Icon
			end
		end
	end
	return if kit.Role == "Monster" then "Skull" else "Heart"
end

local PRIMARY_KEYS = { "Hoodie", "Jacket", "Coat", "Sweater", "Cloth", "Shirt", "Robe", "Dress", "Body" }
local SECONDARY_KEYS = { "Fur", "Stripe", "Trim", "Scarf", "ClothAlt", "Pants", "Shorts", "Hair", "Accent" }
local ACCENT_KEYS = { "EyeGlow", "Accent", "Glow", "Eye", "Slippers", "Shoes" }

local blueprintPalettes: { [string]: any } = {}
local function blueprintPalette(rigId: string): { [string]: Color3 }
	if blueprintPalettes[rigId] == nil then
		local ok, palette = pcall(function()
			local rigBuilder = Common.Module({ "Rigs", "RigBuilder" })
			local bp = rigBuilder and rigBuilder.GetBlueprint(rigId)
			return bp and bp.Palette
		end)
		blueprintPalettes[rigId] = if ok and type(palette) == "table" then palette else false
	end
	return blueprintPalettes[rigId] or {}
end

-- 3 swatch colours for a skin: primary cloth, secondary, accent (blueprint palette <- skin palette).
function Common.SkinColors(kit: any, skin: any): { Color3 }
	local merged: { [string]: Color3 } = {}
	for k, v in blueprintPalette(kit.Rig) do
		if typeof(v) == "Color3" then
			merged[k] = v
		end
	end
	if skin and type(skin.Palette) == "table" then
		for k, v in skin.Palette do
			if typeof(v) == "Color3" then
				merged[k] = v
			end
		end
	end
	local function first(keys: { string }, fallback: Color3): Color3
		for _, k in keys do
			if merged[k] then
				return merged[k]
			end
		end
		return fallback
	end
	local base: Color3 = kit.Color
	local primary = first(PRIMARY_KEYS, base)
	local secondary = first(SECONDARY_KEYS, base:Lerp(WHITE, 0.55))
	local accent = first(ACCENT_KEYS, base:Lerp(WHITE, 0.25))
	return { primary, secondary, accent }
end

-- small UI helpers --------------------------------------------------------------------------------------
local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	local parent = nil
	for k, v in props do
		if k == "Parent" then
			parent = v
		else
			(f :: any)[k] = v
		end
	end
	if parent then
		f.Parent = parent
	end
	return f
end
Common.Frame = frame

function Common.Corner(parent: Instance, radius: UDim)
	if radius.Scale > 0 or radius.Offset > 0 then
		local c = Instance.new("UICorner")
		c.CornerRadius = radius
		c.Parent = parent
	end
end

function Common.Stroke(
	parent: Instance,
	color: Color3,
	thickness: number,
	transparency: number?,
	join: Enum.LineJoinMode?
): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = join or Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

function Common.Gradient(
	parent: Instance,
	color: ColorSequence?,
	transparency: NumberSequence?,
	rotation: number?
): UIGradient
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 0
	if color then
		g.Color = color
	end
	if transparency then
		g.Transparency = transparency
	end
	g.Parent = parent
	return g
end

function Common.NSeq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

-- rounded "chip" radius per theme
function Common.ChipCorner(theme: Theme): UDim
	if theme.Id == "Void" then
		return UDim.new(0.5, 0)
	elseif theme.Id == "Royal" then
		return UDim.new(0, 6)
	end
	return theme.SmallCorner
end

-- inset well used for rows/tiles
function Common.Well(theme: Theme, props: { [string]: any }): Frame
	local c = theme.Colors
	local f = frame({
		Name = props.Name or "Well",
		BackgroundTransparency = if theme.Id == "Void" then 0.45 else 0,
		BackgroundColor3 = props.Color or c.PanelInset,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	Common.Corner(
		f,
		if theme.Id == "Void" then UDim.new(0, 10) elseif theme.Id == "Royal" then UDim.new(0, 6) else theme.SmallCorner
	)
	local strokeColor: Color3 = props.StrokeColor or c.StrokeDim
	Common.Stroke(
		f,
		strokeColor,
		if theme.Id == "Classic" then 2 else 1,
		props.StrokeTransparency or (if theme.Id == "Classic" then 0 else 0.45),
		theme.LineJoin
	)
	if props.Parent then
		f.Parent = props.Parent
	end
	return f
end

function Common.Chip(theme: Theme, props: { [string]: any }): Frame
	local c = theme.Colors
	local h: number = props.Height or 34
	local color: Color3 = props.Color or c.Accent
	local root = frame({
		Name = props.Name or "Chip",
		BackgroundTransparency = if theme.Id == "Void" then 0.35 else 0,
		BackgroundColor3 = c.PanelInset,
		Size = UDim2.fromOffset(0, h),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = props.LayoutOrder or 0,
	})
	Common.Corner(root, Common.ChipCorner(theme))
	Common.Stroke(
		root,
		if theme.Id == "Classic" then c.Stroke else color,
		if theme.Id == "Classic" then 2 else 1.5,
		if theme.Id == "Classic" then 0 else 0.35,
		theme.LineJoin
	)
	UIKit.Padding(root, math.floor(h * 0.3), 0, math.floor(h * 0.42), 0)
	UIKit.ListLayout(root, { Horizontal = true, Gap = math.floor(h * 0.22), VAlign = Enum.VerticalAlignment.Center })
	if props.Icon then
		local holder = frame({
			Name = "IconHolder",
			Size = UDim2.fromOffset(math.floor(h * 0.62), math.floor(h * 0.62)),
			LayoutOrder = 1,
			Parent = root,
		})
		local icon = Icons.Create(props.Icon, color, UDim2.fromScale(1, 1), props.Accent)
		icon.Parent = holder
	end
	local label = UIKit.Label(theme, {
		Name = "Text",
		Text = props.Text or "",
		Role = props.Role or "Number",
		TextSize = props.TextSize or math.floor(h * (if theme.Id == "Classic" then 0.38 else 0.5)),
		Color = props.TextColor or c.Text,
		AutoSize = "X",
		LayoutOrder = 2,
	})
	label.Size = UDim2.new(0, 0, 1, 0)
	label.Parent = root
	if props.Position then
		root.Position = props.Position
	end
	if props.AnchorPoint then
		root.AnchorPoint = props.AnchorPoint
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return root
end

function Common.Currency(theme: Theme, profile: any, props: { [string]: any }): Frame
	local c = theme.Colors
	local h: number = props.Height or 38
	local row = frame({
		Name = "Currency",
		Size = UDim2.fromOffset(0, h),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
	})
	UIKit.ListLayout(row, { Horizontal = true, Gap = 10, VAlign = Enum.VerticalAlignment.Center })
	local level = if profile then (profile.Level or 1) else 1
	local exp = if profile then (profile.Exp or 0) else 0
	local need = Common.ExpToNext(level)
	-- LV chip with a mini exp bar underneath the text
	local lv = frame({
		Name = "Level",
		BackgroundTransparency = if theme.Id == "Void" then 0.35 else 0,
		BackgroundColor3 = c.PanelInset,
		Size = UDim2.fromOffset(if props.Compact then 112 else 150, h),
		LayoutOrder = 1,
		Parent = row,
	})
	Common.Corner(lv, Common.ChipCorner(theme))
	Common.Stroke(
		lv,
		if theme.Id == "Classic" then c.Stroke else c.Exp,
		if theme.Id == "Classic" then 2 else 1.5,
		if theme.Id == "Classic" then 0 else 0.4,
		theme.LineJoin
	)
	UIKit.Label(theme, {
		Name = "Lv",
		Text = Common.L("common.level", level),
		Role = "Number",
		TextSize = math.floor(h * (if theme.Id == "Classic" then 0.34 else 0.44)),
		Color = c.Text,
		Position = UDim2.fromOffset(12, 3),
		Size = UDim2.new(1, -24, 0, math.floor(h * 0.55)),
		Parent = lv,
	})
	local track = frame({
		Name = "ExpTrack",
		BackgroundTransparency = 0,
		BackgroundColor3 = c.Panel,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -7),
		Size = UDim2.new(1, -24, 0, if theme.Id == "Classic" then 6 else 5),
		Parent = lv,
	})
	Common.Corner(track, if theme.Id == "Classic" then UDim.new(0, 0) else UDim.new(0.5, 0))
	local fill = frame({
		Name = "Fill",
		BackgroundTransparency = 0,
		BackgroundColor3 = c.Exp,
		Size = UDim2.fromScale(math.clamp(exp / math.max(need, 1), 0.02, 1), 1),
		Parent = track,
	})
	Common.Corner(fill, if theme.Id == "Classic" then UDim.new(0, 0) else UDim.new(0.5, 0))
	Common.Chip(theme, {
		Name = "Gold",
		Icon = "Gold",
		Text = Common.L("common.gold", Common.Num(if profile then profile.Gold or 0 else 0)),
		Color = c.Gold,
		TextColor = c.Gold:Lerp(c.Text, if theme.Id == "Classic" then 0 else 0.25),
		Height = h,
		LayoutOrder = 2,
		Parent = row,
	})
	if props.Parent then
		row.Parent = props.Parent
	end
	return row
end

function Common.Empty(theme: Theme, text: string, props: { [string]: any }?): Frame
	local p = props or {}
	local root = frame({
		Name = "Empty",
		Size = p.Size or UDim2.fromScale(1, 1),
		Position = p.Position or UDim2.new(),
		LayoutOrder = p.LayoutOrder or 0,
	})
	local heart = UIKit.Heart(theme.Colors.StrokeDim, 26)
	heart.Position = UDim2.new(0.5, 0, 0.5, -22)
	heart.Parent = root
	UIKit.Label(theme, {
		Text = text,
		Role = "Body",
		Tone = "Dim",
		Dialogue = theme.Id == "Classic",
		XAlign = "Center",
		Wrap = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 2),
		Size = UDim2.new(0.86, 0, 0, 60),
		YAlign = "Top",
		Parent = root,
	})
	if p.Parent then
		root.Parent = p.Parent
	end
	return root
end

function Common.Swatch(theme: Theme, kit: any, skin: any, props: { [string]: any }): Frame
	local c = theme.Colors
	local size: number = props.Size or 44
	local colors = Common.SkinColors(kit, skin)
	local rarity = Themes.Rarity(theme, skin and skin.Rarity or "Common")
	local root = frame({
		Name = props.Name or ("Swatch_" .. tostring(skin and skin.Id)),
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = props.LayoutOrder or 0,
	})
	local round = theme.Id ~= "Classic" and theme.Id ~= "Fell"
	local well = frame({
		Name = "Well",
		BackgroundTransparency = 0,
		BackgroundColor3 = colors[1],
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -6, 1, -6),
		ClipsDescendants = true,
		Parent = root,
	})
	Common.Corner(well, if round then UDim.new(0.5, 0) else UDim.new(0, if theme.Id == "Classic" then 0 else 3))
	-- lower-right diagonal band with the secondary colour + an accent dot
	local band = frame({
		Name = "Band",
		BackgroundTransparency = 0,
		BackgroundColor3 = colors[2],
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.78, 0.78),
		Size = UDim2.fromScale(1.3, 0.62),
		Rotation = -40,
		Parent = well,
	})
	band.ZIndex = 1
	local dot = frame({
		Name = "Accent",
		BackgroundTransparency = 0,
		BackgroundColor3 = colors[3],
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.33, 0.35),
		Size = UDim2.fromScale(0.26, 0.26),
		ZIndex = 2,
		Parent = well,
	})
	Common.Corner(dot, if round then UDim.new(0.5, 0) else UDim.new(0, 0))
	Common.Gradient(well, nil, nil, 45).Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 200))
	local ring =
		Common.Stroke(well, rarity, if props.Selected then 3 else 2, if props.Locked then 0.45 else 0, theme.LineJoin)
	ring.Name = "Rarity"
	if props.Selected then
		local sel = frame({
			Name = "Selected",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 4, 1, 4),
			Parent = root,
		})
		Common.Corner(sel, if round then UDim.new(0.5, 0) else UDim.new(0, if theme.Id == "Classic" then 0 else 5))
		Common.Stroke(sel, if theme.Id == "Classic" then c.Selected else c.Accent, 2, 0, theme.LineJoin)
	end
	if props.Locked then
		local veil = frame({
			Name = "Veil",
			BackgroundTransparency = 0.45,
			BackgroundColor3 = BLACK,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -6, 1, -6),
			ZIndex = 3,
			Parent = root,
		})
		Common.Corner(veil, if round then UDim.new(0.5, 0) else UDim.new(0, 0))
		local lock = Icons.Create("Lock", c.Text, UDim2.fromScale(0.42, 0.42))
		lock.ZIndex = 4
		lock.Parent = veil
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return root
end

-- cleanup bag -----------------------------------------------------------------------------------------
function Common.Bag(): any
	local items: { any } = {}
	local bag = {}
	function bag.Add(x: any): any
		table.insert(items, x)
		return x
	end
	function bag.Connect(signal: any, fn: (...any) -> ()): any
		if signal == nil then
			return nil
		end
		local ok, conn = pcall(function()
			if typeof(signal) == "RBXScriptSignal" then
				return signal:Connect(fn)
			end
			return signal:Connect(fn)
		end)
		if ok and conn then
			table.insert(items, conn)
			return conn
		end
		return nil
	end
	function bag.Clean()
		for i = #items, 1, -1 do
			local x = items[i]
			items[i] = nil
			pcall(function()
				if typeof(x) == "RBXScriptConnection" then
					x:Disconnect()
				elseif type(x) == "function" then
					x()
				elseif typeof(x) == "Instance" then
					x:Destroy()
				elseif type(x) == "table" then
					if type(x.Disconnect) == "function" then
						x:Disconnect()
					elseif type(x.Destroy) == "function" then
						x.Destroy()
					end
				end
			end)
		end
	end
	return bag
end

-- key hints ------------------------------------------------------------------------------------------
local GAMEPAD_KEYS: { [string]: string } = {
	Back = "ButtonB",
	Confirm = "ButtonA",
	PrevTab = "ButtonL1",
	NextTab = "ButtonR1",
	Menu = "ButtonStart",
}
local KEYBOARD_KEYS: { [string]: string } = {
	Back = "Backspace",
	Confirm = "Enter",
	PrevTab = "Q",
	NextTab = "E",
	Menu = "M",
}

function Common.Device(deps: any): string
	local input = deps and deps.Input
	if input and type(input.Device) == "function" then
		local ok, d = pcall(input.Device)
		if ok and type(d) == "string" then
			return d
		end
	end
	if deps and type(deps.Device) == "string" then
		return deps.Device
	end
	return "KeyboardMouse"
end

function Common.KeyFor(deps: any, action: string): string
	local device = Common.Device(deps)
	if device == "Gamepad" then
		return GAMEPAD_KEYS[action] or action
	end
	if action == "Back" or action == "Menu" or action == "Confirm" then
		local input = deps and deps.Input
		if input and type(input.KeyLabel) == "function" then
			local ok, label = pcall(input.KeyLabel, action)
			if ok and type(label) == "string" and label ~= "" then
				return label
			end
		end
	end
	return KEYBOARD_KEYS[action] or action
end

function Common.Hints(theme: Theme, deps: any, hints: { { [string]: any } }, props: { [string]: any }): Frame?
	if Common.Device(deps) == "Touch" then
		return nil
	end
	local row = frame({
		Name = "Hints",
		AnchorPoint = props.AnchorPoint or Vector2.new(1, 1),
		Position = props.Position or UDim2.fromScale(1, 1),
		Size = props.Size or UDim2.new(1, 0, 0, 26),
	})
	local list = UIKit.ListLayout(
		row,
		{
			Horizontal = true,
			Gap = 14,
			HAlign = props.HAlign or Enum.HorizontalAlignment.Right,
			VAlign = Enum.VerticalAlignment.Center,
		}
	)
	list.HorizontalAlignment = props.HAlign or Enum.HorizontalAlignment.Right
	for i, h in hints do
		local key = h.Key or Common.KeyFor(deps, h.Action or "Back")
		UIKit.KeyHint(theme, { Key = key, Label = h.Label, Height = props.Height or 24, LayoutOrder = i, Parent = row })
	end
	if props.Parent then
		row.Parent = props.Parent
	end
	return row
end

-- screen chrome ----------------------------------------------------------------------------------------
local BACKDROP_ALPHA: { [string]: number } = { Classic = 0.04, Royal = 0.08, Void = 0.16, Fell = 0.08 }

function Common.Metrics(layout: any): { Margin: number, HeaderH: number, Gap: number, FooterH: number }
	local phone = layout.Phone == true
	local compact = layout.Compact == true
	return {
		Margin = if phone then 18 elseif compact then 24 else 36,
		HeaderH = if phone then 52 elseif compact then 64 else 92,
		Gap = if phone then 10 elseif compact then 14 else 22,
		FooterH = if phone then 0 else 34,
	}
end

function Common.Screen(theme: Theme, deps: any, opts: { [string]: any }): ScreenFrame
	local c = theme.Colors
	local layout = Common.Layout(deps)
	local canvas: Vector2 = layout.Canvas
	local phone = layout.Phone == true
	local compact = layout.Compact == true
	local m = Common.Metrics(layout)
	local bag = Common.Bag()

	local root = frame({ Name = opts.Name or "Screen", Size = UDim2.fromScale(1, 1) })
	local backdropMode: string = opts.Backdrop or "Full"
	if backdropMode == "Full" then
		local bd = UIKit.Backdrop(theme, { Parent = root })
		bd.BackgroundTransparency = BACKDROP_ALPHA[theme.Id] or 0.08
		Common.Bleed(bd, layout)
	elseif backdropMode == "Dim" then
		local dim = frame({
			Name = "Dim",
			BackgroundTransparency = 0.35,
			BackgroundColor3 = c.Overlay,
			Size = UDim2.fromScale(1, 1),
			Parent = root,
		})
		Common.Gradient(dim, nil, Common.NSeq({ { 0, 0.15 }, { 0.5, 0.55 }, { 1, 0.15 } }), 0)
		Common.Bleed(dim, layout)
	end

	-- header
	local header = frame({
		Name = "Header",
		Position = UDim2.fromOffset(m.Margin, if phone then 8 else 18),
		Size = UDim2.new(1, -m.Margin * 2, 0, m.HeaderH),
		ZIndex = 5,
		Parent = root,
	})
	local iconBox = if phone then 34 elseif compact then 44 else 58
	local textX = 0
	if opts.Icon then
		local tile = frame({
			Name = "IconTile",
			BackgroundTransparency = if theme.Id == "Void" then 0.4 else 0,
			BackgroundColor3 = c.PanelInset,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, if phone then 0 else -4),
			Size = UDim2.fromOffset(iconBox, iconBox),
			Parent = header,
		})
		Common.Corner(
			tile,
			if theme.Id == "Void"
				then UDim.new(0.5, 0)
				elseif theme.Id == "Royal" then UDim.new(0, 8)
				else theme.SmallCorner
		)
		local s = Common.Stroke(tile, c.Stroke, if theme.Id == "Classic" then 3 else 2, 0, theme.LineJoin)
		if theme.Gradients.Stroke then
			Common.Gradient(s, theme.Gradients.Stroke, nil, 45)
		end
		if theme.Id == "Fell" then
			tile.Rotation = 45
			tile.Size = UDim2.fromOffset(iconBox * 0.78, iconBox * 0.78)
			tile.Position = UDim2.new(0, iconBox * 0.11, 0.5, if phone then 0 else -4)
		end
		local icon = Icons.Create(opts.Icon, c.Accent, UDim2.fromScale(0.6, 0.6), c.Accent2)
		icon.Parent = tile
		if theme.Id == "Fell" then
			icon.Rotation = -45
		end
		textX = iconBox + (if phone then 12 else 18)
	end
	local titleSize = if phone
		then math.floor(theme.TextSize.Title * 0.72)
		elseif compact then math.floor(theme.TextSize.Title * 0.85)
		else theme.TextSize.Title
	local title = UIKit.Title(theme, {
		Text = opts.Title or "",
		Role = "Title",
		TextSize = titleSize,
		Subtitle = if phone then nil else opts.Subtitle,
		Size = UDim2.new(0.5, -textX, 0, math.ceil(titleSize * 1.2)),
		Position = UDim2.new(
			0,
			textX,
			0,
			if phone
				then math.floor((m.HeaderH - titleSize * 1.2) / 2)
				else (if opts.Subtitle then 2 else math.floor((m.HeaderH - titleSize * 1.2) / 2))
		),
		Glow = false,
	})
	title.Root.Parent = header

	-- right side: currency + close
	local right = frame({
		Name = "Right",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, if phone then 0 else -4),
		Size = UDim2.new(0.5, 0, 1, 0),
		Parent = header,
	})
	local rl = UIKit.ListLayout(
		right,
		{
			Horizontal = true,
			Gap = if phone then 8 else 14,
			HAlign = Enum.HorizontalAlignment.Right,
			VAlign = Enum.VerticalAlignment.Center,
		}
	)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	if opts.Currency ~= false then
		local profile = Common.Profile(deps)
		Common.Currency(
			theme,
			profile,
			{ Height = if phone then 30 else 38, Compact = phone, LayoutOrder = 1, Parent = right }
		)
	end
	if opts.Extra then
		opts.Extra.LayoutOrder = 2
		opts.Extra.Parent = right
	end
	local back: GuiObject? = nil
	if opts.OnBack ~= false then
		local btn = UIKit.Button(theme, {
			Name = "Close",
			Variant = "Icon",
			Icon = "Close",
			Height = if phone then 36 elseif compact then 44 else 50,
			LayoutOrder = 9,
			OnActivated = function()
				if type(opts.OnBack) == "function" then
					opts.OnBack()
				else
					local ui = deps and deps.UI
					if ui and type(ui.Back) == "function" then
						ui.Back()
					elseif deps and deps.UIRoot then
						deps.UIRoot.Pop()
					end
				end
			end,
		})
		btn.Root.Parent = right
		back = btn.Root
	end

	-- body + footer
	local bodyTop = (if phone then 8 else 18) + m.HeaderH + m.Gap
	local footer = frame({
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, m.Margin, 1, -10),
		Size = UDim2.new(1, -m.Margin * 2, 0, m.FooterH - 8),
		ZIndex = 5,
		Parent = root,
	})
	local body = frame({
		Name = "Body",
		Position = UDim2.fromOffset(m.Margin, bodyTop),
		Size = UDim2.new(1, -m.Margin * 2, 1, -bodyTop - m.FooterH - (if phone then 10 else 12)),
		ZIndex = 4,
		Parent = root,
	})
	if not phone and opts.Hints ~= false then
		local hints = opts.Hints or {}
		local list = table.clone(hints)
		table.insert(list, { Action = "Back", Label = Common.L("scr.back") })
		Common.Hints(theme, deps, list, { Parent = footer, Height = 22 })
	end

	return {
		Root = root,
		Body = body,
		Header = header,
		Footer = footer,
		Layout = layout,
		Canvas = canvas,
		Compact = compact,
		Phone = phone,
		Margin = m.Margin,
		Gap = m.Gap,
		Bag = bag,
		Back = back,
		Destroy = function()
			bag.Clean()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- 3D rig viewport ---------------------------------------------------------------------------------------
local function boundsOf(model: Instance): (Vector3, Vector3)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	local any = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local p = d.CFrame.Position
			local s = d.Size * 0.5
			local r = math.max(s.X, s.Z) -- loose (rotation-agnostic) horizontal extent
			minV = Vector3.new(math.min(minV.X, p.X - r), math.min(minV.Y, p.Y - s.Y), math.min(minV.Z, p.Z - r))
			maxV = Vector3.new(math.max(maxV.X, p.X + r), math.max(maxV.Y, p.Y + s.Y), math.max(maxV.Z, p.Z + r))
			any = true
		end
	end
	if not any then
		return Vector3.new(-1, 0, -1), Vector3.new(1, 5, 1)
	end
	return minV, maxV
end

local function buildRig(kit: any, skinId: string?, style: string?, styler: ((Model) -> ())?): (Model?, number)
	local rigBuilder = Common.Module({ "Rigs", "RigBuilder" })
	if rigBuilder == nil then
		return nil, 0
	end
	local model: Model? = nil
	local ok, result = pcall(rigBuilder.Build, kit.Rig, { Skin = skinId, Name = "Preview_" .. kit.Id })
	if ok then
		model = result
	else
		-- the kit blueprint is not written yet: a dummy keeps the layout honest
		local okDummy, dummy = pcall(rigBuilder.Build, "Dummy", { Name = "Preview_" .. kit.Id })
		if okDummy then
			model = dummy
		end
	end
	if model == nil then
		return nil, 0
	end
	local family = if kit.Family == "Skeleton" then "Skeleton" else "Human"
	local poseName = if family == "Skeleton" then "Pockets" else "Ready"
	local pose = rigBuilder.GetPose(model:GetAttribute("RigFamily") or family, poseName)
		or rigBuilder.GetPose(family, poseName)
	if pose then
		pcall(rigBuilder.Pose, model, pose)
		pcall(rigBuilder.ApplyPose, model, pose)
	end
	if styler then
		-- runtime: RigStyleController.ApplyTo (current style incl. Style Lab override, HD meshes)
		pcall(styler, model)
	elseif style then
		local rigStyles = Common.Module({ "Rigs", "RigStyles" })
		if rigStyles then
			pcall(rigStyles.Apply, model, style)
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local minV, maxV = boundsOf(model)
	return model, maxV.Y - minV.Y
end

function Common.RigView(theme: Theme, props: { [string]: any }): RigViewHandle
	local kits = Common.Kits()
	local kit = kits and kits.Get(props.Kit or "")
	local tint: Color3 = if kit then kit.Color else theme.Colors.Accent
	local view = UIKit.Viewport(theme, {
		Name = props.Name or "RigView",
		Color = tint,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		FieldOfView = 28,
		LightDirection = Vector3.new(-0.55, -0.9, -0.6),
		Ambient = Color3.fromRGB(140, 140, 160),
	})
	local root = view.Root
	local vpf = view.Viewport
	local world = Instance.new("WorldModel")
	world.Parent = vpf
	local model: Model? = nil
	local yaw = math.rad(props.Yaw or -24)
	local baseCam = view.Camera.CFrame
	local baseLight = Vector3.new(-0.55, -0.9, -0.6)
	local function placeCamera(height: number)
		local h = math.max(height, 3)
		local centerY = h * 0.5
		local fov = math.rad(view.Camera.FieldOfView)
		local dist = (h * 0.58) / math.tan(fov / 2)
		-- camera in front of the rig (rig faces -Z), slightly above, looking back at it (basis vectors are
		-- built by hand: no CFrame.lookAt, which is mirrored under Lune)
		local pitch = math.rad(-6)
		local pos = Vector3.new(0, centerY + dist * math.sin(-pitch), -dist * math.cos(pitch))
		baseCam = CFrame.new(pos) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(pitch, 0, 0)
	end
	-- turning the rig by +yaw == orbiting camera and light by -yaw around it: only the camera moves per
	-- frame (cheap), the parts stay put
	local function applyYaw()
		local rot = CFrame.Angles(0, -yaw, 0)
		view.Camera.CFrame = rot * baseCam
		vpf.LightDirection = rot * baseLight
	end
	local function set(kitId: string?, skinId: string?)
		if model then
			model:Destroy()
			model = nil
		end
		local k = kits and kitId and kits.Get(kitId)
		if k == nil then
			return
		end
		local built, height = buildRig(k, skinId, props.Style, props.Styler)
		if built then
			model = built
			placeCamera(height)
			applyYaw()
			built.Parent = world
		end
	end
	set(props.Kit, props.Skin)
	-- slow turntable + drag to spin (runtime only; offline the model stays at its 3/4 angle)
	local spin = math.rad(props.Spin or 16)
	local dragging = false
	local lastAx: number? = nil
	Motion.Loop(root, function(dt: number)
		if not dragging then
			yaw += spin * dt
			applyYaw()
		end
	end)
	Motion.BindDrag(root, function(ax: number)
		dragging = true
		if lastAx then
			yaw += (ax - lastAx) * math.pi * 2
			applyYaw()
		end
		lastAx = ax
	end, function()
		dragging = false
		lastAx = nil
	end)
	if props.Parent then
		root.Parent = props.Parent
	end
	return {
		Root = root,
		Viewport = vpf,
		Set = set,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- samples (offline previews & tests) --------------------------------------------------------------------
function Common.SampleProfile(): any
	return {
		Version = 1,
		Level = 7,
		Exp = 312,
		Gold = 1840,
		Stats = {
			Rounds = 64,
			Wins = 31,
			MonsterWins = 9,
			HumanWins = 22,
			Kills = 48,
			Downs = 77,
			Damage = 18210,
			Healing = 2120,
			Parries = 63,
			Dodges = 211,
			Saves = 39,
			Revives = 27,
			BoxesSurvived = 6,
			MVPs = 4,
		},
		Unlocked = {
			ClassicSans = true,
			Determination = true,
			Bravery = true,
			Kindness = true,
			Patience = true,
			FellSans = true,
			["ClassicSans:Midnight"] = true,
			["Determination:Storyshift"] = true,
		},
		Equipped = {
			Human = "Determination",
			Monster = "ClassicSans",
			Skins = { ClassicSans = "Midnight" },
			Title = "wins_25",
		},
		Mastery = {
			ClassicSans = 2950,
			Determination = 1500,
			Bravery = 900,
			Kindness = 300,
			FellSans = 1250,
			Patience = 120,
		},
		MonsterChance = 3,
		RoundsSinceMonster = 2,
		RolePreference = "Either",
		Quests = {
			Window = 0,
			List = {
				{ Id = "DealDamage", Progress = 860, Goal = 1200, Claimed = false },
				{ Id = "Parries", Progress = 8, Goal = 8, Claimed = false },
				{ Id = "MonsterWin", Progress = 1, Goal = 1, Claimed = true },
			},
			Rerolled = false,
		},
		Achievements = { first_round = true, rounds_25 = true, first_win = true, monster_win = true, wins_25 = true },
		Login = { LastDay = 0, Streak = 4 },
		Settings = {},
		Titles = {
			first_round = true,
			rounds_25 = true,
			first_win = true,
			monster_win = true,
			wins_25 = true,
			m_ClassicSans_3 = true,
		},
		ShopToday = {
			Day = 0,
			Items = {
				{ KitId = "ClassicSans", SkinId = "Judge", Discount = 25, Featured = true },
				{ KitId = "Bravery", SkinId = "Champion" },
				{ KitId = "Patience", SkinId = "Frost" },
				{ KitId = "FellSans", SkinId = "Ash" },
			},
		},
	}
end

-- sample profile with achievements/titles derived from the real rules (Shared/Progression) when present
local baseSample = Common.SampleProfile
function Common.SampleProfile(): any
	local p = baseSample()
	local module = Common.Progression("Achievements")
	if module and type(module.Check) == "function" then
		local ok, ids = pcall(module.Check, p)
		if ok and type(ids) == "table" then
			for _, id in ids do
				p.Achievements[id] = true
				p.Titles[id] = true
			end
		end
	end
	return p
end

function Common.SampleRound(): { [string]: any }
	return {
		Phase = "Intermission",
		PhaseEndsAt = os.time() + 18,
		MapId = "HallOfVerdicts",
		HumansAlive = 0,
		HumansTotal = 0,
		Practice = false,
		Winner = "",
	}
end

function Common.SampleLeaderboards(): any
	return {
		Wins = {
			{ name = "papyrus_fan", value = 412 },
			{ name = "Frisk", value = 388 },
			{ name = "TemmieFlakes", value = 301 },
			{ name = "bad_time_bob", value = 254 },
			{ name = "NapstaHook", value = 199 },
			{ name = "ketchup_bottle", value = 171 },
			{ name = "MettatonEXtra", value = 140 },
			{ name = "annoying_dog", value = 96 },
		},
		Level = {
			{ name = "Frisk", value = 61 },
			{ name = "papyrus_fan", value = 58 },
			{ name = "bad_time_bob", value = 44 },
			{ name = "TemmieFlakes", value = 39 },
			{ name = "NapstaHook", value = 33 },
			{ name = "annoying_dog", value = 30 },
			{ name = "ketchup_bottle", value = 21 },
			{ name = "MettatonEXtra", value = 17 },
		},
	}
end

function Common.SampleResult(): any
	return {
		winner = "Humans",
		reason = "Defeated",
		mvpUserId = 1,
		practice = false,
		mapId = "HallOfVerdicts",
		stats = {
			{
				userId = 1,
				name = "Frisk",
				team = "Humans",
				kitId = "Determination",
				damage = 1840,
				healing = 0,
				kills = 1,
				downs = 0,
				parries = 6,
				dodgesForced = 9,
				saves = 2,
				revives = 1,
				survived = true,
			},
			{
				userId = 2,
				name = "TemmieFlakes",
				team = "Humans",
				kitId = "Kindness",
				damage = 410,
				healing = 920,
				kills = 0,
				downs = 1,
				parries = 2,
				dodgesForced = 3,
				saves = 1,
				revives = 2,
				survived = true,
			},
			{
				userId = 3,
				name = "NapstaHook",
				team = "Humans",
				kitId = "Justice",
				damage = 1210,
				healing = 0,
				kills = 0,
				downs = 1,
				parries = 0,
				dodgesForced = 7,
				saves = 0,
				revives = 0,
				survived = false,
			},
			{
				userId = 4,
				name = "papyrus_fan",
				team = "Humans",
				kitId = "Bravery",
				damage = 960,
				healing = 0,
				kills = 0,
				downs = 2,
				parries = 4,
				dodgesForced = 5,
				saves = 0,
				revives = 0,
				survived = true,
			},
			{
				userId = 5,
				name = "bad_time_bob",
				team = "Monster",
				kitId = "ClassicSans",
				damage = 2630,
				healing = 0,
				kills = 1,
				downs = 5,
				parries = 0,
				dodgesForced = 0,
				saves = 0,
				revives = 0,
				survived = false,
			},
		},
	}
end

function Common.SampleRewards(): any
	-- shape of RewardService's RoundEvent "Rewards" packet
	return {
		exp = 148,
		gold = 95,
		items = {
			{ key = "prog.reward.participation", exp = 40, gold = 20 },
			{ key = "prog.reward.win", exp = 50, gold = 30 },
			{ key = "prog.reward.damage", exp = 37, gold = 18, count = 1840 },
			{ key = "prog.reward.parries", exp = 12, gold = 6, count = 6 },
			{ key = "prog.reward.mvp", exp = 9, gold = 21 },
		},
		levelUp = true,
		levels = 1,
		newLevel = 8,
		level = 8,
		expInto = 0,
		expToNext = 520,
		unlocked = { "title:first_win", "skin:FellSans:Ash", "achievement:first_win" },
		questProgress = {
			{ id = "DealDamage", key = "prog.quest.DealDamage", progress = 1200, goal = 1200, completed = true },
		},
		mastery = { kitId = "Determination", from = 4, to = 5, exp = 1640, into = 40, need = 400 },
		firstWin = true,
		practice = false,
	}
end

function Common.SampleAchievements(): { any }
	local function a(id: string, icon: string, en: string, ru: string, den: string, dru: string, title: string?): any
		return { Id = id, Icon = icon, Name = { en = en, ru = ru }, Desc = { en = den, ru = dru }, Title = title }
	end
	return {
		a(
			"FirstTrial",
			"Flag",
			"First Trial",
			"Первый суд",
			"Play your first round.",
			"Сыграй первый раунд."
		),
		a(
			"FirstWin",
			"Trophy",
			"Not Guilty",
			"Невиновен",
			"Win a round.",
			"Выиграй раунд.",
			"Judged"
		),
		a(
			"Parry25",
			"Shield",
			"Steel Nerves",
			"Стальные нервы",
			"Land 25 perfect parries.",
			"Сделай 25 идеальных парирований.",
			"Unbreakable"
		),
		a(
			"SaveAll",
			"Star",
			"Full Determination",
			"Полная решимость",
			"Light all 3 SAVE points in one round.",
			"Зажги все 3 SAVE за раунд."
		),
		a(
			"Judge10",
			"Skull",
			"Hanging Judge",
			"Суровый судья",
			"Win 10 rounds as the Monster.",
			"Выиграй 10 раундов монстром."
		),
		a(
			"Box10",
			"Box",
			"Out of the Box",
			"Вне коробки",
			"Survive 10 Verdict Boxes.",
			"Выживи в 10 Коробках Приговора."
		),
		a(
			"Revive20",
			"Heart",
			"Good Samaritan",
			"Добрая душа",
			"Revive allies 20 times.",
			"Подними союзников 20 раз."
		),
		a(
			"Mastery10",
			"Crown",
			"Master of One",
			"Мастер своего дела",
			"Reach mastery 10 with any kit.",
			"Достигни 10 мастерства с любым набором."
		),
		a(
			"Streak7",
			"Clock",
			"Regular",
			"Завсегдатай",
			"Log in 7 days in a row.",
			"Заходи 7 дней подряд."
		),
		a(
			"Dodge100",
			"Dash",
			"Not Today",
			"Не сегодня",
			"Force 100 dodges.",
			"Вызови 100 уклонений."
		),
	}
end

return Common
