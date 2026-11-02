--!strict
-- Settings screen strings (src/client/UI/Screens/Settings). Lune-safe.
return {
	["set.title"] = { en = "Settings", ru = "Настройки" },
	["set.subtitle"] = { en = "Saved to your profile, applied instantly", ru = "Сохраняются в профиле и применяются сразу" },
	["set.section.graphics"] = { en = "Graphics", ru = "Графика" },
	["set.section.interface"] = { en = "Interface", ru = "Интерфейс" },
	["set.section.audio"] = { en = "Audio", ru = "Звук" },
	["set.section.camera"] = { en = "Camera & controls", ru = "Камера и управление" },
	["set.section.characters"] = { en = "Characters", ru = "Персонажи" },

	["set.GraphicsPreset"] = { en = "Lighting preset", ru = "Пресет освещения" },
	["set.GraphicsQuality"] = { en = "Quality", ru = "Качество" },
	["set.ParticleDensity"] = { en = "Particles", ru = "Частицы" },
	["set.MenuTheme"] = { en = "Menu theme", ru = "Тема меню" },
	["set.HudStyle"] = { en = "HUD style", ru = "Стиль HUD" },
	["set.Language"] = { en = "Language", ru = "Язык" },
	["set.DamageNumbers"] = { en = "Damage numbers", ru = "Числа урона" },
	["set.RigStyle"] = { en = "Character style", ru = "Стиль персонажей" },
	["set.MusicVolume"] = { en = "Music", ru = "Музыка" },
	["set.SfxVolume"] = { en = "Effects", ru = "Эффекты" },
	["set.CameraShake"] = { en = "Camera shake", ru = "Тряска камеры" },
	["set.FieldOfView"] = { en = "Field of view", ru = "Поле зрения" },
	["set.Sensitivity"] = { en = "Sensitivity", ru = "Чувствительность" },
	["set.CameraLock"] = { en = "Shoulder lock", ru = "Фиксация камеры" },
	["set.InvertY"] = { en = "Invert camera Y", ru = "Инверсия камеры по Y" },
	["set.QuickCast"] = { en = "Quick cast", ru = "Быстрое применение" },
	["set.ColorblindPatterns"] = { en = "Colorblind aid", ru = "Для дальтоников" },
	["set.ReducedFlashes"] = { en = "Reduced flashes", ru = "Меньше вспышек" },
	["set.desc.ColorblindPatterns"] = {
		en = "Blue and orange attacks also get stripes and dots, so the colour is never the only clue.",
		ru = "Синие и оранжевые атаки получают полосы и точки — цвет больше не единственная подсказка.",
	},
	["set.desc.ReducedFlashes"] = {
		en = "Softer screen flashes and blaster glare for sensitive eyes.",
		ru = "Мягче вспышки экрана и блики бластеров для чувствительных глаз.",
	},
	["set.previewTitle"] = { en = "Now showing", ru = "Сейчас" },

	["set.preset.MapDefault"] = { en = "Map default", ru = "Как у карты" },
	["set.quality.Auto"] = { en = "Auto", ru = "Авто" },
	["set.quality.Low"] = { en = "Low", ru = "Низкое" },
	["set.quality.Medium"] = { en = "Medium", ru = "Среднее" },
	["set.quality.High"] = { en = "High", ru = "Высокое" },
	["set.quality.Ultra"] = { en = "Ultra", ru = "Ультра" },
	["set.lang.auto"] = { en = "Automatic", ru = "Автоматически" },

	["set.desc.GraphicsPreset"] = {
		en = "Each hall has its own lighting. Pick one you like everywhere, or follow the map.",
		ru = "У каждого зала своё освещение. Выбери любимое для всех карт или оставь как у карты.",
	},
	["set.desc.GraphicsQuality"] = {
		en = "Auto lowers effects when the frame rate drops and raises them back when it recovers.",
		ru = "Авто снижает эффекты при падении FPS и возвращает их, когда всё снова плавно.",
	},
	["set.desc.ParticleDensity"] = {
		en = "Snow, embers, sparks and ability particles. Lower it on older devices.",
		ru = "Снег, искры, угли и частицы способностей. Уменьши на слабых устройствах.",
	},
	["set.desc.MenuTheme"] = {
		en = "Changes every menu instantly. The game plays the same in every theme.",
		ru = "Мгновенно меняет все меню. Игра от темы не меняется.",
	},
	["set.desc.HudStyle"] = {
		en = "Battle: the classic battle-box bars. Modern: slim glassy bars.",
		ru = "Боевой: классические полосы в рамке. Современный: тонкие стеклянные полосы.",
	},
	["set.desc.RigStyle"] = {
		en = "How characters are drawn on your screen: outlines, soft fabric or extra glow.",
		ru = "Как персонажи выглядят у тебя: с контуром, мягкой тканью или ярким свечением.",
	},
	["set.desc.Sensitivity"] = {
		en = "Camera turn speed for mouse, touch and gamepad.",
		ru = "Скорость поворота камеры для мыши, касаний и геймпада.",
	},
	["set.desc.InvertY"] = {
		en = "Moving the mouse or stick up looks down, like a flight stick.",
		ru = "Мышь или стик вверх — взгляд вниз, как у штурвала.",
	},
	["set.desc.QuickCast"] = {
		en = "On: abilities fire on press. Off: hold to aim with a preview, release to cast, Esc or right-click cancels.",
		ru = "Вкл: умения срабатывают сразу. Выкл: держи для прицела с подсказкой, отпусти — применить, Esc/ПКМ — отмена.",
	},
	["set.desc.CameraLock"] = {
		en = "Start every round with the over-the-shoulder lock on. Toggle it any time in battle.",
		ru = "Начинать раунд с фиксацией камеры из-за плеча. Переключается в бою в любой момент.",
	},

	["set.reset"] = { en = "Reset to defaults", ru = "Сбросить" },
	["set.resetDone"] = { en = "Settings reset to defaults", ru = "Настройки сброшены" },
	["set.percent"] = { en = "{1}%", ru = "{1}%" },
	["set.degrees"] = { en = "{1}°", ru = "{1}°" },
	["set.mult"] = { en = "x{1}", ru = "x{1}" },
}
