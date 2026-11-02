--!strict
-- Overlays/Loading: the PLAY / PRACTICE loading screen (owner's request). The screen fades to black, the owner's
-- pixel Sans head (Shared/PixelArt/SansHead) spins in the centre over "LOADING" + animated dots (Classic pixel font
-- PressStart2P through Themes.Font, so ru shows "ЗАГРУЗКА"; Fell tints the dots red), the caller's OnCovered runs
-- while everything is black (UIController closes the Title there, so the reveal shows the lobby / the arena), the
-- overlay holds, then fades out. Its own ScreenGui above every UIRoot layer (DisplayOrder 1000, IgnoreGuiInset =
-- true, ScreenInsets = None, ClipToDeviceSafeArea = false: the black covers the whole phone screen, notch and top-bar
-- strip included; Roblox's own top-bar buttons stay on top). It sinks input while it is up and ALWAYS ends: the
-- MaxWait cap, a real-time failsafe timer, and any error finishes it at once (OnCovered still runs exactly once).
--
-- SPIN MODE - to switch the animation change SPIN_MODE right below these comments:
--   "Turn"  (default) the head turns like a coin around its vertical axis: its width follows |cos|, the mirrored
--           sprite shows while cos < 0 (the back of the coin), ~1.2 s per full turn, plus a tiny vertical bob.
--   "Wheel" the whole head rotates in the screen plane like a wheel (a CanvasGroup rotates the sprite as one image).
--   Loading.Show({ Mode = "Wheel" }) overrides it for one call. With Roblox "Reduced Motion" on the head stays still.
--
-- Sequence (seconds, Loading.Timing): FadeIn 0.35 -> OnCovered -> head + text appear (ContentIn 0.25) -> hold: at
-- least MinVisible 2.2 from Show; with opts.Until until it returns true + Settle 0.3, but never past MaxWait 7 ->
-- ContentOut 0.15 (head + text sink into the black) -> FadeOut 0.4 (the black lifts) -> OnDone.
-- Music cue (opts.MusicLead > 0): OnMusicCue fires MusicLead s before the fade-out starts, or at once when the
-- fade-out is already closer than that (Until turned true late): the lead NEVER delays the reveal. While still waiting
-- on Until it fires MusicLead s before the cap. (PLAY 4 s: cue at 2 s, reveal at 4 s; PRACTICE: the round's Intro
-- arrives -> cue now, reveal Settle s later, so the Intro is seen.)
-- Sound: Audio "PlayTransition" starts with the fade to black; when the overlay ends it fades out (SoundFade 0.4 s)
-- if it is still playing. The music is ducked while the screen is black (SoundController.Duck, re-armed 4x/s).
-- A plain dip (opts.Content = false: no head / text, e.g. FadeIn 0.2 / MinVisible 0.3 / FadeOut 0.3) hides a quick
-- menu -> game switch.
--
-- Pixels: the sprite is drawn with SansHead.LayeredRuns (one Frame per run) inside a container GRID x GRID sprite
-- pixels big (power-of-two Scale fractions = exact maths); at rest every sprite pixel is an integer number of screen
-- pixels (Loading.PixelSize: ~5 on a 400 px tall phone, 12 at 1080p), so the head is crisp. The coin turn only
-- resizes / moves the container (no per-cell work per frame).
--
-- API
--   Loading.Show(opts?) -> Handle?   nil = could not show (the caller then does the old instant behaviour)
--       opts: { OnCovered: (() -> ())?, Until: (() -> boolean)?, OnDone: (() -> ())?, MinVisible: number?,
--               MusicLead: number?, OnMusicCue: (() -> ())? (fires MusicLead s before the reveal; no ducking then),
--               MaxWait: number?, Settle / FadeIn / ContentIn / ContentOut / FadeOut: number? (Timing overrides),
--               Content: boolean? (false = a plain black dip: no head / text), Mode: SpinMode?, Theme: Theme?,
--               Sound: SoundController? (nil = no transition sound, no ducking), Parent: Instance? (default
--               PlayerGui), ReducedMotion: boolean?, Driver: Driver? }
--       The returned handle may already be Done (a dead frame loop finishes at once: OnCovered / OnMusicCue / OnDone
--       have run inside Show then).
--       Driver (tests / tools; default = RunService.Heartbeat + task.delay + the ScreenGui's AbsoluteSize):
--               { Connect: (step: (dt) -> ()) -> (() -> ()) (returns disconnect), Viewport: (() -> Vector2)?,
--                 Delay: ((seconds, fn) -> ())? }
--       A Show while one is running returns the running handle (overlays never stack; the new opts are ignored).
--   Handle: { Covered: boolean, Done: boolean, Sequence: Sequence, View: View, Finish() (fade out as soon as the
--             screen is black), Destroy() (remove now; OnCovered / OnDone still run once) }
--   Loading.Active() -> Handle?
-- Pure (Lune tests / previews)
--   Loading.PixelSize(viewport) -> integer screen px per sprite pixel     Loading.Metrics(viewport, mode?) -> Metrics
--   Loading.TurnPose(t, period?) -> (widthFactor 0..1, mirrored)          Loading.WheelAngle(t, period?) -> degrees
--   Loading.Bob(t, amplitude) -> integer px    Loading.DotCount(t) -> 0..3    Loading.Text(word, dots, color?) -> RichText
--   Loading.NewSequence(timing?) -> Sequence { Stage, Time, Backdrop 0..1, Content 0..1, CoveredAt, ReadyAt, OutAt,
--       Step(dt, ready) -> (coveredNow, doneNow), Skip() }
--   Loading.Build(theme?, { Viewport, Mode?, Plain? }) -> View { Gui, Backdrop, Content, Curtain, Head, Normal,
--       Mirrored?, Label, Mode, Plain, Metrics, Layout(viewport), Pose(t, dots?), Fade(backdrop, content), Destroy() }
--       (text in Strings.Language(): "LOADING" / "ЗАГРУЗКА"; Plain = no sprite cells, no text: the black alone)
--   Loading.Preview(theme?, viewport, { Spin = turn phase 0..1 (0 = facing front), Mode?, Dots? }?) -> View
--       a settled frame for offline renders: black screen, head + text fully shown at that spin phase.

local SPIN_MODE: SpinMode = "Turn" -- "Turn" (coin) | "Wheel" (in-plane rotation)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any
local SansHead = require(Shared:WaitForChild("PixelArt"):WaitForChild("SansHead"))
local Themes = require(script.Parent.Parent.Themes)

type Theme = Themes.Theme

export type SpinMode = "Turn" | "Wheel" | "Still"

export type Timing = {
	FadeIn: number,
	ContentIn: number,
	MinVisible: number,
	Settle: number,
	MaxWait: number,
	ContentOut: number,
	FadeOut: number,
}

export type Sequence = {
	Stage: string, -- "FadeIn" | "Hold" | "FadeOut" | "Done"
	Time: number,
	Backdrop: number,
	Content: number,
	CoveredAt: number?,
	ReadyAt: number?,
	OutAt: number?,
	Timing: Timing,
	Step: (dt: number, ready: boolean) -> (boolean, boolean),
	Skip: () -> (),
}

export type Metrics = {
	Viewport: Vector2,
	Pixel: number,
	Grid: number,
	CenterX: number,
	Left: number,
	Top: number,
	HeadTop: number,
	HeadW: number,
	HeadH: number,
	TextSize: number,
	TextTop: number,
	Bob: number,
}

export type View = {
	Gui: ScreenGui,
	Backdrop: Frame,
	Content: Frame,
	Curtain: Frame,
	Head: GuiObject,
	Normal: Frame,
	Mirrored: Frame?,
	Label: TextLabel,
	Mode: SpinMode,
	Plain: boolean,
	Metrics: Metrics,
	Layout: (Vector2) -> (),
	Pose: (number, number?) -> (),
	Fade: (number, number) -> (),
	Destroy: () -> (),
}

export type Driver = {
	Connect: ((number) -> ()) -> () -> (),
	Viewport: (() -> Vector2)?,
	Delay: ((number, () -> ()) -> ())?,
}

export type Handle = {
	Covered: boolean,
	Done: boolean,
	Sequence: Sequence,
	View: View,
	Finish: () -> (),
	Destroy: () -> (),
}

local Loading = {}

Loading.SPIN_MODE = SPIN_MODE
Loading.DisplayOrder = 1000 -- above every UIRoot layer (Hud 5 .. Cursor 50) and the Verdict Box (25)
Loading.SoundName = "PlayTransition"
Loading.Timing = {
	FadeIn = 0.35, -- s: the screen goes black
	ContentIn = 0.25, -- s: head + text rise out of the black
	MinVisible = 2.2, -- s from Show before the fade-out may start
	Settle = 0.3, -- s held after opts.Until turns true (teleport / camera settle under the black)
	MaxWait = 7, -- s from Show: hard cap (a practice round that never starts)
	MusicLead = 0, -- s: opts.OnMusicCue fires this long BEFORE the fade-out starts (0 = no cue, release at once)
	ContentOut = 0.15, -- s: head + text sink into the black
	FadeOut = 0.4, -- s: the black lifts
}
Loading.TurnPeriod = 1.2 -- s per full coin turn
Loading.WheelPeriod = 1.6 -- s per full wheel turn
Loading.BobPeriod = 2.4 -- s per bob cycle (up and down)
Loading.DotPeriod = 0.35 -- s per dot step ("", ".", "..", "...")
Loading.SoundFade = 0.4 -- s
Loading.DuckAmount = 0.7 -- music at 30% while the screen is black
Loading.FailsafeMargin = 2 -- s past MaxWait + fades before the overlay is force-removed (frame loop died)

local GRID = 64 -- container cells (power of two: exact Scale fractions); the sprite sits inside it:
local OFFSET_X = 12 -- 12 + 40 + 12 = 64 -> centred horizontally (the coin turn squeezes about the true centre)
local OFFSET_Y = 13 -- 13 + 37 + 14 = 64
local HEAD_SHARE = 0.48 -- head height / short side of the screen
local MIN_PIXEL, MAX_PIXEL = 2, 12
local MAX_DOTS = 3
local MAX_STEP = 0.25 -- s: longest dt one Step accepts (a hitch never skips a whole fade)
local DUCK_EVERY = 0.25 -- s between SoundController.Duck re-arms
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

------------------------------------------------------------------------------------------------ pure helpers

local function smooth(x: number): number
	local u = math.clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end

function Loading.PixelSize(viewport: Vector2): number
	local short = math.max(math.min(viewport.X, viewport.Y), 1)
	return math.clamp(math.round(short * HEAD_SHARE / SansHead.Height), MIN_PIXEL, MAX_PIXEL)
end

function Loading.Metrics(viewport: Vector2, mode: SpinMode?): Metrics
	local w = math.max(math.round(viewport.X), 1)
	local h = math.max(math.round(viewport.Y), 1)
	local p = Loading.PixelSize(viewport)
	local headW = SansHead.Width * p
	local headH = SansHead.Height * p
	local textSize = 8 * math.max(1, math.round(p / 2)) -- PressStart2P is drawn on an 8 px grid
	-- a wheel-turning head reaches ~2.5 cells further down at 45 degrees than upright: more room above the text
	local gap = (if mode == "Wheel" then 6 else 3) * p
	local headTop = math.floor((h - (headH + gap + textSize)) / 2)
	local centerX = math.floor(w / 2)
	local grid = GRID * p
	return {
		Viewport = Vector2.new(w, h),
		Pixel = p,
		Grid = grid,
		CenterX = centerX,
		Left = centerX - math.floor(grid / 2),
		Top = headTop - OFFSET_Y * p,
		HeadTop = headTop,
		HeadW = headW,
		HeadH = headH,
		TextSize = textSize,
		TextTop = headTop + headH + gap,
		Bob = math.max(1, math.round(p * 0.5)),
	}
end

function Loading.TurnPose(t: number, period: number?): (number, boolean)
	local c = math.cos(2 * math.pi * t / (period or Loading.TurnPeriod))
	return math.abs(c), c < 0
end

function Loading.WheelAngle(t: number, period: number?): number
	return (360 * t / (period or Loading.WheelPeriod)) % 360
end

function Loading.Bob(t: number, amplitude: number): number
	return math.round(math.sin(2 * math.pi * t / Loading.BobPeriod) * amplitude)
end

function Loading.DotCount(t: number): number
	return math.floor(math.max(t, 0) / Loading.DotPeriod) % (MAX_DOTS + 1)
end

local function hex(c: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.round(math.clamp(c.R, 0, 1) * 255),
		math.round(math.clamp(c.G, 0, 1) * 255),
		math.round(math.clamp(c.B, 0, 1) * 255)
	)
end

local function escapeRich(s: string): string
	return (
		string.gsub(s, "[&<>\"']", {
			["&"] = "&amp;",
			["<"] = "&lt;",
			[">"] = "&gt;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

local HIDE = '<font transparency="1">'

-- "LOADING" + `dots` visible dots. Invisible dots pad both sides (same glyphs = same width), so the word stays
-- exactly centred and never moves while the dots animate.
function Loading.Text(word: string, dots: number, color: Color3?): string
	local n = math.clamp(math.floor(dots), 0, MAX_DOTS)
	local shown = string.rep(".", n)
	if color and n > 0 then
		shown = ('<font color="%s">%s</font>'):format(hex(color), shown)
	end
	local hidden = if n < MAX_DOTS then HIDE .. string.rep(".", MAX_DOTS - n) .. "</font>" else ""
	return HIDE .. string.rep(".", MAX_DOTS) .. "</font>" .. escapeRich(word) .. shown .. hidden
end

local MAX_CAP = 30 -- s: no caller can keep the black screen up longer than this

local function mergedTiming(over: { [string]: any }?): Timing
	local t = table.clone(Loading.Timing) :: any
	if over then
		for key in Loading.Timing do
			local v = over[key]
			if type(v) == "number" and v == v and v >= 0 and v < math.huge then
				t[key] = v
			end
		end
	end
	t.MaxWait = math.min(t.MaxWait, MAX_CAP)
	return t :: Timing
end

function Loading.NewSequence(timing: { [string]: any }?): Sequence
	local cfg = mergedTiming(timing)
	local seq = {
		Stage = "FadeIn",
		Time = 0,
		Backdrop = 0,
		Content = 0,
		CoveredAt = nil :: number?,
		ReadyAt = nil :: number?,
		CueAt = nil :: number?,
		OutAt = nil :: number?,
		Timing = cfg,
	} :: any
	local skipped = false
	local contentAtOut = 0

	function seq.Skip()
		skipped = true
	end

	-- Advances by dt seconds; `ready` = the caller's Until() (only read while holding). Returns (coveredNow,
	-- doneNow, cueNow): coveredNow on the step the screen turned fully black, doneNow on the step the overlay finished,
	-- cueNow on the step the music cue fires (Timing.MusicLead s before the fade-out, at once when the fade-out is
	-- already closer; with MusicLead 0 on the step the fade-out starts).
	function seq.Step(dt: number, ready: boolean): (boolean, boolean, boolean)
		if seq.Stage == "Done" then
			return false, false, false
		end
		local d = if type(dt) == "number" and dt == dt then math.clamp(dt, 0, MAX_STEP) else 0
		seq.Time += d
		local t = seq.Time
		local coveredNow, doneNow, cueNow = false, false, false
		if seq.Stage == "FadeIn" then
			seq.Backdrop = smooth(t / math.max(cfg.FadeIn, 1e-3))
			if t >= cfg.FadeIn then
				seq.Stage = "Hold"
				seq.Backdrop = 1
				seq.CoveredAt = t
				coveredNow = true
			end
		elseif seq.Stage == "Hold" then
			seq.Content = smooth((t - (seq.CoveredAt :: number)) / math.max(cfg.ContentIn, 1e-3))
			if ready and seq.ReadyAt == nil then
				seq.ReadyAt = t
			end
			local readyAt = seq.ReadyAt
			local lead = math.max(cfg.MusicLead or 0, 0)
			-- the reveal: MinVisible after Show and Settle after ready (never later than the cap); the music lead
			-- never moves it - the cue goes out `lead` s before it, or at once when it is already closer than that
			local releaseAt = math.min(
				if readyAt ~= nil then math.max(cfg.MinVisible, readyAt + cfg.Settle) else math.huge,
				cfg.MaxWait
			)
			local release = skipped or t >= releaseAt
			if seq.CueAt == nil and (release or t >= releaseAt - lead) then
				seq.CueAt = t
				cueNow = true
			end
			if release then
				seq.Stage = "FadeOut"
				seq.OutAt = t
				contentAtOut = seq.Content
			end
		elseif seq.Stage == "FadeOut" then
			local u = t - (seq.OutAt :: number)
			if u < cfg.ContentOut then
				seq.Content = contentAtOut * (1 - smooth(u / math.max(cfg.ContentOut, 1e-3)))
			else
				seq.Content = 0
				seq.Backdrop = 1 - smooth((u - cfg.ContentOut) / math.max(cfg.FadeOut, 1e-3))
			end
			if u >= cfg.ContentOut + cfg.FadeOut then
				seq.Stage = "Done"
				seq.Backdrop = 0
				seq.Content = 0
				doneNow = true
			end
		end
		return coveredNow, doneNow, cueNow
	end

	return seq :: Sequence
end

------------------------------------------------------------------------------------------------ builder

local function newFrame(name: string, color: Color3, transparency: number, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Size = UDim2.fromScale(1, 1)
	return f
end

-- one sprite (every run a Frame) filling its GRID x GRID container; white under-fill first, black runs on top
local function buildSprite(name: string, rows: { string }): Frame
	local holder = newFrame(name, BLACK, 1, 1)
	for i, run in SansHead.LayeredRuns(rows) do
		local white = run.color == "."
		local cell =
			newFrame((if white then "W" else "B") .. i, SansHead.Colors[run.color] or WHITE, 0, if white then 1 else 2)
		cell.Position = UDim2.fromScale((run.x + OFFSET_X) / GRID, (run.y + OFFSET_Y) / GRID)
		cell.Size = UDim2.fromScale(run.length / GRID, 1 / GRID)
		cell.Parent = holder
	end
	return holder
end

local function validMode(mode: any): SpinMode
	if mode == "Turn" or mode == "Wheel" or mode == "Still" then
		return mode
	end
	return SPIN_MODE
end

function Loading.Build(theme: Theme?, opts: { [string]: any }?): View
	local o = opts or {}
	local plain = o.Plain == true -- the black alone (a quick dip): no sprite cells, no text
	local mode = if plain then "Still" else validMode(o.Mode)
	local lang = Strings.Language()
	local th = theme or Themes.Get(nil)
	local viewport: Vector2 = if typeof(o.Viewport) == "Vector2" then o.Viewport else Vector2.new(1920, 1080)

	local gui = Instance.new("ScreenGui")
	gui.Name = "SV_Loading"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Loading.DisplayOrder

	-- the black; Active = it swallows taps / clicks meant for the menu underneath while the overlay is up
	local backdrop = newFrame("Backdrop", BLACK, 1, 1)
	backdrop.Active = true
	backdrop.Parent = gui

	local content = newFrame("Content", BLACK, 1, 2)
	content.Visible = false

	-- Wheel: a CanvasGroup draws the sprite into one image and turns that image (seam-free); ~170 separately
	-- rotated cell Frames would each get anti-aliased edges and show hairline seams
	local head: GuiObject = if mode == "Wheel" then Instance.new("CanvasGroup") else Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.BorderSizePixel = 0
	head.ZIndex = 1
	local normal = if plain then newFrame("Normal", BLACK, 1, 1) else buildSprite("Normal", SansHead.Rows)
	normal.Parent = head
	local mirrored: Frame? = nil
	if mode == "Turn" then
		local m = buildSprite("Mirrored", SansHead.MirroredRows)
		m.Visible = false
		m.Parent = head
		mirrored = m
	end
	head.Parent = content

	local word = if plain then "" else Strings.L("loading.title")
	local dotColor: Color3? = if th.Id == "Fell" then th.Colors.SoulRed else nil
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.ZIndex = 2
	label.RichText = true
	label.TextColor3 = WHITE
	label.FontFace = Themes.Font(Themes.Get("Classic"), "Display", lang)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = false
	label.Text = if plain then "" else Loading.Text(word, 0, dotColor)
	label.Parent = content
	content.Parent = gui

	-- above the content: fades it in / out of the black without touching every sprite cell
	local curtain = newFrame("Curtain", BLACK, 0, 3)
	curtain.Visible = false
	curtain.Parent = gui

	local view = {
		Gui = gui,
		Backdrop = backdrop,
		Content = content,
		Curtain = curtain,
		Head = head,
		Normal = normal,
		Mirrored = mirrored,
		Label = label,
		Mode = mode,
		Plain = plain,
	} :: any

	local metrics: Metrics = Loading.Metrics(viewport, mode)
	local shownDots = -1
	local lastWidth = -1
	local lastFlip: boolean? = nil

	local function placeHead(width: number, bob: number)
		head.Size = UDim2.fromOffset(width, metrics.Grid)
		head.Position = UDim2.fromOffset(metrics.CenterX - math.floor(width / 2), metrics.Top + bob)
	end

	function view.Layout(size: Vector2)
		metrics = Loading.Metrics(size, mode)
		view.Metrics = metrics
		lastWidth = -1
		lastFlip = nil
		placeHead(metrics.Grid, 0)
		head.Rotation = 0
		label.Position = UDim2.fromOffset(0, metrics.TextTop)
		label.Size = UDim2.new(1, 0, 0, metrics.TextSize)
		label.TextSize = metrics.TextSize
	end

	-- t = seconds since the head appeared (0 = facing front, upright); dots = override of the animated dot count
	function view.Pose(t: number, dots: number?)
		if plain then
			return -- nothing to animate on a plain dip
		end
		local bob = if mode == "Still" then 0 else Loading.Bob(t, metrics.Bob)
		if mode == "Turn" then
			local factor, flip = Loading.TurnPose(t)
			local width = math.round(metrics.Grid * factor)
			if width ~= lastWidth or flip ~= lastFlip then
				lastWidth = width
				lastFlip = flip
				local show = width >= 2 -- edge-on: nothing to draw
				normal.Visible = show and not flip
				if mirrored then
					mirrored.Visible = show and flip
				end
			end
			placeHead(width, bob)
		else
			placeHead(metrics.Grid, bob)
			head.Rotation = if mode == "Wheel" then Loading.WheelAngle(t) else 0
		end
		local n = if type(dots) == "number" then math.clamp(math.floor(dots), 0, MAX_DOTS) else Loading.DotCount(t)
		if n ~= shownDots then
			shownDots = n
			label.Text = Loading.Text(word, n, dotColor)
		end
	end

	-- backdrop 0..1 = how black the screen is; content 0..1 = how visible the head + text are
	function view.Fade(backdropAlpha: number, contentAlpha: number)
		backdrop.BackgroundTransparency = 1 - math.clamp(backdropAlpha, 0, 1)
		local c = if plain then 0 else math.clamp(contentAlpha, 0, 1)
		content.Visible = c > 0
		curtain.Visible = c > 0 and c < 1
		curtain.BackgroundTransparency = c
	end

	function view.Destroy()
		gui:Destroy()
	end

	view.Layout(viewport)
	view.Pose(0, 0)
	return view :: View
end

function Loading.Preview(theme: Theme?, viewport: Vector2, opts: { [string]: any }?): View
	local o = opts or {}
	local view = Loading.Build(theme, { Viewport = viewport, Mode = o.Mode })
	view.Fade(1, 1)
	local spin = if type(o.Spin) == "number" then o.Spin else 0
	local period = if view.Mode == "Wheel" then Loading.WheelPeriod else Loading.TurnPeriod
	view.Pose(spin * period, if type(o.Dots) == "number" then o.Dots else MAX_DOTS)
	return view
end

------------------------------------------------------------------------------------------------ runtime

local active: Handle? = nil

function Loading.Active(): Handle?
	return if active and not active.Done then active else nil
end

local function safeCall(label: string, fn: any, ...: any): (boolean, any)
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(("[Loading] %s failed: %s"):format(label, tostring(result)))
	end
	return ok, result
end

local function runtimeDriver(): Driver
	local RunService = game:GetService("RunService")
	return {
		Connect = function(step: (number) -> ()): () -> ()
			local conn = RunService.Heartbeat:Connect(step)
			return function()
				conn:Disconnect()
			end
		end,
		Delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
	}
end

local function defaultParent(): Instance?
	local ok, gui = pcall(function()
		local player = game:GetService("Players").LocalPlayer
		return if player then player:FindFirstChildOfClass("PlayerGui") else nil
	end)
	return if ok then gui else nil
end

local function reducedMotion(): boolean
	local ok, on = pcall(function()
		return game:GetService("GuiService").ReducedMotionEnabled
	end)
	return ok and on == true
end

function Loading.Show(opts: { [string]: any }?): Handle?
	if active and not active.Done then
		return active
	end
	local o = opts or {}
	local driver: Driver = if type(o.Driver) == "table" then o.Driver else runtimeDriver()
	local parent: Instance? = if typeof(o.Parent) == "Instance" then o.Parent else defaultParent()
	if parent == nil then
		return nil
	end
	local function measure(gui: ScreenGui?): Vector2
		if driver.Viewport then
			return driver.Viewport()
		end
		if gui and gui.AbsoluteSize.X >= 2 and gui.AbsoluteSize.Y >= 2 then
			return gui.AbsoluteSize
		end
		local camera = workspace.CurrentCamera
		return if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	end
	local reduce = if o.ReducedMotion ~= nil then o.ReducedMotion == true else (o.Driver == nil and reducedMotion())
	local mode: SpinMode = if reduce then "Still" else validMode(o.Mode)
	local plain = o.Content == false

	-- everything that can fail happens before the overlay goes live (then the caller falls back cleanly)
	local okBuild, built = pcall(Loading.Build, o.Theme, { Viewport = measure(nil), Mode = mode, Plain = plain })
	if not okBuild then
		warn("[Loading] build failed: " .. tostring(built))
		return nil
	end
	local view: View = built
	-- timing overrides (NewSequence ignores anything that is not a finite number >= 0)
	local seq = Loading.NewSequence({
		MinVisible = o.MinVisible,
		MaxWait = o.MaxWait,
		MusicLead = o.MusicLead,
		Settle = o.Settle,
		FadeIn = o.FadeIn,
		ContentIn = o.ContentIn,
		ContentOut = o.ContentOut,
		FadeOut = o.FadeOut,
	})
	-- with a music cue the caller hands the music over itself (menu track out, lobby track in): no ducking then
	local duckMusic = not (type(o.MusicLead) == "number" and o.MusicLead > 0)
	local cued = false
	local function musicCue()
		if not cued then
			cued = true
			safeCall("OnMusicCue", o.OnMusicCue)
		end
	end
	local timing = seq.Timing
	local handle = {
		Covered = false,
		Done = false,
		Sequence = seq,
		View = view,
	} :: any

	local soundCtl: any = o.Sound
	local voice: any = nil
	local disconnect: (() -> ())? = nil
	local finished = false
	local laidOut = view.Metrics.Viewport
	local sinceDuck = math.huge

	local function cover()
		if not handle.Covered then
			handle.Covered = true
			safeCall("OnCovered", o.OnCovered)
		end
	end

	local function finish()
		if finished then
			return
		end
		finished = true
		handle.Done = true
		if active == handle then
			active = nil
		end
		if disconnect then
			pcall(disconnect)
			disconnect = nil
		end
		cover() -- the caller's switch (close the Title, send the request) happens even if we died early
		musicCue() -- and the music hand-over too
		pcall(view.Destroy)
		if voice ~= nil and soundCtl ~= nil then
			local okPlaying, playing = pcall(function()
				return voice.Playing
			end)
			if okPlaying and playing == true then
				safeCall("Sound.Stop", soundCtl.Stop, voice, Loading.SoundFade)
			end
		end
		safeCall("OnDone", o.OnDone)
	end

	local function step(dt: number)
		if finished then
			return
		end
		local ok, err = pcall(function()
			local ready = false
			if seq.Stage == "Hold" then
				if type(o.Until) == "function" then
					local okUntil, result = pcall(o.Until)
					ready = (not okUntil) or result == true -- a broken condition never keeps the screen black
				else
					ready = true
				end
			end
			local coveredNow, doneNow, cueNow = seq.Step(dt, ready)
			local size = measure(view.Gui)
			if math.abs(size.X - laidOut.X) >= 1 or math.abs(size.Y - laidOut.Y) >= 1 then
				view.Layout(size)
				laidOut = view.Metrics.Viewport
			end
			view.Fade(seq.Backdrop, seq.Content)
			if seq.Content > 0 and seq.CoveredAt then
				view.Pose(seq.Time - seq.CoveredAt)
			end
			if coveredNow then
				cover()
			end
			if cueNow then
				musicCue()
			end
			if duckMusic and soundCtl ~= nil and (seq.Stage == "FadeIn" or seq.Stage == "Hold") then
				sinceDuck += math.max(dt, 0)
				if sinceDuck >= DUCK_EVERY then
					sinceDuck = 0
					safeCall("Sound.Duck", soundCtl.Duck, Loading.DuckAmount, DUCK_EVERY * 2.4, 0.3)
				end
			end
			if doneNow then
				finish()
			end
		end)
		if not ok then
			warn("[Loading] frame failed, closing the loading screen: " .. tostring(err))
			finish()
		end
	end

	function handle.Finish()
		seq.Skip()
	end
	function handle.Destroy()
		finish()
	end

	-- live from here on: nothing below may throw
	active = handle
	view.Fade(0, 0)
	local okParent, parentErr = pcall(function()
		view.Gui.Parent = parent
	end)
	if not okParent then
		warn("[Loading] could not show: " .. tostring(parentErr))
		active = nil
		handle.Done = true
		pcall(view.Destroy)
		return nil
	end
	if soundCtl ~= nil then
		local okPlay, sound = safeCall("Sound.Play", soundCtl.Play, Loading.SoundName)
		if okPlay then
			voice = sound
		end
	end
	local okConnect, conn = pcall(driver.Connect, step)
	if okConnect and type(conn) == "function" then
		disconnect = conn
	else
		warn("[Loading] no frame loop: " .. tostring(conn))
		finish()
		return handle
	end
	-- failsafe in real time: whatever happens to the frame loop (app in the background, a stalled driver) the
	-- overlay is gone a little after the cap
	local schedule = driver.Delay or function(seconds: number, fn: () -> ())
		task.delay(seconds, fn)
	end
	pcall(schedule, timing.MaxWait + timing.ContentOut + timing.FadeOut + Loading.FailsafeMargin, function()
		if not finished then
			warn("[Loading] failsafe: the loading screen was still up, removing it")
			finish()
		end
	end)
	return handle :: Handle
end

return Loading
