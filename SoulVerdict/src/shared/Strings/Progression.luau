--!strict
-- Progression strings (quests, achievements, titles, trails, rewards, shop, data/request notices). Lune-safe.
-- Owned by the progression area (src/shared/Progression, server data services). Every key starts with "prog.".
--   prog.quest.<QuestId>           {1} = goal, {2} = template Param         (Progression/Quests)
--   prog.ach.<id> / .<id>.desc     {1} = goal                                (Progression/Achievements)
--   prog.title.<titleId>           achievement titles + "m_<KitId>_<3|6|10>" mastery titles (Progression/Titles)
--   prog.trail.<Kind>              Soul | Prism | none                       (Progression/Mastery)
--   prog.reward.<item>             Rewards breakdown lines, {1} = count      (Progression/Rewards)
--   prog.unlock.<kind>             "Title: {1}" ... for the results screen   (RoundEvent "Rewards".unlocked)
--   prog.err.<code>                request failures (Notify style "Warning")
--   prog.notify.<code>             toasts (levels, quests, achievements, streak, shop, data mode)
--   prog.shop.quip.1..5            shopkeeper one-liners for the Shop screen
return {
	-- Quests ----------------------------------------------------------------------------------------
	["prog.quest.PlayRounds"] = {
		en = "Play {1} rounds. Attendance counts.",
		ru = "Сыграй раунды: {1}. Явка засчитывается.",
	},
	["prog.quest.WinRounds"] = {
		en = "Win {1} rounds on either side",
		ru = "Победи в раундах за любую сторону: {1}",
	},
	["prog.quest.DealDamage"] = {
		en = "Deal {1} damage. Politely, if possible.",
		ru = "Нанеси {1} урона. По возможности вежливо.",
	},
	["prog.quest.BeMvp"] = { en = "Be the MVP of a round", ru = "Стань MVP раунда" },
	["prog.quest.BigRound"] = {
		en = "Deal {2}+ damage in a single round ({1}x)",
		ru = "Нанеси {2}+ урона за один раунд (раз: {1})",
	},
	["prog.quest.EarnExp"] = { en = "Earn {1} EXP from rounds", ru = "Заработай {1} EXP в раундах" },
	["prog.quest.PracticeRound"] = {
		en = "Finish a practice round. The dummies won't judge.",
		ru = "Заверши тренировку. Манекены не осудят.",
	},
	["prog.quest.HumanWin"] = { en = "Win {1} rounds as a Human", ru = "Победи за людей (раз: {1})" },
	["prog.quest.HumanSurvive"] = {
		en = "Survive {1} rounds as a Human",
		ru = "Доживи до конца раунда за людей (раз: {1})",
	},
	["prog.quest.Parries"] = {
		en = "Land {1} perfect parries",
		ru = "Сделай идеальные парирования: {1}",
	},
	["prog.quest.Saves"] = { en = "Light {1} SAVE stars", ru = "Зажги звёзды SAVE: {1}" },
	["prog.quest.Revives"] = {
		en = "Revive {1} fallen allies",
		ru = "Подними павших союзников: {1}",
	},
	["prog.quest.Healing"] = {
		en = "Heal {1} HP. Butterscotch optional.",
		ru = "Вылечи {1} HP. Ириска по желанию.",
	},
	["prog.quest.ForceDodges"] = {
		en = "Make the Monster dodge {1} times. Tire him out.",
		ru = "Заставь монстра уклониться {1} раз. Утоми его.",
	},
	["prog.quest.BoxSurvivor"] = {
		en = "Escape {1} Verdict Boxes",
		ru = "Выберись из Коробки Приговора (раз: {1})",
	},
	["prog.quest.HumanDamage"] = {
		en = "Deal {1} damage to the Monster",
		ru = "Нанеси монстру {1} урона",
	},
	["prog.quest.DefeatMonster"] = {
		en = "Help bring the Monster's HP to 0",
		ru = "Помоги обнулить HP монстра",
	},
	["prog.quest.FinalBlow"] = {
		en = "Land the final blow on the Monster",
		ru = "Нанеси монстру последний удар",
	},
	["prog.quest.SurviveCollapse"] = {
		en = "Outlast the Collapse and win",
		ru = "Переживи Обрушение и победи",
	},
	["prog.quest.ParryRound"] = {
		en = "Parry {2}+ attacks in one round ({1}x)",
		ru = "Парируй {2}+ атаки за один раунд (раз: {1})",
	},
	["prog.quest.TeamPlayer"] = {
		en = "Revive an ally AND light a SAVE star in one round",
		ru = "За один раунд подними союзника И зажги звезду SAVE",
	},
	["prog.quest.HealerRound"] = {
		en = "Heal {2}+ HP in a single round",
		ru = "Вылечи {2}+ HP за один раунд",
	},
	["prog.quest.MonsterPlay"] = {
		en = "Play {1} rounds as the Monster",
		ru = "Сыграй за монстра (раз: {1})",
	},
	["prog.quest.MonsterWin"] = {
		en = "Win a round as the Monster",
		ru = "Победи в раунде за монстра",
	},
	["prog.quest.MonsterKills"] = {
		en = "Judge {1} humans as the Monster",
		ru = "Вынеси приговор людям: {1}",
	},
	["prog.quest.MonsterDowns"] = { en = "Knock down {1} humans", ru = "Сбей с ног людей: {1}" },
	["prog.quest.MonsterDamage"] = {
		en = "Deal {1} damage as the Monster",
		ru = "Нанеси {1} урона за монстра",
	},
	["prog.quest.BoxHits"] = {
		en = "Land {1} hits inside the Verdict Box",
		ru = "Попадания по ДУШЕ в Коробке Приговора: {1}",
	},
	["prog.quest.BoxCombo"] = {
		en = "Land {2}+ hits in a single Verdict Box ({1}x)",
		ru = "Набери {2}+ попадания за одну Коробку (раз: {1})",
	},
	["prog.quest.Rampage"] = {
		en = "Judge {2} humans in a single round",
		ru = "Вынеси приговор {2} людям за один раунд",
	},
	["prog.quest.SwiftVerdict"] = {
		en = "Win as the Monster before the Collapse",
		ru = "Победи за монстра до Обрушения",
	},
	-- {2} = Config.Round.FinalPhaseHpFraction in % (Quests "Unshaken" Param); the monster's ultimate does not count
	["prog.quest.Unshaken"] = {
		en = "Win as the Monster without ever dropping to {2}% HP",
		ru = "Победи за монстра, ни разу не опустившись до {2}% HP",
	},

	-- Achievements: name + description -------------------------------------------------------------
	["prog.ach.first_round"] = { en = "Into the Hall", ru = "В зал суда" },
	["prog.ach.first_round.desc"] = {
		en = "Play your first round.",
		ru = "Сыграй свой первый раунд.",
	},
	["prog.ach.rounds_25"] = { en = "Regular Defendant", ru = "Постоянный подсудимый" },
	["prog.ach.rounds_25.desc"] = { en = "Play {1} rounds.", ru = "Сыграй раунды: {1}." },
	["prog.ach.rounds_100"] = { en = "Part of the Furniture", ru = "Часть интерьера" },
	["prog.ach.rounds_100.desc"] = { en = "Play {1} rounds.", ru = "Сыграй раунды: {1}." },
	["prog.ach.rounds_500"] = { en = "Time Is a Flat Hallway", ru = "Время — плоский коридор" },
	["prog.ach.rounds_500.desc"] = {
		en = "Play {1} rounds. The timeline remembers you.",
		ru = "Сыграй раунды: {1}. Таймлайн тебя запомнил.",
	},
	["prog.ach.first_win"] = { en = "First Verdict", ru = "Первый приговор" },
	["prog.ach.first_win.desc"] = { en = "Win a round.", ru = "Выиграй раунд." },
	["prog.ach.wins_25"] = { en = "Habitual Winner", ru = "Привычка побеждать" },
	["prog.ach.wins_25.desc"] = { en = "Win {1} rounds.", ru = "Победы в раундах: {1}." },
	["prog.ach.wins_100"] = { en = "Hero of the Underground", ru = "Герой Подземья" },
	["prog.ach.wins_100.desc"] = { en = "Win {1} rounds.", ru = "Победы в раундах: {1}." },
	["prog.ach.monster_win"] = { en = "Bad Time", ru = "Плохое время" },
	["prog.ach.monster_win.desc"] = {
		en = "Win a round as the Monster.",
		ru = "Выиграй раунд за монстра.",
	},
	["prog.ach.monster_wins_25"] = {
		en = "Judge, Jury and Skeleton",
		ru = "Судья, присяжные и скелет",
	},
	["prog.ach.monster_wins_25.desc"] = {
		en = "Win {1} rounds as the Monster.",
		ru = "Победы за монстра: {1}.",
	},
	["prog.ach.human_wins_25"] = { en = "SOUL Collective", ru = "Коллектив ДУШ" },
	["prog.ach.human_wins_25.desc"] = { en = "Win {1} rounds as a Human.", ru = "Победы за людей: {1}." },
	["prog.ach.mvp_10"] = { en = "Star of the Show", ru = "Звезда шоу" },
	["prog.ach.mvp_10.desc"] = { en = "Be the MVP {1} times.", ru = "Стань MVP (раз: {1})." },
	["prog.ach.kills_50"] = { en = "LOVE Is Growing", ru = "LOVE растёт" },
	["prog.ach.kills_50.desc"] = { en = "Land {1} final blows.", ru = "Последние удары: {1}." },
	["prog.ach.kills_250"] = { en = "EXecution Points", ru = "Очки ИСполнения" },
	["prog.ach.kills_250.desc"] = {
		en = "Land {1} final blows. That's a lot of LOVE.",
		ru = "Последние удары: {1}. Это очень много LOVE.",
	},
	["prog.ach.damage_25k"] = { en = "Heavy Hitter", ru = "Тяжёлая рука" },
	["prog.ach.damage_25k.desc"] = {
		en = "Deal {1} damage in total.",
		ru = "Нанеси {1} урона суммарно.",
	},
	["prog.ach.damage_100k"] = { en = "Unstoppable Force", ru = "Неудержимая сила" },
	["prog.ach.damage_100k.desc"] = {
		en = "Deal {1} damage in total.",
		ru = "Нанеси {1} урона суммарно.",
	},
	["prog.ach.parries_100"] = { en = "Nope.", ru = "Неа." },
	["prog.ach.parries_100.desc"] = {
		en = "Land {1} perfect parries.",
		ru = "Идеальные парирования: {1}.",
	},
	["prog.ach.parries_500"] = { en = "Not Today", ru = "Не сегодня" },
	["prog.ach.parries_500.desc"] = {
		en = "Land {1} perfect parries.",
		ru = "Идеальные парирования: {1}.",
	},
	["prog.ach.dodges_250"] = { en = "Lazy Bones", ru = "Ленивые кости" },
	["prog.ach.dodges_250.desc"] = {
		en = "Make the Monster dodge {1} times.",
		ru = "Заставь монстра уклониться {1} раз.",
	},
	["prog.ach.saves_25"] = { en = "Stargazer", ru = "Звездочёт" },
	["prog.ach.saves_25.desc"] = { en = "Light {1} SAVE stars.", ru = "Зажги звёзды SAVE: {1}." },
	["prog.ach.saves_100"] = { en = "Constellation", ru = "Созвездие" },
	["prog.ach.saves_100.desc"] = { en = "Light {1} SAVE stars.", ru = "Зажги звёзды SAVE: {1}." },
	["prog.ach.revives_25"] = { en = "Not on My Watch", ru = "Не в мою смену" },
	["prog.ach.revives_25.desc"] = { en = "Revive {1} allies.", ru = "Подними союзников: {1}." },
	["prog.ach.revives_100"] = { en = "SOUL Mender", ru = "Целитель ДУШ" },
	["prog.ach.revives_100.desc"] = { en = "Revive {1} allies.", ru = "Подними союзников: {1}." },
	["prog.ach.heal_5000"] = { en = "Pie Delivery", ru = "Доставка пирогов" },
	["prog.ach.heal_5000.desc"] = { en = "Heal {1} HP in total.", ru = "Вылечи {1} HP суммарно." },
	["prog.ach.boxes_10"] = { en = "Out of the Box", ru = "Вне коробки" },
	["prog.ach.boxes_10.desc"] = {
		en = "Survive {1} Verdict Boxes.",
		ru = "Выживи в Коробке Приговора (раз: {1}).",
	},
	["prog.ach.boxes_50"] = { en = "Bullet Ballet", ru = "Балет среди пуль" },
	["prog.ach.boxes_50.desc"] = {
		en = "Survive {1} Verdict Boxes.",
		ru = "Выживи в Коробке Приговора (раз: {1}).",
	},
	["prog.ach.box_hits_100"] = { en = "Thinking Inside the Box", ru = "Мыслить внутри коробки" },
	["prog.ach.box_hits_100.desc"] = {
		en = "Land {1} hits inside Verdict Boxes.",
		ru = "Попадания в Коробке Приговора: {1}.",
	},
	["prog.ach.level_10"] = { en = "LV 10", ru = "LV 10" },
	["prog.ach.level_10.desc"] = { en = "Reach LV {1}.", ru = "Достигни LV {1}." },
	["prog.ach.level_25"] = { en = "Seasoned", ru = "Бывалый опыт" },
	["prog.ach.level_25.desc"] = { en = "Reach LV {1}.", ru = "Достигни LV {1}." },
	["prog.ach.level_50"] = { en = "Halfway Up the Mountain", ru = "Полпути до вершины" },
	["prog.ach.level_50.desc"] = { en = "Reach LV {1}.", ru = "Достигни LV {1}." },
	["prog.ach.level_100"] = { en = "Three Digits of Determination", ru = "Трёхзначная решимость" },
	["prog.ach.level_100.desc"] = { en = "Reach LV {1}.", ru = "Достигни LV {1}." },
	["prog.ach.streak_7"] = { en = "A Week of SAVEs", ru = "Неделя SAVE" },
	["prog.ach.streak_7.desc"] = {
		en = "Log in {1} days in a row.",
		ru = "Заходи в игру дней подряд: {1}.",
	},
	["prog.ach.streak_30"] = { en = "Habit of a Lifetime", ru = "Привычка на всю жизнь" },
	["prog.ach.streak_30.desc"] = {
		en = "Log in {1} days in a row.",
		ru = "Заходи в игру дней подряд: {1}.",
	},
	["prog.ach.quests_25"] = { en = "Errand Runner", ru = "Курьер Подземья" },
	["prog.ach.quests_25.desc"] = { en = "Complete {1} quests.", ru = "Выполни задания: {1}." },
	["prog.ach.gold_10k"] = { en = "Golden Flowers", ru = "Золотые цветы" },
	["prog.ach.gold_10k.desc"] = { en = "Earn {1} G in total.", ru = "Заработай {1} G суммарно." },
	["prog.ach.all_kits"] = { en = "Full Roster", ru = "Полный состав" },
	["prog.ach.all_kits.desc"] = { en = "Unlock all {1} kits.", ru = "Открой все наборы ({1})." },
	["prog.ach.skins_5"] = { en = "Courtroom Dress Code", ru = "Дресс-код суда" },
	["prog.ach.skins_5.desc"] = { en = "Own {1} skins.", ru = "Собери облики: {1}." },
	["prog.ach.mastery_5"] = { en = "Specialist", ru = "Специалист" },
	["prog.ach.mastery_5.desc"] = {
		en = "Reach Mastery {1} with any kit.",
		ru = "Достигни мастерства {1} с любым набором.",
	},
	["prog.ach.mastery_10"] = { en = "Grandmaster", ru = "Гроссмейстер" },
	["prog.ach.mastery_10.desc"] = {
		en = "Reach Mastery {1} with any kit.",
		ru = "Достигни мастерства {1} с любым набором.",
	},
	["prog.ach.clutch"] = { en = "Last SOUL Standing", ru = "Последняя ДУША" },
	["prog.ach.clutch.desc"] = {
		en = "Win as the only human still standing.",
		ru = "Победи, оставшись единственным выжившим человеком.",
	},
	["prog.ach.collapse_survivor"] = {
		en = "The World Ended. You Didn't.",
		ru = "Мир рухнул. Ты — нет.",
	},
	["prog.ach.collapse_survivor.desc"] = {
		en = "Outlast the Collapse and win.",
		ru = "Переживи Обрушение и победи.",
	},
	["prog.ach.no_mercy"] = { en = "No Mercy", ru = "Без пощады" },
	["prog.ach.no_mercy.desc"] = {
		en = "As the Monster, judge every human before the Collapse.",
		ru = "За монстра осуди всех людей до Обрушения.",
	},
	["prog.ach.unshaken"] = { en = "Not Even Sweating", ru = "Ни капли пота" },
	-- 30 % = Config.Round.FinalPhaseHpFraction (the Phase 2 HP threshold)
	["prog.ach.unshaken.desc"] = {
		en = "Win as the Monster without the humans ever pushing you down to 30% HP.",
		ru = "Победи за монстра так, чтобы люди ни разу не довели тебя до 30% HP.",
	},
	["prog.ach.big_damage"] = { en = "One-SOUL Army", ru = "Армия из одной ДУШИ" },
	["prog.ach.big_damage.desc"] = {
		en = "Deal 1000 damage in a single round.",
		ru = "Нанеси 1000 урона за один раунд.",
	},
	["prog.ach.triple_save"] = { en = "Triple SAVE", ru = "Тройной SAVE" },
	["prog.ach.triple_save.desc"] = {
		en = "Light all three SAVE stars yourself in one round.",
		ru = "Зажги все три звезды SAVE сам за один раунд.",
	},
	["prog.ach.revive_3"] = { en = "Nobody Gets Left Behind", ru = "Своих не бросаем" },
	["prog.ach.revive_3.desc"] = {
		en = "Revive 3 allies in a single round.",
		ru = "Подними 3 союзников за один раунд.",
	},
	["prog.ach.pacifist"] = { en = "True Pacifist", ru = "Истинный пацифист" },
	["prog.ach.pacifist.desc"] = {
		en = "Win as a Human without dealing a single point of damage. Mercy wins.",
		ru = "Победи за людей, не нанеся ни единицы урона. Милосердие побеждает.",
	},

	-- Titles (achievements) --------------------------------------------------------------------------
	["prog.title.first_round"] = { en = "Newcomer", ru = "Новичок" },
	["prog.title.rounds_25"] = { en = "Regular", ru = "Завсегдатай" },
	["prog.title.rounds_100"] = { en = "Hall Veteran", ru = "Ветеран зала" },
	["prog.title.rounds_500"] = { en = "Timeless", ru = "Вне времени" },
	["prog.title.first_win"] = { en = "Determined", ru = "Сама решимость" },
	["prog.title.wins_25"] = { en = "Champion", ru = "Чемпион" },
	["prog.title.wins_100"] = { en = "Underground Hero", ru = "Герой Подземья" },
	["prog.title.monster_win"] = { en = "Bad Time Dealer", ru = "Устроитель плохих времён" },
	["prog.title.monster_wins_25"] = { en = "The Judge", ru = "Судья" },
	["prog.title.human_wins_25"] = { en = "SOUL Keeper", ru = "Хранитель ДУШ" },
	["prog.title.mvp_10"] = { en = "Showstopper", ru = "Гвоздь программы" },
	["prog.title.kills_50"] = { en = "Lots of LOVE", ru = "Много LOVE" },
	["prog.title.kills_250"] = { en = "Executioner", ru = "Палач" },
	["prog.title.damage_25k"] = { en = "Heavy Hitter", ru = "Тяжёлая рука" },
	["prog.title.damage_100k"] = { en = "Unstoppable", ru = "Неудержимая сила" },
	["prog.title.parries_100"] = { en = "Parry Prodigy", ru = "Вундеркинд парирования" },
	["prog.title.parries_500"] = { en = "Living Shield", ru = "Живой щит" },
	["prog.title.dodges_250"] = {
		en = "Dodge Tax Collector",
		ru = "Сборщик налога на уклонения",
	},
	["prog.title.saves_25"] = { en = "Star Lighter", ru = "Зажигатель звёзд" },
	["prog.title.saves_100"] = { en = "Constellation", ru = "Созвездие" },
	["prog.title.revives_25"] = { en = "Second Chance", ru = "Второй шанс" },
	["prog.title.revives_100"] = { en = "Lifeline", ru = "Спасательный круг" },
	["prog.title.heal_5000"] = { en = "Butterscotch Baker", ru = "Мастер ирискового пирога" },
	["prog.title.boxes_10"] = { en = "Box Breaker", ru = "Ломатель коробок" },
	["prog.title.boxes_50"] = { en = "Bullet Dancer", ru = "Танцор среди пуль" },
	["prog.title.box_hits_100"] = { en = "Box Architect", ru = "Архитектор коробок" },
	["prog.title.level_10"] = { en = "Rising SOUL", ru = "Восходящая ДУША" },
	["prog.title.level_25"] = { en = "Seasoned SOUL", ru = "Опытная ДУША" },
	["prog.title.level_50"] = { en = "Shining SOUL", ru = "Сияющая ДУША" },
	["prog.title.level_100"] = { en = "Legendary SOUL", ru = "Легендарная ДУША" },
	["prog.title.streak_7"] = { en = "Daily Determination", ru = "Ежедневная решимость" },
	["prog.title.streak_30"] = { en = "Unshakable Routine", ru = "Железный распорядок" },
	["prog.title.quests_25"] = { en = "Questaholic", ru = "Квестоголик" },
	["prog.title.gold_10k"] = { en = "Treasure Keeper", ru = "Хранитель казны" },
	["prog.title.all_kits"] = { en = "Collector of SOULs", ru = "Собиратель ДУШ" },
	["prog.title.skins_5"] = { en = "Fashion Critic", ru = "Модный критик" },
	["prog.title.mastery_5"] = { en = "Specialist", ru = "Специалист" },
	["prog.title.mastery_10"] = { en = "Grandmaster", ru = "Гроссмейстер" },
	["prog.title.clutch"] = { en = "Last SOUL Standing", ru = "Последний оплот" },
	["prog.title.collapse_survivor"] = { en = "Edge of the World", ru = "Край света" },
	["prog.title.no_mercy"] = { en = "No Mercy", ru = "Без пощады" },
	["prog.title.unshaken"] = { en = "Unshaken", ru = "Невозмутимость" },
	["prog.title.big_damage"] = { en = "One-SOUL Army", ru = "Армия из одной ДУШИ" },
	["prog.title.triple_save"] = { en = "Star Collector", ru = "Собиратель звёзд" },
	["prog.title.revive_3"] = { en = "Guardian Angel", ru = "Ангел-хранитель" },
	["prog.title.pacifist"] = { en = "True Pacifist", ru = "Истинный пацифист" },

	-- Titles (kit mastery 3 / 6 / 10) -----------------------------------------------------------------
	["prog.title.m_ClassicSans_3"] = { en = "Lazy Sentinel", ru = "Ленивый часовой" },
	["prog.title.m_ClassicSans_6"] = { en = "Skeleton of Judgement", ru = "Скелет правосудия" },
	["prog.title.m_ClassicSans_10"] = { en = "Bad Time Incarnate", ru = "Плохое время во плоти" },
	["prog.title.m_LastBreathSans_3"] = { en = "Still Standing", ru = "Всё ещё на ногах" },
	["prog.title.m_LastBreathSans_6"] = { en = "Cracked, Not Broken", ru = "Треснувший, но не сломленный" },
	["prog.title.m_LastBreathSans_10"] = { en = "The Last Breath", ru = "Последний вздох" },
	["prog.title.m_FellSans_3"] = { en = "Red-Eyed Recruit", ru = "Красноглазый новобранец" },
	["prog.title.m_FellSans_6"] = { en = "Kill or Be Killed", ru = "Убей или умри" },
	["prog.title.m_FellSans_10"] = { en = "Royal Executioner", ru = "Королевский палач" },
	["prog.title.m_EclipseSans_3"] = { en = "Void Tourist", ru = "Турист пустоты" },
	["prog.title.m_EclipseSans_6"] = { en = "Rift Walker", ru = "Странник разломов" },
	["prog.title.m_EclipseSans_10"] = { en = "Total Eclipse", ru = "Полное затмение" },
	["prog.title.m_Determination_3"] = { en = "Stubborn Heart", ru = "Упрямое сердце" },
	["prog.title.m_Determination_6"] = { en = "Sheer Willpower", ru = "Чистая сила воли" },
	["prog.title.m_Determination_10"] = { en = "Unbreakable SOUL", ru = "Несокрушимая ДУША" },
	["prog.title.m_Patience_3"] = { en = "Waits Their Turn", ru = "Ждёт своей очереди" },
	["prog.title.m_Patience_6"] = { en = "Calm Before the Storm", ru = "Затишье перед бурей" },
	["prog.title.m_Patience_10"] = { en = "Master of Waiting", ru = "Мастер ожидания" },
	["prog.title.m_Bravery_3"] = { en = "Brave-ish", ru = "Почти храбрец" },
	["prog.title.m_Bravery_6"] = { en = "Fearless Fists", ru = "Бесстрашные кулаки" },
	["prog.title.m_Bravery_10"] = { en = "Lionheart", ru = "Львиное сердце" },
	["prog.title.m_Integrity_3"] = { en = "Prima Ballerina", ru = "Прима-балерина" },
	["prog.title.m_Integrity_6"] = { en = "Graceful Under Fire", ru = "Изящество под огнём" },
	["prog.title.m_Integrity_10"] = { en = "Eternal Encore", ru = "Вечный бис" },
	["prog.title.m_Perseverance_3"] = { en = "Bookworm", ru = "Книжный червь" },
	["prog.title.m_Perseverance_6"] = { en = "Thesis Defended", ru = "Диссертация защищена" },
	["prog.title.m_Perseverance_10"] = { en = "Never Gives Up", ru = "Никогда не сдаётся" },
	["prog.title.m_Kindness_3"] = { en = "Pie Enthusiast", ru = "Любитель пирогов" },
	["prog.title.m_Kindness_6"] = { en = "Head Chef", ru = "Шеф-повар" },
	["prog.title.m_Kindness_10"] = { en = "Kindest SOUL", ru = "Добрейшая ДУША" },
	["prog.title.m_Justice_3"] = { en = "Deputy", ru = "Помощник шерифа" },
	["prog.title.m_Justice_6"] = { en = "Quick Draw", ru = "Быстрая рука" },
	["prog.title.m_Justice_10"] = { en = "High Noon", ru = "Ровно полдень" },

	-- Trails ------------------------------------------------------------------------------------------
	["prog.trail.Soul"] = { en = "SOUL Glow", ru = "Сияние ДУШИ" },
	["prog.trail.Prism"] = { en = "Prismatic Echo", ru = "Призматическое эхо" },
	["prog.trail.none"] = { en = "No trail", ru = "Без шлейфа" },

	-- Round rewards breakdown -----------------------------------------------------------------------
	["prog.reward.participation"] = { en = "Showed up to court", ru = "Явка в суд" },
	["prog.reward.win"] = { en = "Victory", ru = "Победа" },
	["prog.reward.damage"] = { en = "Damage dealt ({1})", ru = "Нанесённый урон ({1})" },
	["prog.reward.healing"] = { en = "Healing ({1})", ru = "Лечение ({1})" },
	["prog.reward.kills"] = { en = "Final blows ({1})", ru = "Последние удары ({1})" },
	["prog.reward.saves"] = { en = "SAVE stars lit ({1})", ru = "Зажжённые SAVE ({1})" },
	["prog.reward.revives"] = { en = "Revives ({1})", ru = "Поднятия ({1})" },
	["prog.reward.parries"] = { en = "Perfect parries ({1})", ru = "Парирования ({1})" },
	["prog.reward.mvp"] = { en = "MVP", ru = "MVP" },
	["prog.reward.firstWin"] = { en = "First win of the day", ru = "Первая победа дня" },
	["prog.reward.levelUp"] = { en = "LV up bonus", ru = "Бонус за новый LV" },
	["prog.reward.mastery"] = { en = "Mastery {1} reward", ru = "Награда мастерства {1}" },
	["prog.reward.achievement"] = { en = "Achievement: {1}", ru = "Достижение: {1}" },
	["prog.reward.practice"] = { en = "Practice round: rewards x{1}", ru = "Тренировка: награды x{1}" },
	["prog.unlock.title"] = { en = "Title: {1}", ru = "Титул: {1}" },
	["prog.unlock.trail"] = { en = "Trail: {1}", ru = "Шлейф: {1}" },
	["prog.unlock.skin"] = { en = "Skin: {1}", ru = "Облик: {1}" },
	["prog.unlock.kit"] = { en = "Kit: {1}", ru = "Набор: {1}" },
	["prog.unlock.achievement"] = { en = "Achievement: {1}", ru = "Достижение: {1}" },
	["prog.unlock.mastery"] = { en = "{1} Mastery {2}", ru = "{1}: мастерство {2}" },

	-- Request failures ------------------------------------------------------------------------------
	["prog.err.rateLimited"] = {
		en = "Whoa, slow down. Even skeletons need breaks.",
		ru = "Помедленнее. Даже скелетам нужны перерывы.",
	},
	["prog.err.badRequest"] = {
		en = "That request made no sense. At all.",
		ru = "В этом запросе не было смысла. Совсем.",
	},
	["prog.err.notReady"] = {
		en = "Your profile is still loading...",
		ru = "Профиль ещё загружается...",
	},
	["prog.err.unknownItem"] = {
		en = "That doesn't exist. Spooky.",
		ru = "Такого не существует. Жутковато.",
	},
	["prog.err.notOwned"] = { en = "You don't own that yet.", ru = "У тебя этого пока нет." },
	["prog.err.owned"] = { en = "You already own that.", ru = "Это у тебя уже есть." },
	["prog.err.gold"] = {
		en = "Not enough G ({1} needed). Have you tried winning?",
		ru = "Не хватает G (нужно {1}). Может, попробовать побеждать?",
	},
	["prog.err.level"] = {
		en = "Requires LV {1}. Keep fighting.",
		ru = "Нужен LV {1}. Продолжай сражаться.",
	},
	["prog.err.needKit"] = { en = "Unlock that kit first.", ru = "Сначала открой этот набор." },
	["prog.err.masteryOnly"] = {
		en = "Mastery skins are earned, not bought.",
		ru = "Облики мастерства зарабатывают, а не покупают.",
	},
	["prog.err.notForSale"] = { en = "That's not for sale.", ru = "Это не продаётся." },
	["prog.err.settingKey"] = { en = "Unknown setting.", ru = "Неизвестная настройка." },
	["prog.err.settingValue"] = {
		en = "That value is out of range.",
		ru = "Значение вне допустимого диапазона.",
	},
	["prog.err.questInvalid"] = { en = "That quest doesn't exist.", ru = "Такого задания нет." },
	["prog.err.questDone"] = {
		en = "That quest is already complete.",
		ru = "Это задание уже выполнено.",
	},
	["prog.err.questNotDone"] = { en = "Finish the quest first.", ru = "Сначала выполни задание." },
	["prog.err.questClaimed"] = { en = "Already claimed.", ru = "Уже получено." },
	["prog.err.questExpired"] = {
		en = "Those quests have expired.",
		ru = "Эти задания уже истекли.",
	},
	["prog.err.rerollUsed"] = {
		en = "You already rerolled a quest this window.",
		ru = "Замена в этом окне уже использована.",
	},
	["prog.err.rolePref"] = {
		en = "Pick Either, Monster or Human.",
		ru = "Выбери: любая роль, монстр или человек.",
	},

	-- Notifications --------------------------------------------------------------------------------
	["prog.notify.memoryMode"] = {
		en = "Test server: progress won't be saved here.",
		ru = "Тестовый сервер: прогресс здесь не сохраняется.",
	},
	["prog.notify.loadFailed"] = {
		en = "Couldn't load your progress. This session won't be saved. Try rejoining later.",
		ru = "Не удалось загрузить прогресс. Эта сессия не сохранится. Перезайди позже.",
	},
	["prog.notify.lockWait"] = {
		en = "Fetching your SOUL from your last server...",
		ru = "Забираем твою ДУШУ с прошлого сервера...",
	},
	["prog.notify.welcome"] = {
		en = "Welcome to the hall, {1}. Try not to have a bad time.",
		ru = "Добро пожаловать в зал, {1}. Постарайся не попасть в плохое время.",
	},
	["prog.notify.levelUp"] = {
		en = "LV UP! You reached LV {1}. (+{2} G)",
		ru = "LV UP! Достигнут LV {1}. (+{2} G)",
	},
	["prog.notify.questComplete"] = {
		en = "Quest complete: {1}. Claim it in Quests!",
		ru = "Задание выполнено: {1}. Забери награду в Заданиях!",
	},
	["prog.notify.questClaimed"] = {
		en = "Quest reward: +{1} EXP, +{2} G",
		ru = "Награда за задание: +{1} EXP, +{2} G",
	},
	["prog.notify.questAutoClaimed"] = {
		en = "Unclaimed quest rewards delivered: +{1} EXP, +{2} G",
		ru = "Невостребованные награды доставлены: +{1} EXP, +{2} G",
	},
	["prog.notify.questsNew"] = { en = "New quests have arrived!", ru = "Пришли новые задания!" },
	["prog.notify.rerolled"] = {
		en = "Quest rerolled. Fate shuffled the deck.",
		ru = "Задание заменено. Судьба перетасовала колоду.",
	},
	["prog.notify.achievement"] = { en = "Achievement unlocked: {1}", ru = "Достижение открыто: {1}" },
	["prog.notify.masteryUp"] = { en = "{1} reached Mastery {2}!", ru = "{1}: мастерство {2}!" },
	["prog.notify.streak"] = {
		en = "Day {1} login streak! +{2} G",
		ru = "Серия входов: день {1}! +{2} G",
	},
	["prog.notify.streakSoft"] = {
		en = "Welcome back! Your streak didn't break, it just got softer: day {1}. +{2} G",
		ru = "С возвращением! Серия не сгорела, а лишь смягчилась: день {1}. +{2} G",
	},
	["prog.notify.bought"] = { en = "Purchased: {1}", ru = "Куплено: {1}" },
	["prog.notify.boughtKit"] = { en = "{1} joins your roster!", ru = "{1} теперь в твоём составе!" },
	["prog.notify.equipped"] = { en = "Equipped: {1}", ru = "Выбрано: {1}" },
	["prog.notify.titleSet"] = { en = "Title set: {1}", ru = "Титул: {1}" },
	["prog.notify.titleCleared"] = {
		en = "Title removed. Anonymity suits you.",
		ru = "Титул снят. Анонимность тебе к лицу.",
	},
	["prog.notify.trailSet"] = { en = "Trail equipped: {1}", ru = "Шлейф: {1}" },
	["prog.notify.trailCleared"] = { en = "Trail removed.", ru = "Шлейф снят." },
	["prog.notify.shopRestock"] = {
		en = "The shop restocked. Fresh skins, same shopkeeper.",
		ru = "Магазин обновился. Облики свежие, продавец тот же.",
	},

	-- Shopkeeper one-liners -------------------------------------------------------------------------
	["prog.shop.quip.1"] = {
		en = "everything here costs G. the honest kind. this shop doesn't even know what robux are.",
		ru = "здесь всё за G. за честные G. эта лавка даже не знает, что такое робуксы.",
	},
	["prog.shop.quip.2"] = {
		en = "today's featured deal: 20% off. i'd call it a steal, but stealing is illegal.",
		ru = "скидка дня: 20%. я бы сказал «даром», но это незаконно.",
	},
	["prog.shop.quip.3"] = {
		en = "new stock every day at midnight. UTC. don't ask me what UTC stands for.",
		ru = "новый товар каждую полночь. по UTC. не спрашивай, что это значит.",
	},
	["prog.shop.quip.4"] = {
		en = "a skin won't make you stronger. it'll make you look stronger. huge difference.",
		ru = "облик не сделает тебя сильнее. только с виду. огромная разница.",
	},
	["prog.shop.quip.5"] = {
		en = "mastery skins aren't for sale. you earn those the old way: by getting dunked on a lot.",
		ru = "облики мастерства не продаются. их зарабатывают по старинке: проигрывая и учась.",
	},
}
