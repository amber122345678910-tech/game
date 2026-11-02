--!strict
-- Kit data: Kindness (green SOUL) — Burnt Pan & Stained Apron. Healer / support. Lune-safe.
local Types = require(script.Parent.Parent.Parent.Types)

local kit: Types.KitDef = {
	Id = "Kindness",
	Role = "Human",
	Rig = "Kindness",
	Family = "Human",
	Order = 6,
	Name = { en = "Kindness", ru = "Доброта" },
	Title = { en = "The Cook", ru = "Повар" },
	Lore = {
		en = "A gentle kid in a stained apron who fed everyone they met — and hit hard with a burnt pan when needed.",
		ru = "Добрый ребёнок в запачканном фартуке, кормивший всех встречных — и больно бивший сковородкой, когда надо.",
	},
	Playstyle = {
		en = "Keep the team alive. Heal zones cleanse KR, shields absorb blasters, your ultimate resets a bad fight.",
		ru = "Держи команду в живых. Зоны лечения очищают KR, щиты поглощают бластеры, ульта спасает проигранный бой.",
	},
	Color = Color3.fromRGB(0, 192, 0),
	Difficulty = 1,
	Stats = { MaxHP = 120, WalkSpeed = 16, JumpPower = 50, MaxGuard = 110 },
	Passives = {
		{
			Id = "Nurturing",
			Icon = "Heart",
			Name = { en = "Nurturing", ru = "Забота" },
			Desc = { en = "Allies within 8 studs regenerate 1 HP per second.", ru = "Союзники в радиусе 8 восстанавливают 1 HP в секунду." },
		},
	},
	Abilities = {
		{
			Id = "PanBonk",
			Slot = "M1",
			Icon = "Pan",
			Name = { en = "Burnt Pan", ru = "Горелая сковорода" },
			Desc = { en = "Three swings; the last BONK dazes briefly.", ru = "Три замаха; последний БАМ ненадолго оглушает." },
			Cooldown = 0.42,
			Combo = 3,
			Aim = "Direction",
			Clip = "Slash1",
			Windup = 0.12,
			Tags = { "Melee" },
			Numbers = { Damage1 = 6, Damage2 = 6, Damage3 = 12, Range = 5.5, Daze = 0.4, ComboWindow = 0.9 },
		},
		{
			Id = "HomeCooking",
			Slot = "Q",
			Icon = "Food",
			Name = { en = "Home Cooking", ru = "Домашняя еда" },
			Desc = {
				en = "Toss a dish that becomes a healing zone for 5s: 6 HP/s to allies, removes KR.",
				ru = "Бросаешь блюдо, которое становится зоной лечения на 5с: 6 HP/с союзникам, снимает KR.",
			},
			Cooldown = 12,
			Range = 35,
			Aim = "Ground",
			Clip = "Throw",
			Windup = 0.2,
			Tags = { "Heal", "Area" },
			Numbers = { Radius = 9, Duration = 5, HealPerSecond = 6 },
		},
		{
			Id = "KindShield",
			Slot = "E",
			Icon = "Shield",
			Name = { en = "Kind Shield", ru = "Добрый щит" },
			Desc = {
				en = "Shield the ally you aim at (or yourself): absorbs 40 damage for 5s.",
				ru = "Щит союзнику в прицеле (или себе): поглощает 40 урона на 5с.",
			},
			Cooldown = 10,
			Range = 40,
			Aim = "Ally",
			Clip = "Heal",
			Windup = 0.1,
			Tags = { "Shield" },
			Numbers = { Amount = 40, Duration = 5 },
		},
		{
			Id = "ButterscotchFeast",
			Slot = "R",
			Icon = "Food",
			Ult = true,
			Name = { en = "Butterscotch Feast", ru = "Ириска-пир" },
			Desc = {
				en = "Ultimate. Heal all allies within 30 studs for 45 HP, clear KR and debuffs, +30% speed for 4s. Also revives a downed ally in range.",
				ru = "Ультимейт. Лечит всех союзников в радиусе 30 на 45 HP, снимает KR и дебаффы, +30% скорости на 4с. Поднимает поверженного союзника рядом.",
			},
			Cooldown = 3,
			Aim = "Self",
			Clip = "Heal",
			Windup = 0.4,
			Tags = { "Ultimate", "Heal" },
			Numbers = { Radius = 30, Heal = 45, SpeedMult = 1.3, SpeedTime = 4 },
		},
	},
	Unlock = { Gold = 0 },
	Skins = {
		{ Id = "Default", Name = { en = "Stained Apron", ru = "Запачканный фартук" }, Price = 0, Rarity = "Common", Palette = {} },
		{
			Id = "Chef",
			Name = { en = "Chef's Pan", ru = "Сковорода шефа" },
			Price = 900,
			Rarity = "Rare",
			Palette = { Pan = Color3.fromRGB(160, 160, 170), PanHandle = Color3.fromRGB(30, 30, 34) },
		},
	},
}

return kit
