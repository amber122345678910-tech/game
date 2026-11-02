--!strict
-- Map strings for the second arena batch (Maps/VoidRift, Maps/CoreReactor). Lune-safe.
-- Every key starts with "maps." and has en + ru. Map names/descriptions mirror the map modules' Name/Desc
-- (menus may use either); signs built with MapKit B:Text store their key in the TextKey attribute.
return {
	-- Void Rift --------------------------------------------------------------------------------------------
	["maps.voidrift.name"] = { en = "Void Rift", ru = "Разлом Пустоты" },
	["maps.voidrift.desc"] = {
		en = "Broken platforms drifting between timelines. Mind the edges.",
		ru = "Обломки платформ, дрейфующие между временными линиями. Осторожно с краями.",
	},
	["maps.voidrift.area.core"] = { en = "The Verdict Shard", ru = "Осколок Приговора" },
	["maps.voidrift.area.gate"] = { en = "Rift Gate", ru = "Врата Разлома" },
	["maps.voidrift.area.crown"] = { en = "Shattered Crown", ru = "Разбитая Корона" },
	["maps.voidrift.area.skull"] = { en = "Fallen Watcher", ru = "Павший Страж" },
	["maps.voidrift.area.landing"] = { en = "Shore of Waking", ru = "Берег Пробуждения" },
	["maps.voidrift.area.drift"] = { en = "Drifting Isle", ru = "Дрейфующий Остров" },
	["maps.voidrift.area.shards"] = { en = "Crystal Scar", ru = "Кристальный Шрам" },
	["maps.voidrift.area.ribway"] = { en = "The Ribway", ru = "Рёберный Путь" },

	-- Core Reactor -----------------------------------------------------------------------------------------
	["maps.corereactor.name"] = { en = "Core Reactor", ru = "Реактор Ядра" },
	["maps.corereactor.desc"] = {
		en = "Catwalks over a roaring heart of magma and machinery.",
		ru = "Мостки над ревущим сердцем из магмы и машин.",
	},
	["maps.corereactor.sign.core"] = { en = "REACTOR CONTROL", ru = "УПРАВЛЕНИЕ РЕАКТОРОМ" },
	["maps.corereactor.sign.bay"] = { en = "LOADING BAY 03", ru = "ПОГРУЗОЧНЫЙ ДОК 03" },
	["maps.corereactor.sign.heat"] = { en = "DANGER: EXTREME HEAT", ru = "ОПАСНО: СИЛЬНЫЙ ЖАР" },
	["maps.corereactor.sign.coolant"] = { en = "COOLANT", ru = "ОХЛАДИТЕЛЬ" },
	["maps.corereactor.sign.turbine"] = { en = "TURBINE HALL", ru = "ТУРБИННЫЙ ЗАЛ" },
	["maps.corereactor.sign.gantry"] = { en = "HEAT GANTRY", ru = "ТЕПЛОВАЯ ЭСТАКАДА" },
	["maps.corereactor.area.ring"] = { en = "Reactor Ring", ru = "Кольцо Реактора" },
	["maps.corereactor.area.bay"] = { en = "Loading Bay", ru = "Погрузочный док" },
	["maps.corereactor.area.control"] = { en = "Control Deck", ru = "Пульт управления" },
	["maps.corereactor.area.turbine"] = { en = "Turbine Hall", ru = "Турбинный зал" },
	["maps.corereactor.area.coolant"] = { en = "Coolant Station", ru = "Станция охлаждения" },
	["maps.corereactor.area.gantry"] = { en = "Heat Gantry", ru = "Тепловая эстакада" },
	["maps.corereactor.area.crane"] = { en = "Crane Gantry", ru = "Крановая эстакада" },
}
