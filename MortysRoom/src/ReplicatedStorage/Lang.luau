-- Russian / English text. Lang.t({ru = "...", en = "..."}) or Lang.t("key").
local Settings = require(script.Parent.Settings)

local Lang = {}

Lang.strings = {
	-- interaction hints
	["interact.AlarmClock"] = { ru = "Выключить будильник", en = "Turn off alarm" },
	["interact.AlarmClock.idle"] = { ru = "Посмотреть время", en = "Check the time" },
	["interact.NightLamp"] = { ru = "Ночник", en = "Bedside lamp" },
	["interact.DeskLamp"] = { ru = "Настольная лампа", en = "Desk lamp" },
	["interact.LightSwitch"] = { ru = "Выключатель", en = "Light switch" },
	["interact.Curtains"] = { ru = "Открыть шторы", en = "Open curtains" },
	["interact.Curtains.open"] = { ru = "Закрыть шторы", en = "Close curtains" },
	["interact.Monitor"] = { ru = "Компьютер", en = "Computer" },
	["interact.Door"] = { ru = "Открыть дверь", en = "Open door" },
	["interact.Door.open"] = { ru = "Закрыть дверь", en = "Close door" },
	["interact.Phone"] = { ru = "Взять телефон", en = "Take phone" },
	["interact.SitDown"] = { ru = "Сесть за стол", en = "Sit down" },
	["interact.FrontDoor"] = { ru = "Входная дверь", en = "Front door" },
	["interact.SummerDoor"] = { ru = "Комната Саммер", en = "Summer's room" },
	["interact.Saucer"] = { ru = "Сесть в тарелку", en = "Get in the saucer" },

	-- prompts / hints
	["hint.lying"] = { ru = "Мышь — осмотреться   ·   [ПРОБЕЛ] встать   ·   [E] выключить будильник", en = "Mouse — look around   ·   [SPACE] get up   ·   [E] turn off the alarm" },
	["hint.lying.simple"] = { ru = "Мышь — осмотреться   ·   [ПРОБЕЛ] встать", en = "Mouse — look around   ·   [SPACE] get up" },
	["hint.lying.touch"] = { ru = "Осмотрись. Нажми ВСТАТЬ, когда будешь готов.", en = "Look around. Tap GET UP when ready." },
	["hint.walk"] = { ru = "WASD — идти   ·   [E] взаимодействие   ·   [P] пауза   ·   [G] графика", en = "WASD walk  ·  [E] use  ·  [P] pause  ·  [G] graphics" },
	["hint.walk.touch"] = { ru = "Исследуй комнату Морти.", en = "Explore Morty's room." },
	["hint.alarm"] = { ru = "Выключи будильник: посмотри на него и нажми [E].", en = "Turn off that alarm: look at it and press [E]." },
	["hint.continue"] = { ru = "[ЛКМ / E / ПРОБЕЛ] дальше", en = "[CLICK / E / SPACE] continue" },
	["touch.getup"] = { ru = "ВСТАТЬ", en = "GET UP" },
	["touch.use"] = { ru = "ДЕЙСТВИЕ", en = "USE" },

	-- objectives
	["obj.alarm"] = { ru = "Выключи будильник", en = "Turn off the alarm" },
	["obj.phone"] = { ru = "Возьми телефон с тумбочки", en = "Take your phone from the nightstand" },
	["obj.kitchen"] = { ru = "Спустись на кухню завтракать", en = "Go downstairs for breakfast" },
	["obj.sit"] = { ru = "Сядь за стол", en = "Sit down at the table" },
	["obj.saucer"] = { ru = "Садись в тарелку", en = "Get in the saucer" },
	["obj.follow"] = { ru = "Иди за Риком", en = "Follow Rick" },
	["obj.look"] = { ru = "Осмотрись", en = "Look around" },

	-- chapter titles
	["ch.1"] = { ru = "ГЛАВА 1 — ДОБРОЕ УТРО", en = "CHAPTER 1 — GOOD MORNING" },
	["ch.2"] = { ru = "ГЛАВА 2 — ЗАВТРАК", en = "CHAPTER 2 — BREAKFAST" },
	["ch.3"] = { ru = "ГЛАВА 3 — ГАРАЖ РИКА", en = "CHAPTER 3 — RICK'S GARAGE" },
	["ch.4"] = { ru = "ГЛАВА 4 — КУРС НА B137", en = "CHAPTER 4 — COURSE FOR B137" },
	["ch.5"] = { ru = "ГЛАВА 5 — ПЛАНЕТА B137", en = "CHAPTER 5 — PLANET B137" },
	["ch.6"] = { ru = "ГЛАВА 6 — ТИТАН", en = "CHAPTER 6 — THE TITAN" },
	["ch.7"] = { ru = "ГЛАВА 7 — БУНКЕР", en = "CHAPTER 7 — THE BUNKER" },
	["ch.sub"] = { ru = "РИК И МОРТИ", en = "RICK AND MORTY" },
	["tbc"] = { ru = "ПРОДОЛЖЕНИЕ СЛЕДУЕТ...", en = "TO BE CONTINUED..." },
	["tbc.menu"] = { ru = "В главное меню", en = "Main menu" },

	-- speakers
	["who.Rick"] = { ru = "РИК", en = "RICK" },
	["who.Morty"] = { ru = "МОРТИ", en = "MORTY" },
	["who.MortyThought"] = { ru = "МОРТИ (думает)", en = "MORTY (thinking)" },
	["who.Beth"] = { ru = "БЭТ", en = "BETH" },
	["who.Jerry"] = { ru = "ДЖЕРРИ", en = "JERRY" },
	["who.Summer"] = { ru = "САММЕР", en = "SUMMER" },
	["who.Unknown"] = { ru = "???", en = "???" },

	-- radar
	["radar.title"] = { ru = "РАДАР УГРОЗ", en = "THREAT RADAR" },
	["radar.threat"] = { ru = "УГРОЗА:", en = "THREAT:" },
	["radar.max"] = { ru = "МАКСИМАЛЬНАЯ", en = "MAXIMUM" },
	["radar.eta"] = { ru = "ПРИБЫТИЕ ЧЕРЕЗ:", en = "ARRIVAL IN:" },
	["radar.days"] = { ru = "5 ДНЕЙ", en = "5 DAYS" },
	["map.target"] = { ru = "ЗЛОЙ МОРТИ", en = "EVIL MORTY" },
	["phone.hot"] = { ru = "ПЕРЕГРЕВ", en = "OVERHEATING" },
	["glitch.lost"] = { ru = "СИГНАЛ ПОТЕРЯН", en = "SIGNAL LOST" },
}

function Lang.code(): string
	return Settings.Get("Language") or "RU"
end

function Lang.t(line: any): string
	if line == nil then
		return ""
	end
	if type(line) == "string" then
		local s = Lang.strings[line]
		if not s then
			return line
		end
		line = s
	end
	if Lang.code() == "EN" then
		return line.en or line.ru or ""
	end
	return line.ru or line.en or ""
end

return Lang
