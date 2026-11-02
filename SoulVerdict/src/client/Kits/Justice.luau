--!strict
-- Client kit: Justice (yellow SOUL) — "The Gunslinger" (SPEC §9.1). Visuals for every AbilityFx phase of
-- src/server/Kits/Justice.luau (the muzzle offset below matches the server's MUZZLE_* constants):
--   Revolver       Predict: muzzle flash + tracer to the aim point + brass; Shot {from, to, hit, long, primed, fan}:
--                  remote clients draw flash + tracer, everyone sees the impact (gold hit-marker ring for SharpEye
--                  long shots, a big burst for a primed shot, wall sparks on a miss)
--   FanTheHammer   Fan {count, interval, cone}: the Shoot clip re-fired per round + hammer-fanning arcs; Shot {fan}:
--                  full tracer per round (server-timed, also for the caster)
--   QuickRoll      Roll {from, to, time}: dust kick, afterimages along the roll, cylinder-spin glint + PRIMED popup
--   FinalVerdict   Aim {dir, time, lock, length, width}: a yellow laser sight from the muzzle (stops on walls and
--                  characters, dot + light at the end) eases toward Track {dir}; Lock {dir}: blinks white-hot; Fire
--                  {from, to, width, hits}: 3-layer golden beam, rings racing down it, GUILTY popups, shake / flash;
--                  Cancel: laser off. The aim pose holds (looped Shoot clip + SetAim) while aiming.
-- OnCharacter: faint SOUL-yellow heart at the Chest attachment while the ult status "Verdict" lasts; Reload clip +
--   glint whenever ReloadEndsAt starts a reload (RELOAD popup for the local gunslinger); a gold glow on the gun hand
--   while "Primed"; SharpEye — the local gunslinger sees a small gold diamond over enemies beyond LongRange studs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any

type Map = { [string]: any }

local Kit = {}
local Effects: { [string]: (any, Map) -> () } = {}
local Predict: { [string]: (any, Map) -> () } = {}
local Indicator: { [string]: (any) -> Map? } = {}
Kit.Effects = Effects
Kit.Predict = Predict
Kit.Indicator = Indicator

local KIT_ID = "Justice"
local YELLOW = Color3.fromRGB(255, 255, 0)
local GOLD = Color3.fromRGB(255, 213, 74)
local HOT = Color3.fromRGB(255, 251, 220)
local BRASS = Color3.fromRGB(205, 160, 70)
local WHITE = Color3.new(1, 1, 1)
local MUZZLE = CFrame.new(0.85, 0.65, -1.4) -- right, up, forward of the root (server MUZZLE_*)
local ROT_X_TO_LOOK = CFrame.Angles(0, math.pi / 2, 0) -- cylinder X axis along a LookAlong frame's look

local function numbers(abilityId: string): Map
	local def = Kits.Ability(KIT_ID, abilityId)
	return if def and def.Numbers then def.Numbers else {}
end

local function flatOf(v: Vector3?, fallback: Vector3): Vector3
	if v then
		local f = Vector3.new(v.X, 0, v.Z)
		if f.Magnitude > 1e-3 then
			return f.Unit
		end
	end
	return fallback
end

local function muzzle(fx: any, dir: Vector3?): Vector3?
	local r = fx.Root(fx.Character)
	if r == nil then
		return nil
	end
	local flat = flatOf(dir, flatOf(r.CFrame.LookVector, Vector3.new(0, 0, -1)))
	return (fx.VFX.LookAlong(r.Position, flat) * MUZZLE).Position
end

local function asModel(v: any): Model?
	return if typeof(v) == "Instance" and v:IsA("Model") then v else nil
end

---------------------------------------------------------------------------------------------------
-- Faint SOUL heart at the Chest attachment (ult)

local function ultHeart(fx: any, untilTime: number)
	local char = fx.Character
	if char == nil or fx.State.UltHeart then
		return
	end
	local Lib = fx.VFX
	local heart = Lib.Soul(YELLOW, 0.55)
	local parts: { BasePart } = {}
	for _, d in heart:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 0.35
			table.insert(parts, d)
		end
	end
	heart.Parent = Lib.Folder()
	local core = heart.PrimaryPart or parts[1]
	local light = if core then Lib.Light(core, GOLD, 1.2, 7) else nil
	local st = { Dead = false }
	fx.State.UltHeart = st
	local function stop()
		if st.Dead then
			return
		end
		st.Dead = true
		if fx.State.UltHeart == st then
			fx.State.UltHeart = nil
		end
		heart:Destroy()
		if light then
			light:Destroy()
		end
	end
	fx.Trove:Add(stop)
	Lib.Animate(math.max(0.1, untilTime - fx.Now()), function(_a, _dt, elapsed)
		if st.Dead or char.Parent == nil or char:GetAttribute("Dead") == true then
			return true
		end
		local att = fx.Attachment(char, "Chest")
		local r = fx.Root(char)
		if att and r then
			local look = r.CFrame.LookVector
			local beat = math.exp(-((elapsed * 1.8) % 1) * 7)
			heart:PivotTo(Lib.LookAlong(att.WorldPosition + look * 0.35, look))
			for _, p in parts do
				p.Transparency = 0.45 - 0.2 * beat
			end
			if light then
				light.Brightness = 0.8 + 1.6 * beat
			end
		end
		return nil
	end, stop)
end

---------------------------------------------------------------------------------------------------
-- Shots

local function muzzleFlash(fx: any, pos: Vector3, dir: Vector3, big: boolean?)
	local Lib = fx.VFX
	Lib.Flash(pos, GOLD, if big then 2.6 else 1.6, 0.06)
	Lib.Sparks(pos, dir, YELLOW, if big then 8 else 5, 30)
	Lib.Emit("Smoke", pos, 1, { Color = Color3.fromRGB(200, 200, 200) })
end

local function tracer(fx: any, from: Vector3, to: Vector3, primed: boolean?)
	local Lib = fx.VFX
	Lib.Beam(from, to, if primed then 0.3 else 0.16, GOLD, 0.09)
	Lib.Line(from, to, HOT, if primed then 0.09 else 0.05, 0.06)
end

local function impact(fx: any, data: Map, dir: Vector3)
	local Lib = fx.VFX
	local to: Vector3 = data.to
	if asModel(data.hit) then
		local color = if data.long then GOLD else HOT
		Lib.Sparks(to, -dir, color, 8, 22)
		Lib.EmitBurst(to, if data.primed then 3.4 elseif data.long then 2.6 else 1.8, color, 0.12)
		if data.long then
			Lib.Ring(Lib.AxisFrame(to, dir), 1.7, GOLD, 0.22, 0.12)
		end
		if data.primed then
			Lib.Emit("Star", to, 6, { Color = GOLD, Speed = { 4, 10 } })
			fx.Sound("Crit", to, { Volume = 0.8 })
		end
	else
		Lib.Sparks(to, -dir, WHITE, 5, 14)
		Lib.Emit("Dust", to, 2)
	end
end

local function shotFx(fx: any, data: Map, drawTracer: boolean, pitch: number?)
	if typeof(data.from) ~= "Vector3" or typeof(data.to) ~= "Vector3" then
		return
	end
	local from: Vector3, to: Vector3 = data.from, data.to
	local delta = to - from
	local dir = if delta.Magnitude > 1e-3 then delta.Unit else Vector3.new(0, 0, -1)
	if drawTracer then
		muzzleFlash(fx, from, dir, data.primed)
		tracer(fx, from, to, data.primed)
		fx.Sound("Shot", from, { Pitch = pitch or (0.96 + math.random() * 0.08) })
		fx.VFX.Emit("Debris", from, 1, { Color = BRASS })
	end
	impact(fx, data, dir)
end

Effects.Revolver = function(fx: any, packet: Map)
	if packet.phase == "Shot" then
		local predicted = fx.Predicted
		shotFx(fx, packet.data or {}, not predicted)
	end
end

Predict.Revolver = function(fx: any, payload: Map)
	local aim: Vector3? = if typeof(payload.aim) == "Vector3" then payload.aim else nil
	local dir: Vector3? = if typeof(payload.dir) == "Vector3" then payload.dir else nil
	local from = muzzle(fx, dir)
	if from == nil then
		return
	end
	local to = aim or (from + (dir or Vector3.new(0, 0, -1)) * 60)
	local delta = to - from
	if delta.Magnitude < 1 then
		return
	end
	local range = 120
	if delta.Magnitude > range then
		to = from + delta.Unit * range
	end
	muzzleFlash(fx, from, delta.Unit)
	tracer(fx, from, to)
	fx.Sound("Shot", from, { Pitch = 0.96 + math.random() * 0.08 })
	fx.VFX.Emit("Debris", from, 1, { Color = BRASS })
	if fx.IsLocal then
		fx.Kick(-1.2, 0.08)
	end
end

---------------------------------------------------------------------------------------------------
-- Fan the Hammer (Q)

local function hammerGlint(fx: any)
	local hand = fx.Part(fx.Character, "RightHand")
	if hand then
		fx.VFX.EmitBurst(hand.Position, 1.4, GOLD, 0.12)
		fx.VFX.Emit("Spark", hand.Position, 3, { Color = YELLOW })
	end
end

Effects.FanTheHammer = function(fx: any, packet: Map)
	local data = packet.data or {}
	local char = fx.Character
	if packet.phase == "Start" then
		if not fx.Predicted then
			hammerGlint(fx)
		end
	elseif packet.phase == "Fan" then
		local count = if type(data.count) == "number" then math.min(data.count, 12) else 6
		local interval = if type(data.interval) == "number" then data.interval else 0.07
		for i = 0, count - 1 do
			fx.Delay(i * interval, function()
				if char == nil or char.Parent == nil then
					return
				end
				fx.Anim.Play(char, "Shoot", { Speed = 2.6, FadeIn = 0.02, FadeOut = 0.08 })
				local r = fx.Root(char)
				if r then
					-- the off hand fanning the hammer: a quick gold flick over the gun
					fx.VFX.Slash(
						r.CFrame * CFrame.new(0.6, 0.7, -1) * CFrame.Angles(0, 0, math.rad(80)),
						{ Radius = 0.9, From = -60, To = 60, Width = 0.25, Color = GOLD, Core = HOT, Duration = 0.07 }
					)
				end
			end)
		end
	elseif packet.phase == "Shot" then
		shotFx(fx, data, true, 1.05 + (6 - (if type(data.ammo) == "number" then data.ammo else 0)) * 0.03)
	end
end

Predict.FanTheHammer = function(fx: any, _payload: Map)
	hammerGlint(fx)
end

---------------------------------------------------------------------------------------------------
-- Quick Roll (E)

Effects.QuickRoll = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local char = fx.Character
	if packet.phase == "Roll" and typeof(data.from) == "Vector3" then
		local time = if type(data.time) == "number" then data.time else 0.28
		Lib.Dust(data.from - Vector3.new(0, 2.6, 0), 1.8, nil, 8)
		fx.Sound("Dash", data.from)
		for k = 1, 3 do
			fx.Delay(time * k / 3.5, function()
				if char and char.Parent then
					Lib.Afterimage(char, GOLD, 0.3, { Transparency = 0.5 + k * 0.1, MaxParts = 14 })
				end
			end)
		end
		fx.Delay(time, function()
			local hand = fx.Part(char, "RightHand")
			if hand then
				Lib.EmitRing(hand.Position, 1.3, GOLD, 0.18)
				Lib.Emit("Star", hand.Position, 4, { Color = GOLD, Speed = { 2, 5 } })
				fx.Sound("Ding", hand.Position, { Pitch = 1.6, Volume = 0.6 })
			end
			local chest = fx.Chest(char)
			if chest then
				Lib.Text(chest + Vector3.new(0, 2.4, 0), Strings.L("fx.justice.primed"), GOLD, { Kind = "Alert", Scale = 0.85 })
			end
		end)
	end
end

Predict.QuickRoll = function(fx: any, _payload: Map)
	local r = fx.Root(fx.Character)
	if r then
		fx.VFX.Dust(r.Position - Vector3.new(0, 2.6, 0), 1.4, nil, 5)
	end
end

---------------------------------------------------------------------------------------------------
-- Final Verdict (R, ultimate)

type Laser = {
	Dir: Vector3,
	Target: Vector3,
	Locked: boolean,
	Done: boolean,
	Core: BasePart,
	Glow: BasePart,
	Dot: BasePart,
	Light: PointLight?,
}

local function stopLaser(fx: any, castId: number): Laser?
	local lasers = fx.State.Lasers
	local laser: Laser? = if lasers then lasers[castId] else nil
	if laser then
		lasers[castId] = nil
		laser.Done = true
	end
	return laser
end

local function startLaser(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local char = fx.Character
	if char == nil or typeof(data.dir) ~= "Vector3" then
		return
	end
	local castId = packet.castId or 0
	stopLaser(fx, castId)
	local time = if type(data.time) == "number" then data.time else 1.2
	local length = if type(data.length) == "number" then data.length else 120
	local laser: Laser = {
		Dir = data.dir,
		Target = data.dir,
		Locked = false,
		Done = false,
		Core = Lib.Part("Cylinder", Vector3.new(1, 0.09, 0.09), CFrame.new(), YELLOW, Enum.Material.Neon, 0.1),
		Glow = Lib.Part("Cylinder", Vector3.new(1, 0.32, 0.32), CFrame.new(), GOLD, Enum.Material.Neon, 0.78),
		Dot = Lib.Part("Ball", Vector3.one * 0.6, CFrame.new(), YELLOW, Enum.Material.Neon, 0),
		Light = nil,
	}
	laser.Light = Lib.Light(laser.Dot, YELLOW, 2, 8)
	local lasers = fx.State.Lasers or {}
	fx.State.Lasers = lasers
	lasers[castId] = laser
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, Lib.Folder() }
	local W = game:GetService("Workspace")
	fx.Anim.Play(char, "Shoot", { Loop = true, Speed = 0.3, FadeIn = 0.1 })
	fx.Sound("BlasterCharge", fx.Root(char), { Pitch = 1.35 })
	local lastEmit = 0
	Lib.Animate(time + 1.5, function(_a, dt, elapsed)
		if laser.Done or char.Parent == nil or char:GetAttribute("Dead") == true then
			return true
		end
		local k = 1 - math.exp(-(if laser.Locked then 40 else 14) * dt)
		laser.Dir = (laser.Dir:Lerp(laser.Target, k)).Unit
		local dir = laser.Dir
		local from = muzzle(fx, dir)
		if from == nil then
			return true
		end
		local hit = W:Raycast(from, dir * length, params)
		local to = if hit then hit.Position else from + dir * length
		local len = math.max(0.05, (to - from).Magnitude)
		local frame = Lib.LookAlong(from:Lerp(to, 0.5), dir) * ROT_X_TO_LOOK
		local blink = laser.Locked and (math.floor(elapsed * 22) % 2 == 0)
		local width = if laser.Locked then 0.14 else 0.09
		laser.Core.Size = Vector3.new(len, width, width)
		laser.Glow.Size = Vector3.new(len, width * 3.6, width * 3.6)
		laser.Core.CFrame = frame
		laser.Glow.CFrame = frame
		laser.Core.Color = if blink then WHITE else YELLOW
		laser.Glow.Transparency = if laser.Locked then 0.55 else 0.78
		local pulse = 0.6 + 0.4 * math.sin(elapsed * 25)
		laser.Dot.Size = Vector3.one * ((if laser.Locked then 0.9 else 0.6) * (0.85 + 0.3 * pulse))
		laser.Dot.CFrame = CFrame.new(to)
		laser.Dot.Color = if blink then WHITE else YELLOW
		if laser.Light then
			laser.Light.Brightness = 1.5 + 2 * pulse
		end
		fx.Anim.SetAim(char, to)
		if elapsed - lastEmit > 0.05 then
			lastEmit = elapsed
			Lib.Emit("Glow", from, 1, { Color = GOLD })
		end
		return nil
	end, function()
		laser.Done = true
		Lib.Release(laser.Core)
		Lib.Release(laser.Glow)
		Lib.Release(laser.Dot)
		if laser.Light then
			laser.Light:Destroy()
		end
		fx.Anim.Stop(char, "Shoot", 0.2)
		fx.Anim.SetAim(char, nil)
	end)
end

local function verdictBeam(fx: any, data: Map)
	local Lib = fx.VFX
	if typeof(data.from) ~= "Vector3" or typeof(data.to) ~= "Vector3" then
		return
	end
	local from: Vector3, to: Vector3 = data.from, data.to
	local delta = to - from
	if delta.Magnitude < 0.5 then
		return
	end
	local dir = delta.Unit
	local len = delta.Magnitude
	local width = if type(data.width) == "number" then data.width else 3
	local frame = Lib.LookAlong(from:Lerp(to, 0.5), dir) * ROT_X_TO_LOOK
	local layers = {
		{ Part = Lib.Part("Cylinder", Vector3.new(len, 0.1, 0.1), frame, HOT, Enum.Material.Neon, 0), W = 0.45, T = 0 },
		{ Part = Lib.Part("Cylinder", Vector3.new(len, 0.1, 0.1), frame, GOLD, Enum.Material.Neon, 0.2), W = 0.9, T = 0.2 },
		{ Part = Lib.Part("Cylinder", Vector3.new(len, 0.1, 0.1), frame, YELLOW, Enum.Material.Neon, 0.6), W = 1.4, T = 0.6 },
	}
	local light = Lib.Light(layers[1].Part, GOLD, 4, 30)
	Lib.Animate(0.55, function(_a, _dt, elapsed)
		local grow = math.clamp(elapsed / 0.05, 0, 1)
		local fade = math.clamp((elapsed - 0.16) / 0.39, 0, 1)
		local wobble = 1 + 0.06 * math.sin(elapsed * 60)
		for _, layer in layers do
			local w = width * layer.W * grow * (1 - fade * 0.85) * wobble
			layer.Part.Size = Vector3.new(len, math.max(0.05, w), math.max(0.05, w))
			layer.Part.CFrame = frame
			layer.Part.Transparency = layer.T + (1 - layer.T) * fade
		end
		if light then
			light.Brightness = 4 * (1 - fade)
		end
		return nil
	end, function()
		for _, layer in layers do
			Lib.Release(layer.Part)
		end
		if light then
			light:Destroy()
		end
	end)
	-- rings racing down the beam
	for k = 0, 3 do
		fx.Delay(k * 0.04, function()
			local p = from + dir * math.min(len, 4 + k * len / 4)
			Lib.Ring(Lib.AxisFrame(p, dir), width * 1.2, GOLD, 0.3, 0.16)
		end)
	end
	muzzleFlash(fx, from, dir, true)
	Lib.Flash(from, HOT, 5, 0.15)
	Lib.EmitBurst(to, 6, GOLD, 0.25)
	Lib.Sparks(to, -dir, GOLD, 14, 30)
	Lib.Dust(to, 2.5, nil, 8)
	fx.Sound("BlasterFire", from, { Pitch = 1.2 })
	fx.ShakeAt(from:Lerp(to, 0.3), 0.5, 0.3, 50)
	for _, v in (if type(data.hits) == "table" then data.hits else {}) do
		local m = asModel(v)
		local chest = if m then fx.Chest(m) else nil
		if m and chest then
			Lib.Flash(chest, GOLD, 4, 0.2)
			Lib.Text(chest + Vector3.new(0, 2.8, 0), Strings.L("fx.justice.guilty"), GOLD, { Kind = "Alert", Scale = 1.35 })
			fx.Highlight(m, GOLD, 0.6)
			fx.HitStop(m, 0.2)
			if m == fx.LocalCharacter() then
				fx.Screen.Flash(GOLD, 0.35, 0.25)
			end
		end
	end
	if fx.IsLocal then
		fx.Screen.Flash(GOLD, 0.25, 0.15)
		fx.Kick(5, 0.3)
	end
end

Effects.FinalVerdict = function(fx: any, packet: Map)
	local data = packet.data or {}
	local castId = packet.castId or 0
	if packet.phase == "Start" then
		local predicted = fx.Predicted
		if not predicted then
			hammerGlint(fx)
		end
		ultHeart(fx, fx.Now() + (numbers("FinalVerdict").AimTime or 1.2) + 0.8)
		if fx.IsLocal then
			fx.Screen.Pulse("Ult")
		end
	elseif packet.phase == "Aim" then
		startLaser(fx, packet)
	elseif packet.phase == "Track" then
		local lasers = fx.State.Lasers
		local laser: Laser? = if lasers then lasers[castId] else nil
		if laser and typeof(data.dir) == "Vector3" then
			laser.Target = data.dir
		end
	elseif packet.phase == "Lock" then
		local lasers = fx.State.Lasers
		local laser: Laser? = if lasers then lasers[castId] else nil
		if laser then
			if typeof(data.dir) == "Vector3" then
				laser.Target = data.dir
			end
			laser.Locked = true
			local from = muzzle(fx, laser.Dir)
			if from then
				fx.VFX.Flash(from, WHITE, 2.5, 0.12)
				fx.Sound("Charge", from, { Pitch = 1.6 })
			end
		end
	elseif packet.phase == "Fire" then
		stopLaser(fx, castId)
		verdictBeam(fx, data)
	elseif packet.phase == "Cancel" then
		local laser = stopLaser(fx, castId)
		if laser then
			fx.VFX.Emit("Spark", laser.Dot.Position, 4, { Color = YELLOW })
		end
	end
end

Predict.FinalVerdict = function(fx: any, _payload: Map)
	hammerGlint(fx)
end

---------------------------------------------------------------------------------------------------
-- Passive visuals

local function sharpEye(fx: any, character: Model)
	local Lib = fx.VFX
	local longRange = numbers("Revolver").LongRange or 30
	local marks: { [Model]: BasePart } = {}
	local st = { Dead = false }
	local function clear()
		for m, p in marks do
			Lib.Release(p)
			marks[m] = nil
		end
	end
	local function stop()
		if not st.Dead then
			st.Dead = true
			clear()
		end
	end
	fx.Trove:Add(stop)
	Lib.Animate(1e7, function(_a, _dt, elapsed)
		if st.Dead or character.Parent == nil or character:GetAttribute("Dead") == true then
			return true
		end
		local me = fx.Root(character)
		if me == nil then
			clear()
			return nil
		end
		local seen: { [Model]: boolean } = {}
		for _, other in Lib.Characters() do
			if other ~= character and other:GetAttribute("Dead") ~= true and fx.IsEnemy(other) then
				local head = fx.Part(other, "Head") or fx.Root(other)
				if head and (head.Position - me.Position).Magnitude > longRange then
					seen[other] = true
					local mark = marks[other]
					if mark == nil then
						mark = Lib.Part("Block", Vector3.new(0.55, 0.55, 0.12), CFrame.new(), GOLD, Enum.Material.Neon, 0.15)
						marks[other] = mark
					end
					local bob = math.sin(elapsed * 3) * 0.15
					local m: BasePart = mark :: BasePart
					m.CFrame = CFrame.new(head.Position + Vector3.new(0, 2.2 + bob, 0))
						* CFrame.Angles(0, elapsed * 2, 0)
						* CFrame.Angles(0, 0, math.rad(45))
				end
			end
		end
		for m, p in marks do
			if not seen[m] then
				Lib.Release(p)
				marks[m] = nil
			end
		end
		return nil
	end, stop)
end

function Kit.OnCharacter(fx: any, character: Model)
	local Lib = fx.VFX
	-- ult heart
	local function checkUlt()
		local v = character:GetAttribute("Status_Verdict")
		if type(v) == "number" and v > fx.Now() + 0.2 then
			ultHeart(fx, v)
		end
	end
	fx.Trove:Connect(character:GetAttributeChangedSignal("Status_Verdict"), checkUlt)
	checkUlt()
	-- reload: clip + cylinder glint when a reload starts
	local lastReload = 0
	fx.Trove:Connect(character:GetAttributeChangedSignal("ReloadEndsAt"), function()
		local v = character:GetAttribute("ReloadEndsAt")
		if type(v) == "number" and v > fx.Now() + 0.1 and v ~= lastReload then
			lastReload = v
			fx.Anim.Play(character, "Reload", { FadeIn = 0.08 })
			local hand = fx.Part(character, "RightHand")
			if hand then
				Lib.EmitRing(hand.Position, 1, GOLD, 0.25)
				fx.Sound("Cast", hand.Position, { Volume = 0.5, Pitch = 1.5 })
			end
			if fx.IsLocal then
				local chest = fx.Chest(character)
				if chest then
					Lib.Text(chest + Vector3.new(0, 2.2, 0), Strings.L("fx.justice.reload"), HOT, { Scale = 0.7 })
				end
			end
		end
	end)
	-- primed: gold glow on the gun hand
	local glow: ParticleEmitter? = nil
	local function checkPrimed()
		local v = character:GetAttribute("Status_Primed")
		local on = type(v) == "number" and v > fx.Now()
		if on and glow == nil then
			local att = fx.Attachment(character, "RightGrip") or fx.Attachment(character, "RightHand")
			if att then
				glow = Lib.Emitter("Ember", att, { Color = GOLD, Rate = 14 * Lib.ParticleScale() })
			end
		elseif not on and glow then
			local g: ParticleEmitter = glow
			glow = nil
			g.Rate = 0
			fx.Debris(g, 1)
		end
	end
	fx.Trove:Connect(character:GetAttributeChangedSignal("Status_Primed"), checkPrimed)
	fx.Trove:Add(function()
		if glow then
			glow:Destroy()
			glow = nil
		end
	end)
	checkPrimed()
	-- SharpEye: only the local gunslinger needs the long-range marks
	if fx.IsLocal then
		sharpEye(fx, character)
	end
end

return Kit
