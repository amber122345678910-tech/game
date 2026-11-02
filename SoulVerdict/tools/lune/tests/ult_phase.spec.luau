--!nocheck
-- Ultimates -> Phase 2 (the monster's "FinalPhase" in code). The monster's FIRST ultimate of a round starts its
-- Phase 2 through one central hook in AbilityService (RoundService.TriggerFinalPhase("Ult", caster) while the cast
-- commits); later ultimates are normal ones and the HP threshold stays the safety net. Two levels:
--   * combat harness (as in combat.spec.luau): the REAL AbilityService / CastContext / server kits / DamageService /
--     StatusService / HazardService on Lune instances with a simulated clock (players and bots both cast through
--     AbilityService.tryCast). RoundService is a stand-in that records every call and applies to the monster what
--     the real TriggerFinalPhase applies (Invulnerable window, Exhausted cleared, dodges, FinalForm, RoundState
--     FinalPhase, ult refill except for "Ult"), so each Sans' ultimate is checked to still fire under it;
--   * round loop simulation (round.spec.luau's BuildSim: the REAL RoundService against faked engine services, practice
--     rounds): the "Ult" cause (round's monster only, fight phases only, once, no ult refill) and the HP path ("Hp").
-- Run: lune run tools/lune/run_tests.luau ult_phase
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Vector3 = roblox.Vector3
local Instance = roblox.Instance

local MONSTER_ULTS = { ClassicSans = "BadTime", FellSans = "Execution", EclipseSans = "TotalEclipse" }

-------------------------------------------------------------------------------------------------
-- Harness (combat.spec.luau's approach: real services, simulated clock, flat ground at y = 0, fake world)

local function harness(Loader)
	local H = {}
	local clock = 1000
	local timers = {}
	H.sent = {}
	H.models = {}
	H.kills = {}
	H.round = { Phase = "Round", TeamRevives = 2, FinalPhase = false, Harmony = 1 }
	H.triggers = {}
	H.monster = nil -- RoundService.GetMonster()

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
	H.runDue = runDue
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
	-- run fn once the simulated clock reaches now + seconds (also while a cast holds the clock)
	function H.at(seconds, fn)
		table.insert(timers, { at = clock + seconds, fn = fn })
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
	Validation.HorizontalSpeed = function()
		return 0
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
	function CS.SetDowned(m)
		m:SetAttribute("Downed", true)
	end
	Validation.SetService("CharacterService", CS)
	Validation.SetService("StatsService", { Add = function() end })
	Validation.SetService("VerdictBoxService", {
		Start = function()
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
	H.handlers = {}
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
	H.Config = Loader.require("ReplicatedStorage.Shared.Config")
	H.HazardDefs = Loader.require("ReplicatedStorage.Shared.Combat.HazardDefs")
	H.Kits = Loader.require("ReplicatedStorage.Shared.Kits")

	-- RoundService stand-in: records every call (that is what the AbilityService / DamageService hooks are checked
	-- against) and mirrors RoundService.TriggerFinalPhase's gate and its effects on the monster. The real one is
	-- covered by phase2_round_service_causes below.
	Validation.SetService("RoundService", {
		GetMonster = function()
			return H.monster
		end,
		TriggerFinalPhase = function(cause, caster)
			table.insert(H.triggers, { cause = cause, caster = caster, at = clock, sentIndex = #H.sent })
			local m = H.monster
			local fight = H.round.Phase == "Round" or H.round.Phase == "Collapse"
			if H.round.FinalPhase ~= false or not fight or m == nil or (cause == "Ult" and caster ~= m) then
				return false
			end
			H.round.FinalPhase = true
			H.S.StatusService.Apply(m, "Invulnerable", H.Config.Round.FinalPhaseInvulnerable)
			H.S.StatusService.Remove(m, "Exhausted")
			m:SetAttribute("Dodges", m:GetAttribute("MaxDodges"))
			m:SetAttribute("Exhausted", 0)
			if cause ~= "Ult" then
				m:SetAttribute("Ult", 100)
			end
			m:SetAttribute("FinalForm", true)
			Net.Server.FireAll("RoundEvent", "FinalPhase", { monster = m, cause = cause })
			return true
		end,
	})

	local world = Instance.new("Folder")
	world.Name = "World"

	-- Spawns a character standing on the ground at `pos`, facing `look` (default -Z).
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
		return m
	end

	-- The round's monster (ult full unless opts.ult is given), with its server kit's spawn hooks installed.
	function H.monsterOf(kitId, pos, opts)
		opts = opts or {}
		local m = H.spawn(kitId, "Monster", pos or Vector3.zero, {
			ult = opts.ult or 100,
			hp = opts.hp,
			dodges = opts.dodges or 0,
			maxDodges = opts.dodges or 0,
		})
		local serverKit = H.S.AbilityService.GetServerKit(kitId)
		if serverKit and type(serverKit.OnSpawn) == "function" then
			serverKit.OnSpawn(m, nil)
		end
		H.monster = m
		return m
	end

	function H.hp(m)
		return m:FindFirstChildOfClass("Humanoid").Health
	end
	-- AbilityFx packets of `ability` (optionally one phase) sent after index `from` of H.sent, oldest first
	function H.fx(ability, phase, from)
		local out = {}
		for i = (from or 0) + 1, #H.sent do
			local s = H.sent[i]
			if
				s.name == "AbilityFx"
				and s.args[1].ability == ability
				and (phase == nil or s.args[1].phase == phase)
			then
				table.insert(out, s.args[1])
			end
		end
		return out
	end
	-- index in H.sent of the first AbilityFx Start of `ability` after index `from`
	function H.startIndex(ability, from)
		for i = (from or 0) + 1, #H.sent do
			local s = H.sent[i]
			if s.name == "AbilityFx" and s.args[1].ability == ability and s.args[1].phase == "Start" then
				return i
			end
		end
		return nil
	end
	function H.hazardsSince(from, hazardType)
		local out = {}
		for i = from + 1, #H.sent do
			local s = H.sent[i]
			if s.name == "Hazard" and (hazardType == nil or s.args[1].type == hazardType) then
				table.insert(out, s.args[1])
			end
		end
		return out
	end
	-- advance in 60 Hz frames, stepping the hazards
	function H.run(seconds)
		for _ = 1, math.ceil(seconds * 60 - 1e-6) do
			H.advance(1 / 60)
			H.S.HazardService._Step(1 / 60)
		end
		runDue()
	end
	-- make `m` able to cast its ultimate again right now
	function H.refill(m, abilityId)
		H.S.AbilityService.SetCooldown(m, abilityId, 0)
		m:SetAttribute("Ult", 100)
		H.advance(0.2)
	end
	function H.cleanup()
		Validation.SetScheduler(nil)
		G.workspace = nil
		G.RaycastParams = nil
	end
	return H
end

local function withHarness(Loader, fn)
	Loader.reset() -- fresh service modules for every harness (a test may build several, one per kit)
	local H = harness(Loader)
	local ok, err = pcall(fn, H)
	H.cleanup()
	if not ok then
		error(err, 0)
	end
end

-- Kit-specific proof that the ultimate itself ran in full (`from` = #H.sent before the cast).
local function checkUltFired(T, H, kitId, monster, humans, from)
	local N = H.Kits.Ability(kitId, MONSTER_ULTS[kitId]).Numbers
	if kitId == "ClassicSans" then
		T.eq(#H.hazardsSince(from, "BlasterBeam"), N.Blasters, kitId .. ": every blaster spawned")
		T.eq(#H.hazardsSince(from, "Rain"), 1, kitId .. ": bone rain spawned")
		T.eq(#H.fx("BadTime", "Blaze", from), 1, kitId .. ": Blaze fx")
		T.ok(H.S.StatusService.Has(monster, "KRBoost"), kitId .. ": KR doubled")
		local before = 0
		for _, h in humans do
			before += H.hp(h)
		end
		H.run(N.Duration + 0.5)
		local after = 0
		for _, h in humans do
			after += H.hp(h)
		end
		T.ok(after < before, kitId .. ": the blasters / bones hit the humans in the area")
	elseif kitId == "FellSans" then
		local mark = H.fx("Execution", "Mark", from)[1]
		T.eq(mark and #mark.data.targets, #humans, kitId .. ": every human in range marked")
		T.eq(#H.hazardsSince(from, "BlasterBeam"), #humans, kitId .. ": a blaster per mark (cast not cancelled)")
		T.eq(#H.fx("Execution", "Cancel", from), 0, kitId .. ": no Cancel fx")
		local hp = {}
		for i, h in humans do
			hp[i] = H.hp(h)
		end
		H.run(1.2)
		for i, h in humans do
			T.eq(H.hp(h), hp[i] - N.Damage, kitId .. ": blaster " .. i .. " hit")
		end
	else
		local ec = H.fx("TotalEclipse", "Eclipse", from)[1]
		T.ok(ec ~= nil and ec.data.duration == N.Duration, kitId .. ": Eclipse fx after the windup")
		T.eq(#H.fx("TotalEclipse", "End", from), 1, kitId .. ": the eclipse ran to its end")
	end
end

-------------------------------------------------------------------------------------------------

return {
	-- 1) every Sans: the first ultimate starts Phase 2 exactly once and still fires as its opening move
	phase2_first_ult_starts_it_and_still_fires = function(T, Loader)
		for kitId, ultId in MONSTER_ULTS do
			withHarness(Loader, function(H)
				local SS = H.S.StatusService
				local monster = H.monsterOf(kitId)
				-- inside Bad Time's area (radius 18 around the aim) and Execution's radius, far enough apart that one
				-- Execution blaster (width 6) never catches both
				local humans = {
					H.spawn("Determination", "Humans", Vector3.new(-6, 0, -14), { look = Vector3.new(0, 0, 1) }),
					H.spawn("Justice", "Humans", Vector3.new(6, 0, -16), { look = Vector3.new(0, 0, 1) }),
				}
				local during = {}
				-- Eclipse holds its cast through the windup and the whole eclipse: sample mid-eclipse
				H.at(2, function()
					during.eclipse = SS.Has(monster, "TotalEclipse")
					during.hasted = SS.Has(monster, "Hasted")
				end)
				local from = #H.sent
				local ok, why = H.S.AbilityService.CastAs(monster, ultId, { aim = Vector3.new(0, 0, -15) })
				T.ok(ok, kitId .. ": ultimate accepted (" .. tostring(why) .. ")")
				T.eq(#H.triggers, 1, kitId .. ": exactly one TriggerFinalPhase call")
				local call = H.triggers[1] or {}
				T.eq(call.cause, "Ult", kitId .. ": cause Ult")
				T.eq(call.caster, monster, kitId .. ": caster passed for the round-monster check")
				T.eq(H.round.FinalPhase, true, kitId .. ": Phase 2 started")
				T.eq(monster:GetAttribute("FinalForm"), true, kitId .. ": FinalForm")
				T.eq(monster:GetAttribute("Ult"), 0, kitId .. ": the bar is spent, Phase 2 does not refill it")
				local startAt = H.startIndex(ultId, from)
				T.ok(startAt ~= nil, kitId .. ": the ultimate's Start fx was broadcast")
				T.ok(
					call.sentIndex ~= nil and startAt ~= nil and call.sentIndex < startAt,
					kitId .. ": Phase 2 starts while the cast commits, before the ultimate's Start fx"
				)
				local start = H.fx(ultId, "Start")[1]
				T.eq(start and start.data.phase2, true, kitId .. ": Start fx flags the opening move")
				if kitId == "EclipseSans" then
					T.ok(during.eclipse and during.hasted, kitId .. ": eclipse statuses mid-cast")
				end
				checkUltFired(T, H, kitId, monster, humans, from)
				T.eq(#H.triggers, 1, kitId .. ": still one call after the whole ultimate")
			end)
		end
	end,

	-- 2) later ultimates in Phase 2 are normal ultimates (no second call, no flag, the ult fires again)
	phase2_later_ults_are_normal = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local monster = H.monsterOf("ClassicSans")
			local function target()
				-- a fresh, sturdy human in the blast area for every ultimate
				return {
					H.spawn("Bravery", "Humans", Vector3.new(0, 0, -15), { hp = 5000, look = Vector3.new(0, 0, 1) }),
				}
			end
			target()
			local aim = { aim = Vector3.new(0, 0, -15) }
			T.ok(AS.CastAs(monster, "BadTime", aim), "first ultimate")
			T.eq(#H.triggers, 1, "first ultimate: Phase 2")
			H.run(7)
			for round = 2, 3 do
				H.refill(monster, "BadTime")
				local humans = target()
				local from = #H.sent
				T.ok(AS.CastAs(monster, "BadTime", aim), "ultimate #" .. round .. " accepted")
				T.eq(#H.triggers, 1, "ultimate #" .. round .. ": no second TriggerFinalPhase call")
				T.eq(monster:GetAttribute("Ult"), 0, "ultimate #" .. round .. ": bar spent")
				local start = H.fx("BadTime", "Start", from)[1]
				T.ok(start ~= nil and start.data.phase2 == nil, "ultimate #" .. round .. ": a normal ultimate")
				checkUltFired(T, H, "ClassicSans", monster, humans, from)
				H.run(1)
			end
			T.eq(H.round.FinalPhase, true, "still Phase 2")
		end)
	end,

	-- 3) human ultimates (every SOUL) and monster kits outside the Monster team never start Phase 2
	phase2_human_ults_never_trigger = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local monster = H.monsterOf("ClassicSans", Vector3.new(0, 0, -10), { ult = 0 })
			local x = 0
			for _, kit in H.Kits.ForRole("Human") do
				local ult
				for _, a in kit.Abilities do
					if a.Ult then
						ult = a
					end
				end
				T.ok(ult ~= nil, kit.Id .. " has an ultimate")
				if ult then
					local human = H.spawn(kit.Id, "Humans", Vector3.new(x, 0, 0), { ult = 100 })
					x += 4
					local ok, why = AS.CastAs(human, ult.Id, { aim = Vector3.new(0, 0, -10), target = monster })
					T.ok(ok, kit.Id .. "." .. ult.Id .. " cast (" .. tostring(why) .. ")")
					T.ok(human:GetAttribute("Ult") < 100, kit.Id .. ": ult spent as before")
					H.run(0.5)
				end
			end
			-- a monster kit tried in the lobby (Team "Lobby") while a round runs
			local tryout = H.spawn("FellSans", "Lobby", Vector3.new(60, 0, 60), { ult = 100 })
			T.ok(AS.CastAs(tryout, "Execution", {}), "lobby tryout ultimate cast")
			T.eq(#H.triggers, 0, "no TriggerFinalPhase call for humans / lobby casters")
			T.eq(H.round.FinalPhase, false, "Phase 2 not started")
			T.eq(monster:GetAttribute("FinalForm"), nil, "monster untouched")
		end)
	end,

	-- 4) only during the fight (Round / Collapse); without a RoundState nothing happens either
	phase2_only_in_fight_phases = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local monster = H.monsterOf("ClassicSans")
			local aim = { aim = Vector3.new(0, 0, -15) }
			for _, phase in { "Waiting", "Intermission", "Intro", "Ending" } do
				H.round.Phase = phase
				H.refill(monster, "BadTime")
				T.ok(AS.CastAs(monster, "BadTime", aim), phase .. ": the ultimate itself still casts")
				T.eq(#H.triggers, 0, phase .. ": no TriggerFinalPhase call")
				T.eq(monster:GetAttribute("Ult"), 0, phase .. ": bar spent")
				H.run(7)
			end
			H.round = { Phase = "Round", TeamRevives = 2, Harmony = 1 } -- no FinalPhase attribute (no RoundState)
			H.refill(monster, "BadTime")
			T.ok(AS.CastAs(monster, "BadTime", aim), "no RoundState: cast")
			T.eq(#H.triggers, 0, "no RoundState: no call")
			H.run(7)
			H.round = { Phase = "Collapse", TeamRevives = 2, FinalPhase = false, Harmony = 1 }
			H.refill(monster, "BadTime")
			T.ok(AS.CastAs(monster, "BadTime", aim), "Collapse: cast")
			T.eq(#H.triggers, 1, "Collapse is a fight phase: Phase 2")
			T.eq(H.triggers[1] and H.triggers[1].cause, "Ult", "cause Ult")
			T.eq(H.round.FinalPhase, true, "Phase 2 during the Collapse")
		end)
	end,

	-- 5) the HP threshold is still the safety net; an ult-started Phase 2 consumes it
	phase2_hp_threshold_safety_net = function(T, Loader)
		-- a) no ultimate used: crossing 30 % starts Phase 2 by itself (HP floor 1 until then, ult refilled)
		withHarness(Loader, function(H)
			local AS, DS = H.S.AbilityService, H.S.DamageService
			local monster = H.monsterOf("ClassicSans", nil, { ult = 0, hp = 1000 })
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -6), { look = Vector3.new(0, 0, 1) })
			DS.Apply({ Attacker = human, Target = monster, Amount = 600, Kind = "Melee" })
			T.eq(H.hp(monster), 400, "40 % HP")
			T.eq(#H.triggers, 0, "above the threshold: nothing")
			DS.Apply({ Attacker = human, Target = monster, Amount = 5000, Kind = "Melee" })
			H.runDue()
			T.eq(H.hp(monster), 1, "no death before Phase 2 (HP floor 1)")
			T.eq(#H.triggers, 1, "threshold crossed: one call")
			T.eq(H.triggers[1] and H.triggers[1].cause, "Hp", "cause Hp")
			T.eq(H.round.FinalPhase, true, "Phase 2 started by HP")
			T.eq(monster:GetAttribute("Ult"), 100, "HP start refills the ult (stand-in mirrors RoundService)")
			local from = #H.sent
			T.ok(AS.CastAs(monster, "BadTime", { aim = Vector3.new(0, 0, -6) }), "its ultimate afterwards")
			T.eq(#H.triggers, 1, "that ultimate is a normal one")
			T.eq(#H.hazardsSince(from, "BlasterBeam"), 6, "and it fires")
			H.advance(H.Config.Round.FinalPhaseInvulnerable + 0.1)
			local r = DS.Apply({ Attacker = human, Target = monster, Amount = 5000, Kind = "Melee" })
			T.ok(r.Killed, "in Phase 2 the monster can be defeated")
		end)
		-- b) Phase 2 from the ultimate first: crossing 30 % later starts nothing and the HP floor is gone
		withHarness(Loader, function(H)
			local AS, DS = H.S.AbilityService, H.S.DamageService
			local monster = H.monsterOf("FellSans", nil, { hp = 1000 })
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -6), { look = Vector3.new(0, 0, 1) })
			T.ok(AS.CastAs(monster, "Execution", {}), "ultimate")
			T.eq(#H.triggers, 1, "Phase 2 from the ultimate")
			local inv = DS.Apply({ Attacker = human, Target = monster, Amount = 100, Kind = "Melee" })
			T.ok(inv.Applied == 0 and H.hp(monster) == 1000, "transformation window: the monster is invulnerable")
			H.run(H.Config.Round.FinalPhaseInvulnerable + 0.5)
			DS.Apply({ Attacker = human, Target = monster, Amount = 800, Kind = "Melee" })
			H.runDue()
			T.eq(H.hp(monster), 200, "20 % HP")
			T.eq(#H.triggers, 1, "the HP threshold does not call again")
			T.eq(monster:GetAttribute("Ult") < 100, true, "no late ult refill")
			local r = DS.Apply({ Attacker = human, Target = monster, Amount = 5000, Kind = "Melee" })
			T.ok(r.Killed, "no HP floor once Phase 2 has started")
		end)
	end,

	-- 6) a player's cast (Net "Cast") goes through the same hook as a bot's (AbilityService.CastAs)
	phase2_player_cast = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local monster = H.monsterOf("EclipseSans")
			H.spawn("Determination", "Humans", Vector3.new(0, 0, -8), { look = Vector3.new(0, 0, 1) })
			local player = Instance.new("Player")
			player.Name = "SansPlayer"
			player.Parent = Instance.new("Folder")
			H.playerOf = { [monster] = player }
			H.modelOf = { [player] = monster }
			AS.Start()
			H.handlers.Cast(player, "TotalEclipse", { castId = 7 })
			T.eq(#H.triggers, 1, "player ultimate: one call")
			T.eq(H.triggers[1] and H.triggers[1].caster, monster, "caster = the player's monster")
			local start = H.fx("TotalEclipse", "Start")[1]
			T.ok(start ~= nil and start.castId == 7 and start.data.phase2 == true, "Start fx (castId echoed) + flag")
			T.eq(#H.fx("TotalEclipse", "End"), 1, "the eclipse ran")
		end)
	end,

	-- 7) the REAL RoundService (round loop simulation, practice rounds): the "Ult" cause and the HP path
	phase2_round_service_causes = function(T, Loader)
		local RoundSpec = require("./round.spec")
		local sim = RoundSpec.BuildSim(Loader)
		local waitFor = RoundSpec.WaitFor
		local Config = sim.Config
		Config.Round.RoundTime = 30 -- room for the checks (the simulation shortens every phase)
		local CS = sim.CS
		local Stats = sim.load("StatsService")
		local RS = sim.load("RoundService")
		Stats.Init()
		RS.Init()
		Stats.Start()
		local started = {}
		RS.FinalPhaseStarted:Connect(function(monster, cause)
			table.insert(started, { monster = monster, cause = cause })
		end)
		RS.Start()
		local function finalEvents()
			return sim.events.FinalPhase or {}
		end
		local ok, err = pcall(function()
			local function waitPhase(name, timeout)
				return T.ok(
					waitFor(function()
						return RS.Phase() == name
					end, timeout or 3),
					"reached phase " .. name .. " (now " .. RS.Phase() .. ")"
				)
			end
			local owner = sim.addPlayer(1001, "Owner")
			waitPhase("Waiting", 1)

			-- round 1: practice as a human against a monster bot; Phase 2 from the monster's first ultimate
			T.ok(RS.StartPractice(owner, "Human"), "practice accepted")
			waitPhase("Intro", 2)
			local early = RS.GetMonster()
			T.ok(early ~= nil, "monster spawned for the intro")
			T.eq(RS.TriggerFinalPhase("Ult", early), false, "no Phase 2 before the fight starts")
			waitPhase("Round", 2)
			local monster = RS.GetMonster()
			local human = CS.GetModel(owner)
			monster:SetAttribute("Ult", 37) -- sentinel: AbilityService spends the bar right after the call
			T.eq(RS.TriggerFinalPhase("Ult", human), false, "a human's ultimate never starts it")
			T.eq(RS.TriggerFinalPhase("Ult", nil), false, "the Ult cause needs the caster")
			T.eq(sim.state().FinalPhase, false, "still Phase 1")
			T.eq(#finalEvents(), 0, "no FinalPhase event yet")
			local invBefore = sim.count("StatusApply", "name", "Invulnerable")
			T.eq(RS.TriggerFinalPhase("Ult", monster), true, "the monster's first ultimate starts Phase 2")
			T.eq(sim.state().FinalPhase, true, "RoundState.FinalPhase (clients switch to Theme_<kit>_Final)")
			T.eq(monster:GetAttribute("FinalForm"), true, "FinalForm")
			T.eq(monster:GetAttribute("Ult"), 37, "no ult refill for an ult-started Phase 2")
			T.eq(sim.count("StatusApply", "name", "Invulnerable"), invBefore + 1, "transformation window")
			local inv = sim.last("StatusApply")
			T.ok(
				inv and inv.model == monster and inv.duration == Config.Round.FinalPhaseInvulnerable,
				"Invulnerable on the monster for Config.Round.FinalPhaseInvulnerable"
			)
			local ev = finalEvents()[1]
			T.ok(ev ~= nil and ev.cause == "Ult" and ev.monster == monster, "RoundEvent FinalPhase {cause = Ult}")
			T.ok(#started == 1 and started[1].cause == "Ult", "FinalPhaseStarted(monster, Ult)")
			T.eq(RS.TriggerFinalPhase("Ult", monster), false, "a second ultimate does not re-trigger")
			T.eq(RS.TriggerFinalPhase(), false, "nor does a forced start")
			monster._hum.Health = monster._hum.MaxHealth * 0.2
			sim.services.DamageService.Damaged:Fire(
				{ Target = monster, Attacker = human, Amount = 10 },
				{ Applied = 10 }
			)
			task.wait(0.05)
			T.eq(#finalEvents(), 1, "HP threshold after an ult-started Phase 2: nothing more")
			T.eq(monster:GetAttribute("Ult"), 37, "and no late refill")
			CS.Kill(monster, human, "KnifeCombo")
			waitPhase("Ending", 1)
			waitPhase("Waiting", 2)

			-- round 2: no ultimate used -> the HP threshold starts Phase 2 by itself (unchanged safety net)
			T.ok(RS.StartPractice(owner, "Human"), "practice again")
			waitPhase("Round", 3)
			T.eq(sim.state().FinalPhase, false, "Phase 2 reset for the new round")
			local m2 = RS.GetMonster()
			m2:SetAttribute("Ult", 12)
			m2._hum.Health = m2._hum.MaxHealth * 0.25
			sim.services.DamageService.Damaged:Fire(
				{ Target = m2, Attacker = CS.GetModel(owner), Amount = 10 },
				{ Applied = 10 }
			)
			T.ok(
				waitFor(function()
					return sim.state().FinalPhase == true
				end, 1),
				"HP <= 30 % starts Phase 2"
			)
			local ev2 = finalEvents()[#finalEvents()]
			T.ok(#finalEvents() == 2 and ev2.cause == "Hp", "RoundEvent FinalPhase {cause = Hp}")
			T.eq(m2:GetAttribute("Ult"), 100, "HP start refills the ult")
			T.eq(started[2] and started[2].cause, "Hp", "FinalPhaseStarted(monster, Hp)")
			T.eq(RS.TriggerFinalPhase("Ult", m2), false, "an ultimate after an HP start is a normal ultimate")
			CS.Kill(m2, CS.GetModel(owner), "KnifeCombo")
			waitPhase("Ending", 1)
			waitPhase("Waiting", 2)
		end)
		sim.stopped = true
		T.ok(ok, "simulation ran without errors: " .. tostring(err))
		local loopErrors = {}
		for _, w in sim.warnings do
			if string.find(w, "round loop error", 1, true) or string.find(w, "handler:", 1, true) then
				table.insert(loopErrors, w)
			end
		end
		T.eq(#loopErrors, 0, "no round loop / handler errors: " .. table.concat(loopErrors, " | "))
		task.wait(0.15)
	end,
}
