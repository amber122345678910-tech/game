--!strict
-- Strings for the phone-friendly menu / lobby HUD pass (Screens/Title, Hud/LobbyHud): the Title's PRACTICE and
-- ADMIN entries and the compact lobby banner + practice call-to-action. Lune-safe.
return {
	-- Title menu extras
	["mobile.title.practice"] = { en = "Practice", ru = "Тренировка" },
	["mobile.title.desc.practice"] = {
		en = "No one to play with yet? Start a practice round against bots right now.",
		ru = "Пока не с кем играть? Начни тренировочный раунд против ботов прямо сейчас.",
	},
	["mobile.title.admin"] = { en = "Admin", ru = "Админ" },
	["mobile.title.desc.admin"] = {
		en = "Owner test panel: start rounds, add bots, switch roles and phases.",
		ru = "Панель владельца: запуск раундов, боты, роли и фазы для тестов.",
	},
	-- lobby HUD (phones)
	["mobile.lobby.waiting.short"] = {
		en = "* One more SOUL needed - PRACTICE meanwhile!",
		ru = "* Нужна ещё одна душа - пока ТРЕНИРУЙСЯ!",
	},
	["mobile.lobby.practice.sub"] = { en = "vs bots", ru = "с ботами" },
	["mobile.lobby.menu"] = { en = "MENU", ru = "МЕНЮ" },
}
