--!strict
-- Английские переводы общих данных: глоссарий (названия островов, цветов, питомцев, улучшений, валют),
-- Config, Pets, Quests, Fulgurite, Economy и прочие модули src/shared. Ключ — русский исходник из кода.
-- Глоссарий — единый для всей игры: другие словари используют эти же английские слова.
return {
	-- Игра и валюты
	["Ловцы Молний"] = "Lightning Catchers",
	["Вольты"] = "Volts",
	["Осколки"] = "Shards",
	["Банка"] = "Jar",
	["Заряд"] = "Charge",
	["Комбо"] = "Combo",
	["Электроград"] = "Voltville",
	["Перегрузка"] = "Overcharge",
	["Подстанция"] = "Substation",
	["Молниедекс"] = "Boltdex",
	["Перезапуск"] = "Rebirth",
	["Фульгурит"] = "Fulgurite",
	["Фульгуриты"] = "Fulgurites",
	["Кокон"] = "Cocoon",
	["Коконы"] = "Cocoons",
	["Питомцы-искрята"] = "Sparklings",

	-- События
	["Суперячейка"] = "Supercell",
	["Шаровая молния"] = "Ball Lightning",
	["Радужная молния"] = "Rainbow Lightning",
	["Чёрная молния Перуна"] = "Perun's Black Lightning",

	-- Оценки нажатия
	["ИДЕАЛЬНО!"] = "PERFECT!",
	["ХОРОШО"] = "GOOD",
	["МИМО"] = "MISS",
	["ЛОВИ!"] = "CATCH!",

	-- Острова
	["Грозовой Луг"] = "Storm Meadow",
	["Медные Холмы"] = "Copper Hills",
	["Стеклянные Дюны"] = "Glass Dunes",
	["Ледяной Пик"] = "Frost Peak",
	["Око Бури"] = "Eye of the Storm",
	-- короткие имена островов (Config.Zones[i].Short)
	["Луг"] = "Meadow",
	["Холмы"] = "Hills",
	["Дюны"] = "Dunes",
	["Пик"] = "Peak",
	["Око"] = "Eye",

	-- Цвета молний
	["Голубая"] = "Blue",
	["Фиолетовая"] = "Purple",
	["Изумрудная"] = "Emerald",
	["Алая"] = "Scarlet",
	["Золотая"] = "Golden",
	["Радужная"] = "Rainbow",
	["Чёрная Перуна"] = "Perun's Black",

	-- Виды ударов (контекст kind:: — «Обычный» у редкости переводится иначе)
	["kind::Обычный"] = "Normal",
	["Двойной"] = "Double",
	["Вилка"] = "Fork",
	["Обманка"] = "Fake-out",
	["Бегущий"] = "Runner",

	-- Улучшения
	["Громоотвод"] = "Lightning Rod",
	["Больше заряда за молнию, шире окно ИДЕАЛЬНО"] = "More charge per bolt and a wider PERFECT window",
	["Больше заряда помещается в банку"] = "Your jar holds more charge",
	["Сапоги-скороходы"] = "Speed Boots",
	["Быстрее бегаешь между кольцами"] = "Run faster between rings",
	["Грозовой магнит"] = "Storm Magnet",
	["Молнии бьют чаще; больше колец сразу"] = "Lightning strikes more often; more rings at once",
	["Изоляция"] = "Insulation",
	["Меньше риск перегрузки и короче удар током"] = "Lower overcharge risk and shorter shocks",
	["Тесла-дрон"] = "Tesla Drone",
	["Сам сдаёт банку, когда она полная"] = "Sells your jar for you when it's full",
	-- эффект улучшения в магазине (Economy.effectText)
	["заряд ×%s"] = "charge ×%s",
	["вместимость %s"] = "capacity %s",
	["скорость %d"] = "speed %d",
	["частота +%d%%"] = "strikes +%d%%",
	["частота +%d%%, колец +%d"] = "strikes +%d%%, rings +%d",
	["риск −%d%%"] = "risk −%d%%",

	-- Редкости
	["Обычный"] = "Common",
	["Редкий"] = "Rare",
	["Эпический"] = "Epic",
	["Легендарный"] = "Legendary",
	["Мифический"] = "Mythic",

	-- Коконы
	["Луговой кокон"] = "Meadow Cocoon",
	["Ледяной кокон"] = "Frost Cocoon",
	["Грозовой кокон"] = "Storm Cocoon",

	-- Питомцы-искрята (Sparklings)
	["Искорка"] = "Sparky",
	["Капелька"] = "Droplet",
	["Лучик"] = "Beamy",
	["Тучка"] = "Cloudy",
	["Шаровик"] = "Orby",
	["Зарница"] = "Glimmer",
	["Громик"] = "Rumble",
	["Снежок"] = "Snowball",
	["Иней"] = "Frosty",
	["Северок"] = "Northy",
	["Сосулька"] = "Icicle",
	["Буран"] = "Blizzard",
	["Сияние"] = "Aurora",
	["Полярник"] = "Polaris",
	["Грозик"] = "Stormy",
	["Вихрь"] = "Whirl",
	["Тесла"] = "Tesla",
	["Стрелка"] = "Zippy",
	["Громовик"] = "Thunderling",
	["Царь-Молния"] = "Lightning King",
	["Перунчик"] = "Little Perun",

	-- Бонусы питомцев (Pets.BonusNames, Pets.bonusMsg)
	["⚡ Вольты"] = "⚡ Volts",
	["🍀 Удача"] = "🍀 Luck",
	["🎯 Окно ИДЕАЛЬНО"] = "🎯 PERFECT Window",
	["💎 Осколки"] = "💎 Shards",
	["%s +%d мс"] = "%s +%d ms",

	-- Фульгуриты: формы, мутации, название (Fulgurite.titleMsg)
	["Куст"] = "Bush",
	["Корона"] = "Crown",
	["Спираль"] = "Spiral",
	["Дерево"] = "Tree",
	["Звезда"] = "Star",
	["Золотой"] = "Golden",
	["Ночной"] = "Night",
	["Радужный"] = "Rainbow",
	["Перунов"] = "Perun's",
	["%s фульгурит «%s»"] = "%s %s Fulgurite",
	["Фульгурит «%s»"] = "%s Fulgurite",

	-- Громоотводы по уровню (Models.RodStyles; «Золотой», «Тесла», «Перунов» — выше)
	["Медный"] = "Copper",
	["Серебряный"] = "Silver",
	["Грозовой"] = "Storm",

	-- Задания дня (Quests.Pool: текст + формы слова для Loc.plural)
	["Поймай %d %s"] = "Catch %d %s",
	["Поймай %d %s ИДЕАЛЬНО"] = "Get %d %s",
	["Набери комбо %d"] = "Reach a ×%d Combo",
	["Сдай банку %d %s"] = "Sell your Jar %d %s",
	["Вылупи %d %s"] = "Hatch %d %s",
	["Собери %d %s с земли"] = "Pick up %d %s",
	["молнию|молнии|молний"] = "bolt|bolts",
	["perfect::молнию|молнии|молний"] = "PERFECT catch|PERFECT catches",
	["редкую молнию (◆ и выше)|редкие молнии (◆ и выше)|редких молний (◆ и выше)"] = "rare bolt (◆ or better)|rare bolts (◆ or better)",
	["раз|раза|раз"] = "time|times",
	["питомца|питомцев|питомцев"] = "pet|pets",
	["золотую молнию|золотые молнии|золотых молний"] = "Golden bolt|Golden bolts",
	["осколок|осколка|осколков"] = "Shard|Shards",
}
