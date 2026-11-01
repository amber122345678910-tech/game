--!strict
-- Kit data: Perseverance (purple SOUL) — Torn Notebook & Cloudy Glasses. Control / utility. Lune-safe.
local Types = require(script.Parent.Parent.Parent.Types)

local kit: Types.KitDef = {
	Id = "Perseverance",
	Role = "Human",
	Rig = "Perseverance",
	Family = "Human",
	Order = 5,
	Name = { en = "Perseverance", ru = "Упорство" },
	Title = { en = "The Scholar", ru = "Книжник" },
	Lore = {
		en = "A bookish kid with cloudy glasses and a torn notebook, who kept writing even in the heat of Hotland.",
		ru = "Начитанный ребёнок в мутных очках с рваной тетрадью, продолжавший писать даже в жаре Хотленда.",
	},
	Playstyle = {
		en = "Read the monster: you see its cooldowns. Root it with pages, rewind mistakes, slam it shut with your ultimate.",
		ru = "Читай монстра: ты видишь его перезарядки. Связывай страницами, отматывай ошибки, захлопывай ультой.",
	},
	Color = Color3.fromRGB(213, 53, 217),
	Difficulty = 2,
	Stats = { MaxHP = 100, WalkSpeed = 17, JumpPower = 50, MaxGuard = 100 },
	Passives = {
		{
			Id = "Studious",
			Icon = "Book",
			Name = { en = "Studious", ru = "Прилежность" },
			Desc = { en = "You can see the monster's ability cooldowns.", ru = "Ты видишь перезарядки способностей монстра." },
		},
	},
	Abilities = {
		{
			Id = "NotebookSwat",
			Slot = "M1",
			Icon = "Book",
			Name = { en = "Notebook Swat", ru = "Удар тетрадью" },
			Desc = { en = "Three wide swats with a heavy notebook.", ru = "Три широких удара тяжёлой тетрадью." },
			Cooldown = 0.42,
			Combo = 3,
			Aim = "Direction",
			Clip = "Slash1",
			Windup = 0.12,
			Tags = { "Melee" },
			Numbers = { Damage1 = 6, Damage2 = 7, Damage3 = 10, Range = 6.5, ComboWindow = 0.9 },
		},
		{
			Id = "SpellboundPages",
			Slot = "Q",
			Icon = "Book",
			Name = { en = "Spellbound Pages", ru = "Заколдованные страницы" },
			Desc = {
				en = "Fire a stream of 5 pages. If 3 or more hit, the monster is rooted for 1s.",
				ru = "Выпускаешь поток из 5 страниц. Если попадут 3 и больше — монстр обездвижен на 1с.",
			},
			Cooldown = 9,
			Range = 50,
			Aim = "Direction",
			Clip = "CastForward",
			Windup = 0.15,
			Tags = { "Projectile", "Control" },
			Numbers = { Pages = 5, Damage = 4, Speed = 70, Interval = 0.08, RootHits = 3, Root = 1.0 },
		},
		{
			Id = "Rewrite",
			Slot = "E",
			Icon = "Rewind",
			Name = { en = "Rewrite", ru = "Переписать" },
			Desc = {
				en = "Rewind your position and HP to where you were 3 seconds ago. KR is cleared.",
				ru = "Отматываешь позицию и HP на 3 секунды назад. KR очищается.",
			},
			Cooldown = 16,
			Aim = "Self",
			Clip = "Cast",
			Windup = 0.1,
			Tags = { "Mobility", "Heal" },
			Numbers = { Seconds = 3 },
		},
		{
			Id = "FinalChapter",
			Slot = "R",
			Icon = "Book",
			Ult = true,
			Name = { en = "Final Chapter", ru = "Последняя глава" },
			Desc = {
				en = "Ultimate. A giant book appears over the monster and slams shut: big damage, cannot be dodged, silences for 3s.",
				ru = "Ультимейт. Над монстром появляется огромная книга и захлопывается: много урона, без уклонения, немота на 3с.",
			},
			Cooldown = 3,
			Range = 60,
			Aim = "Target",
			Clip = "CastUp",
			Windup = 0.8,
			Tags = { "Ultimate", "Control" },
			Numbers = { Damage = 35, Silence = 3, Delay = 0.8 },
		},
	},
	Unlock = { Gold = 700 },
	Skins = {
		{ Id = "Default", Name = { en = "Cloudy Glasses", ru = "Мутные очки" }, Price = 0, Rarity = "Common", Palette = {} },
		{
			Id = "Midnight",
			Name = { en = "Night Owl", ru = "Сова" },
			Price = 800,
			Rarity = "Rare",
			Palette = { Sweater = Color3.fromRGB(30, 30, 70), Stripe = Color3.fromRGB(200, 170, 255), Book = Color3.fromRGB(60, 20, 90) },
		},
	},
}

return kit
