--!strict
-- Camera-following ambient weather particles (client VFX). Only built-in particle textures are used
-- (rbxasset://textures/particles/*.dds — present on every platform). Every emitter sets LightInfluence
-- explicitly (Instance.new defaults it to 0).
--
-- How it works: each weather is 1-3 invisible anchored "volume" parts (Box emitters) parented to
-- Workspace.CurrentCamera (local only, CanQuery/CanTouch/CanCollide off). Every frame the volumes are
-- re-centred on the camera (shifted a little along the view so most particles land on screen); particles
-- live in world space, so moving through snow gives real parallax. "Ground" volumes (mist) follow the
-- floor under the camera (raycast 4×/s). Switching weather retires the old emitters (they stop emitting,
-- their particles live out their lifetime) while the new ones start with a pre-filled burst.
--
-- Weather ids: Snow, Blizzard, Embers, Ash, Dust, Fireflies, Spores, VoidMotes, RiftMotes, Glimmer, Rain.
-- Density (1 = authored look on High) = preset Ambient.Density × player setting × quality scale — computed
-- by GraphicsController. Rates are capped at 400/s per emitter (engine limit; 100/s on mobile).
--
-- API:
--   Ambient.Set(weatherId: string?, density: number?, opts: { TimeScale: number? }?)
--       nil / unknown id / density <= 0 -> Stop(). Same id -> rates/time scale updated in place.
--       TimeScale < 1 slows the particle simulation (GraphicsController passes 0.6 for Reduced Motion).
--   Ambient.Stop()
--   Ambient.Current() -> (string?, number)       weather id and density
--   Ambient.Ids() -> {string};  Ambient.Has(id) -> boolean
--   Ambient.Build(weatherId, density?, timeScale?) -> Folder?
--       Pure builder (no services; used by Set and by Lune tests): a Folder of volume parts with configured
--       emitters, positioned relative to the origin.
--   Ambient.TEXTURES -> { [string]: string }    the built-in textures used

local Ambient = {}

local MAX_RATE = 400
local PREFILL_FRACTION = 0.5
local PREFILL_CAP = 500
local TELEPORT_DISTANCE = 80
local GROUND_INTERVAL = 0.25
local GROUND_FALLBACK = 6 -- studs below the camera when no floor is found

local TEXTURES = {
	Glow = "rbxasset://textures/particles/explosion01_implosion_main.dds", -- soft radial glow dot
	Star = "rbxasset://textures/particles/sparkles_main.dds", -- 8-point star
	Smoke = "rbxasset://textures/particles/smoke_main.dds", -- soft grey puff
	DarkSmoke = "rbxasset://textures/particles/explosion01_smoke_main.dds", -- dark puff
}
Ambient.TEXTURES = TEXTURES

type EmitterDef = {
	Name: string,
	Texture: string,
	Rate: number, -- particles/s at density 1
	Lifetime: NumberRange,
	Speed: NumberRange,
	Size: NumberSequence,
	Transparency: NumberSequence,
	Color: ColorSequence,
	LightEmission: number,
	LightInfluence: number,
	Brightness: number,
	Drag: number?,
	Acceleration: Vector3?,
	SpreadAngle: Vector2?,
	Direction: Enum.NormalId?,
	Rotation: NumberRange?,
	RotSpeed: NumberRange?,
	Orientation: Enum.ParticleOrientation?,
	Squash: NumberSequence?,
	Volume: Vector3, -- emitter box size (studs)
	Offset: Vector3, -- box centre relative to the camera (or to the floor when Ground)
	Ground: boolean?,
	Forward: number?, -- studs to shift along the flat view direction (default 20 % of Volume.X)
}

type Volume = { Part: BasePart, Emitter: ParticleEmitter, Def: EmitterDef }

type ActiveWeather = {
	Id: string,
	Density: number,
	TimeScale: number,
	Folder: Folder,
	Volumes: { Volume },
}

------------------------------------------------------------------------------------------- definitions

local function nr(a: number, b: number?): NumberRange
	return NumberRange.new(a, b or a)
end

local function ns(points: { { number } }): NumberSequence
	local keypoints = {}
	for _, p in points do
		table.insert(keypoints, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
	end
	return NumberSequence.new(keypoints)
end

local function cs(points: { { any } }): ColorSequence
	local keypoints = {}
	for _, p in points do
		table.insert(keypoints, ColorSequenceKeypoint.new(p[1] :: number, p[2] :: Color3))
	end
	return ColorSequence.new(keypoints)
end

local function solid(color: Color3): ColorSequence
	return ColorSequence.new(color)
end

local DEFS: { [string]: { EmitterDef } }? = nil
local ORDER =
	{ "Snow", "Blizzard", "Embers", "Ash", "Dust", "Fireflies", "Spores", "VoidMotes", "RiftMotes", "Glimmer", "Rain" }

local function mist(color: Color3, rate: number, transparency: number, lightEmission: number?): EmitterDef
	return {
		Name = "Mist",
		Texture = TEXTURES.Smoke,
		Rate = rate,
		Lifetime = nr(10, 15),
		Speed = nr(0.2, 0.7),
		Size = ns({ { 0, 7, 2 }, { 1, 12, 3 } }),
		Transparency = ns({ { 0, 1 }, { 0.3, transparency }, { 0.7, transparency + 0.02 }, { 1, 1 } }),
		Color = solid(color),
		LightEmission = lightEmission or 0,
		LightInfluence = 0.7,
		Brightness = 1,
		Drag = 0.6,
		SpreadAngle = Vector2.new(80, 80),
		Direction = Enum.NormalId.Top,
		Rotation = nr(0, 360),
		RotSpeed = nr(-6, 6),
		Volume = Vector3.new(110, 2, 110),
		Offset = Vector3.new(0, 1, 0),
		Ground = true,
		Forward = 30,
	}
end

local function ceilingStars(color: Color3, rate: number): EmitterDef
	return {
		Name = "CeilingStars",
		Texture = TEXTURES.Star,
		Rate = rate,
		Lifetime = nr(2, 4),
		Speed = nr(0),
		Size = ns({ { 0, 0 }, { 0.5, 0.45, 0.2 }, { 1, 0 } }),
		Transparency = ns({ { 0, 0.15 }, { 1, 0.15 } }),
		Color = solid(color),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 3,
		Rotation = nr(0, 360),
		Direction = Enum.NormalId.Top,
		Volume = Vector3.new(140, 10, 140),
		Offset = Vector3.new(0, 34, 0),
	}
end

local function voidSet(moteColor: Color3, starA: Color3, starB: Color3, wispColor: Color3): { EmitterDef }
	return {
		{
			Name = "Motes",
			Texture = TEXTURES.Glow,
			Rate = 45,
			Lifetime = nr(6, 10),
			Speed = nr(0.3, 1),
			Size = ns({ { 0, 0.3, 0.15 }, { 1, 0.3, 0.15 } }),
			Transparency = ns({ { 0, 1 }, { 0.2, 0.35 }, { 0.8, 0.4 }, { 1, 1 } }),
			Color = solid(moteColor),
			LightEmission = 0,
			LightInfluence = 0,
			Brightness = 1,
			Drag = 0.8,
			Acceleration = Vector3.new(0, 0.25, 0),
			SpreadAngle = Vector2.new(60, 60),
			Direction = Enum.NormalId.Top,
			Volume = Vector3.new(80, 28, 80),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Stars",
			Texture = TEXTURES.Star,
			Rate = 6,
			Lifetime = nr(2.5, 4.5),
			Speed = nr(0.05, 0.2),
			Size = ns({ { 0, 0 }, { 0.5, 0.5, 0.25 }, { 1, 0 } }),
			Transparency = ns({ { 0, 0 }, { 1, 0 } }),
			Color = cs({ { 0, starA }, { 1, starB } }),
			LightEmission = 1,
			LightInfluence = 0,
			Brightness = 5,
			Rotation = nr(0, 360),
			RotSpeed = nr(-20, 20),
			SpreadAngle = Vector2.new(180, 180),
			Direction = Enum.NormalId.Top,
			Volume = Vector3.new(90, 34, 90),
			Offset = Vector3.new(0, 6, 0),
		},
		{
			Name = "Wisps",
			Texture = TEXTURES.DarkSmoke,
			Rate = 3,
			Lifetime = nr(8, 12),
			Speed = nr(0.2, 0.5),
			Size = ns({ { 0, 8, 2 }, { 1, 13, 3 } }),
			Transparency = ns({ { 0, 1 }, { 0.3, 0.82 }, { 0.7, 0.85 }, { 1, 1 } }),
			Color = solid(wispColor),
			LightEmission = 0,
			LightInfluence = 0.3,
			Brightness = 1,
			Drag = 0.6,
			Rotation = nr(0, 360),
			RotSpeed = nr(-8, 8),
			SpreadAngle = Vector2.new(60, 60),
			Direction = Enum.NormalId.Top,
			Volume = Vector3.new(100, 3, 100),
			Offset = Vector3.new(0, 1.5, 0),
			Ground = true,
			Forward = 30,
		},
	}
end

local function buildDefs(): { [string]: { EmitterDef } }
	local rgb = Color3.fromRGB
	local v3 = Vector3.new
	local v2 = Vector2.new
	local Top, Bottom = Enum.NormalId.Top, Enum.NormalId.Bottom

	return {
		Snow = {
			{
				Name = "Flakes",
				Texture = TEXTURES.Glow,
				Rate = 160,
				Lifetime = nr(7, 10),
				Speed = nr(2.5, 4.5),
				Size = ns({ { 0, 0.24, 0.1 }, { 1, 0.24, 0.1 } }),
				Transparency = ns({ { 0, 1 }, { 0.1, 0.15 }, { 0.85, 0.2 }, { 1, 1 } }),
				Color = solid(rgb(240, 246, 255)),
				LightEmission = 0.2,
				LightInfluence = 0.55,
				Brightness = 1.4,
				Drag = 0.35,
				Acceleration = v3(0, -0.6, 0),
				SpreadAngle = v2(25, 25),
				Direction = Bottom,
				Volume = v3(120, 50, 120),
				Offset = v3(0, 14, 0),
			},
			{
				Name = "Glints",
				Texture = TEXTURES.Star,
				Rate = 6,
				Lifetime = nr(1.5, 3),
				Speed = nr(1, 2),
				Size = ns({ { 0, 0 }, { 0.5, 0.35, 0.15 }, { 1, 0 } }),
				Transparency = ns({ { 0, 0.2 }, { 1, 0.6 } }),
				Color = solid(rgb(220, 235, 255)),
				LightEmission = 1,
				LightInfluence = 0,
				Brightness = 2.5,
				Drag = 0.3,
				SpreadAngle = v2(25, 25),
				Direction = Bottom,
				Rotation = nr(0, 360),
				RotSpeed = nr(-30, 30),
				Volume = v3(60, 30, 60),
				Offset = v3(0, 6, 0),
			},
			mist(rgb(190, 205, 235), 3, 0.88),
		},
		Blizzard = {
			{
				Name = "Flakes",
				Texture = TEXTURES.Glow,
				Rate = 320,
				Lifetime = nr(3, 5),
				Speed = nr(6, 10),
				Size = ns({ { 0, 0.2, 0.08 }, { 1, 0.2, 0.08 } }),
				Squash = ns({ { 0, -1 }, { 1, -1 } }), -- VelocityParallel: negative squash = streak along travel
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				Transparency = ns({ { 0, 1 }, { 0.1, 0.25 }, { 0.8, 0.3 }, { 1, 1 } }),
				Color = solid(rgb(235, 242, 255)),
				LightEmission = 0.15,
				LightInfluence = 0.6,
				Brightness = 1.3,
				Drag = 0.25,
				Acceleration = v3(0, -2, 0),
				SpreadAngle = v2(30, 30),
				Direction = Bottom,
				Volume = v3(100, 45, 100),
				Offset = v3(0, 12, 0),
			},
			{
				Name = "Gusts",
				Texture = TEXTURES.Smoke,
				Rate = 8,
				Lifetime = nr(2, 3.5),
				Speed = nr(2, 4),
				Size = ns({ { 0, 8, 3 }, { 1, 16, 4 } }),
				Transparency = ns({ { 0, 1 }, { 0.3, 0.86 }, { 0.7, 0.9 }, { 1, 1 } }),
				Color = solid(rgb(215, 228, 255)),
				LightEmission = 0,
				LightInfluence = 0.7,
				Brightness = 1,
				Drag = 0.3,
				SpreadAngle = v2(60, 60),
				Direction = Top,
				Rotation = nr(0, 360),
				RotSpeed = nr(-25, 25),
				Volume = v3(90, 20, 90),
				Offset = v3(0, 4, 0),
			},
			mist(rgb(185, 200, 235), 4, 0.85),
		},
		Embers = {
			{
				Name = "Embers",
				Texture = TEXTURES.Glow,
				Rate = 70,
				Lifetime = nr(3.5, 6),
				Speed = nr(1.5, 4),
				Size = ns({ { 0, 0.16, 0.06 }, { 0.7, 0.12, 0.05 }, { 1, 0 } }),
				Transparency = ns({ { 0, 1 }, { 0.08, 0 }, { 0.75, 0.2 }, { 1, 1 } }),
				Color = cs({ { 0, rgb(255, 236, 160) }, { 0.35, rgb(255, 150, 50) }, { 1, rgb(230, 50, 20) } }),
				LightEmission = 1,
				LightInfluence = 0,
				Brightness = 4,
				Drag = 0.6,
				Acceleration = v3(0, 1.2, 0),
				SpreadAngle = v2(35, 35),
				Direction = Top,
				Volume = v3(90, 30, 90),
				Offset = v3(0, -4, 0),
			},
			{
				Name = "Sparks",
				Texture = TEXTURES.Star,
				Rate = 10,
				Lifetime = nr(0.5, 1.2),
				Speed = nr(3, 7),
				Size = ns({ { 0, 0.35, 0.15 }, { 1, 0 } }),
				Transparency = ns({ { 0, 0 }, { 1, 1 } }),
				Color = cs({ { 0, rgb(255, 200, 110) }, { 1, rgb(255, 110, 40) } }),
				LightEmission = 1,
				LightInfluence = 0,
				Brightness = 5,
				Drag = 0.8,
				Rotation = nr(0, 360),
				RotSpeed = nr(-200, 200),
				SpreadAngle = v2(60, 60),
				Direction = Top,
				Volume = v3(60, 20, 60),
				Offset = v3(0, -6, 0),
			},
			{
				Name = "Heat",
				Texture = TEXTURES.Smoke,
				Rate = 4,
				Lifetime = nr(5, 8),
				Speed = nr(1, 2),
				Size = ns({ { 0, 8, 2 }, { 1, 14, 3 } }),
				Transparency = ns({ { 0, 1 }, { 0.3, 0.9 }, { 0.7, 0.92 }, { 1, 1 } }),
				Color = solid(rgb(120, 60, 40)),
				LightEmission = 0,
				LightInfluence = 0.6,
				Brightness = 1,
				Drag = 0.5,
				SpreadAngle = v2(20, 20),
				Direction = Top,
				Rotation = nr(0, 360),
				RotSpeed = nr(-8, 8),
				Volume = v3(100, 3, 100),
				Offset = v3(0, 1, 0),
				Ground = true,
				Forward = 30,
			},
		},
		Ash = {
			{
				Name = "Ash",
				Texture = TEXTURES.Glow,
				Rate = 110,
				Lifetime = nr(6, 9),
				Speed = nr(1, 2.5),
				Size = ns({ { 0, 0.2, 0.08 }, { 1, 0.18, 0.08 } }),
				Squash = ns({ { 0, 0, 0.6 }, { 1, 0, 0.6 } }), -- irregular flakes
				Rotation = nr(0, 360),
				RotSpeed = nr(-90, 90),
				Transparency = ns({ { 0, 1 }, { 0.1, 0.25 }, { 0.85, 0.35 }, { 1, 1 } }),
				Color = cs({ { 0, rgb(90, 86, 84) }, { 1, rgb(60, 56, 56) } }),
				LightEmission = 0,
				LightInfluence = 0.85,
				Brightness = 1,
				Drag = 0.6,
				Acceleration = v3(0, -0.3, 0),
				SpreadAngle = v2(35, 35),
				Direction = Bottom,
				Volume = v3(110, 45, 110),
				Offset = v3(0, 12, 0),
			},
			{
				Name = "Cinders",
				Texture = TEXTURES.Glow,
				Rate = 14,
				Lifetime = nr(4, 7),
				Speed = nr(1, 2),
				Size = ns({ { 0, 0.12, 0.04 }, { 1, 0.05 } }),
				Transparency = ns({ { 0, 1 }, { 0.1, 0 }, { 0.8, 0.3 }, { 1, 1 } }),
				Color = cs({ { 0, rgb(255, 120, 60) }, { 1, rgb(200, 30, 20) } }),
				LightEmission = 1,
				LightInfluence = 0,
				Brightness = 4,
				Drag = 0.5,
				SpreadAngle = v2(40, 40),
				Direction = Bottom,
				Volume = v3(80, 35, 80),
				Offset = v3(0, 10, 0),
			},
		},
		Dust = {
			{
				Name = "Motes",
				Texture = TEXTURES.Glow,
				Rate = 45,
				Lifetime = nr(8, 14),
				Speed = nr(0.08, 0.4),
				Size = ns({ { 0, 0.07, 0.03 }, { 1, 0.07, 0.03 } }),
				Transparency = ns({ { 0, 1 }, { 0.2, 0.35 }, { 0.5, 0.15 }, { 0.8, 0.4 }, { 1, 1 } }),
				Color = solid(rgb(255, 232, 190)),
				LightEmission = 0.8,
				LightInfluence = 0.75, -- additive + lit: motes shine in sun shafts, vanish in shade
				Brightness = 2.4,
				Drag = 1.2,
				Acceleration = v3(0, 0.03, 0),
				SpreadAngle = v2(180, 180),
				Direction = Top,
				Volume = v3(70, 26, 70),
				Offset = v3(0, 3, 0),
			},
			{
				Name = "Glints",
				Texture = TEXTURES.Star,
				Rate = 5,
				Lifetime = nr(1.2, 2.4),
				Speed = nr(0.1, 0.3),
				Size = ns({ { 0, 0 }, { 0.5, 0.22, 0.08 }, { 1, 0 } }),
				Transparency = ns({ { 0, 0.3 }, { 1, 0.6 } }),
				Color = solid(rgb(255, 240, 205)),
				LightEmission = 1,
				LightInfluence = 0.5,
				Brightness = 2.5,
				Drag = 1,
				Rotation = nr(0, 360),
				SpreadAngle = v2(180, 180),
				Direction = Top,
				Volume = v3(50, 20, 50),
				Offset = v3(0, 3, 0),
			},
		},
		Fireflies = {
			{
				Name = "Fireflies",
				Texture = TEXTURES.Glow,
				Rate = 26,
				Lifetime = nr(6, 10),
				Speed = nr(0.3, 1.1),
				Size = ns({ { 0, 0.22, 0.08 }, { 1, 0.22, 0.08 } }),
				-- blink: on, dim, on, dim, on
				Transparency = ns({
					{ 0, 1 },
					{ 0.12, 0.05 },
					{ 0.3, 0.7 },
					{ 0.45, 0.1 },
					{ 0.65, 0.75 },
					{ 0.8, 0.15 },
					{ 1, 1 },
				}),
				Color = cs({ { 0, rgb(120, 255, 235) }, { 1, rgb(60, 200, 255) } }),
				LightEmission = 1,
				LightInfluence = 0,
				Brightness = 3.5,
				Drag = 0.8,
				Acceleration = v3(0, 0.12, 0),
				SpreadAngle = v2(180, 180),
				Direction = Top,
				Volume = v3(70, 22, 70),
				Offset = v3(0, 2, 0),
			},
			ceilingStars(rgb(180, 240, 255), 14),
			mist(rgb(70, 160, 180), 4, 0.86, 0.15),
		},
		Spores = {
			{
				Name = "Spores",
				Texture = TEXTURES.Glow,
				Rate = 60,
				Lifetime = nr(6, 10),
				Speed = nr(0.3, 0.9),
				Size = ns({ { 0, 0.12, 0.05 }, { 1, 0.1, 0.05 } }),
				Transparency = ns({ { 0, 1 }, { 0.15, 0.1 }, { 0.85, 0.2 }, { 1, 1 } }),
				Color = cs({ { 0, rgb(110, 240, 255) }, { 0.5, rgb(190, 120, 255) }, { 1, rgb(255, 120, 220) } }),
				LightEmission = 1,
				LightInfluence = 0,
				Brightness = 3,
				Drag = 0.7,
				Acceleration = v3(0, 0.35, 0),
				SpreadAngle = v2(40, 40),
				Direction = Top,
				Volume = v3(80, 20, 80),
				Offset = v3(0, -3, 0),
			},
			ceilingStars(rgb(220, 180, 255), 16),
			mist(rgb(90, 60, 150), 4, 0.86, 0.15),
		},
		VoidMotes = voidSet(rgb(8, 10, 22), rgb(200, 225, 255), rgb(150, 170, 255), rgb(30, 20, 60)),
		RiftMotes = voidSet(rgb(26, 4, 10), rgb(255, 150, 170), rgb(255, 80, 110), rgb(70, 10, 30)),
		Glimmer = {
			{
				Name = "Glimmer",
				Texture = TEXTURES.Star,
				Rate = 16,
				Lifetime = nr(2, 4),
				Speed = nr(0.2, 0.6),
				Size = ns({ { 0, 0 }, { 0.5, 0.35, 0.15 }, { 1, 0 } }),
				Transparency = ns({ { 0, 0.1 }, { 1, 0.3 } }),
				Color = cs({ { 0, rgb(255, 200, 235) }, { 0.5, rgb(220, 200, 255) }, { 1, rgb(190, 230, 255) } }),
				LightEmission = 1,
				LightInfluence = 0,
				Brightness = 2.2,
				Drag = 0.8,
				Rotation = nr(0, 360),
				RotSpeed = nr(-40, 40),
				SpreadAngle = v2(180, 180),
				Direction = Top,
				Volume = v3(70, 24, 70),
				Offset = v3(0, 4, 0),
			},
			{
				Name = "Motes",
				Texture = TEXTURES.Glow,
				Rate = 30,
				Lifetime = nr(7, 11),
				Speed = nr(0.1, 0.4),
				Size = ns({ { 0, 0.12, 0.05 }, { 1, 0.12, 0.05 } }),
				Transparency = ns({ { 0, 1 }, { 0.25, 0.3 }, { 0.75, 0.35 }, { 1, 1 } }),
				Color = cs({ { 0, rgb(255, 225, 245) }, { 1, rgb(215, 225, 255) } }),
				LightEmission = 0.8,
				LightInfluence = 0.3,
				Brightness = 2,
				Drag = 1,
				Acceleration = v3(0, 0.05, 0),
				SpreadAngle = v2(180, 180),
				Direction = Top,
				Volume = v3(70, 24, 70),
				Offset = v3(0, 3, 0),
			},
			mist(rgb(255, 215, 235), 3, 0.9),
		},
		Rain = {
			{
				Name = "Drops",
				Texture = TEXTURES.Glow,
				Rate = 260,
				Lifetime = nr(0.8, 1.2),
				Speed = nr(50, 60),
				Size = ns({ { 0, 0.35 }, { 1, 0.35 } }),
				Squash = ns({ { 0, -2.5 }, { 1, -2.5 } }),
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				Transparency = ns({ { 0, 0.55 }, { 1, 0.6 } }),
				Color = solid(rgb(170, 185, 205)),
				LightEmission = 0.1,
				LightInfluence = 0.8,
				Brightness = 1.2,
				Acceleration = v3(0, -20, 0),
				SpreadAngle = v2(4, 4),
				Direction = Bottom,
				Volume = v3(70, 6, 70),
				Offset = v3(0, 32, 0),
			},
			mist(rgb(170, 180, 195), 3, 0.9),
		},
	}
end

local function defs(): { [string]: { EmitterDef } }
	local current = DEFS
	if current == nil then
		current = buildDefs()
		DEFS = current
	end
	return current
end

function Ambient.Ids(): { string }
	return table.clone(ORDER)
end

function Ambient.Has(id: string?): boolean
	return id ~= nil and defs()[id] ~= nil
end

----------------------------------------------------------------------------------------------- builder

local function rateFor(def: EmitterDef, density: number): number
	local rate = def.Rate * math.max(density, 0)
	if rate < 0.05 then
		return 0
	end
	return math.min(rate, MAX_RATE)
end

local function buildEmitter(def: EmitterDef, density: number, timeScale: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = def.Name
	emitter.Texture = def.Texture
	emitter.Rate = rateFor(def, density)
	emitter.Lifetime = def.Lifetime
	emitter.Speed = def.Speed
	emitter.Size = def.Size
	emitter.Transparency = def.Transparency
	emitter.Color = def.Color
	emitter.LightEmission = def.LightEmission
	emitter.LightInfluence = def.LightInfluence
	emitter.Brightness = def.Brightness
	emitter.Drag = def.Drag or 0
	emitter.WindAffectsDrag = (def.Drag or 0) > 0
	emitter.Acceleration = def.Acceleration or Vector3.new(0, 0, 0)
	emitter.SpreadAngle = def.SpreadAngle or Vector2.new(0, 0)
	emitter.EmissionDirection = def.Direction or Enum.NormalId.Top
	emitter.Rotation = def.Rotation or NumberRange.new(0, 0)
	emitter.RotSpeed = def.RotSpeed or NumberRange.new(0, 0)
	emitter.Orientation = def.Orientation or Enum.ParticleOrientation.FacingCamera
	if def.Squash then
		emitter.Squash = def.Squash
	end
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.LockedToPart = false
	emitter.VelocityInheritance = 0
	emitter.TimeScale = math.clamp(timeScale, 0, 1)
	emitter.ZOffset = 0
	return emitter
end

local function buildVolumes(id: string, list: { EmitterDef }, density: number, timeScale: number): (Folder, { Volume })
	local folder = Instance.new("Folder")
	folder.Name = "SV_Ambient_" .. id
	local volumes: { Volume } = {}
	for _, def in list do
		local part = Instance.new("Part")
		part.Name = "Volume_" .. def.Name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = def.Volume
		part.CFrame = CFrame.new(def.Offset)
		local emitter = buildEmitter(def, density, timeScale)
		emitter.Parent = part
		part.Parent = folder
		table.insert(volumes, { Part = part, Emitter = emitter, Def = def })
	end
	return folder, volumes
end

function Ambient.Build(weatherId: string, density: number?, timeScale: number?): Folder?
	local list = defs()[weatherId]
	if list == nil then
		return nil
	end
	local folder = buildVolumes(weatherId, list, density or 1, timeScale or 1)
	return folder
end

----------------------------------------------------------------------------------------------- runtime

local active: ActiveWeather? = nil
local followConnection: RBXScriptConnection? = nil
local lastCameraPos: Vector3? = nil
local groundY: number? = nil
local groundTimer = 0
local raycastParams: RaycastParams? = nil

local function camera(): Camera?
	return workspace.CurrentCamera
end

local function maxLifetime(weather: ActiveWeather): number
	local longest = 0
	for _, volume in weather.Volumes do
		longest = math.max(longest, volume.Def.Lifetime.Max)
	end
	return longest
end

local function retire(weather: ActiveWeather)
	for _, volume in weather.Volumes do
		volume.Emitter.Enabled = false
	end
	local folder = weather.Folder
	task.delay(maxLifetime(weather) + 0.5, function()
		folder:Destroy()
	end)
end

local function updateGround(position: Vector3)
	local params = raycastParams
	if params == nil then
		local created = RaycastParams.new()
		created.FilterType = Enum.RaycastFilterType.Exclude
		created.IgnoreWater = false
		raycastParams = created
		params = created
	end
	local exclude: { Instance } = {}
	local cam = camera()
	if cam then
		table.insert(exclude, cam)
	end
	local player = game:GetService("Players").LocalPlayer
	if player and player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(position, Vector3.new(0, -250, 0), params)
	groundY = if result then result.Position.Y else position.Y - GROUND_FALLBACK
end

local function placeVolumes(weather: ActiveWeather, cframe: CFrame)
	local position = cframe.Position
	local look = cframe.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 1e-3 then
		flat = flat.Unit
	else
		flat = Vector3.new(0, 0, 0)
	end
	local floor = groundY or (position.Y - GROUND_FALLBACK)
	for _, volume in weather.Volumes do
		local def = volume.Def
		local forward = def.Forward or def.Volume.X * 0.2
		local center = position + flat * forward + Vector3.new(def.Offset.X, 0, def.Offset.Z)
		local y = if def.Ground then floor + def.Offset.Y else position.Y + def.Offset.Y
		volume.Part.CFrame = CFrame.new(center.X, y, center.Z)
	end
end

local function prefill(weather: ActiveWeather)
	for _, volume in weather.Volumes do
		local emitter = volume.Emitter
		local lifetime = (volume.Def.Lifetime.Min + volume.Def.Lifetime.Max) / 2
		local count = math.floor(math.min(emitter.Rate * lifetime * PREFILL_FRACTION, PREFILL_CAP))
		if count > 0 then
			pcall(function() -- never let a cosmetic burst break weather switching
				emitter:Emit(count)
			end)
		end
	end
end

local function stopFollowing()
	if followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end
end

local function onFrame(dt: number)
	local weather = active
	local cam = camera()
	if weather == nil or cam == nil then
		return
	end
	if weather.Folder.Parent ~= cam then
		weather.Folder.Parent = cam
	end
	local cframe = cam.CFrame
	local position = cframe.Position
	groundTimer -= dt
	local jumped = lastCameraPos ~= nil and (position - (lastCameraPos :: Vector3)).Magnitude > TELEPORT_DISTANCE
	if groundTimer <= 0 or jumped then
		groundTimer = GROUND_INTERVAL
		updateGround(position)
	end
	placeVolumes(weather, cframe)
	if jumped then
		prefill(weather)
	end
	lastCameraPos = position
end

local function startFollowing()
	if followConnection == nil then
		followConnection = game:GetService("RunService").PreRender:Connect(onFrame)
	end
end

function Ambient.Stop()
	local weather = active
	active = nil
	stopFollowing()
	if weather then
		retire(weather)
	end
end

function Ambient.Set(weatherId: string?, density: number?, opts: { TimeScale: number? }?)
	local amount = density or 1
	local timeScale = math.clamp(if opts and opts.TimeScale then opts.TimeScale else 1, 0, 1)
	if weatherId == nil or weatherId == "" or amount <= 0.001 or not Ambient.Has(weatherId) then
		Ambient.Stop()
		return
	end
	local id = weatherId :: string
	local current = active
	if current and current.Id == id then
		if math.abs(current.Density - amount) > 1e-3 or math.abs(current.TimeScale - timeScale) > 1e-3 then
			current.Density = amount
			current.TimeScale = timeScale
			for _, volume in current.Volumes do
				volume.Emitter.Rate = rateFor(volume.Def, amount)
				volume.Emitter.TimeScale = timeScale
			end
		end
		return
	end
	if current then
		retire(current)
		active = nil
	end
	local folder, volumes = buildVolumes(id, defs()[id], amount, timeScale)
	local weather: ActiveWeather =
		{ Id = id, Density = amount, TimeScale = timeScale, Folder = folder, Volumes = volumes }
	active = weather
	local cam = camera()
	if cam then
		updateGround(cam.CFrame.Position)
		placeVolumes(weather, cam.CFrame)
		lastCameraPos = cam.CFrame.Position
		folder.Parent = cam
		prefill(weather)
	end
	startFollowing()
end

function Ambient.Current(): (string?, number)
	local weather = active
	if weather then
		return weather.Id, weather.Density
	end
	return nil, 0
end

return Ambient
