--!strict
-- Client kit: Patience (cyan SOUL) — "The Quiet One" (SPEC §9.1). Visuals for every AbilityFx phase of
-- src/server/Kits/Patience.luau:
--   ToyKnife     Start {combo}: quick cyan thrust streaks (3rd stab longer, ringed), predicted locally;
--                Strike {last, hits}: small burst on a landed finisher
--   RibbonSnare  Start: ribbon flick at the hand; Throw: whoosh; projectile visual "PatienceRibbon" (tumbling bow knot,
--                waving tails, trail, light); Snare {target, time}: two ribbon loops cinch around the target for the
--                slow + "SNARED"
--   Patience     Start: ribbon swirl; Fade {duration}: vanish burst; Reveal: re-appear burst; Ambush {target, pos}:
--                cyan X on the target + "AMBUSH!" + hit-stop. The stealth itself is rendered from the replicated
--                Invisible attribute (OnCharacter): enemies see nothing (only a faint shimmer while dashing), allies
--                and the player a translucent ghost with drifting motes.
--   WaitingGame  Start: clock glint; Field {center, radius, duration}: chime; zone visual "PatienceClock" (12 hour
--                marks + sweeping hands on the ground, slow-motion ghosts of enemies inside, a cyan time tint +
--                "TIME SLOWS..." for a local enemy inside). Indicator: clock-face circle at the aim.
-- OnCharacter: stealth rendering, Calm (attribute CalmActive: rising motes + breathing ring, hidden from enemies while
-- invisible), faint cyan SOUL heart at the Chest while UltActiveUntil is in the future.
-- Kit.StealthAlpha(isSelf, isEnemy) -> number   PURE: LocalTransparencyModifier for a viewer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Teams = require(Shared:WaitForChild("Combat"):WaitForChild("Teams")) :: any

local ClientRoot = script.Parent.Parent
local HazardVisuals = require(ClientRoot:WaitForChild("Controllers"):WaitForChild("HazardVisuals")) :: any
local ScreenFX = require(ClientRoot:WaitForChild("VFX"):WaitForChild("ScreenFX")) :: any

type Map = { [string]: any }

local Kit = {}
local Effects: { [string]: (any, Map) -> () } = {}
local Predict: { [string]: (any, Map) -> () } = {}
local Indicator: { [string]: (any) -> Map? } = {}
Kit.Effects = Effects
Kit.Predict = Predict
Kit.Indicator = Indicator

local CYAN = Color3.fromRGB(66, 252, 255)
local PALE = Color3.fromRGB(215, 255, 255)
local PARK = CFrame.new(0, 25000, 0)
local NEON = Enum.Material.Neon
local TAU = math.pi * 2

local SELF_ALPHA = 0.7 -- how see-through a hidden Patience is for herself / allies
local FADE_TIME = 0.28

local function numbers(abilityId: string): Map
	local a = Kits.Ability("Patience", abilityId)
	return if a and a.Numbers then a.Numbers else {}
end

local function rootCF(fx: any): CFrame?
	local r = fx.Root(fx.Character)
	return if r then r.CFrame else nil
end

local workspaceRef: any = nil
local function bulkMove(parts: { BasePart }, cfs: { CFrame })
	if workspaceRef == nil then
		workspaceRef = game:GetService("Workspace")
	end
	workspaceRef:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function localCharacter(): Model?
	local lp = Players.LocalPlayer
	return if lp then lp.Character else nil
end

function Kit.StealthAlpha(isSelf: boolean, isEnemy: boolean): number
	if isEnemy and not isSelf then
		return 1
	end
	return SELF_ALPHA
end

---------------------------------------------------------------------------------------------------
-- Faint SOUL heart at the chest while the ultimate is active (attribute UltActiveUntil)

local function ultHeart(fx: any, character: Model, color: Color3)
	local st = fx.State
	local untilT = character:GetAttribute("UltActiveUntil")
	if st.UltHeart or type(untilT) ~= "number" or untilT <= fx.Now() + 0.1 then
		return
	end
	local Lib = fx.VFX
	local heart = Lib.Soul(color, 0.62)
	heart.Parent = Lib.Folder()
	local visible: { BasePart } = {}
	for _, d in heart:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			table.insert(visible, d)
		end
	end
	local core = heart.PrimaryPart or heart:FindFirstChildWhichIsA("BasePart", true)
	local light = if core then Lib.Light(core, color, 1, 7) else nil
	local token = {}
	st.UltHeart = token
	local function stop()
		if st.UltHeart ~= token then
			return
		end
		st.UltHeart = nil
		heart:Destroy()
		if light then
			light:Destroy()
		end
	end
	fx.Trove:Add(stop)
	Lib.Animate(60, function(_a, _dt, elapsed)
		local u = character:GetAttribute("UltActiveUntil")
		if
			st.UltHeart ~= token
			or character.Parent == nil
			or character:GetAttribute("Dead") == true
			or type(u) ~= "number"
			or fx.Now() > u
		then
			return true
		end
		local att = fx.Attachment(character, "Chest")
		local pos: Vector3? = if att then att.WorldPosition else fx.Chest(character)
		if pos then
			local r = fx.Root(character)
			local look = if r then r.CFrame.LookVector else Vector3.new(0, 0, -1)
			local beat = math.exp(-((elapsed * 1.4) % 1) * 7)
			heart:PivotTo(Lib.LookAlong(pos + look * 0.5, look))
			for _, p in visible do
				p.Transparency = 0.45 - 0.2 * beat -- faint, brightening on each beat
			end
			if light then
				light.Brightness = 0.6 + 1.6 * beat
			end
		end
		return nil
	end, stop)
end
Kit.UltHeart = ultHeart

---------------------------------------------------------------------------------------------------
-- Toy Knife (M1): stabs

local function stab(fx: any, combo: number)
	fx.Delay(0.05, function()
		local cf = rootCF(fx)
		if cf == nil then
			return
		end
		local Lib = fx.VFX
		local i = ((combo - 1) % 3) + 1
		local big = i == 3
		local side = if i == 2 then -0.55 else 0.5
		local from = (cf * CFrame.new(side, if big then 0.8 else 0.45, -1)).Position
		local tip = from + cf.LookVector * (if big then 4.6 else 3.6)
		Lib.Line(from, tip, CYAN, if big then 0.5 else 0.34, 0.2)
		Lib.Line(from, tip, PALE, if big then 0.2 else 0.13, 0.14)
		Lib.EmitRing(tip, if big then 2 else 1.2, CYAN, 0.2, { Axis = cf.LookVector })
		Lib.Emit("Mote", tip, if big then 7 else 3, { Color = CYAN, Dir = cf.LookVector, Speed = { 3, 9 } })
		if big then
			Lib.EmitBurst(tip, 2.4, CYAN, 0.18)
		end
		fx.Sound("Slash", fx.Root(fx.Character), { Pitch = 1.3 + 0.07 * i, Volume = 0.8 })
	end)
end

Effects.ToyKnife = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			stab(fx, data.combo or 1)
		end
	elseif packet.phase == "Strike" and data.last and (data.hits or 0) > 0 then
		local cf = rootCF(fx)
		if cf then
			local front = (cf * CFrame.new(0, 0.6, -3.6)).Position
			fx.VFX.EmitBurst(front, 3, CYAN, 0.18)
			fx.VFX.Sparks(front, cf.LookVector, PALE, 8, 22)
		end
	end
end

Predict.ToyKnife = function(fx: any, _payload: Map)
	local idx = 1
	local combat = fx.Combat()
	if combat and type(combat.ComboIndex) == "function" then
		local ok, i = pcall(combat.ComboIndex)
		if ok and type(i) == "number" and i > 0 then
			idx = i
		end
	end
	stab(fx, idx)
end

---------------------------------------------------------------------------------------------------
-- Ribbon Snare (Q)

local function flick(fx: any)
	local cf = rootCF(fx)
	if cf == nil then
		return
	end
	local hand = fx.Part(fx.Character, "RightHand")
	local at = if hand then hand.Position else (cf * CFrame.new(0.8, 0.6, -0.6)).Position
	fx.VFX.Slash(
		CFrame.new(at) * (cf - cf.Position) * CFrame.Angles(0, 0, math.rad(-30)),
		{ Radius = 1.8, From = 70, To = -60, Width = 0.32, Color = CYAN, Core = PALE, Duration = 0.2, Sparks = false }
	)
	fx.VFX.Emit("Mote", at, 3, { Color = CYAN })
end

-- two ribbon loops that cinch around the target (waist + knees) for the slow
local function wrap(fx: any, target: Model, time: number)
	local Lib = fx.VFX
	local r0 = fx.Root(target)
	if r0 == nil then
		return
	end
	local SEG = 10
	local loops = {
		{ H = 0.3, R = 2, Tilt = 0.22, Speed = 2.4 },
		{ H = -1.7, R = 1.6, Tilt = -0.18, Speed = -3 },
	}
	local parts: { BasePart } = {}
	for _, L in loops do
		local chord = 2 * L.R * math.sin(math.pi / SEG) * 1.15
		for _ = 1, SEG do
			table.insert(parts, Lib.Part("Block", Vector3.new(chord, 0.12, 0.34), PARK, CYAN, NEON, 0.15))
		end
	end
	local cfs: { CFrame } = table.create(#parts)
	Lib.Text(
		r0.Position + Vector3.new(0, 3.4, 0),
		Strings.L("fx.patience.snared"),
		CYAN,
		{ Kind = "Alert", Scale = 0.9 }
	)
	Lib.EmitBurst(r0.Position, 3.2, CYAN, 0.22)
	fx.Sound("SoulGrab", r0, { Pitch = 1.3, Volume = 0.6 })
	Lib.Animate(math.max(0.3, time), function(a, _dt, elapsed)
		local r = fx.Root(target)
		if r == nil or target.Parent == nil then
			return true
		end
		local cinch = 1 - 0.3 * math.min(1, elapsed / 0.22)
		local fade = if a > 0.8 then (a - 0.8) / 0.2 else 0
		local k = 0
		for _, L in loops do
			local frame = CFrame.new(r.Position + Vector3.new(0, L.H, 0)) * CFrame.Angles(L.Tilt, elapsed * L.Speed, 0)
			for s = 1, SEG do
				k += 1
				cfs[k] = frame * CFrame.Angles(0, (s / SEG) * TAU, 0) * CFrame.new(0, 0, -L.R * cinch)
				parts[k].Transparency = 0.15 + 0.85 * fade
			end
		end
		bulkMove(parts, cfs)
		return nil
	end, function()
		for _, p in parts do
			Lib.Release(p)
		end
	end)
end

Effects.RibbonSnare = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			flick(fx)
		end
	elseif packet.phase == "Throw" then
		fx.Sound("Whoosh", fx.Root(fx.Character), { Pitch = 1.35, Volume = 0.6 })
	elseif packet.phase == "Snare" then
		local target = data.target
		if typeof(target) == "Instance" and target:IsA("Model") then
			wrap(fx, target, if type(data.time) == "number" then data.time else 2.5)
		end
	end
end

Predict.RibbonSnare = function(fx: any, _payload: Map)
	flick(fx)
end

-- Projectile visual: tumbling bow knot with two loops, six waving tails, a trail and a light.
HazardVisuals.RegisterVisual("PatienceRibbon", function(ctx: Map)
	local Lib = ctx.Lib
	local c: Color3 = CYAN
	local knot = Instance.new("Part")
	knot.Name = "PatienceRibbonKnot"
	knot.Shape = Enum.PartType.Ball
	knot.Size = Vector3.new(0.5, 0.5, 0.5)
	knot.Material = NEON
	knot.Color = PALE
	knot.Anchored = true
	knot.CanCollide = false
	knot.CanQuery = false
	knot.CanTouch = false
	knot.CastShadow = false
	knot.CFrame = PARK
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.3, 0)
	a0.Parent = knot
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.3, 0)
	a1.Parent = knot
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(PALE, c)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Lifetime = 0.28
	trail.MinLength = 0.05
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Parent = knot
	knot.Parent = Lib.Folder()
	local light = Lib.Light(knot, c, 1.4, 9)
	local parts: { BasePart } = {
		knot,
		Lib.Part("Block", Vector3.new(0.85, 0.1, 0.5), PARK, c, NEON, 0.05),
		Lib.Part("Block", Vector3.new(0.85, 0.1, 0.5), PARK, c, NEON, 0.05),
	}
	for i = 1, 6 do
		table.insert(parts, Lib.Part("Block", Vector3.new(0.42, 0.06, 0.62), PARK, c, NEON, 0.08 + i * 0.12))
	end
	local cfs: { CFrame } = table.create(#parts)
	local v: Map = {}
	function v.Update(_s: any, cf: CFrame, t: number, _dt: number)
		local tumble = cf * CFrame.Angles(0, 0, t * 10)
		cfs[1] = tumble
		cfs[2] = tumble * CFrame.new(-0.45, 0, 0.1) * CFrame.Angles(0, math.rad(25), 0)
		cfs[3] = tumble * CFrame.new(0.45, 0, 0.1) * CFrame.Angles(0, math.rad(-25), 0)
		for i = 1, 6 do
			local wave = math.sin(t * 16 - i * 0.9)
			cfs[3 + i] = cf
				* CFrame.new(wave * 0.09 * i, math.cos(t * 11 - i) * 0.04 * i, 0.3 + i * 0.55)
				* CFrame.Angles(0, 0, wave * 0.6)
		end
		bulkMove(parts, cfs)
	end
	function v.Impact(_s: any, pos: Vector3)
		Lib.EmitBurst(pos, 3, c, 0.2)
		Lib.EmitRing(pos, 2.4, c, 0.25)
		Lib.Emit("Mote", pos, 10, { Color = c, Speed = { 4, 12 } })
	end
	function v.Destroy(_s: any)
		if light then
			light:Destroy()
		end
		knot:Destroy()
		for i = 2, #parts do
			Lib.Release(parts[i])
		end
	end
	return v
end)

---------------------------------------------------------------------------------------------------
-- Patience (E): stealth

local function gather(fx: any)
	local char = fx.Character
	local r = fx.Root(char)
	if r == nil then
		return
	end
	local Lib = fx.VFX
	local feet = r.Position - Vector3.new(0, 2.8, 0)
	Lib.Ring(CFrame.new(feet + Vector3.new(0, 0.2, 0)), 2.6, CYAN, 0.45, 0.12)
	Lib.Emit("Mote", r.Position, 8, { Color = CYAN, Dir = Vector3.yAxis, Speed = { 1, 4 } })
end

Effects.Patience = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local char = fx.Character
	local chest = if char then fx.Chest(char) else nil
	if packet.phase == "Start" then
		if not fx.Predicted then
			gather(fx)
		end
	elseif packet.phase == "Fade" then
		if chest then
			Lib.EmitBurst(chest, 3.6, CYAN, 0.35)
			Lib.Emit("SoulDust", chest, 14, { Color = CYAN, Speed = { 2, 6 } })
			fx.Sound("Afterimage", chest, { Pitch = 0.8 })
		end
		if fx.IsLocal then
			fx.Screen.Tint(CYAN, 0.16, 0.6)
		end
	elseif packet.phase == "Reveal" then
		if chest then
			Lib.EmitBurst(chest, 3, CYAN, 0.25)
			Lib.Emit("Mote", chest, 12, { Color = CYAN, Speed = { 4, 10 } })
			fx.Sound("Afterimage", chest, { Pitch = 1.25 })
		end
	elseif packet.phase == "Ambush" then
		local target = data.target
		local pos: Vector3? = if typeof(data.pos) == "Vector3" then data.pos else nil
		local tr = if typeof(target) == "Instance" and target:IsA("Model") then fx.Root(target) else nil
		if tr then
			pos = tr.Position
		end
		if pos == nil then
			return
		end
		local from = rootCF(fx)
		local face = Lib.LookAlong(pos, if from then from.Position - pos else Vector3.zAxis)
		-- cyan X: two crossing stabs through the target
		for _, sgn in { 1, -1 } do
			local axis = (face * CFrame.Angles(0, 0, math.rad(45 * sgn))).UpVector
			Lib.Line(pos - axis * 2.4, pos + axis * 2.4, CYAN, 0.55, 0.3)
			Lib.Line(pos - axis * 2.4, pos + axis * 2.4, PALE, 0.2, 0.22)
		end
		Lib.Flash(pos, CYAN, 5, 0.22)
		Lib.EmitRing(pos, 3.4, CYAN, 0.3, { Axis = face.LookVector })
		Lib.Emit("Star", pos, 8, { Color = PALE, Speed = { 6, 14 } })
		Lib.Text(pos + Vector3.new(0, 2.6, 0), Strings.L("fx.patience.ambush"), CYAN, { Kind = "Alert", Scale = 1.15 })
		fx.Sound("Crit", pos)
		if typeof(target) == "Instance" and target:IsA("Model") then
			fx.HitStop(target, 0.12)
		end
		fx.HitStop(char, 0.12)
		if fx.IsLocal then
			fx.Shake(0.25, 0.18)
			fx.Kick(-3, 0.2)
		end
	end
end

Predict.Patience = function(fx: any, _payload: Map)
	gather(fx)
end

-- Renders a hidden Patience for this viewer until the Invisible attribute clears (then fades back in).
local function collectHideable(character: Model): { Instance }
	local out: { Instance } = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			table.insert(out, d)
		end
	end
	return out
end

local function runStealth(fx: any, character: Model)
	local st = fx.State
	if st.Stealth then
		return
	end
	local Lib = fx.VFX
	local items = collectHideable(character)
	local orig: { [Instance]: number } = {}
	for _, it in items do
		orig[it] = (it :: any).LocalTransparencyModifier
	end
	local token = {}
	st.Stealth = token
	-- the silhouette lingers where she vanished (everyone sees the vanish, nobody sees where she goes)
	Lib.Afterimage(character, CYAN, 0.55, { Transparency = 0.35, MaxParts = 24 })
	local chestAtt = fx.Attachment(character, "Chest")
	local motes = if chestAtt then Lib.Emitter("Mote", chestAtt, { Color = CYAN, Rate = 0 }) else nil
	local level = 0
	local lastHaze = 0
	local function finish()
		if st.Stealth ~= token then
			return
		end
		st.Stealth = nil
		for _, it in items do
			if it.Parent ~= nil and (orig[it] or 0) < 0.999 then
				(it :: any).LocalTransparencyModifier = orig[it] or 0
			end
		end
		if motes then
			motes.Rate = 0
			fx.Debris(motes, 1.2)
		end
	end
	fx.Trove:Add(finish)
	Lib.Animate(3600, function(_a, dt, elapsed)
		local active = character.Parent ~= nil
			and character:GetAttribute("Invisible") == true
			and character:GetAttribute("Dead") ~= true
		local isSelf = fx.LocalCharacter() == character
		local isEnemy = fx.IsEnemy(character)
		local goal = if active then Kit.StealthAlpha(isSelf, isEnemy) else 0
		local stepK = math.max(dt, 1 / 240) / FADE_TIME
		level = if level < goal then math.min(goal, level + stepK) else math.max(goal, level - stepK)
		for _, it in items do
			local o = orig[it] or 0
			if o < 0.999 and it.Parent ~= nil then
				(it :: any).LocalTransparencyModifier = math.max(o, level)
			end
		end
		if motes then
			motes.Rate = if active and not isEnemy then 5 else 0
		end
		-- fairness: a hidden Patience who dashes leaves a faint heat haze even for enemies
		if active and isEnemy and elapsed - lastHaze > 0.25 then
			local r = fx.Root(character)
			if r and r.AssemblyLinearVelocity.Magnitude > 24 then
				lastHaze = elapsed
				Lib.Emit("Mote", r.Position - Vector3.new(0, 2, 0), 1, { Color = PALE, Speed = { 0.5, 1.5 } })
			end
		end
		if not active and level <= 0.001 then
			return true
		end
		return nil
	end, finish)
end

---------------------------------------------------------------------------------------------------
-- Calm (passive): standing still heals

local function runCalm(fx: any, character: Model)
	local st = fx.State
	if st.Calm then
		return
	end
	local Lib = fx.VFX
	local token = {}
	st.Calm = token
	local rootAtt = fx.Attachment(character, "RootAttachment")
	local motes = if rootAtt then Lib.Emitter("Heal", rootAtt, { Color = CYAN, Rate = 0 }) else nil
	local lastRing = -1
	local function finish()
		if st.Calm ~= token then
			return
		end
		st.Calm = nil
		if motes then
			motes.Rate = 0
			fx.Debris(motes, 1.5)
		end
	end
	fx.Trove:Add(finish)
	Lib.Animate(3600, function(_a, _dt, elapsed)
		if character.Parent == nil or character:GetAttribute("CalmActive") ~= true then
			return true
		end
		-- never give a hidden Patience away
		local hidden = character:GetAttribute("Invisible") == true and fx.IsEnemy(character)
		if motes then
			motes.Rate = if hidden then 0 else 3
		end
		if not hidden and elapsed - lastRing > 1.2 then
			lastRing = elapsed
			local r = fx.Root(character)
			if r then
				Lib.EmitRing(
					r.Position - Vector3.new(0, 2.7, 0),
					2.4,
					CYAN,
					1.1,
					{ Start = 0.55, Brightness = 1.4, Transparency = 0.45 }
				)
			end
		end
		return nil
	end, finish)
end

---------------------------------------------------------------------------------------------------
-- Waiting Game (R, ultimate)

Effects.WaitingGame = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	if packet.phase == "Start" then
		if not fx.Predicted then
			local hand = fx.Part(fx.Character, "RightHand")
			if hand then
				Lib.EmitBurst(hand.Position, 2.4, CYAN, 0.3)
				Lib.Emit("Star", hand.Position, 4, { Color = PALE })
			end
		end
	elseif packet.phase == "Field" and typeof(data.center) == "Vector3" then
		local r = if type(data.radius) == "number" then data.radius else 16
		Lib.EmitRing(data.center + Vector3.new(0, 0.3, 0), r, CYAN, 0.7, { Start = 0.15, Brightness = 2.5 })
		Lib.Flash(data.center + Vector3.new(0, 1.5, 0), CYAN, 6, 0.3)
		fx.Sound("Freeze", data.center, { Pitch = 0.75 })
		fx.Sound("Ding", data.center, { Pitch = 0.6, Volume = 0.7 })
		if fx.IsLocal then
			fx.Screen.Pulse("Ult")
		end
	end
	if packet.phase == "Field" then
		ultHeart(fx, fx.Character, CYAN)
	end
end

Predict.WaitingGame = function(fx: any, _payload: Map)
	local hand = fx.Part(fx.Character, "RightHand")
	if hand then
		fx.VFX.EmitBurst(hand.Position, 2, CYAN, 0.25)
	end
end

-- clock-face marks around a ground circle (shared by the indicator and the zone visual)
local function placeClock(
	parts: { BasePart },
	cfs: { CFrame },
	center: Vector3,
	radius: number,
	sweep: number,
	grow: number
)
	local base = CFrame.new(center + Vector3.new(0, 0.12, 0))
	for i = 1, 12 do
		local len = if i % 3 == 0 then 2.4 else 1.4
		cfs[i] = base * CFrame.Angles(0, -(i / 12) * TAU, 0) * CFrame.new(0, 0, -(radius - len * 0.5 - 0.6) * grow)
	end
	local minute = sweep * TAU
	local hour = sweep * TAU / 12 + math.rad(120)
	cfs[13] = base * CFrame.Angles(0, -minute, 0) * CFrame.new(0, 0.03, -radius * 0.41 * grow)
	cfs[14] = base * CFrame.Angles(0, -hour, 0) * CFrame.new(0, 0.05, -radius * 0.25 * grow)
	cfs[15] = base * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2)
	bulkMove(parts, cfs)
end

local function clockParts(Lib: any, radius: number, transparency: number): { BasePart }
	local parts: { BasePart } = {}
	for i = 1, 12 do
		local big = i % 3 == 0
		local size = Vector3.new(if big then 0.55 else 0.3, 0.12, if big then 2.4 else 1.4)
		table.insert(parts, Lib.Part("Block", size, PARK, if big then PALE else CYAN, NEON, transparency))
	end
	table.insert(parts, Lib.Part("Block", Vector3.new(0.42, 0.14, radius * 0.82), PARK, PALE, NEON, transparency))
	table.insert(parts, Lib.Part("Block", Vector3.new(0.75, 0.16, radius * 0.5), PARK, CYAN, NEON, transparency))
	table.insert(parts, Lib.Part("Cylinder", Vector3.new(0.3, 1.6, 1.6), PARK, PALE, NEON, transparency))
	return parts
end

Indicator.WaitingGame = function(fx: any): Map?
	local Lib = fx.VFX
	local radius = numbers("WaitingGame").Radius or 16
	local circle = Lib.GroundCircle(Vector3.zero, radius, CYAN, { Rim = 0.24, Fill = 0.86, Height = 0.16 })
	local parts = clockParts(Lib, radius, 0.35)
	local cfs: { CFrame } = table.create(#parts)
	local handle: Map = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		circle:SetCenter(aim)
		placeClock(parts, cfs, aim, radius, (os.clock() * 0.25) % 1, 1)
	end
	function handle.Destroy(_self: any)
		circle:Destroy()
		for _, p in parts do
			Lib.Release(p)
		end
	end
	return handle
end

-- Zone visual: the clock face, slow-motion ghosts of enemies inside, time tint for a local enemy inside.
HazardVisuals.RegisterVisual("PatienceClock", function(ctx: Map)
	local Lib = ctx.Lib
	local p = ctx.Params
	local radius: number = ctx.Size
	local delay: number = if type(p.delay) == "number" then p.delay else 0.3
	local duration: number = if type(p.duration) == "number" then p.duration else 6
	local linger: number = math.max(0.1, if type(p.linger) == "number" then p.linger else 0.3)
	local team: string = if ctx.Packet and type(ctx.Packet.team) == "string" then ctx.Packet.team else "Humans"
	local parts = clockParts(Lib, radius, 1)
	local cfs: { CFrame } = table.create(#parts)
	local lastGhost = -1
	local lastTint = -1
	local warned = false
	local function inside(model: Model, center: Vector3): boolean
		local r = model:FindFirstChild("HumanoidRootPart")
		if r == nil or not r:IsA("BasePart") then
			return false
		end
		local d = r.CFrame.Position - center
		return Vector3.new(d.X, 0, d.Z).Magnitude <= radius and d.Y > -4 and d.Y < 12
	end
	local function enemy(model: Model): boolean
		local t = model:GetAttribute("Team")
		return type(t) == "string" and Teams.AreEnemyTeams(team, t) and model:GetAttribute("Dead") ~= true
	end
	local v: Map = {}
	function v.Update(_s: any, cf: CFrame, t: number, _dt: number)
		local center = cf.Position
		local life = t - delay
		local grow = math.clamp(life / 0.35, 0, 1)
		local fade = if life > duration then math.clamp((life - duration) / linger, 0, 1) else 0
		local tr = math.max(0.12 + 0.88 * (1 - grow), fade)
		for _, part in parts do
			part.Transparency = tr
		end
		placeClock(parts, cfs, center, radius, math.clamp(life / duration, 0, 1), 0.6 + 0.4 * grow)
		if life > duration then
			return
		end
		if t - lastGhost > 0.3 then
			lastGhost = t
			for _, m in Lib.Characters() do
				if enemy(m) and inside(m, center) then
					Lib.Afterimage(m, CYAN, 0.45, { Transparency = 0.62, MaxParts = 12 })
				end
			end
		end
		local lc = localCharacter()
		if lc and enemy(lc) and inside(lc, center) then
			if t - lastTint > 0.7 then
				lastTint = t
				ScreenFX.Tint(CYAN, 0.16, 0.8)
			end
			if not warned then
				warned = true
				local r = lc:FindFirstChild("HumanoidRootPart")
				if r and r:IsA("BasePart") then
					Lib.Text(r.CFrame.Position + Vector3.new(0, 3.6, 0), Strings.L("fx.patience.timeSlows"), CYAN, {
						Kind = "Alert",
						Scale = 0.8,
					})
				end
			end
		end
	end
	function v.Destroy(_s: any)
		for _, part in parts do
			Lib.Release(part)
		end
	end
	return v
end)

---------------------------------------------------------------------------------------------------
-- Passive visuals

function Kit.OnCharacter(fx: any, character: Model)
	local function stealth()
		if character:GetAttribute("Invisible") == true then
			runStealth(fx, character)
		end
	end
	local function calm()
		if character:GetAttribute("CalmActive") == true then
			runCalm(fx, character)
		end
	end
	local function ult()
		ultHeart(fx, character, CYAN)
	end
	fx.Trove:Connect(character:GetAttributeChangedSignal("Invisible"), stealth)
	fx.Trove:Connect(character:GetAttributeChangedSignal("CalmActive"), calm)
	fx.Trove:Connect(character:GetAttributeChangedSignal("UltActiveUntil"), ult)
	stealth()
	calm()
	ult()
end

return Kit
