--!strict
-- Английские переводы строк для игрока (ключ — русский исходник из кода). Глоссарий — в Strings/Shared.luau.
return {
	-- Общие ответы сервера
	["Данные ещё загружаются"] = "Data is still loading",
	["Сначала открой остров «%s»"] = "Unlock %s first",

	-- EconomyService: банка, покупки, перезапуск, телепорт
	["Не хватает Вольт"] = "Not enough Volts",
	["Банка полна! Сдай заряд ⚡"] = "Jar full! Go sell your charge ⚡",
	["Неизвестное улучшение"] = "Unknown upgrade",
	["Уже максимальный уровень"] = "Already max level",
	["Нет такого острова"] = "No such island",
	["Остров уже открыт"] = "Island already unlocked",
	["Сначала открой предыдущий остров"] = "Unlock the previous island first",
	["Дрон уже куплен"] = "You already have the drone",
	["Дрон откроется с острова «%s»"] = "The drone unlocks at %s",
	["Сначала купи дрон"] = "Buy the drone first",
	["Нужно %s ⚡"] = "Need %s ⚡",
	["♻ Генератор перезапущен! %s теперь ×%s"] = "♻ Rebirth! %s is now ×%s",
	["Ты уже в городе"] = "You're already in the Hub",
	["Ты уже на этом острове"] = "You're already on this island",
	["Телепорт заряжается: ещё %d с"] = "Teleport recharging: %ds left",

	-- EventService: события
	["⚡ Суперячейка"] = "⚡ Supercell",
	["🔮 Шаровая молния"] = "🔮 Ball Lightning",
	["🌈 Радужная молния"] = "🌈 Rainbow Lightning",
	["%s через %d с!"] = "%s in %ds!",
	["%s и ещё %d"] = "%s and %d more",
	["⚡ СУПЕРЯЧЕЙКА! Молнии чаще и дороже!"] = "⚡ SUPERCELL! More bolts, bigger payouts!",
	["Суперячейка закончилась — до следующей!"] = "The Supercell is over — see you next time!",
	["🔮 ШАРОВАЯ МОЛНИЯ над островом «%s»! Ловите её кольца вместе!"] = "🔮 BALL LIGHTNING over %s! Catch its rings together!",
	["🔮 Шаровая молния повержена!"] = "🔮 Ball Lightning defeated!",
	["🔮 Шаровая молния повержена! +%s ⚡ +%s 💎"] = "🔮 Ball Lightning defeated! +%s ⚡ +%s 💎",
	["🔮 Шаровая молния ушла..."] = "🔮 Ball Lightning got away...",
	["Шаровая молния ушла… Утешительный приз: +%s ⚡"] = "Ball Lightning got away… Consolation prize: +%s ⚡",
	["🔮 Шаровая молния не нашла ловцов — все в городе"] = "🔮 Ball Lightning found no catchers — everyone's in the Hub",
	["🌈 РАДУЖНАЯ МОЛНИЯ НАДВИГАЕТСЯ! Ударит на каждом острове с ловцами!"] = "🌈 RAINBOW LIGHTNING INCOMING! It'll strike every island with catchers!",
	["🌈 Беги на остров — через %d с там ударит Радужная молния!"] = "🌈 Run to an island — Rainbow Lightning strikes in %ds!",
	["🌈 Радужная молния твоя! +%s ⚡"] = "🌈 The Rainbow Lightning is yours! +%s ⚡",
	["🌈 Радужную молнию поймали: %s!"] = "🌈 Rainbow Lightning caught by %s!",
	["🌈 Радужная молния ушла... В следующий раз!"] = "🌈 Rainbow Lightning got away... Next time!",
	["☠ ЧЁРНАЯ МОЛНИЯ ПЕРУНА бьёт рядом с %s!"] = "☠ PERUN'S BLACK LIGHTNING strikes near %s!",
	["☠ Чёрная молния Перуна бьёт рядом с %s!"] = "☠ Perun's Black Lightning strikes near %s!",
	["☠ Чёрная молния Перуна поймана! Ловец: %s"] = "☠ Perun's Black Lightning caught! Catcher: %s",
	["☠ Я видел Чёрную молнию! +%s ⚡"] = "☠ I saw the Black Lightning! +%s ⚡",
	["☠ Чёрная молния Перуна ушла в землю — в другой раз!"] = "☠ Perun's Black Lightning hit the ground — maybe next time!",

	-- StrikeService
	["Молниедекс: %s — %s!"] = "New Boltdex entry: %s — %s!",

	-- PetService: питомцы
	["Нет такого питомца"] = "No such pet",
	["Нет такого кокона"] = "No such cocoon",
	["Нет места — удали лишних питомцев"] = "No room — delete some pets",
	["🐾 %s питомец «%s»! Хозяин: %s"] = "🐾 %s pet \"%s\"! Owner: %s",
	["🎁 Подарок: %s!"] = "🎁 Gift: %s!",
	["Не хватает 💎 Осколков"] = "Not enough 💎 Shards",
	["Этот питомец уже надет"] = "This pet is already equipped",
	["Все слоты заняты (%d) — сними другого питомца"] = "All %d slots are full — unequip a pet first",
	["Этот питомец не надет"] = "This pet isn't equipped",
	["У тебя пока нет питомцев"] = "You don't have any pets yet",

	-- FulguriteService: фульгуриты и галерея
	["Нет такого фульгурита"] = "No such fulgurite",
	["№%06d"] = "#%06d",
	["пока без фульгурита"] = "no fulgurite yet",
	["Коллекция полна: %s %s разбит, +%d 💎 — место для нового!"] = "Collection full: %s %s shattered, +%d 💎 — room for a new one!",
	["Коллекция фульгуритов полна — разбей лишние в «Коллекции»"] = "Fulgurite collection full — shatter extras in Collection",
	["🔮 %s нашёл: %s %s!"] = "🔮 %s found: %s %s!",
	["Этот фульгурит уже надет"] = "This fulgurite is already equipped",
	["Можно надеть только %d — сними другой"] = "You can only equip %d — unequip one first",
	["Этот фульгурит не надет"] = "This fulgurite isn't equipped",

	-- CityService: Электроград
	["🏙 ЭЛЕКТРОГРАД СИЯЕТ! %s Вольт на %d %s"] = "🏙 VOLTVILLE IS SHINING! %s Volts for %d %s",
	["минуту|минуты|минут"] = "minute|minutes",
	["🏙 Электроград гаснет — сдавайте банки, чтобы зажечь снова!"] = "🏙 Voltville is going dark — sell your jars to light it up again!",

	-- KioskService: подсказки киосков (ProximityPrompt); «Коконы», «Питомцы-искрята», «Перезапуск» — в глоссарии (Shared)
	["Магазин"] = "Shop",
	["Улучшения и острова"] = "Upgrades & Islands",
	["Коллекция"] = "Collection",
	["Фульгуриты и Молниедекс"] = "Fulgurites & Boltdex",
	["Генератор"] = "Generator",
	["Награды"] = "Rewards",
	["Календарь и задания"] = "Calendar & Quests",
	["Вылупить"] = "Hatch",

	-- TutorialService
	["Неизвестный шаг обучения"] = "Unknown tutorial step",
}
