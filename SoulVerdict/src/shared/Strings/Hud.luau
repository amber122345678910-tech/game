--!strict
-- In-round HUD strings (src/client/UI/Hud/**). Phase names, kill-feed lines and SAVE labels that the
-- server also uses live in Strings/Round.luau (round.*); this file holds HUD-only text (hud.*).
return {
	-- timer strip / boss bar
	["hud.saves"] = { en = "SAVES", ru = "СОХР." },
	["hud.alive"] = { en = "ALIVE", ru = "ЖИВЫ" },
	["hud.timeLeft"] = { en = "TIME", ru = "ВРЕМЯ" },
	["hud.practice"] = { en = "PRACTICE", ru = "ТРЕНИРОВКА" },
	["hud.boss.title"] = { en = "* {1}", ru = "* {1}" },
	["hud.boss.studious"] = {
		en = "STUDIOUS: MONSTER COOLDOWNS",
		ru = "ПРИЛЕЖНОСТЬ: ПЕРЕЗАРЯДКИ МОНСТРА",
	},
	["hud.exhausted"] = { en = "EXHAUSTED", ru = "ВЫДОХСЯ" },
	["hud.exhaustedFor"] = { en = "EXHAUSTED {1}s", ru = "ВЫДОХСЯ {1}с" },
	["hud.final"] = { en = "FINAL PHASE", ru = "ФИНАЛ" },
	["hud.dash"] = { en = "DASH", ru = "РЫВОК" },
	["hud.ready"] = { en = "READY", ru = "ГОТОВО" },
	["hud.ultReady"] = { en = "ULT READY", ru = "УЛЬТА ГОТОВА" },
	["hud.shield"] = { en = "SHIELD {1}", ru = "ЩИТ {1}" },
	["hud.lv"] = { en = "LV {1}", ru = "LV {1}" },
	["hud.you"] = { en = "YOU", ru = "ТЫ" },
	["hud.bot"] = { en = "BOT", ru = "БОТ" },
	-- ability bar
	["hud.slot.block"] = { en = "BLOCK", ru = "БЛОК" },
	["hud.slot.dash"] = { en = "DASH", ru = "РЫВОК" },
	["hud.slot.verdict"] = { en = "VERDICT BOX", ru = "КОРОБКА СУДА" },
	["hud.slot.jump"] = { en = "JUMP", ru = "ПРЫЖОК" },
	["hud.slot.lock"] = { en = "LOCK", ru = "ФИКС." },
	["hud.slot.reload"] = { en = "RELOAD", ru = "ПЕРЕЗАРЯДКА" },
	["hud.slot.silenced"] = { en = "SILENCED", ru = "НЕМОТА" },
	["hud.slot.stunned"] = { en = "STUNNED", ru = "ОГЛУШЁН" },
	-- second wind / surge / statuses
	["hud.secondWind"] = { en = "SECOND WIND", ru = "ВТОРОЕ ДЫХАНИЕ" },
	["hud.surge"] = { en = "DETERMINATION SURGE", ru = "ВСПЛЕСК РЕШИМОСТИ" },
	["hud.surgeShort"] = { en = "SURGE", ru = "ВСПЛЕСК" },
	["hud.boxed"] = { en = "IN THE VERDICT BOX", ru = "В КОРОБКЕ СУДА" },
	["hud.status.Stunned"] = { en = "Stunned", ru = "Оглушение" },
	["hud.status.Rooted"] = { en = "Rooted", ru = "Обездвижен" },
	["hud.status.Slowed"] = { en = "Slowed", ru = "Замедление" },
	["hud.status.Hasted"] = { en = "Haste", ru = "Ускорение" },
	["hud.status.Silenced"] = { en = "Silenced", ru = "Немота" },
	["hud.status.Blue"] = { en = "Blue SOUL", ru = "Синяя душа" },
	["hud.status.Invulnerable"] = { en = "Invulnerable", ru = "Неуязвимость" },
	["hud.status.Invisible"] = { en = "Invisible", ru = "Невидимость" },
	["hud.status.Marked"] = { en = "Marked", ru = "Метка" },
	["hud.status.Rage"] = { en = "Rage", ru = "Ярость" },
	["hud.status.DamageUp"] = { en = "Damage up", ru = "Урон выше" },
	["hud.status.DamageDown"] = { en = "Damage taken down", ru = "Входящий урон ниже" },
	["hud.status.Shielded"] = { en = "Shielded", ru = "Щит" },
	["hud.status.Exhausted"] = { en = "Exhausted", ru = "Усталость" },
	["hud.status.Boxed"] = { en = "Boxed", ru = "В коробке" },
	["hud.status.SecondWind"] = { en = "Second Wind", ru = "Второе дыхание" },
	["hud.status.Surge"] = { en = "Surge", ru = "Всплеск" },
	["hud.status.Undodgeable"] = { en = "Undodgeable", ru = "Без уклонений" },
	["hud.status.Determined"] = { en = "Determined", ru = "Решимость" },
	-- downed
	["hud.downed.title"] = { en = "DOWNED", ru = "ПОВЕРЖЕН" },
	["hud.downed.hint"] = {
		en = "Hold on — an ally can revive you",
		ru = "Держись — союзник может тебя поднять",
	},
	["hud.downed.bleed"] = { en = "Bleeding out in {1}s", ru = "Угаснешь через {1}с" },
	["hud.downed.revives"] = { en = "Team revives left: {1}", ru = "Подъёмов у команды: {1}" },
	["hud.downed.noRevives"] = { en = "No team revives left!", ru = "Подъёмов не осталось!" },
	-- team panel
	["hud.team.title"] = { en = "HUMANS", ru = "ЛЮДИ" },
	["hud.team.revives"] = { en = "REVIVES", ru = "ПОДЪЁМЫ" },
	["hud.team.harmony"] = { en = "HARMONY +{1}%", ru = "ГАРМОНИЯ +{1}%" },
	["hud.team.down"] = { en = "DOWN {1}s", ru = "ЛЕЖИТ {1}с" },
	["hud.team.fallen"] = { en = "FALLEN", ru = "ПАЛ" },
	-- objectives
	["hud.obj.save"] = { en = "SAVE {1}", ru = "СОХР. {1}" },
	["hud.obj.lit"] = { en = "LIT", ru = "ГОРИТ" },
	["hud.obj.distance"] = { en = "{1}m", ru = "{1}м" },
	["hud.obj.channel"] = { en = "{1}%", ru = "{1}%" },
	["hud.collapse.warn"] = { en = "GET BACK INSIDE THE RING!", ru = "ВЕРНИСЬ В КРУГ!" },
	["hud.collapse.radius"] = { en = "RING {1}m", ru = "КРУГ {1}м" },
	-- kill feed (round.feed.* are reused for kills/downs/revives)
	["hud.feed.save"] = { en = "{1} lit SAVE {2}", ru = "{1} зажёг(ла) СОХРАНЕНИЕ {2}" },
	["hud.feed.surge"] = { en = "DETERMINATION SURGE!", ru = "ВСПЛЕСК РЕШИМОСТИ!" },
	["hud.feed.secondWind"] = { en = "{1} got a SECOND WIND", ru = "{1}: ВТОРОЕ ДЫХАНИЕ" },
	-- announcements
	["hud.ann.fight"] = { en = "FIGHT!", ru = "В БОЙ!" },
	["hud.ann.fight.line"] = {
		en = "* Light the SAVE stars. Stay together.",
		ru = "* Зажгите звёзды СОХРАНЕНИЯ. Держитесь вместе.",
	},
	["hud.ann.fight.monster"] = {
		en = "* Judge them before the stars are lit.",
		ru = "* Осуди их, пока звёзды не зажглись.",
	},
	["hud.ann.final.line"] = {
		en = "* The judge stops holding back.",
		ru = "* Судья перестаёт сдерживаться.",
	},
	["hud.ann.final.monster"] = {
		en = "* Your eye blazes. Dodges and ultimate restored.",
		ru = "* Твой глаз пылает. Уклонения и ульта восстановлены.",
	},
	["hud.ann.surge.line"] = {
		en = "* Three stars burn as one. The monster falters!",
		ru = "* Три звезды горят как одна. Монстр дрогнул!",
	},
	["hud.ann.surge.monster"] = {
		en = "* Every star is lit. You feel exhausted...",
		ru = "* Все звёзды горят. Ты чувствуешь усталость...",
	},
	["hud.ann.secondWind.line"] = { en = "* {1} refuses to give up.", ru = "* {1} не сдаётся." },
	["hud.ann.secondWind.self"] = {
		en = "* You're the last one standing. Keep going!",
		ru = "* Ты остался один. Не сдавайся!",
	},
	["hud.ann.collapse"] = { en = "COLLAPSE", ru = "ОБРУШЕНИЕ" },
	["hud.ann.collapse.line"] = {
		en = "* The hall is falling into the void. Stay inside the ring!",
		ru = "* Зал рушится в пустоту. Оставайся внутри круга!",
	},
	["hud.ann.saveLit"] = { en = "SAVE {1}/{2}", ru = "СОХРАНЕНИЕ {1}/{2}" },
	["hud.ann.saveLit.line"] = {
		en = "* The star's light fills you with hope.",
		ru = "* Свет звезды наполняет тебя надеждой.",
	},
	["hud.ann.exhausted"] = { en = "EXHAUSTED!", ru = "ВЫДОХСЯ!" },
	-- intro splash
	["hud.intro.vs"] = { en = "VS", ru = "VS" },
	["hud.intro.monster"] = { en = "THE MONSTER", ru = "МОНСТР" },
	["hud.intro.humans"] = { en = "THE HUMANS", ru = "ЛЮДИ" },
	["hud.intro.map"] = { en = "* {1}", ru = "* {1}" },
	["hud.intro.ready"] = { en = "GET READY", ru = "ПРИГОТОВЬСЯ" },
	["hud.intro.harmony"] = { en = "Harmony +{1}% damage", ru = "Гармония +{1}% урона" },
	-- spectate / death
	["hud.spec.title"] = { en = "SPECTATING", ru = "НАБЛЮДЕНИЕ" },
	["hud.spec.prev"] = { en = "PREV", ru = "НАЗАД" },
	["hud.spec.next"] = { en = "NEXT", ru = "ДАЛЕЕ" },
	["hud.spec.none"] = { en = "* No one left to watch...", ru = "* Больше не за кем следить..." },
	["hud.spec.line"] = {
		en = "* Cheer them on. The trial isn't over.",
		ru = "* Поддержи их. Суд ещё не окончен.",
	},
	["hud.death.title"] = { en = "YOUR SOUL SHATTERED", ru = "ТВОЯ ДУША РАЗБИТА" },
	["hud.death.line1"] = { en = "* Stay determined...", ru = "* Не теряй решимости..." },
	["hud.death.line2"] = {
		en = "* The trial isn't over. Your friends still fight.",
		ru = "* Суд не окончен. Твои друзья ещё сражаются.",
	},
	["hud.death.line3"] = {
		en = "* Even a shattered SOUL remembers how to hope.",
		ru = "* Даже разбитая душа помнит, как надеяться.",
	},
	["hud.death.by"] = { en = "Judged by {1}", ru = "Осуждён: {1}" },
	["hud.death.spectate"] = { en = "Spectating in {1}...", ru = "Наблюдение через {1}..." },

	-- nameplates: an invisible ally's faded plate
	["hud.plate.hidden"] = { en = "hidden", ru = "невидим" },

	-- emote wheel (Hud/EmoteWheel) + EmoteService refusal toast
	["hud.emote.title"] = { en = "EMOTES", ru = "ЭМОЦИИ" },
	["hud.emote.button"] = { en = "EMOTE", ru = "ЭМОЦИЯ" },
	["hud.emote.Emote_Wave"] = { en = "Wave", ru = "Помахать" },
	["hud.emote.Emote_Shrug"] = { en = "Shrug", ru = "Пожать плечами" },
	["hud.emote.Emote_Sit"] = { en = "Sit", ru = "Сесть" },
	["hud.emote.Emote_Laugh"] = { en = "Laugh", ru = "Смех" },
	["hud.emote.Taunt"] = { en = "Taunt", ru = "Дразнить" },
	["hud.emote.Victory"] = { en = "Cheer", ru = "Ликовать" },
	["hud.emote.Wink"] = { en = "Wink", ru = "Подмигнуть" },
	["hud.emote.hint.KeyboardMouse"] = {
		en = "Click or 1-{1}  ·  {2} / Esc to close",
		ru = "Клик или 1-{1}  ·  {2} / Esc — закрыть",
	},
	["hud.emote.hint.Gamepad"] = {
		en = "Right stick + {1} to play  ·  B to close",
		ru = "Правый стик + {1}  ·  B — закрыть",
	},
	["hud.emote.hint.Touch"] = { en = "Tap an emote", ru = "Нажми на эмоцию" },
	["hud.emote.busy"] = {
		en = "You can't emote right now",
		ru = "Сейчас нельзя использовать эмоцию",
	},
}
