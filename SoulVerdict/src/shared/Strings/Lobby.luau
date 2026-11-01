--!strict
-- Lobby HUD strings (src/client/UI/Hud/LobbyHud.luau): phase banner, map vote, monster chances,
-- quick buttons and the monster announcement. Server-side lobby/round text lives in Strings/Round.luau.
return {
	["lobby.waiting.players"] = { en = "{1}/{2} PLAYERS", ru = "ИГРОКОВ: {1}/{2}" },
	["lobby.waiting.line"] = {
		en = "* Waiting for one more SOUL... or start a PRACTICE round vs bots.",
		ru = "* Ждём ещё одну душу... или начни ТРЕНИРОВКУ против ботов.",
	},
	["lobby.intermission.line"] = {
		en = "* The monster is chosen in {1}s",
		ru = "* Монстр будет выбран через {1}с",
	},
	["lobby.intro.line"] = {
		en = "* The trial is about to begin...",
		ru = "* Суд вот-вот начнётся...",
	},
	["lobby.round.line"] = {
		en = "* A trial is in progress. You'll join the next one.",
		ru = "* Идёт суд. Ты присоединишься к следующему.",
	},
	-- vote
	["lobby.vote.title"] = { en = "NEXT HALL", ru = "СЛЕДУЮЩИЙ ЗАЛ" },
	["lobby.vote.votes"] = { en = "{1} VOTES", ru = "ГОЛОСОВ: {1}" },
	["lobby.vote.one"] = { en = "1 VOTE", ru = "1 ГОЛОС" },
	["lobby.vote.mine"] = { en = "YOUR VOTE", ru = "ТВОЙ ГОЛОС" },
	["lobby.vote.leading"] = { en = "LEADING", ru = "ЛИДЕР" },
	["lobby.vote.closed"] = { en = "VOTING CLOSED", ru = "ГОЛОСОВАНИЕ ЗАКРЫТО" },
	-- monster chance
	["lobby.chance.title"] = { en = "MONSTER CHANCE", ru = "ШАНС НА МОНСТРА" },
	["lobby.chance.you"] = { en = "YOU", ru = "ТЫ" },
	["lobby.chance.pref.Monster"] = { en = "wants Monster", ru = "хочет монстра" },
	["lobby.chance.pref.Human"] = { en = "human only", ru = "только человек" },
	["lobby.chance.pref.Either"] = { en = "any role", ru = "любая роль" },
	["lobby.chance.hint"] = {
		en = "* Every round as a human raises your chance.",
		ru = "* Каждый раунд за человека повышает твой шанс.",
	},
	["lobby.chance.empty"] = { en = "* Nobody here yet...", ru = "* Пока никого..." },
	-- quick buttons
	["lobby.btn.practice"] = { en = "PRACTICE", ru = "ТРЕНИРОВКА" },
	["lobby.btn.loadout"] = { en = "LOADOUT", ru = "СНАРЯЖЕНИЕ" },
	["lobby.btn.shop"] = { en = "SHOP", ru = "МАГАЗИН" },
	["lobby.btn.quests"] = { en = "QUESTS", ru = "ЗАДАНИЯ" },
	-- monster announcement
	["lobby.chosen.title"] = { en = "THE MONSTER HAS BEEN CHOSEN", ru = "МОНСТР ВЫБРАН" },
	["lobby.chosen.line"] = {
		en = "* {1} will judge you as {2}.",
		ru = "* {1} будет судить вас в роли: {2}.",
	},
	["lobby.chosen.you"] = {
		en = "* It's you. Judge them well.",
		ru = "* Это ты. Суди их как следует.",
	},
}
