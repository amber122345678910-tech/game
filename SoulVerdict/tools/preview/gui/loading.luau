--!nocheck
-- loading: offline preview of the PLAY / PRACTICE loading screen (src/client/UI/Overlays/Loading) on a device: the
-- overlay's own full-screen ScreenGui exactly as Loading.Build makes it (pixel-exact, no design scale), posed at a
-- moment of the spin, with the Roblox top bar (core UI, drawn over every game ScreenGui) on top for phones and a
-- painted lobby underneath (visible while the black is still fading). Writes dump_gui-style JSON for
-- tools/preview/gui/render.mjs.
--
-- Usage (project root):
--   lune run tools/preview/gui/loading.luau --size 860x400 --out /tmp/l.json
--        [--theme Classic] [--lang en|ru] [--mode Turn|Wheel|Still]
--        [--spin 0.25]          turn phase 0..1 of one full turn (0 = facing front)   (or --t <seconds since shown>)
--        [--dots 0..3]          fixed dot count (default: animated from the time)
--        [--black 1] [--content 1]   backdrop / head+text visibility 0..1 (fade frames)
--        [--frames 14 --outdir dir]  one JSON per frame over one full turn: dir/frame_00.json ...
--        [--no-topbar]
-- Then: node tools/preview/gui/render.mjs --in /tmp/l.json --out shot.png  (several --in/--out pairs share one browser)
-- GIF: render the frames, then e.g. python3 -c "from PIL import Image; ..." (see the lead's notes / previews/ui).
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

Loader.isServer = false
Loader.quietWarnings = true
local roblox = Loader.roblox
local Instance, UDim2, UDim, Vector2, Color3, Enum =
	roblox.Instance, roblox.UDim2, roblox.UDim, roblox.Vector2, roblox.Color3, roblox.Enum
local ColorSequence, ColorSequenceKeypoint = roblox.ColorSequence, roblox.ColorSequenceKeypoint

local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
Strings.SetLanguage(args.lang or "en")
local Themes = Loader.requirePath("src/client/UI/Themes")
local Loading = Loader.requirePath("src/client/UI/Overlays/Loading")
assert(Themes.Has(themeId), "unknown theme " .. tostring(themeId))
local theme = Themes.Get(themeId)
local phone = H < 560 or W < 900

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

-- one frame: the stage (painted lobby) + the overlay's layers + the Roblox top bar -------------------------------
local function buildStage(t)
	local stage = make("ScreenGui", { Name = "Stage", IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	local world = rect("World", 0, 0, W, H, Color3.new(1, 1, 1), 0, stage, 0)
	world.Size = UDim2.fromScale(1, 1)
	local grad = {}
	for _, k in {
		{ 0, Color3.fromRGB(96, 160, 214) },
		{ 0.42, Color3.fromRGB(196, 222, 236) },
		{ 0.5, Color3.fromRGB(120, 168, 92) },
		{ 1, Color3.fromRGB(58, 104, 52) },
	} do
		table.insert(grad, ColorSequenceKeypoint.new(k[1], k[2]))
	end
	make("UIGradient", { Color = ColorSequence.new(grad), Rotation = 90 }, world)
	local plaza = rect("Plaza", math.floor(W * 0.22), math.floor(H * 0.6), math.floor(W * 0.56), math.floor(H * 0.3), Color3.fromRGB(232, 226, 210), 0, world, 1)
	corner(plaza, UDim.new(0.5, 0))

	-- the overlay exactly as at runtime; its layers move into a full-screen holder of the stage
	local view = Loading.Build(theme, { Viewport = Vector2.new(W, H), Mode = args.mode })
	local black = tonumber(args.black) or 1
	local content = tonumber(args.content) or 1
	view.Fade(black, content)
	view.Pose(t, tonumber(args.dots))
	local holder = rect("Overlay_" .. view.Gui.Name, 0, 0, W, H, Color3.new(0, 0, 0), 1, stage, 50)
	holder.Size = UDim2.fromScale(1, 1)
	for _, child in view.Gui:GetChildren() do
		child.Parent = holder
	end

	if phone and not args["no-topbar"] then
		-- Roblox top bar (core UI, always on top of game ScreenGuis): Roblox button + menu + chat at the top-left
		local bar = rect("RobloxTopbar", 36 + 12, 8, 148, 44, Color3.fromRGB(18, 18, 22), 0.35, stage, 100)
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
	end
	return stage, view
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
	ScreenGui = { "DisplayOrder", "IgnoreGuiInset", "Enabled", "ZIndexBehavior", "ScreenInsets" },
	CanvasGroup = { "GroupTransparency", "GroupColor3" },
	UIStroke = { "Color", "Thickness", "Transparency", "ApplyStrokeMode", "LineJoinMode", "Enabled" },
	UICorner = { "CornerRadius" },
	UIGradient = { "Color", "Transparency", "Rotation", "Offset", "Enabled" },
}

local function num(x)
	if x ~= x then
		return 0
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

local function write(path, t)
	count = 0
	local stage, view = buildStage(t)
	local doc = {
		version = 1,
		viewport = { W, H },
		scale = 1,
		canvas = { W, H },
		theme = themeId,
		screen = "src/client/UI/Overlays/Loading",
		root = serialize(stage),
	}
	fs.writeFile(path, serde.encode("json", doc, false))
	local m = view.Metrics
	print(("loading: %dx%d %s t=%.3f -> %s (%d instances, pixel %d, head %dx%d at y %d, text %d px)"):format(
		W, H, view.Mode, t, path, count, m.Pixel, m.HeadW, m.HeadH, m.HeadTop, m.TextSize))
end

local frames = tonumber(args.frames)
if frames and frames > 0 then
	local dir = assert(args.outdir ~= true and args.outdir, "--frames needs --outdir")
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	local period = if args.mode == "Wheel" then Loading.WheelPeriod else Loading.TurnPeriod
	for i = 0, frames - 1 do
		write(("%s/frame_%02d.json"):format(dir, i), period * i / frames)
	end
else
	local t = tonumber(args.t)
	if t == nil then
		local period = if args.mode == "Wheel" then Loading.WheelPeriod else Loading.TurnPeriod
		t = (tonumber(args.spin) or 0) * period
	end
	assert(args.out and args.out ~= true, "--out <file.json> is required")
	write(args.out, t)
end
