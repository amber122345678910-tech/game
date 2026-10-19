--!strict
-- Английские переводы строк для игрока (ключ — русский исходник из кода). Глоссарий — в Strings/Shared.luau.
-- Острова (UI/TeleportUI), настройки (UI/SettingsUI), «С возвращением!» (UI/WelcomeUI)
return {
	-- Острова («Острова», «Ты здесь», «Ты уже здесь!», «Открыт», «Открыть», «Закрыт», «Лететь», «Можно открыть»,
	-- «Не хватает ⚡ %s», «Сначала открой «%s»» — в Strings/ShopPets.luau; «Телепорт заряжается: ещё %d с» — в Strings/Server.luau)
	["Магазин, питомцы, награды"] = "Shop, pets, rewards",
	["Ещё %d с"] = "%ds left",
	["Сначала открой предыдущий"] = "Unlock the previous one first",

	-- Настройки
	["Настройки"] = "Settings",
	["Язык"] = "Language",
	["Музыка"] = "Music",
	["Звуки"] = "Sounds",
	["Мягкие вспышки"] = "Soft Flashes",
	["Тряска камеры"] = "Camera Shake",
	["ВКЛ"] = "ON",
	["ВЫКЛ"] = "OFF",
	["Задержка касания"] = "Tap Timing",
	["+%d мс"] = "+%d ms",
	["%d мс"] = "%d ms",
	["Подстроить автоматически"] = "Auto-Calibrate",
	["Не выходит ИДЕАЛЬНО? Поймай пару молний и нажми «Подстроить»."] = "No PERFECTs? Catch a few bolts, then tap Auto-Calibrate.",
	["Сначала поймай несколько молний!"] = "Catch a few bolts first!",
	["Задержка: %s"] = "Timing: %s",

	-- С возвращением («Забрать» — в Strings/Windows.luau)
	["С возвращением!"] = "Welcome back!",
	["Пока тебя не было, станция накопила"] = "While you were away, your station made",
}
