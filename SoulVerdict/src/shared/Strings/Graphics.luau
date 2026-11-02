--!strict
-- Strings for graphics: settings labels, quality tiers, ambient weather names, Style Lab helpers. Lune-safe.
-- Preset names/descriptions live in Graphics/Presets.luau (Name/Desc) and rig style names in
-- Rigs/RigStyles.luau (RigStyles.Get(id).Name/Desc) — show them with Strings.Pick.
return {
	["graphics.title"] = { en = "Graphics", ru = "Графика" },
	["graphics.preset"] = { en = "Lighting preset", ru = "Пресет освещения" },
	["graphics.preset.mapDefault"] = { en = "Map default", ru = "Как на карте" },
	["graphics.preset.mapDefault.desc"] = {
		en = "Use each map's own lighting (recommended).",
		ru = "Своё освещение у каждой карты (рекомендуется).",
	},
	["graphics.preset.active"] = { en = "Now showing: {1}", ru = "Сейчас: {1}" },
	["graphics.group.Map"] = { en = "Map looks", ru = "Облик карт" },
	["graphics.group.Style"] = { en = "Styles", ru = "Стили" },
	["graphics.group.Special"] = { en = "Special", ru = "Особые" },
	["graphics.group.Final"] = { en = "Phase 2", ru = "Фаза 2" },

	["graphics.quality"] = { en = "Effects quality", ru = "Качество эффектов" },
	["graphics.quality.desc"] = {
		en = "Auto follows your Roblox graphics level and frame rate.",
		ru = "«Авто» учитывает уровень графики Roblox и частоту кадров.",
	},
	["graphics.quality.Auto"] = { en = "Auto", ru = "Авто" },
	["graphics.quality.Low"] = { en = "Low", ru = "Низкое" },
	["graphics.quality.Medium"] = { en = "Medium", ru = "Среднее" },
	["graphics.quality.High"] = { en = "High", ru = "Высокое" },
	["graphics.quality.Ultra"] = { en = "Ultra", ru = "Ультра" },
	["graphics.quality.current"] = { en = "Current: {1}", ru = "Сейчас: {1}" },
	["graphics.fps"] = { en = "{1} FPS", ru = "{1} к/с" },

	["graphics.particles"] = { en = "Particle density", ru = "Плотность частиц" },
	["graphics.particles.desc"] = {
		en = "Weather and ambient particles: snow, embers, dust and more.",
		ru = "Погода и частицы окружения: снег, искры, пыль и другое.",
	},
	["graphics.reducedMotion"] = {
		en = "Reduce Motion is on (Roblox setting): calmer particles and effects.",
		ru = "Включено «Уменьшить движение» (настройка Roblox): частицы и эффекты спокойнее.",
	},

	["graphics.weather"] = { en = "Weather", ru = "Погода" },
	["graphics.weather.none"] = { en = "None", ru = "Нет" },
	["graphics.weather.Snow"] = { en = "Snowfall", ru = "Снегопад" },
	["graphics.weather.Blizzard"] = { en = "Blizzard", ru = "Метель" },
	["graphics.weather.Embers"] = { en = "Embers", ru = "Искры" },
	["graphics.weather.Ash"] = { en = "Falling ash", ru = "Пепел" },
	["graphics.weather.Dust"] = { en = "Dust motes", ru = "Пылинки" },
	["graphics.weather.Fireflies"] = { en = "Fireflies", ru = "Светлячки" },
	["graphics.weather.Spores"] = { en = "Echo spores", ru = "Споры эха" },
	["graphics.weather.VoidMotes"] = { en = "Void motes", ru = "Частицы пустоты" },
	["graphics.weather.RiftMotes"] = { en = "Rift motes", ru = "Частицы разлома" },
	["graphics.weather.Glimmer"] = { en = "Glimmer", ru = "Мерцание" },
	["graphics.weather.Rain"] = { en = "Rain", ru = "Дождь" },

	["graphics.rigStyle"] = { en = "Character style", ru = "Стиль персонажей" },
	["graphics.styleLab.preview"] = { en = "Preview preset", ru = "Предпросмотр пресета" },
	["graphics.styleLab.clear"] = { en = "Back to normal", ru = "Вернуть как было" },
	["graphics.styleLab.lightingNote"] = {
		en = "Lighting style (Realistic / Soft) can only be changed in Studio: Lighting > LightingStyle.",
		ru = "Стиль освещения (Realistic / Soft) меняется только в Studio: Lighting > LightingStyle.",
	},
}
