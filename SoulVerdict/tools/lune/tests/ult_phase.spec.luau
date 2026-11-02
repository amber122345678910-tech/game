--!nocheck
-- Ultimates -> Phase 2 (the monster's "FinalPhase" in code). The monster's FIRST ultimate of a round starts its
-- Phase 2 through one central hook in AbilityService (RoundService.TriggerFinalPhase("Ult", caster) while the cast
-- commits); later ultimates are normal ones and the HP threshold stays the safety net. Levels:
--   * combat harness (as in combat.spec.luau): the REAL AbilityService / CastContext / server kits / DamageService /
--     StatusService / HazardService on Lune instances with a simulated clock (players and bots both cast through
--     AbilityService.tryCast). RoundService is a stand-in that records every call and applies to the monster what
--     the real TriggerFinalPhase applies (FinalForm, RoundState FinalPhase; "Ult": nothing refilled, Invulnerable
--     window only while not Exhausted; "Hp": Invulnerable window, Exhausted cleared, dodges + ult refilled), so each
--     Sans' ultimate is checked to still fire under it and an Exhausted monster stays Exhausted through it;
--   * round loop simulation (round.spec.luau's BuildSim: the REAL RoundService against faked engine services, practice
--     rounds): the "Ult" cause (round's monster only, fight phases only, once, no reset), the HP path ("Hp", full
--     refresh) and RoundEnded.monsterBroken (the monster's HP reached the 30 % threshold) for the Unshaken rewards;
--   * RewardService on a memory profile: the Unshaken quest / achievement follow monsterBroken, not Phase 2;
--   * client: Classic Sans' attack eye (Blue Soul's flash returns to the Phase 2 eye) on a fake fx, and the HUD
--     (Hud.Mount) showing the arena call-outs to round participants only, never to players waiting in the lobby.
-- Run: lune run tools/lune/run_tests.luau ult_phase
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
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
			local SS = H.S.StatusService
			if cause == "Ult" then
				-- no reset button: Exhausted / dodges / ult bar stay; the short transformation window only when the
				-- monster is not Exhausted, lifted when it becomes Exhausted inside it (StatusService.Applied below)
				if not SS.Has(m, "Exhausted") then
					SS.Apply(m, "Invulnerable", H.Config.Round.FinalPhaseInvulnerable)
					H.ultGuardUntil = clock + H.Config.Round.FinalPhaseInvulnerable
				end
			else
				SS.Apply(m, "Invulnerable", H.Config.Round.FinalPhaseInvulnerable)
				SS.Remove(m, "Exhausted")
				m:SetAttribute("Dodges", m:GetAttribute("MaxDodges"))
				m:SetAttribute("Exhausted", 0)
				m:SetAttribute("Ult", 100)
			end
			m:SetAttribute("FinalForm", true)
			Net.Server.FireAll("RoundEvent", "FinalPhase", { monster = m, cause = cause })
			return true
		end,
	})
	-- RoundService's onStatusApplied: Exhausted on the monster inside the ult window ends that window at once
	H.ultGuardUntil = 0
	H.S.StatusService.Applied:Connect(function(model, name)
		if name == "Exhausted" and model == H.monster and H.ultGuardUntil > clock then
			H.ultGuardUntil = 0
			H.S.StatusService.Remove(model, "Invulnerable")
		end
	end)

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

-- The third SAVE star's Surge on the monster (ObjectiveService.surge): dodges 0 + Exhausted for ExhaustTime.
local function surgeExhaust(H, monster)
	local exhaust = H.Config.Monster.ExhaustTime
	monster:SetAttribute("Dodges", 0)
	monster:SetAttribute("Exhausted", H.now() + exhaust)
	H.S.StatusService.Apply(monster, "Exhausted", exhaust)
end

-- RewardService fixtures (progression.spec.luau's shapes): a RoundStatRow, a RoundEnded result, a Player stand-in.
local function statRow(userId, fields)
	local r = {
		userId = userId,
		name = "P" .. tostring(userId),
		team = "Humans",
		kitId = "Determination",
		damage = 0,
		healing = 0,
		kills = 0,
		downs = 0,
		parries = 0,
		dodgesForced = 0,
		saves = 0,
		revives = 0,
		survived = false,
	}
	for k, v in fields or {} do
		r[k] = v
	end
	return r
end

local function roundResult(fields)
	local r = {
		winner = "Monster",
		reason = "Eliminated",
		rows = {},
		practice = false,
		durations = { round = 200, collapse = 0, total = 230 },
		mapId = "TestArena",
		roundId = 1,
	}
	for k, v in fields do
		r[k] = v
	end
	return r
end

local function fakePlayer(userId)
	local attrs = {}
	return {
		Name = "Tester" .. tostring(userId),
		DisplayName = "Tester",
		UserId = userId,
		Parent = {},
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end,
	}
end

-- Classic Sans' client attack eye on a fake fx: FxController.EyeGlow's semantics (one flame per eye keyed by colour; a
-- call with another colour destroys the old flame, on/off enables / disables it) and a simulated fx.Delay clock.
local function sansEyeRig(Loader)
	local rig = { clock = 0, timers = {}, eye = nil }
	rig.Kit = Loader.require("StarterPlayer.StarterPlayerScripts.Client.Kits.ClassicSans")
	local function keyOf(color)
		return if color then string.format("%.3f,%.3f,%.3f", color.R, color.G, color.B) else "default"
	end
	function rig.eyeGlow(_char, side, color, on)
		assert(side == "Left", "the attack eye is the left one")
		local key = keyOf(color)
		local h = rig.eye
		if h and h.key ~= key then
			rig.eye = nil
			h = nil
		end
		if on then
			if h == nil then
				h = { key = key }
				rig.eye = h
			end
			h.on = true
		elseif h then
			h.on = false
		end
	end
	-- "default" (the cyan/yellow flame), "blue" or "dark"
	function rig.state()
		local h = rig.eye
		if h == nil or not h.on then
			return "dark"
		end
		return if h.key == "default"
			then "default"
			elseif h.key == keyOf(Color3.fromRGB(20, 169, 255)) then "blue"
			else h.key
	end
	function rig.at(seconds, fn)
		table.insert(rig.timers, { at = rig.clock + seconds, fn = fn })
	end
	function rig.advance(seconds)
		local target = rig.clock + seconds
		while true do
			table.sort(rig.timers, function(a, b)
				return a.at < b.at
			end)
			local first = rig.timers[1]
			if first == nil or first.at > target then
				break
			end
			table.remove(rig.timers, 1)
			rig.clock = math.max(rig.clock, first.at)
			first.fn()
		end
		rig.clock = target
	end
	-- a Sans character (FinalForm = Phase 2) whose resting eye is already in place, as OnCharacter leaves it
	function rig.character(finalForm)
		local attrs = { FinalForm = finalForm }
		local char = {
			Name = "Sans",
			GetAttribute = function(_, k)
				return attrs[k]
			end,
			SetAttribute = function(_, k, v)
				attrs[k] = v
			end,
		}
		rig.eye = nil
		rig.eyeGlow(char, "Left", nil, finalForm == true)
		return char
	end
	function rig.fx(char, opts)
		opts = opts or {}
		local noop = function() end
		return {
			Character = char,
			IsLocal = opts.isLocal == true,
			Predicted = opts.predicted == true,
			EyeGlow = rig.eyeGlow,
			Delay = rig.at,
			Sound = noop,
			Shake = noop,
			Root = function()
				return nil
			end,
			Part = function()
				return nil
			end,
			Screen = { Tint = noop, Vignette = noop },
			VFX = {
				EmitBurst = noop,
				GroundCircle = function()
					return { SetTransparency = noop, Destroy = noop }
				end,
				Animate = function(duration, _step, done)
					rig.at(duration, function()
						if done then
							done()
						end
					end)
				end,
			},
		}
	end
	function rig.effect(char, ability, phase, opts, data)
		rig.Kit.Effects[ability](rig.fx(char, opts), { ability = ability, phase = phase, data = data or {} })
	end
	return rig
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

	-- 7) the REAL RoundService (round loop simulation, practice rounds): the "Ult" cause (no reset: Exhausted, dodges
	--    and the bar stay; the Invulnerable window only while not Exhausted), the HP path ("Hp": full refresh) and
	--    RoundEnded {finalPhase, monsterBroken} (monsterBroken = HP reached the 30 % threshold in the fight, ever)
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
		local ended = {}
		RS.RoundEnded:Connect(function(result)
			table.insert(ended, result)
		end)
		RS.Start()
		local function finalEvents()
			return sim.events.FinalPhase or {}
		end
		local function damaged(target, attacker)
			sim.services.DamageService.Damaged:Fire(
				{ Target = target, Attacker = attacker, Amount = 10 },
				{ Applied = 10 }
			)
		end
		local function exhaustedRemovals(model)
			local n = 0
			for _, c in sim.calls do
				if c.kind == "StatusRemove" and c.name == "Exhausted" and c.model == model then
					n += 1
				end
			end
			return n
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
			local function killHumans(by)
				for m, r in sim.records do
					if r.team == "Humans" and not r.dead then
						CS.Kill(m, by, "BoneJab")
					end
				end
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
			monster:SetAttribute("Dodges", 3) -- partly spent: the ultimate must not refill them
			T.eq(RS.TriggerFinalPhase("Ult", human), false, "a human's ultimate never starts it")
			T.eq(RS.TriggerFinalPhase("Ult", nil), false, "the Ult cause needs the caster")
			T.eq(sim.state().FinalPhase, false, "still Phase 1")
			T.eq(#finalEvents(), 0, "no FinalPhase event yet")
			local invBefore = sim.count("StatusApply", "name", "Invulnerable")
			T.eq(RS.TriggerFinalPhase("Ult", monster), true, "the monster's first ultimate starts Phase 2")
			T.eq(sim.state().FinalPhase, true, "RoundState.FinalPhase (clients switch to Theme_<kit>_Final)")
			T.eq(monster:GetAttribute("FinalForm"), true, "FinalForm")
			T.eq(monster:GetAttribute("Ult"), 37, "no ult refill for an ult-started Phase 2")
			T.eq(monster:GetAttribute("Dodges"), 3, "no dodge refill: the first ultimate is no reset button")
			T.eq(exhaustedRemovals(monster), 0, "Exhausted is never touched by an ult start")
			T.eq(
				sim.count("StatusApply", "name", "Invulnerable"),
				invBefore + 1,
				"transformation window (not Exhausted)"
			)
			local inv = sim.last("StatusApply")
			T.ok(
				inv and inv.model == monster and inv.duration == Config.Round.FinalPhaseInvulnerable,
				"Invulnerable on the monster for Config.Round.FinalPhaseInvulnerable"
			)
			local ev = finalEvents()[1]
			T.ok(ev ~= nil and ev.cause == "Ult" and ev.monster == monster, "RoundEvent FinalPhase {cause = Ult}")
			T.eq(ev and ev.duration, Config.Round.FinalPhaseInvulnerable, "event duration = the window")
			T.ok(#started == 1 and started[1].cause == "Ult", "FinalPhaseStarted(monster, Ult)")
			T.eq(RS.TriggerFinalPhase("Ult", monster), false, "a second ultimate does not re-trigger")
			T.eq(RS.TriggerFinalPhase(), false, "nor does a forced start")
			monster._hum.Health = monster._hum.MaxHealth * 0.2
			damaged(monster, human)
			task.wait(0.05)
			T.eq(#finalEvents(), 1, "HP threshold after an ult-started Phase 2: nothing more")
			T.eq(monster:GetAttribute("Ult"), 37, "and no late refill")
			CS.Kill(monster, human, "KnifeCombo")
			waitPhase("Ending", 1)
			local r1 = ended[#ended] or {}
			T.ok(#ended == 1 and r1.winner == "Humans", "round 1 ended: humans won")
			T.eq(r1.finalPhase, true, "RoundEnded.finalPhase")
			T.eq(r1.monsterBroken, true, "pushed to 20 % after the ult start: RoundEnded.monsterBroken")
			waitPhase("Waiting", 2)

			-- round 2: no ultimate used -> the HP threshold starts Phase 2 by itself, with the full comeback refresh
			T.ok(RS.StartPractice(owner, "Human"), "practice again")
			waitPhase("Round", 3)
			T.eq(sim.state().FinalPhase, false, "Phase 2 reset for the new round")
			local m2 = RS.GetMonster()
			m2:SetAttribute("Ult", 12)
			-- Exhausted (dodges burnt) when the humans push it under 30 %
			m2:SetAttribute("Dodges", 0)
			m2:SetAttribute("Exhausted", os.clock() + Config.Monster.ExhaustTime)
			sim.setStatus(m2, "Exhausted", true)
			local inv2 = sim.count("StatusApply", "name", "Invulnerable")
			m2._hum.Health = m2._hum.MaxHealth * 0.25
			damaged(m2, CS.GetModel(owner))
			T.ok(
				waitFor(function()
					return sim.state().FinalPhase == true
				end, 1),
				"HP <= 30 % starts Phase 2"
			)
			local ev2 = finalEvents()[#finalEvents()]
			T.ok(#finalEvents() == 2 and ev2.cause == "Hp", "RoundEvent FinalPhase {cause = Hp}")
			T.eq(ev2 and ev2.duration, Config.Round.FinalPhaseInvulnerable, "Hp: event duration = the window")
			T.eq(m2:GetAttribute("Ult"), 100, "HP start refills the ult")
			T.eq(exhaustedRemovals(m2), 1, "HP start clears Exhausted")
			T.eq(m2:GetAttribute("Exhausted"), 0, "Exhausted attribute cleared")
			T.eq(m2:GetAttribute("Dodges"), m2:GetAttribute("MaxDodges"), "dodges refilled")
			T.eq(sim.count("StatusApply", "name", "Invulnerable"), inv2 + 1, "Invulnerable window")
			T.eq(started[2] and started[2].cause, "Hp", "FinalPhaseStarted(monster, Hp)")
			T.eq(RS.TriggerFinalPhase("Ult", m2), false, "an ultimate after an HP start is a normal ultimate")
			CS.Kill(m2, CS.GetModel(owner), "KnifeCombo")
			waitPhase("Ending", 1)
			local r2 = ended[#ended] or {}
			T.ok(#ended == 2 and r2.finalPhase == true and r2.monsterBroken == true, "round 2: Hp start = broken")
			waitPhase("Waiting", 2)

			-- round 3: practice as the MONSTER; Exhausted by the SAVE Surge, it casts its first ultimate: Phase 2
			-- starts but stays a no-reset start (no window, Exhausted + 0 dodges kept); it wins without ever going
			-- under 30 % -> monsterBroken false (the Unshaken quest / achievement stay available)
			T.ok(RS.StartPractice(owner, "Monster"), "monster practice")
			waitPhase("Round", 3)
			local m3 = CS.GetModel(owner)
			T.eq(RS.GetMonster(), m3, "the owner is the monster")
			local exhaustedUntil = os.clock() + Config.Monster.ExhaustTime
			m3:SetAttribute("Dodges", 0)
			m3:SetAttribute("Exhausted", exhaustedUntil)
			sim.setStatus(m3, "Exhausted", true)
			m3:SetAttribute("Ult", 100)
			local inv3 = sim.count("StatusApply", "name", "Invulnerable")
			T.eq(RS.TriggerFinalPhase("Ult", m3), true, "an Exhausted monster's first ultimate still starts Phase 2")
			T.eq(m3:GetAttribute("FinalForm"), true, "FinalForm")
			T.eq(sim.count("StatusApply", "name", "Invulnerable"), inv3, "no Invulnerable window while Exhausted")
			T.eq(exhaustedRemovals(m3), 0, "Exhausted kept")
			T.eq(sim.statuses[m3] and sim.statuses[m3].Exhausted, true, "the Exhausted status is still on")
			T.eq(m3:GetAttribute("Exhausted"), exhaustedUntil, "Exhausted attribute kept")
			T.eq(m3:GetAttribute("Dodges"), 0, "dodges stay 0")
			local ev3 = finalEvents()[#finalEvents()]
			T.ok(
				ev3 ~= nil and ev3.cause == "Ult" and ev3.duration == 0,
				"RoundEvent FinalPhase {cause = Ult, duration 0}"
			)
			m3._hum.Health = m3._hum.MaxHealth * 0.5
			damaged(m3, nil)
			task.wait(0.25) -- a few round-loop ticks at 50 %
			killHumans(m3)
			waitPhase("Ending", 1)
			local r3 = ended[#ended] or {}
			T.ok(#ended == 3 and r3.winner == "Monster" and r3.reason == "Eliminated", "round 3: the monster won")
			T.eq(r3.finalPhase, true, "Phase 2 happened (from the ultimate)")
			T.eq(r3.monsterBroken, false, "never under 30 %: monsterBroken false")
			waitPhase("Waiting", 2)

			-- round 4: practice as the monster; the Exhausted ATTRIBUTE alone (the Surge writes it first) also skips the
			-- window; HP dips to 25 % with no hit event (the round loop's tick sees it) and is healed back: still broken
			T.ok(RS.StartPractice(owner, "Monster"), "monster practice again")
			waitPhase("Round", 3)
			local m4 = CS.GetModel(owner)
			T.eq(sim.state().FinalPhase, false, "Phase 2 reset")
			m4:SetAttribute("Exhausted", os.clock() + Config.Monster.ExhaustTime)
			local inv4 = sim.count("StatusApply", "name", "Invulnerable")
			T.eq(RS.TriggerFinalPhase("Ult", m4), true, "ult start")
			T.eq(sim.count("StatusApply", "name", "Invulnerable"), inv4, "Exhausted attribute: no window either")
			m4._hum.Health = m4._hum.MaxHealth * 0.25
			task.wait(0.3)
			m4._hum.Health = m4._hum.MaxHealth
			killHumans(m4)
			waitPhase("Ending", 1)
			local r4 = ended[#ended] or {}
			T.ok(#ended == 4 and r4.winner == "Monster", "round 4: the monster won")
			T.eq(r4.monsterBroken, true, "was pushed to 25 % once (healed since): monsterBroken")
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

	-- 8) the first ultimate is no reset button (combat harness; the real RoundService is covered by 7):
	--    a) every Sans, Exhausted by the SAVE Surge: still Exhausted with 0 dodges through the transformation, no
	--       Invulnerable window, the humans' hits land at once with the Exhausted bonus; dodges return only when the
	--       exhaustion ends (the normal rule)
	--    b) not Exhausted, dodges partly spent: the count stays (no refill), only the short transformation window
	--    c) the HP comeback ("Hp") keeps its full refresh: Exhausted cleared, dodges + ult refilled, Invulnerable
	phase2_ult_is_no_reset_button = function(T, Loader)
		for kitId, ultId in MONSTER_ULTS do
			withHarness(Loader, function(H)
				local SS, DS = H.S.StatusService, H.S.DamageService
				local Config = H.Config
				local maxDodges = H.Kits.Get(kitId).Stats.MaxDodges
				local monster = H.monsterOf(kitId, nil, { dodges = maxDodges, hp = 5000 })
				local human = H.spawn(
					"Determination",
					"Humans",
					Vector3.new(-6, 0, -14),
					{ look = Vector3.new(0, 0, 1), hp = 5000 }
				)
				surgeExhaust(H, monster)
				local during = {}
				H.at(0.05, function()
					during.exhausted = SS.Has(monster, "Exhausted")
					during.invulnerable = SS.Has(monster, "Invulnerable")
					during.dodges = monster:GetAttribute("Dodges")
					during.finalForm = monster:GetAttribute("FinalForm")
					during.hit = DS.Apply({ Attacker = human, Target = monster, Amount = 100, Kind = "Melee" })
				end)
				local ok, why = H.S.AbilityService.CastAs(monster, ultId, { aim = Vector3.new(0, 0, -15) })
				T.ok(ok, kitId .. ": ultimate accepted while Exhausted (" .. tostring(why) .. ")")
				H.run(0.1)
				T.eq(#H.triggers, 1, kitId .. ": Phase 2 from the ultimate")
				T.eq(H.triggers[1] and H.triggers[1].cause, "Ult", kitId .. ": cause Ult")
				T.eq(H.round.FinalPhase, true, kitId .. ": Phase 2 started")
				T.eq(during.finalForm, true, kitId .. ": FinalForm (eye, faster dodge regen)")
				T.eq(during.exhausted, true, kitId .. ": still Exhausted right after the transformation")
				T.eq(during.dodges, 0, kitId .. ": no dodge refill")
				T.eq(during.invulnerable, false, kitId .. ": no Invulnerable window on top of the exhaustion")
				local hit = during.hit or {}
				T.ok(
					hit.Reason ~= "Immune" and hit.Dodged ~= true and (hit.Applied or 0) > 0,
					kitId .. ": the humans' hit lands (" .. tostring(hit.Reason) .. ")"
				)
				T.near(
					hit.Applied or 0,
					100 * Config.Monster.ExhaustDamageMult,
					0.01,
					kitId .. ": with the Exhausted damage bonus"
				)
				T.eq(monster:GetAttribute("Ult"), 0, kitId .. ": the bar stays spent")
				H.run(Config.Monster.ExhaustTime + 0.5)
				T.eq(SS.Has(monster, "Exhausted"), false, kitId .. ": the exhaustion runs out as usual")
				T.eq(monster:GetAttribute("Dodges"), maxDodges, kitId .. ": then the dodges come back (normal rule)")
			end)
		end

		-- b) 3 of 8 dodges left, not Exhausted
		withHarness(Loader, function(H)
			local SS = H.S.StatusService
			local monster = H.monsterOf("ClassicSans", nil, { dodges = 8 })
			monster:SetAttribute("Dodges", 3)
			local during = {}
			H.at(0.05, function()
				during.dodges = monster:GetAttribute("Dodges")
				during.invulnerable = SS.Has(monster, "Invulnerable")
				during.exhausted = SS.Has(monster, "Exhausted")
			end)
			T.ok(H.S.AbilityService.CastAs(monster, "BadTime", { aim = Vector3.new(0, 0, -15) }), "ultimate")
			H.run(0.1)
			T.eq(#H.triggers, 1, "Phase 2 from the ultimate")
			T.eq(during.dodges, 3, "the dodge count stays (no refill)")
			T.eq(during.exhausted, false, "not Exhausted")
			T.eq(during.invulnerable, true, "the short transformation window")
			H.run(H.Config.Round.FinalPhaseInvulnerable)
			T.eq(SS.Has(monster, "Invulnerable"), false, "the window is over after FinalPhaseInvulnerable")
		end)

		-- c) Exhausted when the humans push it under 30 %: the comeback refresh
		withHarness(Loader, function(H)
			local SS, DS = H.S.StatusService, H.S.DamageService
			local Config = H.Config
			local monster = H.monsterOf("FellSans", nil, { ult = 0, hp = 1000, dodges = 6 })
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -6), { look = Vector3.new(0, 0, 1) })
			surgeExhaust(H, monster)
			local r = DS.Apply({ Attacker = human, Target = monster, Amount = 700, Kind = "Melee" })
			T.near(r.Applied, 700 * Config.Monster.ExhaustDamageMult, 0.01, "Exhausted: the hit lands with the bonus")
			H.runDue()
			T.ok(H.hp(monster) <= 1000 * Config.Round.FinalPhaseHpFraction, "under the threshold")
			T.eq(#H.triggers, 1, "threshold crossed: one call")
			T.eq(H.triggers[1] and H.triggers[1].cause, "Hp", "cause Hp")
			T.eq(SS.Has(monster, "Exhausted"), false, "Exhausted cleared")
			T.eq(monster:GetAttribute("Exhausted"), 0, "Exhausted attribute cleared")
			T.eq(monster:GetAttribute("Dodges"), 6, "dodges refilled")
			T.eq(monster:GetAttribute("Ult"), 100, "ult refilled")
			T.eq(SS.Has(monster, "Invulnerable"), true, "the comeback's Invulnerable window")
		end)
	end,

	-- 9) RewardService: the Unshaken quest and the "Not Even Sweating" achievement (+ its title) follow
	--    RoundEnded.monsterBroken (the humans pushed the monster to the Phase 2 HP threshold), not Phase 2 itself
	phase2_unshaken_rewards_follow_hp_threshold = function(T, Loader)
		local base = "ServerScriptService.Server.Services."
		local DS = Loader.require(base .. "DataService")
		local Net = Loader.require("ReplicatedStorage.Shared.Net")
		local Quests = Loader.require("ReplicatedStorage.Shared.Progression.Quests")
		for _, name in { "RequestService", "MasteryService", "QuestService", "AchievementService", "RewardService" } do
			Loader.require(base .. name).Init()
		end
		local Reward = Loader.require(base .. "RewardService")
		DS._TestSetup({ Store = nil, Mode = "Memory", JobId = "J1" })
		local original = Net.Server.Fire
		Net.Server.Fire = function() end
		-- one real monster win with an Unshaken quest in the list; returns the quest progress + achievement / title
		local function monsterWin(userId, fields)
			local p = fakePlayer(userId)
			DS._StartSession(p)
			DS.Update(p, function(prof)
				prof.Quests.Window = Quests.Window(os.time())
				prof.Quests.List = { { Id = "Unshaken", Progress = 0, Goal = 1, Claimed = false } }
			end)
			fields.rows = {
				statRow(userId, { team = "Monster", kitId = "FellSans", kills = 2 }),
				statRow(-1000001, { kitId = "Justice" }),
			}
			Reward.Process(roundResult(fields), function(id)
				return if id == userId then p else nil
			end)
			local prof = DS.Get(p)
			local quest = prof.Quests.List[1]
			local out = {
				quest = if quest and quest.Id == "Unshaken" then quest.Progress else -1,
				achievement = prof.Achievements.unshaken == true,
				title = prof.Titles.unshaken == true,
			}
			DS._ReleaseSession(p)
			return out
		end
		local ok, err = pcall(function()
			local ult = monsterWin(1401, { finalPhase = true, monsterBroken = false })
			T.eq(ult.quest, 1, "Phase 2 from its own ultimate, never under 30 %: Unshaken quest done")
			T.ok(ult.achievement and ult.title, "and the achievement + title")
			local pushed = monsterWin(1402, { finalPhase = true, monsterBroken = true })
			T.eq(pushed.quest, 0, "pushed to 30 % HP: no Unshaken quest")
			T.ok(not pushed.achievement and not pushed.title, "and no achievement / title")
			local calm = monsterWin(1403, { finalPhase = false, monsterBroken = false })
			T.eq(calm.quest, 1, "won before any Phase 2: quest done")
			T.ok(calm.achievement, "and the achievement")
			local legacy = monsterWin(1404, { finalPhase = true })
			T.eq(legacy.quest, 1, "a result without monsterBroken never fails it")
		end)
		Net.Server.Fire = original
		T.ok(ok, "reward runs: " .. tostring(err))

		-- the texts name the HP threshold (en + ru), in step with Config.Round.FinalPhaseHpFraction
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		local pct = tostring(math.floor(Config.Round.FinalPhaseHpFraction * 100 + 0.5)) .. "%"
		local template = Quests.Get("Unshaken")
		T.eq(template and template.Param, math.floor(Config.Round.FinalPhaseHpFraction * 100 + 0.5), "quest Param")
		for _, lang in { "en", "ru" } do
			Strings.SetLanguage(lang)
			local quest = Strings.L("prog.quest.Unshaken", 1, template and template.Param)
			local desc = Strings.L("prog.ach.unshaken.desc", 1)
			T.ok(
				string.find(quest, pct, 1, true) ~= nil and not string.find(quest, "{", 1, true),
				lang .. ": " .. quest
			)
			T.ok(string.find(desc, pct, 1, true) ~= nil, lang .. ": " .. desc)
		end
		Strings.SetLanguage("en")
	end,

	-- 10) Classic Sans (client): Blue Soul's blue eye flash returns to the Phase 2 blazing eye instead of switching it
	--     off; the newest flash owns the eye (an older Gaster Blaster flash ending never cuts a Blue Soul flash short);
	--     outside Phase 2 the eye goes dark after each flash as before
	phase2_classic_sans_eye_survives_blue_soul = function(T, Loader)
		local rig = sansEyeRig(Loader)
		local observer = { predicted = false }

		-- a) Phase 2, seen by others: blue for the flash, then the Phase 2 flame again (and it stays)
		local sans = rig.character(true)
		T.eq(rig.state(), "default", "Phase 2: the eye blazes")
		rig.effect(sans, "BlueSoul", "Start", observer)
		T.eq(rig.state(), "blue", "Blue Soul: blue flash")
		rig.advance(1.0)
		T.eq(rig.state(), "blue", "still blue mid-flash")
		rig.advance(0.7)
		T.eq(rig.state(), "default", "after the flash: the Phase 2 eye blazes again")
		rig.advance(5)
		T.eq(rig.state(), "default", "and keeps blazing")

		-- b) Phase 2, the local caster: the predicted flash (the confirmed Start adds none)
		sans = rig.character(true)
		rig.Kit.Predict.BlueSoul(rig.fx(sans, { isLocal = true }), {})
		rig.effect(sans, "BlueSoul", "Start", { isLocal = true, predicted = true })
		T.eq(rig.state(), "blue", "predicted Blue Soul: blue flash")
		rig.advance(1.7)
		T.eq(rig.state(), "default", "predicted flash over: the Phase 2 eye again")

		-- c) Phase 1: the eye goes dark after the flash
		sans = rig.character(false)
		T.eq(rig.state(), "dark", "Phase 1: no blazing eye")
		rig.effect(sans, "BlueSoul", "Start", observer)
		T.eq(rig.state(), "blue", "Phase 1 Blue Soul flash")
		rig.advance(1.7)
		T.eq(rig.state(), "dark", "Phase 1: dark after the flash")

		-- d) overlapping flashes: Gaster Blaster (1.5 s) then Blue Soul 1 s later
		for _, finalForm in { true, false } do
			local label = if finalForm then "Phase 2" else "Phase 1"
			sans = rig.character(finalForm)
			rig.effect(sans, "GasterBlaster", "Start", observer)
			T.eq(rig.state(), "default", label .. ": blaster flash")
			rig.advance(1.0)
			rig.effect(sans, "BlueSoul", "Start", observer)
			rig.advance(0.6) -- the blaster flash has ended
			T.eq(rig.state(), "blue", label .. ": the newer Blue Soul flash is not cut short")
			rig.advance(1.1)
			T.eq(rig.state(), if finalForm then "default" else "dark", label .. ": then the resting eye")
		end

		-- e) Bad Time's blaze with a Blue Soul inside it
		sans = rig.character(true)
		rig.effect(sans, "BadTime", "Start", observer)
		rig.effect(sans, "BadTime", "Blaze", observer, { center = Vector3.zero, radius = 18, duration = 6 })
		rig.advance(1)
		rig.effect(sans, "BlueSoul", "Start", observer)
		T.eq(rig.state(), "blue", "Phase 2 blaze: Blue Soul flash")
		rig.advance(1.7)
		T.eq(rig.state(), "default", "Phase 2 blaze: back to the blazing eye")
		rig.advance(5)
		T.eq(rig.state(), "default", "Phase 2: still blazing after the blaze")
		-- outside a round (lobby tryout, never Phase 2): an older Blue Soul flash ending keeps the blaze's eye lit
		sans = rig.character(false)
		rig.effect(sans, "BlueSoul", "Start", observer)
		rig.advance(0.5)
		rig.effect(sans, "BadTime", "Start", observer)
		rig.effect(sans, "BadTime", "Blaze", observer, { center = Vector3.zero, radius = 18, duration = 6 })
		rig.advance(1.5) -- the Blue Soul flash ends inside the blaze
		T.eq(rig.state(), "default", "Phase 1 blaze: the eye stays lit for the blaze")
		rig.advance(5)
		T.eq(rig.state(), "dark", "Phase 1: dark once the blaze ends")
	end,

	-- 11) arena call-outs (FIGHT!, PHASE 2, Surge, SAVE n/3, Second Wind, COLLAPSE) only for round participants: a
	--     player waiting in the lobby during someone else's round sees none of them, fighters and spectators see all;
	--     the kill feed gets the same entries either way (unchanged)
	phase2_lobby_sees_no_arena_callouts = function(T, Loader)
		local isServer, quiet = Loader.isServer, Loader.quietWarnings
		Loader.isServer = false
		Loader.quietWarnings = true
		local ok, err = pcall(function()
			local roblox = Loader.roblox
			local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
			Strings.SetLanguage("en")
			local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
			local Hud = Loader.requirePath("src/client/UI/Hud")
			local Signal = Loader.require("ReplicatedStorage.Shared.Util.Signal")

			-- the pure rule
			local kinds = 0
			for kind in Hud.ARENA_CALLOUTS do
				kinds += 1
				T.eq(Hud.ShowsCallout(kind, "Lobby"), false, kind .. ": not in the lobby")
				T.eq(Hud.ShowsCallout(kind, nil), false, kind .. ": no role yet = lobby")
				for _, role in { "Human", "Monster", "Spectator" } do
					T.eq(Hud.ShowsCallout(kind, role), true, kind .. ": shown to a " .. role)
				end
			end
			T.eq(kinds, 6, "Fight, FinalPhase, Surge, SecondWind, Collapse, SaveLit")
			T.eq(Hud.ShowsCallout("Exhausted", "Lobby"), true, "other kinds are not gated")
			T.eq(Hud.ShowsCallout("Custom", nil), true, "previews are not gated")

			-- the live HUD (Hud.Mount) with a StateController stand-in: RoundEvent + Role()
			local role = "Lobby"
			local roundEvent = Signal.new()
			local state = {
				RoundEvent = roundEvent,
				Role = function()
					return role
				end,
			}
			local layout = UIRoot.ComputeLayout(roblox.Vector2.new(844, 390)) -- the owner's phone
			local h = Hud.Mount(roblox.Instance.new("Frame"), { Layout = layout, State = state, Input = {}, UI = {} })
			local shown, feed = {}, 0
			h.Pieces.Announcements.Show = function(kind, data)
				table.insert(shown, { kind = kind, data = data })
			end
			h.Pieces.KillFeed.Push = function()
				feed += 1
			end
			local function play()
				table.clear(shown)
				feed = 0
				-- back through Intermission so the next "Round" is a fresh fight start (FIGHT!)
				roundEvent:Fire("PhaseChanged", { phase = "Intermission" })
				roundEvent:Fire("PhaseChanged", { phase = "Round" })
				roundEvent:Fire("SaveLit", { lit = 1, total = 3, index = 1, by = {} })
				roundEvent:Fire("FinalPhase", { cause = "Ult" })
				roundEvent:Fire("Surge", { duration = 20 })
				roundEvent:Fire("SecondWind", { name = "Frisk" })
				roundEvent:Fire("Collapse", {})
				task.wait()
			end
			local function kindsShown()
				local out = {}
				for _, a in shown do
					table.insert(out, a.kind)
				end
				return table.concat(out, ",")
			end
			play()
			T.eq(kindsShown(), "", "lobby during someone else's round: no call-out at all")
			local lobbyFeed = feed
			T.ok(lobbyFeed > 0, "the kill feed still gets its entries")
			for _, r in { "Human", "Monster", "Spectator" } do
				role = r
				play()
				T.eq(kindsShown(), "Fight,SaveLit,FinalPhase,Surge,SecondWind,Collapse", r .. ": every call-out")
				T.eq(feed, lobbyFeed, r .. ": the same kill-feed entries")
			end
			role = "Monster"
			play()
			local final = shown[3] or {}
			T.ok(
				final.kind == "FinalPhase" and final.data and final.data.Monster == true and final.data.Ult == true,
				"the monster gets its own Phase 2 line (cause Ult)"
			)
			h.Destroy()
		end)
		Loader.isServer, Loader.quietWarnings = isServer, quiet
		T.ok(ok, "HUD mounted and ran: " .. tostring(err))
	end,
}
