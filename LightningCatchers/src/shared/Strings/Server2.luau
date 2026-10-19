--!strict
-- Английские переводы строк для игрока (ключ — русский исходник из кода). Глоссарий — в Strings/Shared.luau.
-- Сервисы: PlayerService, LeaderboardService, DailyService, DataService, RequestService.
-- «Данные ещё загружаются», «Нет такого острова», имена событий для прогноза — в Strings/Server.luau.
return {
	-- RequestService: общие ответы
	["Ошибка, попробуй ещё раз"] = "Oops! Try again",
	["Неизвестное действие"] = "Unknown action",
	["Слишком быстро! Подожди секунду"] = "Too fast! Wait a sec",

	-- DataService
	["⚠ Прогресс сейчас не сохраняется (сбой серверов Roblox). Перезайди в игру попозже"] = "⚠ Your progress isn't saving right now (Roblox server issue). Rejoin a bit later",

	-- PlayerService: барьеры островов и телепорт
	["Остров закрыт — открой его в магазине"] = "Island locked — unlock it in the Shop",
	["Остров закрыт — сначала открой «%s»"] = "Island locked — unlock %s first",
	["Остров закрыт — нужно ⚡ %s, не хватает ⚡ %s"] = "Island locked — costs ⚡ %s, you need ⚡ %s more",
	["Хватает ⚡! Открой «%s» в магазине"] = "You have enough ⚡! Unlock %s in the Shop",
	["Подожди, пока появится персонаж"] = "Wait for your character to spawn",
	-- PlayerService: табличка над головой (титул и лучшая серия)
	["☠ Ловец Перуна"] = "☠ Perun Catcher",
	["🌈 Радужный ловец"] = "🌈 Rainbow Catcher",
	["🌟 Золотой ловец"] = "🌟 Golden Catcher",
	["♻ Перезапуск ×%d"] = "♻ Rebirth ×%d",
	["Серия: %d"] = "Best Combo: %d",

	-- LeaderboardService: leaderstats («Вольты» — в глоссарии) и табло в хабе
	["Перезапуски"] = "Rebirths",
	["Ловец"] = "Catcher",
	["ЛУЧШИЕ ЛОВЦЫ"] = "TOP CATCHERS",
	["ЗАЛ СЛАВЫ"] = "HALL OF FAME",
	["ПРОГНОЗ ПОГОДЫ"] = "WEATHER FORECAST",
	["Пока пусто — лови молнии!"] = "Nobody yet — go catch some bolts!",
	["лучшие во всей игре"] = "best in the whole game",
	["лучшие на этом сервере"] = "best on this server",
	["Поймай Радужную молнию!"] = "Catch the Rainbow Lightning!",
	["ловцы Радужной и Чёрной молнии на этом сервере"] = "Rainbow & Black Lightning catchers on this server",
	["%s — СЕЙЧАС! %s"] = "%s — NOW! %s",
	["%s — через %s"] = "%s — in %s",
	["🏙 Электроград сияет! %s"] = "🏙 Voltville is shining! %s",
	["🏙 Электроград — %d/%d"] = "🏙 Voltville — %d/%d",

	-- DailyService: календарь
	["Нет места для питомца — удали лишних в «Питомцах»"] = "No room for a new pet — delete some in Pets",
	["+%s ⚡ и +%s 💎"] = "+%s ⚡ and +%s 💎",
	["Сегодня уже забрал — приходи завтра!"] = "Already claimed today — come back tomorrow!",
	["🥚 Кокон"] = "🥚 Cocoon",
	["×2 Вольт на %d мин!"] = "×2 Volts for %d min!",
	["🐾 Новый питомец: %s!"] = "🐾 New pet: %s!",
	["🐾 Питомец"] = "🐾 Pet",
	["День %d: %s"] = "Day %d: %s",
	-- DailyService: задания дня
	["✅ Награда за прошлое задание зачислена: %s"] = "✅ Unclaimed quest reward added: %s",
	["✅ Задание выполнено! Забери награду в «Наградах»"] = "✅ Quest complete! Claim your reward in Rewards",
	["Нет такого задания"] = "No such quest",
	["Наступил новый день — задания обновились"] = "It's a new day — fresh quests are here!",
	["Награда уже получена"] = "Reward already claimed",
	["Ещё не выполнено: осталось %d"] = "Not done yet: %d to go",
	-- DailyService: коды и офлайн-доход
	["Неверный код"] = "Invalid code",
	["Этот код уже использован"] = "You already used this code",
	["Код сработал! %s"] = "Code redeemed! %s",
	["Код сработал! ×2 Вольт на %d мин"] = "Code redeemed! ×2 Volts for %d min",
	["Код сработал!"] = "Code redeemed!",
	["Уже забрано"] = "Already claimed",
}
