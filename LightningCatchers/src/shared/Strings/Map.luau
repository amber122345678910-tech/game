--!strict
-- Английские переводы строк для игрока (ключ — русский исходник из кода). Глоссарий — в Strings/Shared.luau.
-- Таблички карты (tools/map, tools/gen_map.luau). Названия островов, «Магазин», «Коконы», «Подстанция»,
-- «Перезапуск», «Награды» — в Strings/Shared.luau и Strings/Server.luau.
return {
	-- Табло в хабе (заголовки ЗАГЛАВНЫМИ: LocUpper)
	["Лучшие ловцы"] = "Top Catchers",
	["Прогноз бури"] = "Storm Forecast",
	["Зал славы"] = "Hall of Fame",

	-- Киоски хаба
	["Галерея"] = "Gallery",
	["фульгуритов"] = "of Fulgurites",
	["sign::генератора"] = "Generator reboot",
	["каждый день"] = "every day",

	-- Таблички витринных коконов (имя кокона без слова «кокон»)
	["cocoon::Луговой"] = "Meadow",
	["cocoon::Ледяной"] = "Frost",
	["cocoon::Грозовой"] = "Storm",
}
