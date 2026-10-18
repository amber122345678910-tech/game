--!strict
-- Чистая логика ударов: окна тайминга, оценка нажатия, комбо, выбор цвета и типа,
-- риск перегрузки, анимация кольца. Одинаково используется сервером, клиентом и тестами.

local Config = require(script.Parent.Config)
local Rng = require(script.Parent.Rng)

export type Grade = "perfect" | "good" | "miss"

local Strikes = {}

-- Окна ИДЕАЛЬНО/ХОРОШО (±секунд) с учётом громоотвода и бонусов питомцев (мс)
function Strikes.windows(rodLevel: number, bonusMs: number?): (number, number)
	local c = Config.Catch
	local steps = math.floor(math.max(0, rodLevel) / 5)
	local bonus = (bonusMs or 0) / 1000
	local perfect = math.min(c.MaxPerfectWindow, c.PerfectWindow + steps * c.RodWindowStepPerfect + bonus)
	local good = math.min(c.MaxGoodWindow, c.GoodWindow + steps * c.RodWindowStepGood + bonus)
	return perfect, math.max(good, perfect + 0.05)
end

-- Оценка по разнице времени нажатия и удара (dt = нажатие − удар)
function Strikes.judge(dt: number, perfect: number, good: number): Grade
	local a = math.abs(dt)
	if a <= perfect then
		return "perfect"
	elseif a <= good then
		return "good"
	end
	return "miss"
end

function Strikes.comboMult(combo: number): number
	local c = Config.Catch
	return 1 + c.ComboStep * math.clamp(combo, 0, c.ComboCap)
end

-- Веса цветов зоны с учётом удачи (удача множит всё, что реже голубой).
-- boostGold — дополнительный множитель для золотых (Суперячейка).
function Strikes.colorWeights(zone: number, luck: number?, boostGold: number?): { Rng.Weighted<Config.ColorId> }
	local def = Config.Zones[zone]
	local l = 1 + math.max(0, luck or 0)
	local out: { Rng.Weighted<Config.ColorId> } = {}
	for _, id in Config.NormalColors do
		local w = def.ColorWeights[id] or 0
		if id ~= "blue" then
			w *= l
		end
		if id == "gold" and boostGold then
			w *= boostGold
		end
		if w > 0 then
			table.insert(out, { item = id, weight = w })
		end
	end
	return out
end

function Strikes.rollColor(zone: number, luck: number?, roll: number, boostGold: number?): Config.ColorId
	return Rng.pick(Strikes.colorWeights(zone, luck, boostGold), roll)
end

-- Следующий по редкости обычный цвет (для "переливающихся" колец)
function Strikes.upgradedColor(color: Config.ColorId): Config.ColorId
	local order = Config.NormalColors
	local i = table.find(order, color)
	if i and i < #order then
		return order[i + 1]
	end
	return color
end

function Strikes.rollKind(zone: number, roll: number): Config.KindId
	local def = Config.Zones[zone]
	local list: { Rng.Weighted<Config.KindId> } = {}
	for id, w in def.KindWeights do
		if w > 0 and Config.Kinds[id].FromZone <= zone then
			table.insert(list, { item = id, weight = w })
		end
	end
	if #list == 0 then
		return "single"
	end
	-- порядок pairs не определён — сортируем для детерминизма
	table.sort(list, function(a, b)
		return (a.item :: string) < (b.item :: string)
	end)
	return Rng.pick(list, roll)
end

-- Смещения ударов внутри одного кольца (секунды от первого удара)
function Strikes.hitOffsets(kind: Config.KindId): { number }
	return table.clone(Config.Kinds[kind].Hits)
end

-- Время предупреждения зоны (с учётом события)
function Strikes.warning(zone: number): number
	return Config.Zones[zone].Warning
end

-- Риск перегрузки (0..1) для поимки, после которой заполнение = fill (>1)
function Strikes.overchargeRisk(fill: number, insulationLevel: number): number
	if fill <= 1 then
		return 0
	end
	local o = Config.Overcharge
	local t = math.clamp((fill - 1) / (o.MaxFill - 1), 0, 1)
	local base = o.BaseRisk + o.ExtraRisk * t
	local ins = math.max(0.2, 1 - Config.UpgradeEffects.InsulationRiskPerLevel * insulationLevel)
	return math.clamp(base * ins, 0, 0.95)
end

-- Насколько внешнее кольцо прошло путь к внутреннему (0 — только появилось, 1 — удар).
-- t01 — доля прошедшего времени предупреждения. Обманка замирает на середине и догоняет.
function Strikes.ringProgress(kind: Config.KindId, t01: number): number
	local t = math.clamp(t01, 0, 1)
	if kind == "fake" then
		-- 0..0.45 времени: до 60% пути; 0.45..0.7: стоит; 0.7..1: резко до 100%
		if t < 0.45 then
			return 0.6 * (t / 0.45)
		elseif t < 0.7 then
			return 0.6
		end
		local k = (t - 0.7) / 0.3
		return 0.6 + 0.4 * k
	end
	return t
end

-- Позиция бегущего кольца в момент времени (линейно от start к finish)
function Strikes.runnerPosition(start: Vector3, finish: Vector3, t01: number): Vector3
	return start:Lerp(finish, math.clamp(t01, 0, 1))
end

return Strikes
