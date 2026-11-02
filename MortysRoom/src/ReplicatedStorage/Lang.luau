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
	["interact.Pylon"] = { ru = "Включить пилон", en = "Switch on the pylon" },
	["interact.Bed"] = { ru = "Лечь спать", en = "Go to sleep" },
	["interact.Cow"] = { ru = "Погладить корову", en = "Pet the cow" },

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
	["obj.pylons"] = { ru = "Включи три пилона вокруг колокола", en = "Switch on the three pylons around the bell" },
	["obj.rickBell"] = { ru = "Вернись к Рику у колокола", en = "Go back to Rick at the bell" },
	["obj.explore"] = { ru = "Осмотрись в этом мире", en = "Look around this world" },
	["obj.cow"] = { ru = "Подойди к кубической корове", en = "Walk up to the cube cow" },
	["obj.clearing"] = { ru = "Иди по светящейся тропе", en = "Follow the glowing path" },
	["obj.portal"] = { ru = "Шагай в портал", en = "Step into the portal" },
	["obj.run"] = { ru = "БЕГИ В БУНКЕР!", en = "RUN TO THE BUNKER!" },
	["obj.friends"] = { ru = "Иди с друзьями к бункеру базы", en = "Walk to the base bunker with your friends" },
	["obj.bed"] = { ru = "Ложись спать", en = "Go to bed" },

	-- chapter titles
	["ch.1"] = { ru = "ГЛАВА 1 — ДОБРОЕ УТРО", en = "CHAPTER 1 — GOOD MORNING" },
	["ch.2"] = { ru = "ГЛАВА 2 — ЗАВТРАК", en = "CHAPTER 2 — BREAKFAST" },
	["ch.3"] = { ru = "ГЛАВА 3 — ГАРАЖ РИКА", en = "CHAPTER 3 — RICK'S GARAGE" },
	["ch.4"] = { ru = "ГЛАВА 4 — КУРС НА B137", en = "CHAPTER 4 — COURSE FOR B137" },
	["ch.5"] = { ru = "ГЛАВА 5 — ПЛАНЕТА B137", en = "CHAPTER 5 — PLANET B137" },
	["ch.6"] = { ru = "ГЛАВА 6 — ТИТАН", en = "CHAPTER 6 — THE TITAN" },
	["ch.7"] = { ru = "ГЛАВА 7 — БУНКЕР", en = "CHAPTER 7 — THE BUNKER" },
	["ch.8"] = { ru = "ГЛАВА 8 — КОЛОКОЛ КРИВОЙ", en = "CHAPTER 8 — THE CURVE BELL" },
	["ch.9"] = { ru = "ГЛАВА 9 — ОХОТА", en = "CHAPTER 9 — THE HUNT" },
	["ch.10"] = { ru = "ГЛАВА 10 — АЛЬЯНС", en = "CHAPTER 10 — THE ALLIANCE" },
	["ch.11"] = { ru = "ГЛАВА 11 — БАЗА КАМЕРАМЕНОВ", en = "CHAPTER 11 — THE CAMERA BASE" },
	["ch.12"] = { ru = "ГЛАВА 12 — ДОМОЙ", en = "CHAPTER 12 — HOME" },
	["the.end"] = { ru = "КОНЕЦ?", en = "THE END?" },
	["loc.silent"] = { ru = "ТИХОЕ ИЗМЕРЕНИЕ S-0", en = "SILENT DIMENSION S-0" },
	["loc.j22"] = { ru = "ИЗМЕРЕНИЕ J-22 · ВСЁ ВВЕРХ НОГАМИ", en = "DIMENSION J-22 · UPSIDE DOWN" },
	["loc.d716"] = { ru = "ИЗМЕРЕНИЕ D-716 · КУБИЧЕСКИЙ МИР", en = "DIMENSION D-716 · CUBE WORLD" },
	["loc.k9"] = { ru = "ИЗМЕРЕНИЕ K-9 · ГРИБНОЙ ЛЕС", en = "DIMENSION K-9 · MUSHROOM FOREST" },
	["loc.b137"] = { ru = "ПЛАНЕТА B137 · ЗАКАТ", en = "PLANET B137 · SUNSET" },
	["loc.base"] = { ru = "БАЗА АЛЬЯНСА · ГОРОД СКИБИДИ", en = "ALLIANCE BASE · SKIBIDI CITY" },
	["loc.home"] = { ru = "ДОМ СМИТОВ · НОЧЬ", en = "THE SMITH HOUSE · NIGHT" },
	["loc.later"] = { ru = "ТЕМ ВРЕМЕНЕМ, В ГАРАЖЕ...", en = "MEANWHILE, IN THE GARAGE..." },
	["choice.bunker"] = { ru = "Уйти в бункер", en = "Go into the bunker" },
	["choice.look"] = { ru = "Осмотреться", en = "Look around" },
	["death.big"] = { ru = "ТЫ ПОГИБ", en = "YOU DIED" },
	["death.small"] = { ru = "Этот бункер строил не настоящий Рик...", en = "That bunker wasn't built by the real Rick..." },
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
	["who.Titan"] = { ru = "ТИТАН СПИКЕРМЕН", en = "TITAN SPEAKERMAN" },
	["who.EvilMorty"] = { ru = "ЗЛОЙ МОРТИ", en = "EVIL MORTY" },
	["who.Cam"] = { ru = "КЭМ", en = "CAM" },
	["who.Lens"] = { ru = "ЛИНЗА", en = "LENS" },
	["who.Commander"] = { ru = "КОМАНДИР ТВ", en = "TV COMMANDER" },
	["who.Agent"] = { ru = "АГЕНТ", en = "AGENT" },
	["who.RickPrime"] = { ru = "РИК ПРАЙМ", en = "RICK PRIME" },
	["who.Cow"] = { ru = "КУБОКОРОВА", en = "CUBE COW" },

	-- radar
	["radar.title"] = { ru = "РАДАР УГРОЗ", en = "THREAT RADAR" },
	["radar.threat"] = { ru = "УГРОЗА:", en = "THREAT:" },
	["radar.max"] = { ru = "МАКСИМАЛЬНАЯ", en = "MAXIMUM" },
	["radar.eta"] = { ru = "ПРИБЫТИЕ ЧЕРЕЗ:", en = "ARRIVAL IN:" },
	["radar.days"] = { ru = "5 ДНЕЙ", en = "5 DAYS" },
	["map.target"] = { ru = "ЗЛОЙ МОРТИ", en = "EVIL MORTY" },
	["radar.search"] = { ru = "ПОИСК СУЩНОСТИ", en = "ENTITY SEARCH" },
	["radar.signal"] = { ru = "СИГНАЛ:", en = "SIGNAL:" },
	["radar.none"] = { ru = "НЕТ", en = "NONE" },
	["radar.weak"] = { ru = "СЛАБЫЙ", en = "WEAK" },
	["radar.glitch"] = { ru = "СБОЙ ?!", en = "ERROR ?!" },
	["radar.strong"] = { ru = "СИЛЬНЫЙ", en = "STRONG" },
	["radar.where"] = { ru = "ГДЕ:", en = "WHERE:" },
	["radar.b137"] = { ru = "ПЛАНЕТА B137", en = "PLANET B137" },
	["radar.dist"] = { ru = "ДИСТАНЦИЯ:", en = "DISTANCE:" },
	["radar.zero"] = { ru = "0 МЕТРОВ", en = "0 METERS" },
	["radar.here"] = { ru = "ЗДЕСЬ", en = "RIGHT HERE" },
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
