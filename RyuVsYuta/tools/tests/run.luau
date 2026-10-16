--!nocheck
-- Юнит-тесты движка катсцены (Lune): lune run tools/tests/run.luau
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local Loader = require("../lib/loader")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local MathX = Loader.load("src/shared/Math")
local Track = Loader.load("src/shared/Track")
local Rig = Loader.load("src/shared/Rig")
local Skeletons = Loader.load("src/shared/Skeletons")
local Gait = Loader.load("src/shared/Anim/Gait")
local Hair = Loader.load("src/shared/Anim/Hair")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-4) then
		error(string.format("%s: %s vs %s", msg or "near", tostring(a), tostring(b)), 2)
	end
end
local function nearV(a, b, eps, msg)
	if (a - b).Magnitude > (eps or 1e-3) then
		error(string.format("%s: %s vs %s", msg or "nearV", tostring(a), tostring(b)), 2)
	end
end

test("easing endpoints", function()
	for _, n in { "Linear", "InSine", "OutSine", "InOutSine", "InQuad", "OutCubic", "InOutQuint", "OutBack", "InOutBack", "OutExpo", "InOutCirc", "OutElastic", "OutBounce", "Smooth", "Smoother" } do
		near(MathX.ease(n, 0), 0, 1e-6, n .. "@0")
		near(MathX.ease(n, 1), 1, 1e-6, n .. "@1")
	end
	near(MathX.ease("InOutSine", 0.5), 0.5, 1e-6)
end)

test("lookAt matches direction", function()
	local cf = MathX.lookAt(Vector3.new(1, 2, 3), Vector3.new(1, 2, -7))
	nearV(cf.LookVector, Vector3.new(0, 0, -1), 1e-5, "look -Z")
	nearV(cf.UpVector, Vector3.new(0, 1, 0), 1e-5, "up")
	local cf2 = MathX.lookAt(Vector3.zero, Vector3.new(10, 0, -10))
	nearV(cf2.LookVector, Vector3.new(1, 0, -1).Unit, 1e-5, "diag look")
	nearV(cf2.RightVector, Vector3.new(1, 0, 1).Unit, 1e-5, "diag right")
end)

test("axisX", function()
	local cf = MathX.axisX(Vector3.new(0, 1, 0), Vector3.new(0, 0, 5))
	nearV(cf.RightVector, Vector3.new(0, 0, 1), 1e-5)
end)

test("track number hermite/ease", function()
	local keys = { { t = 0, v = 0 }, { t = 1, v = 10 }, { t = 2, v = 10, ease = "Linear" }, { t = 3, v = 0, ease = "InOutSine" } }
	near(Track.number(keys, -1), 0)
	near(Track.number(keys, 0), 0)
	near(Track.number(keys, 1), 10)
	near(Track.number(keys, 1.5), 10)
	near(Track.number(keys, 2.5), 5, 1e-6)
	near(Track.number(keys, 5), 0)
	-- монотонность без перелёта на 0..1 (ключ 1 — экстремум => касательная 0)
	for i = 0, 10 do
		local v = Track.number(keys, i / 10)
		assert(v >= -1e-6 and v <= 10 + 1e-6, "overshoot " .. v)
	end
end)

test("track pose", function()
	local keys = { { t = 0, v = { Head = { 0, 0, 0 } } }, { t = 1, v = { Head = { 90, 0, 0 }, Chest = { 0, 0, 0, 0, 1, 0 } }, ease = "Linear" } }
	local p = Track.pose(keys, 0.5)
	local x = select(1, p.Head:ToEulerAnglesYXZ())
	near(math.deg(x), 45, 1e-3, "head pitch")
	nearV(p.Chest.Position, Vector3.new(0, 0.5, 0), 1e-5, "chest shift")
end)

test("rig rest solve equals rest", function()
	local def = Skeletons.Rika
	local w = Rig.solve(def, CFrame.new(), {}, nil)
	for i, cf in w do
		nearV(cf.Position, def.rest[i].Position, 1e-4, def.bones[i].name)
	end
	-- стопы на земле: лодыжка на высоте ankleHeight
	near(Rig.boneWorld(def, w, "FootL").Position.Y, Skeletons.RikaProportions.ankleHeight, 1e-4, "ankle")
end)

test("ik reaches target", function()
	for _, name in { "Yuta", "Ryu", "Rika" } do
		local def = Skeletons[name]
		local origin = CFrame.new(5, 0, 3) * CFrame.Angles(0, 0.7, 0)
		local head = Rig.solve(def, origin, {}, nil)[def.index.Head]
		local target = head.Position + head.RightVector * -0.6 + head.UpVector * 0.4
		local pole = head.Position + head.RightVector * -3 + head.LookVector * -2
		local w = Rig.solve(def, origin, {}, { { upper = "UpperArmL", lower = "LowerArmL", tip = "HandL", target = target, pole = pole } })
		local hand = w[def.index.HandL].Position
		local reach = def.lengths.UpperArmL + def.lengths.LowerArmL
		local shoulder = w[def.index.UpperArmL].Position
		if (target - shoulder).Magnitude < reach * 0.98 then
			nearV(hand, target, 1e-2, name .. " hand")
		end
		-- локоть отклонён к полюсу
		local elbow = w[def.index.LowerArmL].Position
		local mid = (shoulder + hand) / 2
		assert((elbow - mid):Dot(pole - mid) > 0, name .. " elbow toward pole")
	end
end)

test("leg ik keeps knee forward", function()
	local def = Skeletons.Yuta
	local w0 = Rig.solve(def, CFrame.new(), {}, nil)
	local ankle = w0[def.index.FootL].Position + Vector3.new(0, 0.6, -0.4)
	local hip = w0[def.index.UpperLegL].Position
	local w = Rig.solve(def, CFrame.new(), {}, { { upper = "UpperLegL", lower = "LowerLegL", tip = "FootL", target = ankle, pole = hip + Vector3.new(0, -1, -6), hingeSign = 1 } })
	nearV(w[def.index.FootL].Position, ankle, 1e-2, "ankle")
	assert(w[def.index.LowerLegL].Position.Z < hip.Z - 0.05, "knee should be in front (-Z)")
	-- без кручения: ось X бедра почти не изменилась
	local x = w[def.index.UpperLegL].RightVector
	assert(x:Dot(Vector3.new(1, 0, 0)) > 0.95, "thigh twist " .. tostring(x))
end)

test("gait plants feet (no sliding during stance)", function()
	local def = Skeletons.Yuta
	local P = Skeletons.YutaProportions
	local path = { { t = 0, pos = Vector3.new(0, 0, 20) }, { t = 10, pos = Vector3.new(0, 0, -20) } }
	local params = { stepTime = 0.55, firstStep = 0.2, footSpacing = 0.35, lift = 0.4, bob = 0.08, rise = 0.05, sway = 0.06, hipRoll = 4, hipYaw = 6, lean = 3, armSwing = 18, armOut = 5, elbow = 10, armLag = 0.1, headBob = 0.7, impact = 0.2, ankleHeight = P.ankleHeight, toeOff = 15 }
	-- в течение опоры (шаг 4, левая) позиция лодыжки постоянна
	local tc = params.firstStep + 4 * params.stepTime
	local a = nil
	for i = 0, 8 do
		local t = tc + i * params.stepTime / 10
		local r = Gait.walk(def, path, params, t)
		local w = Rig.solve(def, r.origin, r.pose, r.ik)
		local p = w[def.index.FootL].Position
		if a then
			nearV(p, a, 0.03, "stance foot moved at " .. t)
		end
		a = p
	end
	local cs = Gait.contacts(params, 0, 2)
	assert(#cs == 4 and cs[1].foot == "L" and cs[2].foot == "R", "contacts")
end)

test("hair deterministic and rooted", function()
	local p = { wind = Vector3.new(1, 0, 0), lift = Vector3.new(0, 0.5, 0), turbulence = 0.4, freq = 1, scale = 0.3 }
	local rest = MathX.axisX(Vector3.new(0, 1, 0), Vector3.new(0, 1, 0))
	local a = Hair.pointCFrame(rest, 0.7, 3.1, 2.5, p)
	local b = Hair.pointCFrame(rest, 0.7, 3.1, 2.5, p)
	nearV(a.Position, b.Position, 1e-9, "deterministic")
	local r = Hair.displace(Vector3.new(0, 1, 0), 0, 3.1, 2.5, p)
	nearV(r, Vector3.zero, 1e-9, "root fixed")
end)

local ok, Sequence = pcall(Loader.load, "src/shared/Sequence/Sequence")
if ok then
	test("sequence evaluates everywhere", function()
		local d = Sequence.duration()
		assert(d > 5, "duration")
		local t = 0
		while t <= d do
			local f = Sequence.evaluate(t)
			assert(f.camera and f.camera.cf and f.camera.fov > 1 and f.camera.fov < 120, "camera @" .. t)
			for name, cs in f.chars do
				assert(cs.origin and cs.pose, name .. " state @" .. t)
			end
			t += 0.25
		end
		local ev = Sequence.events()
		for i = 2, #ev do
			assert(ev[i].t >= ev[i - 1].t, "events sorted")
		end
		local marks = Sequence.shotMarks()
		assert(#marks >= 3, "shots")
		local m = Sequence.menuFrame(3.3)
		assert(m.camera.cf, "menu frame")
	end)
else
	print("(Sequence not ready: " .. tostring(Sequence) .. ")")
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
