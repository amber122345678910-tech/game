--!strict
-- Client kit: Fell Sans — "The Executioner" (SPEC §9.1). Visuals for every AbilityFx phase the server kit
-- (src/server/Kits/FellSans.luau) broadcasts. Hazards (the blaster beams, the red spikes, the chain projectile)
-- are drawn by HazardVisuals from their own packets, so what you see is what hits you; this module adds the
-- caster-side flavour around them. Identity: crimson / black, gold glints, heavier camera shake, sparks.
--
--   BoneCleaver     Start/Predict: Props BoneSword summoned into the right hand (kept through the combo, with a
--                   blade Trail) + a crimson arc per hit matching Slash1-4; Strike {last, hits}: finisher crater
--   CrimsonBlaster  Start/Predict: both eyes flare + summoning burst at the blaster slot; Summon {hazard, origin}:
--                   sigil ring, then (at fire time) muzzle flash, sparks along the beam, impact crater, shake;
--                   Fizzle: the skull cracks apart. Indicator: ghost Fell blaster + exact beam line / shell
--   ChainGrab       RegisterVisual "FellChain": Props.Chain of red bones unspooling from the right hand to the hook
--                   (glowing head >= hitbox); Grab {target, time}: the same chain reels the human in (highlight,
--                   clank, local victim screen hit); Snap: the chain shatters. Indicator: throw line + hook ring
--   BoneRush        Start/Predict: crouch burst; Rush {from, to, time, spikeDelay}: crimson afterimages, ground
--                   scrape sparks along the path, eruption shake. Indicator: exact spike lane (2 x SpikeRadius)
--   Bloodlust       Start/Predict: roar burst; Rage: "NO MERCY", local red vignette; the aura (embers, smoke,
--                   outline, light, blazing eyes) follows the Status_Rage attribute (OnCharacter);
--                   Siphon {target, amount}: blood motes stream from the victim to Fell
--   Lunge           Predict/Dash {from, to}: crimson afterimages, dust, streak. Indicator: lane
--   Execution       Start/Predict: eyes blaze, "EXECUTION", BloodFellFinal sky for nearby players;
--                   Mark {targets, lock}: rotating crimson target marks over every marked human (local victim:
--                   vignette + "MARKED"); Drop {points, delay, width}: each mark slams onto the ground as the exact
--                   beam footprint filling to the rim at fire time, then crater + heavy shake; Cancel: marks break;
--                   Executed {target}: gold "EXECUTED". Indicator: radius ring + preview marks
--   GoldTooth       Glint {target}: gold glint at the tooth + gold sparks on the victim ("BRUTAL")
-- OnCharacter: Rage aura watcher, FinalForm blazing eyes, idle gold-tooth glints. OnDamageFx: lazy-dodge smirk.
-- Kit.Constants mirrors the server kit's geometry (tools/lune/tests/kit_fellsans.spec.luau checks it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Strings = require(Shared:WaitForChild("Strings")) :: any

local ClientRoot = script.Parent.Parent
local Controllers = ClientRoot:WaitForChild("Controllers")
local HazardVisuals = require(Controllers:WaitForChild("HazardVisuals")) :: any
local Lib = require(ClientRoot:WaitForChild("VFX"):WaitForChild("Lib")) :: any

type Map = { [string]: any }

local Kit = {}
local Effects: { [string]: (any, Map) -> () } = {}
local Predict: { [string]: (any, Map) -> () } = {}
local Indicator: { [string]: (any) -> Map? } = {}
Kit.Effects = Effects
Kit.Predict = Predict
Kit.Indicator = Indicator

local KIT_ID = "FellSans"
local CRIMSON = Color3.fromRGB(220, 30, 45)
local BLOOD = Color3.fromRGB(255, 36, 48)
local EMBER = Color3.fromRGB(255, 120, 80)
local HOT = Color3.fromRGB(255, 222, 210)
local DARK = Color3.fromRGB(70, 0, 8)
local GOLD = Color3.fromRGB(255, 200, 61)
local EYE = Color3.fromRGB(255, 42, 42)
local NEON = Enum.Material.Neon
local PARK = CFrame.new(0, 25000, 0)

-- Mirrors src/server/Kits/FellSans.luau Kit.Constants (geometry the client draws).
local C = {
	BlasterSlot = { 2.4, 4.4, 1.8 },
	ChainRadius = 1.1,
	ChainMaxSlope = 0.47,
	SpikeRadius = 2.6,
	RushTime = 0.24,
	LungeTime = 0.16,
	ExecLock = 0.5,
	ExecWidth = 6,
}
Kit.Constants = C

local SWORD_SCALE = 1.7 -- the 2.7-stud Props BoneSword becomes a ~4.6-stud cleaver (reach ~ the 7-stud M1 box)
local SWORD_TILT = CFrame.Angles(math.rad(-20), 0, 0) -- Weapons grip convention (HumanCommon.HoldWeapon)
local CHAIN_LINKS = 24
local CHAIN_SCALE = 1.8
-- Combo hit frames (Anim/Clips/Skeleton Slash1..4 "Hit" markers) and the arc of each swing.
local SWING_HIT = { 0.12, 0.12, 0.13, 0.21 }

---------------------------------------------------------------------------------------------------
-- Helpers

local function numbers(abilityId: string): Map
	local a = Kits.Ability(KIT_ID, abilityId)
	return if a and a.Numbers then a.Numbers else {}
end

local function asModel(v: any): Model?
	if typeof(v) == "Instance" and v:IsA("Model") then
		return v
	end
	return nil
end

local function rootCF(fx: any, model: Model?): CFrame?
	local r = fx.Root(model or fx.Character)
	return if r then r.CFrame else nil
end

local function flat(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		local g = Vector3.new(fallback.X, 0, fallback.Z)
		return if g.Magnitude > 1e-3 then g.Unit else Vector3.new(0, 0, -1)
	end
	return f.Unit
end

local function feetOf(fx: any, model: Model?): Vector3?
	local r = fx.Root(model or fx.Character)
	if r == nil then
		return nil
	end
	return Lib.Ground(r.Position, 12) or (r.Position - Vector3.new(0, 2.9, 0))
end

local function localRoot(): BasePart?
	local lp = Players.LocalPlayer
	local c = lp and lp.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function nearLocal(pos: Vector3, radius: number): boolean
	local r = localRoot()
	return r ~= nil and (r.Position - pos).Magnitude <= radius
end

local function text(key: string, ...: any): string
	local ok, s = pcall(Strings.L, key, ...)
	return if ok and type(s) == "string" then s else key
end

-- The skin's eye colour, read once per character before any flare (EyeFlame tints the pupil while lit).
local function eyeColor(fx: any, character: Model?): Color3
	local cached = fx.State.EyeColor
	if typeof(cached) == "Color3" then
		return cached
	end
	local p = fx.Part(character or fx.Character, "LeftPupil")
	local c = if p then p.Color else EYE
	fx.State.EyeColor = c
	return c
end

local function raging(character: Model?): boolean
	if character == nil then
		return false
	end
	local v = character:GetAttribute("Status_Rage")
	return type(v) == "number" and v > Lib.Now()
end

-- Both eye lights blaze for `seconds` (kept on while Rage / FinalForm hold them).
local function eyeFlare(fx: any, seconds: number)
	local char: Model? = fx.Character
	if char == nil then
		return
	end
	local st = fx.State
	local now = os.clock()
	st.EyeUntil = math.max(st.EyeUntil or 0, now + seconds)
	local color = eyeColor(fx, char)
	fx.EyeGlow(char, "Both", color, true)
	fx.Delay(seconds + 0.02, function()
		if os.clock() + 0.01 < (st.EyeUntil or 0) then
			return
		end
		if char:GetAttribute("FinalForm") == true or raging(char) then
			return
		end
		fx.EyeGlow(char, "Both", color, false)
	end)
end

local function graphics(): any?
	local m = Controllers:FindFirstChild("GraphicsController")
	if m and m:IsA("ModuleScript") then
		local ok, g = pcall(require, m)
		if ok and type(g) == "table" then
			return g
		end
	end
	return nil
end

-- Pooled neon parts placed every frame; returns { Parts, Place(cfs), Release() }.
local function partSet(count: number, shape: string, size: Vector3, color: Color3, transparency: number): Map
	local parts: { BasePart } = table.create(count)
	for i = 1, count do
		parts[i] = Lib.Part(shape, size, PARK, color, NEON, transparency)
	end
	local set: Map = { Parts = parts }
	function set.Place(cfs: { CFrame })
		game:GetService("Workspace"):BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	function set.SetTransparency(t: number)
		for _, p in parts do
			p.Transparency = t
		end
	end
	function set.Release()
		for _, p in parts do
			Lib.Release(p)
		end
		table.clear(parts)
	end
	return set
end

-- Heavy hit punctuation: crater ring, debris, sparks, flash and a distance-scaled shake.
local function impact(fx: any, pos: Vector3, radius: number, shake: number)
	local ground = Lib.Ground(pos + Vector3.new(0, 2, 0), 8) or pos
	Lib.Shockwave(ground, radius, CRIMSON, 0.4, { Dust = true })
	Lib.Emit("Debris", ground + Vector3.new(0, 0.4, 0), math.floor(radius * 2), { Color = Color3.fromRGB(60, 50, 50) })
	Lib.Sparks(ground + Vector3.new(0, 0.6, 0), Vector3.yAxis, EMBER, math.floor(radius * 2.5), 26)
	Lib.Emit("Spark", ground + Vector3.new(0, 0.8, 0), 4, { Color = GOLD, Speed = { 14, 24 } })
	Lib.Flash(ground + Vector3.new(0, 1, 0), BLOOD, radius * 0.9, 0.18)
	fx.ShakeAt(ground, shake, 0.32, radius * 7)
end

---------------------------------------------------------------------------------------------------
-- Bone Cleaver (M1): the summoned bone sword + crimson arcs

local function swordState(fx: any): Map?
	local char: Model? = fx.Character
	if char == nil then
		return nil
	end
	local st: Map? = fx.State.Sword
	if st and st.Model.Parent ~= nil then
		return st
	end
	local BoneSword = Lib.Prop("BoneSword")
	if BoneSword == nil then
		return nil
	end
	local ok, model = pcall(BoneSword.Build, nil, true)
	if not ok or typeof(model) ~= "Instance" then
		return nil
	end
	local PartKit = require(Shared:WaitForChild("Rigs"):WaitForChild("PartKit")) :: any
	PartKit.ScaleModel(model, SWORD_SCALE)
	local parts: { BasePart } = {}
	local rest: { CFrame } = {}
	local base: { number } = {}
	local blade: BasePart? = nil
	local core: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(rest, d.CFrame)
			table.insert(base, d.Transparency)
			d.Transparency = 1
			d.CastShadow = false
			if d.Name == "Blade" then
				blade = d
			elseif d.Name == "Core" then
				core = d
			end
		end
	end
	local trail: Trail? = nil
	if blade then
		local b: BasePart = blade
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailBase"
		a0.Position = Vector3.new(0, 0, b.Size.Z * 0.5)
		a0.Parent = b
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailTip"
		a1.Position = Vector3.new(0, 0, -b.Size.Z * 0.5 - 0.42 * SWORD_SCALE)
		a1.Parent = b
		local t = Instance.new("Trail")
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Color = ColorSequence.new(HOT, CRIMSON)
		t.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.6, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		t.Lifetime = 0.14
		t.MinLength = 0.05
		t.LightEmission = 1
		t.LightInfluence = 0
		t.FaceCamera = false
		t.Brightness = 3
		t.Texture = ""
		t.Enabled = false
		t.Parent = b
		trail = t
	end
	model.Parent = Lib.Folder()
	local s: Map = {
		Model = model,
		Parts = parts,
		Rest = rest,
		Base = base,
		Cfs = table.create(#parts),
		Trail = trail,
		Core = core,
		Light = nil,
		ShowAt = 0,
		Until = 0,
		Alpha = 0,
		TrailUntil = 0,
		Running = false,
	}
	fx.State.Sword = s
	fx.Trove:Add(function()
		s.Running = false
		if s.Light then
			s.Light:Destroy()
		end
		model:Destroy()
	end)
	return s
end

local function setSwordAlpha(s: Map, alpha: number)
	if alpha == s.Alpha or (math.abs(alpha - s.Alpha) < 0.02 and alpha > 0 and alpha < 1) then
		return
	end
	s.Alpha = alpha
	for i, p in s.Parts do
		local b = s.Base[i]
		p.Transparency = b + (1 - b) * (1 - alpha)
	end
end

local function runSword(fx: any, s: Map)
	if s.Running then
		return
	end
	s.Running = true
	local char: Model = fx.Character
	local W = game:GetService("Workspace")
	Lib.Animate(1e6, function()
		if not s.Running or char.Parent == nil or s.Model.Parent == nil then
			return true
		end
		local now = os.clock()
		local hand = fx.Part(char, "RightHand")
		if hand == nil or char:GetAttribute("Dead") == true then
			s.Until = 0
		end
		local alpha: number
		if now > s.Until then
			alpha = 1 - math.clamp((now - s.Until) / 0.2, 0, 1)
		else
			alpha = math.clamp((now - s.ShowAt) / 0.07, 0, 1)
		end
		if hand then
			local att = hand:FindFirstChild("RightGrip")
			local grip = hand.CFrame
				* (if att and att:IsA("Attachment") then att.CFrame else CFrame.new(0, -0.3, 0))
				* SWORD_TILT
			for i, r in s.Rest do
				s.Cfs[i] = grip * r
			end
			W:BulkMoveTo(s.Parts, s.Cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		setSwordAlpha(s, alpha)
		if s.Trail then
			s.Trail.Enabled = now < s.TrailUntil and alpha > 0.5
		end
		if alpha <= 0 and now > s.Until then
			-- dismissed: a few dark-red motes where the blade was, then park it
			local core: BasePart? = s.Core
			if core and core.Position.Y < 20000 then
				Lib.Emit("Mote", core.Position, 6, { Color = CRIMSON })
			end
			if s.Light then
				s.Light:Destroy()
				s.Light = nil
			end
			for _, p in s.Parts do
				p.CFrame = PARK
			end
			s.Running = false
			return true
		end
		return nil
	end, function()
		s.Running = false
	end)
end

local function summonSword(fx: any, hitT: number)
	local s = swordState(fx)
	if s == nil then
		return
	end
	local now = os.clock()
	local window = numbers("BoneCleaver").ComboWindow or 0.9
	if now > s.Until then
		s.ShowAt = now
		local hand = fx.Part(fx.Character, "RightHand")
		if hand then
			Lib.EmitBurst(hand.Position, 3, CRIMSON, 0.22)
			Lib.Emit("Spark", hand.Position, 5, { Color = BLOOD, Speed = { 6, 12 } })
		end
	end
	s.Until = now + window + 0.4
	s.TrailUntil = now + hitT + 0.14
	if s.Light == nil and s.Core then
		s.Light = Lib.Light(s.Core, BLOOD, 1.6, 9)
	end
	runSword(fx, s)
end

local function cleaverSwing(fx: any, combo: number)
	local idx = math.clamp(combo, 1, 4)
	local hitT = SWING_HIT[idx]
	summonSword(fx, hitT)
	local char = fx.Character
	fx.Delay(math.max(0, hitT - 0.04), function()
		local cf = rootCF(fx)
		if cf == nil then
			return
		end
		local base = cf * CFrame.new(0, 0.9, 0)
		local opts: Map
		local tilt: CFrame
		if idx == 1 then -- forward jab
			tilt = CFrame.Angles(0, 0, math.rad(8))
			opts = { Radius = 6.4, From = -22, To = 24, Width = 0.8, Duration = 0.16 }
		elseif idx == 2 then -- backhand, left to right
			tilt = CFrame.Angles(0, 0, math.rad(-14))
			opts = { Radius = 5.8, From = -85, To = 78, Width = 1.1, Duration = 0.2 }
		elseif idx == 3 then -- rising diagonal
			tilt = CFrame.Angles(0, 0, math.rad(68))
			opts = { Radius = 5.8, From = -62, To = 86, Width = 1.2, Duration = 0.2 }
		else -- overhead execution chop
			tilt = CFrame.Angles(0, 0, math.rad(90))
			opts = { Radius = 6.4, From = 118, To = -38, Width = 1.7, Duration = 0.24 }
		end
		opts.Color = CRIMSON
		opts.Core = HOT
		Lib.Slash(base * tilt, opts)
		fx.Sound(if idx == 4 then "Slash" else "Whoosh", fx.Root(char), { Pitch = if idx == 4 then 0.8 else 0.95 })
	end)
end

local function comboIndex(fx: any): number
	local combat = fx.Combat()
	if combat and type(combat.ComboIndex) == "function" then
		local ok, i = pcall(combat.ComboIndex)
		if ok and type(i) == "number" and i > 0 then
			return i
		end
	end
	return 1
end

Effects.BoneCleaver = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			cleaverSwing(fx, if type(data.combo) == "number" then data.combo else 1)
		end
	elseif packet.phase == "Strike" then
		local cf = rootCF(fx)
		if cf == nil then
			return
		end
		local hits = if type(data.hits) == "number" then data.hits else 0
		if data.last then
			impact(
				fx,
				(cf * CFrame.new(0, 0, -4.2)).Position,
				if hits > 0 then 6 else 4.5,
				if hits > 0 then 0.6 else 0.35
			)
			fx.Sound("Slam", (cf * CFrame.new(0, -2, -4)).Position, { Pitch = 0.9 })
		elseif hits > 0 and fx.IsLocal then
			fx.Shake(0.14, 0.12) -- every landed cut thumps the caster's camera
		end
	end
end

Predict.BoneCleaver = function(fx: any, _payload: Map)
	cleaverSwing(fx, comboIndex(fx))
end

---------------------------------------------------------------------------------------------------
-- Crimson Blaster (Q)

local function blasterSlot(origin: Vector3, fwd: Vector3): Vector3
	local right = fwd:Cross(Vector3.yAxis).Unit
	local s = C.BlasterSlot
	return origin + right * s[1] + Vector3.yAxis * s[2] - fwd * s[3]
end
Kit.BlasterSlot = blasterSlot

-- Same aim rule as the server: chest height above nearby ground; too close / behind -> straight ahead.
local function blasterFrame(origin: Vector3, aim: Vector3, look: Vector3): CFrame
	local fwd = flat(aim - origin, look)
	local pos = blasterSlot(origin, fwd)
	local target = aim
	local g = Lib.Ground(aim + Vector3.new(0, 0.5, 0), 3.5)
	if g then
		target = g + Vector3.new(0, 2.5, 0)
	end
	local dir = target - pos
	if dir.Magnitude < 4 or flat(dir, fwd):Dot(fwd) < 0.1 then
		dir = fwd + Vector3.new(0, -0.05, 0)
	end
	return Lib.LookAlong(pos, dir)
end

local fizzled: { [number]: boolean } = {}

local function summonBurst(fx: any, aim: Vector3?)
	local cf = rootCF(fx)
	if cf == nil then
		return
	end
	local fwd = flat(if aim then aim - cf.Position else cf.LookVector, cf.LookVector)
	local pos = blasterSlot(cf.Position, fwd)
	Lib.EmitBurst(pos, 7, CRIMSON, 0.3)
	Lib.EmitRing(pos, 4.2, BLOOD, 0.35, { Axis = fwd, Brightness = 4 })
	Lib.Emit("Ember", pos, 10, { Color = EMBER })
end

Effects.CrimsonBlaster = function(fx: any, packet: Map)
	local data = packet.data or {}
	local phase = packet.phase
	if phase == "Start" then
		if not fx.Predicted then
			eyeFlare(fx, 0.9)
			summonBurst(fx, packet.aim)
		end
		fx.Sound("BlasterSummon", fx.Root(fx.Character), { Pitch = 0.85 })
	elseif phase == "Summon" and typeof(data.origin) == "CFrame" then
		local origin: CFrame = data.origin
		local N = numbers("CrimsonBlaster")
		local delay = N.Delay or 0.45
		local length = N.Length or 80
		local beamTime = N.BeamTime or 0.35
		local t0 = if type(packet.t0) == "number" then packet.t0 else Lib.Now()
		local hazardId = if type(data.hazard) == "number" then data.hazard else 0
		local look = origin.LookVector
		-- rotating sigil behind the skull during the charge
		Lib.Ring(origin * CFrame.new(0, 0, 1.4) * CFrame.Angles(math.pi / 2, 0, 0), 4.6, CRIMSON, delay, 0.35)
		Lib.EmitRing(origin.Position - look * 1.2, 5.5, DARK, delay + 0.1, { Axis = look, Brightness = 2 })
		local waitFor = math.max(0, delay - (Lib.Now() - t0))
		fx.Delay(waitFor, function()
			local hv = fx.Hazards
			if fizzled[hazardId] or (hazardId ~= 0 and hv and hv.Get and hv.Get(hazardId) == nil) then
				fizzled[hazardId] = nil
				return -- interrupted: the hazard was removed before it fired
			end
			local muzzle = origin.Position + look * 1.2
			Lib.Flash(muzzle, HOT, 6, 0.16)
			Lib.EmitBurst(muzzle, 9, BLOOD, 0.25)
			-- where the beam hits the world: a scorched crater
			local W = game:GetService("Workspace")
			local hit = W:Raycast(muzzle, look * length, Lib.RaycastParams())
			local finish = if hit then hit.Position else muzzle + look * length
			if hit then
				impact(fx, hit.Position, 4, 0.45)
			end
			-- sparks spraying off the beam for its whole duration
			local len = (finish - muzzle).Magnitude
			Lib.Animate(beamTime, function(_a, _dt, elapsed)
				if math.floor(elapsed * 30) % 2 == 0 then
					local p = muzzle + look * (math.random() * len)
					Lib.Emit("Spark", p, 2, { Color = if math.random() < 0.25 then GOLD else EMBER, Speed = { 8, 18 } })
				end
				return nil
			end)
			-- heavier shake than Classic for anyone near the line of fire
			local r = localRoot()
			if r then
				local ab = finish - muzzle
				local tt = math.clamp((r.Position - muzzle):Dot(ab) / math.max(1e-3, ab:Dot(ab)), 0, 1)
				local d = (r.Position - (muzzle + ab * tt)).Magnitude
				if d < 24 then
					fx.Shake(0.55 * (1 - d / 24) + 0.15, beamTime + 0.1)
				end
			end
		end)
	elseif phase == "Fizzle" and typeof(data.origin) == "CFrame" then
		if type(data.hazard) == "number" and data.hazard ~= 0 then
			local id: number = data.hazard
			fizzled[id] = true
			task.delay(3, function()
				fizzled[id] = nil
			end)
		end
		local origin: CFrame = data.origin
		Lib.Shatter(origin, 3, Color3.fromRGB(236, 228, 210), 10, { Speed = 12 })
		Lib.Sparks(origin.Position, nil, BLOOD, 14, 18)
		Lib.Text(origin.Position + Vector3.new(0, 2, 0), text("fell.fx.interrupted"), CRIMSON, { Scale = 0.8 })
		fx.Sound("BoneImpact", origin.Position)
	end
end

Predict.CrimsonBlaster = function(fx: any, payload: Map)
	eyeFlare(fx, 0.9)
	summonBurst(fx, if typeof(payload.aim) == "Vector3" then payload.aim else nil)
end

Indicator.CrimsonBlaster = function(fx: any): Map?
	local N = numbers("CrimsonBlaster")
	local width = N.Width or 3.5
	local length = N.Length or 80
	local hv = fx.Hazards
	local ghost = if hv and hv.AcquireBlaster then hv.AcquireBlaster("Fell", width, { Ghost = true }) else nil
	local line = Lib.Part("Cylinder", Vector3.new(1, 0.12, 0.12), PARK, BLOOD, NEON, 0.35)
	local shell = Lib.Part("Cylinder", Vector3.new(1, width, width), PARK, CRIMSON, NEON, 0.9)
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		local cf = rootCF(fx)
		if cf == nil then
			return
		end
		local mcf = blasterFrame(cf.Position, aim, cf.LookVector)
		if ghost then
			ghost:Pose(mcf, 0.1 + 0.06 * math.sin(os.clock() * 9))
			ghost:SetTransparency(0)
		end
		local axis = mcf * CFrame.new(0, 0, -length / 2) * CFrame.Angles(0, math.pi / 2, 0)
		line.Size = Vector3.new(length, 0.12, 0.12)
		line.CFrame = axis
		line.Transparency = 0.3 + 0.15 * math.sin(os.clock() * 10)
		shell.Size = Vector3.new(length, width, width)
		shell.CFrame = axis
	end
	function handle.Destroy(_self: any)
		if ghost then
			ghost:Release()
		end
		Lib.Release(line)
		Lib.Release(shell)
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Chain Grab (E): a chain of red bones (Props.Chain) unspooling from the right hand

type ChainSt = {
	Model: Model,
	Parts: { BasePart },
	Rest: { CFrame },
	Links: { number },
	Base: { number },
	Hidden: { boolean },
	Cfs: { CFrame },
	N: number,
	Pitch: number,
	Scale: number,
}

local chainPool: { ChainSt } = {}
local liveChains: { [Model]: Map } = setmetatable({}, { __mode = "k" }) :: any

local function acquireChain(): ChainSt?
	while #chainPool > 0 do
		local st = table.remove(chainPool) :: ChainSt
		if st.Model.Parent ~= nil then
			return st
		end
	end
	local Chain = Lib.Prop("Chain")
	if Chain == nil then
		return nil
	end
	local ok, model = pcall(Chain.Build, CHAIN_LINKS, Color3.fromRGB(205, 28, 40), CHAIN_SCALE)
	if not ok or typeof(model) ~= "Instance" then
		return nil
	end
	local st: ChainSt = {
		Model = model,
		Parts = {},
		Rest = {},
		Links = {},
		Base = {},
		Hidden = {},
		Cfs = {},
		N = model:GetAttribute("Links") or CHAIN_LINKS,
		Pitch = model:GetAttribute("Pitch") or 0.62 * CHAIN_SCALE,
		Scale = CHAIN_SCALE,
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local i = d:GetAttribute("Link")
			local rest = d:GetAttribute("LinkRest")
			if type(i) == "number" and typeof(rest) == "CFrame" then
				table.insert(st.Parts, d)
				table.insert(st.Rest, rest)
				table.insert(st.Links, i)
				table.insert(st.Base, d.Transparency)
				table.insert(st.Hidden, false)
				d.CastShadow = false
			else
				d.Transparency = 1 -- the anchor knob stays hidden (the hand holds the chain)
				d.CFrame = PARK
			end
		end
	end
	model.Parent = Lib.Folder()
	return st
end

local function hideChain(st: ChainSt)
	for k, p in st.Parts do
		p.Transparency = 1
		st.Hidden[k] = true
		p.CFrame = PARK
	end
end

local function releaseChain(st: ChainSt)
	hideChain(st)
	if #chainPool < 3 then
		table.insert(chainPool, st)
	else
		st.Model:Destroy()
	end
end

-- Lays the chain from the hand to the hook tip: links unspool from the hook back at their rest pitch (the part
-- still "in the hand" is hidden) and stretch evenly once the throw is longer than the chain. `wave` = lateral
-- whip amplitude (studs) travelling along the chain.
local function layChain(st: ChainSt, from: Vector3, to: Vector3, wave: number, t: number)
	local delta = to - from
	local dist = delta.Magnitude
	if dist < 0.05 then
		hideChain(st)
		return
	end
	local dir = delta / dist
	local up = if math.abs(dir.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local right = dir:Cross(up).Unit
	local y = right:Cross(dir).Unit
	local s = st.Scale
	local n = st.N
	local hookCentre = math.max(dist - 0.64 * s, 0.02)
	local avail = math.max(hookCentre - 0.31 * s, 0.01)
	local spacing = math.max(st.Pitch, avail / n)
	for k, part in st.Parts do
		local i = st.Links[k]
		local along = if i > n then hookCentre else avail - (n - i + 0.5) * spacing
		local hidden = along < -0.1
		if hidden ~= st.Hidden[k] then
			st.Hidden[k] = hidden
			part.Transparency = if hidden then 1 else st.Base[k]
		end
		if hidden then
			st.Cfs[k] = PARK
		else
			local f = math.clamp(along / dist, 0, 1)
			local lateral = right * (math.sin(i * 0.8 - t * 26) * wave * 4 * f * (1 - f))
			st.Cfs[k] = CFrame.fromMatrix(from + dir * along + lateral, right, y, -dir) * st.Rest[k]
		end
	end
	game:GetService("Workspace"):BulkMoveTo(st.Parts, st.Cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function handPos(model: Model?): Vector3?
	if model == nil or model.Parent == nil then
		return nil
	end
	local att = model:FindFirstChild("RightGrip", true)
	if att and att:IsA("Attachment") then
		return att.WorldPosition
	end
	local h = model:FindFirstChild("RightHand", true)
	return if h and h:IsA("BasePart") then h.Position else nil
end

-- Projectile visual for the ChainGrab hazard (params.visual = "FellChain").
HazardVisuals.RegisterVisual("FellChain", function(vctx: Map)
	local owner: Model? = if vctx.Packet then asModel(vctx.Packet.owner) else nil
	local params = vctx.Params or {}
	local origin: CFrame = if typeof(params.origin) == "CFrame" then params.origin else CFrame.identity
	local radius = if type(params.radius) == "number" then params.radius else C.ChainRadius
	local st = acquireChain()
	-- glowing hook head: never smaller than the hit ball
	local glow = Lib.Part("Ball", Vector3.one * (radius * 2), PARK, BLOOD, NEON, 0.62)
	local light = Lib.Light(glow, BLOOD, 2.5, 12)
	local live: Map = { St = st, Taken = false, Head = origin.Position }
	if owner then
		liveChains[owner] = live
	end
	local lastSpark = 0
	local v: Map = {}
	function v.Update(_s: any, cf: CFrame, t: number, _dt: number)
		live.Head = cf.Position
		glow.CFrame = cf
		if live.Taken then
			return
		end
		if st then
			layChain(st, handPos(owner) or origin.Position, cf.Position, 0.3, t)
		end
		if t - lastSpark > 0.045 then
			lastSpark = t
			Lib.Emit("Spark", cf.Position, 1, { Color = EMBER, Speed = { 2, 6 } })
		end
	end
	function v.Impact(_s: any, pos: Vector3)
		Lib.Sparks(pos, nil, BLOOD, 10, 20)
		Lib.Emit("Spark", pos, 3, { Color = GOLD })
	end
	function v.Destroy(_s: any)
		if light then
			light:Destroy()
		end
		Lib.Release(glow)
		if owner and liveChains[owner] == live then
			liveChains[owner] = nil
		end
		if st == nil or live.Taken then
			return -- the Grab effect owns the chain now
		end
		-- missed: the chain whips back into the hand
		local chain: ChainSt = st
		local head: Vector3 = live.Head
		Lib.Animate(0.16, function(a, _dt, elapsed)
			local hand = handPos(owner) or origin.Position
			layChain(chain, hand, head:Lerp(hand, a * a), 0.5 * (1 - a), elapsed)
			return nil
		end, function()
			releaseChain(chain)
		end)
	end
	return v :: any
end)

local function chainGlint(fx: any)
	local hand = handPos(fx.Character)
	if hand then
		Lib.EmitBurst(hand, 2.4, CRIMSON, 0.2)
		Lib.Emit("Spark", hand, 4, { Color = BLOOD, Speed = { 4, 9 } })
	end
end

Effects.ChainGrab = function(fx: any, packet: Map)
	local data = packet.data or {}
	local phase = packet.phase
	local caster: Model? = fx.Character
	if phase == "Start" then
		if not fx.Predicted then
			chainGlint(fx)
		end
	elseif phase == "Throw" then
		fx.Sound("BoneThrow", fx.Root(caster), { Pitch = 0.85 })
	elseif phase == "Grab" then
		local target = asModel(data.target)
		if target == nil or caster == nil then
			return
		end
		local time = if type(data.time) == "number" then data.time else 0.35
		local live = liveChains[caster]
		local st: ChainSt? = nil
		if live and live.St and not live.Taken then
			live.Taken = true
			st = live.St
		end
		if st == nil then
			st = acquireChain()
		end
		local stun = numbers("ChainGrab").Stun or 0.7
		fx.Highlight(target, CRIMSON, time + stun, { Fill = 0.6 })
		local chest = fx.Chest(target)
		if chest then
			Lib.Sparks(chest, nil, EMBER, 12, 22)
			Lib.EmitBurst(chest, 4, BLOOD, 0.2)
			Lib.Emit("Spark", chest, 4, { Color = GOLD })
		end
		fx.Sound("SoulGrab", fx.Root(target), { Pitch = 0.8 })
		if target == fx.LocalCharacter() then
			fx.Screen.Flash(DARK, 0.3, 0.16)
			fx.Screen.Vignette(CRIMSON, 0.7, time + stun, "Hit")
			fx.Shake(0.45, 0.3)
			fx.Kick(-6, 0.25)
		elseif fx.IsLocal then
			fx.Shake(0.2, 0.15)
		end
		if st == nil then
			return
		end
		local chain: ChainSt = st
		Lib.Animate(time + 0.08, function(_a, _dt, elapsed)
			local hand = handPos(caster)
			local tip = fx.Chest(target)
			if hand == nil or tip == nil then
				return true
			end
			layChain(chain, hand, tip, 0.12, elapsed)
			return nil
		end, function()
			local hand = handPos(caster)
			if hand then
				Lib.Emit("Mote", hand, 8, { Color = CRIMSON })
			end
			local front = rootCF(fx)
			if front then
				local p = (front * CFrame.new(0, -0.5, -3.2)).Position
				Lib.Dust(p - Vector3.new(0, 2.2, 0), 2, nil, 6)
				Lib.Flash(p, BLOOD, 3, 0.12)
			end
			releaseChain(chain)
		end)
	elseif phase == "Snap" then
		local pos: Vector3? = if typeof(data.pos) == "Vector3" then data.pos else nil
		if pos then
			Lib.Shatter(CFrame.new(pos), 2, Color3.fromRGB(205, 28, 40), 8, { Speed = 10 })
			Lib.Sparks(pos, nil, BLOOD, 10, 18)
		end
		fx.Sound("BoneImpact", pos)
	end
end

Predict.ChainGrab = function(fx: any, _payload: Map)
	chainGlint(fx)
end

Indicator.ChainGrab = function(fx: any): Map?
	local range = (Kits.Ability(KIT_ID, "ChainGrab") or {}).Range or 40
	local line = Lib.Part("Cylinder", Vector3.new(range, 0.1, 0.1), PARK, BLOOD, NEON, 0.4)
	local hook = Lib.Part("Ball", Vector3.one * (C.ChainRadius * 2), PARK, CRIMSON, NEON, 0.75)
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		local cf = rootCF(fx)
		if cf == nil then
			return
		end
		local fwd = flat(aim - cf.Position, cf.LookVector)
		local start = cf.Position + Vector3.new(0, 1, 0) + fwd * 1.5
		local target = aim
		local g = Lib.Ground(aim + Vector3.new(0, 0.5, 0), 3.5)
		if g then
			target = g + Vector3.new(0, 2.5, 0) -- same chest-height rule as the server
		end
		local dir = target - start
		local flatLen = Vector3.new(dir.X, 0, dir.Z).Magnitude
		local look = if flatLen < 1
			then fwd
			else Vector3.new(
				dir.X,
				math.clamp(dir.Y, -flatLen * C.ChainMaxSlope, flatLen * C.ChainMaxSlope),
				dir.Z
			).Unit
		line.CFrame = Lib.LookAlong(start, look) * CFrame.new(0, 0, -range / 2) * CFrame.Angles(0, math.pi / 2, 0)
		line.Transparency = 0.35 + 0.15 * math.sin(os.clock() * 8)
		hook.CFrame = CFrame.new(start + look * range)
	end
	function handle.Destroy(_self: any)
		Lib.Release(line)
		Lib.Release(hook)
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Bone Rush (R)

local function crouchBurst(fx: any)
	local feet = feetOf(fx)
	if feet then
		Lib.EmitRing(feet + Vector3.new(0, 0.2, 0), 3.2, CRIMSON, 0.25)
		Lib.Dust(feet, 1.6, nil, 6)
	end
end

Effects.BoneRush = function(fx: any, packet: Map)
	local data = packet.data or {}
	local char: Model? = fx.Character
	if packet.phase == "Start" then
		if not fx.Predicted then
			crouchBurst(fx)
		end
	elseif packet.phase == "Rush" and typeof(data.from) == "Vector3" and typeof(data.to) == "Vector3" then
		local from: Vector3 = data.from
		local to: Vector3 = data.to
		local time = if type(data.time) == "number" then data.time else C.RushTime
		local spikeDelay = if type(data.spikeDelay) == "number" then data.spikeDelay else 0.35
		if char then
			Lib.Afterimage(char, CRIMSON, 0.35, { Transparency = 0.4, MaxParts = 20 })
			for i = 1, 2 do
				fx.Delay(time * i / 3, function()
					if char.Parent then
						Lib.Afterimage(char, BLOOD, 0.3, { Transparency = 0.55, MaxParts = 16 })
					end
				end)
			end
		end
		fx.Sound("Dash", from, { Pitch = 0.8 })
		-- ground scrape: sparks chase Fell along the path
		local feetY = (Lib.Ground(from, 8) or (from - Vector3.new(0, 2.9, 0))).Y
		local a = Vector3.new(from.X, feetY + 0.2, from.Z)
		local b = Vector3.new(to.X, feetY + 0.2, to.Z)
		local dir = if (b - a).Magnitude > 1e-3 then (b - a).Unit else Vector3.zAxis
		Lib.Animate(time, function(alpha)
			local p = a:Lerp(b, alpha)
			Lib.Emit("Spark", p, 2, { Color = if math.random() < 0.3 then GOLD else EMBER, Dir = -dir + Vector3.yAxis })
			return nil
		end, function()
			Lib.Dust(b, 2, nil, 8)
		end)
		-- the eruption (bones themselves: HazardVisuals BoneSpikes)
		local mid = a:Lerp(b, 0.5)
		fx.Delay(spikeDelay + time * 0.5, function()
			fx.ShakeAt(mid, 0.45, 0.28, 34)
			fx.Sound("BoneRise", mid, { Pitch = 0.85 })
		end)
	end
end

Predict.BoneRush = function(fx: any, _payload: Map)
	crouchBurst(fx)
end

Indicator.BoneRush = function(fx: any): Map?
	local N = numbers("BoneRush")
	local dist = N.Distance or 26
	local lane = Lib.Lane(CFrame.new(), dist, C.SpikeRadius * 2, CRIMSON, { Fill = 0.82, Edge = 0.16, Height = 0.14 })
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		local cf = rootCF(fx)
		local feet = feetOf(fx)
		if cf and feet then
			lane:SetCFrame(Lib.LookAlong(feet, flat(aim - cf.Position, cf.LookVector)))
		end
	end
	function handle.Destroy(_self: any)
		lane:Destroy()
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Bloodlust (T)

local function roar(fx: any)
	local char: Model? = fx.Character
	local chest = if char then fx.Chest(char) else nil
	if chest then
		Lib.EmitBurst(chest, 9, CRIMSON, 0.4)
		Lib.Emit("Ember", chest, 16, { Color = EMBER, Speed = { 6, 14 } })
	end
	local feet = feetOf(fx)
	if feet then
		Lib.Shockwave(feet, 7, CRIMSON, 0.45, { Dust = true })
	end
	eyeFlare(fx, 1)
	fx.Sound("Charge", fx.Root(char), { Pitch = 0.7 })
end

-- Blood motes stream from the victim's chest into Fell's.
local function siphon(fx: any, from: Model, amount: number)
	local char: Model? = fx.Character
	if char == nil then
		return
	end
	local n = math.clamp(math.floor(amount * 0.8) + 3, 3, 9)
	local motes = partSet(n, "Ball", Vector3.one * 0.32, BLOOD, 0.1)
	local seeds: { Vector3 } = {}
	for i = 1, n do
		seeds[i] = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 3
	end
	local cfs: { CFrame } = table.create(n)
	Lib.Animate(0.45, function(alpha)
		local a = fx.Chest(from)
		local b = fx.Chest(char)
		if a == nil or b == nil then
			return true
		end
		for i = 1, n do
			local k = math.clamp(alpha * 1.25 - (i - 1) / n * 0.25, 0, 1)
			local e = k * k * (3 - 2 * k)
			local arc = seeds[i] * (4 * e * (1 - e))
			cfs[i] = CFrame.new(a:Lerp(b, e) + arc)
		end
		motes.Place(cfs)
		return nil
	end, function()
		motes.Release()
		local b = fx.Chest(char)
		if b then
			Lib.EmitBurst(b, 2.6, BLOOD, 0.2)
		end
	end)
end

Effects.Bloodlust = function(fx: any, packet: Map)
	local data = packet.data or {}
	local phase = packet.phase
	local char: Model? = fx.Character
	if phase == "Start" then
		if not fx.Predicted then
			roar(fx)
		end
	elseif phase == "Rage" then
		local duration = if type(data.duration) == "number" then data.duration else 6
		local head = if char then fx.Part(char, "Head") else nil
		if head then
			Lib.Text(head.Position + Vector3.new(0, 2.2, 0), text("fell.fx.noMercy"), BLOOD, { Scale = 1.1 })
		end
		if fx.IsLocal then
			fx.Screen.Vignette(CRIMSON, 0.45, duration, "Status")
			fx.Screen.Tint(CRIMSON, 0.22, 0.5)
			fx.Shake(0.3, 0.3)
		elseif char then
			local r = fx.Root(char)
			if r and nearLocal(r.Position, 40) then
				fx.Shake(0.15, 0.25)
			end
		end
	elseif phase == "Siphon" then
		local target = asModel(data.target)
		if target then
			siphon(fx, target, if type(data.amount) == "number" then data.amount else 2)
		end
	end
end

Predict.Bloodlust = function(fx: any, _payload: Map)
	roar(fx)
end

-- The Rage aura: embers + dark smoke from the body, crimson outline, a red light and blazing eyes.
local function setAura(fx: any, character: Model, on: boolean)
	local st = fx.State
	local aura: Map? = st.Aura
	if on and aura == nil then
		local root = fx.Root(character)
		if root == nil then
			return
		end
		local embers = Lib.Emitter("Ember", root, {
			Color = ColorSequence.new(EMBER, CRIMSON),
			Rate = 26,
			Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 7, 0),
			LightEmission = 1,
		})
		local smoke = Lib.Emitter("Smoke", root, {
			Color = ColorSequence.new(Color3.fromRGB(120, 0, 12), Color3.fromRGB(20, 0, 2)),
			Rate = 7,
			Lifetime = NumberRange.new(0.8, 1.3),
			Speed = NumberRange.new(1, 2.5),
			Acceleration = Vector3.new(0, 4, 0),
		})
		local hl = Instance.new("Highlight")
		hl.Name = "SV_FellRage"
		hl.Adornee = character
		hl.FillColor = CRIMSON
		hl.FillTransparency = 0.88
		hl.OutlineColor = BLOOD
		hl.OutlineTransparency = 0.15
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = Lib.Folder()
		local light = Lib.Light(root, CRIMSON, 1.8, 14)
		local newAura: Map = { Embers = embers, Smoke = smoke, Highlight = hl, Light = light, Alive = true }
		st.Aura = newAura
		fx.EyeGlow(character, "Both", eyeColor(fx, character), true)
		-- the outline breathes with a heartbeat
		Lib.Animate(60, function(_a, _dt, elapsed)
			if not newAura.Alive or hl.Parent == nil then
				return true
			end
			local beat = math.max(0, math.sin(elapsed * 7.5)) ^ 6
			hl.OutlineTransparency = 0.35 - 0.3 * beat
			hl.FillTransparency = 0.9 - 0.12 * beat
			return nil
		end)
	elseif not on and aura then
		st.Aura = nil
		aura.Alive = false
		aura.Embers.Enabled = false
		aura.Smoke.Enabled = false
		Lib.Debris(aura.Embers, 1.2)
		Lib.Debris(aura.Smoke, 1.4)
		aura.Highlight:Destroy()
		if aura.Light then
			aura.Light:Destroy()
		end
		if character:GetAttribute("FinalForm") ~= true and os.clock() > (st.EyeUntil or 0) then
			fx.EyeGlow(character, "Both", eyeColor(fx, character), false)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Lunge (Shift)

local function lungeVisual(fx: any, from: Vector3?, dir: Vector3?)
	local char: Model? = fx.Character
	if char == nil then
		return
	end
	Lib.Afterimage(char, CRIMSON, 0.3, { Transparency = 0.42, MaxParts = 18 })
	fx.Delay(0.06, function()
		if char.Parent then
			Lib.Afterimage(char, DARK, 0.26, { Transparency = 0.6, MaxParts = 14 })
		end
	end)
	local root = fx.Root(char)
	local p: Vector3? = from or (if root then root.Position else nil)
	if p then
		Lib.Dust(p - Vector3.new(0, 2.8, 0), 1.3, nil, 6)
		if dir and dir.Magnitude > 1e-3 then
			Lib.Emit("Ember", p, 6, { Color = EMBER, Dir = -dir })
		end
	end
	fx.Sound("Lunge", fx.Root(char))
end

Effects.Lunge = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Dash" and not fx.Predicted then
		local from: Vector3? = if typeof(data.from) == "Vector3" then data.from else nil
		local to: Vector3? = if typeof(data.to) == "Vector3" then data.to else nil
		lungeVisual(fx, from, if from and to then to - from else nil)
	end
end

Predict.Lunge = function(fx: any, payload: Map)
	local char: Model? = fx.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local dir: Vector3? = nil
	if hum and hum.MoveDirection.Magnitude > 0.2 then
		dir = hum.MoveDirection
	elseif typeof(payload.dir) == "Vector3" then
		dir = payload.dir
	end
	lungeVisual(fx, nil, dir)
end

Indicator.Lunge = function(fx: any): Map?
	local dist = numbers("Lunge").Distance or 18
	local lane = Lib.Lane(CFrame.new(), dist, 2, CRIMSON, { Fill = 0.85, Edge = 0.14, Height = 0.12 })
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		local cf = rootCF(fx)
		local feet = feetOf(fx)
		if cf and feet then
			local char = fx.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local dir = if hum and hum.MoveDirection.Magnitude > 0.2
				then flat(hum.MoveDirection, cf.LookVector)
				else flat(aim - cf.Position, cf.LookVector)
			lane:SetCFrame(Lib.LookAlong(feet, dir))
		end
	end
	function handle.Destroy(_self: any)
		lane:Destroy()
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Execution (G, ultimate)

local RING_SEGS = 8

-- A rotating crimson target mark (8 neon blocks + a pointer diamond) hovering over a human.
local function newMark(target: Model, fx: any): Map
	local ring = partSet(RING_SEGS, "Block", Vector3.new(0.5, 0.16, 0.22), BLOOD, 0.05)
	local pointer = partSet(1, "Block", Vector3.new(0.7, 0.7, 0.7), CRIMSON, 0)
	local mark: Map = { Target = target, Ring = ring, Pointer = pointer, Alive = true, Dropped = false }
	local cfs: { CFrame } = table.create(RING_SEGS)
	local pcf: { CFrame } = { CFrame.identity }
	local born = os.clock()
	Lib.Animate(8, function(_a, _dt, elapsed)
		if not mark.Alive then
			return true
		end
		local head = fx.Part(target, "Head")
		local r = fx.Root(target)
		if r == nil or target.Parent == nil then
			mark.Alive = false
			return true
		end
		local top = if head then head.Position + Vector3.new(0, 2.4, 0) else r.Position + Vector3.new(0, 5, 0)
		local urgency = math.clamp((os.clock() - born) / math.max(0.2, mark.Lock or 0.7), 0, 1)
		local radius = 2.2 - 0.8 * urgency
		local spin = elapsed * (2 + 6 * urgency)
		local centre = mark.Override or top
		for i = 1, RING_SEGS do
			local a = spin + (i - 1) * (2 * math.pi / RING_SEGS)
			local p = centre + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			cfs[i] = CFrame.new(p) * CFrame.Angles(0, -a, 0)
		end
		ring.Place(cfs)
		local bob = 0.25 * math.sin(elapsed * 6)
		pcf[1] = CFrame.new(centre + Vector3.new(0, 1.1 + bob, 0))
			* CFrame.Angles(math.rad(45), elapsed * 3, math.rad(45))
		pointer.Place(pcf)
		local blink = urgency > 0.6 and math.floor(elapsed * 14) % 2 == 0
		ring.SetTransparency(if blink then 0.5 else 0.05)
		return nil
	end, function()
		mark.Alive = false
		ring.Release()
		pointer.Release()
	end)
	return mark
end

local function clearMarks(fx: any, shatter: boolean)
	local marks: { [Model]: Map }? = fx.State.ExecMarks
	if marks == nil then
		return
	end
	fx.State.ExecMarks = nil
	for target, mark in marks do
		if shatter and mark.Alive then
			local r = fx.Root(target)
			if r then
				Lib.Sparks(r.Position + Vector3.new(0, 4, 0), nil, BLOOD, 8, 12)
			end
		end
		mark.Alive = false
	end
end

local function executionStart(fx: any, isCaster: boolean)
	local char: Model? = fx.Character
	if char == nil then
		return
	end
	local N = numbers("Execution")
	local delay = N.Delay or 1.2
	eyeFlare(fx, delay + 1)
	local head = fx.Part(char, "Head")
	if head then
		Lib.EmitBurst(head.Position, 8, BLOOD, 0.45)
		Lib.Text(head.Position + Vector3.new(0, 2.5, 0), text("fell.fx.execution"), BLOOD, { Scale = 1.3 })
	end
	local feet = feetOf(fx)
	if feet then
		Lib.EmitRing(feet + Vector3.new(0, 0.3, 0), N.Radius or 40, CRIMSON, 0.7, { Start = 0.05, Brightness = 2 })
	end
	if isCaster or (feet and nearLocal(feet, (N.Radius or 40) + 20)) then
		local g = graphics()
		if g and type(g.PushTimed) == "function" then
			local pr = if type(g.PRIORITY) == "table" then g.PRIORITY.Gameplay else 100
			pcall(g.PushTimed, "FellExecution", "BloodFellFinal", delay + 1.3, pr, 0.25, 0.9)
		end
		fx.Shake(0.3, 0.5)
	end
	fx.Sound("Charge", fx.Root(char), { Pitch = 0.6 })
end

local function groundMark(fx: any, point: Vector3, width: number, delay: number)
	local r = width / 2
	local circle = Lib.GroundCircle(point, r, BLOOD, { Rim = 0.3, Fill = 0.72, Height = 0.28 })
	circle:SetFill(0)
	local brackets = partSet(4, "Block", Vector3.new(0.9, 0.18, 0.3), CRIMSON, 0)
	local cfs: { CFrame } = table.create(4)
	Lib.Flash(point + Vector3.new(0, 0.5, 0), BLOOD, 3, 0.15)
	Lib.Animate(delay, function(a, _dt, elapsed)
		circle:SetFill(a)
		local spin = elapsed * 2.5
		local rr = r + 1.6 * (1 - a)
		for i = 1, 4 do
			local ang = spin + (i - 1) * math.pi / 2
			cfs[i] = CFrame.new(point + Vector3.new(math.cos(ang) * rr, 0.25, math.sin(ang) * rr))
				* CFrame.Angles(0, -ang, 0)
		end
		brackets.Place(cfs)
		return nil
	end, function()
		circle:Destroy()
		brackets.Release()
		impact(fx, point, width * 1.1, 0.85)
		fx.Sound("Explosion", point, { Pitch = 0.85 })
	end)
end

Effects.Execution = function(fx: any, packet: Map)
	local data = packet.data or {}
	local phase = packet.phase
	if phase == "Start" then
		if not fx.Predicted then
			executionStart(fx, false)
		end
	elseif phase == "Mark" then
		clearMarks(fx, false)
		local marks: { [Model]: Map } = {}
		local lock = if type(data.lock) == "number" then data.lock else 0.7
		local delay = if type(data.delay) == "number" then data.delay else 1.2
		for _, t in (if type(data.targets) == "table" then data.targets else {}) :: { any } do
			local target = asModel(t)
			if target then
				local m = newMark(target, fx)
				m.Lock = lock
				marks[target] = m
				fx.Highlight(target, CRIMSON, delay + 0.4, { Fill = 0.8 })
				if target == fx.LocalCharacter() then
					local head = fx.Part(target, "Head")
					if head then
						Lib.Text(head.Position + Vector3.new(0, 3, 0), text("fell.fx.marked"), BLOOD, { Scale = 1 })
					end
					fx.Screen.Vignette(CRIMSON, 0.65, delay + 0.4, "Status")
					fx.Sound("Stun", nil, { Pitch = 0.7 })
				end
			end
		end
		fx.State.ExecMarks = marks
		-- safety: marks never outlive the ultimate if the Drop / Cancel packet is lost
		fx.Delay(delay + 1.5, function()
			if fx.State.ExecMarks == marks then
				clearMarks(fx, false)
			end
		end)
	elseif phase == "Drop" then
		local marks: { [Model]: Map } = fx.State.ExecMarks or {}
		fx.State.ExecMarks = nil
		local width = if type(data.width) == "number" then data.width else C.ExecWidth
		local delay = if type(data.delay) == "number" then data.delay else C.ExecLock
		local t0 = if type(packet.t0) == "number" then packet.t0 else Lib.Now()
		local left = math.max(0.05, delay - (Lib.Now() - t0))
		local targets: { any } = if type(data.targets) == "table" then data.targets else {}
		for i, p in (if type(data.points) == "table" then data.points else {}) :: { any } do
			if typeof(p) == "Vector3" then
				local point: Vector3 = p
				local target = asModel(targets[i])
				local mark = if target then marks[target] else nil
				if mark then
					marks[target :: Model] = nil
					-- the mark slams down onto the locked spot
					local head = fx.Part(target, "Head")
					local troot = fx.Root(target)
					local from: Vector3 = if head then head.Position elseif troot then troot.Position else point
					local m: Map = mark
					Lib.Animate(0.12, function(a)
						m.Override = from:Lerp(point + Vector3.new(0, 0.3, 0), a * a)
						return nil
					end, function()
						m.Alive = false
						Lib.Line(from, point, BLOOD, 0.3, 0.15)
					end)
				end
				groundMark(fx, point, width, left)
			end
		end
		for _, mark in marks do
			mark.Alive = false
		end
	elseif phase == "Cancel" then
		clearMarks(fx, true)
		local head = fx.Part(fx.Character, "Head")
		if head then
			Lib.Text(head.Position + Vector3.new(0, 2.5, 0), text("fell.fx.interrupted"), CRIMSON, { Scale = 0.8 })
		end
	elseif phase == "Executed" then
		local target = asModel(data.target)
		local pos: Vector3? = if typeof(data.pos) == "Vector3" then data.pos elseif target then fx.Chest(target) else nil
		if pos then
			Lib.Text(pos + Vector3.new(0, 3.2, 0), text("fell.fx.executed"), GOLD, { Scale = 1.4 })
			Lib.Flash(pos, GOLD, 5, 0.2)
			Lib.Emit("Spark", pos, 12, { Color = GOLD, Speed = { 12, 24 } })
			fx.ShakeAt(pos, 0.5, 0.3, 40)
		end
		fx.Sound("Crit", pos, { Pitch = 0.75 })
	end
end

Predict.Execution = function(fx: any, _payload: Map)
	executionStart(fx, true)
end

Indicator.Execution = function(fx: any): Map?
	local N = numbers("Execution")
	local radius = N.Radius or 40
	local area = Lib.GroundCircle(Vector3.zero, radius, CRIMSON, { Rim = 0.3, Fill = 0.9, Height = 0.16 })
	local pins: { BasePart } = {}
	local handle = {}
	function handle.Update(_self: any, _aim: Vector3, _charge: number)
		local feet = feetOf(fx)
		local cf = rootCF(fx)
		if feet == nil or cf == nil then
			return
		end
		area:SetCenter(feet)
		local n = 0
		for _, m in Lib.Characters() do
			if m ~= fx.Character and fx.IsEnemy(m) and m:GetAttribute("Downed") ~= true then
				local r = fx.Root(m)
				if r and (r.Position - cf.Position).Magnitude <= radius then
					n += 1
					local pin = pins[n]
					if pin == nil then
						pin = Lib.Part("Block", Vector3.new(0.6, 0.6, 0.6), PARK, BLOOD, NEON, 0.2)
						pins[n] = pin
					end
					pin.CFrame = CFrame.new(r.Position + Vector3.new(0, 4.6, 0))
						* CFrame.Angles(math.rad(45), os.clock() * 3, math.rad(45))
				end
			end
		end
		for i = n + 1, #pins do
			pins[i].CFrame = PARK
		end
	end
	function handle.Destroy(_self: any)
		area:Destroy()
		for _, p in pins do
			Lib.Release(p)
		end
		table.clear(pins)
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Gold Tooth (passive)

local function toothGlint(fx: any, character: Model?, size: number)
	local tooth = fx.Part(character or fx.Character, "GoldTooth")
	if tooth then
		Lib.EmitBurst(tooth.Position, size, GOLD, 0.18, { Brightness = 5 })
		Lib.Emit("Star", tooth.Position, 1, { Color = GOLD, Speed = { 0.5, 1.5 } })
	end
end

Effects.GoldTooth = function(fx: any, packet: Map)
	if packet.phase ~= "Glint" then
		return
	end
	local data = packet.data or {}
	toothGlint(fx, nil, 1.6)
	local target = asModel(data.target)
	local pos: Vector3? = if target then fx.Chest(target) else nil
	if pos == nil and typeof(data.pos) == "Vector3" then
		pos = data.pos
	end
	if pos then
		Lib.Emit("Spark", pos, 8, { Color = GOLD, Speed = { 10, 20 } })
		Lib.EmitBurst(pos, 3, GOLD, 0.16)
		Lib.Text(pos + Vector3.new(1.2, 2.2, 0), text("fell.fx.brutal"), GOLD, { Scale = 0.7 })
	end
	fx.Sound("Crit", pos, { Pitch = 1.15, Volume = 0.6 })
end

---------------------------------------------------------------------------------------------------
-- Passives

function Kit.OnCharacter(fx: any, character: Model)
	local trove = fx.Trove
	local alive = true
	fx.State.EyeColor = nil
	eyeColor(fx, character) -- cache the skin's eye colour while the eyes are idle
	trove:Add(function()
		alive = false
		local st = fx.State
		if st.Aura then
			setAura(fx, character, false)
		end
		clearMarks(fx, false)
	end)
	-- Bloodlust aura follows the replicated Rage status (late joiners and respawns included)
	local function rageChanged()
		local v = character:GetAttribute("Status_Rage")
		local on = type(v) == "number" and v > Lib.Now() and character:GetAttribute("Dead") ~= true
		setAura(fx, character, on)
		if on then
			fx.Delay(math.max(0.05, (v :: number) - Lib.Now() + 0.1), function()
				if alive then
					local v2 = character:GetAttribute("Status_Rage")
					setAura(fx, character, type(v2) == "number" and v2 > Lib.Now())
				end
			end)
		end
	end
	trove:Connect(character:GetAttributeChangedSignal("Status_Rage"), rageChanged)
	trove:Connect(character:GetAttributeChangedSignal("Dead"), rageChanged)
	rageChanged()
	-- FinalForm: both eyes blaze for the rest of the round
	local function finalForm()
		local on = character:GetAttribute("FinalForm") == true
		if on then
			fx.EyeGlow(character, "Both", eyeColor(fx, character), true)
			local head = fx.Part(character, "Head")
			if head then
				Lib.EmitBurst(head.Position, 9, BLOOD, 0.5)
			end
		elseif not raging(character) then
			fx.EyeGlow(character, "Both", eyeColor(fx, character), false)
		end
	end
	trove:Connect(character:GetAttributeChangedSignal("FinalForm"), finalForm)
	if character:GetAttribute("FinalForm") == true then
		finalForm()
	end
	-- idle: the gold tooth catches the light now and then
	task.spawn(function()
		while alive and character.Parent do
			task.wait(4 + math.random() * 5)
			if not alive or character.Parent == nil or character:GetAttribute("Dead") == true then
				break
			end
			toothGlint(fx, character, 1.1)
		end
	end)
end

-- Lazy dodge on top of FxController's grey MISS ghost: a red wink, a gold-tooth grin and a puff of dust.
function Kit.OnDamageFx(fx: any, packet: Map)
	if not packet.dodged then
		return
	end
	local char = fx.Character
	local eye = fx.Attachment(char, "RightEye")
	if eye then
		Lib.EmitBurst(eye.WorldPosition, 1.3, eyeColor(fx, char), 0.18)
	end
	toothGlint(fx, char, 1.2)
	local r = fx.Root(char)
	if r then
		Lib.Dust(r.Position - Vector3.new(0, 2.8, 0), 1, nil, 4)
	end
end

return Kit
