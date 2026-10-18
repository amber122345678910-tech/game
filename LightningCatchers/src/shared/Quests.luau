--!strict
-- Задания дня: 3 задания, одинаковые для игрока в течение суток (зависят от дня и UserId).

local Prng = require(script.Parent.Prng)

export type QuestDef = {
	Id: string,
	Event: string, -- какое событие двигает прогресс: catch, perfect, combo, rare, sell, hatch, gold, shards
	Text: string, -- %d = цель
	Target: number,
	MinZone: number,
	Shards: number, -- награда осколками
	Minutes: number, -- награда: минут дохода
	Max: boolean?, -- прогресс = максимум (комбо), а не сумма
}

local Quests = {}

Quests.Pool = {
	{ Id = "catch", Event = "catch", Text = "Поймай %d молний", Target = 60, MinZone = 1, Shards = 40, Minutes = 4 },
	{ Id = "perfect", Event = "perfect", Text = "%d раз ИДЕАЛЬНО", Target = 20, MinZone = 1, Shards = 50, Minutes = 5 },
	{ Id = "combo", Event = "combo", Text = "Набери комбо %d", Target = 12, MinZone = 1, Shards = 60, Minutes = 6, Max = true },
	{ Id = "rare", Event = "rare", Text = "Поймай %d фиолетовых или реже", Target = 8, MinZone = 1, Shards = 50, Minutes = 5 },
	{ Id = "sell", Event = "sell", Text = "Сдай банку %d раз", Target = 8, MinZone = 1, Shards = 40, Minutes = 4 },
	{ Id = "hatch", Event = "hatch", Text = "Вылупи %d питомца", Target = 1, MinZone = 1, Shards = 30, Minutes = 3 },
	{ Id = "gold", Event = "gold", Text = "Поймай %d золотую молнию", Target = 1, MinZone = 2, Shards = 80, Minutes = 8 },
	{ Id = "shards", Event = "shards", Text = "Собери %d осколков с земли", Target = 30, MinZone = 1, Shards = 40, Minutes = 4 },
} :: { QuestDef }

function Quests.def(id: string): QuestDef?
	for _, q in Quests.Pool do
		if q.Id == id then
			return q
		end
	end
	return nil
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
