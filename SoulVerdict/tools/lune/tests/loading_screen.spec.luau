--!nocheck
-- PLAY / PRACTICE loading screen: the owner's pixel Sans head data (Shared/PixelArt/SansHead: 37 rows x 40 cells of
-- '#', '.', ' ', cell counts pinned, run merging and the layered seam-proof runs reproduce the sprite exactly, the
-- mirrored variant), the overlay (Client/UI/Overlays/Loading) built offline in Turn / Wheel / Still at phone and
-- desktop sizes (own full-screen ScreenGui above every layer, pixel-exact sprite at rest, text inside the screen,
-- ru "ЗАГРУЗКА" in the pixel font), the coin-turn / wheel poses and the dot animation, the pure sequence (minimum
-- time, Until + settle, practice cap, skip, hitches) and the runtime driver with a fake frame loop / sound /
-- scheduler (OnCovered and OnDone exactly once, no stacking, sound + ducking, errors and the failsafe never leave
-- the black screen up). Also the Strings key, the Audio entry and the UIController fallback path.
-- UIController flows (controllerRig: UIController._Harness + the real overlay on the fake loop, fake UIRoot / Sound /
-- State, test clock): the music override never stays "Silence" (overlay missing / throwing / dead loop / already
-- running), the owner's first PLAY timings (Menu out, lobby track 2 s before the light at 4 s, waits for a spawning
-- character), later PLAYs = a ~0.6 s plain dip with a Menu -> lobby crossfade, PRACTICE revealed 0.3 s after the
-- round's Intro starts (>= 2.5 s of the 4 s Intro visible), a refusal ends the black at once (re-toast only after a
-- late reveal), no loading screen while a round runs; the music lead never delays the reveal; the plain dip view.
local LOADING = "src/client/UI/Overlays/Loading"
local SANS = "src/shared/PixelArt/SansHead"
local DT = 1 / 60

-- client-side suite: put the loader flags back even when a test fails (test hygiene)
local function restoringFlags(tests)
	for name, fn in tests do
		tests[name] = function(T, Loader)
			local isServer, quiet, onWarn = Loader.isServer, Loader.quietWarnings, Loader.onWarn
			local ok, err = pcall(fn, T, Loader)
			Loader.isServer, Loader.quietWarnings, Loader.onWarn = isServer, quiet, onWarn
			if not ok then
				error(err, 0)
			end
		end
	end
	return tests
end

local function setup(Loader, lang)
	Loader.isServer = false
	Loader.quietWarnings = true
	local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
	Strings.SetLanguage(lang or "en")
	local Themes = Loader.requirePath("src/client/UI/Themes")
	local Loading = Loader.requirePath(LOADING)
	return Loading, Themes, Strings, Loader.roblox
end

-- paints runs into a Height x Width grid of ' ' and returns the rows (nil + message on overlap when `exclusive`)
local function paint(runs, width, height, exclusive)
	local grid = {}
	for y = 1, height do
		grid[y] = table.create(width, " ")
	end
	for _, r in runs do
		for x = r.x + 1, r.x + r.length do
			local row = grid[r.y + 1]
			if row == nil or x < 1 or x > width then
				return nil, ("run out of bounds at %d,%d"):format(r.x, r.y)
			end
			if exclusive and row[x] ~= " " then
				return nil, ("cell %d,%d painted twice"):format(x - 1, r.y)
			end
			row[x] = r.color
		end
	end
	local out = {}
	for y = 1, height do
		out[y] = table.concat(grid[y])
	end
	return out
end

local function sameRows(T, a, b, msg)
	T.eq(#a, #b, msg .. ": row count")
	local bad = 0
	for i = 1, math.min(#a, #b) do
		if a[i] ~= b[i] then
			bad += 1
		end
	end
	T.eq(bad, 0, msg .. ": rows that differ")
end

-- the sprite of a built sprite holder, read back from the cell Frames at a resting head (container = Grid square)
local function readSprite(T, holder, metrics, Loading, label)
	local p, grid = metrics.Pixel, metrics.Grid
	local left, top = metrics.Left, metrics.Top
	local spriteLeft, spriteTop = metrics.CenterX - 20 * p, metrics.HeadTop
	local white, black = {}, {}
	local fractional = 0
	for _, cell in holder:GetChildren() do
		local ax = left + cell.Position.X.Scale * grid + cell.Position.X.Offset
		local ay = top + cell.Position.Y.Scale * grid + cell.Position.Y.Offset
		local w = cell.Size.X.Scale * grid + cell.Size.X.Offset
		local h = cell.Size.Y.Scale * grid + cell.Size.Y.Offset
		for _, v in { ax, ay, w, h } do
			if v ~= math.floor(v) then
				fractional += 1
			end
		end
		local run = {
			x = (ax - spriteLeft) / p,
			y = (ay - spriteTop) / p,
			length = w / p,
			color = if cell.BackgroundColor3.R > 0.5 then "." else "#",
		}
		if
			h ~= p
			or run.x ~= math.floor(run.x)
			or run.length ~= math.floor(run.length)
			or run.y ~= math.floor(run.y)
		then
			fractional += 1
		end
		table.insert(if cell.ZIndex <= 1 then white else black, run)
	end
	T.eq(fractional, 0, label .. ": every cell sits on whole screen pixels / whole sprite pixels at rest")
	local all = table.clone(white)
	for _, r in black do
		table.insert(all, r)
	end
	return paint(all, 40, 37, false)
end

local function fakeDriver(Loader, w, h)
	local d = { size = Loader.roblox.Vector2.new(w, h), delays = {}, connects = 0 }
	d.Connect = function(step)
		d.connects += 1
		d.step = step
		return function()
			d.step = nil
		end
	end
	d.Viewport = function()
		return d.size
	end
	d.Delay = function(seconds, fn)
		table.insert(d.delays, { t = seconds, fn = fn })
	end
	-- steps the frame loop for `seconds` (or until it disconnects); returns the time stepped
	function d.run(seconds, dt)
		local elapsed = 0
		dt = dt or DT
		while d.step and elapsed < seconds - 1e-9 do
			d.step(dt)
			elapsed += dt
		end
		return elapsed
	end
	return d
end

local function fakeSound(playing)
	local s = { plays = {}, stops = {}, ducks = {}, voice = { Playing = playing } }
	s.Play = function(name)
		table.insert(s.plays, name)
		return s.voice
	end
	s.Stop = function(voice, fade)
		table.insert(s.stops, { voice = voice, fade = fade })
	end
	s.Duck = function(amount, duration, fade)
		table.insert(s.ducks, { amount, duration, fade })
	end
	return s
end

local function guisUnder(parent)
	local n = 0
	for _, c in parent:GetChildren() do
		if c.Name == "SV_Loading" then
			n += 1
		end
	end
	return n
end

-- UIController's PLAY / PRACTICE / menu music driven offline (UIController._Harness): the real overlay on a fake
-- frame loop, a fake UIRoot (screen stack + toasts), a fake SoundController that logs SetMusicOverride, a fake
-- StateController (phase, role, local character, requests, Notify) and a test clock. Every rig loads a fresh module
-- set (Loader.reset); rig.done() puts the shared mocks back (UIController.sync touches GuiService).
local function syncSignal()
	local s = { handlers = {} }
	function s:Connect(fn)
		local c = { Connected = true }
		s.handlers[c] = fn
		function c:Disconnect()
			c.Connected = false
			s.handlers[c] = nil
		end
		return c
	end
	function s:Fire(...)
		for _, fn in table.clone(s.handlers) do
			fn(...)
		end
	end
	function s:Count()
		local n = 0
		for _ in s.handlers do
			n += 1
		end
		return n
	end
	return s
end

local function controllerRig(Loader, opts)
	opts = opts or {}
	local snapshot = Loader.captureState()
	Loader.reset()
	local Loading, _, Strings, roblox = setup(Loader)
	local UIController = Loader.requirePath("src/client/Controllers/UIController")
	local rig = { now = 0, Loading = Loading, UI = UIController, Strings = Strings, roblox = roblox, warnings = {} }
	Loader.onWarn = function(...)
		table.insert(rig.warnings, table.concat({ ... }, " "))
	end
	rig.parent = roblox.Instance.new("Folder")
	rig.driver = opts.Driver or fakeDriver(Loader, 860, 400)
	rig.sound = fakeSound(true)
	rig.sound.overrides = {}
	rig.sound.SetMusicOverride = function(key, fade)
		table.insert(rig.sound.overrides, { key = key, fade = fade, at = rig.now })
		rig.sound.override = key
	end
	local state = { phase = "Waiting", role = "Lobby", requests = {}, Notify = syncSignal() }
	state.Phase = function()
		return state.phase
	end
	state.Role = function()
		return state.role
	end
	state.Request = function(action, data)
		table.insert(state.requests, { action = action, data = data, at = rig.now })
	end
	state.LocalCharacter = function()
		return state.character
	end
	rig.state = state
	local root = { screens = {}, toasts = {}, clears = 0 }
	root.IsInitialized = function()
		return true
	end
	root.Push = function(module)
		local handle = { Root = { Visible = true }, Module = module }
		table.insert(root.screens, handle)
		return handle
	end
	root.Pop = function()
		table.remove(root.screens)
		return true
	end
	root.Replace = function(module)
		table.remove(root.screens)
		return root.Push(module)
	end
	root.Clear = function()
		table.clear(root.screens)
		root.clears += 1
	end
	root.Top = function()
		return root.screens[#root.screens]
	end
	root.Toast = function(text, kind)
		table.insert(root.toasts, { text = text, kind = kind, at = rig.now })
	end
	rig.root = root
	local showOpts = { Driver = rig.driver, Parent = if opts.NoParent then nil else rig.parent }
	UIController._Harness({
		UIRoot = root,
		Sound = rig.sound,
		State = state,
		ShowOpts = showOpts,
		Clock = function()
			return rig.now
		end,
	})

	-- the local character (a Model with a positioned root part); nil = not spawned
	function rig.spawn(position)
		local model = roblox.Instance.new("Model")
		local part = roblox.Instance.new("Part")
		part.Name = "HumanoidRootPart"
		part.Position = position or roblox.Vector3.new(0, 3, 0)
		part.Parent = model
		model.PrimaryPart = part
		state.character = model
		return model
	end
	-- advances the clock and the overlay's frame loop together (onStep(now) runs before each frame)
	function rig.run(seconds, onStep)
		local target = rig.now + seconds - 1e-9
		while rig.now < target do
			rig.now += DT
			if onStep then
				onStep(rig.now)
			end
			if rig.driver.step then
				rig.driver.step(DT)
			end
		end
	end
	-- runs until the running overlay has finished; returns its handle and the clock when it finished
	function rig.finish(maxSeconds, onStep)
		local handle = Loading.Active()
		local limit = rig.now + (maxSeconds or 30)
		while handle and not handle.Done and rig.now < limit do
			rig.now += DT
			if onStep then
				onStep(rig.now)
			end
			if rig.driver.step then
				rig.driver.step(DT)
			end
		end
		return handle, rig.now
	end
	-- the override log as "key@fade" (key "auto" = nil = automatic selection; fade "-" = SoundController's default)
	function rig.music(from)
		local out = {}
		for i = from or 1, #rig.sound.overrides do
			local o = rig.sound.overrides[i]
			table.insert(out, ("%s@%s"):format(o.key or "auto", if o.fade then tostring(o.fade) else "-"))
		end
		return table.concat(out, " ")
	end
	function rig.done()
		pcall(function()
			rig.parent:Destroy()
		end)
		Loader.restoreState(snapshot)
	end
	return rig
end

-- the sprite exactly as the owner sent it (a copy: an accidental edit of the module fails here)
local OWNER_ROWS = {
	"             ###############            ",
	"           ####################         ",
	"         ####...............####        ",
	"       ####....................###      ",
	"      ###.......................###     ",
	"     ##...........................##    ",
	"    ##.............................##   ",
	"   ##...............................##  ",
	"  ##.................................## ",
	" ##..................................## ",
	" ##..................................## ",
	" ##...................................##",
	"##.......######.......................##",
	"##.....#########......................##",
	"##....###########.......#.............##",
	"##...############.......#..........#..##",
	"##...#####..#####.......#..........#..##",
	"##...#####..#####.......#.........##.## ",
	" ##...##########....#...##.......##..## ",
	" ##....#########...###...#########..##  ",
	"  ##...........#...###...##........##   ",
	"   ##.........#...#####...#........##   ",
	"   ##.......##....#####....##.......##  ",
	"   ##....#........#####.............##  ",
	"  ##.....#....................#......## ",
	"  ##....###...................#......## ",
	"  ##..##.#.##................####....## ",
	"  ##......##.################.#......## ",
	"  ##.......#.#..#...#...#..#.#.......## ",
	"  ##........##..#...#...#..##.......##  ",
	"   ##........#..#...#...#..#........##  ",
	"    ##........#############........##   ",
	"     ##..........................###    ",
	"      ###......................####     ",
	"       #####.................####       ",
	"         ######################         ",
	"            #################           ",
}

return restoringFlags({
	sprite_data_integrity = function(T, Loader)
		local SansHead = Loader.requirePath(SANS)
		T.eq(SansHead.Width, 40, "width")
		T.eq(SansHead.Height, 37, "height")
		T.eq(#SansHead.Rows, 37, "37 rows")
		for i, row in SansHead.Rows do
			T.eq(#row, 40, "row " .. i .. " has 40 cells")
			T.ok(string.find(row, "[^#%. ]") == nil, "row " .. i .. " only uses '#', '.', ' '")
		end
		T.eq(#SansHead.Validate(), 0, "Validate: " .. table.concat(SansHead.Validate(), "; "))
		sameRows(T, SansHead.Rows, OWNER_ROWS, "the owner's sprite")
		local counts = { ["#"] = 0, ["."] = 0, [" "] = 0 }
		for _, row in SansHead.Rows do
			for x = 1, #row do
				local c = string.sub(row, x, x)
				counts[c] += 1
			end
		end
		T.eq(counts["#"] + counts["."] + counts[" "], 40 * 37, "every cell counted")
		T.ok(counts["."] > counts["#"], "mostly white skull")
		T.eq(SansHead.Colors["#"], Loader.roblox.Color3.fromRGB(0, 0, 0), "'#' = black")
		T.eq(SansHead.Colors["."], Loader.roblox.Color3.fromRGB(255, 255, 255), "'.' = white")
		-- Validate catches malformed sprites
		T.ok(#SansHead.Validate({ "##" }) >= 2, "wrong size reported")
		local broken = table.clone(SansHead.Rows)
		broken[5] = string.sub(broken[5], 1, 39) .. "x"
		T.eq(#SansHead.Validate(broken), 1, "bad character reported")
	end,

	sprite_runs_reproduce_sprite = function(T, Loader)
		local SansHead = Loader.requirePath(SANS)
		local runs = SansHead.Runs()
		local painted, err = paint(runs, 40, 37, true)
		T.ok(painted ~= nil, "runs do not overlap: " .. tostring(err))
		if painted then
			sameRows(T, painted, SansHead.Rows, "Runs() painted")
		end
		local cells, maximal = 0, true
		for i, r in runs do
			T.ok(r.length >= 1 and (r.color == "#" or r.color == "."), "run " .. i .. " well-formed")
			cells += r.length
			local nextRun = runs[i + 1]
			if nextRun and nextRun.y == r.y and nextRun.x == r.x + r.length and nextRun.color == r.color then
				maximal = false
			end
		end
		T.ok(maximal, "neighbouring runs of one colour are merged")
		local filled = 0
		for _, row in SansHead.Rows do
			local _, n = string.gsub(row, "[#%.]", "")
			filled += n
		end
		T.eq(cells, filled, "runs cover every non-transparent cell once")
		T.ok(#runs < filled / 4, ("merging pays off: %d runs for %d cells"):format(#runs, filled))
		-- layered (seam-proof) order: white under-fill first, black on top; painted in order = the sprite
		local layered = SansHead.LayeredRuns()
		local seenBlack = false
		local orderOk = true
		for _, r in layered do
			if r.color == "#" then
				seenBlack = true
			elseif seenBlack then
				orderOk = false
			end
		end
		T.ok(orderOk, "every white run comes before the black runs")
		local layeredPaint = paint(layered, 40, 37, false)
		T.ok(layeredPaint ~= nil, "layered runs inside the sprite")
		if layeredPaint then
			sameRows(T, layeredPaint, SansHead.Rows, "LayeredRuns() painted in order")
		end
		T.ok(#layered < #runs, ("layered order needs fewer frames (%d < %d)"):format(#layered, #runs))
		-- custom sprites work too (holes inside the white extent are never filled)
		local custom = { "#..#", ". .#" }
		local cp = paint(SansHead.LayeredRuns(custom), 4, 2, false)
		sameRows(T, cp, custom, "layered runs of a sprite with a hole")
		sameRows(T, paint(SansHead.Runs(custom), 4, 2, true), custom, "runs of a sprite with a hole")
	end,

	sprite_mirror = function(T, Loader)
		local SansHead = Loader.requirePath(SANS)
		T.eq(#SansHead.MirroredRows, 37, "mirrored rows")
		for i, row in SansHead.Rows do
			T.eq(SansHead.MirroredRows[i], string.reverse(row), "row " .. i .. " mirrored")
		end
		sameRows(T, SansHead.Mirror(SansHead.MirroredRows), SansHead.Rows, "mirror twice = original")
		T.eq(#SansHead.Validate(SansHead.MirroredRows), 0, "mirrored sprite valid")
		sameRows(T, paint(SansHead.Runs(SansHead.MirroredRows), 40, 37, true), SansHead.MirroredRows, "mirrored runs")
		sameRows(
			T,
			paint(SansHead.LayeredRuns(SansHead.MirroredRows), 40, 37, false),
			SansHead.MirroredRows,
			"mirrored layered runs"
		)
		-- every original run has its mirror image (x' = 40 - x - length)
		local set = {}
		for _, r in SansHead.Runs(SansHead.MirroredRows) do
			set[("%d:%d:%d:%s"):format(r.x, r.y, r.length, r.color)] = true
		end
		local missing = 0
		for _, r in SansHead.Runs() do
			if not set[("%d:%d:%d:%s"):format(40 - r.x - r.length, r.y, r.length, r.color)] then
				missing += 1
			end
		end
		T.eq(missing, 0, "runs mirror one to one")
		T.ok(SansHead.MirroredRows[16] ~= SansHead.Rows[16], "the wink is asymmetric (mirroring is visible)")
	end,

	overlay_builds_offline_both_modes = function(T, Loader)
		local Loading, Themes, _, roblox = setup(Loader)
		local SansHead = Loader.requirePath(SANS)
		local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
		local cellsPerSprite = #SansHead.LayeredRuns()
		local topLayer = 0
		for _, order in UIRoot.DisplayOrder do
			topLayer = math.max(topLayer, order)
		end
		for _, mode in { "Turn", "Wheel", "Still" } do
			for _, size in { { 860, 400 }, { 740, 360 }, { 812, 375 }, { 1920, 1080 }, { 390, 844 } } do
				local label = ("%s %dx%d"):format(mode, size[1], size[2])
				local viewport = roblox.Vector2.new(size[1], size[2])
				local ok, view = pcall(Loading.Build, Themes.Get("Classic"), { Viewport = viewport, Mode = mode })
				if not T.ok(ok, label .. " builds: " .. tostring(view)) then
					continue
				end
				local gui = view.Gui
				T.eq(gui.ClassName, "ScreenGui", label .. " own ScreenGui")
				T.eq(gui.IgnoreGuiInset, true, label .. " IgnoreGuiInset")
				T.eq(gui.ScreenInsets, roblox.Enum.ScreenInsets.None, label .. " ScreenInsets None (notch covered)")
				T.eq(gui.ClipToDeviceSafeArea, false, label .. " not clipped to the safe area")
				T.eq(gui.ResetOnSpawn, false, label .. " survives respawns")
				T.ok(gui.DisplayOrder > topLayer and gui.DisplayOrder > 25, label .. " above every UI layer")
				T.eq(view.Backdrop.Active, true, label .. " backdrop swallows input")
				T.eq(view.Backdrop.Size, roblox.UDim2.fromScale(1, 1), label .. " backdrop full screen")
				T.eq(view.Backdrop.BackgroundColor3, roblox.Color3.new(0, 0, 0), label .. " black")
				T.eq(
					view.Head.ClassName,
					if mode == "Wheel" then "CanvasGroup" else "Frame",
					label .. " head container"
				)
				T.eq(#view.Normal:GetChildren(), cellsPerSprite, label .. " one Frame per layered run")
				T.eq(view.Mirrored ~= nil, mode == "Turn", label .. " mirrored sprite only for the coin turn")
				if view.Mirrored then
					T.eq(#view.Mirrored:GetChildren(), cellsPerSprite, label .. " mirrored cells")
				end
				T.ok(string.find(view.Label.FontFace.Family, "PressStart2P", 1, true) ~= nil, label .. " pixel font")
				T.ok(string.find(view.Label.Text, "LOADING", 1, true) ~= nil, label .. " says LOADING")
				T.eq(view.Mode, mode, label .. " mode")
				-- metrics: whole pixels, head + text on screen
				local m = view.Metrics
				T.eq(m.Pixel, math.floor(m.Pixel), label .. " integer pixel size")
				if size[2] <= 400 or size[1] <= 400 then
					T.ok(
						m.Pixel >= 5 and m.Pixel <= 6,
						label .. " ~5-6 px per sprite pixel on a phone (" .. m.Pixel .. ")"
					)
				end
				T.ok(m.HeadTop >= 0 and m.TextTop + m.TextSize <= size[2], label .. " head + text inside the screen")
				T.ok(m.HeadTop > size[2] * 0.08, label .. " not glued to the top")
				local textWidth = 14 * m.TextSize -- worst case: "ЗАГРУЗКА" + 3 dots + 3 invisible pad dots
				T.ok(textWidth <= size[1] - 16, label .. " text fits the width")
				T.eq(m.HeadW, 40 * m.Pixel, label .. " head width")
				T.eq(m.HeadH, 37 * m.Pixel, label .. " head height")
				-- previews at several spin phases never fail
				for _, spin in { 0, 0.13, 0.25, 0.4, 0.5, 0.77 } do
					T.noerror(function()
						view.Pose(spin * Loading.TurnPeriod)
					end, label .. " pose " .. spin)
				end
				T.noerror(function()
					view.Fade(0.5, 0.5)
					view.Layout(roblox.Vector2.new(size[2], size[1]))
				end, label .. " fade + relayout (rotation)")
				view.Destroy()
				T.eq(gui.Parent, nil, label .. " destroyed")
			end
		end
		-- unknown mode -> the file's SPIN_MODE
		local fallback = Loading.Build(nil, { Viewport = roblox.Vector2.new(860, 400), Mode = "Bogus" })
		T.eq(fallback.Mode, Loading.SPIN_MODE, "unknown mode falls back to SPIN_MODE")
		T.ok(Loading.SPIN_MODE == "Turn" or Loading.SPIN_MODE == "Wheel", "SPIN_MODE is a real mode")
		fallback.Destroy()
	end,

	overlay_sprite_pixel_exact_at_rest = function(T, Loader)
		local Loading, Themes, _, roblox = setup(Loader)
		local SansHead = Loader.requirePath(SANS)
		for _, size in { { 860, 400 }, { 861, 401 }, { 1366, 768 } } do
			local label = ("%dx%d"):format(size[1], size[2])
			local view = Loading.Preview(
				Themes.Get("Classic"),
				roblox.Vector2.new(size[1], size[2]),
				{ Mode = "Turn", Spin = 0 }
			)
			local m = view.Metrics
			T.eq(view.Head.Size, roblox.UDim2.fromOffset(m.Grid, m.Grid), label .. " head container at rest")
			T.eq(view.Head.Position, roblox.UDim2.fromOffset(m.Left, m.Top), label .. " head container position")
			T.eq(m.Left + 12 * m.Pixel, m.CenterX - 20 * m.Pixel, label .. " sprite centred")
			T.eq(view.Normal.Visible, true, label .. " front sprite shown")
			T.eq(view.Mirrored.Visible, false, label .. " back sprite hidden")
			sameRows(
				T,
				readSprite(T, view.Normal, m, Loading, label),
				SansHead.Rows,
				label .. " front sprite on screen"
			)
			sameRows(
				T,
				readSprite(T, view.Mirrored, m, Loading, label),
				SansHead.MirroredRows,
				label .. " back sprite on screen"
			)
			view.Destroy()
		end
	end,

	overlay_poses_and_text = function(T, Loader)
		local Loading, Themes, Strings, roblox = setup(Loader)
		-- coin turn
		local P = Loading.TurnPeriod
		T.near(P, 1.2, 0.3, "about 1.2 s per turn")
		local f0, m0 = Loading.TurnPose(0)
		T.near(f0, 1, 1e-9, "facing front at t = 0")
		T.eq(m0, false, "front = not mirrored")
		local fq = Loading.TurnPose(P / 4)
		T.near(fq, 0, 1e-6, "edge-on at a quarter turn")
		local fh, mh = Loading.TurnPose(P / 2)
		T.near(fh, 1, 1e-9, "full width at half a turn")
		T.eq(mh, true, "back of the coin = mirrored")
		for i = 0, 47 do
			local t = P * i / 48
			local f, mirrored = Loading.TurnPose(t)
			local c = math.cos(2 * math.pi * t / P)
			T.near(f, math.abs(c), 1e-9, "width follows |cos|")
			T.eq(mirrored, c < 0, "mirrored while cos < 0")
		end
		local view = Loading.Build(Themes.Get("Classic"), { Viewport = roblox.Vector2.new(860, 400), Mode = "Turn" })
		local m = view.Metrics
		for i = 0, 23 do
			local t = P * i / 24
			view.Pose(t)
			local f, mirrored = Loading.TurnPose(t)
			local width = view.Head.Size.X.Offset
			T.eq(width, math.round(m.Grid * f), "turn width at " .. i)
			T.eq(view.Head.Size.Y.Offset, m.Grid, "height never changes")
			T.ok(math.abs(view.Head.Position.X.Offset + width / 2 - m.CenterX) <= 1, "stays centred at " .. i)
			local bob = view.Head.Position.Y.Offset - m.Top
			T.ok(math.abs(bob) <= m.Bob and bob == math.floor(bob), "tiny whole-pixel bob at " .. i)
			local shown = width >= 2
			T.eq(view.Normal.Visible, shown and not mirrored, "front visibility at " .. i)
			T.eq(view.Mirrored.Visible, shown and mirrored, "back visibility at " .. i)
		end
		T.ok(m.Bob >= 1 and m.Bob <= m.Pixel, "bob amplitude is tiny (" .. m.Bob .. " px)")
		view.Destroy()
		-- wheel
		local wheel = Loading.Build(Themes.Get("Classic"), { Viewport = roblox.Vector2.new(860, 400), Mode = "Wheel" })
		for _, t in { 0, 0.4, 0.8, 1.2, 1.55 } do
			wheel.Pose(t)
			T.near(wheel.Head.Rotation, Loading.WheelAngle(t), 1e-3, "wheel angle at " .. t)
			T.eq(
				wheel.Head.Size,
				roblox.UDim2.fromOffset(wheel.Metrics.Grid, wheel.Metrics.Grid),
				"wheel keeps its size"
			)
			T.eq(wheel.Normal.Visible, true, "wheel sprite visible")
		end
		T.near(Loading.WheelAngle(Loading.WheelPeriod / 4), 90, 1e-6, "a quarter turn = 90 degrees")
		-- the turning head never reaches the text: farthest painted cell corner from the pivot (the container
		-- centre = sprite cell (20, 19)) + the bob stays above the text, and the top stays on screen
		local SansHead = Loader.requirePath(SANS)
		local reach = 0
		for y, row in SansHead.Rows do
			for x = 1, #row do
				if string.sub(row, x, x) ~= " " then
					for _, cx in { x - 1, x } do
						for _, cy in { y - 1, y } do
							reach = math.max(reach, math.sqrt((cx - 20) ^ 2 + (cy - 19) ^ 2))
						end
					end
				end
			end
		end
		for _, size in { { 860, 400 }, { 740, 360 }, { 1920, 1080 }, { 390, 844 } } do
			local wm = Loading.Metrics(roblox.Vector2.new(size[1], size[2]), "Wheel")
			local pivotY = wm.Top + wm.Grid / 2
			T.eq(pivotY, wm.HeadTop + 19 * wm.Pixel, "pivot = container centre")
			T.ok(
				pivotY + reach * wm.Pixel + wm.Bob < wm.TextTop,
				("%dx%d wheel clears the text"):format(size[1], size[2])
			)
			T.ok(pivotY - reach * wm.Pixel - wm.Bob >= 0, ("%dx%d wheel stays on screen"):format(size[1], size[2]))
		end
		wheel.Destroy()
		-- still (Reduced Motion)
		local still = Loading.Build(nil, { Viewport = roblox.Vector2.new(860, 400), Mode = "Still" })
		still.Pose(0.77)
		T.eq(
			still.Head.Position,
			roblox.UDim2.fromOffset(still.Metrics.Left, still.Metrics.Top),
			"still head does not move"
		)
		T.eq(still.Head.Rotation, 0, "still head upright")
		still.Destroy()
		-- dots
		local seen = {}
		for i = 0, 40 do
			local n = Loading.DotCount(i * 0.1)
			T.ok(n >= 0 and n <= 3, "0..3 dots")
			seen[n] = true
		end
		T.ok(seen[0] and seen[1] and seen[2] and seen[3], "every dot count shows up")
		T.eq(Loading.DotCount(0), 0, "starts without dots")
		for n = 0, 3 do
			local text = Loading.Text("LOADING", n)
			local _, dots = string.gsub(text, "%.", "")
			T.eq(dots, 6, n .. " dots: always 3 pad + 3 dot glyphs (the word never moves)")
			T.ok(
				string.find(text, '^<font transparency="1">%.%.%.</font>LOADING') ~= nil,
				n .. " dots: invisible left pad"
			)
		end
		T.ok(string.find(Loading.Text("LOADING", 3), "LOADING...", 1, true) ~= nil, "three visible dots")
		T.ok(string.find(Loading.Text("A<B", 0), "A&lt;B", 1, true) ~= nil, "RichText escaped")
		T.ok(
			string.find(
				Loading.Text("X", 2, roblox.Color3.fromRGB(255, 24, 44)),
				'<font color="#FF182C">..</font>',
				1,
				true
			) ~= nil,
			"tinted dots"
		)
		-- language + theme
		T.eq(Strings.L("loading.title"), "LOADING", "en string")
		Strings.SetLanguage("ru")
		T.eq(Strings.L("loading.title"), "ЗАГРУЗКА", "ru string")
		local ru = Loading.Build(Themes.Get("Fell"), { Viewport = roblox.Vector2.new(860, 400) })
		T.ok(string.find(ru.Label.Text, "ЗАГРУЗКА", 1, true) ~= nil, "ru label")
		T.eq(
			ru.Label.FontFace.Family,
			Themes.Font(Themes.Get("Classic"), "Display", "ru").Family,
			"ru keeps the (Cyrillic) pixel font"
		)
		ru.Pose(3 * Loading.DotPeriod + 0.01)
		T.ok(string.find(ru.Label.Text, "<font color=", 1, true) ~= nil, "Fell tints the dots")
		ru.Destroy()
		Strings.SetLanguage("en")
	end,

	sequence_minimum_time = function(T, Loader)
		local Loading = setup(Loader)
		local timing = Loading.Timing
		T.near(timing.FadeIn, 0.35, 0.1, "fade to black ~0.35 s")
		T.near(timing.MinVisible, 2.2, 0.2, "minimum ~2.2 s")
		T.near(timing.ContentOut + timing.FadeOut, 0.5, 0.1, "fade out ~0.5 s")
		T.eq(timing.MaxWait, 7, "7 s cap")
		local seq = Loading.NewSequence()
		local coveredAt, outAt, doneAt
		local covers, dones = 0, 0
		local lastBackdrop = -1
		local monotonic = true
		local maxContent = 0
		while seq.Stage ~= "Done" and seq.Time < 20 do
			local phaseBefore = seq.Stage
			local covered, done = seq.Step(DT, true) -- PLAY: no condition
			if covered then
				covers += 1
				coveredAt = seq.Time
			end
			if done then
				dones += 1
				doneAt = seq.Time
			end
			if phaseBefore == "FadeIn" then
				monotonic = monotonic and seq.Backdrop >= lastBackdrop
				lastBackdrop = seq.Backdrop
			end
			if phaseBefore == "Hold" and seq.Stage == "FadeOut" then
				outAt = seq.Time
			end
			maxContent = math.max(maxContent, seq.Content)
			if seq.Stage == "Hold" then
				T.eq(seq.Backdrop, 1, "black while holding")
			end
		end
		T.eq(covers, 1, "covered once")
		T.eq(dones, 1, "done once")
		T.ok(monotonic, "the black only grows during the fade-in")
		T.near(coveredAt, timing.FadeIn, 2 * DT, "covered when the fade-in ends")
		T.near(outAt, timing.MinVisible, 2 * DT, "fade-out starts at the minimum time")
		T.near(doneAt, timing.MinVisible + timing.ContentOut + timing.FadeOut, 3 * DT, "done after the fade-out")
		T.near(maxContent, 1, 1e-9, "head + text fully shown")
		T.eq(seq.Backdrop, 0, "clear at the end")
		T.eq(seq.Content, 0, "content gone at the end")
		local covered, done = seq.Step(DT, true)
		T.ok(not covered and not done, "no events after Done")
	end,

	sequence_music_cue = function(T, Loader)
		local Loading = setup(Loader)
		local function run(opts, readyFrom)
			local seq = Loading.NewSequence(opts)
			local cueAt, outAt, cues = nil, nil, 0
			local t = 0
			for _ = 1, 2000 do
				local _covered, done, cue = seq.Step(1 / 60, t >= (readyFrom or 0))
				t += 1 / 60
				if cue then
					cues += 1
					cueAt = cueAt or seq.Time
				end
				if seq.OutAt and outAt == nil then
					outAt = seq.OutAt
				end
				if done then
					break
				end
			end
			return cueAt, outAt, cues
		end
		-- PLAY: 4 s minimum, the music cue 2 s before the fade-out
		local cueAt, outAt, cues = run({ MinVisible = 4, MusicLead = 2 })
		T.eq(cues, 1, "the cue fires exactly once")
		T.ok(cueAt ~= nil and math.abs(cueAt - 2) < 0.05, ("cue at about 2 s (got %s)"):format(tostring(cueAt)))
		T.ok(outAt ~= nil and math.abs(outAt - 4) < 0.05, ("fade-out at about 4 s (got %s)"):format(tostring(outAt)))
		-- practice: ready late (5 s) -> cue then, reveal 2 s later, but never past the cap
		cueAt, outAt = run({ MinVisible = 4, MusicLead = 2, MaxWait = 7 }, 5)
		T.ok(cueAt ~= nil and cueAt >= 5 and cueAt < 5.5, ("late ready: cue right after it (got %s)"):format(tostring(cueAt)))
		T.ok(outAt ~= nil and outAt <= 7 + 0.05, ("never past the cap (got %s)"):format(tostring(outAt)))
		-- never ready: the cue fires MusicLead before the cap
		cueAt, outAt = run({ MinVisible = 4, MusicLead = 2, MaxWait = 7 }, math.huge)
		T.ok(cueAt ~= nil and math.abs(cueAt - 5) < 0.05, ("cap: cue at cap - lead (got %s)"):format(tostring(cueAt)))
		T.ok(outAt ~= nil and math.abs(outAt - 7) < 0.05, ("cap: fade-out at the cap (got %s)"):format(tostring(outAt)))
		-- without a lead the cue fires on the release step (old behaviour unchanged)
		cueAt, outAt, cues = run({})
		T.eq(cues, 1, "no lead: one cue")
		T.ok(cueAt ~= nil and outAt ~= nil and math.abs(cueAt - outAt) < 1e-6, "no lead: cue = release")
	end,

	sequence_until_cap_skip_hitches = function(T, Loader)
		local Loading = setup(Loader)
		local timing = Loading.Timing
		local function runUntil(readyFrom, opts)
			local seq = Loading.NewSequence(opts)
			local outAt
			while seq.Stage ~= "Done" and seq.Time < 30 do
				local before = seq.Stage
				seq.Step(DT, readyFrom ~= nil and seq.Time >= readyFrom)
				if before == "Hold" and seq.Stage == "FadeOut" then
					outAt = seq.Time
				end
			end
			return outAt, seq
		end
		-- practice: the round never starts -> the cap
		local outCap = runUntil(nil)
		T.near(outCap, timing.MaxWait, 2 * DT, "never ready -> released at the 7 s cap")
		-- the round starts at 3 s -> + settle
		local outLate = runUntil(3)
		T.ok(
			outLate >= 3 + timing.Settle and outLate <= 3 + timing.Settle + 4 * DT,
			"ready at 3 s -> released after the settle (" .. outLate .. ")"
		)
		-- ready early -> still the minimum time
		local outEarly = runUntil(0.5)
		T.near(outEarly, timing.MinVisible, 2 * DT, "ready early -> minimum time")
		-- custom MinVisible / MaxWait
		local outCustom = runUntil(nil, { MaxWait = 4 })
		T.near(outCustom, 4, 2 * DT, "custom cap")
		local outMin = runUntil(0, { MinVisible = 1 })
		T.near(outMin, 1, 2 * DT, "custom minimum")
		local _, junk = runUntil(nil, { MaxWait = -3, MinVisible = 0 / 0 })
		T.eq(junk.Timing.MaxWait, timing.MaxWait, "negative / NaN overrides are ignored")
		T.eq(junk.Timing.MinVisible, timing.MinVisible, "NaN override ignored")
		T.eq(Loading.NewSequence({ MaxWait = math.huge }).Timing.MaxWait, timing.MaxWait, "an endless cap is ignored")
		T.ok(Loading.NewSequence({ MaxWait = 1000 }).Timing.MaxWait <= 30, "the cap itself is capped")
		-- skip: fade-out as soon as the screen is black
		local seq = Loading.NewSequence()
		seq.Skip()
		local out
		while seq.Stage ~= "Done" and seq.Time < 5 do
			local before = seq.Stage
			seq.Step(DT, false)
			if before == "Hold" and seq.Stage == "FadeOut" then
				out = seq.Time
			end
		end
		T.near(out, timing.FadeIn + DT, 2 * DT, "Skip releases right after the screen is black")
		-- hitches: a huge dt never skips a whole phase; NaN / negative dt do nothing
		local h = Loading.NewSequence()
		h.Step(10, true)
		T.eq(h.Stage, "FadeIn", "one huge step stays in the fade-in (clamped)")
		local covered = h.Step(10, true)
		T.ok(covered and h.Stage == "Hold", "the next one covers")
		local t0 = h.Time
		h.Step(0 / 0, true)
		h.Step(-5, true)
		T.eq(h.Time, t0, "NaN / negative dt ignored")
		local steps = 0
		while h.Stage ~= "Done" and steps < 1000 do
			h.Step(10, true)
			steps += 1
		end
		T.eq(h.Stage, "Done", "finishes with huge steps too")
		T.ok(steps < 100, "in a bounded number of steps")
	end,

	show_runtime_sequence_sound_and_no_stacking = function(T, Loader)
		local Loading, Themes, _, roblox = setup(Loader)
		local parent = roblox.Instance.new("Folder")
		local driver = fakeDriver(Loader, 860, 400)
		local sound = fakeSound(true)
		local covered, done = 0, 0
		local coveredAtGui
		local handle = Loading.Show({
			Driver = driver,
			Parent = parent,
			Sound = sound,
			Theme = Themes.Get("Classic"),
			OnCovered = function()
				covered += 1
				coveredAtGui = guisUnder(parent)
			end,
			OnDone = function()
				done += 1
			end,
		})
		T.ok(handle ~= nil, "shown")
		T.eq(guisUnder(parent), 1, "one overlay parented")
		T.eq(Loading.Active(), handle, "active handle")
		T.eq(sound.plays[1], "PlayTransition", "sound starts with the fade to black")
		T.eq(#sound.plays, 1, "played once")
		T.eq(#driver.delays, 1, "failsafe scheduled")
		T.ok(driver.delays[1].t >= Loading.Timing.MaxWait, "failsafe after the cap")
		local gui = handle.View.Gui
		T.eq(gui.Parent, parent, "under the given parent")
		T.eq(handle.View.Backdrop.BackgroundTransparency, 1, "starts transparent")
		-- no stacking
		local otherCovered = false
		local second = Loading.Show({
			Driver = fakeDriver(Loader, 860, 400),
			Parent = parent,
			OnCovered = function()
				otherCovered = true
			end,
		})
		T.eq(second, handle, "a second Show returns the running overlay")
		T.eq(guisUnder(parent), 1, "still one overlay")
		-- fade to black
		driver.run(0.2)
		local mid = handle.View.Backdrop.BackgroundTransparency
		T.ok(mid > 0 and mid < 1, "half-way into the black (" .. mid .. ")")
		T.eq(covered, 0, "not covered yet")
		T.eq(handle.View.Content.Visible, false, "head hidden while fading in")
		driver.run(0.2)
		T.eq(covered, 1, "covered once the screen is black")
		T.eq(coveredAtGui, 1, "the overlay is up when OnCovered runs")
		T.eq(handle.View.Backdrop.BackgroundTransparency, 0, "fully black")
		driver.run(0.4)
		T.eq(handle.View.Content.Visible, true, "head + text shown")
		T.eq(handle.View.Curtain.Visible, false, "curtain gone once the content is in")
		T.ok(#sound.ducks >= 2, "music ducked while black")
		T.eq(sound.ducks[1][1], Loading.DuckAmount, "duck amount")
		-- a viewport change (rotation) re-lays out
		driver.size = roblox.Vector2.new(400, 860)
		driver.run(DT)
		T.eq(handle.View.Metrics.Viewport, roblox.Vector2.new(400, 860), "relayout on resize")
		driver.size = roblox.Vector2.new(860, 400)
		-- hold until the minimum time, then fade out
		local elapsed = 0.8 + DT
		while not handle.Done and elapsed < 10 do
			driver.step(DT)
			elapsed += DT
		end
		T.ok(handle.Done, "finished")
		T.near(
			elapsed,
			Loading.Timing.MinVisible + Loading.Timing.ContentOut + Loading.Timing.FadeOut,
			4 * DT,
			"~2.75 s in total"
		)
		T.eq(covered, 1, "OnCovered exactly once")
		T.eq(done, 1, "OnDone exactly once")
		T.eq(otherCovered, false, "the ignored second Show never fires its callbacks")
		T.eq(gui.Parent, nil, "overlay removed")
		T.eq(guisUnder(parent), 0, "nothing left under the parent")
		T.eq(Loading.Active(), nil, "no active overlay")
		T.eq(driver.step, nil, "frame loop disconnected")
		T.eq(#sound.stops, 1, "still-playing sound faded out")
		T.eq(sound.stops[1].voice, sound.voice, "the overlay's own voice")
		T.near(sound.stops[1].fade, 0.4, 1e-9, "0.4 s fade")
		local ducks = #sound.ducks
		-- the failsafe firing later is harmless
		driver.delays[1].fn()
		T.eq(done, 1, "failsafe after the end does nothing")
		T.eq(#sound.ducks, ducks, "no ducking after the end")
		-- a new Show after the end makes a new overlay; a sound that already ended is not touched
		local quiet = fakeSound(false)
		local d2 = fakeDriver(Loader, 860, 400)
		local h2 = Loading.Show({ Driver = d2, Parent = parent, Sound = quiet })
		T.ok(h2 ~= nil and h2 ~= handle, "a fresh overlay after the end")
		d2.run(4)
		T.ok(h2.Done, "second overlay done")
		T.eq(#quiet.stops, 0, "a finished sound is not stopped")
		parent:Destroy()
	end,

	show_practice_until_cap_and_errors = function(T, Loader)
		local Loading, _, _, roblox = setup(Loader)
		local warnings = {}
		Loader.onWarn = function(...)
			table.insert(warnings, table.concat({ ... }, " "))
		end
		local parent = roblox.Instance.new("Folder")
		-- practice that never starts: released by the cap, OnCovered (the request) once
		local driver = fakeDriver(Loader, 860, 400)
		local requests, polls = 0, 0
		local h = Loading.Show({
			Driver = driver,
			Parent = parent,
			MaxWait = 7,
			OnCovered = function()
				requests += 1
			end,
			Until = function()
				polls += 1
				return false
			end,
		})
		local t = driver.run(30)
		T.ok(h.Done, "the black never stays up forever")
		T.near(t, 7 + Loading.Timing.ContentOut + Loading.Timing.FadeOut, 4 * DT, "cap + fade-out")
		T.eq(requests, 1, "request sent once")
		T.ok(polls > 100, "condition polled while holding")
		-- the round starts at ~3 s
		local d2 = fakeDriver(Loader, 860, 400)
		local started = false
		local outAt
		local h2 = Loading.Show({
			Driver = d2,
			Parent = parent,
			Until = function()
				return started
			end,
		})
		local clock = 0
		while not h2.Done and clock < 20 do
			if clock >= 3 then
				started = true
			end
			local before = h2.Sequence.Stage
			d2.step(DT)
			clock += DT
			if before == "Hold" and h2.Sequence.Stage == "FadeOut" then
				outAt = clock
			end
		end
		T.ok(
			outAt >= 3 + Loading.Timing.Settle and outAt <= 3 + Loading.Timing.Settle + 4 * DT,
			"released after the round started + settle (" .. tostring(outAt) .. ")"
		)
		-- errors never keep the screen black: OnCovered / Until throwing
		local d3 = fakeDriver(Loader, 860, 400)
		local h3 = Loading.Show({
			Driver = d3,
			Parent = parent,
			OnCovered = function()
				error("boom in OnCovered")
			end,
			Until = function()
				error("boom in Until")
			end,
		})
		local t3 = d3.run(30)
		T.ok(h3.Done, "finished despite failing callbacks")
		T.ok(t3 < Loading.Timing.MinVisible + 1, "a failing Until counts as ready (" .. t3 .. ")")
		local sawWarn = false
		for _, w in warnings do
			if string.find(w, "OnCovered", 1, true) then
				sawWarn = true
			end
		end
		T.ok(sawWarn, "the failure is reported")
		-- a broken frame (view destroyed under it) finishes at once, OnCovered + OnDone still exactly once
		local d4 = fakeDriver(Loader, 860, 400)
		local c4, done4 = 0, 0
		local h4 = Loading.Show({
			Driver = d4,
			Parent = parent,
			OnCovered = function()
				c4 += 1
			end,
			OnDone = function()
				done4 += 1
			end,
		})
		h4.View.Fade = function()
			error("broken view")
		end
		d4.step(DT)
		T.ok(h4.Done, "a frame error closes the overlay")
		T.eq(c4, 1, "OnCovered still runs (the title closes)")
		T.eq(done4, 1, "OnDone once")
		T.eq(guisUnder(parent), 0, "removed")
		-- the frame loop never runs (app in the background): the failsafe removes it
		local d5 = fakeDriver(Loader, 860, 400)
		local c5, done5 = 0, 0
		local h5 = Loading.Show({
			Driver = d5,
			Parent = parent,
			OnCovered = function()
				c5 += 1
			end,
			OnDone = function()
				done5 += 1
			end,
		})
		T.eq(guisUnder(parent), 1, "up")
		d5.delays[1].fn()
		T.ok(h5.Done, "failsafe finished it")
		T.eq(c5, 1, "OnCovered once")
		T.eq(done5, 1, "OnDone once")
		T.eq(guisUnder(parent), 0, "removed by the failsafe")
		-- Destroy during the fade-in; Finish skips the hold
		local d6 = fakeDriver(Loader, 860, 400)
		local c6 = 0
		local h6 = Loading.Show({
			Driver = d6,
			Parent = parent,
			OnCovered = function()
				c6 += 1
			end,
		})
		d6.run(0.1)
		h6.Destroy()
		h6.Destroy()
		T.ok(h6.Done and c6 == 1, "Destroy: done, OnCovered once")
		T.eq(d6.step, nil, "loop disconnected")
		local d7 = fakeDriver(Loader, 860, 400)
		local h7 = Loading.Show({
			Driver = d7,
			Parent = parent,
			Until = function()
				return false
			end,
		})
		h7.Finish()
		local t7 = d7.run(30)
		T.ok(h7.Done, "Finish ends it")
		T.ok(
			t7 < Loading.Timing.FadeIn + Loading.Timing.ContentOut + Loading.Timing.FadeOut + 0.1,
			"Finish skips the hold (" .. t7 .. ")"
		)
		-- no parent -> nil (the caller falls back to the instant switch); a driver that cannot connect -> no overlay left
		T.eq(Loading.Show({ Driver = fakeDriver(Loader, 860, 400) }), nil, "no PlayerGui offline -> nil")
		local c8 = 0
		local h8 = Loading.Show({
			Driver = {
				Connect = function()
					error("no loop")
				end,
				Viewport = function()
					return roblox.Vector2.new(860, 400)
				end,
				Delay = function() end,
			},
			Parent = parent,
			OnCovered = function()
				c8 += 1
			end,
		})
		T.ok(h8 == nil or h8.Done, "a dead driver leaves nothing running")
		T.eq(c8, 1, "and the caller's switch still happened")
		T.eq(guisUnder(parent), 0, "nothing left")
		T.eq(Loading.Active(), nil, "nothing active")
		parent:Destroy()
	end,

	strings_audio_and_controller_hooks = function(T, Loader)
		local Loading, _, Strings = setup(Loader)
		T.ok(Strings.Has("loading.title"), "loading.title registered (Strings/init SOURCES)")
		local Audio = Loader.require("ReplicatedStorage.Shared.Audio")
		local def = Audio.Get(Loading.SoundName)
		if T.ok(def ~= nil, "Audio has " .. Loading.SoundName) then
			T.eq(def.Group, "UI", "UI sound")
			T.eq(def.Spatial, false, "2D")
			T.near(def.Volume, 0.6, 1e-9, "volume 0.6")
			T.eq(#Audio.Candidates(Loading.SoundName), 0, "PlayTransition is an optional, empty one-shot slot")
			T.eq(Audio.Candidates("Menu")[1], "rbxassetid://120586834968743", "the owner's id is the title (Menu) track")
			T.eq(Audio.Candidates("Lobby")[1], "rbxassetid://133849870887812", "the owner's lobby track comes first")
			T.eq(#Audio.Candidates("Silence"), 0, "Silence never plays anything")
			T.ok(def.Looped ~= true, "not looped (it is faded out when the overlay ends)")
		end
		T.eq(#Audio.Validate(), 0, "Audio still validates")
		-- UIController finds the overlay where it looks for it, and PLAY / PRACTICE fall back before Start
		local UIController = Loader.requirePath("src/client/Controllers/UIController")
		T.ok(type(Loading.Show) == "function", "UI/Overlays/Loading exposes Show")
		T.noerror(function()
			UIController.Play()
		end, "Play before Start (instant fallback)")
		T.noerror(function()
			UIController.Practice("Human")
		end, "Practice before Start (instant fallback)")
	end,

	-- the reveal never waits for the music lead once the round is ready (PRACTICE's Intro must be seen); a plain dip
	sequence_lead_never_delays_reveal = function(T, Loader)
		local Loading = setup(Loader)
		local function run(opts, readyFrom)
			local seq = Loading.NewSequence(opts)
			local cueAt, doneAt
			while seq.Stage ~= "Done" and seq.Time < 30 do
				local _covered, done, cue = seq.Step(DT, seq.Time >= (readyFrom or 0))
				if cue and cueAt == nil then
					cueAt = seq.Time
				end
				if done then
					doneAt = seq.Time
				end
			end
			return cueAt, seq.OutAt, doneAt
		end
		-- PRACTICE (1.2 s minimum, 2 s lead): the Intro arrives at 3.5 s -> cue now, reveal after the settle only
		-- (one frame of slack below, a few above: `ready` is sampled before each 1/60 s step)
		local function within(v, at, label)
			T.ok(v ~= nil and v >= at - DT and v <= at + 4 * DT, ("%s (%s, expected ~%.2f)"):format(label, tostring(v), at))
		end
		local cueAt, outAt = run({ MinVisible = 1.2, MusicLead = 2, MaxWait = 7 }, 3.5)
		within(cueAt, 3.5, "cue as soon as the round is ready")
		within(outAt, 3.5 + Loading.Timing.Settle, "fade-out after the settle, not after the 2 s lead")
		-- the Intro arrives early (0.5 s): the minimum time still holds, the music starts with the round
		cueAt, outAt = run({ MinVisible = 1.2, MusicLead = 2, MaxWait = 7 }, 0.5)
		within(cueAt, 0.5, "early round: cue at once")
		within(outAt, 1.2, "early round: the 1.2 s minimum")
		-- PLAY waiting for a late character (3 s): the lead shrinks, the 4 s reveal does not move
		cueAt, outAt = run({ MinVisible = 4, MusicLead = 2, MaxWait = 7 }, 3)
		within(cueAt, 3, "late character: cue when it is there")
		within(outAt, 4, "late character: still revealed at 4 s")
		-- a plain dip (a later PLAY): ~0.6 s in all
		local _, dipOut, dipDone = run({ FadeIn = 0.2, MinVisible = 0.3, Settle = 0, ContentOut = 0, FadeOut = 0.3 })
		within(dipOut, 0.3, "dip: black for a moment")
		within(dipDone, 0.6, "dip: done after ~0.6 s")
	end,

	overlay_plain_dip = function(T, Loader)
		local Loading, _, _, roblox = setup(Loader)
		local view = Loading.Build(nil, { Viewport = roblox.Vector2.new(860, 400), Plain = true })
		T.eq(view.Plain, true, "plain view")
		T.eq(#view.Normal:GetChildren(), 0, "no sprite cells")
		T.eq(view.Mirrored, nil, "no mirrored sprite")
		T.eq(view.Label.Text, "", "no LOADING text")
		view.Fade(1, 1)
		T.eq(view.Content.Visible, false, "content never shows on a plain view")
		view.Destroy()
		-- runtime: Content = false + timing overrides; no Sound = no transition sound, no ducking
		local parent = roblox.Instance.new("Folder")
		local driver = fakeDriver(Loader, 860, 400)
		local covered = 0
		local handle = Loading.Show({
			Driver = driver,
			Parent = parent,
			Content = false,
			FadeIn = 0.2,
			MinVisible = 0.3,
			Settle = 0,
			ContentOut = 0,
			FadeOut = 0.3,
			OnCovered = function()
				covered += 1
			end,
		})
		T.ok(handle ~= nil and handle.View.Plain, "a plain dip is up")
		local shown = false
		local t = 0
		while not handle.Done and t < 5 do
			shown = shown or handle.View.Content.Visible
			driver.step(DT)
			t += DT
		end
		T.ok(handle.Done, "done")
		T.near(t, 0.6, 3 * DT, "~0.6 s")
		T.eq(covered, 1, "OnCovered once")
		T.eq(shown, false, "no head / text at any point")
		parent:Destroy()
	end,

	-- review fix: whatever happens to the loading screen, the "Silence" override never outlives it
	controller_music_never_stuck_silent = function(T, Loader)
		local function scenario(label, opts, prepare)
			local rig = controllerRig(Loader, opts)
			local ok, err = pcall(function()
				rig.spawn()
				if prepare then
					prepare(rig)
				end
				rig.UI.Open("Title")
				T.eq(rig.sound.override, "Menu", label .. ": the Title plays the Menu track")
				rig.UI.Play()
				rig.run(0.1)
				T.eq(rig.UI.IsOpen(), false, label .. ": PLAY closed the menus")
				T.eq(rig.sound.override, nil, label .. ": music back on automatic selection")
				T.ok(not string.find(rig.music(), "Silence", 1, true), label .. ": no Silence (" .. rig.music() .. ")")
				T.eq(rig.Loading.Active(), nil, label .. ": no overlay left")
				rig.UI.Open("Title")
				rig.UI.Practice("Human")
				rig.run(0.1)
				T.eq(#rig.state.requests, 1, label .. ": PRACTICE still sends its request, once")
				T.eq(rig.state.requests[1] and rig.state.requests[1].action, "StartPractice", label .. ": StartPractice")
				T.eq(rig.UI.IsOpen(), false, label .. ": PRACTICE closed the menus")
				T.eq(rig.sound.override, nil, label .. ": music automatic after PRACTICE")
				T.ok(not string.find(rig.music(), "Silence", 1, true), label .. ": still no Silence")
			end)
			rig.done()
			if not ok then
				error(err, 0)
			end
		end
		-- Show returns nil (no PlayerGui), Show throws, the module is unusable, the frame loop is dead
		scenario("no PlayerGui", { NoParent = true })
		scenario("Show throws", nil, function(rig)
			rig.Loading.Show = function()
				error("boom")
			end
		end)
		scenario("module unusable", nil, function(rig)
			rig.Loading.Show = nil
		end)
		scenario("dead frame loop", {
			Driver = {
				Connect = function()
					error("no frame loop")
				end,
				Viewport = function()
					return Loader.roblox.Vector2.new(860, 400)
				end,
				Delay = function() end,
			},
		})

		-- a second activation while a screen runs: no side effects; PRACTICE during PLAY's fade-in only asks
		local rig = controllerRig(Loader)
		local ok, err = pcall(function()
			rig.spawn()
			rig.UI.Open("Title")
			rig.UI.Play()
			local handle = rig.Loading.Active()
			T.ok(handle ~= nil, "PLAY's loading screen is up")
			T.eq(rig.music(), "Menu@- Silence@1.2", "the menu track fades out into the black")
			rig.run(0.1)
			rig.UI.Play()
			T.eq(rig.Loading.Active(), handle, "a second PLAY starts nothing")
			T.eq(rig.music(), "Menu@- Silence@1.2", "a second PLAY changes no music")
			rig.UI.Practice("Human")
			T.eq(#rig.state.requests, 1, "PRACTICE during PLAY's fade-in still asks for the round")
			T.eq(rig.music(), "Menu@- Silence@1.2", "and changes no music")
			local h = rig.finish()
			T.ok(h.Done, "PLAY's screen ends")
			T.eq(rig.sound.override, nil, "automatic music after it")
			T.eq(rig.music(), "Menu@- Silence@1.2 auto@1.5", "Menu -> silence -> lobby")
			-- PRACTICE twice: the second press does nothing
			rig.UI.Practice("Human")
			rig.run(0.5)
			rig.UI.Practice("Human")
			rig.run(0.5)
			T.eq(#rig.state.requests, 2, "one more request only")
			rig.state.phase = "Intro"
			rig.finish()
			T.eq(rig.sound.override, nil, "automatic music (the round's) after practice loading")
			T.eq(rig.Loading.Active(), nil, "nothing left running")
		end)
		rig.done()
		if not ok then
			error(err, 0)
		end
	end,

	-- the owner's main flow: the first PLAY darkens, the head spins, the Menu track fades out into the black and the
	-- lobby track starts 2 s before the light (4 s minimum); it also waits for a character that is still spawning
	controller_first_play_keeps_the_owner_flow = function(T, Loader)
		local rig = controllerRig(Loader)
		local ok, err = pcall(function()
			rig.spawn()
			rig.UI.Open("Title")
			rig.UI.Play()
			T.eq(rig.music(), "Menu@- Silence@1.2", "the Menu track fades out into the black at once")
			local handle = rig.Loading.Active()
			T.ok(handle ~= nil and not handle.View.Plain, "the full loading screen (head + text)")
			T.eq(rig.sound.plays[1], "PlayTransition", "the transition sound plays")
			rig.run(0.3)
			T.eq(rig.UI.IsOpen("Title"), true, "the Title stays until the screen is black")
			rig.run(0.1)
			T.eq(rig.UI.IsOpen(), false, "closed under the black")
			local _, doneAt = rig.finish()
			local cue = rig.sound.overrides[3]
			T.ok(cue ~= nil and cue.key == nil and cue.fade == 1.5, "the lobby track fades in (" .. rig.music() .. ")")
			T.near(cue and cue.at or -1, 2, 2 * DT, "2 s before the light")
			T.near(handle.Sequence.OutAt, 4, 2 * DT, "the light comes back at 4 s")
			T.near(doneAt, 4.55, 3 * DT, "done at ~4.55 s")
			T.eq(#rig.sound.overrides, 3, "no other music change")
			T.eq(#rig.sound.ducks, 0, "the music hand-over is not ducked")
		end)
		rig.done()
		if not ok then
			error(err, 0)
		end
		-- the character is still spawning: the black waits for it (at 4 s at the earliest, 7 s at the latest); the
		-- lobby track comes with the character (or 2 s before the cap)
		for _, case in { { 3, 3, 4 }, { 5.5, 5, 5.8 }, { math.huge, 5, 7 } } do
			local spawnAt, cueAt, outAt = case[1], case[2], case[3]
			local r = controllerRig(Loader)
			local okCase, errCase = pcall(function()
				r.UI.Open("Title")
				r.UI.Play()
				local handle = r.Loading.Active()
				r.finish(20, function(now)
					if now >= spawnAt and r.state.character == nil then
						r.spawn()
					end
				end)
				local label = ("spawn at %s s"):format(tostring(spawnAt))
				local cue = r.sound.overrides[3]
				T.ok(cue ~= nil and cue.key == nil, label .. ": the lobby track fades in (" .. r.music() .. ")")
				T.near(cue and cue.at or -1, cueAt, 2 * DT, label .. ": cue time")
				T.near(handle.Sequence.OutAt, outAt, 2 * DT, label .. ": reveal time")
				T.eq(r.sound.override, nil, label .. ": automatic music at the end")
			end)
			r.done()
			if not okCase then
				error(errCase, 0)
			end
		end
	end,

	-- review fix: on phones PLAY is the only way back from a reopened Title - later PLAYs are a short dip
	controller_later_play_is_a_quick_dip = function(T, Loader)
		local rig = controllerRig(Loader)
		local ok, err = pcall(function()
			rig.spawn()
			rig.UI.Open("Title")
			rig.UI.Play()
			rig.finish()
			-- the lobby MENU button reopens the Title, PLAY goes back
			rig.UI.Open("Title")
			T.eq(rig.sound.override, "Menu", "the reopened Title plays the Menu track")
			local before = #rig.sound.overrides
			local plays = #rig.sound.plays
			local pressedAt = rig.now
			rig.UI.Play()
			local handle = rig.Loading.Active()
			T.ok(handle ~= nil and handle.View.Plain, "a plain dip (no head, no LOADING)")
			T.eq(rig.music(before + 1), "auto@1", "Menu -> lobby crossfade (1 s) right at the press, no Silence")
			T.eq(#rig.sound.plays, plays, "no transition sound for the dip")
			local contentShown = false
			local closedAt
			local _, doneAt = rig.finish(5, function(now)
				contentShown = contentShown or handle.View.Content.Visible
				if closedAt == nil and not rig.UI.IsOpen() then
					closedAt = now
				end
			end)
			T.ok(closedAt ~= nil and closedAt - pressedAt <= 0.25, "the Title closes under the black (~0.2 s)")
			T.ok(doneAt - pressedAt <= 0.65, ("the dip is over in ~0.6 s (%.2f)"):format(doneAt - pressedAt))
			T.eq(contentShown, false, "no head / text during the dip")
			T.eq(rig.music(before + 1), "auto@1", "no other music change")
			T.eq(#rig.sound.ducks, 0, "nothing ducked")
			-- the character is gone (respawning): the full screen again
			rig.state.character = nil
			rig.UI.Open("Title")
			before = #rig.sound.overrides
			rig.UI.Play()
			T.eq(rig.music(before + 1), "Silence@1.2", "no character: the full loading screen")
			local full = rig.Loading.Active()
			T.ok(full ~= nil and not full.View.Plain, "with the head")
			local spawnAt = rig.now + 1
			rig.finish(20, function(now)
				if now >= spawnAt and rig.state.character == nil then
					rig.spawn()
				end
			end)
			T.near(full.Sequence.OutAt, 4, 2 * DT, "revealed at 4 s (the character came at 1 s)")
			T.eq(rig.sound.override, nil, "automatic music after it")
		end)
		rig.done()
		if not ok then
			error(err, 0)
		end
		-- leaving the join Title with the Menu key (no PLAY) counts as entering too
		local r = controllerRig(Loader)
		local okKey, errKey = pcall(function()
			r.spawn()
			r.UI.Open("Title")
			r.UI.Close()
			T.eq(r.sound.override, nil, "the Menu key closes the Title (automatic music)")
			r.UI.Open("Title")
			r.UI.Play()
			local handle = r.Loading.Active()
			T.ok(handle ~= nil and handle.View.Plain, "PLAY from the reopened Title is a dip")
			r.finish()
		end)
		r.done()
		if not okKey then
			error(errKey, 0)
		end
	end,

	-- review fix: PRACTICE reveals as soon as the round leaves "Waiting": its Intro (VS splash, 3-2-1, flyover) is seen
	controller_practice_reveals_the_intro = function(T, Loader)
		local RoundRules = Loader.require("ReplicatedStorage.Shared.Round.RoundRules")
		local introLength = RoundRules.PhaseDuration("Intro", true)
		for _, introAt in { 0.5, 1.2, 3.5 } do
			local rig = controllerRig(Loader)
			local ok, err = pcall(function()
				local label = ("Intro at %.1f s"):format(introAt)
				rig.spawn()
				rig.UI.Open("Title")
				rig.UI.Practice("Human")
				T.eq(rig.music(), "Menu@- Silence@1.2", label .. ": the Menu track fades out into the black")
				local handle = rig.Loading.Active()
				rig.run(0.3)
				T.eq(#rig.state.requests, 0, label .. ": no request before the screen is black")
				rig.run(0.1)
				T.eq(#rig.state.requests, 1, label .. ": request sent once black")
				T.eq(rig.state.requests[1].data.side, "Human", label .. ": side")
				T.eq(rig.UI.IsOpen(), false, label .. ": menus closed")
				local _, doneAt = rig.finish(20, function(now)
					if now >= introAt and rig.state.phase == "Waiting" then
						rig.state.phase = "Intro"
						rig.state.role = "Human"
					end
				end)
				local cue = rig.sound.overrides[3]
				T.near(cue and cue.at or -1, introAt, 2 * DT, label .. ": the round's track starts with the round")
				local expected = math.max(1.2, introAt + 0.3) + 0.55
				T.ok(doneAt <= expected + 3 * DT, ("%s: revealed by %.2f s (got %.2f)"):format(label, expected, doneAt))
				local seen = introLength - (doneAt - introAt)
				T.ok(seen >= 2.5, ("%s: %.2f s of the %.0f s Intro fully visible"):format(label, seen, introLength))
				T.eq(rig.sound.override, nil, label .. ": automatic music (the round's track)")
				T.eq(handle.Done, true, label .. ": done")
				T.eq(rig.state.Notify:Count(), 0, label .. ": the refusal listener is gone")
				T.eq(#rig.state.requests, 1, label .. ": one request")
			end)
			rig.done()
			if not ok then
				error(err, 0)
			end
		end
		-- the round never starts: the 7 s cap (the lobby track 2 s before it)
		local rig = controllerRig(Loader)
		local ok, err = pcall(function()
			rig.spawn()
			rig.UI.Practice("Human")
			local handle = rig.Loading.Active()
			rig.finish(20)
			T.near(handle.Sequence.OutAt, 7, 2 * DT, "cap at 7 s")
			local cue = rig.sound.overrides[2]
			T.near(cue and cue.at or -1, 5, 2 * DT, "lobby track 2 s before the cap")
			T.eq(rig.sound.override, nil, "automatic music")
		end)
		rig.done()
		if not ok then
			error(err, 0)
		end
	end,

	-- review fix: a refused PRACTICE ends the black at once (its toast is seen); during a round no loading screen
	controller_practice_refused_or_round_running = function(T, Loader)
		local function refused(key, stall)
			local rig = controllerRig(Loader)
			local ok, err = pcall(function()
				rig.spawn()
				rig.UI.Open("Title")
				rig.UI.Practice("Human")
				local handle = rig.Loading.Active()
				local refusedAt
				local _, doneAt = rig.finish(20, function(now)
					if refusedAt == nil and now >= 0.5 then
						refusedAt = now
						rig.state.Notify:Fire(key, nil, "Warning")
						rig.now += stall -- a stalled frame loop (app in the background) keeps the black up
					end
				end)
				local label = key .. (if stall > 0 then " + stall" else "")
				T.ok(handle.Done, label .. ": the black ends")
				T.ok(
					doneAt - refusedAt - stall <= 0.55 + 3 * DT,
					("%s: right after the refusal (%.2f s)"):format(label, doneAt - refusedAt - stall)
				)
				T.eq(rig.state.Notify:Count(), 0, label .. ": listener disconnected")
				T.eq(rig.sound.override, nil, label .. ": automatic music (lobby)")
				T.eq(rig.music(), "Menu@- Silence@1.2 auto@1.5", label .. ": Menu -> silence -> lobby")
				if stall > 0 then
					T.eq(#rig.root.toasts, 1, label .. ": the reason is toasted again after the late reveal")
					local toast = rig.root.toasts[1]
					T.eq(toast and toast.text, rig.Strings.L(key), label .. ": the server's reason")
					T.eq(toast and toast.kind, "Warning", label .. ": as a warning")
				else
					T.eq(#rig.root.toasts, 0, label .. ": no duplicate of the server's toast (seen right away)")
				end
			end)
			rig.done()
			if not ok then
				error(err, 0)
			end
		end
		refused("round.practice.busy", 0)
		refused("round.practice.disabled", 0)
		refused("prog.err.rateLimited", 3)

		-- other notifications (the server's "starting...") keep the black until the round comes
		local rig = controllerRig(Loader)
		local ok, err = pcall(function()
			rig.spawn()
			rig.UI.Practice("Human")
			rig.run(0.5)
			rig.state.Notify:Fire("round.practice.queued", nil, "Info")
			rig.run(0.5)
			T.ok(rig.Loading.Active() ~= nil, "still black after 'Practice is starting...'")
			local _, doneAt = rig.finish(20, function(now)
				if now >= 1.5 then
					rig.state.phase = "Intro"
				end
			end)
			T.near(doneAt, 1.5 + 0.3 + 0.55, 3 * DT, "revealed with the Intro")
		end)
		rig.done()
		if not ok then
			error(err, 0)
		end

		-- a round is running (Intermission / match / Ending): no loading screen, the request goes out at once
		for _, phaseName in { "Intermission", "Round", "Ending" } do
			local r = controllerRig(Loader)
			local okPhase, errPhase = pcall(function()
				r.spawn()
				r.UI.Open("Title")
				r.state.phase = phaseName
				r.UI.Practice("Human")
				T.eq(r.Loading.Active(), nil, phaseName .. ": no loading screen")
				T.eq(guisUnder(r.parent), 0, phaseName .. ": nothing parented")
				T.eq(#r.state.requests, 1, phaseName .. ": the request goes out at once")
				T.eq(r.UI.IsOpen("Title"), true, phaseName .. ": the menu stays")
				T.eq(r.music(), "Menu@-", phaseName .. ": music untouched")
			end)
			r.done()
			if not okPhase then
				error(errPhase, 0)
			end
		end
	end,
})
