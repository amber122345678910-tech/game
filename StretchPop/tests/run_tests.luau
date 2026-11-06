-- Lune: рантайм-тесты чистой логики + построения полосы настоящими Instance.
-- Запуск из корня StretchPop: lune run tests/run_tests.luau
local process = require("@lune/process")
local H = require("./harness")
local roblox = H.roblox
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Bezier = H.require("ReplicatedStorage.Shared.Math.Bezier")
local Spring = H.require("ReplicatedStorage.Shared.Math.Spring")
local StretchPhysics = H.require("ReplicatedStorage.Shared.Physics.StretchPhysics")
local PhysicsConfig = H.require("ReplicatedStorage.Shared.Config.PhysicsConfig")
local LevelConfig = H.require("ReplicatedStorage.Shared.Config.LevelConfig")
local GloveConfig = H.require("ReplicatedStorage.Shared.Config.GloveConfig")
local ProfileTemplate = H.require("ReplicatedStorage.Shared.Data.ProfileTemplate")
local Signal = H.require("ReplicatedStorage.Shared.Util.Signal")
local LevelBuilder = H.require("ServerScriptService.Server.Level.LevelBuilder")

local function vnear(a: any, b: any, eps: number, label: string)
	H.check((a - b).Magnitude <= eps, string.format("%s: |%s - %s| > %g", label, tostring(a), tostring(b), eps))
end

-- ── Bezier ─────────────────────────────────────────────────────────────────
H.suite("Bezier")
H.test("SplitCubic halves reproduce the original curve", function()
	local p0, p1, p2, p3 = Vector3.new(0, 0, 0), Vector3.new(3, 8, 1), Vector3.new(9, -4, 2), Vector3.new(12, 2, -5)
	local a0, a1, a2, m, b1, b2, b3 = Bezier.SplitCubic(p0, p1, p2, p3, 0.5)
	for i = 0, 10 do
		local t = i / 10
		vnear(Bezier.Cubic(a0, a1, a2, m, t), Bezier.Cubic(p0, p1, p2, p3, t * 0.5), 1e-4, "left half")
		vnear(Bezier.Cubic(m, b1, b2, b3, t), Bezier.Cubic(p0, p1, p2, p3, 0.5 + t * 0.5), 1e-4, "right half")
	end
	-- гладкий стык: касательные в m коллинеарны
	local left = (m - a2).Unit
	local right = (b1 - m).Unit
	H.near(left:Dot(right), 1, 1e-5, "tangent continuity")
end)
H.test("FromBallistic is exact for a parabola", function()
	local p0, v0, g = Vector3.new(1, 2, 3), Vector3.new(40, 60, -80), Vector3.new(0, -160, 0)
	local duration = 1.7
	local c0, c1, c2, c3 = Bezier.FromBallistic(p0, v0, g, duration)
	for i = 0, 20 do
		local s = i / 20
		local t = s * duration
		local analytic = p0 + v0 * t + g * (0.5 * t * t)
		vnear(Bezier.Cubic(c0, c1, c2, c3, s), analytic, 1e-3, "parabola point")
	end
end)
H.test("CubicDerivative matches finite differences", function()
	local p0, p1, p2, p3 = Vector3.new(0, 0, 0), Vector3.new(1, 5, 0), Vector3.new(4, 5, 2), Vector3.new(6, 0, 1)
	local h = 1e-4
	for _, t in { 0.1, 0.4, 0.77 } do
		local numeric = (Bezier.Cubic(p0, p1, p2, p3, t + h) - Bezier.Cubic(p0, p1, p2, p3, t - h)) / (2 * h)
		vnear(Bezier.CubicDerivative(p0, p1, p2, p3, t), numeric, 1e-2, "derivative")
	end
end)

-- ── Spring (закон Гука) ────────────────────────────────────────────────────
H.suite("Spring")
H.test("critically damped spring converges without overshoot", function()
	local spring = Spring.Number.new(0, 4, 1)
	spring.Target = 10
	local maxValue = 0
	for _ = 1, 240 do
		maxValue = math.max(maxValue, spring:Update(1 / 60))
	end
	H.near(spring.Position, 10, 1e-3, "settled")
	H.check(maxValue <= 10.0001, "critical damping must not overshoot, max=" .. maxValue)
end)
H.test("underdamped spring overshoots (cartoon wobble)", function()
	local spring = Spring.Number.new(0, 3, 0.3)
	spring.Target = 1
	local maxValue = 0
	for _ = 1, 120 do
		maxValue = math.max(maxValue, spring:Update(1 / 60))
	end
	H.check(maxValue > 1.3, "expected overshoot, max=" .. maxValue)
end)
H.test("vector spring follows target and impulses decay", function()
	local spring = Spring.Vector.new(Vector3.zero, 5, 0.8)
	spring.Target = Vector3.new(3, -2, 7)
	spring:Impulse(Vector3.new(50, 0, 0))
	for _ = 1, 300 do
		spring:Update(1 / 60)
	end
	vnear(spring.Position, Vector3.new(3, -2, 7), 1e-3, "vector settle")
end)
H.test("huge frame dt is clamped (no explosion)", function()
	local spring = Spring.Number.new(0, 8, 0.5)
	spring.Target = 1
	spring:Update(5)
	H.check(spring.Position == spring.Position and math.abs(spring.Position) < 10, "spring exploded: " .. spring.Position)
end)

-- ── StretchPhysics ─────────────────────────────────────────────────────────
H.suite("StretchPhysics")
local baseStats = { Elasticity = 0, SpringPower = 0, SmashMass = 0 }
local baseParams = StretchPhysics.Derive(baseStats, "Rubber")
H.test("Derive: base values and monotonic growth with levels", function()
	H.near(baseParams.Stiffness, PhysicsConfig.Stiffness.Base, 1e-9, "k")
	H.near(baseParams.MaxStretch, PhysicsConfig.MaxStretch.Base, 1e-9, "x_max")
	H.near(baseParams.ImpactMass, 1, 1e-9, "m")
	local strong = StretchPhysics.Derive({ Elasticity = 10, SpringPower = 10, SmashMass = 10 }, "Rubber")
	H.check(strong.Stiffness > baseParams.Stiffness, "k grows")
	H.check(strong.MaxStretch > baseParams.MaxStretch, "x_max grows")
	H.check(strong.GrabRange > baseParams.GrabRange, "range grows")
	H.check(strong.ImpactMass > baseParams.ImpactMass, "mass grows")
	H.check(strong.Restitution > baseParams.Restitution and strong.Restitution < 1, "restitution grows, < 1")
	local capped = StretchPhysics.Derive({ Elasticity = 9999, SpringPower = 9999, SmashMass = 9999 }, "Rubber")
	H.near(capped.Stiffness, PhysicsConfig.Stiffness.Max, 1e-9, "k cap")
	local voidFist = StretchPhysics.Derive(baseStats, "VoidFist")
	H.near(voidFist.ImpactMass, 1 + GloveConfig.Gloves.VoidFist.ImpactMassBonus, 1e-9, "glove bonus")
end)
H.test("SlingshotLaunch: E = ½kx², v = √(2E/m), direction toward anchor", function()
	local body = Vector3.new(0, 3, 0)
	local anchor = Vector3.new(0, 3, -50)
	local rest = 30 -- растяжение 20
	local velocity, energy, tension = StretchPhysics.SlingshotLaunch(body, { { Anchor = anchor, Rest = rest } }, baseParams)
	local x = 20
	H.near(energy, 0.5 * baseParams.Stiffness * x * x, 1e-6, "energy")
	H.near(velocity.Magnitude, math.sqrt(2 * energy / baseParams.FlightMass), 1e-4, "speed")
	H.check(velocity.Unit:Dot(Vector3.new(0, 0, -1)) > 0.99, "points at anchor")
	H.check(velocity.Y > 0, "upward bias")
	H.near(tension, (x * x) / (baseParams.MaxStretch * baseParams.MaxStretch), 1e-6, "tension01")
end)
H.test("SlingshotLaunch: stretch is clamped to x_max, slack band gives nothing", function()
	local body = Vector3.zero
	local far = StretchPhysics.SlingshotLaunch(body, { { Anchor = Vector3.new(0, 0, -500), Rest = 10 } }, baseParams)
	local expected = baseParams.MaxStretch * math.sqrt(baseParams.Stiffness / baseParams.FlightMass)
	H.near(far.Magnitude, expected, 1e-3, "clamped launch speed")
	local slackVelocity, slackEnergy = StretchPhysics.SlingshotLaunch(body, { { Anchor = Vector3.new(0, 0, -5), Rest = 10 } }, baseParams)
	H.check(slackVelocity.Magnitude == 0 and slackEnergy == 0, "slack band must not launch")
end)
H.test("two bands at x_max match MaxLaunchSpeed", function()
	local body = Vector3.zero
	local x = baseParams.MaxStretch
	local bands = {
		{ Anchor = Vector3.new(-10, 0, -40), Rest = Vector3.new(-10, 0, -40).Magnitude - x },
		{ Anchor = Vector3.new(10, 0, -40), Rest = Vector3.new(10, 0, -40).Magnitude - x },
	}
	local velocity = StretchPhysics.SlingshotLaunch(body, bands, baseParams)
	H.near(velocity.Magnitude, StretchPhysics.MaxLaunchSpeed(baseParams), 1e-3, "max launch")
	H.check(StretchPhysics.MaxPlausibleSpeed(baseParams) >= velocity.Magnitude, "plausible ≥ launch")
end)
H.test("BandForce: tension only, Hooke magnitude, outward damping", function()
	local force, stretch = StretchPhysics.BandForce(Vector3.zero, Vector3.new(0, 0, -20), 12, 10, Vector3.zero, 2)
	H.near(stretch, 8, 1e-9, "stretch")
	vnear(force, Vector3.new(0, 0, -80), 1e-6, "F = k·x toward anchor")
	local slack = StretchPhysics.BandForce(Vector3.zero, Vector3.new(0, 0, -5), 12, 10, Vector3.zero, 2)
	H.check(slack.Magnitude == 0, "slack band pushes nothing")
	local damped = StretchPhysics.BandForce(Vector3.zero, Vector3.new(0, 0, -20), 12, 10, Vector3.new(0, 0, 10), 2)
	H.check(damped.Magnitude > 80, "moving away adds pull (damping)")
	local approaching = StretchPhysics.BandForce(Vector3.zero, Vector3.new(0, 0, -20), 12, 10, Vector3.new(0, 0, -10), 2)
	H.near(approaching.Magnitude, 80, 1e-6, "approach keeps full pull")
end)
H.test("Reflect keeps tangent, flips normal with restitution", function()
	local out = StretchPhysics.Reflect(Vector3.new(30, -40, 0), Vector3.new(0, 1, 0), 0.5, 1)
	vnear(out, Vector3.new(30, 20, 0), 1e-9, "reflect")
	local away = StretchPhysics.Reflect(Vector3.new(0, 10, 0), Vector3.new(0, 1, 0), 0.5, 1)
	vnear(away, Vector3.new(0, 10, 0), 1e-9, "moving away unchanged")
end)
H.test("Smash threshold: exactly the required speed breaks, slightly less does not", function()
	for _, strength in LevelConfig.WallStrengths do
		for tier = 0, 4 do
			local multiplier = LevelConfig.DurabilityMultiplier(tier)
			local durability = StretchPhysics.DurabilityFromSpeed(strength.RequiredSpeed, multiplier)
			local need = StretchPhysics.SpeedToBreak(durability, 1)
			H.near(need, strength.RequiredSpeed * math.sqrt(multiplier), 1e-6, strength.Name .. " speed")
			H.check(StretchPhysics.CanSmash(durability, 1, need + 1e-6), "breaks at threshold")
			H.check(not StretchPhysics.CanSmash(durability, 1, need * 0.99), "holds below threshold")
		end
	end
end)
H.test("ImpactSpeed favours head-on hits", function()
	local headOn = StretchPhysics.ImpactSpeed(Vector3.new(0, 0, -100), Vector3.new(0, 0, 1))
	local glancing = StretchPhysics.ImpactSpeed(Vector3.new(100, 0, -5), Vector3.new(0, 0, 1))
	H.near(headOn, 100, 1e-9, "head-on")
	H.near(glancing, 100.1249 * 0.6, 0.01, "glancing floor at 60%")
end)
H.test("base two-band launch can break Hard walls on tier 0 but not Titan", function()
	local speed = StretchPhysics.MaxLaunchSpeed(baseParams)
	local hard = StretchPhysics.DurabilityFromSpeed(LevelConfig.WallStrengths[3].RequiredSpeed, 1)
	local titan = StretchPhysics.DurabilityFromSpeed(LevelConfig.WallStrengths[4].RequiredSpeed, 1)
	H.check(StretchPhysics.CanSmash(hard, 1, speed), "hard should break at " .. speed)
	H.check(not StretchPhysics.CanSmash(titan, 1, speed), "titan should hold at " .. speed)
	local gongSpeed = LevelConfig.GongRequirement(0)
	H.check(speed >= gongSpeed, "first rebirth must be reachable with base stats")
end)
H.test("IsFiniteVector rejects NaN and huge values", function()
	H.check(StretchPhysics.IsFiniteVector(Vector3.new(1, 2, 3), 1e4), "finite ok")
	H.check(not StretchPhysics.IsFiniteVector(Vector3.new(0 / 0, 0, 0), 1e4), "NaN rejected")
	H.check(not StretchPhysics.IsFiniteVector(Vector3.new(1e9, 0, 0), 1e4), "huge rejected")
end)

-- ── Signal ─────────────────────────────────────────────────────────────────
H.suite("Signal")
H.test("connect / fire / disconnect / once / error isolation", function()
	local signal = Signal.new()
	local total = 0
	local connection = signal:Connect(function(a, b)
		total += a + b
	end)
	signal:Connect(function()
		error("boom")
	end)
	local onceCount = 0
	signal:Once(function()
		onceCount += 1
	end)
	signal:Fire(2, 3)
	signal:Fire(1, 1)
	H.check(total == 7, "sum " .. total)
	H.check(onceCount == 1, "once fired " .. onceCount)
	connection:Disconnect()
	signal:Fire(100, 100)
	H.check(total == 7, "disconnected listener still called")
end)

-- ── ProfileTemplate ────────────────────────────────────────────────────────
H.suite("ProfileTemplate")
H.test("Create returns complete defaults", function()
	local profile = ProfileTemplate.Create(1000)
	H.check(profile.DataVersion == ProfileTemplate.DataVersion, "version")
	H.check(profile.Gloves.Owned[GloveConfig.DefaultGlove] == true, "default glove owned")
	H.check(profile.Locations[LevelConfig.DefaultLocation].Tier == 0, "default location tier 0")
end)
H.test("Sanitize survives garbage and clamps values", function()
	local garbage = {
		Coins = -50,
		Stats = { Elasticity = "lots", SpringPower = 0 / 0, SmashMass = 1e9 },
		Gloves = { Owned = { VoidFist = true, Hacked = true, [5] = true }, Equipped = "Hacked" },
		Locations = { Meadows = { Tier = 3.7, Rebirths = -2 }, Unknown = { Tier = 99 } },
		ActiveLocation = "Unknown",
		Records = "nope",
	}
	local profile = ProfileTemplate.Sanitize(garbage, 2000)
	H.check(profile.Coins == 0, "coins clamped")
	H.check(profile.Stats.Elasticity == 0 and profile.Stats.SpringPower == 0, "bad stats → 0")
	H.check(profile.Stats.SmashMass == PhysicsConfig.StatUpgrade.MaxLevel, "stat capped")
	H.check(profile.Gloves.Owned.VoidFist == true and profile.Gloves.Owned.Hacked == nil, "unknown gloves dropped")
	H.check(profile.Gloves.Equipped == GloveConfig.DefaultGlove, "invalid equip reset")
	H.check(profile.Locations.Meadows.Tier == 3 and profile.Locations.Meadows.Rebirths == 0, "location sanitized")
	H.check(profile.Locations.Unknown == nil, "unknown location dropped")
	H.check(profile.ActiveLocation == LevelConfig.DefaultLocation, "active location fallback")
	H.check(profile.Records.TopSpeed == 0, "records defaulted")
end)
H.test("Sanitize keeps valid data; DeepCopy is independent", function()
	local original = ProfileTemplate.Create(1)
	original.Coins = 12345
	original.Stats.SpringPower = 7
	original.Locations.Meadows.Tier = 2
	original.Gloves.Owned.GoldenGrip = true
	original.Gloves.Equipped = "GoldenGrip"
	local restored = ProfileTemplate.Sanitize(ProfileTemplate.DeepCopy(original), 5)
	H.check(restored.Coins == 12345 and restored.Stats.SpringPower == 7, "values kept")
	H.check(restored.Locations.Meadows.Tier == 2 and restored.Gloves.Equipped == "GoldenGrip", "nested kept")
	local copy = ProfileTemplate.DeepCopy(original)
	copy.Stats.SpringPower = 99
	H.check(original.Stats.SpringPower == 7, "deep copy shares nothing")
end)

-- ── LevelConfig ────────────────────────────────────────────────────────────
H.suite("LevelConfig")
H.test("gong requirements, length, multipliers grow with tier", function()
	local previousSpeed, previousCombo = LevelConfig.GongRequirement(0)
	for tier = 1, 8 do
		local speed, combo = LevelConfig.GongRequirement(tier)
		H.check(speed >= previousSpeed and combo >= previousCombo, "requirements non-decreasing")
		previousSpeed, previousCombo = speed, combo
		H.check(LevelConfig.LootMultiplier(tier) > LevelConfig.LootMultiplier(tier - 1), "loot grows")
		H.check(LevelConfig.LaneLength(tier) <= LevelConfig.MaxLength, "length capped")
	end
	H.check(LevelConfig.TierName(0) == "Classic" and LevelConfig.TierName(3) == "Void", "names")
	H.check(LevelConfig.TierName(5) == "Void +2", "prestige name " .. LevelConfig.TierName(5))
end)

-- ── LevelBuilder: раскладка ────────────────────────────────────────────────
H.suite("LevelBuilder.GenerateLayout")
local function aabb(cframe: any, size: any): (any, any)
	-- мировой AABB повернутого бокса
	local half = size * 0.5
	local r, u, l = cframe.RightVector, cframe.UpVector, cframe.LookVector
	local extent = Vector3.new(
		math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z,
		math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z,
		math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
	)
	return cframe.Position - extent, cframe.Position + extent
end
local function overlaps(aMin: any, aMax: any, bMin: any, bMax: any, shrink: number): boolean
	return aMin.X + shrink < bMax.X and aMax.X - shrink > bMin.X
		and aMin.Y + shrink < bMax.Y and aMax.Y - shrink > bMin.Y
		and aMin.Z + shrink < bMax.Z and aMax.Z - shrink > bMin.Z
end

H.test("deterministic for the same location + tier", function()
	local a = LevelBuilder.GenerateLayout("Meadows", 2)
	local b = LevelBuilder.GenerateLayout("Meadows", 2)
	H.check(#a.Pieces == #b.Pieces and #a.Obstacles == #b.Obstacles, "counts differ")
	for i, spec in a.Obstacles do
		H.check(spec.Id == b.Obstacles[i].Id, "ids differ")
		vnear(spec.LocalCFrame.Position, b.Obstacles[i].LocalCFrame.Position, 1e-9, "positions differ")
	end
end)
for tier = 0, 6 do
	H.test("tier " .. tier .. ": invariants (bounds, ids, gong, gaps, overlaps)", function()
		local layout = LevelBuilder.GenerateLayout("Meadows", tier)
		local halfWidth = LevelConfig.LaneWidth / 2
		H.check(layout.Length == LevelConfig.LaneLength(tier), "length")
		H.check(#layout.Obstacles >= 8, "too few obstacles: " .. #layout.Obstacles)
		local ids = {}
		local walls, chests = 0, 0
		for _, spec in layout.Obstacles do
			H.check(not ids[spec.Id], "duplicate id " .. spec.Id)
			ids[spec.Id] = true
			local p = spec.LocalCFrame.Position
			H.check(math.abs(p.X) + spec.Size.X * 0.5 <= halfWidth + 0.01, spec.Id .. " outside lane width")
			H.check(p.Z < -100 and p.Z > -layout.Length + 40, spec.Id .. " outside lane length: " .. p.Z)
			H.check(spec.Durability > 0 and spec.Loot >= 1, spec.Id .. " bad durability/loot")
			if spec.Kind == "Wall" then
				walls += 1
				for _, gap in layout.Gaps do
					H.check(not (p.Z <= gap.From and p.Z >= gap.To), spec.Id .. " wall floats over a gap")
				end
			else
				chests += 1
			end
		end
		H.check(walls >= 3 and chests >= 2, string.format("walls=%d chests=%d", walls, chests))
		-- препятствия не пересекаются друг с другом
		for i = 1, #layout.Obstacles do
			local a = layout.Obstacles[i]
			local aMin, aMax = aabb(a.LocalCFrame, a.Size)
			for j = i + 1, #layout.Obstacles do
				local b = layout.Obstacles[j]
				local bMin, bMax = aabb(b.LocalCFrame, b.Size)
				H.check(not overlaps(aMin, aMax, bMin, bMax, 0.05), a.Id .. " overlaps " .. b.Id)
			end
		end
		local gongDiscs = 0
		for _, piece in layout.Pieces do
			if piece.Kind == "GongDisc" then
				gongDiscs += 1
				H.near(piece.LocalCFrame.Position.Z, -layout.Length - 8, 1e-6, "gong z")
			end
		end
		H.check(gongDiscs == 1, "exactly one gong")
		if tier < 2 then
			H.check(#layout.Gaps == 0, "no gaps before Cyber-Slime")
		end
	end)
end
H.test("higher tier walls require more speed and give more loot", function()
	local function stats(tier: number): (number, number)
		local layout = LevelBuilder.GenerateLayout("Meadows", tier)
		for _, spec in layout.Obstacles do
			if spec.Kind == "Chest" then
				return spec.RequiredSpeed, spec.Loot
			end
		end
		error("no chest")
	end
	local speed0, loot0 = stats(0)
	local speed3, loot3 = stats(3)
	H.check(speed3 > speed0 and loot3 > loot0, string.format("speed %g→%g loot %g→%g", speed0, speed3, loot0, loot3))
end)

-- ── LevelBuilder: настоящие Instance (свойства валидирует reflection-база) ──
H.suite("LevelBuilder instances")
for tier = 0, 3 do
	H.test("CreateLane builds a valid lane for tier " .. tier, function()
		local container = roblox.Instance.new("Folder")
		local layout = LevelBuilder.GenerateLayout("Meadows", tier)
		local context = {
			Origin = LevelConfig.SlotOrigin(2),
			Theme = LevelConfig.GetTheme(tier),
			Slot = 2,
			Tier = tier,
			OwnerUserId = 42,
		}
		local handles = LevelBuilder.CreateLane(layout, context, container)
		H.check(handles.Model.Parent == container, "model parented")
		H.check(handles.Gong ~= nil, "gong part exists")
		local gong = handles.Gong :: any
		H.check(gong:HasTag(PhysicsConfig.Tags.Gong) and gong:GetAttribute("GongLaneSlot") == 2, "gong tagged")
		local obstacleCount = 0
		for _, part in handles.ObstacleFolder:GetChildren() do
			obstacleCount += 1
			H.check(part:HasTag(PhysicsConfig.Tags.Smashable), "smashable tag")
			H.check(type(part:GetAttribute("Durability")) == "number", "durability attr")
			H.check(type(part:GetAttribute("ObstacleId")) == "string", "id attr")
		end
		H.check(obstacleCount == #layout.Obstacles, "obstacle count")
		local bouncy, grab = 0, 0
		for _, part in handles.Mutable:GetChildren() do
			if part:HasTag(PhysicsConfig.Tags.Bouncy) then
				bouncy += 1
			end
			if part:HasTag(PhysicsConfig.Tags.GrabPoint) then
				grab += 1
			end
		end
		H.check(bouncy > 0 and grab >= 2, string.format("bouncy=%d grab=%d", bouncy, grab))
		local sign = handles.Mutable:FindFirstChild("GongSign")
		H.check(sign and sign:FindFirstChild("SignGui"), "gong sign gui")
		LevelBuilder.ApplyTheme(handles.StartPad, LevelConfig.GetTheme(tier + 1))
		H.check(handles.StartPad.Color == LevelConfig.GetTheme(tier + 1).Floor.Color, "retheme start pad")
		local start = LevelBuilder.StartCFrame(2)
		H.check((start.Position - LevelConfig.SlotOrigin(2).Position).Magnitude < 30, "start near origin")
	end)
end

-- ── SoundConfig ────────────────────────────────────────────────────────────
local SoundConfig = H.require("ReplicatedStorage.Shared.Config.SoundConfig")
H.suite("SoundConfig")
H.test("every slot: asset id, sane volume / pitch / voices, known group", function()
	local groups = { Sfx = true, Resonance = true, Ui = true }
	local count = 0
	for name, def in SoundConfig.Sounds do
		count += 1
		local id = def.Id
		H.check(string.sub(id, 1, 11) == "rbxasset://" or string.sub(id, 1, 13) == "rbxassetid://", name .. " id " .. id)
		H.check(def.Volume > 0 and def.Volume <= 10, name .. " volume")
		H.check(def.Pitch > 0 and def.Pitch <= 4, name .. " pitch")
		H.check(def.Voices >= 1 and def.Voices <= 16, name .. " voices")
		H.check(groups[def.Group] == true, name .. " group")
	end
	H.check(count >= 15, "slots: " .. count)
	H.check(SoundConfig.Sounds.StretchLoop.Looped and SoundConfig.Sounds.WindLoop.Looped, "loops are looped")
	for _, key in { "Snap", "Bounce", "Smash", "Gong", "WaveSweep", "Creak", "UiClick" } do
		H.check(SoundConfig.Sounds[key] ~= nil and not SoundConfig.Sounds[key].Looped, key .. " one-shot present")
	end
	H.check(SoundConfig.Sounds.Gong.Group == "Resonance" and SoundConfig.Sounds.WaveSweep.Group == "Resonance", "gong & wave go through reverb")
end)
H.test("major pentatonic steps climb by octaves and cap at the top octave", function()
	local expected = { 0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28, 31, 33 }
	for index, semitones in expected do
		H.check(SoundConfig.PentatonicSemitones(index - 1) == semitones, string.format("step %d → %d", index - 1, SoundConfig.PentatonicSemitones(index - 1)))
	end
	for step = 15, 40 do
		local value = SoundConfig.PentatonicSemitones(step)
		H.check(value >= 12 * SoundConfig.PentatonicOctaves and value <= 12 * SoundConfig.PentatonicOctaves + 9, "capped at step " .. step)
	end
	H.near(SoundConfig.SemitoneRatio(12), 2, 1e-12, "octave = x2")
	H.near(SoundConfig.SemitoneRatio(7), 1.498307, 1e-5, "fifth")
end)

-- ── Экономика прокачки ─────────────────────────────────────────────────────
H.suite("Progression economy")
H.test("upgrade cost starts at BaseCost, is an integer and strictly grows", function()
	H.check(StretchPhysics.UpgradeCost(0) == PhysicsConfig.StatUpgrade.BaseCost, "base cost")
	local previous = 0
	for level = 0, PhysicsConfig.StatUpgrade.MaxLevel - 1 do
		local cost = StretchPhysics.UpgradeCost(level)
		H.check(cost == math.floor(cost) and cost > previous, "level " .. level .. " cost " .. cost)
		previous = cost
	end
end)
H.test("each stat level visibly improves its parameter (shop preview is never flat)", function()
	for level = 0, PhysicsConfig.StatUpgrade.MaxLevel - 1 do
		local now = StretchPhysics.Derive({ Elasticity = level, SpringPower = level, SmashMass = level }, "Rubber")
		local nextLevel = StretchPhysics.Derive({ Elasticity = level + 1, SpringPower = level + 1, SmashMass = level + 1 }, "Rubber")
		local improves = nextLevel.MaxStretch > now.MaxStretch or nextLevel.GrabRange > now.GrabRange
		H.check(improves or now.MaxStretch >= PhysicsConfig.MaxStretch.Max, "elasticity flat at " .. level)
		H.check(nextLevel.ImpactMass > now.ImpactMass or now.ImpactMass >= PhysicsConfig.ImpactMass.Max, "mass flat at " .. level)
	end
end)

local ok = H.summary()
process.exit(if ok then 0 else 1)
