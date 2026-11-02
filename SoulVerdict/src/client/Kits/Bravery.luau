--!strict
-- Client kit: Bravery (orange SOUL) — "The Brawler" (SPEC §9.1). Visuals for every AbilityFx phase of
-- src/server/Kits/Bravery.luau:
--   ToughPunches    Start {combo}: glove impact puffs with speed lines (4th: big hook, flash, embers), predicted
--                   locally; Strike {last, hits}: heavy finisher sparks + mini shockwave + hit-stop
--   GutsCharge      Start: engine rev (flame burst); Charge {from, to, time}: flame streak, afterimages, ember trail,
--                   FOV kick; Impact {target, pos, landed}: big orange impact, "STUN!", hit-stop, shake; Skid {pos}
--   BraveStand      Start: gold glint; Stand {duration, radius, allies}: golden ForceField dome over Bravery (pops in,
--                   follows, fades), radius pulse, smaller bubbles + tethers on every shielded ally
--   BurningCourage  Start: flames gather; Leap {from, to, time, radius}: landing telegraph filling up + ember trail;
--                   Slam {center, radius, allies, buffTime}: fiery shockwave, fire tongues, debris, scorch mark,
--                   "COURAGE!", flaming fists on every rallied ally for buffTime. Indicator: landing circle + arc.
-- OnCharacter: Unbreakable — a golden guard shield in front of Bravery while Blocking; faint orange SOUL heart at the
-- Chest while UltActiveUntil is in the future (helper shared with the Patience client kit).
-- Kit.LeapIndicator(fx, color, radius, apex) -> indicator handle (landing circle + flowing arc dots; also Integrity).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any

local PatienceKit = require(script.Parent:WaitForChild("Patience")) :: any

type Map = { [string]: any }

local Kit = {}
local Effects: { [string]: (any, Map) -> () } = {}
local Predict: { [string]: (any, Map) -> () } = {}
local Indicator: { [string]: (any) -> Map? } = {}
Kit.Effects = Effects
Kit.Predict = Predict
Kit.Indicator = Indicator

local ORANGE = Color3.fromRGB(252, 166, 0)
local FLAME = Color3.fromRGB(255, 104, 28)
local GOLD = Color3.fromRGB(255, 214, 92)
local HOT = Color3.fromRGB(255, 244, 214)
local ROCK = Color3.fromRGB(120, 96, 82)
local SCORCH = Color3.fromRGB(40, 22, 12)
local PARK = CFrame.new(0, 25000, 0)
local NEON = Enum.Material.Neon
local FIELD = Enum.Material.ForceField
local UP = Vector3.yAxis
local TAU = math.pi * 2
local CYL_UP = CFrame.Angles(0, 0, math.pi / 2) -- cylinder X axis -> world up

local function numbers(abilityId: string): Map
	local a = Kits.Ability("Bravery", abilityId)
	return if a and a.Numbers then a.Numbers else {}
end

local function rootCF(fx: any): CFrame?
	local r = fx.Root(fx.Character)
	return if r then r.CFrame else nil
end

local function feetOf(fx: any, model: Model?): Vector3?
	local r = fx.Root(model)
	return if r then r.Position - Vector3.new(0, 2.8, 0) else nil
end

local workspaceRef: any = nil
local function bulkMove(parts: { BasePart }, cfs: { CFrame })
	if workspaceRef == nil then
		workspaceRef = game:GetService("Workspace")
	end
	workspaceRef:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function backOut(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function asModel(v: any): Model?
	return if typeof(v) == "Instance" and v:IsA("Model") then v else nil
end

---------------------------------------------------------------------------------------------------
-- Shared leap indicator (Bravery ult, Integrity Grand Jete)

function Kit.LeapIndicator(fx: any, color: Color3, radius: number, apex: number): Map
	local Lib = fx.VFX
	local circle = Lib.GroundCircle(Vector3.zero, radius, color, { Rim = 0.22, Fill = 0.84, Height = 0.16 })
	local DOTS = 12
	local dots: { BasePart } = {}
	for i = 1, DOTS do
		dots[i] = Lib.Part("Ball", Vector3.one * (0.24 + 0.02 * i), PARK, color, NEON, 0.15)
	end
	local cfs: { CFrame } = table.create(DOTS)
	local handle: Map = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		circle:SetCenter(aim)
		local r = fx.Root(fx.Character)
		if r == nil then
			return
		end
		local from = r.Position - Vector3.new(0, 1.5, 0)
		local flow = (os.clock() * 1.4) % 1
		for i = 1, DOTS do
			local u = (i - 1 + flow) / DOTS
			cfs[i] = CFrame.new(from:Lerp(aim, u) + Vector3.new(0, apex * 4 * u * (1 - u), 0))
		end
		bulkMove(dots, cfs)
	end
	function handle.Destroy(_self: any)
		circle:Destroy()
		for _, d in dots do
			Lib.Release(d)
		end
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Tough Glove (M1)

local function punch(fx: any, combo: number)
	fx.Delay(0.07, function()
		local cf = rootCF(fx)
		if cf == nil then
			return
		end
		local Lib = fx.VFX
		local i = ((combo - 1) % 4) + 1
		local big = i == 4
		local side = if i % 2 == 1 then 0.55 else -0.55
		local look = cf.LookVector
		local p = (cf * CFrame.new(if big then 0 else side, if big then 0.9 else 0.5, -2.6)).Position
		Lib.EmitBurst(p, if big then 3.6 else 2.2, ORANGE, if big then 0.2 else 0.14)
		Lib.EmitRing(p, if big then 2.6 else 1.5, FLAME, 0.18, { Axis = look })
		-- speed lines trailing the glove
		for k = -1, 1 do
			local off = cf.RightVector * (k * 0.35) + cf.UpVector * ((k % 2) * 0.25)
			Lib.Line(p - look * (2.2 + 0.3 * math.abs(k)) + off, p - look * 0.6 + off, HOT, 0.08, 0.12)
		end
		if big then
			Lib.Flash(p, HOT, 3.4, 0.14)
			Lib.Emit("Ember", p, 8, { Color = FLAME, Dir = look, Speed = { 6, 16 } })
		end
		fx.Sound("Punch", fx.Root(fx.Character), { Pitch = if big then 0.82 else 1 + 0.05 * i })
	end)
end

Effects.ToughPunches = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			punch(fx, data.combo or 1)
		end
	elseif packet.phase == "Strike" and data.last and (data.hits or 0) > 0 then
		local cf = rootCF(fx)
		if cf then
			local Lib = fx.VFX
			local front = (cf * CFrame.new(0, 0.6, -3)).Position
			Lib.Sparks(front, cf.LookVector, FLAME, 14, 32)
			Lib.Shockwave(front - Vector3.new(0, 3.2, 0), 3.5, ORANGE, 0.3, { Dust = true })
			fx.Sound("HitHeavy", front)
			fx.ShakeAt(front, 0.25, 0.18, 24)
			fx.HitStop(fx.Character, 0.07)
		end
	end
end

Predict.ToughPunches = function(fx: any, _payload: Map)
	local idx = 1
	local combat = fx.Combat()
	if combat and type(combat.ComboIndex) == "function" then
		local ok, i = pcall(combat.ComboIndex)
		if ok and type(i) == "number" and i > 0 then
			idx = i
		end
	end
	punch(fx, idx)
end

---------------------------------------------------------------------------------------------------
-- Guts Charge (Q)

local function rev(fx: any)
	local char = fx.Character
	local chest = fx.Chest(char)
	local feet = feetOf(fx, char)
	if chest then
		fx.VFX.EmitBurst(chest, 3, FLAME, 0.25)
	end
	if feet then
		fx.VFX.Emit("Ember", feet + UP * 0.4, 10, { Color = FLAME, Dir = UP, Speed = { 3, 8 } })
		fx.VFX.Dust(feet, 1.4, nil, 6)
	end
end

Effects.GutsCharge = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local char = fx.Character
	if packet.phase == "Start" then
		if not fx.Predicted then
			rev(fx)
		end
	elseif packet.phase == "Charge" and typeof(data.from) == "Vector3" and typeof(data.to) == "Vector3" then
		local from: Vector3, to: Vector3 = data.from, data.to
		local time = if type(data.time) == "number" then data.time else 0.35
		Lib.Dust(from - Vector3.new(0, 2.6, 0), 2, nil, 10)
		fx.Sound("Charge", from)
		Lib.Beam(from + UP * 0.3, to + UP * 0.3, 1.1, FLAME, time + 0.25)
		for k = 1, 3 do
			fx.Delay(time * k / 3.4, function()
				if char and char.Parent then
					Lib.Afterimage(char, ORANGE, 0.3, { Transparency = 0.45 + k * 0.08, MaxParts = 16 })
				end
			end)
		end
		local lastEmber = -1
		Lib.Animate(time, function(_a, _dt, elapsed)
			local r = fx.Root(char)
			if r == nil then
				return true
			end
			if elapsed - lastEmber > 0.04 then
				lastEmber = elapsed
				Lib.Emit("Ember", r.Position, 2, { Color = FLAME, Speed = { 1, 4 } })
			end
			return nil
		end)
		if fx.IsLocal then
			fx.Kick(7, time + 0.1)
		end
	elseif packet.phase == "Impact" then
		local target = asModel(data.target)
		local pos: Vector3? = if typeof(data.pos) == "Vector3" then data.pos else nil
		if pos == nil then
			return
		end
		local cf = rootCF(fx)
		local dir = if cf then Vector3.new(pos.X - cf.Position.X, 0, pos.Z - cf.Position.Z) else Vector3.zero
		dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, -1)
		Lib.Flash(pos, HOT, 6, 0.22)
		Lib.EmitBurst(pos, 5, FLAME, 0.25)
		Lib.Sparks(pos, dir, FLAME, 20, 40)
		Lib.EmitRing(pos, 3.6, ORANGE, 0.28, { Axis = dir })
		Lib.Shockwave(pos - Vector3.new(0, 2.8, 0), 6, ORANGE, 0.4, { Dust = true })
		if data.landed then
			Lib.Text(pos + UP * 3, Strings.L("fx.bravery.stun"), ORANGE, { Kind = "Alert", Scale = 1.1 })
			fx.Sound("Stun", pos)
		end
		fx.Sound("HitHeavy", pos)
		fx.HitStop(char, 0.12)
		if target then
			fx.HitStop(target, 0.12)
		end
		fx.ShakeAt(pos, 0.45, 0.3, 40)
	elseif packet.phase == "Skid" and typeof(data.pos) == "Vector3" then
		local ground = data.pos - Vector3.new(0, 2.7, 0)
		Lib.Dust(ground, 2.5, nil, 12)
		Lib.EmitRing(ground + UP * 0.2, 2.2, ORANGE, 0.3)
	end
end

Predict.GutsCharge = function(fx: any, _payload: Map)
	rev(fx)
end

---------------------------------------------------------------------------------------------------
-- Brave Stand (E)

-- Golden ForceField bubble that pops in around `model`, follows it and fades for its last 0.3 s.
local function shieldBubble(fx: any, model: Model, diameter: number, duration: number, withRing: boolean)
	local Lib = fx.VFX
	local r0 = fx.Root(model)
	if r0 == nil then
		return
	end
	local start = CFrame.new(r0.Position)
	local dome = Lib.Part("Ball", Vector3.one * diameter, start, GOLD, FIELD, 0)
	local glow = Lib.Part("Ball", Vector3.one * diameter * 0.96, start, ORANGE, NEON, 0.92)
	local ring = if withRing
		then Lib.GroundCircle(r0.Position - Vector3.new(0, 2.8, 0), diameter * 0.5, GOLD, { Rim = 0.2, Fill = 0.88, Height = 0.18 })
		else nil
	local light = Lib.Light(glow, GOLD, 1.1, diameter * 1.4)
	Lib.Animate(math.max(0.3, duration), function(_a, _dt, elapsed)
		local r = fx.Root(model)
		if r == nil or model.Parent == nil then
			return true
		end
		local pop = if elapsed < 0.22 then backOut(elapsed / 0.22) else 1
		local fade = math.clamp((elapsed - (duration - 0.3)) / 0.3, 0, 1)
		local size = diameter * math.max(0.05, pop) * (1 - 0.15 * fade)
		local c = CFrame.new(r.Position + Vector3.new(0, 0.2, 0))
		dome.Size = Vector3.one * size
		glow.Size = Vector3.one * size * 0.96
		dome.CFrame = c
		glow.CFrame = c
		dome.Transparency = fade
		glow.Transparency = 0.9 + 0.03 * math.sin(elapsed * 9) + 0.07 * fade
		if ring then
			ring:SetCenter(r.Position - Vector3.new(0, 2.8, 0))
			ring:SetTransparency(0.2 + 0.8 * fade, 0.88 + 0.12 * fade)
		end
		if light then
			light.Brightness = 1.1 * (1 - fade)
		end
		return nil
	end, function()
		if light then
			light:Destroy()
		end
		Lib.Release(dome)
		Lib.Release(glow)
		if ring then
			ring:Destroy()
		end
	end)
end

Effects.BraveStand = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local char = fx.Character
	if packet.phase == "Start" then
		if not fx.Predicted then
			local chest = fx.Chest(char)
			if chest then
				Lib.EmitBurst(chest, 2.6, GOLD, 0.2)
			end
		end
	elseif packet.phase == "Stand" then
		local duration = if type(data.duration) == "number" then data.duration else 3
		local radius = if type(data.radius) == "number" then data.radius else 10
		local feet = feetOf(fx, char)
		if feet == nil then
			return
		end
		Lib.Shockwave(feet, radius, GOLD, 0.5, { Dust = false })
		Lib.EmitRing(feet + UP * 0.2, radius, ORANGE, 0.45, { Start = 0.2 })
		shieldBubble(fx, char, 9, duration, true)
		local myChest = fx.Chest(char)
		local localChar = fx.LocalCharacter()
		local covered = fx.IsLocal
		for _, v in (if type(data.allies) == "table" then data.allies else {}) :: { any } do
			local ally = asModel(v)
			if ally and ally ~= char then
				shieldBubble(fx, ally, 6, duration, false)
				local theirChest = fx.Chest(ally)
				if myChest and theirChest then
					Lib.Beam(myChest, theirChest, 0.25, GOLD, 0.3)
				end
				covered = covered or ally == localChar
			end
		end
		fx.Sound("Shield", fx.Root(char))
		fx.Sound("Block", fx.Root(char), { Pitch = 0.8 })
		if covered then
			fx.Screen.Tint(GOLD, 0.12, 0.5)
		end
	end
end

Predict.BraveStand = function(fx: any, _payload: Map)
	local chest = fx.Chest(fx.Character)
	if chest then
		fx.VFX.EmitBurst(chest, 2.6, GOLD, 0.2)
	end
end

---------------------------------------------------------------------------------------------------
-- Burning Courage (R, ultimate)

local function gatherFlames(fx: any)
	local char = fx.Character
	local feet = feetOf(fx, char)
	local chest = fx.Chest(char)
	if feet then
		fx.VFX.Emit("Ember", feet + UP * 0.3, 14, { Color = FLAME, Dir = UP, Speed = { 4, 10 } })
	end
	if chest then
		fx.VFX.EmitBurst(chest, 3, FLAME, 0.4)
	end
	fx.Sound("Charge", fx.Root(char), { Pitch = 0.8 })
end

-- flaming fists for a rallied ally (DamageUp)
local function rally(fx: any, ally: Model, duration: number)
	local Lib = fx.VFX
	for _, grip in { "RightGrip", "LeftGrip" } do
		local att = fx.Attachment(ally, grip)
		if att then
			local e = Lib.Emitter("Ember", att, { Color = FLAME, Rate = 14 * Lib.ParticleScale() })
			fx.Debris(e, duration)
		end
	end
	local chest = fx.Chest(ally)
	if chest then
		Lib.EmitBurst(chest, 2.6, ORANGE, 0.3)
	end
end

local function fireTongue(Lib: any, pos: Vector3, life: number)
	local p = Lib.Part("Cylinder", Vector3.new(0.2, 1.4, 1.4), CFrame.new(pos) * CYL_UP, FLAME, NEON, 0.1)
	Lib.Animate(life, function(a)
		local h = 7 * math.sin(math.pi * math.min(1, a * 1.3)) + 0.2
		local w = 1.4 * (1 - 0.6 * a)
		p.Size = Vector3.new(h, w, w)
		p.CFrame = CFrame.new(pos + Vector3.new(0, h * 0.5, 0)) * CYL_UP
		p.Transparency = 0.1 + 0.9 * a * a
		return nil
	end, function()
		Lib.Release(p)
	end)
end

Effects.BurningCourage = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local char = fx.Character
	if packet.phase == "Start" then
		if not fx.Predicted then
			gatherFlames(fx)
		end
	elseif packet.phase == "Leap" and typeof(data.to) == "Vector3" then
		local to: Vector3 = data.to
		local time = if type(data.time) == "number" then data.time else 0.5
		local radius = if type(data.radius) == "number" then data.radius else 14
		local circle = Lib.GroundCircle(to, radius, ORANGE, { Rim = 0.35, Fill = 0.75, Height = 0.25 })
		circle:SetFill(0)
		local lastEmber = -1
		Lib.Animate(time + 0.05, function(a, _dt, elapsed)
			circle:SetFill(a)
			local blink = a > 0.6 and math.floor(elapsed * 16) % 2 == 0
			circle:SetTransparency(if blink then 0.45 else 0.1, 0.75)
			local r = fx.Root(char)
			if r and elapsed - lastEmber > 0.03 then
				lastEmber = elapsed
				Lib.Emit("Ember", r.Position, 3, { Color = FLAME, Speed = { 1, 5 } })
			end
			return nil
		end, function()
			circle:Destroy()
		end)
		if typeof(data.from) == "Vector3" then
			Lib.Dust(data.from - Vector3.new(0, 2.6, 0), 2.2, nil, 10)
			fx.Sound("Whoosh", data.from, { Pitch = 0.75 })
		end
		fx.Delay(time * 0.5, function()
			if char and char.Parent then
				Lib.Afterimage(char, FLAME, 0.35, { Transparency = 0.5, MaxParts = 18 })
			end
		end)
	elseif packet.phase == "Slam" and typeof(data.center) == "Vector3" then
		local c: Vector3 = data.center
		local radius = if type(data.radius) == "number" then data.radius else 14
		local buffTime = if type(data.buffTime) == "number" then data.buffTime else 6
		Lib.Flash(c + UP * 2, HOT, 10, 0.3)
		Lib.Shockwave(c, radius, FLAME, 0.6, { Dust = true })
		Lib.Ring(CFrame.new(c + UP * 0.3), radius, ORANGE, 0.5, 0.35)
		fx.Delay(0.08, function()
			Lib.Ring(CFrame.new(c + UP * 0.5), radius * 0.7, GOLD, 0.45, 0.25)
		end)
		Lib.Emit("Ember", c + UP, 36, { Color = FLAME, Dir = UP, Speed = { 10, 28 } })
		Lib.Shatter(CFrame.new(c + UP * 0.5), 1.4, ROCK, 12, { Speed = 24 })
		for k = 1, 10 do
			local ang = k / 10 * TAU
			fireTongue(Lib, c + Vector3.new(math.cos(ang), 0, math.sin(ang)) * radius * 0.82, 0.45 + 0.1 * (k % 3))
		end
		local scorch = Lib.GroundCircle(c, radius * 0.55, SCORCH, { Rim = 0.6, Fill = 0.45, Height = 0.08, Shadow = false })
		Lib.Animate(2.2, function(a)
			scorch:SetTransparency(0.3 + 0.7 * a, 0.45 + 0.55 * a)
			return nil
		end, function()
			scorch:Destroy()
		end)
		Lib.Text(c + UP * 5, Strings.L("fx.bravery.courage"), ORANGE, { Kind = "Alert", Scale = 1.25 })
		fx.Sound("Slam", c)
		fx.Sound("Explosion", c, { Volume = 0.7 })
		fx.ShakeAt(c, 0.85, 0.5, 70)
		local localChar = fx.LocalCharacter()
		local rallied = false
		for _, v in (if type(data.allies) == "table" then data.allies else {}) :: { any } do
			local ally = asModel(v)
			if ally then
				rally(fx, ally, buffTime)
				rallied = rallied or ally == localChar
			end
		end
		if fx.IsLocal then
			fx.Screen.Pulse("Ult")
		elseif rallied then
			fx.Screen.Tint(ORANGE, 0.18, 0.7)
		end
		if char then
			PatienceKit.UltHeart(fx, char, ORANGE)
		end
	end
end

Predict.BurningCourage = function(fx: any, _payload: Map)
	gatherFlames(fx)
end

Indicator.BurningCourage = function(fx: any): Map?
	return Kit.LeapIndicator(fx, ORANGE, numbers("BurningCourage").Radius or 14, 9)
end

---------------------------------------------------------------------------------------------------
-- Passive visuals: Unbreakable guard + ult heart

local function guardShield(fx: any, character: Model)
	local st = fx.State
	if st.Guard then
		return
	end
	local Lib = fx.VFX
	local token = {}
	st.Guard = token
	local shield = Lib.Part("Cylinder", Vector3.new(0.3, 0.1, 0.1), PARK, GOLD, FIELD, 0)
	local rim = Lib.Part("Cylinder", Vector3.new(0.12, 0.1, 0.1), PARK, ORANGE, NEON, 0.55)
	local size = 0
	Lib.Animate(3600, function(_a, dt, elapsed)
		local blocking = character.Parent ~= nil
			and character:GetAttribute("Blocking") == true
			and character:GetAttribute("Dead") ~= true
		size = if blocking then math.min(1, size + dt * 9) else math.max(0, size - dt * 6)
		local r = fx.Root(character)
		if r == nil or (not blocking and size <= 0) then
			return true
		end
		local d = 5.2 * backOut(math.clamp(size, 0, 1))
		-- the cylinder axis (X) faces forward: a round guard in front of the glove
		local cf = r.CFrame * CFrame.new(0, 0.3, -1.7) * CFrame.Angles(0, math.pi / 2, 0)
		shield.Size = Vector3.new(0.3, d, d)
		rim.Size = Vector3.new(0.12, d * 1.04, d * 1.04)
		shield.CFrame = cf
		rim.CFrame = cf * CFrame.new(-0.12, 0, 0)
		rim.Transparency = 0.55 + 0.2 * math.sin(elapsed * 10)
		return nil
	end, function()
		if st.Guard == token then
			st.Guard = nil
		end
		Lib.Release(shield)
		Lib.Release(rim)
	end)
end

function Kit.OnCharacter(fx: any, character: Model)
	local function guard()
		if character:GetAttribute("Blocking") == true then
			guardShield(fx, character)
		end
	end
	local function ult()
		PatienceKit.UltHeart(fx, character, ORANGE)
	end
	fx.Trove:Connect(character:GetAttributeChangedSignal("Blocking"), guard)
	fx.Trove:Connect(character:GetAttributeChangedSignal("UltActiveUntil"), ult)
	guard()
	ult()
end

return Kit
