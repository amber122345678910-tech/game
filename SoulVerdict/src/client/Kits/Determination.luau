--!strict
-- Client kit: Determination (red SOUL) — "The Fallen" (SPEC §9.1). Visuals for every AbilityFx phase of
-- src/server/Kits/Determination.luau:
--   KnifeCombo        Start {combo}: red-white knife arcs (1 right->left, 2 left->right, 3 rising, 4 wide finisher),
--                     predicted locally; Strike {last, hits}: finisher burst on hit
--   LungingStrike     Start: blade glint; Dash {from, to, time}: red streak, trailing afterimages, dust, end slash
--   Afterimage        Step {from, window}: red ghost left behind for the window; Counter {attacker}: red X slash on
--                     the attacker + "COUNTER" + hit-stop
--   DeterminationUlt  Burst {duration}: big SOUL flash + red shockwave; faint red SOUL glow at the Chest for the
--                     duration (also restored from the Status_Determined attribute by OnCharacter)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any

type Map = { [string]: any }

local Kit = {}
local Effects: { [string]: (any, Map) -> () } = {}
local Predict: { [string]: (any, Map) -> () } = {}
Kit.Effects = Effects
Kit.Predict = Predict
Kit.Indicator = {}

local RED = Color3.fromRGB(255, 30, 40)
local PALE = Color3.fromRGB(255, 220, 220)
local WHITE = Color3.new(1, 1, 1)

local function rootCF(fx: any): CFrame?
	local r = fx.Root(fx.Character)
	return if r then r.CFrame else nil
end

---------------------------------------------------------------------------------------------------
-- Knife combo (M1)

local function knifeSwing(fx: any, combo: number)
	local Lib = fx.VFX
	fx.Delay(0.06, function()
		local cf = rootCF(fx)
		if cf == nil then
			return
		end
		local base = cf * CFrame.new(0, 0.7, 0)
		local i = ((combo - 1) % 4) + 1
		if i == 1 then
			Lib.Slash(
				base * CFrame.Angles(0, 0, math.rad(12)),
				{ Radius = 3.6, From = 80, To = -70, Width = 0.7, Color = RED, Core = PALE, Duration = 0.16 }
			)
		elseif i == 2 then
			Lib.Slash(
				base * CFrame.Angles(0, 0, math.rad(-14)),
				{ Radius = 3.6, From = -80, To = 70, Width = 0.7, Color = RED, Core = PALE, Duration = 0.16 }
			)
		elseif i == 3 then
			Lib.Slash(
				base * CFrame.Angles(0, 0, math.rad(70)),
				{ Radius = 3.8, From = 70, To = -70, Width = 0.75, Color = RED, Core = PALE, Duration = 0.18 }
			)
		else
			Lib.Slash(
				base,
				{
					Radius = 4.6,
					From = 150,
					To = -150,
					Width = 1.2,
					Color = RED,
					Core = WHITE,
					Duration = 0.26,
					Segments = 18,
				}
			)
		end
		local hand = fx.Part(fx.Character, "RightHand")
		if hand then
			Lib.Emit("Mote", hand.Position, 3, { Color = RED })
		end
		fx.Sound(if i == 4 then "KnifeHeavy" else "Knife", fx.Root(fx.Character))
	end)
end

Effects.KnifeCombo = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			knifeSwing(fx, data.combo or 1)
		end
	elseif packet.phase == "Strike" and data.last and (data.hits or 0) > 0 then
		local cf = rootCF(fx)
		if cf then
			local front = (cf * CFrame.new(0, 0.5, -3.5)).Position
			fx.VFX.EmitBurst(front, 4, RED, 0.2)
			fx.VFX.EmitRing(front, 2.6, RED, 0.22, { Axis = cf.LookVector })
		end
	end
end

Predict.KnifeCombo = function(fx: any, _payload: Map)
	local combat = fx.Combat()
	local idx = 1
	if combat and type(combat.ComboIndex) == "function" then
		local ok, i = pcall(combat.ComboIndex)
		if ok and type(i) == "number" and i > 0 then
			idx = i
		end
	end
	knifeSwing(fx, idx)
end

---------------------------------------------------------------------------------------------------
-- Lunging Strike (Q)

local function glint(fx: any)
	local hand = fx.Part(fx.Character, "RightHand")
	if hand then
		fx.VFX.EmitBurst(hand.Position, 2.2, WHITE, 0.15)
		fx.VFX.Emit("Star", hand.Position, 2, { Color = PALE, Speed = { 0.5, 1.5 } })
	end
end

Effects.LungingStrike = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	if packet.phase == "Start" then
		if not fx.Predicted then
			glint(fx)
		end
	elseif packet.phase == "Dash" and typeof(data.from) == "Vector3" and typeof(data.to) == "Vector3" then
		local from: Vector3, to: Vector3 = data.from, data.to
		local time = if type(data.time) == "number" then data.time else 0.22
		local char = fx.Character
		Lib.Dust(from - Vector3.new(0, 2.6, 0), 1.6, nil, 8)
		fx.Sound("Lunge", from)
		-- streak + ghosts that trail the dash
		Lib.Beam(from + Vector3.new(0, 0.5, 0), to + Vector3.new(0, 0.5, 0), 0.5, RED, time + 0.25)
		for k = 1, 3 do
			fx.Delay(time * k / 3.2, function()
				if char and char.Parent then
					Lib.Afterimage(char, RED, 0.32, { Transparency = 0.45 + k * 0.08, MaxParts = 16 })
				end
			end)
		end
		fx.Delay(time, function()
			local cf = rootCF(fx)
			if cf then
				Lib.Slash(
					cf * CFrame.new(0, 0.6, 0),
					{ Radius = 4, From = 100, To = -100, Width = 1, Color = RED, Core = WHITE, Duration = 0.22 }
				)
			end
		end)
	end
end

Predict.LungingStrike = function(fx: any, _payload: Map)
	glint(fx)
end

---------------------------------------------------------------------------------------------------
-- Afterimage (E)

local function leaveGhost(fx: any, window: number)
	local char = fx.Character
	if char == nil then
		return
	end
	-- the ghost stays where the human stood for the whole counter window, then fades
	fx.VFX.Afterimage(char, Color3.fromRGB(255, 90, 100), window + 0.35, { Transparency = 0.3, MaxParts = 28 })
	fx.Sound("Afterimage", fx.Root(char))
end

Effects.Afterimage = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	if packet.phase == "Step" then
		if not fx.Predicted then
			leaveGhost(fx, if type(data.window) == "number" then data.window else 0.5)
		end
		if typeof(data.from) == "Vector3" then
			Lib.Emit("Mote", data.from, 6, { Color = RED })
		end
	elseif packet.phase == "Counter" then
		local attacker: Model? = if typeof(data.attacker) == "Instance" and data.attacker:IsA("Model")
			then data.attacker
			else nil
		local r = if attacker then fx.Root(attacker) else nil
		if r then
			local cf = r.CFrame * CFrame.new(0, 0.6, 0)
			-- red X: two crossing slashes facing the attacker
			local face = Lib.LookAlong(cf.Position, (rootCF(fx) or cf).Position - cf.Position)
			Lib.Slash(
				face * CFrame.Angles(0, 0, math.rad(45)) * CFrame.Angles(math.rad(90), 0, 0),
				{ Radius = 2.6, From = -70, To = 70, Width = 0.9, Color = RED, Core = WHITE, Duration = 0.25 }
			)
			fx.Delay(0.06, function()
				Lib.Slash(
					face * CFrame.Angles(0, 0, math.rad(-45)) * CFrame.Angles(math.rad(90), 0, 0),
					{ Radius = 2.6, From = -70, To = 70, Width = 0.9, Color = RED, Core = WHITE, Duration = 0.25 }
				)
			end)
			Lib.Flash(cf.Position, RED, 4, 0.2)
			Lib.Text(
				cf.Position + Vector3.new(0, 2.2, 0),
				Strings.L("fx.counter"),
				RED,
				{ Kind = "Alert", Scale = 1.15 }
			)
			fx.HitStop(attacker, 0.14)
			fx.HitStop(fx.Character, 0.14)
			fx.Sound("Counter", cf.Position)
			if fx.IsLocal then
				fx.Shake(0.3, 0.2)
				fx.Kick(-4, 0.2)
			end
		end
	end
end

Predict.Afterimage = function(fx: any, _payload: Map)
	leaveGhost(fx, 0.5)
end

---------------------------------------------------------------------------------------------------
-- DETERMINATION (R, ultimate)

local function soulGlow(fx: any, untilTime: number)
	local char = fx.Character
	if char == nil or fx.State.UltGlow then
		return
	end
	local Lib = fx.VFX
	local heart = Lib.Soul(RED, 0.7)
	heart.Parent = Lib.Folder()
	local core = heart.PrimaryPart or heart:FindFirstChildWhichIsA("BasePart", true)
	local light = if core then Lib.Light(core, RED, 1.5, 8) else nil
	local chest = fx.Attachment(char, "Chest")
	local embers = if chest then Lib.Emitter("Ember", chest, { Color = RED, Rate = 10 * Lib.ParticleScale() }) else nil
	local st = { Dead = false }
	fx.State.UltGlow = st
	local function stop()
		if st.Dead then
			return
		end
		st.Dead = true
		if fx.State.UltGlow == st then
			fx.State.UltGlow = nil
		end
		heart:Destroy()
		if embers then
			embers.Rate = 0
			fx.Debris(embers, 1.5)
		end
		if light then
			light:Destroy()
		end
	end
	fx.Trove:Add(stop)
	Lib.Animate(math.max(0.1, untilTime - fx.Now()), function(_a, _dt, elapsed)
		if st.Dead or char.Parent == nil or char:GetAttribute("Dead") == true then
			return true
		end
		local pos = fx.Chest(char)
		if pos then
			local r = fx.Root(char)
			local look = if r then r.CFrame.LookVector else Vector3.new(0, 0, -1)
			-- faint SOUL glow just in front of the chest, beating
			local beat = (elapsed * 1.6) % 1
			local k = math.exp(-beat * 8)
			heart:PivotTo(Lib.LookAlong(pos + look * 0.45, look))
			if light then
				light.Brightness = 1 + 2.5 * k
			end
		end
		return nil
	end, stop)
end

Effects.DeterminationUlt = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase ~= "Burst" then
		return
	end
	local Lib = fx.VFX
	local char = fx.Character
	local pos = if char then fx.Chest(char) else nil
	local duration = if type(data.duration) == "number" then data.duration else 8
	if pos then
		-- the SOUL bursts out, big, then settles at the chest
		local big = Lib.Soul(RED, 2.4)
		big.Parent = Lib.Folder()
		local r = fx.Root(char)
		local look = if r then r.CFrame.LookVector else Vector3.new(0, 0, -1)
		Lib.Animate(0.45, function(a)
			big:PivotTo(Lib.LookAlong(pos + Vector3.new(0, 1.2 * (1 - a), 0) + look * 0.6, look))
			return nil
		end, function()
			big:Destroy()
		end)
		Lib.Flash(pos, RED, 6, 0.35)
		Lib.Shockwave(pos - Vector3.new(0, 2.6, 0), 9, RED, 0.5, { Dust = true })
		Lib.Emit("Star", pos, 18, { Color = RED, Speed = { 6, 14 } })
		fx.Sound("Determination", pos)
		fx.ShakeAt(pos, 0.35, 0.3, 26)
	end
	if fx.IsLocal then
		fx.Screen.Pulse("Ult")
		fx.Screen.Tint(Color3.fromRGB(255, 120, 120), 0.18, 0.8, 0.3)
	end
	soulGlow(fx, fx.Now() + duration)
end

Predict.DeterminationUlt = function(fx: any, _payload: Map)
	local pos = fx.Chest(fx.Character)
	if pos then
		fx.VFX.EmitBurst(pos, 3, RED, 0.2)
	end
end

---------------------------------------------------------------------------------------------------
-- Passive: restore the ult glow from the replicated status (late joiners, missed packets)

function Kit.OnCharacter(fx: any, character: Model)
	local function check()
		local v = character:GetAttribute("Status_Determined")
		if type(v) == "number" and v > fx.Now() + 0.2 then
			soulGlow(fx, v)
		end
	end
	fx.Trove:Connect(character:GetAttributeChangedSignal("Status_Determined"), check)
	check()
end

return Kit
