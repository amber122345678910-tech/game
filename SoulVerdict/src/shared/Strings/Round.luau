--!strict
-- Round-loop strings (phases, results, revive prompt, objectives, queue, practice, kill feed, notices).
-- Lune-safe. Every key starts with "round." and has en + ru with the same {n} placeholders.
-- Result headline keys: "round.result.<Winner>.<Reason>" (+ ".sub" subtitle), Winner = Humans|Monster,
-- Reason = Defeated|Survived|Eliminated|Left|Aborted.
return {
	-- Phases (HUD timer captions)
	["round.phase.Waiting"] = { en = "WAITING FOR PLAYERS", ru = "ОЖИДАНИЕ ИГРОКОВ" },
	["round.phase.Intermission"] = { en = "INTERMISSION", ru = "ПЕРЕРЫВ" },
	["round.phase.Intro"] = { en = "THE TRIAL BEGINS", ru = "СУД НАЧИНАЕТСЯ" },
	["round.phase.Round"] = { en = "FIGHT", ru = "БИТВА" },
	["round.phase.Collapse"] = { en = "COLLAPSE", ru = "ОБРУШЕНИЕ" },
	["round.phase.Ending"] = { en = "VERDICT", ru = "ПРИГОВОР" },
	["round.waiting.need"] = {
		en = "Need {1} players to start ({2}/{1}). Try PRACTICE while you wait!",
		ru = "Нужно {1} игрока для старта ({2}/{1}). Попробуй ТРЕНИРОВКУ, пока ждёшь!",
	},

	-- Results: headline + subtitle per winner/reason
	["round.result.Humans.Defeated"] = { en = "DETERMINATION PREVAILED", ru = "РЕШИМОСТЬ ПОБЕДИЛА" },
	["round.result.Humans.Defeated.sub"] = {
		en = "The judge has fallen. The SOULs shine on.",
		ru = "Судья пал. ДУШИ продолжают сиять.",
	},
	["round.result.Humans.Survived"] = {
		en = "THEY SURVIVED THE VERDICT",
		ru = "ОНИ ПЕРЕЖИЛИ ПРИГОВОР",
	},
	["round.result.Humans.Survived.sub"] = {
		en = "The world collapsed, but they refused to.",
		ru = "Мир рухнул, но они устояли.",
	},
	["round.result.Humans.Left"] = { en = "THE JUDGE LEFT THE HALL", ru = "СУДЬЯ ПОКИНУЛ ЗАЛ" },
	["round.result.Humans.Left.sub"] = {
		en = "The monster walked away. Nobody is penalised.",
		ru = "Монстр ушёл. Никто не наказан.",
	},
	["round.result.Humans.Aborted"] = { en = "THE TRIAL WAS ADJOURNED", ru = "СУД ОТЛОЖЕН" },
	["round.result.Humans.Aborted.sub"] = {
		en = "This round was stopped early.",
		ru = "Раунд остановлен досрочно.",
	},
	["round.result.Monster.Eliminated"] = { en = "THE HUMANS WERE JUDGED", ru = "ЛЮДИ БЫЛИ СУЖДЕНЫ" },
	["round.result.Monster.Eliminated.sub"] = {
		en = "Every SOUL has been weighed... and found wanting.",
		ru = "Каждая ДУША взвешена... и признана недостойной.",
	},
	["round.result.Monster.Left"] = {
		en = "NO ONE STAYED FOR THE VERDICT",
		ru = "НИКТО НЕ ДОЖДАЛСЯ ПРИГОВОРА",
	},
	["round.result.Monster.Left.sub"] = {
		en = "The humans fled the hall. The judge wins by default.",
		ru = "Люди сбежали из зала. Судья побеждает по умолчанию.",
	},
	["round.result.Monster.Aborted"] = { en = "THE TRIAL WAS ADJOURNED", ru = "СУД ОТЛОЖЕН" },
	["round.result.Monster.Aborted.sub"] = {
		en = "This round was stopped early.",
		ru = "Раунд остановлен досрочно.",
	},
	["round.result.draw"] = { en = "THE TRIAL WAS ADJOURNED", ru = "СУД ОТЛОЖЕН" },
	["round.result.victory"] = { en = "VICTORY", ru = "ПОБЕДА" },
	["round.result.defeat"] = { en = "DEFEAT", ru = "ПОРАЖЕНИЕ" },
	["round.result.mvp"] = { en = "MVP", ru = "MVP" },
	["round.result.practice"] = {
		en = "PRACTICE — reduced rewards",
		ru = "ТРЕНИРОВКА — награды снижены",
	},

	-- Revive prompt (ProximityPrompt texts; the prompt also carries ActionKey for client localisation)
	["round.revive.action"] = { en = "Revive", ru = "Поднять" },
	["round.revive.object"] = { en = "{1} is down", ru = "{1} повержен(а)" },
	["round.revive.none"] = { en = "No revives left!", ru = "Подъёмы закончились!" },
	["round.revive.left"] = { en = "Team revives: {1}", ru = "Подъёмов у команды: {1}" },

	-- Kill feed / events
	["round.feed.judged"] = { en = "{2} judged {1}", ru = "{2} осудил(а) {1}" },
	["round.feed.downed"] = { en = "{1} is down!", ru = "{1} повержен(а)!" },
	["round.feed.revived"] = { en = "{2} revived {1}", ru = "{2} поднял(а) {1}" },
	["round.feed.faded"] = { en = "{1} faded away", ru = "{1} угас(ла)" },
	["round.feed.void"] = { en = "{1} fell into the void", ru = "{1} упал(а) в пустоту" },
	["round.feed.collapse"] = {
		en = "{1} was swallowed by the collapse",
		ru = "{1} поглотило обрушение",
	},
	["round.feed.left"] = { en = "{1} left the trial", ru = "{1} покинул(а) суд" },
	["round.feed.monsterDown"] = { en = "{1} has been defeated!", ru = "{1} повержен!" },

	-- Big moments
	["round.notify.monsterChosen"] = { en = "{1} will be the MONSTER", ru = "{1} будет МОНСТРОМ" },
	["round.notify.youAreMonster"] = {
		en = "You are the MONSTER. Judge them all.",
		ru = "Ты — МОНСТР. Суди их всех.",
	},
	["round.notify.youAreHuman"] = {
		en = "You are a HUMAN. Light the SAVE stars and stay determined.",
		ru = "Ты — ЧЕЛОВЕК. Зажги звёзды СОХРАНЕНИЯ и не теряй решимости.",
	},
	["round.notify.finalPhase"] = {
		en = "The judge stops holding back...",
		ru = "Судья перестаёт сдерживаться...",
	},
	["round.notify.secondWind"] = {
		en = "{1} refuses to give up! SECOND WIND!",
		ru = "{1} не сдаётся! ВТОРОЕ ДЫХАНИЕ!",
	},
	["round.notify.collapse"] = {
		en = "The world is collapsing! Stay inside the ring!",
		ru = "Мир рушится! Оставайся внутри кольца!",
	},
	["round.notify.harmony"] = {
		en = "HARMONY +{1}% team damage",
		ru = "ГАРМОНИЯ +{1}% урона команды",
	},
	["round.notify.spectating"] = {
		en = "Your SOUL shattered. Spectating until the verdict.",
		ru = "Твоя ДУША разбита. Наблюдаешь до приговора.",
	},
	["round.notify.lateJoin"] = {
		en = "A trial is in progress. You will join the next one.",
		ru = "Идёт суд. Ты присоединишься к следующему.",
	},
	["round.notify.notEnough"] = {
		en = "Not enough players — back to waiting.",
		ru = "Недостаточно игроков — снова ожидание.",
	},
	["round.notify.mapFailed"] = {
		en = "That map failed to load. Using the test arena.",
		ru = "Карта не загрузилась. Используется тестовая арена.",
	},

	-- SAVE objectives
	["round.save.name"] = { en = "SAVE", ru = "СОХРАНЕНИЕ" },
	["round.save.channel"] = { en = "Channeling...", ru = "Сохранение..." },
	["round.save.contested"] = { en = "CONTESTED", ru = "ОСПАРИВАЕТСЯ" },
	["round.save.lit"] = {
		en = "A SAVE star shines! ({1}/{2})",
		ru = "Звезда СОХРАНЕНИЯ сияет! ({1}/{2})",
	},
	["round.save.surge"] = {
		en = "DETERMINATION SURGE! The monster is exhausted!",
		ru = "ВСПЛЕСК РЕШИМОСТИ! Монстр измотан!",
	},
	["round.save.dodgeLost"] = {
		en = "The monster lost a DODGE ({1} left)",
		ru = "Монстр потерял УКЛОНЕНИЕ (осталось {1})",
	},

	-- Map vote
	["round.vote.title"] = { en = "VOTE FOR THE NEXT HALL", ru = "ГОЛОСУЙ ЗА СЛЕДУЮЩИЙ ЗАЛ" },
	["round.vote.cast"] = { en = "You voted for {1}", ru = "Ты проголосовал(а) за {1}" },
	["round.vote.closed"] = { en = "Voting is closed", ru = "Голосование закрыто" },
	["round.vote.invalid"] = {
		en = "That map is not on the ballot",
		ru = "Этой карты нет в голосовании",
	},
	["round.vote.nextMap"] = { en = "Next hall: {1}", ru = "Следующий зал: {1}" },

	-- Monster queue
	["round.queue.chance"] = { en = "Monster chance: {1}%", ru = "Шанс стать монстром: {1}%" },
	["round.queue.prefSet"] = { en = "Role preference: {1}", ru = "Предпочтение роли: {1}" },
	["round.queue.prefInvalid"] = {
		en = "Unknown role preference",
		ru = "Неизвестное предпочтение роли",
	},

	-- Practice
	["round.practice.start"] = {
		en = "PRACTICE: {1} vs bots",
		ru = "ТРЕНИРОВКА: {1} против ботов",
	},
	["round.practice.side.Human"] = { en = "Human", ru = "Человек" },
	["round.practice.side.Monster"] = { en = "Monster", ru = "Монстр" },
	["round.practice.busy"] = {
		en = "Practice is only available while waiting for players.",
		ru = "Тренировка доступна только во время ожидания игроков.",
	},
	["round.practice.unavailable"] = {
		en = "Practice bots are not available.",
		ru = "Боты для тренировки недоступны.",
	},
	["round.practice.disabled"] = { en = "Practice is disabled.", ru = "Тренировка отключена." },
	["round.practice.queued"] = { en = "Practice is starting...", ru = "Тренировка начинается..." },
	["round.practice.ended"] = { en = "Practice over.", ru = "Тренировка окончена." },
	["round.practice.bot"] = { en = "{1} (bot)", ru = "{1} (бот)" },
	["round.dummy.name"] = { en = "Training Dummy", ru = "Тренировочный манекен" },

	-- Lobby / Try kit
	["round.trykit.invalid"] = { en = "Unknown kit", ru = "Неизвестный набор" },
	["round.trykit.notLobby"] = {
		en = "You can only try kits in the lobby.",
		ru = "Примерять наборы можно только в лобби.",
	},
	["round.trykit.trying"] = { en = "Trying {1}", ru = "Примеряешь: {1}" },

	-- Style Lab (server side messages)
	["round.lab.denied"] = {
		en = "Style Lab is for the owner only.",
		ru = "Style Lab доступен только владельцу.",
	},
	["round.lab.unknown"] = {
		en = "Unknown Style Lab action",
		ru = "Неизвестное действие Style Lab",
	},
	["round.lab.done"] = { en = "Style Lab: {1}", ru = "Style Lab: {1}" },
	["round.lab.noMap"] = {
		en = "Unknown or unavailable map",
		ru = "Неизвестная или недоступная карта",
	},
	["round.lab.noRound"] = { en = "No round in progress", ru = "Раунд не идёт" },
	["round.lab.noCharacter"] = { en = "You have no character", ru = "У тебя нет персонажа" },

	-- HUD helpers
	["round.hud.alive"] = { en = "{1}/{2} alive", ru = "Живы: {1}/{2}" },
	["round.hud.saves"] = { en = "SAVES {1}/{2}", ru = "СОХР. {1}/{2}" },
	["round.hud.final"] = { en = "FINAL PHASE", ru = "ФИНАЛЬНАЯ ФАЗА" },
	["round.hud.harmony"] = { en = "Harmony x{1}", ru = "Гармония x{1}" },
	["round.hud.downed"] = { en = "DOWNED — hold on! {1}s", ru = "ПОВЕРЖЕН — держись! {1}с" },
	["round.hud.spectator"] = { en = "SPECTATING", ru = "НАБЛЮДЕНИЕ" },
}
