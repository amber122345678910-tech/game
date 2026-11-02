--!nocheck
-- Eclipse Sans kit tests: every ability runs through the REAL combat services (AbilityService, StatusService,
-- DamageService, HazardService, MovementService) under Lune with a simulated clock, a fake CharacterService / Net
-- and flat ground at y = 0 (optional wall plane x = H.wallX). Same approach as combat.spec.luau's harness.
-- Checks: no errors, hazards spawned with valid plain params, damage / KR / statuses as designed, cooldowns,
-- traps (cap, arming, swept trigger, pull-through, expiry), void fire during the eclipse, Void Karma drain,
-- robustness when Eclipse falls mid-cast, and that the client kit loads with visuals for every phase.
-- Run: lune run tools/lune/run_tests.luau kit_eclipse
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Instance = roblox.Instance

local KIT = "EclipseSans"
local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."

local function harness(Loader)
	local H = {}
	local clock = 1000
	local timers = {}
	H.sent = {}
	H.models = {}
	H.round = { Phase = "Round", TeamRevives = 2, FinalPhase = false, Harmony = 1 }
	H.speeds = {}

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
		clock = math.max(clock, target)
	end
	function H.runDue()
		H.advance(0)
	end

	local G = getfenv(Loader.requirePath)
	H.G = G
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
	function H.at(seconds, fn)
		table.insert(timers, { at = clock + seconds, fn = fn })
	end
	Validation.RoundAttr = function(name)
		return H.round[name]
	end
	Validation.HorizontalSpeed = function(m)
		return H.speeds[m] or 0
	end

	local Signal = Loader.require("ReplicatedStorage.Shared.Util.Signal")
	local CS = { Spawned = Signal.new(), Died = Signal.new(), Downed = Signal.new(), Revived = Signal.new() }
	CS.Despawning = Signal.new()
	function CS.GetAll()
		local out = {}
		for _, m in H.models do
			if m:GetAttribute("Dead") ~= true and m.Parent ~= nil then
				table.insert(out, m)
			end
		end
		return out
	end
	function CS.GetPlayer()
		return nil
	end
	function CS.GetModel()
		return nil
	end
	function CS.Kill(m)
		m:SetAttribute("Dead", true)
	end
	function CS.SetDowned(m)
		m:SetAttribute("Downed", true)
	end
	H.CS = CS
	Validation.SetService("CharacterService", CS)
	Validation.SetService("StatsService", { Add = function() end })
	Validation.SetService("RoundService", {
		TriggerFinalPhase = function()
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
		hum.Parent = m
		m:SetAttribute("KitId", kitId)
		m:SetAttribute("Team", team)
		m:SetAttribute("Ult", opts.ult or 0)
		m:SetAttribute("Blocking", false)
		m:SetAttribute("Downed", false)
		m:SetAttribute("Dead", false)
		if kit and kit.Role == "Monster" then
			m:SetAttribute("Dodges", 0)
			m:SetAttribute("MaxDodges", 0)
			m:SetAttribute("Exhausted", 0)
		else
			m:SetAttribute("KR", 0)
			m:SetAttribute("Guard", 100)
			m:SetAttribute("MaxGuard", 100)
			m:SetAttribute("DashCharges", 2)
		end
		m.Parent = world
		table.insert(H.models, m)
		H.S.StatusService.Track(m)
		return m
	end

	-- Eclipse Sans with his kit lifecycle (OnSpawn + passive context factory), facing -Z at `pos`.
	function H.eclipse(pos, opts)
		local m = H.spawn(KIT, "Monster", pos or Vector3.zero, opts)
		H.kit = H.S.AbilityService.GetServerKit(KIT)
		H.kit.OnSpawn(m, function(id)
			return H.S.AbilityService.ContextFor(m, id)
		end)
		return m
	end

	function H.hp(m)
		return m:FindFirstChildOfClass("Humanoid").Health
	end
	function H.place(m, pos)
		m.PrimaryPart.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
	end
	function H.fx(phase, ability)
		local out = {}
		for _, s in H.sent do
			local p = s.args[1]
			if s.name == "AbilityFx" and p.kit == KIT and p.phase == phase and (ability == nil or p.ability == ability) then
				table.insert(out, p)
			end
		end
		return out
	end
	function H.hazards(hazardType)
		local out = {}
		for _, s in H.sent do
			if s.name == "Hazard" and (hazardType == nil or s.args[1].type == hazardType) then
				table.insert(out, s.args[1])
			end
		end
		return out
	end
	-- Runs the hazard simulation for `seconds` in `step` increments (StatusService ticks every 0.1 s).
	function H.simulate(seconds, step)
		step = step or 0.02
		local acc = 0
		for _ = 1, math.ceil(seconds / step) do
			H.advance(step)
			H.S.HazardService._Step(step)
			acc += step
			if acc >= 0.1 - 1e-9 then
				acc = 0
				H.S.StatusService._Step(0.1)
			end
		end
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

-- Every hazard the kit broadcast validates against HazardDefs and is plain packet data.
local function checkHazards(T, H, label)
	for _, pkt in H.hazards() do
		local ok, err = H.HazardDefs.Validate(pkt.type, pkt.params)
		T.ok(ok, label .. ": " .. pkt.type .. " params valid " .. tostring(err))
		T.ok(H.HazardDefs.IsPlainData(pkt.params), label .. ": " .. pkt.type .. " plain data")
	end
end

local function near(a, b, eps)
	return (a - b).Magnitude <= eps
end

return {
	eclipse_kit_shape = function(T, Loader)
		withHarness(Loader, function(H)
			local kit = H.S.AbilityService.GetServerKit(KIT)
			T.ok(type(kit) == "table" and type(kit.Abilities) == "table", "server kit loads")
			for _, ability in H.Kits.Get(KIT).Abilities do
				T.ok(type(kit.Abilities[ability.Id]) == "function", "handler for " .. ability.Id)
			end
			T.ok(type(kit.OnSpawn) == "function" and type(kit.OnDespawn) == "function", "lifecycle hooks")
		end)
	end,

	eclipse_void_lash_combo = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local N = H.Kits.Ability(KIT, "VoidLash").Numbers
			local eclipse = H.eclipse(Vector3.zero)
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -8), { look = Vector3.new(0, 0, 1) })
			local far = H.spawn("Patience", "Humans", Vector3.new(0, 0, -13), { look = Vector3.new(0, 0, 1) })
			local hp0, far0 = H.hp(human), H.hp(far)
			local aim = { aim = Vector3.new(0, 3, -8), dir = Vector3.new(0, 0, -1) }
			T.ok(AS.CastAs(eclipse, "VoidLash", aim), "lash 1")
			T.eq(H.hp(human), hp0 - N.Damage1, "long reach: hit at 8 studs")
			T.eq(human:GetAttribute("KR"), N.KR, "purple KR")
			local ok2, why = AS.CastAs(eclipse, "VoidLash", aim)
			T.ok(not ok2 and why == "cooldown", "cooldown respected")
			H.advance(0.45)
			T.ok(AS.CastAs(eclipse, "VoidLash", aim), "lash 2")
			H.advance(0.45)
			T.ok(AS.CastAs(eclipse, "VoidLash", aim), "lash 3")
			T.eq(H.hp(human), hp0 - N.Damage1 - N.Damage2 - N.Damage3, "three-hit damage")
			T.eq(H.hp(far), far0, "13 studs is out of reach")
			local _, data = SS.Get(human, "Slowed")
			T.ok(SS.Has(human, "Slowed") and data and data.mult == N.SlowMult, "last lash slows")
			local lashes = H.fx("Lash", "VoidLash")
			T.eq(#lashes, 3, "Lash fx per hit")
			T.ok(lashes[3].data.last == true and lashes[3].data.combo == 3, "combo index in fx")
			local dmg
			for _, s in H.sent do
				if s.name == "DamageFx" then
					dmg = s.args[1]
				end
			end
			T.eq(dmg and dmg.color, "Purple", "void hits are purple")
		end)
	end,

	eclipse_rift_blaster = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local N = H.Kits.Ability(KIT, "RiftBlaster").Numbers
			local eclipse = H.eclipse(Vector3.zero)
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -30), { look = Vector3.new(0, 0, 1) })
			local hp0 = H.hp(human)
			T.ok(AS.CastAs(eclipse, "RiftBlaster", { aim = Vector3.new(0, 0, -30) }), "cast")
			local beam = H.hazards("BlasterBeam")[1]
			T.ok(beam ~= nil, "beam hazard")
			local p = beam.params
			T.eq(p.style, "Eclipse", "void-wolf skull")
			T.eq(p.delay, N.Delay, "fires after Delay")
			T.eq(p.damage, N.Damage, "damage")
			local pos = p.origin.Position
			local chest = Vector3.new(0, 2.6, -30)
			T.near(Vector3.new(pos.X, 0, pos.Z - -30).Magnitude, N.Offset, 0.01, "rift opens Offset to the side")
			T.ok(math.abs(pos.Z + 30) < 0.01, "beside the aim point (perpendicular to the cast line)")
			-- the beam runs through the aim point
			local look = p.origin.LookVector
			local toChest = chest - pos
			local along = toChest:Dot(look)
			T.ok(along > 0 and (toChest - look * along).Magnitude < 0.05, "beam crosses the aim point")
			local rift = H.fx("Rift", "RiftBlaster")[1]
			T.ok(rift and rift.data.hazard == beam.id and near(rift.data.pos, pos, 1e-3), "Rift fx carries the rift")
			local ok2, why = AS.CastAs(eclipse, "RiftBlaster", { aim = Vector3.new(0, 0, -30) })
			T.ok(not ok2 and why == "cooldown", "cooldown respected")
			H.simulate(0.9)
			T.eq(H.hp(human), hp0, "silence before the burst")
			H.simulate(0.4)
			T.eq(H.hp(human), hp0 - N.Damage, "beam hit")
			T.eq(human:GetAttribute("KR"), N.KR, "beam KR")
			-- a wall on the preferred side: the rift opens on the open side
			AS.SetCooldown(eclipse, "RiftBlaster", 0)
			H.wallX = 5
			T.ok(AS.CastAs(eclipse, "RiftBlaster", { aim = Vector3.new(0, 0, -30) }), "cast 2")
			local beam2 = H.hazards("BlasterBeam")[2]
			T.ok(beam2.params.origin.Position.X < -10, "rift avoids the wall")
			H.wallX = nil
			checkHazards(T, H, "RiftBlaster")
		end)
	end,

	eclipse_gravity_well = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local N = H.Kits.Ability(KIT, "GravityWell").Numbers
			local eclipse = H.eclipse(Vector3.zero)
			local center = H.spawn("Determination", "Humans", Vector3.new(0, 0, -20), { look = Vector3.new(0, 0, 1) })
			local edge = H.spawn("Kindness", "Humans", Vector3.new(0, 0, -31), { look = Vector3.new(0, 0, 1) })
			local hpC, hpE = H.hp(center), H.hp(edge)
			T.ok(AS.CastAs(eclipse, "GravityWell", { aim = Vector3.new(0, 0, -20) }), "cast")
			local throw = H.fx("Throw", "GravityWell")[1]
			T.ok(throw and throw.data.time > 0.15 and throw.data.time <= 0.8, "thrown star")
			local orb = H.hazards("Orb")[1]
			T.ok(orb ~= nil, "orb after landing")
			T.eq(orb.params.pullStrength, N.Pull, "pull strength")
			T.eq(orb.params.duration, N.Duration, "pull duration")
			T.eq(orb.params.implodeRadius, N.ImplodeRadius, "implosion radius")
			T.eq(orb.params.visual, "EclipseWell", "custom visual")
			T.ok(near(orb.params.center, throw.data.to, 1e-3), "lands where thrown")
			T.ok(#H.fx("Land", "GravityWell") == 1, "Land fx")
			H.simulate(0.4)
			local mover = edge.PrimaryPart:FindFirstChild("SV_Mover")
			T.ok(mover ~= nil and mover.VectorVelocity.Z > 5, "edge human pulled toward the centre")
			H.simulate(N.Duration + 0.2)
			T.eq(H.hp(center), hpC - N.Damage, "implosion hits the centre")
			T.eq(H.hp(edge), hpE, "resisting the pull at the edge is safe")
			T.ok(center:GetAttribute("KR") >= N.KR, "implosion KR")
			local ok2, why = AS.CastAs(eclipse, "GravityWell", { aim = Vector3.new(0, 0, -20) })
			T.ok(not ok2 and why == "cooldown", "cooldown respected")
			checkHazards(T, H, "GravityWell")
		end)
	end,

	eclipse_starfall = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local N = H.Kits.Ability(KIT, "Starfall").Numbers
			local eclipse = H.eclipse(Vector3.zero)
			T.ok(AS.CastAs(eclipse, "Starfall", { aim = Vector3.new(0, 0, -30) }), "cast")
			local rain = H.hazards("Rain")[1]
			T.ok(rain ~= nil, "rain hazard")
			local p = rain.params
			T.eq(p.count, N.Count, "count")
			T.eq(p.interval, N.Interval, "interval")
			T.eq(p.size, N.ImpactRadius, "impact radius")
			T.eq(p.visual, "EclipseStar", "star visual")
			T.ok(p.telegraph ~= false and p.warn > 0.3 and p.warn <= p.delay, "impact markers shown before landing")
			local drops = H.HazardDefs.RainDrops(p)
			T.eq(#drops, N.Count, "drops")
			for _, d in drops do
				T.ok((Vector3.new(d.Position.X, 0, d.Position.Z) - Vector3.new(0, 0, -30)).Magnitude <= N.Radius + 1e-6, "in area")
			end
			local human = H.spawn("Determination", "Humans", drops[4].Position, { look = Vector3.new(0, 0, 1) })
			local hp0 = H.hp(human)
			H.simulate(p.delay + N.Count * N.Interval + 0.5)
			local lost = hp0 - H.hp(human)
			T.ok(lost >= N.Damage and lost % N.Damage == 0, "star impacts hit (" .. tostring(lost) .. ")")
			T.ok(human:GetAttribute("KR") >= N.KR, "star KR")
			local ok2, why = AS.CastAs(eclipse, "Starfall", { aim = Vector3.new(0, 0, -30) })
			T.ok(not ok2 and why == "cooldown", "cooldown respected")
			checkHazards(T, H, "Starfall")
		end)
	end,

	eclipse_rift_trap = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local N = H.Kits.Ability(KIT, "RiftTrap").Numbers
			local eclipse = H.eclipse(Vector3.zero)
			local human = H.spawn("Determination", "Humans", Vector3.new(40, 0, 0), { look = Vector3.new(0, 0, 1) })
			local spots = { Vector3.new(0, 0, -20), Vector3.new(10, 0, -20), Vector3.new(-10, 0, -20) }
			T.ok(AS.CastAs(eclipse, "RiftTrap", { aim = spots[1] }), "trap 1")
			local ok2, why = AS.CastAs(eclipse, "RiftTrap", { aim = spots[2] })
			T.ok(not ok2 and why == "cooldown", "cooldown respected")
			for i = 2, 3 do
				AS.SetCooldown(eclipse, "RiftTrap", 0)
				T.ok(AS.CastAs(eclipse, "RiftTrap", { aim = spots[i] }), "trap " .. i)
			end
			local traps = H.fx("Trap", "RiftTrap")
			T.eq(#traps, 3, "Trap fx")
			T.eq(traps[1].data.reveal, N.RevealDistance, "reveal distance sent to clients")
			local collapse = H.fx("Collapse", "RiftTrap")
			T.ok(#collapse == 1 and collapse[1].data.id == traps[1].data.id, "MaxTraps: the oldest collapses")
			T.eq(#H.kit._State(eclipse).Traps, N.MaxTraps, "two live traps")
			-- unarmed: walking over trap 3 right away is safe
			H.place(human, Vector3.new(-14, 0, -20))
			SS._Step(0.1)
			H.place(human, Vector3.new(-6, 0, -20))
			SS._Step(0.1)
			T.eq(#H.fx("Spring", "RiftTrap"), 0, "not armed yet")
			H.advance(N.ArmTime + 0.1)
			-- i-frames (a dash) pass over it
			SS.Apply(human, "IFrames", 0.3)
			H.place(human, Vector3.new(-14, 0, -20))
			SS._Step(0.1)
			T.eq(#H.fx("Spring", "RiftTrap"), 0, "dash i-frames pass safely")
			SS.Remove(human, "IFrames")
			-- a fast crossing between two ticks is still caught (swept test)
			H.place(human, Vector3.new(14, 0, -20))
			SS._Step(0.1)
			H.place(human, Vector3.new(6, 0, -20))
			SS._Step(0.1)
			local spring = H.fx("Spring", "RiftTrap")
			T.eq(#spring, 1, "trap sprung")
			T.eq(spring[1].data.victim, human, "victim in fx")
			local pos = human.PrimaryPart.Position
			T.ok(near(pos, Vector3.new(0, 3.05, -4.5), 0.1), "pulled through to the front of Eclipse")
			T.ok(SS.Has(human, "Rooted"), "rooted")
			T.eq(#H.kit._State(eclipse).Traps, 1, "sprung trap is used up")
			-- lifetime
			H.advance(N.Lifetime + 1)
			SS._Step(0.1)
			T.eq(#H.kit._State(eclipse).Traps, 0, "expired")
			T.eq(#H.fx("Collapse", "RiftTrap"), 2, "expiry collapses the rift")
			-- despawn collapses the remaining traps
			AS.SetCooldown(eclipse, "RiftTrap", 0)
			AS.CastAs(eclipse, "RiftTrap", { aim = spots[1] })
			H.kit.OnDespawn(eclipse)
			T.eq(#H.fx("Collapse", "RiftTrap"), 3, "OnDespawn collapses traps")
			T.eq(H.kit._State(eclipse), nil, "state cleared")
		end)
	end,

	eclipse_void_step = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local N = H.Kits.Ability(KIT, "VoidStep").Numbers
			local eclipse = H.eclipse(Vector3.zero)
			T.ok(AS.CastAs(eclipse, "VoidStep", { aim = Vector3.new(0, 0, -80), dir = Vector3.new(0, 0, -1) }), "cast")
			local pos = eclipse.PrimaryPart.Position
			T.near(pos.Z, -N.Distance, 0.1, "stepped Distance through the portal")
			T.ok(SS.Has(eclipse, "Invisible") and eclipse:GetAttribute("Invisible") == true, "invisible")
			T.eq(#H.fx("Enter", "VoidStep"), 1, "Enter fx")
			local tp = H.fx("Teleport", "VoidStep")[1]
			T.ok(tp and near(tp.data.to, pos, 0.1), "Teleport fx at the exit")
			H.advance(N.Invisible + 0.05)
			SS._Step(0.1)
			T.ok(not SS.Has(eclipse, "Invisible"), "visible again")
			local ok2, why = AS.CastAs(eclipse, "VoidStep", { aim = Vector3.new(0, 0, -80) })
			T.ok(not ok2 and why == "cooldown", "cooldown respected")
		end)
	end,

	eclipse_total_eclipse = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, SS, DS = H.S.AbilityService, H.S.StatusService, H.S.DamageService
			local N = H.Kits.Ability(KIT, "TotalEclipse").Numbers
			local eclipse = H.eclipse(Vector3.zero)
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -6), { look = Vector3.new(0, 0, 1) })
			local okUlt, whyUlt = AS.CastAs(eclipse, "TotalEclipse", {})
			T.ok(not okUlt and whyUlt == "ult", "ult needs 100")
			eclipse:SetAttribute("Ult", 100)
			local during = {}
			H.at(2, function()
				during.active = H.kit.EclipseActive(eclipse)
				during.hasted = SS.Has(eclipse, "Hasted")
				during.status = SS.Has(eclipse, "TotalEclipse")
				local _, data = SS.Get(eclipse, "Hasted")
				during.mult = data and data.mult
				-- a hit during the eclipse sets the victim's ground on fire
				DS.Apply({ Attacker = eclipse, Target = human, Amount = 5, Kind = "Melee" })
			end)
			T.ok(AS.CastAs(eclipse, "TotalEclipse", {}), "ult cast")
			T.eq(eclipse:GetAttribute("Ult"), 0, "ult consumed")
			T.ok(during.active and during.hasted and during.status, "eclipse statuses")
			T.eq(during.mult, N.SpeedMult, "speed bonus")
			local ec = H.fx("Eclipse", "TotalEclipse")[1]
			T.ok(ec and ec.data.duration == N.Duration and ec.data.vision == N.VisionRadius, "Eclipse fx")
			T.eq(#H.fx("End", "TotalEclipse"), 1, "End fx when the light returns")
			T.ok(not H.kit.EclipseActive(eclipse), "over")
			local fires = H.hazards("Zone")
			T.eq(#fires, 1, "void fire under the victim")
			local fp = fires[1].params
			T.ok(fp.color == "Purple" and fp.visual == "EclipseVoidFire" and fp.ability == "TotalEclipse", "fire params")
			T.eq(fp.damage, N.FireDamage, "fire damage")
			T.near(fp.radius, N.FireRadius, 1e-6, "fire radius")
			-- no fire outside the eclipse
			DS.Apply({ Attacker = eclipse, Target = human, Amount = 5, Kind = "Melee" })
			H.runDue()
			T.eq(#H.hazards("Zone"), 1, "no fire after the eclipse")
			-- void fire ticks FireDamage (white-box: open a short eclipse window)
			local st = H.kit._State(eclipse)
			st.EclipseUntil = H.now() + 3
			H.place(human, Vector3.new(20, 0, 20))
			local id = H.kit.VoidFire(eclipse, Vector3.new(20, 0, 20), 0.3)
			T.ok(id > 0, "fire zone spawned")
			T.eq(H.kit.VoidFire(eclipse, Vector3.new(21, 0, 20), 0.3), 0, "burning spots are not stacked")
			local hp0 = H.hp(human)
			H.simulate(0.3 + N.FireTick * 2 + 0.05)
			T.ok(hp0 - H.hp(human) >= 2 * N.FireDamage - 1e-6, "fire ticks FireDamage")
			-- the fire's own ticks never spread more fire
			T.eq(#H.hazards("Zone"), 2, "no chain reaction")
			checkHazards(T, H, "TotalEclipse")
		end)
	end,

	eclipse_void_karma_drain = function(T, Loader)
		withHarness(Loader, function(H)
			local SS = H.S.StatusService
			local N = H.Kits.Ability(KIT, "TotalEclipse").Numbers
			local eclipse = H.eclipse(Vector3.zero)
			local close = H.spawn("Determination", "Humans", Vector3.new(0, 0, -(N.AuraRadius - 3)), { ult = 50 })
			local mid = H.spawn("Kindness", "Humans", Vector3.new(0, 0, N.AuraRadius + 6), { ult = 50 })
			for _ = 1, 10 do
				H.advance(0.1)
				SS._Step(0.1)
			end
			T.ok(close:GetAttribute("Ult") < 50 - N.AuraDrain * 0.5, "aura drains ult")
			T.ok(mid:GetAttribute("Ult") >= 50, "outside the aura: no drain")
			-- the eclipse widens the darkness and deepens the drain
			H.kit._State(eclipse).EclipseUntil = H.now() + 5
			local c0, m0 = close:GetAttribute("Ult"), mid:GetAttribute("Ult")
			for _ = 1, 10 do
				H.advance(0.1)
				SS._Step(0.1)
			end
			T.ok(mid:GetAttribute("Ult") < m0 - N.DarkDrain * 0.5, "darkness reaches VisionRadius")
			T.ok(c0 - close:GetAttribute("Ult") > N.AuraDrain, "darkness drains faster")
			-- never below 0, not outside a combat phase
			close:SetAttribute("Ult", 0.05)
			H.round.Phase = "Intermission"
			mid:SetAttribute("Ult", 30)
			H.advance(0.1)
			SS._Step(0.1)
			T.eq(mid:GetAttribute("Ult") >= 30, true, "no drain outside the round")
			H.round.Phase = "Round"
			for _ = 1, 3 do
				H.advance(0.1)
				SS._Step(0.1)
			end
			T.ok(close:GetAttribute("Ult") >= 0, "clamped at 0")
		end)
	end,

	eclipse_falls_mid_cast = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local eclipse = H.eclipse(Vector3.zero)
			H.spawn("Determination", "Humans", Vector3.new(0, 0, -20))
			-- Rift Trap: dies during the windup -> no trap
			H.at(0.1, function()
				H.CS.Kill(eclipse)
			end)
			T.ok(AS.CastAs(eclipse, "RiftTrap", { aim = Vector3.new(0, 0, -10) }), "trap cast accepted")
			T.eq(#H.fx("Trap", "RiftTrap"), 0, "no trap from a fallen Eclipse")
			-- Gravity Well: dies while the star flies -> it fizzles, no orb
			local e2 = H.eclipse(Vector3.new(50, 0, 0))
			H.at(0.4, function()
				H.CS.Kill(e2)
			end)
			T.ok(AS.CastAs(e2, "GravityWell", { aim = Vector3.new(50, 0, -40) }), "well cast accepted")
			T.eq(#H.fx("Fizzle", "GravityWell"), 1, "fizzle")
			T.eq(#H.hazards("Orb"), 0, "no orb")
			-- Total Eclipse: dies during the windup -> no darkness
			local e3 = H.eclipse(Vector3.new(-50, 0, 0), { ult = 100 })
			H.at(0.3, function()
				H.CS.Kill(e3)
			end)
			T.ok(AS.CastAs(e3, "TotalEclipse", {}), "ult accepted")
			T.eq(#H.fx("Eclipse", "TotalEclipse"), 0, "no eclipse from a fallen Eclipse")
			-- the passive loop forgets fallen casters
			H.S.StatusService._Step(0.1)
			T.eq(H.kit._State(eclipse), nil, "fallen caster cleaned up")
		end)
	end,

	eclipse_client_kit = function(T, Loader)
		local client = Loader.require(CLIENT .. "Kits.EclipseSans")
		T.ok(type(client) == "table" and type(client.Effects) == "table", "client kit loads under Lune")
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		for _, ability in Kits.Get(KIT).Abilities do
			T.ok(type(client.Effects[ability.Id]) == "function", "Effects." .. ability.Id)
			if ability.Aim == "Ground" or ability.Hold then
				T.ok(type(client.Indicator[ability.Id]) == "function", "Indicator." .. ability.Id)
			end
		end
		T.ok(type(client.OnCharacter) == "function", "OnCharacter")
		local HV = Loader.require(CLIENT .. "Controllers.HazardVisuals")
		for _, name in { "EclipseStar", "EclipseWell", "EclipseVoidFire" } do
			T.ok(HV.HasVisual(name), "registered visual " .. name)
		end
		-- pure helpers shared with the server geometry
		T.ok(type(client.TrapVisibility) == "function", "TrapVisibility")
		T.eq(client.TrapVisibility(true, 100, 10), 1, "the monster always sees his traps")
		T.eq(client.TrapVisibility(false, 12, 10), 0, "humans: invisible beyond RevealDistance")
		T.ok(client.TrapVisibility(false, 4, 10) > 0.4, "humans: visible up close")
		local strings = Loader.require("ReplicatedStorage.Shared.Strings")
		T.ok(strings.L("eclipse.trap.sprung") ~= "eclipse.trap.sprung", "strings merged")
	end,
}
