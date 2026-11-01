--!strict
-- Shop: the free daily cosmetic shop + purchase rules (SPEC §1.6, genre idea 18). Pure + Lune-safe.
-- Catalog = every SkinDef with Price > 0 and no Mastery gate (Mastery skins are earned, never sold).
-- Daily rotation (UTC day): the catalog is shuffled once per CYCLE (Util/Rng, seed = cycle index) and each
-- day of the cycle shows the next Config.Shop.DailySkins skins, so every skin comes back every few days;
-- the first day of a cycle is fixed up so it never repeats the previous day. One offer per day is
-- FEATURED at FeaturedDiscount off (the rarest of the day). Skins that are not in today's shop can
-- still be bought at full price (nothing is ever locked away); kits are always for sale (G + LV gate).
--
--   Shop.Day(unixTime) -> number                 Shop.DayEndsAt(day) -> unix time
--   Shop.Catalog() -> {CatalogItem}              sorted by Key
--   Shop.Daily(day) -> DailyShop                 { Day, EndsAt, Offers = {Offer}, Items (= Offers), Discount }
--   Shop.PriceFor(kitId, skinId, day) -> (price, featured)    nil price = not for sale
--   Shop.ParseItem(data) -> Item?                accepts {kind="Kit"|"Skin", kitId, skinId?} (+ PascalCase)
--   Shop.CheckBuy(profile, item, day) -> (ok, errKey?, price?)
--   Shop.Apply(profile, item, price)             Gold -= price, Unlocked[...] = true (after CheckBuy)
-- CatalogItem = { Key = "kitId:skinId", KitId, SkinId, Price, Rarity }
-- Offer = CatalogItem + { BasePrice, Featured } (Price = discounted price when featured)
-- Item = { Kind = "Kit"|"Skin", KitId, SkinId? }

local Config = require(script.Parent.Parent.Config)
local Kits = require(script.Parent.Parent.Kits)
local Rng = require(script.Parent.Parent.Util.Rng)

export type CatalogItem = { Key: string, KitId: string, SkinId: string, Price: number, Rarity: string }
export type Offer = {
	Key: string,
	KitId: string,
	SkinId: string,
	Price: number,
	BasePrice: number,
	Rarity: string,
	Featured: boolean,
}
export type DailyShop = { Day: number, EndsAt: number, Offers: { Offer }, Items: { Offer }, Discount: number }
export type Item = { Kind: string, KitId: string, SkinId: string? }

local Shop = {}

Shop.FeaturedDiscount = 0.2
Shop.PerDay = math.max(1, Config.Shop.DailySkins :: number)
Shop.MaxGold = 1e9

local DAY = 86400
local RARITY_RANK: { [string]: number } = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

local catalog: { CatalogItem }? = nil
local dailyCache: { [number]: DailyShop } = {}

function Shop.Day(unixTime: number): number
	return math.floor(unixTime / DAY)
end

function Shop.DayEndsAt(day: number): number
	return (day + 1) * DAY
end

function Shop.Catalog(): { CatalogItem }
	if catalog then
		return catalog
	end
	local items: { CatalogItem } = {}
	for _, kit in Kits.All() do
		for _, skin in kit.Skins do
			if skin.Price > 0 and skin.Mastery == nil then
				table.insert(items, {
					Key = kit.Id .. ":" .. skin.Id,
					KitId = kit.Id,
					SkinId = skin.Id,
					Price = skin.Price,
					Rarity = skin.Rarity,
				})
			end
		end
	end
	table.sort(items, function(a, b)
		return a.Key < b.Key
	end)
	catalog = items
	return items
end

local function discounted(price: number): number
	return math.max(0, math.floor(price * (1 - Shop.FeaturedDiscount) / 10 + 0.5) * 10)
end

-- Raw permutation of catalog indices for one cycle.
local function rawCycle(cycle: number, count: number): { number }
	local order = table.create(count, 0)
	for i = 1, count do
		order[i] = i
	end
	return Rng.new(Rng.Hash("SV_Shop", cycle)):Shuffle(order)
end

-- Cycle permutation with day 1 fixed against the previous cycle's last day. Only window 1 and the
-- positions after it except the LAST window are swapped, so the last window of every cycle is its raw
-- one and the fix-up never recurses.
local function cyclePerm(cycle: number, count: number, per: number, windows: number): { number }
	local perm = rawCycle(cycle, count)
	if windows < 2 then
		return perm
	end
	local prev = rawCycle(cycle - 1, count)
	local blocked: { [number]: boolean } = {}
	for i = (windows - 1) * per + 1, windows * per do
		blocked[prev[i]] = true
	end
	local lastStart = (windows - 1) * per + 1
	local partners: { number } = {}
	for pos = per + 1, count do
		if (pos < lastStart or pos > windows * per) and not blocked[perm[pos]] then
			table.insert(partners, pos)
		end
	end
	local p = 1
	for pos = 1, per do
		if blocked[perm[pos]] and partners[p] then
			local other = partners[p]
			perm[pos], perm[other] = perm[other], perm[pos]
			p += 1
		end
	end
	return perm
end

function Shop.Daily(day: number): DailyShop
	local cached = dailyCache[day]
	if cached then
		return cached
	end
	local items = Shop.Catalog()
	local count = #items
	local per = math.min(Shop.PerDay, count)
	local chosen: { CatalogItem } = {}
	if count > 0 then
		local windows = math.max(1, math.floor(count / per))
		local cycle = math.floor(day / windows)
		local slot = day - cycle * windows -- 0 .. windows-1 (also correct for negative days)
		local perm = cyclePerm(cycle, count, per, windows)
		for i = slot * per + 1, slot * per + per do
			table.insert(chosen, items[perm[i]])
		end
	end
	-- featured: the rarest offer of the day (ties broken deterministically)
	local featuredIndex = 0
	local bestRank, bestRoll = -1, -1
	local rng = Rng.new(Rng.Hash("SV_ShopFeatured", day))
	for i, item in chosen do
		local rank = RARITY_RANK[item.Rarity] or 0
		local roll = rng:Number()
		if rank > bestRank or (rank == bestRank and roll > bestRoll) then
			bestRank, bestRoll, featuredIndex = rank, roll, i
		end
	end
	local offers: { Offer } = {}
	for i, item in chosen do
		local featured = i == featuredIndex
		table.insert(offers, {
			Key = item.Key,
			KitId = item.KitId,
			SkinId = item.SkinId,
			Price = if featured then discounted(item.Price) else item.Price,
			BasePrice = item.Price,
			Rarity = item.Rarity,
			Featured = featured,
		})
	end
	local shop: DailyShop = {
		Day = day,
		EndsAt = Shop.DayEndsAt(day),
		Offers = offers,
		Items = offers, -- alias read by the Shop screen
		Discount = Shop.FeaturedDiscount,
	}
	-- keep the cache small (today, yesterday, tomorrow are the only days a server asks for)
	local size = 0
	for _ in dailyCache do
		size += 1
	end
	if size > 8 then
		table.clear(dailyCache)
	end
	dailyCache[day] = shop
	return shop
end

function Shop.PriceFor(kitId: string, skinId: string, day: number): (number?, boolean)
	local skin = Kits.Skin(kitId, skinId)
	if skin == nil or skin.Price <= 0 or skin.Mastery ~= nil then
		return nil, false
	end
	for _, offer in Shop.Daily(day).Offers do
		if offer.KitId == kitId and offer.SkinId == skinId then
			return offer.Price, offer.Featured
		end
	end
	return skin.Price, false
end

local function str(v: any): string?
	if type(v) == "string" and #v > 0 and #v <= 40 and string.match(v, "^[%w_]+$") then
		return v
	end
	return nil
end

function Shop.ParseItem(data: any): Item?
	if type(data) ~= "table" then
		return nil
	end
	local kind = data.kind or data.Kind
	local kitId = str(data.kitId or data.KitId)
	local skinId = str(data.skinId or data.SkinId)
	if kitId == nil then
		return nil
	end
	if kind == nil then
		kind = if skinId then "Skin" else "Kit"
	end
	if kind == "Kit" then
		return { Kind = "Kit", KitId = kitId }
	elseif kind == "Skin" and skinId then
		return { Kind = "Skin", KitId = kitId, SkinId = skinId }
	end
	return nil
end

function Shop.CheckBuy(profile: any, item: Item, day: number): (boolean, string?, number?)
	local kit = Kits.Get(item.KitId)
	if kit == nil then
		return false, "prog.err.unknownItem", nil
	end
	local gold = tonumber(profile.Gold) or 0
	if item.Kind == "Kit" then
		if profile.Unlocked[kit.Id] then
			return false, "prog.err.owned", nil
		end
		local price = kit.Unlock.Gold
		local needLevel = kit.Unlock.Level or 1
		if (tonumber(profile.Level) or 1) < needLevel then
			return false, "prog.err.level", nil
		end
		if gold < price then
			return false, "prog.err.gold", price
		end
		return true, nil, price
	end
	local skinId = item.SkinId
	if skinId == nil then
		return false, "prog.err.unknownItem", nil
	end
	local skin = Kits.Skin(kit.Id, skinId)
	if skin == nil then
		return false, "prog.err.unknownItem", nil
	end
	if profile.Unlocked[kit.Id .. ":" .. skinId] or skinId == "Default" then
		return false, "prog.err.owned", nil
	end
	if skin.Mastery ~= nil then
		return false, "prog.err.masteryOnly", nil
	end
	if not profile.Unlocked[kit.Id] then
		return false, "prog.err.needKit", nil
	end
	local price = Shop.PriceFor(kit.Id, skinId, day)
	if price == nil then
		return false, "prog.err.notForSale", nil
	end
	if gold < price then
		return false, "prog.err.gold", price
	end
	return true, nil, price
end

function Shop.Apply(profile: any, item: Item, price: number)
	profile.Gold = math.max(0, (tonumber(profile.Gold) or 0) - price)
	if item.Kind == "Kit" then
		profile.Unlocked[item.KitId] = true
		profile.Unlocked[item.KitId .. ":Default"] = true
	elseif item.SkinId then
		profile.Unlocked[item.KitId .. ":" .. item.SkinId] = true
	end
end

return Shop
