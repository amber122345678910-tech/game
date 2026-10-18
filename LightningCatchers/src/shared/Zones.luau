--!strict
-- Геометрия мира: где хаб, острова, мосты, точки появления, подстанции.
-- Этим же модулем пользуется генератор карты (tools/gen_map.luau), поэтому карта и логика всегда совпадают.

local Config = require(script.Parent.Config)

export type ZoneGeo = {
	Index: number,
	Center: Vector3, -- центр поверхности острова
	Dir: Vector3, -- от хаба к острову (горизонтальный единичный)
	ToHub: Vector3,
	Right: Vector3, -- вправо, если смотреть с острова на хаб
	Entrance: Vector3, -- край острова, где начинается мост
	Spawn: Vector3, -- точка появления (над землёй)
	SellPad: Vector3, -- подстанция (на земле)
	Landmark: Vector3, -- ориентир острова (на дальнем краю, вне игровой зоны)
	BridgeStart: Vector3, -- край хаба
	BridgeEnd: Vector3,
	Gate: Vector3, -- барьер на мосту
}

local Zones = {}

Zones.HubCenter = Vector3.new(0, Config.Hub.GroundY, 0)
Zones.SellPadRadius = 6
Zones.SellExclusion = 13 -- кольца не появляются ближе к подстанции
Zones.HubSellRadius = 17 -- кольцо подстанции вокруг Тесла-башни

local function dirOf(angleDeg: number): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

local geos: { ZoneGeo } = {}
for i, z in Config.Zones do
	local dir = dirOf(z.Angle)
	local toHub = -dir
	local right = Vector3.new(-toHub.Z, 0, toHub.X)
	local center = dir * z.Distance + Vector3.new(0, z.GroundY, 0)
	local entrance = center + toHub * z.Radius
	local bridgeStart = dir * Config.Hub.Radius + Vector3.new(0, Config.Hub.GroundY, 0)
	geos[i] = {
		Index = i,
		Center = center,
		Dir = dir,
		ToHub = toHub,
		Right = right,
		Entrance = entrance,
		Spawn = center + toHub * (z.Radius - 20) + Vector3.new(0, 3, 0),
		SellPad = center + toHub * (z.Radius - 28) + right * 17,
		Landmark = center + dir * (z.PlayRadius + 8),
		BridgeStart = bridgeStart,
		BridgeEnd = entrance,
		Gate = bridgeStart:Lerp(entrance, 0.78),
	}
end
Zones.Geo = geos

-- Точки хаба (между мостами)
local function hubPoint(angleDeg: number, dist: number): Vector3
	return dirOf(angleDeg) * dist + Vector3.new(0, Config.Hub.GroundY, 0)
end

Zones.Hub = {
	Spawn = hubPoint(180, 32) + Vector3.new(0, 3, 0),
	Tower = Zones.HubCenter,
	Shop = hubPoint(36, 60),
	Hatchery = hubPoint(108, 60),
	Gallery = hubPoint(180, 64),
	Rebirth = hubPoint(252, 60),
	Daily = hubPoint(324, 60),
	BoardLeaders = hubPoint(160, 82),
	BoardForecast = hubPoint(200, 82),
}

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
Zones.flatDist = flatDist

-- Где находится точка: 0 = хаб, 1..5 = остров, nil = мост или пустота
function Zones.zoneAt(pos: Vector3): number?
	if flatDist(pos, Zones.HubCenter) <= Config.Hub.Radius + 4 then
		return 0
	end
	for i, g in geos do
		if flatDist(pos, g.Center) <= Config.Zones[i].Radius + 4 then
			return i
		end
	end
	return nil
end

-- Можно ли поставить сюда кольцо радиуса r
function Zones.inPlayArea(zone: number, pos: Vector3, r: number?): boolean
	local g = geos[zone]
	local z = Config.Zones[zone]
	local rr = r or Config.Catch.RingRadius
	if flatDist(pos, g.Center) > z.PlayRadius - rr then
		return false
	end
	if flatDist(pos, g.SellPad) < Zones.SellExclusion + rr then
		return false
	end
	return true
end

-- Точка на земле острова (Y = поверхность)
function Zones.groundPoint(zone: number, x: number, zz: number): Vector3
	return Vector3.new(x, Config.Zones[zone].GroundY, zz)
end

-- Кандидат для кольца: в кольце [minD, maxD] вокруг точки around. u1, u2 — случайные [0,1).
function Zones.candidate(zone: number, around: Vector3, minD: number, maxD: number, u1: number, u2: number): Vector3
	local a = u1 * math.pi * 2
	local d = minD + (maxD - minD) * math.sqrt(u2)
	return Zones.groundPoint(zone, around.X + math.cos(a) * d, around.Z + math.sin(a) * d)
end

-- Ближайшая точка игровой зоны (для бегущих колец и босса)
function Zones.clampToPlay(zone: number, pos: Vector3, margin: number?): Vector3
	local g = geos[zone]
	local limit = Config.Zones[zone].PlayRadius - (margin or Config.Catch.RingRadius)
	local off = Vector3.new(pos.X - g.Center.X, 0, pos.Z - g.Center.Z)
	if off.Magnitude > limit then
		off = off.Unit * limit
	end
	return Vector3.new(g.Center.X + off.X, Config.Zones[zone].GroundY, g.Center.Z + off.Z)
end

function Zones.groundY(zone: number): number
	if zone == 0 then
		return Config.Hub.GroundY
	end
	return Config.Zones[zone].GroundY
end

function Zones.spawnFor(zone: number): Vector3
	if zone == 0 then
		return Zones.Hub.Spawn
	end
	return geos[zone].Spawn
end

return Zones
