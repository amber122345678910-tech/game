--!strict
-- PixelIcons: the owner's 112 pixel icons (ChatGPT sheets, sliced to 32x32; docs/ICON_SHEETS.md). Lune-safe.
-- Keys: "Skin.<KitId>.<SkinId>", "Kit.<KitId>", "Ability.<AbilityId>", "UI.<Name>", "Rarity.<Rarity>", "Item.<Name>".
--
-- API
--   PixelIcons.Has(key) -> boolean          PixelIcons.Keys() -> {string}
--   PixelIcons.Size -> 32
--   PixelIcons.Runs(key) -> { {X, Y, Len, Color} }?   merged horizontal runs (0-based X/Y), cached
--   PixelIcons.Resolve(name) -> string?    a pixel key for `name` (itself, or a UI alias like "Gold" -> "UI.Gold")
--   PixelIcons.AbilityIcon(ability) -> string   "Ability.<Id>" when drawn, else ability.Icon
--   PixelIcons.KitIcon(kitId) -> string?   "Kit.<KitId>" when drawn
--   PixelIcons.SkinIcon(kitId, skinId) -> string?   "Skin.<KitId>.<SkinId>" when drawn

local PixelIcons = {}
PixelIcons.Size = 32

local CH = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local data: { [string]: any } = {}
for n = 1, 7 do
	local module = (script.Parent :: any).IconData:FindFirstChild("Sheet" .. n)
	if module then
		local ok, sheet = pcall(require, module)
		if ok and type(sheet) == "table" then
			for key, icon in sheet do
				data[key] = icon
			end
		end
	end
end

-- vector icon names that read better as the owner's pixel icons (unambiguous UI names only)
PixelIcons.Aliases = {
	Gold = "UI.Gold",
	Exp = "UI.Exp",
	Quests = "UI.Quests",
	Trophy = "UI.Trophy",
	Shop = "UI.Shop",
	Settings = "UI.Settings",
	Music = "UI.Music",
	Crown = "UI.Admin",
	Box = "UI.VerdictBox",
	Soul = "UI.SoulRed",
}

function PixelIcons.Has(key: string?): boolean
	return type(key) == "string" and data[key] ~= nil
end

function PixelIcons.Keys(): { string }
	local out = {}
	for key in data do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

function PixelIcons.Resolve(name: string?): string?
	if type(name) ~= "string" then
		return nil
	end
	if data[name] then
		return name
	end
	local alias = PixelIcons.Aliases[name]
	return if alias and data[alias] then alias else nil
end

local function hex(h: string): Color3
	return Color3.fromRGB(tonumber(string.sub(h, 1, 2), 16) or 0, tonumber(string.sub(h, 3, 4), 16) or 0, tonumber(string.sub(h, 5, 6), 16) or 0)
end

local runsCache: { [string]: any } = {}

function PixelIcons.Runs(key: string): { { X: number, Y: number, Len: number, Color: Color3 } }?
	if runsCache[key] then
		return runsCache[key]
	end
	local icon = data[key]
	if icon == nil then
		return nil
	end
	local colors: { Color3 } = {}
	for i, h in icon.Palette do
		colors[i] = hex(h)
	end
	local runs = {}
	for y, row in icon.Rows do
		local x = 1
		local n = #row
		while x <= n do
			local ch = string.sub(row, x, x)
			if ch == "." then
				x += 1
			else
				local len = 1
				while x + len <= n and string.sub(row, x + len, x + len) == ch do
					len += 1
				end
				local idx = string.find(CH, ch, 1, true)
				table.insert(runs, { X = x - 1, Y = y - 1, Len = len, Color = colors[idx or 1] or Color3.new(1, 0, 1) })
				x += len
			end
		end
	end
	runsCache[key] = runs
	return runs
end

function PixelIcons.AbilityIcon(ability: any): string
	if type(ability) ~= "table" then
		return "Heart"
	end
	local key = "Ability." .. tostring(ability.Id)
	return if data[key] then key else ability.Icon
end

function PixelIcons.KitIcon(kitId: string?): string?
	local key = "Kit." .. tostring(kitId)
	return if data[key] then key else nil
end

function PixelIcons.SkinIcon(kitId: string?, skinId: string?): string?
	local key = "Skin." .. tostring(kitId) .. "." .. tostring(if skinId == nil or skinId == "" then "Default" else skinId)
	return if data[key] then key else nil
end

return PixelIcons
