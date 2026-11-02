--!strict
-- Client kit: Kindness (green SOUL) — "The Cook" (SPEC §9.1). Visuals for every AbilityFx phase of
-- src/server/Kits/Kindness.luau:
--   PanBonk            Start {combo}: burnt-pan arcs (1 forehand, 2 backhand, 3 overhead), predicted locally;
--                      Bonk {targets, daze}: BONK! popup, pan clang ring, cartoon stars orbiting the head, hit-stop
--   HomeCooking        Throw {from, to, time, radius}: a pie (Dish prop) arcs to the landing point, splash of green;
--                      the Zone hazard renders with the registered "HomeCooking" zone visual (steaming butterscotch pie,
--                      rising hearts, warm light). Indicator: heal circle + throw arc dots.
--   KindShield         Shield {target, duration, amount}: green ForceField bubble that follows the target, ripples
--                      when it absorbs a hit (attribute "Shield"), shatters (SHIELD BROKEN) if emptied early, fades
--                      at the end. Indicator: ring + bubble preview on the soft-targeted ally (self when none).
--   ButterscotchFeast  Start: a giant butterscotch pie rises over the cook; Feast {radius, allies, revived, heal}: the
--                      pie bursts, a 30-stud green wave, heal bursts on every fed ally, a golden pillar + REVIVED on
--                      the revived ally, FEAST! popup.
-- OnCharacter: faint SOUL-green heart at the Chest attachment while the ult status "Feast" lasts; Nurturing — allies
--   of the cook see a faint 8-stud ring around them and soft heart motes on allies inside it every second.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Teams = require(Shared:WaitForChild("Combat"):WaitForChild("Teams")) :: any

type Map = { [string]: any }

local Kit = {}
local Effects: { [string]: (any, Map) -> () } = {}
local Predict: { [string]: (any, Map) -> () } = {}
local Indicator: { [string]: (any) -> Map? } = {}
Kit.Effects = Effects
Kit.Predict = Predict
Kit.Indicator = Indicator

local KIT_ID = "Kindness"
local GREEN = Color3.fromRGB(0, 192, 0)
local LEAF = Color3.fromRGB(90, 255, 120)
local GOLD = Color3.fromRGB(255, 205, 90)
local STEEL = Color3.fromRGB(215, 220, 225)
local CREAM = Color3.fromRGB(255, 250, 225)
local WHITE = Color3.new(1, 1, 1)
local NURTURE_RADIUS = 8

local propsModule: any = nil
local function prop(name: string): any?
	if propsModule == nil then
		local ok, m = pcall(function()
			return require(Shared:WaitForChild("Rigs"):WaitForChild("Props") :: any)
		end)
		propsModule = if ok then m else false
	end
	return if propsModule then propsModule.Get(name) else nil
end

local function buildDish(kind: string, scale: number): Model?
	local Dish = prop("Dish")
	if Dish == nil then
		return nil
	end
	local ok, m = pcall(Dish.Build, kind, scale)
	return if ok then m else nil
end

local function numbers(abilityId: string): Map
	local def = Kits.Ability(KIT_ID, abilityId)
	return if def and def.Numbers then def.Numbers else {}
end

local function rootCF(fx: any, model: Model?): CFrame?
	local r = fx.Root(model or fx.Character)
	return if r then r.CFrame else nil
end

local function handPos(fx: any): Vector3?
	local hand = fx.Part(fx.Character, "RightHand")
	if hand then
		return hand.Position
	end
	local cf = rootCF(fx)
	return if cf then (cf * CFrame.new(0.6, 0.6, -1.2)).Position else nil
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
	local heart = Lib.Soul(GREEN, 0.55)
	local parts: { BasePart } = {}
	for _, d in heart:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 0.35
			table.insert(parts, d)
		end
	end
	heart.Parent = Lib.Folder()
	local core = heart.PrimaryPart or parts[1]
	local light = if core then Lib.Light(core, LEAF, 1.2, 7) else nil
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
			local beat = math.exp(-((elapsed * 1.2) % 1) * 7)
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
-- "HomeCooking" zone visual (registered with HazardVisuals when this module loads)

local function homeCookingVisual(ctx: Map): Map
	local Lib = ctx.Lib
	local pie = buildDish("ButterscotchPie", 1.15)
	local steam: ParticleEmitter? = nil
	local hearts: ParticleEmitter? = nil
	local light: PointLight? = nil
	local shown = false
	local v: Map = {}
	function v.Update(_s: any, cf: CFrame, t: number, _dt: number)
		if pie == nil then
			return
		end
		local m: Model = pie
		local spin = CFrame.Angles(0, t * 0.6, 0)
		m:PivotTo(CFrame.new(cf.Position + Vector3.new(0, 0.05 + math.abs(math.sin(t * 2.2)) * 0.08, 0)) * spin)
		if not shown then
			shown = true
			m.Parent = Lib.Folder()
			local base = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
			if base then
				local scale = Lib.ParticleScale()
				steam = Lib.Emitter("Smoke", base, { Color = CREAM, Rate = 5 * scale })
				hearts = Lib.Emitter("Heal", base, { Color = LEAF, Rate = 4 * scale })
				light = Lib.Light(base, GOLD, 1.6, 14)
			end
		end
	end
	function v.Destroy(_s: any)
		if steam then
			steam:Destroy()
		end
		if hearts then
			hearts:Destroy()
		end
		if light then
			light:Destroy()
		end
		if pie then
			local m: Model = pie
			local pos = m:GetPivot().Position
			Lib.Emit("Heal", pos + Vector3.new(0, 0.6, 0), 6, { Color = LEAF })
			m:Destroy()
		end
	end
	return v
end

pcall(function()
	local controllers = script.Parent.Parent:WaitForChild("Controllers")
	local HazardVisuals = require(controllers:WaitForChild("HazardVisuals") :: any) :: any
	HazardVisuals.RegisterVisual("HomeCooking", homeCookingVisual)
end)

---------------------------------------------------------------------------------------------------
-- Pan Bonk (M1)

local function panSwing(fx: any, combo: number)
	local Lib = fx.VFX
	fx.Delay(0.07, function()
		local cf = rootCF(fx)
		if cf == nil then
			return
		end
		local base = cf * CFrame.new(0, 0.5, 0)
		local i = ((combo - 1) % 3) + 1
		if i == 1 then
			Lib.Slash(
				base * CFrame.Angles(0, 0, math.rad(10)),
				{ Radius = 3.6, From = 75, To = -75, Width = 0.9, Color = GREEN, Core = STEEL, Duration = 0.16 }
			)
		elseif i == 2 then
			Lib.Slash(
				base * CFrame.Angles(0, 0, math.rad(-12)),
				{ Radius = 3.6, From = -75, To = 75, Width = 0.9, Color = GREEN, Core = STEEL, Duration = 0.16 }
			)
		else
			Lib.Slash(base * CFrame.Angles(0, 0, math.rad(90)), {
				Radius = 3.9,
				From = -95,
				To = 70,
				Width = 1.3,
				Color = LEAF,
				Core = WHITE,
				Duration = 0.2,
				Segments = 16,
			})
		end
		local hand = handPos(fx)
		if hand then
			Lib.Emit("Ember", hand, 2, { Color = Color3.fromRGB(255, 140, 60) })
		end
		fx.Sound("Whoosh", fx.Root(fx.Character), { Pitch = if i == 3 then 0.75 else 0.95 + 0.05 * i })
	end)
end

local function dizzyStars(fx: any, target: Model, duration: number)
	local Lib = fx.VFX
	local stars: { BasePart } = {}
	for k = 1, 3 do
		stars[k] = Lib.Part("Block", Vector3.new(0.45, 0.45, 0.12), CFrame.new(), GOLD, Enum.Material.Neon, 0)
	end
	Lib.Animate(duration, function(a, _dt, elapsed)
		local head = fx.Part(target, "Head")
		local r = fx.Root(target)
		local top = if head then head.Position + Vector3.new(0, 1.1, 0) elseif r then r.Position + Vector3.new(0, 3.4, 0) else nil
		if top == nil then
			return true
		end
		for k, s in stars do
			local ang = elapsed * 7 + k * math.pi * 2 / 3
			s.CFrame = CFrame.new(top + Vector3.new(math.cos(ang) * 1.1, math.sin(elapsed * 9 + k) * 0.15, math.sin(ang) * 1.1))
				* CFrame.Angles(0, -ang, math.rad(45) + elapsed * 6)
			s.Transparency = if a > 0.75 then (a - 0.75) / 0.25 else 0
		end
		return nil
	end, function()
		for _, s in stars do
			Lib.Release(s)
		end
	end)
end

Effects.PanBonk = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	if packet.phase == "Start" then
		if not fx.Predicted then
			panSwing(fx, data.combo or 1)
		end
	elseif packet.phase == "Bonk" then
		local daze = if type(data.daze) == "number" then data.daze else 0.4
		for _, v in (if type(data.targets) == "table" then data.targets else {}) do
			local target = asModel(v)
			local head = if target then (fx.Part(target, "Head") or fx.Root(target)) else nil
			if target and head then
				local pos = head.Position + Vector3.new(0, 0.6, 0)
				Lib.Text(pos + Vector3.new(0, 1.8, 0), Strings.L("fx.kindness.bonk"), GOLD, { Kind = "Alert", Scale = 1.5 })
				Lib.Ring(CFrame.new(pos), 2.6, WHITE, 0.22, 0.2)
				Lib.Flash(pos, CREAM, 3, 0.12)
				Lib.Emit("Star", pos, 6, { Color = GOLD, Speed = { 4, 9 } })
				dizzyStars(fx, target, math.max(0.9, daze + 0.5))
				fx.HitStop(target, 0.12)
				fx.Sound("Ding", pos, { Pitch = 0.72 })
				fx.Sound("HitHeavy", pos, { Volume = 0.7 })
			end
		end
		fx.HitStop(fx.Character, 0.08)
		if fx.IsLocal then
			fx.Shake(0.25, 0.15)
		end
	end
end

Predict.PanBonk = function(fx: any, _payload: Map)
	local combat = fx.Combat()
	local idx = 1
	if combat and type(combat.ComboIndex) == "function" then
		local ok, i = pcall(combat.ComboIndex)
		if ok and type(i) == "number" and i > 0 then
			idx = i
		end
	end
	panSwing(fx, idx)
end

---------------------------------------------------------------------------------------------------
-- Home Cooking (Q)

local function arcPoint(from: Vector3, to: Vector3, height: number, a: number): Vector3
	return from:Lerp(to, a) + Vector3.new(0, 4 * height * a * (1 - a), 0)
end

Effects.HomeCooking = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	if packet.phase == "Start" then
		if not fx.Predicted then
			local hand = handPos(fx)
			if hand then
				Lib.EmitBurst(hand, 1.8, LEAF, 0.15)
			end
		end
	elseif packet.phase == "Throw" and typeof(data.from) == "Vector3" and typeof(data.to) == "Vector3" then
		local from: Vector3, to: Vector3 = data.from, data.to
		local time = if type(data.time) == "number" then math.max(0.1, data.time) else 0.5
		local radius = if type(data.radius) == "number" then data.radius else 9
		local height = 2.5 + (to - from).Magnitude * 0.12
		local dish = buildDish("Pie", 0.75)
		if dish then
			dish:PivotTo(CFrame.new(from))
			dish.Parent = Lib.Folder()
		end
		fx.Sound("Whoosh", from, { Pitch = 1.2 })
		local lastEmit = 0
		Lib.Animate(time, function(a, _dt, elapsed)
			local p = arcPoint(from, to, height, a)
			if dish then
				dish:PivotTo(CFrame.new(p) * CFrame.Angles(0, elapsed * 14, math.sin(elapsed * 9) * 0.25))
			end
			if elapsed - lastEmit > 0.05 then
				lastEmit = elapsed
				Lib.Emit("Heal", p, 1, { Color = LEAF })
			end
			return nil
		end, function()
			if dish then
				dish:Destroy()
			end
			Lib.EmitRing(to + Vector3.new(0, 0.2, 0), radius, LEAF, 0.35)
			Lib.Emit("Heal", to + Vector3.new(0, 0.5, 0), 10, { Color = LEAF, Speed = { 2, 6 } })
			Lib.Dust(to, 2, nil, 6)
			fx.Sound("Heal", to)
		end)
	end
end

Predict.HomeCooking = function(fx: any, _payload: Map)
	local hand = handPos(fx)
	if hand then
		fx.VFX.EmitBurst(hand, 1.8, LEAF, 0.15)
	end
end

Indicator.HomeCooking = function(fx: any): Map?
	local Lib = fx.VFX
	local radius = numbers("HomeCooking").Radius or 9
	local circle = Lib.GroundCircle(Vector3.zero, radius, LEAF, { Rim = 0.3, Fill = 0.85, Height = 0.2 })
	local dots: { BasePart } = {}
	for k = 1, 8 do
		dots[k] = Lib.Part("Ball", Vector3.one * 0.32, CFrame.new(), LEAF, Enum.Material.Neon, 0.25)
	end
	local handle: Map = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		circle:SetCenter(aim)
		local from = handPos(fx)
		if from == nil then
			return
		end
		local height = 2.5 + (aim - from).Magnitude * 0.12
		local phase = (os.clock() * 1.5) % 1
		for k, d in dots do
			local a = math.clamp((k - 1 + phase) / #dots, 0, 1)
			d.CFrame = CFrame.new(arcPoint(from, aim, height, a))
		end
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
-- Kind Shield (E)

type Bubble = { Target: Model, EndsAt: number, Dead: boolean, Outer: BasePart, Inner: BasePart, Light: PointLight? }
local bubbles: { [Model]: Bubble } = setmetatable({}, { __mode = "k" }) :: any

local function shieldBubble(fx: any, target: Model, duration: number)
	local Lib = fx.VFX
	local endsAt = fx.Now() + duration
	local existing = bubbles[target]
	if existing and not existing.Dead then
		existing.EndsAt = math.max(existing.EndsAt, endsAt)
		Lib.EmitBurst(existing.Outer.Position, 6, LEAF, 0.2)
		return
	end
	local r = fx.Root(target)
	if r == nil then
		return
	end
	local outer = Lib.Part("Ball", Vector3.one * 6.6, r.CFrame, LEAF, Enum.Material.ForceField, 0)
	local inner = Lib.Part("Ball", Vector3.one * 6.2, r.CFrame, GREEN, Enum.Material.Neon, 0.9)
	local b: Bubble = { Target = target, EndsAt = endsAt, Dead = false, Outer = outer, Inner = inner, Light = nil }
	b.Light = Lib.Light(inner, LEAF, 1.2, 10)
	bubbles[target] = b
	local lastShield = target:GetAttribute("Shield")
	local ripple = 0
	local broken = false
	local seen = false -- the status attribute may replicate a frame after the Fx packet
	Lib.Animate(duration + 30, function(_a, dt, elapsed)
		if b.Dead then
			return true
		end
		local rr = fx.Root(target)
		if rr == nil or target.Parent == nil or target:GetAttribute("Dead") == true then
			return true
		end
		local now = fx.Now()
		local status = target:GetAttribute("Status_Shielded")
		local active = type(status) == "number" and status > now
		if active then
			seen = true
			b.EndsAt = math.max(b.EndsAt, status)
		elseif seen or elapsed > 0.6 or now >= b.EndsAt then
			broken = seen and now < b.EndsAt - 0.15
			return true
		end
		local amount = target:GetAttribute("Shield")
		if type(amount) == "number" and type(lastShield) == "number" and amount < lastShield - 0.01 then
			ripple = 1 -- absorbed a hit
			Lib.EmitBurst(rr.Position, 4.5, LEAF, 0.15)
		end
		lastShield = amount
		ripple = math.max(0, ripple - dt * 5)
		local pop = math.clamp(elapsed / 0.15, 0, 1)
		local size = 6.6 * (0.6 + 0.4 * (1 - (1 - pop) ^ 3)) * (1 + 0.04 * math.sin(elapsed * 5))
		local cf = rr.CFrame
		outer.Size = Vector3.one * size
		inner.Size = Vector3.one * (size - 0.4)
		outer.CFrame = cf
		inner.CFrame = cf
		local left = b.EndsAt - now
		local fade = if left < 0.6 then (0.6 - left) / 0.6 * 0.5 else 0
		inner.Transparency = math.clamp(0.9 - 0.35 * ripple + fade, 0, 1)
		outer.Transparency = math.clamp(fade * 2, 0, 1)
		return nil
	end, function()
		b.Dead = true
		if bubbles[target] == b then
			bubbles[target] = nil
		end
		local pos = outer.Position
		if broken then
			Lib.Shatter(outer.CFrame, 6, LEAF, 12)
			Lib.Text(pos + Vector3.new(0, 3.4, 0), Strings.L("fx.kindness.shieldBreak"), LEAF, { Kind = "Alert" })
			fx.Sound("GuardBreak", pos, { Pitch = 1.2 })
		else
			Lib.Emit("Mote", pos, 8, { Color = LEAF })
		end
		Lib.Release(outer)
		Lib.Release(inner)
		if b.Light then
			b.Light:Destroy()
		end
	end)
end

Effects.KindShield = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	if packet.phase == "Start" then
		if not fx.Predicted then
			local hand = handPos(fx)
			if hand then
				Lib.EmitBurst(hand, 2, LEAF, 0.15)
			end
		end
	elseif packet.phase == "Shield" then
		local target = asModel(data.target)
		if target == nil then
			return
		end
		local duration = if type(data.duration) == "number" then data.duration else 5
		local from = fx.Chest(fx.Character)
		local to = fx.Chest(target)
		if from and to and target ~= fx.Character then
			Lib.Beam(from, to, 0.35, LEAF, 0.25)
			Lib.Emit("Heal", to, 4, { Color = LEAF })
		end
		if to then
			Lib.Text(to + Vector3.new(0, 2.6, 0), Strings.L("fx.kindness.shield"), LEAF, { Kind = "Alert", Scale = 0.9 })
			fx.Sound("Shield", to)
		end
		shieldBubble(fx, target, duration)
	end
end

Predict.KindShield = function(fx: any, _payload: Map)
	local hand = handPos(fx)
	if hand then
		fx.VFX.EmitBurst(hand, 2, LEAF, 0.15)
	end
end

Indicator.KindShield = function(fx: any): Map?
	local Lib = fx.VFX
	local ring = Lib.GroundCircle(Vector3.zero, 2.6, LEAF, { Rim = 0.25, Fill = 0.8, Height = 0.18 })
	local ghost = Lib.Part("Ball", Vector3.one * 6.4, CFrame.new(), LEAF, Enum.Material.ForceField, 0.4)
	local handle: Map = {}
	function handle.Update(_self: any, _aim: Vector3, _charge: number, target: Model?)
		local who = target or fx.Character
		local r = if who then fx.Root(who) else nil
		if r then
			ring:SetVisible(true)
			ring:SetCenter(r.Position - Vector3.new(0, 2.8, 0))
			ghost.CFrame = r.CFrame
			ghost.Transparency = 0.4
		else
			ring:SetVisible(false)
			ghost.Transparency = 1
		end
	end
	function handle.Destroy(_self: any)
		ring:Destroy()
		Lib.Release(ghost)
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Butterscotch Feast (R, ultimate)

local function raisePie(fx: any)
	local char = fx.Character
	if char == nil or fx.State.FeastPie then
		return
	end
	local Lib = fx.VFX
	local pie = buildDish("ButterscotchPie", 1.9)
	if pie == nil then
		return
	end
	local m: Model = pie
	fx.State.FeastPie = m
	m.Parent = Lib.Folder()
	local base = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	local light = if base then Lib.Light(base, GOLD, 2.5, 16) else nil
	Lib.Animate(1.2, function(a, _dt, elapsed)
		if m.Parent == nil then
			return true
		end
		local r = fx.Root(char)
		if r == nil then
			return true
		end
		local rise = 1 - (1 - math.clamp(a / 0.35, 0, 1)) ^ 3
		m:PivotTo(CFrame.new(r.Position + Vector3.new(0, 2 + 2.6 * rise, 0)) * CFrame.Angles(0, elapsed * 3, 0))
		return nil
	end, function()
		if light then
			light:Destroy()
		end
		if fx.State.FeastPie == m then
			fx.State.FeastPie = nil
		end
		if m.Parent then
			m:Destroy()
		end
	end)
	Lib.Emit("Heal", (fx.Chest(char) or Vector3.zero), 8, { Color = GOLD })
	fx.Sound("SoulAppear", fx.Root(char), { Pitch = 1.3 })
end

Effects.ButterscotchFeast = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	if packet.phase == "Start" then
		if not fx.Predicted then
			raisePie(fx)
		end
		ultHeart(fx, fx.Now() + 0.4 + (numbers("ButterscotchFeast").SpeedTime or 4))
	elseif packet.phase == "Feast" then
		local char = fx.Character
		local r = fx.Root(char)
		local pie: Model? = fx.State.FeastPie
		local burstAt = if pie then pie:GetPivot().Position elseif r then r.Position + Vector3.new(0, 4.5, 0) else nil
		if pie then
			fx.State.FeastPie = nil
			pie:Destroy()
		end
		if burstAt then
			Lib.EmitBurst(burstAt, 9, GOLD, 0.3)
			Lib.Emit("Heal", burstAt, 18, { Color = LEAF, Speed = { 4, 12 } })
			Lib.Emit("Star", burstAt, 10, { Color = GOLD, Speed = { 6, 14 } })
			Lib.Text(burstAt + Vector3.new(0, 2, 0), Strings.L("fx.kindness.feast"), GOLD, { Kind = "Alert", Scale = 1.3 })
			fx.Sound("Heal", burstAt, { Pitch = 0.9 })
		end
		if r then
			local feet = r.Position - Vector3.new(0, 2.8, 0)
			local radius = if type(data.radius) == "number" then data.radius else 30
			Lib.Shockwave(feet, radius, LEAF, 0.8)
			Lib.EmitRing(feet + Vector3.new(0, 0.3, 0), radius * 0.6, GOLD, 0.6)
		end
		local localChar = fx.LocalCharacter()
		for _, v in (if type(data.allies) == "table" then data.allies else {}) do
			local ally = asModel(v)
			local chest = if ally then fx.Chest(ally) else nil
			if ally and chest then
				Lib.EmitBurst(chest, 3, LEAF, 0.25)
				Lib.Emit("Heal", chest, 6, { Color = LEAF })
				Lib.Ring(CFrame.new(chest - Vector3.new(0, 2.6, 0)), 2.8, GOLD, 0.4, 0.15)
				if burstAt and ally ~= char then
					Lib.Line(burstAt, chest, GOLD, 0.12, 0.3)
				end
				if ally == localChar then
					fx.Screen.Pulse("Heal")
				end
			end
		end
		local revived = asModel(data.revived)
		local rr = if revived then fx.Root(revived) else nil
		if revived and rr then
			local feet = rr.Position - Vector3.new(0, 2.8, 0)
			Lib.Beam(feet, feet + Vector3.new(0, 18, 0), 2.6, GOLD, 0.7)
			Lib.Flash(rr.Position, CREAM, 6, 0.3)
			Lib.Text(rr.Position + Vector3.new(0, 3.5, 0), Strings.L("fx.revived"), GOLD, { Kind = "Alert", Scale = 1.2 })
			fx.Sound("Revive", rr.Position)
		end
		if fx.IsLocal then
			fx.Screen.Pulse("Ult")
		end
	end
end

Predict.ButterscotchFeast = function(fx: any, _payload: Map)
	raisePie(fx)
end

---------------------------------------------------------------------------------------------------
-- Passive visuals

local function nurturing(fx: any, character: Model)
	local Lib = fx.VFX
	-- only the cook's allies care about the regen radius
	local lc = fx.LocalCharacter()
	if lc == nil or fx.IsEnemy(character) then
		return
	end
	local ring = Lib.GroundCircle(Vector3.zero, NURTURE_RADIUS, LEAF, { Rim = 0.12, Fill = 1, Height = 0.12 })
	ring:SetTransparency(0.8, 1)
	ring:SetVisible(false)
	local st = { Dead = false }
	local function stop()
		if not st.Dead then
			st.Dead = true
			ring:Destroy()
		end
	end
	fx.Trove:Add(stop)
	local acc = 0
	Lib.Animate(1e7, function(_a, dt, _elapsed)
		if st.Dead or character.Parent == nil or character:GetAttribute("Dead") == true then
			return true
		end
		local r = fx.Root(character)
		local up = r ~= nil and character:GetAttribute("Downed") ~= true
		ring:SetVisible(up)
		if not up or r == nil then
			return nil
		end
		local pos = r.Position
		ring:SetCenter(pos - Vector3.new(0, 2.85, 0))
		acc += dt
		local pulse = math.exp(-acc * 5)
		ring:SetTransparency(0.82 - 0.25 * pulse, 1)
		if acc >= 1 then
			acc = 0
			for _, other in Lib.Characters() do
				if other ~= character and other:GetAttribute("Downed") ~= true and Teams.AreAllies(character, other) then
					local orr = fx.Root(other)
					if orr and (orr.Position - pos).Magnitude <= NURTURE_RADIUS then
						Lib.Emit("Heal", orr.Position + Vector3.new(0, 0.5, 0), 2, { Color = LEAF })
					end
				end
			end
		end
		return nil
	end, stop)
end

function Kit.OnCharacter(fx: any, character: Model)
	local function check()
		local v = character:GetAttribute("Status_Feast")
		if type(v) == "number" and v > fx.Now() + 0.2 then
			ultHeart(fx, v)
		end
	end
	fx.Trove:Connect(character:GetAttributeChangedSignal("Status_Feast"), check)
	check()
	nurturing(fx, character)
end

return Kit
