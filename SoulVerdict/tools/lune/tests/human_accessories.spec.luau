--!nocheck
-- Owner rule: the human SOULs get no outfit skins - a human skin may only recolour accessories (the held weapon and
-- small worn items), never the sweater, pants, skin or hair.
local ACCESSORY_KEYS = {
	-- held weapons (Rigs/Props/Weapons palette keys)
	Blade = true, Handle = true, ToyBlade = true, ToyHandle = true, Book = true, Page = true, BookTrim = true,
	Pan = true, PanHandle = true, Gun = true, GunGrip = true, GunTrim = true,
	-- small worn items (Undertale armour pieces)
	Ribbon = true, Bandanna = true, Glove = true, Shoes = true, Hat = true, Glasses = true,
}

return {
	human_skins_are_accessories_only = function(T, Loader)
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		local humans = 0
		for _, kit in Kits.All() do
			if kit.Role == "Human" then
				humans += 1
				for _, skin in kit.Skins or {} do
					local keys = 0
					for key in skin.Palette or {} do
						keys += 1
						T.ok(ACCESSORY_KEYS[key] == true, ("%s skin %s recolours %s (only accessories allowed)"):format(kit.Id, skin.Id, key))
					end
					if skin.Id ~= "Default" then
						T.ok(keys > 0, ("%s skin %s changes at least one accessory"):format(kit.Id, skin.Id))
					end
				end
			end
		end
		T.eq(humans, 7, "seven human SOUL kits")
	end,
}
