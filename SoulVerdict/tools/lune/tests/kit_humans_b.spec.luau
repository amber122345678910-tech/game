--!nocheck
-- Kit tests: Perseverance, Kindness, Justice (server kits through the REAL combat services under Lune, plus the
-- client kit modules' shape / visual registration and the KitHumansB strings).
-- Harness = combat.spec.luau's simulated-service approach, extended: every simulated wait advances the clock in
-- 1/60 s frames and steps HazardService (and, when H.tickStatus, StatusService every 0.1 s) like the real
-- Heartbeat, so projectiles / zones / passives run while kit handlers wait. Kit handler errors are caught from
-- warn() and fail the test.
-- Run: lune run tools/lune/run_tests.luau kit_humans_b
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Instance = roblox.Instance
local Color3 = roblox.Color3
local Enum = roblox.Enum

local FRAME = 1 / 60

-- Shared simulated clock + workspace for every harness of this spec: modules capture the `workspace` global when
-- they load (Luau import caching), so one table must serve all harness instances created in a single test.
local clock = 1000
local timers = {}
local current = nil -- the active harness

local SHARED_WORKSPACE = {
	GetServerTimeNow = function()
		return clock
	end,
	Raycast = function(_, origin, dir)
		local wallX = current and current.wallX
		if wallX and (origin.X - wallX) * (origin.X + dir.X - wallX) < 0 then
			local t = (wallX - origin.X) / dir.X
			return { Position = origin + dir * t, Normal = Vector3.xAxis, Distance = dir.Magnitude * t }
		end
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

local function harness(Loader)
	local H = { sent = {}, models = {}, kills = {}, downs = {}, revives = {}, errors = {}, handlers = {} }
	H.round = { Phase = "Round", TeamRevives = 2, FinalPhase = false, Harmony = 1 }
	H.speeds = {}
	H.tickStatus = false
	table.clear(timers)
	current = H
	local statusAcc = 0

	local function runDue()
		while true do
			table.sort(timers, function(a, b)
				return a.at < b.at
			end)
			local first = timers[1]
			if first == nil or first.at > clock + 1e-9 then
				return
			end
			table.remove(timers, 1)
			first.fn()
		end
	end
	function H.now()
		return clock
	end
	function H.after(seconds, fn)
		table.insert(timers, { at = clock + seconds, fn = fn })
	end
	-- Advances the simulated clock frame by frame: timers, hazards, optional 10 Hz status ticks.
	function H.advance(seconds)
		local target = clock + (seconds or 0)
		runDue()
		while clock < target - 1e-9 do
			local dt = math.min(FRAME, target - clock)
			clock += dt
			runDue()
			if H.S and H.S.HazardService then
				H.S.HazardService._Step(dt)
			end
			if H.tickStatus and H.S and H.S.StatusService then
				statusAcc += dt
				if statusAcc >= 0.1 - 1e-9 then
					statusAcc -= 0.1
					H.S.StatusService._Step(0.1)
				end
			end
		end
	end

	local G = getfenv(Loader.requirePath)
	H.G = G
	G.workspace = SHARED_WORKSPACE
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
	function CS.Kill(m, attacker, ability)
		m:SetAttribute("Dead", true)
		table.insert(H.kills, { model = m, attacker = attacker, ability = ability })
	end
	function CS.SetDowned(m, attacker)
		m:SetAttribute("Downed", true)
		table.insert(H.downs, { model = m, attacker = attacker })
	end
	function CS.Revive(m, by)
		if m:GetAttribute("Downed") ~= true or (H.round.TeamRevives or 0) <= 0 then
			return false
		end
		H.round.TeamRevives -= 1
		m:SetAttribute("Downed", false)
		local hum = m:FindFirstChildOfClass("Humanoid")
		hum.Health = math.max(hum.Health, hum.MaxHealth * 0.35)
		table.insert(H.revives, { model = m, by = by })
		return true
	end
	H.CS = CS
	Validation.SetService("CharacterService", CS)
	Validation.SetService("StatsService", { Add = function() end })
	Validation.SetService("RoundService", {
		TriggerFinalPhase = function()
			return true
		end,
	})
	Validation.SetService("AimService", false)

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
	H.S.HazardService.Clear()
	H.teleports = {}
	H.S.MovementService.Teleport = function(m, cf)
		table.insert(H.teleports, { model = m, cframe = cf })
		m.PrimaryPart.CFrame = cf
	end
	H.HazardDefs = Loader.require("ReplicatedStorage.Shared.Combat.HazardDefs")
	H.Kits = Loader.require("ReplicatedStorage.Shared.Kits")

	local world = Instance.new("Folder")
	world.Name = "World"

	-- Spawns a character standing on the ground at `pos`, facing `look` (default -Z), and runs its kit OnSpawn.
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
		local hp = opts.maxHp or (kit and kit.Stats.MaxHP) or 100
		hum.MaxHealth = hp
		hum.Health = opts.hp or hp
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
			local d = opts.dodges or 0
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
		if serverKit and type(serverKit.Abilities) == "table" and not serverKit.__testWrapped then
			serverKit.__testWrapped = true
			for id, fn in serverKit.Abilities do
				serverKit.Abilities[id] = function(ctx)
					local ok, err = xpcall(fn, debug.traceback, ctx)
					if not ok then
						table.insert(current.errors, kitId .. "." .. id .. ": " .. tostring(err))
					end
				end
			end
		end
		if serverKit and type(serverKit.OnSpawn) == "function" and opts.noSpawnHook ~= true then
			serverKit.OnSpawn(m, nil)
		end
		return m
	end

	function H.hp(m)
		return m:FindFirstChildOfClass("Humanoid").Health
	end
	function H.setHp(m, v)
		m:FindFirstChildOfClass("Humanoid").Health = v
	end
	function H.root(m)
		return m.PrimaryPart.CFrame.Position
	end
	function H.fx(ability, phase)
		local out = {}
		for _, s in H.sent do
			local p = s.args[1]
			if s.name == "AbilityFx" and p.ability == ability and (phase == nil or p.phase == phase) then
				table.insert(out, p)
			end
		end
		return out
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
		for _, m in H.models do
			local serverKit = H.S.AbilityService.GetServerKit(m:GetAttribute("KitId"))
			if serverKit and type(serverKit.OnDespawn) == "function" then
				serverKit.OnDespawn(m)
			end
			m:SetAttribute("Dead", true)
			m.Parent = nil
		end
		Validation.SetScheduler(nil)
		Validation.SetService("AimService", nil)
		H.S.HazardService.Clear()
		table.clear(timers)
		current = nil
	end
	return H
end

local function withHarness(T, Loader, fn)
	local H = harness(Loader)
	local ok, err = pcall(fn, H)
	H.cleanup()
	if not ok then
		error(err, 0)
	end
	for _, e in H.errors do
		T.ok(false, "kit handler error: " .. e)
	end
end

local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."

---------------------------------------------------------------------------------------------------
-- Client smoke harness: runs every client Effects phase / Predict / Indicator / OnCharacter / visual builder
-- with stub characters (tables that pass typeof == "Instance") and a stub VFX layer whose Animate / fx.Delay run
-- synchronously, so every code path executes under Lune (no engine). Real Lune Parts receive the property writes,
-- so wrong property names still fail.

local function clientSmoke(Loader)
	local G = getfenv(Loader.requirePath)
	local realTypeof = typeof
	local S = { errors = {}, calls = 0 }
	local oldTypeof, oldRP = G.typeof, G.RaycastParams
	G.typeof = function(v)
		if type(v) == "table" and rawget(v, "__stub") then
			return "Instance"
		end
		return realTypeof(v)
	end
	G.RaycastParams = {
		new = function()
			return {}
		end,
	}
	function S.restore()
		G.typeof = oldTypeof
		G.RaycastParams = oldRP
	end
	local HazardDefs = Loader.require("ReplicatedStorage.Shared.Combat.HazardDefs")
	local function noop() end
	-- a real Lune Part behind a proxy (Lune cannot read BasePart.Position): writes are validated by the real part
	local function proxyPart(real)
		return setmetatable({ __real = real }, {
			__index = function(_, k)
				if k == "Position" then
					return real.CFrame.Position
				end
				local v = real[k]
				if type(v) == "function" then
					return function(_, ...)
						return v(real, ...)
					end
				end
				return v
			end,
			__newindex = function(_, k, v)
				if k == "Position" then
					real.CFrame = CFrame.new(v)
				else
					real[k] = v
				end
			end,
		})
	end
	local function stubModel(name, pos)
		local function part(n, at)
			local q = Instance.new("Part")
			q.Name = n
			q.CFrame = CFrame.new(at)
			return proxyPart(q)
		end
		local root = part("HumanoidRootPart", pos)
		local parts = { HumanoidRootPart = root }
		for _, n in { "Head", "RightHand" } do
			parts[n] = part(n, pos + Vector3.new(0.5, 1.5, -0.5))
		end
		local attrs = {}
		local m = { __stub = true, Name = name, Parent = true, PrimaryPart = root, _pivot = CFrame.new(pos) }
		function m:IsA(c)
			return c == "Model" or c == "Instance" or c == "PVInstance"
		end
		function m:GetAttribute(k)
			return attrs[k]
		end
		function m:SetAttribute(k, v)
			attrs[k] = v
		end
		function m:GetAttributeChangedSignal()
			return { Connect = function()
				return { Disconnect = noop }
			end }
		end
		function m:FindFirstChild(n)
			return parts[n]
		end
		function m:FindFirstChildWhichIsA()
			return root
		end
		function m:GetDescendants()
			return { parts.HumanoidRootPart, parts.Head, parts.RightHand }
		end
		function m:PivotTo(cf)
			self._pivot = cf
		end
		function m:GetPivot()
			return self._pivot
		end
		function m:Destroy()
			self.Parent = nil
		end
		return m
	end
	S.stubModel = stubModel
	local function circle()
		local c = {}
		for _, k in { "SetCenter", "SetRadius", "SetInner", "SetFill", "SetColor", "SetTransparency", "SetVisible", "SetCFrame", "Destroy" } do
			c[k] = noop
		end
		return c
	end
	local folder = Instance.new("Folder")
	local Lib = {
		LookAlong = HazardDefs.LookAlong,
		AxisFrame = HazardDefs.AxisFrame,
		Colors = { White = Color3.new(1, 1, 1) },
	}
	for _, k in { "Emit", "EmitRing", "EmitBurst", "Sparks", "Dust", "Flash", "Shockwave", "Ring", "Slash", "Line", "Beam", "Afterimage", "Shatter", "Text", "Debris" } do
		Lib[k] = function()
			S.calls += 1
		end
	end
	function Lib.Folder()
		return folder
	end
	function Lib.Now()
		return 100
	end
	function Lib.ParticleScale()
		return 1
	end
	function Lib.Ground(pos)
		return pos - Vector3.new(0, 3, 0)
	end
	function Lib.Characters()
		return S.chars or {}
	end
	function Lib.Part(shape, size, cf, color, material, transparency)
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
		return proxyPart(p)
	end
	function Lib.Release(p)
		p:Destroy()
	end
	function Lib.Light(parent, color, brightness, range)
		local l = Instance.new("PointLight")
		l.Color, l.Brightness, l.Range = color, brightness, range
		return l
	end
	function Lib.Emitter(_kind, _parent, props)
		local e = Instance.new("ParticleEmitter")
		for k, v in props or {} do
			if k ~= "Color" then
				e[k] = v
			end
		end
		return e
	end
	function Lib.GroundCircle()
		return circle()
	end
	function Lib.Soul(_color, _size)
		return stubModel("Soul", Vector3.zero)
	end
	function Lib.Animate(duration, step, done)
		for _, a in { 0, 0.3, 0.6, 1 } do
			if step(a, 1 / 30, a * math.min(duration, 2)) == true then
				break
			end
		end
		if done then
			done()
		end
		return { Cancel = noop }
	end
	S.Lib = Lib
	-- props: stub GiantBook / Dish builders (Lune Models have no PivotTo)
	local Props = Loader.require("ReplicatedStorage.Shared.Rigs.Props")
	local realGet = Props.Get
	Props.Get = function(name)
		if name == "GiantBook" then
			return { Size = Vector3.new(16, 1, 12), Build = function()
				return stubModel("Book", Vector3.zero)
			end, SetOpen = noop }
		elseif name == "Dish" then
			return { Build = function()
				return stubModel("Dish", Vector3.zero)
			end }
		end
		return realGet(name)
	end
	local oldRestore = S.restore
	function S.restore()
		oldRestore()
		Props.Get = realGet
	end
	function S.fx(character, isLocal, enemies)
		local anim = {}
		for _, k in { "Play", "Stop", "SetAim", "HitStop" } do
			anim[k] = noop
		end
		local screen = {}
		for _, k in { "Pulse", "Tint", "Flash", "Desaturate", "Vignette" } do
			screen[k] = noop
		end
		return {
			Character = character,
			IsLocal = isLocal,
			Predicted = false,
			State = {},
			Trove = { Add = noop, Connect = noop },
			Now = function()
				return 100
			end,
			Anim = anim,
			VFX = Lib,
			Screen = screen,
			Shake = noop,
			ShakeAt = noop,
			Kick = noop,
			Flash = noop,
			Sound = noop,
			Debris = noop,
			Delay = function(_s, fn)
				fn()
			end,
			Attachment = function(model, _name)
				local r = model and model.PrimaryPart
				return if r then { WorldPosition = r.Position } else nil
			end,
			Part = function(model, name)
				return model and model:FindFirstChild(name)
			end,
			Root = function(model)
				return model and model.PrimaryPart
			end,
			Chest = function(model)
				return model and model.PrimaryPart and model.PrimaryPart.Position + Vector3.new(0, 1, 0)
			end,
			Highlight = noop,
			HitStop = noop,
			EyeGlow = noop,
			LocalCharacter = function()
				return character
			end,
			IsEnemy = function(model)
				return enemies[model] == true
			end,
			Combat = function()
				return { ComboIndex = function()
					return 3
				end }
			end,
		}
	end
	function S.run(label, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			table.insert(S.errors, label .. ": " .. tostring(err))
		end
	end
	return S
end

return {
	---------------------------------------------------------------------------------------------
	-- Perseverance

	perseverance_swat_and_pages = function(T, Loader)
		withHarness(T, Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local p = H.spawn("Perseverance", "Humans", Vector3.zero)
			local mon = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -4))
			local side = H.spawn("FellSans", "Monster", Vector3.new(5, 0, -3))
			local hp0, side0 = H.hp(mon), H.hp(side)
			for i = 1, 3 do
				T.ok(AS.CastAs(p, "NotebookSwat", { aim = Vector3.new(0, 3, -4) }), "swat " .. i)
				if i < 3 then
					H.advance(0.45)
				end
			end
			T.eq(hp0 - H.hp(mon), 6 + 7 + 10, "3-hit combo damage")
			T.eq(side0 - H.hp(side), 6 + 7 + 10, "wide swats reach a target 5 studs to the side")
			T.ok(mon.PrimaryPart:FindFirstChild("SV_Mover") ~= nil, "3rd swat knocks back")
			local strikes = H.fx("NotebookSwat", "Strike")
			T.eq(#strikes, 3, "Strike fx per swat")
			T.ok(strikes[3].data.last == true and strikes[3].data.hits == 2, "last swat flagged")
		end)
		withHarness(T, Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local p = H.spawn("Perseverance", "Humans", Vector3.zero)
			local mon = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -20))
			local hp0 = H.hp(mon)
			T.ok(AS.CastAs(p, "SpellboundPages", { aim = Vector3.new(0, 3, -20) }), "pages cast")
			H.advance(1)
			T.eq(H.count("Hazard"), 5, "5 page projectiles")
			T.eq(H.last("Hazard").params.visual, "SpellPage", "page visual")
			T.eq(hp0 - H.hp(mon), 20, "5 pages x 4")
			T.ok(SS.Has(mon, "Rooted"), "3+ hits root the monster")
			local bind = H.fx("SpellboundPages", "Bind")
			T.ok(#bind == 1 and bind[1].data.target == mon and bind[1].data.duration == 1, "Bind fx")
			-- dodged pages do not count: 3 dodges eat the first 3 pages, only 2 land
			H.advance(1.2)
			SS.Remove(mon, "Rooted")
			mon:SetAttribute("Dodges", 3)
			mon:SetAttribute("MaxDodges", 3)
			AS.ResetCooldowns(p)
			local hp1 = H.hp(mon)
			T.ok(AS.CastAs(p, "SpellboundPages", { aim = Vector3.new(0, 3, -20) }), "pages cast again")
			H.advance(1)
			T.eq(mon:GetAttribute("Dodges"), 0, "pages strip dodges")
			T.ok(H.hp(mon) < hp1, "the last pages land")
			T.ok(not SS.Has(mon, "Rooted"), "only 2 landed: no root")
		end)
	end,

	perseverance_rewrite = function(T, Loader)
		withHarness(T, Loader, function(H)
			local AS, DS = H.S.AbilityService, H.S.DamageService
			local kit = AS.GetServerKit("Perseverance")
			local p = H.spawn("Perseverance", "Humans", Vector3.zero)
			H.tickStatus = true
			H.advance(1)
			T.ok(#kit.History(p) >= 9, "10 Hz history")
			-- walk away, get hurt and KR'd
			p.PrimaryPart.CFrame = H.HazardDefs.LookAlong(Vector3.new(12, 3, 0), Vector3.new(1, 0, 0))
			H.setHp(p, 60)
			DS.AddKR(p, 10)
			H.advance(2.6)
			local hpBefore = H.hp(p)
			T.ok(hpBefore < 60, "KR drained meanwhile")
			T.ok(AS.CastAs(p, "Rewrite", {}), "rewrite cast")
			local pos = H.root(p)
			T.ok(near(pos.X, 0, 0.01) and near(pos.Z, 0, 0.01), "rewound to the spot from 3 s ago")
			T.eq(#H.teleports, 1, "validated teleport")
			T.eq(H.hp(p), 100, "HP restored")
			T.eq(p:GetAttribute("KR"), 0, "KR cleared")
			local rewind = H.fx("Rewrite", "Rewind")[1]
			T.ok(rewind and #rewind.data.path >= 2 and rewind.data.heal > 0, "Rewind fx with a ghost path")
			T.eq(#H.fx("Rewrite", "Teleport"), 1, "Teleport fx")
			-- a rewind never hurts: taking a heal after the snapshot keeps the higher HP
			AS.ResetCooldowns(p)
			H.setHp(p, 40)
			H.advance(3.5)
			H.setHp(p, 90)
			T.ok(AS.CastAs(p, "Rewrite", {}), "second rewrite")
			T.eq(H.hp(p), 90, "max(now, then)")
			-- wall between here and the past: falls back to a newer visible sample
			AS.ResetCooldowns(p)
			p.PrimaryPart.CFrame = H.HazardDefs.LookAlong(Vector3.new(-10, 3, 0), Vector3.new(1, 0, 0))
			H.advance(1.5)
			p.PrimaryPart.CFrame = H.HazardDefs.LookAlong(Vector3.new(10, 3, 0), Vector3.new(1, 0, 0))
			H.advance(1.6)
			H.wallX = 0
			T.ok(AS.CastAs(p, "Rewrite", {}), "rewrite behind a wall")
			T.ok(H.root(p).X > 0, "never rewinds through a wall")
		end)
	end,

	perseverance_final_chapter = function(T, Loader)
		withHarness(T, Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local p = H.spawn("Perseverance", "Humans", Vector3.zero, { ult = 100 })
			local mon = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -20), { dodges = 3 })
			local hp0 = H.hp(mon)
			T.ok(AS.CastAs(p, "FinalChapter", { aim = Vector3.new(0, 3, -20), target = mon }), "ult cast")
			T.eq(hp0 - H.hp(mon), 35, "book slam damage")
			T.eq(mon:GetAttribute("Dodges"), 3, "undodgeable: no dodge used")
			T.ok(SS.Has(mon, "Silenced"), "silenced")
			local _, silenceData = SS.Get(mon, "Silenced")
			local endsAt = SS.Get(mon, "Silenced")
			T.ok(near(endsAt - H.now(), 3, 0.05), "3 s silence")
			T.eq(#H.fx("FinalChapter", "Summon"), 1, "Summon fx")
			T.eq(#H.fx("FinalChapter", "Lock"), 1, "Lock fx")
			T.eq(#H.fx("FinalChapter", "Slam")[1].data.hits, 1, "Slam fx lists the hit")
			T.ok(SS.Has(p, "Chapter"), "caster ult status (SOUL glow)")
			-- the book locks: a target that leaves the circle after the lock escapes
			SS.Remove(mon, "Silenced")
			p:SetAttribute("Ult", 100)
			AS.ResetCooldowns(p)
			local hp1 = H.hp(mon)
			H.after(0.6, function()
				mon.PrimaryPart.CFrame = mon.PrimaryPart.CFrame + Vector3.new(12, 0, 0)
			end)
			T.ok(AS.CastAs(p, "FinalChapter", { aim = Vector3.new(0, 3, -20), target = mon }), "ult cast 2")
			T.eq(H.hp(mon), hp1, "dashed out after the lock")
			-- stunned mid-cast: the slam is cancelled
			mon.PrimaryPart.CFrame = H.HazardDefs.LookAlong(Vector3.new(0, 3, -20), Vector3.new(0, 0, 1))
			p:SetAttribute("Ult", 100)
			AS.ResetCooldowns(p)
			H.after(0.3, function()
				SS.Apply(p, "Stunned", 1)
			end)
			T.ok(AS.CastAs(p, "FinalChapter", { aim = Vector3.new(0, 3, -20), target = mon }), "ult cast 3")
			T.eq(H.hp(mon), hp1, "no slam after the caster was stunned")
			T.ok(#H.fx("FinalChapter", "Cancel") >= 1, "Cancel fx")
		end)
	end,

	---------------------------------------------------------------------------------------------
	-- Kindness

	kindness_bonk_and_cooking = function(T, Loader)
		withHarness(T, Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local k = H.spawn("Kindness", "Humans", Vector3.zero)
			local mon = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -4))
			local hp0 = H.hp(mon)
			for i = 1, 3 do
				T.ok(AS.CastAs(k, "PanBonk", { aim = Vector3.new(0, 3, -4) }), "pan " .. i)
				if i < 3 then
					H.advance(0.45)
				end
			end
			T.eq(hp0 - H.hp(mon), 6 + 6 + 12, "pan combo damage")
			T.ok(SS.Has(mon, "Stunned"), "BONK dazes")
			local bonk = H.fx("PanBonk", "Bonk")
			T.ok(#bonk == 1 and bonk[1].data.targets[1] == mon, "Bonk fx")
		end)
		withHarness(T, Loader, function(H)
			local AS = H.S.AbilityService
			local k = H.spawn("Kindness", "Humans", Vector3.zero)
			local ally = H.spawn("Determination", "Humans", Vector3.new(0, 0, -15), { hp = 50 })
			local mon = H.spawn("ClassicSans", "Monster", Vector3.new(3, 0, -15))
			ally:SetAttribute("KR", 12)
			local monHp = H.hp(mon)
			T.ok(AS.CastAs(k, "HomeCooking", { aim = Vector3.new(0, 0, -15) }), "dish thrown")
			local zone = H.last("Hazard")
			T.ok(zone and zone.type == "Zone", "zone hazard")
			T.ok(zone.params.effect == "Heal" and zone.params.affects == "Allies", "heal zone for allies")
			T.ok(near(zone.params.amount, 3) and zone.params.tick == 0.5, "6 HP/s in 0.5 s ticks")
			T.ok(zone.params.radius == 9 and zone.params.duration == 5, "radius / duration from Numbers")
			local throw = H.fx("HomeCooking", "Throw")[1]
			T.ok(throw and near(throw.data.time, zone.params.delay), "flight time = telegraph")
			H.advance(zone.params.delay + 1.05)
			T.eq(ally:GetAttribute("KR"), 0, "KR removed")
			T.eq(H.hp(ally), 50 + 3 * 3, "3 heal ticks in the first second")
			T.eq(H.hp(mon), monHp, "the monster is not fed")
			H.advance(6)
			T.eq(H.hp(ally), 50 + 6 * 5, "6 HP/s for 5 s")
		end)
	end,

	kindness_shield_feast_nurturing = function(T, Loader)
		withHarness(T, Loader, function(H)
			local AS, SS, DS = H.S.AbilityService, H.S.StatusService, H.S.DamageService
			local k = H.spawn("Kindness", "Humans", Vector3.zero, { ult = 100 })
			local ally = H.spawn("Determination", "Humans", Vector3.new(0, 0, -12), { look = Vector3.new(0, 0, 1) })
			local mon = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -30))
			T.ok(AS.CastAs(k, "KindShield", { aim = Vector3.new(0, 3, -12), target = ally }), "shield ally")
			T.ok(SS.Has(ally, "Shielded"), "ally shielded")
			local _, data = SS.Get(ally, "Shielded")
			T.eq(data.amount, 40, "absorb 40")
			local r = DS.Apply({ Attacker = mon, Target = ally, Amount = 30, Kind = "Projectile" })
			T.eq(r.Absorbed, 30, "absorbed")
			T.eq(H.hp(ally), 110, "no HP lost")
			AS.ResetCooldowns(k)
			T.ok(AS.CastAs(k, "KindShield", { aim = Vector3.new(0, 3, 20) }), "shield without a target")
			T.ok(SS.Has(k, "Shielded"), "self shield")
			-- feast: heal + cleanse + haste + revive
			local hurt = H.spawn("Patience", "Humans", Vector3.new(10, 0, 0), { hp = 40 })
			hurt:SetAttribute("KR", 9)
			SS.Apply(hurt, "Slowed", 5, { mult = 0.5 })
			SS.Apply(hurt, "Rooted", 5)
			local down = H.spawn("Bravery", "Humans", Vector3.new(-20, 0, 0), { hp = 1 })
			down:SetAttribute("Downed", true)
			local far = H.spawn("Integrity", "Humans", Vector3.new(60, 0, 0), { hp = 30 })
			local revives = H.round.TeamRevives
			T.ok(AS.CastAs(k, "ButterscotchFeast", {}), "feast")
			T.eq(H.hp(hurt), 85, "healed 45")
			T.eq(hurt:GetAttribute("KR"), 0, "KR cleansed")
			T.ok(not SS.Has(hurt, "Slowed") and not SS.Has(hurt, "Rooted"), "debuffs cleansed")
			T.ok(SS.Has(hurt, "Hasted") and SS.Has(k, "Hasted"), "hasted")
			T.eq(down:GetAttribute("Downed"), false, "downed ally revived")
			T.eq(H.round.TeamRevives, revives - 1, "uses the team revive budget")
			T.ok(H.hp(down) > 40, "revived ally fed too")
			T.eq(H.hp(far), 30, "out of range")
			local feast = H.fx("ButterscotchFeast", "Feast")[1]
			T.ok(feast and feast.data.revived == down and #feast.data.allies >= 4, "Feast fx")
			T.ok(SS.Has(k, "Feast"), "caster ult status (SOUL glow)")
		end)
		withHarness(T, Loader, function(H)
			local k = H.spawn("Kindness", "Humans", Vector3.zero, { hp = 50 })
			local nearAlly = H.spawn("Determination", "Humans", Vector3.new(6, 0, 0), { hp = 50 })
			local farAlly = H.spawn("Determination", "Humans", Vector3.new(15, 0, 0), { hp = 50 })
			local mon = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -5), { hp = 500 })
			H.tickStatus = true
			H.advance(3.05)
			T.eq(H.hp(nearAlly), 53, "Nurturing: 1 HP/s within 8 studs")
			T.eq(H.hp(farAlly), 50, "nothing beyond 8 studs")
			T.eq(H.hp(k), 50, "not on herself")
			T.eq(H.hp(mon), 500, "not on enemies")
		end)
	end,

	---------------------------------------------------------------------------------------------
	-- Justice

	justice_revolver_ammo = function(T, Loader)
		withHarness(T, Loader, function(H)
			local AS = H.S.AbilityService
			local kit = AS.GetServerKit("Justice")
			local j = H.spawn("Justice", "Humans", Vector3.zero)
			local mon = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -10))
			T.eq(j:GetAttribute("Ammo"), 6, "ammo attribute on spawn")
			local hp0 = H.hp(mon)
			T.ok(AS.CastAs(j, "Revolver", { aim = Vector3.new(0, 3, -10) }), "shot")
			T.eq(hp0 - H.hp(mon), 8, "hitscan damage")
			T.eq(j:GetAttribute("Ammo"), 5, "ammo mirrored")
			local shot = H.fx("Revolver", "Shot")[1]
			T.ok(shot and shot.data.hit == mon and shot.data.long == false, "Shot fx")
			for i = 2, 6 do
				H.advance(0.4)
				T.ok(AS.CastAs(j, "Revolver", { aim = Vector3.new(0, 3, -10) }), "shot " .. i)
			end
			T.eq(hp0 - H.hp(mon), 48, "6 hits")
			T.eq(j:GetAttribute("Ammo"), 0, "empty")
			local reloadEnds = j:GetAttribute("ReloadEndsAt")
			T.ok(near(reloadEnds - H.now(), 1.6, 0.01), "reload mirrored")
			T.ok(near(AS.GetCooldowns(j).Revolver, reloadEnds, 0.01), "reload = Revolver cooldown")
			H.advance(0.4)
			local ok, why = AS.CastAs(j, "Revolver", { aim = Vector3.new(0, 3, -10) })
			T.ok(not ok and why == "cooldown", "no shot mid-reload")
			H.advance(1.3)
			T.eq(j:GetAttribute("Ammo"), 6, "reloaded")
			T.eq(j:GetAttribute("ReloadEndsAt"), 0, "reload done")
			local ammo, max = kit.Ammo(j)
			T.ok(ammo == 6 and max == 6, "Kit.Ammo")
			-- SharpEye: +15 % beyond 30 studs
			local far = H.spawn("FellSans", "Monster", Vector3.new(30, 0, -30))
			local f0 = H.hp(far)
			T.ok(AS.CastAs(j, "Revolver", { aim = Vector3.new(30, 3, -30) }), "long shot")
			T.ok(near(f0 - H.hp(far), 8 * 1.15, 1e-3), "SharpEye bonus " .. tostring(f0 - H.hp(far)))
			T.eq(H.fx("Revolver", "Shot")[7].data.long, true, "long flag")
			-- walls stop bullets
			H.wallX = 5
			local behind = H.spawn("FellSans", "Monster", Vector3.new(10, 0, 0))
			local b0 = H.hp(behind)
			H.advance(0.4)
			T.ok(AS.CastAs(j, "Revolver", { aim = Vector3.new(10, 3, 0), dir = Vector3.new(1, 0, 0) }), "shot at wall")
			T.eq(H.hp(behind), b0, "the wall took the bullet")
		end)
	end,

	justice_fan_roll_verdict = function(T, Loader)
		withHarness(T, Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local j = H.spawn("Justice", "Humans", Vector3.zero, { ult = 100 })
			local mon = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -8), { hp = 600 })
			local hp0 = H.hp(mon)
			T.ok(AS.CastAs(j, "FanTheHammer", { aim = Vector3.new(0, 3, -8) }), "fan")
			T.eq(#H.fx("FanTheHammer", "Shot"), 6, "a full cylinder")
			T.eq(hp0 - H.hp(mon), 48, "6 x 8 in the cone")
			T.eq(j:GetAttribute("Ammo"), 0, "cylinder emptied")
			T.ok(j:GetAttribute("ReloadEndsAt") > H.now(), "reloading after the fan")
			-- QuickRoll: instant reload + primed shot
			T.ok(AS.CastAs(j, "QuickRoll", { aim = Vector3.new(12, 3, 0), dir = Vector3.new(1, 0, 0) }), "roll")
			T.eq(j:GetAttribute("Ammo"), 6, "instant reload")
			T.eq(j:GetAttribute("ReloadEndsAt"), 0, "reload cleared")
			T.ok((AS.GetCooldowns(j).Revolver or 0) <= H.now() + 1e-6, "revolver ready")
			T.ok(SS.Has(j, "Primed") and SS.Has(j, "IFrames"), "primed + roll i-frames")
			T.ok(j.PrimaryPart:FindFirstChild("SV_Mover") ~= nil, "roll movement")
			H.advance(0.3)
			j.PrimaryPart.CFrame = H.HazardDefs.LookAlong(Vector3.new(0, 3, 0), Vector3.new(0, 0, -1))
			local hp1 = H.hp(mon)
			T.ok(AS.CastAs(j, "Revolver", { aim = Vector3.new(0, 3, -8) }), "primed shot")
			T.eq(hp1 - H.hp(mon), 12, "x1.5 next shot")
			T.ok(not SS.Has(j, "Primed"), "consumed")
			-- Final Verdict: undodgeable beam, drains every dodge
			local judge = H.spawn("FellSans", "Monster", Vector3.new(-40, 0, -40), { dodges = 3, hp = 600 })
			local judgeHp = H.hp(judge)
			T.ok(AS.CastAs(j, "FinalVerdict", { aim = Vector3.new(-40, 3, -40) }), "verdict")
			T.ok(near(judgeHp - H.hp(judge), 45 * 1.15, 1e-4), "beam damage (+SharpEye)")
			T.eq(judge:GetAttribute("Dodges"), 0, "all dodges drained")
			T.ok(SS.Has(judge, "Exhausted"), "exhausted")
			T.eq(#H.fx("FinalVerdict", "Fire"), 1, "Fire fx")
			T.ok(SS.Has(j, "Verdict"), "caster ult status (SOUL glow)")
		end)
		withHarness(T, Loader, function(H)
			local AS, SS = H.S.AbilityService, H.S.StatusService
			local j = H.spawn("Justice", "Humans", Vector3.zero, { ult = 100 })
			local a = H.spawn("ClassicSans", "Monster", Vector3.new(0, 0, -50), { hp = 600 })
			local b = H.spawn("FellSans", "Monster", Vector3.new(30, 0, -50), { hp = 600 })
			local a0, b0 = H.hp(a), H.hp(b)
			-- the laser tracks the live aim (turn-rate limited) until the lock
			H.Validation.SetService("AimService", {
				GetAim = function()
					return Vector3.new(30, 3, -50)
				end,
			})
			T.ok(AS.CastAs(j, "FinalVerdict", { aim = Vector3.new(0, 3, -50) }), "verdict tracked")
			T.ok(#H.fx("FinalVerdict", "Track") >= 2, "Track fx")
			T.eq(H.hp(a), a0, "left the first aim")
			T.ok(H.hp(b) < b0, "followed the aim onto the second target")
			-- cancelled when stunned while aiming
			j:SetAttribute("Ult", 100)
			AS.ResetCooldowns(j)
			H.Validation.SetService("AimService", false)
			H.after(0.5, function()
				SS.Apply(j, "Stunned", 1)
			end)
			local b1 = H.hp(b)
			T.ok(AS.CastAs(j, "FinalVerdict", { aim = Vector3.new(30, 3, -50) }), "verdict 2")
			T.eq(H.hp(b), b1, "no beam")
			T.ok(#H.fx("FinalVerdict", "Cancel") >= 1, "Cancel fx")
		end)
	end,

	---------------------------------------------------------------------------------------------
	-- Client kits + strings

	client_kits_shape = function(T, Loader)
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		local HV = Loader.require(CLIENT .. "Controllers.HazardVisuals")
		for _, id in { "Perseverance", "Kindness", "Justice" } do
			local ok, mod = pcall(Loader.require, CLIENT .. "Kits." .. id)
			T.ok(ok and type(mod) == "table", id .. " client kit loads: " .. tostring(mod))
			if ok then
				for _, ability in Kits.Get(id).Abilities do
					T.ok(type(mod.Effects[ability.Id]) == "function", id .. " Effects." .. ability.Id)
				end
				T.ok(type(mod.OnCharacter) == "function", id .. " OnCharacter")
				T.ok(type(mod.Predict) == "table", id .. " Predict")
			end
		end
		T.ok(HV.HasVisual("SpellPage"), "SpellPage visual registered")
		T.ok(HV.HasVisual("HomeCooking"), "HomeCooking zone visual registered")
		local P = Loader.require(CLIENT .. "Kits.Perseverance")
		local K = Loader.require(CLIENT .. "Kits.Kindness")
		T.ok(type(P.Indicator.FinalChapter) == "function", "FinalChapter indicator")
		T.ok(type(K.Indicator.HomeCooking) == "function" and type(K.Indicator.KindShield) == "function", "Kindness indicators")
		local strings = Loader.require("ReplicatedStorage.Shared.Strings.KitHumansB")
		for key, v in strings do
			T.ok(type(v.en) == "string" and v.en ~= "" and type(v.ru) == "string" and v.ru ~= "", key .. " en + ru")
		end
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		T.eq(Strings.L("fx.kindness.bonk"), "BONK!", "merged into Strings")
	end,

	client_effects_smoke = function(T, Loader)
		local S = clientSmoke(Loader)
		local ok, err = pcall(function()
			local me = S.stubModel("Me", Vector3.new(0, 3, 0))
			local mon = S.stubModel("Mon", Vector3.new(0, 3, -20))
			local ally = S.stubModel("Ally", Vector3.new(4, 3, 0))
			S.chars = { me, mon, ally }
			me:SetAttribute("Team", "Humans")
			ally:SetAttribute("Team", "Humans")
			mon:SetAttribute("Team", "Monster")
			me:SetAttribute("Status_Chapter", 105)
			me:SetAttribute("Status_Feast", 105)
			me:SetAttribute("Status_Verdict", 105)
			me:SetAttribute("Status_Primed", 105)
			ally:SetAttribute("Status_Shielded", 104)
			ally:SetAttribute("Shield", 40)
			local enemies = { [mon] = true }
			local from, to = Vector3.new(0.8, 3.6, -1.4), Vector3.new(0, 3, -20)
			local cases = {
				Perseverance = {
					NotebookSwat = { { "Start", { combo = 3 } }, { "Strike", { combo = 3, last = true, hits = 1 } } },
					SpellboundPages = { { "Start", {} }, { "Stream", { count = 5, interval = 0.08 } }, { "Bind", { target = mon, duration = 1 } } },
					Rewrite = {
						{ "Start", {} },
						{ "Rewind", { from = from, path = { Vector3.new(5, 3, 0), Vector3.new(3, 3, 0), from }, heal = 20 } },
						{ "Teleport", { from = from, to = Vector3.new(5, 3, 0) } },
					},
					FinalChapter = {
						{ "Start", {} },
						{ "Summon", { target = mon, pos = to, delay = 0.8, lockAt = 0.48, radius = 7.5 } },
						{ "Lock", { pos = to } },
						{ "Slam", { pos = to - Vector3.new(0, 3, 0), hits = { mon }, silence = 3 } },
						{ "Summon", { target = mon, pos = to, delay = 0.8, lockAt = 0.48, radius = 7.5 } },
						{ "Cancel", {} },
					},
				},
				Kindness = {
					PanBonk = { { "Start", { combo = 2 } }, { "Bonk", { targets = { mon }, daze = 0.4 } } },
					HomeCooking = { { "Start", {} }, { "Throw", { from = from, to = Vector3.new(0, 0, -12), time = 0.4, radius = 9 } } },
					KindShield = { { "Start", {} }, { "Shield", { target = ally, duration = 5, amount = 40 } } },
					ButterscotchFeast = { { "Start", {} }, { "Feast", { radius = 30, allies = { me, ally }, revived = ally, heal = 45 } } },
				},
				Justice = {
					Revolver = { { "Start", {} }, { "Shot", { from = from, to = to, hit = mon, long = true, primed = true } } },
					FanTheHammer = { { "Start", {} }, { "Fan", { count = 6, interval = 0.07, cone = 12 } }, { "Shot", { from = from, to = to, fan = true, ammo = 3 } } },
					QuickRoll = { { "Start", {} }, { "Roll", { from = from, to = from + Vector3.new(12, 0, 0), time = 0.28 } } },
					FinalVerdict = {
						{ "Start", {} },
						{ "Aim", { dir = Vector3.new(0, 0, -1), time = 1.2, lock = 0.25, length = 120, width = 3 } },
						{ "Track", { dir = Vector3.new(0.2, 0, -0.98).Unit } },
						{ "Lock", { dir = Vector3.new(0.2, 0, -0.98).Unit } },
						{ "Fire", { from = from, to = to, width = 3, hits = { mon } } },
						{ "Aim", { dir = Vector3.new(0, 0, -1), time = 1.2, lock = 0.25, length = 120, width = 3 } },
						{ "Cancel", {} },
					},
				},
			}
			for kitId, abilities in cases do
				local mod = Loader.require(CLIENT .. "Kits." .. kitId)
				for _, isLocal in { true, false } do
					local fx = S.fx(me, isLocal, enemies)
					for abilityId, phases in abilities do
						for _, ph in phases do
							fx.Predicted = false
							S.run(kitId .. "." .. abilityId .. "." .. ph[1], mod.Effects[abilityId], fx, {
								caster = me, kit = kitId, ability = abilityId, phase = ph[1], castId = 7, t0 = 99.5, data = ph[2],
							})
						end
						local pred = mod.Predict[abilityId]
						if pred then
							S.run(kitId .. ".Predict." .. abilityId, pred, fx, { aim = to, dir = Vector3.new(0, 0, -1), castId = 8 })
						end
						local ind = mod.Indicator[abilityId]
						if ind then
							S.run(kitId .. ".Indicator." .. abilityId, function()
								local h = ind(fx)
								h:Update(to, 0.5, mon)
								h:Update(to, 0.5, nil)
								h:Destroy()
							end)
						end
					end
					S.run(kitId .. ".OnCharacter", mod.OnCharacter, fx, me)
				end
				for name, builder in mod.Visuals or {} do
					S.run(kitId .. ".Visual." .. name, function()
						local v = builder({ Lib = S.Lib, Color = Color3.new(1, 0, 1), Rule = "Purple", Size = 9, Params = {} })
						v:Update(CFrame.new(0, 3, -5), 0.5, 1 / 60)
						v:Update(CFrame.new(0, 3, -6), 0.6, 1 / 60)
						if v.Impact then
							v:Impact(Vector3.new(0, 3, -6))
						end
						v:Destroy()
					end)
				end
			end
		end)
		S.restore()
		T.ok(ok, "smoke harness: " .. tostring(err))
		for _, e in S.errors do
			T.ok(false, e)
		end
		T.ok(S.calls > 50, "effects drew something (" .. S.calls .. " VFX calls)")
	end,
}
