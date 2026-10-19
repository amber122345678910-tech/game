--!nocheck
-- Юнит-тесты: lune run tools/tests/run.luau
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local Loader = require("../lib/loader")
local Pose = require("../lib/Pose")
local Rig = require("../lib/Rig")

local Config = Loader.load("src/shared/Config")
local Timeline = Loader.load("src/shared/Timeline")
local Easing = Loader.load("src/shared/Anim/Easing")
local KFS = Loader.load("src/shared/Anim/KFS")
local CameraTrack = Loader.load("src/shared/CameraTrack")
local Lyrics = Loader.load("src/shared/Lyrics")
local Presets = Loader.load("src/shared/Presets")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. "\n  " .. tostring(err))
	end
end
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-4) then
		error(string.format("%s: expected %.5f, got %.5f", msg or "near", b, a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

test("easing endpoints", function()
	for _, st in { "Linear", "Sine", "Quad", "Cubic", "Back", "Elastic", "Bounce", "Exponential", "Circular" } do
		for _, d in { "In", "Out", "InOut" } do
			near(Easing.tween(st, d, 0), 0, 1e-3, st .. d .. "@0")
			near(Easing.tween(st, d, 1), 1, 1e-3, st .. d .. "@1")
		end
	end
	near(Easing.pose("Constant", "In", 0.99), 0, 1e-9, "constant")
end)

test("timeline contiguous and covers clip", function()
	local shots = Timeline.shots
	near(shots[1].start, 0, 1e-6, "first start")
	for i = 1, #shots - 1 do
		near(shots[i].finish, shots[i + 1].start, 1e-3, "gap after " .. shots[i].id)
	end
	near(shots[#shots].finish, Config.BlackFrom, 1e-3, "last finish")
	for _, s in shots do
		truthy(Config.Sets[s.set], "unknown set in " .. s.id)
		truthy(Presets[s.preset], "unknown preset in " .. s.id)
		truthy(#s.camera.keys >= 1, "no camera keys " .. s.id)
	end
end)

test("lyrics ordered", function()
	for i = 1, #Lyrics - 1 do
		truthy(Lyrics[i].finish <= Lyrics[i + 1].start + 1e-6, "lyrics overlap " .. i)
	end
end)

test("camera evaluates finite for every frame", function()
	for _, s in Timeline.shots do
		local t = s.start
		while t <= s.finish do
			local r = CameraTrack.evaluate(s, t)
			local p = r.cframe.Position
			truthy(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "NaN camera in " .. s.id)
			truthy(r.fov > 1 and r.fov < 120, "fov out of range in " .. s.id)
			t += 1 / 30
		end
	end
end)

test("IK reaches target, FK round trip through KFS", function()
	local rig = Rig.new("T", { fingers = true })
	local solver = Pose.solver(rig)
	local target = Vector3.new(0.6, 3.2, -0.9)
	local keys = {
		{ t = 0, rArm = { ik = { 0.6, 3.2, 0.9 } }, waist = { turn = 15, bend = 10 }, neck = { nod = 10 } },
		{ t = 1, rArm = { ik = { 0.6, 3.2, 0.9 } }, waist = { turn = -15 }, rHand = "fist" },
	}
	local tracks = Pose.tracks(keys, solver)
	for _, t in { 0, 0.5, 1 } do
		local tr = Pose.evaluate(tracks, solver, t)
		local cfs = solver:fk(tr)
		local w = (cfs.RightLowerArm * rig.motors.RightHand.C0).Position
		near((w - target).Magnitude, 0, 1e-3, "wrist error at " .. t)
	end
	local kfs = Pose.bake(rig, { start = 0, finish = 1 }, { keys = keys }, "T", 30)
	local clip = KFS.compile(kfs)
	local out = {}
	KFS.sample(clip, 0.5, out)
	local direct = Pose.evaluate(tracks, solver, 0.5)
	local a, b = out.RightUpperArm, direct.RightUpperArm
	local _, ang = (a:Inverse() * b):ToAxisAngle()
	truthy(math.abs(ang) < math.rad(0.6), "baked vs direct mismatch " .. math.deg(ang))
end)

test("smooth keys pass through key values", function()
	local rig = Rig.new("T2")
	local solver = Pose.solver(rig)
	local keys = { { t = 0, neck = { turn = 0 } }, { t = 1, neck = { turn = 40 } }, { t = 2, neck = { turn = 10 } } }
	local tracks = Pose.tracks(keys, solver)
	local tr = Pose.evaluate(tracks, solver, 1)
	local _, ry = tr.Head:ToEulerAnglesYXZ()
	near(math.deg(ry), 40, 0.05, "key value")
end)

test("all shots build and bake", function()
	local World = require("../lib/World")
	local w = World.build({ allSets = true })
	for id, e in w.shots do
		for name, a in e.actors do
			truthy(a.model:FindFirstChild("HumanoidRootPart"), id .. "/" .. name .. " no HRP")
		end
	end
end)

print(string.format("tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
