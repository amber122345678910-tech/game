--!strict
-- Локализация: английский и русский.
--
-- Исходный язык кода — русский: строки для игрока пишутся в коде по-русски и оборачиваются в Loc.t(...),
-- а словари src/shared/Strings/*.luau переводят их на английский ({ [русский исходник] = "English" }).
-- Язык игрока: настройка Settings.Lang ("en" | "ru"), а если она пустая — локаль аккаунта Roblox
-- (ru* → русский, всё остальное → английский). Английский — язык по умолчанию: игра для всего мира.
--
-- Правила для переводов (их проверяет tools/check_loc.luau):
--  * плейсхолдеры string.format (%d, %s, %.1f, %%) в переводе те же и в том же порядке, что в исходнике;
--  * множественное число — одной строкой через «|»: Loc.plural(n, "минута|минуты|минут") ↔ "minute|minutes";
--  * переводятся только строки для игрока; логи (warn/print) и имена объектов остаются как есть.
--
-- Сервер не знает языка игрока и не переводит сам: тексты для клиента он отправляет как Loc.msg(исходник, аргументы...)
-- (таблица { fmt, arg1, ... }), а клиент рисует их через Loc.render на своём языке. Простая строка-исходник тоже годится.
-- Строковые аргументы, которые сами есть в словаре (имена питомцев, островов, цветов), переводятся автоматически.
--
-- Надписи в мире (таблички карты, табло, подписи над головой, ProximityPrompt) видят игроки на разных языках:
-- у объекта свойство (Text, ActionText, ObjectText) — по-английски, а атрибут "Loc_<свойство>" хранит исходник
-- (Loc.encode). Клиент с русским языком подменяет свойство локально (Controllers/WorldText). Сервер ставит такие
-- надписи через Loc.setWorldText, генератор карты — через B.text (tools/lib/builder.luau).

local Loc = {}

export type Lang = "en" | "ru"
-- Сообщение для перевода на клиенте: { fmt, arg1, arg2, ... }. Аргумент — число, строка или вложенное сообщение
export type Msg = { any }

local SEP = "\31" -- разделитель полей в атрибуте
local PLURAL = "#plural" -- служебный fmt: { "#plural", n, "форма1|форма2|форма3" }

----------------------------------------------------------------------
-- Словарь
----------------------------------------------------------------------
local EN: { [string]: string } = {}
-- Повторы ключей с разным переводом (их показывает tools/check_loc.luau)
Loc.Conflicts = {} :: { { key: string, a: string, b: string } }

local function merge(tbl: { [string]: string })
	for k, v in tbl do
		local prev = EN[k]
		if prev ~= nil and prev ~= v then
			table.insert(Loc.Conflicts, { key = k, a = prev, b = v })
		else
			EN[k] = v
		end
	end
end

local Strings = script.Parent.Strings
merge(require(Strings.Shared) :: any)
merge(require(Strings.Server) :: any)
merge(require(Strings.Server2) :: any)
merge(require(Strings.HUD) :: any)
merge(require(Strings.ShopPets) :: any)
merge(require(Strings.Windows) :: any)
merge(require(Strings.Windows2) :: any)
merge(require(Strings.Controllers) :: any)
merge(require(Strings.Map) :: any)

Loc.EN = EN

----------------------------------------------------------------------
-- Язык
----------------------------------------------------------------------
local current: Lang = "en"

function Loc.lang(): Lang
	return current
end

function Loc.setLang(lang: Lang)
	current = lang
end

-- Язык по настройке ("en" | "ru" | "" / nil — авто) и локали Roblox (например "ru-ru", "en-us")
function Loc.pick(setting: string?, localeId: string?): Lang
	if setting == "en" or setting == "ru" then
		return setting
	end
	local id = string.lower(localeId or "")
	if string.sub(id, 1, 2) == "ru" then
		return "ru"
	end
	return "en"
end

-- Локаль аккаунта Roblox на клиенте (без game на этапе загрузки модуля: Lune-тесты грузят его без движка)
function Loc.localeId(): string
	local id = ""
	pcall(function()
		local g: any = game
		local ls: any = g:GetService("LocalizationService")
		id = ls.RobloxLocaleId or ""
		if id == "" then
			local lp: any = g:GetService("Players").LocalPlayer
			id = if lp then lp.LocaleId or "" else ""
		end
	end)
	return id
end

----------------------------------------------------------------------
-- Перевод
----------------------------------------------------------------------
-- Ключ с контекстом "ctx::исходник" — когда одна русская строка в разных местах переводится по-разному
-- ("kind::Обычный" → "Normal", а редкость "Обычный" → "Common"). По-русски показывается часть после "::"
local function lookup(lang: Lang, src: string): string
	local hit = EN[src]
	local cut = string.find(src, "::", 1, true)
	if lang == "ru" then
		return if cut then string.sub(src, cut + 2) else src
	end
	if hit then
		return hit
	end
	if cut then
		local plain = string.sub(src, cut + 2)
		return EN[plain] or plain
	end
	return src
end

-- Русское множественное число: 1 минута, 2 минуты, 5 минут
local function ruForm(n: number): number
	local m = math.floor(math.abs(n)) % 100
	local m10 = m % 10
	if m10 == 1 and m ~= 11 then
		return 1
	elseif m10 >= 2 and m10 <= 4 and (m < 12 or m > 14) then
		return 2
	end
	return 3
end

local function pluralIn(lang: Lang, n: number, forms: string): string
	local text = lookup(lang, forms)
	local parts = string.split(text, "|")
	if lang == "ru" then
		return parts[ruForm(n)] or parts[#parts] or text
	end
	return if n == 1 then parts[1] else (parts[2] or parts[1])
end

local renderIn: (Lang, any) -> string

-- Аргумент формата: числа как есть, строки-исходники переводятся, сообщения рисуются
local function argIn(lang: Lang, a: any): any
	local ty = typeof(a)
	if ty == "string" then
		return lookup(lang, a)
	elseif ty == "table" then
		return renderIn(lang, a)
	end
	return a
end

local function formatIn(lang: Lang, src: string, args: { any }, n: number): string
	local fmt = lookup(lang, src)
	if n == 0 then
		return fmt
	end
	local conv = table.create(n)
	for i = 1, n do
		conv[i] = argIn(lang, args[i])
	end
	local ok, out = pcall(string.format, fmt, table.unpack(conv, 1, n))
	if ok then
		return out
	end
	-- перевод сломан (не те плейсхолдеры) — лучше показать исходник, чем ничего
	local ok2, out2 = pcall(string.format, src, table.unpack(conv, 1, n))
	return if ok2 then out2 else src
end

renderIn = function(lang: Lang, x: any): string
	local ty = typeof(x)
	if ty == "string" then
		return lookup(lang, x)
	elseif ty == "table" then
		local fmt = x[1]
		if fmt == PLURAL then
			return pluralIn(lang, tonumber(x[2]) or 0, tostring(x[3]))
		end
		if typeof(fmt) ~= "string" then
			return ""
		end
		local n = math.max(0, #x - 1)
		local args = table.create(n)
		for i = 1, n do
			args[i] = x[i + 1]
		end
		return formatIn(lang, fmt, args, n)
	elseif x == nil then
		return ""
	end
	return tostring(x)
end

-- Перевести исходник на язык игрока; с аргументами — ещё и string.format
function Loc.t(src: string, ...: any): string
	local n = select("#", ...)
	if n == 0 then
		return lookup(current, src)
	end
	return formatIn(current, src, { ... }, n)
end

-- То же для явного языка (надписи в мире, тесты)
function Loc.tl(lang: Lang, src: string, ...: any): string
	local n = select("#", ...)
	if n == 0 then
		return lookup(lang, src)
	end
	return formatIn(lang, src, { ... }, n)
end

-- Форма слова для числа n: Loc.plural(5, "минута|минуты|минут") → "минут" / "minutes"
function Loc.plural(n: number, forms: string): string
	return pluralIn(current, n, forms)
end

-- Сообщение, которое переведёт клиент (сервер → клиент: Notify, Banner, ответы Request)
function Loc.msg(src: string, ...: any): Msg
	return { src, ... }
end

-- Форма слова как аргумент сообщения: Loc.msg("на %d %s", m, Loc.pmsg(m, "минуту|минуты|минут"))
function Loc.pmsg(n: number, forms: string): Msg
	return { PLURAL, n, forms }
end

-- Нарисовать строку-исходник или сообщение на языке игрока
function Loc.render(x: any): string
	return renderIn(current, x)
end

function Loc.renderIn(lang: Lang, x: any): string
	return renderIn(lang, x)
end

-- Есть ли перевод у исходника
function Loc.has(src: string): boolean
	return EN[src] ~= nil
end

-- Заглавные буквы и для кириллицы (string.upper её не трогает)
function Loc.upper(s: string): string
	local out = {}
	for _, c in utf8.codes(s) do
		if c >= 0x430 and c <= 0x44F then
			c -= 0x20
		elseif c == 0x451 then
			c = 0x401
		elseif c >= 97 and c <= 122 then
			c -= 32
		end
		table.insert(out, utf8.char(c))
	end
	return table.concat(out)
end

----------------------------------------------------------------------
-- Надписи в мире
----------------------------------------------------------------------
-- Сообщение в строку атрибута: поля через \31, у каждого аргумента префикс типа (n — число, s — строка)
function Loc.encode(msg: Msg | string): string
	if typeof(msg) == "string" then
		return msg
	end
	local m = msg :: Msg
	local parts = { tostring(m[1]) }
	for i = 2, #m do
		local a = m[i]
		if typeof(a) == "number" then
			table.insert(parts, "n" .. tostring(a))
		else
			table.insert(parts, "s" .. (if typeof(a) == "table" then renderIn("ru", a) else tostring(a)))
		end
	end
	return table.concat(parts, SEP)
end

function Loc.decode(s: string): Msg
	local parts = string.split(s, SEP)
	local m: Msg = { parts[1] }
	for i = 2, #parts do
		local p = parts[i]
		local tag, rest = string.sub(p, 1, 1), string.sub(p, 2)
		if tag == "n" then
			table.insert(m, tonumber(rest) or 0)
		else
			table.insert(m, rest)
		end
	end
	return m
end

-- Атрибут с исходником для свойства prop ("Text", "ActionText", "ObjectText")
function Loc.attr(prop: string): string
	return "Loc_" .. prop
end

-- Поставить надпись в мире: свойство — по-английски (так её видят все и автоперевод Roblox),
-- атрибут — исходник для русского клиента. upper = true — заглавными (первая строка вывески)
function Loc.setWorldText(inst: Instance, prop: string, src: string, ...: any)
	local msg: Msg = { src, ... }
	local text = renderIn("en", msg)
	if inst:GetAttribute("LocUpper") then
		text = Loc.upper(text)
	end
	-- пишем только изменения: табло обновляются часто, а лишняя запись того же значения ничего не даёт
	local anyInst: any = inst
	if anyInst[prop] ~= text then
		anyInst[prop] = text
	end
	local attr, raw = Loc.attr(prop), Loc.encode(msg)
	if inst:GetAttribute(attr) ~= raw then
		inst:SetAttribute(attr, raw)
	end
end

-- Текст надписи в мире на языке lang по её атрибуту (nil — у свойства нет исходника)
function Loc.worldText(inst: Instance, prop: string, lang: Lang): string?
	local raw = inst:GetAttribute(Loc.attr(prop))
	if typeof(raw) ~= "string" then
		return nil
	end
	local text = renderIn(lang, Loc.decode(raw))
	if inst:GetAttribute("LocUpper") then
		text = Loc.upper(text)
	end
	return text
end

return Loc
