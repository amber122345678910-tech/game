--!strict
-- Задания дня: 3 задания, одинаковые для игрока в течение суток (зависят от дня и UserId).
-- Тексты — русские исходники и ключи словаря (переводы — в Strings/Shared.luau): клиент рисует Quests.text,
-- сервер отправляет Quests.msg (Loc.Msg, переводит клиент).

local Loc = require(script.Parent.Loc)
local Prng = require(script.Parent.Prng)

export type QuestDef = {
	Id: string,
	Event: string, -- какое событие двигает прогресс: catch, perfect, combo, rare, sell, hatch, gold, shards
	Text: string, -- исходник: %d = цель, %s = слово из Forms в нужном числе (см. Quests.text)
	Forms: string?, -- формы для Loc.plural через «|»: 1 / 2–4 / 5+ («молнию|молнии|молний»)
	Target: number,
	MinZone: number,
	Shards: number, -- награда осколками
	Minutes: number, -- награда: минут дохода
	Max: boolean?, -- прогресс = максимум (комбо), а не сумма
}

local Quests = {}

local LIGHTNING = "молнию|молнии|молний"
local TIMES = "раз|раза|раз"

Quests.Pool = {
	{ Id = "catch", Event = "catch", Text = "Поймай %d %s", Forms = LIGHTNING, Target = 60, MinZone = 1, Shards = 40, Minutes = 4 },
	-- у «ИДЕАЛЬНО» свои английские формы (perfect:: → «Get 20 PERFECT catches»), по-русски — те же, что у LIGHTNING
	{ Id = "perfect", Event = "perfect", Text = "Поймай %d %s ИДЕАЛЬНО", Forms = "perfect::молнию|молнии|молний", Target = 20, MinZone = 1, Shards = 50, Minutes = 5 },
	{ Id = "combo", Event = "combo", Text = "Набери комбо %d", Target = 12, MinZone = 1, Shards = 60, Minutes = 6, Max = true },
	{
		Id = "rare",
		Event = "rare",
		Text = "Поймай %d %s",
		Forms = "редкую молнию (◆ и выше)|редкие молнии (◆ и выше)|редких молний (◆ и выше)",
		Target = 8,
		MinZone = 1,
		Shards = 50,
		Minutes = 5,
	},
	{ Id = "sell", Event = "sell", Text = "Сдай банку %d %s", Forms = TIMES, Target = 8, MinZone = 1, Shards = 40, Minutes = 4 },
	{ Id = "hatch", Event = "hatch", Text = "Вылупи %d %s", Forms = "питомца|питомцев|питомцев", Target = 1, MinZone = 1, Shards = 30, Minutes = 3 },
	{ Id = "gold", Event = "gold", Text = "Поймай %d %s", Forms = "золотую молнию|золотые молнии|золотых молний", Target = 1, MinZone = 2, Shards = 80, Minutes = 8 },
	{ Id = "shards", Event = "shards", Text = "Собери %d %s с земли", Forms = "осколок|осколка|осколков", Target = 30, MinZone = 1, Shards = 40, Minutes = 4 },
} :: { QuestDef }

function Quests.def(id: string): QuestDef?
	for _, q in Quests.Pool do
		if q.Id == id then
			return q
		end
	end
	return nil
end

-- Текст задания на языке игрока (клиент) для цели target с согласованным словом:
-- «Поймай 1 молнию», «Поймай 60 молний» / «Catch 1 bolt», «Catch 60 bolts»
function Quests.text(def: QuestDef, target: number): string
	local forms = def.Forms
	if forms then
		return Loc.t(def.Text, target, Loc.plural(target, forms))
	end
	return Loc.t(def.Text, target)
end

-- То же сообщением для клиента (сервер не знает языка игрока: переводит клиент через Loc.render)
function Quests.msg(def: QuestDef, target: number): Loc.Msg
	local forms = def.Forms
	if forms then
		return Loc.msg(def.Text, target, Loc.pmsg(target, forms))
	end
	return Loc.msg(def.Text, target)
end

-- Номер дня (UTC) по os.time()
function Quests.dayNumber(t: number): number
	return math.floor(t / 86400)
end

-- 3 разных задания на день
function Quests.forDay(day: number, userId: number, zone: number): { { Id: string, Target: number, Progress: number, Claimed: boolean } }
	local rng = Prng.new(Prng.hash(day, userId))
	local available = {}
	for _, q in Quests.Pool do
		if zone >= q.MinZone then
			table.insert(available, q)
		end
	end
	local out = {}
	for _ = 1, math.min(3, #available) do
		local i = rng:int(1, #available)
		local q = table.remove(available, i) :: QuestDef
		table.insert(out, { Id = q.Id, Target = q.Target, Progress = 0, Claimed = false })
	end
	return out
end

return Quests
