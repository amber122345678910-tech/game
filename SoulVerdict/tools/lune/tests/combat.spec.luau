--!nocheck
-- Combat core unit tests: Teams, HitTest, HazardDefs (every type), DamageMath.
-- Run: lune run tools/lune/run_tests.luau combat
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Instance = roblox.Instance

local function load(Loader, name)
	return Loader.require("ReplicatedStorage.Shared.Combat." .. name)
end

-- Character capsule standing on the ground at (x, 0, z): root at y = 3 (feet 3 below the root).
local function charAt(HitTest, x, z, feetY)
	local feet = feetY or 0
	return HitTest.CharacterCapsule(Vector3.new(x, feet + 3, z), 1, 3)
end

local function anyHit(HitTest, cap, volumes, forgiveness)
	for _, v in volumes do
		if HitTest.Hits(cap, v, forgiveness) then
			return true
		end
	end
	return false
end

local function model(team, kit)
	local m = Instance.new("Model")
	if team then
		m:SetAttribute("Team", team)
	end
	if kit then
		m:SetAttribute("KitId", kit)
	end
	return m
end

-- brute-force squared distance from a segment to a volume using PointDistance samples
local function bruteSegDist(HitTest, a, b, vol, n)
	local best = math.huge
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		local d = HitTest.PointDistance(p, vol)
		if d < best then
			best = d
		end
	end
	return best
end

-- brute-force point-to-box distance (independent of HitTest internals)
local function pointBoxDist(p, cf, size)
	local l = cf:PointToObjectSpace(p)
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local dx = math.max(0, math.abs(l.X) - hx)
	local dy = math.max(0, math.abs(l.Y) - hy)
	local dz = math.max(0, math.abs(l.Z) - hz)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local tests = {
	---------------------------------------------------------------------------------------------
	-- Teams
	teams_rules = function(T, Loader)
		local Teams = load(Loader, "Teams")
		local h1, h2 = model("Humans"), model("Humans")
		local mon = model("Monster")
		local lobby, lobby2 = model("Lobby"), model("Lobby")
		local dummy = model("Dummy", "Dummy")
		local dummyNoTeam = model(nil, "Dummy")
		local nobody = model(nil)
		T.ok(Teams.AreEnemies(h1, mon) and Teams.AreEnemies(mon, h1), "humans vs monster")
		T.ok(not Teams.AreEnemies(h1, h2), "same team never")
		T.ok(not Teams.AreEnemies(h1, h1), "self never")
		T.ok(
			Teams.AreEnemies(h1, dummy) and Teams.AreEnemies(mon, dummy) and Teams.AreEnemies(dummy, mon),
			"dummy enemy of all"
		)
		T.ok(not Teams.AreEnemies(dummy, dummyNoTeam), "dummy vs dummy")
		T.eq(Teams.TeamOf(dummyNoTeam), "Dummy", "KitId Dummy -> Dummy team")
		T.ok(Teams.AreEnemies(lobby, dummy), "lobby hits dummies")
		T.ok(
			not Teams.AreEnemies(lobby, h1) and not Teams.AreEnemies(lobby, mon) and not Teams.AreEnemies(mon, lobby),
			"lobby only hits dummies"
		)
		T.ok(not Teams.AreEnemies(lobby, lobby2), "lobby vs lobby")
		T.ok(not Teams.AreEnemies(nobody, mon) and not Teams.AreEnemies(nobody, dummy), "no team = nobody's enemy")
		T.ok(not Teams.AreEnemies(nil, mon), "nil")
		T.ok(Teams.AreAllies(h1, h2) and Teams.AreAllies(h1, h1), "allies")
		T.ok(not Teams.AreAllies(h1, mon) and not Teams.AreAllies(dummy, dummyNoTeam), "dummies are nobody's allies")
		T.ok(Teams.AreEnemyTeams("Monster", "Humans") and not Teams.AreEnemyTeams("Monster", "Monster"), "string form")
		T.ok(not Teams.AreEnemyTeams("", "Dummy"), "empty team vs dummy")
	end,

	---------------------------------------------------------------------------------------------
	-- HitTest
	hittest_character_capsule = function(T, Loader)
		local HitTest = load(Loader, "HitTest")
		local cap = HitTest.CharacterCapsule(Vector3.new(0, 3, 0), 1, 3)
		T.near(cap.A.Y, 1.1, 1e-6, "A.y")
		T.near(cap.B.Y, 3.9, 1e-6, "B.y")
		T.near(cap.R, 1.1, 1e-6, "R")
		local big = HitTest.CharacterCapsule(Vector3.new(0, 3.3, 0), 1.1, 3.3)
		T.near(big.R, 1.21, 1e-6, "scaled R")
		T.near(big.B.Y + big.R, 5.5, 1e-6, "scaled top = feet + 5*1.1")
		local default = HitTest.CharacterCapsule(Vector3.new(0, 3, 0))
		T.near(default.A.Y - default.R, 0, 1e-6, "default ground offset 0.6*H")
	end,

	hittest_box = function(T, Loader)
		local HitTest = load(Loader, "HitTest")
		local cap = charAt(HitTest, 0, 0)
		T.ok(not HitTest.CapsuleVsBox(cap, CFrame.new(2.5, 2, 0), Vector3.new(2, 2, 2)), "face at x=1.5 misses (R=1.1)")
		T.ok(HitTest.CapsuleVsBox(cap, CFrame.new(2.5, 2, 0), Vector3.new(3, 2, 2)), "face at x=1.0 hits")
		T.ok(
			not HitTest.CapsuleVsBox(cap, CFrame.new(0, 6.2, 0), Vector3.new(4, 2, 4)),
			"box above head misses (bottom 5.2 > top 5.0)"
		)
		T.ok(HitTest.CapsuleVsBox(cap, CFrame.new(0, 5.8, 0), Vector3.new(4, 2, 4)), "box touching head hits")
		T.ok(HitTest.CapsuleVsBox(cap, CFrame.new(0, 2, 0), Vector3.new(0.2, 0.2, 0.2)), "tiny box inside the body")
		-- rotated box: 45 deg about Y, corner points at the capsule
		local cf = CFrame.new(2.4, 2, 0) * CFrame.Angles(0, math.rad(45), 0)
		local size = Vector3.new(2, 2, 2)
		local exact = math.sqrt(HitTest.SegmentDistanceSq(cap.A, cap.B, { Shape = "Box", CFrame = cf, Size = size }))
		T.near(exact, 2.4 - math.sqrt(2), 1e-6, "rotated box corner distance")
		-- random property test vs brute force
		local Rng = Loader.require("ReplicatedStorage.Shared.Util.Rng")
		local rng = Rng.new(42)
		local worst = 0
		for _ = 1, 150 do
			local a = Vector3.new(rng:Number(-6, 6), rng:Number(-6, 6), rng:Number(-6, 6))
			local b = a + Vector3.new(rng:Number(-6, 6), rng:Number(-6, 6), rng:Number(-6, 6))
			local bcf = CFrame.new(rng:Number(-3, 3), rng:Number(-3, 3), rng:Number(-3, 3))
				* CFrame.Angles(rng:Number(0, 6.28), rng:Number(0, 6.28), rng:Number(0, 6.28))
			local bsize = Vector3.new(rng:Number(0.2, 5), rng:Number(0.2, 5), rng:Number(0.2, 5))
			local e = math.sqrt(HitTest.SegmentDistanceSq(a, b, { Shape = "Box", CFrame = bcf, Size = bsize }))
			local best = math.huge
			for i = 0, 2000 do
				local d = pointBoxDist(a:Lerp(b, i / 2000), bcf, bsize)
				if d < best then
					best = d
				end
			end
			T.ok(e <= best + 1e-6, "exact distance must not exceed sampled minimum")
			worst = math.max(worst, best - e)
		end
		T.ok(worst < 0.02, "exact vs brute force within sampling error, worst " .. worst)
	end,

	hittest_ball_capsule = function(T, Loader)
		local HitTest = load(Loader, "HitTest")
		local cap = charAt(HitTest, 0, 0)
		T.ok(HitTest.CapsuleVsBall(cap, Vector3.new(2, 2, 0), 1), "ball overlapping side")
		T.ok(not HitTest.CapsuleVsBall(cap, Vector3.new(2.2, 2, 0), 1), "ball 0.1 away")
		T.ok(HitTest.CapsuleVsBall(cap, Vector3.new(0, 6, 0), 1.05), "ball over head (top 5.0, ball bottom 4.95)")
		T.ok(not HitTest.CapsuleVsBall(cap, Vector3.new(0, 6.2, 0), 1.1), "ball above head")
		-- capsule vs capsule: horizontal bar crossing the body
		T.ok(HitTest.CapsuleVsCapsule(cap, Vector3.new(-5, 2, 1.5), Vector3.new(5, 2, 1.5), 0.5), "crossing bar")
		T.ok(
			not HitTest.CapsuleVsCapsule(cap, Vector3.new(-5, 2, 1.7), Vector3.new(5, 2, 1.7), 0.5),
			"bar just in front"
		)
		T.ok(not HitTest.CapsuleVsCapsule(cap, Vector3.new(2, 2, 0), Vector3.new(8, 2, 0), 0.8), "segment ends 2 away")
		T.ok(HitTest.CapsuleVsCapsule(cap, Vector3.new(1.8, 2, 0), Vector3.new(8, 2, 0), 0.8), "segment ends 1.8 away")
		local d2 = HitTest.ClosestSegmentPoints(
			Vector3.new(0, 0, 0),
			Vector3.new(0, 0, 0),
			Vector3.new(3, 4, 0),
			Vector3.new(3, 4, 0)
		)
		T.near(d2, 25, 1e-9, "degenerate segments")
		-- capsule volume shape uses Size.Y as tip-to-tip length
		local vol = {
			Shape = "Capsule",
			CFrame = CFrame.new(0, 2, -5) * CFrame.Angles(math.rad(90), 0, 0),
			Size = Vector3.new(1, 6, 1),
		}
		-- axis along Z: sphere centres at z = -7.5 and -2.5 (radius 0.5), tips at -8 and -2
		T.near(HitTest.PointDistance(Vector3.new(0, 2, -1), vol), 1.0, 1e-6, "capsule tip distance")
	end,

	hittest_cylinder_ring = function(T, Loader)
		local HitTest = load(Loader, "HitTest")
		local zone = CFrame.new(0, 3, 0)
		T.ok(HitTest.CapsuleVsCylinder(charAt(HitTest, 9.5, 0), zone, 18, 6), "radius 9 + R 1.1 reaches 9.5")
		T.ok(not HitTest.CapsuleVsCylinder(charAt(HitTest, 10.2, 0), zone, 18, 6), "10.2 is outside")
		T.ok(HitTest.CapsuleVsCylinder(charAt(HitTest, 0, 0), zone, 18, 6), "centre")
		T.ok(not HitTest.CapsuleVsCylinder(charAt(HitTest, 0, 0, 7.2), zone, 18, 6), "jumped above (feet 7.2 > top 6)")
		-- ring: outer 8, band 3 -> inner 5
		local ring = CFrame.new(0, 1, 0)
		T.ok(not HitTest.CapsuleVsRing(charAt(HitTest, 0, 0), ring, 16, 2, 3), "inside the hole")
		T.ok(not HitTest.CapsuleVsRing(charAt(HitTest, 3.8, 0), ring, 16, 2, 3), "hole: 5 - 3.8 = 1.2 > R")
		T.ok(HitTest.CapsuleVsRing(charAt(HitTest, 4, 0), ring, 16, 2, 3), "touching inner edge")
		T.ok(HitTest.CapsuleVsRing(charAt(HitTest, 6.5, 0), ring, 16, 2, 3), "on the band")
		T.ok(not HitTest.CapsuleVsRing(charAt(HitTest, 9.2, 0), ring, 16, 2, 3), "outside")
		-- tilted cylinder (non-parallel path) vs brute force
		local Rng = Loader.require("ReplicatedStorage.Shared.Util.Rng")
		local rng = Rng.new(7)
		for _ = 1, 40 do
			local vol = {
				Shape = if rng:Bool() then "Cylinder" else "Ring",
				CFrame = CFrame.new(rng:Number(-3, 3), rng:Number(-3, 3), rng:Number(-3, 3))
					* CFrame.Angles(rng:Number(0, 6), rng:Number(0, 6), 0),
				Size = Vector3.new(rng:Number(2, 8), rng:Number(0.5, 4), rng:Number(0.5, 2)),
			}
			local a = Vector3.new(rng:Number(-6, 6), rng:Number(-6, 6), rng:Number(-6, 6))
			local b = a + Vector3.new(rng:Number(-6, 6), rng:Number(-6, 6), rng:Number(-6, 6))
			local e = math.sqrt(HitTest.SegmentDistanceSq(a, b, vol))
			local brute = bruteSegDist(HitTest, a, b, vol, 3000)
			T.ok(math.abs(e - brute) < 0.03, ("%s distance %.4f vs brute %.4f"):format(vol.Shape, e, brute))
		end
	end,

	hittest_shrink_grow = function(T, Loader)
		local HitTest = load(Loader, "HitTest")
		local beam = HitTest.Shrink({ Shape = "Box", CFrame = CFrame.new(), Size = Vector3.new(5, 5, 90) }, 0.85)
		T.near(beam.Size.X, 4.25, 1e-6, "thin dim scaled by forgiveness")
		T.near(beam.Size.Z, 89.25, 1e-6, "long dim loses the same margin")
		local ball = HitTest.Shrink({ Shape = "Ball", CFrame = CFrame.new(), Size = Vector3.new(1.2, 1.2, 1.2) }, 0.85)
		T.near(ball.Size.X, 1.02, 1e-6, "ball")
		local zone = HitTest.Shrink({ Shape = "Cylinder", CFrame = CFrame.new(), Size = Vector3.new(36, 20, 36) }, 0.5)
		T.near(zone.Size.X, 34, 1e-6, "margin capped at 1 stud")
		local ring = HitTest.Shrink({ Shape = "Ring", CFrame = CFrame.new(), Size = Vector3.new(20, 2.5, 2) }, 0.85)
		T.near(ring.Size.Z, 1.7, 1e-6, "ring band")
		T.near(ring.Size.X, 19.7, 1e-6, "ring outer")
		local same = HitTest.Shrink(beam, 1)
		T.eq(same, beam, "forgiveness 1 returns the same volume")
		local grown = HitTest.Grow({ Shape = "Box", CFrame = CFrame.new(), Size = Vector3.new(4, 5, 6) }, 1)
		T.ok(grown.Size == Vector3.new(5, 6, 7), "grow")
		-- forgiveness changes the outcome at the edge
		local cap = charAt(HitTest, 0, 0)
		local edge = { Shape = "Box", CFrame = CFrame.new(2.6, 2, 0), Size = Vector3.new(3, 2, 2) } -- face at 1.1
		T.ok(HitTest.Hits(cap, edge), "exact touch")
		T.ok(not HitTest.Hits(cap, edge, 0.85), "forgiveness favours the dodger")
		T.ok(
			HitTest.ContainsPoint(edge, Vector3.new(2.6, 2, 0))
				and not HitTest.ContainsPoint(edge, Vector3.new(0, 2, 0)),
			"contains"
		)
		T.ok(HitTest.MayOverlap(cap, edge), "broadphase near")
		T.ok(
			not HitTest.MayOverlap(cap, { Shape = "Ball", CFrame = CFrame.new(50, 0, 0), Size = Vector3.new(2, 2, 2) }),
			"broadphase far"
		)
	end,

	---------------------------------------------------------------------------------------------
	-- HazardDefs
	hazard_registry = function(T, Loader)
		local H = load(Loader, "HazardDefs")
		for _, name in
			{
				"BlasterBeam",
				"BoneLine",
				"BoneSpikes",
				"BoneProjectile",
				"Projectile",
				"Shockwave",
				"Orb",
				"Zone",
				"Rain",
			}
		do
			local def = H.Get(name)
			T.ok(def ~= nil and H[name] == def, "registered " .. name)
			T.ok(table.find(H.Types, name) ~= nil, "listed " .. name)
		end
		T.eq(H.Get("Telegraph"), nil, "helpers are not hazard types")
		local look = H.LookAlong(Vector3.new(1, 2, 3), Vector3.new(0, 0, -5))
		T.ok(look.LookVector:FuzzyEq(Vector3.new(0, 0, -1), 1e-5), "LookAlong -Z")
		local look2 = H.LookAlong(Vector3.zero, Vector3.new(1, -1, 0))
		T.ok(look2.LookVector:FuzzyEq(Vector3.new(1, -1, 0).Unit, 1e-5), "LookAlong diagonal")
		T.ok(look2.UpVector.Y > 0, "LookAlong keeps up")
		local ax = H.AxisFrame(Vector3.zero, Vector3.new(0, 0, 1))
		T.ok(ax.UpVector:FuzzyEq(Vector3.new(0, 0, 1), 1e-5), "AxisFrame up = axis")
	end,

	hazard_blaster_beam = function(T, Loader)
		local H = load(Loader, "HazardDefs")
		local HitTest = load(Loader, "HitTest")
		local p = H.Normalize(
			"BlasterBeam",
			{
				origin = H.LookAlong(Vector3.new(0, 3, 0), Vector3.new(0, 0, -1)),
				length = 60,
				width = 4,
				delay = 0.6,
				duration = 0.5,
			}
		)
		T.ok(H.Validate("BlasterBeam", p), "valid")
		local def = H.BlasterBeam
		T.near(def.Duration(p), 0.6 + 0.5 + 0.35, 1e-9, "duration")
		T.eq(#def.Volumes(p, 0.3), 0, "charging: no damage")
		T.eq(#def.Volumes(p, 1.2), 0, "after firing")
		local vols = def.Volumes(p, 0.8)
		T.eq(#vols, 1, "one beam volume")
		local f = 0.85
		T.ok(anyHit(HitTest, charAt(HitTest, 0, -30), vols, f), "in the beam")
		T.ok(anyHit(HitTest, charAt(HitTest, 0, -60), vols, f), "near the far end (beam ends at -61)")
		T.ok(not anyHit(HitTest, charAt(HitTest, 0, -64), vols, f), "past the end")
		T.ok(not anyHit(HitTest, charAt(HitTest, 0, 10), vols, f), "behind the blaster")
		T.ok(anyHit(HitTest, charAt(HitTest, 2.6, -30), vols, f), "side: 2.6 < 1.7 + 1.1")
		T.ok(not anyHit(HitTest, charAt(HitTest, 3.0, -30), vols, f), "side: 3.0 > 2.8")
		T.eq(def.HitPolicy(p).Once, true, "once by default")
		local ticking = def.HitPolicy(H.Normalize("BlasterBeam", { origin = CFrame.new(), tick = 0.2 }))
		T.ok(ticking.Once == false and ticking.Interval == 0.2, "tick policy")
		local tg = H.Telegraph("BlasterBeam", p)
		T.eq(tg.Kind, "Beam", "telegraph kind")
		T.near(tg.End, 0.6, 1e-9, "telegraph ends when firing")
		T.ok(tg.CFrame.Position:FuzzyEq(Vector3.new(0, 3, -1), 1e-5), "telegraph starts at beam start")
		local s, e = H.ActiveWindow("BlasterBeam", p)
		T.ok(s == 0.6 and math.abs(e - 1.1) < 1e-9, "active window")
		T.eq(H.DamageKind("BlasterBeam", p), "Beam", "kind")
		T.eq(p.blockable, true, "beams are blockable")
	end,

	hazard_bone_line = function(T, Loader)
		local H = load(Loader, "HazardDefs")
		local HitTest = load(Loader, "HitTest")
		local p = H.Normalize(
			"BoneLine",
			{
				origin = CFrame.new(0, 0, 0),
				count = 9,
				spacing = 2.5,
				height = 5,
				speed = 30,
				distance = 60,
				delay = 0.5,
				color = "Blue",
			}
		)
		local def = H.BoneLine
		T.near(def.Duration(p), 0.5 + 2 + 0.25, 1e-9, "duration")
		T.eq(#def.Volumes(p, 0.4), 0, "waiting")
		local vols = def.Volumes(p, 1.5) -- travel 30
		T.eq(#vols, 9, "nine bones")
		T.ok(vols[1].Key == 1 and vols[9].Key == 9, "keys")
		T.ok(vols[5].CFrame.Position:FuzzyEq(Vector3.new(0, 2.5, -30), 1e-5), "centre bone position")
		T.ok(vols[1].CFrame.Position:FuzzyEq(Vector3.new(-10, 2.5, -30), 1e-5), "first bone at -(count-1)/2*spacing")
		T.ok(anyHit(HitTest, charAt(HitTest, 0, -30), vols, 0.85), "row hits the character")
		T.ok(anyHit(HitTest, charAt(HitTest, 1.25, -30), vols, 0.85), "between bones still hit (gap < body)")
		T.ok(not anyHit(HitTest, charAt(HitTest, 0, -20), vols, 0.85), "not reached yet")
		T.ok(not anyHit(HitTest, charAt(HitTest, 0, -30, 5.2), vols, 0.85), "jumped over (feet above bones)")
		T.ok(not anyHit(HitTest, charAt(HitTest, 14, -30), vols, 0.85), "beside the row")
		T.eq(#def.Volumes(p, 2.6), 0, "finished")
		-- gaps
		local gp = H.Normalize("BoneLine", { origin = CFrame.new(), count = 5, spacing = 6, gaps = { 3 }, delay = 0 })
		local gv = def.Volumes(gp, 1)
		T.eq(#gv, 4, "gap removes a bone")
		local travel = 30
		T.ok(not anyHit(HitTest, charAt(HitTest, 0, -travel), gv, 0.85), "character in the gap is safe")
		local tg = H.Telegraph("BoneLine", p)
		T.ok(
			tg.Kind == "Lane" and tg.Length == 60 and math.abs(tg.Width - 20.8) < 1e-9 and tg.Color == "Blue",
			"lane telegraph"
		)
		T.eq(H.DamageKind("BoneLine", p), "Area", "kind")
	end,

	hazard_bone_spikes = function(T, Loader)
		local H = load(Loader, "HazardDefs")
		local HitTest = load(Loader, "HitTest")
		local p = H.Normalize(
			"BoneSpikes",
			{ center = Vector3.new(0, 0, 0), radius = 8, delay = 0.6, rise = 0.12, hold = 0.45 }
		)
		local def = H.BoneSpikes
		T.near(def.Duration(p), 0.6 + 0.12 + 0.45 + 0.2, 1e-9, "duration")
		T.eq(#def.Volumes(p, 0.5), 0, "telegraph only")
		T.near(H.SpikeHeight(p, 0.66), 2.5, 1e-6, "rising")
		local vols = def.Volumes(p, 0.8)
		T.eq(vols[1].Shape, "Cylinder", "disc")
		T.ok(anyHit(HitTest, charAt(HitTest, 5, 0), vols, 0.85), "inside")
		T.ok(not anyHit(HitTest, charAt(HitTest, 10.5, 0), vols, 0.85), "outside")
		T.eq(#def.Volumes(p, 1.3), 0, "retracting does not hurt")
		local ring = H.Normalize(
			"BoneSpikes",
			{ center = Vector3.new(0, 0, 0), radius = 10, ring = true, ringWidth = 3, delay = 1.4, color = "Orange" }
		)
		local rv = def.Volumes(ring, 1.5)
		T.eq(rv[1].Shape, "Ring", "ring")
		T.ok(not anyHit(HitTest, charAt(HitTest, 0, 0), rv, 0.85), "centre of ring safe")
		T.ok(anyHit(HitTest, charAt(HitTest, 10, 0), rv, 0.85), "on the ring")
		T.ok(not anyHit(HitTest, charAt(HitTest, 14, 0), rv, 0.85), "outside the ring")
		local tg = H.Telegraph("BoneSpikes", ring)
		T.ok(
			tg.Kind == "Ring" and tg.Radius == 11.5 and tg.InnerRadius == 8.5 and tg.Color == "Orange",
			"ring telegraph"
		)
		T.near(tg.Start, 0, 1e-9, "full delay telegraph by default")
		local warned =
			H.Telegraph("BoneSpikes", H.Normalize("BoneSpikes", { center = Vector3.zero, delay = 1.4, warn = 0.6 }))
		T.near(warned.Start, 0.8, 1e-9, "warn shortens the telegraph")
		local layout = H.SpikeLayout(p)
		T.eq(#layout, 14, "layout count")
		for _, s in layout do
			T.ok(s.Offset.Magnitude <= 8 + 1e-6, "spike inside radius")
		end
		local layout2 = H.SpikeLayout(H.Normalize("BoneSpikes", { center = Vector3.zero, radius = 8 }))
		T.ok(layout2[3].Offset:FuzzyEq(layout[3].Offset, 1e-9), "layout deterministic for equal params")
	end,

	hazard_projectiles = function(T, Loader)
		local H = load(Loader, "HazardDefs")
		local HitTest = load(Loader, "HitTest")
		local bp = H.Normalize(
			"BoneProjectile",
			{ origin = CFrame.new(0, 3, 0), speed = 60, maxDist = 60, delay = 0.15, length = 3.5 }
		)
		local def = H.BoneProjectile
		T.near(def.Duration(bp), 1.15, 1e-9, "flight duration")
		T.eq(#def.Volumes(bp, 0.1), 0, "held")
		local vols = def.Volumes(bp, 0.65) -- 30 studs
		T.ok(vols[1].CFrame.Position:FuzzyEq(Vector3.new(0, 3, -30), 1e-5), "position")
		T.ok(vols[1].CFrame.UpVector:FuzzyEq(Vector3.new(1, 0, 0), 1e-5), "bone lies along RightVector")
		T.ok(anyHit(HitTest, charAt(HitTest, 0, -30), vols, 0.85), "hit")
		T.ok(not anyHit(HitTest, charAt(HitTest, 0, -35), vols, 0.85), "miss")
		local spun = H.Normalize("BoneProjectile", { origin = CFrame.new(), spin = math.pi / 2, delay = 0 })
		local f = H.ProjectileFrame("BoneProjectile", spun, 1)
		T.ok(f.UpVector:FuzzyEq(Vector3.new(0, 1, 0), 1e-5), "spin rotates the bone axis")
		T.eq(def.HitPolicy(bp).Once, true, "once")
		T.ok(
			H.IsProjectile("BoneProjectile") and H.IsProjectile("Projectile") and not H.IsProjectile("Zone"),
			"IsProjectile"
		)
		-- generic projectile with gravity
		local pp = H.Normalize(
			"Projectile",
			{ origin = CFrame.new(0, 10, 0), speed = 40, gravity = 20, maxDist = 80, radius = 0.6 }
		)
		local frame, traveled = H.ProjectileFrame("Projectile", pp, 1)
		T.ok(frame.Position:FuzzyEq(Vector3.new(0, 0, -40), 1e-5), "ballistic position")
		T.near(traveled, 40, 1e-9, "traveled")
		T.ok(frame.LookVector.Y < 0, "faces velocity (falling)")
		T.eq(#H.Projectile.Volumes(pp, 2.1), 0, "expired after maxDist/speed")
		local pv = H.Projectile.Volumes(pp, 1)
		T.eq(pv[1].Shape, "Ball", "ball")
		T.eq(H.Telegraph("Projectile", pp).Kind, "None", "instant projectiles have no telegraph")
		T.eq(H.Telegraph("BoneProjectile", bp).Kind, "Beam", "held bone shows its path")
		T.eq(H.DamageKind("Projectile", pp), "Projectile", "kind")
	end,

	hazard_shockwave = function(T, Loader)
		local H = load(Loader, "HazardDefs")
		local HitTest = load(Loader, "HitTest")
		local p = H.Normalize(
			"Shockwave",
			{ center = Vector3.zero, maxRadius = 14, speed = 28, height = 2.5, thickness = 2, delay = 0.3 }
		)
		local def = H.Shockwave
		T.near(def.Duration(p), 0.3 + 0.5 + 0.15, 1e-9, "duration")
		local vols = def.Volumes(p, 0.55) -- R = 7, band [5, 7]
		T.near(H.ShockwaveRadius(p, 0.55), 7, 1e-9, "front radius")
		T.ok(anyHit(HitTest, charAt(HitTest, 7, 0), vols, 0.85), "on the front")
		T.ok(not anyHit(HitTest, charAt(HitTest, 2, 0), vols, 0.85), "already passed")
		T.ok(not anyHit(HitTest, charAt(HitTest, 10, 0), vols, 0.85), "not reached")
		T.ok(not anyHit(HitTest, charAt(HitTest, 7, 0, 2.6), vols, 0.85), "jumped over")
		T.eq(#def.Volumes(p, 0.9), 0, "past maxRadius")
		T.eq(#def.Volumes(p, 0.2), 0, "before delay")
		local kb = H.KnockbackDir("Shockwave", p, 0.55, Vector3.new(7, 3, 0))
		T.ok(kb:FuzzyEq(Vector3.new(1, 0, 0), 1e-5), "knockback away from centre")
	end,

	hazard_orb = function(T, Loader)
		local H = load(Loader, "HazardDefs")
		local HitTest = load(Loader, "HitTest")
		local p = H.Normalize(
			"Orb",
			{ center = Vector3.new(0, 3, 0), radius = 12, delay = 0.4, duration = 2.5, pullStrength = 14, damage = 18 }
		)
		T.eq(p.implodeDamage, 18, "implodeDamage defaults to damage")
		T.eq(p.implodeRadius, 12, "implodeRadius defaults to radius")
		local def = H.Orb
		T.eq(#def.Volumes(p, 1), 0, "pulling, no damage")
		local e = H.Effect("Orb", p, 1)
		T.ok(e and e.Kind == "Pull" and e.Strength == 14 and e.Radius == 12, "pull effect active")
		T.eq(H.Effect("Orb", p, 0.2), nil, "no pull before delay")
		T.eq(H.Effect("Orb", p, 3.0), nil, "no pull after implosion")
		local vols = def.Volumes(p, 2.95)
		T.eq(#vols, 1, "implosion")
		T.ok(anyHit(HitTest, charAt(HitTest, 10, 0), vols, 0.85), "inside implosion")
		T.ok(not anyHit(HitTest, charAt(HitTest, 14.5, 0), vols, 0.85), "outside implosion")
		T.eq(#def.Volumes(p, 3.2), 0, "after implosion")
		T.near(def.Duration(p), 0.4 + 2.5 + 0.15 + 0.4, 1e-9, "duration")
		local tg = H.Telegraph("Orb", p)
		T.ok(tg.Kind == "Circle" and math.abs(tg.End - 2.9) < 1e-9, "telegraph until implosion")
	end,

	hazard_zone = function(T, Loader)
		local H = load(Loader, "HazardDefs")
		local HitTest = load(Loader, "HitTest")
		local p = H.Normalize(
			"Zone",
			{ center = Vector3.zero, radius = 9, delay = 0.3, duration = 5, tick = 0.5, effect = "Heal" }
		)
		T.eq(p.amount, 5, "heal amount default")
		T.eq(p.affects, "Allies", "heal affects allies")
		local dz = H.Normalize("Zone", { center = Vector3.zero, damage = 7 })
		T.eq(dz.amount, 7, "damage zone amount = damage")
		T.eq(dz.affects, "Enemies", "damage affects enemies")
		local def = H.Zone
		T.eq(#def.Volumes(p, 0.2), 0, "before delay")
		local vols = def.Volumes(p, 3)
		T.ok(anyHit(HitTest, charAt(HitTest, 8, 0), vols, 0.85), "inside")
		T.ok(not anyHit(HitTest, charAt(HitTest, 11, 0), vols, 0.85), "outside")
		T.eq(#def.Volumes(p, 5.4), 0, "expired")
		local pol = def.HitPolicy(p)
		T.ok(pol.Once == false and pol.Interval == 0.5, "interval policy")
	end,

	hazard_rain_determinism = function(T, Loader)
		local H = load(Loader, "HazardDefs")
		local HitTest = load(Loader, "HitTest")
		local p1 = H.Normalize(
			"Rain",
			{
				center = Vector3.new(10, 0, 5),
				radius = 14,
				count = 10,
				interval = 0.15,
				delay = 0.6,
				size = 3,
				seed = 1234,
			}
		)
		local p2 = H.Normalize(
			"Rain",
			{
				center = Vector3.new(10, 0, 5),
				radius = 14,
				count = 10,
				interval = 0.15,
				delay = 0.6,
				size = 3,
				seed = 1234,
			}
		)
		local p3 = H.Normalize(
			"Rain",
			{
				center = Vector3.new(10, 0, 5),
				radius = 14,
				count = 10,
				interval = 0.15,
				delay = 0.6,
				size = 3,
				seed = 99,
			}
		)
		local d1, d2, d3 = H.RainDrops(p1), H.RainDrops(p2), H.RainDrops(p3)
		T.eq(#d1, 10, "count")
		local same, differs = true, false
		for i = 1, 10 do
			same = same and d1[i].Position == d2[i].Position
			differs = differs or d1[i].Position ~= d3[i].Position
			T.ok((d1[i].Position - Vector3.new(10, 0, 5)).Magnitude <= 14 + 1e-9, "drop inside radius")
			T.near(d1[i].ImpactTime, 0.6 + (i - 1) * 0.15, 1e-9, "impact time")
		end
		T.ok(same, "same seed -> same drops")
		T.ok(differs, "different seed -> different drops")
		T.eq(H.RainDrops(p1), d1, "cached by params identity")
		local def = H.Rain
		T.near(def.Duration(p1), 0.6 + 9 * 0.15 + 0.12 + 0.3, 1e-9, "duration")
		T.eq(#def.Volumes(p1, 0.5), 0, "nothing before first impact")
		local v = def.Volumes(p1, 0.65)
		T.eq(#v, 1, "first drop impacting")
		T.eq(v[1].Key, 1, "keyed by drop index")
		local pos = d1[1].Position
		T.ok(anyHit(HitTest, charAt(HitTest, pos.X + 2, pos.Z), v, 0.85), "under the drop")
		T.ok(not anyHit(HitTest, charAt(HitTest, pos.X + 6, pos.Z), v, 0.85), "away from the drop")
		local pol = def.HitPolicy(p1)
		T.ok(pol.Once and pol.PerKey, "per-drop once")
		local tg = H.Telegraph("Rain", p1)
		T.ok(tg.Kind == "Multi" and #tg.Items == 10, "multi telegraph")
		T.near(tg.Items[3].End, d1[3].ImpactTime, 1e-9, "item end = impact")
		T.near(tg.Items[3].Start, d1[3].ImpactTime - 0.6, 1e-9, "item lead = delay")
	end,

	hazard_normalize_validate = function(T, Loader)
		local H = load(Loader, "HazardDefs")
		local raw = { origin = CFrame.new(), damage = 20 }
		local n = H.Normalize("BlasterBeam", raw)
		T.ok(n ~= raw and raw.length == nil, "normalize copies")
		T.ok(
			n.length == 60 and n.color == "White" and n.kr == 0 and n.warn == 0.6 and n.damage == 20,
			"defaults filled"
		)
		T.ok(H.Validate("BlasterBeam", n), "valid")
		T.ok(not H.Validate("BlasterBeam", { damage = 5 }), "missing origin")
		T.ok(not H.Validate("BlasterBeam", { origin = CFrame.new(), length = "long" }), "bad type")
		T.ok(not H.Validate("BlasterBeam", { origin = CFrame.new(), length = 0 / 0 }), "NaN")
		T.ok(not H.Validate("Zone", { radius = 5 }), "zone needs center")
		T.ok(not H.Validate("Nope", {}), "unknown type")
		T.ok(H.IsPlainData(n), "plain data")
		T.ok(not H.IsPlainData({ x = Instance.new("Part") }), "instances are not plain data")
		T.ok(not H.IsPlainData({ f = function() end }), "functions are not plain data")
		T.ok(H.IsPlainData({ gaps = { 1, 2 } }), "arrays of numbers ok")
		for _, name in H.Types do
			local params = H.Normalize(name, { origin = CFrame.new(), center = Vector3.zero })
			local def = H.Get(name)
			local d = def.Duration(params)
			T.ok(type(d) == "number" and d > 0, name .. " duration positive")
			local s, e = H.ActiveWindow(name, params)
			T.ok(s >= 0 and e >= s and e <= d + 1e-9, name .. " active window inside lifetime")
			-- volumes exist somewhere inside the active window
			local found = false
			for k = 0, 40 do
				local t = s + (e - s) * k / 40
				if #def.Volumes(params, t) > 0 then
					found = true
					break
				end
			end
			T.ok(found, name .. " has volumes in its active window")
			T.eq(#def.Volumes(params, d + 0.5), 0, name .. " no volumes after Duration")
			T.ok(type(H.Telegraph(name, params).Kind) == "string", name .. " telegraph")
		end
	end,

	---------------------------------------------------------------------------------------------
	-- DamageMath
	damagemath_kr = function(T, Loader)
		local D = load(Loader, "DamageMath")
		local cfg = { DrainBase = 2.5, DrainPerStack = 0.3, MinHealth = 1, Max = 40 }
		T.near(D.KRRate(1, cfg), 2.5, 1e-9, "rate at 1")
		T.near(D.KRRate(40, cfg), 2.5 + 0.3 * 39, 1e-9, "rate at 40")
		T.eq(D.KRRate(0, cfg), 0, "no KR no drain")
		-- KR never kills
		local hp, kr = 5, 40
		for _ = 1, 400 do
			hp, kr = D.KRStep(hp, kr, 0.1, cfg)
			T.ok(hp >= 1 - 1e-9, "KR never drops HP below MinHealth")
		end
		T.near(hp, 1, 1e-9, "drained to the floor")
		T.eq(kr, 0, "KR fully decays")
		-- at the floor KR still decays without damage
		local h2, k2, drained = D.KRStep(1, 10, 0.5, cfg)
		T.ok(h2 == 1 and drained == 0 and k2 < 10, "floor: KR decays, HP untouched")
		-- total drain equals KR when HP allows
		local h3, k3 = 100, 10
		for _ = 1, 200 do
			h3, k3 = D.KRStep(h3, k3, 0.1, cfg)
		end
		T.near(h3, 90, 1e-6, "KR is delayed damage equal to its amount")
		T.eq(D.KRAdd(35, 10, cfg), 40, "cap")
		T.eq(D.KRAdd(5, -3, cfg), 5, "negative add ignored")
		T.eq(D.KRCleanse(2, 3), 0, "cleanse floor 0")
		-- default config
		local h4 = D.KRStep(50, 10, 0.1)
		T.ok(h4 < 50, "default config drains")
	end,

	damagemath_dodges = function(T, Loader)
		local D = load(Loader, "DamageMath")
		local cfg = { DodgeRegenDelay = 3, DodgeRegenInterval = 2, ExhaustTime = 5 }
		local s = D.NewDodgeState(3, 0)
		T.eq(D.ConsumeDodge(s, 1, cfg), false, "3 -> 2")
		T.eq(D.ConsumeDodge(s, 1.5, cfg), false, "2 -> 1")
		T.eq(D.ConsumeDodge(s, 2, cfg), true, "1 -> 0 exhausts")
		T.eq(s.Dodges, 0, "empty")
		T.eq(s.ExhaustedUntil, 7, "exhausted for ExhaustTime")
		T.eq(D.ConsumeDodge(s, 2.5, cfg), false, "cannot dodge while exhausted")
		local t = 2
		local refilledAt = nil
		while t < 10 do
			t += 0.1
			local _, refilled = D.DodgeTick(s, t, 0.1, 1, cfg)
			if refilled and not refilledAt then
				refilledAt = t
			end
			if t < 6.95 then
				T.eq(s.Dodges, 0, "no regen while exhausted")
			end
		end
		T.ok(refilledAt and math.abs(refilledAt - 7) < 0.11, "refilled when exhaustion ends")
		T.eq(s.Dodges, 3, "refilled to max")
		-- regen timing: one dodge used at t=0 -> +1 at 3 + 2 = 5
		local r = D.NewDodgeState(3, 0)
		D.ConsumeDodge(r, 0, cfg)
		local gainedAt = nil
		local now = 0
		for _ = 1, 140 do
			now += 0.05
			if D.DodgeRegen(r, now, 0.05, 1, cfg) > 0 and not gainedAt then
				gainedAt = now
			end
		end
		T.ok(gainedAt and math.abs(gainedAt - 5) < 0.06, "regen after delay + interval, got " .. tostring(gainedAt))
		-- faster regen multiplier (final form)
		local f = D.NewDodgeState(3, 0)
		D.ConsumeDodge(f, 0, cfg)
		local fastAt = nil
		now = 0
		for _ = 1, 100 do
			now += 0.05
			if D.DodgeRegen(f, now, 0.05, 1.5, cfg) > 0 and not fastAt then
				fastAt = now
			end
		end
		T.ok(fastAt and math.abs(fastAt - (3 + 2 / 1.5)) < 0.06, "x1.5 regen, got " .. tostring(fastAt))
		-- dodging resets the regen delay
		local g = D.NewDodgeState(3, 0)
		D.ConsumeDodge(g, 0, cfg)
		D.DodgeRegen(g, 4, 1, 1, cfg) -- 1 s of progress
		D.ConsumeDodge(g, 4, cfg)
		T.eq(g.Acc, 0, "progress reset by a new dodge")
		-- max lowered (SAVE point) clamps
		local m = D.NewDodgeState(8, 0)
		m.Max = 7
		D.DodgeRegen(m, 1, 0.1, 1, cfg)
		T.eq(m.Dodges, 7, "clamped to new max")
	end,

	damagemath_block_parry = function(T, Loader)
		local D = load(Loader, "DamageMath")
		local taken, blocked = D.BlockSplit(100, 0.7)
		T.near(taken, 30, 1e-9, "70 % blocked")
		T.near(blocked, 70, 1e-9, "blocked part")
		local g, broken = D.GuardAfterBlock(50, 70)
		T.ok(g == 0 and broken, "guard break")
		local g2, broken2 = D.GuardAfterBlock(100, 21)
		T.ok(g2 == 79 and not broken2, "guard drained")
		T.ok(D.IsParry(10, 10.15, 0.2, "Melee"), "inside window")
		T.ok(D.IsParry(10, 10.2, 0.2, "Projectile"), "edge of window")
		T.ok(not D.IsParry(10, 10.3, 0.2, "Melee"), "late")
		T.ok(not D.IsParry(10, 10.1, 0.2, "Beam"), "beams cannot be parried")
		T.ok(not D.IsParry(0, 0.1, 0.2, "Melee"), "no block start")
		T.ok(not D.IsParry(nil, 0.1, 0.2, "Melee"), "nil block start")
		local pos, look = Vector3.zero, Vector3.new(0, 0, -1)
		T.ok(D.IsFacing(pos, look, Vector3.new(0, 5, -5), 0.15), "front (height ignored)")
		T.ok(not D.IsFacing(pos, look, Vector3.new(0, 0, 5), 0.15), "behind")
		T.ok(not D.IsFacing(pos, look, Vector3.new(5, 0, 0), 0.15), "side (dot 0)")
		T.ok(D.IsFacing(pos, look, Vector3.new(4, 0, -5), 0.15), "front-side")
		T.ok(D.IsFacing(pos, look, Vector3.new(0.01, 0, 0), 0.15), "coincident counts as front")
		-- guard regen
		local cfg = { GuardRegenDelay = 1.2, GuardRegenPerSecond = 18 }
		T.eq(D.GuardRegen(50, 100, 10, 9.5, 0.1, 1, cfg), 50, "inside delay")
		T.near(D.GuardRegen(50, 100, 11, 9.5, 0.1, 1, cfg), 51.8, 1e-9, "regen")
		T.near(D.GuardRegen(50, 100, 10.75, 9.5, 0.1, 1, cfg), 50 + 18 * 0.05, 1e-9, "partial first step")
		T.near(D.GuardRegen(50, 100, 11, 9.5, 0.1, 1.5, cfg), 52.7, 1e-9, "mult")
		T.eq(D.GuardRegen(99.9, 100, 20, 0, 1, 1, cfg), 100, "capped")
	end,

	damagemath_multipliers = function(T, Loader)
		local D = load(Loader, "DamageMath")
		T.near(D.OutgoingMult({}), 1, 1e-9, "no buffs")
		T.near(D.OutgoingMult({ 1.2, 1.3 }), 1.5, 1e-9, "buffs add")
		T.near(D.OutgoingMult({ 1.2, 1.3, 0.5 }), 0.75, 1e-9, "debuffs multiply")
		T.near(D.OutgoingMult({ 1.2, 0 / 0 }), 1.2, 1e-9, "NaN ignored")
		T.near(D.OutgoingMult({ 10, 10 }), 5, 1e-9, "clamped")
		T.near(D.IncomingMult({ 0.6, 1.15 }), 0.69, 1e-9, "incoming multiply")
		T.near(D.IncomingMult({ 0.6, 0.6 }), 0.36, 1e-9, "two reductions multiply")
		local cfg = { HarmonyPerClass = 0.04, HarmonyMax = 0.2 }
		T.near(D.HarmonyMult(1, cfg), 1, 1e-9, "one class")
		T.near(D.HarmonyMult(3, cfg), 1.08, 1e-9, "three classes")
		T.near(D.HarmonyMult(9, cfg), 1.2, 1e-9, "cap")
		T.near(D.HarmonyFromAttribute(0.12, cfg), 1.12, 1e-9, "fraction form")
		T.near(D.HarmonyFromAttribute(1.08, cfg), 1.08, 1e-9, "multiplier form")
		T.near(D.HarmonyFromAttribute(nil, cfg), 1, 1e-9, "missing")
		T.near(D.HarmonyFromAttribute(3, cfg), 1.2, 1e-6, "clamped")
		T.ok(not D.ColorHurts("Blue", 0, 2) and D.ColorHurts("Blue", 5, 2), "blue hurts movers")
		T.ok(D.ColorHurts("Orange", 0, 2) and not D.ColorHurts("Orange", 5, 2), "orange hurts the still")
		T.ok(D.ColorHurts("Orange", 2, 2), "orange: threshold counts as still")
		T.ok(D.ColorHurts("White", 0, 2) and D.ColorHurts(nil, 9, 2), "white always")
		local hp, applied = D.ApplyHealth(10, 50, 1)
		T.ok(hp == 1 and applied == 9, "Determined floor")
		local hp2, applied2 = D.ApplyHealth(0.5, 5, 1)
		T.ok(hp2 == 0.5 and applied2 == 0, "never raises HP")
		local hp3, applied3 = D.ApplyHealth(30, 12)
		T.ok(hp3 == 18 and applied3 == 12, "normal")
		local hh, healed = D.ApplyHeal(90, 100, 25)
		T.ok(hh == 100 and healed == 10, "heal capped")
		local rem, abs, left = D.AbsorbShield(30, 40)
		T.ok(rem == 0 and abs == 30 and left == 10, "shield absorbs")
		local rem2, abs2, left2 = D.AbsorbShield(50, 40)
		T.ok(rem2 == 10 and abs2 == 40 and left2 == 0, "shield breaks")
	end,

	damagemath_misc = function(T, Loader)
		local D = load(Loader, "DamageMath")
		local c, acc = D.ChargeTick(0, 2, 0, 3, 2.8)
		T.ok(c == 1 and math.abs(acc - 0.2) < 1e-9, "dash charge regen")
		local c2, acc2 = D.ChargeTick(1, 2, 2.7, 0.2, 2.8)
		T.ok(c2 == 2 and acc2 == 0, "full resets accumulator")
		T.near(D.ScaledCooldownEnd(100, 2, 6, 0.5), 104, 1e-9, "finishes inside the slow window")
		T.near(D.ScaledCooldownEnd(100, 4, 6, 0.5), 107, 1e-9, "outlasts the slow window")
		T.near(D.ScaledCooldownEnd(100, 4, 0, 0.5), 104, 1e-9, "no window")
		T.near(D.ScaledCooldownEnd(100, 4, 10, 2), 102, 1e-9, "haste")
		T.eq(D.NextComboIndex(0, nil, 1, 0.9, 3), 1, "first")
		T.eq(D.NextComboIndex(1, 1, 1.5, 0.9, 3), 2, "second")
		T.eq(D.NextComboIndex(2, 1.5, 2.0, 0.9, 3), 3, "third")
		T.eq(D.NextComboIndex(3, 2.0, 2.4, 0.9, 3), 1, "restarts after the last hit")
		T.eq(D.NextComboIndex(2, 1.0, 3.0, 0.9, 3), 1, "window expired")
		T.near(D.ClampCharge(1, 10, 10.6, 1.2, 0.1), 0.6, 1e-9, "cannot claim more hold than elapsed")
		T.near(D.ClampCharge(0.3, 10, 12, 1.2, 0.1), 0.3, 1e-9, "honest charge kept")
		T.eq(D.ClampCharge("x", 0, 1, 1.2), 0, "garbage -> 0")
		T.eq(D.ClampCharge(5, 0, 100, 1.2), 1, "clamped to 1")
		T.ok(D.ClampAim(Vector3.zero, Vector3.new(0, 0, -100), 40):FuzzyEq(Vector3.new(0, 0, -40), 1e-6), "aim clamp")
		T.ok(D.ClampAim(Vector3.zero, Vector3.new(3, 0, 0), 40) == Vector3.new(3, 0, 0), "aim inside range")
		local cfg = {
			HumanPerDamage = 0.3,
			MonsterPerDamage = 0.22,
			HumanOnHitTaken = 0.1,
			HumanPerHeal = 0.4,
			HumanPerSecond = 0.2,
			MonsterPerSecond = 0.3,
		}
		T.near(D.UltForDamageDealt("Human", 10, cfg), 3, 1e-9, "human ult per damage")
		T.near(D.UltForDamageDealt("Monster", 10, cfg), 2.2, 1e-9, "monster ult per damage")
		T.near(D.UltForDamageTaken("Human", 10, cfg), 1, 1e-9, "human ult when hit")
		T.eq(D.UltForDamageTaken("Monster", 10, cfg), 0, "monster gains nothing when hit")
		T.near(D.UltForHeal("Human", 10, cfg), 4, 1e-9, "heal ult")
		T.near(D.UltPerSecond("Monster", cfg), 0.3, 1e-9, "per second")
		T.eq(D.AddUlt(95, 10), 100, "ult cap")
		T.eq(D.AddUlt(5, -10), 0, "ult floor")
		T.eq(D.RoleOfTeam("Monster"), "Monster", "role")
		T.eq(D.RoleOfTeam("Lobby"), "Human", "lobby counts as human")
	end,
}

-------------------------------------------------------------------------------------------------
-- Service integration harness: real combat services on Lune instances with a simulated clock,
-- a fake CharacterService / Net / workspace (flat ground at y = 0). No physics: movement is checked
-- through the packets / server movers it produces.

local function harness(Loader)
	local H = {}
	local clock = 1000
	local timers = {}
	H.sent = {}
	H.models = {}
	H.kills = {}
	H.downs = {}
	H.round = { Phase = "Round", TeamRevives = 2, FinalPhase = false, Harmony = 1 }
	H.speeds = {}
	H.handlers = {}

	local function runDue()
		while true do
			table.sort(timers, function(a, b)
				return a.at < b.at
			end)
			local first = timers[1]
			if first == nil or first.at > clock then
				return
			end
			table.remove(timers, 1)
			first.fn()
		end
	end
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

	-- module globals come from the loader's environment (Lune isolates each script's _G)
	local G = getfenv(Loader.requirePath)
	H.G = G
	G.workspace = {
		GetServerTimeNow = function()
			return clock
		end,
		Raycast = function(_, origin, dir)
			local y1 = origin.Y + dir.Y
			if origin.Y >= 0 and y1 <= 0 and dir.Y < 0 and not (H.pitX and origin.X > H.pitX) then
				local t = origin.Y / -dir.Y
				return { Position = origin + dir * t, Normal = Vector3.yAxis, Distance = dir.Magnitude * t }
			end
			if H.wallX and (origin.X - H.wallX) * (origin.X + dir.X - H.wallX) < 0 then
				local t = (H.wallX - origin.X) / dir.X
				return { Position = origin + dir * t, Normal = Vector3.xAxis, Distance = dir.Magnitude * t }
			end
			return nil
		end,
		FindFirstChild = function()
			return nil
		end,
	}
	G.RaycastParams = {
		new = function()
			return {}
		end,
	}

	local Validation = Loader.requirePath("src/server/Combat/Validation")
	H.Validation = Validation
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
	H.runDue = runDue
	Validation.RoundAttr = function(name)
		return H.round[name]
	end
	Validation.HorizontalSpeed = function(m)
		return H.speeds[m] or 0
	end

	local Signal = Loader.require("ReplicatedStorage.Shared.Util.Signal")
	local CS = {
		Spawned = Signal.new(),
		Died = Signal.new(),
		Downed = Signal.new(),
		Revived = Signal.new(),
		Despawning = Signal.new(),
	}
	function CS.GetAll()
		local out = {}
		for _, m in H.models do
			if m:GetAttribute("Dead") ~= true and m.Parent ~= nil then
				table.insert(out, m)
			end
		end
		return out
	end
	function CS.GetPlayer(m)
		return H.playerOf and H.playerOf[m] or nil
	end
	function CS.GetModel(p)
		return H.modelOf and H.modelOf[p] or nil
	end
	function CS.Kill(m, attacker, ability)
		m:SetAttribute("Dead", true)
		table.insert(H.kills, { model = m, attacker = attacker, ability = ability })
	end
	function CS.SetDowned(m, attacker)
		m:SetAttribute("Downed", true)
		table.insert(H.downs, { model = m, attacker = attacker })
	end
	H.CS = CS
	Validation.SetService("CharacterService", CS)
	H.stats = {}
	Validation.SetService("StatsService", {
		Add = function(m, stat, amount)
			table.insert(H.stats, { model = m, stat = stat, amount = amount })
		end,
	})
	H.finalPhase = 0
	Validation.SetService("RoundService", {
		TriggerFinalPhase = function()
			H.finalPhase += 1
			return true
		end,
	})
	H.boxes = {}
	Validation.SetService("VerdictBoxService", {
		Start = function(monster, victim)
			table.insert(H.boxes, { monster = monster, victim = victim })
			return true
		end,
	})

	local Net = Loader.require("ReplicatedStorage.Shared.Net")
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

	H.S = {}
	for _, n in { "StatusService", "MovementService", "DamageService", "HazardService", "AbilityService" } do
		H.S[n] = Loader.requirePath("src/server/Services/" .. n)
	end
	for _, n in { "StatusService", "MovementService", "DamageService", "HazardService", "AbilityService" } do
		H.S[n].Init()
	end
	H.HazardDefs = Loader.require("ReplicatedStorage.Shared.Combat.HazardDefs")
	H.Kits = Loader.require("ReplicatedStorage.Shared.Kits")

	local world = Instance.new("Folder")
	world.Name = "World"

	-- Spawns a character standing on the ground at `pos`, facing `look` (default -Z).
	function H.spawn(kitId, team, pos, opts)
		opts = opts or {}
		local kit = H.Kits.Get(kitId)
		local m = Instance.new("Model")
		m.Name = (opts.name or kitId) .. "_" .. tostring(#H.models + 1)
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.CFrame = H.HazardDefs.LookAlong(pos + Vector3.new(0, 3, 0), opts.look or Vector3.new(0, 0, -1))
		root.Parent = m
		m.PrimaryPart = root
		local hum = Instance.new("Humanoid")
		hum.HipHeight = 2
		local hp = opts.hp or (kit and kit.Stats.MaxHP) or 100
		hum.MaxHealth = hp
		hum.Health = hp
		hum.WalkSpeed = kit and kit.Stats.WalkSpeed or 0
		hum.JumpPower = kit and kit.Stats.JumpPower or 0
		hum.Parent = m
		m:SetAttribute("KitId", kitId)
		m:SetAttribute("Team", team)
		m:SetAttribute("Ult", opts.ult or 0)
		m:SetAttribute("Blocking", false)
		m:SetAttribute("Downed", false)
		m:SetAttribute("Dead", false)
		if kit and kit.Role == "Monster" then
			local d = opts.dodges or kit.Stats.MaxDodges
			m:SetAttribute("Dodges", d)
			m:SetAttribute("MaxDodges", opts.maxDodges or d)
			m:SetAttribute("Exhausted", 0)
		else
			m:SetAttribute("KR", 0)
			local g = kit and kit.Stats.MaxGuard or 100
			m:SetAttribute("Guard", g)
			m:SetAttribute("MaxGuard", g)
			m:SetAttribute("DashCharges", 2)
		end
		m.Parent = world
		table.insert(H.models, m)
		H.S.StatusService.Track(m)
		return m
	end

	function H.hp(m)
		return m:FindFirstChildOfClass("Humanoid").Health
	end
	function H.count(name)
		local n = 0
		for _, s in H.sent do
			if s.name == name then
				n += 1
			end
		end
		return n
	end
	function H.last(name)
		for i = #H.sent, 1, -1 do
			if H.sent[i].name == name then
				return H.sent[i].args[1], H.sent[i]
			end
		end
		return nil
	end
	function H.cleanup()
		Validation.SetScheduler(nil)
		G.workspace = nil
		G.RaycastParams = nil
	end
	return H
end

local function withHarness(Loader, fn)
	local H = harness(Loader)
	local ok, err = pcall(fn, H)
	H.cleanup()
	if not ok then
		error(err, 0)
	end
end

local integration = {
	services_teleport_validation = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local moved = {}
			H.S.MovementService.Teleport = function(_m, cf)
				table.insert(moved, cf)
			end
			local sans = H.spawn("ClassicSans", "Monster", Vector3.zero, { dodges = 0, maxDodges = 0 })
			T.ok(AS.CastAs(sans, "Shortcut", { aim = Vector3.new(0, 0, -20) }), "cast")
			T.ok(
				moved[1] and moved[1].Position:FuzzyEq(Vector3.new(0, 3.05, -20), 1e-3),
				"lands on the ground at the aim"
			)
			T.ok(moved[1].LookVector.Z < -0.99, "faces the aim")
			local fx = H.last("AbilityFx")
			T.ok(fx.phase == "Teleport" and fx.data.to ~= nil, "Teleport fx broadcast")
			AS.ResetCooldowns(sans)
			AS.CastAs(sans, "Shortcut", { aim = Vector3.new(0, 0, -100) })
			T.ok(moved[2] and math.abs(moved[2].Position.Z + 32) < 0.05, "clamped to Distance 32")
			AS.ResetCooldowns(sans)
			H.wallX = 10
			AS.CastAs(sans, "Shortcut", { aim = Vector3.new(20, 0, 0) })
			T.ok(moved[3] and math.abs(moved[3].Position.X - 8.5) < 0.05, "stops 1.5 studs before a wall")
			AS.ResetCooldowns(sans)
			H.wallX = nil
			H.pitX = 5
			AS.CastAs(sans, "Shortcut", { aim = Vector3.new(20, 0, 0) })
			T.ok(
				moved[4] and moved[4].Position.X <= 5 and moved[4].Position.X > 3,
				"walks back from a pit to solid ground"
			)
			AS.ResetCooldowns(sans)
			H.pitX = -100
			AS.CastAs(sans, "Shortcut", { aim = Vector3.new(20, 0, 0) })
			T.eq(#moved, 4, "no ground anywhere: no teleport")
		end)
	end,

	services_dodge_exhaust = function(T, Loader)
		withHarness(Loader, function(H)
			local DS, SS = H.S.DamageService, H.S.StatusService
			local monster = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -6), { dodges = 3, hp = 1000 })
			local human = H.spawn("Determination", "Humans", Vector3.zero)
			local dodgedSignals = 0
			DS.Dodged:Connect(function()
				dodgedSignals += 1
			end)
			for i = 1, 3 do
				local r = DS.Apply({ Attacker = human, Target = monster, Amount = 10, Kind = "Melee" })
				T.ok(r.Dodged and r.Applied == 0, "hit " .. i .. " dodged")
				H.advance(0.2)
			end
			T.eq(monster:GetAttribute("Dodges"), 0, "dodges used up")
			T.ok(SS.Has(monster, "Exhausted"), "exhausted at 0 dodges")
			T.ok(
				monster:GetAttribute("Status_Exhausted") ~= nil and monster:GetAttribute("Exhausted") > H.now(),
				"exhausted attributes"
			)
			T.eq(H.hp(monster), 1000, "no damage while dodging")
			local fx = H.last("DamageFx")
			T.ok(fx and fx.dodged == true, "MISS fx")
			local r = DS.Apply({ Attacker = human, Target = monster, Amount = 10, Kind = "Melee" })
			T.ok(not r.Dodged, "exhausted cannot dodge")
			T.near(r.Applied, 11.5, 1e-6, "exhausted takes x1.15")
			H.advance(5.1)
			T.ok(not SS.Has(monster, "Exhausted"), "exhaustion over")
			T.eq(monster:GetAttribute("Dodges"), 3, "dodges refilled")
			T.eq(monster:GetAttribute("Exhausted"), 0, "Exhausted attribute reset")
			-- stunned monsters, ultimates and Undodgeable hits ignore dodges
			SS.Apply(monster, "Stunned", 0.5)
			T.ok(
				not DS.Apply({ Attacker = human, Target = monster, Amount = 5, Kind = "Melee" }).Dodged,
				"stunned: no dodge"
			)
			H.advance(0.6)
			T.ok(
				not DS.Apply({
					Attacker = human,
					Target = monster,
					Amount = 5,
					Kind = "Melee",
					Ability = "DeterminationUlt",
				}).Dodged,
				"ultimate: no dodge"
			)
			T.ok(
				not DS.Apply({ Attacker = human, Target = monster, Amount = 5, Kind = "Melee", Undodgeable = true }).Dodged,
				"Undodgeable"
			)
			SS.Apply(human, "Undodgeable", 1)
			T.ok(
				not DS.Apply({ Attacker = human, Target = monster, Amount = 5, Kind = "Melee" }).Dodged,
				"attacker status Undodgeable"
			)
			SS.Remove(human, "Undodgeable")
			T.ok(DS.Apply({ Attacker = human, Target = monster, Amount = 5, Kind = "Melee" }).Dodged, "dodges again")
			H.runDue()
			T.eq(dodgedSignals, 4, "Dodged signal per dodge")
			-- dodge regen through the 10 Hz tick
			local before = monster:GetAttribute("Dodges")
			for _ = 1, 60 do
				H.advance(0.1)
				SS._Step(0.1)
			end
			T.eq(monster:GetAttribute("Dodges"), math.min(3, before + 1), "regen +1 after delay+interval")
			T.ok(#H.stats > 0, "stats recorded")
		end)
	end,

	services_block_parry_guard = function(T, Loader)
		withHarness(Loader, function(H)
			local DS, SS = H.S.DamageService, H.S.StatusService
			local monster = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -5), { dodges = 0, maxDodges = 0 })
			local human = H.spawn("Determination", "Humans", Vector3.zero) -- faces -Z (toward the monster)
			local parried = 0
			DS.Parried:Connect(function()
				parried += 1
			end)
			human:SetAttribute("Blocking", true)
			human:SetAttribute("BlockStart", H.now() - 0.05)
			human:SetAttribute("Guard", 50)
			local r = DS.Apply({ Attacker = monster, Target = human, Amount = 20, Kind = "Melee", KR = 5 })
			T.ok(r.Parried and r.Applied == 0, "perfect parry")
			T.ok(SS.Has(monster, "Stunned"), "melee attacker stunned")
			T.eq(human:GetAttribute("Guard"), 65, "parry +guard")
			T.eq(human:GetAttribute("Ult"), 8, "parry +ult")
			T.eq(human:GetAttribute("KR"), 0, "no KR on parry")
			H.runDue()
			T.eq(parried, 1, "Parried signal")
			-- beam during the window: blocked, not parried
			local rb = DS.Apply({ Attacker = monster, Target = human, Amount = 20, Kind = "Beam", KR = 10 })
			T.ok(rb.Blocked and not rb.Parried, "beams are blocked, not parried")
			T.near(rb.Applied, 6, 1e-6, "70 % reduced")
			T.near(human:GetAttribute("Guard"), 51, 1e-6, "guard drained by the blocked amount")
			T.near(human:GetAttribute("KR"), 3, 1e-6, "KR reduced when blocked")
			-- outside the parry window
			human:SetAttribute("BlockStart", H.now() - 1)
			local r2 = DS.Apply({ Attacker = monster, Target = human, Amount = 10, Kind = "Melee" })
			T.ok(r2.Blocked and not r2.Parried, "late block")
			-- from behind: not blocked
			local behind = H.spawn("FellSans", "Monster", Vector3.new(0, 0, 6), { dodges = 0, maxDodges = 0 })
			local r3 = DS.Apply({ Attacker = behind, Target = human, Amount = 10, Kind = "Melee" })
			T.ok(not r3.Blocked and r3.Applied == 10, "attack from behind ignores block")
			-- area damage is not blockable by default
			local r4 = DS.Apply({ Attacker = monster, Target = human, Amount = 10, Kind = "Area" })
			T.ok(not r4.Blocked, "area not blockable")
			-- guard break
			human:SetAttribute("Guard", 5)
			local r5 = DS.Apply({ Attacker = monster, Target = human, Amount = 40, Kind = "Melee", Stun = 2 })
			T.ok(r5.Blocked and r5.GuardBroken, "guard break")
			T.eq(human:GetAttribute("Blocking"), false, "block dropped")
			T.ok(SS.Has(human, "Stunned"), "guard break stun")
			local hum = human:FindFirstChildOfClass("Humanoid")
			T.eq(hum.WalkSpeed, 0, "stunned cannot walk")
		end)
	end,

	services_kr_downed_kill = function(T, Loader)
		withHarness(Loader, function(H)
			local DS, SS = H.S.DamageService, H.S.StatusService
			local monster =
				H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -5), { dodges = 0, maxDodges = 0, hp = 2000 })
			local human = H.spawn("Determination", "Humans", Vector3.zero)
			local ally = H.spawn("Bravery", "Humans", Vector3.new(4, 0, 0))
			local r = DS.Apply({ Attacker = monster, Target = human, Amount = 10, Kind = "Melee", KR = 6 })
			T.eq(r.Applied, 10, "damage")
			T.eq(human:GetAttribute("KR"), 6, "KR added")
			T.ok(human:GetAttribute("Ult") > 0 and monster:GetAttribute("Ult") > 0, "ult gained both sides")
			-- KR drain never kills
			DS.AddKR(human, 100)
			T.eq(human:GetAttribute("KR"), 40, "KR cap")
			local hum = human:FindFirstChildOfClass("Humanoid")
			hum.Health = 5
			for _ = 1, 100 do
				H.advance(0.1)
				SS._Step(0.1)
			end
			T.near(H.hp(human), 1, 1e-6, "KR drained to 1 HP, not 0")
			T.ok(human:GetAttribute("KR") < 40, "KR decays")
			-- human hit cleanses KR
			human:SetAttribute("KR", 10)
			DS.Apply({ Attacker = human, Target = monster, Amount = 5, Kind = "Melee" })
			T.eq(human:GetAttribute("KR"), 7, "landing a hit cleanses 3 KR")
			-- lethal hit -> downed (revives left, round phase)
			local rd = DS.Apply({ Attacker = monster, Target = human, Amount = 50, Kind = "Melee", KR = 5 })
			T.ok(rd.Downed and not rd.Killed, "downed")
			T.eq(H.hp(human), 1, "downed humans keep 1 HP (Humanoid stays alive)")
			T.eq(#H.downs, 1, "SetDowned called")
			-- allies cannot hurt, monster damage kills a downed human
			local rf = DS.Apply({ Attacker = ally, Target = human, Amount = 5, Kind = "Melee" })
			T.eq(rf.Reason, "Team", "no friendly fire")
			local rk = DS.Apply({ Attacker = monster, Target = human, Amount = 1, Kind = "Area" })
			T.ok(rk.Killed, "monster damage kills the downed")
			T.eq(H.kills[1].model, human, "Kill called")
			T.eq(H.kills[1].attacker, monster, "killer attributed")
			-- no revives left -> straight kill
			H.round.TeamRevives = 0
			local r2 = DS.Apply({ Attacker = monster, Target = ally, Amount = 500, Kind = "Melee" })
			T.ok(r2.Killed and not r2.Downed, "no revives: killed")
			-- Determined keeps 1 HP
			local det = H.spawn("Determination", "Humans", Vector3.new(-4, 0, 0))
			SS.Apply(det, "Determined", 5)
			local r3 = DS.Apply({ Attacker = monster, Target = det, Amount = 999, Kind = "Melee" })
			T.ok(not r3.Killed and H.hp(det) == 1, "Determined floor")
			-- monster cannot die before its final phase; crossing 30 % triggers it
			local mh = monster:FindFirstChildOfClass("Humanoid")
			DS.Apply({ Attacker = det, Target = monster, Amount = 1500, Kind = "Melee" })
			H.runDue()
			T.ok(H.finalPhase >= 1, "final phase triggered below 30 %")
			DS.Apply({ Attacker = det, Target = monster, Amount = 5000, Kind = "Melee" })
			T.ok(mh.Health >= 1 and monster:GetAttribute("Dead") ~= true, "no death before the final phase")
			H.round.FinalPhase = true
			local rk2 = DS.Apply({ Attacker = det, Target = monster, Amount = 5000, Kind = "Melee" })
			T.ok(rk2.Killed, "monster dies after its final phase")
			-- environment True damage passes IFrames, not Invulnerable
			local h3 = H.spawn("Kindness", "Humans", Vector3.new(8, 0, 0))
			SS.Apply(h3, "IFrames", 1)
			T.eq(DS.Apply({ Target = h3, Amount = 5, Kind = "True" }).Applied, 5, "collapse damage passes i-frames")
			T.eq(DS.Apply({ Attacker = monster, Target = h3, Amount = 5, Kind = "Melee" }).Reason, "Immune", "i-frames")
			SS.Apply(h3, "Invulnerable", 1)
			T.eq(DS.Apply({ Target = h3, Amount = 5, Kind = "True" }).Reason, "Immune", "invulnerable")
			-- boxed targets only take Box damage, floor 1
			local h4 = H.spawn("Justice", "Humans", Vector3.new(12, 0, 0), { hp = 20 })
			SS.Apply(h4, "Boxed", 3)
			SS.Apply(h4, "Invulnerable", 3)
			T.eq(DS.Apply({ Attacker = monster, Target = h4, Amount = 5, Kind = "Melee" }).Reason, "Immune", "boxed")
			local rb = DS.Apply({ Attacker = monster, Target = h4, Amount = 50, Kind = "Box", KR = 3 })
			T.ok(rb.Applied == 19 and not rb.Killed, "box damage floors at 1 HP")
			-- training dummies refill instead of dying
			local dummy = H.spawn("Dummy", "Dummy", Vector3.new(0, 0, 10), { hp = 50 })
			local rdm = DS.Apply({ Attacker = human, Target = dummy, Amount = 60, Kind = "Melee" })
			T.ok(rdm.Killed and H.hp(dummy) == 50, "dummy refilled")
		end)
	end,

	services_colors_shield_hooks_mults = function(T, Loader)
		withHarness(Loader, function(H)
			local DS, SS = H.S.DamageService, H.S.StatusService
			local monster =
				H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -5), { dodges = 0, maxDodges = 0, hp = 5000 })
			local human = H.spawn("Determination", "Humans", Vector3.zero)
			T.eq(
				DS.Apply({ Attacker = monster, Target = human, Amount = 10, Kind = "Area", Color = "Blue" }).Reason,
				"Color",
				"blue spares the still"
			)
			H.speeds[human] = 6
			T.eq(
				DS.Apply({ Attacker = monster, Target = human, Amount = 10, Kind = "Area", Color = "Blue" }).Applied,
				10,
				"blue hurts movers"
			)
			T.eq(
				DS.Apply({ Attacker = monster, Target = human, Amount = 10, Kind = "Area", Color = "Orange" }).Reason,
				"Color",
				"orange spares movers"
			)
			H.speeds[human] = 0
			T.eq(
				DS.Apply({ Attacker = monster, Target = human, Amount = 10, Kind = "Area", Color = "Orange" }).Applied,
				10,
				"orange hurts the still"
			)
			local hum = human:FindFirstChildOfClass("Humanoid")
			hum.Health = hum.MaxHealth
			-- shield
			SS.Apply(human, "Shielded", 5, { amount = 40 })
			T.eq(human:GetAttribute("Shield"), 40, "shield attribute")
			local rs = DS.Apply({ Attacker = monster, Target = human, Amount = 30, Kind = "Beam", KR = 6 })
			T.ok(rs.Absorbed == 30 and rs.Applied == 0, "absorbed")
			T.eq(human:GetAttribute("KR"), 0, "fully absorbed: no KR")
			T.eq(human:GetAttribute("Shield"), 10, "shield left")
			local rs2 = DS.Apply({ Attacker = monster, Target = human, Amount = 30, Kind = "Beam" })
			T.ok(rs2.Absorbed == 10 and rs2.Applied == 20, "shield breaks")
			T.ok(not SS.Has(human, "Shielded"), "shield removed")
			hum.Health = hum.MaxHealth
			-- multipliers: buffs add, reductions multiply
			SS.Apply(human, "DamageUp", 5, { mult = 1.2 })
			SS.Apply(human, "Rage", 5, { damage = 1.3, speed = 1 })
			T.near(human:GetAttribute("Buff_DamageMult"), 1.5, 1e-6, "Buff_DamageMult attribute")
			T.near(
				DS.Apply({ Attacker = human, Target = monster, Amount = 10, Kind = "Melee" }).Applied,
				15,
				1e-6,
				"x1.5"
			)
			SS.Apply(monster, "DamageDown", 5, { mult = 0.5 })
			T.near(
				DS.Apply({ Attacker = human, Target = monster, Amount = 10, Kind = "Melee" }).Applied,
				7.5,
				1e-6,
				"target reduction"
			)
			SS.Remove(monster, "DamageDown")
			H.round.Harmony = 1.12
			T.near(
				DS.Apply({ Attacker = human, Target = monster, Amount = 10, Kind = "Melee" }).Applied,
				16.2,
				1e-6,
				"Harmony adds for humans"
			)
			H.round.Harmony = 1
			SS.Remove(human, "Rage")
			SS.Remove(human, "DamageUp")
			-- StealthStrike: x mult, undodgeable, consumed
			monster:SetAttribute("Dodges", 2)
			monster:SetAttribute("MaxDodges", 2)
			SS.Apply(human, "StealthStrike", 6, { mult = 1.6 })
			local rst = DS.Apply({ Attacker = human, Target = monster, Amount = 10, Kind = "Melee" })
			T.ok(not rst.Dodged and math.abs(rst.Applied - 16) < 1e-6, "stealth strike")
			T.ok(not SS.Has(human, "StealthStrike"), "consumed")
			T.ok(
				DS.Apply({ Attacker = human, Target = monster, Amount = 10, Kind = "Melee" }).Dodged,
				"next hit dodgeable"
			)
			monster:SetAttribute("Dodges", 0)
			monster:SetAttribute("MaxDodges", 0)
			-- hooks
			local remove = DS.AddHook("Before", function(info, _result, state)
				if info.Ability == "Nope" then
					state.CancelReason = "TestShield"
					return true
				end
				if info.Ability == "Double" then
					state.Mult = 2
				end
				return nil
			end)
			local seen = 0
			local removeAfter = DS.AddHook("After", function(_info, result)
				seen += 1
				return nil
			end)
			local rc = DS.Apply({ Attacker = human, Target = monster, Amount = 10, Kind = "Melee", Ability = "Nope" })
			T.eq(rc.Reason, "Cancelled", "hook cancel")
			local fx = H.last("DamageFx")
			T.eq(fx.negated, "TestShield", "negated fx")
			T.near(
				DS.Apply({ Attacker = human, Target = monster, Amount = 10, Kind = "Melee", Ability = "Double" }).Applied,
				20,
				1e-6,
				"hook mult"
			)
			T.ok(seen >= 2, "after hooks run")
			remove()
			removeAfter()
			T.near(
				DS.Apply({ Attacker = human, Target = monster, Amount = 10, Kind = "Melee", Ability = "Double" }).Applied,
				10,
				1e-6,
				"hook removed"
			)
			-- KRBoost doubles KR
			SS.Apply(monster, "KRBoost", 5, { mult = 2 })
			human:SetAttribute("KR", 0)
			DS.Apply({ Attacker = monster, Target = human, Amount = 1, Kind = "Melee", KR = 4 })
			T.eq(human:GetAttribute("KR"), 8, "KRBoost")
			-- heal
			hum.Health = 50
			local healed = DS.Heal(human, 1000, monster)
			T.eq(healed, hum.MaxHealth - 50, "heal capped at max")
			-- drain dodges -> exhausted
			monster:SetAttribute("Dodges", 2)
			monster:SetAttribute("MaxDodges", 4)
			T.eq(DS.DrainDodges(monster, 5, human), 2, "drained what was left")
			T.ok(SS.Has(monster, "Exhausted"), "drained to 0 exhausts")
		end)
	end,

	services_status_movement = function(T, Loader)
		withHarness(Loader, function(H)
			local SS = H.S.StatusService
			local human = H.spawn("Determination", "Humans", Vector3.zero) -- WalkSpeed 17, JumpPower 50
			local hum = human:FindFirstChildOfClass("Humanoid")
			T.eq(hum.WalkSpeed, 17, "base walk")
			SS.Apply(human, "Slowed", 2, { mult = 0.5 })
			T.near(hum.WalkSpeed, 8.5, 1e-6, "slowed")
			T.ok(type(human:GetAttribute("Status_Slowed")) == "number", "status attribute")
			SS.Apply(human, "Hasted", 1, { mult = 1.2 })
			T.near(hum.WalkSpeed, 17 * 0.5 * 1.2, 1e-6, "modifiers multiply")
			H.advance(1.05)
			T.near(hum.WalkSpeed, 8.5, 1e-6, "haste expired (exact timer)")
			T.eq(human:GetAttribute("Status_Hasted"), nil, "attribute cleared")
			SS.Apply(human, "Stunned", 0.5)
			T.eq(hum.WalkSpeed, 0, "stunned")
			T.eq(hum.JumpPower, 0, "stunned no jump")
			T.ok(not SS.CanAct(human), "cannot act")
			H.advance(0.6)
			T.ok(SS.CanAct(human), "can act again")
			H.advance(1)
			T.eq(hum.WalkSpeed, 17, "all expired")
			human:SetAttribute("Blocking", true)
			SS.RecomputeMovement(human)
			T.near(hum.WalkSpeed, 17 * 0.55, 1e-6, "blocking slows")
			human:SetAttribute("Blocking", false)
			SS.Apply(human, "Blue", 1)
			SS.RecomputeMovement(human)
			T.near(hum.JumpPower, 50 * 0.35, 1e-6, "blue gravity")
			T.eq(human:GetAttribute("SoulMode"), "Blue", "soul mode blue")
			SS.Apply(human, "Boxed", 1)
			T.eq(human:GetAttribute("SoulMode"), "Boxed", "boxed wins")
			SS.Remove(human, "Boxed")
			T.eq(human:GetAttribute("SoulMode"), "Blue", "back to blue")
			H.advance(1.1)
			T.eq(human:GetAttribute("SoulMode"), "Red", "red again")
			human:SetAttribute("Downed", true)
			SS.RecomputeMovement(human)
			T.eq(hum.WalkSpeed, 4, "downed crawl speed")
			human:SetAttribute("Downed", false)
			-- refresh keeps the later end time and replaces data
			SS.Apply(human, "Slowed", 3, { mult = 0.9 })
			SS.Apply(human, "Slowed", 1, { mult = 0.7 })
			local endsAt, data = SS.Get(human, "Slowed")
			T.ok(endsAt and math.abs(endsAt - (H.now() + 3)) < 1e-6 and data.mult == 0.7, "refresh semantics")
			T.eq(SS.Cleanse(human), 1, "cleanse removes debuffs")
			-- ult passive (round phase) and dash/guard regen
			human:SetAttribute("Ult", 0)
			human:SetAttribute("DashCharges", 0)
			human:SetAttribute("Guard", 50)
			for _ = 1, 30 do
				H.advance(0.1)
				SS._Step(0.1)
			end
			T.near(human:GetAttribute("Ult"), 0.6, 0.11, "human ult per second")
			T.eq(human:GetAttribute("DashCharges"), 1, "dash charge regen 2.8 s")
			T.ok(human:GetAttribute("Guard") > 70, "guard regen")
			local unhook = SS.OnTick(function() end)
			T.ok(type(unhook) == "function", "OnTick returns a disconnect")
			unhook()
		end)
	end,

	services_hazards = function(T, Loader)
		withHarness(Loader, function(H)
			local HS = H.S.HazardService
			local monster = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -20), { dodges = 0, maxDodges = 0 })
			local human = H.spawn("Determination", "Humans", Vector3.zero)
			local friend = H.spawn("Kindness", "Humans", Vector3.new(30, 0, 0))
			local hits = 0
			HS.HazardHit:Connect(function()
				hits += 1
			end)
			local id = HS.Spawn(
				monster,
				"Monster",
				"BoneSpikes",
				{ center = Vector3.zero, radius = 5, delay = 0.6, damage = 12, kr = 4 }
			)
			T.ok(id > 0, "spawned")
			local pkt = H.last("Hazard")
			T.ok(
				pkt and pkt.id == id and pkt.type == "BoneSpikes" and pkt.t0 == H.now() and pkt.team == "Monster",
				"Hazard packet"
			)
			T.eq(pkt.params.rise, 0.12, "normalized params broadcast")
			HS._Step(1 / 60)
			T.eq(H.hp(human), 110, "telegraph: no damage")
			H.advance(0.7)
			HS._Step(1 / 60)
			T.eq(H.hp(human), 98, "spikes hit")
			T.eq(human:GetAttribute("KR"), 4, "hazard KR")
			H.advance(0.1)
			HS._Step(1 / 60)
			T.eq(H.hp(human), 98, "Once policy")
			H.runDue()
			T.eq(hits, 1, "HazardHit")
			-- blue line: the still human is spared and hit once moving
			local line = HS.Spawn(monster, "Monster", "BoneLine", {
				origin = H.HazardDefs.LookAlong(Vector3.new(0, 0, -10), Vector3.new(0, 0, 1)),
				count = 5,
				spacing = 2,
				speed = 20,
				distance = 30,
				delay = 0,
				damage = 7,
				color = "Blue",
			})
			H.advance(0.5)
			HS._Step(1 / 60) -- row at z = 0
			T.eq(H.hp(human), 98, "blue spares the still")
			H.speeds[human] = 5
			H.advance(0.02)
			HS._Step(1 / 60)
			T.eq(H.hp(human), 91, "blue hits the mover")
			H.speeds[human] = 0
			HS.Remove(line)
			T.eq(H.last("HazardEnd"), line, "HazardEnd on removal")
			-- projectile ends on its first hit; fast projectile cannot tunnel on a slow frame
			local before = H.count("HazardEnd")
			local proj = HS.Spawn(monster, "Monster", "Projectile", {
				origin = H.HazardDefs.LookAlong(Vector3.new(0, 3, -20), Vector3.new(0, 0, 1)),
				speed = 120,
				radius = 0.5,
				maxDist = 60,
				damage = 5,
			})
			HS._Step(0)
			H.advance(1 / 6) -- 20 studs in one (slow) frame: sub-stepping must catch the body at z = 0
			HS._Step(1 / 6)
			T.eq(H.hp(human), 86, "projectile hit (sub-stepped)")
			T.eq(HS.Get(proj), nil, "projectile ended")
			T.eq(H.count("HazardEnd"), before + 1, "HazardEnd for the projectile")
			-- rain: two drops can hit the same target (PerKey)
			local rain = HS.Spawn(
				monster,
				"Monster",
				"Rain",
				{ center = Vector3.zero, radius = 0.01, count = 2, interval = 0.3, delay = 0.2, size = 3, damage = 3 }
			)
			for _ = 1, 50 do
				H.advance(0.02)
				HS._Step(0.02)
			end
			T.eq(H.hp(human), 80, "two rain drops")
			T.eq(HS.Get(rain), nil, "rain expired naturally")
			-- heal zone for allies only
			local hum = human:FindFirstChildOfClass("Humanoid")
			hum.Health = 50
			local zone = HS.Spawn(
				friend,
				"Humans",
				"Zone",
				{
					center = Vector3.zero,
					radius = 6,
					delay = 0,
					duration = 2,
					tick = 0.5,
					effect = "Heal",
					amount = 6,
					cleanseKR = 2,
				}
			)
			for _ = 1, 30 do
				H.advance(0.05)
				HS._Step(0.05)
			end
			T.eq(H.hp(human), 68, "heal ticks (t = 0, 0.5, 1.0)")
			T.eq(human:GetAttribute("KR"), 0, "KR cleansed")
			HS.Remove(zone)
			-- orb pulls enemies (server-applied mover for bots)
			HS.Spawn(
				monster,
				"Monster",
				"Orb",
				{ center = Vector3.new(0, 3, -6), radius = 12, delay = 0, duration = 1, pullStrength = 14, damage = 9 }
			)
			H.advance(0.05)
			HS._Step(0.05)
			local root = human.PrimaryPart
			local mover = root:FindFirstChild("SV_Mover")
			T.ok(mover ~= nil and mover.VectorVelocity.Z < -10, "pulled toward the orb")
			H.advance(1.1)
			HS._Step(0.05)
			T.eq(H.hp(human), 59, "implosion")
			T.eq(root:FindFirstChild("SV_Mover"), nil, "mover cleaned up")
			-- invalid params are rejected, the cap holds (expected warnings silenced)
			Loader.quietWarnings = true
			T.eq(HS.Spawn(monster, "Monster", "BlasterBeam", { length = 5 }), 0, "missing origin rejected")
			for _ = 1, 45 do
				HS.Spawn(monster, "Monster", "Zone", { center = Vector3.new(500, 0, 0), duration = 30 })
			end
			Loader.quietWarnings = false
			T.ok(HS.Count() <= 40, "hazard cap")
			T.eq(#HS.GetActive(), HS.Count(), "GetActive lists live records")
			T.ok(HS.GetActive()[1].Def ~= nil and HS.GetActive()[1].Params ~= nil, "records expose Def/Params")
			HS.Clear()
			T.eq(HS.Count(), 0, "cleared")
		end)
	end,

	services_ability_casts = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, SS, HS = H.S.AbilityService, H.S.StatusService, H.S.HazardService
			local sans = H.spawn("ClassicSans", "Monster", Vector3.zero, { dodges = 0, maxDodges = 0 })
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -5), { look = Vector3.new(0, 0, 1) })
			local far = H.spawn("Patience", "Humans", Vector3.new(0, 0, -30), { look = Vector3.new(0, 0, 1) })
			-- M1 combo
			local ok = AS.CastAs(sans, "BoneJab", { aim = Vector3.new(0, 3, -5), castId = 7 })
			T.ok(ok, "BoneJab cast")
			local fx = H.last("AbilityFx")
			T.ok(fx ~= nil, "fx")
			T.eq(H.hp(human), 103, "combo hit 1 (7 dmg)")
			T.eq(human:GetAttribute("KR"), 3, "BoneJab KR")
			T.ok(type(sans:GetAttribute("Cooldown_BoneJab")) == "number", "cooldown attribute")
			local ok2, why = AS.CastAs(sans, "BoneJab", { aim = Vector3.new(0, 3, -5) })
			T.ok(not ok2 and why == "cooldown", "cooldown enforced")
			H.advance(0.45)
			AS.CastAs(sans, "BoneJab", { aim = Vector3.new(0, 3, -5) })
			H.advance(0.45)
			AS.CastAs(sans, "BoneJab", { aim = Vector3.new(0, 3, -5) })
			T.eq(H.hp(human), 110 - 7 - 7 - 12, "three-hit combo damage")
			local root = human.PrimaryPart
			T.ok(root:FindFirstChild("SV_Mover") ~= nil, "last hit knocks back (bot mover)")
			H.advance(1.2)
			AS.CastAs(sans, "BoneJab", { aim = Vector3.new(0, 3, -5) })
			H.runDue()
			-- Gaster Blaster: full charge after holding long enough
			H.advance(2)
			local hazardsBefore = H.count("Hazard")
			AS.CastAs(sans, "GasterBlaster", { aim = Vector3.new(0, 0, -30), charge = 1 })
			T.eq(H.count("Hazard") - hazardsBefore, 3, "3 blasters at full charge")
			local beam = H.last("Hazard")
			T.eq(beam.type, "BlasterBeam", "beam hazard")
			T.ok(beam.params.origin.Position.Y > 3, "blasters float above Sans")
			T.ok(beam.params.origin.LookVector.Z < -0.9, "aimed at the target")
			T.ok(beam.params.delay > 0.75, "staggered")
			-- cheated charge is clamped (just came off cooldown)
			AS.SetCooldown(sans, "GasterBlaster", 0)
			hazardsBefore = H.count("Hazard")
			AS.CastAs(sans, "GasterBlaster", { aim = Vector3.new(0, 0, -30), charge = 1 })
			T.eq(H.count("Hazard") - hazardsBefore, 1, "charge clamped to the real hold time")
			-- Blue Soul on a target
			local hpBefore = H.hp(far)
			T.ok(AS.CastAs(sans, "BlueSoul", { aim = Vector3.new(0, 3, -30), target = far }), "BlueSoul")
			T.ok(SS.Has(far, "Blue"), "blue soul applied")
			T.eq(H.hp(far), hpBefore - 14, "slam damage")
			T.ok(SS.Has(far, "Stunned"), "stunned after the slam")
			-- Bone Zone / Bone Wall / Bad Time
			T.ok(AS.CastAs(sans, "BoneZone", { aim = Vector3.new(0, 0, -20) }), "BoneZone")
			local zoneHazard = H.last("Hazard")
			T.ok(zoneHazard.params.ring == true and zoneHazard.params.color == "Orange", "orange ring")
			T.ok(AS.CastAs(sans, "BoneWall", { aim = Vector3.new(0, 0, -20), dir = Vector3.new(0, 0, -1) }), "BoneWall")
			T.eq(H.last("Hazard").params.color, "Blue", "blue wall")
			local okUlt, whyUlt = AS.CastAs(sans, "BadTime", { aim = Vector3.new(0, 0, -20) })
			T.ok(not okUlt and whyUlt == "ult", "ult needs 100")
			sans:SetAttribute("Ult", 100)
			hazardsBefore = H.count("Hazard")
			T.ok(AS.CastAs(sans, "BadTime", { aim = Vector3.new(0, 0, -20) }), "BadTime")
			T.eq(sans:GetAttribute("Ult"), 0, "ult consumed")
			T.eq(H.count("Hazard") - hazardsBefore, 7, "6 blasters + rain")
			T.ok(SS.Has(sans, "KRBoost"), "KR boost")
			HS.Clear()
			-- Determination kit: afterimage counter, ultimate, lunge
			local det = H.spawn("Determination", "Humans", Vector3.new(12, 0, 0), { look = Vector3.new(-1, 0, 0) })
			H.S.AbilityService.GetServerKit("Determination").OnSpawn(det, nil)
			T.ok(AS.CastAs(det, "Afterimage", { dir = Vector3.new(0, 0, 1) }), "Afterimage cast")
			T.ok(SS.Has(det, "Afterimage"), "afterimage window")
			local sansHp = H.hp(sans)
			local rr = H.S.DamageService.Apply({ Attacker = sans, Target = det, Amount = 30, Kind = "Melee" })
			T.eq(rr.Reason, "Cancelled", "hit negated by Afterimage")
			H.runDue()
			T.eq(H.hp(sans), sansHp - 20, "counter-slash damage")
			T.ok(SS.Has(sans, "Stunned"), "counter stun")
			det:SetAttribute("Ult", 100)
			T.ok(AS.CastAs(det, "DeterminationUlt", {}), "ult cast")
			T.ok(SS.Has(det, "Undodgeable") and SS.Has(det, "Determined") and SS.Has(det, "DamageUp"), "ult statuses")
			sans:SetAttribute("Dodges", 3)
			sans:SetAttribute("MaxDodges", 3)
			SS.Remove(sans, "Stunned")
			local ru = H.S.DamageService.Apply({ Attacker = det, Target = sans, Amount = 10, Kind = "Melee" })
			T.ok(not ru.Dodged and math.abs(ru.Applied - 12) < 1e-6, "undodgeable +20 %")
			-- Hope: below 35 % HP -> +12 %
			det:FindFirstChildOfClass("Humanoid").Health = 20
			SS.Remove(det, "DamageUp")
			local rh = H.S.DamageService.Apply({ Attacker = det, Target = sans, Amount = 10, Kind = "Melee" })
			T.near(rh.Applied, 11.2, 1e-6, "Hope passive")
			-- Lunging strike hits along the path
			local victim = H.spawn("FellSans", "Monster", Vector3.new(5, 0, 0), { dodges = 0, maxDodges = 0 })
			local vhp = H.hp(victim)
			T.ok(AS.CastAs(det, "LungingStrike", { aim = Vector3.new(0, 3, 0), dir = Vector3.new(-1, 0, 0) }), "lunge")
			T.ok(H.hp(victim) < vhp, "lunge hit the monster on the path")
			-- player-facing net handlers
			local player = Instance.new("Player")
			player.Name = "P"
			player.Parent = Instance.new("Folder")
			H.playerOf = { [human] = player }
			H.modelOf = { [player] = human }
			AS.Start()
			human:SetAttribute("Blocking", false)
			H.handlers.Block(player, true)
			T.eq(human:GetAttribute("Blocking"), true, "Block handler")
			T.ok(human:GetAttribute("BlockStart") > 0, "parry window open")
			H.handlers.Block(player, false)
			H.handlers.Block(player, "yes")
			T.eq(human:GetAttribute("Blocking"), false, "garbage ignored")
			local charges = human:GetAttribute("DashCharges")
			SS.Remove(human, "Stunned")
			SS.Remove(human, "Blue")
			H.handlers.Dash(player, Vector3.new(1, 0, 0))
			T.eq(human:GetAttribute("DashCharges"), charges - 1, "dash consumed a charge")
			T.ok(SS.Has(human, "IFrames"), "dash i-frames")
			local fm = H.last("ForceMove")
			T.ok(fm and fm.kind == "Dash" and fm.echo == true, "dash echo packet to the owner")
			H.handlers.Cast(player, "KnifeCombo", { aim = Vector3.new(0, 3, 5), castId = 3 })
			local cd = H.last("Cooldown")
			T.eq(cd, "KnifeCombo", "cooldown sent to caster")
			H.handlers.Cast(player, string.rep("x", 100), {})
			H.handlers.Cast(player, "KnifeCombo", "garbage")
			-- Verdict Box (monster, F)
			SS.Remove(sans, "Stunned")
			local box = AS.CastAs(sans, "VerdictBox", { dir = Vector3.new(0, 0, -1) })
			T.ok(box and #H.boxes == 1, "verdict box started")
			T.ok(H.boxes[1].victim == far or H.boxes[1].victim == human, "victim in the cone")
			T.ok(not AS.CastAs(sans, "VerdictBox", { dir = Vector3.new(0, 0, -1) }), "verdict box cooldown")
			-- cooldown scaling (Patience field)
			AS.SetCooldown(sans, "BoneZone", 4)
			local before = AS.GetCooldowns(sans).BoneZone
			AS.ScaleCooldowns(sans, 0.5, 6)
			T.near(AS.GetCooldowns(sans).BoneZone - before, 3, 1e-6, "half-speed cooldowns")
			AS.ResetCooldowns(sans)
			T.eq(next(AS.GetCooldowns(sans)), nil, "reset")
		end)
	end,
}

for name, fn in integration do
	tests[name] = fn
end

return tests
