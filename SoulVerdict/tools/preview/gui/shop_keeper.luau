--!nocheck
-- shop_keeper: offline preview of the Shop screen (src/client/UI/Screens/Shop) with sleepy Sans, the shopkeeper
-- (Screens/ShopKeeper), on a device the way it runs: phones get the CoreUISafeInsets usable rect below the Roblox top
-- bar (58 px, drawn on top) + notch insets, the layout comes from UIRoot.ComputeLayout(usable, safe) like UIRoot does.
-- The keeper is posed at a moment of his wake-up (Shop deps.KeeperAt). Writes dump_gui-style JSON for
-- tools/preview/gui/render.mjs.
--
-- Usage (project root):
--   lune run tools/preview/gui/shop_keeper.luau --size 860x400 --out /tmp/s.json
--        [--theme Classic] [--lang en|ru] [--device auto|notch|iphone|plain|desktop] [--no-topbar]
--        [--tab Daily|All] [--kit FellSans]       phone tab / kit rail selection
--        [--t 2.5]                                keeper time in seconds since the shop opened (default: settled,
--                                                 the whole greeting shown)
--        [--say thanks|poor --say-at 4]           he says shop.keeper.<line> at --say-at s (then --t poses a moment)
--        [--reduced]                              Reduced Motion (no bob / hop, standing Z letters, no snow)
--        [--gold 25]                              the sample profile's G
--        [--no-keeper]                            the Shop without him (Shop deps.Keeper = false), to compare
--        [--frames 40 --fps 12 --outdir dir]      one JSON per frame from --from (default 0) s: dir/frame_00.json ...
--        [--seams]                                keep the renderer's hairline seams in the pixel art (see below)
-- Pixel art: in Roblox the scene sits on whole screen pixels (ShopKeeper Snap) and every cell is Pixel screen px, so
-- the frames meet exactly. The HTML renderer applies the UIScale as a CSS transform and Chromium snaps boxes in DESIGN
-- px, then anti-aliases the scaled edges: rows of one colour would show dark hairlines between them. So, unless
-- --seams, every painted cell under the scene is drawn 1 design px taller (into the next row, which is painted later
-- and covers it), which hides those seams without moving any edge.
-- Every document carries `crop` = the keeper panel's rect in screen px ({x, y, w, h}) for cropping a GIF.
-- previews/ui/shop_keeper_phone.png  = --size 860x400 --theme Classic --t 3.4   (render.mjs)
-- previews/ui/shop_keeper_desktop.png = --size 1920x1080 --theme Classic --t 3.4
-- previews/ui/shop_keeper_wake.gif   = --size 860x400 --frames 44 --fps 12 --outdir dir, each frame rendered to
--   dir/frame_NN.png, then cropped to `crop` (+8 px) and saved with PIL (duration 1000/fps ms, loop 0).
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

local W, H = string.match(args.size or "860x400", "^(%d+)x(%d+)$")
assert(W and H, "--size must look like 860x400")
W, H = tonumber(W), tonumber(H)
local themeId = args.theme or "Classic"
local TOPBAR = 58

Loader.isServer = false
Loader.quietWarnings = true
local roblox = Loader.roblox
local Vector2, UDim2, UDim, Color3 = roblox.Vector2, roblox.UDim2, roblox.UDim, roblox.Color3
local Instance, Enum, ColorSequence, ColorSequenceKeypoint =
	roblox.Instance, roblox.Enum, roblox.ColorSequence, roblox.ColorSequenceKeypoint

local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
Strings.SetLanguage(if args.lang and args.lang ~= true then args.lang else "en")
local Themes = Loader.requirePath("src/client/UI/Themes")
local ThemeService = Loader.requirePath("src/client/UI/ThemeService")
local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
local Common = Loader.requirePath("src/client/UI/Screens/Common")
local Shop = Loader.requirePath("src/client/UI/Screens/Shop")
assert(Themes.Has(themeId), "unknown theme " .. tostring(themeId))
ThemeService.Set(themeId)
local theme = Themes.Get(themeId)

-- device (same table as tools/preview/gui/composite.luau) -----------------------------------------------------
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
local topbar = if args["no-topbar"] then 0 else TOPBAR
local inset = { L = dev.L, R = dev.R, T = math.max(dev.T, topbar), B = dev.B }
local usable = Vector2.new(W - inset.L - inset.R, H - inset.T - inset.B)
local layout = UIRoot.ComputeLayout(usable, { Left = inset.L, Top = inset.T, Right = inset.R, Bottom = inset.B })

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

-- stage: a dim lobby behind (the Shop's backdrop covers it almost fully), the Menu layer, the top bar ------------
local stage = make("ScreenGui", { Name = "Stage", IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local world = rect("World", 0, 0, W, H, Color3.new(1, 1, 1), 0, stage, 0)
world.Size = UDim2.fromScale(1, 1)
make("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 160, 214)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 168, 92)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(58, 104, 52)),
	}),
	Rotation = 90,
}, world)
local holder = rect("Layer_Menu", inset.L, inset.T, usable.X, usable.Y, Color3.new(0, 0, 0), 1, stage, 10)
local menuRoot = make("Frame", {
	Name = "Root",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1 / layout.Scale, 1 / layout.Scale),
}, holder)
make("UIScale", { Name = "DesignScale", Scale = layout.Scale }, menuRoot)

-- the Shop ---------------------------------------------------------------------------------------------------
local profile = Common.SampleProfile()
if args.gold and args.gold ~= true then
	profile.Gold = tonumber(args.gold)
end
local fixedT = if args.t and args.t ~= true then tonumber(args.t) else nil
local sayKey = if args.say and args.say ~= true then "shop.keeper." .. args.say else nil
local sayAt = if args["say-at"] and args["say-at"] ~= true then tonumber(args["say-at"]) else 4
local framesN = if args.frames and args.frames ~= true then tonumber(args.frames) else nil
local fps = if args.fps and args.fps ~= true then tonumber(args.fps) else 12
local from = if args.from and args.from ~= true then tonumber(args.from) else 0
local deps = {
	Layout = layout,
	Profile = profile,
	Now = 1700000000 + 3600 * 5,
	Kit = if args.kit and args.kit ~= true then args.kit else nil,
	Tab = if args.tab and args.tab ~= true then args.tab else nil,
	ReducedMotion = args.reduced == true,
	KeeperAt = if sayKey then sayAt elseif framesN then from else fixedT,
	Keeper = if args["no-keeper"] then false else nil,
}
local handle = Shop.Create(theme, deps)
handle.Root.Parent = menuRoot
local keeper = handle.Keeper
if sayKey and keeper then
	keeper.Say(sayKey)
	if fixedT then
		keeper.Pose(fixedT)
	end
end

-- Roblox top bar (core UI, drawn over every game ScreenGui) --------------------------------------------------
if topbar > 0 then
	local bar = rect("RobloxTopbar", inset.L + 12, 8, 148, 44, Color3.fromRGB(18, 18, 22), 0.35, stage, 100)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bar)
	for i = 0, 2 do
		local b = rect("CoreButton" .. i, 6 + i * 48, 4, 36, 36, Color3.fromRGB(30, 30, 36), 0.1, bar, 101)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		local glyph = rect("Glyph", 10, 10, 16, 16, Color3.new(1, 1, 1), 0, b, 102)
		if i == 1 then
			glyph.Size = UDim2.fromOffset(16, 3)
			glyph.Position = UDim2.fromOffset(10, 16)
		elseif i == 2 then
			make("UICorner", { CornerRadius = UDim.new(0, 4) }, glyph)
		end
	end
end

-- the keeper panel's rect on the screen (design px of the Menu root -> screen px); the scene is snapped to whole
-- screen pixels from there (at runtime ShopKeeper reads the stage's AbsolutePosition itself) ---------------------
local crop = nil
if keeper then
	local m = Common.Metrics(layout)
	local phone = layout.Phone == true
	local bodyTop = (if phone then 8 else 18) + m.HeaderH + m.Gap
	local size = keeper.Root.Size
	local x = inset.L + m.Margin * layout.Scale
	local y = inset.T + bodyTop * layout.Scale
	crop = {
		math.floor(x),
		math.floor(y),
		math.ceil(size.X.Offset * layout.Scale),
		math.ceil(size.Y.Offset * layout.Scale),
	}
	keeper.Snap(Vector2.new(x + keeper.Fit.Pad * layout.Scale, y + keeper.Fit.Pad * layout.Scale))
end

-- renderer seams (see the header): each painted cell frame under the scene 1 design px taller
local function bleed(inst, h)
	for _, child in inst:GetChildren() do
		if child:IsA("Frame") then
			local size = child.Size
			local ch = size.Y.Scale * h + size.Y.Offset
			if child.BackgroundTransparency < 1 and ch > 0 and string.sub(child.Name, 1, 4) ~= "Snow" then
				child.Size = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale + 1 / h, size.Y.Offset)
			end
			bleed(child, ch)
		end
	end
end
if keeper and args.seams ~= true then
	bleed(keeper.Scene, keeper.Fit.SceneH)
end

-- serialization (same format as tools/lune/dump_gui.luau) ----------------------------------------------------
local PROPS = {
	GuiObject = {
		"Position",
		"Size",
		"AnchorPoint",
		"Rotation",
		"ZIndex",
		"LayoutOrder",
		"Visible",
		"ClipsDescendants",
		"BackgroundColor3",
		"BackgroundTransparency",
		"BorderSizePixel",
		"BorderColor3",
		"AutomaticSize",
		"SizeConstraint",
	},
	Text = {
		"Text",
		"TextColor3",
		"TextSize",
		"TextScaled",
		"TextWrapped",
		"RichText",
		"FontFace",
		"TextXAlignment",
		"TextYAlignment",
		"TextTransparency",
		"TextStrokeColor3",
		"TextStrokeTransparency",
		"LineHeight",
		"MaxVisibleGraphemes",
		"TextTruncate",
	},
	Image = { "Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter", "ResampleMode" },
	ScreenGui = { "DisplayOrder", "IgnoreGuiInset", "Enabled", "ZIndexBehavior", "ScreenInsets" },
	CanvasGroup = { "GroupTransparency", "GroupColor3" },
	ScrollingFrame = {
		"CanvasSize",
		"CanvasPosition",
		"AutomaticCanvasSize",
		"ScrollingDirection",
		"ScrollBarThickness",
		"ScrollBarImageColor3",
		"ScrollBarImageTransparency",
		"VerticalScrollBarInset",
	},
	ViewportFrame = { "Ambient", "LightColor", "LightDirection", "ImageColor3", "ImageTransparency" },
	UIStroke = {
		"Color",
		"Thickness",
		"Transparency",
		"ApplyStrokeMode",
		"LineJoinMode",
		"Enabled",
		"BorderStrokePosition",
		"BorderOffset",
		"StrokeSizingMode",
	},
	UICorner = { "CornerRadius" },
	UIGradient = { "Color", "Transparency", "Rotation", "Offset", "Enabled" },
	UIPadding = { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" },
	UIListLayout = {
		"FillDirection",
		"Padding",
		"SortOrder",
		"HorizontalAlignment",
		"VerticalAlignment",
		"Wraps",
		"HorizontalFlex",
		"VerticalFlex",
		"ItemLineAlignment",
	},
	UIGridLayout = {
		"CellSize",
		"CellPadding",
		"FillDirection",
		"FillDirectionMaxCells",
		"SortOrder",
		"HorizontalAlignment",
		"VerticalAlignment",
		"StartCorner",
	},
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

local function document()
	count = 0
	return serde.encode("json", {
		version = 1,
		viewport = { W, H },
		scale = layout.Scale,
		canvas = { num(layout.Canvas.X), num(layout.Canvas.Y) },
		theme = themeId,
		screen = "shop_keeper",
		crop = crop,
		root = serialize(stage),
	}, false)
end

local summary = ("shop_keeper: %s %dx%d %s (scale %.3f, canvas %dx%d, keeper %s)"):format(
	themeId,
	W,
	H,
	deviceId,
	layout.Scale,
	math.floor(layout.Canvas.X),
	math.floor(layout.Canvas.Y),
	if keeper
		then ("%dpx/cell, %s"):format(
			keeper.Fit.Pixel,
			if keeper.Fit.Covered then "box over the counter" else "box below"
		)
		else "none"
)
if framesN then
	assert(keeper, "no keeper column at this size")
	local dir = assert(args.outdir ~= true and args.outdir, "--frames needs --outdir")
	fs.writeDir(dir)
	for i = 0, framesN - 1 do
		local t = from + i / fps
		keeper.Pose(t)
		fs.writeFile(("%s/frame_%02d.json"):format(dir, i), document())
	end
	print(("%s -> %d frames in %s (%.2f..%.2f s)"):format(summary, framesN, dir, from, from + (framesN - 1) / fps))
else
	local json = document()
	if args.out and args.out ~= true then
		fs.writeFile(args.out, json)
		print(("%s -> %s (%d instances)"):format(summary, args.out, count))
	else
		print(json)
	end
end
