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
}
