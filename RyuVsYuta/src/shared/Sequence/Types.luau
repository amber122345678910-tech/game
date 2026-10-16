--!strict
-- Типы "кадра" катсцены. Кадр — полное описание сцены в момент t: его считает Sequence (чистая функция
-- времени, одинаково в Roblox и в превизе), а клиент только применяет.

local Rig = require(script.Parent.Parent.Rig)

local Types = {}

export type HairState = {
	wind: Vector3, -- мировое направление*сила ветра для прядей
	lift: Vector3, -- мировой "подъём" прядей
	turbulence: number,
	freq: number,
	scale: number,
}

export type CharState = {
	visible: boolean,
	origin: CFrame,
	pose: { [string]: CFrame },
	ik: { Rig.IKTarget }?,
	outline: number, -- 0..1 видимость аниме-контура
	fill: number?, -- 0..1 заливка цветом тумана (силуэт в дыму), nil = 0
	fillColor: Color3?,
	flutter: number, -- 0..1+ сила трепета ткани/меха
	hair: HairState?,
}

export type CameraState = {
	cf: CFrame,
	fov: number,
	focusDist: number, -- расстояние фокуса (DepthOfField)
	inFocus: number, -- ширина зоны резкости
	farBlur: number, -- 0..1
	nearBlur: number, -- 0..1
}

export type EnvState = {
	fogDensity: number, -- Atmosphere.Density
	fogOffset: number,
	fogHaze: number,
	fogGlare: number,
	fogColor: Color3,
	fogDecay: Color3,
	exposure: number,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	tint: Color3,
	saturation: number,
	contrast: number,
	ccBrightness: number,
	bloomIntensity: number,
	bloomSize: number,
	bloomThreshold: number,
	sunRays: number,
	blur: number,
	wind: Vector3, -- Workspace.GlobalWind (частицы, облака)
}

export type UIState = {
	fade: number, -- 0 — картинка видна, 1 — чёрный экран
	flash: number, -- 0..1 белая вспышка
	letterbox: number, -- доля высоты экрана под каждой полосой
	subtitle: string?,
	subtitleAlpha: number,
	caption: string?, -- титр (название этапа и т. п.)
	captionAlpha: number,
	speedLines: number?, -- 0..1 аниме-линии скорости по краям кадра (на вспышке)
}

export type Frame = {
	t: number,
	shotIndex: number,
	shotName: string,
	shotT: number,
	camera: CameraState,
	chars: { [string]: CharState },
	env: EnvState,
	fx: { [string]: number }, -- непрерывные параметры эффектов (густота тумана у камеры, энергия и т. д.)
	ui: UIState,
}

-- Разовое событие на таймлайне: звук, всплеск частиц и т. п.
export type Event = {
	t: number,
	kind: string, -- "sound" | "fx"
	name: string,
	args: { [string]: any }?,
}

return Types
