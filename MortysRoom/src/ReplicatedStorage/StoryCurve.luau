--[[
	CHAPTERS 7-12: the Curve arc. Every line is written in Russian and English.
	  7  The bunker      - how to reach Evil Morty: the Central Finite Curve, Rick Prime, the Curve Bell
	  8  The Curve Bell  - the Silent dimension: three pylons, the bell rings, the sky cracks, Evil Morty
	  9  The hunt        - J-22 (upside down), D-716 (cubes), K-9 (mushrooms), back to B137:
	                       the signal is Rick. Tentacles. The chase. "YOU DON'T BELONG HERE."
	 10  The Alliance    - the army, the wounded Titan, the choice (the bunker = death), the virus
	 11  The camera base - friends Cam and Lens, Astro toilets teleport in, the mothership, the real Rick
	 12  Home            - "Blips and Chitz?" "No, Rick." Sleep. ...and after the credits: Rick Prime.
]]
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local Game = script.Parent
local Lang = require(Game.Lang)
local Audio = require(Game.Audio)
local Graphics = require(Game.Graphics)
local Fx = require(Game.Fx)
local Director = require(Game.Director)
local Dialogue = require(Game.Dialogue)
local Puppet = require(Game.Puppet)
local Scenes = require(Game.Scenes)

local StoryCurve = {}
local rgb = Color3.fromRGB
local R6 = Puppet.R6

local K: any = nil -- the tools Story hands over
local R: any, P: any = nil, nil
local W: { [string]: any } = {} -- world references
local S: { [string]: any } = { crowd = {}, conns = {}, portals = {}, loops = {} } -- undone by reset()
local start: { [string]: any } = {} -- where things live when unused

----------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------
local function api()
	return K.api()
end

local function say(c, who: string, ru: string, en: string, opts: any?)
	c.say(who, { ru = ru, en = en }, opts)
end

local function spot(folder: Instance, name: string): CFrame
	local m = folder:FindFirstChild(name)
	if m and m:IsA("BasePart") then
		return m.CFrame
	end
	warn("StoryCurve: missing spot " .. name)
	return CFrame.new()
end

-- a root marker (feet + 3) -> the eye of a standing Morty
local function eyeOf(rootCF: CFrame, h: number?): CFrame
	return CFrame.new(rootCF.Position + Vector3.new(0, h or 1.92, 0)) * rootCF.Rotation
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function near(pos: Vector3, r: number): boolean
	local root = api().root()
	if not root then
		return false
	end
	return flat(root.Position - pos).Magnitude <= r
end

local function waitNear(c, pos: Vector3, r: number, timeout: number?): boolean
	return c.waitUntil(function()
		return near(pos, r)
	end, timeout)
end

local function connect(sig: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
	local conn = sig:Connect(fn)
	table.insert(S.conns, conn)
	return conn
end

local function openPortal(cf: CFrame, kind: string?, d: number?)
	local h = Fx.portal(cf, kind, d)
	table.insert(S.portals, h)
	return h
end

local function closePortals()
	for _, h in S.portals do
		h.Close()
	end
	table.clear(S.portals)
end

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
local function groundAt(pos: Vector3): number
	terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(pos.X, 80, pos.Z), Vector3.new(0, -200, 0), terrainOnly)
	return if hit then hit.Position.Y else 0
end

local function partsWithAttr(model: Instance, attr: string): { BasePart }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute(attr) ~= nil then
			table.insert(out, d)
		end
	end
	return out
end

local function loop(key: string, parent: Instance?, volume: number?, pitch: number?): Sound?
	local s = K.loopSound(key, parent)
	if s then
		if volume then
			s.Volume = volume
		end
		if pitch then
			s.PlaybackSpeed = pitch
		end
		s.Looped = true
	end
	return s
end

----------------------------------------------------------------------------
-- crowds (Cameramen, Speakermen, TV Men cloned from templates)
----------------------------------------------------------------------------
local function spawnAgent(kind: string, cf: CFrame, name: string?): any
	local t = W.templates and W.templates:FindFirstChild(kind)
	if not t then
		return nil
	end
	local m = t:Clone() :: Model
	m.Name = name or kind
	m:SetAttribute("Template", nil)
	m:PivotTo(cf)
	m.Parent = R.cast
	local p = Puppet.new(m, "R6")
	p.t = math.random() * 10
	table.insert(S.crowd, p)
	return p
end

local function clearCrowd()
	for _, p in S.crowd do
		p:destroy()
		if p.model then
			p.model:Destroy()
		end
	end
	table.clear(S.crowd)
	S.cam, S.lens, S.commander = nil, nil, nil
end

local AGENT_KINDS = { "Cameraman", "Speakerman", "TVMan" }

-- rows of agents in front of `center`, all facing `faceTo`
local function formation(center: Vector3, faceTo: Vector3, rows: number, cols: number, gap: number)
	local dir = flat(faceTo - center).Unit
	local right = dir:Cross(Vector3.yAxis)
	local out = {}
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local x = (col - (cols - 1) / 2) * gap + (if row % 2 == 1 then gap * 0.5 else 0)
			local p = center + right * x - dir * row * gap * 1.1
			local y = groundAt(p) + 3.45
			local pos = Vector3.new(p.X, y, p.Z)
			local kind = AGENT_KINDS[((row * cols + col) % 3) + 1]
			local a = spawnAgent(kind, CFrame.lookAt(pos, pos + dir))
			if a then
				table.insert(out, a)
			end
		end
	end
	return out
end

----------------------------------------------------------------------------
-- Evil Morty's two faces
----------------------------------------------------------------------------
local EVIL_ONLY = { "EvilLidL", "EvilBrowL", "EvilBrowR", "EvilSmirk", "EyeL", "PupilL", "Mouth" }
local function evilFace(neutral: boolean)
	local m = P.evil.model
	for _, n in EVIL_ONLY do
		local p = m:FindFirstChild(n, true)
		if p and p:IsA("BasePart") then
			p.Transparency = if neutral then 1 else 0
		end
	end
	for _, p in partsWithAttr(m, "NeutralFace") do
		p.Transparency = if neutral then 0 else 1
	end
	S.neutral = neutral
end

----------------------------------------------------------------------------
-- the Titan: extra poses, wounds, the curse's head in his hand, cannons
----------------------------------------------------------------------------
local TP = {}
TP.aimBoth = {
	ShoulderL = CFrame.Angles(1.45, 0, -0.08),
	ShoulderR = CFrame.Angles(1.45, 0, 0.08),
	ElbowL = CFrame.Angles(0.1, 0, 0),
	ElbowR = CFrame.Angles(0.1, 0, 0),
	Waist = CFrame.Angles(-0.1, 0, 0),
	HipL = CFrame.Angles(0.35, 0, -0.12),
	HipR = CFrame.Angles(-0.25, 0, 0.12),
	KneeL = CFrame.Angles(-0.45, 0, 0),
}
TP.holdHead = {
	ShoulderL = CFrame.Angles(0.75, 0, -0.25),
	ElbowL = CFrame.Angles(0.95, 0, 0),
	ShoulderR = CFrame.Angles(0.15, 0, 0.3),
	Waist = CFrame.Angles(0.05, 0.1, 0),
	KneeR = CFrame.Angles(-0.15, 0, 0),
}
TP.aimRight = {
	ShoulderR = CFrame.Angles(1.5, 0, 0.1),
	ElbowR = CFrame.Angles(0.05, 0, 0),
	ShoulderL = CFrame.Angles(0.75, 0, -0.25),
	ElbowL = CFrame.Angles(0.95, 0, 0),
	Waist = CFrame.Angles(-0.05, -0.2, 0),
	HipL = CFrame.Angles(0.3, 0, -0.1),
	KneeL = CFrame.Angles(-0.4, 0, 0),
}
TP.carry = {
	ShoulderL = CFrame.Angles(0.75, 0, -0.25),
	ElbowL = CFrame.Angles(0.95, 0, 0),
	ShoulderR = CFrame.Angles(0.2, 0, 0.45),
	HipL = CFrame.Angles(0.25, 0, -0.08),
	HipR = CFrame.Angles(0.1, 0, 0.08),
	KneeL = CFrame.Angles(-0.5, 0, 0),
	KneeR = CFrame.Angles(-0.35, 0, 0),
	AnkleL = CFrame.Angles(0.4, 0, 0),
	AnkleR = CFrame.Angles(0.3, 0, 0),
	Waist = CFrame.Angles(-0.25, 0, 0),
}

local function titanWounded(on: boolean)
	for _, d in R.titanModel:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("Damage") then
				d.Transparency = if on then 0 else 1
			end
			if d:GetAttribute("LeftCannon") then
				d.Transparency = if on then 1 else 0
			end
		elseif d:IsA("ParticleEmitter") and (d.Name == "Sparks" or d.Name == "Smoke") then
			d.Enabled = on
		elseif d:IsA("PointLight") and d.Name == "MuzzleLight" and d.Parent and d.Parent:GetAttribute("LeftCannon") then
			d.Enabled = not on
		end
	end
	S.wounded = on
end

local function muzzle(name: string): BasePart?
	return R.titanModel:FindFirstChild(name, true) :: BasePart?
end

-- glow the cannon muzzles (0..1)
local function cannonCharge(a: number)
	for _, g in partsWithAttr(R.titanModel, "TitanMuzzle") do
		local base = g:GetAttribute("BaseSize") or g.Size
		if not g:GetAttribute("BaseSize") then
			g:SetAttribute("BaseSize", g.Size)
		end
		g.Size = base * (1 + a * 0.8)
		local l = g:FindFirstChildOfClass("PointLight")
		if l then
			l.Brightness = 1.5 + a * 10
			l.Range = 26 + a * 24
		end
	end
end

local function holdCurseHead(on: boolean)
	if S.headConn then
		S.headConn:Disconnect()
		S.headConn = nil
	end
	local wisps = W.curseHead.PrimaryPart and W.curseHead.PrimaryPart:FindFirstChildOfClass("ParticleEmitter")
	if wisps then
		wisps.Enabled = on
	end
	if on then
		local hand = R.titanModel:FindFirstChild("HandL") :: BasePart?
		S.headConn = RunService.RenderStepped:Connect(function()
			if hand then
				local look = R.titanModel.PrimaryPart.CFrame.LookVector
				local pos = hand.Position + Vector3.new(0, 4.4, 0) + look * 1.5
				W.curseHead:PivotTo(CFrame.lookAt(pos, pos + flat(look)))
			end
		end)
	end
end

local function titanTo(cf: CFrame)
	P.titan.root.CFrame = cf * CFrame.new(0, 30.4, 0)
end

-- the Titan flies in along a curve and lands (yields)
local function titanLand(c, from: Vector3, groundCF: CFrame, dur: number)
	local titan = P.titan
	local standRoot = groundCF * CFrame.new(0, 30.4, 0)
	local mid = from:Lerp(standRoot.Position, 0.5) + Vector3.new(0, 60, 0)
	titan:pose(K.TITAN_POSES.fly, 6)
	titan:snap()
	titan.root.CFrame = CFrame.lookAt(from, mid)
	K.titanJets(true)
	local thruster = Audio.make("Thruster", titan.root)
	if thruster then
		thruster:Play()
	end
	local prev = from
	K.animate(dur, function(a)
		local pos = K.bezier(from, mid, standRoot.Position + Vector3.new(0, 12, 0), a)
		local dir = pos - prev
		prev = pos
		local look = if dir.Magnitude > 0.01 then dir.Unit else standRoot.LookVector
		titan.root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(look.X, look.Y * 0.4, look.Z)):Lerp(CFrame.new(pos) * standRoot.Rotation, math.clamp((a - 0.7) * 3.4, 0, 1))
		if a > 0.82 then
			titan:pose(K.TITAN_POSES.land, 10)
		end
	end, "out")
	c.check()
	K.titanJets(false)
	if thruster then
		Audio.fadeOut(thruster, 0.4, true)
	end
	local crouch = groundCF * CFrame.new(0, 30.4 - 7.2, 0)
	K.animate(0.25, function(a)
		titan.root.CFrame = (standRoot * CFrame.new(0, 12, 0)):Lerp(crouch, a)
	end, "in")
	K.play3D("RobotStomp", groundCF.Position)
	Audio.play("Boom", 0.9)
	Fx.dust(groundCF.Position, 34, 160)
	Fx.shockwave(groundCF.Position + Vector3.new(0, 2, 0), 46, 0.7, rgb(255, 190, 150))
	Director.shake(2.4, 1.2, 14)
	c.wait(0.6)
	titan:pose(K.TITAN_POSES.stand, 4)
	K.animate(1.0, function(a)
		titan.root.CFrame = crouch:Lerp(standRoot, a)
	end)
end

----------------------------------------------------------------------------
-- tentacle beasts
----------------------------------------------------------------------------
local function beastWiggle(p, speed: number)
	p.wiggle = speed
	p.extra = function(t, _dt)
		local sp = p.wiggle or 1
		local out = {}
		local n = p.model:GetAttribute("Tentacles") or 8
		for ti = 1, n do
			local legs = ti <= 4
			for k = 1, 6 do
				local ph = t * (2.5 + sp * 5) + ti * 1.9 + k * 0.7
				local amp = (if legs then 0.18 else 0.3) * (0.6 + sp * 0.4)
				out["T" .. ti .. "_" .. k] = CFrame.Angles(math.sin(ph) * amp, 0, math.cos(ph * 0.83) * amp * 0.8)
			end
		end
		out.Waist = CFrame.Angles(math.sin(t * 6 * sp) * 0.05, math.sin(t * 2.1) * 0.12, 0)
		return out
	end
end

local function pitWiggle(speed: number, reach: number)
	local p = P.pit
	p.extra = function(t, _dt)
		local out = {}
		for ti = 1, 5 do
			for k = 1, 7 do
				local ph = t * (3 + speed * 6) + ti * 1.3 + k * 0.8
				out["T" .. ti .. "_" .. k] = CFrame.Angles(math.sin(ph) * 0.35 + reach * 0.12, 0, math.cos(ph * 0.9) * 0.3)
			end
		end
		return out
	end
end

local function hideBeasts()
	for _, key in { "rickBeast", "evilBeast", "pit" } do
		local p = P[key]
		p.follow = nil
		p.extra = nil
		p.root.CFrame = start[key]
		K.emitters(p.model, "BlackCloud", false)
	end
	P.entity.root.CFrame = start.entity
	P.entity.extra = nil
	K.entityCloud(false)
end

----------------------------------------------------------------------------
-- the bunker shed (the fake one)
----------------------------------------------------------------------------
local function shedVisible(on: boolean)
	for _, d in W.shed:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("ShedPart") then
			d.Transparency = if on then 0 else 1
			d.CanCollide = on
		end
	end
	local sign = W.shed:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChildOfClass("SurfaceGui")
	if gui then
		gui.Enabled = on
	end
end

local function shedDoor(a: number)
	local door = W.shed:FindFirstChild("ShedDoor")
	if door and start.shedDoor then
		K.hingeRotate(start.shedDoor, door:GetAttribute("Hinge"), CFrame.Angles(0, a * math.rad(100), 0))
	end
end

----------------------------------------------------------------------------
-- the Silent dimension
----------------------------------------------------------------------------
local function pylonOn(model: Instance, on: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("PylonCrystal") then
				d.Material = if on then Enum.Material.Neon else Enum.Material.Glass
				d.Color = if on then rgb(140, 255, 180) else rgb(40, 80, 60)
			elseif d:GetAttribute("PylonPanel") then
				d.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
				d.Color = if on then rgb(140, 255, 180) else rgb(60, 120, 90)
			end
		elseif d:IsA("PointLight") and d.Name == "PylonLight" then
			d.Brightness = if on then 2.5 else 0
		end
	end
end

local function resetSilent()
	for i = 1, 3 do
		local py = W.silent:FindFirstChild("Pylon" .. i)
		if py then
			pylonOn(py, false)
		end
	end
	for _, p in partsWithAttr(W.cracks, "Crack") do
		p.Transparency = 1
	end
	for _, p in partsWithAttr(W.bell, "BellRing") do
		p.Transparency = 1
	end
	for _, p in partsWithAttr(W.bell, "BellCone") do
		p.Color = rgb(150, 40, 24)
	end
	for part, cf in start.prongs or {} do
		part.CFrame = cf
	end
end

----------------------------------------------------------------------------
-- companions who follow Morty around
----------------------------------------------------------------------------
local function follow(p, side: number, speed: number)
	p.follow = function(dt)
		local cur = p.root.CFrame
		local root = api().root()
		if not root then
			return cur
		end
		local rc = root.CFrame
		local target = rc.Position + rc.RightVector * (side * 3.4) - rc.LookVector * 3.2
		local delta = flat(target - cur.Position)
		local dist = delta.Magnitude
		if dist < 1.4 then
			p.walk = 0
			local look = flat(rc.LookVector)
			if look.Magnitude < 0.01 then
				return cur
			end
			return cur:Lerp(CFrame.lookAt(cur.Position, cur.Position + look), math.min(1, dt * 4))
		end
		p.walk = 1
		p.walkSpeed = speed
		local step = math.min(dist, (speed + math.max(0, dist - 6) * 1.6) * dt)
		local newPos = cur.Position + delta.Unit * step
		return CFrame.lookAt(newPos, newPos + delta)
	end
end

local function stopFollow(p)
	p.follow = nil
	p.walk = 0
end

----------------------------------------------------------------------------
-- small shared beats
----------------------------------------------------------------------------
local function arriveIn(c, folder: Instance, scene: string, caption: string, withEvil: boolean)
	Fx.black(1)
	local arrive = spot(folder, "Arrive")
	K.holdCharacterAt(c, arrive)
	api().hideCharacter(true)
	Scenes.apply(scene, true)
	local rick = P.rick
	rick.follow = nil
	rick:visible(true)
	rick:place(spot(folder, "RickArrive"))
	rick:pose("stand")
	rick:snap()
	if withEvil then
		local evil = P.evil
		evil.follow = nil
		evil:visible(true)
		evil:place(spot(folder, "EvilArrive"))
		evil:pose("stand")
		evil:snap()
	end
	local portal = openPortal(spot(folder, "Portal"), "green", 9)
	Director.start()
	Director.cut(eyeOf(arrive), 70)
	Director.freeLook(true, { yaw = 1.4, pitchUp = 0.8, pitchDown = 0.6 })
	Audio.play("Whoosh")
	Fx.flash(rgb(200, 255, 200), 0.8, 0.02, 0.6)
	Fx.fade(0, 0.5)
	Fx.caption(caption)
	task.delay(1.4, function()
		portal.Close()
	end)
	return arrive
end

-- a portal out: Rick + Evil Morty walk in, then the player (yields until the player is through)
local function leaveThrough(c, cf: CFrame, kind: string?)
	local portal = openPortal(cf, kind or "green", 9)
	local pos = cf.Position
	local ground = Vector3.new(pos.X, 0, pos.Z)
	for _, p in { P.rick, P.evil } do
		if p.root.Position.Y > -100 then
			stopFollow(p)
			task.spawn(function()
				p:walkTo(Vector3.new(ground.X, p.root.Position.Y, ground.Z), 10)
				p:visible(false)
			end)
		end
	end
	api().objective("obj.portal")
	waitNear(c, pos, 3.4, 40)
	api().objective(nil)
	Audio.play("Whoosh")
	Fx.flash(rgb(200, 255, 200), 1, 0.05, 0.4)
	Fx.fade(1, 0.25, true)
	portal.Close()
	api().gameplay(false)
	api().freeze(true)
end

-- Rick checks the radar (yields)
local function radarCheck(c, lines: { any }, blipX: number, blipY: number, blipOn: boolean)
	local rick = P.rick
	stopFollow(rick)
	rick:lookAt(nil)
	rick:pose("holdRadar", 8)
	K.Radar.holdProp(true)
	Audio.play("Servo", 1.6)
	c.wait(0.6)
	K.Radar.show(true, lines)
	K.Radar.setBlip(blipX, blipY, blipOn)
end

local function radarDone()
	K.Radar.show(false)
	K.Radar.holdProp(false)
	P.rick:pose("stand", 8)
end

----------------------------------------------------------------------------
-- CHAPTER 7: The bunker - the plan
----------------------------------------------------------------------------
local function ch7(c, _fresh: boolean)
	api().state("story")
	api().gameplay(false)
	Fx.black(1)
	local rick = P.rick
	local spots = R.bunkerSpots
	local seat = spots.MortySeat.CFrame
	K.holdCharacterAt(c, seat)
	Scenes.apply("Bunker", true)
	Fx.muffle(false)
	rick.follow = nil
	rick:visible(true)
	rick:place(spots.RickSeat.CFrame)
	rick:pose("sit", 10)
	rick:snap()
	rick.glitch = 0.25
	local eye = spots.MortyEye.CFrame
	rick:lookAt(eye.Position)
	Director.start()
	Director.cut(eye, 70)
	Director.freeLook(true, { yaw = 1.4, pitchUp = 0.6, pitchDown = 0.9 })
	local room = R.bunkerRoom
	local tbl = room:FindFirstChild("BunkerTable")
	local map = tbl and tbl:FindFirstChild("Map") :: BasePart?
	local label = map and map:FindFirstChild("TargetLabel", true) :: TextLabel?
	if label then
		label.Text = Lang.t("map.target")
	end
	Audio.music("MusicBunker", 4)
	Fx.title("ch.7")
	c.check()
	Fx.fade(0, 1.6)

	-- bombs falling up above: the lamp swings, dust rains down
	local lamp = room:FindFirstChild("HangingLamp")
	local lampInit: { [BasePart]: CFrame } = {}
	if lamp then
		for _, d in lamp:GetDescendants() do
			if d:IsA("BasePart") then
				lampInit[d] = d.CFrame
			end
		end
	end
	local swing = 0
	local pivot = if lamp then lamp:GetAttribute("Pivot") else nil
	local dust = room:FindFirstChild("DustSource")
	local dustEmitter = dust and dust:FindFirstChildOfClass("ParticleEmitter")
	local function boom(strength: number)
		Audio.play("MuffledBoom", 0.8 + math.random() * 0.4)
		Director.shake(0.5 * strength, 0.9)
		swing += 0.18 * strength
		if dustEmitter then
			dustEmitter:Emit(math.floor(30 * strength))
		end
		Audio.play("DustFall", 1 + math.random() * 0.2)
		Graphics.SetLight("BunkerLamp", false)
		Graphics.SetLight("BunkerEmergency", true, { Brightness = 1.6 })
		task.delay(0.08 + math.random() * 0.12, function()
			Graphics.SetLight("BunkerLamp", true)
		end)
		task.delay(0.6, function()
			Graphics.SetLight("BunkerEmergency", false)
		end)
	end
	local bombing = true
	task.spawn(function()
		local t = 0
		while bombing and c.alive() do
			local dt = RunService.RenderStepped:Wait()
			t += dt
			swing *= math.exp(-dt * 0.5)
			if pivot then
				local a = math.sin(t * 2.2) * swing
				K.hingeRotate(lampInit, pivot, CFrame.Angles(a, 0, a * 0.6))
			end
		end
		if lamp then
			for part, cf in lampInit do
				part.CFrame = cf
			end
		end
	end)
	task.spawn(function()
		while bombing and c.alive() do
			task.wait(5 + math.random() * 3)
			if bombing and c.alive() then
				boom(1)
			end
		end
	end)

	c.wait(1)
	say(c, "Morty", "Рик... что это было? Тот робот... с колонками вместо головы?", "Rick... what was that? That robot... with speakers for a head?")
	say(c, "Rick", "Титан Спикермен. Версия два-ноль. Если он здесь — дело дрянь.", "Titan Speakerman. Version two-point-oh. If he's here, things are bad.", { glitch = 0.2 })
	say(c, "Rick", "А та штука в дыму... Морти, проклятие — это не просто неудача. За ним кто-то стоит.", "And that thing in the smoke... Morty, the curse isn't just bad luck. Someone's behind it.", { glitch = 0.3 })
	-- Rick points at the map
	rick:pose({
		["Right Hip"] = R6.leg(1, 1.57),
		["Left Hip"] = R6.leg(-1, 1.57),
		["Right Shoulder"] = R6.arm(1, 1.3, 0.1),
		RootJoint = R6.root(0.25),
	}, 8)
	Director.freeLook(false)
	if map then
		Director.move(CFrame.lookAt(eye.Position, map.Position), 1.0)
	end
	say(c, "Rick", "Злой Морти. Только он знает, что творится за краем.", "Evil Morty. He's the only one who knows what's out past the edge.", { glitch = 0.15 })
	boom(1.6)
	say(c, "Morty", "Злой Морти?! Но как нам до него добраться?", "Evil Morty?! How do we even get to him?")
	rick:pose("sit", 8)
	Director.move(eye, 1.0)
	Director.freeLook(true)
	say(c, "Rick", "Он сидит снаружи Центральной Конечной Кривой. Туда просто так не попасть.", "He's sitting outside the Central Finite Curve. You don't just walk out there.", { glitch = 0.2 })
	say(c, "Morty", "Центральной... чего?", "The Central... what?")
	say(c, "Rick", "Ладно, урок. Мультивселенная бесконечна, Морти. Бесконечно много миров.", "Okay, lesson time. The multiverse is infinite, Morty. Infinitely many worlds.", { glitch = 0.15 })
	say(c, "Rick", "Но мы, Рики, вырезали из неё кусок. Только те миры, где Рик — самый умный во вселенной. И обнесли их стеной.", "But we Ricks cut a piece out of it. Only the worlds where Rick is the smartest being in the universe. And we walled them in.", { glitch = 0.2 })
	say(c, "Rick", "Это и есть Центральная Конечная Кривая. Огромный загон для Риков. А снаружи — всё остальное.", "That's the Central Finite Curve. A giant pen for Ricks. And outside it: everything else.", { glitch = 0.2 })

	-- Morty dozes off while Rick lectures
	Fx.muffle(true)
	task.spawn(api().lids, 0.22, 3.2)
	Director.move(eye * CFrame.Angles(math.rad(-16), 0, math.rad(4)), 3.4, "smooth", nil, true)
	say(c, "Rick", "...стенка держится на резонансе... частота... гармоники... бла-бла-бла...", "...the wall runs on resonance... frequency... harmonics... blah blah blah...", { auto = 1.2, glitch = 0.35 })
	say(c, "Rick", "...и вот тогда мы с Риком Праймом...", "...and that's when Rick Prime and I...", { auto = 0.6, glitch = 0.2 })
	Dialogue.hide()
	-- ...and he's awake
	Fx.muffle(false)
	api().lids(1, 0.12)
	Audio.play("Gasp")
	Director.move(eye, 0.2)
	Director.shake(0.4, 0.3)
	boom(1.2)
	say(c, "Morty", "РИК ПРАЙМ?!", "RICK PRIME?!")
	say(c, "Rick", "О, проснулся. Да. Мы с ним однажды уже трясли эту стенку. Давно. Когда были... почти друзьями.", "Oh, now you're awake. Yeah. He and I rattled that wall once. Long ago. Back when we were... almost friends.", { glitch = 0.25 })
	say(c, "Rick", "Мы нашли её частоту. Если ударить по кривой правильным звуком — она звенит, как колокол. И её слышат все, кто за ней.", "We found its frequency. Hit the curve with the right sound and it rings like a bell. Everyone outside hears it.", { glitch = 0.2 })
	say(c, "Morty", "И Злой Морти услышит?", "And Evil Morty will hear it?")
	say(c, "Rick", "Это его стена, Морти. Конечно, услышит. И придёт посмотреть, кто по ней стучит.", "It's his wall now, Morty. Of course he'll hear it. And he'll come see who's knocking.", { glitch = 0.2 })
	say(c, "Morty", "А чем мы по ней ударим? У нас нет колокола.", "And what do we hit it with? We don't have a bell.")
	-- the Titan's speaker on the table
	local prop = Fx.part({ Size = Vector3.new(1.6, 1.6, 0.9), Color = rgb(18, 18, 20), Material = Enum.Material.Metal })
	local cone = Fx.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1.2, 1.2), Color = rgb(255, 64, 28), Material = Enum.Material.Neon })
	if map then
		local base = map.CFrame * CFrame.new(0.6, 0.8, -0.2) * CFrame.Angles(0, math.rad(160), 0)
		prop.CFrame = base
		cone.CFrame = base * CFrame.new(0, 0, -0.46) * CFrame.Angles(0, math.rad(90), 0)
	end
	local glow = Instance.new("PointLight")
	glow.Color = rgb(255, 70, 30)
	glow.Range = 8
	glow.Brightness = 1.5
	glow.Parent = cone
	Audio.play("Clink", 0.6)
	if map then
		Director.move(CFrame.lookAt(eye.Position, prop.Position), 0.8)
	end
	say(c, "Rick", "Есть. Кусок колонки Титана. Подобрал, пока ты валялся в песке. Самый громкий динамик в мультивселенной.", "We do. A chunk of the Titan's speaker. Grabbed it while you were lying in the sand. The loudest speaker in the multiverse.", { glitch = 0.2 })
	say(c, "Rick", "Сделаем из него Колокол Кривой. Но звонить надо в полной тишине. Там, где нет ни одного звука.", "We'll turn it into a Curve Bell. But you have to ring it in total silence. Somewhere with no sound at all.", { glitch = 0.2 })
	say(c, "Morty", "И где такое место?", "And where's a place like that?")
	-- Rick gets up and opens a portal
	Director.move(eye, 0.8)
	local y0 = seat.Position.Y - 2.7
	local center = Vector3.new(seat.Position.X, y0, seat.Position.Z - 3.6)
	local portalCF = CFrame.lookAt(center + Vector3.new(-8.6, 3.6, 0), center + Vector3.new(0, 3.6, 0))
	rick:pose("stand", 8)
	rick:place(CFrame.lookAt(center + Vector3.new(-2.5, 3.36, -3.6), center + Vector3.new(-8, 3.36, 0)))
	Audio.play("Click")
	local portal = openPortal(portalCF, "green", 7.5)
	say(c, "Rick", "Тихое измерение. Пошли, Морти. И постарайся не шуметь. *рыг*", "The Silent dimension. Let's go, Morty. And try not to make a sound. *burp*", { glitch = 0.25 })
	Audio.play("Burp")
	Dialogue.hide()
	task.spawn(function()
		rick:walkTo(Vector3.new(portalCF.Position.X + 0.5, center.Y + 3.36, portalCF.Position.Z), 7)
		rick:visible(false)
	end)
	-- Morty walks in himself
	Director.freeLook(false)
	local standPos = Vector3.new(center.X + 1.8, y0 + 3, center.Z + 3.6)
	K.giveControl(c, CFrame.lookAt(standPos, Vector3.new(portalCF.Position.X, standPos.Y, portalCF.Position.Z)))
	api().objective("obj.portal")
	waitNear(c, portalCF.Position, 2.6, 45)
	api().objective(nil)
	bombing = false
	Audio.play("Whoosh")
	Fx.flash(rgb(220, 255, 220), 1, 0.05, 0.4)
	Fx.fade(1, 0.25, true)
	portal.Close()
	prop:Destroy()
	cone:Destroy()
	api().gameplay(false)
	api().freeze(true)
	Audio.music(nil, 0.4)
end

----------------------------------------------------------------------------
-- CHAPTER 8: The Curve Bell
----------------------------------------------------------------------------
local function bellBong(strength: number)
	local B = spot(W.silentSpots, "Bell").Position
	Audio.play("Clink", 0.22)
	Audio.play("Boom", 0.55)
	K.play3D("SonicBoom", B + Vector3.new(0, 30, 0), 0.6)
	Fx.shockwave(B + Vector3.new(0, 20, 0), 180 + strength * 120, 1.6 + strength, rgb(235, 245, 255))
	Fx.flash(Color3.new(1, 1, 1), 0.25 + strength * 0.35, 0.03, 0.9)
	Director.shake(0.6 + strength * 1.2, 1.4 + strength, 18)
	-- the prongs shiver
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 2.4 do
			local k = 1 - (os.clock() - t0) / 2.4
			for part, cf in start.prongs or {} do
				local sx = part:GetAttribute("BellProng") or 1
				part.CFrame = cf * CFrame.new(sx * math.sin(os.clock() * 70) * 0.35 * k * strength, 0, 0)
			end
			RunService.RenderStepped:Wait()
		end
		for part, cf in start.prongs or {} do
			part.CFrame = cf
		end
	end)
end

local function crackSky(c, upTo: number)
	-- show crack segments in order of their number (k * 10 + branch)
	local list = partsWithAttr(W.cracks, "Crack")
	table.sort(list, function(a, b)
		return a:GetAttribute("Crack") < b:GetAttribute("Crack")
	end)
	local level = -1
	for _, p in list do
		local n = p:GetAttribute("Crack")
		if n <= upTo and p.Transparency > 0.5 then
			p.Transparency = 0
			local k = math.floor(n / 10)
			if k ~= level then
				level = k
				Audio.play("Glitch2", 0.45 + k * 0.05)
				Director.shake(0.25, 0.3)
			end
			task.wait(0.035)
			c.check()
		end
	end
end

local function ch8(c, _fresh: boolean)
	api().state("story")
	api().gameplay(false)
	Audio.music(nil, 0.3)
	resetSilent()
	P.evil:place(start.evil)
	evilFace(false)
	P.evil.glitch = 0
	local sp = W.silentSpots
	local arrive = arriveIn(c, sp, "Silent", "loc.silent", false)
	local rick = P.rick
	rick.glitch = 0.3
	Fx.title("ch.8")
	c.check()
	say(c, "Morty", "Тут... так тихо. Я слышу, как у меня сердце стучит.", "It's... so quiet here. I can hear my own heartbeat.")
	say(c, "Rick", "Тихое измерение S-0. Тут нет ни одного звука, кроме тех, что ты принёс с собой.", "Silent dimension S-0. There's not a single sound here except the ones you bring along.", { glitch = 0.2 })
	local bellPos = spot(sp, "Bell").Position
	Director.freeLook(false)
	Director.move(CFrame.lookAt(eyeOf(arrive).Position, bellPos + Vector3.new(0, 28, 0)), 1.4)
	say(c, "Rick", "Идеальное место, чтобы позвонить в кривую. Знакомься — Колокол Кривой.", "The perfect place to ring the curve. Meet the Curve Bell.", { glitch = 0.15 })
	say(c, "Morty", "Это же... гигантский камертон! С колонкой Титана посередине!", "That's... a giant tuning fork! With the Titan's speaker in the middle!")
	say(c, "Rick", "Собрал за ночь. Ну, почти за ночь. Включи три пилона вокруг, а я настрою частоту.", "Built it overnight. Well, almost overnight. Switch on the three pylons around it, I'll tune the frequency.", { glitch = 0.25 })
	Dialogue.hide()
	local consoleCF = spot(sp, "RickConsole")
	task.spawn(function()
		rick:walkTo(consoleCF.Position, 9, consoleCF.Position + consoleCF.LookVector * 5)
	end)
	K.giveControl(c, arrive, CFrame.lookAt(eyeOf(arrive).Position, bellPos + Vector3.new(0, 10, 0)))
	api().objective("obj.pylons")
	local done = 0
	local activated = {}
	while done < 3 do
		local model = c.interact("Pylon")
		local idx = model:GetAttribute("Index")
		if idx and not activated[idx] then
			activated[idx] = true
			done += 1
			pylonOn(model, true)
			Audio.play("Electric", 1.2)
			Audio.play("Switch")
			local crystal = model:FindFirstChild("Crystal") :: BasePart?
			if crystal then
				Fx.sparks(crystal.Position, 24, rgb(160, 255, 190))
				Fx.sonicRing(CFrame.lookAt(crystal.Position, bellPos + Vector3.new(0, 9, 0)), (bellPos - crystal.Position).Magnitude, 0.8, 3, rgb(140, 255, 180))
			end
			api().objective({ ru = ("Включи три пилона (%d/3)"):format(done), en = ("Switch on the three pylons (%d/3)"):format(done) })
			if done == 1 then
				say(c, "Rick", "Есть один! Чувствуешь, как воздух дрожит? Это кривая чешется.", "That's one! Feel the air trembling? That's the curve getting itchy.", { auto = 1.6, glitch = 0.2 })
			elseif done == 2 then
				say(c, "MortyThought", "Почему Рик так глючит? Даже здесь, где ничего нет...", "Why is Rick glitching so much? Even here, where there's nothing at all...", { auto = 2 })
			end
			Dialogue.hide()
		end
	end
	api().objective("obj.rickBell")
	waitNear(c, consoleCF.Position, 12, 60)
	api().objective(nil)
	api().gameplay(false)
	api().freeze(true)
	api().hideCharacter(true)

	-- RING THE BELL ---------------------------------------------------------------
	local watch = spot(sp, "MortyWatch")
	local watchEye = CFrame.lookAt(eyeOf(watch).Position, bellPos + Vector3.new(0, 30, 0))
	Director.start()
	Director.move(watchEye, 1.4, "smooth", 70)
	rick:lookAt(bellPos + Vector3.new(0, 10, 0))
	say(c, "Rick", "Частота... есть. Морти, закрой уши. Хотя нет. Не поможет.", "Frequency... locked. Morty, cover your ears. Actually no. It won't help.", { glitch = 0.3 })
	Dialogue.hide()
	local cone = partsWithAttr(W.bell, "BellCone")[1]
	local ring = partsWithAttr(W.bell, "BellRing")[1]
	K.play3D("ChargeLong", bellPos, 0.8)
	K.animate(2.2, function(a)
		if cone then
			cone.Color = Color3.fromRGB(150, 40, 24):Lerp(Color3.fromRGB(255, 120, 70), a)
		end
		if ring then
			ring.Transparency = 1 - a * 0.85
		end
		Director.roll(math.sin(os.clock() * 40) * 0.003 * a)
	end, "in")
	Director.roll(0)
	c.check()
	bellBong(0.6)
	c.wait(2.2)
	say(c, "Morty", "О-ОНО РАБОТАЕТ?!", "I-IS IT WORKING?!", { auto = 0.8 })
	Dialogue.hide()
	bellBong(1)
	Scenes.apply("SilentCrack")
	-- the sky cracks
	Director.move(CFrame.lookAt(watchEye.Position, Vector3.new(bellPos.X, 175, bellPos.Z - 390)), 1.2, "smooth", 62)
	crackSky(c, 39)
	c.wait(1.2)
	bellBong(1.4)
	crackSky(c, 99)
	Fx.glitch(0.8, 0.5)
	Audio.music("MusicEerie", 3)
	say(c, "Rick", "Есть! Кривая трещит! Её сейчас слышит каждый Рик в мультивселенной!", "Yes! The curve is cracking! Every Rick in the multiverse can hear it right now!", { auto = 1.4, glitch = 0.4 })
	Dialogue.hide()
	-- someone comes through
	local core = partsWithAttr(W.cracks, "Crack")
	for _, p in core do
		if p:GetAttribute("Crack") == 0 then
			p.Transparency = 0
		end
	end
	c.wait(0.8)
	local evilPortal = openPortal(spot(sp, "EvilPortal"), "white", 8)
	Director.move(CFrame.lookAt(watchEye.Position, spot(sp, "EvilPortal").Position), 1.0, "smooth", 60)
	local evil = P.evil
	evil:visible(true)
	evil:place(spot(sp, "EvilPortal") * CFrame.new(0, -3, 0))
	evil:pose("stand")
	evil:snap()
	local evilSpot = spot(sp, "EvilArrive")
	evil:walkTo(evilSpot.Position, 5, watchEye.Position)
	evilPortal.Close()
	evil:lookAt(watchEye.Position)
	Director.track(function()
		local head = evil.model:FindFirstChild("Head") :: BasePart?
		return CFrame.lookAt(watchEye.Position, if head then head.Position else evilSpot.Position)
	end)
	Director.fov(48, 1.5)
	say(c, "EvilMorty", "Кто стучит в мою стену?", "Who's knocking on my wall?")
	say(c, "Morty", "Э-это мы! То есть... привет. Злой Морти.", "I-it's us! I mean... hi. Evil Morty.")
	say(c, "EvilMorty", "Не называй меня так.", "Don't call me that.")
	evil:lookAt(rick.root.Position + Vector3.new(0, 1.5, 0))
	say(c, "EvilMorty", "Рик. Ну конечно. Кто ещё станет ломать кривую ради собственной шкуры.", "Rick. Of course. Who else would crack the curve to save his own skin.")
	say(c, "Rick", "Не ради своей. Ради шкуры Морти. За нами охотится проклятие.", "Not mine. Morty's. A curse is hunting us.", { glitch = 0.3 })
	evil:lookAt(watchEye.Position)
	say(c, "EvilMorty", "Это не проклятие. Я видел его снаружи кривой. Оно не из нашей мультивселенной.", "It's not a curse. I've seen it outside the curve. It's not from our multiverse.")
	say(c, "EvilMorty", "Оно ходит между мирами и ищет самого умного. Питается неудачей. Ломает тебе жизнь — и растёт.", "It walks between worlds looking for the smartest one around. It feeds on bad luck. It wrecks your life, and it grows.")
	say(c, "EvilMorty", "А потом надевает твоё лицо.", "And then it puts on your face.")
	say(c, "Morty", "Н-надевает... лицо?!", "P-puts on... your face?!")
	say(c, "EvilMorty", "Чтобы его убить, нужно найти, где оно прячется. Оно всегда прячется у всех на виду.", "To kill it, you have to find where it hides. It always hides in plain sight.")
	-- Rick glitches hard... and Evil Morty notices
	say(c, "Rick", "Отлично. Найдём, убьём, закроем дыру, и все р-р-р-расходятся по д-д-домам.", "Great. We find it, we kill it, we patch the hole and everyone g-g-g-goes h-h-home.", { glitch = 0.9 })
	rick.glitch = 1
	Fx.glitch(0.5, 0.35)
	Audio.play("Glitch3", 0.9)
	c.wait(0.7)
	rick.glitch = 0.35
	evil:lookAt(rick.root.Position + Vector3.new(0, 1.6, 0))
	local head = evil.model:FindFirstChild("Head") :: BasePart?
	if head then
		local face = head.CFrame * CFrame.new(0, 0.1, -3.2)
		Director.move(CFrame.lookAt(face.Position, head.Position), 0.5, "out", 40)
	end
	c.wait(0.5)
	evilFace(true)
	Audio.play("Glitch1", 0.6)
	c.wait(1.6)
	evil.glitch = 0.14
	c.wait(0.6)
	Director.move(CFrame.lookAt(watchEye.Position, if head then head.Position else evilSpot.Position), 0.6, "smooth", 50)
	evil:lookAt(watchEye.Position)
	say(c, "Morty", "Эй... Всё хорошо?", "Hey... Is everything okay?")
	say(c, "EvilMorty", "Не твоё дело.", "None of your business.")
	c.wait(0.4)
	say(c, "EvilMorty", "Я иду с вами. Хочу увидеть эту тварь своими глазами. Ну... своим глазом.", "I'm coming with you. I want to see this thing with my own eyes. Well... my own eye.")
	say(c, "Rick", "Тогда в путь. Радар найдёт её в одном из миров. Наверное.", "Then let's go. The radar will find it in one of the worlds. Probably.", { glitch = 0.3 })
	Dialogue.hide()
	Director.fov(70, 1)
	local out = openPortal(CFrame.lookAt(watch.Position + Vector3.new(-8, 3, -10), watch.Position + Vector3.new(0, 3, 0)), "green", 9)
	Audio.play("Click")
	c.wait(1.2)
	Fx.fade(1, 0.6, true)
	out.Close()
	Audio.music(nil, 1)
end

----------------------------------------------------------------------------
-- CHAPTER 9: The hunt
----------------------------------------------------------------------------
local function worldJ22(c)
	local sp = W.j22:FindFirstChild("J22Spots")
	local rain = W.j22:FindFirstChild("RainSource")
	local rainEmitter = rain and rain:FindFirstChildOfClass("ParticleEmitter")
	if rainEmitter then
		rainEmitter.Enabled = true
	end
	local arrive = arriveIn(c, sp, "Upside", "loc.j22", true)
	Audio.music("MusicEerie", 2)
	c.wait(1.2)
	say(c, "Rick", "J-22. Тут всё вверх ногами.", "J-22. Everything here is upside down.", { glitch = 0.2 })
	Director.freeLook(false)
	Director.move(CFrame.lookAt(eyeOf(arrive).Position, eyeOf(arrive).Position + Vector3.new(-10, 18, -40)), 1.2)
	say(c, "Morty", "Рик... а почему дождь идёт ВВЕРХ?!", "Rick... why is the rain falling UP?!")
	say(c, "Rick", "Потому что тут «вверх» — это «вниз», Морти. Не задавай вопросов, ответы тебе не понравятся.", "Because up here is down, Morty. Don't ask questions you don't want the answers to.", { glitch = 0.2 })
	say(c, "EvilMorty", "Проверь радар, Рик. Я не собираюсь торчать в этом мире.", "Check the radar, Rick. I'm not hanging around in this world.")
	Director.move(eyeOf(arrive), 0.8)
	radarCheck(c, { "radar.search", "radar.signal", "radar.none", "radar.where", "radar.glitch" }, 0.5, 0.5, false)
	say(c, "Rick", "Пусто. Хм. Пройдёмся по улице, может, оно залезло в какой-нибудь дом.", "Nothing. Hm. Let's walk down the street, maybe it crawled into one of the houses.", { glitch = 0.2 })
	radarDone()
	Dialogue.hide()
	Director.freeLook(false)
	K.giveControl(c, arrive)
	follow(P.rick, 1, 8)
	follow(P.evil, -1, 8)
	api().objective("obj.explore")
	local walk = spot(sp, "Walk")
	waitNear(c, walk.Position, 8, 50)
	api().objective(nil)
	-- a voice from an upside-down house
	K.play3D("Thud", walk.Position + Vector3.new(-28, 14, 0), 0.8)
	say(c, "Unknown", "ЭЙ! А ну не топчите наш потолок!", "HEY! Stop stomping on our ceiling!", { auto = 1.4 })
	say(c, "Morty", "П-простите!", "S-sorry!", { auto = 1 })
	say(c, "Rick", "Местные. Живут на потолке и ругаются на всех, кто ходит по полу. Классика.", "Locals. They live on the ceiling and yell at anyone walking on the floor. Classic.", { auto = 2, glitch = 0.2 })
	say(c, "EvilMorty", "Его здесь нет. Дальше.", "It's not here. Next.", { auto = 1.4 })
	Dialogue.hide()
	leaveThrough(c, spot(sp, "PortalOut"))
	if rainEmitter then
		rainEmitter.Enabled = false
	end
end

local function worldD716(c)
	local sp = W.d716:FindFirstChild("D716Spots")
	local arrive = arriveIn(c, sp, "Cube", "loc.d716", true)
	Audio.music("MusicLofi", 2)
	c.wait(1.2)
	say(c, "Rick", "D-716. Тут всё из кубов. Даже солнце. Особенно солнце.", "D-716. Everything here is made of cubes. Even the sun. Especially the sun.", { glitch = 0.2 })
	say(c, "Morty", "А почему коровы квадратные?", "And why are the cows square?")
	say(c, "Rick", "Потому что круглые коровы — это физика, Морти. А здесь — геометрия.", "Because round cows are physics, Morty. This place is geometry.", { glitch = 0.15 })
	Dialogue.hide()
	Director.freeLook(false)
	K.giveControl(c, arrive)
	follow(P.rick, 1, 8)
	follow(P.evil, -1, 8)
	api().objective("obj.cow")
	local cowSpot = spot(sp, "CowTalk")
	waitNear(c, cowSpot.Position, 9, 60)
	api().objective(nil)
	-- the nearest cow turns to Morty
	local cow: Model? = nil
	local best = math.huge
	for _, m in W.d716:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Cow") then
			local d = (m:GetPivot().Position - cowSpot.Position).Magnitude
			if d < best then
				best = d
				cow = m
			end
		end
	end
	local root = api().root()
	if cow and root then
		-- the cow's head is on its -Z side: point -Z at Morty
		local from = cow:GetPivot()
		local to = CFrame.lookAt(from.Position, Vector3.new(root.Position.X, from.Position.Y, root.Position.Z))
		task.spawn(K.animate, 0.6, function(a)
			cow:PivotTo(from:Lerp(to, a))
		end)
	end
	K.play3D("RobotVoice", cowSpot.Position, 0.5)
	say(c, "Cow", "МУ.", "MOO.", { auto = 1 })
	say(c, "Morty", "...Э-э, привет?", "...Uh, hi?")
	say(c, "Cow", "Ищете чёрную штуку с щупальцами? Была тут вчера. Сказала «му» и исчезла. Я обиделась.", "Looking for a black thing with tentacles? It was here yesterday. Said moo and vanished. I was offended.")
	say(c, "Morty", "К-корова разговаривает?!", "Th-the cow is talking?!")
	say(c, "Rick", "Это даже не входит в топ-пять странностей за сегодня, Морти.", "That's not even in today's top five weirdest things, Morty.", { glitch = 0.25 })
	radarCheck(c, { "radar.search", "radar.signal", "radar.weak", "radar.where", "radar.glitch" }, 0.88, 0.3, true)
	say(c, "Rick", "Сигнал слабый... и прыгает. Будто оно ходит вокруг нас.", "The signal's weak... and it keeps jumping. Like it's walking around us.", { glitch = 0.35 })
	radarDone()
	P.evil.glitch = 0.25
	P.evil:lookAt(eyeOf(api().root() and api().root().CFrame or arrive).Position)
	say(c, "Morty", "Эй... ты мерцаешь. Как Рик.", "Hey... you're flickering. Like Rick.")
	say(c, "EvilMorty", "Тебе кажется. Идём.", "You're imagining it. Let's go.")
	Dialogue.hide()
	P.evil.glitch = 0.15
	leaveThrough(c, spot(sp, "PortalOut"))
end

local function worldK9(c)
	local sp = W.k9:FindFirstChild("K9Spots")
	local spores = W.k9:FindFirstChild("SporeSource")
	local sporeEmitter = spores and spores:FindFirstChildOfClass("ParticleEmitter")
	if sporeEmitter then
		sporeEmitter.Enabled = true
	end
	local arrive = arriveIn(c, sp, "Mushroom", "loc.k9", true)
	Audio.music("MusicEerie", 2)
	c.wait(1.2)
	say(c, "Rick", "K-9. Грибной лес. Не дыши глубоко, Морти. Споры.", "K-9. The mushroom forest. Don't breathe too deep, Morty. Spores.", { glitch = 0.25 })
	say(c, "Morty", "Красиво... и жутко.", "It's pretty... and creepy.")
	Dialogue.hide()
	Director.freeLook(false)
	K.giveControl(c, arrive)
	follow(P.rick, 1, 8)
	follow(P.evil, -1, 8)
	api().objective("obj.clearing")
	local clearing = spot(sp, "Clearing")
	-- halfway down the path the spores kick in
	c.waitUntil(function()
		local r = api().root()
		return r ~= nil and (r.Position.Z < (arrive.Position.Z + clearing.Position.Z) / 2 + 6)
	end, 40)
	local eyes = W.k9:FindFirstChild("SporeEyes")
	Fx.glitch(1.4, 0.35)
	Audio.play("Glitch2", 0.6)
	if eyes then
		for _, p in eyes:GetChildren() do
			if p:IsA("BasePart") then
				p.Transparency = 0
			end
		end
	end
	K.play3D("RoarDeep", arrive.Position + Vector3.new(0, 10, -40), 0.7)
	say(c, "Morty", "Т-там глаза! Красные глаза в грибах!", "Th-there are eyes! Red eyes in the mushrooms!", { auto = 1.2 })
	c.wait(0.4)
	if eyes then
		for _, p in eyes:GetChildren() do
			if p:IsA("BasePart") then
				p.Transparency = 1
			end
		end
	end
	say(c, "Rick", "Это споры, Морти. Галлюцинации. Наверное.", "That's the spores, Morty. Hallucinations. Probably.", { auto = 1.4, glitch = 0.3 })
	say(c, "EvilMorty", "Это не галлюцинации.", "Those aren't hallucinations.", { auto = 1.4 })
	Dialogue.hide()
	waitNear(c, clearing.Position, 10, 50)
	api().objective(nil)
	api().gameplay(false)
	api().freeze(true)
	api().hideCharacter(true)
	stopFollow(P.rick)
	stopFollow(P.evil)
	local r = api().root()
	local eyeCF = if r then CFrame.lookAt(r.Position + Vector3.new(0, 1.5, 0), P.rick.root.Position + Vector3.new(0, 1.4, 0)) else eyeOf(clearing)
	Director.start()
	Director.cut(eyeCF, 70)
	radarCheck(c, { "radar.search", "radar.signal", "radar.strong", "radar.where", "radar.b137" }, 0.5, 0.5, true)
	Audio.play("OverheatBeep", 1.4)
	say(c, "Rick", "Есть сигнал! Сильный! Это... B137?! Мы же только оттуда!", "A signal! A strong one! It's... B137?! We just came from there!", { glitch = 0.45 })
	say(c, "EvilMorty", "Значит, оно всё время было рядом с вами.", "Then it's been right next to you the whole time.")
	say(c, "Rick", "Открываю портал. Держитесь ближе. И... не смотрите на меня так.", "Opening a portal. Stay close. And... stop looking at me like that.", { glitch = 0.6 })
	radarDone()
	Dialogue.hide()
	local out = openPortal(CFrame.lookAt(clearing.Position + Vector3.new(0, 3, -10), clearing.Position + Vector3.new(0, 3, 0)), "green", 9)
	Audio.play("Click")
	c.wait(1.4)
	Fx.fade(1, 0.5, true)
	out.Close()
	if sporeEmitter then
		sporeEmitter.Enabled = false
	end
end

-- B137 at sunset: the signal is Rick
local function hunt137(c)
	K.ensureDesert(c)
	local sp = R.planet:FindFirstChild("ChaseSpots")
	shedVisible(true)
	shedDoor(0)
	local arrive = arriveIn(c, sp, "DesertDusk", "loc.b137", true)
	local rick, evil = P.rick, P.evil
	rick.glitch = 0.4
	Audio.music("MusicDread", 3)
	c.wait(1.2)
	local shedPos = W.shed:GetPivot().Position
	Director.freeLook(false)
	Director.move(CFrame.lookAt(eyeOf(arrive).Position, shedPos + Vector3.new(0, 4, 0)), 1.2, "smooth", 55)
	say(c, "Morty", "Это... наш бункер? Ты его достроил?", "Is that... our bunker? You finished it?")
	say(c, "Rick", "Пока ты спал. Пять дней, Морти. Ну, или пять минут. Время — сложная штука.", "While you were asleep. Five days, Morty. Or five minutes. Time's complicated.", { glitch = 0.45 })
	Director.move(eyeOf(arrive), 0.8, "smooth", 70)
	radarCheck(c, { "radar.search", "radar.dist", "radar.zero", "radar.where", "radar.here" }, 0.5, 0.5, true)
	Audio.play("OverheatBeep", 1.6)
	say(c, "Rick", "Ноль метров? Значит, оно прямо... здесь.", "Zero meters? So it's right... here.", { glitch = 0.5 })
	say(c, "Morty", "Рик... точка на радаре — это ты.", "Rick... the dot on the radar is you.")
	rick:lookAt(eyeOf(arrive).Position)
	say(c, "Rick", "Я? Хе... хе-хе... Не-е-ет, Морти, это бред, я же... я же Р-Р-Р-РИК...", "Me? Heh... heh-heh... No-o-o, Morty, that's crazy, I'm... I'm R-R-R-RICK...", { glitch = 1 })
	say(c, "EvilMorty", "Морти. Отойди от него. Медленно.", "Morty. Step away from him. Slowly.")
	radarDone()
	Dialogue.hide()

	-- RICK TURNS ------------------------------------------------------------------
	rick.glitch = 1.4
	Fx.glitch(2.2, 0.7)
	Audio.play("Glitch3")
	K.play3D("RoarDeep", rick.root.Position, 1.2)
	Director.shake(1.2, 2.2, 14)
	local rickPos = rick.root.Position
	local groundY = groundAt(rickPos)
	for i = 1, 4 do
		K.bigBlackSmoke(rickPos + Vector3.new(0, i * 2, 0), 1 + i * 0.4)
		c.wait(0.3)
	end
	rick:visible(false)
	rick.glitch = 0
	local rb = P.rickBeast
	local beastHome = CFrame.lookAt(Vector3.new(rickPos.X, groundY, rickPos.Z), Vector3.new(arrive.Position.X, groundY, arrive.Position.Z))
	rb.root.CFrame = beastHome * CFrame.new(0, -30, 0)
	beastWiggle(rb, 1.4)
	K.emitters(rb.model, "BlackCloud", true)
	Director.track(function()
		return CFrame.lookAt(eyeOf(arrive).Position, rb.root.Position + Vector3.new(0, 18, 0))
	end)
	Director.fov(68, 0.8)
	K.animate(1.1, function(a)
		rb.root.CFrame = (beastHome * CFrame.new(0, -30, 0)):Lerp(beastHome, a)
	end, "out")
	K.play3D("Roar", rickPos + Vector3.new(0, 20, 0), 0.8)
	Director.shake(1.6, 1.2)
	say(c, "Morty", "Р-Р-РИК?!", "R-R-RICK?!", { auto = 0.8 })
	say(c, "EvilMorty", "Я так и знал...", "I knew it...", { auto = 0.8 })
	Dialogue.hide()
	-- it grabs Evil Morty (we only hear it)
	local evilPos = evil.root.Position
	Director.track(function()
		local head = evil.model:FindFirstChild("Head") :: BasePart?
		return CFrame.lookAt(eyeOf(arrive).Position, if head then head.Position else evilPos)
	end)
	rb.wiggle = 3
	c.wait(0.6)
	Fx.black(1)
	Audio.play("Thud", 0.7)
	Audio.play("Glitch1", 0.5)
	c.wait(0.9)
	evil:visible(false)
	evil.glitch = 0
	local eb = P.evilBeast
	local evilHome = CFrame.lookAt(Vector3.new(evilPos.X, groundAt(evilPos), evilPos.Z), Vector3.new(arrive.Position.X, 0, arrive.Position.Z))
	eb.root.CFrame = evilHome * CFrame.new(0, -6, 0)
	beastWiggle(eb, 1.6)
	K.emitters(eb.model, "BlackCloud", true)
	Fx.fade(0, 0.3)
	K.animate(0.8, function(a)
		eb.root.CFrame = (evilHome * CFrame.new(0, -6, 0)):Lerp(evilHome, a)
	end, "out")
	K.play3D("Roar", evilPos + Vector3.new(0, 14, 0), 1.1)
	Director.shake(1.0, 0.8)
	say(c, "MortyThought", "Он... он и его тоже...", "He... he got him too...", { auto = 1.2 })
	-- the curse itself rises behind them
	local ent = P.entity
	local entCF = CFrame.lookAt(Vector3.new(rickPos.X, 0, rickPos.Z + 110), Vector3.new(arrive.Position.X, 0, arrive.Position.Z))
	ent.root.CFrame = entCF * CFrame.new(0, -170, 0)
	K.entityCloud(true)
	ent:pose(K.ENTITY_POSES.raise, 3)
	Director.track(function()
		return CFrame.lookAt(eyeOf(arrive).Position, ent.root.Position + Vector3.new(0, 90, 0))
	end)
	K.play3D("RoarDeep", entCF.Position + Vector3.new(0, 80, 0), 0.6)
	K.animate(2.4, function(a)
		ent.root.CFrame = (entCF * CFrame.new(0, -170, 0)):Lerp(entCF, a)
	end, "out")
	Director.shake(1.6, 2, 8)
	say(c, "MortyThought", "Проклятие, Рик и Злой Морти... они теперь одно целое...", "The curse, Rick and Evil Morty... they're one thing now...", { auto = 1.2 })
	say(c, "Morty", "А-А-А-А-А! БЕЖАТЬ! БЕЖАТЬ!", "A-A-A-A-AH! RUN! RUN!", { auto = 0.6 })
	Dialogue.hide()

	-- THE CHASE -----------------------------------------------------------------
	Audio.music("MusicAction", 0.5)
	Director.fov(70, 0.3)
	local hum = api().humanoid()
	K.giveControl(c, arrive, CFrame.lookAt(eyeOf(arrive).Position, shedPos + Vector3.new(0, 3, 0)))
	if hum then
		hum.WalkSpeed = 16
	end
	api().objective("obj.run")
	local t0 = os.clock()
	local gap = 26
	local lunge = false
	local held = false -- the Titan is holding them back
	local holdPos: Vector3? = nil
	local entityGap = 95
	local chaseConn = connect(RunService.Heartbeat, function(dt)
		local root = api().root()
		if not root then
			return
		end
		local target = if lunge then 4 else math.max(10, 26 - (os.clock() - t0) * 1.1)
		gap += (target - gap) * math.min(1, dt * (if lunge then 6 else 1.5))
		local pp = flat(root.Position)
		for i, b in { rb, eb } do
			local cur = b.root.Position
			local side = (if i == 1 then 1 else -1) * 5
			local want: Vector3
			if held and holdPos then
				want = holdPos + Vector3.new(side * 2, 0, 6 + math.sin(os.clock() * 2 + i) * 3)
			else
				local away = flat(cur) - pp
				if away.Magnitude < 0.1 then
					away = Vector3.new(0, 0, 1)
				end
				local right = away.Unit:Cross(Vector3.yAxis)
				want = pp + away.Unit * gap + right * side
			end
			local next = flat(cur):Lerp(want, math.min(1, dt * 3.2))
			local y = groundAt(next)
			b.root.CFrame = CFrame.lookAt(Vector3.new(next.X, y, next.Z), Vector3.new(pp.X, y, pp.Z))
		end
		-- the giant follows far behind
		local ec = flat(ent.root.Position)
		local away = ec - pp
		if away.Magnitude > 1 then
			local want = pp + away.Unit * (if held then entityGap + 60 else entityGap)
			local next = ec:Lerp(want, math.min(1, dt * 0.8))
			ent.root.CFrame = CFrame.lookAt(next, pp)
		end
	end)
	-- growls behind your back
	task.spawn(function()
		while c.alive() and not held do
			task.wait(2 + math.random() * 1.5)
			if held or not c.alive() then
				break
			end
			K.play3D(if math.random() < 0.5 then "Roar" else "RoarDeep", rb.root.Position + Vector3.new(0, 12, 0), 0.9 + math.random() * 0.4)
			if gap < 16 then
				Fx.glitch(0.2, 0.25)
			end
		end
	end)
	-- run until they almost catch you
	c.waitUntil(function()
		local root = api().root()
		return (os.clock() - t0 > 13) or (root ~= nil and root.Position.Z < shedPos.Z + 125)
	end, 30)
	lunge = true
	rb.wiggle = 3
	eb.wiggle = 3
	Fx.glitch(0.4, 0.3)
	K.play3D("Roar", api().root() and api().root().Position or arrive.Position, 1)
	c.wait(0.7)
	-- freeze! the Titan arrives
	api().gameplay(false)
	api().freeze(true)
	api().hideCharacter(true)
	local root = api().root()
	local mpos = if root then root.Position else arrive.Position
	local eyePos = mpos + Vector3.new(0, 1.5, 0)
	local back = flat(rb.root.Position - mpos).Unit
	Director.start()
	Director.move(CFrame.lookAt(eyePos, eyePos + back * 20 + Vector3.new(0, 6, 0)), 0.35, "out", 75)
	Audio.music(nil, 0.3)
	local theme = Audio.make("TitanTheme", SoundService)
	if theme then
		theme:Play()
		table.insert(S.loops, theme)
	end
	local landAt = mpos + back * 14
	landAt = Vector3.new(landAt.X, groundAt(landAt), landAt.Z)
	holdPos = flat(mpos + back * 34)
	local landCF = CFrame.lookAt(landAt, landAt + back)
	titanWounded(false)
	Director.track(function()
		return CFrame.lookAt(eyePos, P.titan.root.Position + Vector3.new(0, 8, 0))
	end)
	titanLand(c, mpos - back * 160 + Vector3.new(0, 260, 0), landCF, 2.6)
	-- the shockwave throws them back
	held = true
	lunge = false
	Fx.shockwave(landAt + Vector3.new(0, 3, 0), 60, 0.6, rgb(255, 120, 80))
	Director.track(function()
		return CFrame.lookAt(eyePos, P.titan.root.Position + Vector3.new(0, 30, 0))
	end)
	c.wait(0.6)
	K.play3D("RobotVoice", P.titan.root.Position + Vector3.new(0, 30, 0), 0.7)
	say(c, "Titan", "ВАМ. НЕ МЕСТО. ЗДЕСЬ.", "YOU. DON'T. BELONG. HERE.", { auto = 1.6 })
	Dialogue.hide()
	P.titan:pose(TP.aimBoth, 6)
	K.play3D("ChargeLong", P.titan.root.Position + Vector3.new(0, 30, 0), 1)
	task.spawn(K.animate, 3, function(a)
		cannonCharge(a)
	end, "in")
	c.wait(0.8)
	say(c, "MortyThought", "Бункер! Бегом!", "The bunker! Go!", { auto = 0.6 })
	Dialogue.hide()
	-- run to the shed
	local doorSpot = W.shed:FindFirstChild("DoorSpot") :: BasePart
	K.giveControl(c, CFrame.lookAt(mpos, Vector3.new(shedPos.X, mpos.Y, shedPos.Z)))
	if hum then
		hum.WalkSpeed = 16
	end
	api().objective("obj.run")
	rb.wiggle = 2.5
	eb.wiggle = 2.5
	waitNear(c, doorSpot.Position, 16, 10)
	api().objective(nil)

	-- FIRE --------------------------------------------------------------------
	local blastAt = Vector3.new(holdPos.X, 6, holdPos.Z)
	local beams = {}
	for _, name in { "Muzzle", "MuzzleL" } do
		local m = muzzle(name)
		if m then
			table.insert(beams, { muzzle = m, beam = Fx.beam(m.Position, blastAt, 6, rgb(255, 70, 40)) })
		end
	end
	local core = K.titanPart("Core")
	local coreBeam = if core then Fx.beam(core.Position, blastAt, 9, rgb(255, 90, 50)) else nil
	K.play3D("Laser", P.titan.root.Position + Vector3.new(0, 30, 0))
	local firing = true
	task.spawn(function()
		while firing do
			for _, b in beams do
				b.beam.Set(b.muzzle.Position, blastAt)
			end
			if coreBeam and core then
				coreBeam.Set(core.Position, blastAt)
			end
			RunService.RenderStepped:Wait()
		end
		for _, b in beams do
			b.beam.Destroy()
		end
		if coreBeam then
			coreBeam.Destroy()
		end
	end)
	c.wait(0.9)
	Fx.explosion(blastAt, 10, { sound = "ExplosionBig", smokeColor = rgb(10, 8, 12), waveColor = rgb(255, 150, 110), debris = 30 })
	Fx.shockwave(blastAt, 320, 1.4, rgb(255, 200, 170))
	K.bigBlackSmoke(blastAt, 4)
	firing = false
	cannonCharge(0)
	-- the blast throws Morty
	api().gameplay(false)
	api().freeze(true)
	api().hideCharacter(true)
	local r2 = api().root()
	local m2 = if r2 then r2.Position else doorSpot.Position
	local fwd = flat(shedPos - m2)
	fwd = if fwd.Magnitude > 0.1 then fwd.Unit else Vector3.new(0, 0, -1)
	Fx.flash(Color3.new(1, 1, 1), 1, 0.03, 1.4)
	Fx.glitch(3, 1)
	Fx.muffle(true)
	Audio.play("Tinnitus")
	Audio.play("BodyWhoosh")
	Director.start()
	local fly = CFrame.lookAt(m2 + fwd * 8 + Vector3.new(0, 5, 0), m2 + fwd * 30) * CFrame.Angles(0.8, 0, 1.4)
	Director.move(fly, 0.5, "out")
	local lieAt = Vector3.new(m2.X, groundAt(m2) + 0.9, m2.Z) + fwd * 12
	Director.move(CFrame.lookAt(lieAt, lieAt + Vector3.new(0, 30, 0) + fwd * 4) * CFrame.Angles(0, 0, math.rad(15)), 0.3, "in")
	Audio.play("Thud")
	Fx.dust(lieAt, 6, 30)
	Director.shake(1.4, 0.6)
	if hum then
		hum.WalkSpeed = 9
	end
	-- park everything for the next chapter
	chaseConn:Disconnect()
	hideBeasts()
	S.mortyLie = lieAt
	c.wait(2.2)
	Fx.fade(1, 1.6, true)
	if theme then
		Audio.fadeOut(theme, 2, true)
	end
end

local function ch9(c, fresh: boolean)
	api().state("story")
	api().gameplay(false)
	if fresh then
		Fx.black(1)
		evilFace(true)
	end
	P.rick.glitch = 0.3
	P.evil.glitch = 0.15
	Fx.title("ch.9")
	c.check()
	worldJ22(c)
	worldD716(c)
	worldK9(c)
	hunt137(c)
	Fx.stopGlitch()
end

----------------------------------------------------------------------------
-- CHAPTER 10: The Alliance
----------------------------------------------------------------------------
local function ch10(c, _fresh: boolean)
	api().state("story")
	api().gameplay(false)
	Fx.black(1)
	K.ensureDesert(c)
	Scenes.apply("DesertDusk", true)
	hideBeasts()
	P.rick:visible(false)
	P.evil:visible(false)
	shedVisible(true)
	shedDoor(0)
	clearCrowd()
	local doorSpot = (W.shed:FindFirstChild("DoorSpot") :: BasePart).CFrame
	local facing = -flat(doorSpot.LookVector).Unit -- away from the shed
	local M = doorSpot.Position + facing * 8
	M = Vector3.new(M.X, groundAt(M) + 3, M.Z)
	local lieAt = Vector3.new(M.X, M.Y - 2.1, M.Z)
	K.holdCharacterAt(c, CFrame.lookAt(M, M + facing))
	api().hideCharacter(true)
	-- the army and the wounded Titan holding the curse's head
	local armyCenter = M + facing * 34
	formation(Vector3.new(armyCenter.X, 0, armyCenter.Z), M, 3, 8, 5)
	local tPos = M + facing * 78
	tPos = Vector3.new(tPos.X, groundAt(tPos), tPos.Z)
	local titan = P.titan
	titanWounded(true)
	titan:pose(TP.holdHead, 10)
	titan:snap()
	titanTo(CFrame.lookAt(tPos, Vector3.new(M.X, tPos.Y, M.Z)))
	titan:lookAt(M)
	holdCurseHead(true)
	local commanderCF = CFrame.lookAt(Vector3.new(armyCenter.X, 0, armyCenter.Z) - facing * 10 + Vector3.new(0, groundAt(armyCenter) + 3.45, 0), M)
	S.commander = spawnAgent("TVMan", commanderCF, "Commander")
	-- wake up on the sand
	Director.start()
	Director.cut(CFrame.lookAt(lieAt, lieAt + Vector3.new(0, 30, 0) - facing * 4) * CFrame.Angles(0, 0, math.rad(15)), 70)
	local blur = Lighting:FindFirstChild("Blur") :: BlurEffect?
	if blur then
		blur.Size = 14
		blur.Enabled = true
	end
	Fx.muffle(true)
	for _ = 1, 3 do
		Fx.smoke(M + facing * 20 + Vector3.new(0, 4, 0), 8, 10, rgb(30, 28, 30), 6)
	end
	Fx.fade(0, 2)
	Fx.title("ch.10")
	c.check()
	say(c, "Morty", "Ох... я... живой?..", "Ugh... am I... alive?..", { auto = 1.2 })
	Dialogue.hide()
	if blur then
		task.spawn(K.animate, 2, function(a)
			blur.Size = 14 * (1 - a)
		end)
	end
	Fx.muffle(false)
	Audio.play("Cloth")
	Audio.play("GetUp")
	local eye = CFrame.lookAt(M + Vector3.new(0, 1.5, 0), tPos + Vector3.new(0, 30, 0))
	Director.move(CFrame.lookAt(M + Vector3.new(0, 0.2, 0), M + Vector3.new(0, 0.2, 0) + facing * 10), 1.0)
	Director.move(eye, 1.4, "smooth", 62)
	if blur then
		blur.Enabled = false
	end
	Audio.music("MusicEerie", 3)
	say(c, "MortyThought", "Камерамены... Спикермены... ТВ-мены... Целая армия.", "Cameramen... Speakermen... TV Men... A whole army.")
	say(c, "MortyThought", "И у Титана в руке... голова проклятия.", "And in the Titan's hand... the curse's head.")
	Dialogue.hide()

	-- THE CHOICE ---------------------------------------------------------------
	local pitCF = CFrame.new(W.shed:GetPivot().Position)
	while true do
		c.check()
		Director.freeLook(false)
		Director.cut(eye, 62)
		local pick = Dialogue.choice({ "choice.bunker", "choice.look" })
		c.check()
		if pick == 1 then
			-- into the bunker...
			Director.move(CFrame.lookAt(eye.Position, doorSpot.Position + Vector3.new(0, 1.5, 0) - facing * 6), 0.8)
			local inside = doorSpot.Position + Vector3.new(0, 1.5, 0)
			Director.move(CFrame.lookAt(inside, inside - facing * 10), 1.8, "smooth")
			Audio.play("Click", 0.7)
			K.animate(0.6, function(a)
				shedDoor(a)
			end, "out")
			c.wait(0.8)
			-- tentacles burst out of the hatch
			local pit = P.pit
			local tilt = CFrame.lookAt(pitCF.Position, pitCF.Position + Vector3.new(facing.X, 0, facing.Z)) * CFrame.Angles(math.rad(-55), 0, 0)
			pit.root.CFrame = tilt * CFrame.new(0, -14, 0)
			pitWiggle(2, 1)
			K.emitters(pit.model, "BlackCloud", true)
			K.play3D("Roar", pitCF.Position, 1.3)
			K.animate(0.35, function(a)
				pit.root.CFrame = (tilt * CFrame.new(0, -14, 0)):Lerp(tilt, a)
			end, "out")
			Fx.flash(rgb(120, 0, 0), 0.6, 0.02, 0.4)
			Director.move(CFrame.lookAt(pitCF.Position + Vector3.new(0, 1, 0), pitCF.Position - Vector3.new(0, 10, 0)) * CFrame.Angles(0, 0, 1.2), 0.35, "in")
			Audio.play("Thud")
			Fx.glitch(0.6, 1)
			Fx.black(1)
			Fx.death(true)
			Audio.music(nil, 0.3)
			c.wait(3.6)
			-- back to the moment of choice
			pit.root.CFrame = start.pit
			K.emitters(pit.model, "BlackCloud", false)
			pit.extra = nil
			shedDoor(0)
			Fx.death(false)
			Fx.stopGlitch()
			c.wait(0.6)
			Fx.fade(0, 0.8)
			Audio.music("MusicEerie", 2)
		else
			break
		end
	end

	-- LOOK AROUND: the Titan blasts the fake bunker ----------------------------
	Director.freeLook(true, { yaw = 2.6, pitchUp = 0.9, pitchDown = 0.5 })
	say(c, "MortyThought", "Где Рик?.. Где Злой Морти?..", "Where's Rick?.. Where's Evil Morty?..", { auto = 2.2 })
	Dialogue.hide()
	Director.freeLook(false)
	local shedPos = W.shed:GetPivot().Position + Vector3.new(0, 3.5, 0)
	titan:face(Vector3.new(shedPos.X, tPos.Y, shedPos.Z))
	titan:pose(TP.aimRight, 6)
	titan:lookAt(shedPos)
	Director.move(CFrame.lookAt(eye.Position + facing:Cross(Vector3.yAxis) * 6, (titan.root.Position + shedPos) / 2 + Vector3.new(0, 14, 0)), 1.2, "smooth", 66)
	K.play3D("Charge", titan.root.Position + Vector3.new(0, 30, 0))
	task.spawn(K.animate, 1.6, function(a)
		cannonCharge(a)
	end, "in")
	say(c, "Morty", "Эй! Что ты делаешь?! Это же наш бункер!", "Hey! What are you doing?! That's our bunker!", { auto = 0.8 })
	Dialogue.hide()
	local m = muzzle("Muzzle")
	if m then
		local beam = Fx.beam(m.Position, shedPos, 5, rgb(255, 70, 40))
		K.play3D("Laser", m.Position)
		K.animate(0.6, function()
			beam.Set(m.Position, shedPos)
		end, "linear")
		beam.Destroy()
	end
	cannonCharge(0)
	local wood = { rgb(120, 86, 56), rgb(110, 78, 50), rgb(132, 94, 60), rgb(90, 64, 40) }
	Fx.explosion(shedPos, 4, { sound = "ExplosionBig", smokeColor = rgb(40, 34, 30), waveColor = rgb(255, 160, 110), debris = 46, debrisColors = wood })
	shedVisible(false)
	Director.shake(1.6, 1)
	-- what was hiding inside
	local pit = P.pit
	pit.root.CFrame = pitCF * CFrame.new(0, -14, 0)
	pitWiggle(2.4, 0)
	K.emitters(pit.model, "BlackCloud", true)
	K.animate(0.5, function(a)
		pit.root.CFrame = (pitCF * CFrame.new(0, -14, 0)):Lerp(pitCF * CFrame.new(0, -1, 0), a)
	end, "out")
	K.play3D("Roar", pitCF.Position, 1.4)
	Director.move(CFrame.lookAt(eye.Position, pitCF.Position + Vector3.new(0, 5, 0)), 0.5, "smooth", 55)
	say(c, "Morty", "Т-там были... ЩУПАЛЬЦА?! В нашем бункере?!", "Th-there were... TENTACLES?! In our bunker?!", { auto = 1 })
	Dialogue.hide()
	-- second shot into the hole
	if m then
		local beam = Fx.beam(m.Position, pitCF.Position, 4, rgb(255, 70, 40))
		K.animate(0.5, function()
			beam.Set(m.Position, pitCF.Position)
		end, "linear")
		beam.Destroy()
	end
	Fx.explosion(pitCF.Position + Vector3.new(0, 2, 0), 3, { sound = "Explosion", smokeColor = rgb(10, 8, 12), waveColor = rgb(255, 120, 80) })
	Fx.sparks(pitCF.Position + Vector3.new(0, 3, 0), 60, rgb(255, 80, 50))
	K.animate(0.8, function(a)
		pit.root.CFrame = (pitCF * CFrame.new(0, -1, 0)):Lerp(pitCF * CFrame.new(0, -16, 0), a)
	end, "in")
	pit.root.CFrame = start.pit
	pit.extra = nil
	K.emitters(pit.model, "BlackCloud", false)
	titan:pose(TP.holdHead, 4)
	titan:face(Vector3.new(M.X, tPos.Y, M.Z))
	titan:lookAt(M)

	-- the Commander explains
	local cmd = S.commander
	if cmd then
		local to = M + facing * 6
		task.spawn(function()
			cmd:walkTo(Vector3.new(to.X, cmd.root.Position.Y, to.Z), 7, M)
		end)
		Director.track(function()
			local head = cmd.model:FindFirstChild("Head") :: BasePart?
			return CFrame.lookAt(eye.Position, if head then head.Position else cmd.root.Position)
		end)
		Director.fov(55, 2)
	end
	Audio.music("MusicBunker", 3)
	c.wait(1.6)
	say(c, "Commander", "Спокойно, малыш. Мы — Альянс. Камерамены, Спикермены, ТВ-мены.", "Easy, kid. We're the Alliance. Cameramen, Speakermen, TV Men.")
	say(c, "Commander", "То, что гналось за тобой, — не проклятие. Это вирус. Он прячется от нас уже двадцать лет.", "The thing chasing you isn't a curse. It's a virus. It's been hiding from us for twenty years.")
	say(c, "Commander", "Он вселяется в самых умных существ во вселенной. Носит их лица. Говорит их голосами.", "It gets inside the smartest beings in the universe. Wears their faces. Talks with their voices.")
	say(c, "Morty", "Т-то есть... Рик... это был не Рик?!", "S-so... Rick... wasn't Rick?!")
	say(c, "Commander", "Твой Рик был заражён. С того самого момента, как его коснулась та рука.", "Your Rick was infected. Ever since that hand touched him.")
	say(c, "MortyThought", "Рука... Там, в пустыне, когда тарелка упала. «Это была ЕГО рука»...", "The hand... Back in the desert, when the saucer went down. \"That was ITS hand\"...")
	say(c, "Commander", "Даже бункер он строил для тебя. Ловушку.", "He even built that bunker for you. A trap.")
	say(c, "Morty", "А настоящий Рик?.. И Злой Морти?..", "And the real Rick?.. And Evil Morty?..")
	say(c, "Commander", "Вирус копирует, а не заменяет. Настоящий Рик где-то там. Найдётся. Они всегда находятся.", "The virus copies, it doesn't replace. The real Rick is out there somewhere. He'll turn up. They always do.")
	K.play3D("RobotVoice", titan.root.Position + Vector3.new(0, 30, 0), 0.6)
	say(c, "Titan", "ГОЛОВУ — НА БАЗУ.", "THE HEAD GOES TO THE BASE.")
	say(c, "Commander", "Слышал? Летим на базу. Ты с нами, Морти. Здесь тебе больше нельзя оставаться.", "You heard him. We're flying to the base. You're coming with us, Morty. You can't stay here.")
	Dialogue.hide()

	-- THE FLIGHT ------------------------------------------------------------------
	Fx.fade(1, 0.6, true)
	Director.fov(70, 0)
	titan:pose(TP.carry, 8)
	titan:lookAt(nil)
	local torso = R.titanModel:FindFirstChild("Torso") :: BasePart?
	local function shoulderEye(): CFrame
		if not torso then
			return eye
		end
		local cf = torso.CFrame * CFrame.new(9, 12, -2)
		local look = R.titanModel.PrimaryPart.CFrame.LookVector
		return CFrame.lookAt(cf.Position, cf.Position + look * 40 - Vector3.new(0, 6, 0))
	end
	Director.track(shoulderEye)
	Fx.fade(0, 0.6)
	say(c, "MortyThought", "Я сижу на плече у Титана Спикермена. Мама мне не поверит.", "I'm sitting on Titan Speakerman's shoulder. Mom's never gonna believe this.", { auto = 1.6 })
	Dialogue.hide()
	K.titanJets(true)
	local thruster = loop("Thruster", titan.root, 0.8)
	local up0 = titan.root.CFrame
	local skyPortal = up0.Position + up0.LookVector * 260 + Vector3.new(0, 230, 0)
	local portal = openPortal(CFrame.lookAt(skyPortal, skyPortal - up0.LookVector), "red", 120)
	K.play3D("Takeoff", tPos, 0.8)
	Director.shake(0.6, 2)
	K.animate(5.2, function(a)
		local pos = K.bezier(up0.Position, up0.Position + Vector3.new(0, 140, 0), skyPortal + up0.LookVector * 40, a)
		titan.root.CFrame = CFrame.lookAt(pos, pos + up0.LookVector + Vector3.new(0, 0.25 * (1 - a), 0))
	end, "in")
	Audio.play("Warp")
	Fx.flash(rgb(255, 120, 90), 1, 0.05, 0.8)
	Fx.speedLines(true, 1)
	c.wait(0.4)
	Fx.fade(1, 0.3, true)
	Fx.speedLines(false)
	portal.Close()
	K.titanJets(false)
	K.stopLoop(thruster, 0.5)
	holdCurseHead(false)
	clearCrowd()
end

----------------------------------------------------------------------------
-- CHAPTER 11: The camera base
----------------------------------------------------------------------------
local function cityFx(on: boolean)
	K.emitters(W.base, "CitySmoke", on)
end

local function placeShips(visible: boolean)
	for i = 1, 10 do
		local ship = W.astro:FindFirstChild("AstroShip" .. i)
		if ship then
			ship:PivotTo(if visible then spot(W.baseSpots, "Ship" .. i) else start.ships[i])
		end
	end
end

local function ch11(c, fresh: boolean)
	api().state("story")
	api().gameplay(false)
	Fx.black(1)
	Scenes.apply("City", true)
	cityFx(true)
	clearCrowd()
	placeShips(false)
	W.mother:PivotTo(start.mother)
	local sp = W.baseSpots
	local land = spot(sp, "TitanLand")
	local mortyLand = spot(sp, "MortyLand")
	-- the curse's head goes into the containment cube
	local cube = W.base:FindFirstChild("Containment", true) :: BasePart?
	if cube then
		W.curseHead:PivotTo(CFrame.lookAt(cube.Position, cube.Position + Vector3.new(0, 0, 1)))
	end
	-- agents around the pad
	for _, mk in W.formation:GetChildren() do
		if mk:IsA("BasePart") then
			local kind = AGENT_KINDS[(tonumber(string.sub(mk.Name, 2)) or 1) % 3 + 1]
			spawnAgent(kind, mk.CFrame)
		end
	end
	S.cam = spawnAgent("Cameraman", spot(sp, "CamFriend"), "Cam")
	S.lens = spawnAgent("Cameraman", spot(sp, "LensFriend"), "Lens")
	S.commander = spawnAgent("TVMan", spot(sp, "Commander"), "Commander")
	-- Lens has a blue lens and a little antenna, so the friends don't look the same
	if S.lens then
		local lens = S.lens.model:FindFirstChild("CamLens", true) :: BasePart?
		if lens then
			lens.Color = rgb(60, 140, 220)
		end
	end
	local titan = P.titan
	titanWounded(true)
	holdCurseHead(false)
	K.holdCharacterAt(c, mortyLand)
	api().hideCharacter(true)
	local torso = R.titanModel:FindFirstChild("Torso") :: BasePart?
	Director.start()
	if not fresh and torso then
		-- landing on the pad, seen from the Titan's shoulder
		local from = land.Position + Vector3.new(-200, 260, 160)
		Director.track(function()
			local cf = torso.CFrame * CFrame.new(9, 12, -2)
			return CFrame.lookAt(cf.Position, land.Position + Vector3.new(0, 10, 0))
		end)
		Fx.fade(0, 0.6)
		Fx.caption("loc.base")
		titanLand(c, from, land, 3.4)
		c.wait(0.6)
		Fx.fade(1, 0.4, true)
	else
		titan:pose(K.TITAN_POSES.stand, 10)
		titan:snap()
		titanTo(land)
		Fx.caption("loc.base")
	end
	titan:pose(K.TITAN_POSES.stand, 6)
	titanTo(land)
	Director.cut(eyeOf(mortyLand), 70)
	Director.freeLook(true, { yaw = 1.6, pitchUp = 1.0, pitchDown = 0.5 })
	Audio.music("MusicLofi", 3)
	Fx.fade(0, 0.8)
	Fx.title("ch.11")
	c.check()
	local cmd = S.commander
	if cmd then
		cmd:lookAt(eyeOf(mortyLand).Position)
	end
	say(c, "Commander", "Добро пожаловать на базу Альянса. Отдыхай, малыш. Здесь безопасно.", "Welcome to the Alliance base. Get some rest, kid. You're safe here.")
	say(c, "MortyThought", "Почему, когда так говорят в кино, сразу всё взрывается?..", "Why is it that whenever someone says that in a movie, everything blows up?..", { auto = 1.6 })
	local cam, lens = S.cam, S.lens
	if cam and lens then
		cam:lookAt(eyeOf(mortyLand).Position)
		lens:lookAt(eyeOf(mortyLand).Position)
		task.spawn(function()
			cam:walkTo(mortyLand.Position + Vector3.new(-4, 0.45, -3), 6, mortyLand.Position)
		end)
		task.spawn(function()
			lens:walkTo(mortyLand.Position + Vector3.new(-1, 0.45, -5), 6, mortyLand.Position)
		end)
	end
	c.wait(1.6)
	say(c, "Cam", "Эй! Ты же тот самый Морти? Который пережил выстрел Титана?", "Hey! You're that Morty, right? The one who survived the Titan's blast?")
	say(c, "Morty", "Ну... типа того. Меня немножко отбросило.", "Uh... kind of. I got knocked back a little.")
	say(c, "Lens", "НЕМНОЖКО? Тебя было видно с орбиты!", "A LITTLE? We could see you from orbit!")
	say(c, "Cam", "Я Кэм. Это Линза. Пошли, покажем тебе базу. Ты голодный? У нас есть батарейки.", "I'm Cam. This is Lens. Come on, we'll show you the base. Hungry? We've got batteries.")
	say(c, "Morty", "Я... не ем батарейки.", "I... don't eat batteries.")
	say(c, "Lens", "Ничего, привыкнешь.", "Don't worry, you'll get used to it.")
	Dialogue.hide()

	-- WALK AND TALK -----------------------------------------------------------
	Director.freeLook(false)
	K.giveControl(c, mortyLand)
	api().objective("obj.friends")
	local walkPts = {}
	for i = 1, 4 do
		walkPts[i] = spot(sp, "Walk" .. i).Position
	end
	local friendsGo = true
	task.spawn(function()
		for i = 1, 4 do
			if not friendsGo then
				break
			end
			local wp = walkPts[i]
			if cam then
				task.spawn(function()
					cam:walkTo(wp + Vector3.new(-2.5, 0.45, 0), 6)
				end)
			end
			if lens then
				lens:walkTo(wp + Vector3.new(2.5, 0.45, 0), 6)
			end
			c.waitUntil(function()
				return not friendsGo or near(wp, 14)
			end, 30)
		end
	end)
	waitNear(c, walkPts[1], 10, 40)
	say(c, "Cam", "Тут раньше был целый город. Потом пришли туалеты.", "There used to be a whole city here. Then the toilets came.", { auto = 1.8 })
	say(c, "Morty", "Т-туалеты?!", "T-toilets?!", { auto = 1 })
	say(c, "Lens", "Скибиди. Они поют. Это хуже, чем звучит.", "Skibidi. They sing. It's worse than it sounds.", { auto = 2 })
	Dialogue.hide()
	waitNear(c, walkPts[2], 12, 40)
	-- the head in the cube blinks
	for _, e in partsWithAttr(W.curseHead, "CurseEye") do
		e.Color = rgb(255, 255, 255)
		task.delay(0.15, function()
			e.Color = rgb(255, 30, 20)
		end)
	end
	Audio.play("Glitch1", 0.4)
	say(c, "Lens", "Ты видел? Голова в кубе... моргнула.", "Did you see that? The head in the cube... blinked.", { auto = 1.6 })
	say(c, "Cam", "Тебе показалось. Из куба ещё никто не выходил.", "You're seeing things. Nothing's ever gotten out of the cube.", { auto = 1.8 })
	Dialogue.hide()
	waitNear(c, walkPts[3], 12, 40)
	friendsGo = false
	api().objective(nil)

	-- THE ATTACK ------------------------------------------------------------------
	api().gameplay(false)
	api().freeze(true)
	api().hideCharacter(true)
	local r = api().root()
	local mpos = if r then r.Position else walkPts[3]
	local eyePos = mpos + Vector3.new(0, 1.5, 0)
	Director.start()
	Director.freeLook(true, { yaw = 2.6, pitchUp = 1.2, pitchDown = 0.4 })
	Audio.music(nil, 0.2)
	local alarm = loop("OverheatBeep", workspace.CurrentCamera, 0.35, 0.55)
	local alarmLight = W.base:FindFirstChild("BaseAlarmLight", true) :: PointLight?
	connect(RunService.RenderStepped, function()
		if alarmLight then
			alarmLight.Brightness = if math.floor(os.clock() * 3) % 2 == 0 then 4 else 0.5
		end
	end)
	local bobbing = {}
	for i = 1, 10 do
		local ship = W.astro:FindFirstChild("AstroShip" .. i)
		local at = spot(sp, "Ship" .. i)
		if ship then
			ship:PivotTo(at)
			bobbing[ship] = at
			Fx.flash(rgb(230, 200, 255), 0.35, 0.02, 0.3)
			Fx.shockwave(at.Position, 40, 0.5, rgb(200, 140, 255))
			K.play3D("SonicBoom", at.Position, 0.9 + math.random() * 0.3)
			Director.shake(0.5, 0.4)
		end
		if i == 1 then
			Scenes.apply("CityAlarm")
			Director.track(function()
				return CFrame.lookAt(eyePos, at.Position)
			end)
			say(c, "Cam", "АСТРО! Это Астро-туалеты!", "ASTRO! It's the Astro toilets!", { auto = 0.8 })
			Director.freeLook(true)
		elseif i == 3 then
			say(c, "Lens", "Они телепортируются на скорости звука! Все на позиции!", "They teleport at the speed of sound! Everyone to your posts!", { auto = 0.8 })
		end
		c.wait(0.45)
	end
	Dialogue.hide()
	connect(RunService.RenderStepped, function()
		local t = os.clock()
		local k = 0
		for ship, at in bobbing do
			k += 1
			ship:PivotTo(at * CFrame.new(0, math.sin(t * 1.3 + k) * 2, 0) * CFrame.Angles(0, t * 0.6 + k, 0))
		end
	end)
	Audio.music("MusicAction", 1)
	-- everybody turns to the sky, the Titan raises his cannon
	for _, p in S.crowd do
		p:lookAt(spot(sp, "Ship1").Position)
	end
	titan:pose(TP.aimRight, 6)
	titan:lookAt(spot(sp, "Ship1").Position)
	say(c, "Commander", "Нас окружили! Держать периметр!", "We're surrounded! Hold the perimeter!", { auto = 1 })
	Dialogue.hide()
	c.wait(0.8)
	-- the real Rick
	local rick = P.rick
	local rickSpot = spot(sp, "RickPortal")
	local rp = openPortal(spot(sp, "PortalRick"), "green", 9)
	rick:visible(true)
	rick.glitch = 0
	rick.follow = nil
	rick:place(spot(sp, "PortalRick") * CFrame.new(0, -2.64, 0))
	rick:pose("stand")
	rick:snap()
	Director.freeLook(false)
	Director.track(function()
		local head = rick.model:FindFirstChild("Head") :: BasePart?
		return CFrame.lookAt(eyePos, if head then head.Position else rickSpot.Position)
	end)
	rick:walkTo(rickSpot.Position, 6, eyePos)
	rp.Close()
	rick:lookAt(eyePos)
	say(c, "Rick", "Морти! Вот ты где. Я тебя по всей мультивселенной ищу.", "Morty! There you are. I've been looking for you across the whole multiverse.")
	say(c, "Morty", "Р-Рик?! Ты... ты не глючишь!", "R-Rick?! You... you're not glitching!")
	say(c, "Rick", "А должен? *рыг* Слышал, меня тут один вирус косплеил. Безвкусно.", "Should I be? *burp* I heard some virus was cosplaying as me. Tacky.")
	Audio.play("Burp")
	Dialogue.hide()
	-- the mothership
	local mother = W.mother
	local far = spot(sp, "MothershipFar")
	local over = spot(sp, "Mothership")
	mother:PivotTo(far)
	Director.track(function()
		return CFrame.lookAt(eyePos, mother:GetPivot().Position)
	end)
	Director.fov(80, 3)
	K.play3D("RoarDeep", eyePos + Vector3.new(0, 200, 0), 0.35)
	local drone = loop("Drone", workspace.CurrentCamera, 0.6, 0.5)
	K.animate(5, function(a)
		mother:PivotTo(far:Lerp(over, a))
	end, "out")
	Director.shake(0.8, 3, 6)
	say(c, "Lens", "Мамочки... это их МАТЕРИНСКИЙ корабль!", "Oh no... that's their MOTHERSHIP!", { auto = 1 })
	local beamCore = mother:FindFirstChild("BeamCore") :: BasePart?
	K.play3D("ChargeLong", over.Position, 0.5)
	local charging = true
	task.spawn(function()
		local t0 = os.clock()
		while charging and c.alive() do
			local a = math.min(1, (os.clock() - t0) / 14)
			if beamCore then
				beamCore.Size = Vector3.new(30, 90, 90) * (1 + a * 0.6)
				local l = beamCore:FindFirstChildOfClass("PointLight")
				if l then
					l.Brightness = 4 + a * 20
					l.Range = 60
				end
			end
			RunService.RenderStepped:Wait()
		end
	end)
	say(c, "Commander", "Все в бункер! БЫСТРО!", "Everyone into the bunker! NOW!", { auto = 0.8 })
	Director.fov(70, 1)
	Director.track(function()
		local head = rick.model:FindFirstChild("Head") :: BasePart?
		return CFrame.lookAt(eyePos, if head then head.Position else rickSpot.Position)
	end)
	local homeCF = spot(sp, "PortalHome")
	local home = openPortal(homeCF, "green", 9)
	Audio.play("Click")
	say(c, "Rick", "Ну, нам пора. Морти, айда в Блипс-энд-Читц? Там новый автомат «Рой»!", "Well, time to go. Morty, how about Blips and Chitz? They've got a new Roy machine!")
	say(c, "Morty", "Рик, тут сейчас всё взорвётся!", "Rick, this whole place is about to blow up!")
	say(c, "Rick", "Вот именно поэтому нам и пора.", "Which is exactly why it's time to go.")
	if cam then
		cam:lookAt(eyePos)
	end
	say(c, "Cam", "Беги, Морти! Ещё увидимся!", "Run, Morty! We'll see you again!", { auto = 1 })
	say(c, "Lens", "Мы справимся! Наверное!", "We'll be fine! Probably!", { auto = 1 })
	Dialogue.hide()
	task.spawn(function()
		rick:walkTo(Vector3.new(homeCF.Position.X, rick.root.Position.Y, homeCF.Position.Z), 8)
		rick:visible(false)
	end)
	Director.fov(70, 0.5)
	K.giveControl(c, CFrame.lookAt(mpos, Vector3.new(homeCF.Position.X, mpos.Y, homeCF.Position.Z)))
	api().objective("obj.portal")
	waitNear(c, homeCF.Position, 3.6, 25)
	api().objective(nil)
	-- the beam comes down as the portal closes
	charging = false
	if beamCore then
		local center = land.Position
		local b = Fx.beam(beamCore.Position, Vector3.new(center.X, 0, center.Z), 40, rgb(210, 120, 255))
		task.delay(0.6, b.Destroy)
	end
	Fx.flash(rgb(230, 200, 255), 1, 0.05, 0.6)
	Audio.play("ExplosionBig", 0.7)
	Fx.fade(1, 0.2, true)
	home.Close()
	api().gameplay(false)
	api().freeze(true)
	K.stopLoop(alarm, 0.2)
	K.stopLoop(drone, 0.2)
	for _, conn in S.conns do
		conn:Disconnect()
	end
	table.clear(S.conns)
	Audio.music(nil, 0.5)
end

----------------------------------------------------------------------------
-- CHAPTER 12: Home (+ after the credits)
----------------------------------------------------------------------------
local CREDITS = {
	{ text = { ru = "РИК И МОРТИ: КОМНАТА МОРТИ", en = "RICK AND MORTY: MORTY'S ROOM" }, big = true },
	{ ru = "фан-игра", en = "a fan game" },
	"",
	{ text = { ru = "СЮЖЕТ", en = "STORY" }, big = true },
	{ ru = "придумал игрок", en = "made up by the player" },
	"",
	{ text = { ru = "В РОЛЯХ", en = "STARRING" }, big = true },
	{ ru = "Морти — ты", en = "Morty — you" },
	{ ru = "Рик (настоящий и не очень)", en = "Rick (the real one and not so much)" },
	{ ru = "Злой Морти — в одном глазу", en = "Evil Morty — in one eye" },
	{ ru = "Титан Спикермен 2.0", en = "Titan Speakerman 2.0" },
	{ ru = "Кэм и Линза", en = "Cam and Lens" },
	{ ru = "Кубокорова — в роли себя", en = "Cube Cow — as herself" },
	"",
	{ ru = "Ни один телефон не пострадал. Кроме одного.", en = "No phones were harmed. Except one." },
	"",
	{ text = { ru = "СПАСИБО ЗА ИГРУ!", en = "THANKS FOR PLAYING!" }, big = true },
}

local function ch12(c, _fresh: boolean)
	api().state("story")
	api().gameplay(false)
	Fx.black(1)
	Fx.stopGlitch()
	Scenes.apply("HomeNight", true)
	K.setPhoneOnNightstand(false)
	K.setDoor(false, true)
	api().setSleeping(false)
	local rick = P.rick
	rick.glitch = 0
	local portalCF = CFrame.lookAt(Vector3.new(6.6, 3.6, 2.6), Vector3.new(0, 3.6, 2.6))
	local mortyCF = CFrame.lookAt(Vector3.new(4.4, 3, 2.6), Vector3.new(-6, 3, -2))
	K.holdCharacterAt(c, mortyCF)
	api().hideCharacter(true)
	local portal = openPortal(portalCF, "green", 6.5)
	rick:visible(true)
	rick.follow = nil
	rick:place(CFrame.lookAt(Vector3.new(4.4, 3.36, 4.8), Vector3.new(3, 3.36, 2.6)))
	rick:pose("stand")
	rick:snap()
	local eye = eyeOf(mortyCF)
	Director.start()
	Director.cut(CFrame.lookAt(eye.Position, eye.Position + Vector3.new(-1, -0.1, -0.35)), 70)
	Director.freeLook(true, { yaw = 1.6, pitchUp = 0.8, pitchDown = 0.8 })
	Audio.play("Whoosh")
	Fx.flash(rgb(200, 255, 200), 0.7, 0.02, 0.6)
	Fx.fade(0, 0.6)
	Fx.caption("loc.home")
	Fx.title("ch.12")
	c.check()
	portal.Close()
	Audio.music("MusicNight", 3)
	rick:lookAt(eye.Position)
	say(c, "Rick", "Ну так что, Морти? Блипс-энд-Читц? Там новый автомат «Рой» — проживёшь целую жизнь за пять минут!", "So what do you say, Morty? Blips and Chitz? The new Roy machine — live a whole life in five minutes!")
	say(c, "Morty", "Нет, Рик. Я сегодня навидался такого... Я спать.", "No, Rick. I've seen enough today... I'm going to bed.")
	say(c, "Rick", "Пф-ф. Скучный ты, Морти. *рыг* Ладно. Спокойной ночи.", "Pfft. You're boring, Morty. *burp* Fine. Good night.")
	Audio.play("Burp")
	Dialogue.hide()
	-- Rick leaves through the door
	K.setDoor(true)
	task.spawn(function()
		rick:walkTo(Vector3.new(6.5, 3.36, 6.6), 6)
		rick:walkTo(Vector3.new(6.5, 3.36, 10.5), 6)
		rick:visible(false)
		K.setDoor(false)
	end)
	say(c, "MortyThought", "Взорвавшийся телефон. Титан. Щупальца. Туалеты из космоса... Обычный вторник.", "An exploding phone. A Titan. Tentacles. Toilets from space... Just a normal Tuesday.", { auto = 2.4 })
	Dialogue.hide()
	-- go to bed
	local bed = R.house:FindFirstChild("Bed")
	if bed then
		bed:SetAttribute("Interact", "Bed")
	end
	Director.freeLook(false)
	K.giveControl(c, mortyCF)
	api().objective("obj.bed")
	c.interact("Bed")
	api().objective(nil)
	if bed then
		bed:SetAttribute("Interact", nil)
	end
	api().gameplay(false)
	api().freeze(true)
	api().hideCharacter(true)
	Director.start()
	Audio.play("Cloth")
	local lying = K.eyeFromHead(api().headCore.CFrame)
	Director.move(lying, 1.6, "smooth", 70)
	Director.freeLook(true, { yaw = 1.2, pitchUp = 0.8, pitchDown = 0.6 })
	api().lids(0.35, 2.2)
	say(c, "MortyThought", "Надеюсь, завтра будет самый обычный, скучный день...", "I hope tomorrow is a totally normal, boring day...", { auto = 2.2 })
	Dialogue.hide()
	api().lids(0, 1.6)
	api().snore(true)
	c.wait(1.2)
	Fx.fade(1, 1.4, true)
	api().snore(false)

	-- CREDITS -----------------------------------------------------------------
	Audio.music("MusicDreamy", 2)
	Director.freeLook(false)
	Fx.credits(CREDITS)
	c.check()
	Audio.music(nil, 2)
	c.wait(1)

	-- AFTER THE CREDITS: meanwhile, in the garage ---------------------------------
	api().lids(1, 0)
	local term = R.lab:FindFirstChild("Terminal")
	local screen = term and term:FindFirstChild("Screen1") :: BasePart?
	local screen2 = term and term:FindFirstChild("Screen2") :: BasePart?
	local text1 = screen and screen:FindFirstChild("Text", true) :: TextLabel?
	local text2 = screen2 and screen2:FindFirstChild("Text", true) :: TextLabel?
	start.term1 = start.term1 or (text1 and text1.Text)
	start.term2 = start.term2 or (text2 and text2.Text)
	Scenes.apply("HomeNight", true)
	-- (the saucer is still lying on B137)
	K.saucerTo(CFrame.new(6014, -1.2, -6) * CFrame.Angles(math.rad(14), math.rad(70), math.rad(-11)))
	Graphics.SetLight("GarageLight", false)
	Graphics.SetLight("VatGlow", true)
	if screen then
		local view = screen.CFrame * CFrame.new(1.2, 0.3, -6.5)
		Director.cut(CFrame.lookAt(view.Position, screen.Position + Vector3.new(0, 0, 1)), 60)
	end
	Fx.fade(0, 1.2)
	Fx.caption("loc.later")
	c.wait(1.6)
	for _, pct in { 98, 87, 61, 34, 12 } do
		if text1 then
			text1.Text = ("CENTRAL FINITE CURVE\n> integrity: %d%%\n> resonance: RISING\n> source: S-0"):format(pct)
			text1.TextColor3 = if pct < 40 then rgb(255, 90, 80) else rgb(120, 255, 140)
		end
		Audio.play("RadarPing", if pct < 40 then 0.8 else 1)
		c.wait(0.9)
	end
	if text2 then
		text2.Text = "!! BREACH DETECTED !!\n> visitor: C-???\n> access: PRIME"
		text2.TextColor3 = rgb(255, 90, 80)
	end
	Audio.play("OverheatBeep", 0.8)
	Fx.glitch(0.4, 0.3)
	c.wait(1.2)
	-- a cold portal opens behind
	local prime = P.prime
	local labCenter = if screen then screen.Position + Vector3.new(9, -4.3, 0) else Vector3.new(-32, -9, -21)
	local pcf = CFrame.lookAt(labCenter + Vector3.new(0, 3.5, 3), labCenter + Vector3.new(-4, 3.5, 0))
	local pp = openPortal(pcf, "white", 7)
	if screen then
		Director.move(CFrame.lookAt(screen.Position + Vector3.new(6, 0.4, -4), pcf.Position), 1.4, "smooth", 55)
	end
	prime:visible(true)
	prime.follow = nil
	local primeFrom = Vector3.new(pcf.Position.X, labCenter.Y + 3.36, pcf.Position.Z)
	prime:place(CFrame.lookAt(primeFrom, primeFrom + pcf.LookVector))
	prime:pose("stand")
	prime:snap()
	local walkTo = labCenter + Vector3.new(-1.5, 3.36, 1)
	prime:walkTo(walkTo, 4)
	pp.Close()
	local primeHead = prime.model:FindFirstChild("Head") :: BasePart?
	if primeHead then
		prime:lookAt(Director.base().Position)
		Director.move(CFrame.lookAt(primeHead.Position + primeHead.CFrame.LookVector * 5 + Vector3.new(0.6, 0.2, 0), primeHead.Position), 1.2, "smooth", 42)
	end
	say(c, "RickPrime", "Здравствуй, C-137.", "Hello, C-137.")
	say(c, "RickPrime", "Спасибо, что позвонил.", "Thanks for calling.")
	Dialogue.hide()
	c.wait(0.6)
	Fx.fade(1, 0.15, true)
	Audio.play("Boom", 0.6)
	Fx.title("tbc")
	c.wait(0.8)
	-- tidy up the garage screens for the next run
	if text1 and start.term1 then
		text1.Text = start.term1
		text1.TextColor3 = rgb(120, 255, 140)
	end
	if text2 and start.term2 then
		text2.Text = start.term2
		text2.TextColor3 = rgb(120, 255, 140)
	end
	prime:place(start.prime)
	api().toMenu()
end

----------------------------------------------------------------------------
-- public
----------------------------------------------------------------------------
function StoryCurve.onSpeaker(who: string?)
	if not P then
		return
	end
	if P.evil then
		P.evil.talking = (who == "EvilMorty")
	end
	if P.prime then
		P.prime.talking = (who == "RickPrime")
	end
	for key, name in { cam = "Cam", lens = "Lens", commander = "Commander" } do
		local p = S[key]
		if p then
			p.talking = (who == name)
		end
	end
	S.titanTalking = (who == "Titan")
end

function StoryCurve.init(kit)
	K = kit
	R, P = kit.R, kit.P
	local worlds = workspace:WaitForChild("Worlds")
	W.silent = worlds:WaitForChild("SilentDimension")
	W.silentSpots = W.silent:WaitForChild("SilentSpots")
	W.bell = W.silent:WaitForChild("CurveBell")
	W.cracks = W.silent:WaitForChild("Cracks")
	W.j22 = worlds:WaitForChild("WorldJ22")
	W.d716 = worlds:WaitForChild("WorldD716")
	W.k9 = worlds:WaitForChild("WorldK9")
	W.base = worlds:WaitForChild("CameraBase")
	W.baseSpots = W.base:WaitForChild("BaseSpots")
	W.formation = W.base:WaitForChild("BaseFormation")
	W.shed = R.planet:WaitForChild("BunkerShed")
	W.astro = workspace:WaitForChild("Astro")
	W.mother = W.astro:WaitForChild("Mothership")
	W.curseHead = R.fight:WaitForChild("CurseHead")
	W.templates = Game:WaitForChild("Templates")

	P.evil = Puppet.new(R.cast:WaitForChild("EvilMorty"), "R6")
	P.prime = Puppet.new(R.cast:WaitForChild("RickPrime"), "R6")
	P.rickBeast = Puppet.new(R.fight:WaitForChild("RickBeast"), "Rig")
	P.evilBeast = Puppet.new(R.fight:WaitForChild("EvilBeast"), "Rig")
	P.pit = Puppet.new(R.fight:WaitForChild("PitTentacles"), "Rig")

	start.evil = P.evil.root.CFrame
	start.prime = P.prime.root.CFrame
	start.rickBeast = P.rickBeast.root.CFrame
	start.evilBeast = P.evilBeast.root.CFrame
	start.pit = P.pit.root.CFrame
	start.entity = P.entity.root.CFrame
	start.curseHead = W.curseHead:GetPivot()
	start.mother = W.mother:GetPivot()
	start.ships = {}
	for i = 1, 10 do
		local ship = W.astro:FindFirstChild("AstroShip" .. i)
		start.ships[i] = if ship then ship:GetPivot() else CFrame.new()
	end
	start.prongs = {}
	for _, p in partsWithAttr(W.bell, "BellProng") do
		start.prongs[p] = p.CFrame
	end
	start.shedDoor = {}
	local door = W.shed:FindFirstChild("ShedDoor")
	if door then
		for _, d in door:GetDescendants() do
			if d:IsA("BasePart") then
				start.shedDoor[d] = d.CFrame
			end
		end
	end
	-- Evil Morty wears his own angry brows: hide the default ones
	for _, n in { "BrowL", "BrowR" } do
		local p = P.evil.model:FindFirstChild(n, true)
		if p and p:IsA("BasePart") then
			p.Transparency = 1
		end
	end
	evilFace(false)

	-- the Titan's head speaker pulses when he talks; the Commander's screen flickers
	local eyeLight = R.titanModel:FindFirstChild("EyeLight", true) :: PointLight?
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if eyeLight then
			eyeLight.Brightness = if S.titanTalking then 1.5 + math.abs(math.sin(t * 13)) * 6 else 1.5
		end
		local cmd = S.commander
		if cmd and cmd.talking then
			local scr = cmd.model:FindFirstChild("Screen", true) :: BasePart?
			if scr then
				local v = 0.75 + math.abs(math.sin(t * 17)) * 0.25
				scr.Color = Color3.new(0.67 * v, 0.82 * v, v)
			end
		end
	end)

	K.CH[7] = ch7
	K.CH[8] = ch8
	K.CH[9] = ch9
	K.CH[10] = ch10
	K.CH[11] = ch11
	K.CH[12] = ch12
end

function StoryCurve.reset()
	if not K then
		return
	end
	for _, conn in S.conns do
		conn:Disconnect()
	end
	table.clear(S.conns)
	for _, s in S.loops do
		if s and s.Parent then
			s:Destroy()
		end
	end
	table.clear(S.loops)
	closePortals()
	clearCrowd()
	holdCurseHead(false)
	W.curseHead:PivotTo(start.curseHead)
	hideBeasts()
	titanWounded(false)
	cannonCharge(0)
	shedVisible(false)
	shedDoor(0)
	resetSilent()
	placeShips(false)
	W.mother:PivotTo(start.mother)
	local beamCore = W.mother:FindFirstChild("BeamCore") :: BasePart?
	if beamCore then
		beamCore.Size = Vector3.new(30, 90, 90)
	end
	cityFx(false)
	for _, key in { "evil", "prime" } do
		local p = P[key]
		p.follow = nil
		p.walk = 0
		p.glitch = 0
		p:lookAt(nil)
		p:visible(true)
		p:place(start[key])
	end
	stopFollow(P.rick)
	evilFace(false)
	local hum = api().humanoid()
	if hum then
		hum.WalkSpeed = 9
	end
	local bed = R.house:FindFirstChild("Bed")
	if bed then
		bed:SetAttribute("Interact", nil)
	end
	for _, worldName in { "j22", "k9" } do
		local wm = W[worldName]
		if wm then
			K.emitters(wm, nil, false)
		end
	end
	local eyes = W.k9 and W.k9:FindFirstChild("SporeEyes")
	if eyes then
		for _, p in eyes:GetChildren() do
			if p:IsA("BasePart") then
				p.Transparency = 1
			end
		end
	end
	Fx.death(false)
	S.titanTalking = false
end

return StoryCurve
