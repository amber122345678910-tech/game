--!strict
-- Английские переводы строк для игрока (ключ — русский исходник из кода). Глоссарий — в Strings/Shared.luau.
-- Контроллеры клиента (Tutorial, StrikeController, CharacterFX, EventFX, CatchController) и ClientState.
return {
	-- ClientState: запросы к серверу
	["Нет связи с сервером"] = "No connection to server",

	-- Tutorial: подсказки обучения
	["Встань в светящийся круг"] = "Step into the glowing ring",
	["Жми ⚡, когда круги сойдутся!"] = "Tap ⚡ when the rings meet!",
	["Жми ⚡ или E, когда круги сойдутся!"] = "Press ⚡ or E when the rings meet!",
	["Жми R2, когда круги сойдутся!"] = "Press R2 when the rings meet!",
	["Беги на остров ловить молнии!"] = "Run to an island to catch lightning!",
	["Сдай заряд на подстанции"] = "Sell your charge at the Substation",
	["Купи улучшение"] = "Buy an upgrade",
	["Открой новый остров в магазине!"] = "Unlock a new island in the Shop!",
	["Лети на новый остров!"] = "Fly to your new island!",
	["Банка полна — лови дальше, если не боишься!"] = "Jar full — keep catching if you dare!",

	-- StrikeController: подсказки новых типов ударов и надписи над кольцами
	["Обманка! Кольцо замрёт — жди"] = "Fake-out! The ring freezes — wait",
	["Бегущее! Беги за ним"] = "Runner! Chase it",
	["%s! Жми ⚡ %d раза"] = "%s! Hit ⚡ %d times",
	["Ещё %d раза!"] = "%d more!",
	["Ещё раз!"] = "One more!",
	["Банка полна — дрон в пути"] = "Jar full — drone on the way",
	["Банка полна!"] = "Jar full!",

	-- CharacterFX: дрон, банка, цепная молния
	["🤖 Дрон везёт заряд"] = "🤖 Drone delivering charge",
	["Банка лопнула!"] = "Jar burst!",
	["Банка лопнула! −%s"] = "Jar burst! −%s",
	["Цепная молния!"] = "Chain Lightning!",

	-- CatchController: нажатия и вехи комбо
	["Молнии бьют на островах!"] = "Lightning strikes on the islands!",
	["Встань в круг!"] = "Step into a ring!",
	["Рано! Жди кольцо"] = "Too early! Wait for the ring",
	["Жми ⚡ в момент удара!"] = "Hit ⚡ right as it strikes!",
	["Комбо %d! Ты молния! ⚡"] = "×%d Combo! You're lightning! ⚡",

	-- EventFX: шаровая молния, подарки, «Я видел!», фульгурит
	["ШАРОВАЯ МОЛНИЯ  %d/%d"] = "BALL LIGHTNING  %d/%d",
	["☠ Я видел! +%s ⚡"] = "☠ I saw it! +%s ⚡",
	["☠ Я видел!"] = "☠ I saw it!",
	["🔮 Фульгурит!"] = "🔮 Fulgurite!",
}
