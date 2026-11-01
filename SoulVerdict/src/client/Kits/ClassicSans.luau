--!strict
-- Client kit: Classic Sans — "The Judge" (SPEC §9.1). Visuals for every AbilityFx phase the server kit
-- (src/server/Kits/ClassicSans.luau) broadcasts; the hazards themselves (blasters, bones) are drawn by
-- HazardVisuals from their own packets, so these effects add the caster-side flavour around them.
--
--   BoneJab        Start: conjured bone in the hand + arc swipe per combo hit (predicted); Strike: last-hit burst
--   GasterBlaster  Start: attack eye flares (cyan/yellow flicker); Summon {origins}: summoning flashes at each slot
--                  Indicator (hold): ghost blasters at the exact server slots (1..3 by charge) + aim lines
--   BlueSoul       Start: eye flashes blue; Grab {target}: blue tether hand -> SOUL + blue outline; Lift: rising
--                  sparkles; Slam: crater shockwave + dust + shake; Release: tether off. Indicator: blue ring + heart
--   BoneZone       Zone {center, radius}: summoning circle. Indicator: white circle + orange outer ring preview
--   BoneWall       Start: blue sweep at the hand + dust. (The wall is a BoneLine hazard.)
--   Shortcut       Vanish {from}: ghost + eye glint; Teleport {from, to}: arrival flash. Indicator: destination
--   BadTime (ult)  Start: eye blaze + darkening for players nearby; Blaze {center, radius, duration}: pulsing judgement
--                  circle for the duration. Indicator: area + blaster ring
-- OnCharacter: idle pupil blinks; FinalForm attribute -> permanent blazing eye. OnDamageFx: lazy-dodge flourish.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kits = require(Shared:WaitForChild("Kits")) :: any
local DamageMath = require(Shared:WaitForChild("Combat"):WaitForChild("DamageMath")) :: any

type Map = { [string]: any }

local Kit = {}
local Effects: { [string]: (any, Map) -> () } = {}
local Predict: { [string]: (any, Map) -> () } = {}
local Indicator: { [string]: (any) -> Map? } = {}
Kit.Effects = Effects
Kit.Predict = Predict
Kit.Indicator = Indicator

local KIT_ID = "ClassicSans"
local BLUE = Color3.fromRGB(20, 169, 255)
local ORANGE = Color3.fromRGB(255, 160, 64)
local SANS_CYAN = Color3.fromRGB(150, 235, 255)
local WHITE = Color3.new(1, 1, 1)

local function numbers(abilityId: string): Map
	local a = Kits.Ability(KIT_ID, abilityId)
	return if a and a.Numbers then a.Numbers else {}
end

local function rootCF(fx: any): CFrame?
	local r = fx.Root(fx.Character)
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

local function eyeFor(fx: any, color: Color3?, seconds: number)
	local char = fx.Character
	fx.EyeGlow(char, "Left", color, true)
	fx.Delay(seconds, function()
		-- FinalForm keeps the eye lit (OnCharacter re-enables it)
		if char and char:GetAttribute("FinalForm") == true and color == nil then
			return
		end
		fx.EyeGlow(char, "Left", color, false)
	end)
end

---------------------------------------------------------------------------------------------------
-- BoneJab (M1)

local function boneSwing(fx: any, comboIndex: number)
	local Lib = fx.VFX
	local char = fx.Character
	local hand = fx.Part(char, "RightHand")
	local cf = rootCF(fx)
	if cf == nil then
		return
	end
	-- conjured bone in the hand for the swing
	if hand then
		local bone = Lib.Bone(0.42, 3.2, WHITE)
		local h: BasePart = hand
		Lib.Animate(0.32, function(a)
			if h.Parent == nil then
				return true
			end
			bone:Place(h.CFrame * CFrame.new(0, -0.3, -1.2) * CFrame.Angles(math.rad(90), 0, 0))
			bone:SetTransparency(if a > 0.7 then (a - 0.7) / 0.3 else 0)
			return nil
		end, function()
			bone:Release()
		end)
	end
	local last = comboIndex >= 3
	fx.Delay(0.1, function()
		local now = rootCF(fx) or cf
		local base = now * CFrame.new(0, 0.6, 0)
		if comboIndex == 1 then
			Lib.Slash(base, { Radius = 4, From = 75, To = -60, Width = 0.9, Color = SANS_CYAN, Duration = 0.2 })
		elseif comboIndex == 2 then
			Lib.Slash(
				base * CFrame.Angles(0, 0, math.rad(-18)),
				{ Radius = 4, From = -75, To = 60, Width = 0.9, Color = SANS_CYAN, Duration = 0.2 }
			)
		else
			-- overhead: arc in the vertical plane through the facing direction
			Lib.Slash(base * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), {
				Radius = 4.6,
				From = -80,
				To = 70,
				Width = 1.3,
				Color = BLUE,
				Duration = 0.24,
			})
		end
		fx.Sound(if last then "SwingHeavy" else "Swing", fx.Root(char))
	end)
end

Effects.BoneJab = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			boneSwing(fx, data.combo or 1)
		end
	elseif packet.phase == "Strike" then
		if data.last and (data.hits or 0) > 0 then
			local cf = rootCF(fx)
			if cf then
				local front = (cf * CFrame.new(0, 0.2, -4)).Position
				fx.VFX.EmitRing(front, 3, BLUE, 0.25, { Axis = cf.LookVector })
				fx.VFX.Emit("Spark", front, 10, { Color = WHITE, Dir = cf.LookVector })
			end
		end
	end
end

Predict.BoneJab = function(fx: any, _payload: Map)
	local combat = fx.Combat()
	local idx = 1
	if combat and type(combat.ComboIndex) == "function" then
		local ok, i = pcall(combat.ComboIndex)
		if ok and type(i) == "number" and i > 0 then
			idx = i
		end
	end
	boneSwing(fx, idx)
end

---------------------------------------------------------------------------------------------------
-- Gaster Blaster (Q, hold)

-- Same layout as the server kit (caster space: right, up, back).
local BLASTER_LAYOUTS: { [number]: { { number } } } = {
	[1] = { { 2.8, 4.2, 2.5 } },
	[2] = { { -3.6, 3.6, 2.2 }, { 3.6, 3.6, 2.2 } },
	[3] = { { -4.6, 3.0, 1.4 }, { 0, 5.6, 2.8 }, { 4.6, 3.0, 1.4 } },
}

local function blasterSlots(count: number): { { number } }
	local layout = BLASTER_LAYOUTS[count]
	if layout then
		return layout
	end
	local out = {}
	for i = 1, count do
		local frac = (i - 1) / math.max(1, count - 1)
		local a = math.rad(-70 + 140 * frac)
		table.insert(out, { math.sin(a) * 5, 3 + math.cos(a) * 2.5, 1.5 + math.cos(a) * 1.5 })
	end
	return out
end
Kit.BlasterSlots = blasterSlots

Effects.GasterBlaster = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			eyeFor(fx, nil, 1.5)
		end
		fx.Sound("BlasterSummon", fx.Root(fx.Character))
	elseif packet.phase == "Summon" then
		local Lib = fx.VFX
		for _, cf in (data.origins or {}) :: { CFrame } do
			if typeof(cf) == "CFrame" then
				Lib.EmitBurst(cf.Position, 5, SANS_CYAN, 0.28)
				Lib.EmitRing(cf.Position, 2.6, WHITE, 0.3, { Axis = cf.LookVector })
			end
		end
	end
end

Predict.GasterBlaster = function(fx: any, _payload: Map)
	eyeFor(fx, nil, 1.5)
end

Indicator.GasterBlaster = function(fx: any): Map?
	local Lib = fx.VFX
	local hv = fx.Hazards
	local N = numbers("GasterBlaster")
	local maxBlasters = math.max(1, math.floor(N.MaxBlasters or 3))
	local width = N.Width or 5
	local ghosts: { any } = {}
	local lines: { BasePart } = {}
	local count = 0
	local function ensure(n: number)
		while #ghosts < n do
			local b = if hv and hv.AcquireBlaster then hv.AcquireBlaster("Classic", width, { Ghost = true }) else nil
			table.insert(ghosts, b or false)
			table.insert(
				lines,
				Lib.Part("Cylinder", Vector3.new(1, 0.12, 0.12), CFrame.new(), WHITE, Enum.Material.Neon, 0.45)
			)
		end
	end
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, charge: number)
		local cf = rootCF(fx)
		if cf == nil then
			return
		end
		local n = math.clamp(1 + math.floor(charge * maxBlasters), 1, maxBlasters)
		if n ~= count then
			count = n
			ensure(n)
			if n > 1 then
				fx.Sound("BlasterTick", fx.Root(fx.Character), { Volume = 0.5 })
			end
		end
		local origin = cf.Position
		local fwd = flat(aim - origin, cf.LookVector)
		local right = fwd:Cross(Vector3.yAxis).Unit
		-- same target rule as the server: chest height above nearby ground
		local target = aim
		local g = Lib.Ground(aim + Vector3.new(0, 0.5, 0), 3.5)
		if g then
			target = g + Vector3.new(0, 2.5, 0)
		end
		local slots = blasterSlots(n)
		for i = 1, #ghosts do
			local ghost = ghosts[i]
			local line = lines[i]
			if i <= n then
				local slot = slots[i]
				local pos = origin + right * slot[1] + Vector3.yAxis * slot[2] - fwd * slot[3]
				local dir = target - pos
				if dir.Magnitude < 4 or flat(dir, fwd):Dot(fwd) < 0.1 then
					dir = fwd + Vector3.new(0, -0.05, 0)
				end
				local mcf = Lib.LookAlong(pos, dir)
				if ghost then
					ghost:Pose(mcf, 0.08 + 0.05 * math.sin(os.clock() * 8 + i))
					ghost:SetTransparency(0)
				end
				local len = math.min(dir.Magnitude, N.Length or 90)
				line.Size = Vector3.new(len, 0.1, 0.1)
				line.CFrame = mcf * CFrame.new(0, 0, -len / 2) * CFrame.Angles(0, math.pi / 2, 0)
				line.Transparency = 0.35 + 0.15 * math.sin(os.clock() * 10)
			else
				if ghost then
					ghost:SetTransparency(1)
				end
				line.Transparency = 1
			end
		end
	end
	function handle.Destroy(_self: any)
		for _, g in ghosts do
			if g then
				g:Release()
			end
		end
		for _, l in lines do
			Lib.Release(l)
		end
		table.clear(ghosts)
		table.clear(lines)
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Blue Soul (E)

local function stopTether(fx: any)
	local st = fx.State.BlueTether
	if st then
		fx.State.BlueTether = nil
		st.Dead = true
		if st.Beam then
			st.Beam:Destroy()
		end
		if st.Heart then
			st.Heart:Destroy()
		end
	end
end

Effects.BlueSoul = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local target: Model? = if typeof(data.target) == "Instance" and data.target:IsA("Model") then data.target else nil
	local phase = packet.phase
	if phase == "Start" then
		if not fx.Predicted then
			eyeFor(fx, BLUE, 1.6)
		end
	elseif phase == "Grab" and target then
		stopTether(fx)
		local hand = fx.Attachment(fx.Character, "RightGrip")
		local chest = fx.Attachment(target, "Chest")
		local st: Map = { Dead = false }
		if hand and chest then
			local beam = Instance.new("Beam")
			beam.Attachment0 = hand
			beam.Attachment1 = chest
			beam.Color = ColorSequence.new(BLUE, Color3.fromRGB(120, 210, 255))
			beam.Transparency = NumberSequence.new(0.15, 0.35)
			beam.Width0 = 0.18
			beam.Width1 = 0.6
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Brightness = 3
			beam.Segments = 16
			beam.CurveSize0 = 2
			beam.CurveSize1 = -1
			beam.Texture = ""
			beam.Parent = Lib.Folder()
			st.Beam = beam
		end
		local heart = Lib.Soul(BLUE, 0.9)
		heart.Parent = Lib.Folder()
		st.Heart = heart
		fx.State.BlueTether = st
		fx.Highlight(target, BLUE, 1.6, { Fill = 0.7 })
		fx.Sound("SoulGrab", fx.Root(target))
		local tgt: Model = target
		Lib.Animate(2.6, function(_a, _dt, elapsed)
			if st.Dead then
				return true
			end
			local pos = fx.Chest(tgt)
			if pos and heart.Parent then
				local cam = game:GetService("Workspace").CurrentCamera
				local look = if cam then cam.CFrame.Position - pos else Vector3.new(0, 0, 1)
				local bob = 0.06 * math.sin(elapsed * 18) -- the grabbed SOUL trembles
				heart:PivotTo(
					Lib.LookAlong(pos + Vector3.new(bob, 0, 0), flat(look, Vector3.zAxis)) * CFrame.new(0, 0, -0.7)
				)
			end
			return nil
		end, function()
			if fx.State.BlueTether == st then
				stopTether(fx)
			end
		end)
	elseif phase == "Lift" and target then
		local pos = fx.Chest(target)
		if pos then
			Lib.Emit("Star", pos, 10, { Color = BLUE, Speed = { 2, 6 } })
			Lib.EmitRing(pos - Vector3.new(0, 2.6, 0), 3, BLUE, 0.4)
		end
	elseif phase == "Slam" and target then
		stopTether(fx)
		local root = fx.Root(target)
		local pos = if root then root.Position else nil
		if pos then
			fx.Delay(0.18, function()
				local feet = Lib.Ground(pos, 30) or (pos - Vector3.new(0, 2.8, 0))
				Lib.Shockwave(feet, 7, BLUE, 0.45)
				Lib.Emit("Debris", feet, 12, { Color = Color3.fromRGB(140, 130, 120) })
				Lib.Flash(feet + Vector3.new(0, 1, 0), BLUE, 4, 0.2)
				fx.ShakeAt(feet, 0.6, 0.35, 30)
				fx.Sound("Slam", feet)
			end)
		end
	elseif phase == "Release" then
		stopTether(fx)
	end
end

Predict.BlueSoul = function(fx: any, _payload: Map)
	eyeFor(fx, BLUE, 1.6)
end

Indicator.BlueSoul = function(fx: any): Map?
	local Lib = fx.VFX
	local ring = Lib.GroundCircle(Vector3.zero, 2.4, BLUE, { Rim = 0.24, Fill = 0.78, Height = 0.18 })
	ring:SetVisible(false)
	local heart = Lib.Soul(BLUE, 0.6)
	heart.Parent = Lib.Folder()
	heart:PivotTo(CFrame.new(0, 25000, 0))
	local handle = {}
	function handle.Update(_self: any, _aim: Vector3, _charge: number, target: Model?)
		local r = if target then fx.Root(target) else nil
		if r then
			ring:SetVisible(true)
			ring:SetCenter(r.Position - Vector3.new(0, 2.8, 0))
			local cam = game:GetService("Workspace").CurrentCamera
			local p = r.Position + Vector3.new(0, 3.6 + 0.15 * math.sin(os.clock() * 5), 0)
			local look = if cam then cam.CFrame.Position - p else Vector3.zAxis
			heart:PivotTo(Lib.LookAlong(p, flat(look, Vector3.zAxis)))
		else
			ring:SetVisible(false)
			heart:PivotTo(CFrame.new(0, 25000, 0))
		end
	end
	function handle.Destroy(_self: any)
		ring:Destroy()
		heart:Destroy()
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Bone Zone (R)

Effects.BoneZone = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		local hand = fx.Part(fx.Character, "RightHand")
		if hand then
			fx.VFX.EmitBurst(hand.Position, 2.5, SANS_CYAN, 0.3)
		end
	elseif packet.phase == "Zone" and typeof(data.center) == "Vector3" then
		local r = if type(data.radius) == "number" then data.radius else 10
		fx.VFX.EmitRing(data.center + Vector3.new(0, 0.2, 0), r, WHITE, 0.5, { Start = 0.9, Brightness = 2 })
		fx.Sound("BoneSummon", data.center)
	end
end

Indicator.BoneZone = function(fx: any): Map?
	local Lib = fx.VFX
	local N = numbers("BoneZone")
	local r = N.Radius or 10
	local inner = Lib.GroundCircle(Vector3.zero, r, WHITE, { Rim = 0.22, Fill = 0.86, Height = 0.16 })
	local outer = Lib.GroundCircle(
		Vector3.zero,
		r + 1.5 + 2,
		ORANGE,
		{ Inner = r + 1.5 - 2, Rim = 0.16, Fill = 0.88, Height = 0.14 }
	)
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		inner:SetCenter(aim)
		outer:SetCenter(aim)
	end
	function handle.Destroy(_self: any)
		inner:Destroy()
		outer:Destroy()
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Blue Bone Wall (T)

Effects.BoneWall = function(fx: any, packet: Map)
	if packet.phase ~= "Start" or fx.Predicted then
		return
	end
	local cf = rootCF(fx)
	if cf then
		fx.VFX.Slash(
			cf * CFrame.new(0, 0.2, 0),
			{ Radius = 3.4, From = -80, To = 80, Width = 0.7, Color = BLUE, Duration = 0.3 }
		)
		fx.VFX.Dust(cf.Position - Vector3.new(0, 2.6, 0) + cf.LookVector * 2.5, 2.5, nil, 8)
	end
end

Predict.BoneWall = function(fx: any, _payload: Map)
	local cf = rootCF(fx)
	if cf then
		fx.VFX.Slash(
			cf * CFrame.new(0, 0.2, 0),
			{ Radius = 3.4, From = -80, To = 80, Width = 0.7, Color = BLUE, Duration = 0.3 }
		)
	end
end

---------------------------------------------------------------------------------------------------
-- Shortcut (Shift)

Effects.Shortcut = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local char = fx.Character
	if packet.phase == "Vanish" then
		Lib.Afterimage(char, Color3.fromRGB(120, 180, 255), 0.45, { Transparency = 0.35, MaxParts = 22 })
		local eye = fx.Attachment(char, "LeftEye")
		if eye then
			Lib.EmitBurst(eye.WorldPosition, 1.6, SANS_CYAN, 0.2)
		end
		if typeof(data.from) == "Vector3" then
			Lib.Dust(data.from - Vector3.new(0, 2.6, 0), 1.4, nil, 5)
		end
		fx.Sound("Shortcut", if typeof(data.from) == "Vector3" then data.from else nil)
	elseif packet.phase == "Teleport" then
		if typeof(data.to) == "Vector3" then
			Lib.EmitBurst(data.to, 4, SANS_CYAN, 0.25)
			Lib.EmitRing(data.to - Vector3.new(0, 2.6, 0), 2.5, WHITE, 0.3)
			Lib.Emit("Mote", data.to, 8, { Color = SANS_CYAN })
		end
		if fx.IsLocal then
			fx.Screen.Flash(Color3.new(0, 0, 0), 0.35, 0.12) -- the "cut" of a shortcut
		end
	end
end

Indicator.Shortcut = function(fx: any): Map?
	local Lib = fx.VFX
	local N = numbers("Shortcut")
	local dist = N.Distance or 32
	local marker = Lib.GroundCircle(Vector3.zero, 1.6, SANS_CYAN, { Rim = 0.2, Fill = 0.7, Height = 0.18 })
	local range = Lib.GroundCircle(Vector3.zero, dist, WHITE, { Rim = 0.1, Fill = 1, Height = 0.08, Shadow = false })
	range:SetTransparency(0.8, 1)
	local pillar =
		Lib.Part("Cylinder", Vector3.new(6, 0.5, 0.5), CFrame.new(0, 25000, 0), SANS_CYAN, Enum.Material.Neon, 0.6)
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		local r = fx.Root(fx.Character)
		if r == nil then
			return
		end
		local dest = DamageMath.ClampAim(r.Position, aim, dist)
		local g = Lib.Ground(dest + Vector3.new(0, 2, 0), 30) or dest
		marker:SetCenter(g)
		range:SetCenter(r.Position - Vector3.new(0, 2.8, 0))
		pillar.CFrame = CFrame.new(g + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		pillar.Transparency = 0.55 + 0.15 * math.sin(os.clock() * 6)
	end
	function handle.Destroy(_self: any)
		marker:Destroy()
		range:Destroy()
		Lib.Release(pillar)
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Bad Time (G, ultimate)

local function nearLocal(pos: Vector3, radius: number): boolean
	local lp = Players.LocalPlayer
	local c = lp and lp.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return (r.Position - pos).Magnitude <= radius
	end
	return false
end

Effects.BadTime = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	if packet.phase == "Start" then
		local char = fx.Character
		fx.EyeGlow(char, "Left", nil, true)
		local head = fx.Part(char, "Head")
		if head then
			Lib.EmitBurst(head.Position, 6, SANS_CYAN, 0.4)
		end
		fx.Sound("BadTime", fx.Root(char))
		local aim = packet.aim
		if fx.IsLocal or (typeof(aim) == "Vector3" and nearLocal(aim, 60)) then
			fx.Screen.Tint(Color3.fromRGB(110, 140, 255), 0.35, 1.2, 0.6)
			fx.Screen.Vignette(Color3.fromRGB(0, 30, 90), 0.5, 1.6, "Status")
			fx.Shake(0.25, 0.6)
		end
	elseif packet.phase == "Blaze" and typeof(data.center) == "Vector3" then
		local center: Vector3 = data.center
		local radius = if type(data.radius) == "number" then data.radius else 18
		local duration = if type(data.duration) == "number" then data.duration else 6
		local circle = Lib.GroundCircle(center, radius, WHITE, { Rim = 0.35, Fill = 0.92, Height = 0.25 })
		local ringOut = Lib.GroundCircle(center, radius + 6, SANS_CYAN, { Rim = 0.2, Fill = 1, Height = 0.15 })
		local lastShake = 0
		local char = fx.Character
		Lib.Animate(duration, function(a, _dt, elapsed)
			local pulse = 0.5 + 0.5 * math.sin(elapsed * 6)
			circle:SetTransparency(0.15 + 0.25 * pulse + 0.6 * math.max(0, (a - 0.85) / 0.15), 0.9)
			ringOut:SetTransparency(0.45 + 0.3 * pulse + 0.25 * math.max(0, (a - 0.85) / 0.15), 1)
			if elapsed - lastShake > 0.5 and nearLocal(center, radius + 8) then
				lastShake = elapsed
				fx.Shake(0.12, 0.4)
			end
			return nil
		end, function()
			circle:Destroy()
			ringOut:Destroy()
			if char and char:GetAttribute("FinalForm") ~= true then
				fx.EyeGlow(char, "Left", nil, false)
			end
		end)
	end
end

Predict.BadTime = function(fx: any, _payload: Map)
	fx.EyeGlow(fx.Character, "Left", nil, true)
end

Indicator.BadTime = function(fx: any): Map?
	local Lib = fx.VFX
	local N = numbers("BadTime")
	local r = N.Radius or 18
	local area = Lib.GroundCircle(Vector3.zero, r, WHITE, { Rim = 0.25, Fill = 0.88, Height = 0.16 })
	local ring = Lib.GroundCircle(Vector3.zero, r + 6, SANS_CYAN, { Rim = 0.16, Fill = 1, Height = 0.12 })
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		area:SetCenter(aim)
		ring:SetCenter(aim)
	end
	function handle.Destroy(_self: any)
		area:Destroy()
		ring:Destroy()
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Passives

function Kit.OnCharacter(fx: any, character: Model)
	local trove = fx.Trove
	-- FinalForm: the attack eye blazes for the rest of the round
	local function finalForm()
		local on = character:GetAttribute("FinalForm") == true
		fx.EyeGlow(character, "Left", nil, on)
		if on then
			local head = fx.Part(character, "Head")
			if head then
				fx.VFX.EmitBurst(head.Position, 8, SANS_CYAN, 0.5)
			end
		end
	end
	trove:Connect(character:GetAttributeChangedSignal("FinalForm"), finalForm)
	if character:GetAttribute("FinalForm") == true then
		finalForm()
	end
	-- idle pupil blinks (the pupils are the rig's white Neon "LeftPupil" / "RightPupil")
	local alive = true
	trove:Add(function()
		alive = false
	end)
	task.spawn(function()
		while alive and character.Parent do
			task.wait(3.5 + math.random() * 4)
			if not alive or character.Parent == nil or character:GetAttribute("Dead") == true then
				break
			end
			local l = fx.Part(character, "LeftPupil")
			local r = fx.Part(character, "RightPupil")
			for _, p in { l, r } do
				if p then
					p.LocalTransparencyModifier = 1
				end
			end
			task.wait(0.11)
			for _, p in { l, r } do
				if p and p.Parent then
					p.LocalTransparencyModifier = 0
				end
			end
		end
	end)
end

-- Lazy dodge flourish on top of FxController's grey MISS ghost: a little wink of blue at the eye + dust.
function Kit.OnDamageFx(fx: any, packet: Map)
	if not packet.dodged then
		return
	end
	local char = fx.Character
	local eye = fx.Attachment(char, "LeftEye")
	if eye then
		fx.VFX.EmitBurst(eye.WorldPosition, 1.2, SANS_CYAN, 0.18)
	end
	local r = fx.Root(char)
	if r then
		fx.VFX.Dust(r.Position - Vector3.new(0, 2.8, 0), 1, nil, 4)
	end
end

return Kit
