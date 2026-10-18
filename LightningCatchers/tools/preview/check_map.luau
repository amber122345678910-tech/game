--!nocheck
-- Проверка карты src/map/Map.rbxmx на соответствие логике игры.
-- Запуск из LightningCatchers/: .tools/lune run tools/preview/check_map.luau
--  * все метки на месте (Markers), табло с Gui/Content, барьеры с атрибутом Zone, окна с OnColor;
--  * внутри PlayRadius нет деталей с коллизией (кроме земли, подстанции и стен);
--  * мелкий декор в игровой зоне не выше GroundY + 0.06 (кроме цветов/травинок без коллизий);
--  * невидимые стены не перекрывают мосты; точки появления внутри острова;
--  * декор без CanTouch/CanQuery; бюджет деталей и источников света.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("../lib/loader")
local Vector3 = roblox.Vector3

local Config = Loader.load("src/shared/Config")
local Zones = Loader.load("src/shared/Zones")

local file = process.args[1] or "src/map/Map.rbxmx"
local map = roblox.deserializeModel(fs.readFile(file))[1]
local problems = {}
local function fail(msg)
	table.insert(problems, msg)
end

local function flatDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function corners(p)
	local cf, s = p.CFrame, p.Size / 2
	local out = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(out, cf:PointToWorldSpace(Vector3.new(s.X * x, s.Y * y, s.Z * z)))
			end
		end
	end
	table.insert(out, cf.Position)
	return out
end

local function contains(p, point)
	local l = p.CFrame:PointToObjectSpace(point)
	local s = p.Size / 2
	return math.abs(l.X) <= s.X and math.abs(l.Y) <= s.Y and math.abs(l.Z) <= s.Z
end

-- 1. Метки
local markers = map:FindFirstChild("Markers")
local need = { "SellPad_0", "Tower_Top", "Board_Leaders", "Board_Forecast", "Board_Hall", "Cocoon_meadow", "Cocoon_ice", "Cocoon_storm" }
for i = 0, 5 do
	table.insert(need, "Spawn_" .. i)
	if i >= 1 then
		table.insert(need, "SellPad_" .. i)
	end
	if i >= 2 then
		table.insert(need, "Gate_" .. i)
	end
end
for _, k in { "Shop", "Hatchery", "Gallery", "Rebirth", "Daily" } do
	table.insert(need, "Kiosk_" .. k)
end
for i = 1, 12 do
	table.insert(need, "Pedestal_" .. i)
end
for i = 1, 4 do
	table.insert(need, "Tower_Coil_" .. i)
end
for _, n in need do
	local m = markers and markers:FindFirstChild(n)
	if not m then
		fail("нет метки " .. n)
	elseif m.Transparency < 1 or m.CanCollide or m.CanQuery or m.CanTouch then
		fail("метка " .. n .. " должна быть невидимой и без коллизий/запросов/касаний")
	end
end
for _, b in { "Board_Leaders", "Board_Forecast", "Board_Hall" } do
	local m = markers and markers:FindFirstChild(b)
	local gui = m and m:FindFirstChild("Gui")
	if not (gui and gui:IsA("SurfaceGui") and gui:FindFirstChild("Content")) then
		fail(b .. ": нет SurfaceGui Gui/Content")
	end
end
-- точки появления и подстанции совпадают с Zones
for i = 0, 5 do
	local m = markers and markers:FindFirstChild("Spawn_" .. i)
	if m and (m.CFrame.Position - Zones.spawnFor(i)).Magnitude > 0.01 then
		fail("Spawn_" .. i .. " не совпадает с Zones.spawnFor")
	end
end

-- 2. Барьеры
local gates = map:FindFirstChild("Gates")
for i = 2, 5 do
	local gte = gates and gates:FindFirstChild("Gate_" .. i)
	if not gte then
		fail("нет Map.Gates.Gate_" .. i)
	elseif gte:GetAttribute("Zone") ~= i or gte.Material ~= roblox.Enum.Material.ForceField or gte.CanCollide then
		fail("Gate_" .. i .. ": нужен атрибут Zone, ForceField и CanCollide=false")
	end
end

-- 3. Окна кварталов
local city = map:FindFirstChild("City")
local windows = 0
for k = 1, Config.City.Districts do
	local d = city and city:FindFirstChild("District_" .. k)
	if not d then
		fail("нет City.District_" .. k)
	else
		for _, w in d:GetDescendants() do
			if w:IsA("BasePart") then
				windows += 1
				if typeof(w:GetAttribute("OnColor")) ~= "Color3" then
					fail("окно без OnColor в District_" .. k)
				end
			end
		end
	end
end

-- 4. Тучи
local clouds = map:FindFirstChild("Clouds")
for i = 1, 5 do
	if not (clouds and clouds:FindFirstChild("Clouds_" .. i)) then
		fail("нет Clouds_" .. i)
	end
end

-- 5. Игровые зоны: без коллизий внутри PlayRadius
local allowed = { Top = true, Wall = true, Pad = true }
local parts = {}
local lights = 0
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(parts, d)
	elseif d:IsA("PointLight") then
		lights += 1
	end
end
local walls = {}
for _, p in parts do
	if p.Name == "Wall" then
		table.insert(walls, p)
	end
	if p.CanTouch then
		fail("CanTouch=true: " .. p:GetFullName())
	end
	if not p.CanCollide and p.CanQuery and p.Transparency < 1 then
		fail("декор с CanQuery: " .. p:GetFullName())
	end
end
for i, z in Config.Zones do
	local g = Zones.Geo[i]
	local bad = 0
	for _, p in parts do
		local isBall = p:IsA("Part") and p.Shape == roblox.Enum.PartType.Ball
		local isVCyl = p:IsA("Part") and p.Shape == roblox.Enum.PartType.Cylinder and math.abs(p.CFrame.RightVector.Y) > 0.999
		if p.CanCollide and isVCyl and not allowed[p.Name] and not p:IsDescendantOf(map.Stations) then
			-- вертикальный цилиндр: точная проверка по радиусу
			local c = p.CFrame.Position
			local top = c.Y + p.Size.X / 2
			if top > z.GroundY + 0.05 and c.Y - p.Size.X / 2 < z.GroundY + 40 and flatDist(c, g.Center) - p.Size.Y / 2 < z.PlayRadius then
				bad += 1
				fail(string.format("остров %d: цилиндр с коллизией в игровой зоне: %s", i, p:GetFullName()))
			end
		elseif p.CanCollide and isBall and not allowed[p.Name] then
			-- шар: точная проверка «шапки» над землёй
			local c = p.CFrame.Position
			local s = math.min(p.Size.X, p.Size.Y, p.Size.Z) / 2
			local h = z.GroundY + 0.05 - c.Y
			if math.abs(h) < s then
				local foot = if h > 0 then math.sqrt(s * s - h * h) else s
				if flatDist(c, g.Center) - foot < z.PlayRadius then
					bad += 1
					fail(string.format("остров %d: шар с коллизией заходит в игровую зону: %s", i, p:GetFullName()))
				end
			end
		elseif p.CanCollide and not allowed[p.Name] and not p:IsDescendantOf(map.Stations) then
			for _, c in corners(p) do
				if flatDist(c, g.Center) < z.PlayRadius and c.Y > z.GroundY + 0.05 and c.Y < z.GroundY + 40 then
					bad += 1
					if bad <= 5 then
						fail(string.format("остров %d: деталь с коллизией в игровой зоне: %s", i, p:GetFullName()))
					end
					break
				end
			end
		end
		-- высокий декор без коллизий в игровой зоне (кроме цветов/травинок)
		if not p.CanCollide and p.Transparency < 1 and flatDist(p.CFrame.Position, g.Center) < z.PlayRadius - 1 then
			local top = -math.huge
			for _, c in corners(p) do
				top = math.max(top, c.Y)
			end
			local small = math.max(p.Size.X, p.Size.Y, p.Size.Z) <= 2.2
			if top > z.GroundY + 0.06 and not small and not p:IsDescendantOf(map.Stations) and not p:IsDescendantOf(map.Clouds) and top < z.GroundY + 30 then
				fail(string.format("остров %d: крупный декор в игровой зоне: %s (верх %.2f)", i, p:GetFullName(), top - z.GroundY))
			end
		end
	end
	-- точка появления внутри острова и над землёй
	if flatDist(g.Spawn, g.Center) > z.Radius - 2 or g.Spawn.Y <= z.GroundY then
		fail("остров " .. i .. ": точка появления вне острова")
	end
end

-- 6. Стены не перекрывают мосты
for i, g in Zones.Geo do
	local blocked = 0
	for k = 0, 40 do
		local p = g.BridgeStart:Lerp(g.BridgeEnd, k / 40) + Vector3.new(0, 3, 0)
		for _, side in { -6, 0, 6 } do
			local q = p + g.Right * side
			for _, w in walls do
				if contains(w, q) then
					blocked += 1
				end
			end
		end
	end
	-- и вход на остров/хаб: точки чуть внутри края
	for _, q in { g.Entrance + g.Dir * 3 + Vector3.new(0, 3, 0), g.BridgeStart - g.Dir * 3 + Vector3.new(0, 3, 0) } do
		for _, w in walls do
			if contains(w, q) then
				blocked += 1
			end
		end
	end
	if blocked > 0 then
		fail("мост " .. i .. ": невидимые стены перекрывают проход (" .. blocked .. ")")
	end
end

print(string.format("Деталей: %d, источников света: %d, окон: %d, стен: %d", #parts, lights, windows, #walls))
if #parts > 7000 then
	fail("слишком много деталей для телефонов: " .. #parts)
end
if #problems == 0 then
	print("OK: карта соответствует логике игры")
else
	for _, m in problems do
		print("ПРОБЛЕМА: " .. m)
	end
	process.exit(1)
end
