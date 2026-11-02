--!strict
-- Map strings for the wave-2 arenas SnowdinCrossroads and WaterfallGrotto. Lune-safe.
-- Names / descriptions (the map modules read their Name/Desc from here: one source of truth) and the
-- texts of their signs and plaques (builders store the key on the TextLabel attribute "TextKey" so
-- clients re-localise them). Every key starts with "maps." and has en + ru.
-- Shop / inn / bakery / sentry signs of the Snowdin map reuse the existing "maps.snowdin.*" keys (Maps.luau).
return {
	-- Snowdin Crossroads ------------------------------------------------------------------------------------
	["maps.crossroads.name"] = { en = "Snowdin Crossroads", ru = "Перекрёсток Сноудина" },
	["maps.crossroads.desc"] = {
		en = "A sleepy snow town square at night. Warm windows, cold verdicts.",
		ru = "Сонная заснеженная площадь ночью. Тёплые окна, холодные приговоры.",
	},
	["maps.crossroads.gate"] = { en = "SNOWDIN CROSSROADS", ru = "ПЕРЕКРЁСТОК СНОУДИНА" },
	["maps.crossroads.board"] = {
		en = "TOWN NOTICES\n* Skating on the pond at your own risk\n* Lost: one snowball. If found, keep it\n* Curfew: whenever the lamps go out",
		ru = "ОБЪЯВЛЕНИЯ\n* Катание на пруду - на свой страх и риск\n* Потерян снежок. Нашедшему - оставить себе\n* Комендантский час: когда погаснут фонари",
	},
	["maps.crossroads.sign.camp"] = { en = "Camp", ru = "Лагерь" },

	-- Waterfall Grotto ----------------------------------------------------------------------------------------
	["maps.grotto.name"] = { en = "Waterfall Grotto", ru = "Грот Водопадов" },
	["maps.grotto.desc"] = {
		en = "Glowing crystals and echo flowers in a cavern that remembers every word.",
		ru = "Светящиеся кристаллы и эхо-цветы в пещере, что помнит каждое слово.",
	},
	["maps.grotto.plaque"] = {
		en = "Speak softly. The flowers remember.",
		ru = "Говори тише. Цветы всё помнят.",
	},
	["maps.grotto.sign.falls"] = { en = "The Falls", ru = "Водопад" },
	["maps.grotto.sign.garden"] = { en = "Echo Garden", ru = "Сад эха" },
	["maps.grotto.sign.dock"] = { en = "Old Dock", ru = "Старый причал" },
}
