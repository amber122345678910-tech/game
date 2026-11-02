--!strict
-- VerdictBoxView: frame-based 2D renderer of the Verdict Box (SPEC §11). Draws a Sim.Timeline at any time t into any
-- container size; used by VerdictBoxController for the victim's full-screen overlay ("Overlay": fixed 640x480 stage,
-- HP / KR line, hints, typewriter line) and for the watchers' mirror on the 3D box's Screen SurfaceGui ("Mirror":
-- camera auto-fits the current box + blasters, victim name header), and by previews (Create).
-- Lune-safe at require time (pure GUI building; Sim / Strings from ReplicatedStorage.Shared).
--
-- Look (docs/research/undertale.md §4, §6): black box with a 5 px white border; bones = white rounded shafts with
-- pill knobs (Blue #14A9FF / Orange #FFA040 tints; Fell: pale bones with crimson outlines; Eclipse darkness: black
-- bones with glowing violet outlines and a dimmed border); "Chain" bones get ring knobs; stabs = rows of bones from
-- the wall after a blinking red (#FF0000) outlined warning; blasters = pixel-ish skulls (cranium, horns, sockets
-- with glowing pupils, split jaw) firing a three-layer wobbling beam; platforms = white outline + dark green
-- (#2E5F2E) outline offset 4 px; star-bones = spinning 3-bone asterisks; rifts = violet-rimmed void slits; the SOUL =
-- the 16x16 pixel heart (red #FF0000, blue #003CFF in gravity mode, rotated toward gravity, blinking while invincible).
-- Overlay HP line: name, LV, "HP", bar 21 px tall x MaxHP*1.2 (red #FF0000 back, yellow #FFFF00 fill, magenta #FF00FF
-- KR segment, numbers magenta while KR > 0), "KR". Feedback: red flash + shake + floating "-5" / "+3 KR" numbers on
-- hits, white flash + ring pulse on mode changes, verdict banner at the end.
--
-- API
--   VerdictBoxView.new(parent, timeline, opts?) -> View
--       opts: { Mode: "Overlay"|"Mirror"?, Size: Vector2? (container px), Title: string?, Name: string?, ZIndex: number? }
--   view:SetSize(size: Vector2)                 container pixel size (runtime: AbsoluteSize; previews: explicit)
--   view:Render(t, soul?, hud?)                 soul: {x, y, mode, gravity, blink: boolean?, visible: boolean?}
--                                               hud: {name, lv, hp, maxHp, kr} (Overlay only)
--   view:Hit(t, damage?, kr?)                   hit feedback at box time t (flash, shake, floating numbers)
--   view:Pulse(t, color?)                       ring + flash at the soul (mode change / slam)
--   view:SetVerdict(kind?, sub?)                "Innocent" | "Guilty" | "Dismissed" banner (nil hides)
--   view:SetHint(text?)                         Overlay hint line under the HP row (nil hides)
--   view:SetFade(alpha)                         0 = visible .. 1 = hidden (whole view)
--   view:Destroy()
--   view.Root: Frame
--   VerdictBoxView.SOUL_ROWS                    the heart sprite as {row, x0, x1, rows} runs (16x16, 186 px)
--   VerdictBoxView.Create(theme, deps) -> { Root, Destroy }   preview screen for tools/lune/dump_gui.luau
--       deps: { Set = "Classic", Seed = 7, Kind = "Sheet"|"Overlay"|"Mirror", Time = 3.2, Times = {..} }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sim = require(Shared:WaitForChild("VerdictBox"):WaitForChild("Sim")) :: any
local Patterns = require(Shared:WaitForChild("VerdictBox"):WaitForChild("Patterns")) :: any
local Strings = require(Shared:WaitForChild("Strings")) :: any

local VerdictBoxView = {}
VerdictBoxView.__index = VerdictBoxView

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local HP_BACK = Color3.fromRGB(255, 0, 0)
local HP_FILL = Color3.fromRGB(255, 255, 0)
local KR_COLOR = Color3.fromRGB(255, 0, 255)
local WARN = Sim.Palette.Warn
local PLATFORM_EDGE = Sim.Palette.PlatformEdge
local BORDER = 5 -- px (logical) battle-box border
local STAGE_W, STAGE_H = 640, 480
local OVERLAY_BOX_Y = 238 -- box centre on the 640x480 stage
local MIRROR_MARGIN = 58 -- logical px around the box kept visible in the mirror (blasters)

local function font(family: string, weight: Enum.FontWeight?): Font
	return Font.new("rbxasset://fonts/families/" .. family .. ".json", weight or Enum.FontWeight.Regular)
end
local PIXEL = font("PressStart2P")

type Theme = {
	bone: Color3,
	boneStroke: Color3?,
	border: Color3,
	inner: Color3,
	innerGlow: Color3?,
	text: Color3,
	textStroke: Color3?,
	pupil: Color3,
	beamOuter: Color3,
	glow: Color3,
	speech: string,
}

local THEMES: { [string]: Theme } = {
	Classic = {
		bone = WHITE,
		border = WHITE,
		inner = BLACK,
		text = WHITE,
		pupil = WHITE,
		beamOuter = Color3.fromRGB(214, 236, 255),
		glow = Color3.fromRGB(190, 225, 255),
		speech = "ComicNeueAngular",
	},
	Fell = {
		bone = Color3.fromRGB(255, 232, 232),
		boneStroke = Color3.fromRGB(226, 18, 46),
		border = WHITE,
		inner = Color3.fromRGB(8, 0, 2),
		innerGlow = Color3.fromRGB(70, 0, 10),
		text = Color3.fromRGB(255, 92, 92),
		textStroke = Color3.fromRGB(60, 0, 0),
		pupil = Color3.fromRGB(255, 36, 36),
		beamOuter = Color3.fromRGB(255, 120, 130),
		glow = Color3.fromRGB(255, 70, 80),
		speech = "ComicNeueAngular",
	},
	Eclipse = {
		bone = Color3.fromRGB(238, 230, 255),
		border = Color3.fromRGB(236, 228, 255),
		inner = Color3.fromRGB(9, 4, 20),
		innerGlow = Color3.fromRGB(46, 18, 92),
		text = Color3.fromRGB(206, 182, 255),
		textStroke = Color3.fromRGB(30, 0, 60),
		pupil = Color3.fromRGB(176, 112, 255),
		beamOuter = Color3.fromRGB(160, 108, 255),
		glow = Color3.fromRGB(178, 122, 255),
		speech = "Jura",
	},
}
local DARK_FILL = Color3.fromRGB(6, 3, 12)

-- 16x16 heart (docs/research/undertale.md §6): {firstRow, x0, x1, rowCount} merged runs, 186 filled pixels.
VerdictBoxView.SOUL_ROWS = {
	{ 0, 2, 3, 1 },
	{ 0, 12, 13, 1 },
	{ 1, 1, 5, 1 },
	{ 1, 10, 14, 1 },
	{ 2, 0, 6, 2 },
	{ 2, 9, 15, 2 },
	{ 4, 0, 15, 6 },
	{ 10, 2, 13, 2 },
	{ 12, 4, 11, 2 },
	{ 14, 6, 9, 2 },
}

---------------------------------------------------------------------------------------------------
-- tiny builders

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function frame(props: { [string]: any }, parent: Instance?): Frame
	props.BorderSizePixel = 0
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 0
	end
	return new("Frame", props, parent)
end

local function corner(parent: Instance, scale: number)
	new("UICorner", { CornerRadius = UDim.new(scale, 0) }, parent)
end

local function stroke(parent: Instance, color: Color3, thickness: number, enabled: boolean?): UIStroke
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Enabled = if enabled == nil then true else enabled,
	}, parent)
end

local function label(props: { [string]: any }, parent: Instance?): TextLabel
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	if props.FontFace == nil then
		props.FontFace = PIXEL
	end
	if props.TextColor3 == nil then
		props.TextColor3 = WHITE
	end
	return new("TextLabel", props, parent)
end

local function hash01(a: number, b: number): number
	local v = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return v - math.floor(v)
end

---------------------------------------------------------------------------------------------------
-- pooled drawables

type BoneObj = {
	root: Frame,
	shaft: Frame,
	top: Frame,
	bottom: Frame,
	strokes: { UIStroke },
	lastL: number,
	lastT: number,
	look: string,
}

type StarObj = { root: Frame, bars: { Frame }, strokes: { UIStroke }, look: string }
type WarnObj = { root: Frame, stroke: UIStroke }
type BlasterObj = {
	root: Frame,
	jawTop: Frame,
	jawBottom: Frame,
	mouth: Frame,
	pupils: { Frame },
	whites: { Frame },
	strokes: { UIStroke },
	look: string,
}
type BeamObj = { root: Frame, layers: { Frame } }
type PlatformObj = { root: Frame, back: Frame, strokes: { UIStroke } }
type RiftObj = { root: Frame, core: Frame, stroke: UIStroke }

type Pool<T> = { items: { T }, used: number, make: () -> T, hide: (T) -> () }

local function pool<T>(make: () -> T, hide: (T) -> ()): Pool<T>
	return { items = {}, used = 0, make = make, hide = hide }
end

local function take<T>(p: Pool<T>): T
	p.used += 1
	local item = p.items[p.used]
	if item == nil then
		item = p.make()
		p.items[p.used] = item
	end
	return item
end

local function finishPool<T>(p: Pool<T>)
	for i = p.used + 1, #p.items do
		p.hide(p.items[i])
	end
	p.used = 0
end

---------------------------------------------------------------------------------------------------

export type SoulView = { x: number, y: number, mode: string, gravity: string, blink: boolean?, visible: boolean? }
export type HudView = { name: string, lv: number, hp: number, maxHp: number, kr: number }

type Float = { label: TextLabel, t0: number, x: number, y: number, active: boolean }

export type View = typeof(setmetatable(
	{} :: {
		Root: Frame,
		timeline: any,
		mode: string,
		theme: Theme,
		size: Vector2,
		scale: number,
		cx: number,
		cy: number,
		stage: Frame,
		border: Frame,
		inner: Frame,
		innerGlow: Frame,
		over: Frame,
		darkVeil: Frame,
		flash: Frame,
		textLabel: TextLabel,
		lineText: string,
		soulRoot: Frame,
		soulPixels: { Frame },
		soulColor: Color3?,
		ring: Frame,
		ringStroke: UIStroke,
		timer: Frame,
		timerFill: Frame,
		header: TextLabel?,
		hud: { [string]: any }?,
		hint: TextLabel?,
		verdict: TextLabel,
		verdictSub: TextLabel,
		floats: { Float },
		bones: Pool<BoneObj>,
		stars: Pool<StarObj>,
		warns: Pool<WarnObj>,
		blasters: Pool<BlasterObj>,
		beams: Pool<BeamObj>,
		platforms: Pool<PlatformObj>,
		rifts: Pool<RiftObj>,
		pose: any,
		hitAt: number,
		pulseAt: number,
		pulseColor: Color3,
		fade: number,
		lastT: number,
	},
	VerdictBoxView
))

local function makeBone(parent: Instance): BoneObj
	local root = frame({ Name = "Bone", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 4 }, nil)
	local shaft = frame({
		Name = "Shaft",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.58, 0.8),
		BackgroundColor3 = WHITE,
		ZIndex = 4,
	}, root)
	corner(shaft, 0.25)
	local top = frame({
		Name = "KnobA",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 0.2),
		BackgroundColor3 = WHITE,
		ZIndex = 4,
	}, root)
	corner(top, 0.5)
	local bottom = frame({
		Name = "KnobB",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0.2),
		BackgroundColor3 = WHITE,
		ZIndex = 4,
	}, root)
	corner(bottom, 0.5)
	local strokes = {
		stroke(shaft, WHITE, 1, false),
		stroke(top, WHITE, 1, false),
		stroke(bottom, WHITE, 1, false),
	}
	root.Parent = parent
	return { root = root, shaft = shaft, top = top, bottom = bottom, strokes = strokes, lastL = -1, lastT = -1, look = "" }
end

local function makeStar(parent: Instance): StarObj
	local root = frame({ Name = "StarBone", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 4 }, nil)
	local bars, strokes = {}, {}
	for i = 0, 2 do
		local bar = frame({
			Name = "Arm",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.26, 1),
			Rotation = i * 60,
			BackgroundColor3 = WHITE,
			ZIndex = 4,
		}, root)
		corner(bar, 0.5)
		table.insert(bars, bar)
		table.insert(strokes, stroke(bar, WHITE, 1, false))
	end
	local hub = frame({
		Name = "Hub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.42),
		BackgroundColor3 = WHITE,
		ZIndex = 5,
	}, root)
	corner(hub, 0.5)
	table.insert(bars, hub)
	table.insert(strokes, stroke(hub, WHITE, 1, false))
	root.Parent = parent
	return { root = root, bars = bars, strokes = strokes, look = "" }
end

local function makeWarn(parent: Instance): WarnObj
	local root = frame({ Name = "Warning", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 2 }, nil)
	local s = stroke(root, WARN, 1)
	s.LineJoinMode = Enum.LineJoinMode.Miter
	root.Parent = parent
	return { root = root, stroke = s }
end

-- skull in a 44 x 40 local box, facing +x (the beam direction); children in scale units
local function makeBlaster(parent: Instance): BlasterObj
	local root = frame({ Name = "Blaster", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 7 }, nil)
	local strokes = {}
	local function part(name: string, x: number, y: number, w: number, h: number, color: Color3, rot: number?, round: number?, z: number?): Frame
		local f = frame({
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x / 44, y / 40),
			Size = UDim2.fromScale(w / 44, h / 40),
			Rotation = rot or 0,
			BackgroundColor3 = color,
			ZIndex = z or 7,
		}, root)
		if round then
			corner(f, round)
		end
		return f
	end
	local whites = {}
	table.insert(whites, part("HornA", 6, 6, 14, 5, WHITE, -32, 0.5))
	table.insert(whites, part("HornB", 6, 34, 14, 5, WHITE, 32, 0.5))
	table.insert(whites, part("Cranium", 16, 20, 26, 34, WHITE, 0, 0.32))
	table.insert(whites, part("Ridge", 9, 20, 10, 5, WHITE, 0, 0.5))
	local mouth = part("Mouth", 35, 20, 15, 4, BLACK, 0, 0.2, 7)
	local jawTop = part("JawTop", 33, 14.5, 19, 11, WHITE, 0, 0.18, 8)
	local jawBottom = part("JawBottom", 33, 25.5, 19, 11, WHITE, 0, 0.18, 8)
	table.insert(whites, jawTop)
	table.insert(whites, jawBottom)
	local pupils = {}
	for _, y in { 13, 27 } do
		part("Socket", 20, y, 8, 8, BLACK, 0, 0.25, 8)
		local p = part("Pupil", 21, y, 3.6, 3.6, WHITE, 45, nil, 9)
		table.insert(pupils, p)
	end
	for _, w in whites do
		table.insert(strokes, stroke(w, WHITE, 1, false))
	end
	root.Parent = parent
	return {
		root = root,
		jawTop = jawTop,
		jawBottom = jawBottom,
		mouth = mouth,
		pupils = pupils,
		whites = whites,
		strokes = strokes,
		look = "",
	}
end

local function makeBeam(parent: Instance): BeamObj
	local root = frame({ Name = "Beam", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 6 }, nil)
	local layers = {}
	for i, h in { 1, 0.8, 0.5 } do
		local f = frame({
			Name = "Layer" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, h),
			BackgroundColor3 = WHITE,
			ZIndex = 6,
		}, root)
		table.insert(layers, f)
	end
	root.Parent = parent
	return { root = root, layers = layers }
end

local function makePlatform(parent: Instance): PlatformObj
	local root = frame({ Name = "Platform", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 3 }, nil)
	local back = frame({
		Name = "Offset",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 4),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, root)
	local s1 = stroke(back, PLATFORM_EDGE, 1)
	local s2 = stroke(root, WHITE, 1)
	s1.LineJoinMode = Enum.LineJoinMode.Miter
	s2.LineJoinMode = Enum.LineJoinMode.Miter
	root.Parent = parent
	return { root = root, back = back, strokes = { s1, s2 } }
end

local function makeRift(parent: Instance): RiftObj
	local root = frame({ Name = "Rift", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 6 }, nil)
	local core = frame({
		Name = "Void",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(5, 0, 12),
		ZIndex = 6,
	}, root)
	corner(core, 0.5)
	local s = stroke(core, Color3.fromRGB(176, 112, 255), 2)
	root.Parent = parent
	return { root = root, core = core, stroke = s }
end

local function hideFrame(obj: any)
	if obj.root.Visible then
		obj.root.Visible = false
	end
end

---------------------------------------------------------------------------------------------------
-- construction

function VerdictBoxView.new(parent: Instance?, timeline: any, opts: { [string]: any }?): View
	local o = opts or {}
	local mode = o.Mode or "Overlay"
	local theme = THEMES[timeline.theme] or THEMES.Classic
	local z = o.ZIndex or 1
	local root = frame({
		Name = "VerdictBox",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
		ZIndex = z,
	}, nil)
	-- stage: everything shakes together
	local stage = frame({ Name = "Stage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z }, root)
	local border = frame({
		Name = "Border",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = theme.border,
		ZIndex = 1,
	}, stage)
	local inner = frame({
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = theme.inner,
		ClipsDescendants = true,
		ZIndex = 1,
	}, border)
	local innerGlow = frame({
		Name = "Glow",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.innerGlow or theme.inner,
		BackgroundTransparency = if theme.innerGlow then 0 else 1,
		ZIndex = 1,
	}, inner)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.55, 0.85),
			NumberSequenceKeypoint.new(1, 0.35),
		}),
	}, innerGlow)
	if timeline.theme == "Eclipse" then
		-- faint fixed stars inside the box (deterministic from the seed)
		for i = 1, 14 do
			local sx, sy = hash01(i, timeline.seed % 101), hash01(i * 3.7, timeline.seed % 53)
			local d = frame({
				Name = "Speck",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(sx, sy),
				Size = UDim2.fromOffset(2, 2),
				BackgroundColor3 = Color3.fromRGB(200, 180, 255),
				BackgroundTransparency = 0.35 + hash01(i, 9) * 0.5,
				ZIndex = 1,
			}, innerGlow)
			corner(d, 0.5)
		end
	end
	local darkVeil = frame({
		Name = "Dark",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, inner)
	local over = frame({ Name = "Over", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6 }, stage)

	-- intro line (typed inside the dialogue box)
	local speechFont = if Strings.Language() == "ru" then "Jura" else theme.speech
	local textLabel = label({
		Name = "Line",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.fromScale(1, 1),
		FontFace = font(speechFont, Enum.FontWeight.Bold),
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = "",
		ZIndex = 8,
	}, inner)
	if theme.textStroke then
		textLabel.TextStrokeColor3 = theme.textStroke
		textLabel.TextStrokeTransparency = 0.2
	end
	new("UIPadding", {
		PaddingLeft = UDim.new(0.06, 0),
		PaddingTop = UDim.new(0.14, 0),
		PaddingRight = UDim.new(0.05, 0),
	}, textLabel)

	-- soul
	local soulRoot = frame({ Name = "Soul", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 9 }, nil)
	local soulPixels = {}
	for _, run in VerdictBoxView.SOUL_ROWS do
		local row, x0, x1, rows = run[1], run[2], run[3], run[4]
		table.insert(
			soulPixels,
			frame({
				Name = "Px",
				Position = UDim2.fromScale(x0 / 16, row / 16),
				Size = UDim2.new((x1 - x0 + 1) / 16, 0, rows / 16 + 0.004, 0),
				BackgroundColor3 = Sim.Palette.SoulRed,
				ZIndex = 9,
			}, soulRoot)
		)
	end
	soulRoot.Parent = inner
	local ring = frame({ Name = "Pulse", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 9, Visible = false }, inner)
	corner(ring, 0.5)
	local ringStroke = stroke(ring, WHITE, 2)

	-- time-left bar under the box
	local timer = frame({
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(40, 40, 40),
		ZIndex = 2,
	}, stage)
	local timerFill = frame({ Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = theme.border, ZIndex = 3 }, timer)

	local flash = frame({ Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 20 }, root)
	local verdict = label({
		Name = "Verdict",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(1, 0.14),
		TextScaled = true,
		Text = "",
		Visible = false,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = BLACK,
		ZIndex = 21,
	}, root)
	new("UITextSizeConstraint", { MaxTextSize = 72 }, verdict)
	local verdictSub = label({
		Name = "VerdictSub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.9, 0.06),
		TextScaled = true,
		Text = "",
		Visible = false,
		FontFace = font(speechFont, Enum.FontWeight.Bold),
		TextStrokeTransparency = 0.3,
		ZIndex = 21,
	}, root)
	new("UITextSizeConstraint", { MaxTextSize = 30 }, verdictSub)

	local self = setmetatable({
		Root = root,
		timeline = timeline,
		mode = mode,
		theme = theme,
		size = o.Size or Vector2.new(STAGE_W, STAGE_H),
		scale = 1,
		cx = 0,
		cy = 0,
		stage = stage,
		border = border,
		inner = inner,
		innerGlow = innerGlow,
		over = over,
		darkVeil = darkVeil,
		flash = flash,
		textLabel = textLabel,
		lineText = Strings.L(timeline.line),
		soulRoot = soulRoot,
		soulPixels = soulPixels,
		soulColor = nil,
		ring = ring,
		ringStroke = ringStroke,
		timer = timer,
		timerFill = timerFill,
		header = nil,
		hud = nil,
		hint = nil,
		verdict = verdict,
		verdictSub = verdictSub,
		floats = {},
		bones = pool(function()
			return makeBone(inner)
		end, hideFrame),
		stars = pool(function()
			return makeStar(inner)
		end, hideFrame),
		warns = pool(function()
			return makeWarn(inner)
		end, hideFrame),
		blasters = pool(function()
			return makeBlaster(over)
		end, hideFrame),
		beams = pool(function()
			return makeBeam(over)
		end, hideFrame),
		platforms = pool(function()
			return makePlatform(inner)
		end, hideFrame),
		rifts = pool(function()
			return makeRift(over)
		end, hideFrame),
		pose = Sim.NewPose(),
		hitAt = -10,
		pulseAt = -10,
		pulseColor = WHITE,
		fade = 0,
		lastT = 0,
	}, VerdictBoxView) :: any
	self.textLabel.Text = self.lineText

	if mode == "Overlay" then
		self:_buildHud(o.Title)
	else
		self.header = label({
			Name = "Header",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.new(0.96, 0, 0.085, 0),
			TextScaled = true,
			Text = Strings.L("vb.watch", string.upper(o.Name or "?")),
			TextColor3 = theme.text,
			ZIndex = 10,
		}, root)
	end
	for _ = 1, 4 do
		local f = label({
			Name = "Float",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(120, 24),
			TextScaled = true,
			Visible = false,
			TextStrokeTransparency = 0,
			ZIndex = 12,
		}, stage)
		table.insert(self.floats, { label = f, t0 = -10, x = 0, y = 0, active = false })
	end
	if parent then
		root.Parent = parent
	end
	return self
end

function VerdictBoxView._buildHud(self: View, title: string?)
	local stage = self.stage
	local hud: { [string]: any } = {}
	hud.title = label({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = title or Strings.L("vb.title"),
		TextColor3 = self.theme.text,
		TextScaled = true,
		ZIndex = 4,
	}, stage)
	hud.name = label({ Name = "Name", Text = "", TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, stage)
	hud.hpTag = label({ Name = "HpTag", Text = Strings.L("vb.hp"), TextScaled = true, ZIndex = 4 }, stage)
	hud.bar = frame({ Name = "HpBar", BackgroundColor3 = HP_BACK, ZIndex = 4 }, stage)
	hud.fill = frame({ Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = HP_FILL, ZIndex = 5 }, hud.bar)
	hud.kr = frame({ Name = "KR", AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = KR_COLOR, ZIndex = 6 }, hud.fill)
	hud.krTag = label({ Name = "KrTag", Text = Strings.L("vb.kr"), TextScaled = true, ZIndex = 4 }, stage)
	hud.numbers = label({ Name = "HpText", Text = "", TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, stage)
	self.hint = label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "",
		TextScaled = true,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		Visible = false,
		ZIndex = 4,
	}, stage)
	self.hud = hud
end

---------------------------------------------------------------------------------------------------
-- public controls

function VerdictBoxView.SetSize(self: View, size: Vector2)
	if size.X > 1 and size.Y > 1 then
		self.size = size
	end
end

function VerdictBoxView.Hit(self: View, t: number, damage: number?, kr: number?)
	self.hitAt = t
	local soul = self.soulRoot
	local placed = 0
	for _, f in self.floats do
		if placed >= 2 then
			break
		end
		if not f.active or t - f.t0 > 0.7 then
			f.active = true
			f.t0 = t
			f.x = soul.Position.X.Offset + self.inner.AbsolutePosition.X * 0
			f.y = 0
			if placed == 0 then
				f.label.Text = "-" .. tostring(damage or 0)
				f.label.TextColor3 = Color3.fromRGB(255, 70, 70)
			else
				f.label.Text = "+" .. tostring(kr or 0) .. " " .. Strings.L("vb.kr")
				f.label.TextColor3 = KR_COLOR
			end
			f.y = placed
			placed += 1
			if kr == nil or kr <= 0 then
				break
			end
		end
	end
end

function VerdictBoxView.Pulse(self: View, t: number, color: Color3?)
	self.pulseAt = t
	self.pulseColor = color or WHITE
end

function VerdictBoxView.SetVerdict(self: View, kind: string?, sub: string?)
	if kind == nil then
		self.verdict.Visible = false
		self.verdictSub.Visible = false
		return
	end
	self.verdict.Text = Strings.L("vb.verdict." .. kind)
	self.verdict.TextColor3 = if kind == "Innocent"
		then HP_FILL
		elseif kind == "Guilty" then Color3.fromRGB(255, 50, 50)
		else Color3.fromRGB(200, 200, 200)
	self.verdict.Visible = true
	self.verdictSub.Text = sub or ""
	self.verdictSub.Visible = sub ~= nil and sub ~= ""
end

function VerdictBoxView.SetHint(self: View, text: string?)
	local hint = self.hint
	if hint == nil then
		return
	end
	hint.Visible = text ~= nil and text ~= ""
	hint.Text = text or ""
end

function VerdictBoxView.SetFade(self: View, alpha: number)
	self.fade = math.clamp(alpha, 0, 1)
end

function VerdictBoxView.Destroy(self: View)
	self.Root:Destroy()
end

---------------------------------------------------------------------------------------------------
-- rendering

local function setVisible(inst: GuiObject, on: boolean)
	if inst.Visible ~= on then
		inst.Visible = on
	end
end

local function colorOf(theme: Theme, color: string): Color3
	if color == "Blue" then
		return Sim.Palette.Blue
	elseif color == "Orange" then
		return Sim.Palette.Orange
	end
	return theme.bone
end

-- look of a bone / star: fill + optional outline (Fell outline, darkness glow, chain rings)
local function applyBoneLook(self: View, obj: any, parts: { Frame }, strokes: { UIStroke }, color: string, style: string, alpha: number, dark: boolean)
	local key = color .. "|" .. style .. "|" .. (if dark then "D" else "L") .. "|" .. tostring(math.floor(alpha * 10 + 0.5))
	if obj.look == key then
		return
	end
	obj.look = key
	local theme = self.theme
	local fill = colorOf(theme, color)
	local outline: Color3? = nil
	local fillAlpha = 1 - alpha
	if dark then
		outline = if color == "White" then theme.glow else fill
		fill = DARK_FILL
	elseif color == "White" and theme.boneStroke then
		outline = theme.boneStroke
	end
	for i, part in parts do
		part.BackgroundColor3 = fill
		part.BackgroundTransparency = fillAlpha
		local s = strokes[i]
		if s then
			s.Enabled = outline ~= nil
			if outline then
				s.Color = outline
				s.Transparency = 1 - alpha
			end
		end
	end
	if style == "Chain" and obj.top then
		-- ring knobs: hollow links
		for _, knob in { obj.top, obj.bottom } do
			knob.BackgroundTransparency = 1
		end
		for i = 2, 3 do
			strokes[i].Enabled = true
			strokes[i].Color = if dark then (outline or theme.glow) else colorOf(theme, color)
			strokes[i].Transparency = 1 - alpha
		end
	end
end

function VerdictBoxView._bone(self: View, x: number, y: number, len: number, thick: number, angle: number, color: string, style: string, alpha: number, dark: boolean)
	local s = self.scale
	local o = take(self.bones)
	local root = o.root
	local lenPx, thickPx = len * s, thick * s
	root.Position = UDim2.fromOffset(x * s, y * s)
	root.Size = UDim2.fromOffset(thickPx, lenPx)
	root.Rotation = math.deg(angle)
	if math.abs(o.lastL - lenPx) > 0.25 or math.abs(o.lastT - thickPx) > 0.25 then
		o.lastL, o.lastT = lenPx, thickPx
		local knob = math.min(thickPx * 0.78, lenPx * 0.5)
		o.top.Size = UDim2.fromOffset(thickPx, knob)
		o.bottom.Size = UDim2.fromOffset(thickPx, knob)
		o.shaft.Size = UDim2.new(0.58, 0, 1, -knob)
		local th = math.max(1, s * (if dark then 1.4 else 1.1))
		for _, st in o.strokes do
			st.Thickness = th
		end
	end
	applyBoneLook(self, o, { o.shaft, o.top, o.bottom }, o.strokes, color, style, alpha, dark)
	setVisible(root, true)
end

function VerdictBoxView._star(self: View, x: number, y: number, size: number, angle: number, color: string, alpha: number, dark: boolean)
	local s = self.scale
	local o = take(self.stars)
	o.root.Position = UDim2.fromOffset(x * s, y * s)
	o.root.Size = UDim2.fromOffset(size * s, size * s)
	o.root.Rotation = math.deg(angle)
	applyBoneLook(self, o, o.bars, o.strokes, color, "", alpha, dark)
	setVisible(o.root, true)
end

function VerdictBoxView._warn(self: View, cx: number, cy: number, hw: number, hh: number, t: number)
	local s = self.scale
	local o = take(self.warns)
	o.root.Position = UDim2.fromOffset(cx * s, cy * s)
	o.root.Size = UDim2.fromOffset(math.max(hw * 2 * s - 2, 1), math.max(hh * 2 * s - 2, 1))
	o.stroke.Thickness = math.max(1, s * 1.2)
	o.stroke.Transparency = if math.floor(t * 12) % 2 == 0 then 0 else 0.45
	setVisible(o.root, true)
end

function VerdictBoxView._stab(self: View, p: any, b: any, t: number, dark: boolean)
	if p.phase == "Warn" then
		self:_warn(p.fx, p.fy, p.fw, p.fh, t)
		return
	end
	local h = p.height
	if h <= 0.5 then
		return
	end
	local wall = p.wall
	local span = math.abs(b.b - b.a)
	local thick = 10
	local count = math.max(math.floor(span / 11 + 0.5), 1)
	local step = span / count
	local embed = 8
	local len = h + embed
	for i = 0, count - 1 do
		local along = math.min(b.a, b.b) + step * (i + 0.5)
		local x, y, angle
		if wall == "Bottom" then
			x, y, angle = along, b.bh / 2 - h + len / 2, 0
		elseif wall == "Top" then
			x, y, angle = along, -b.bh / 2 + h - len / 2, 0
		elseif wall == "Left" then
			x, y, angle = -b.bw / 2 + h - len / 2, along, math.pi / 2
		else
			x, y, angle = b.bw / 2 - h + len / 2, along, math.pi / 2
		end
		self:_bone(x, y, len, thick, angle, p.color, p.style, 1, dark)
	end
end

function VerdictBoxView._blaster(self: View, p: any, t: number)
	local s = self.scale
	local scale = p.len / 44
	local o = take(self.blasters)
	local root = o.root
	root.Position = UDim2.fromOffset(p.x * s, p.y * s)
	root.Size = UDim2.fromOffset(44 * scale * s, 40 * scale * s)
	root.Rotation = math.deg(p.angle)
	local open = p.open
	local gap = 5.5 + open * 5
	o.jawTop.Position = UDim2.fromScale(33 / 44, (20 - gap) / 40)
	o.jawBottom.Position = UDim2.fromScale(33 / 44, (20 + gap) / 40)
	o.mouth.Size = UDim2.fromScale(15 / 44, (4 + open * 14) / 40)
	local look = p.style .. tostring(math.floor(p.alpha * 10 + 0.5))
	if o.look ~= look then
		o.look = look
		local alpha = p.alpha
		for _, w in o.whites do
			w.BackgroundTransparency = 1 - alpha
		end
		local rift = p.style == "Rift"
		for _, st in o.strokes do
			st.Enabled = rift or self.theme.boneStroke ~= nil
			st.Color = if rift then self.theme.glow else (self.theme.boneStroke or WHITE)
			st.Thickness = math.max(1, s)
			st.Transparency = 1 - alpha
		end
		for _, pupil in o.pupils do
			pupil.BackgroundColor3 = self.theme.pupil
			pupil.BackgroundTransparency = 1 - alpha
		end
		o.mouth.BackgroundTransparency = 1 - alpha
	end
	-- pupils flare while charging
	local flare = if p.phase == "Charge" then 1 + 0.35 * math.sin(t * 40) else 1
	for _, pupil in o.pupils do
		pupil.Size = UDim2.fromScale(3.6 * flare / 44, 3.6 * flare / 40)
	end
	setVisible(root, true)
	if p.beamW > 0.2 and p.beamAlpha > 0.01 then
		local bo = take(self.beams)
		local L = 900
		local dx, dy = math.cos(p.angle), math.sin(p.angle)
		bo.root.Position = UDim2.fromOffset((p.beamX + dx * L / 2) * s, (p.beamY + dy * L / 2) * s)
		bo.root.Size = UDim2.fromOffset(L * s, p.beamW * s)
		bo.root.Rotation = math.deg(p.angle)
		local wob = math.sin(p.time * 20) * 0.12
		local alpha = p.beamAlpha
		local sizes = { 1 + wob, 0.8 + wob * 0.8, 0.5 + wob * 0.5 }
		for i, layer in bo.layers do
			layer.Size = UDim2.fromScale(1, math.max(sizes[i], 0.05))
			layer.BackgroundColor3 = if i == 1 then self.theme.beamOuter else WHITE
			layer.BackgroundTransparency = 1 - alpha * (if i == 1 then 0.55 else if i == 2 then 0.85 else 1)
		end
		setVisible(bo.root, true)
	end
end

function VerdictBoxView._platform(self: View, p: any)
	local s = self.scale
	local o = take(self.platforms)
	o.root.Position = UDim2.fromOffset(p.x * s, p.y * s)
	o.root.Size = UDim2.fromOffset(p.len * s, p.thick * s)
	o.back.Position = UDim2.new(0.5, 0, 0.5, 4 * s)
	for _, st in o.strokes do
		st.Thickness = math.max(1, s)
	end
	setVisible(o.root, true)
end

function VerdictBoxView._rift(self: View, p: any)
	local s = self.scale
	local o = take(self.rifts)
	o.root.Position = UDim2.fromOffset(p.x * s, p.y * s)
	o.root.Size = UDim2.fromOffset(math.max(p.thick * s * (0.4 + 0.6 * p.open), 1), math.max(p.len * s * p.open, 1))
	o.root.Rotation = math.deg(p.angle)
	o.stroke.Thickness = math.max(1, 2 * s)
	o.stroke.Color = self.theme.glow
	setVisible(o.root, true)
end

-- camera: logical box-centred px -> container px
function VerdictBoxView._camera(self: View, w: number, h: number)
	local size = self.size
	if self.mode == "Overlay" then
		local s = math.min(size.X / STAGE_W, size.Y / STAGE_H)
		self.scale = s
		self.cx = size.X / 2
		self.cy = size.Y / 2 + (OVERLAY_BOX_Y - STAGE_H / 2) * s
	else
		local header = size.Y * 0.1
		local s = math.min(size.X / (w + MIRROR_MARGIN * 2), (size.Y - header) / (h + MIRROR_MARGIN * 2))
		self.scale = s
		self.cx = size.X / 2
		self.cy = header + (size.Y - header) / 2
	end
end

function VerdictBoxView._layoutHud(self: View, w: number, h: number, hudData: HudView?, t: number)
	local hud = self.hud
	if hud == nil then
		return
	end
	local s = self.scale
	local size = self.size
	local left = size.X / 2 - STAGE_W / 2 * s
	local top = size.Y / 2 - STAGE_H / 2 * s
	local function at(x: number, y: number): UDim2
		return UDim2.fromOffset(left + x * s, top + y * s)
	end
	hud.title.Position = at(320, 64)
	hud.title.Size = UDim2.fromOffset(560 * s, 22 * s)
	local rowY = OVERLAY_BOX_Y + 82.5 + 30
	local d = hudData
	local maxHp = if d then math.max(d.maxHp, 1) else 100
	local barW = math.clamp(maxHp * 1.2, 60, 190)
	local nameText = if d then string.upper(d.name) .. "   " .. Strings.L("vb.lv", d.lv) else ""
	hud.name.Text = nameText
	hud.name.Position = at(36, rowY)
	hud.name.Size = UDim2.fromOffset(200 * s, 14 * s)
	local barX = 300
	hud.hpTag.Position = at(barX - 34, rowY)
	hud.hpTag.Size = UDim2.fromOffset(26 * s, 12 * s)
	hud.bar.Position = at(barX, rowY - 3)
	hud.bar.Size = UDim2.fromOffset(barW * s, 21 * s)
	local hp = if d then math.clamp(d.hp, 0, maxHp) else maxHp
	local kr = if d then math.clamp(d.kr, 0, hp) else 0
	hud.fill.Size = UDim2.fromScale(hp / maxHp, 1)
	hud.kr.Position = UDim2.fromScale(1, 0)
	hud.kr.Size = UDim2.fromScale(if hp > 0 then kr / hp else 0, 1)
	hud.kr.Visible = kr > 0
	hud.krTag.Position = at(barX + barW + 8, rowY)
	hud.krTag.Size = UDim2.fromOffset(26 * s, 12 * s)
	hud.krTag.TextColor3 = if kr > 0 then KR_COLOR else WHITE
	hud.numbers.Position = at(barX + barW + 40, rowY)
	hud.numbers.Size = UDim2.fromOffset(120 * s, 14 * s)
	hud.numbers.Text = string.format("%02d / %d", math.ceil(hp), maxHp)
	hud.numbers.TextColor3 = if kr > 0 then KR_COLOR else WHITE
	if self.hint then
		self.hint.Position = at(320, rowY + 42)
		self.hint.Size = UDim2.fromOffset(520 * s, 13 * s)
	end
end

-- Draws the box at time t. soul = nil hides the heart.
function VerdictBoxView.Render(self: View, t: number, soul: SoulView?, hudData: HudView?)
	local tl = self.timeline
	self.lastT = t
	local w, h = Sim.BoxAt(tl, t)
	self:_camera(w, h)
	local s = self.scale
	local dark = Sim.EffectLevel(tl, "Dark", t)
	local isDark = dark > 0.5
	local shake = Sim.EffectLevel(tl, "Shake", t) * 3
	local sinceHit = t - self.hitAt
	if sinceHit >= 0 and sinceHit < 0.3 then
		shake += (1 - sinceHit / 0.3) * 5
	end
	local sincePulse = t - self.pulseAt
	if sincePulse >= 0 and sincePulse < 0.2 then
		shake += (1 - sincePulse / 0.2) * 3
	end
	local jx = (hash01(t * 60, 1) - 0.5) * 2 * shake * s
	local jy = (hash01(t * 60, 2) - 0.5) * 2 * shake * s
	self.stage.Position = UDim2.fromOffset(jx, jy)

	-- box
	local bpx = BORDER * s
	self.border.Position = UDim2.fromOffset(self.cx, self.cy)
	self.border.Size = UDim2.fromOffset(w * s + bpx * 2, h * s + bpx * 2)
	self.border.BackgroundTransparency = if isDark then 0.8 else 0
	self.inner.Size = UDim2.fromOffset(w * s, h * s)
	self.darkVeil.BackgroundTransparency = 1 - dark
	local overX, overY = self.cx - w * s / 2 - bpx, self.cy - h * s / 2 - bpx
	-- `over` is positioned so that its origin is the box centre too
	self.over.Position = UDim2.fromOffset(self.cx, self.cy)
	self.over.Size = UDim2.fromOffset(0, 0)
	local _ = overX + overY

	-- timer bar
	local remain = math.clamp(1 - (t - tl.introEnd) / math.max(tl.duration - tl.introEnd, 0.1), 0, 1)
	self.timer.Position = UDim2.fromOffset(self.cx, self.cy + h * s / 2 + bpx + 4 * s)
	self.timer.Size = UDim2.fromOffset(w * s, math.max(2, 2.5 * s))
	self.timerFill.Size = UDim2.fromScale(remain, 1)
	setVisible(self.timer, t >= tl.introEnd)

	-- intro line
	local intro = t < tl.introEnd
	setVisible(self.textLabel, intro)
	if intro then
		self.textLabel.TextSize = math.max(8, math.floor(17 * s))
		local total = utf8.len(self.lineText) or #self.lineText
		self.textLabel.MaxVisibleGraphemes = Sim.IntroChars(tl, t, total)
	end

	-- bullets: inner children use box-centred offsets from the inner frame's centre
	local half = Vector2.new(w * s / 2, h * s / 2)
	local p = self.pose
	for _, b in tl.bullets do
		if t >= b.t0 and t <= b.t1 then
			local pose = Sim.Pose(b, t, p)
			if pose then
				local kind = pose.kind
				if kind == "Bone" then
					self:_bone(pose.x + half.X / s, pose.y + half.Y / s, pose.len, pose.thick, pose.angle, pose.color, pose.style, pose.alpha, isDark)
				elseif kind == "Star" then
					self:_star(pose.x + half.X / s, pose.y + half.Y / s, pose.len, pose.angle, pose.color, pose.alpha, isDark)
				elseif kind == "Stab" then
					-- stab geometry is box-centred; shift into inner-frame space
					local shifted = pose
					shifted.fx += half.X / s
					shifted.fy += half.Y / s
					local bb = {
						a = b.a,
						b = b.b,
						bw = b.bw,
						bh = b.bh,
					}
					if shifted.phase == "Warn" then
						self:_warn(shifted.fx, shifted.fy, shifted.fw, shifted.fh, t)
					else
						self:_stabShifted(shifted, bb, half.X / s, half.Y / s, isDark)
					end
				elseif kind == "Platform" then
					pose.x += half.X / s
					pose.y += half.Y / s
					self:_platform(pose)
				elseif kind == "Blaster" then
					self:_blaster(pose, t)
				elseif kind == "Rift" then
					self:_rift(pose)
				end
			end
		end
	end
	finishPool(self.bones)
	finishPool(self.stars)
	finishPool(self.warns)
	finishPool(self.blasters)
	finishPool(self.beams)
	finishPool(self.platforms)
	finishPool(self.rifts)

	-- soul
	local soulRoot = self.soulRoot
	if soul and soul.visible ~= false and not intro and t < tl.duration then
		local blink = soul.blink == true and math.floor(t * 15) % 2 == 0
		soulRoot.Visible = not blink
		soulRoot.Position = UDim2.fromOffset(soul.x * s + half.X, soul.y * s + half.Y)
		soulRoot.Size = UDim2.fromOffset(16 * s, 16 * s)
		soulRoot.Rotation = if soul.mode == "Blue" then Sim.SoulAngle(soul.gravity) else 0
		local color = if soul.mode == "Blue" then Sim.Palette.SoulBlue else Sim.Palette.SoulRed
		if self.soulColor ~= color then
			self.soulColor = color
			for _, px in self.soulPixels do
				px.BackgroundColor3 = color
			end
		end
	else
		soulRoot.Visible = false
	end
	-- pulse ring
	if sincePulse >= 0 and sincePulse < 0.35 and soul then
		local k = sincePulse / 0.35
		self.ring.Visible = true
		self.ring.Position = soulRoot.Position
		local d = (16 + 50 * k) * s
		self.ring.Size = UDim2.fromOffset(d, d)
		self.ringStroke.Color = self.pulseColor
		self.ringStroke.Transparency = k
		self.ringStroke.Thickness = math.max(1, 2 * s)
	else
		self.ring.Visible = false
	end

	-- floating numbers (stage space)
	for _, f in self.floats do
		local age = t - f.t0
		if f.active and age >= 0 and age < 0.7 then
			f.label.Visible = true
			local sx = if soul then soul.x * s + self.cx else self.cx
			local sy = if soul then soul.y * s + self.cy else self.cy
			f.label.Position = UDim2.fromOffset(sx + (f.y * 10 + 14) * s, sy - (14 + f.y * 14 + age * 40) * s)
			f.label.Size = UDim2.fromOffset(90 * s, 12 * s)
			f.label.TextTransparency = math.clamp((age - 0.35) / 0.35, 0, 1)
			f.label.TextStrokeTransparency = f.label.TextTransparency
		else
			f.active = f.active and age < 0.7
			f.label.Visible = false
		end
	end

	-- flashes
	local flashLevel = Sim.EffectLevel(tl, "Flash", t)
	local flashColor = WHITE
	if sinceHit >= 0 and sinceHit < 0.3 then
		local k = (1 - sinceHit / 0.3) * 0.4
		if k > flashLevel then
			flashLevel, flashColor = k, Color3.fromRGB(255, 0, 0)
		end
	end
	if sincePulse >= 0 and sincePulse < 0.12 then
		local k = (1 - sincePulse / 0.12) * 0.25
		if k > flashLevel then
			flashLevel, flashColor = k, self.pulseColor
		end
	end
	self.flash.BackgroundColor3 = flashColor
	self.flash.BackgroundTransparency = 1 - math.max(flashLevel, self.fade)
	if self.fade > flashLevel then
		self.flash.BackgroundColor3 = BLACK
	end

	-- HUD / header
	if self.hud then
		self:_layoutHud(w, h, hudData, t)
	end
	if self.header then
		self.header.Size = UDim2.new(0.96, 0, 0.085, 0)
	end
end

-- stab drawing in inner-frame space (box geometry + half-size offset)
function VerdictBoxView._stabShifted(self: View, p: any, b: any, ox: number, oy: number, dark: boolean)
	local h = p.height
	if h <= 0.5 then
		return
	end
	local wall = p.wall
	local lo, hi = math.min(b.a, b.b), math.max(b.a, b.b)
	local span = hi - lo
	local count = math.max(math.floor(span / 11 + 0.5), 1)
	local step = span / count
	local embed = 8
	local len = h + embed
	for i = 0, count - 1 do
		local along = lo + step * (i + 0.5)
		local x, y, angle
		if wall == "Bottom" then
			x, y, angle = along, b.bh / 2 - h + len / 2, 0
		elseif wall == "Top" then
			x, y, angle = along, -b.bh / 2 + h - len / 2, 0
		elseif wall == "Left" then
			x, y, angle = -b.bw / 2 + h - len / 2, along, math.pi / 2
		else
			x, y, angle = b.bw / 2 - h + len / 2, along, math.pi / 2
		end
		self:_bone(x + ox, y + oy, len, 10, angle, p.color, p.style, 1, dark)
	end
end

---------------------------------------------------------------------------------------------------
-- Preview screen (tools/lune/dump_gui.luau): Create(theme, deps) -> { Root, Destroy }

local function previewSoul(tl: any, t: number): SoulView
	local m = Sim.ModeAt(tl, t)
	local x, y = Sim.AutoSoul(tl, t)
	return { x = x, y = y, mode = m.mode, gravity = m.gravity, blink = false, visible = true }
end

function VerdictBoxView.Create(_theme: any, deps: { [string]: any }?): { Root: GuiObject, Destroy: () -> () }
	local d = deps or {}
	local set = d.Set or "Classic"
	local seed = d.Seed or 7
	local tl = Patterns.Build(set, seed, d.Duration)
	local layout = d.Layout
	local canvas: Vector2 = if layout and layout.Canvas then layout.Canvas else Vector2.new(1600, 900)
	local root = frame({ Name = "VerdictBoxPreview", Size = UDim2.fromOffset(canvas.X, canvas.Y), BackgroundColor3 = Color3.fromRGB(14, 14, 18) }, nil)
	local kind = d.Kind or "Sheet"
	if kind == "Overlay" then
		local view = VerdictBoxView.new(root, tl, { Mode = "Overlay", Size = canvas, Title = d.Title })
		local t = d.Time or 3.2
		if d.HitAt then
			view:Hit(d.HitAt, 5, 3)
		end
		view:Render(t, previewSoul(tl, t), { name = d.Name or "Frisk", lv = 7, hp = d.Hp or 74, maxHp = 110, kr = d.Kr or 9 })
		if d.Hint then
			view:SetHint(Strings.L(d.Hint))
			view:Render(t, previewSoul(tl, t), { name = d.Name or "Frisk", lv = 7, hp = d.Hp or 74, maxHp = 110, kr = d.Kr or 9 })
		end
		if d.Verdict then
			view:SetVerdict(d.Verdict, Strings.L("vb.verdict." .. d.Verdict .. ".sub", 3))
		end
	else
		-- a grid of mirror-style frames at several times (with segment captions)
		local times: { number } = d.Times or { 0.6, 1.7, 2.6, 3.4, 4.3, 5.1, 5.9, 6.6 }
		local cols = d.Cols or 4
		local rows = math.ceil(#times / cols)
		local pad = 18
		local cell = math.min((canvas.X - pad * (cols + 1)) / cols, (canvas.Y - pad * (rows + 1) - 30) / rows)
		label({
			Name = "Caption",
			Position = UDim2.fromOffset(pad, 4),
			Size = UDim2.fromOffset(canvas.X - pad * 2, 24),
			Text = string.format("VERDICT BOX - %s - seed %d - %s", set, seed, table.concat(Patterns.Chain(set, seed), " > ")),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(190, 190, 200),
		}, root)
		for i, t in times do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			local holder = frame({
				Name = "Cell" .. i,
				Position = UDim2.fromOffset(pad + col * (cell + pad), 34 + pad + row * (cell + pad)),
				Size = UDim2.fromOffset(cell, cell),
				BackgroundColor3 = BLACK,
			}, root)
			local view = VerdictBoxView.new(holder, tl, { Mode = if kind == "Overlay" then "Overlay" else "Mirror", Size = Vector2.new(cell, cell), Name = d.Name or "Frisk" })
			view:Render(t, previewSoul(tl, t))
			local segName = "intro"
			for _, sg in tl.segments do
				if t >= sg.t0 and t < sg.t1 then
					segName = sg.name
				end
			end
			label({
				Name = "Time",
				Position = UDim2.new(0, 6, 1, -20),
				Size = UDim2.new(1, -12, 0, 16),
				Text = string.format("t=%.1fs  %s", t, segName),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(150, 150, 160),
				ZIndex = 30,
			}, holder)
		end
	end
	return {
		Root = root,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return VerdictBoxView
