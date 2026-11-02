--!strict
-- Localisation. Lune-safe.
-- Every child module of this folder returns { [key] = { en = "...", ru = "..." } } and is merged here.
-- Usage: Strings.L("menu.play"), Strings.L("hud.timer", 12), Strings.Pick(kit.Name)
-- Placeholders: {1}, {2}, ... are replaced by the extra arguments (tostring-ed).
-- Each area owns its own file (Core, Menu, Hud, Round, Kits, Progression, StyleLab, VerdictBox...).

local Types = require(script.Parent.Types)

type Localized = Types.Localized

local Strings = {}

local SOURCES = {
	"Core",
	"Menu",
	"Hud",
	"Round",
	"Progression",
	"StyleLab",
	"VerdictBox",
	"Maps",
	"Graphics",
	"Settings",
	"Screens",
	"KitText",
	"Lobby",
	"Tutorial",
	"Controls",
	"KitFell",
	"KitEclipse",
	"KitHumansA",
	"KitHumansB",
	"Integration",
	"Maps3",
	"Maps2",
	"Admin",
	"MobileUI",
	"Loading",
}

local merged: { [string]: Localized } = {}
local language: "en" | "ru" = "en"

for _, name in SOURCES do
	local child = (script :: any):FindFirstChild(name)
	if child then
		local ok, tbl = pcall(require, child)
		if ok and type(tbl) == "table" then
			for key, value in tbl :: any do
				if merged[key] ~= nil then
					warn(("Strings: duplicate key %s (in %s)"):format(key, name))
				end
				merged[key] = value
			end
		else
			warn("Strings: failed to load " .. name .. ": " .. tostring(tbl))
		end
	end
end

function Strings.SetLanguage(lang: string)
	if lang == "ru" then
		language = "ru"
	else
		language = "en"
	end
end

function Strings.Language(): "en" | "ru"
	return language
end

-- Picks the current-language string from a Localized table (falls back to en).
function Strings.Pick(tbl: Localized?): string
	if tbl == nil then
		return ""
	end
	local s = (tbl :: any)[language]
	if type(s) == "string" and s ~= "" then
		return s
	end
	return tbl.en or ""
end

local function format(template: string, ...: any): string
	local args = table.pack(...)
	return (
		string.gsub(template, "{(%d+)}", function(index: string): string?
			local i = tonumber(index)
			if i and i <= args.n then
				return tostring(args[i])
			end
			return nil
		end)
	)
end

function Strings.L(key: string, ...: any): string
	local entry = merged[key]
	if entry == nil then
		return key
	end
	return format(Strings.Pick(entry), ...)
end

function Strings.Has(key: string): boolean
	return merged[key] ~= nil
end

function Strings.Register(tbl: { [string]: Localized })
	for key, value in tbl do
		merged[key] = value
	end
end

function Strings.AllKeys(): { string }
	local keys = {}
	for key in merged do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

return Strings
