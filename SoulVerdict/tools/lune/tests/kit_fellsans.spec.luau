--!nocheck
-- Fell Sans kit tests: every ability runs through the REAL combat services (AbilityService -> CastContext ->
-- HazardService / DamageService / StatusService / MovementService) on Lune instances with a simulated clock,
-- the same harness approach as combat.spec.luau (flat ground at y = 0, fake CharacterService / Net / workspace,
-- bots get server-applied movers). Checks: no errors, hazards spawned with valid plain-data params, damage /
-- KR / statuses as designed, cooldowns, passives (Gold Tooth, Bloodlust lifesteal, Execution vs the weakened)
-- and robustness when Fell is interrupted mid-cast.
-- Run: lune run tools/lune/run_tests.luau kit_fellsans
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Instance = roblox.Instance

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."

-------------------------------------------------------------------------------------------------
-- Harness (copied from combat.spec.luau: real services, simulated clock, fake world)

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
			if H.wallZ and (origin.Z - H.wallZ) * (origin.Z + dir.Z - H.wallZ) < 0 then
				local t = (H.wallZ - origin.Z) / dir.Z
				return { Position = origin + dir * t, Normal = Vector3.zAxis, Distance = dir.Magnitude * t }
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
	function CS.GetPlayer(_m)
		return nil
	end
	function CS.GetModel(_p)
		return nil
	end
	function CS.Kill(m, attacker, ability)
		m:SetAttribute("Dead", true)
		table.insert(H.kills, { model = m, attacker = attacker, ability = ability })
	end
	function CS.SetDowned(m, attacker)
		m:SetAttribute("Downed", true)
		table.insert(H.downs, { model = m, attacker = attacker })
	end
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
	function H.setHp(m, hp)
		m:FindFirstChildOfClass("Humanoid").Health = hp
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

-------------------------------------------------------------------------------------------------
-- Helpers

-- Advance the clock in 60 Hz frames, stepping the hazard service each frame.
local function run(H, seconds)
	for _ = 1, math.ceil(seconds * 60 - 1e-6) do
		H.advance(1 / 60)
		H.S.HazardService._Step(1 / 60)
	end
	H.runDue()
end

local function fxOf(H, ability, phase)
	local out = {}
	for _, s in H.sent do
		if s.name == "AbilityFx" then
			local p = s.args[1]
			if p.ability == ability and (phase == nil or p.phase == phase) then
				table.insert(out, p)
			end
		end
	end
	return out
end

-- Hazard packets sent since index `from` (of H.sent), optionally of one type.
local function hazardsSince(H, from, hazardType)
	local out = {}
	for i = from + 1, #H.sent do
		local s = H.sent[i]
		if s.name == "Hazard" and (hazardType == nil or s.args[1].type == hazardType) then
			table.insert(out, s.args[1])
		end
	end
	return out
end

local function moverOf(m)
	return m.PrimaryPart:FindFirstChild("SV_Mover")
end

local function fellSetup(H, opts)
	local fell = H.spawn("FellSans", "Monster", Vector3.zero, {
		dodges = (opts and opts.dodges) or 0,
		maxDodges = (opts and opts.dodges) or 0,
		ult = opts and opts.ult,
	})
	H.S.AbilityService.GetServerKit("FellSans").OnSpawn(fell, nil)
	return fell
end

local function numbers(H, abilityId)
	return H.Kits.Ability("FellSans", abilityId).Numbers
end

-------------------------------------------------------------------------------------------------

return {
	fell_kit_shape = function(T, Loader)
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		local kit = Kits.Get("FellSans")
		T.ok(kit ~= nil and kit.Role == "Monster", "kit data")
		local server = Loader.requirePath("src/server/Kits/FellSans")
		local client = Loader.require(CLIENT .. "Kits.FellSans")
		for _, ability in kit.Abilities do
			T.ok(type(server.Abilities[ability.Id]) == "function", "server handler " .. ability.Id)
			T.ok(type(client.Effects[ability.Id]) == "function", "client Effects." .. ability.Id)
			T.ok(type(client.Predict[ability.Id]) == "function", "client Predict." .. ability.Id)
		end
		for _, id in { "CrimsonBlaster", "ChainGrab", "BoneRush", "Lunge", "Execution" } do
			T.ok(type(client.Indicator[id]) == "function", "client Indicator." .. id)
		end
		T.ok(type(client.Effects.GoldTooth) == "function", "passive Glint effect")
		T.ok(type(client.OnCharacter) == "function" and type(client.OnDamageFx) == "function", "passive hooks")
		T.ok(type(server.OnSpawn) == "function" and type(server.OnDespawn) == "function", "server lifecycle")
		-- client geometry mirrors the server
		local sc, cc = server.Constants, client.Constants
		for _, key in { "ExecWidth", "ExecLock", "ChainRadius", "ChainMaxSlope", "SpikeRadius", "RushTime", "LungeTime" } do
			T.eq(cc[key], sc[key], "client constant " .. key)
		end
		for i = 1, 3 do
			T.eq(cc.BlasterSlot[i], sc.BlasterSlot[i], "blaster slot " .. i)
		end
		-- strings: every key in both languages and merged
		local text = Loader.require("ReplicatedStorage.Shared.Strings.KitFell")
		for key, entry in text do
			T.ok(string.sub(key, 1, 5) == "fell.", key .. " prefix")
			T.ok(type(entry.en) == "string" and entry.en ~= "", key .. " en")
			T.ok(type(entry.ru) == "string" and entry.ru ~= "", key .. " ru")
		end
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		T.ok(Strings.Has("fell.fx.noMercy") and Strings.Has("fell.fx.executed"), "merged into Strings")
		-- pure helpers
		local pts = server.RushPoints(Vector3.zero, Vector3.new(0, 0, -1), 28, 7)
		T.eq(#pts, 7, "rush points")
		T.near(pts[1].Z, -2, 1e-6, "first rush point")
		T.near(pts[7].Z, -26, 1e-6, "last rush point")
	end,

	fell_bone_cleaver_combo = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local N = numbers(H, "BoneCleaver")
			local fell = fellSetup(H)
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -5), { look = Vector3.new(0, 0, 1) })
			local side = H.spawn("Patience", "Humans", Vector3.new(9, 0, 0))
			local hp0, sideHp = H.hp(human), H.hp(side)
			local aim = { aim = Vector3.new(0, 3, -5), dir = Vector3.new(0, 0, -1), castId = 11 }
			T.ok(AS.CastAs(fell, "BoneCleaver", aim), "hit 1")
			T.eq(H.hp(human), hp0 - N.Damage1, "hit 1 damage")
			T.eq(human:GetAttribute("KR"), N.KR + 1, "KR + Gold Tooth KR")
			local ok2, why = AS.CastAs(fell, "BoneCleaver", aim)
			T.ok(not ok2 and why == "cooldown", "cooldown enforced")
			H.advance(0.45)
			T.ok(AS.CastAs(fell, "BoneCleaver", aim), "hit 2")
			H.advance(0.45)
			T.ok(AS.CastAs(fell, "BoneCleaver", aim), "hit 3")
			T.eq(moverOf(human), nil, "hits 1-3 do not launch")
			H.advance(0.45)
			T.ok(AS.CastAs(fell, "BoneCleaver", aim), "hit 4")
			T.eq(H.hp(human), hp0 - N.Damage1 - N.Damage2 - N.Damage3 - N.Damage4, "four-hit combo damage")
			T.eq(H.hp(side), sideHp, "nothing outside the box")
			local mover = moverOf(human)
			T.ok(mover ~= nil and mover.VectorVelocity.Y > 25 and mover.VectorVelocity.Z < -20, "finisher launches")
			local strikes = fxOf(H, "BoneCleaver", "Strike")
			T.eq(#strikes, 4, "Strike fx per hit")
			T.ok(strikes[4].data.last == true and strikes[4].data.combo == 4 and strikes[4].data.hits == 1, "finisher fx")
			T.ok(strikes[1].data.last == false, "first hit is not the finisher")
			-- the combo resets after the window
			H.advance(2)
			AS.CastAs(fell, "BoneCleaver", aim)
			T.eq(fxOf(H, "BoneCleaver", "Strike")[5].data.combo, 1, "combo restarts")
			-- interrupted swing deals nothing
			H.advance(2)
			local before = H.hp(human)
			H.Validation.Delay(0.05, function()
				H.S.StatusService.Apply(fell, "Stunned", 0.5)
			end)
			AS.CastAs(fell, "BoneCleaver", aim)
			T.eq(H.hp(human), before, "stunned mid-swing: no hit")
		end)
	end,

	fell_gold_tooth = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local N = numbers(H, "BoneCleaver")
			local fell = fellSetup(H)
			local human = H.spawn("Justice", "Humans", Vector3.new(0, 0, -5), { look = Vector3.new(0, 0, 1) })
			SS.Apply(human, "Rooted", 3)
			local hp0 = H.hp(human)
			AS.CastAs(fell, "BoneCleaver", { aim = Vector3.new(0, 3, -5), dir = Vector3.new(0, 0, -1) })
			T.near(H.hp(human), hp0 - N.Damage1 * 1.25, 1e-3, "+25 % vs Rooted")
			local glint = fxOf(H, "GoldTooth", "Glint")
			T.eq(#glint, 1, "Glint fx for the boosted hit")
			T.eq(glint[1].data.target, human, "glint target")
			-- a plain hit is not boosted and sends no glint
			SS.Remove(human, "Rooted")
			H.advance(2)
			local hp1 = H.hp(human)
			AS.CastAs(fell, "BoneCleaver", { aim = Vector3.new(0, 3, -5), dir = Vector3.new(0, 0, -1) })
			T.near(H.hp(human), hp1 - N.Damage1, 1e-3, "no bonus when free")
			T.eq(#fxOf(H, "GoldTooth", "Glint"), 1, "no new glint")
			-- other attackers never get Fell's passive
			local classic = H.spawn("ClassicSans", "Monster", Vector3.new(30, 0, 0))
			SS.Apply(human, "Stunned", 2)
			local hp2 = H.hp(human)
			H.S.DamageService.Apply({ Attacker = classic, Target = human, Amount = 10, Kind = "Melee" })
			T.near(H.hp(human), hp2 - 10, 1e-3, "Gold Tooth is Fell-only")
		end)
	end,

	fell_crimson_blaster = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, HS = H.S.AbilityService, H.S.HazardService
			local N = numbers(H, "CrimsonBlaster")
			local fell = fellSetup(H)
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -30), { look = Vector3.new(0, 0, 1) })
			local off = H.spawn("Kindness", "Humans", Vector3.new(8, 0, -30))
			local hp0, offHp = H.hp(human), H.hp(off)
			local mark = #H.sent
			T.ok(AS.CastAs(fell, "CrimsonBlaster", { aim = Vector3.new(0, 0, -30), dir = Vector3.new(0, 0, -1) }), "cast")
			local beams = hazardsSince(H, mark, "BlasterBeam")
			T.eq(#beams, 1, "exactly one blaster")
			local p = beams[1].params
			T.eq(p.style, "Fell", "Fell style")
			T.eq(p.color, "Red", "red colour rule")
			T.eq(p.width, N.Width, "narrow beam")
			T.eq(p.delay, N.Delay, "fast charge")
			T.eq(p.duration, N.BeamTime, "beam time")
			T.ok(p.origin.Position.Y > 6 and p.origin.Position.X > 1, "looms over the right shoulder")
			T.ok(p.origin.LookVector.Z < -0.95, "aimed at the target")
			T.ok(H.HazardDefs.Validate("BlasterBeam", p), "valid params")
			T.eq(#fxOf(H, "CrimsonBlaster", "Summon"), 1, "Summon fx")
			T.eq(H.hp(human), hp0, "no damage during the charge")
			run(H, 0.2)
			T.eq(H.hp(human), hp0 - N.Damage, "beam damage")
			T.eq(human:GetAttribute("KR"), N.KR + 1, "beam KR + Gold Tooth")
			T.eq(H.hp(off), offHp, "narrow: the neighbour 8 studs aside is safe")
			-- interrupted during the charge: the shot fizzles
			AS.SetCooldown(fell, "CrimsonBlaster", 0)
			H.advance(1)
			H.Validation.Delay(0.2, function()
				H.S.StatusService.Apply(fell, "Stunned", 0.6)
			end)
			mark = #H.sent
			local hp1 = H.hp(human)
			T.ok(AS.CastAs(fell, "CrimsonBlaster", { aim = Vector3.new(0, 0, -30), dir = Vector3.new(0, 0, -1) }), "recast")
			local id = hazardsSince(H, mark, "BlasterBeam")[1].id
			T.eq(HS.Get(id), nil, "hazard removed when interrupted")
			T.eq(#fxOf(H, "CrimsonBlaster", "Fizzle"), 1, "Fizzle fx")
			run(H, 0.5)
			T.eq(H.hp(human), hp1, "no damage from a fizzled blaster")
		end)
	end,

	fell_chain_grab = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, SS, HS = H.S.AbilityService, H.S.StatusService, H.S.HazardService
			local N = numbers(H, "ChainGrab")
			local fell = fellSetup(H)
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -20), { look = Vector3.new(0, 0, 1) })
			local hp0 = H.hp(human)
			local mark = #H.sent
			local payload = { aim = Vector3.new(0, 3, -20), dir = Vector3.new(0, 0, -1) }
			T.ok(AS.CastAs(fell, "ChainGrab", payload), "cast")
			local proj = hazardsSince(H, mark, "Projectile")
			T.eq(#proj, 1, "chain projectile")
			T.eq(proj[1].params.visual, "FellChain", "custom chain visual")
			T.eq(proj[1].params.speed, N.Speed, "chain speed")
			T.ok(H.HazardDefs.Validate("Projectile", proj[1].params), "valid params")
			T.eq(#fxOf(H, "ChainGrab", "Throw"), 1, "Throw fx")
			run(H, 0.35)
			T.eq(HS.Get(proj[1].id), nil, "the chain ends on the grab")
			T.eq(H.hp(human), hp0 - N.Damage, "grab damage")
			T.eq(human:GetAttribute("KR"), 1, "Gold Tooth KR on a KR-less hit")
			T.ok(SS.Has(human, "Stunned"), "stunned")
			local endsAt = SS.Get(human, "Stunned")
			T.ok(endsAt - H.now() > N.Stun, "stunned through the pull and after it")
			local mover = moverOf(human)
			T.ok(mover ~= nil and mover.VectorVelocity.Z > 30, "pulled toward Fell")
			local grab = fxOf(H, "ChainGrab", "Grab")
			T.eq(#grab, 1, "Grab fx")
			T.eq(grab[1].data.target, human, "grab target")
			T.ok(math.abs(grab[1].data.to.Z + 3.4) < 0.01, "pulled to just in front of Fell")
			-- Gold Tooth follow-up on the stunned human
			local N1 = numbers(H, "BoneCleaver")
			human.PrimaryPart.CFrame = H.HazardDefs.LookAlong(Vector3.new(0, 3, -4), Vector3.new(0, 0, 1))
			local hp1 = H.hp(human)
			AS.CastAs(fell, "BoneCleaver", { aim = Vector3.new(0, 3, -4), dir = Vector3.new(0, 0, -1) })
			T.near(H.hp(human), hp1 - N1.Damage1 * 1.25, 1e-3, "grab -> cleaver gets the Gold Tooth bonus")
			T.ok(AS.CastAs(fell, "ChainGrab", payload) == false, "cooldown")
		end)
	end,

	fell_chain_grab_blocked_and_iframes = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local fell = fellSetup(H)
			local blocker = H.spawn("Integrity", "Humans", Vector3.new(0, 0, -15), { look = Vector3.new(0, 0, 1) })
			blocker:SetAttribute("Blocking", true)
			blocker:SetAttribute("BlockStart", H.now() - 5)
			AS.CastAs(fell, "ChainGrab", { aim = Vector3.new(0, 3, -15), dir = Vector3.new(0, 0, -1) })
			run(H, 0.3)
			T.eq(#fxOf(H, "ChainGrab", "Snap"), 1, "blocked chain snaps")
			T.ok(not SS.Has(blocker, "Stunned"), "a block stops the grab")
			T.eq(moverOf(blocker), nil, "no pull")
			-- an i-framed human lets the chain fly through to the next one
			AS.SetCooldown(fell, "ChainGrab", 0)
			blocker:SetAttribute("Blocking", false)
			SS.Apply(blocker, "IFrames", 2)
			local behind = H.spawn("Bravery", "Humans", Vector3.new(0, 0, -25), { look = Vector3.new(0, 0, 1) })
			local hpB = H.hp(blocker)
			H.advance(0.5)
			AS.CastAs(fell, "ChainGrab", { aim = Vector3.new(0, 3, -25), dir = Vector3.new(0, 0, -1) })
			run(H, 0.4)
			T.eq(H.hp(blocker), hpB, "i-frames: untouched")
			T.ok(SS.Has(behind, "Stunned"), "the human behind is grabbed")
			-- Fell interrupted during the windup: no chain at all
			AS.SetCooldown(fell, "ChainGrab", 0)
			SS.Remove(behind, "Stunned")
			H.advance(1)
			local mark = #H.sent
			H.Validation.Delay(0.1, function()
				SS.Apply(fell, "Stunned", 0.5)
			end)
			AS.CastAs(fell, "ChainGrab", { aim = Vector3.new(0, 3, -25), dir = Vector3.new(0, 0, -1) })
			T.eq(#hazardsSince(H, mark, "Projectile"), 0, "no chain when interrupted")
		end)
	end,

	fell_bone_rush = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local N = numbers(H, "BoneRush")
			local fell = fellSetup(H)
			local onPath = H.spawn("Determination", "Humans", Vector3.new(0.5, 0, -12))
			local offPath = H.spawn("Kindness", "Humans", Vector3.new(7, 0, -12))
			local hp0, offHp = H.hp(onPath), H.hp(offPath)
			local pops = {}
			H.S.MovementService.Sent:Connect(function(model, packet)
				if model == onPath then
					table.insert(pops, packet)
				end
			end)
			local mark = #H.sent
			T.ok(AS.CastAs(fell, "BoneRush", { aim = Vector3.new(0, 3, -30), dir = Vector3.new(0, 0, -1) }), "cast")
			local dash = moverOf(fell)
			T.ok(dash ~= nil and dash.VectorVelocity.Z < -80, "fast dash along the aim")
			local spikes = hazardsSince(H, mark, "BoneSpikes")
			T.eq(#spikes, N.Spikes, "one cluster per spike point")
			for i, s in spikes do
				T.ok(H.HazardDefs.Validate("BoneSpikes", s.params), "valid params " .. i)
				T.eq(s.params.color, "Red", "red bones")
				T.eq(s.params.delay, N.SpikeDelay, "erupts SpikeDelay after Fell passes")
				T.near(s.params.center.Y, 0, 1e-4, "on the ground")
				T.near(s.params.center.Z, -N.Distance * (i - 0.5) / N.Spikes, 1e-4, "along the path")
			end
			T.ok(spikes[N.Spikes].t0 > spikes[1].t0, "clusters spawn as Fell passes")
			T.eq(#fxOf(H, "BoneRush", "Rush"), 1, "Rush fx")
			T.eq(H.hp(onPath), hp0, "nothing before the eruption")
			run(H, 0.8)
			T.eq(H.hp(onPath), hp0 - N.Damage, "hit once despite overlapping clusters")
			T.eq(onPath:GetAttribute("KR"), N.KR + 1, "rush KR + Gold Tooth")
			T.eq(H.hp(offPath), offHp, "off the path: safe")
			T.ok(#pops == 1 and pops[1].kind == "Impulse" and pops[1].velocity.Y > 10, "spikes knock up")
			-- a wall shortens the rush and its trail
			AS.SetCooldown(fell, "BoneRush", 0)
			H.wallZ = -10
			mark = #H.sent
			fell.PrimaryPart.CFrame = H.HazardDefs.LookAlong(Vector3.new(0, 3, 0), Vector3.new(0, 0, -1))
			AS.CastAs(fell, "BoneRush", { aim = Vector3.new(0, 3, -30), dir = Vector3.new(0, 0, -1) })
			for _, s in hazardsSince(H, mark, "BoneSpikes") do
				T.ok(s.params.center.Z > -10, "no spikes through the wall")
			end
			H.wallZ = nil
			-- interrupted mid-dash: the trail stops where Fell stopped
			AS.SetCooldown(fell, "BoneRush", 0)
			mark = #H.sent
			H.Validation.Delay(0.2, function()
				H.S.StatusService.Apply(fell, "Stunned", 0.4)
			end)
			AS.CastAs(fell, "BoneRush", { aim = Vector3.new(0, 3, -30), dir = Vector3.new(0, 0, -1) })
			local partial = #hazardsSince(H, mark, "BoneSpikes")
			T.ok(partial > 0 and partial < N.Spikes, "partial trail when interrupted (" .. partial .. ")")
		end)
	end,

	fell_bloodlust = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, SS, DS = H.S.AbilityService, H.S.StatusService, H.S.DamageService
			local N = numbers(H, "Bloodlust")
			local fell = fellSetup(H, { dodges = 5 })
			local human = H.spawn("Determination", "Humans", Vector3.new(0, 0, -5), { look = Vector3.new(0, 0, 1) })
			T.ok(AS.CastAs(fell, "Bloodlust", {}), "cast")
			T.ok(SS.Has(fell, "Rage"), "Rage")
			local _, data = SS.Get(fell, "Rage")
			T.eq(data.damage, N.DamageMult, "damage mult")
			T.eq(data.speed, N.SpeedMult, "speed mult")
			T.eq(data.lifesteal, N.Lifesteal, "lifesteal")
			local endsAt = SS.Get(fell, "Rage")
			T.near(endsAt - H.now(), N.Duration, 0.01, "duration")
			T.near(fell:FindFirstChildOfClass("Humanoid").WalkSpeed, 18 * N.SpeedMult, 1e-3, "+20 % speed")
			T.eq(#fxOf(H, "Bloodlust", "Rage"), 1, "Rage fx")
			-- +30 % damage and 20 % lifesteal
			H.setHp(fell, 500)
			local N1 = numbers(H, "BoneCleaver")
			local hp0 = H.hp(human)
			AS.CastAs(fell, "BoneCleaver", { aim = Vector3.new(0, 3, -5), dir = Vector3.new(0, 0, -1) })
			local dealt = N1.Damage1 * N.DamageMult
			T.near(H.hp(human), hp0 - dealt, 1e-3, "+30 % damage")
			T.near(H.hp(fell), 500 + dealt * N.Lifesteal, 1e-3, "lifesteal heal")
			local siphon = fxOf(H, "Bloodlust", "Siphon")
			T.eq(#siphon, 1, "Siphon fx")
			T.eq(siphon[1].data.target, human, "siphon source")
			-- no lazy dodges while raging
			local fellHp = H.hp(fell)
			local r = DS.Apply({ Attacker = human, Target = fell, Amount = 10, Kind = "Melee" })
			T.ok(not r.Dodged and r.Applied > 0, "dodges disabled")
			T.eq(fell:GetAttribute("Dodges"), 5, "no dodge spent")
			T.ok(H.hp(fell) < fellHp, "took the hit")
			-- after it ends: back to normal
			H.advance(N.Duration + 0.5)
			H.runDue()
			T.ok(not SS.Has(fell, "Rage"), "Rage over")
			local r2 = DS.Apply({ Attacker = human, Target = fell, Amount = 10, Kind = "Melee" })
			T.ok(r2.Dodged, "lazy dodge is back")
		end)
	end,

	fell_lunge = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local N = numbers(H, "Lunge")
			local fell = fellSetup(H)
			T.ok(AS.CastAs(fell, "Lunge", { aim = Vector3.new(20, 3, 0), dir = Vector3.new(1, 0, 0) }), "cast")
			local mover = moverOf(fell)
			T.ok(mover ~= nil and mover.VectorVelocity.X > 100, "fast dash")
			local dash = fxOf(H, "Lunge", "Dash")[1]
			T.near((dash.data.to - dash.data.from).Magnitude, N.Distance, 1e-4, "distance")
			local ok, why = AS.CastAs(fell, "Lunge", { dir = Vector3.new(1, 0, 0) })
			T.ok(not ok and why == "cooldown", "cooldown")
		end)
	end,

	fell_execution = function(T, Loader)
		withHarness(Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local N = numbers(H, "Execution")
			local fell = fellSetup(H, { ult = 100 })
			local healthy = H.spawn("Determination", "Humans", Vector3.new(12, 0, 0))
			local weak = H.spawn("Patience", "Humans", Vector3.new(0, 0, -25), { hp = 300 })
			local far = H.spawn("Kindness", "Humans", Vector3.new(70, 0, 0))
			H.setHp(weak, 300 * (N.LowHpFraction - 0.05))
			local hpH, hpW, hpF = H.hp(healthy), H.hp(weak), H.hp(far)
			local ok0, why0 = AS.CastAs(H.spawn("FellSans", "Monster", Vector3.new(0, 0, 50)), "Execution", {})
			T.ok(not ok0 and why0 == "ult", "needs a full ult")
			local mark = #H.sent
			T.ok(AS.CastAs(fell, "Execution", {}), "cast")
			T.eq(fell:GetAttribute("Ult"), 0, "ult consumed")
			T.ok(SS.Has(healthy, "Marked") and SS.Has(weak, "Marked"), "humans in the radius are marked")
			T.ok(not SS.Has(far, "Marked"), "outside the radius: not marked")
			local markFx = fxOf(H, "Execution", "Mark")[1]
			T.eq(#markFx.data.targets, 2, "Mark fx lists both")
			local beams = hazardsSince(H, mark, "BlasterBeam")
			T.eq(#beams, 2, "one blaster per mark")
			for _, b in beams do
				local p = b.params
				T.ok(H.HazardDefs.Validate("BlasterBeam", p), "valid params")
				T.ok(p.origin.LookVector.Y < -0.99, "fires straight down")
				T.ok(p.origin.Position.Y > 15, "from above")
				T.eq(p.style, "Fell", "Fell style")
				T.eq(p.blockable, false, "unblockable")
				T.ok(p.spawnFrom.Y > p.origin.Position.Y, "drops in from higher up")
			end
			local drop = fxOf(H, "Execution", "Drop")[1]
			T.eq(#drop.data.points, 2, "Drop fx with the locked points")
			run(H, 0.75)
			T.eq(H.hp(healthy), hpH - N.Damage, "normal damage")
			T.eq(H.hp(weak), hpW - N.Damage * N.LowHpMult, "double damage to the weakened")
			T.eq(H.hp(far), hpF, "far human untouched")
			local executed = fxOf(H, "Execution", "Executed")
			T.eq(#executed, 1, "Executed fx for the low-HP hit")
			T.eq(executed[1].data.target, weak, "executed target")
			-- interrupted during the marking: nothing drops
			fell:SetAttribute("Ult", 100)
			AS.SetCooldown(fell, "Execution", 0)
			H.advance(1)
			mark = #H.sent
			H.Validation.Delay(0.3, function()
				SS.Apply(fell, "Stunned", 0.5)
			end)
			T.ok(AS.CastAs(fell, "Execution", {}), "recast")
			T.eq(#hazardsSince(H, mark, "BlasterBeam"), 0, "no blasters when interrupted")
			T.eq(#fxOf(H, "Execution", "Cancel"), 1, "Cancel fx")
		end)
	end,

	fell_all_hazards_plain_and_no_errors = function(T, Loader)
		withHarness(Loader, function(H)
			local AS = H.S.AbilityService
			local fell = fellSetup(H, { ult = 100 })
			H.spawn("Determination", "Humans", Vector3.new(0, 0, -8), { look = Vector3.new(0, 0, 1) })
			H.spawn("Perseverance", "Humans", Vector3.new(10, 0, -20))
			-- module code calls the loader's per-module `warn` (not the script env's), so collect through
			-- Loader.onWarn; restored below even if a cast throws (withHarness re-raises after cleanup)
			local warned = {}
			local oldOnWarn = Loader.onWarn
			Loader.onWarn = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					table.insert(parts, tostring((select(i, ...))))
				end
				table.insert(warned, table.concat(parts, " "))
			end
			local okCasts, castErr = pcall(function()
				local kit = H.Kits.Get("FellSans")
				for _, ability in kit.Abilities do
					AS.SetCooldown(fell, ability.Id, 0)
					H.S.StatusService.Remove(fell, "Stunned")
					local ok, why =
						AS.CastAs(fell, ability.Id, { aim = Vector3.new(0, 3, -12), dir = Vector3.new(0, 0, -1) })
					T.ok(ok, ability.Id .. " cast (" .. tostring(why) .. ")")
					run(H, 1.5)
				end
			end)
			Loader.onWarn = oldOnWarn
			T.ok(okCasts, "casts ran: " .. tostring(castErr))
			for _, w in warned do
				T.ok(false, "warning: " .. w)
			end
			for _, s in H.sent do
				if s.name == "Hazard" then
					local pkt = s.args[1]
					local ok, bad = H.HazardDefs.IsPlainData(pkt.params)
					T.ok(ok, pkt.type .. " plain data (" .. tostring(bad) .. ")")
					T.ok(H.HazardDefs.Validate(pkt.type, pkt.params), pkt.type .. " valid")
				end
			end
		end)
	end,
}
