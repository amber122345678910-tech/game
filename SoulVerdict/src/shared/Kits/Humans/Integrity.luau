--!strict
-- Kit data: Integrity (blue SOUL) — Ballet Shoes & Old Tutu. Mobility / disruption. Lune-safe.
local Types = require(script.Parent.Parent.Parent.Types)

local kit: Types.KitDef = {
	Id = "Integrity",
	Role = "Human",
	Rig = "Integrity",
	Family = "Human",
	Order = 4,
	Name = { en = "Integrity", ru = "Честность" },
	Title = { en = "The Dancer", ru = "Танцор" },
	Lore = {
		en = "A dancer in an old tutu who crossed the glowing waters of Waterfall on the tips of their toes.",
		ru = "Танцор в старой пачке, пересёкший светящиеся воды Водопадья на кончиках пальцев.",
	},
	Playstyle = {
		en = "Double jump, leap in, spin away. Reflect bones with Pirouette and chain your ultimate dashes.",
		ru = "Двойной прыжок, прыжок в бой, уход вращением. Отражай кости Пируэтом и связывай рывки ульты.",
	},
	Color = Color3.fromRGB(0, 60, 255),
	Difficulty = 2,
	Stats = { MaxHP = 105, WalkSpeed = 19, JumpPower = 54, MaxGuard = 90, DoubleJump = true },
	Passives = {
		{
			Id = "Grace",
			Icon = "Shoe",
			Name = { en = "Grace", ru = "Грация" },
			Desc = { en = "You can double jump.", ru = "Ты можешь делать двойной прыжок." },
		},
	},
	Abilities = {
		{
			Id = "BalletKicks",
			Slot = "M1",
			Icon = "Shoe",
			Name = { en = "Ballet Kicks", ru = "Балетные удары" },
			Desc = { en = "Three elegant kicks.", ru = "Три изящных удара ногой." },
			Cooldown = 0.36,
			Combo = 3,
			Aim = "Direction",
			Clip = "Kick1",
			Windup = 0.1,
			Tags = { "Melee" },
			Numbers = { Damage1 = 7, Damage2 = 7, Damage3 = 11, Range = 6, Knockback = 25, ComboWindow = 0.9 },
		},
		{
			Id = "GrandJete",
			Slot = "Q",
			Icon = "Spin",
			Name = { en = "Grand Jeté", ru = "Гран жете" },
			Desc = { en = "Leap to a point up to 30 studs away and land with a kick shockwave.", ru = "Прыжок в точку до 30 стадов с ударной волной при приземлении." },
			Cooldown = 8,
			Range = 30,
			Aim = "Ground",
			Clip = "Leap",
			Windup = 0.15,
			Tags = { "Mobility", "Area" },
			Numbers = { Damage = 14, Radius = 7, Distance = 30, Knockback = 30, AirTime = 0.6 },
		},
		{
			Id = "Pirouette",
			Slot = "E",
			Icon = "Spin",
			Name = { en = "Pirouette", ru = "Пируэт" },
			Desc = {
				en = "Spin for 1.2s: bone projectiles touching you are destroyed, melee can't hurt you, adjacent enemies take damage.",
				ru = "Вращение 1.2с: костяные снаряды рядом уничтожаются, ближний бой не ранит, соседние враги получают урон.",
			},
			Cooldown = 11,
			Aim = "Self",
			Clip = "Spin",
			Windup = 0.0,
			Tags = { "Shield", "Area" },
			Numbers = { Duration = 1.2, TickDamage = 5, Radius = 6, Ticks = 4 },
		},
		{
			Id = "Encore",
			Slot = "R",
			Icon = "Star",
			Ult = true,
			Name = { en = "Encore", ru = "На бис" },
			Desc = {
				en = "Ultimate. Three rapid dashes through enemies — each removes 1 dodge — then a final bow burst.",
				ru = "Ультимейт. Три стремительных рывка сквозь врагов — каждый снимает 1 уклонение — и финальный поклон-взрыв.",
			},
			Cooldown = 3,
			Range = 20,
			Aim = "Direction",
			Clip = "Spin",
			Windup = 0.2,
			Tags = { "Ultimate", "Mobility" },
			Numbers = { Dashes = 3, DashDamage = 12, Distance = 20, FinalDamage = 20, Radius = 9, DodgeDrain = 1 },
		},
	},
	Unlock = { Gold = 500 },
	Skins = {
		{ Id = "Default", Name = { en = "Old Tutu", ru = "Старая пачка" }, Price = 0, Rarity = "Common", Palette = {} },
		{
			Id = "Swan",
			Name = { en = "Black Swan", ru = "Чёрный лебедь" },
			Price = 1100,
			Rarity = "Epic",
			Palette = { Tutu = Color3.fromRGB(25, 25, 35), Sweater = Color3.fromRGB(40, 40, 60), Shoes = Color3.fromRGB(200, 40, 80) },
		},
	},
}

return kit
