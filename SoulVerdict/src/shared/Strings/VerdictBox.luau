--!strict
-- Verdict Box strings (SPEC §11). Lune-safe. Every key starts with "vb." and has en + ru with the same {n} placeholders.
-- Opening lines ("vb.line.<Set>.<n>", picked by VerdictBox/Patterns from the seed) are ORIGINAL lines in each
-- monster's voice (lowercase Sans-style speech), typed with a typewriter before the first attack.
return {
	-- opening lines -------------------------------------------------------------------------------------------
	["vb.line.Classic.1"] = { en = "* court's in session, kiddo.", ru = "* суд идёт, малыш." },
	["vb.line.Classic.2"] = {
		en = "* let's weigh your soul, pal.",
		ru = "* взвесим твою душу, приятель.",
	},
	["vb.line.Classic.3"] = {
		en = "* hold still. quick trial.",
		ru = "* не дёргайся. суд быстрый.",
	},
	["vb.line.Fell.1"] = { en = "* heh. nowhere to run now.", ru = "* хех. бежать больше некуда." },
	["vb.line.Fell.2"] = {
		en = "* sentence first. trial later.",
		ru = "* сначала приговор. суд потом.",
	},
	["vb.line.Fell.3"] = {
		en = "* this box is your cell, punk.",
		ru = "* эта коробка - твоя камера.",
	},
	["vb.line.Eclipse.1"] = {
		en = "* lights out, little soul.",
		ru = "* гаснет свет, маленькая душа.",
	},
	["vb.line.Eclipse.2"] = {
		en = "* the dark has a verdict too.",
		ru = "* у тьмы тоже есть приговор.",
	},
	["vb.line.Eclipse.3"] = {
		en = "* don't blink. the void won't.",
		ru = "* не моргай. пустота не моргнёт.",
	},

	-- battle UI -----------------------------------------------------------------------------------------------
	["vb.title"] = { en = "VERDICT BOX", ru = "КОРОБКА ПРИГОВОРА" },
	["vb.hp"] = { en = "HP", ru = "ОЗ" },
	["vb.kr"] = { en = "KR", ru = "КР" },
	["vb.lv"] = { en = "LV {1}", ru = "LV {1}" },
	["vb.jump"] = { en = "JUMP", ru = "ПРЫЖОК" },
	["vb.hint.move"] = { en = "MOVE: WASD / ARROWS / STICK", ru = "ДВИЖЕНИЕ: WASD / СТРЕЛКИ / СТИК" },
	["vb.hint.move.touch"] = { en = "DRAG ON THE LEFT TO MOVE", ru = "ВЕДИ ПАЛЬЦЕМ СЛЕВА" },
	["vb.hint.jump"] = {
		en = "BLUE SOUL: JUMP WITH UP / SPACE",
		ru = "СИНЯЯ ДУША: ПРЫЖОК - ВВЕРХ / ПРОБЕЛ",
	},
	["vb.hint.jump.pad"] = { en = "BLUE SOUL: JUMP WITH A", ru = "СИНЯЯ ДУША: ПРЫЖОК - A" },
	["vb.hint.jump.touch"] = { en = "BLUE SOUL: TAP JUMP", ru = "СИНЯЯ ДУША: ЖМИ «ПРЫЖОК»" },
	["vb.hint.blue"] = { en = "BLUE: STAY STILL", ru = "СИНИЕ: НЕ ДВИГАЙСЯ" },
	["vb.hint.orange"] = { en = "ORANGE: KEEP MOVING", ru = "ОРАНЖЕВЫЕ: ДВИГАЙСЯ" },
	["vb.hits"] = { en = "HITS {1}", ru = "ПОПАДАНИЯ {1}" },

	-- watchers (3D box) ---------------------------------------------------------------------------------------
	["vb.watch"] = { en = "{1} IS ON TRIAL", ru = "{1} НА СУДЕ" },

	-- verdict -------------------------------------------------------------------------------------------------
	["vb.verdict.Innocent"] = { en = "INNOCENT", ru = "НЕВИНОВЕН" },
	["vb.verdict.Guilty"] = { en = "GUILTY", ru = "ВИНОВЕН" },
	["vb.verdict.Dismissed"] = { en = "DISMISSED", ru = "ДЕЛО ЗАКРЫТО" },
	["vb.verdict.Innocent.sub"] = {
		en = "* your SOUL held firm. DAMAGE UP!",
		ru = "* твоя ДУША выстояла. УРОН ПОВЫШЕН!",
	},
	["vb.verdict.Guilty.sub"] = {
		en = "* {1} hits. your SOUL endures.",
		ru = "* попаданий: {1}. ДУША держится.",
	},
	["vb.verdict.Dismissed.sub"] = { en = "* the trial was interrupted.", ru = "* суд прерван." },
}
