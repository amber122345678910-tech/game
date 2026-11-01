--!nocheck
-- dump_gui: builds a UI screen module offline (Lune) and serializes the GuiObject tree to JSON for
-- tools/preview/gui/render.mjs (HTML/CSS renderer + Playwright screenshots).
--
-- Usage (from the project root):
--   lune run tools/lune/dump_gui.luau --screen src/client/UI/Gallery --theme Classic --size 1920x1080 \
--        [--deps deps.json | --deps-json '{"Page":"Icons"}'] [--hud Battle] [--lang en|ru] [--out gui.json]
-- The screen module must expose Create(theme, deps) -> { Root: GuiObject, ... } (SPEC §10). The root is
-- parented under a ScreenGui built by UIRoot.CreateLayer (same responsive UIScale as at runtime);
-- deps.Layout = UIRoot.ComputeLayout(size) is injected. Unknown/unsupported properties are skipped.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("./loader")

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

local screenPath = args.screen or "src/client/UI/Gallery"
local themeId = args.theme or "Classic"
local sizeText = args.size or "1920x1080"
local w, h = string.match(sizeText, "^(%d+)x(%d+)$")
assert(w and h, "--size must look like 1920x1080")
w, h = tonumber(w), tonumber(h)

Loader.isServer = false
Loader.quietWarnings = true
local roblox = Loader.roblox

local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
Strings.SetLanguage(args.lang or "en")
local Themes = Loader.requirePath("src/client/UI/Themes")
local ThemeService = Loader.requirePath("src/client/UI/ThemeService")
local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
assert(Themes.Has(themeId), "unknown theme " .. tostring(themeId))
ThemeService.Set(themeId)
if args.hud then
	ThemeService.SetHudStyle(args.hud)
end

local deps = {}
if args.deps and args.deps ~= true then
	deps = serde.decode("json", fs.readFile(args.deps))
end
if args["deps-json"] then
	for k, v in serde.decode("json", args["deps-json"]) do
		deps[k] = v
	end
end
if args.hud then
	deps.Hud = args.hud
end

local layout = UIRoot.ComputeLayout(roblox.Vector2.new(w, h))
deps.Layout = layout
local gui, root = UIRoot.CreateLayer("Preview", 10, layout)

local module = Loader.requirePath(screenPath)
assert(type(module) == "table" and type(module.Create) == "function", screenPath .. " has no Create(theme, deps)")
local handle = module.Create(Themes.Get(themeId), deps)
assert(handle and handle.Root, "Create must return a handle with Root")
handle.Root.Parent = root

-- serialization ------------------------------------------------------------------------------------
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
	Path2D = { "Closed", "Color3", "Thickness", "Transparency", "Visible", "ZIndex" },
}

local function num(x)
	if x ~= x then
		return 0
	end
	if x == math.huge or x > 1e9 then
		return 1e9
	end
	if x == -math.huge or x < -1e9 then
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
	elseif t == "Vector3" then
		return { num(v.X), num(v.Y), num(v.Z) }
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
	local attrs = {}
	local hasAttrs = false
	for k, v in inst:GetAttributes() do
		local e = encode(v)
		if e ~= nil then
			attrs[k] = e
			hasAttrs = true
		end
	end
	local children = {}
	for _, child in inst:GetChildren() do
		table.insert(children, serialize(child))
	end
	return {
		class = inst.ClassName,
		name = inst.Name,
		props = props,
		attrs = if hasAttrs then attrs else nil,
		children = children,
	}
end

local doc = {
	version = 1,
	viewport = { w, h },
	scale = layout.Scale,
	canvas = { num(layout.Canvas.X), num(layout.Canvas.Y) },
	theme = themeId,
	screen = screenPath,
	root = serialize(gui),
}

local json = serde.encode("json", doc, false)
if args.out and args.out ~= true then
	fs.writeFile(args.out, json)
	print(("dump_gui: %s [%s %dx%d] -> %s (%d instances, %d KB)"):format(screenPath, themeId, w, h, args.out, count, #json // 1024))
else
	print(json)
end
