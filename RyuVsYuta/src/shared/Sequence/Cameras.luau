--!strict
-- Камера по кадрам: ключи позиции и точки взгляда (сглаженные сплайны), FOV, крен,
-- "ручная" тряска (фрактальный шум), удар на вспышке, фокус для глубины резкости.

local Shared = script.Parent.Parent
local MathX = require(Shared.Math)
local Track = require(Shared.Track)
local Types = require(script.Parent.Types)
local Timing = require(script.Parent.Timing)
local Layout = require(script.Parent.Layout)

local Cameras = {}
local T = Timing

type CamKey = { t: number, pos: Vector3, look: Vector3, fov: number, roll: number?, ease: string? }

local function track(keys: { CamKey }, field: string): { Track.Key<Vector3> }
	local out = {}
	for i, k in keys do
		out[i] = { t = k.t, v = (k :: any)[field], ease = k.ease }
	end
	return out
end

local function trackN(keys: { CamKey }, field: string, default: number): { Track.Key<number> }
	local out = {}
	for i, k in keys do
		local v = (k :: any)[field]
		out[i] = { t = k.t, v = if type(v) == "number" then v else default, ease = k.ease }
	end
	return out
end

type Compiled = { pos: { Track.Key<Vector3> }, look: { Track.Key<Vector3> }, fov: { Track.Key<number> }, roll: { Track.Key<number> } }

local function compile(keys: { CamKey }): Compiled
	return { pos = track(keys, "pos"), look = track(keys, "look"), fov = trackN(keys, "fov", 60), roll = trackN(keys, "roll", 0) }
end

------------------------------------------------------------------------------------------
-- Кадр A: сквозь дым к Рике и Юте. Камера низко, медленно плывёт вперёд, потом почти замирает,
-- а они выходят из тумана навстречу (как в ролике: фигуры почти неподвижны, редеет туман).
------------------------------------------------------------------------------------------
local shotA = compile({
	{ t = 0, pos = Vector3.new(2.2, 4.4, 14), look = Vector3.new(0.6, 6.0, 70), fov = 52, roll = 1.8 },
	{ t = 2.5, pos = Vector3.new(1.4, 3.6, 21.5), look = Vector3.new(0.2, 6.4, 66), fov = 47, roll = 0.8 },
	{ t = T.driftEnd, pos = Vector3.new(0.7, 2.9, 27.6), look = Vector3.new(-0.2, 6.6, 58), fov = 42, roll = -0.3 },
	-- дальше камера почти замирает (как в ролике с 2.97 с): низко, взгляд вверх ~14°, длинный фокус
	{ t = 7.5, pos = Vector3.new(0.45, 2.6, 28.9), look = Vector3.new(-0.35, 8.2, 52), fov = 42.5, roll = -0.1 },
	{ t = T.aEnd, pos = Vector3.new(0.4, 2.55, 29.2), look = Vector3.new(-0.45, 8.6, 47.5), fov = 42, roll = 0 },
})

------------------------------------------------------------------------------------------
-- Кадр B: Рю снизу на фоне облаков, ступни срезаны нижним краем, медленный наезд
------------------------------------------------------------------------------------------
local ryuBase = Layout.ryuSpot
local shotB = compile({
	-- неподвижная камера (в ролике план статичен), только едва заметный дрейф
	{ t = T.bStart, pos = ryuBase + Vector3.new(0.3, 1.05, 15.0), look = ryuBase + Vector3.new(0, 7.0, 0), fov = 49, roll = -1.0 },
	{ t = T.bEnd, pos = ryuBase + Vector3.new(0.27, 1.08, 14.75), look = ryuBase + Vector3.new(0, 7.05, 0), fov = 48.6, roll = -0.9 },
})

------------------------------------------------------------------------------------------
-- Кадр C: крупно снизу. Сначала помпадур "дулом" в объектив, на вспышке — лицо снизу
------------------------------------------------------------------------------------------
local shotC = compile({
	{ t = T.cStart, pos = ryuBase + Vector3.new(0.28, 5.05, 3.55), look = ryuBase + Vector3.new(0, 6.05, 0.3), fov = 42, roll = 1.5 },
	{ t = T.liftStart, pos = ryuBase + Vector3.new(0.22, 5.1, 3.25), look = ryuBase + Vector3.new(0, 6.15, 0.25), fov = 41, roll = 1.0 },
	{ t = T.headUp, pos = ryuBase + Vector3.new(0.2, 5.0, 3.05), look = ryuBase + Vector3.new(0, 6.25, 0.0), fov = 40, roll = 0.4, ease = "OutCubic" },
	{ t = T.cEnd, pos = ryuBase + Vector3.new(0.18, 5.05, 2.75), look = ryuBase + Vector3.new(0, 6.25, 0.0), fov = 38.5, roll = 0 },
})

-- Шум "ручной камеры": позиция (студы) и поворот (градусы)
local function handheld(t: number, amp: number, rotAmp: number, freq: number): CFrame
	local x = MathX.fbm(t * freq, 1.1, 3) * amp
	local y = MathX.fbm(t * freq, 2.3, 3) * amp
	local z = MathX.fbm(t * freq * 0.7, 3.7, 2) * amp * 0.5
	local rx = MathX.fbm(t * freq * 0.9, 4.9, 3) * rotAmp
	local ry = MathX.fbm(t * freq * 0.8, 6.1, 3) * rotAmp
	local rz = MathX.fbm(t * freq * 0.6, 7.3, 2) * rotAmp * 0.6
	return CFrame.new(x, y, z) * MathX.angles(rx, ry, rz)
end

-- Затухающий удар (вспышка энергии, тяжёлый шаг)
local function impulse(t: number, t0: number, amp: number, rotAmp: number, freq: number, decay: number): CFrame
	if t < t0 then
		return CFrame.new()
	end
	local d = t - t0
	local k = math.exp(-d * decay)
	local s = math.sin(d * freq * 2 * math.pi)
	local c = math.cos(d * freq * 2 * math.pi * 1.3)
	return CFrame.new(s * amp * k, c * amp * 0.7 * k, 0) * MathX.angles(c * rotAmp * k, s * rotAmp * 0.6 * k, s * rotAmp * 0.8 * k)
end

local function evalShot(c: Compiled, t: number): (CFrame, number, Vector3)
	local pos = Track.vector(c.pos, t)
	local look = Track.vector(c.look, t)
	local fov = Track.number(c.fov, t)
	local roll = Track.number(c.roll, t)
	local cf = MathX.lookAt(pos, look) * MathX.angles(0, 0, roll)
	return cf, fov, look
end

-- Тяжёлые толчки Рики слегка встряхивают камеру в кадре A
local function rikaThuds(t: number, pulses: { { t: number, side: string } }): CFrame
	local cf = CFrame.new()
	for _, p in pulses do
		if t >= p.t and t - p.t < 1.2 then
			-- ближе к концу кадра (Рика ближе) — сильнее
			local near = MathX.smoothstep(MathX.progress(p.t, 3, T.aEnd))
			cf = cf * impulse(t, p.t, 0.015 + 0.03 * near, 0.12 + 0.25 * near, 9, 6)
		end
	end
	return cf
end

function Cameras.evaluate(t: number, rikaPulses: { { t: number, side: string } }, subjectDist: number?): Types.CameraState
	if t < T.bStart then
		local cf, fov, look = evalShot(shotA, t)
		cf = cf * handheld(t, 0.09, 0.45, 0.45) * rikaThuds(t, rikaPulses)
		local dist = subjectDist or (look - cf.Position).Magnitude
		return {
			cf = cf,
			fov = fov,
			focusDist = dist,
			inFocus = 7,
			farBlur = 0.22,
			nearBlur = 0.35,
		}
	elseif t < T.cStart then
		local cf, fov, look = evalShot(shotB, t)
		cf = cf * handheld(t, 0.02, 0.18, 0.9)
		return {
			cf = cf,
			fov = fov,
			focusDist = (look - cf.Position).Magnitude,
			inFocus = 5,
			farBlur = 0.3,
			nearBlur = 0,
		}
	end
	local tc = math.min(t, T.cEnd)
	local cf, fov, look = evalShot(shotC, tc)
	cf = cf * handheld(t, 0.018, 0.22, 0.9) * impulse(t, T.zing, 0.05, 1.3, 16, 5.5)
	-- лёгкий "удар" FOV на вспышке
	fov -= 2.2 * MathX.window(t, T.zing - 0.02, T.zing + 0.5, 0.04, 0.45)
	return {
		cf = cf,
		fov = fov,
		focusDist = (look - cf.Position).Magnitude,
		inFocus = 1.3,
		farBlur = 0.6,
		nearBlur = 0,
	}
end

-- Фон стартового меню: медленный облёт вокруг Рики и Юты в тумане
function Cameras.menu(clock: number, center: Vector3): Types.CameraState
	local a = math.rad(200 + 14 * math.sin(clock * 0.05))
	local r = 19 + 1.5 * math.sin(clock * 0.07)
	local pos = center + Vector3.new(math.sin(a) * r, 4.2 + 0.6 * math.sin(clock * 0.09), math.cos(a) * r)
	local cf = MathX.lookAt(pos, center + Vector3.new(0, 7.6, 0)) * handheld(clock, 0.08, 0.4, 0.35)
	return { cf = cf, fov = 52, focusDist = r, inFocus = 8, farBlur = 0.3, nearBlur = 0.3 }
end

return Cameras
