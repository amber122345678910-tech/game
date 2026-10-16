--!strict
-- Атмосфера по времени: туман, свет, цветокоррекция, свечение; параметры эффектов; интерфейс (затемнения,
-- кинорамка, субтитры, титры). Цвета — из палитры, снятой с кадров ролика.

local Shared = script.Parent.Parent
local MathX = require(Shared.Math)
local Track = require(Shared.Track)
local Types = require(script.Parent.Types)
local Timing = require(script.Parent.Timing)

local Atmos = {}
local T = Timing

local function c(hex: string): Color3
	local s = string.gsub(hex, "#", "")
	return Color3.fromRGB(tonumber(string.sub(s, 1, 2), 16) or 0, tonumber(string.sub(s, 3, 4), 16) or 0, tonumber(string.sub(s, 5, 6), 16) or 0)
end

local function n(keys: { { number } }): { Track.Key<number> }
	local out = {}
	for i, k in keys do
		out[i] = { t = k[1], v = k[2] }
	end
	return out
end

-- Плотность Atmosphere: в дыму очень плотно, редеет, когда Рика выходит; наверху у Рю — дымка
local fogDensity = n({ { 0, 0.64 }, { 3.0, 0.63 }, { 6.5, 0.55 }, { 9.5, 0.45 }, { T.aEnd, 0.42 } })
local fogHaze = n({ { 0, 2.6 }, { 6.0, 2.4 }, { T.aEnd, 2.1 } })
local wispsKeys = n({ { 0, 1 }, { T.driftEnd, 0.9 }, { 7.5, 0.4 }, { T.aEnd, 0.3 } })
local nearKeys = n({ { 0, 1 }, { 3.5, 0.8 }, { T.driftEnd + 0.5, 0.25 }, { T.aEnd, 0.1 } })
local fogMulKeys = n({ { 0, 1.25 }, { 5.0, 1.15 }, { 9.0, 0.95 }, { T.aEnd, 0.9 } })
local blurKeys = n({ { 0, 3.5 }, { 2.0, 1.2 }, { 4.0, 0 } })

local A_FOG = c("#C1CBDF")
local A_DECAY = c("#8E9BC4")
local B_FOG = c("#C1CDDF")
local B_DECAY = c("#8695B6")
local C_FOG = c("#9AA7C8")
local C_DECAY = c("#5D709D")

function Atmos.env(t: number): Types.EnvState
	if t < T.bStart then
		return {
			fogDensity = Track.number(fogDensity, t),
			fogOffset = 0.22,
			fogHaze = Track.number(fogHaze, t),
			fogGlare = 0.25,
			fogColor = A_FOG,
			fogDecay = A_DECAY,
			exposure = 0.3,
			brightness = 2.0,
			ambient = c("#7A82A6"),
			outdoorAmbient = c("#A9B1D2"),
			tint = c("#E6EAFF"),
			saturation = -0.12,
			contrast = 0.05,
			ccBrightness = 0.02,
			bloomIntensity = 0.55,
			bloomSize = 34,
			bloomThreshold = 1.05,
			sunRays = 0.03,
			blur = Track.number(blurKeys, t),
			wind = Vector3.new(7, 0.4, -2.5),
		}
	end
	if t < T.cStart then
		return {
			fogDensity = 0.3,
			fogOffset = 0.05,
			fogHaze = 1.3,
			fogGlare = 0.3,
			fogColor = B_FOG,
			fogDecay = B_DECAY,
			exposure = 0.12,
			brightness = 2.6,
			ambient = c("#7F86AA"),
			outdoorAmbient = c("#AEB6D8"),
			tint = c("#F0F2FF"),
			saturation = 0.02,
			contrast = 0.1,
			ccBrightness = 0.01,
			bloomIntensity = 0.5,
			bloomSize = 28,
			bloomThreshold = 1.15,
			sunRays = 0.06,
			blur = 0,
			wind = Vector3.new(16, 1.2, -7),
		}
	end
	-- крупный план: вспышка энергии высвечивает кадр
	local flash = MathX.window(t, T.zing - 0.02, T.zing + 0.9, 0.04, 0.8)
	local glow = MathX.window(t, T.tipGlow, T.crackleOut, 0.3, 0.6)
	return {
		fogDensity = 0.26,
		fogOffset = 0.02,
		fogHaze = 1.0,
		fogGlare = 0.2,
		fogColor = C_FOG,
		fogDecay = C_DECAY,
		exposure = 0.1 + 0.35 * flash,
		brightness = 2.5,
		ambient = c("#7C82A8"):Lerp(c("#5FA9C4"), 0.35 * flash),
		outdoorAmbient = c("#A3ABD0"),
		tint = c("#EEF2FF"):Lerp(c("#D8F6FF"), 0.6 * flash),
		saturation = 0.04 + 0.12 * flash,
		contrast = 0.14 + 0.08 * flash,
		ccBrightness = 0.0 + 0.05 * flash,
		bloomIntensity = 0.5 + 0.5 * glow + 1.8 * flash,
		bloomSize = 30 + 18 * flash,
		bloomThreshold = 1.1 - 0.3 * flash,
		sunRays = 0.04,
		blur = 0,
		wind = Vector3.new(12, 1, -5),
	}
end

function Atmos.fx(t: number): { [string]: number }
	local fx: { [string]: number } = {}
	if t < T.bStart then
		fx.fog = Track.number(fogMulKeys, t)
		fx.fog_bank = 1
		fx.fog_ground = 1
		fx.fog_high = 0.6
		fx.fog_sky = 1
		fx.wisps = Track.number(wispsKeys, t)
		fx.wispsNear = Track.number(nearKeys, t)
		-- глаз: вспыхивает в дыму и тлеет с лёгкой пульсацией
		local on = MathX.smoothstep(MathX.progress(t, T.eyeOn - 0.1, T.eyeOn + 0.5))
		local pulse = 0.85 + 0.15 * math.sin(t * 5.3) * math.sin(t * 1.7)
		fx.eyeGlow = on * pulse + 0.6 * MathX.window(t, T.eyeOn - 0.05, T.eyeOn + 0.8, 0.05, 0.7)
	else
		fx.fog = 0.75
		fx.fog_bank = 0.8
		fx.fog_ground = 1
		fx.fog_high = 1
		fx.fog_sky = 1
		fx.wisps = 0
		fx.wispsNear = 0
		fx.eyeGlow = 0
	end
	-- энергия: кончик помпадура -> нарастание -> вспышка -> гаснет справа налево
	local tip = MathX.smoothstep(MathX.progress(t, T.tipGlow, T.tipGlow + 0.3)) * 0.18
	local charge = MathX.smoothstep(MathX.progress(t, T.charge, T.zing)) * 0.35
	local burst = MathX.window(t, T.zing - 0.03, T.crackleOut, 0.03, T.crackleOut - T.settle)
	fx.energy = math.clamp((tip + charge) * (if t < T.zing then 1 else 0) + burst * 1.0, 0, 1)
	fx.energyFlash = MathX.window(t, T.zing - 0.02, T.zing + 0.6, 0.03, 0.55)
	return fx
end

local SUBTITLE = "Ну что ж…"

function Atmos.ui(t: number): Types.UIState
	local fadeIn = 1 - MathX.smoothstep(MathX.progress(t, T.fadeInStart, T.fadeInEnd))
	local fadeOut = MathX.smoothstep(MathX.progress(t, T.fadeOutStart, T.cEnd))
	local captionA = MathX.window(t, T.cEnd + 0.5, T.outroEnd - 0.2, 0.7, 0.9)
	return {
		fade = math.max(fadeIn, fadeOut),
		flash = 0.42 * MathX.window(t, T.zing - 0.02, T.zing + 0.4, 0.03, 0.36),
		letterbox = 0.085,
		subtitle = SUBTITLE,
		subtitleAlpha = MathX.window(t, T.subtitleIn, T.subtitleOut, 0.25, 0.45),
		caption = "ЭТАП 1  ·  ИЗ ТУМАНА",
		captionAlpha = captionA,
		speedLines = MathX.window(t, T.zing - 0.02, T.zing + 0.45, 0.03, 0.4),
	}
end

return Atmos
