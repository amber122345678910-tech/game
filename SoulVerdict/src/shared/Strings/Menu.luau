--!strict
-- Menu strings: generic UI-kit labels and the component Gallery (owned by the UI core).
-- Menu screen agents append their own keys below. Lune-safe.
return {
	-- generic UI kit
	["ui.select"] = { en = "Select", ru = "Выбрать" },
	["ui.back"] = { en = "Back", ru = "Назад" },
	["ui.theme"] = { en = "Theme", ru = "Тема" },
	["ui.menuTheme"] = { en = "Menu theme", ru = "Тема меню" },
	["ui.hudStyle"] = { en = "HUD style", ru = "Стиль HUD" },
	["ui.language"] = { en = "Language", ru = "Язык" },
	["ui.lang.en"] = { en = "English", ru = "English" },
	["ui.lang.ru"] = { en = "Русский", ru = "Русский" },

	-- gallery
	["ui.gallery.title"] = { en = "UI Gallery", ru = "Галерея UI" },
	["ui.gallery.subtitle"] = { en = "{1} theme · every component, every icon", ru = "Тема «{1}» · все компоненты и иконки" },
	["ui.gallery.buttons"] = { en = "Buttons", ru = "Кнопки" },
	["ui.gallery.controls"] = { en = "Controls", ru = "Управление" },
	["ui.gallery.kits"] = { en = "Kit cards", ru = "Карточки наборов" },
	["ui.gallery.bars"] = { en = "Bars & stats", ru = "Полосы и статы" },
	["ui.gallery.icons"] = { en = "Icons", ru = "Иконки" },
	["ui.gallery.dialogue"] = { en = "Dialogue", ru = "Диалог" },
	["ui.gallery.page.all"] = { en = "All", ru = "Всё" },
	["ui.gallery.page.controls"] = { en = "Controls", ru = "Управление" },
	["ui.gallery.page.data"] = { en = "Data", ru = "Данные" },
	["ui.gallery.page.icons"] = { en = "Icons", ru = "Иконки" },
	["ui.gallery.page.overlay"] = { en = "Overlays", ru = "Оверлеи" },
	["ui.gallery.switch"] = { en = "Switch theme", ru = "Сменить тему" },
	["ui.gallery.hud"] = { en = "HUD: {1}", ru = "HUD: {1}" },

	-- gallery sample content (original text)
	["ui.sample.play"] = { en = "Play", ru = "Играть" },
	["ui.sample.loadout"] = { en = "Loadout", ru = "Снаряжение" },
	["ui.sample.quests"] = { en = "Quests", ru = "Задания" },
	["ui.sample.leave"] = { en = "Leave", ru = "Выйти" },
	["ui.sample.ranked"] = { en = "Ranked", ru = "Рейтинг" },
	["ui.sample.music"] = { en = "Music", ru = "Музыка" },
	["ui.sample.shake"] = { en = "Camera shake", ru = "Тряска камеры" },
	["ui.sample.damageNumbers"] = { en = "Damage numbers", ru = "Числа урона" },
	["ui.sample.dialogue"] = {
		en = "The hall is quiet. Somewhere above, a SOUL waits for its verdict.",
		ru = "В зале тихо. Где-то наверху ДУША ждёт своего приговора.",
	},
	["ui.sample.toast"] = { en = "Quest complete: Parry 5 bones. +40 G", ru = "Задание выполнено: парируй 5 костей. +40 G" },
	["ui.sample.toastLevel"] = { en = "LV up! You reached LV 7.", ru = "Новый LV! Достигнут LV 7." },
	["ui.sample.round"] = { en = "Round ends", ru = "До конца раунда" },
	["ui.sample.wins"] = { en = "Wins", ru = "Победы" },
	["ui.sample.damage"] = { en = "Damage dealt", ru = "Нанесено урона" },
	["ui.sample.parries"] = { en = "Perfect parries", ru = "Идеальные парирования" },
	["ui.sample.chance"] = { en = "Monster chance", ru = "Шанс стать монстром" },
	["ui.sample.unlockTitle"] = { en = "Unlock kit?", ru = "Открыть набор?" },
	["ui.sample.unlockText"] = { en = "Spend {1} G to unlock {2}? Kits are sidegrades: same power, new style.", ru = "Потратить {1} G, чтобы открыть {2}? Наборы равны по силе — меняется только стиль." },
}
