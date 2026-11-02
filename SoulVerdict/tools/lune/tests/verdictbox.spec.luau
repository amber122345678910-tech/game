--!nocheck
-- Tests for the Verdict Box: VerdictBox/Sim (determinism, colour rules, blue-soul gravity, platforms, collisions,
-- i-frames, fair hitboxes), VerdictBox/Patterns (every set covers the full duration for many seeds, chains,
-- determinism, red-mode reachability = a hit-free path exists), the strings file, the server rules
-- (VerdictBoxService.Rules: validation, hit rate limit, verdict) and a service integration run on the combat harness.

local roblox = require("@lune/roblox")
local Vector3, Vector2, Instance, Enum = roblox.Vector3, roblox.Vector2, roblox.Instance, roblox.Enum

local function load(Loader, name)
	return Loader.require("ReplicatedStorage.Shared.VerdictBox." .. name)
end

local function isFinite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- minimal hand-made timeline: one mode entry after a 0.1 s intro
local function timeline(Sim, mode, gravity, bullets, w, h, duration)
	local tl = {
		set = "Test",
		theme = "Classic",
		seed = 1,
		duration = duration or 10,
		introEnd = 0.1,
		line = "vb.line.Classic.1",
		modes = {
			{ t = 0, mode = "Intro", gravity = "Down", slam = false, w = w or 165, h = h or 165 },
			{ t = 0.1, mode = mode, gravity = gravity or "Down", slam = false, w = w or 165, h = h or 165 },
			{ t = duration or 10, mode = "End", gravity = gravity or "Down", slam = false, w = w or 165, h = h or 165 },
		},
		bullets = {},
		effects = {},
		segments = {},
	}
	for i, spec in bullets or {} do
		local b = Sim.Bullet(spec.kind, spec.spec)
		b.id = i
		table.insert(tl.bullets, b)
	end
	return tl
end

local function run(Sim, st, seconds, input)
	local hits = 0
	local n = math.floor(seconds * 60 + 0.5)
	for _ = 1, n do
		hits += Sim.Step(st, 1 / 60, input)
	end
	return hits
end

-- scripted input sequence: deterministic wiggle
local function scripted(i)
	local phase = i % 97
	return {
		x = math.sin(i * 0.13) > 0.2 and 1 or (math.sin(i * 0.13) < -0.2 and -1 or 0),
		y = math.cos(i * 0.07) > 0.3 and 1 or (math.cos(i * 0.07) < -0.3 and -1 or 0),
		jump = phase < 20,
		slow = phase > 80,
	}
end

local function replay(Sim, tl, frames)
	local st = Sim.new(tl)
	local trace = {}
	for i = 1, frames do
		Sim.Step(st, 1 / 60, scripted(i))
		if i % 15 == 0 then
			table.insert(trace, string.format("%.4f,%.4f,%d", st.soul.x, st.soul.y, st.hits))
		end
	end
	return table.concat(trace, ";"), st
end

local function serialize(tl)
	local parts = {}
	for _, b in tl.bullets do
		table.insert(
			parts,
			string.format("%s|%.5f|%.5f|%.4f|%.4f|%.4f|%.4f|%s", b.kind, b.t0, b.t1, b.x, b.y, b.vx, b.vy, b.color)
		)
	end
	for _, m in tl.modes do
		table.insert(parts, string.format("M%s%.4f%s%s", m.mode, m.t, m.gravity, tostring(m.slam)))
	end
	return table.concat(parts, "\n")
end

local tests = {}

---------------------------------------------------------------------------------------------------
-- Sim

tests.sim_soul_moves_and_stays_in_box = function(T, Loader)
	local Sim = load(Loader, "Sim")
	local tl = timeline(Sim, "Red")
	local st = Sim.new(tl)
	run(Sim, st, 0.2, {})
	T.ok(st.soul.active, "soul active after the intro")
	T.near(st.soul.x, 0, 1e-9, "spawns at the centre")
	run(Sim, st, 0.5, { x = 1 })
	T.near(st.soul.x, 75, 1.0, "moved ~150 px/s for 0.5 s")
	run(Sim, st, 2, { x = 1, y = -1 })
	T.near(st.soul.x, 165 / 2 - Sim.Tuning.SoulHalf, 1e-6, "clamped at the right wall (sprite inside)")
	T.near(st.soul.y, -(165 / 2 - Sim.Tuning.SoulHalf), 1e-6, "clamped at the top wall")
	local x0 = st.soul.x
	run(Sim, st, 0.5, { x = -1, slow = true })
	T.near(x0 - st.soul.x, 37.5, 1.0, "slow movement = half speed")
	run(Sim, st, 0.1, { x = 0 / 0, y = math.huge })
	T.ok(isFinite(st.soul.x) and isFinite(st.soul.y), "NaN / inf input is ignored")
end

tests.sim_determinism = function(T, Loader)
	local Sim, Patterns = load(Loader, "Sim"), load(Loader, "Patterns")
	for _, set in Patterns.SetIds do
		local tl1 = Patterns.Build(set, 4242, 7)
		local tl2 = Patterns.Build(set, 4242, 7)
		local a, sa = replay(Sim, tl1, 7 * 60)
		local b, sb = replay(Sim, tl2, 7 * 60)
		T.eq(a, b, set .. ": same seed + same inputs -> identical soul trace and hits")
		T.eq(sa.hits, sb.hits, set .. ": identical hit count")
		-- frame-rate independence: 30 fps steps with the same per-tick input give the same result
		local st = Sim.new(tl1)
		for i = 1, 7 * 30 do
			Sim.Step(st, 1 / 30, { x = 1, jump = true })
		end
		local st2 = Sim.new(tl1)
		for i = 1, 7 * 60 do
			Sim.Step(st2, 1 / 60, { x = 1, jump = true })
		end
		T.near(st.soul.x, st2.soul.x, 1e-9, set .. ": fixed tick (30 vs 60 fps) x")
		T.near(st.soul.y, st2.soul.y, 1e-9, set .. ": fixed tick (30 vs 60 fps) y")
		T.eq(st.hits, st2.hits, set .. ": fixed tick hits")
	end
end

tests.sim_color_rules = function(T, Loader)
	local Sim = load(Loader, "Sim")
	T.ok(Sim.ColorHurts("White", false) and Sim.ColorHurts("White", true), "white always hurts")
	T.ok(Sim.ColorHurts("Blue", true) and not Sim.ColorHurts("Blue", false), "blue only while moving")
	T.ok(Sim.ColorHurts("Orange", false) and not Sim.ColorHurts("Orange", true), "orange only while still")
	-- a long bone parked on the soul
	for _, case in { { "Blue", {}, 0 }, { "Blue", { x = 1 }, 1 }, { "Orange", {}, 1 }, { "Orange", { x = 1 }, 0 } } do
		local color, input, expect = case[1], case[2], case[3]
		local tl = timeline(Sim, "Red", "Down", {
			{ kind = "Bone", spec = { t0 = 0.2, t1 = 0.4, x = 0, y = 0, len = 200, thick = 40, color = color } },
		})
		local st = Sim.new(tl)
		run(Sim, st, 0.18, {})
		local hits = run(Sim, st, 0.25, input)
		T.eq(hits, expect, ("%s bone, input x=%s -> %d hit(s)"):format(color, tostring(input.x), expect))
	end
	-- pushing against a wall does not count as moving (no displacement)
	local tl = timeline(Sim, "Red", "Down", {
		{ kind = "Bone", spec = { t0 = 1.6, t1 = 1.8, x = 70, y = 0, len = 200, thick = 40, color = "Blue" } },
	})
	local st = Sim.new(tl)
	local hits = run(Sim, st, 1.9, { x = 1 })
	T.eq(hits, 0, "blue bone vs a soul pressed into the wall: still")
end

tests.sim_iframes_and_events = function(T, Loader)
	local Sim = load(Loader, "Sim")
	local tl = timeline(Sim, "Red", "Down", {
		{ kind = "Bone", spec = { t0 = 0.1, t1 = 5, x = 0, y = 0, len = 300, thick = 60 } },
	})
	local st = Sim.new(tl, { hitInterval = 0.45 })
	local hits = run(Sim, st, 2.11, {})
	-- first hit on the first active tick, then one every 0.45 s
	T.eq(hits, 5, "hits limited by the invincibility interval")
	local hitEvents = 0
	for _, e in st.events do
		if e.kind == "Hit" then
			hitEvents += 1
		end
	end
	T.eq(hitEvents, 5, "one Hit event per hit")
	T.eq(st.events[#st.events].n, 5, "event carries the running hit count")
end

tests.sim_fair_hitbox = function(T, Loader)
	local Sim = load(Loader, "Sim")
	local tune = Sim.Tuning
	-- a vertical bone (thick 10) whose sprite overlaps the 16 px heart sprite but not the hurt circle
	local x = tune.HitRadius + 10 * tune.BoneShaft / 2 + 0.5
	local tl = timeline(Sim, "Red", "Down", {
		{ kind = "Bone", spec = { t0 = 0.1, t1 = 2, x = x, y = 0, len = 100, thick = 10 } },
	})
	local st = Sim.new(tl)
	T.eq(run(Sim, st, 1, {}), 0, "grazing bone (sprites overlap) does not hurt")
	T.ok(x < tune.SoulHalf + 5, "the sprites really overlap in this setup")
	local p = Sim.Pose(tl.bullets[1], 0.5)
	T.ok(Sim.Overlap(p, x - 1, 0, tune.HitRadius), "1 px closer hurts")
	-- rotated rectangle test
	local pose = Sim.NewPose()
	pose.hurt, pose.shape, pose.hx, pose.hy, pose.hw, pose.hh, pose.hangle = true, "Rect", 0, 0, 50, 3, math.pi / 4
	T.ok(Sim.Overlap(pose, 20, 20, 1), "point on the rotated axis")
	T.ok(not Sim.Overlap(pose, 20, -20, 1), "point across the rotated axis")
end

tests.sim_blue_gravity = function(T, Loader)
	local Sim = load(Loader, "Sim")
	local tune = Sim.Tuning
	local tl = timeline(Sim, "Blue", "Down", {}, 375, 140)
	local st = Sim.new(tl)
	run(Sim, st, 1.2, {})
	local floorY = 140 / 2 - tune.SoulHalf
	T.near(st.soul.y, floorY, 1e-6, "falls onto the floor")
	T.ok(st.soul.grounded, "grounded")
	-- full jump (held)
	local apex = st.soul.y
	for _ = 1, 120 do
		Sim.Step(st, 1 / 60, { jump = true })
		apex = math.min(apex, st.soul.y)
	end
	local full = floorY - apex
	T.ok(full > 55 and full < 80, "full jump height ~60-75 px, got " .. full)
	run(Sim, st, 2, {})
	-- short hop: release after 0.1 s
	local st2 = Sim.new(tl)
	run(Sim, st2, 1.2, {})
	local apex2 = st2.soul.y
	for i = 1, 90 do
		Sim.Step(st2, 1 / 60, { jump = i <= 6 })
		apex2 = math.min(apex2, st2.soul.y)
	end
	local short = floorY - apex2
	T.ok(short > 5 and short < full * 0.6, "releasing jump cuts the height (" .. short .. " vs " .. full .. ")")
	-- "up" input also jumps; moving sideways while grounded
	local st3 = Sim.new(tl)
	run(Sim, st3, 1.2, {})
	Sim.Step(st3, 1 / 60, { y = -1 })
	T.ok(not st3.soul.grounded and st3.soul.y < floorY, "up = jump in gravity Down")
	-- gravity Left: lands on the left wall, jump = right
	local tlL = timeline(Sim, "Blue", "Left", {}, 375, 140)
	local s4 = Sim.new(tlL)
	run(Sim, s4, 2, {})
	T.near(s4.soul.x, -(375 / 2 - tune.SoulHalf), 1e-6, "gravity Left: on the left wall")
	run(Sim, s4, 0.3, { x = 1 })
	T.ok(s4.soul.x > -(375 / 2 - tune.SoulHalf) + 10, "gravity Left: right = jump")
	T.eq(Sim.SoulAngle("Left"), 90, "heart rotates toward gravity")
	-- slam: a slam entry hits the wall fast and reports a Slam event
	local tlS = timeline(Sim, "Blue", "Up", {}, 165, 165)
	tlS.modes[2].slam = true
	local s5 = Sim.new(tlS)
	run(Sim, s5, 0.25, {})
	T.near(s5.soul.y, -(165 / 2 - tune.SoulHalf), 1e-6, "slammed into the ceiling within 0.15 s")
	local slams = 0
	for _, e in s5.events do
		if e.kind == "Slam" then
			slams += 1
		end
	end
	T.eq(slams, 1, "one Slam event")
end

tests.sim_platforms_one_way = function(T, Loader)
	local Sim = load(Loader, "Sim")
	local tune = Sim.Tuning
	local top = 140 / 2 - 44
	local tl = timeline(Sim, "Blue", "Down", {
		{
			kind = "Platform",
			spec = { t0 = 0, t1 = 10, x = 0, y = top + tune.PlatformThick / 2, w = 66, vx = 30, minX = -20, maxX = 20 },
		},
	}, 375, 140)
	local st = Sim.new(tl)
	-- the soul starts at the centre (above the platform top) and lands on it
	run(Sim, st, 0.8, {})
	T.ok(st.soul.grounded and st.soul.platform ~= nil, "landed on the platform")
	T.near(st.soul.y, top - tune.SoulHalf, 1e-6, "standing on its top surface")
	local x0 = st.soul.x
	run(Sim, st, 0.3, {})
	T.ok(math.abs(st.soul.x - x0) > 3, "carried by the moving platform")
	T.ok(not st.soul.moving, "being carried is not 'moving' (blue rule)")
	-- walk off -> fall to the floor
	run(Sim, st, 1.0, { x = 1 })
	run(Sim, st, 0.8, {})
	T.near(st.soul.y, 140 / 2 - tune.SoulHalf, 1e-6, "walked off and fell to the floor")
	-- one-way: jumping from below passes through
	local st2 = Sim.new(tl)
	run(Sim, st2, 0.8, { x = -1 })
	run(Sim, st2, 1.2, { x = -1 }) -- off the platform's left end, on the floor
	local floorY = 140 / 2 - tune.SoulHalf
	T.near(st2.soul.y, floorY, 1e-6, "on the floor")
	local apex = floorY
	for _ = 1, 60 do
		Sim.Step(st2, 1 / 60, { jump = true, x = 1 })
		apex = math.min(apex, st2.soul.y)
	end
	T.ok(apex < top - tune.SoulHalf, "jumped up through the platform (one-way)")
end

tests.sim_stabs_beams_warn_first = function(T, Loader)
	local Sim = load(Loader, "Sim")
	local stab = Sim.Bullet("Stab", { t0 = 1, wall = "Bottom", a = -90, b = 90, height = 30, warn = 0.4, bw = 165, bh = 165 })
	T.near(stab.t1, 1 + 0.4 + 0.06 + 0.3 + 0.12, 1e-9, "stab lifetime from its phases")
	local p = Sim.Pose(stab, 1.2)
	T.eq(p.phase, "Warn", "warning phase")
	T.ok(not p.hurt, "a warning never hurts")
	T.near(p.fh * 2, 30, 1e-9, "warning outline = full stab height")
	p = Sim.Pose(stab, 1.6)
	T.eq(p.phase, "Hold", "hold phase")
	T.ok(Sim.Overlap(p, 0, 165 / 2 - 10, 4.5), "the raised stab hurts near the floor")
	T.ok(not Sim.Overlap(p, 0, 165 / 2 - 40, 4.5), "above the stab is safe")
	local bl = Sim.Bullet("Blaster", { t0 = 0, x = -120, y = 0, angle = 0, appear = 0.2, charge = 0.4, fire = 0.27, fade = 0.25 })
	T.ok(not Sim.Pose(bl, 0.5).hurt, "charging blaster does not hurt")
	local fire = Sim.Pose(bl, 0.75)
	T.eq(fire.phase, "Fire", "firing")
	T.ok(Sim.Overlap(fire, 0, 0, 4.5), "beam crosses the box")
	T.ok(not Sim.Overlap(fire, 0, 30, 4.5), "beam is ~26 px wide at scale 1")
	T.ok(not Sim.Pose(bl, 0.6 + 0.27 + 0.12).hurt, "a fading beam (< 80 % opaque) does not hurt")
	T.eq(Sim.Pose(bl, 2), nil, "inactive after its lifetime")
end

tests.sim_advance_and_auto_soul = function(T, Loader)
	local Sim, Patterns = load(Loader, "Sim"), load(Loader, "Patterns")
	local tl = Patterns.Build("Classic", 7, 7)
	local st = Sim.new(tl)
	Sim.AdvanceTo(st, 3.0, {})
	T.near(st.t, 3.0, 1 / 60 + 1e-9, "AdvanceTo reaches the target")
	Sim.AdvanceTo(st, 6.5, {}) -- far behind: capped work, skips ahead
	T.near(st.t, 6.5, 1 / 60 + 1e-9, "AdvanceTo skips ahead when far behind")
	for t = 0, 7, 0.1 do
		local x, y = Sim.AutoSoul(tl, t)
		local w, h = Sim.BoxAt(tl, t)
		T.ok(math.abs(x) <= w / 2 and math.abs(y) <= h / 2, "auto soul inside the box at " .. t)
	end
	local cx, cy = Sim.Clamp(tl, 3, 1e6, -1e6)
	local w, h = Sim.BoxAt(tl, 3)
	T.near(cx, w / 2 - Sim.Tuning.SoulHalf, 1e-9, "clamp x")
	T.near(cy, -(h / 2 - Sim.Tuning.SoulHalf), 1e-9, "clamp y")
	T.eq(Sim.IntroChars(tl, 0, 26), 0, "typewriter starts empty")
	T.eq(Sim.IntroChars(tl, tl.introEnd - 0.2, 26), 26, "short line fully typed before the attacks")
	T.eq(Sim.IntroChars(tl, tl.introEnd - 0.2, 60), 60, "long (translated) line types faster to fit")
end

---------------------------------------------------------------------------------------------------
-- Patterns

local SEEDS = 60

tests.patterns_cover_full_duration = function(T, Loader)
	local Sim, Patterns = load(Loader, "Sim"), load(Loader, "Patterns")
	local Config = Loader.require("ReplicatedStorage.Shared.Config")
	local D = Config.VerdictBox.Duration
	local pose = Sim.NewPose()
	for _, set in Patterns.SetIds do
		local maxGapSeen, minBullets, maxBullets = 0, math.huge, 0
		local names = {}
		for seed = 1, SEEDS do
			local ok, tl = pcall(Patterns.Build, set, seed * 7919 + 13, D)
			T.ok(ok, set .. " seed " .. seed .. " builds: " .. tostring(not ok and tl or ""))
			if not ok then
				continue
			end
			T.eq(tl.duration, D, "duration = Config.VerdictBox.Duration")
			T.eq(#tl.segments, Patterns.SEGMENTS, set .. ": 8 attack segments")
			T.near(tl.segments[1].t0, tl.introEnd, 1e-9, "first attack right after the intro line")
			for i = 2, #tl.segments do
				T.near(tl.segments[i].t0, tl.segments[i - 1].t1, 1e-9, "segments chained back to back")
			end
			T.near(tl.segments[#tl.segments].t1, D - Patterns.END_PAD, 1e-9, "chain fills exactly the duration")
			T.ok(tl.segments[#tl.segments].k == 1 and tl.segments[1].k == 0, "escalation 0 -> 1")
			T.eq(tl.modes[1].mode, "Intro", "intro first")
			T.eq(tl.modes[#tl.modes].mode, "End", "end last")
			T.near(tl.modes[#tl.modes].t, D, 1e-9, "ends at the duration")
			for i = 2, #tl.modes do
				T.ok(tl.modes[i].t >= tl.modes[i - 1].t, "modes sorted")
			end
			T.ok(Loader.require("ReplicatedStorage.Shared.Strings").L(tl.line) ~= tl.line, "opening line has a string")
			for _, s in tl.segments do
				names[s.name] = true
			end
			minBullets = math.min(minBullets, #tl.bullets)
			maxBullets = math.max(maxBullets, #tl.bullets)
			for i, b in tl.bullets do
				if not (b.id == i and b.t0 < b.t1 and b.t1 <= D + 1e-9 and b.t0 >= tl.introEnd - 0.2) then
					T.ok(false, ("%s seed %d bullet %d (%s) bad timing %.3f..%.3f"):format(set, seed, i, b.kind, b.t0, b.t1))
					break
				end
				for _, key in { "x", "y", "vx", "vy", "len", "thick", "angle" } do
					if not isFinite(b[key]) then
						T.ok(false, set .. " non-finite " .. key)
					end
				end
			end
			-- no dead air: some bullet (incl. warnings / charging blasters) on screen all through the attacks
			local lastBusy = tl.introEnd + 0.25
			for t = tl.introEnd + 0.25, D - Patterns.END_PAD, 0.05 do
				local busy = false
				for _, b in tl.bullets do
					if b.kind ~= "Platform" and b.kind ~= "Rift" and t >= b.t0 and t <= b.t1 then
						local p = Sim.Pose(b, t, pose)
						if p then
							busy = true
							break
						end
					end
				end
				if busy then
					maxGapSeen = math.max(maxGapSeen, t - lastBusy)
					lastBusy = t
				end
			end
			maxGapSeen = math.max(maxGapSeen, D - Patterns.END_PAD - lastBusy)
			-- every segment spawns something inside its window
			for _, s in tl.segments do
				local any = false
				for _, b in tl.bullets do
					if b.t0 >= s.t0 - 0.13 and b.t0 < s.t1 then
						any = true
						break
					end
				end
				T.ok(any, ("%s seed %d: segment %s spawns bullets"):format(set, seed, s.name))
			end
		end
		T.ok(maxGapSeen <= 0.5, ("%s: longest empty stretch %.2f s"):format(set, maxGapSeen))
		local list = {}
		for n in names do
			table.insert(list, n)
		end
		table.sort(list)
		print(("  %s: %d-%d bullets, max dead air %.2f s, segments used: %s"):format(set, minBullets, maxBullets, maxGapSeen, table.concat(list, ",")))
		T.ok(#list >= 8, set .. " uses at least 8 distinct segment types over the seeds")
	end
end

tests.patterns_deterministic_and_varied = function(T, Loader)
	local Patterns = load(Loader, "Patterns")
	for _, set in Patterns.SetIds do
		local a = serialize(Patterns.Build(set, 99, 7))
		local b = serialize(Patterns.Build(set, 99, 7))
		T.eq(a, b, set .. ": same seed -> identical timeline")
		local distinct = {}
		for seed = 1, 12 do
			distinct[serialize(Patterns.Build(set, seed, 7))] = true
		end
		local n = 0
		for _ in distinct do
			n += 1
		end
		T.ok(n >= 10, set .. ": seeds give different timelines (" .. n .. "/12)")
		local chain = Patterns.Chain(set, 99)
		T.eq(#chain, Patterns.SEGMENTS, set .. " chain length")
	end
	T.eq(Patterns.Resolve("Nope"), "Classic", "unknown set -> Classic")
	T.eq(Patterns.Build("Nope", 1, 7).set, "Classic", "build falls back to Classic")
	T.ok(Patterns.Has("Fell") and not Patterns.Has(nil), "Has")
	local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
	for _, kit in Kits.ForRole("Monster") do
		T.ok(Patterns.Has(kit.VerdictBox), kit.Id .. " VerdictBox set exists: " .. tostring(kit.VerdictBox))
	end
	-- a short duration still works (tunable)
	local tl = Patterns.Build("Eclipse", 5, 4)
	T.near(tl.segments[#tl.segments].t1, 4 - Patterns.END_PAD, 1e-9, "4 s box fills exactly")
end

-- Red-mode fairness: a hit-free path exists. Grid reachability through time: a cell is safe at t when no White
-- bullet's hurt shape covers it (Blue = the soul can stand still, Orange = it can wiggle in place); reachable cells
-- spread at the soul speed. The reachable set must never become empty during red-mode segments.
tests.patterns_red_segments_have_a_hit_free_path = function(T, Loader)
	local Sim, Patterns = load(Loader, "Sim"), load(Loader, "Patterns")
	local tune = Sim.Tuning
	local pose = Sim.NewPose()
	local STEP = 1 / 30
	local CELL = 6
	for _, set in Patterns.SetIds do
		for _, seed in { 3, 17, 101 } do
			local tl = Patterns.Build(set, seed, 7)
			for _, seg in tl.segments do
				if seg.mode == "Red" then
					local w, h = 165, 165
					local hx, hy = w / 2 - tune.SoulHalf, h / 2 - tune.SoulHalf
					local nx, ny = math.floor(2 * hx / CELL) + 1, math.floor(2 * hy / CELL) + 1
					local reach = {}
					for i = 0, nx - 1 do
						for j = 0, ny - 1 do
							reach[i * ny + j] = true
						end
					end
					local spread = math.floor(tune.SoulSpeed * STEP / CELL + 1e-6)
					local t = seg.t0 + 0.2
					local alive = true
					while t < seg.t1 and alive do
						-- active white bullets at t
						local active = {}
						for _, b in tl.bullets do
							if b.color == "White" and t >= b.t0 and t <= b.t1 then
								local p = Sim.Pose(b, t, Sim.NewPose())
								if p and p.hurt then
									table.insert(active, p)
								end
							end
						end
						local nextReach = {}
						local count = 0
						for i = 0, nx - 1 do
							for j = 0, ny - 1 do
								local can = false
								for di = -spread, spread do
									for dj = -spread, spread do
										if reach[(i + di) * ny + (j + dj)] and i + di >= 0 and i + di < nx and j + dj >= 0 and j + dj < ny then
											can = true
											break
										end
									end
									if can then
										break
									end
								end
								if can then
									local x, y = -hx + i * CELL, -hy + j * CELL
									for _, p in active do
										if Sim.Overlap(p, x, y, tune.HitRadius) then
											can = false
											break
										end
									end
								end
								if can then
									nextReach[i * ny + j] = true
									count += 1
								end
							end
						end
						reach = nextReach
						if count == 0 then
							alive = false
							T.ok(false, ("%s seed %d: no hit-free path in %s at t=%.2f"):format(set, seed, seg.name, t))
						end
						t += STEP
					end
					if alive then
						T.ok(true)
					end
				end
			end
		end
	end
	local _ = pose
end

tests.strings_complete = function(T, Loader)
	local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
	local Patterns = load(Loader, "Patterns")
	local file = Loader.requirePath("src/shared/Strings/VerdictBox")
	for key, entry in file do
		T.ok(string.sub(key, 1, 3) == "vb.", "prefix " .. key)
		T.ok(type(entry.en) == "string" and type(entry.ru) == "string", "en + ru for " .. key)
		local _, ne = string.gsub(entry.en, "{%d}", "")
		local _, nr = string.gsub(entry.ru, "{%d}", "")
		T.eq(ne, nr, "same placeholders " .. key)
	end
	for _, set in Patterns.SetIds do
		for _, key in Patterns.Lines(set) do
			T.ok(file[key] ~= nil, "opening line " .. key)
			T.ok(#file[key].en <= 34, "line short enough for the 1.15 s intro: " .. key)
			T.ok(string.sub(file[key].en, 1, 2) == "* ", "dialogue starts with '* ': " .. key)
		end
	end
	T.ok(Strings.L("vb.verdict.Innocent") == "INNOCENT", "merged into Strings")
end

---------------------------------------------------------------------------------------------------
-- Server: pure rules

local function service(Loader)
	return Loader.requirePath("src/server/Services/VerdictBoxService")
end

tests.server_rules_pure = function(T, Loader)
	local VB = service(Loader)
	local R = VB.Rules
	local Config = Loader.require("ReplicatedStorage.Shared.Config")
	local c = Config.VerdictBox
	local m = { team = "Monster", up = true, pos = Vector3.new(0, 3, 0) }
	local v = { team = "Humans", up = true, boxed = false, pos = Vector3.new(0, 3, -12) }
	T.ok(R.CheckPair(m, v, true), "valid pair")
	T.eq(select(2, R.CheckPair(m, v, false)), "los", "needs line of sight")
	T.eq(select(2, R.CheckPair({ team = "Humans", up = true, pos = m.pos }, v, true)), "role", "monster only")
	T.eq(select(2, R.CheckPair(m, { team = "Monster", up = true, pos = v.pos }, true)), "target", "humans only")
	T.eq(select(2, R.CheckPair(m, { team = "Humans", up = false, pos = v.pos }, true)), "down", "victim must be up (not Downed)")
	T.eq(select(2, R.CheckPair({ team = "Monster", up = false, pos = m.pos }, v, true)), "caster", "monster must be up")
	T.eq(select(2, R.CheckPair(m, { team = "Humans", up = true, boxed = true, pos = v.pos }, true)), "boxed", "not twice")
	T.eq(select(2, R.CheckPair(m, { team = "Humans", up = true, pos = Vector3.new(0, 3, -(c.Range + 12)) }, true)), "range", "range + slack")
	T.ok(R.CheckPair(m, { team = "Humans", up = true, pos = Vector3.new(0, 3, -(c.Range + 4)) }, true), "range slack tolerates lag")
	local looking = { team = "Monster", up = true, pos = m.pos, look = Vector3.new(0, 0, 1) }
	T.eq(select(2, R.CheckPair(looking, v, true)), "cone", "cone checked when a look direction is given")
	-- hit cap
	local intro = 1.0
	T.eq(R.AcceptHits(0, 3, 0.4, intro), 0, "no hits before the first attack (+ latency slack)")
	T.eq(R.AcceptHits(0, 1, intro + 0.01, intro), 1, "first hit right away")
	T.eq(R.AcceptHits(1, 1, intro + 0.05, intro), 0, "second hit needs MinHitInterval")
	T.eq(R.AcceptHits(0, 5, intro + 0.5, intro), 2, "capped by elapsed / interval")
	T.eq(R.AcceptHits(0, 1e9, 30, intro), math.floor((c.Duration - intro) / c.MinHitInterval) + 1 > 8 and 8 or math.floor((c.Duration - intro) / c.MinHitInterval) + 1, "per-packet and per-box caps")
	for _, bad in { 0 / 0, -1, "3", nil, 0.5 } do
		T.eq(R.AcceptHits(0, bad, 5, intro), 0, "garbage report " .. tostring(bad))
	end
	-- verdict
	T.ok(R.Verdict(0, "Duration", true), "no hits -> survived")
	T.ok(R.Verdict(c.SurviveMaxHits, "Duration", true), "<= SurviveMaxHits -> survived")
	T.ok(not R.Verdict(c.SurviveMaxHits + 1, "Duration", true), "too many hits")
	T.ok(not R.Verdict(0, "Cancelled", true), "cancelled boxes give nothing")
	T.ok(not R.Verdict(0, "Duration", false), "downed victims did not survive")
	T.eq(R.VerdictName(0, "Duration", true), "Innocent", "verdict name")
	T.eq(R.VerdictName(3, "Duration", false), "Guilty", "verdict name")
	T.eq(R.VerdictName(0, "Cancelled", false), "Dismissed", "verdict name")
	-- soul relay validation
	T.ok(R.ValidSoul(10, -20), "valid soul")
	T.ok(not R.ValidSoul(0 / 0, 0) and not R.ValidSoul(1e6, 0) and not R.ValidSoul("1", 2), "invalid soul")
	-- bot hits
	local Rng = Loader.require("ReplicatedStorage.Shared.Util.Rng")
	for seed = 1, 50 do
		local times = R.BotHits(Rng.new(seed), intro)
		T.ok(#times >= 1 and #times <= 4, "bots take 1-4 hits")
		for i, t in times do
			T.ok(t >= intro + 0.3 and t <= c.Duration - 0.25, "bot hit inside the attacks")
			if i > 1 then
				T.ok(t - times[i - 1] >= c.MinHitInterval - 1e-9, "bot hits spaced by MinHitInterval")
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Server: integration on real StatusService / DamageService with a simulated clock and fake Net / world

local function harness(Loader)
	local H = { sent = {}, handlers = {}, models = {}, round = { Phase = "Round", TeamRevives = 2 } }
	local clock = 500
	local timers = {}
	function H.now()
		return clock
	end
	function H.advance(seconds)
		local target = clock + seconds
		while true do
			table.sort(timers, function(a, b)
				return a.at < b.at
			end)
			local first = timers[1]
			if first == nil or first.at > target then
				break
			end
			clock = math.max(clock, first.at)
			table.remove(timers, 1)
			first.fn()
		end
		clock = target
	end
	local G = getfenv(Loader.requirePath)
	G.workspace = {
		GetServerTimeNow = function()
			return clock
		end,
		Raycast = function()
			return nil
		end,
		FindFirstChild = function()
			return nil
		end,
	}
	G.RaycastParams = { new = function()
		return {}
	end }
	local Validation = Loader.requirePath("src/server/Combat/Validation")
	Validation.SetScheduler({
		wait = function(s)
			H.advance(s or 0)
			return s or 0
		end,
		delay = function(s, fn)
			table.insert(timers, { at = clock + s, fn = fn })
		end,
		defer = function(fn)
			table.insert(timers, { at = clock, fn = fn })
		end,
	})
	Validation.RoundAttr = function(name)
		return H.round[name]
	end
	local Signal = Loader.require("ReplicatedStorage.Shared.Util.Signal")
	H.playerOf = {}
	local CS = { Spawned = Signal.new(), Died = Signal.new(), Downed = Signal.new(), Revived = Signal.new(), Despawning = Signal.new() }
	function CS.GetAll()
		return H.models
	end
	function CS.GetPlayer(m)
		return H.playerOf[m]
	end
	function CS.SetDowned(m)
		m:SetAttribute("Downed", true)
	end
	function CS.Kill(m)
		m:SetAttribute("Dead", true)
	end
	H.CS = CS
	Validation.SetService("CharacterService", CS)
	Validation.SetService("StatsService", { Add = function() end })
	Validation.SetService("RoundService", { TriggerFinalPhase = function() end })
	local Net = Loader.require("ReplicatedStorage.Shared.Net")
	H.Net = Net
	Net.Server.FireAll = function(name, ...)
		table.insert(H.sent, { name = name, args = table.pack(...) })
	end
	Net.Server.Fire = function(name, player, ...)
		table.insert(H.sent, { name = name, player = player, args = table.pack(...) })
	end
	Net.Server.On = function(name, fn)
		H.handlers[name] = fn
		return { Disconnect = function() end }
	end
	H.players = {}
	H.S = {}
	for _, n in { "StatusService", "MovementService", "DamageService", "VerdictBoxService" } do
		H.S[n] = Loader.requirePath("src/server/Services/" .. n)
	end
	for _, n in { "StatusService", "MovementService", "DamageService", "VerdictBoxService" } do
		H.S[n].Init()
	end
	-- the Players mock lives in the module environments (game = the loader's mock); it is shared by every
	-- spec, so H.cleanup puts the original GetPlayers back (test hygiene)
	local playersMock = getfenv(H.S.VerdictBoxService.Open).game:GetService("Players")
	local originalGetPlayers = rawget(playersMock, "GetPlayers")
	playersMock.GetPlayers = function()
		return H.players
	end
	H.S.VerdictBoxService.Start() -- lifecycle hook: connects the remotes
	H.S.VerdictBoxService.SetSeedSource(function()
		return 4242
	end)
	local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
	local HazardDefs = Loader.require("ReplicatedStorage.Shared.Combat.HazardDefs")
	function H.spawn(kitId, team, pos, player)
		local kit = Kits.Get(kitId)
		local m = Instance.new("Model")
		m.Name = kitId .. "_" .. tostring(#H.models + 1)
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = HazardDefs.LookAlong(pos + Vector3.new(0, 3, 0), Vector3.new(0, 0, -1))
		root.Parent = m
		m.PrimaryPart = root
		local hum = Instance.new("Humanoid")
		hum.MaxHealth = kit.Stats.MaxHP
		hum.Health = kit.Stats.MaxHP
		hum.Parent = m
		m:SetAttribute("KitId", kitId)
		m:SetAttribute("Team", team)
		m:SetAttribute("Ult", 0)
		m:SetAttribute("Downed", false)
		m:SetAttribute("Dead", false)
		m:SetAttribute("KR", 0)
		if player == nil then
			m:SetAttribute("IsBot", true)
		end
		m.Parent = Instance.new("Folder")
		table.insert(H.models, m)
		H.playerOf[m] = player
		H.S.StatusService.Track(m)
		return m
	end
	function H.last(name)
		for i = #H.sent, 1, -1 do
			if H.sent[i].name == name then
				return H.sent[i].args, H.sent[i]
			end
		end
		return nil
	end
	function H.count(name, player)
		local n = 0
		for _, e in H.sent do
			if e.name == name and (player == nil or e.player == player) then
				n += 1
			end
		end
		return n
	end
	function H.hp(m)
		return m:FindFirstChildOfClass("Humanoid").Health
	end
	function H.cleanup()
		H.S.VerdictBoxService.CancelAll()
		H.S.VerdictBoxService.SetSeedSource(nil)
		Validation.SetScheduler(nil)
		G.workspace = nil
		G.RaycastParams = nil
		rawset(playersMock, "GetPlayers", originalGetPlayers)
	end
	return H
end

tests.server_box_lifecycle = function(T, Loader)
	Loader.reset()
	local H = harness(Loader)
	local ok, err = pcall(function()
		local VB, SS, DS = H.S.VerdictBoxService, H.S.StatusService, H.S.DamageService
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		local c = Config.VerdictBox
		local playersFolder = Instance.new("Folder")
		local function player(name, display, id)
			local p = Instance.new("Player")
			p.Name = name
			p.DisplayName = display
			p.UserId = id
			p.Parent = playersFolder
			return p
		end
		local p1 = player("P1", "Frisk", 1)
		local p2 = player("P2", "Kris", 2)
		H.players = { p1, p2 }
		local sans = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, 0), nil)
		local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -10), p1)
		local bot = H.spawn("Bravery", "Humans", Vector3.new(4, 0, -12), nil)
		local far = H.spawn("Justice", "Humans", Vector3.new(0, 0, -200), p2)

		T.ok(not VB.Start(sans, far), "out of range")
		T.ok(not VB.Start(human, sans), "humans cannot box")
		T.ok(VB.Start(sans, human), "box opened")
		T.ok(VB.IsBoxed(human) and not VB.IsBoxed(bot), "IsBoxed")
		T.ok(not VB.Start(sans, bot), "one box per monster")
		local args = H.last("BoxStart")
		local pk = args[1]
		T.ok(pk.boxId == 1 and pk.victim == human and pk.monster == sans, "BoxStart ids")
		T.eq(pk.seed, 4242, "seed")
		T.eq(pk.patternSet, "Classic", "kit pattern set")
		T.eq(pk.duration, c.Duration, "duration")
		T.eq(pk.damagePerHit, c.DamagePerHit, "damage per hit")
		T.eq(pk.krPerHit, c.KRPerHit, "KR per hit")
		T.ok(pk.box and pk.box:IsA("Model") and pk.box:GetAttribute("BoxId") == 1, "3D box model in the packet")
		local screen = pk.box:FindFirstChild("Screen", true)
		T.ok(screen and math.abs(screen.CFrame.Position.Y - (3 + c.Height)) < 1.5, "3D box floats Height above the victim")
		T.ok(SS.Has(human, "Boxed") and SS.Has(human, "Invulnerable"), "Boxed + Invulnerable")
		T.eq(human:GetAttribute("SoulMode"), "Boxed", "SoulMode Boxed")
		-- only box damage applies
		local hp0 = H.hp(human)
		DS.Apply({ Attacker = sans, Target = human, Amount = 30, Kind = "Melee" })
		T.eq(H.hp(human), hp0, "immune to normal damage while boxed")
		-- hit reports
		local tl = Loader.require("ReplicatedStorage.Shared.VerdictBox.Patterns").Build("Classic", 4242, c.Duration)
		H.handlers.BoxReport(p1, 1, 2, false)
		T.eq(H.hp(human), hp0, "no hits accepted during the intro")
		H.handlers.BoxReport(p2, 1, 1, false)
		T.eq(H.hp(human), hp0, "only the victim's client may report")
		H.advance(tl.introEnd + 0.5)
		local ult0 = sans:GetAttribute("Ult")
		H.handlers.BoxReport(p1, 1, 5, false)
		T.eq(H.hp(human), hp0 - 2 * c.DamagePerHit, "hits capped by MinHitInterval (2 of 5)")
		T.ok(human:GetAttribute("KR") > 0, "box hits add KR")
		T.ok(sans:GetAttribute("Ult") >= ult0 + 2 * c.MonsterUltPerHit, "monster ult per hit")
		H.handlers.BoxReport(p1, 1, "x", "y")
		H.handlers.BoxReport(p1, 99, 1, false)
		-- soul relay
		H.handlers.BoxSoul(p1, 1, 12.34, -5)
		local relayed = H.count("BoxSoul", p2)
		T.eq(relayed, 1, "relayed to the other player")
		T.eq(H.count("BoxSoul", p1), 0, "not echoed to the victim")
		local ra = H.last("BoxSoul")
		T.ok(ra[1] == 1 and math.abs(ra[2] - 12.3) < 1e-6 and ra[4] == 2, "relay = (boxId, x, y, hits)")
		H.handlers.BoxSoul(p1, 1, 1, 1)
		T.eq(H.count("BoxSoul", p2), 1, "rate limited to 15 Hz")
		H.advance(0.1)
		H.handlers.BoxSoul(p1, 1, 0 / 0, 1)
		H.handlers.BoxSoul(p2, 1, 1, 1)
		T.eq(H.count("BoxSoul", p2), 1, "invalid / foreign soul packets dropped")
		H.handlers.BoxSoul(p1, 1, 1, 1)
		T.eq(H.count("BoxSoul", p2), 2, "next valid sample relayed")
		-- end at the duration
		local ended = nil
		VB.Ended:Connect(function(id, victim, hits, survived)
			ended = { id = id, victim = victim, hits = hits, survived = survived }
		end)
		H.advance(c.Duration - (tl.introEnd + 0.6) + 0.15) -- just past the end (the 3D box lingers 0.9 s)
		local endArgs = H.last("BoxEnd")
		T.ok(endArgs and endArgs[1] == 1 and endArgs[2].hits == 2 and endArgs[2].survived == false, "BoxEnd {hits, survived}")
		T.eq(endArgs[2].reason, "Duration", "ended by the clock")
		T.ok(ended and ended.victim == human and ended.hits == 2, "Ended signal")
		T.ok(not SS.Has(human, "Boxed") and not SS.Has(human, "Invulnerable"), "statuses removed")
		T.ok(human:GetAttribute("SoulMode") ~= "Boxed", "SoulMode restored")
		T.ok(not VB.IsBoxed(human), "no longer boxed")
		T.eq(pk.box:GetAttribute("Verdict"), "Guilty", "verdict shown on the 3D box")
		T.ok(not SS.Has(human, "DamageUp"), "2 hits: no survive buff")
		H.advance(1.0)
		T.ok(pk.box.Parent == nil, "3D box removed after showing the verdict")

		-- survive: <= SurviveMaxHits -> DamageUp + ult
		human:SetAttribute("Ult", 0)
		T.ok(VB.Start(sans, human), "second box")
		H.advance(tl.introEnd + 0.2)
		H.handlers.BoxReport(p1, 2, 1, true)
		H.advance(c.Duration)
		local e2 = H.last("BoxEnd")
		T.ok(e2[1] == 2 and e2[2].survived == true and e2[2].hits == 1, "survived with one hit")
		T.ok(SS.Has(human, "DamageUp"), "survive buff DamageUp")
		T.ok(human:GetAttribute("Ult") >= c.SurviveUlt, "survive ult")
		local _, mult = SS.Get(human, "DamageUp")
		T.ok(mult and mult.mult == c.SurviveDamageMult, "DamageUp mult")

		-- HP floor: box damage never drops below 1
		local hum = human:FindFirstChildOfClass("Humanoid")
		hum.Health = 3
		T.ok(VB.Start(sans, human), "third box")
		H.advance(tl.introEnd + 3)
		H.handlers.BoxReport(p1, 3, 6, false)
		T.ok(H.hp(human) >= 1, "box damage keeps 1 HP")
		T.ok(not human:GetAttribute("Downed"), "never downed inside the box")
		-- cancel (round end)
		VB.CancelAll()
		local e3 = H.last("BoxEnd")
		T.ok(e3[1] == 3 and e3[2].reason == "Cancelled" and e3[2].survived == false, "cancelled")
		T.ok(not SS.Has(human, "Boxed"), "cancel removes statuses")

		-- bot victims auto-resolve with 1-4 hits
		local botHp = H.hp(bot)
		T.ok(VB.Start(sans, bot), "bot box")
		T.ok(H.last("BoxStart")[1].bot == true, "packet flags bot victims")
		H.advance(c.Duration + 0.2)
		local e4 = H.last("BoxEnd")
		T.ok(e4[1] == 4 and e4[2].hits >= 1 and e4[2].hits <= 4, "bot took 1-4 hits: " .. tostring(e4[2].hits))
		T.near(botHp - H.hp(bot), e4[2].hits * c.DamagePerHit, 1e-6, "bot damage applied per hit")

		-- victim leaves / dies mid-box
		T.ok(VB.Start(sans, human), "fifth box")
		H.advance(1)
		human:SetAttribute("Dead", true)
		H.advance(0.25)
		local e5 = H.last("BoxEnd")
		T.ok(e5[1] == 5 and e5[2].reason == "VictimGone", "ends when the victim is gone")
		-- Ending phase refuses
		human:SetAttribute("Dead", false)
		H.round.Phase = "Ending"
		T.ok(not VB.Start(sans, bot), "no box during the Ending phase")
	end)
	H.cleanup()
	Loader.reset()
	if not ok then
		error(err, 0)
	end
end

---------------------------------------------------------------------------------------------------
-- Client: renderer + controller helpers

tests.view_renders_every_set_without_leaks = function(T, Loader)
	local View = Loader.requirePath("src/client/UI/VerdictBoxView")
	local Patterns, Sim = load(Loader, "Patterns"), load(Loader, "Sim")
	local px = 0
	for _, r in View.SOUL_ROWS do
		px += (r[3] - r[2] + 1) * r[4]
	end
	T.eq(px, 186, "the 16x16 heart sprite has 186 filled pixels")
	local hud = { name = "Frisk", lv = 7, hp = 60, maxHp = 110, kr = 9 }
	for _, set in Patterns.SetIds do
		local tl = Patterns.Build(set, 31, 7)
		for _, mode in { "Overlay", "Mirror" } do
			local size = if mode == "Overlay" then Vector2.new(1600, 900) else Vector2.new(312, 312)
			local v = View.new(nil, tl, { Mode = mode, Size = size, Name = "Kris" })
			local function pass()
				for t = 0, 7.4, 1 / 20 do
					local x, y = Sim.AutoSoul(tl, t)
					local m = Sim.ModeAt(tl, t)
					v:Render(t, { x = x, y = y, mode = m.mode, gravity = m.gravity, blink = t % 1 < 0.2 }, hud)
				end
			end
			local ok, err = pcall(pass)
			T.ok(ok, ("%s %s renders the whole box: %s"):format(set, mode, tostring(err or "")))
			local count1 = #v.Root:GetDescendants()
			pcall(pass)
			T.eq(#v.Root:GetDescendants(), count1, set .. " " .. mode .. ": pooled drawables (no growth on replay)")
			T.ok(count1 < 2500, set .. " " .. mode .. " instance budget: " .. count1)
			T.noerror(function()
				v:Hit(3, 5, 3)
				v:Pulse(3)
				v:SetHint("hint")
				v:SetVerdict("Innocent", "sub")
				v:SetOpen(0.3)
				v:Render(3.1, nil, nil)
				v:SetOpen(1)
				v:SetVerdict(nil)
				v:Destroy()
			end, set .. " " .. mode .. " controls")
		end
	end
	-- preview wrapper (dump_gui contract)
	local handle = View.Create(nil, { Set = "Fell", Seed = 3, Kind = "Overlay", Time = 3, HitAt = 2.9, Verdict = "Guilty" })
	T.ok(handle and handle.Root and type(handle.Destroy) == "function", "Create(theme, deps) -> {Root, Destroy}")
	handle.Destroy()
end

tests.controller_pure_helpers = function(T, Loader)
	local C = Loader.requirePath("src/client/Controllers/VerdictBoxController")
	T.eq(C.Priority, 40, "priority 40 (SPEC §20)")
	local samples = { { 1, 0, 0 }, { 1.1, 10, -10 }, { 1.2, 20, -20 } }
	local x, y = C.Interpolate(samples, 1.05)
	T.near(x, 5, 1e-9, "interpolate x")
	T.near(y, -5, 1e-9, "interpolate y")
	x, y = C.Interpolate(samples, 0.5)
	T.eq(x, 0, "clamped before the first sample")
	x, y = C.Interpolate(samples, 9)
	T.eq(x, 20, "clamped after the last sample")
	T.eq(C.Interpolate({}, 1), nil, "no samples")
	local tx, ty = C.TouchVector(Vector2.new(100, 100), Vector2.new(100 + 28, 100), 56)
	T.near(tx, 0.5, 1e-9, "half radius = half speed")
	T.near(ty, 0, 1e-9, "no vertical")
	tx, ty = C.TouchVector(Vector2.new(0, 0), Vector2.new(0, 500), 56)
	T.near(ty, 1, 1e-9, "full speed beyond the radius")
	tx, ty = C.TouchVector(Vector2.new(0, 0), Vector2.new(3, 0), 56)
	T.eq(tx, 0, "deadzone")
	-- (Lune EnumItems are not interned: compare with == instead of table keys)
	local kx, ky, jump, slow = C.KeyAxes(function(k)
		return k == Enum.KeyCode.A or k == Enum.KeyCode.Up or k == Enum.KeyCode.Space
	end)
	T.ok(kx == -1 and ky == -1 and jump and not slow, "WASD / arrows / space")
	T.eq(C.VerdictKind({ survived = true, reason = "Duration" }), "Innocent", "verdict kind")
	T.eq(C.VerdictKind({ survived = false, reason = "Duration" }), "Guilty", "verdict kind")
	T.eq(C.VerdictKind({ survived = false, reason = "Cancelled" }), "Dismissed", "verdict kind")
	T.eq(C.VerdictKind(nil), "Dismissed", "verdict kind (no result)")
end

return tests
