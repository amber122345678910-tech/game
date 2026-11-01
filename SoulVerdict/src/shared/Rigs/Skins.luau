--!strict
-- Skins: per-kit skin lookup for rigs (SPEC §5.4). [Lune-safe]
-- Thin wrapper over the kit data (Shared/Kits/**, KitDef.Skins). RigBuilder.Build merges a skin's
-- palette overrides over the blueprint palette (blueprint Palette <- skin Palette <- opts.Palette);
-- menus use List/Get for names, rarity and prices.
--
-- API
--   Skins.Get(kitId, skinId?) -> SkinInfo?
--       SkinInfo = { Id, Name: Localized, Palette: {[string]: Color3} (overrides, a fresh copy),
--                    Rarity, Price, Mastery? }
--       skinId nil / "" / "Default" -> the kit's "Default" entry (empty Palette). nil when the kit or
--       the skin is unknown. kitId may also be a blueprint id (a kit whose Rig equals it).
--   Skins.Palette(kitId, skinId?) -> {[string]: Color3}   the overrides only ({} when unknown)
--   Skins.List(kitId) -> {SkinInfo}                        in kit order ({} when the kit is unknown)
--   Skins.Has(kitId, skinId) -> boolean

local Kits = require(script.Parent.Parent.Kits)
local Types = require(script.Parent.Parent.Types)

export type SkinInfo = {
	Id: string,
	Name: Types.Localized,
	Palette: { [string]: Color3 },
	Rarity: string,
	Price: number,
	Mastery: number?,
}

local Skins = {}

local function kitFor(id: string): Types.KitDef?
	local kit = Kits.Get(id)
	if kit then
		return kit
	end
	for _, k in Kits.All() do
		if k.Rig == id then
			return k
		end
	end
	return nil
end

local function info(skin: Types.SkinDef): SkinInfo
	return {
		Id = skin.Id,
		Name = skin.Name,
		Palette = table.clone(skin.Palette or {}),
		Rarity = skin.Rarity,
		Price = skin.Price,
		Mastery = skin.Mastery,
	}
end

function Skins.Get(kitId: string, skinId: string?): SkinInfo?
	local kit = kitFor(kitId)
	if kit == nil then
		return nil
	end
	local wanted = if skinId == nil or skinId == "" then "Default" else skinId
	for _, skin in kit.Skins do
		if skin.Id == wanted then
			return info(skin)
		end
	end
	return nil
end

function Skins.Palette(kitId: string, skinId: string?): { [string]: Color3 }
	local skin = Skins.Get(kitId, skinId)
	return if skin then skin.Palette else {}
end

function Skins.List(kitId: string): { SkinInfo }
	local kit = kitFor(kitId)
	local out: { SkinInfo } = {}
	if kit then
		for _, skin in kit.Skins do
			table.insert(out, info(skin))
		end
	end
	return out
end

function Skins.Has(kitId: string, skinId: string): boolean
	return Skins.Get(kitId, skinId) ~= nil
end

return Skins
