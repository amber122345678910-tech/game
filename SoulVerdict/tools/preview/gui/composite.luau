--!nocheck
-- composite: offline preview of the WHOLE client UI stack on a device, built the way UIController does it at
-- runtime: the Title (Menu layer) over the HUD (Hud layer, Hud.Create with the live per-phase/menu visibility
-- rules) over a painted stand-in of the 3D lobby, inside an emulated device (notch insets, home indicator) with
-- the Roblox top bar (Roblox / menu / chat buttons, 58 px) drawn on top. Writes dump_gui-style JSON for
-- tools/preview/gui/render.mjs.
--
-- Usage (project root):
--   lune run tools/preview/gui/composite.luau --size 860x400 --out /tmp/c.json
--        [--state title|lobby|round|admin]   title = Title open in the lobby (default); lobby = menus closed,
--                                            waiting for players; round = touch round HUD; admin = Title + Admin
--        [--device auto|notch|iphone|plain|desktop]   device insets (auto: phones = notch, 1920 wide = desktop)
--        [--theme Classic] [--hud Battle] [--lang en|ru] [--admin] (player attributes Admin + StyleLab)
--        [--phase Waiting|Intermission]   lobby phase for title/lobby states (Intermission = map vote)
--        [--legacy]          pre-fix layering: layers on DeviceSafeInsets (under the top bar), layout from the full
--                            viewport, HUD drawn under the menus
--        [--stale 354x745]   build the screens with the layout of another viewport (UI built while the phone was
--                            still portrait, before it rotated) - reproduces the owner's screenshot with --legacy
-- Then: node tools/preview/gui/render.mjs --in /tmp/c.json --out shot.png
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../../lune/loader")

local args = {}
do
	local i = 1
	local raw = process.args
	while i <= #raw do
		local a = raw[i]
		if string.sub(a, 1, 2) == "--" then
			local key = string.sub(a, 3)
			local value = raw[i + 1]
			if value == nil or string.sub(value, 1, 2) == "--" then
				args[key] = true
				i += 1
			else
				args[key] = value
				i += 2
			end
		else
			i += 1
		end
	end
end

local function parseSize(text)
	local w, h = string.match(text or "", "^(%d+)x(%d+)$")
	assert(w and h, "size must look like 860x400: " .. tostring(text))
	return tonumber(w), tonumber(h)
end

local W, H = parseSize(args.size or "860x400")
local themeId = args.theme or "Classic"
local state = args.state or "title"
local legacy = args.legacy == true
local TOPBAR = 58

Loader.isServer = false
Loader.quietWarnings = true
local roblox = Loader.roblox
local Instance, UDim2, UDim, Vector2, Color3, Enum =
	roblox.Instance, roblox.UDim2, roblox.UDim, roblox.Vector2, roblox.Color3, roblox.Enum
local ColorSequence, ColorSequenceKeypoint, NumberSequence, NumberSequenceKeypoint =
	roblox.ColorSequence, roblox.ColorSequenceKeypoint, roblox.NumberSequence, roblox.NumberSequenceKeypoint

local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
Strings.SetLanguage(args.lang or "en")
local Themes = Loader.requirePath("src/client/UI/Themes")
local ThemeService = Loader.requirePath("src/client/UI/ThemeService")
local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
local Hud = Loader.requirePath("src/client/UI/Hud")
local Mock = Loader.requirePath("src/client/UI/Hud/Mock")
local Title = Loader.requirePath("src/client/UI/Screens/Title")
local Common = Loader.requirePath("src/client/UI/Screens/Common")
assert(Themes.Has(themeId), "unknown theme " .. tostring(themeId))
ThemeService.Set(themeId)
if args.hud then
	ThemeService.SetHudStyle(args.hud)
end
local theme = Themes.Get(themeId)

-- device ------------------------------------------------------------------------------------------------
local DEVICES = {
	notch = { L = 36, R = 36, T = 0, B = 0 }, -- Android with a camera hole (the owner's phone)
	iphone = { L = 44, R = 44, T = 0, B = 21 },
	plain = { L = 0, R = 0, T = 0, B = 0 },
	desktop = { L = 0, R = 0, T = 0, B = 0 },
}
local deviceId = args.device
if deviceId == nil or deviceId == true or deviceId == "auto" then
	deviceId = if W >= 1200 then "desktop" elseif W == 812 then "iphone" elseif W <= 760 then "plain" else "notch"
end
local dev = assert(DEVICES[deviceId], "unknown device " .. tostring(deviceId))
local touch = deviceId ~= "desktop"
-- legacy: IgnoreGuiInset + DeviceSafeInsets (device insets only); fixed: CoreUISafeInsets (+ the top bar)
local inset = { L = dev.L, R = dev.R, T = if legacy then dev.T else math.max(dev.T, TOPBAR), B = dev.B }
local usable = Vector2.new(W - inset.L - inset.R, H - inset.T - inset.B)
local layout
if legacy then
	layout = UIRoot.ComputeLayout(Vector2.new(W, H)) -- the old code measured camera.ViewportSize
else
	layout = UIRoot.ComputeLayout(usable, { Left = inset.L, Top = inset.T, Right = inset.R, Bottom = inset.B })
end
local buildLayout = layout
if args.stale and args.stale ~= true then
	local sw, sh = parseSize(args.stale)
	buildLayout = UIRoot.ComputeLayout(Vector2.new(sw, sh))
	buildLayout.Scale = layout.Scale -- the layer's UIScale follows the viewport; only the screens stay stale
end

-- helpers ------------------------------------------------------------------------------------------------
local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in props do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local function rect(name, x, y, w, h, color, transparency, parent, z)
	return make("Frame", {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = z or 1,
	}, parent)
end
local function corner(parent, radius)
	make("UICorner", { CornerRadius = radius }, parent)
end
local function vgrad(parent, keys)
	local list = {}
	for _, k in keys do
		table.insert(list, ColorSequenceKeypoint.new(k[1], k[2]))
	end
	make("UIGradient", { Color = ColorSequence.new(list), Rotation = 90 }, parent)
end

-- stage + painted lobby ------------------------------------------------------------------------------------
local stage = make("ScreenGui", { Name = "Stage", IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local world = rect("World", 0, 0, W, H, Color3.new(1, 1, 1), 0, stage, 0)
world.Size = UDim2.fromScale(1, 1)
vgrad(world, {
	{ 0, Color3.fromRGB(96, 160, 214) },
	{ 0.42, Color3.fromRGB(196, 222, 236) },
	{ 0.5, Color3.fromRGB(120, 168, 92) },
	{ 1, Color3.fromRGB(58, 104, 52) },
})
-- a plaza, a stage and a few lamp posts / players so contrast problems are visible
local plaza = rect("Plaza", math.floor(W * 0.22), math.floor(H * 0.6), math.floor(W * 0.56), math.floor(H * 0.3), Color3.fromRGB(232, 226, 210), 0, world, 1)
corner(plaza, UDim.new(0.5, 0))
local hall = rect("Hall", math.floor(W * 0.42), math.floor(H * 0.34), math.floor(W * 0.18), math.floor(H * 0.2), Color3.fromRGB(30, 28, 44), 0, world, 1)
rect("HallRoof", math.floor(W * 0.41), math.floor(H * 0.32), math.floor(W * 0.2), math.floor(H * 0.03), Color3.fromRGB(210, 170, 70), 0, world, 2)
local _ = hall
for i, x in { 0.18, 0.36, 0.66, 0.84 } do
	rect("Lamp" .. i, math.floor(W * x), math.floor(H * 0.38), 4, math.floor(H * 0.34), Color3.fromRGB(28, 24, 22), 0, world, 2)
	local bulb = rect("Bulb" .. i, math.floor(W * x) - 5, math.floor(H * 0.36), 14, 14, Color3.fromRGB(255, 226, 150), 0, world, 2)
	corner(bulb, UDim.new(0.5, 0))
end
for i, x in { 0.3, 0.58, 0.74 } do
	local body = rect("Player" .. i, math.floor(W * x), math.floor(H * 0.62), 14, 30, Color3.fromRGB(70, 60, 50), 0, world, 3)
	corner(body, UDim.new(0, 4))
end

-- layers -------------------------------------------------------------------------------------------------
local function layer(name, z)
	local holder = rect("Layer_" .. name, inset.L, inset.T, usable.X, usable.Y, Color3.new(0, 0, 0), 1, stage, z)
	local root = make("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1 / layout.Scale, 1 / layout.Scale),
	}, holder)
	make("UIScale", { Name = "DesignScale", Scale = layout.Scale }, root)
	return root
end
local hudRoot = layer("Hud", 5)
local menuRoot = layer("Menu", 10)

-- data ----------------------------------------------------------------------------------------------------
local profile = Common.SampleProfile()
profile.Level = 1
profile.Gold = 25
profile.Exp = 4
local playerName = "Itadori"
local attrs = { MonsterChance = 1, StyleLab = args.admin == true, Admin = args.admin == true, Role = "Lobby" }
local round = { Phase = if state == "round" then "Round" else "Waiting", PhaseEndsAt = 0 }
local fakeState = {
	Profile = function()
		return profile
	end,
	Round = function()
		return round
	end,
	Now = function()
		return 1000
	end,
	Phase = function()
		return round.Phase
	end,
}
local fakeUI = {
	Open = function() end,
	Close = function() end,
	Play = function() end,
}
local device = if touch then "Touch" else "KeyboardMouse"

-- which menu is open (the exclusivity rule reads it from the snapshot)
local menuName = if state == "title" or state == "admin" then "Title" else nil
if state == "admin" then
	menuName = "Admin"
end

-- HUD -----------------------------------------------------------------------------------------------------
local snap
if state == "round" then
	snap = Mock.Scenario("Touch")
	snap.Device = device
elseif args.phase == "Intermission" then
	snap = Mock.Scenario("Lobby")
	snap.Device = device
	snap.Me = Mock.Unit("Determination", playerName, { IsLocal = true, Level = 1 })
	round.Phase = "Intermission"
else
	snap = Mock.Scenario("LobbyWaiting")
	snap.Device = device
	snap.Me = Mock.Unit("Determination", playerName, { IsLocal = true, Level = 1 })
	snap.Chances = { { Name = playerName, UserId = 1, Chance = 1, Pref = "Either", IsLocal = true } }
end
snap.Menu = menuName
snap.MenuOpen = menuName ~= nil
local hud = Hud.Create(theme, {
	Snapshot = snap,
	Layout = buildLayout,
	Backdrop = false,
	Hud = args.hud,
	Device = device,
	PlayerName = playerName,
	Attrs = attrs,
})
hud.Root.Parent = hudRoot

-- menus ---------------------------------------------------------------------------------------------------
local deps = {
	Layout = buildLayout,
	State = fakeState,
	UI = fakeUI,
	Profile = profile,
	PlayerName = playerName,
	Attrs = attrs,
	Device = device,
}
if state == "title" or state == "admin" then
	local title = Title.Create(theme, deps)
	title.Root.Parent = menuRoot
	-- UIRoot.Push hides the previous top screen
	title.Root.Visible = state ~= "admin"
end
if state == "admin" then
	local ok, Admin = pcall(Loader.requirePath, "src/client/UI/Screens/Admin")
	if ok and type(Admin) == "table" and Admin.Create then
		local okCreate, handle = pcall(Admin.Create, theme, deps)
		if okCreate and handle and handle.Root then
			handle.Root.Parent = menuRoot
		else
			print("composite: Admin.Create failed: " .. tostring(handle))
		end
	else
		print("composite: no Admin screen yet")
	end
end

-- Roblox top bar (core UI, always on top): Roblox button + menu + chat at the top-left -----------------------
local bar = rect("RobloxTopbar", inset.L + 12, 8, 148, 44, Color3.fromRGB(18, 18, 22), 0.35, stage, 100)
corner(bar, UDim.new(0.5, 0))
for i = 0, 2 do
	local b = rect("CoreButton" .. i, 6 + i * 48, 4, 36, 36, Color3.fromRGB(30, 30, 36), 0.1, bar, 101)
	corner(b, UDim.new(0.5, 0))
	local glyph = rect("Glyph", 10, 10, 16, 16, Color3.new(1, 1, 1), 0, b, 102)
	if i == 0 then
		glyph.Rotation = 15
	elseif i == 1 then
		glyph.Size = UDim2.fromOffset(16, 3)
		glyph.Position = UDim2.fromOffset(10, 16)
	else
		corner(glyph, UDim.new(0, 4))
	end
end
if touch then
	-- Roblox's default thumbstick + jump button (PlayerGui.TouchGui, drawn UNDER our layers; hidden by
	-- UIController while a menu is open after the fix). Small-screen TouchJump: 70x70 at (W-95, H-90).
	local showTouch = legacy or menuName == nil
	if showTouch then
		local stick = rect("Thumbstick", 30, H - 140, 110, 110, Color3.new(0, 0, 0), 0.75, stage, 4)
		corner(stick, UDim.new(0.5, 0))
		make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.6, Thickness = 2 }, stick)
		local jump = rect("JumpButton", W - 95, H - 90, 70, 70, Color3.new(0, 0, 0), 0.7, stage, 4)
		corner(jump, UDim.new(0.5, 0))
		make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.5, Thickness = 2 }, jump)
	end
end

-- serialization (same format as tools/lune/dump_gui.luau) ----------------------------------------------------
local PROPS = {
	GuiObject = {
		"Position", "Size", "AnchorPoint", "Rotation", "ZIndex", "LayoutOrder", "Visible", "ClipsDescendants",
		"BackgroundColor3", "BackgroundTransparency", "BorderSizePixel", "BorderColor3", "AutomaticSize", "SizeConstraint",
	},
	Text = {
		"Text", "TextColor3", "TextSize", "TextScaled", "TextWrapped", "RichText", "FontFace", "TextXAlignment",
		"TextYAlignment", "TextTransparency", "TextStrokeColor3", "TextStrokeTransparency", "LineHeight",
		"MaxVisibleGraphemes", "TextTruncate",
	},
	Image = { "Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter", "ResampleMode" },
	ScreenGui = { "DisplayOrder", "IgnoreGuiInset", "Enabled", "ZIndexBehavior", "ScreenInsets" },
	CanvasGroup = { "GroupTransparency", "GroupColor3" },
	ScrollingFrame = {
		"CanvasSize", "CanvasPosition", "AutomaticCanvasSize", "ScrollingDirection", "ScrollBarThickness",
		"ScrollBarImageColor3", "ScrollBarImageTransparency", "VerticalScrollBarInset",
	},
	ViewportFrame = { "Ambient", "LightColor", "LightDirection", "ImageColor3", "ImageTransparency" },
	UIStroke = { "Color", "Thickness", "Transparency", "ApplyStrokeMode", "LineJoinMode", "Enabled", "BorderStrokePosition", "BorderOffset", "StrokeSizingMode" },
	UICorner = { "CornerRadius" },
	UIGradient = { "Color", "Transparency", "Rotation", "Offset", "Enabled" },
	UIPadding = { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" },
	UIListLayout = { "FillDirection", "Padding", "SortOrder", "HorizontalAlignment", "VerticalAlignment", "Wraps", "HorizontalFlex", "VerticalFlex", "ItemLineAlignment" },
	UIGridLayout = { "CellSize", "CellPadding", "FillDirection", "FillDirectionMaxCells", "SortOrder", "HorizontalAlignment", "VerticalAlignment", "StartCorner" },
	UIAspectRatioConstraint = { "AspectRatio", "AspectType", "DominantAxis" },
	UISizeConstraint = { "MinSize", "MaxSize" },
	UITextSizeConstraint = { "MinTextSize", "MaxTextSize" },
	UIScale = { "Scale" },
	UIFlexItem = { "FlexMode", "GrowRatio", "ShrinkRatio", "ItemLineAlignment" },
}

local function num(x)
	if x ~= x then
		return 0
	end
	if x > 1e9 then
		return 1e9
	elseif x < -1e9 then
		return -1e9
	end
	return math.floor(x * 10000 + 0.5) / 10000
end

local function encode(v)
	local t = typeof(v)
	if t == "number" then
		return num(v)
	elseif t == "boolean" or t == "string" then
		return v
	elseif t == "UDim2" then
		return { num(v.X.Scale), num(v.X.Offset), num(v.Y.Scale), num(v.Y.Offset) }
	elseif t == "UDim" then
		return { num(v.Scale), num(v.Offset) }
	elseif t == "Vector2" then
		return { num(v.X), num(v.Y) }
	elseif t == "Color3" then
		return { num(v.R), num(v.G), num(v.B) }
	elseif t == "EnumItem" then
		return v.Name
	elseif t == "Font" then
		return { family = v.Family, weight = v.Weight.Name, style = v.Style.Name }
	elseif t == "ColorSequence" then
		local out = {}
		for _, k in v.Keypoints do
			table.insert(out, { num(k.Time), num(k.Value.R), num(k.Value.G), num(k.Value.B) })
		end
		return out
	elseif t == "NumberSequence" then
		local out = {}
		for _, k in v.Keypoints do
			table.insert(out, { num(k.Time), num(k.Value) })
		end
		return out
	elseif t == "Rect" then
		return { num(v.Min.X), num(v.Min.Y), num(v.Max.X), num(v.Max.Y) }
	end
	return nil
end

local function propListFor(inst)
	local lists = {}
	if inst:IsA("GuiObject") then
		table.insert(lists, PROPS.GuiObject)
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		table.insert(lists, PROPS.Text)
	end
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		table.insert(lists, PROPS.Image)
	end
	if PROPS[inst.ClassName] then
		table.insert(lists, PROPS[inst.ClassName])
	end
	return lists
end

local count = 0
local function serialize(inst)
	count += 1
	local props = {}
	for _, list in propListFor(inst) do
		for _, name in list do
			local ok, value = pcall(function()
				return inst[name]
			end)
			if ok and value ~= nil then
				local e = encode(value)
				if e ~= nil then
					props[name] = e
				end
			end
		end
	end
	local children = {}
	for _, child in inst:GetChildren() do
		table.insert(children, serialize(child))
	end
	return { class = inst.ClassName, name = inst.Name, props = props, children = children }
end

local doc = {
	version = 1,
	viewport = { W, H },
	scale = layout.Scale,
	canvas = { num(layout.Canvas.X), num(layout.Canvas.Y) },
	theme = themeId,
	screen = "composite:" .. state,
	root = serialize(stage),
}
local json = serde.encode("json", doc, false)
if args.out and args.out ~= true then
	fs.writeFile(args.out, json)
	print(
		("composite: %s %s %dx%d %s%s -> %s (scale %.3f, canvas %dx%d, %d instances)"):format(
			state,
			themeId,
			W,
			H,
			deviceId,
			if legacy then " legacy" else "",
			args.out,
			layout.Scale,
			math.floor(layout.Canvas.X),
			math.floor(layout.Canvas.Y),
			count
		)
	)
else
	print(json)
end
