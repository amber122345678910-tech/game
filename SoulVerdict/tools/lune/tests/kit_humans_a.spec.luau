--!nocheck
-- Human SOUL kits Patience / Bravery / Integrity: every ability runs through the REAL combat services under Lune
-- (simulated clock, fake CharacterService / Net / workspace with flat ground at y = 0 — the same approach as
-- combat.spec.luau), plus client kit coverage (every Effects phase runs against a recording FxContext stub).
-- Run: lune run tools/lune/run_tests.luau kit_humans_a
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Instance = roblox.Instance
local Color3 = roblox.Color3
local Enum = roblox.Enum

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."

-------------------------------------------------------------------------------------------------
-- Service harness (trimmed copy of combat.spec.luau's)

local function harness(Loader)
	local H = {}
	local clock = 1000
	local timers = {}
	H.sent = {}
	H.models = {}
	H.speeds = {}
	H.round = { Phase = "Round", TeamRevives = 2, FinalPhase = false, Harmony = 1 }

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
	function H.runDue()
		H.advance(0)
	end

	local G = getfenv(Loader.requirePath)
	G.workspace = {
		GetServerTimeNow = function()
			return clock
		end,
		Raycast = function(_, origin, dir)
			local y1 = origin.Y + dir.Y
			if origin.Y >= 0 and y1 <= 0 and dir.Y < 0 then
				local t = origin.Y / -dir.Y
				return { Position = origin + dir * t, Normal = Vector3.yAxis, Distance = dir.Magnitude * t }
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
	function CS.GetPlayer(_m)
		return nil
	end
	function CS.GetModel(_p)
		return nil
	end
	function CS.Kill(m)
		m:SetAttribute("Dead", true)
	end
	function CS.SetDowned(m)
		m:SetAttribute("Downed", true)
	end
	Validation.SetService("CharacterService", CS)
	Validation.SetService("StatsService", { Add = function() end })
	Validation.SetService("RoundService", {
		TriggerFinalPhase = function()
			return true
		end,
	})

	local Net = Loader.require("ReplicatedStorage.Shared.Net")
	local netOriginal = { FireAll = Net.Server.FireAll, Fire = Net.Server.Fire, On = Net.Server.On }
	Net.Server.FireAll = function(name, ...)
		table.insert(H.sent, { name = name, args = table.pack(...) })
	end
	Net.Server.Fire = function(name, player, ...)
		table.insert(H.sent, { name = name, player = player, args = table.pack(...) })
	end
	Net.Server.On = function()
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

	function H.spawn(kitId, team, pos, opts)
		opts = opts or {}
		local kit = H.Kits.Get(kitId)
		local m = Instance.new("Model")
		m.Name = kitId .. "_" .. tostring(#H.models + 1)
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
		local serverKit = H.S.AbilityService.GetServerKit(kitId)
		if serverKit and serverKit.OnSpawn and not opts.noSpawnHook then
			serverKit.OnSpawn(m, nil)
		end
		return m
	end

	function H.hp(m)
		return m:FindFirstChildOfClass("Humanoid").Health
	end
	-- AbilityFx packets of one phase (optionally of one ability) sent after index `from` (a #H.sent mark)
	function H.fx(phase, ability, from)
		local out = {}
		for i = (from or 0) + 1, #H.sent do
			local s = H.sent[i]
			if s.name == "AbilityFx" then
				local p = s.args[1]
				if p.phase == phase and (ability == nil or p.ability == ability) then
					table.insert(out, p)
				end
			end
		end
		return out
	end
	function H.lastHazard()
		for i = #H.sent, 1, -1 do
			if H.sent[i].name == "Hazard" then
				return H.sent[i].args[1]
			end
		end
		return nil
	end
	-- steps hazards (and statuses) for `seconds` of simulated time
	function H.simulate(seconds, dt)
		local step = dt or 0.05
		local t = 0
		while t < seconds - 1e-9 do
			H.advance(step)
			H.S.HazardService._Step(step)
			H.S.StatusService._Step(step)
			t += step
		end
	end
	-- a monster that can be hit: no dodges unless asked
	function H.monster(pos, dodges)
		local m = H.spawn("ClassicSans", "Monster", pos, { dodges = dodges or 0, maxDodges = math.max(3, dodges or 0) })
		return m
	end
	function H.cleanup()
		H.S.HazardService.Clear()
		Validation.SetScheduler(nil)
		for _, name in { "CharacterService", "StatsService", "RoundService" } do
			Validation.SetService(name, nil)
		end
		for k, fn in netOriginal do
			Net.Server[k] = fn
		end
		G.workspace = nil
		G.RaycastParams = nil
		Loader.reset() -- later specs get fresh modules (no kit hooks / fakes left behind)
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

local FORWARD = Vector3.new(0, 0, -1)

local tests = {}

-------------------------------------------------------------------------------------------------
-- Patience

tests.patience_knife_stealth_ambush = function(T, Loader)
	withHarness(Loader, function(H)
		local AS, SS = H.S.AbilityService, H.S.StatusService
		local pat = H.spawn("Patience", "Humans", Vector3.zero)
		local mon = H.monster(Vector3.new(0, 0, -4), 3)
		-- plain stab: dodgeable -> MISS, one dodge consumed
		T.ok(AS.CastAs(pat, "ToyKnife", { aim = Vector3.new(0, 3, -4), dir = FORWARD }), "ToyKnife cast")
		T.eq(mon:GetAttribute("Dodges"), 2, "plain stab was lazily dodged")
		T.eq(#H.fx("Strike", "ToyKnife"), 1, "Strike fx")
		-- stealth
		T.ok(AS.CastAs(pat, "Patience", {}), "Patience cast")
		T.ok(SS.Has(pat, "Invisible") and pat:GetAttribute("Invisible") == true, "invisible")
		T.ok(SS.Has(pat, "StealthStrike"), "stealth strike armed")
		local fade = H.fx("Fade", "Patience")[1]
		T.ok(fade and fade.data.duration == 6, "Fade fx with duration")
		-- blocking / waiting keeps the stealth
		H.simulate(1)
		T.ok(SS.Has(pat, "Invisible"), "still invisible after 1 s")
		-- attacking breaks it, and that attack carries the bonus: undodgeable x1.6
		local hp = H.hp(mon)
		local mark = #H.sent
		AS.ResetCooldowns(pat)
		T.ok(AS.CastAs(pat, "ToyKnife", { aim = Vector3.new(0, 3, -4), dir = FORWARD }), "ambush stab")
		T.ok(not SS.Has(pat, "Invisible"), "stealth broken by the attack")
		T.eq(#H.fx("Reveal", "Patience", mark), 1, "Reveal fx")
		T.eq(mon:GetAttribute("Dodges"), 2, "ambush cannot be dodged")
		T.near(hp - H.hp(mon), 6 * 1.6, 1e-3, "+60 % from stealth")
		T.ok(not SS.Has(pat, "StealthStrike"), "stealth strike consumed")
		H.runDue()
		local ambush = H.fx("Ambush", "Patience", mark)[1]
		T.ok(ambush and ambush.data.target == mon, "Ambush fx names the target")
		-- next stab is a normal one again
		hp = H.hp(mon)
		AS.ResetCooldowns(pat)
		AS.CastAs(pat, "ToyKnife", { aim = Vector3.new(0, 3, -4), dir = FORWARD })
		T.eq(mon:GetAttribute("Dodges"), 1, "normal stab dodgeable again")
		-- natural expiry: StealthStrike ends with the stealth (+ tail)
		AS.ResetCooldowns(pat)
		AS.CastAs(pat, "Patience", {})
		H.simulate(6.5, 0.1)
		T.ok(not SS.Has(pat, "Invisible") and not SS.Has(pat, "StealthStrike"), "stealth expired")
		-- downed: stealth removed
		AS.ResetCooldowns(pat)
		AS.CastAs(pat, "Patience", {})
		pat:SetAttribute("Downed", true)
		SS._Step(0.1)
		T.ok(not SS.Has(pat, "Invisible"), "a downed human is never hidden")
	end)
end

tests.patience_ribbon_snare = function(T, Loader)
	withHarness(Loader, function(H)
		local AS, SS = H.S.AbilityService, H.S.StatusService
		local pat = H.spawn("Patience", "Humans", Vector3.zero)
		local mon = H.monster(Vector3.new(0, 0, -15), 3)
		local hp = H.hp(mon)
		T.ok(AS.CastAs(pat, "RibbonSnare", { aim = Vector3.new(0, 4, -15), dir = FORWARD }), "RibbonSnare cast")
		local hz = H.lastHazard()
		T.ok(hz and hz.type == "Projectile" and hz.params.visual == "PatienceRibbon", "ribbon projectile")
		T.eq(hz.params.speed, 80, "Speed from data")
		T.eq(#H.fx("Throw", "RibbonSnare"), 1, "Throw fx")
		H.simulate(0.6)
		T.near(hp - H.hp(mon), 6, 1e-6, "ribbon damage (undodgeable)")
		T.ok(SS.Has(mon, "Slowed"), "slowed")
		local _, data = SS.Get(mon, "Slowed")
		T.eq(data.mult, 0.6, "slow mult 0.6 (40 %)")
		T.eq(mon:GetAttribute("Dodges"), 2, "one dodge drained (and none spent on the hit)")
		local snare = H.fx("Snare", "RibbonSnare")[1]
		T.ok(snare and snare.data.target == mon and snare.data.time == 2.5, "Snare fx")
		T.eq(H.S.HazardService.Count(), 0, "projectile ended on the hit")
	end)
end

tests.patience_waiting_game_and_calm = function(T, Loader)
	withHarness(Loader, function(H)
		local AS, SS = H.S.AbilityService, H.S.StatusService
		local pat = H.spawn("Patience", "Humans", Vector3.zero, { ult = 100 })
		local mon = H.monster(Vector3.new(0, 0, -20), 3)
		AS.SetCooldown(mon, "BoneZone", 4)
		local before = AS.GetCooldowns(mon).BoneZone
		T.ok(AS.CastAs(pat, "WaitingGame", { aim = Vector3.new(0, 0, -20) }), "WaitingGame cast")
		T.eq(pat:GetAttribute("Ult"), 0, "ult consumed")
		local hz = H.lastHazard()
		T.ok(hz and hz.type == "Zone" and hz.params.visual == "PatienceClock", "clock zone")
		T.eq(hz.params.radius, 16, "Radius from data")
		T.eq(hz.params.effect, "Slow")
		T.ok(math.abs(hz.params.center.Z + 20) < 1e-3 and math.abs(hz.params.center.Y) < 1e-3, "on the ground at the aim")
		T.ok(pat:GetAttribute("UltActiveUntil") > H.now() + 5, "ult heart attribute")
		T.eq(#H.fx("Field", "WaitingGame"), 1, "Field fx")
		H.simulate(2)
		T.ok(SS.Has(mon, "Slowed"), "monster slowed inside")
		local _, data = SS.Get(mon, "Slowed")
		T.eq(data.mult, 0.5, "50 % slow")
		local after = AS.GetCooldowns(mon).BoneZone
		T.ok(after - before > 0.7, "cooldowns tick at half speed inside the field (+" .. (after - before) .. " s)")
		-- Calm: standing still heals 3 HP/s
		local hum = pat:FindFirstChildOfClass("Humanoid")
		hum.Health = 50
		H.speeds[pat] = 0
		H.simulate(2, 0.1)
		T.ok(pat:GetAttribute("CalmActive") == true, "CalmActive")
		T.ok(H.health == nil and hum.Health >= 53 - 1e-6 and hum.Health <= 56.5, "healed while still: " .. hum.Health)
		local healed = hum.Health
		H.speeds[pat] = 12
		H.simulate(1, 0.1)
		T.ok(pat:GetAttribute("CalmActive") == false, "moving stops Calm")
		T.ok(hum.Health - healed < 3, "no heal while moving")
	end)
end

-------------------------------------------------------------------------------------------------
-- Bravery

tests.bravery_passive_punches_charge = function(T, Loader)
	withHarness(Loader, function(H)
		local AS, SS = H.S.AbilityService, H.S.StatusService
		local brave = H.spawn("Bravery", "Humans", Vector3.zero)
		T.eq(brave:GetAttribute("MaxGuard"), 150, "Unbreakable: +50 % guard (not stacked twice)")
		T.eq(brave:GetAttribute("Guard"), 150, "guard full")
		T.eq(brave:GetAttribute("GuardRegenMult"), 1.6, "faster guard regen")
		local mon = H.monster(Vector3.new(0, 0, -3.5), 0)
		local hp = H.hp(mon)
		for i = 1, 4 do
			AS.ResetCooldowns(brave)
			T.ok(AS.CastAs(brave, "ToughPunches", { aim = Vector3.new(0, 3, -3.5), dir = FORWARD }), "punch " .. i)
		end
		T.near(hp - H.hp(mon), 8 + 8 + 9 + 14, 1e-6, "four punches")
		T.ok(SS.Has(mon, "Stunned"), "the last punch staggers")
		SS.Remove(mon, "Stunned")
		-- Guts Charge: undodgeable shoulder check, stuns, stops on contact
		local far = H.monster(Vector3.new(0, 0, -14), 3)
		hp = H.hp(far)
		T.ok(AS.CastAs(brave, "GutsCharge", { aim = Vector3.new(0, 3, -22), dir = FORWARD }), "GutsCharge")
		local charge = H.fx("Charge", "GutsCharge")[1]
		T.ok(charge and charge.data.time > 0.2, "Charge fx")
		-- the near monster (3.5 studs ahead) is met first
		local impact = H.fx("Impact", "GutsCharge")[1]
		T.ok(impact and impact.data.target == mon and impact.data.landed == true, "Impact fx on the first enemy met")
		T.ok(SS.Has(mon, "Stunned"), "charge stun")
		T.eq(H.hp(far), hp, "the charge stopped on the first enemy")
		-- a dodge-ready monster cannot side-step the charge
		mon:SetAttribute("Dead", true)
		AS.ResetCooldowns(brave)
		AS.CastAs(brave, "GutsCharge", { aim = Vector3.new(0, 3, -22), dir = FORWARD })
		T.eq(far:GetAttribute("Dodges"), 3, "no dodge consumed")
		T.near(hp - H.hp(far), 18, 1e-6, "charge damage")
		local _, st = SS.Get(far, "Stunned")
		T.ok(SS.Has(far, "Stunned"), "stunned monsters cannot dodge")
		local _ = st
		-- miss: skid
		far:SetAttribute("Dead", true)
		AS.ResetCooldowns(brave)
		local mark = #H.sent
		AS.CastAs(brave, "GutsCharge", { aim = Vector3.new(0, 3, -22), dir = FORWARD })
		T.eq(#H.fx("Skid", "GutsCharge", mark), 1, "Skid fx when nothing is hit")
	end)
end

tests.bravery_stand_and_ult = function(T, Loader)
	withHarness(Loader, function(H)
		local AS, SS, DS = H.S.AbilityService, H.S.StatusService, H.S.DamageService
		local brave = H.spawn("Bravery", "Humans", Vector3.zero, { ult = 100 })
		local near = H.spawn("Determination", "Humans", Vector3.new(4, 0, 0))
		local tough = H.spawn("Determination", "Humans", Vector3.new(-4, 0, 0))
		local farAlly = H.spawn("Determination", "Humans", Vector3.new(40, 0, 0))
		local mon = H.monster(Vector3.new(0, 0, -6), 3)
		SS.Apply(tough, "DamageDown", 10, { mult = 0.3 })
		T.ok(AS.CastAs(brave, "BraveStand", {}), "BraveStand")
		local _, d1 = SS.Get(brave, "DamageDown")
		local _, d2 = SS.Get(near, "DamageDown")
		local _, d3 = SS.Get(tough, "DamageDown")
		T.near(d1.mult, 0.6, 1e-6, "self -40 %")
		T.near(d2.mult, 0.6, 1e-6, "ally in radius -40 %")
		T.near(d3.mult, 0.3, 1e-6, "a stronger reduction is kept")
		T.ok(not SS.Has(farAlly, "DamageDown"), "far ally untouched")
		local stand = H.fx("Stand", "BraveStand")[1]
		T.ok(stand and #stand.data.allies == 3 and stand.data.radius == 10, "Stand fx lists the shielded")
		local r = DS.Apply({ Attacker = mon, Target = near, Amount = 10, Kind = "Melee" })
		T.near(r.Applied, 6, 1e-6, "damage reduced")
		-- Burning Courage: leap & slam
		SS.Apply(near, "DamageUp", 10, { mult = 1.3 })
		local hp = H.hp(mon)
		T.ok(AS.CastAs(brave, "BurningCourage", { aim = Vector3.new(0, 0, -6) }), "BurningCourage")
		local leap = H.fx("Leap", "BurningCourage")[1]
		T.ok(leap and math.abs(leap.data.to.Z + 6) < 0.1, "Leap fx aims at the landing point")
		local slam = H.fx("Slam", "BurningCourage")[1]
		T.ok(slam and slam.data.radius == 14, "Slam fx")
		T.eq(mon:GetAttribute("Dodges"), 1, "2 dodges drained")
		T.near(hp - H.hp(mon), 30, 1e-6, "slam damage (ultimate: undodgeable)")
		T.ok(SS.Has(mon, "Stunned"), "slam stun")
		local _, b1 = SS.Get(brave, "DamageUp")
		local _, b2 = SS.Get(tough, "DamageUp")
		local _, b3 = SS.Get(near, "DamageUp")
		T.near(b1.mult, 1.15, 1e-6, "self +15 %")
		T.near(b2.mult, 1.15, 1e-6, "ally +15 %")
		T.near(b3.mult, 1.3, 1e-6, "a stronger damage buff is kept")
		T.ok(not SS.Has(farAlly, "DamageUp"), "far ally not rallied")
		T.ok(brave:GetAttribute("UltActiveUntil") > H.now() + 5, "ult heart attribute")
		-- robust to being stunned mid-leap: no slam
		brave:SetAttribute("Ult", 100)
		SS.Remove(mon, "Stunned")
		local hp2 = H.hp(mon)
		local mark = #H.sent
		H.Validation.Delay(0.3, function()
			SS.Apply(brave, "Stunned", 1)
		end)
		AS.ResetCooldowns(brave)
		T.ok(AS.CastAs(brave, "BurningCourage", { aim = Vector3.new(0, 0, -6) }), "recast")
		T.eq(H.hp(mon), hp2, "interrupted ult does nothing")
		T.eq(#H.fx("Slam", "BurningCourage", mark), 0, "no Slam fx")
	end)
end

-------------------------------------------------------------------------------------------------
-- Integrity

tests.integrity_kicks_and_jete = function(T, Loader)
	withHarness(Loader, function(H)
		local AS, SS = H.S.AbilityService, H.S.StatusService
		local dancer = H.spawn("Integrity", "Humans", Vector3.zero)
		local mon = H.monster(Vector3.new(0, 0, -4), 0)
		local hp = H.hp(mon)
		for i = 1, 3 do
			AS.ResetCooldowns(dancer)
			T.ok(AS.CastAs(dancer, "BalletKicks", { aim = Vector3.new(0, 3, -4), dir = FORWARD }), "kick " .. i)
		end
		T.near(hp - H.hp(mon), 7 + 7 + 11, 1e-6, "three kicks")
		hp = H.hp(mon)
		T.ok(AS.CastAs(dancer, "GrandJete", { aim = Vector3.new(0, 0, -4) }), "GrandJete")
		local leap = H.fx("Leap", "GrandJete")[1]
		T.ok(leap and leap.data.time == 0.6, "Leap fx with AirTime")
		local land = H.fx("Land", "GrandJete")[1]
		T.ok(land and land.data.radius == 7, "Land fx")
		T.near(hp - H.hp(mon), 14, 1e-6, "landing shockwave damage")
		-- the leap is clamped to Distance
		AS.ResetCooldowns(dancer)
		AS.CastAs(dancer, "GrandJete", { aim = Vector3.new(0, 0, -80) })
		local leap2 = H.fx("Leap", "GrandJete")[2]
		T.ok(leap2 and leap2.data.to.Z >= -30.5, "clamped to 30 studs")
		T.ok(not SS.Has(dancer, "Stunned"), "fine")
	end)
end

tests.integrity_pirouette = function(T, Loader)
	withHarness(Loader, function(H)
		local AS, HS, DS = H.S.AbilityService, H.S.HazardService, H.S.DamageService
		local dancer = H.spawn("Integrity", "Humans", Vector3.zero)
		local mon = H.monster(Vector3.new(0, 0, -3), 0)
		local hp, dhp = H.hp(mon), H.hp(dancer)
		-- an enemy bone flying at the dancer
		local bone = HS.Spawn(mon, "Monster", "BoneProjectile", {
			origin = H.HazardDefs.LookAlong(Vector3.new(20, 3, 0), Vector3.new(-1, 0, 0)),
			speed = 60,
			delay = 0,
			damage = 10,
		})
		T.ok(bone > 0, "bone spawned")
		local results = {}
		H.Validation.Delay(0.4, function()
			results.melee = DS.Apply({ Attacker = mon, Target = dancer, Amount = 20, Kind = "Melee" })
			results.area = DS.Apply({ Attacker = mon, Target = dancer, Amount = 5, Kind = "Area" })
		end)
		T.ok(AS.CastAs(dancer, "Pirouette", {}), "Pirouette")
		T.eq(results.melee.Reason, "Cancelled", "melee negated while spinning")
		T.near(dhp - H.hp(dancer), 5, 1e-6, "area damage still hurts")
		T.eq(HS.Get(bone), nil, "the bone was destroyed")
		T.ok(#H.fx("Deflect", "Pirouette") >= 1, "Deflect fx")
		T.eq(#H.fx("Tick", "Pirouette"), 4, "4 ticks")
		T.near(hp - H.hp(mon), 4 * 5, 1e-6, "tick damage")
		local spin = H.fx("Spin", "Pirouette")[1]
		T.ok(spin and spin.data.duration == 1.2 and spin.data.radius == 6, "Spin fx")
		local kit = AS.GetServerKit("Integrity")
		T.ok(not kit.IsSpinning(dancer), "spin over")
		local r = DS.Apply({ Attacker = mon, Target = dancer, Amount = 10, Kind = "Melee" })
		T.ok(r.Reason == nil and r.Applied > 0, "melee hurts again after the spin")
	end)
end

tests.integrity_encore = function(T, Loader)
	withHarness(Loader, function(H)
		local AS, SS = H.S.AbilityService, H.S.StatusService
		local dancer = H.spawn("Integrity", "Humans", Vector3.zero, { ult = 100 })
		local mon = H.monster(Vector3.new(0, 0, -8), 3)
		local hp = H.hp(mon)
		T.ok(AS.CastAs(dancer, "Encore", { aim = Vector3.new(0, 3, -20), dir = FORWARD }), "Encore")
		T.eq(#H.fx("Dash", "Encore"), 3, "three dashes")
		T.eq(mon:GetAttribute("Dodges"), 0, "each pass drained a dodge")
		T.ok(SS.Has(mon, "Exhausted"), "drained to exhaustion")
		local bow = H.fx("Bow", "Encore")[1]
		T.ok(bow and bow.data.radius == 9, "Bow fx")
		T.ok(hp - H.hp(mon) >= 3 * 12 + 20 - 1e-6, "dash + bow damage: " .. (hp - H.hp(mon)))
		T.ok(dancer:GetAttribute("UltActiveUntil") > 0, "ult heart attribute")
		-- death mid-ult stops the sequence
		dancer:SetAttribute("Ult", 100)
		local hum = dancer:FindFirstChildOfClass("Humanoid")
		local mark = #H.sent
		H.Validation.Delay(0.1, function()
			hum.Health = 0
		end)
		AS.ResetCooldowns(dancer)
		T.ok(AS.CastAs(dancer, "Encore", { aim = Vector3.new(0, 3, -20), dir = FORWARD }), "recast")
		T.eq(#H.fx("Bow", "Encore", mark), 0, "no bow after dying")
	end)
end

-------------------------------------------------------------------------------------------------
-- Client kits: every Effects phase / Predict / Indicator / OnCharacter / registered visual runs against a
-- recording FxContext stub. Animate steps really run (a = 0, 0.5, 1); parts, lights, emitters and SOUL models
-- are real Lune Instances, so wrong property names fail the test.

local function universal()
	local mt = {}
	local obj = setmetatable({}, mt)
	mt.__index = function(_, _k)
		return function()
			return universal()
		end
	end
	mt.__call = function()
		return universal()
	end
	return obj
end

local function fakeSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end

local function clientEnv(Loader)
	local E = { calls = {}, captured = {}, clock = 500 }
	Loader.reset()
	local HV = Loader.require(CLIENT .. "Controllers.HazardVisuals")
	local register = HV.RegisterVisual
	HV.RegisterVisual = function(name, builder)
		E.captured[name] = builder
		return register(name, builder)
	end
	local restores = {}
	local RealLib = Loader.require(CLIENT .. "VFX.Lib")
	local HazardDefs = Loader.require("ReplicatedStorage.Shared.Combat.HazardDefs")
	-- offline Workspace: BulkMoveTo / Raycast are no-ops
	-- (the loader's service mocks are shared by every spec: everything set here is undone by E.restore)
	local gameMock = getfenv(RealLib.Color).game
	local W = gameMock:GetService("Workspace")
	local PlayersSvc = gameMock:GetService("Players")
	local function mock(tbl, key, value)
		local before = rawget(tbl, key)
		rawset(tbl, key, value)
		table.insert(restores, function()
			rawset(tbl, key, before)
		end)
	end
	mock(W, "BulkMoveTo", function() end)
	mock(W, "Raycast", function()
		return nil
	end)
	mock(PlayersSvc, "LocalPlayer", { Character = nil, Name = "Viewer" })
	table.insert(restores, function()
		HV.RegisterVisual = register
	end)
	function E.restore()
		for i = #restores, 1, -1 do
			restores[i]()
		end
		table.clear(restores)
		Loader.reset()
	end
	E.folder = Instance.new("Folder")
	local function record(name)
		E.calls[name] = (E.calls[name] or 0) + 1
	end
	local overrides = {
		Colors = RealLib.Colors,
		Color = RealLib.Color,
		LerpColor = RealLib.LerpColor,
		LookAlong = HazardDefs.LookAlong,
		AxisFrame = HazardDefs.AxisFrame,
		ParticleScale = function()
			return 1
		end,
		ReducedMotion = function()
			return false
		end,
		Now = function()
			return E.clock
		end,
		Folder = function()
			return E.folder
		end,
		Characters = function()
			return E.characters or {}
		end,
		Part = function(shape, size, cf, color, material, transparency)
			record("Part")
			local p = Instance.new("Part")
			if shape == "Ball" then
				p.Shape = Enum.PartType.Ball
			elseif shape == "Cylinder" then
				p.Shape = Enum.PartType.Cylinder
			end
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = material or Enum.Material.Neon
			p.Transparency = transparency or 0
			return p
		end,
		Light = function(parent, color, brightness, range)
			record("Light")
			local l = Instance.new("PointLight")
			l.Color = color
			l.Brightness = brightness
			l.Range = range
			if typeof(parent) == "Instance" then
				l.Parent = parent
			end
			return l
		end,
		Emitter = function(kind, parent, props)
			record("Emitter:" .. kind)
			local e = Instance.new("ParticleEmitter")
			for k, v in props or {} do
				if k ~= "Color" then
					e[k] = v
				end
			end
			if typeof(parent) == "Instance" then
				e.Parent = parent
			end
			return e
		end,
		Soul = function(color, _size)
			record("Soul")
			local m = Instance.new("Model")
			local core = Instance.new("Part")
			core.Transparency = 1
			core.Parent = m
			local lobe = Instance.new("Part")
			lobe.Color = color
			lobe.Parent = m
			m.PrimaryPart = core
			-- Model:PivotTo is missing offline
			return setmetatable({ PivotTo = function() end }, {
				__index = function(_, k)
					local v = m[k]
					if type(v) == "function" then
						return function(_self, ...)
							return v(m, ...)
						end
					end
					return v
				end,
			})
		end,
		Animate = function(duration, step, done)
			record("Animate")
			assert(type(duration) == "number" and duration >= 0, "Animate duration")
			for _, a in { 0, 0.5, 1 } do
				if step(a, 1 / 60, a * math.min(duration, 2)) == true then
					break
				end
			end
			if done then
				done()
			end
			return { Cancel = function() end }
		end,
		Text = function(_pos, text, _color, _opts)
			record("Text")
			assert(type(text) == "string" and text ~= "" and not string.find(text, "^fx%."), "localized text: " .. tostring(text))
		end,
	}
	E.VFX = setmetatable({}, {
		__index = function(_, k)
			local o = overrides[k]
			if o ~= nil then
				return o
			end
			return function()
				record(k)
				return universal()
			end
		end,
	})
	-- a real model with the parts the kits look up
	function E.model(name, team, pos)
		local m = Instance.new("Model")
		m.Name = name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(pos or Vector3.zero)
		root.Parent = m
		for _, n in { "UpperTorso", "RightHand", "LeftHand", "RightFoot", "LeftFoot", "Head" } do
			local p = Instance.new("Part")
			p.Name = n
			p.CFrame = CFrame.new((pos or Vector3.zero) + Vector3.new(0, 1, 0))
			p.LocalTransparencyModifier = 0 -- offline parts have no default for this property
			p.Parent = m
		end
		local d = Instance.new("Decal")
		d.LocalTransparencyModifier = 0
		d.Parent = m.Head
		m:SetAttribute("Team", team)
		m.Parent = E.folder
		return m
	end
	-- proxy that adds GetAttributeChangedSignal (missing offline) to a real model
	function E.proxy(model)
		return setmetatable({
			GetAttributeChangedSignal = function()
				return fakeSignal()
			end,
		}, {
			__index = function(_, k)
				local v = model[k]
				if type(v) == "function" then
					return function(_self, ...)
						return v(model, ...)
					end
				end
				return v
			end,
		})
	end
	function E.fx(character, opts)
		opts = opts or {}
		local function rootOf(m)
			if m == nil then
				return nil
			end
			local r = m:FindFirstChild("HumanoidRootPart")
			if r == nil then
				return nil
			end
			-- offline parts cannot report velocity: a table stand-in with the fields kits read
			return { Position = r.CFrame.Position, CFrame = r.CFrame, AssemblyLinearVelocity = Vector3.new(30, 0, 0), Size = r.Size }
		end
		local noop = function() end
		return {
			Character = character,
			IsLocal = opts.isLocal == true,
			Predicted = opts.predicted == true,
			State = {},
			Trove = {
				Add = noop,
				Connect = function(_, signal, _fn)
					assert(signal ~= nil, "Trove:Connect needs a signal")
				end,
			},
			Now = function()
				return E.clock
			end,
			Anim = universal(),
			VFX = E.VFX,
			Screen = universal(),
			Numbers = universal(),
			Hazards = universal(),
			Shake = noop,
			ShakeAt = noop,
			Kick = noop,
			Flash = noop,
			Sound = noop,
			Debris = noop,
			Delay = function(_s, fn)
				fn()
			end,
			Attachment = function(_m, name)
				return { WorldPosition = Vector3.new(0, 1.5, 0), Name = name, CFrame = CFrame.new() }
			end,
			Part = function(m, name)
				local p = m and m:FindFirstChild(name) or nil
				-- offline parts cannot report Position: stand-in with the fields kits read
				return p and { Position = p.CFrame.Position, CFrame = p.CFrame, Size = p.Size, Name = p.Name } or nil
			end,
			Root = rootOf,
			Chest = function(m)
				local r = rootOf(m)
				return r and r.Position + Vector3.new(0, 1, 0) or nil
			end,
			EyeGlow = noop,
			Color = E.VFX.Color,
			KitColor = function()
				return nil
			end,
			LocalCharacter = function()
				return opts.localChar
			end,
			IsEnemy = function()
				return opts.enemyView == true
			end,
			HitStop = noop,
			Highlight = noop,
			Combat = function()
				return { ComboIndex = function()
					return 2
				end }
			end,
		}
	end
	return E
end

-- Runs every listed phase of every ability (as caster / observer, predicted or not), Predict, Indicator,
-- OnCharacter and the kit's registered hazard visuals.
local exerciseBody

local function exerciseClientKit(T, Loader, kitId, phases, visuals)
	local E = clientEnv(Loader)
	local ok, err = pcall(exerciseBody, E, T, Loader, kitId, phases, visuals)
	E.restore()
	if not ok then
		error(err, 0)
	end
	return E
end

function exerciseBody(E, T, Loader, kitId, phases, visuals)
	local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
	local client = Loader.require(CLIENT .. "Kits." .. kitId)
	local caster = E.model(kitId, "Humans", Vector3.zero)
	local monster = E.model("Sans", "Monster", Vector3.new(0, 0, -6))
	local ally = E.model("Ally", "Humans", Vector3.new(4, 0, 0))
	E.characters = { caster, monster, ally }
	T.ok(type(client.OnCharacter) == "function", kitId .. " OnCharacter")
	for _, ability in Kits.Get(kitId).Abilities do
		local fn = client.Effects[ability.Id]
		T.ok(type(fn) == "function", kitId .. " has Effects." .. ability.Id)
		local list = { { phase = "Start", data = { combo = 3 } } }
		for _, extra in phases[ability.Id] or {} do
			table.insert(list, extra)
		end
		for _, view in { { isLocal = true }, { isLocal = false, predicted = false, enemyView = true } } do
			for _, ph in list do
				local data = {}
				for k, v in ph.data or {} do
					data[k] = v
				end
				-- placeholders resolved to this run's models
				for k, v in data do
					if v == "$monster" then
						data[k] = monster
					elseif v == "$allies" then
						data[k] = { caster, ally }
					end
				end
				local fx = E.fx(caster, { isLocal = view.isLocal, predicted = view.predicted, enemyView = view.enemyView })
				local packet = {
					caster = caster,
					kit = kitId,
					ability = ability.Id,
					phase = ph.phase,
					castId = 1,
					t0 = E.clock,
					aim = Vector3.new(0, 0, -10),
					dir = Vector3.new(0, 0, -1),
					data = data,
				}
				T.noerror(function()
					fn(fx, packet)
				end, ("%s.Effects.%s(%s)"):format(kitId, ability.Id, ph.phase))
			end
		end
		if client.Predict and client.Predict[ability.Id] then
			T.noerror(function()
				client.Predict[ability.Id](E.fx(caster, { isLocal = true }), { aim = Vector3.new(0, 0, -10), castId = 2 })
			end, kitId .. ".Predict." .. ability.Id)
		end
		local aimed = ability.Aim == "Ground" or ability.Aim == "Target" or type(ability.Hold) == "table"
		if aimed then
			T.ok(client.Indicator and type(client.Indicator[ability.Id]) == "function", kitId .. " Indicator." .. ability.Id)
		end
		if client.Indicator and client.Indicator[ability.Id] then
			T.noerror(function()
				local ind = client.Indicator[ability.Id](E.fx(caster, { isLocal = true }))
				assert(ind and type(ind.Update) == "function" and type(ind.Destroy) == "function", "indicator handle")
				ind.Update(ind, Vector3.new(0, 0, -12), 0.5, nil)
				ind.Update(ind, Vector3.new(3, 0, -20), 1, nil)
				ind.Destroy(ind)
			end, kitId .. ".Indicator." .. ability.Id)
		end
	end
	-- passives
	caster:SetAttribute("UltActiveUntil", E.clock + 5)
	caster:SetAttribute("Invisible", true)
	caster:SetAttribute("CalmActive", true)
	caster:SetAttribute("Blocking", true)
	for _, view in { { enemyView = true }, { enemyView = false } } do
		local proxy = E.proxy(caster)
		T.noerror(function()
			client.OnCharacter(E.fx(proxy, { enemyView = view.enemyView }), proxy)
		end, kitId .. ".OnCharacter")
	end
	if client.OnDamageFx then
		T.noerror(function()
			client.OnDamageFx(E.fx(caster), { target = caster, attacker = monster, negated = "Pirouette", pos = Vector3.new(0, 3, 0), kind = "Melee", amount = 0 })
		end, kitId .. ".OnDamageFx")
	end
	for _, spec in visuals or {} do
		local builder = E.captured[spec.name]
		T.ok(type(builder) == "function", "visual registered: " .. spec.name)
		if builder then
			T.noerror(function()
				local ctx = {
					Packet = { id = 1, type = spec.kind, t0 = E.clock, owner = caster, team = "Humans", params = spec.params },
					Params = spec.params,
					Type = spec.kind,
					Kind = spec.kind,
					Color = Color3.fromRGB(66, 252, 255),
					Rule = "Cyan",
					Style = "Classic",
					Size = spec.size,
					Lib = E.VFX,
				}
				local v = builder(ctx)
				for _, t in { 0, 0.3, 1, 3, 6.4, 7 } do
					v.Update(v, CFrame.new(0, 0, -5), t, 1 / 60)
				end
				if v.Impact then
					v.Impact(v, Vector3.new(0, 3, -5))
				end
				v.Destroy(v)
			end, "visual " .. spec.name)
		end
	end
end

tests.patience_client = function(T, Loader)
	local E = exerciseClientKit(T, Loader, "Patience", {
		ToyKnife = { { phase = "Strike", data = { combo = 3, last = true, hits = 1 } } },
		RibbonSnare = { { phase = "Throw", data = { id = 3 } }, { phase = "Snare", data = { target = "$monster", time = 2.5 } } },
		Patience = {
			{ phase = "Fade", data = { duration = 6 } },
			{ phase = "Reveal", data = {} },
			{ phase = "Ambush", data = { target = "$monster", pos = Vector3.new(0, 3, -6), amount = 9.6 } },
		},
		WaitingGame = { { phase = "Field", data = { center = Vector3.new(0, 0, -10), radius = 16, duration = 6, delay = 0.25, id = 4 } } },
	}, {
		{ name = "PatienceRibbon", kind = "Projectile", size = 0.9, params = { speed = 80, radius = 0.9 } },
		{ name = "PatienceClock", kind = "Zone", size = 16, params = { center = Vector3.new(0, 0, -5), radius = 16, delay = 0.25, duration = 6, linger = 0.6 } },
	})
	T.ok((E.calls.Animate or 0) > 5, "animations ran")
	local P = Loader.require(CLIENT .. "Kits.Patience")
	T.eq(P.StealthAlpha(false, true), 1, "enemies see nothing")
	T.ok(P.StealthAlpha(true, false) < 0.9 and P.StealthAlpha(false, false) < 0.9, "self / allies see a ghost")
end

tests.bravery_client = function(T, Loader)
	local E = exerciseClientKit(T, Loader, "Bravery", {
		ToughPunches = { { phase = "Strike", data = { combo = 4, last = true, hits = 1 } } },
		GutsCharge = {
			{ phase = "Charge", data = { from = Vector3.new(0, 3, 0), to = Vector3.new(0, 3, -22), time = 0.35 } },
			{ phase = "Impact", data = { target = "$monster", pos = Vector3.new(0, 3, -6), landed = true } },
			{ phase = "Skid", data = { pos = Vector3.new(0, 3, -22) } },
		},
		BraveStand = { { phase = "Stand", data = { duration = 3, radius = 10, allies = "$allies" } } },
		BurningCourage = {
			{ phase = "Leap", data = { from = Vector3.new(0, 3, 0), to = Vector3.new(0, 0, -20), time = 0.5, radius = 14 } },
			{ phase = "Slam", data = { center = Vector3.new(0, 0, -20), radius = 14, allies = "$allies", buffTime = 6 } },
		},
	})
	T.ok((E.calls.GroundCircle or 0) > 0, "telegraphs drawn")
end

tests.integrity_client = function(T, Loader)
	exerciseClientKit(T, Loader, "Integrity", {
		BalletKicks = { { phase = "Strike", data = { combo = 3, last = true, hits = 1 } } },
		GrandJete = {
			{ phase = "Leap", data = { from = Vector3.new(0, 3, 0), to = Vector3.new(0, 0, -25), time = 0.6, radius = 7 } },
			{ phase = "Land", data = { center = Vector3.new(0, 0, -25), radius = 7 } },
		},
		Pirouette = {
			{ phase = "Spin", data = { duration = 1.2, radius = 6, ticks = 4 } },
			{ phase = "Tick", data = { index = 1, hits = 1 } },
			{ phase = "Deflect", data = { pos = Vector3.new(2, 3, 0) } },
		},
		Encore = {
			{ phase = "Dash", data = { from = Vector3.new(0, 3, 0), to = Vector3.new(0, 3, -20), time = 0.2 } },
			{ phase = "Dash", data = { from = Vector3.new(0, 3, -20), to = Vector3.new(0, 3, 0), time = 0.2 } },
			{ phase = "Bow", data = { pos = Vector3.new(0, 3, 0), radius = 9 } },
		},
	})
	local I = Loader.require(CLIENT .. "Kits.Integrity")
	T.ok(I.IsDoubleJump(-12, 54, 54), "mid-air jump while falling")
	T.ok(I.IsDoubleJump(8, 54, 54), "mid-air jump while rising")
	T.ok(not I.IsDoubleJump(0, 54, 54), "a ground jump is not a double jump")
	T.ok(not I.IsDoubleJump(-30, -10, 54), "falling is not a jump")
end

tests.strings_complete = function(T, Loader)
	local text = Loader.require("ReplicatedStorage.Shared.Strings.KitHumansA")
	local n = 0
	for key, entry in text do
		n += 1
		T.ok(type(entry.en) == "string" and entry.en ~= "", key .. " en")
		T.ok(type(entry.ru) == "string" and entry.ru ~= "", key .. " ru")
	end
	T.ok(n >= 7, "keys present")
	local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
	T.ok(Strings.Has("fx.patience.ambush") and Strings.Has("fx.bravery.courage") and Strings.Has("fx.integrity.bravo"), "merged")
end

return tests
