--!nocheck
-- Тесты CORE ROULETTE в Lune (вне Roblox): lune run tests/run.luau  (из папки core-roulette)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local process = require("@lune/process")

local failures = 0
local function check(cond: boolean, msg: string)
	if cond then
		print("  ok   " .. msg)
	else
		failures += 1
		print("  FAIL " .. msg)
	end
end

local function loadModule(path: string, env: { [string]: any })
	local source = fs.readFile(path)
	local base = {
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		Vector2 = roblox.Vector2,
		Enum = roblox.Enum,
		Instance = roblox.Instance,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		typeof = roblox.typeof or typeof,
		task = task,
	}
	for k, v in env do
		base[k] = v
	end
	local fn = luau.load(source, { debugName = path, environment = setmetatable(base, { __index = _G }), injectGlobals = true })
	return fn()
end

------------------------------------------------------------------------
print("[Spring]")
local Spring = loadModule("src/ReplicatedStorage/Spring.luau", {})

for _, damper in { 0.3, 1, 2.5 } do
	local s = Spring.new(0, damper, 10)
	s.Target = 1
	for _ = 1, 600 do
		s:Update(1 / 60)
	end
	check(math.abs(s.Position - 1) < 1e-3, string.format("number spring converges (damper %.1f) -> %.5f", damper, s.Position))
end

-- Аналитика против мелкошаговой численной интеграции
for _, damper in { 0.4, 1, 1.8 } do
	local s = Spring.new(0, damper, 8)
	s.Target = 2
	s:Impulse(5)
	local x, v = 0, 5
	local h = 1e-5
	for _ = 1, math.floor(0.5 / h) do
		local a = -64 * (x - 2) - 2 * damper * 8 * v
		v += a * h
		x += v * h
	end
	for _ = 1, 30 do
		s:Update(0.5 / 30)
	end
	check(math.abs(s.Position - x) < 2e-3 and math.abs(s.Velocity - v) < 2e-2, string.format("analytic == numeric (damper %.1f): %.4f vs %.4f", damper, s.Position, x))
end

local vs = Spring.new(roblox.Vector3.new(0, 0, 0), 1, 12)
vs.Target = roblox.Vector3.new(3, -2, 5)
vs:Impulse(roblox.Vector3.new(10, 0, 0))
for _ = 1, 300 do
	vs:Update(1 / 60)
end
check((vs.Position - vs.Target).Magnitude < 1e-3, "Vector3 spring converges")
check(vs:IsResting(1e-2), "IsResting() after settle")
local big = Spring.new(0, 0.5, 20)
big.Target = 1
big:Update(10) -- огромный dt зажимается
check(big.Position == big.Position and math.abs(big.Position) < 5, "huge dt stays finite")
vs:Snap(roblox.Vector3.new(1, 1, 1))
check(vs.Position == roblox.Vector3.new(1, 1, 1) and vs.Velocity == roblox.Vector3.new(0, 0, 0), "Snap() resets velocity")

------------------------------------------------------------------------
print("[BunkerBuilder]")
local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
-- Шаблон Baseplate: спавн в центре должен исчезнуть
local oldSpawn = roblox.Instance.new("SpawnLocation")
oldSpawn.Position = roblox.Vector3.new(0, 0.5, 0)
oldSpawn.Parent = workspace

local Builder = loadModule("src/ServerScriptService/BunkerBuilder.luau", { game = game, workspace = workspace })
local ok, world = pcall(Builder.Build)
check(ok, "Build() runs without errors" .. (if ok then "" else ": " .. tostring(world)))
if ok then
	check(#world.Seats == 4 and #world.Prompts == 4, "4 seats with ProximityPrompts")
	check(world.Prompts[1].ActionText == "Sit at Table", "prompt text = Sit at Table")
	check(#world.FuelRods == 3, "3 fuel rods")
	check(#world.CRTLabels == 2, "2 CRT monitors")
	check(world.CRTLabels[1].Screen:IsA("SurfaceGui"), "CRT SurfaceGui built")
	check(world.ManipulatorPart.Name == "ManipulatorHead", "ManipulatorPart returned")
	check(world.SparksEmitter:IsA("ParticleEmitter"), "SparksEmitter returned")
	check(world.CoreLight:IsA("PointLight"), "CoreLight returned")
	check(world.Spotlight:IsA("SpotLight"), "Spotlight returned")
	local soundCount = 0
	for name, s in world.Sounds do
		soundCount += 1
		check(string.sub(s.SoundId, 1, 18) == "rbxasset://sounds/", "built-in sound " .. name)
	end
	check(soundCount >= 8, "all core sounds")
	check(oldSpawn.Parent == nil, "template spawn at the table removed")
	check(world.SpawnLocation.Parent ~= nil, "bunker spawn present")
	check(game:GetService("Lighting"):FindFirstChild("CoreGrade") ~= nil, "ColorCorrection created")
	check(game:GetService("Lighting"):FindFirstChild("CoreAtmosphere") ~= nil, "Atmosphere created")

	-- Ключевые имена, которые ищет клиент
	local bunker = workspace:FindFirstChild("CoreRouletteBunker")
	local need = {
		"Core.CoreNeon.CoreLight",
		"Core.Cap.RimAttachment.RimSparks",
		"Core.Cap.SteamAttachment.Steam",
		"Core.FuelRods.Rod1.RodRoot",
		"Core.FuelRods.Rod3.RodRoot",
		"Manipulator.ShoulderPivot",
		"Manipulator.Sleeve",
		"Manipulator.Piston",
		"Manipulator.ManipulatorHead.TipAttachment.ClawSparks",
		"Manipulator.ManipulatorHead.TipAttachment.ArcLight",
		"Manipulator.Finger1",
		"Manipulator.Finger3",
		"Lamp.Hinge",
		"Lamp.Bulb.Spotlight",
		"Chairs.Chair1.Seat.SitPrompt",
		"Chairs.Chair4.Seat",
		"Beacons.BeaconDome1.BeaconLight",
		"Beacons.BeaconDome3.BeaconLight",
	}
	for _, path in need do
		local node = bunker
		for name in string.gmatch(path, "[^%.]+") do
			node = node and node:FindFirstChild(name)
		end
		check(node ~= nil, "client path " .. path)
	end
	for _, name in { "Hum", "Geiger", "Scrape", "Clunk", "Explosion", "Siren", "Overclock", "Eject", "Servo" } do
		check(bunker.Core.CoreNeon:FindFirstChild(name) ~= nil, "sound " .. name .. " under CoreNeon")
	end
	check(typeof(bunker.Core.FuelRods.Rod1.RodRoot:GetAttribute("RestCFrame")) == "CFrame", "rod RestCFrame attribute")
	for _, attr in { "CoreCenter", "PivotPos", "HeadRest", "LampHinge" } do
		check(typeof(bunker:GetAttribute(attr)) == "Vector3", "bunker attribute " .. attr)
	end

	-- (Ориентацию сидений тут не проверяем: CFrame.lookAt в Lune 0.10 даёт неверный поворот для части направлений.)
	for i, info in world.SeatInfos do
		local sp = info.Seat.CFrame.Position
		check(math.abs(math.sqrt(sp.X * sp.X + sp.Z * sp.Z) - 9.6) < 0.01, "seat " .. i .. " on the table ring")
	end

	-- Повторная сборка не дублирует мир
	Builder.Build()
	local count = 0
	for _, child in workspace:GetChildren() do
		if child.Name == "CoreRouletteBunker" then
			count += 1
		end
	end
	check(count == 1, "rebuild replaces the old bunker")

	local parts = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("  info %d parts in the bunker", parts))
end

------------------------------------------------------------------------
print("[Server/Client sync]")
local serverSrc = fs.readFile("src/ServerScriptService/CoreServer.server.luau")
local clientSrc = fs.readFile("src/StarterPlayerScripts/CoreClient.client.luau")
local function extractSweet(src: string): string?
	return string.match(src, "local function sweetCenter%(.-\nend\n")
end
local a, b = extractSweet(serverSrc), extractSweet(clientSrc)
check(a ~= nil and a == b, "sweetCenter() identical on server and client")
local serverMax = tonumber(string.match(serverSrc, "CursorMaxSpeed = ([%d%.]+)"))
local clientMax = tonumber(string.match(clientSrc, "CursorMaxSpeed = ([%d%.]+)"))
check(serverMax ~= nil and clientMax ~= nil and clientMax < serverMax, "client cursor speed below server anti-cheat cap")
for _, src in { serverSrc, clientSrc, fs.readFile("src/ServerScriptService/BunkerBuilder.luau"), fs.readFile("src/ReplicatedStorage/Spring.luau") } do
	check(string.sub(src, 1, 9) == "--!strict", "--!strict header")
	check(not string.find(src, "[^%.:_%w]wait%(") and not string.find(src, "[^%.:_%w]spawn%(") and not string.find(src, "[^%.:_%w]delay%("), "no deprecated wait/spawn/delay")
	check(not string.find(src, "TODO"), "no TODO")
	check(not string.find(src, "BodyVelocity") and not string.find(src, "BodyPosition") and not string.find(src, "BodyGyro"), "no legacy BodyMovers")
	check(not string.find(src, "rbxassetid://"), "no uploaded asset ids")
end

------------------------------------------------------------------------
print("[Micro-game balance]")
-- Та же физика курсора, что в клиенте, и те же правила, что на сервере.
local sweetFn = luau.load(a .. "\nreturn sweetCenter", { debugName = "sweet", environment = { math = math } })()
-- Детерминированный ГСЧ (в Lune нет Random)
local function makeRng(seed: number)
	local state = seed * 9301 + 49297
	return {
		NextNumber = function(_, a: number?, b: number?)
			state = (state * 1103515245 + 12345) % 2147483648
			local f = state / 2147483648
			if a and b then
				return a + (b - a) * f
			end
			return f
		end,
	}
end
local function simulate(strategy: string, drift: number, instability: number, seed: number): (string, number, number)
	local r = makeRng(seed)
	local params = {
		Phase1 = r:NextNumber(0, math.pi * 2),
		Phase2 = r:NextNumber(0, math.pi * 2),
		Phase3 = r:NextNumber(0, math.pi * 2),
		Speed = 1 * (1 + instability / 100 * 0.6) * (1 + 0.15 * (drift - 1)),
		HalfWidth = 0.13,
	}
	local cursor, vel, progress, inst = 0, 0, 0, instability
	local dt = 1 / 60
	local t = 0
	local noiseSeed = r:NextNumber(0, 500)
	local lastSent, sentCursor, sentT = 0, 0, 0
	while true do
		t += dt
		local hold
		if strategy == "skilled" then
			-- человек с реакцией ~0.12 с: целится в центр зоны с упреждением
			local c = sweetFn(math.max(t - 0.15, 0), params)
			hold = cursor + vel * 0.2 < c
		elseif strategy == "idle" then
			hold = false
		else
			hold = r:NextNumber() < 0.5
		end
		local inst01 = math.clamp(inst / 100, 0, 1)
		local accel = (if hold then 5.4 else 0) - 2.6
		accel += (math.noise(noiseSeed, t * 3.1) * 2.6 + math.noise(noiseSeed + 7.3, t * 11.7) * 1.2) * 0.5 * drift * (0.6 + inst01)
		vel += accel * dt
		vel *= math.exp(-2.0 * dt)
		vel = math.clamp(vel, -2.0, 2.0)
		cursor += vel * dt
		if cursor <= 0 then
			cursor = 0
			vel = math.max(vel, 0) - vel * 0.2
		elseif cursor >= 1 then
			cursor = 1
			vel = math.min(vel, 0) - vel * 0.2
		end
		if t - lastSent >= 0.065 then
			lastSent = t
			sentCursor, sentT = cursor, t
		end
		if t >= 0.8 then
			local inside = math.abs(sentCursor - sweetFn(sentT, params)) <= params.HalfWidth
			if inside then
				progress = math.min(1, progress + 0.3 * dt)
			else
				progress = math.max(0, progress - 0.06 * dt)
				inst = math.min(100, inst + 18 * dt)
			end
		end
		if progress >= 1 then
			return "SUCCESS", t, inst
		elseif inst >= 100 then
			return "CRITICAL", t, inst
		elseif t >= 7 then
			return "TIMEOUT", t, inst
		end
	end
end

local function rate(strategy: string, drift: number, instability: number): number
	local wins = 0
	for seed = 1, 200 do
		if simulate(strategy, drift, instability, seed) == "SUCCESS" then
			wins += 1
		end
	end
	return wins / 200
end
local skilledLow = rate("skilled", 1, 20)
local skilledHigh = rate("skilled", 1, 60)
local skilledDrift = rate("skilled", 2, 40)
local masher = rate("random", 1, 20)
local idle = rate("idle", 1, 20)
print(string.format("  info success: skilled@20%%=%.0f%%  skilled@60%%=%.0f%%  skilled drift2@40%%=%.0f%%  masher=%.0f%%  idle=%.0f%%", skilledLow * 100, skilledHigh * 100, skilledDrift * 100, masher * 100, idle * 100))
check(skilledLow > 0.85, "a focused player usually wins at low instability")
check(skilledHigh < skilledLow - 0.2 and skilledHigh > 0.25, "higher instability is not easier")
check(skilledDrift < skilledLow - 0.3 and skilledDrift > 0.2, "overclock tremor makes it harder")
check(masher < 0.1, "button-mashing rarely works")
check(idle == 0, "doing nothing always detonates")

print(if failures == 0 then "ALL TESTS PASSED" else string.format("%d FAILURE(S)", failures))
process.exit(if failures == 0 then 0 else 1)
