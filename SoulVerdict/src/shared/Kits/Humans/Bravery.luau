--!strict
-- Kit data: Bravery (orange SOUL) — Tough Glove & Manly Bandanna. Bruiser / tank. Lune-safe.
local Types = require(script.Parent.Parent.Parent.Types)

local kit: Types.KitDef = {
	Id = "Bravery",
	Role = "Human",
	Rig = "Bravery",
	Family = "Human",
	Order = 3,
	Name = { en = "Bravery", ru = "Храбрость" },
	Title = { en = "The Brawler", ru = "Драчун" },
	Lore = {
		en = "A tough kid with a bandanna and a boxing glove who walked into the snow and never backed down.",
		ru = "Крепкий ребёнок с банданой и боксёрской перчаткой, ушедший в снега и ни разу не отступивший.",
	},
	Playstyle = {
		en = "Stand in front. Charge in, stun, protect the team with Brave Stand.",
		ru = "Стой впереди. Врывайся, оглушай, защищай команду Храброй стойкой.",
	},
	Color = Color3.fromRGB(252, 166, 0),
	Difficulty = 1,
	Stats = { MaxHP = 150, WalkSpeed = 16, JumpPower = 48, MaxGuard = 150 },
	Passives = {
		{
			Id = "Unbreakable",
			Icon = "Shield",
			Name = { en = "Unbreakable", ru = "Несгибаемый" },
			Desc = { en = "+50% Guard and faster Guard recovery.", ru = "+50% Защиты и быстрее её восстановление." },
		},
	},
	Abilities = {
		{
			Id = "ToughPunches",
			Slot = "M1",
			Icon = "Fist",
			Name = { en = "Tough Glove", ru = "Крепкая перчатка" },
			Desc = { en = "A heavy four-punch combo; the last punch staggers.", ru = "Тяжёлое комбо из четырёх ударов; последний пошатывает." },
			Cooldown = 0.4,
			Combo = 4,
			Aim = "Direction",
			Clip = "Punch1",
			Windup = 0.1,
			Tags = { "Melee" },
			Numbers = { Damage1 = 8, Damage2 = 8, Damage3 = 9, Damage4 = 14, Range = 5.5, Stagger = 0.3, Knockback = 30, ComboWindow = 0.9 },
		},
		{
			Id = "GutsCharge",
			Slot = "Q",
			Icon = "Fist",
			Name = { en = "Guts Charge", ru = "Рывок отваги" },
			Desc = {
				en = "Charge 22 studs. Hitting the monster stuns it for 0.8s (stunned monsters cannot dodge).",
				ru = "Рывок на 22 стада. Попадание по монстру оглушает его на 0.8с (оглушённый не уклоняется).",
			},
			Cooldown = 9,
			Range = 22,
			Aim = "Direction",
			Clip = "Charge",
			Windup = 0.15,
			Tags = { "Mobility", "Control" },
			Numbers = { Damage = 18, Distance = 22, Stun = 0.8 },
		},
		{
			Id = "BraveStand",
			Slot = "E",
			Icon = "Shield",
			Name = { en = "Brave Stand", ru = "Храбрая стойка" },
			Desc = {
				en = "For 3s you and allies within 10 studs take 40% less damage.",
				ru = "На 3с ты и союзники в радиусе 10 получаете на 40% меньше урона.",
			},
			Cooldown = 15,
			Aim = "Self",
			Clip = "Guard",
			Windup = 0.15,
			Tags = { "Buff", "Shield" },
			Numbers = { Duration = 3, Radius = 10, Reduction = 0.4 },
		},
		{
			Id = "BurningCourage",
			Slot = "R",
			Icon = "Flame",
			Ult = true,
			Name = { en = "Burning Courage", ru = "Пылающая отвага" },
			Desc = {
				en = "Ultimate. Leap and slam: a fiery shockwave stuns and drains 2 dodges; allies gain +15% damage for 6s.",
				ru = "Ультимейт. Прыжок и удар: огненная волна оглушает и снимает 2 уклонения; союзники получают +15% урона на 6с.",
			},
			Cooldown = 3,
			Range = 24,
			Aim = "Ground",
			Clip = "Leap",
			Windup = 0.6,
			Tags = { "Ultimate", "Area", "Control" },
			Numbers = { Radius = 14, Damage = 30, Stun = 1.2, DodgeDrain = 2, AllyBuff = 1.15, BuffTime = 6 },
		},
	},
	Unlock = { Gold = 0 },
	Skins = {
		{ Id = "Default", Name = { en = "Manly Bandanna", ru = "Мужественная бандана" }, Price = 0, Rarity = "Common", Palette = {} },
		{
			Id = "Champion",
			Name = { en = "Champion Gloves", ru = "Перчатки чемпиона" },
			Price = 900,
			Rarity = "Rare",
			Palette = { Glove = Color3.fromRGB(240, 200, 60), Bandanna = Color3.fromRGB(30, 30, 30) },
		},
	},
}

return kit
