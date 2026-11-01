--!strict
-- Map strings (signs, boards, prompts and plates built by Shared/Maps/* + Controllers/LobbyController).
-- Lune-safe. Every key starts with "maps." and has en + ru. Map builders store the key on the TextLabel /
-- ProximityPrompt (attributes TextKey / ActionTextKey / ObjectTextKey) so clients re-localise them.
return {
	-- Lobby: Last Star Haven -----------------------------------------------------------------------------
	["maps.lobby.welcome"] = { en = "LAST STAR HAVEN", ru = "ПРИЮТ ПОСЛЕДНЕЙ ЗВЕЗДЫ" },
	["maps.lobby.shop.sign"] = { en = "DAILY SHOP", ru = "ЛАВКА ДНЯ" },
	["maps.lobby.shop.action"] = { en = "Browse", ru = "Смотреть" },
	["maps.lobby.shop.object"] = { en = "Daily Shop", ru = "Лавка дня" },
	["maps.lobby.quests.sign"] = { en = "QUEST BOARD", ru = "ДОСКА ЗАДАНИЙ" },
	["maps.lobby.quests.action"] = { en = "Read", ru = "Читать" },
	["maps.lobby.quests.object"] = { en = "Quest Board", ru = "Доска заданий" },
	["maps.lobby.portal.sign"] = { en = "PRACTICE", ru = "ТРЕНИРОВКА" },
	["maps.lobby.portal.action"] = { en = "Practice vs bots", ru = "Тренировка с ботами" },
	["maps.lobby.portal.object"] = { en = "Practice Portal", ru = "Портал тренировки" },
	["maps.lobby.training.sign"] = { en = "TRAINING GROUNDS", ru = "ТРЕНИРОВОЧНАЯ ПЛОЩАДКА" },
	["maps.lobby.loadout.action"] = { en = "Choose your SOUL", ru = "Выбрать ДУШУ" },
	["maps.lobby.loadout.object"] = { en = "SOUL Gallery", ru = "Галерея ДУШ" },
	["maps.lobby.stage.sign"] = { en = "THE JUDGES", ru = "СУДЬИ" },
	["maps.lobby.board.wins"] = { en = "MOST WINS", ru = "БОЛЬШЕ ВСЕГО ПОБЕД" },
	["maps.lobby.board.level"] = { en = "HIGHEST LV", ru = "ВЫСШИЙ УР" },
	["maps.lobby.board.loading"] = { en = "Gathering verdicts...", ru = "Собираем приговоры..." },
	["maps.lobby.board.empty"] = { en = "---", ru = "---" },
	["maps.lobby.board.value.wins"] = { en = "{1} W", ru = "{1} П" },
	["maps.lobby.board.value.level"] = { en = "LV {1}", ru = "УР {1}" },
	["maps.lobby.notes.title"] = { en = "PATCH NOTES", ru = "ИЗМЕНЕНИЯ" },
	["maps.lobby.notes.body"] = {
		en = "v0.1 - THE FIRST TRIAL\n* Hall of Verdicts and Snowdin Crossroads\n* 3 monsters, 7 SOULs\n* Verdict Box, SAVE stars, Collapse\n* Daily shop, quests, mastery\nStay determined!",
		ru = "v0.1 - ПЕРВЫЙ СУД\n* Зал Приговоров и Перекрёсток Сноудина\n* 3 монстра, 7 ДУШ\n* Коробка Приговора, звёзды СОХРАНЕНИЯ, Обрушение\n* Лавка дня, задания, мастерство\nНе теряй решимости!",
	},
	["maps.lobby.podium.try"] = { en = "Try on", ru = "Примерить" },
	["maps.lobby.plate.monster"] = { en = "MONSTER", ru = "МОНСТР" },
	["maps.lobby.plate.human"] = { en = "SOUL", ru = "ДУША" },

	-- Snowdin Crossroads -----------------------------------------------------------------------------------
	["maps.snowdin.sign.square"] = { en = "Town Square", ru = "Площадь" },
	["maps.snowdin.sign.pond"] = { en = "Frozen Pond", ru = "Замёрзший пруд" },
	["maps.snowdin.sign.bridge"] = { en = "Old Bridge", ru = "Старый мост" },
	["maps.snowdin.sign.forest"] = { en = "Pine Woods", ru = "Сосновый лес" },
	["maps.snowdin.sign.sentry"] = { en = "Sentry Post", ru = "Пост часового" },
	["maps.snowdin.shop"] = { en = "SHOP", ru = "ЛАВКА" },
	["maps.snowdin.inn"] = { en = "INN", ru = "ГОСТИНИЦА" },
	["maps.snowdin.bakery"] = { en = "BAKERY", ru = "ПЕКАРНЯ" },
	["maps.snowdin.sentry"] = { en = "SENTRY POST", ru = "ПОСТ ЧАСОВОГО" },
	["maps.snowdin.sentry.note"] = { en = "back in 5 min (maybe)", ru = "вернусь через 5 минут (наверное)" },
}
