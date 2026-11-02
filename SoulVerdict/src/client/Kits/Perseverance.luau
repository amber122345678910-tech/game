--!strict
-- Client kit: Perseverance (purple SOUL) — "The Scholar" (SPEC §9.1). Visuals for every AbilityFx phase of
-- src/server/Kits/Perseverance.luau:
--   NotebookSwat     Start {combo}: wide purple page-arcs (1 R->L, 2 L->R, 3 overhead slam with a paper burst on the
--                    ground), predicted locally; Strike {last, hits}: ink burst + shockwave on a landed slam
--   SpellboundPages  Start: the notebook flares; Stream {count, interval}: a paper puff per page at the hand (the pages
--                    themselves are "SpellPage" projectile hazards registered below); Bind {target, duration}: two
--                    counter-rotating rune rings lock the target in place + BOUND popup + purple outline
--   Rewrite          Rewind {from, path, heal}: purple afterimage left behind + clock ring; Teleport {from, to}: ghost
--                    echoes along the recorded path (newest -> oldest), clock hands spinning backwards at the arrival,
--                    local screen desaturate + REWRITE popup
--   FinalChapter     Summon {target, pos, delay, lockAt, radius}: the GiantBook prop falls in open over the target,
--                    follows it with a purple ground circle (the escape telegraph), Lock {pos}: settles (circle flashes),
--                    slams shut at t0 + delay; Slam {pos, hits, silence}: shockwave, paper storm, SILENCED / THE END
--                    popups, shake; Cancel: the book bursts into pages. Indicator: target circle + ghost book.
-- OnCharacter: faint SOUL-purple heart at the Chest attachment while the ult status "Chapter" lasts; a slow drift of
--   purple page motes from the notebook (Studious — the monster's cooldowns themselves are shown by Hud/BossBar).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any

type Map = { [string]: any }

local Kit = {}
local Effects: { [string]: (any, Map) -> () } = {}
local Predict: { [string]: (any, Map) -> () } = {}
local Indicator: { [string]: (any) -> Map? } = {}
Kit.Effects = Effects
Kit.Predict = Predict
Kit.Indicator = Indicator

local PURPLE = Color3.fromRGB(213, 53, 217)
local VIOLET = Color3.fromRGB(150, 70, 255)
local PALE = Color3.fromRGB(244, 214, 255)
local PAPER = Color3.fromRGB(250, 246, 235)
local INK = Color3.fromRGB(70, 24, 100)
local WHITE = Color3.new(1, 1, 1)
local BOOK_HEIGHT = 9 -- hover height of the giant book above the ground (server BOOK_REACH_UP)

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
	return if cf then (cf * CFrame.new(0.6, 0.6, -1.3)).Position else nil
end

---------------------------------------------------------------------------------------------------
-- Faint SOUL heart at the Chest attachment (ult) — restored from the replicated status by OnCharacter

local function ultHeart(fx: any, untilTime: number)
	local char = fx.Character
	if char == nil or fx.State.UltHeart then
		return
	end
	local Lib = fx.VFX
	local heart = Lib.Soul(PURPLE, 0.55)
	local parts: { BasePart } = {}
	for _, d in heart:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 0.35
			table.insert(parts, d)
		end
	end
	heart.Parent = Lib.Folder()
	local core = heart.PrimaryPart or parts[1]
	local light = if core then Lib.Light(core, PURPLE, 1.2, 7) else nil
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
			local beat = math.exp(-((elapsed * 1.4) % 1) * 7)
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
-- "SpellPage" projectile visual (registered with HazardVisuals when this module loads)

local function spellPageVisual(ctx: Map): Map
	local Lib = ctx.Lib
	local c: Color3 = if ctx.Rule == "White" then PURPLE else ctx.Color
	local park = CFrame.new(0, -1e4, 0)
	local page = Lib.Part("Block", Vector3.new(1.25, 1.65, 0.05), park, PAPER, Enum.Material.SmoothPlastic, 0)
	local glow = Lib.Part("Block", Vector3.new(1.55, 1.95, 0.02), park, c, Enum.Material.Neon, 0.62)
	local line1 = Lib.Part("Block", Vector3.new(0.85, 0.1, 0.07), park, c, Enum.Material.Neon, 0)
	local line2 = Lib.Part("Block", Vector3.new(0.65, 0.1, 0.07), park, c, Enum.Material.Neon, 0)
	local line3 = Lib.Part("Block", Vector3.new(0.75, 0.1, 0.07), park, INK, Enum.Material.SmoothPlastic, 0)
	local parts = { page, glow, line1, line2, line3 }
	local offsets = {
		CFrame.identity,
		CFrame.new(0, 0, 0.03),
		CFrame.new(-0.05, 0.42, -0.03),
		CFrame.new(-0.15, 0.08, -0.03),
		CFrame.new(-0.1, -0.3, -0.03),
	}
	local light = Lib.Light(glow, c, 1.4, 7)
	local cfs: { CFrame } = table.create(#parts)
	local W = game:GetService("Workspace")
	local lastEmit = 0
	local v: Map = {}
	function v.Update(_s: any, cf: CFrame, t: number, _dt: number)
		-- a thrown page: flat-ish to the flight, rolling and flapping
		local frame = cf
			* CFrame.Angles(math.rad(62) + math.sin(t * 17) * 0.35, 0, 0)
			* CFrame.Angles(0, 0, t * 11)
		for i = 1, #parts do
			cfs[i] = frame * offsets[i]
		end
		W:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if t - lastEmit > 0.045 then
			lastEmit = t
			Lib.Emit("Mote", cf.Position, 1, { Color = c })
		end
	end
	function v.Impact(_s: any, pos: Vector3)
		Lib.Sparks(pos, nil, c, 7, 16)
		Lib.EmitBurst(pos, 2.6, c, 0.18)
		Lib.Emit("Debris", pos, 3, { Color = PAPER })
	end
	function v.Destroy(_s: any)
		for _, p in parts do
			Lib.Release(p)
		end
		if light then
			light:Destroy()
		end
	end
	return v
end

Kit.Visuals = { SpellPage = spellPageVisual } -- exported for tests / previews

pcall(function()
	local controllers = script.Parent.Parent:WaitForChild("Controllers")
	local HazardVisuals = require(controllers:WaitForChild("HazardVisuals") :: any) :: any
	HazardVisuals.RegisterVisual("SpellPage", spellPageVisual)
end)

---------------------------------------------------------------------------------------------------
-- Notebook Swat (M1)

local function swat(fx: any, combo: number)
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
				base * CFrame.Angles(0, 0, math.rad(8)),
				{ Radius = 4.8, From = 95, To = -95, Width = 1.2, Color = PURPLE, Core = PAPER, Duration = 0.18 }
			)
		elseif i == 2 then
			Lib.Slash(
				base * CFrame.Angles(0, 0, math.rad(-10)),
				{ Radius = 4.8, From = -95, To = 95, Width = 1.2, Color = PURPLE, Core = PAPER, Duration = 0.18 }
			)
		else
			-- overhead slam: vertical arc, then the page burst where it lands
			Lib.Slash(base * CFrame.Angles(0, 0, math.rad(90)), {
				Radius = 4.4,
				From = -100,
				To = 70,
				Width = 1.4,
				Color = VIOLET,
				Core = WHITE,
				Duration = 0.2,
				Segments = 16,
			})
			fx.Delay(0.09, function()
				local cf2 = rootCF(fx)
				if cf2 then
					local ground = (cf2 * CFrame.new(0, -2.8, -3.6)).Position
					Lib.Shockwave(ground, 5.5, PURPLE, 0.35)
					Lib.Emit("Debris", ground + Vector3.new(0, 0.6, 0), 6, { Color = PAPER })
					Lib.Dust(ground, 2, nil, 6)
					fx.Sound("Slam", ground, { Volume = 0.6, Pitch = 1.15 })
				end
			end)
		end
		local hand = handPos(fx)
		if hand then
			Lib.Emit("Mote", hand, 3, { Color = PURPLE })
			Lib.Emit("Debris", hand, 1, { Color = PAPER })
		end
		fx.Sound("Whoosh", fx.Root(fx.Character), { Pitch = if i == 3 then 0.8 else 1 + 0.06 * i })
	end)
end

Effects.NotebookSwat = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			swat(fx, data.combo or 1)
		end
	elseif packet.phase == "Strike" and (data.hits or 0) > 0 then
		local cf = rootCF(fx)
		if cf then
			local front = (cf * CFrame.new(0, 0.4, -3.8)).Position
			fx.VFX.EmitBurst(front, if data.last then 5 else 3, PURPLE, 0.18)
			if data.last then
				fx.VFX.EmitRing(front, 3.2, PURPLE, 0.25, { Axis = cf.LookVector })
				if fx.IsLocal then
					fx.Shake(0.22, 0.15)
				end
			end
		end
	end
end

Predict.NotebookSwat = function(fx: any, _payload: Map)
	local combat = fx.Combat()
	local idx = 1
	if combat and type(combat.ComboIndex) == "function" then
		local ok, i = pcall(combat.ComboIndex)
		if ok and type(i) == "number" and i > 0 then
			idx = i
		end
	end
	swat(fx, idx)
end

---------------------------------------------------------------------------------------------------
-- Spellbound Pages (Q)

local function bookFlare(fx: any)
	local hand = handPos(fx)
	if hand then
		fx.VFX.EmitBurst(hand, 2.4, PURPLE, 0.2)
		fx.VFX.Emit("Star", hand, 3, { Color = PALE, Speed = { 1, 3 } })
		fx.Sound("Cast", hand, { Pitch = 1.1 })
	end
end

local function bind(fx: any, target: Model, duration: number)
	local Lib = fx.VFX
	local r = fx.Root(target)
	if r == nil then
		return
	end
	local runes: { BasePart } = {}
	local rings = { { Y = -1.6, R = 2.2, Speed = 2.6 }, { Y = 0.4, R = 2.5, Speed = -3.2 } }
	for _ = 1, 2 do
		for _ = 1, 6 do
			table.insert(
				runes,
				Lib.Part("Block", Vector3.new(0.5, 0.5, 0.08), CFrame.new(r.Position), PURPLE, Enum.Material.Neon, 0.1)
			)
		end
	end
	local circle = Lib.GroundCircle(r.Position - Vector3.new(0, 2.9, 0), 2.6, PURPLE, { Rim = 0.25, Fill = 0.75 })
	local light = Lib.Light(runes[1], PURPLE, 2, 10)
	fx.Highlight(target, PURPLE, duration)
	Lib.Text(r.Position + Vector3.new(0, 3.2, 0), Strings.L("fx.perseverance.bound"), PURPLE, { Kind = "Alert" })
	Lib.EmitRing(r.Position - Vector3.new(0, 2.6, 0), 3, PURPLE, 0.3)
	fx.Sound("Freeze", r.Position)
	Lib.Animate(duration + 0.25, function(a, _dt, elapsed)
		local rr = fx.Root(target)
		if rr == nil then
			return true
		end
		local pos = rr.Position
		local fade = if elapsed > duration then (elapsed - duration) / 0.25 else 0
		for ring, spec in rings do
			for k = 1, 6 do
				local part = runes[(ring - 1) * 6 + k]
				local ang = elapsed * spec.Speed + (k - 1) * math.pi / 3
				local p = pos + Vector3.new(math.cos(ang) * spec.R, spec.Y + math.sin(elapsed * 4 + k) * 0.1, math.sin(ang) * spec.R)
				part.CFrame = Lib.LookAlong(p, Vector3.new(-math.sin(ang), 0, math.cos(ang)))
					* CFrame.Angles(0, 0, math.rad(45))
				part.Transparency = 0.1 + 0.9 * fade
			end
		end
		circle:SetCenter(pos - Vector3.new(0, 2.9, 0))
		circle:SetTransparency(0.15 + 0.85 * fade, 0.75 + 0.25 * fade)
		if light then
			light.Brightness = 2 * (1 - fade) * (0.75 + 0.25 * math.sin(a * 30))
		end
		return nil
	end, function()
		for _, p in runes do
			Lib.Release(p)
		end
		circle:Destroy()
		if light then
			light:Destroy()
		end
	end)
end

Effects.SpellboundPages = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			bookFlare(fx)
		end
	elseif packet.phase == "Stream" then
		local count = if type(data.count) == "number" then math.min(data.count, 12) else 5
		local interval = if type(data.interval) == "number" then data.interval else 0.08
		for i = 0, count - 1 do
			fx.Delay(i * interval, function()
				local hand = handPos(fx)
				if hand then
					fx.VFX.Emit("Debris", hand, 1, { Color = PAPER })
					fx.VFX.Emit("Mote", hand, 2, { Color = PURPLE })
					fx.Sound("Whoosh", hand, { Volume = 0.35, Pitch = 1.5 + i * 0.05 })
				end
			end)
		end
	elseif packet.phase == "Bind" then
		local target = data.target
		if typeof(target) == "Instance" and target:IsA("Model") then
			bind(fx, target, if type(data.duration) == "number" then data.duration else 1)
		end
	end
end

Predict.SpellboundPages = function(fx: any, _payload: Map)
	bookFlare(fx)
end

---------------------------------------------------------------------------------------------------
-- Rewrite (E)

local function clockHands(fx: any, pos: Vector3, duration: number)
	local Lib = fx.VFX
	local face = Lib.GroundCircle(pos, 3.2, PURPLE, { Rim = 0.2, Fill = 0.85, Height = 0.2 })
	local long = Lib.Part("Block", Vector3.new(0.18, 0.08, 2.6), CFrame.new(pos), PALE, Enum.Material.Neon, 0)
	local short = Lib.Part("Block", Vector3.new(0.22, 0.08, 1.6), CFrame.new(pos), PURPLE, Enum.Material.Neon, 0)
	Lib.Animate(duration, function(a)
		-- hands spin BACKWARDS, decelerating
		local turn = -(1 - (1 - a) ^ 3) * math.pi * 4
		long.CFrame = CFrame.new(pos + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0, -1.3)
		short.CFrame = CFrame.new(pos + Vector3.new(0, 0.14, 0))
			* CFrame.Angles(0, turn / 12, 0)
			* CFrame.new(0, 0, -0.8)
		local t = a * a
		long.Transparency = t
		short.Transparency = t
		face:SetTransparency(0.2 + 0.8 * t, 0.85 + 0.15 * t)
		return nil
	end, function()
		Lib.Release(long)
		Lib.Release(short)
		face:Destroy()
	end)
end

Effects.Rewrite = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local char = fx.Character
	if packet.phase == "Start" then
		if not fx.Predicted then
			local chest = fx.Chest(char)
			if chest then
				Lib.EmitRing(chest, 2.2, PURPLE, 0.2)
			end
		end
	elseif packet.phase == "Rewind" then
		fx.State.RewritePath = if type(data.path) == "table" then data.path else nil
		if char then
			Lib.Afterimage(char, PURPLE, 0.7, { Transparency = 0.3, MaxParts = 22 })
		end
		if typeof(data.from) == "Vector3" then
			Lib.Emit("Star", data.from, 8, { Color = PALE, Speed = { 2, 6 } })
			Lib.Flash(data.from, PURPLE, 3, 0.18)
		end
		fx.Sound("Portal", data.from, { Pitch = 1.4 })
	elseif packet.phase == "Teleport" then
		local to: Vector3? = if typeof(data.to) == "Vector3" then data.to else nil
		local path: { any } = fx.State.RewritePath or {}
		fx.State.RewritePath = nil
		local r = fx.Root(char)
		if char and r then
			-- ghost echoes along the recorded path, newest first: time flowing backwards
			local n = #path
			for k = n, 1, -1 do
				local p = path[k]
				if typeof(p) == "Vector3" then
					fx.Delay((n - k) * 0.035, function()
						local rr = fx.Root(char)
						if rr and char.Parent then
							Lib.Afterimage(char, VIOLET, 0.42, {
								Transparency = 0.5 + 0.3 * (k / math.max(1, n)),
								MaxParts = 10,
								Offset = CFrame.new(p - rr.Position),
							})
						end
					end)
					if k > 1 and typeof(path[k - 1]) == "Vector3" then
						Lib.Line(p, path[k - 1], PURPLE, 0.12, 0.5)
					end
				end
			end
			if typeof(data.from) == "Vector3" and n > 0 and typeof(path[n]) == "Vector3" then
				Lib.Line(data.from, path[n], PURPLE, 0.12, 0.5)
			end
		end
		if to then
			Lib.Flash(to, PURPLE, 5, 0.3)
			Lib.Emit("Mote", to, 14, { Color = PURPLE, Speed = { 3, 8 } })
			clockHands(fx, to - Vector3.new(0, 2.8, 0), 0.6)
			fx.Sound("Teleport", to, { Pitch = 0.85 })
		end
		if fx.IsLocal then
			fx.Screen.Desaturate(0.55, 0.45)
			fx.Screen.Tint(PALE, 0.2, 0.4)
		end
		local chest = fx.Chest(char)
		if chest then
			Lib.Text(chest + Vector3.new(0, 2.4, 0), Strings.L("fx.perseverance.rewind"), PURPLE, { Kind = "Alert" })
		end
	end
end

Predict.Rewrite = function(fx: any, _payload: Map)
	local chest = fx.Chest(fx.Character)
	if chest then
		fx.VFX.EmitRing(chest, 2.2, PURPLE, 0.2)
		fx.VFX.Emit("Star", chest, 4, { Color = PALE })
	end
end

---------------------------------------------------------------------------------------------------
-- Final Chapter (R, ultimate)

local function bookScale(radius: number): number
	local GiantBook = prop("GiantBook")
	local size: Vector3 = if GiantBook and typeof(GiantBook.Size) == "Vector3" then GiantBook.Size else Vector3.new(16, 1, 12)
	return math.max(0.3, (radius * 2.1) / math.max(1, size.X))
end

local function groundUnder(fx: any, pos: Vector3): Vector3
	return fx.VFX.Ground(pos + Vector3.new(0, 1, 0), 30) or (pos - Vector3.new(0, 3, 0))
end

local function dissolve(fx: any, model: Model, burst: boolean)
	local Lib = fx.VFX
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local pivot = model:GetPivot()
	if burst then
		Lib.Emit("Debris", pivot.Position, 10, { Color = PAPER, Speed = { 6, 14 } })
		Lib.Emit("Mote", pivot.Position, 12, { Color = PURPLE, Speed = { 4, 10 } })
		Lib.EmitBurst(pivot.Position, 6, PURPLE, 0.25)
	end
	local base: { number } = {}
	for i, p in parts do
		base[i] = p.Transparency
	end
	Lib.Animate(0.45, function(a)
		model:PivotTo(pivot + Vector3.new(0, a * 2.5, 0))
		for i, p in parts do
			p.Transparency = base[i] + (1 - base[i]) * a
		end
		return nil
	end, function()
		model:Destroy()
	end)
end

type Book = {
	Model: Model,
	Circle: any,
	Target: Model?,
	Pos: Vector3,
	Locked: boolean,
	Slammed: boolean,
	Done: boolean,
	Light: PointLight?,
}

local function summon(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local GiantBook = prop("GiantBook")
	if GiantBook == nil then
		return
	end
	local radius = if type(data.radius) == "number" then data.radius else 7.5
	local delay = if type(data.delay) == "number" then data.delay else 0.8
	local target: Model? = if typeof(data.target) == "Instance" and data.target:IsA("Model") then data.target else nil
	local pos: Vector3 = if typeof(data.pos) == "Vector3" then data.pos else Vector3.zero
	local okBuild, model = pcall(GiantBook.Build, bookScale(radius), PURPLE)
	if not okBuild or model == nil then
		return
	end
	local m: Model = model
	GiantBook.SetOpen(m, 1)
	local casterRoot = fx.Root(fx.Character)
	local yawDir = if casterRoot then (pos - casterRoot.Position) else Vector3.new(0, 0, -1)
	local flat = Vector3.new(yawDir.X, 0, yawDir.Z)
	local facing = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	local ground = groundUnder(fx, pos)
	m:PivotTo(Lib.LookAlong(ground + Vector3.new(0, BOOK_HEIGHT + 8, 0), facing))
	m.Parent = Lib.Folder()
	local book: Book = {
		Model = m,
		Circle = Lib.GroundCircle(ground, radius, PURPLE, { Rim = 0.35, Fill = 0.82, Height = 0.25 }),
		Target = target,
		Pos = pos,
		Locked = false,
		Slammed = false,
		Done = false,
		Light = nil,
	}
	book.Light = Lib.Light(m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true) :: any, PURPLE, 3, 24)
	local books = fx.State.Books or {}
	fx.State.Books = books
	books[packet.castId or 0] = book
	Lib.EmitBurst(ground + Vector3.new(0, BOOK_HEIGHT, 0), 9, PURPLE, 0.3)
	fx.Sound("SoulAppear", ground, { Pitch = 0.7 })
	if fx.IsLocal then
		fx.Screen.Pulse("Ult")
	end
	local t0 = if type(packet.t0) == "number" then packet.t0 else fx.Now()
	local x, z = pos.X, pos.Z
	Lib.Animate(delay + 0.5, function(_a, dt, _elapsed)
		if book.Done or m.Parent == nil then
			return true
		end
		local t = fx.Now() - t0
		-- follow the target until the lock, then settle on the locked point
		local want = book.Pos
		if not book.Locked and target then
			local tr = fx.Root(target)
			if tr then
				want = tr.Position
			end
		end
		local k = 1 - math.exp(-(if book.Locked then 30 else 12) * dt)
		x += (want.X - x) * k
		z += (want.Z - z) * k
		local g = groundUnder(fx, Vector3.new(x, want.Y, z))
		-- fall in (ease out), hover, then slam (0.14 s before the hit)
		local fall = math.clamp(t / 0.3, 0, 1)
		local height = BOOK_HEIGHT + 8 * (1 - fall) ^ 3
		local slamStart = delay - 0.14
		local open = 1
		if t >= slamStart then
			local s = math.clamp((t - slamStart) / 0.14, 0, 1)
			height = BOOK_HEIGHT - (BOOK_HEIGHT - 2.4) * s * s
			open = 1 - s * s
		elseif t >= slamStart - 0.12 then
			open = 1 + 0.08 * math.sin((t - (slamStart - 0.12)) / 0.12 * math.pi) -- anticipation: opens a hair wider
		end
		m:PivotTo(Lib.LookAlong(g + Vector3.new(0, height + math.sin(t * 6) * 0.15, 0), facing))
		GiantBook.SetOpen(m, open)
		book.Circle:SetCenter(g)
		local pulse = 0.5 + 0.5 * math.sin(t * 18)
		if book.Locked then
			book.Circle:SetColor(PALE)
			book.Circle:SetFill(math.clamp(t / delay, 0, 1), 0.7 - 0.1 * pulse)
		else
			book.Circle:SetFill(math.clamp(t / delay, 0, 1), 0.8 - 0.08 * pulse)
		end
		return nil
	end, nil)
end

local function finishBook(fx: any, castId: number, burst: boolean): Book?
	local books = fx.State.Books
	local book: Book? = if books then books[castId] else nil
	if book == nil then
		return nil
	end
	books[castId] = nil
	book.Done = true
	book.Circle:Destroy()
	if book.Light then
		book.Light:Destroy()
	end
	if burst then
		dissolve(fx, book.Model, true)
	else
		local m = book.Model
		fx.Delay(0.35, function()
			dissolve(fx, m, true)
		end)
	end
	return book
end

Effects.FinalChapter = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local castId = packet.castId or 0
	if packet.phase == "Start" then
		if not fx.Predicted then
			local hand = handPos(fx)
			if hand then
				Lib.Beam(hand, hand + Vector3.new(0, 14, 0), 0.6, PURPLE, 0.35)
				Lib.EmitBurst(hand, 3, PURPLE, 0.25)
			end
		end
		local chest = fx.Chest(fx.Character)
		if chest then
			ultHeart(fx, fx.Now() + 1.6)
		end
	elseif packet.phase == "Summon" then
		summon(fx, packet)
	elseif packet.phase == "Lock" then
		local books = fx.State.Books
		local book: Book? = if books then books[castId] else nil
		if book and typeof(data.pos) == "Vector3" then
			book.Pos = data.pos
			book.Locked = true
			fx.Sound("Charge", data.pos, { Pitch = 1.3 })
		end
	elseif packet.phase == "Slam" then
		local pos: Vector3 = if typeof(data.pos) == "Vector3" then data.pos else Vector3.zero
		finishBook(fx, castId, false)
		Lib.Shockwave(pos, 11, PURPLE, 0.5, { Dust = true })
		Lib.Flash(pos + Vector3.new(0, 2, 0), PALE, 8, 0.25)
		Lib.Emit("Debris", pos + Vector3.new(0, 2, 0), 16, { Color = PAPER, Speed = { 8, 18 } })
		Lib.Emit("Star", pos + Vector3.new(0, 2, 0), 10, { Color = PURPLE, Speed = { 6, 14 } })
		Lib.Dust(pos, 6, nil, 14)
		fx.ShakeAt(pos, 0.55, 0.35, 45)
		fx.Sound("Slam", pos)
		fx.Sound("Explosion", pos, { Volume = 0.6, Pitch = 1.25 })
		local silence = if type(data.silence) == "number" then data.silence else 3
		local hits = if type(data.hits) == "table" then data.hits else {}
		for _, m in hits do
			if typeof(m) == "Instance" and m:IsA("Model") then
				local chest = fx.Chest(m)
				if chest then
					Lib.Text(chest + Vector3.new(0, 2.6, 0), Strings.L("fx.perseverance.silenced"), PURPLE, {
						Kind = "Alert",
						Scale = 1.2,
					})
				end
				fx.Highlight(m, PURPLE, silence)
				fx.HitStop(m, 0.16)
				if m == fx.LocalCharacter() then
					fx.Screen.Flash(PURPLE, 0.35, 0.3)
				end
			end
		end
		if #hits > 0 then
			Lib.Text(pos + Vector3.new(0, 6, 0), Strings.L("fx.perseverance.theEnd"), PALE, { Kind = "Alert", Scale = 1.4 })
		end
	elseif packet.phase == "Cancel" then
		finishBook(fx, castId, true)
	end
end

Predict.FinalChapter = function(fx: any, _payload: Map)
	local hand = handPos(fx)
	if hand then
		fx.VFX.EmitBurst(hand, 3, PURPLE, 0.25)
	end
end

Indicator.FinalChapter = function(fx: any): Map?
	local Lib = fx.VFX
	local radius = 7.5
	local ring = Lib.GroundCircle(Vector3.zero, radius, PURPLE, { Rim = 0.3, Fill = 0.88, Height = 0.2 })
	ring:SetVisible(false)
	local ghost: Model? = nil
	local GiantBook = prop("GiantBook")
	if GiantBook then
		local ok, m = pcall(GiantBook.Build, bookScale(radius), PURPLE)
		if ok and m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.Transparency = 0.8
					d.Material = Enum.Material.Neon
				end
			end
			GiantBook.SetOpen(m, 1)
			ghost = m
		end
	end
	local handle: Map = {}
	function handle.Update(_self: any, _aim: Vector3, _charge: number, target: Model?)
		local r = if target then fx.Root(target) else nil
		if r == nil then
			ring:SetVisible(false)
			if ghost then
				ghost.Parent = nil
			end
			return
		end
		local g = groundUnder(fx, r.Position)
		ring:SetVisible(true)
		ring:SetCenter(g)
		if ghost then
			local me = fx.Root(fx.Character)
			local d = if me then r.Position - me.Position else Vector3.new(0, 0, -1)
			local flat = Vector3.new(d.X, 0, d.Z)
			ghost:PivotTo(Lib.LookAlong(g + Vector3.new(0, BOOK_HEIGHT, 0), if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)))
			ghost.Parent = Lib.Folder()
		end
	end
	function handle.Destroy(_self: any)
		ring:Destroy()
		if ghost then
			ghost:Destroy()
		end
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Passive visuals

function Kit.OnCharacter(fx: any, character: Model)
	-- ult heart (late joiners, missed packets)
	local function check()
		local v = character:GetAttribute("Status_Chapter")
		if type(v) == "number" and v > fx.Now() + 0.2 then
			ultHeart(fx, v)
		end
	end
	fx.Trove:Connect(character:GetAttributeChangedSignal("Status_Chapter"), check)
	check()
	-- Studious: a slow drift of purple page motes from the notebook
	local hand = fx.Attachment(character, "RightGrip") or fx.Attachment(character, "RightHand")
	if hand then
		local Lib = fx.VFX
		local e = Lib.Emitter("Mote", hand, { Color = PURPLE, Rate = 1.5 * Lib.ParticleScale() })
		fx.Trove:Add(e)
	end
end

return Kit
