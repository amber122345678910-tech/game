--!nocheck
-- The Verdict Box victim's ENTRY transition (UI/VerdictBoxEntry, SPEC §11): stage timing (pull-in -> black -> sharp
-- flash, on time / late packets / Reduced Motion), fairness (the flash has faded before the first attack can reach
-- the SOUL for every set and seed, Sim.SkipTo never produces hits, the server rejects hits while the box flashes in,
-- the watchers' mirror before t0), the camera pull (pose, no accumulation, restored exactly afterwards through the
-- same Runner the controller binds), the screen layer (iris, streaks, heart, flash; Reduced Motion), and the music:
-- SoundController.Prewarm checks the box track ahead of time and the "Box" context switches to it on the same frame
-- with the short box fade (and back out with the normal one).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, Vector2, CFrame = roblox.Vector3, roblox.Vector2, roblox.CFrame

local ENTRY = "src/client/UI/VerdictBoxEntry"
local AUDIO = "ReplicatedStorage.Shared.Audio"
local REGISTRY = "ReplicatedStorage.Shared.Maps.Registry"

local function entryModule(Loader)
	local before = Loader.quietWarnings
	Loader.quietWarnings = true
	local ok, mod = pcall(Loader.requirePath, ENTRY)
	Loader.quietWarnings = before
	if not ok then
		error(mod, 0)
	end
	return mod
end

-- a camera CFrame at `pos` looking at `target` (built from basis vectors: Lune's CFrame.lookAt is mirrored)
local function lookAt(pos, target)
	local f = (target - pos).Unit
	local right = f:Cross(Vector3.new(0, 1, 0)).Unit
	local up = right:Cross(f)
	return CFrame.fromMatrix(pos, right, up, -f)
end

-- pinhole projection of a fake camera {CFrame, FieldOfView} onto a screen of `size` px (nil = behind)
local function projector(size)
	return function(camera, point)
		local rel = camera.CFrame:PointToObjectSpace(point)
		if rel.Z >= 0 then
			return nil
		end
		local focal = (size.Y / 2) / math.tan(math.rad(camera.FieldOfView) / 2)
		return Vector2.new(size.X / 2 + rel.X / -rel.Z * focal, size.Y / 2 - rel.Y / -rel.Z * focal)
	end
end

local function countDescendants(inst)
	return #inst:GetDescendants()
end

---------------------------------------------------------------------------------------------------
-- SoundController with fake engine objects (compact version of audio_candidates.spec's harness): Sounds whose assets
-- load on the next step according to world.fetch[id] ("Success" | "Failure"), a ContentProvider, State/Input fakes
-- (world.setContext fires InputController.ContextChanged) and a manual scheduler driven by world.step(dt).

local function makeSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local entry = { fn = fn }
		table.insert(handlers, entry)
		return {
			Connected = true,
			Disconnect = function()
				for i, e in handlers do
					if e == entry then
						table.remove(handlers, i)
						break
					end
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, e in table.clone(handlers) do
			e.fn(...)
		end
	end
	return signal
end

local function loadSound(Loader)
	local Enum = roblox.Enum
	local world = { now = 0, fetch = {}, preloads = {}, warnings = {}, sounds = {}, round = { Phase = "Waiting" } }
	local timers, deferred, loading = {}, {}, {}
	local seq = 0
	local function addTimer(t, fn, ...)
		seq += 1
		table.insert(timers, { at = world.now + (t or 0), seq = seq, fn = fn, args = table.pack(...) })
	end
	local fakeTask = {
		delay = function(t, fn, ...)
			addTimer(t, fn, ...)
		end,
		defer = function(fn, ...)
			table.insert(deferred, { fn = fn, args = table.pack(...) })
		end,
		spawn = function(fn, ...)
			local co = coroutine.create(fn)
			local ok, err = coroutine.resume(co, ...)
			if not ok then
				error(err, 0)
			end
			return co
		end,
		wait = function(t)
			local co = coroutine.running()
			addTimer(t, function()
				coroutine.resume(co)
			end)
			return coroutine.yield()
		end,
	}
	function world.flush()
		for _ = 1, 500 do
			local d = table.remove(deferred, 1)
			if d == nil then
				return
			end
			d.fn(table.unpack(d.args, 1, d.args.n))
		end
		error("the deferred queue does not drain")
	end
	local heartbeat = makeSignal()
	local function fakeInstance(className)
		local props = { ClassName = className, Name = className, Destroying = makeSignal() }
		local methods = {}
		local obj = {}
		function methods:IsA(c)
			return c == className or c == "Instance"
		end
		function methods:FindFirstChild()
			return nil
		end
		function methods:Destroy()
			props.Parent = nil
			props.Destroying:Fire()
		end
		if className == "Sound" then
			props.SoundId, props.Volume, props.Looped, props.Playing = "", 0.5, false, false
			props.IsLoaded, props.TimeLength, props.PlaybackSpeed, props.TimePosition = false, 0, 1, 0
			props.Ended, props.Loaded = makeSignal(), makeSignal()
			function methods:Play()
				props.Playing = true
			end
			function methods:Stop()
				props.Playing = false
			end
			table.insert(world.sounds, obj)
		end
		return setmetatable(obj, {
			__index = function(_, k)
				local m = methods[k]
				if m ~= nil then
					return m
				end
				return props[k]
			end,
			__newindex = function(_, k, v)
				if k == "IsLoaded" or k == "TimeLength" or k == "ClassName" then
					error("mock: " .. k .. " is read-only", 2)
				end
				props[k] = v
				if k == "SoundId" then
					props.IsLoaded = false
					props.TimeLength = 0
					loading[obj] = props
				end
			end,
		})
	end
	function world.step(dt)
		world.now += dt
		while true do
			local best, index = nil, nil
			for i, t in timers do
				if t.at <= world.now + 1e-9 and (best == nil or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
					best, index = t, i
				end
			end
			if best == nil then
				break
			end
			table.remove(timers, index)
			best.fn(table.unpack(best.args, 1, best.args.n))
			world.flush()
		end
		local batch = loading
		loading = {}
		for _, props in batch do
			if world.fetch[props.SoundId] == "Success" then
				props.IsLoaded = true
				props.TimeLength = 30
				props.Loaded:Fire()
			end
		end
		world.flush()
		heartbeat:Fire(dt)
		world.flush()
	end
	function world.advance(seconds, dt)
		dt = dt or 0.05
		for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
			world.step(dt)
		end
	end
	local contentProvider = {}
	function contentProvider:PreloadAsync(items, callback)
		local id = items[1].SoundId
		table.insert(world.preloads, id)
		local status = if world.fetch[id] == "Success"
			then Enum.AssetFetchStatus.Success
			else Enum.AssetFetchStatus.Failure
		callback(id, status)
	end
	function contentProvider:GetAssetFetchStatus()
		return Enum.AssetFetchStatus.None
	end
	local state = { RoundChanged = makeSignal(), RoleChanged = makeSignal(), SettingChanged = makeSignal() }
	function state.Round()
		return world.round
	end
	function state.Role()
		return "Human"
	end
	function state.Setting()
		return 1
	end
	function state.OnRoundEvent() end
	local contexts = {}
	local input = { ContextChanged = makeSignal() }
	function input.HasContext(name)
		return contexts[name] == true
	end
	function world.setContext(name, active)
		contexts[name] = active or nil
		input.ContextChanged:Fire(name, active)
		world.flush()
	end
	local function module(path, fake)
		return {
			__module = path,
			__fake = fake,
			IsA = function(_, c)
				return c == "ModuleScript"
			end,
		}
	end
	local function folder(children)
		return {
			WaitForChild = function(_, n)
				return children[n] or error("mock: missing child " .. n)
			end,
			FindFirstChild = function(_, n)
				return children[n]
			end,
		}
	end
	local services = {
		SoundService = fakeInstance("SoundService"),
		RunService = { Heartbeat = heartbeat },
		TweenService = {
			Create = function()
				return { Play = function() end, Completed = makeSignal() }
			end,
		},
		ContentProvider = contentProvider,
		ReplicatedStorage = folder({
			Shared = folder({
				Audio = module(AUDIO),
				Maps = folder({ Registry = module(REGISTRY) }),
				Util = folder({ Signal = module("ReplicatedStorage.Shared.Util.Signal") }),
			}),
		}),
	}
	local env = setmetatable({
		game = {
			GetService = function(_, n)
				return services[n] or error("mock: no service " .. n)
			end,
		},
		workspace = {},
		script = {
			Name = "SoundController",
			Parent = folder({ StateController = module(nil, state), InputController = module(nil, input) }),
		},
		require = function(target)
			if type(target) == "table" and target.__fake then
				return target.__fake
			elseif type(target) == "table" and target.__module then
				return Loader.require(target.__module)
			end
			error("mock: unexpected require")
		end,
		warn = function(...)
			table.insert(world.warnings, table.concat({ ... }, " "))
		end,
		print = function() end,
		task = fakeTask,
		os = setmetatable({
			clock = function()
				return world.now
			end,
		}, { __index = os }),
		Instance = { new = fakeInstance },
		Enum = Enum,
		Random = Loader.Random,
		TweenInfo = roblox.TweenInfo,
		CFrame = roblox.CFrame,
		Vector3 = roblox.Vector3,
	}, { __index = _G })
	local source = fs.readFile("src/client/Controllers/SoundController.luau")
	world.controller = luau.load(source, { debugName = "SoundController(mock)", environment = env, injectGlobals = true })()
	-- the music deck currently playing `id` (nil = none)
	function world.deck(id)
		for _, s in world.sounds do
			if string.find(s.Name, "SV_MusicDeck", 1, true) and s.SoundId == id and s.Playing then
				return s
			end
		end
		return nil
	end
	return world
end

---------------------------------------------------------------------------------------------------

local tests = {}

tests.entry_stages_on_time = function(T, Loader)
	local Entry = entryModule(Loader)
	local E = Entry.Tuning
	T.ok(E.Pull >= 0.6 and E.Pull <= 0.7, "pull-in about 0.6-0.7 s")
	T.ok(E.Black >= 0.08 and E.Black <= 0.12, "about 0.1 s of full black")
	T.ok(E.FlashHold >= 1 / 60 and E.FlashHold <= 2.5 / 60, "white at full opacity for 1-2 frames")
	T.ok(E.FlashFade >= 0.2 and E.FlashFade <= 0.3, "the white fades in 0.2-0.3 s")
	local open, intro, introEnd = 100, 0.8, 1.0
	local t0 = open + intro
	local start = open + 0.05 -- 50 ms one-way latency
	local st = Entry.Stages(start, t0, introEnd)
	T.eq(st.start, start, "the pull-in starts the moment BoxStart arrives")
	T.near(st.pull, E.Pull, 1e-9, "full pull-in")
	T.near(st.pullEnd, start + E.Pull, 1e-9, "pull end")
	T.near(st.flashAt, t0, 1e-9, "the flash lands on the timeline start t0")
	T.near(st.flashAt - st.pullEnd, E.Black, 1e-9, "black between the pull-in and the flash")
	T.near(st.flashEnd, st.flashAt + E.FlashHold + E.FlashFade, 1e-9, "flash end")
	T.eq(st.reduced, false, "full motion by default")
	-- the pull-in: everything grows, nothing of the box yet
	local prevIris, prevCam, prevDark = -1, -1, -1
	local n = 0
	for now = start, st.pullEnd - 1e-3, 1 / 60 do
		local f = Entry.At(st, now)
		n += 1
		T.eq(f.stage, "Pull", "pull stage")
		T.ok(f.iris >= prevIris - 1e-9 and f.camera >= prevCam - 1e-9 and f.dark >= prevDark - 1e-9, "monotonic pull-in")
		T.ok(f.open == 0 and f.flash == 0, "no box and no flash during the pull-in")
		prevIris, prevCam, prevDark = f.iris, f.camera, f.dark
	end
	T.ok(n >= 35, "about 40 frames of pull-in at 60 fps")
	local first = Entry.At(st, start)
	T.ok(first.iris == 0 and first.camera == 0 and first.dark == 0 and first.heart == 0, "starts from the plain world")
	local early = Entry.At(st, start + E.Pull * 0.3)
	local late = Entry.At(st, start + E.Pull * 0.9)
	T.ok(late.camera - early.camera > 0.4 and late.camera > 0.7, "accelerating camera pull (eased in)")
	T.ok(early.heart == 0 and late.heart > 0.6, "the SOUL heart appears in the second half")
	T.ok(late.roll > 0 and late.swirl > 0 and late.streaks > 0, "swirl + streaks while sucked in")
	local closing = Entry.At(st, st.pullEnd - 1e-4)
	T.ok(closing.iris > 0.99 and closing.camera > 0.99 and closing.heart > 0.99, "the iris shuts at the end of the pull")
	-- black
	local black = Entry.At(st, st.pullEnd + E.Black / 2)
	T.eq(black.stage, "Black", "black stage")
	T.ok(black.dark == 1 and black.heart == 1 and black.open == 0 and black.flash == 0, "full black with the SOUL")
	T.eq(black.camera, 0, "the camera is its own again in the black (unseen)")
	-- the sharp flash
	local flash = Entry.At(st, st.flashAt)
	T.eq(flash.stage, "Flash", "flash stage")
	T.ok(flash.flash == 1 and flash.open == 1 and flash.dark == 0 and flash.heart == 0, "full white over the box")
	T.eq(Entry.At(st, st.flashAt + E.FlashHold * 0.9).flash, 1, "held at full white for FlashHold")
	local mid = Entry.At(st, st.flashAt + E.FlashHold + E.FlashFade * 0.5)
	T.ok(mid.flash > 0 and mid.flash < 0.5, "fast-then-slow fade: under half white halfway")
	local done = Entry.At(st, st.flashEnd)
	T.ok(done.stage == "Done" and done.flash == 0 and done.open == 1, "done: only the box")
	-- At reuses its output table
	local out = Entry.At(st, start)
	T.eq(Entry.At(st, st.flashAt, out), out, "At(stages, now, out) fills `out`")
end

tests.entry_stages_late_packets = function(T, Loader)
	local Entry = entryModule(Loader)
	local E = Entry.Tuning
	local c = Loader.require("ReplicatedStorage.Shared.Config").VerdictBox
	local open, introEnd = 50, 1.0
	local t0 = open + c.IntroTime
	local onTime = c.IntroTime - E.MinPull - E.Black
	T.ok(onTime >= 0.35, "one-way latencies up to 0.35 s still flash exactly on t0")
	for L = 0, 2.5, 0.01 do
		local start = open + L
		local st = Entry.Stages(start, t0, introEnd)
		local tag = ("latency %.2f s"):format(L)
		T.eq(st.start, start, "starts on arrival (" .. tag .. ")")
		T.ok(st.pull >= 0 and st.pullEnd <= st.flashAt + 1e-9 and st.flashAt >= start - 1e-9, "ordered (" .. tag .. ")")
		local deadline = t0 + introEnd - E.Gap
		T.ok(
			st.flashEnd <= math.max(deadline, start + E.FlashHold + E.FlashFade) + 1e-9,
			"faded before the first attack, or at once when hopelessly late (" .. tag .. ")"
		)
		if L <= onTime + 1e-9 then
			T.near(st.flashAt, t0, 1e-9, "on time: the flash is on t0 (" .. tag .. ")")
			T.ok(st.pull >= E.MinPull - 1e-9 and st.pull <= E.Pull + 1e-9, "pull-in in range (" .. tag .. ")")
			T.ok(st.flashAt - st.pullEnd >= E.Black - 1e-9, "black kept (" .. tag .. ")")
		elseif st.flashAt < deadline - E.FlashHold - E.FlashFade - 1e-6 then
			T.near(st.pull, E.MinPull, 1e-9, "late: the shortest full pull-in (" .. tag .. ")")
			T.near(st.flashAt - st.pullEnd, E.Black, 1e-9, "late: black kept (" .. tag .. ")")
		end
	end
	-- typical phone pings: a proper pull-in
	for _, L in { 0.03, 0.08, 0.15, 0.25 } do
		local st = Entry.Stages(open + L, t0, introEnd)
		T.ok(st.pull >= 0.45, ("%.2f s ping keeps a %.2f s pull-in"):format(L, st.pull))
	end
	-- a packet that arrives after the deadline flashes at once
	local hopeless = Entry.Stages(t0 + 2, t0, introEnd)
	T.ok(hopeless.pull == 0 and hopeless.flashAt == hopeless.start, "hopelessly late: straight to the flash")
end

tests.entry_reduced_motion = function(T, Loader)
	local Entry = entryModule(Loader)
	local normal = Entry.Stages(10, 10.75, 1)
	local st = Entry.Stages(10, 10.75, 1, true)
	T.eq(st.reduced, true, "reduced flag")
	T.ok(st.pullEnd == normal.pullEnd and st.flashAt == normal.flashAt, "same timing as the full transition")
	local prev = -1
	for now = 10, st.flashEnd + 0.05, 1 / 60 do
		local f = Entry.At(st, now)
		T.ok(f.iris == 0 and f.camera == 0 and f.roll == 0 and f.swirl == 0 and f.streaks == 0, "no zoom / swirl")
		if f.stage == "Pull" then
			T.ok(f.dark >= prev - 1e-9, "a plain darkening")
			prev = f.dark
		end
	end
	T.ok(Entry.At(st, st.pullEnd - 1e-4).dark > 0.99, "dark by the end of the pull-in")
	T.eq(Entry.At(st, st.pullEnd + 0.01).dark, 1, "black")
	T.eq(Entry.At(st, st.flashAt).flash, 1, "still the sharp flash")
	T.eq(Entry.At(st, st.flashAt).open, 1, "the box under the flash")
end

tests.entry_fight_starts_after_the_flash = function(T, Loader)
	local Entry = entryModule(Loader)
	local E = Entry.Tuning
	local Patterns = Loader.require("ReplicatedStorage.Shared.VerdictBox.Patterns")
	local Sim = Loader.require("ReplicatedStorage.Shared.VerdictBox.Sim")
	local c = Loader.require("ReplicatedStorage.Shared.Config").VerdictBox
	local R = Loader.requirePath("src/server/Services/VerdictBoxService").Rules
	local open = 20
	local t0 = open + c.IntroTime
	for _, set in Patterns.SetIds do
		for seed = 1, 10 do
			local tl = Patterns.Build(set, seed, c.Duration)
			-- nothing can hurt the SOUL before the first attack (it only becomes active at introEnd)
			local st = Sim.new(tl)
			Sim.AdvanceTo(st, tl.introEnd - Sim.TICK, {})
			T.ok(st.hits == 0 and not st.soul.active, ("%s %d: no SOUL / hits during the opening"):format(set, seed))
			for _, L in { 0, 0.05, 0.12, 0.25, 0.35, 0.5 } do
				local stg = Entry.Stages(open + L, t0, tl.introEnd)
				T.ok(
					stg.flashEnd <= t0 + tl.introEnd - E.Gap + 1e-9,
					("%s %d latency %.2f: the flash has faded %.2f s before the first attack"):format(
						set,
						seed,
						L,
						t0 + tl.introEnd - stg.flashEnd
					)
				)
				-- the server accepts no hit while the box is still flashing in
				T.eq(R.AcceptHits(0, 1, stg.flashEnd - t0 - 1e-3, tl.introEnd), 0, "server: no hit before the reveal")
			end
		end
	end
	-- a hopelessly late client: Sim.SkipTo (used until the box is revealed) never produces hits
	local tl = Patterns.Build("Fell", 3, c.Duration)
	local st = Sim.new(tl)
	Sim.SkipTo(st, 2.5)
	T.ok(st.hits == 0 and #st.events == 0, "SkipTo simulates nothing (no hits, no events)")
	T.near(st.t, 2.5, Sim.TICK, "SkipTo moves the sim clock")
	Sim.SkipTo(st, 1.0)
	T.near(st.t, 2.5, Sim.TICK, "never backwards")
	Sim.AdvanceTo(st, 2.6, {})
	T.ok(st.soul.active, "the next tick enters the mode active at that time")
	for _, e in st.events do
		T.ok(e.t >= 2.5 - 1e-9, "every event after the skip")
	end
	-- watchers mirror the box from t0 on; before it (negative box time) the view shows the empty dialog box
	local View = Loader.requirePath("src/client/UI/VerdictBoxView")
	local v = View.new(nil, tl, { Mode = "Mirror", Size = Vector2.new(312, 312), Name = "Kris" })
	T.noerror(function()
		for t = -c.IntroTime, 0.1, 0.05 do
			v:Render(t, { x = 0, y = 0, mode = "Intro", gravity = "Down", visible = true })
		end
	end, "mirror renders negative box times")
	v:Render(-0.3, { x = 0, y = 0, mode = "Intro", gravity = "Down", visible = true })
	T.eq(v.textLabel.MaxVisibleGraphemes, 0, "the opening line has not started before t0")
	v:Destroy()
end

tests.entry_camera_pose = function(T, Loader)
	local Entry = entryModule(Loader)
	local E = Entry.Tuning
	local chest = Vector3.new(0.6, 3.4, 0)
	local base = lookAt(Vector3.new(3, 6.5, 11), Vector3.new(-1, 4.2, -2)) -- over the shoulder, not at the chest
	local cf, fov = Entry.CameraPose(base, 70, chest, 0, 0)
	T.ok(cf == base and fov == 70, "k = 0 leaves the camera exactly as it was")
	local full, fullFov = Entry.CameraPose(base, 70, chest, 1, 0)
	local dir = (chest - full.Position).Unit
	T.ok(full.LookVector:Dot(dir) > 0.9999, "k = 1 looks straight at the chest")
	T.near(fullFov, 70 * E.FovScale, 1e-9, "FOV narrowed to FovScale")
	local d0, d1 = (base.Position - chest).Magnitude, (full.Position - chest).Magnitude
	T.ok(d1 < d0 - 1 and d1 >= E.MinDistance - 1e-6, "pushed toward the chest, never too close")
	local half, halfFov = Entry.CameraPose(base, 70, chest, 0.5, 0)
	local dirHalf = (chest - half.Position).Unit
	T.ok(halfFov < 70 and halfFov > fullFov, "FOV in between")
	T.ok(
		half.LookVector:Dot(dirHalf) > base.LookVector:Dot((chest - base.Position).Unit)
			and half.LookVector:Dot(dirHalf) < 0.9999,
		"turned part of the way"
	)
	local rolled = Entry.CameraPose(base, 70, chest, 1, 10)
	local angle = math.deg(math.acos(math.clamp(rolled.UpVector:Dot(full.UpVector), -1, 1)))
	T.near(angle, 10, 0.05, "roll in degrees about the view axis")
	T.ok(rolled.LookVector:Dot(full.LookVector) > 0.9999, "roll keeps the aim")
	local near = Entry.CameraPose(base, 70, base.Position + base.LookVector * 1.5, 1, 0)
	T.ok((near.Position - base.Position).Magnitude < 1e-6, "no push when already closer than MinDistance")
end

tests.entry_runner_restores_the_camera = function(T, Loader)
	local Entry = entryModule(Loader)
	local size = Vector2.new(860, 400)
	local chest = Vector3.new(0.6, 3.4, 0)
	local base = lookAt(Vector3.new(3, 6.5, 11), Vector3.new(-1, 4.2, -2))
	local function run(rewrite, stopAt)
		local cam = { CFrame = base, FieldOfView = 70 }
		local post = {}
		local layer = Entry.new(nil, {})
		local stages = Entry.Stages(0, 0.75, 1)
		local runner = Entry.Runner(stages, layer, {
			camera = function()
				return cam
			end,
			chest = function()
				return chest
			end,
			project = projector(size),
			size = function()
				return size
			end,
			postFx = function(a)
				table.insert(post, a)
			end,
		})
		local log = { centers = {}, fovs = {}, frames = 0 }
		local t = 0
		while not runner.done and t < 2 do
			if rewrite then
				cam.CFrame, cam.FieldOfView = base, 70 -- CameraController writes its own frame first
			end
			local f = runner:Step(t)
			log.frames += 1
			if f.stage == "Pull" then
				table.insert(log.centers, { k = f.camera, c = runner.center })
				table.insert(log.fovs, { k = f.camera, fov = cam.FieldOfView })
			elseif f.stage == "Black" or f.stage == "Flash" then
				log.restoredInBlack = (log.restoredInBlack ~= false) and cam.CFrame == base and cam.FieldOfView == 70
			end
			if stopAt and t >= stopAt then
				runner:Stop()
			end
			t += 1 / 60
		end
		return cam, runner, post, log, layer
	end
	-- with a camera controller rewriting the camera every frame (the game)
	local cam, runner, post, log, layer = run(true)
	T.ok(runner.done and runner.layer == nil, "the runner stops itself when Done and drops its layer")
	T.ok(layer.Root.Parent == nil, "layer destroyed")
	T.ok(cam.CFrame == base and cam.FieldOfView == 70, "camera exactly as the controller left it")
	T.eq(log.restoredInBlack, true, "the camera is back from the black on")
	T.eq(post[#post], 0, "post effects off at the end")
	local maxPost = 0
	for _, a in post do
		maxPost = math.max(maxPost, a)
	end
	T.ok(maxPost > 0.9, "post effects follow the camera pull")
	local narrow = false
	for _, e in log.fovs do
		T.near(e.fov, 70 * (1 - (1 - Entry.Tuning.FovScale) * e.k), 1e-6, "FOV = the controller's x the pull (no compounding)")
		narrow = narrow or e.fov < 45
	end
	T.ok(narrow, "a strong zoom by the end of the pull-in")
	-- the iris centre follows the chest through the turning camera: off-centre first, the screen middle at the end
	local firstC, lastC = log.centers[1].c, log.centers[#log.centers].c
	local mid = size * 0.5
	T.ok((firstC - mid).Magnitude > 15, "starts on the chest where it is on screen")
	T.ok((lastC - mid).Magnitude < 4, "ends on the screen centre (the camera aims at the SOUL)")
	-- without anything rewriting the camera: no accumulation, and the original frame comes back exactly
	local cam2, runner2, _, log2 = run(false)
	T.ok(runner2.done and cam2.CFrame == base and cam2.FieldOfView == 70, "restored without a camera controller")
	for _, e in log2.fovs do
		T.near(e.fov, 70 * (1 - (1 - Entry.Tuning.FovScale) * e.k), 1e-6, "no accumulation frame to frame")
	end
	-- cancelled mid pull-in (the box ended early): Stop puts the camera back at once
	local cam3, runner3 = run(false, 0.4)
	T.ok(runner3.done and cam3.CFrame == base and cam3.FieldOfView == 70, "Stop mid pull-in restores the camera")
	T.noerror(function()
		runner3:Stop()
	end, "Stop is idempotent")
end

tests.entry_layer_renders = function(T, Loader)
	local Entry = entryModule(Loader)
	local size = Vector2.new(860, 400)
	local center = Vector2.new(470, 170)
	for _, reduced in { false, true } do
		local st = Entry.Stages(0, 0.75, 1, reduced)
		local layer = Entry.new(nil, { ZIndex = 60 })
		T.eq(layer.Root.ZIndex, 60, "layer ZIndex")
		local count = countDescendants(layer.Root)
		local sawRings, sawStreaks, sawHeart, sawFlash = false, false, false, false
		local tag = if reduced then "reduced" else "full"
		T.noerror(function()
			for now = 0, st.flashEnd + 0.1, 1 / 60 do
				local f = Entry.At(st, now)
				layer:Render(f, center, size)
				for _, r in layer.rings do
					sawRings = sawRings or r.frame.Visible
				end
				for _, s in layer.streaks do
					sawStreaks = sawStreaks or s.frame.Visible
				end
				sawHeart = sawHeart or layer.heart.Visible
				sawFlash = sawFlash or (layer.flash.Visible and layer.flash.BackgroundTransparency == 0)
				if f.stage == "Black" then
					T.ok(layer.dim.Visible and layer.dim.BackgroundTransparency == 0, tag .. ": black")
					T.ok(layer.heart.Visible, tag .. ": the SOUL in the dark")
				elseif f.stage == "Flash" or f.stage == "Done" then
					T.ok(not layer.heart.Visible and not layer.dim.Visible, tag .. ": nothing but the flash over the box")
				end
			end
		end, tag .. ": renders the whole transition")
		T.eq(sawRings, not reduced, tag .. ": iris only with full motion")
		T.eq(sawStreaks, not reduced, tag .. ": streaks only with full motion")
		T.ok(sawHeart and sawFlash, tag .. ": SOUL heart + full white flash")
		T.eq(countDescendants(layer.Root), count, tag .. ": no instances created per frame")
		local f = Entry.At(st, st.flashEnd + 1)
		layer:Render(f, center, size)
		T.ok(not layer.flash.Visible and not layer.dim.Visible, tag .. ": invisible when done")
		layer:Destroy()
	end
	-- the hard iris ring always reaches past the farthest corner (no world peeking around the black)
	local st = Entry.Stages(0, 0.75, 1)
	local layer = Entry.new(nil, {})
	local corner = Vector2.new(20, 20) -- the chest near a corner: the farthest corner is the opposite one
	layer:Render(Entry.At(st, st.pull * 0.8), corner, size)
	local hard = layer.rings[#layer.rings]
	local inner = hard.frame.Size.X.Offset / 2
	T.ok(inner + hard.stroke.Thickness >= (size - corner).Magnitude, "the black covers the whole screen outside the hole")
	layer:Destroy()
	local preview = Entry.Create(nil, { Time = 0.5 })
	T.ok(preview and preview.Root and type(preview.Destroy) == "function", "Create(theme, deps) preview contract")
	preview.Destroy()
end

tests.entry_music_switches_on_the_first_frame = function(T, Loader)
	local Audio = Loader.require(AUDIO)
	local box = Audio.Candidates("VerdictBox")
	T.eq(box[1], "rbxassetid://118325539349483", "the owner's box track is the first VerdictBox candidate")
	local lobby = Audio.Candidates("Lobby")
	T.ok(#lobby > 0, "the lobby has a track")
	local world = loadSound(Loader)
	local S = world.controller
	T.eq(S.BOX_FADE_IN, 0.15, "short fade into the box")
	T.eq(S.BOX_FADE_OUT, 1.0, "normal fade back out")
	world.fetch[lobby[1]] = "Success"
	world.fetch[box[1]] = "Success"
	S.Init()
	S.Start()
	world.advance(0.3)
	T.eq(S.CurrentMusic(), "Lobby", "lobby music first")
	-- the client starts: VerdictBoxController.Start prewarms the box track (checked once, in the background)
	S.Prewarm("VerdictBox")
	world.advance(0.1)
	T.eq(S.IdState(box[1]), "good", "the box track id is checked ahead of time")
	T.eq(S.Status("VerdictBox"), "ok", "ready before any box")
	local probes = #world.preloads
	-- the pull-in starts: the "Box" context -> the box track on this very frame, no new check
	world.setContext("Box", true)
	T.eq(S.CurrentMusic(), "VerdictBox", "switched on the same frame as the pull-in")
	T.eq(#world.preloads, probes, "no probe wait at the switch")
	local deck = world.deck(box[1])
	T.ok(deck ~= nil, "a music deck plays the owner's id right away")
	local def = Audio.Get("VerdictBox")
	world.step(0.1)
	T.ok(deck.Volume > def.Volume * 0.55 and deck.Volume < def.Volume, "fading in fast (0.1 s of 0.15 s)")
	world.step(0.1)
	T.near(deck.Volume, def.Volume, 1e-6, "full volume after the 0.15 s box fade")
	T.eq(world.deck(lobby[1]), nil, "the lobby track is out as fast")
	-- the box ends: back to the lobby track with the normal fade
	world.setContext("Box", false)
	T.eq(S.NowPlaying().Key, "Lobby", "back to the round's track")
	world.advance(0.5, 0.1)
	local back = world.deck(lobby[1])
	local lobbyDef = Audio.Get("Lobby")
	T.ok(back ~= nil and back.Volume > lobbyDef.Volume * 0.3 and back.Volume < lobbyDef.Volume * 0.7, "normal ~1 s fade out of the box")
	-- a bad first candidate: Prewarm moves on to the next one in the background
	local world2 = loadSound(Loader)
	local S2 = world2.controller
	world2.fetch[lobby[1]] = "Success"
	world2.fetch[box[1]] = "Failure"
	world2.fetch[box[2]] = "Success"
	S2.Init()
	S2.Start()
	world2.advance(0.2)
	S2.Prewarm("VerdictBox")
	world2.advance(0.3)
	T.eq(S2.IdState(box[1]), "bad", "first candidate failed")
	T.eq(S2.IdState(box[2]), "good", "the next candidate checked right after")
	T.eq(S2.ActiveId("VerdictBox"), box[2], "the box would play the next candidate")
	T.noerror(function()
		S2.Prewarm("")
		S2.Prewarm("NoSuchEntry")
		S2.Prewarm("VerdictBox")
	end, "Prewarm ignores bad names and repeats")
end

return tests
