--!nocheck
-- verdictbox_entry: offline preview of the Verdict Box VICTIM's entry transition on a phone (UI/VerdictBoxEntry +
-- UI/VerdictBoxView exactly as VerdictBoxController stacks them): a painted stand-in of the 3D arena (flat billboards
-- projected through the SAME camera pull the game applies: VerdictBoxEntry.CameraPose of an over-the-shoulder
-- follow camera), the box overlay (open from the flash), the entry layer (iris, streaks, SOUL heart, black, flash),
-- the JUMP touch button (shown from the flash on) and the Roblox top bar. Writes dump_gui-style JSON for
-- tools/preview/gui/render.mjs.
--
-- Usage (project root):
--   lune run tools/preview/gui/verdictbox_entry.luau --size 860x400 --out /tmp/e.json --t 0.4
--        [--lang en|ru] [--set Classic|Fell|Eclipse] [--seed 7] [--latency 0.05] [--reduced]
--        [--frames --outdir dir]   the whole sequence: dir/frame_NN.json + dir/frames.json ({file, t, stage, ms})
-- Times are seconds since BoxStart arrived (the pull-in, the box music and "Implode" start at 0).
-- previews/verdictbox/entry.gif = every frame rendered with render.mjs, then assembled with Python PIL using the
-- per-frame durations in frames.json (see the end of this file's output).
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
local SIZE_PX = nil -- Vector2 (set below)

Loader.isServer = false
Loader.quietWarnings = true
local roblox = Loader.roblox
local Instance, UDim2, UDim, Vector2, Vector3, Color3, Enum, CFrame =
	roblox.Instance, roblox.UDim2, roblox.UDim, roblox.Vector2, roblox.Vector3, roblox.Color3, roblox.Enum, roblox.CFrame
local ColorSequence, ColorSequenceKeypoint, NumberSequence, NumberSequenceKeypoint =
	roblox.ColorSequence, roblox.ColorSequenceKeypoint, roblox.NumberSequence, roblox.NumberSequenceKeypoint
SIZE_PX = Vector2.new(W, H)

local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
Strings.SetLanguage(args.lang or "ru")
local Config = Loader.require("ReplicatedStorage.Shared.Config")
local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
local Patterns = Loader.require("ReplicatedStorage.Shared.VerdictBox.Patterns")
local Sim = Loader.require("ReplicatedStorage.Shared.VerdictBox.Sim")
local View = Loader.requirePath("src/client/UI/VerdictBoxView")
local Entry = Loader.requirePath("src/client/UI/VerdictBoxEntry")

local setId = args.set or "Classic"
local seed = tonumber(args.seed) or 7
local latency = tonumber(args.latency) or 0.05
local reduced = args.reduced == true
local c = Config.VerdictBox
local timeline = Patterns.Build(setId, seed, c.Duration)
local START = 0
local T0 = START - latency + c.IntroTime -- the box timeline start (server open + IntroTime)
local stages = Entry.Stages(START, T0, timeline.introEnd, reduced)
local monsterKit = ({ Classic = "ClassicSans", Fell = "FellSans", Eclipse = "EclipseSans" })[timeline.set] or "ClassicSans"
local title = string.upper(Strings.Pick(Kits.Get(monsterKit).Title))

-- the follow camera of CameraController (Config.Camera: distance 11, right shoulder 1.8, pivot 1.6 above the root,
-- pitch -12 degrees, FOV 72) behind a victim standing at the origin facing -Z
local FOV = Config.Defaults.FieldOfView or 72
local ROOT = Vector3.new(0, 3, 0)
local CHEST = Vector3.new(0, 4.35, -0.35) -- UpperTorso "Chest" attachment
local function lookAlong(pos, dir)
	local f = dir.Unit
	local right = f:Cross(Vector3.new(0, 1, 0)).Unit
	local up = right:Cross(f)
	return CFrame.fromMatrix(pos, right, up, -f)
end
local pitch = math.rad(-12)
local lookDir = Vector3.new(0, math.sin(pitch), -math.cos(pitch))
local pivot = ROOT + Vector3.new(1.8, 1.6, 0)
local BASE = lookAlong(pivot - lookDir * Config.Camera.Distance, lookDir)

local function project(cam, fov, point)
	local rel = cam:PointToObjectSpace(point)
	if rel.Z >= -0.05 then
		return nil, 0
	end
	local focal = (H / 2) / math.tan(math.rad(fov) / 2)
	local k = focal / -rel.Z
	return Vector2.new(W / 2 + rel.X * k, H / 2 - rel.Y * k), k
end

---------------------------------------------------------------------------------------------------
-- GUI helpers

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
local function corner(parent, scale)
	make("UICorner", { CornerRadius = UDim.new(scale, 0) }, parent)
end
local function vgrad(parent, top, bottom, rot)
	make("UIGradient", {
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(1, bottom) }),
		Rotation = rot or 90,
	}, parent)
end

-- a flat billboard in the world (centre, width x height studs) drawn through the camera: position, size and the
-- roll of its up axis on screen
local function billboard(holder, cam, fov, name, center, wStuds, hStuds, color, opts)
	local o = opts or {}
	local p, k = project(cam, fov, center)
	if p == nil then
		return nil
	end
	local top = project(cam, fov, center + Vector3.new(0, 1, 0))
	local rot = 0
	if top then
		local d = top - p
		rot = math.deg(math.atan2(d.X, -d.Y))
	end
	local f = make("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(p.X, p.Y),
		Size = UDim2.fromOffset(wStuds * k, hStuds * k),
		Rotation = rot,
		BackgroundColor3 = color,
		BackgroundTransparency = o.alpha or 0,
		BorderSizePixel = 0,
		ZIndex = o.z or 1,
	}, holder)
	if o.round then
		corner(f, o.round)
	end
	if o.grad then
		vgrad(f, o.grad[1], o.grad[2], o.gradRot)
	end
	if o.stroke then
		make("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = o.stroke,
			Thickness = math.max(1, (o.strokeStuds or 0.12) * k),
		}, f)
	end
	return f
end

-- the painted arena (a Hall of Verdicts stand-in) + the victim from behind + the monster + the 3D box above
local function paintWorld(holder, cam, fov)
	local function bb(...)
		return billboard(holder, cam, fov, ...)
	end
	-- sky / far wall (very far, huge)
	bb("Far", Vector3.new(0, 30, -260), 900, 260, Color3.new(1, 1, 1), {
		z = 1,
		grad = { Color3.fromRGB(40, 34, 74), Color3.fromRGB(214, 150, 96) },
	})
	-- floor band (a far vertical stand-in for the ground)
	bb("Floor", Vector3.new(0, -40, -60), 400, 86, Color3.new(1, 1, 1), {
		z = 2,
		grad = { Color3.fromRGB(150, 120, 96), Color3.fromRGB(70, 54, 50) },
	})
	-- pillars and windows of the hall
	for i, x in { -26, -14, 14, 26, 40, -40 } do
		bb("Pillar" .. i, Vector3.new(x, 8, -34), 3.4, 22, Color3.new(1, 1, 1), {
			z = 3,
			grad = { Color3.fromRGB(226, 214, 190), Color3.fromRGB(120, 104, 92) },
			gradRot = 0,
		})
	end
	for i, x in { -20, 0, 20 } do
		bb("Window" .. i, Vector3.new(x, 11, -35), 6, 12, Color3.fromRGB(255, 214, 140), {
			z = 3,
			round = 0.5,
			alpha = 0.15,
			grad = { Color3.fromRGB(255, 240, 200), Color3.fromRGB(255, 170, 90) },
		})
	end
	-- the monster across the hall (Sans: blue hoodie, white skull, one glowing eye)
	local m = Vector3.new(7, 3, -16)
	bb("SansLegs", m + Vector3.new(0, -1.6, 0), 1.6, 1.6, Color3.fromRGB(30, 30, 38), { z = 4 })
	bb("SansBody", m + Vector3.new(0, 0.2, 0), 2.6, 2.4, Color3.fromRGB(60, 110, 200), { z = 5, round = 0.25 })
	bb("SansHead", m + Vector3.new(0, 2.1, 0), 1.9, 1.7, Color3.fromRGB(240, 240, 236), { z = 6, round = 0.45 })
	bb("SansEye", m + Vector3.new(-0.35, 2.15, 0.1), 0.38, 0.38, Color3.fromRGB(90, 220, 255), { z = 7, round = 0.5 })
	-- the 3D Verdict Box the server spawned above the victim (Height studs), its mirror screen = the dialog box
	local boxC = ROOT + Vector3.new(0, c.Height, 0.2)
	bb("Box3D", boxC, 5.2, 5.2, Color3.fromRGB(8, 8, 10), {
		z = 8,
		stroke = Color3.new(1, 1, 1),
		strokeStuds = 0.18,
	})
	bb("Box3DLine", boxC, 3.4, 1.4, Color3.fromRGB(8, 8, 10), { z = 9, stroke = Color3.new(1, 1, 1), strokeStuds = 0.1 })
	-- the victim from behind (striped sweater, brown hair)
	local legC = Color3.fromRGB(40, 50, 92)
	bb("LegL", ROOT + Vector3.new(-0.42, -1.45, 0), 0.75, 2.4, legC, { z = 10 })
	bb("LegR", ROOT + Vector3.new(0.42, -1.45, 0), 0.75, 2.4, legC, { z = 10 })
	bb("ShoeL", ROOT + Vector3.new(-0.42, -2.75, 0.05), 0.85, 0.45, Color3.fromRGB(96, 60, 36), { z = 11, round = 0.3 })
	bb("ShoeR", ROOT + Vector3.new(0.42, -2.75, 0.05), 0.85, 0.45, Color3.fromRGB(96, 60, 36), { z = 11, round = 0.3 })
	local sweater = Color3.fromRGB(64, 110, 214)
	bb("ArmL", ROOT + Vector3.new(-1.25, 1.05, 0.05), 0.62, 2.2, sweater, { z = 11, round = 0.3 })
	bb("ArmR", ROOT + Vector3.new(1.25, 1.05, 0.05), 0.62, 2.2, sweater, { z = 11, round = 0.3 })
	bb("Torso", ROOT + Vector3.new(0, 1.3, 0.05), 2.0, 2.3, sweater, {
		z = 12,
		round = 0.12,
		grad = { Color3.fromRGB(96, 140, 236), Color3.fromRGB(46, 84, 176) },
	})
	bb("Stripe1", ROOT + Vector3.new(0, 1.55, 0.1), 2.0, 0.3, Color3.fromRGB(224, 70, 150), { z = 13 })
	bb("Stripe2", ROOT + Vector3.new(0, 0.85, 0.1), 2.0, 0.3, Color3.fromRGB(224, 70, 150), { z = 13 })
	bb("Neck", ROOT + Vector3.new(0, 2.5, 0.05), 0.6, 0.4, Color3.fromRGB(236, 196, 160), { z = 12 })
	bb("Head", ROOT + Vector3.new(0, 3.25, 0.05), 1.55, 1.45, Color3.fromRGB(110, 70, 40), {
		z = 14,
		round = 0.42,
		grad = { Color3.fromRGB(140, 92, 56), Color3.fromRGB(84, 52, 30) },
	})
end

---------------------------------------------------------------------------------------------------
-- one frame

local function buildStage(now)
	local f = Entry.At(stages, now)
	local cam, fov = BASE, FOV
	if f.camera > 0 then
		cam, fov = Entry.CameraPose(BASE, FOV, CHEST, f.camera, f.roll)
	end
	local stage = make("ScreenGui", { Name = "Stage", IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	local world = make("Frame", {
		Name = "World3D",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(30, 26, 40),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 0,
	}, stage)
	paintWorld(world, cam, fov)
	-- post effects stand-in: desaturation / blur cannot be drawn here; a faint grey wash shows the amount
	if f.camera > 0 and not reduced then
		make("Frame", {
			Name = "PostFxStandIn",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(70, 66, 80),
			BackgroundTransparency = 1 - 0.28 * f.camera,
			BorderSizePixel = 0,
			ZIndex = 40,
		}, world)
	end

	-- the victim's overlay ScreenGui "VerdictBox" (DisplayOrder 25): box view + touch JUMP + the entry layer
	local overlay = make("Frame", {
		Name = "Overlay_VerdictBox",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
	}, stage)
	local view = View.new(overlay, timeline, { Mode = "Overlay", Size = SIZE_PX, Title = title })
	view:SetSize(SIZE_PX)
	view:SetOpen(f.open)
	local boxT = now - T0
	local soul = nil
	if boxT >= timeline.introEnd then
		local x, y = Sim.AutoSoul(timeline, boxT)
		local m = Sim.ModeAt(timeline, boxT)
		soul = { x = x, y = y, mode = m.mode, gravity = m.gravity, blink = false, visible = true }
	end
	view:Render(math.min(boxT, timeline.duration + 0.5), soul, { name = "Frisk", lv = 7, hp = 92, maxHp = 110, kr = 0 })
	if f.open > 0 then
		local jump = make("TextButton", {
			Name = "Jump",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -28, 1, -34),
			Size = UDim2.fromOffset(118, 118),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			Text = Strings.L("vb.jump"),
			TextColor3 = Color3.new(1, 1, 1),
			FontFace = Font.new("rbxasset://fonts/families/PressStart2P.json"),
			TextSize = 16,
			ZIndex = 42,
		}, overlay)
		corner(jump, 0.5)
		make("UIStroke", {
			Color = Sim.Palette.SoulBlue,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, jump)
	end
	local layer = Entry.new(overlay, { ZIndex = 60 })
	-- the chest through the pulled camera (frozen from the black on, like the Runner)
	local fPull = if f.stage == "Pull" then f else Entry.At(stages, stages.pullEnd - 1e-4)
	local camPull, fovPull = BASE, FOV
	if fPull.camera > 0 then
		camPull, fovPull = Entry.CameraPose(BASE, FOV, CHEST, fPull.camera, fPull.roll)
	end
	local center = project(camPull, fovPull, CHEST) or SIZE_PX * 0.5
	layer:Render(f, center, SIZE_PX)

	-- Roblox top bar (core UI, always on top) on phones
	if H < 560 and not args["no-topbar"] then
		local bar = make("Frame", {
			Name = "RobloxTopbar",
			Position = UDim2.fromOffset(48, 8),
			Size = UDim2.fromOffset(148, 44),
			BackgroundColor3 = Color3.fromRGB(18, 18, 22),
			BackgroundTransparency = 0.35,
			ZIndex = 100,
		}, stage)
		corner(bar, 0.5)
		for i = 0, 2 do
			local b = make("Frame", {
				Name = "CoreButton" .. i,
				Position = UDim2.fromOffset(6 + i * 48, 4),
				Size = UDim2.fromOffset(36, 36),
				BackgroundColor3 = Color3.fromRGB(30, 30, 36),
				BackgroundTransparency = 0.1,
				ZIndex = 101,
			}, bar)
			corner(b, 0.5)
		end
	end
	return stage, f
end

---------------------------------------------------------------------------------------------------
-- serialization (same format as tools/lune/dump_gui.luau)

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
	UIPadding = { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" },
	UITextSizeConstraint = { "MaxTextSize", "MinTextSize" },
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

local function write(path, now)
	count = 0
	local stage, f = buildStage(now)
	local doc = {
		version = 1,
		viewport = { W, H },
		scale = 1,
		canvas = { W, H },
		theme = "Classic",
		screen = "src/client/UI/VerdictBoxEntry",
		root = serialize(stage),
	}
	fs.writeFile(path, serde.encode("json", doc, false))
	return f
end

print(
	("verdictbox_entry: %dx%d %s seed %d latency %.2f%s | pull %.2f s, black %.2f s, flash at %.2f s, box at %.2f s, first attack at %.2f s"):format(
		W,
		H,
		timeline.set,
		seed,
		latency,
		if reduced then " (reduced motion)" else "",
		stages.pull,
		stages.flashAt - stages.pullEnd,
		stages.flashAt,
		stages.flashEnd,
		T0 + timeline.introEnd
	)
)

if args.frames then
	local dir = assert(args.outdir ~= true and args.outdir, "--frames needs --outdir")
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	-- 30 fps through the transition, then 15 fps for the opening line and the first attack
	local times = {}
	local t = 0
	while t < stages.flashEnd + 0.12 do
		table.insert(times, t)
		t += 1 / 30
	end
	-- the exact flash frames (full white for FlashHold)
	table.insert(times, stages.flashAt)
	table.sort(times)
	local tail = T0 + timeline.introEnd + 0.9
	t = times[#times] + 1 / 15
	while t <= tail do
		table.insert(times, t)
		t += 1 / 15
	end
	local index = {}
	for i, now in times do
		local file = ("%s/frame_%02d.json"):format(dir, i - 1)
		local f = write(file, now)
		local nextT = times[i + 1] or (now + 0.6)
		table.insert(index, { file = file, t = now, stage = f.stage, ms = math.floor((nextT - now) * 1000 + 0.5) })
	end
	fs.writeFile(dir .. "/frames.json", serde.encode("json", index, true))
	print(("wrote %d frames to %s (frames.json has the per-frame durations)"):format(#times, dir))
else
	assert(args.out and args.out ~= true, "--out <file.json> is required")
	local f = write(args.out, tonumber(args.t) or 0.4)
	print(("frame t=%.3f stage %s -> %s (%d instances)"):format(tonumber(args.t) or 0.4, f.stage, args.out, count))
end
