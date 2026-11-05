--!strict
-- STRETCH-POP · Перчатки (открываемые кастомизации рук). Бонус к ударной массе учитывают
-- и клиент (предсказание пробития), и сервер (валидация) через StretchPhysics.Derive.

export type GloveDef = {
	Id: string,
	DisplayName: string,
	Color: Color3,
	Accent: Color3,
	Material: Enum.Material,
	ImpactMassBonus: number, -- множитель: ImpactMass · (1 + bonus)
	Price: number,
}

local Gloves: { [string]: GloveDef } = {
	Rubber = {
		Id = "Rubber",
		DisplayName = "Rubber Classic",
		Color = Color3.fromRGB(255, 72, 88),
		Accent = Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.SmoothPlastic,
		ImpactMassBonus = 0,
		Price = 0,
	},
	Bubblegum = {
		Id = "Bubblegum",
		DisplayName = "Bubblegum Pop",
		Color = Color3.fromRGB(255, 132, 204),
		Accent = Color3.fromRGB(255, 236, 248),
		Material = Enum.Material.SmoothPlastic,
		ImpactMassBonus = 0.03,
		Price = 2500,
	},
	GoldenGrip = {
		Id = "GoldenGrip",
		DisplayName = "Golden Grip",
		Color = Color3.fromRGB(255, 206, 60),
		Accent = Color3.fromRGB(255, 250, 214),
		Material = Enum.Material.Foil,
		ImpactMassBonus = 0.06,
		Price = 15000,
	},
	SlimeMitt = {
		Id = "SlimeMitt",
		DisplayName = "Slime Mitt",
		Color = Color3.fromRGB(90, 255, 150),
		Accent = Color3.fromRGB(220, 255, 230),
		Material = Enum.Material.Glass,
		ImpactMassBonus = 0.1,
		Price = 60000,
	},
	VoidFist = {
		Id = "VoidFist",
		DisplayName = "Void Fist",
		Color = Color3.fromRGB(150, 70, 255),
		Accent = Color3.fromRGB(240, 200, 255),
		Material = Enum.Material.Neon,
		ImpactMassBonus = 0.15,
		Price = 250000,
	},
}

local GloveConfig = {
	DefaultGlove = "Rubber",
	Gloves = Gloves,
}

function GloveConfig.Get(id: string?): GloveDef
	if id ~= nil then
		local glove = Gloves[id]
		if glove then
			return glove
		end
	end
	return Gloves[GloveConfig.DefaultGlove]
end

function GloveConfig.Exists(id: string): boolean
	return Gloves[id] ~= nil
end

return GloveConfig
