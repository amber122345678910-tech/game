--!strict
-- Текстуры. В месте по умолчанию стоят встроенные текстуры клиента (rbxasset:// — есть всегда);
-- при запуске клиент предзагружает качественные публичные текстуры из Магазина Roblox (rbxassetid://)
-- и, если они загрузились, подменяет ими встроенные (см. FX/Effects: upgradeTextures).

local Textures = {}

export type Tex = {
	id: string, -- качественная текстура (изображение из Магазина Roblox)
	fallback: string, -- встроенная текстура клиента
	flipbook: string?, -- раскладка флипбука для id: "Grid2x2" | "Grid4x4" | "Grid8x8"
}

Textures.hq = {
	-- дым и туман
	smokePuffs = { id = "rbxassetid://13346862770", fallback = "rbxasset://textures/particles/smoke_main.dds", flipbook = "Grid4x4" },
	softFog = { id = "rbxassetid://5611867493", fallback = "rbxasset://textures/particles/smoke_main.dds" },
	mist = { id = "rbxassetid://16830667309", fallback = "rbxasset://textures/particles/smoke_main.dds" },
	cumulusPuff = { id = "rbxassetid://6956634044", fallback = "rbxasset://textures/particles/smoke_main.dds" },
	whitePuff = { id = "rbxassetid://716847870", fallback = "rbxasset://textures/particles/smoke_main.dds" },
	fogStrip = { id = "rbxassetid://18715969952", fallback = "rbxasset://textures/particles/smoke_main.dds" },
	fogStrip2 = { id = "rbxassetid://99854528239110", fallback = "rbxasset://textures/particles/smoke_main.dds" },
	wisps = { id = "rbxassetid://13490928216", fallback = "rbxasset://textures/particles/smoke_main.dds" },
	-- пыль от толчков Рики
	dustBurst = { id = "rbxassetid://16829556885", fallback = "rbxasset://textures/particles/explosion01_smoke_main.dds" },
	dustRing = { id = "rbxassetid://134674538402910", fallback = "rbxasset://textures/particles/explosion01_shockwave_main.dds" },
	-- энергия
	radialGlow = { id = "rbxassetid://6673021984", fallback = "rbxasset://textures/particles/explosion01_implosion_main.dds" },
	sparkStreak = { id = "rbxassetid://11469784323", fallback = "rbxasset://textures/particles/sparkles_main.dds" },
	electricBurst = { id = "rbxassetid://12301752761", fallback = "rbxasset://textures/particles/sparkles_main.dds" },
	starGlint = { id = "rbxassetid://3909691881", fallback = "rbxasset://textures/sparkle.png" },
	flare = { id = "rbxassetid://9222478621", fallback = "rbxasset://textures/glow.png" },
	-- экран
	vignette = { id = "rbxassetid://4576475446", fallback = "rbxasset://textures/loading/loadingvignette.png" },
	grain = { id = "rbxassetid://98159299798452", fallback = "" },
	speedLines = { id = "rbxassetid://105323735180936", fallback = "" },
} :: { [string]: Tex }

-- Встроенные (то, что попадает в место при сборке)
Textures.smoke = "rbxasset://textures/particles/smoke_main.dds"
Textures.smokeDark = "rbxasset://textures/particles/explosion01_smoke_main.dds"
Textures.spark = "rbxasset://textures/particles/sparkles_main.dds"
Textures.glow = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- мягкое круглое свечение
Textures.ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
Textures.embers = "rbxasset://textures/particles/fire_sparks_main.dds"
Textures.fire = "rbxasset://textures/particles/fire_main.dds"
Textures.arc = ""

-- Какие качественные текстуры подставлять в эмиттеры тумана по слою (атрибут Layer у эмиттера)
Textures.fogLayer = {
	bank = "smokePuffs",
	ground = "softFog",
	high = "mist",
	sky = "cumulusPuff",
} :: { [string]: string }

return Textures
