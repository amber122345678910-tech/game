--!strict
-- Screens/ShopKeeper: sleepy Sans behind his shop counter, the left column of the Shop screen (owner's request:
-- "zzz... oh hi kid, what you want?"). A theme panel holds a stage with the pixel scene
-- (Shared/PixelArt/SansShopkeeper: snowy booth, blue hoodie, counter with coins + ketchup, the "SHOP" board) and a
-- dialogue box with Sans's line (ComicNeueAngular like his Verdict Box lines, Jura in ru, "* " in Classic).
-- Pixels: every sprite cell is a whole number of SCREEN pixels (ShopKeeper.Fit picks it from the UIRoot scale), cells
-- are placed with Scale fractions of the scene frame (one Frame per merged rect), so the art stays crisp.
--
-- Sequence (ShopKeeper.Timing, seconds): asleep - the head bobs 1 cell, "Z z z" rise and fade, the box shows
-- "Zzz..." - for Sleep 0.8 -> wakes: sprite swap + a 3-cell hop (Hop 0.25) -> Beat 0.15 -> types shop.keeper.greet
-- with SansTextBlip blips -> idle (blinks every BlinkEvery s). Say(key) types another line (thanks / poor); said
-- while he still sleeps it wakes him first. Reduced Motion (GuiService.ReducedMotionEnabled or opts.ReducedMotion):
-- no bob, no hop, the Z letters stand still, no falling snow. Offline (Motion not live) the scene shows the settled
-- end state (awake, whole greeting) unless opts.At poses a moment of the sequence.
--
-- API
--   ShopKeeper.Plan(bodyW, bodyH, scale, phone, gap) -> Plan?   column for a Shop body (design px): the largest whole
--       screen-pixel cell that fits while the goods keep MinGoods px; nil = no room (portrait / tiny window).
--       Plan = Fit + { Width (column, design px), Height }
--   ShopKeeper.Create(theme, opts) -> Keeper?   nil when opts.Size cannot hold the scene
--       opts: { Size: Vector2 (design px), Scale: number (UIRoot layout scale), Phone: boolean?, Deps: any?
--               (Deps.Sound.Play plays the blips; else Motion.Sound), At: number? (pose this moment, offline),
--               ReducedMotion: boolean?, Name: string? }
--   Keeper: { Root: Frame, Stage: Frame, Scene: Frame, Box: Frame, Text: TextLabel, Sign: TextLabel?, Fit: Fit,
--             Timeline: Timeline, Step(dt) (advance the clock: pose + blips), Pose(t) (pose only, no sound),
--             Settle() (end state), Say(key, ...), Time() -> number, State() -> string, Line() -> string,
--             Blips() -> number (blips played), Destroy() }
-- Pure (tests / previews)
--   ShopKeeper.Timing                         Sleep, Hop, HopHeight, Beat, Interval, Pause, Comma, BobPeriod, ZEvery,
--                                             ZLife, ZPreroll, BlinkEvery, BlinkTime, BlipEvery, SnowSpeed
--   ShopKeeper.Fit(innerW, innerH, scale, phone, maxW?) -> Fit?
--       Fit = { Pixel (screen px per cell), Unit (design px per cell), Covered (the box covers the counter front),
--               InnerW, InnerH, BoxH, StageH, SceneW, SceneH, SceneX, SceneTop, Pad, Gap }
--   ShopKeeper.Schedule(text, timing?) -> (times, graphemes)   reveal time of each grapheme after the line starts
--   ShopKeeper.Shown(times, dt) -> number     graphemes visible dt s after the line started
--   ShopKeeper.NewTimeline(greet, zzz, timing?) -> Timeline { WakeAt, LineAt, Line, Prev, Say(text, now),
--       PoseAt(t, reduced?, noBlink?) -> Pose, EndAt() -> number }
--   Pose = { State ("Asleep"|"Waking"|"Talking"|"Idle"), Head ("Awake"|"Asleep"), HeadY (cells), Z = {ZPose},
--            Text, Shown (graphemes, -1 = all), Dim (the "Zzz..." placeholder) }
--   ZPose = { Glyph ("Small"|"Medium"|"Big"), X, Y (cells), Transparency }

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Motion = require(script.Parent.Parent.Motion)
local Common = require(script.Parent.Common)

type Theme = Themes.Theme

export type Fit = {
	Pixel: number,
	Unit: number,
	Covered: boolean,
	InnerW: number,
	InnerH: number,
	BoxH: number,
	StageH: number,
	SceneW: number,
	SceneH: number,
	SceneX: number,
	SceneTop: number,
	Pad: number,
	Gap: number,
}

export type ZPose = { Glyph: string, X: number, Y: number, Transparency: number }

export type Pose = {
	State: string,
	Head: string,
	HeadY: number,
	Z: { ZPose },
	Text: string,
	Shown: number,
	Dim: boolean,
}

local ShopKeeper = {}

ShopKeeper.Timing = {
	Sleep = 0.8, -- s asleep before he notices you
	Hop = 0.25, -- s: the wake-up hop
	HopHeight = 3, -- cells above the straight path at the top of the hop
	Beat = 0.15, -- s between landing and the first letter
	Interval = 0.045, -- s per letter
	Pause = 0.24, -- s after . ! ? (once per run of them)
	Comma = 0.12, -- s after , ; :
	BobPeriod = 1.2, -- s per sleepy head bob (down 1 cell and back)
	ZEvery = 0.5, -- s between two rising Z letters
	ZLife = 1.5, -- s a Z letter floats
	ZPreroll = 1.0, -- s of Z stream already running when the shop opens (letters in flight at once)
	BlinkEvery = 3.2, -- s between idle blinks
	BlinkTime = 0.14, -- s eyes closed per blink
	BlipEvery = 2, -- a SansTextBlip every n-th voiced letter
	SnowSpeed = 5, -- cells per second
}

ShopKeeper.BlipSound = "SansTextBlip"
ShopKeeper.MaxPixel = 12
ShopKeeper.MinGoods = { Phone = 640, Desktop = 1080 } -- design px the goods (daily + all skins) keep beside the column
ShopKeeper.MinBox = { Phone = 84, Desktop = 150 }
ShopKeeper.MaxBox = { Phone = 150, Desktop = 210 }
ShopKeeper.Pad = { Phone = 8, Desktop = 12 }
ShopKeeper.Gap = { Phone = 6, Desktop = 10 }
ShopKeeper.TextSize = { Phone = 16, Desktop = 22 }

local SNOWFLAKES = 9
local SIGN_COLOR = Color3.fromRGB(74, 40, 18)
local PAUSE: { [string]: boolean } = { ["."] = true, ["!"] = true, ["?"] = true, ["…"] = true }
local COMMA: { [string]: boolean } = { [","] = true, [";"] = true, [":"] = true }
local SILENT: { [string]: boolean } = { [" "] = true, ["."] = true, [","] = true, ["!"] = true, ["?"] = true, ["…"] = true, [";"] = true, [":"] = true, ["-"] = true, ["*"] = true }

local spriteModule: any = nil
local function Sprite(): any
	if spriteModule == nil then
		spriteModule = Common.Module({ "PixelArt", "SansShopkeeper" }) or false
	end
	return if spriteModule then spriteModule else nil
end

local function timingOf(over: { [string]: any }?): { [string]: number }
	local t = table.clone(ShopKeeper.Timing) :: any
	if over then
		for key in ShopKeeper.Timing do
			local v = over[key]
			if type(v) == "number" and v == v and v >= 0 and v < math.huge then
				t[key] = v
			end
		end
	end
	return t
end

------------------------------------------------------------------------------------------------ layout (pure)

local function device(phone: boolean?): string
	return if phone then "Phone" else "Desktop"
end

function ShopKeeper.Fit(innerW: number, innerH: number, scale: number, phone: boolean?, maxW: number?): Fit?
	local sprite = Sprite()
	if sprite == nil or type(scale) ~= "number" or scale <= 0 then
		return nil
	end
	local dev = device(phone)
	local W, H = sprite.Width, sprite.Height
	local frontY = sprite.CounterFrontY
	local minBox, maxBox, gap = ShopKeeper.MinBox[dev], ShopKeeper.MaxBox[dev], ShopKeeper.Gap[dev]
	local widthCap = math.min(innerW, maxW or innerW)
	for p = ShopKeeper.MaxPixel, 1, -1 do
		local u = p / scale
		local sw, sh = W * u, H * u
		if sw <= widthCap + 1e-6 and sh <= innerH + 1e-6 then
			local fit: Fit? = nil
			if sh + gap + minBox <= innerH + 1e-6 then
				-- the box below the scene (the counter-front board stays visible); spare height becomes sky
				local boxH = math.floor(math.clamp(innerH - sh - gap, minBox, maxBox))
				local stageH = innerH - gap - boxH
				fit = {
					Pixel = p,
					Unit = u,
					Covered = false,
					InnerW = innerW,
					InnerH = innerH,
					BoxH = boxH,
					StageH = stageH,
					SceneW = sw,
					SceneH = sh,
					SceneX = (innerW - sw) / 2,
					SceneTop = stageH - sh,
					Pad = ShopKeeper.Pad[dev],
					Gap = gap,
				}
			elseif innerH - frontY * u >= minBox - 1e-6 then
				-- short phones: the box stands in front of the counter (it covers the counter-front planks)
				local boxH = math.floor(math.clamp(innerH - frontY * u, minBox, maxBox))
				fit = {
					Pixel = p,
					Unit = u,
					Covered = true,
					InnerW = innerW,
					InnerH = innerH,
					BoxH = boxH,
					StageH = innerH,
					SceneW = sw,
					SceneH = sh,
					SceneX = (innerW - sw) / 2,
					SceneTop = innerH - boxH - frontY * u,
					Pad = ShopKeeper.Pad[dev],
					Gap = gap,
				}
			end
			if fit then
				return fit
			end
		end
	end
	return nil
end

function ShopKeeper.Plan(bodyW: number, bodyH: number, scale: number, phone: boolean?, gap: number?): any
	local dev = device(phone)
	local pad = ShopKeeper.Pad[dev]
	local maxInnerW = bodyW - (gap or 0) - ShopKeeper.MinGoods[dev] - pad * 2
	if maxInnerW <= 0 then
		return nil
	end
	local innerH = math.floor(bodyH) - pad * 2
	local fit = ShopKeeper.Fit(maxInnerW, innerH, scale, phone)
	if fit == nil then
		return nil
	end
	local width = math.ceil(fit.SceneW - 1e-6) + pad * 2
	local plan = ShopKeeper.Fit(width - pad * 2, innerH, scale, phone) :: any
	if plan == nil then
		return nil
	end
	plan.Width = width
	plan.Height = math.floor(bodyH)
	return plan
end

------------------------------------------------------------------------------------------------ text timing (pure)

function ShopKeeper.Schedule(text: string, timing: { [string]: any }?): ({ number }, { string })
	local cfg = timingOf(timing)
	local graphemes: { string } = {}
	local ok = pcall(function()
		for _, cp in utf8.codes(text) do
			table.insert(graphemes, utf8.char(cp))
		end
	end)
	if not ok then
		graphemes = {}
		for i = 1, #text do
			graphemes[i] = string.sub(text, i, i)
		end
	end
	local times = table.create(#graphemes)
	local t = 0
	for i, g in graphemes do
		times[i] = t
		local nextG = graphemes[i + 1]
		if PAUSE[g] and not (nextG and PAUSE[nextG]) then
			t += cfg.Pause
		elseif COMMA[g] then
			t += cfg.Comma
		else
			t += cfg.Interval
		end
	end
	return times, graphemes
end

function ShopKeeper.Shown(times: { number }, dt: number): number
	if dt < 0 then
		return 0
	end
	local lo, hi = 0, #times
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if times[mid] <= dt + 1e-9 then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo
end

------------------------------------------------------------------------------------------------ timeline (pure)

local function zPoses(t: number, cfg: { [string]: number }, reduced: boolean): { ZPose }
	local sprite = Sprite()
	local out: { ZPose } = {}
	if sprite == nil then
		return out
	end
	local a, b = sprite.ZStart, sprite.ZEnd
	local function at(f: number, transparency: number): ZPose
		local glyph = if f < 0.34 then "Small" elseif f < 0.67 then "Medium" else "Big"
		local sway = if reduced then 0 else math.round(math.sin(f * math.pi * 2) * 1)
		return {
			Glyph = glyph,
			X = math.round(a.x + (b.x - a.x) * f) + sway,
			Y = math.round(a.y + (b.y - a.y) * f),
			Transparency = transparency,
		}
	end
	if reduced then
		-- standing letters: z Z Z up the path
		for _, f in { 0.12, 0.5, 0.88 } do
			table.insert(out, at(f, 0.1))
		end
		return out
	end
	local life, every = math.max(cfg.ZLife, 1e-3), math.max(cfg.ZEvery, 1e-3)
	local clock = t + cfg.ZPreroll
	local newest = math.floor(clock / every)
	for n = newest, newest - math.ceil(life / every), -1 do
		local age = clock - n * every
		if n >= 0 and age >= 0 and age < life then
			local f = age / life
			local fadeIn = math.clamp(f / 0.15, 0, 1)
			local fadeOut = math.clamp((1 - f) / 0.35, 0, 1)
			local alpha = math.min(fadeIn, fadeOut)
			table.insert(out, at(f, 1 - alpha * 0.95))
		end
	end
	return out
end

function ShopKeeper.NewTimeline(greet: string, zzz: string, timing: { [string]: any }?): any
	local cfg = timingOf(timing)
	local times, graphemes = ShopKeeper.Schedule(greet, cfg)
	local tl = {
		Timing = cfg,
		WakeAt = cfg.Sleep,
		LineAt = cfg.Sleep + cfg.Hop + cfg.Beat,
		Line = greet,
		Prev = zzz,
		PrevDim = true,
		Times = times,
		Graphemes = graphemes,
	}

	function tl.EndAt(): number
		local n = #tl.Times
		return tl.LineAt + (if n > 0 then tl.Times[n] else 0)
	end

	function tl.Say(text: string, now: number)
		if now < tl.WakeAt then
			tl.WakeAt = now
		end
		-- what the box shows until the new line starts: the old line as far as it got
		if now >= tl.LineAt then
			tl.Prev = tl.Line
			tl.PrevDim = false
		end
		tl.Line = text
		tl.LineAt = math.max(now, tl.WakeAt + cfg.Hop + cfg.Beat)
		tl.Times, tl.Graphemes = ShopKeeper.Schedule(text, cfg)
	end

	function tl.PoseAt(t: number, reduced: boolean?, noBlink: boolean?): Pose
		local sprite = Sprite()
		local awakeY = if sprite then sprite.HeadAwakeY else 8
		local asleepY = if sprite then sprite.HeadAsleepY else 10
		local calm = reduced == true
		local pose: Pose = {
			State = "Idle",
			Head = "Awake",
			HeadY = awakeY,
			Z = {},
			Text = tl.Line,
			Shown = -1,
			Dim = false,
		}
		if t < tl.WakeAt then
			pose.State = "Asleep"
			pose.Head = "Asleep"
			local bob = if calm then 0 else math.round((1 - math.cos(2 * math.pi * t / math.max(cfg.BobPeriod, 1e-3))) / 2)
			pose.HeadY = asleepY + bob
			pose.Z = zPoses(t, cfg, calm)
		elseif t < tl.WakeAt + cfg.Hop then
			pose.State = "Waking"
			if not calm then
				local u = (t - tl.WakeAt) / math.max(cfg.Hop, 1e-3)
				pose.HeadY = math.round(asleepY + (awakeY - asleepY) * u - cfg.HopHeight * 4 * u * (1 - u))
			end
		else
			pose.State = if t < tl.EndAt() then "Talking" else "Idle"
			if not noBlink then
				local every = math.max(cfg.BlinkEvery, 1e-3)
				local since = t - (tl.WakeAt + cfg.Hop)
				if since % every >= every - cfg.BlinkTime then
					pose.Head = "Asleep" -- a blink: both eyes closed for a moment
				end
			end
		end
		if t < tl.LineAt then
			pose.Text = tl.Prev
			pose.Dim = tl.PrevDim
		else
			local shown = ShopKeeper.Shown(tl.Times, t - tl.LineAt)
			pose.Shown = if shown >= #tl.Times then -1 else shown
		end
		return pose
	end

	return tl
end

------------------------------------------------------------------------------------------------ builder

local function newFrame(name: string, color: Color3?, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or Color3.new(0, 0, 0)
	f.BackgroundTransparency = if color then 0 else 1
	f.ZIndex = z
	return f
end

-- every merged rect of `rows` as a Frame inside `parent` (a frame exactly cols x rowsN cells big)
local function paint(parent: Frame, rows: { string }, cols: number, rowsN: number, ox: number, oy: number, z: number, out: { Frame }?)
	local sprite = Sprite()
	for i, r in sprite.Rects(rows) do
		local f = newFrame(r.color .. i, sprite.Colors[r.color], z)
		f.Position = UDim2.fromScale((r.x + ox) / cols, (r.y + oy) / rowsN)
		f.Size = UDim2.fromScale(r.w / cols, r.h / rowsN)
		f.Parent = parent
		if out then
			table.insert(out, f)
		end
	end
end

local function speechFont(): Font
	local lang = Common.Strings() and Common.Strings().Language() or "en"
	local family = if lang == "ru" then "Jura" else "ComicNeueAngular"
	return Font.new("rbxasset://fonts/families/" .. family .. ".json", Enum.FontWeight.Bold)
end

local function reducedMotion(): boolean
	if not Motion.IsLive() then
		return false
	end
	local ok, value = pcall(function()
		return (game:GetService("GuiService") :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

function ShopKeeper.Create(theme: Theme, opts: { [string]: any }): any
	local sprite = Sprite()
	if sprite == nil then
		return nil
	end
	local c = theme.Colors
	local phone = opts.Phone == true
	local dev = device(phone)
	local size: Vector2 = opts.Size
	local pad = ShopKeeper.Pad[dev]
	local innerW, innerH = math.floor(size.X) - pad * 2, math.floor(size.Y) - pad * 2
	local fit = ShopKeeper.Fit(innerW, innerH, opts.Scale or 1, phone)
	if fit == nil then
		return nil
	end
	local W, H = sprite.Width, sprite.Height
	local u = fit.Unit
	local reduced = if opts.ReducedMotion ~= nil then opts.ReducedMotion == true else reducedMotion()
	local deps = opts.Deps

	local panel = UIKit.Panel(theme, {
		Name = opts.Name or "Keeper",
		Size = UDim2.fromOffset(math.floor(size.X), math.floor(size.Y)),
		Padding = pad,
	})
	local root = panel.Root
	local content = panel.Content

	-- stage: the scene + the sky above it (clipped)
	local stage = newFrame("Stage", c.PanelInset, 1)
	stage.Size = UDim2.fromOffset(innerW, math.floor(fit.StageH))
	stage.ClipsDescendants = true
	if theme.Id ~= "Classic" then
		Common.Gradient(stage, ColorSequence.new(c.PanelInset:Lerp(c.Accent, 0.12), c.PanelInset), nil, 90)
	end
	Common.Corner(stage, if theme.Id == "Void" then UDim.new(0, 8) elseif theme.Id == "Royal" then UDim.new(0, 4) else UDim.new(0, 0))
	stage.Parent = content
	local stageW, stageH = innerW, math.floor(fit.StageH)

	local scene = newFrame("Scene", nil, 2)
	scene.Size = UDim2.fromScale(fit.SceneW / stageW, fit.SceneH / stageH)
	scene.Position = UDim2.fromScale(fit.SceneX / stageW, fit.SceneTop / stageH)
	scene.Parent = stage

	-- falling snow in the sky above the roof (only where there is sky)
	local flakes: { Frame } = {}
	local skyCells = math.floor(fit.SceneTop / u)
	if skyCells >= 6 then
		for i = 1, SNOWFLAKES do
			local flake = newFrame("Snow" .. i, sprite.Colors.s, 1)
			flake.BackgroundTransparency = 0.25 + (i % 3) * 0.2
			flake.Size = UDim2.fromScale(u / stageW, u / stageH)
			flake.Parent = stage
			table.insert(flakes, flake)
		end
	end

	local layers: { [string]: Frame } = {}
	local z = 1
	local head: Frame = newFrame("Head", nil, 1)
	local eyesAwake = newFrame("EyesAwake", nil, 2)
	local eyesAsleep = newFrame("EyesAsleep", nil, 2)
	for _, name in sprite.Order do
		z += 1
		if name == "Head" then
			local parts = sprite.HeadParts()
			head.ZIndex = z
			head.Size = UDim2.fromScale(40 / W, 37 / H)
			paint(head, parts.Base, 40, 37, 0, 0, 1)
			for _, pair in { { eyesAwake, parts.Awake }, { eyesAsleep, parts.Asleep } } do
				local holder = pair[1] :: Frame
				holder.Size = UDim2.fromScale(1, 1)
				paint(holder, pair[2] :: { string }, 40, 37, 0, 0, 1)
				holder.Parent = head
			end
			head.Parent = scene
		else
			local layer = sprite.Layers[name]
			local holder = newFrame(name, nil, z)
			holder.Size = UDim2.fromScale(1, 1)
			paint(holder, layer.Rows, W, H, layer.X, layer.Y, 1)
			holder.Parent = scene
			layers[name] = holder
		end
	end

	-- the counter-front board label ("SHOP" / "МАГАЗИН") in the pixel font; hidden behind the box when covered
	local sign: TextLabel? = nil
	if not fit.Covered then
		local s = sprite.Sign
		local lang = Common.Strings() and Common.Strings().Language() or "en"
		local label = Instance.new("TextLabel")
		label.Name = "Sign"
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.ZIndex = z + 1
		label.Position = UDim2.fromScale(s.X / W, (s.Y + 0.5) / H)
		label.Size = UDim2.fromScale(s.W / W, (s.H - 1) / H)
		label.FontFace = Themes.Font(Themes.Get("Classic"), "Display", lang)
		label.Text = UIKit.Upper(Common.L("scr.shop.title"))
		label.TextColor3 = SIGN_COLOR
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = math.max(8, math.floor((s.H - 2) * u))
		limit.MinTextSize = 6
		limit.Parent = label
		label.Parent = scene
		sign = label
	end

	-- floating Z letters: three slots, each with the three glyph sizes (one shown at a time)
	type ZSlot = { Root: Frame, Glyphs: { [string]: Frame }, Cells: { [string]: { Frame } } }
	local zSlots: { ZSlot } = {}
	for i = 1, 3 do
		local slot = newFrame("Z" .. i, nil, z + 2)
		slot.Size = UDim2.fromScale(5 / W, 5 / H)
		slot.Visible = false
		local glyphs, cells = {}, {}
		for glyphName, rows in sprite.Z do
			local holder = newFrame(glyphName, nil, 1)
			holder.Size = UDim2.fromScale(1, 1)
			holder.Visible = false
			local list = {}
			paint(holder, rows, 5, 5, 0, 5 - #rows, 1, list)
			holder.Parent = slot
			glyphs[glyphName] = holder
			cells[glyphName] = list
		end
		slot.Parent = scene
		zSlots[i] = { Root = slot, Glyphs = glyphs, Cells = cells }
	end

	-- dialogue box
	local box = newFrame("Dialogue", c.PanelInset, 5)
	box.Position = UDim2.fromOffset(0, innerH - fit.BoxH)
	box.Size = UDim2.fromOffset(innerW, fit.BoxH)
	Common.Corner(box, if theme.Id == "Void" then UDim.new(0, 10) elseif theme.Id == "Royal" then UDim.new(0, 6) else theme.SmallCorner)
	local stroke = Common.Stroke(box, c.Stroke, if theme.Id == "Classic" then 3 else 2, 0, theme.LineJoin)
	if theme.Gradients.Stroke then
		Common.Gradient(stroke, theme.Gradients.Stroke, nil, 45)
	end
	local textPad = if phone then 10 else 16
	local text = Instance.new("TextLabel")
	text.Name = "Line"
	text.BackgroundTransparency = 1
	text.BorderSizePixel = 0
	text.ZIndex = 2
	text.Position = UDim2.fromOffset(textPad, if phone then 8 else 14)
	text.Size = UDim2.new(1, -textPad * 2, 1, -(if phone then 14 else 24))
	text.FontFace = speechFont()
	text.TextSize = ShopKeeper.TextSize[dev]
	text.TextColor3 = c.Text
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.LineHeight = 1.1
	text.Text = ""
	text.Parent = box
	box.Parent = content

	local prefix = theme.DialoguePrefix or ""
	local prefixLen = utf8.len(prefix) or #prefix

	-- applying a pose (only touches what changed) ---------------------------------------------------
	local timeline = ShopKeeper.NewTimeline(Common.L("shop.keeper.greet"), Common.L("shop.keeper.zzz"))
	local clock = 0
	local blips = 0
	local lastShown = -2
	local lastText: string? = nil
	local lastHead: string? = nil
	local lastHeadY: number? = nil
	local lastDim: boolean? = nil
	local lastSnow = -1

	local function applySnow(t: number)
		if #flakes == 0 then
			return
		end
		local tick = if reduced then 0 else math.floor(t * ShopKeeper.Timing.SnowSpeed)
		if tick == lastSnow then
			return
		end
		lastSnow = tick
		local skyTop = 0
		local skyBottom = math.max(skyCells + 2, 1) -- flakes vanish behind the snowy roof
		local span = skyBottom - skyTop
		local cols = math.floor(stageW / u)
		for i, flake in flakes do
			local col = (i * 37 + 11) % math.max(cols, 1)
			local fall = (tick + i * 7) % span
			local sway = if reduced then 0 else math.round(math.sin((tick + i * 3) * 0.5))
			flake.Position = UDim2.fromScale(((col + sway) * u) / stageW, ((skyTop + fall) * u) / stageH)
		end
	end

	local function apply(pose: Pose)
		if pose.Head ~= lastHead then
			lastHead = pose.Head
			eyesAwake.Visible = pose.Head == "Awake"
			eyesAsleep.Visible = pose.Head ~= "Awake"
		end
		if pose.HeadY ~= lastHeadY then
			lastHeadY = pose.HeadY
			head.Position = UDim2.fromScale(sprite.HeadX / W, pose.HeadY / H)
		end
		for i, slot in zSlots do
			local zp = pose.Z[i]
			slot.Root.Visible = zp ~= nil
			if zp then
				slot.Root.Position = UDim2.fromScale(zp.X / W, zp.Y / H)
				for glyphName, holder in slot.Glyphs do
					local on = glyphName == zp.Glyph
					holder.Visible = on
					if on then
						for _, cellFrame in slot.Cells[glyphName] do
							cellFrame.BackgroundTransparency = zp.Transparency
						end
					end
				end
			end
		end
		if pose.Text ~= lastText then
			lastText = pose.Text
			text.Text = prefix .. pose.Text
			lastShown = -2
		end
		if pose.Dim ~= lastDim then
			lastDim = pose.Dim
			text.TextColor3 = if pose.Dim then c.TextDim else c.Text
		end
		if pose.Shown ~= lastShown then
			lastShown = pose.Shown
			text.MaxVisibleGraphemes = if pose.Shown < 0 then -1 else prefixLen + pose.Shown
		end
	end

	local keeper: any = {
		Root = root,
		Stage = stage,
		Scene = scene,
		Box = box,
		Text = text,
		Sign = sign,
		Fit = fit,
		Timeline = timeline,
		Layers = layers,
		Head = head,
	}

	function keeper.Pose(t: number)
		apply(timeline.PoseAt(t, reduced))
		applySnow(t)
	end

	function keeper.Settle()
		clock = math.max(clock, timeline.EndAt() + 0.5)
		apply(timeline.PoseAt(clock, reduced, true))
		applySnow(clock)
	end

	local function blip()
		blips += 1
		local sound = deps and deps.Sound
		if sound and type(sound.Play) == "function" then
			pcall(sound.Play, ShopKeeper.BlipSound)
		else
			Motion.Sound(ShopKeeper.BlipSound)
		end
	end

	function keeper.Step(dt: number)
		local d = if type(dt) == "number" and dt == dt then math.clamp(dt, 0, 0.25) else 0
		local before = if clock >= timeline.LineAt then ShopKeeper.Shown(timeline.Times, clock - timeline.LineAt) else 0
		clock += d
		local pose = timeline.PoseAt(clock, reduced)
		if clock >= timeline.LineAt then
			local now = ShopKeeper.Shown(timeline.Times, clock - timeline.LineAt)
			-- one blip per step at most (MinInterval drops the rest anyway)
			for i = before + 1, now do
				local g = timeline.Graphemes[i]
				if g and not SILENT[g] and (i % ShopKeeper.Timing.BlipEvery == 1 or ShopKeeper.Timing.BlipEvery <= 1) then
					blip()
					break
				end
			end
		end
		apply(pose)
		applySnow(clock)
	end

	function keeper.Say(key: string, ...: any)
		timeline.Say(Common.L(key, ...), clock)
		if not Motion.IsLive() then
			keeper.Settle()
		else
			apply(timeline.PoseAt(clock, reduced))
		end
	end

	function keeper.Time(): number
		return clock
	end

	function keeper.State(): string
		return timeline.PoseAt(clock, reduced).State
	end

	function keeper.Line(): string
		return timeline.Line
	end

	function keeper.Blips(): number
		return blips
	end

	local stopLoop: (() -> ())? = nil
	function keeper.Destroy()
		if stopLoop then
			stopLoop()
			stopLoop = nil
		end
		panel.Destroy()
	end

	if type(opts.At) == "number" then
		clock = math.max(opts.At, 0)
		keeper.Pose(clock)
	elseif Motion.IsLive() then
		keeper.Pose(0)
		stopLoop = Motion.Loop(root, function(dt: number)
			keeper.Step(dt)
		end)
	else
		keeper.Settle()
	end
	return keeper
end

return ShopKeeper
