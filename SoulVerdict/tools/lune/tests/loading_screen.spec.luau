--!nocheck
-- PLAY / PRACTICE loading screen: the owner's pixel Sans head data (Shared/PixelArt/SansHead: 37 rows x 40 cells of
-- '#', '.', ' ', cell counts pinned, run merging and the layered seam-proof runs reproduce the sprite exactly, the
-- mirrored variant), the overlay (Client/UI/Overlays/Loading) built offline in Turn / Wheel / Still at phone and
-- desktop sizes (own full-screen ScreenGui above every layer, pixel-exact sprite at rest, text inside the screen,
-- ru "ЗАГРУЗКА" in the pixel font), the coin-turn / wheel poses and the dot animation, the pure sequence (minimum
-- time, Until + settle, practice cap, skip, hitches) and the runtime driver with a fake frame loop / sound /
-- scheduler (OnCovered and OnDone exactly once, no stacking, sound + ducking, errors and the failsafe never leave
-- the black screen up). Also the Strings key, the Audio entry and the UIController fallback path.
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
		if h ~= p or run.x ~= math.floor(run.x) or run.length ~= math.floor(run.length) or run.y ~= math.floor(run.y) then
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
		sameRows(T, paint(SansHead.LayeredRuns(SansHead.MirroredRows), 40, 37, false), SansHead.MirroredRows, "mirrored layered runs")
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
				T.eq(view.Head.ClassName, if mode == "Wheel" then "CanvasGroup" else "Frame", label .. " head container")
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
					T.ok(m.Pixel >= 5 and m.Pixel <= 6, label .. " ~5-6 px per sprite pixel on a phone (" .. m.Pixel .. ")")
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
			local view = Loading.Preview(Themes.Get("Classic"), roblox.Vector2.new(size[1], size[2]), { Mode = "Turn", Spin = 0 })
			local m = view.Metrics
			T.eq(view.Head.Size, roblox.UDim2.fromOffset(m.Grid, m.Grid), label .. " head container at rest")
			T.eq(view.Head.Position, roblox.UDim2.fromOffset(m.Left, m.Top), label .. " head container position")
			T.eq(m.Left + 12 * m.Pixel, m.CenterX - 20 * m.Pixel, label .. " sprite centred")
			T.eq(view.Normal.Visible, true, label .. " front sprite shown")
			T.eq(view.Mirrored.Visible, false, label .. " back sprite hidden")
			sameRows(T, readSprite(T, view.Normal, m, Loading, label), SansHead.Rows, label .. " front sprite on screen")
			sameRows(T, readSprite(T, view.Mirrored, m, Loading, label), SansHead.MirroredRows, label .. " back sprite on screen")
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
			T.near(wheel.Head.Rotation, Loading.WheelAngle(t), 1e-6, "wheel angle at " .. t)
			T.eq(wheel.Head.Size, roblox.UDim2.fromOffset(wheel.Metrics.Grid, wheel.Metrics.Grid), "wheel keeps its size")
			T.eq(wheel.Normal.Visible, true, "wheel sprite visible")
		end
		T.near(Loading.WheelAngle(Loading.WheelPeriod / 4), 90, 1e-6, "a quarter turn = 90 degrees")
		wheel.Destroy()
		-- still (Reduced Motion)
		local still = Loading.Build(nil, { Viewport = roblox.Vector2.new(860, 400), Mode = "Still" })
		still.Pose(0.77)
		T.eq(still.Head.Position, roblox.UDim2.fromOffset(still.Metrics.Left, still.Metrics.Top), "still head does not move")
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
			T.ok(string.find(text, "^<font transparency=\"1\">%.%.%.</font>LOADING") ~= nil, n .. " dots: invisible left pad")
		end
		T.ok(string.find(Loading.Text("LOADING", 3), "LOADING...", 1, true) ~= nil, "three visible dots")
		T.ok(string.find(Loading.Text("A<B", 0), "A&lt;B", 1, true) ~= nil, "RichText escaped")
		T.ok(string.find(Loading.Text("X", 2, roblox.Color3.fromRGB(255, 24, 44)), '<font color="#FF182C">..</font>', 1, true) ~= nil, "tinted dots")
		-- language + theme
		T.eq(Strings.L("loading.title"), "LOADING", "en string")
		Strings.SetLanguage("ru")
		T.eq(Strings.L("loading.title"), "ЗАГРУЗКА", "ru string")
		local ru = Loading.Build(Themes.Get("Fell"), { Viewport = roblox.Vector2.new(860, 400) })
		T.ok(string.find(ru.Label.Text, "ЗАГРУЗКА", 1, true) ~= nil, "ru label")
		T.eq(ru.Label.FontFace, Themes.Font(Themes.Get("Classic"), "Display", "ru"), "ru keeps the (Cyrillic) pixel font")
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
		while seq.Phase ~= "Done" and seq.Time < 20 do
			local phaseBefore = seq.Phase
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
			if phaseBefore == "Hold" and seq.Phase == "FadeOut" then
				outAt = seq.Time
			end
			maxContent = math.max(maxContent, seq.Content)
			if seq.Phase == "Hold" then
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

	sequence_until_cap_skip_hitches = function(T, Loader)
		local Loading = setup(Loader)
		local timing = Loading.Timing
		local function runUntil(readyFrom, opts)
			local seq = Loading.NewSequence(opts)
			local outAt
			while seq.Phase ~= "Done" and seq.Time < 30 do
				local before = seq.Phase
				seq.Step(DT, readyFrom ~= nil and seq.Time >= readyFrom)
				if before == "Hold" and seq.Phase == "FadeOut" then
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
		T.near(outLate, 3 + timing.Settle, 2 * DT, "ready at 3 s -> released after the settle")
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
		-- skip: fade-out as soon as the screen is black
		local seq = Loading.NewSequence()
		seq.Skip()
		local out
		while seq.Phase ~= "Done" and seq.Time < 5 do
			local before = seq.Phase
			seq.Step(DT, false)
			if before == "Hold" and seq.Phase == "FadeOut" then
				out = seq.Time
			end
		end
		T.near(out, timing.FadeIn + DT, 2 * DT, "Skip releases right after the screen is black")
		-- hitches: a huge dt never skips a whole phase; NaN / negative dt do nothing
		local h = Loading.NewSequence()
		h.Step(10, true)
		T.eq(h.Phase, "FadeIn", "one huge step stays in the fade-in (clamped)")
		local covered = h.Step(10, true)
		T.ok(covered and h.Phase == "Hold", "the next one covers")
		local t0 = h.Time
		h.Step(0 / 0, true)
		h.Step(-5, true)
		T.eq(h.Time, t0, "NaN / negative dt ignored")
		local steps = 0
		while h.Phase ~= "Done" and steps < 1000 do
			h.Step(10, true)
			steps += 1
		end
		T.eq(h.Phase, "Done", "finishes with huge steps too")
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
		T.near(elapsed, Loading.Timing.MinVisible + Loading.Timing.ContentOut + Loading.Timing.FadeOut, 4 * DT, "~2.75 s in total")
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
			local before = h2.Sequence.Phase
			d2.step(DT)
			clock += DT
			if before == "Hold" and h2.Sequence.Phase == "FadeOut" then
				outAt = clock
			end
		end
		T.near(outAt, 3 + Loading.Timing.Settle, 3 * DT, "released after the round started + settle")
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
		T.ok(t7 < Loading.Timing.FadeIn + Loading.Timing.ContentOut + Loading.Timing.FadeOut + 0.1, "Finish skips the hold (" .. t7 .. ")")
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
			T.eq(Audio.Candidates(Loading.SoundName)[1], "rbxassetid://120586834968743", "the owner's id")
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
})
