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
}
