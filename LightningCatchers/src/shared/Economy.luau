--!strict
-- Экономика: цены и эффекты улучшений, заряд за поимку, стоимость сдачи банки, множители,
-- острова, перезапуск. Чистые функции — их же гоняет симуляция баланса.

local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)
local Pets = require(script.Parent.Pets)
local Fulgurite = require(script.Parent.Fulgurite)
local PlayerData = require(script.Parent.PlayerData)

local Economy = {}

----------------------------------------------------------------------
-- Улучшения
----------------------------------------------------------------------

-- Цена перехода с level на level+1 (nil, если уже максимум)
function Economy.upgradeCost(id: Config.UpgradeId, level: number): number?
	local def = Config.Upgrades[id]
	if level >= def.MaxLevel then
		return nil
	end
	return math.floor(def.BaseCost * def.Growth ^ level + 0.5)
end

function Economy.rodMult(level: number): number
	return 1 + Config.UpgradeEffects.RodAddPerLevel * level
end

function Economy.jarCapacity(level: number): number
	local e = Config.UpgradeEffects
	return math.floor(e.JarBase * e.JarGrowth ^ level + 0.5)
end

function Economy.walkSpeed(level: number): number
	local e = Config.UpgradeEffects
	return e.BootsBase + e.BootsPerLevel * level
end

function Economy.rateMult(magnetLevel: number): number
	return 1 + Config.UpgradeEffects.MagnetRatePerLevel * magnetLevel
end

function Economy.extraRings(magnetLevel: number): number
	local n = 0
	for _, lvl in Config.UpgradeEffects.MagnetExtraRingLevels do
		if magnetLevel >= lvl then
			n += 1
		end
	end
	return n
end

function Economy.zapStun(insulationLevel: number): number
	return math.max(0.2, Config.Catch.ZapStun - Config.UpgradeEffects.InsulationStunPerLevel * insulationLevel)
end

-- Текст эффекта для магазина: текущий и следующий уровень
function Economy.effectText(id: Config.UpgradeId, level: number): string
	if id == "Rod" then
		return string.format("заряд ×%s", Economy.shortMult(Economy.rodMult(level)))
	elseif id == "Jar" then
		-- «вместимость 25», «вместимость 1.2K»: без слова после числа — не нужно согласовывать падеж
		return "вместимость " .. Format.short(Economy.jarCapacity(level))
	elseif id == "Boots" then
		return string.format("скорость %d", Economy.walkSpeed(level))
	elseif id == "Magnet" then
		local extra = Economy.extraRings(level)
		return string.format("частота +%d%%%s", math.floor((Economy.rateMult(level) - 1) * 100 + 0.5), if extra > 0 then string.format(", колец +%d", extra) else "")
	else
		return string.format("риск −%d%%", math.floor(Config.UpgradeEffects.InsulationRiskPerLevel * level * 100 + 0.5))
	end
end

function Economy.shortMult(m: number): string
	if m >= 100 then
		return string.format("%d", math.floor(m))
	elseif m >= 10 then
		return string.format("%.1f", m)
	end
	return string.format("%.2f", m)
end

----------------------------------------------------------------------
-- Заряд и сдача
----------------------------------------------------------------------

-- Заряд за одну поимку
function Economy.catchCharge(zone: number, color: Config.ColorId, grade: "perfect" | "good", combo: number, rodLevel: number, eventMult: number?): number
	local base = Config.Zones[zone].BaseCharge
	local cm = Config.Colors[color].Mult
	local gm = if grade == "perfect" then Config.Catch.PerfectMult else Config.Catch.GoodMult
	local combom = 1 + Config.Catch.ComboStep * math.clamp(combo, 0, Config.Catch.ComboCap)
	return base * cm * gm * combom * Economy.rodMult(rodLevel) * (eventMult or 1)
end

-- Сколько заряда можно держать в банке (с перегрузкой или без)
function Economy.maxCharge(capacity: number, overchargeAllowed: boolean): number
	if overchargeAllowed then
		return capacity * Config.Overcharge.MaxFill
	end
	return capacity
end

-- Вольты за сдачу банки (заряд сверх 100% стоит ×1.5)
function Economy.sellValue(charge: number, capacity: number, multiplier: number): number
	local normal = math.min(charge, capacity)
	local over = math.max(0, charge - capacity)
	return math.floor((normal + over * Config.Overcharge.SellBonus) * multiplier + 0.5)
end

----------------------------------------------------------------------
-- Множители
----------------------------------------------------------------------
export type MultContext = {
	friends: number?, -- друзей на сервере
	cityBoost: boolean?, -- "Город сияет"
	now: number?, -- os.time() для личных бустов
}

function Economy.rebirthMult(rebirths: number): number
	return 1 + Config.Rebirth.MultPerRebirth * rebirths
end

-- Сколько островов полностью собрано в Молниедексе (все 5 обычных цветов)
function Economy.indexRows(d: PlayerData.Data): number
	local rows = 0
	for z = 1, #Config.Zones do
		local full = true
		for _, c in Config.NormalColors do
			if not d.Index[z .. ":" .. c] then
				full = false
				break
			end
		end
		if full then
			rows += 1
		end
	end
	return rows
end

-- Бонус фульгурита зависит только от seed/цвета/мутации — кэшируем, чтобы не строить геометрию заново
local fulgBonusCache: { [string]: number } = {}
function Economy.fulgRecordBonus(f: PlayerData.FulgRecord): number
	local key = f.Seed .. ":" .. f.Color .. ":" .. (f.Mut or "")
	local cached = fulgBonusCache[key]
	if cached then
		return cached
	end
	local bonus = Fulgurite.generate(f.Seed, f.Color, f.Mut :: any).Bonus
	fulgBonusCache[key] = bonus
	return bonus
end

function Economy.fulgBonus(d: PlayerData.Data): number
	local total = 0
	for _, id in d.EquippedFulgs do
		local f = PlayerData.findFulg(d, id)
		if f then
			total += Economy.fulgRecordBonus(f)
		end
	end
	return total
end

function Economy.petBonuses(d: PlayerData.Data): Pets.Bonuses
	return Pets.totalBonus(PlayerData.equippedKinds(d))
end

-- Итоговый множитель Вольт при сдаче банки
function Economy.multiplier(d: PlayerData.Data, ctx: MultContext?): number
	local c: MultContext = ctx or {}
	local m = Economy.rebirthMult(d.Rebirths)
	m *= 1 + Economy.petBonuses(d).volts
	m *= 1 + Economy.fulgBonus(d)
	m *= 1 + Config.Multipliers.IndexRowBonus * Economy.indexRows(d)
	local friends = c.friends or 0
	m *= 1 + math.min(Config.Multipliers.FriendBonusMax, Config.Multipliers.FriendBonus * friends)
	if c.cityBoost then
		m *= Config.Multipliers.CityBoost
	end
	local now = c.now
	if now and d.Boosts.Volts2x > now then
		m *= 2
	end
	return m
end

function Economy.petSlots(rebirths: number): number
	local n = Config.Rebirth.BasePetSlots
	for _, r in Config.Rebirth.PetSlotsAt do
		if rebirths >= r then
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------------
-- Острова и перезапуск
----------------------------------------------------------------------
function Economy.zoneCost(zone: number): number
	return Config.Zones[zone].Cost
end

function Economy.rebirthCost(rebirths: number): number
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ rebirths)
end

function Economy.canRebirth(d: PlayerData.Data): boolean
	return d.Zone >= Config.Rebirth.RequiredZone and d.Volts >= Economy.rebirthCost(d.Rebirths)
end

-- Награда "N минут дохода" (не меньше минимума, чтобы новичку тоже было приятно)
function Economy.incomeMinutes(d: PlayerData.Data, minutes: number): number
	local rate = math.max(Config.MinIncomePerMinute, d.IncomeRate)
	return math.floor(rate * minutes)
end

-- Обновить сглаженный доход в минуту (вызывать раз в минуту активной игры)
function Economy.updateIncomeRate(old: number, earnedLastMinute: number): number
	if old <= 0 then
		return earnedLastMinute
	end
	return old * 0.8 + earnedLastMinute * 0.2
end

return Economy
