--!strict
-- Kit registry. Lune-safe.
-- Kits.Get(id) -> KitDef?, Kits.All() -> {KitDef} (sorted by role then Order), Kits.ForRole(role),
-- Kits.Ability(kitId, abilityId) -> AbilityDef?, Kits.AbilityBySlot(kitId, slot) -> AbilityDef?
local Types = require(script.Parent.Types)

type KitDef = Types.KitDef
type AbilityDef = Types.AbilityDef

local Kits = {}

local MODULES = {
	script.Monsters.ClassicSans,
	script.Monsters.FellSans,
	script.Monsters.EclipseSans,
	script.Monsters.LastBreathSans,
	script.Humans.Determination,
	script.Humans.Patience,
	script.Humans.Bravery,
	script.Humans.Integrity,
	script.Humans.Perseverance,
	script.Humans.Kindness,
	script.Humans.Justice,
}

local byId: { [string]: KitDef } = {}
local list: { KitDef } = {}

for _, module in MODULES do
	local kit: KitDef = require(module) :: any
	assert(byId[kit.Id] == nil, "duplicate kit id " .. kit.Id)
	byId[kit.Id] = kit
	table.insert(list, kit)
end

table.sort(list, function(a, b)
	if a.Role ~= b.Role then
		return a.Role == "Monster"
	end
	return a.Order < b.Order
end)

Kits.DefaultHuman = "Determination"
Kits.DefaultMonster = "ClassicSans"

function Kits.Get(id: string): KitDef?
	return byId[id]
end

function Kits.All(): { KitDef }
	return list
end

function Kits.ForRole(role: Types.Role): { KitDef }
	local out = {}
	for _, kit in list do
		if kit.Role == role then
			table.insert(out, kit)
		end
	end
	return out
end

function Kits.Ability(kitId: string, abilityId: string): AbilityDef?
	local kit = byId[kitId]
	if not kit then
		return nil
	end
	for _, ability in kit.Abilities do
		if ability.Id == abilityId then
			return ability
		end
	end
	return nil
end

function Kits.AbilityBySlot(kitId: string, slot: Types.Slot): AbilityDef?
	local kit = byId[kitId]
	if not kit then
		return nil
	end
	for _, ability in kit.Abilities do
		if ability.Slot == slot then
			return ability
		end
	end
	return nil
end

function Kits.Skin(kitId: string, skinId: string): Types.SkinDef?
	local kit = byId[kitId]
	if not kit then
		return nil
	end
	for _, skin in kit.Skins do
		if skin.Id == skinId then
			return skin
		end
	end
	return nil
end

-- Every icon name used by kit data; UI/Icons.luau must implement all of them.
Kits.IconNames = {
	"Bone", "Blaster", "BlueSoul", "BoneZone", "BoneWall", "Teleport", "Eye", "Skull", "Dash", "Sword",
	"Chain", "Rage", "Crown", "Wave", "Portal", "Orb", "Star", "Trap", "Moon", "Eclipse", "Knife",
	"Afterimage", "Heart", "Clock", "Ribbon", "Stealth", "Fist", "Shield", "Flame", "Shoe", "Spin",
	"Book", "Rewind", "Pan", "Food", "Gun", "Bullet", "Target", "Box",
}

return Kits
