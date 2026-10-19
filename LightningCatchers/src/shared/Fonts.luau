--!strict
-- Шрифты игры, docs/STYLE.md §8.3. Один источник для клиента (UI) и сервера (таблички над головой,
-- табло, подписи фульгуритов). Только Font.new: у Enum.Font вес зашит (Oswald и Nunito там только 400).
-- У всех трёх семейств полная кириллица (66 букв: А–Я, а–я, Ё, ё), проверено по клиенту 0.743.
-- BuilderSans, FredokaOne, LuckiestGuy, Bangers, Michroma кириллицы НЕ имеют: для русских строк не использовать.
-- Запасной набор (только встроенные начертания, §8.3.7) меняется только здесь.
-- Вес 900 в Roblox называется Enum.FontWeight.Heavy (в STYLE.md он записан как «Black» — такого пункта нет).

local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local OSWALD = "rbxasset://fonts/families/Oswald.json"
local NUNITO = "rbxasset://fonts/families/Nunito.json"

local Fonts = {
	-- Montserrat Black Italic (900, курсив): логотип, оценки, заголовки окон, кнопки-глаголы, строка 1 вывесок.
	-- Облачное начертание rbxassetid://11598119154: качается при первом использовании (прогрев в Main.client).
	Display = Font.new(MONTSERRAT, Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
	-- Montserrat Black (900, прямой), встроен: названия предметов и питомцев, глифы ◆ ▲ ▼.
	DisplayFlat = Font.new(MONTSERRAT, Enum.FontWeight.Heavy),
	-- Oswald Bold (700, узкий), встроен: валюта, цены, множители ×12, «+12 ⚡», большие счётчики.
	Number = Font.new(OSWALD, Enum.FontWeight.Bold),
	-- Nunito Bold (700, округлый), облачный rbxassetid://8075189006: описания, тосты, строки списков и табло, поле ввода.
	Body = Font.new(NUNITO, Enum.FontWeight.Bold),
	-- Nunito ExtraBold (800), облачный rbxassetid://8075191639: теги, вкладки, второстепенные кнопки, подписи плиток, таймеры.
	BodyHeavy = Font.new(NUNITO, Enum.FontWeight.ExtraBold),
}

-- Все начертания (для прогрева при старте клиента)
Fonts.All = { Fonts.Display, Fonts.DisplayFlat, Fonts.Number, Fonts.Body, Fonts.BodyHeavy } :: { Font }

return Fonts
