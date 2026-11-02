--!strict
-- Kit data: Patience (cyan SOUL) — Toy Knife & Faded Ribbon. Stealth assassin. Lune-safe.
local Types = require(script.Parent.Parent.Parent.Types)

local kit: Types.KitDef = {
	Id = "Patience",
	Role = "Human",
	Rig = "Patience",
	Family = "Human",
	Order = 2,
	Name = { en = "Patience", ru = "Терпение" },
	Title = { en = "The Quiet One", ru = "Тихоня" },
	Lore = {
		en = "The first to fall in the Ruins, with a faded ribbon and a toy knife. Waiting is a weapon too.",
		ru = "Первый павший в Руинах — с выцветшей лентой и игрушечным ножом. Ожидание — тоже оружие.",
	},
	Playstyle = {
		en = "Wait in stealth, strike when the monster commits, slip away. Your first stealth hit drains dodges.",
		ru = "Жди в невидимости, бей, когда монстр раскроется, и уходи. Первый удар из невидимости сжигает уклонения.",
	},
	Color = Color3.fromRGB(66, 252, 255),
	Difficulty = 3,
	Stats = { MaxHP = 95, WalkSpeed = 18, JumpPower = 50, MaxGuard = 80 },
	Passives = {
		{
			Id = "Calm",
			Icon = "Clock",
			Name = { en = "Calm", ru = "Спокойствие" },
			Desc = { en = "Standing still heals 3 HP per second.", ru = "Стоя на месте, лечишь 3 HP в секунду." },
		},
	},
	Abilities = {
		{
			Id = "ToyKnife",
			Slot = "M1",
			Icon = "Knife",
			Name = { en = "Toy Knife", ru = "Игрушечный нож" },
			Desc = { en = "Three quick stabs.", ru = "Три быстрых укола." },
			Cooldown = 0.3,
			Combo = 3,
			Aim = "Direction",
			Clip = "Slash1",
			Windup = 0.07,
			Tags = { "Melee" },
			Numbers = { Damage1 = 6, Damage2 = 6, Damage3 = 10, Range = 5.5, ComboWindow = 0.9 },
		},
		{
			Id = "RibbonSnare",
			Slot = "Q",
			Icon = "Ribbon",
			Name = { en = "Ribbon Snare", ru = "Ленточная петля" },
			Desc = {
				en = "Throw the faded ribbon. A hit slows the monster by 40% and removes 1 dodge.",
				ru = "Бросаешь выцветшую ленту. Попадание замедляет монстра на 40% и снимает 1 уклонение.",
			},
			Cooldown = 8,
			Range = 45,
			Aim = "Direction",
			Clip = "Throw",
			Windup = 0.18,
			Tags = { "Projectile", "Control" },
			Numbers = { Damage = 6, Speed = 80, SlowMult = 0.6, SlowTime = 2.5, DodgeDrain = 1 },
		},
		{
			Id = "Patience",
			Slot = "E",
			Icon = "Stealth",
			Name = { en = "Patience", ru = "Терпение" },
			Desc = {
				en = "Fade out for up to 6s. Your next hit from stealth deals +60% and cannot be dodged.",
				ru = "Исчезаешь до 6с. Следующий удар из невидимости наносит +60% и не может быть уклонён.",
			},
			Cooldown = 14,
			Aim = "Self",
			Clip = "Guard",
			Windup = 0.2,
			Tags = { "Stealth" },
			Numbers = { Duration = 6, BonusMult = 1.6 },
		},
		{
			Id = "WaitingGame",
			Slot = "R",
			Icon = "Clock",
			Ult = true,
			Name = { en = "Waiting Game", ru = "Игра в ожидание" },
			Desc = {
				en = "Ultimate. A cyan field (radius 16, 6s): the monster inside is slowed 50% and its cooldowns tick at half speed.",
				ru = "Ультимейт. Голубое поле (радиус 16, 6с): монстр внутри замедлен на 50%, его перезарядки идут вдвое медленнее.",
			},
			Cooldown = 3,
			Range = 40,
			Aim = "Ground",
			Clip = "Cast",
			Windup = 0.4,
			Tags = { "Ultimate", "Area", "Control" },
			Numbers = { Radius = 16, Duration = 6, SlowMult = 0.5, CooldownMult = 0.5 },
		},
	},
	Unlock = { Gold = 600 },
	Skins = {
		{ Id = "Default", Name = { en = "Faded Ribbon", ru = "Выцветшая лента" }, Price = 0, Rarity = "Common", Palette = {} },
		{
			Id = "Frost",
			Name = { en = "Frost Ribbon", ru = "Ледяная лента" },
			Price = 800,
			Rarity = "Rare",
			Palette = { Ribbon = Color3.fromRGB(40, 120, 200), ToyBlade = Color3.fromRGB(210, 240, 255), ToyHandle = Color3.fromRGB(90, 180, 230) },
		},
	},
}

return kit
