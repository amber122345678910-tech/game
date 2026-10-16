--!strict
-- Этап 1: «Из тумана». Собирает кадр сцены в момент t (чистая функция времени) и список событий.
-- Кадры: A — дым, из него выходят Рика и Юта; B — Рю снизу на фоне облаков; C — крупно: помпадур и энергия.

local Shared = script.Parent.Parent
local MathX = require(Shared.Math)
local Track = require(Shared.Track)
local Gait = require(Shared.Anim.Gait)
local Types = require(script.Parent.Types)
local Timing = require(script.Parent.Timing)
local Actors = require(script.Parent.Actors)
local Cameras = require(script.Parent.Cameras)
local Atmos = require(script.Parent.Atmos)
local Layout = require(script.Parent.Layout)

local Sequence = {}
local T = Timing

export type Bed = { cue: string, keys: { Track.Key<number> }, speedKeys: { Track.Key<number> }? }
export type ShotMark = { name: string, title: string, start: number, finish: number }

local SHOTS: { ShotMark } = {
	{ name = "A", title = "Кадр 1 — дым, Рика и Юта", start = 0, finish = T.bStart },
	{ name = "B", title = "Кадр 2 — Рю на фоне облаков", start = T.bStart, finish = T.cStart },
	{ name = "C", title = "Кадр 3 — помпадур, энергия", start = T.cStart, finish = T.cEnd },
	{ name = "End", title = "Титр", start = T.cEnd, finish = T.outroEnd },
}

local rikaPulses = Actors.rikaPulses(0, T.aEnd)
local FOG_FILL = Color3.fromRGB(185, 195, 222)

function Sequence.duration(): number
	return T.outroEnd
end

function Sequence.shotMarks(): { ShotMark }
	return SHOTS
end

function Sequence.buildOrigin(name: string): CFrame
	return Actors.buildOrigin(name)
end

local function shotAt(t: number): (number, ShotMark)
	for i, s in SHOTS do
		if t < s.finish then
			return i, s
		end
	end
	return #SHOTS, SHOTS[#SHOTS]
end

local HIDDEN: Types.CharState = {
	visible = false,
	origin = CFrame.new(),
	pose = {},
	ik = nil,
	outline = 0,
	flutter = 0,
	hair = nil,
}

function Sequence.evaluate(t: number): Types.Frame
	local index, shot = shotAt(t)
	local chars: { [string]: Types.CharState } = {}
	if shot.name == "A" then
		local rika = Actors.rika(t)
		local yuta = Actors.yuta(t)
		-- линии-контуры проступают, когда фигуры выходят из дыма
		local ol = MathX.smoothstep(MathX.progress(t, T.outlineOn, T.outlineFull))
		rika.outline = ol
		yuta.outline = ol
		-- в дыму фигуры — бледный силуэт цвета тумана (плоская заливка), потом проступают детали
		-- до появления силуэта фигуры почти полностью растворены в дыму
		local hidden = 1 - MathX.smoothstep(MathX.progress(t, T.silhouette - 1.2, T.silhouette + 0.8))
		local fogFill = 0.86 * (1 - MathX.ease("InQuad", MathX.progress(t, T.eyeOn - 0.4, T.outlineFull - 0.2))) + 0.12 * hidden
		rika.fill = fogFill
		rika.fillColor = FOG_FILL
		yuta.fill = 0.78 * (1 - MathX.ease("InQuad", MathX.progress(t, T.eyeOn - 0.6, T.outlineFull - 0.6))) + 0.2 * hidden
		yuta.fillColor = FOG_FILL
		chars.Rika = rika
		chars.Yuta = yuta
		chars.Ryu = HIDDEN
	elseif shot.name == "B" or shot.name == "C" then
		chars.Rika = HIDDEN
		chars.Yuta = HIDDEN
		chars.Ryu = Actors.ryu(t)
	else
		chars.Rika = HIDDEN
		chars.Yuta = HIDDEN
		chars.Ryu = Actors.ryu(T.cEnd)
	end
	local subject: number? = nil
	if shot.name == "A" then
		local cam = Cameras.evaluate(t, rikaPulses, nil)
		subject = (chars.Rika.origin.Position + Vector3.new(0, 7, 0) - cam.cf.Position).Magnitude
	end
	local camera = Cameras.evaluate(math.min(t, T.cEnd), rikaPulses, subject)
	return {
		t = t,
		shotIndex = index,
		shotName = shot.name,
		shotT = t - shot.start,
		camera = camera,
		chars = chars,
		env = Atmos.env(t),
		fx = Atmos.fx(t),
		ui = Atmos.ui(t),
	}
end

-- Фон стартового меню: Рика и Юта стоят в тумане, камера медленно облетает
function Sequence.menuFrame(clock: number): Types.Frame
	local at = CFrame.new(Layout.rikaTo + Vector3.new(0, 0, 4))
	local yutaAt = CFrame.new(Layout.yutaTo + Vector3.new(0, 0, 4))
	local camera = Cameras.menu(clock, at.Position)
	local env = Atmos.env(8.5)
	env.blur = 0
	local fx = Atmos.fx(9)
	fx.wisps = 0.5
	fx.wispsNear = 0.15
	fx.eyeGlow = 0.85 + 0.15 * math.sin(clock * 2.1)
	local ui = Atmos.ui(5)
	ui.fade = 0
	ui.subtitleAlpha = 0
	ui.captionAlpha = 0
	ui.letterbox = 0
	return {
		t = clock,
		shotIndex = 0,
		shotName = "Menu",
		shotT = clock,
		camera = camera,
		chars = {
			Rika = Actors.rikaIdle(clock, at),
			Yuta = Actors.yutaIdle(clock, yutaAt),
			Ryu = HIDDEN,
		},
		env = env,
		fx = fx,
		ui = ui,
	}
end

------------------------------------------------------------------------------------------
-- Звук и разовые эффекты
------------------------------------------------------------------------------------------

local function bed(cue: string, keys: { { number } }): Bed
	local k: { Track.Key<number> } = {}
	for i, p in keys do
		k[i] = { t = p[1], v = p[2], ease = if i > 1 then "InOutSine" else nil }
	end
	return { cue = cue, keys = k }
end

local BEDS: { Bed } = {
	-- ветер: громкий порыв вместе с хвостом взрыва, потом ровный фон; наверху у Рю — сильнее
	bed("wind_bed", { { 0, 1.8 }, { 1.3, 1.8 }, { 2.3, 1.0 }, { T.aEnd - 0.05, 1.0 }, { T.bStart, 1.5 }, { T.cStart - 0.05, 1.5 }, { T.cStart, 0.9 }, { T.fadeOutStart, 0.9 }, { T.cEnd + 0.6, 0 } }),
	-- гул клубящегося дыма — только в кадре A
	bed("rumble_bed", { { 0, 1.0 }, { T.aEnd - 0.4, 0.85 }, { T.aEnd, 0 } }),
	-- музыка: вступает, когда в дыму появляется силуэт; обрывается на смене кадра; нарастает к вспышке
	bed("tension_music", { { 2.8, 0 }, { 6.0, 0.7 }, { T.aEnd - 0.1, 1.0 }, { T.bStart, 0.45 }, { T.cStart, 0.45 }, { T.charge, 0.8 }, { T.zing, 1.0 }, { T.settle, 0.55 }, { T.fadeOutStart, 0.4 }, { T.cEnd + 1.2, 0 } }),
	-- куртка треплется на ветру
	bed("coat_flap", { { T.bStart - 0.01, 0 }, { T.bStart, 1.0 }, { T.cStart - 0.01, 1.0 }, { T.cStart, 0.5 }, { T.fadeOutStart, 0.45 }, { T.cEnd, 0 } }),
	bed("fur_rustle", { { T.bStart - 0.01, 0 }, { T.bStart, 0.8 }, { T.cStart - 0.01, 0.8 }, { T.cStart, 0.55 }, { T.fadeOutStart, 0.5 }, { T.cEnd, 0 } }),
	-- треск энергии: от кончика помпадура к вспышке и затухание
	bed("electric_crackle_loop", { { T.tipGlow - 0.05, 0 }, { T.tipGlow + 0.25, 0.35 }, { T.zing - 0.05, 0.75 }, { T.zing + 0.05, 1.0 }, { T.settle, 0.6 }, { T.crackleOut + 0.1, 0 } }),
}

function Sequence.beds(): { Bed }
	return BEDS
end

local EVENTS: { Types.Event } = {}
local function ev(t: number, kind: string, name: string, args: { [string]: any }?)
	table.insert(EVENTS, { t = t, kind = kind, name = name, args = args })
end

-- Кадр A: хвост взрыва, клубы дыма мимо камеры, осыпь, далёкое обрушение
ev(0.0, "sound", "blast_aftermath")
ev(0.15, "sound", "fog_whoosh")
ev(1.25, "sound", "fog_whoosh", { volume = 0.9 })
ev(2.7, "sound", "fog_whoosh", { volume = 0.75 })
ev(4.3, "sound", "fog_whoosh", { volume = 0.55 })
ev(0.6, "sound", "debris_settle")
ev(2.2, "sound", "distant_crumble")
-- тяжёлые толчки Рики: громче по мере приближения; пыль от массы, когда её уже видно
for i, p in rikaPulses do
	local near = MathX.smoothstep(MathX.progress(p.t, 0.5, T.aEnd))
	ev(p.t, "sound", "giant_footstep", { volume = 0.35 + 0.65 * near, speed = 0.92 + 0.04 * ((i % 3) - 1) })
	ev(p.t + 0.02, "sound", "step_debris", { volume = 0.3 + 0.6 * near })
	if i % 2 == 0 then
		ev(p.t, "sound", "ground_tremor", { volume = 0.3 + 0.5 * near, cut = 1.5 })
	end
	if p.t > 3.5 then
		ev(p.t + 0.03, "fx", "stepDust", { char = "Rika", foot = p.side, scale = 0.8 + 0.5 * near })
	end
end
-- шаги Юты: слышны, когда он близко
for _, c in Gait.contacts(Actors.yutaGait, 0, T.aEnd) do
	local near = MathX.smoothstep(MathX.progress(c.t, 4, T.aEnd))
	if near > 0.05 then
		ev(c.t, "sound", "human_footstep_gravel", { volume = 0.15 + 0.5 * near })
	end
end
-- пик "звона" наступает через ~0.6 с после начала файла — совпадает со вспышкой глаза
ev(T.eyeOn - 0.6, "sound", "eye_glint")
ev(T.eyeOn + 1.4, "sound", "creature_breath", { volume = 0.7 })
ev(10.2, "sound", "creature_breath", { volume = 1.0 })

-- Кадр B
ev(T.bStart, "sound", "sting_hit")
ev(T.bStart + 0.25, "sound", "coat_swish", { volume = 0.8 })
ev(T.armsUp + 0.05, "sound", "coat_swish", { volume = 1.0 })
-- хлопок ладоней по помпадуру (в ролике 4.745 с)
ev(T.handsOnHair - 0.02, "sound", "hand_grab")
ev(T.handsOnHair, "sound", "hair_slick", { volume = 0.7 })

-- Кадр C
ev(T.cStart + 0.1, "sound", "hair_slick")
ev(T.cStart + 1.0, "sound", "hair_slick", { volume = 0.9 })
ev(T.cStart + 0.3, "sound", "heartbeat", { volume = 0.8 })
-- нарастание: пик звука (1.43 с от начала файла) совпадает со вспышкой
ev(T.zing - 1.35, "sound", "energy_charge")
ev(T.zing, "sound", "electric_zing")
ev(T.zing, "fx", "zingBurst")
ev(T.settle - 0.15, "sound", "hair_slick", { volume = 0.8 })
-- финальный титр
ev(T.cEnd + 0.4, "sound", "sting_hit", { volume = 0.55 })

table.sort(EVENTS, function(a: Types.Event, b: Types.Event)
	return a.t < b.t
end)

function Sequence.events(): { Types.Event }
	return EVENTS
end

return Sequence
