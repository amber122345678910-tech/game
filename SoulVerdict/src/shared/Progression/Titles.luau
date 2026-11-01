--!strict
-- Titles: every equippable title (Profile.Titles / Equipped.Title, Player attribute "Title" = id, "" = none).
-- Pure + Lune-safe. Sources: one title per achievement (id = achievement id) and three per kit from mastery
-- (id "m_<KitId>_<3|6|10>"). Text lives in Strings/Progression under "prog.title.<id>".
--
--   Titles.Get(id) -> TitleDef?           Titles.Has(id) -> boolean        Titles.All() -> {TitleDef} (sorted)
--   Titles.Key(id) -> string              Titles.Text(id) -> Localized {en, ru} (id itself if unknown)
--   Titles.Color(id) -> Color3            rarity colour (mastery titles use the kit's signature colour)
--   Titles.ColorHex(id) -> string         "#rrggbb" for RichText
--   Titles.RarityColor[rarity] -> Color3  Titles.RarityOrder[rarity] -> 1..4
-- TitleDef = { Id, Key, Rarity, Color, Source = "Achievement"|"Mastery", KitId?, Level?, Order }

local Types = require(script.Parent.Parent.Types)
local Kits = require(script.Parent.Parent.Kits)
local Mastery = require(script.Parent.Mastery)
local Achievements = require(script.Parent.Achievements)
local Text = require(script.Parent.Parent.Strings.Progression) :: { [string]: Types.Localized }

export type TitleDef = {
	Id: string,
	Key: string,
	Rarity: string,
	Color: Color3,
	Source: string,
	KitId: string?,
	Level: number?,
	Order: number,
}

local Titles = {}

Titles.RarityColor = {
	Common = Color3.fromRGB(235, 235, 235),
	Rare = Color3.fromRGB(110, 200, 255),
	Epic = Color3.fromRGB(196, 120, 255),
	Legendary = Color3.fromRGB(255, 205, 70),
} :: { [string]: Color3 }

Titles.RarityOrder = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 } :: { [string]: number }

local MASTERY_RARITY: { [number]: string } = { [3] = "Rare", [6] = "Epic", [10] = "Legendary" }

local byId: { [string]: TitleDef } = {}
local all: { TitleDef } = {}

local function key(id: string): string
	return "prog.title." .. id
end

for _, ach in Achievements.List() do
	local def: TitleDef = {
		Id = ach.Title,
		Key = key(ach.Title),
		Rarity = ach.Rarity,
		Color = Titles.RarityColor[ach.Rarity] or Titles.RarityColor.Common,
		Source = "Achievement",
		Order = ach.Order,
	}
	byId[def.Id] = def
	table.insert(all, def)
end

for _, kit in Kits.All() do
	for _, lv in Mastery.TitleLevels do
		local id = Mastery.TitleId(kit.Id, lv)
		local def: TitleDef = {
			Id = id,
			Key = key(id),
			Rarity = MASTERY_RARITY[lv] or "Rare",
			Color = kit.Color,
			Source = "Mastery",
			KitId = kit.Id,
			Level = lv,
			Order = 1000 + kit.Order * 20 + lv + (if kit.Role == "Monster" then 0 else 300),
		}
		byId[id] = def
		table.insert(all, def)
	end
end

table.sort(all, function(a, b)
	return a.Order < b.Order
end)

function Titles.Get(id: string): TitleDef?
	return byId[id]
end

function Titles.Has(id: string): boolean
	return byId[id] ~= nil
end

function Titles.All(): { TitleDef }
	return all
end

function Titles.Key(id: string): string
	return key(id)
end

function Titles.Text(id: string): Types.Localized
	local entry = Text[key(id)]
	if entry then
		return entry
	end
	return { en = id, ru = id }
end

function Titles.Color(id: string): Color3
	local def = byId[id]
	return if def then def.Color else Titles.RarityColor.Common
end

function Titles.ColorHex(id: string): string
	local c = Titles.Color(id)
	return ("#%02x%02x%02x"):format(
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end

return Titles
