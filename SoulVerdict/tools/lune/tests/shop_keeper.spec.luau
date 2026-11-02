--!nocheck
-- Sleepy Sans, the shopkeeper of the Shop screen (owner's request "zzz... oh hi kid, what you want?"):
--   * the pixel art (Shared/PixelArt/SansShopkeeper): well-formed layers inside the 72 x 72 scene, the awake head is
--     the owner's sprite, the sleeping head closes BOTH eyes (mirror-symmetric arcs, only the eye area changes),
--     head parts / merged rects reproduce the rows exactly, readable Z letters on a path inside the scene;
--   * the pure sequence (Screens/ShopKeeper): asleep ~0.8 s (bob, rising + fading Z z z) -> wakes (sprite swap +
--     tiny hop) -> types shop.keeper.greet letter by letter with punctuation pauses -> idle; Reduced Motion (no bob,
--     no hop, standing Z letters); Say() wakes him early / starts a new line;
--   * the builder: every theme x phone / desktop x en / ru, whole screen pixels per cell, Snap puts the scene on a
--     whole pixel, Sans's blips (SansTextBlip, first letter voiced), Destroy;
--   * the Shop screen: the keeper column + the goods fit the body side by side (goods keep their minimum width),
--     no column when there is no room (portrait) or deps.Keeper = false, and the purchase lines: not enough G ->
--     shop.keeper.poor (no request, no pop-up), a confirmed purchase (Notify or the next profile) -> thanks once,
--     the server's "prog.err.gold" -> poor; without the keeper the old "not enough G" pop-up stays.
local SPRITE = "src/shared/PixelArt/SansShopkeeper"
local HEAD = "src/shared/PixelArt/SansHead"
local KEEPER = "src/client/UI/Screens/ShopKeeper"
local SHOP = "src/client/UI/Screens/Shop"

-- client-side suite: put the loader flags back even when a test fails (test hygiene)
local function restoringFlags(tests)
	for name, fn in tests do
		tests[name] = function(T, Loader)
			local isServer, quiet = Loader.isServer, Loader.quietWarnings
			local ok, err = pcall(fn, T, Loader)
			Loader.isServer, Loader.quietWarnings = isServer, quiet
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
	return Strings,
		Loader.requirePath("src/client/UI/Themes"),
		Loader.requirePath("src/client/UI/UIRoot"),
		Loader.roblox
end

-- paints merged rects into a w x h grid; nil + message when a cell is painted twice or out of bounds
local function paintRects(rects, w, h)
	local grid = {}
	for y = 1, h do
		grid[y] = table.create(w, " ")
	end
	for _, r in rects do
		for y = r.y + 1, r.y + r.h do
			for x = r.x + 1, r.x + r.w do
				local row = grid[y]
				if row == nil or x < 1 or x > w then
					return nil, ("rect out of bounds at %d,%d"):format(r.x, r.y)
				end
				if row[x] ~= " " then
					return nil, ("cell %d,%d painted twice"):format(x - 1, y - 1)
				end
				row[x] = r.color
			end
		end
	end
	local out = {}
	for y = 1, h do
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

local function at(rows, x, y)
	return string.sub(rows[y + 1], x + 1, x + 1)
end

-- the UIRoot layout the way it runs: CoreUISafeInsets below the Roblox top bar (58 px) + notch insets
local function deviceLayout(UIRoot, roblox, w, h, notch)
	local side = notch or 0
	local usable = roblox.Vector2.new(w - side * 2, h - 58)
	return UIRoot.ComputeLayout(usable, { Left = side, Top = 58, Right = side, Bottom = 0 })
end

local function fakeSignal()
	local handlers = {}
	local sig = {}
	function sig:Connect(fn)
		table.insert(handlers, fn)
		return { Connected = true, Disconnect = function() end }
	end
	function sig:Fire(...)
		for _, fn in handlers do
			fn(...)
		end
	end
	return sig
end

local function mockState(profile)
	local requests = {}
	local state = {
		ProfileChanged = fakeSignal(),
		SettingChanged = fakeSignal(),
		RoundChanged = fakeSignal(),
		Notify = fakeSignal(),
	}
	function state.Profile()
		return profile
	end
	function state.Round()
		return { Phase = "Waiting", PhaseEndsAt = 0 }
	end
	function state.Now()
		return 1700000000
	end
	function state.Request(action, data)
		table.insert(requests, { action, data })
	end
	function state.Setting()
		return nil
	end
	return state, requests
end

-- a skin of a kit the profile owns that the profile does not own yet (and is for sale)
local function skinForSale(Common, Kits, profile)
	for _, kit in Kits.All() do
		if Common.KitOwned(profile, kit) then
			for _, skin in kit.Skins do
				if (skin.Price or 0) > 0 and skin.Mastery == nil and not Common.SkinOwned(profile, kit, skin) then
					return kit, skin
				end
			end
		end
	end
	return nil, nil
end

return restoringFlags({
	-- pixel art ---------------------------------------------------------------------------------------------------
	spriteIsWellFormed = function(T, Loader)
		setup(Loader)
		local Sprite = Loader.requirePath(SPRITE)
		local SansHead = Loader.requirePath(HEAD)
		local problems = Sprite.Validate()
		T.eq(#problems, 0, "Validate: " .. table.concat(problems, "; "))
		T.eq(Sprite.Width, 72, "scene width")
		T.eq(Sprite.Height, 72, "scene height")
		for _, name in { "Booth", "Body", "Head", "Counter", "Arms", "Props" } do
			T.ok(table.find(Sprite.Order, name) ~= nil, "drawing order has " .. name)
		end
		-- the awake head is exactly the owner's sprite
		sameRows(T, Sprite.AwakeHead, SansHead.Rows, "awake head = owner's sprite")
		-- every palette key is a Color3 and the Z letters use 'z' only
		for key, color in Sprite.Colors do
			T.ok(typeof(color) == "Color3", "colour " .. key)
		end
		for name, glyph in Sprite.Z do
			T.ok(#glyph >= 4 and #glyph <= Sprite.ZSize, "Z." .. name .. " size (a Z needs 4 cells to read)")
			for _, row in glyph do
				T.ok(string.match(row, "^[z ]+$") ~= nil, "Z." .. name .. " cells")
			end
		end
		T.ok(#Sprite.Z.Small < #Sprite.Z.Medium and #Sprite.Z.Medium < #Sprite.Z.Big, "Z letters grow")
		-- the Z path rises beside the head (right of the awake / asleep head, left of the right post)
		T.ok(Sprite.ZEnd.y < Sprite.ZStart.y, "Z letters rise")
		T.ok(Sprite.ZStart.x >= Sprite.HeadX + SansHead.Width - 1, "Z path starts beside the head")
		T.ok(Sprite.ZEnd.x + Sprite.ZSize <= Sprite.Width - 6, "Z path stays left of the right post")
		-- the counter front starts where the doc says (the box may cover it on phones)
		local counter = Sprite.Layers.Counter
		T.ok(Sprite.CounterFrontY > counter.Y and Sprite.CounterFrontY < counter.Y + #counter.Rows, "counter front row")
	end,

	sleepingHeadClosesBothEyes = function(T, Loader)
		setup(Loader)
		local Sprite = Loader.requirePath(SPRITE)
		local awake, sleep = Sprite.AwakeHead, Sprite.SleepHead
		T.eq(#sleep, 37, "37 rows")
		-- the open left eye (black socket with a white pupil) is gone ...
		T.eq(at(awake, 10, 16), ".", "awake: the pupil")
		T.eq(at(awake, 9, 16), "#", "awake: the socket around it")
		T.eq(at(sleep, 9, 16), ".", "asleep: no socket")
		T.eq(at(sleep, 10, 14), ".", "asleep: the socket's top cleared")
		-- ... and both eyes are closed arcs, mirror images of each other (x -> 40 - x)
		local mirrored, arcCells = 0, 0
		for y = 12, 17 do
			for x = 4, 17 do
				if at(sleep, x, y) == "#" then
					arcCells += 1
				end
				if at(sleep, x, y) == at(sleep, 40 - x, y) then
					mirrored += 1
				end
			end
		end
		T.eq(mirrored, 6 * 14, "the eye area is mirror-symmetric")
		T.ok(arcCells >= 6, "the left closed arc is drawn: " .. arcCells)
		-- only the eye area changed (rows 12..19, left half); the grin, the nose and the outline are the owner's
		for y = 0, 36 do
			for x = 0, 39 do
				if at(awake, x, y) ~= at(sleep, x, y) then
					T.ok(y >= 12 and y <= 19 and x <= 20, ("changed cell %d,%d is in the eye area"):format(x, y))
				end
			end
		end
		-- SleepingHead is pure (the owner's rows are untouched)
		local again = Sprite.SleepingHead(awake)
		sameRows(T, again, sleep, "deterministic derivation")
	end,

	headPartsAndRectsReproduceTheRows = function(T, Loader)
		setup(Loader)
		local Sprite = Loader.requirePath(SPRITE)
		local parts = Sprite.HeadParts()
		-- base + overlay = each head; the overlays only hold the differing cells
		for _, pair in { { "Awake", Sprite.AwakeHead }, { "Asleep", Sprite.SleepHead } } do
			local overlay = parts[pair[1]]
			local merged = {}
			for y = 1, 37 do
				local row = {}
				for x = 1, 40 do
					local o = string.sub(overlay[y], x, x)
					row[x] = if o ~= " " then o else string.sub(parts.Base[y], x, x)
					if o ~= " " then
						T.eq(string.sub(parts.Base[y], x, x), " ", "overlay cell not in the base")
					end
				end
				merged[y] = table.concat(row)
			end
			sameRows(T, merged, pair[2], pair[1] .. " = base + overlay")
		end
		-- merged rects paint every layer / head / Z glyph exactly, each cell once
		local function check(label, rows)
			local w = #rows[1]
			local painted, err = paintRects(Sprite.Rects(rows), w, #rows)
			T.ok(painted ~= nil, label .. ": " .. tostring(err))
			if painted then
				sameRows(T, painted, rows, label)
			end
		end
		for name, layer in Sprite.Layers do
			check(name, layer.Rows)
		end
		check("AwakeHead", Sprite.AwakeHead)
		check("SleepHead", Sprite.SleepHead)
		check("Base", parts.Base)
		for name, glyph in Sprite.Z do
			check("Z." .. name, glyph)
		end
		-- fewer frames than runs (the vertical merge pays off on the booth posts / counter)
		T.ok(#Sprite.Rects(Sprite.Layers.Booth.Rows) < #Sprite.Runs(Sprite.Layers.Booth.Rows), "rects merge rows")
		-- Compose: the head sits HeadAsleepY - HeadAwakeY cells lower asleep
		local awake, asleep = Sprite.Compose("Awake"), Sprite.Compose("Asleep")
		T.eq(#awake, 72, "composed rows")
		-- (the head is drawn over the booth, under the counter / arms: compare a row of the face)
		local row = 16
		local face = Sprite.AwakeHead[row + 1]
		local sleepFace = Sprite.SleepHead[row + 1]
		T.eq(
			string.sub(awake[Sprite.HeadAwakeY + row + 1], Sprite.HeadX + 1, Sprite.HeadX + 40),
			face,
			"awake face row"
		)
		T.eq(
			string.sub(asleep[Sprite.HeadAsleepY + row + 1], Sprite.HeadX + 1, Sprite.HeadX + 40),
			sleepFace,
			"asleep face row"
		)
		T.ok(Sprite.HeadAsleepY > Sprite.HeadAwakeY, "he slumps when asleep")
	end,

	-- the sequence ------------------------------------------------------------------------------------------------
	wakeUpSequenceTiming = function(T, Loader)
		local Strings = setup(Loader)
		local SK = Loader.requirePath(KEEPER)
		local Sprite = Loader.requirePath(SPRITE)
		local tm = SK.Timing
		T.near(tm.Sleep, 0.8, 0.15, "asleep for about 0.8 s")
		local greet = Strings.L("shop.keeper.greet")
		local tl = SK.NewTimeline(greet, Strings.L("shop.keeper.zzz"))
		T.near(tl.WakeAt, tm.Sleep, 1e-9, "wakes at Sleep")
		T.near(tl.LineAt, tm.Sleep + tm.Hop + tm.Beat, 1e-9, "the greeting starts after the hop + a beat")
		-- asleep: sleeping head, slumped, Z letters, the dim "Zzz..." in the box
		local p = tl.PoseAt(0.1)
		T.eq(p.State, "Asleep", "asleep at 0.1 s")
		T.eq(p.Head, "Asleep", "eyes closed")
		T.ok(p.HeadY >= Sprite.HeadAsleepY, "slumped")
		T.ok(#p.Z >= 1 and #p.Z <= 3, "Z letters in flight: " .. #p.Z)
		T.eq(p.Text, Strings.L("shop.keeper.zzz"), "box shows Zzz...")
		T.ok(p.Dim, "the placeholder is dim")
		-- the head bobs while he sleeps (whole cells, 1 cell)
		local ys = {}
		for i = 0, 7 do
			ys[tl.PoseAt(i * 0.1).HeadY] = true
		end
		T.ok(ys[Sprite.HeadAsleepY] and ys[Sprite.HeadAsleepY + 1], "bob: both heights")
		-- Z letters rise and fade
		local z0 = tl.PoseAt(0.2).Z
		local z1 = tl.PoseAt(0.3).Z
		local function lowest(list)
			local best = nil
			for _, z in list do
				if best == nil or z.Y > best.Y then
					best = z
				end
			end
			return best
		end
		T.ok(lowest(z1) ~= nil and lowest(z0) ~= nil, "letters present")
		for _, z in z0 do
			T.ok(z.Transparency >= 0 and z.Transparency <= 1, "transparency in range")
			T.ok(z.Glyph == "Small" or z.Glyph == "Medium" or z.Glyph == "Big", "glyph name")
		end
		-- waking: awake sprite + a tiny hop above the awake height
		local minY = math.huge
		local t = tl.WakeAt
		while t < tl.WakeAt + tm.Hop do
			local w = tl.PoseAt(t)
			T.eq(w.State, "Waking", "waking at " .. t)
			T.eq(w.Head, "Awake", "eyes open while waking")
			minY = math.min(minY, w.HeadY)
			T.eq(#w.Z, 0, "no Z once awake")
			t += 0.02
		end
		T.ok(minY < Sprite.HeadAwakeY, "the hop goes above the awake height")
		T.ok(Sprite.HeadAwakeY - minY <= tm.HopHeight, "a tiny hop")
		-- talking: the greeting appears letter by letter
		local times, graphemes = SK.Schedule(greet)
		T.eq(#times, #graphemes, "one time per grapheme")
		for i = 2, #times do
			T.ok(times[i] > times[i - 1], "letters in order")
		end
		local p1 = tl.PoseAt(tl.LineAt + 0.001)
		T.eq(p1.State, "Talking", "talking")
		T.eq(p1.Text, greet, "the greeting")
		T.eq(p1.Shown, 1, "first letter at once")
		local mid = tl.PoseAt(tl.LineAt + 0.5)
		T.ok(mid.Shown > 1 and mid.Shown < #graphemes, "half-way through: " .. mid.Shown)
		-- punctuation pauses: "zzz..." waits longer after the dots than between letters
		local dotsEnd = string.find(greet, "%.%.%. ")
		if dotsEnd then
			local gap = times[dotsEnd + 3] - times[dotsEnd + 2]
			T.ok(gap >= tm.Pause - 1e-9, "pause after ...")
		end
		local done = tl.PoseAt(tl.EndAt() + 0.01, nil, true)
		T.eq(done.State, "Idle", "idle after the line")
		T.eq(done.Shown, -1, "the whole line shown")
		T.ok(tl.EndAt() > tl.LineAt + 1 and tl.EndAt() < 6, "the greeting takes a few seconds: " .. tl.EndAt())
		-- idle blinks (eyes closed for a moment), never while noBlink
		local blinked = false
		for i = 0, 200 do
			local q = tl.PoseAt(tl.EndAt() + i * 0.05)
			if q.Head == "Asleep" then
				blinked = true
			end
			T.eq(tl.PoseAt(tl.EndAt() + i * 0.05, nil, true).Head, "Awake", "noBlink")
		end
		T.ok(blinked, "he blinks when idle")
	end,

	reducedMotionAndSay = function(T, Loader)
		local Strings = setup(Loader)
		local SK = Loader.requirePath(KEEPER)
		local Sprite = Loader.requirePath(SPRITE)
		local tl = SK.NewTimeline(Strings.L("shop.keeper.greet"), Strings.L("shop.keeper.zzz"))
		-- Reduced Motion: no bob, no hop, standing Z letters
		local first = tl.PoseAt(0.05, true)
		for i = 0, 7 do
			local p = tl.PoseAt(i * 0.1, true)
			T.eq(p.HeadY, Sprite.HeadAsleepY, "no bob")
			T.eq(#p.Z, 3, "three standing letters")
			for k, z in p.Z do
				T.eq(z.X, first.Z[k].X, "Z stands still (x)")
				T.eq(z.Y, first.Z[k].Y, "Z stands still (y)")
			end
		end
		local t = tl.WakeAt
		while t < tl.WakeAt + SK.Timing.Hop do
			T.eq(tl.PoseAt(t, true).HeadY, Sprite.HeadAwakeY, "no hop")
			t += 0.02
		end
		-- Say while idle: the new line starts now
		local idle = tl.EndAt() + 1
		tl.Say(Strings.L("shop.keeper.thanks"), idle)
		T.near(tl.LineAt, idle, 1e-9, "thanks starts at once")
		T.eq(tl.PoseAt(idle + 0.001).Text, Strings.L("shop.keeper.thanks"), "thanks typed")
		-- Say while he still sleeps: he wakes first, then says it (the greeting is skipped)
		local tl2 = SK.NewTimeline(Strings.L("shop.keeper.greet"), Strings.L("shop.keeper.zzz"))
		tl2.Say(Strings.L("shop.keeper.poor"), 0.3)
		T.near(tl2.WakeAt, 0.3, 1e-9, "woken early")
		T.near(tl2.LineAt, 0.3 + SK.Timing.Hop + SK.Timing.Beat, 1e-9, "after the hop")
		T.eq(tl2.PoseAt(0.35).State, "Waking", "waking")
		T.eq(tl2.PoseAt(tl2.LineAt + 0.01).Text, Strings.L("shop.keeper.poor"), "poor line")
		-- Schedule / Shown edge cases
		local times = SK.Schedule("")
		T.eq(#times, 0, "empty line")
		T.eq(SK.Shown({ 0, 0.1, 0.2 }, -1), 0, "before the line")
		T.eq(SK.Shown({ 0, 0.1, 0.2 }, 0.15), 2, "two letters")
		T.eq(SK.Shown({ 0, 0.1, 0.2 }, 5), 3, "all")
		local ru = SK.Schedule("о. привет")
		T.eq(#ru, 9, "graphemes, not bytes (ru)")
	end,

	-- builder -------------------------------------------------------------------------------------------------------
	buildsInEveryThemeAtPhoneAndDesktop = function(T, Loader)
		local Strings, Themes, UIRoot, roblox = setup(Loader)
		local SK = Loader.requirePath(KEEPER)
		local Sprite = Loader.requirePath(SPRITE)
		local cases = {
			{ "phone 860x400", deviceLayout(UIRoot, roblox, 860, 400, 36), roblox.Vector2.new(320, 400) },
			{ "phone 740x360", deviceLayout(UIRoot, roblox, 740, 360), roblox.Vector2.new(360, 400) },
			{ "desktop 1920x1080", deviceLayout(UIRoot, roblox, 1920, 1080), roblox.Vector2.new(468, 722) },
		}
		for _, lang in { "en", "ru" } do
			Strings.SetLanguage(lang)
			for _, theme in Themes.List() do
				for _, case in cases do
					local label = ("%s %s %s"):format(theme.Id, case[1], lang)
					local layout = case[2]
					local ok, k =
						pcall(SK.Create, theme, { Size = case[3], Scale = layout.Scale, Phone = layout.Phone })
					if T.ok(ok and k ~= nil, label .. ": " .. tostring(k)) then
						local fit = k.Fit
						-- whole screen pixels per cell
						T.eq(fit.Pixel, math.floor(fit.Pixel), label .. ": integer pixel")
						T.near(fit.Unit * layout.Scale, fit.Pixel, 1e-9, label .. ": unit = pixel / scale")
						T.ok(fit.Pixel >= (if layout.Phone then 2 else 4), label .. ": big enough: " .. fit.Pixel)
						-- the scene fits the stage, the box fits the panel
						T.ok(fit.SceneW <= fit.InnerW + 1e-6 and fit.SceneTop >= -1e-6, label .. ": scene inside")
						T.ok(
							fit.BoxH >= SK.MinBox[if layout.Phone then "Phone" else "Desktop"],
							label .. ": box height"
						)
						T.ok(k.Box.Parent ~= nil and k.Stage.Parent ~= nil, label .. ": parts parented")
						-- the settled offline state: awake, the whole greeting shown
						T.eq(k.State(), "Idle", label .. ": settled")
						T.eq(k.Line(), Strings.L("shop.keeper.greet"), label .. ": greeting")
						T.eq(k.Text.MaxVisibleGraphemes, -1, label .. ": all shown")
						T.ok(
							string.find(k.Text.Text, Strings.L("shop.keeper.greet"), 1, true) ~= nil,
							label .. ": text"
						)
						-- ru uses a Cyrillic-capable face
						if lang == "ru" then
							T.ok(string.find(k.Text.FontFace.Family, "Jura", 1, true) ~= nil, label .. ": Jura in ru")
						end
						-- Classic keeps the Undertale "* " prefix
						if theme.Id == "Classic" then
							T.eq(string.sub(k.Text.Text, 1, 2), "* ", label .. ": dialogue prefix")
						end
						-- every sprite cell frame is a whole number of cells of the scene
						local cells = 0
						for _, d in k.Scene:GetDescendants() do
							if d:IsA("Frame") and d.BackgroundTransparency < 1 and d.Parent ~= k.Scene then
								cells += 1
							end
						end
						T.ok(cells > 150, label .. ": painted cells " .. cells)
						-- the sign on the counter front when it is visible
						if not fit.Covered then
							T.ok(k.Sign ~= nil, label .. ": SHOP sign")
						end
						T.noerror(k.Destroy, label .. ": destroy")
						T.ok(k.Root.Parent == nil, label .. ": destroyed")
					end
				end
			end
		end
		Strings.SetLanguage("en")
		-- too small: no keeper
		local tiny = SK.Create(Themes.Get("Classic"), { Size = roblox.Vector2.new(60, 60), Scale = 1, Phone = true })
		T.ok(tiny == nil, "no keeper in a 60x60 box")
		T.ok(SK.Plan(700, 400, 0.7, true, 10) == nil, "no column when the goods would lose their room")
		local _ = Sprite
	end,

	snapPutsTheSceneOnWholePixels = function(T, Loader)
		local _, Themes, UIRoot, roblox = setup(Loader)
		local SK = Loader.requirePath(KEEPER)
		local layout = deviceLayout(UIRoot, roblox, 1920, 1080)
		local k =
			SK.Create(Themes.Get("Royal"), { Size = roblox.Vector2.new(468, 722), Scale = layout.Scale, Phone = false })
		local stageW = k.Stage.Size.X.Offset
		local stageH = k.Stage.Size.Y.Offset
		for _, origin in { { 54.5088, 221.5264 }, { 10.25, 3.75 }, { 0, 0 }, { 99.5, 99.5 } } do
			k.Snap(roblox.Vector2.new(origin[1], origin[2]))
			local pos = k.Scene.Position
			local x = origin[1] + pos.X.Scale * stageW * layout.Scale + pos.X.Offset * layout.Scale
			local y = origin[2] + pos.Y.Scale * stageH * layout.Scale + pos.Y.Offset * layout.Scale
			-- (UDim Scale is a float32: ~1e-5 px of noise, far from a rounding edge)
			T.near(x, math.round(x), 1e-3, "scene x on a whole pixel")
			T.near(y, math.round(y), 1e-3, "scene y on a whole pixel")
			T.near(x, origin[1] + k.Fit.SceneX * layout.Scale, 0.5 + 1e-3, "moved by half a pixel at most")
		end
		k.Destroy()
	end,

	blipsWhileTyping = function(T, Loader)
		local Strings, Themes, UIRoot, roblox = setup(Loader)
		local SK = Loader.requirePath(KEEPER)
		local layout = deviceLayout(UIRoot, roblox, 860, 400, 36)
		local played = {}
		local sound = {
			Play = function(name)
				table.insert(played, name)
			end,
		}
		local k = SK.Create(Themes.Get("Classic"), {
			Size = roblox.Vector2.new(320, 400),
			Scale = layout.Scale,
			Phone = true,
			Deps = { Sound = sound },
			At = 0,
			ReducedMotion = false,
		})
		T.eq(k.State(), "Asleep", "starts asleep (At = 0)")
		local firstBlipAt = nil
		local dt = 1 / 60
		for _ = 1, 360 do
			k.Step(dt)
			if firstBlipAt == nil and #played > 0 then
				firstBlipAt = k.Time()
			end
		end
		T.ok(#played > 0, "blips played")
		for _, name in played do
			T.eq(name, SK.BlipSound, "Sans's blip")
		end
		T.eq(SK.BlipSound, "SansTextBlip", "the SoundController entry")
		T.ok(firstBlipAt ~= nil and firstBlipAt <= k.Timeline.LineAt + dt * 1.5, "the first letter is voiced")
		local graphemes = #k.Timeline.Graphemes
		T.ok(
			#played >= graphemes / 4 and #played <= graphemes,
			("about every other letter: %d of %d"):format(#played, graphemes)
		)
		T.eq(k.Blips(), #played, "Blips() counts them")
		T.eq(k.State(), "Idle", "done after 6 s")
		-- a new line: typed again with blips; the same line while it is being typed is not restarted
		local before = #played
		k.Say("shop.keeper.thanks")
		local startedAt = k.Timeline.LineAt
		k.Step(0.1)
		k.Say("shop.keeper.thanks")
		T.near(k.Timeline.LineAt, startedAt, 1e-9, "not restarted by a second Say")
		for _ = 1, 120 do
			k.Step(dt)
		end
		T.ok(#played > before, "thanks voiced")
		T.eq(k.Line(), Strings.L("shop.keeper.thanks"), "thanks line")
		k.Destroy()
	end,

	-- the Shop screen -----------------------------------------------------------------------------------------------
	shopLaysOutKeeperBesideTheGoods = function(T, Loader)
		local Strings, Themes, UIRoot, roblox = setup(Loader)
		local Shop = Loader.requirePath(SHOP)
		local SK = Loader.requirePath(KEEPER)
		local layouts = {
			{ "phone 860x400 notch", deviceLayout(UIRoot, roblox, 860, 400, 36), true },
			{ "phone 844x390", deviceLayout(UIRoot, roblox, 844, 390), true },
			{ "phone 740x360", deviceLayout(UIRoot, roblox, 740, 360), true },
			{ "desktop 1920x1080", deviceLayout(UIRoot, roblox, 1920, 1080), true },
			{ "desktop 1366x768", deviceLayout(UIRoot, roblox, 1366, 768), true },
			{ "portrait 390x844", UIRoot.ComputeLayout(roblox.Vector2.new(390, 844)), false },
		}
		for _, lang in { "en", "ru" } do
			Strings.SetLanguage(lang)
			for _, theme in Themes.List() do
				for _, case in layouts do
					local label = ("%s %s %s"):format(theme.Id, case[1], lang)
					local ok, h = pcall(Shop.Create, theme, { Layout = case[2] })
					if T.ok(ok and h ~= nil, label .. ": " .. tostring(h)) then
						local body = h.Root:FindFirstChild("Body")
						local goods = body and body:FindFirstChild("Goods")
						T.ok(goods ~= nil, label .. ": goods frame")
						if case[3] then
							local k = h.Keeper
							if T.ok(k ~= nil, label .. ": keeper column") then
								T.ok(k.Root.Parent == body, label .. ": in the body")
								local colW = k.Root.Size.X.Offset
								local m = case[2].Canvas.X
									- 2 * (if case[2].Phone then 18 elseif case[2].Compact then 24 else 36)
								T.eq(
									goods.Position.X.Offset,
									colW + (if case[2].Phone then 10 elseif case[2].Compact then 14 else 22),
									label .. ": goods right of the column"
								)
								local goodsW = goods.Size.X.Offset
								T.ok(
									goodsW >= SK.MinGoods[if case[2].Phone then "Phone" else "Desktop"] - 1,
									label .. ": goods keep their room: " .. goodsW
								)
								T.near(
									colW + goodsW + goods.Position.X.Offset - colW,
									m,
									1.5,
									label .. ": column + gap + goods = body"
								)
							end
							-- the shop still holds the daily rotation (phone tab or desktop) and the kit rail on desktop
							T.ok(goods:FindFirstChild("DailyHolder") ~= nil, label .. ": daily")
							T.ok(goods:FindFirstChild("AllHolder") ~= nil, label .. ": all skins")
						else
							T.ok(h.Keeper == nil, label .. ": no keeper column in portrait")
						end
						T.noerror(h.Destroy, label .. ": destroy")
					end
				end
			end
		end
		Strings.SetLanguage("en")
		-- the All tab on a phone keeps the kit rail + skins next to him; deps.Keeper = false keeps the old layout
		local phone = deviceLayout(UIRoot, roblox, 860, 400, 36)
		local all = Shop.Create(Themes.Get("Fell"), { Layout = phone, Tab = "All" })
		T.ok(all.Keeper ~= nil, "keeper on the All tab")
		T.ok(all.Root:FindFirstChild("KitRail", true) ~= nil, "kit rail")
		all.Destroy()
		local off = Shop.Create(Themes.Get("Fell"), { Layout = phone, Keeper = false })
		T.ok(off.Keeper == nil, "deps.Keeper = false")
		T.eq(off.Root.Body.Goods.Position.X.Offset, 0, "goods take the whole body")
		off.Destroy()
	end,

	purchaseLines = function(T, Loader)
		local Strings, Themes, UIRoot, roblox = setup(Loader)
		local Shop = Loader.requirePath(SHOP)
		local Common = Loader.requirePath("src/client/UI/Screens/Common")
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		local phone = deviceLayout(UIRoot, roblox, 860, 400, 36)
		local theme = Themes.Get("Classic")
		local L = function(key)
			return Strings.L(key)
		end
		local function modalOpen(h)
			return h.Root:FindFirstChild("Modal") ~= nil
		end

		-- not enough G: Sans says so, no request, no pop-up
		local poor = Common.SampleProfile()
		poor.Gold = 5
		local state, requests = mockState(poor)
		local h = Shop.Create(theme, { Layout = phone, State = state, Profile = poor })
		local kit, skin = skinForSale(Common, Kits, poor)
		if T.ok(kit ~= nil, "a skin for sale") then
			T.ok(h.Press(kit.Id, skin.Id), "pressed")
			T.eq(h.Keeper.Line(), L("shop.keeper.poor"), "poor line")
			T.eq(#requests, 0, "no request")
			T.ok(not modalOpen(h), "no pop-up with the keeper")
			T.ok(not h.Confirm(), "nothing to confirm")
		end
		-- the server says not enough G (stale balance): poor too
		h.Keeper.Say("shop.keeper.greet")
		state.Notify:Fire("prog.err.gold", { 100 }, "Warning")
		T.eq(h.Keeper.Line(), L("shop.keeper.poor"), "server's gold error -> poor")
		h.Destroy()

		-- enough G: the confirm pop-up, the request, then thanks once the server confirms (Notify)
		local rich = Common.SampleProfile()
		rich.Gold = 1e6
		local state2, requests2 = mockState(rich)
		local h2 = Shop.Create(theme, { Layout = phone, State = state2, Profile = rich })
		local kit2, skin2 = skinForSale(Common, Kits, rich)
		T.ok(h2.Press(kit2.Id, skin2.Id), "pressed (rich)")
		T.ok(modalOpen(h2), "confirm pop-up")
		T.eq(h2.Keeper.Line(), L("shop.keeper.greet"), "still the greeting before buying")
		T.ok(h2.Confirm(), "confirmed")
		T.eq(#requests2, 1, "one request")
		T.eq(requests2[1][1], "Buy", "Buy request")
		T.eq(requests2[1][2].kitId, kit2.Id, "kit id")
		T.eq(requests2[1][2].skinId, skin2.Id, "skin id")
		T.ok(not modalOpen(h2), "pop-up closed")
		local says = 0
		local realSay = h2.Keeper.Say
		h2.Keeper.Say = function(...)
			says += 1
			return realSay(...)
		end
		state2.Notify:Fire("prog.notify.shopRestock", nil, "Info")
		T.eq(says, 0, "unrelated notifications are ignored")
		state2.Notify:Fire("prog.notify.bought", { "x" }, "Success")
		T.eq(h2.Keeper.Line(), L("shop.keeper.thanks"), "thanks")
		-- the profile (now owning the skin) arrives after the notification: no second thanks
		local owned = table.clone(rich)
		owned.Unlocked = table.clone(rich.Unlocked or {})
		owned.Unlocked[kit2.Id .. ":" .. skin2.Id] = true
		T.ok(Common.SkinOwned(owned, kit2, skin2), "owned now")
		state2.ProfileChanged:Fire(owned)
		T.eq(says, 1, "thanked once")
		h2.Destroy()

		-- thanks from the profile alone (the item shows up owned)
		local rich3 = Common.SampleProfile()
		rich3.Gold = 1e6
		local state3 = mockState(rich3)
		local h3 = Shop.Create(theme, { Layout = phone, State = state3, Profile = rich3 })
		local kit3, skin3 = skinForSale(Common, Kits, rich3)
		h3.Press(kit3.Id, skin3.Id)
		h3.Confirm()
		local after = table.clone(rich3)
		after.Unlocked = table.clone(rich3.Unlocked or {})
		after.Unlocked[kit3.Id .. ":" .. skin3.Id] = true
		local marked = Common.SkinOwned(after, kit3, skin3)
		if T.ok(marked, "could mark the skin owned in the sample profile") then
			state3.ProfileChanged:Fire(after)
			T.eq(h3.Keeper.Line(), L("shop.keeper.thanks"), "thanks from the profile")
		end
		h3.Destroy()

		-- without the keeper the old pop-up tells you how much G is missing
		local poor4 = Common.SampleProfile()
		poor4.Gold = 5
		local state4, requests4 = mockState(poor4)
		local h4 = Shop.Create(theme, { Layout = phone, State = state4, Profile = poor4, Keeper = false })
		local kit4, skin4 = skinForSale(Common, Kits, poor4)
		h4.Press(kit4.Id, skin4.Id)
		T.ok(modalOpen(h4), "not-enough pop-up without the keeper")
		T.eq(#requests4, 0, "no request")
		h4.Destroy()
	end,

	stringsExistInBothLanguages = function(T, Loader)
		local Strings = setup(Loader)
		local raw = Loader.require("ReplicatedStorage.Shared.Strings.ShopKeeper")
		for _, key in
			{ "shop.keeper.zzz", "shop.keeper.greet", "shop.keeper.thanks", "shop.keeper.poor", "shop.keeper.bye" }
		do
			local entry = raw[key]
			if T.ok(type(entry) == "table", key) then
				T.ok(type(entry.en) == "string" and #entry.en > 0, key .. " en")
				T.ok(type(entry.ru) == "string" and #entry.ru > 0, key .. " ru")
			end
			T.ok(Strings.Has(key), key .. " registered")
		end
		Strings.SetLanguage("ru")
		T.ok(string.find(Strings.L("shop.keeper.greet"), "малой", 1, true) ~= nil, "ru greeting")
		Strings.SetLanguage("en")
		T.ok(string.find(Strings.L("shop.keeper.greet"), "kid", 1, true) ~= nil, "en greeting")
	end,
})
